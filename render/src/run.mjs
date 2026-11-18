// Render runner. Never starts a server: it probes baseUrl, and in test mode
// answers baseUrl requests from disk through context.route.
import { mkdir, readFile, readdir, rm, lstat } from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { THEMES, BREAKPOINTS, validatePlan } from './plan.mjs';
import { buildManifest, writeManifest } from './manifest.mjs';
import { analyze, buildAxe, writeAxe } from './axe.mjs';

export class UnreachableError extends Error {}

const VIEWPORT_HEIGHT = 800;
const NAV_TIMEOUT = 15000;
const STEP_TIMEOUT = 5000;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.woff2': 'font/woff2',
};

async function probe(baseUrl) {
  try {
    await fetch(baseUrl, { method: 'GET', signal: AbortSignal.timeout(5000), redirect: 'manual' });
  } catch (err) {
    const code = err?.cause?.code || err?.name || 'error';
    throw new UnreachableError(`Nothing answering at ${baseUrl} (${code}). Start your server first; this harness never does.`);
  }
}

// Serve baseUrl from a folder via route interception (no port is opened).
// Anything outside baseUrl's origin is blocked so runs stay hermetic.
async function installFixtureRoutes(context, baseUrl, fixturesDir) {
  const origin = new URL(baseUrl).origin;
  const root = path.resolve(fixturesDir);
  // Optional test aid: <fixturesDir>/_headers.json maps a pathname to response headers.
  let extraHeaders = {};
  try {
    extraHeaders = JSON.parse(await readFile(path.join(root, '_headers.json'), 'utf8'));
  } catch {}
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) return route.abort();
    let rel = decodeURIComponent(url.pathname);
    if (rel.endsWith('/')) rel += 'index.html';
    const file = path.resolve(root, '.' + rel);
    if (file !== root && !file.startsWith(root + path.sep)) {
      return route.fulfill({ status: 403, body: 'forbidden' });
    }
    try {
      const body = await readFile(file);
      return route.fulfill({
        status: 200,
        headers: extraHeaders[url.pathname] || {},
        body,
        contentType: MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      });
    } catch {
      return route.fulfill({ status: 404, contentType: 'text/plain', body: 'not found' });
    }
  });
}

async function applySetup(page, steps = []) {
  for (const step of steps) {
    if ('click' in step) await page.click(step.click, { timeout: STEP_TIMEOUT });
    else if ('fill' in step) await page.fill(step.fill[0], step.fill[1], { timeout: STEP_TIMEOUT });
    else if ('hover' in step) await page.hover(step.hover, { timeout: STEP_TIMEOUT });
    else if ('wait' in step) await page.waitForTimeout(step.wait);
  }
}

// Theme markers on <html>: a "dark" class and a data-theme attribute. On a Storybook frame (iframe.html)
// the class is left to Storybook (theme addon, selected by the URL global) because it strips an externally
// set class on mount, story switch and theme change; only data-theme, which Storybook ignores, is set there.
const applyBody = (theme) => `
  const el = document.documentElement;
  if (!location.pathname.endsWith('iframe.html')) el.classList.toggle('dark', ${theme === 'dark'});
  el.setAttribute('data-theme', '${theme}');`;

// Installed with addInitScript. An init script can run before <html> exists, so
// when it is missing we watch the document and apply the markers the moment the
// element is created, which is before the page's own scripts run.
function initScript(theme) {
  return `(() => {
    const apply = () => {${applyBody(theme)}};
    if (document.documentElement) { apply(); return; }
    const mo = new MutationObserver(() => {
      if (document.documentElement) { mo.disconnect(); apply(); }
    });
    mo.observe(document, { childList: true });
  })();`;
}

// Re-applied after load and setup, in case the page or a setup step changed them.
const reapplyScript = (theme) => `(() => {${applyBody(theme)}})();`;

const KILL_MOTION = '*,*::before,*::after{transition:none!important;animation:none!important}';
const STORY_TIMEOUT = Number(process.env.ATELIER_RENDER_STORY_TIMEOUT_MS) || 10000;

const isStoryFrame = (url, baseUrl) => new URL(url, baseUrl).pathname.endsWith('iframe.html');

// Storybook targets pick the theme through the URL global (?globals=theme:dark). Any other globals the
// plan URL already carries are kept; only the theme entry is replaced.
export function storyUrl(url, baseUrl, theme) {
  const u = new URL(url, baseUrl);
  const kept = (u.searchParams.get('globals') || '').split(';').filter((g) => g && !g.startsWith('theme:'));
  u.searchParams.set('globals', [...kept, `theme:${theme}`].join(';'));
  return u.href;
}

const targetUrl = (target, baseUrl, theme) =>
  isStoryFrame(target.url, baseUrl) ? storyUrl(target.url, baseUrl, theme) : new URL(target.url, baseUrl).href;

// Fails the shot when <html> does not carry the requested theme. Storybook story-level globals override the
// URL global, so a mismatch is a failed capture, never a silent wrong-theme shot.
async function assertStoryTheme(page, theme, settleMs) {
  const want = theme === 'dark';
  const matches = () => document.documentElement.classList.contains('dark');
  try {
    if (settleMs) await page.waitForFunction((w) => document.documentElement.classList.contains('dark') === w, want, { timeout: settleMs });
  } catch {}
  if ((await page.evaluate(matches)) !== want) {
    throw new Error(
      `Theme mismatch: requested ${theme} but <html> ${want ? 'has no' : 'still has the'} "dark" class after the story rendered (a story-level globals override or the theme decorator's mapping may be forcing it)`,
    );
  }
}

const FIRST_INTERACTIVE = [
  'a[href]', 'button:not([disabled])', 'input:not([disabled]):not([type=hidden])', 'select:not([disabled])',
  'textarea:not([disabled])', 'summary', '[role=button]', '[role=link]', '[role=tab]', '[role=menuitem]',
  '[tabindex]:not([tabindex="-1"])',
].join(',');
const HOVER_STATE = /(^|[-_])hover(ed)?($|[-_])/i;

// Real pointer hover (mouse move, never a click or mouse-down) so CSS :hover applies. Skipped when the plan
// has its own {"hover"} setup step. Selector comes from the story's parameters.harness.hover, else the first
// interactive element for a state named like "hover".
async function applyHover(page, target, isStory) {
  if ((target.setup || []).some((s) => 'hover' in s)) return;
  let want = null;
  if (isStory) {
    want = await page.evaluate(() => {
      try {
        const h = window.__STORYBOOK_PREVIEW__.currentRender.story.parameters.harness;
        return h && h.hover !== undefined ? h.hover : null;
      } catch {
        return null;
      }
    });
  }
  let selector = typeof want === 'string' && want ? want : null;
  if (!selector && (want === true || HOVER_STATE.test(target.state))) selector = FIRST_INTERACTIVE;
  if (!selector) return;
  const inRoot = page.locator('#storybook-root').locator(selector);
  const anywhere = page.locator(selector);
  const loc = (await inRoot.count()) > 0 ? inRoot.first() : (await anywhere.count()) > 0 ? anywhere.first() : null;
  const none = () =>
    new Error(`Hover requested but no hoverable element matched ${selector === FIRST_INTERACTIVE ? 'the first-interactive fallback' : selector}`);
  if (!loc) throw none();
  try {
    await loc.hover({ timeout: STEP_TIMEOUT });
  } catch {
    throw none();
  }
}

// Waits until the page is worth photographing. Throws a one-line Error to mark the shot "error".
async function waitUntilReady(page, target, baseUrl) {
  // Short cap; hitting it is fine (pages with long polling never go idle).
  await page.waitForLoadState('networkidle', { timeout: 2000 }).catch(() => {});
  if (!isStoryFrame(target.url, baseUrl)) return;
  // Rendered = #storybook-root has a child element, OR body has a direct child that is a portal-style
  // node (not root/docs, script/style/link/noscript, or a Storybook "sb-" wrapper by id or class).
  const hasContent = () => {
    const body = document.body;
    if (!body) return false;
    const root = document.querySelector('#storybook-root');
    if (root && root.children.length > 0) return true;
    const skipTags = ['SCRIPT', 'STYLE', 'LINK', 'NOSCRIPT'];
    for (const el of body.children) {
      if (skipTags.includes(el.tagName)) continue;
      if (el.id === 'storybook-root' || el.id === 'storybook-docs') continue;
      if (el.id.startsWith('sb-') || [...el.classList].some((c) => c.startsWith('sb-'))) continue;
      return true;
    }
    return false;
  };
  try {
    await page.waitForFunction(hasContent, null, { timeout: STORY_TIMEOUT });
  } catch {
    throw new Error(`Storybook story did not render: no story content appeared within ${STORY_TIMEOUT}ms`);
  }
  try {
    await page.waitForFunction(
      () => !document.body.classList.contains('sb-show-preparing-story') && !document.body.classList.contains('sb-show-preparing-docs'),
      null,
      { timeout: STORY_TIMEOUT },
    );
  } catch {
    throw new Error(`Storybook story did not render: still preparing after ${STORY_TIMEOUT}ms`);
  }
  if (await page.evaluate(() => document.body.classList.contains('sb-show-errordisplay'))) {
    throw new Error('Storybook story did not render: error display is showing');
  }
  // Finished phase: Storybook's current render goes ... playing -> played -> completed. 'errored' means the
  // render or the play function threw, which is a failed capture. If the preview global is absent (not a
  // real Storybook frame) the content checks above are all there is.
  const phase = () => {
    const r = window.__STORYBOOK_PREVIEW__ && window.__STORYBOOK_PREVIEW__.currentRender;
    return r ? r.phase : null;
  };
  if ((await page.evaluate(() => !!window.__STORYBOOK_PREVIEW__)) === false) return;
  try {
    await page.waitForFunction(
      () => {
        const r = window.__STORYBOOK_PREVIEW__ && window.__STORYBOOK_PREVIEW__.currentRender;
        return !!r && (r.phase === 'completed' || r.phase === 'errored');
      },
      null,
      { timeout: STORY_TIMEOUT },
    );
  } catch {
    throw new Error(`Storybook story did not finish: render phase is "${await page.evaluate(phase)}" after ${STORY_TIMEOUT}ms (play function still running?)`);
  }
  if ((await page.evaluate(phase)) === 'errored') {
    throw new Error('Storybook story errored: the play function or render threw (render phase "errored")');
  }
}

// Refuses symbolic links for the out dir and the slug folder (a missing path is fine).
async function refuseSymlink(p) {
  let st;
  try {
    st = await lstat(p);
  } catch {
    return;
  }
  if (st.isSymbolicLink()) throw new UnreachableError(`Refusing to write through a symbolic link: ${p}`);
}

// Removes the previous run's outputs from one slug folder, and nothing else.
async function cleanSlugDir(outDir, slugDir) {
  const root = path.resolve(outDir);
  if (!slugDir.startsWith(root + path.sep)) {
    throw new UnreachableError(`Refusing to clean ${slugDir}: not inside ${root}`);
  }
  let names = [];
  try {
    names = await readdir(slugDir);
  } catch {
    return;
  }
  for (const name of names) {
    if (name.endsWith('.png') || name === 'manifest.json' || name === 'axe.json') {
      await rm(path.join(slugDir, name), { force: true });
    }
  }
}

export async function run(rawPlan, { outDir = '.atelier/renders', fixturesDir } = {}) {
  const plan = validatePlan(rawPlan);
  if (!fixturesDir) await probe(plan.baseUrl);

  const slugDir = path.resolve(outDir, plan.slug);
  await refuseSymlink(path.resolve(outDir));
  await refuseSymlink(slugDir);
  await mkdir(slugDir, { recursive: true });
  await cleanSlugDir(outDir, slugDir);

  const browser = await chromium.launch();
  const shots = [];
  const axeShots = [];
  try {
    for (const theme of THEMES) {
      for (const [bp, width] of Object.entries(BREAKPOINTS)) {
        const context = await browser.newContext({
          viewport: { width, height: VIEWPORT_HEIGHT },
          colorScheme: theme,
          // The animation-kill style is injected inline; a strict page CSP would block it.
          bypassCSP: true,
        });
        if (fixturesDir) await installFixtureRoutes(context, plan.baseUrl, fixturesDir);
        await context.addInitScript(initScript(theme));
        for (const target of plan.targets) {
          const file = `${target.state}.${theme}.${bp}.png`;
          const shot = { state: target.state, theme, bp, path: file, status: 'ok' };
          const page = await context.newPage();
          page.setDefaultNavigationTimeout(NAV_TIMEOUT);
          try {
            let response;
            try {
              response = await page.goto(targetUrl(target, plan.baseUrl, theme), { waitUntil: 'load' });
            } catch (err) {
              shot.status = 'missing';
              shot.error = `navigation failed: ${String(err.message).split('\n')[0]}`;
            }
            if (shot.status === 'ok' && response && response.status() >= 400) {
              shot.status = 'missing';
              shot.error = `HTTP ${response.status()}`;
            }
            if (shot.status === 'ok') {
              try {
                const isStory = isStoryFrame(target.url, plan.baseUrl);
                await waitUntilReady(page, target, plan.baseUrl);
                if (isStory) await assertStoryTheme(page, theme, 3000);
                await applySetup(page, target.setup);
                await applyHover(page, target, isStory);
                // Motion is switched off only now, after the finished phase, so the shot is of the end state.
                await page.addStyleTag({ content: KILL_MOTION });
                await page.evaluate(reapplyScript(theme));
                if (isStory) await assertStoryTheme(page, theme, 0);
                await page.screenshot({ path: path.join(slugDir, file), fullPage: true, animations: 'disabled' });
              } catch (err) {
                shot.status = 'error';
                shot.error = String(err.message).split('\n')[0];
              }
              // Axe only for shots that have a PNG, so a FAIL line always points at a file.
              if (shot.status === 'ok') {
                try {
                  axeShots.push({ state: target.state, theme, bp, violations: await analyze(page) });
                } catch (err) {
                  shot.status = 'error';
                  shot.error = `axe failed: ${String(err.message).split('\n')[0]}`;
                }
              }
            }
          } finally {
            await page.close();
          }
          shots.push(shot);
        }
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }

  const axe = buildAxe(plan.slug, axeShots);
  const axePath = await writeAxe(slugDir, axe);
  const manifest = buildManifest({ plan, shots, axe: axe.totals });
  const manifestPath = await writeManifest(slugDir, manifest);
  return { plan, slugDir, shots, manifest, manifestPath, axe, axePath };
}
