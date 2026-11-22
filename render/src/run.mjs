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
const STEP_TIMEOUT = Number(process.env.ATELIER_RENDER_STEP_TIMEOUT_MS) || 5000;

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

// Storybook reports some play and render errors only on its addons channel, with no error display (for
// example `parameters.throwPlayFunctionExceptions: false` logs the error and the render still ends on
// "finished"). The channel is created with a plain assignment to window.__STORYBOOK_ADDONS_CHANNEL__, so a
// setter on that name hooks it the moment it exists, before any render. Errors land in
// window.__atelierStoryErrors. Events and payloads checked against Storybook 10.6.7 (see waitUntilReady).
const CHANNEL_HOOK = `(() => {
  const errors = (window.__atelierStoryErrors = []);
  const hooked = new WeakSet();
  const hook = (ch) => {
    if (!ch || typeof ch.on !== 'function' || hooked.has(ch)) return;
    hooked.add(ch);
    const msg = (p) => (p && (p.message || p.title || p.name)) || '';
    ch.on('playFunctionThrewException', (p) => errors.push('play function threw: ' + msg(p)));
    ch.on('storyThrewException', (p) => errors.push('story threw: ' + msg(p)));
    ch.on('storyErrored', (p) => errors.push('story errored: ' + msg(p)));
    ch.on('unhandledErrorsWhilePlaying', (p) => errors.push('unhandled errors while playing: ' + msg(Array.isArray(p) ? p[0] : p)));
    ch.on('storyFinished', (p) => { if (p && p.status === 'error') errors.push('storyFinished reported status "error"'); });
  };
  try {
    let value = window.__STORYBOOK_ADDONS_CHANNEL__;
    Object.defineProperty(window, '__STORYBOOK_ADDONS_CHANNEL__', {
      configurable: true,
      get: () => value,
      set: (v) => { value = v; hook(v); },
    });
    hook(value);
  } catch {}
})();`;

// Installed with addInitScript. An init script can run before <html> exists, so
// when it is missing we watch the document and apply the markers the moment the
// element is created, which is before the page's own scripts run.
function initScript(theme) {
  return `${CHANNEL_HOOK}
  (() => {
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

// Motion is settled, not removed: removing a CSS animation reverts the element to its base style, which is
// not the end state (a sheet that slides in with `forwards` would be shot off-screen). So, in the page:
//   - finite animations and transitions are finished (jump to their end state; a fill-forwards animation
//     keeps holding it),
//   - infinite animations (skeleton pulse, spinner) cannot finish; they are paused at currentTime 0, i.e.
//     their first keyframe, and that frame is what is shot.
// Then transitions are switched off so nothing starts moving again. Animations are not killed with
// `animation: none`, and the screenshot is taken with animations 'allow' so Playwright does not cancel the
// held frame.
const SETTLE_MOTION = `(() => {
  for (const a of document.getAnimations()) {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    if (t && t.endTime === Infinity) { a.pause(); a.currentTime = 0; }
    else { try { a.finish(); } catch { a.pause(); } }
  }
})();`;

// Measured right before the shot, after setup, hover and motion settling. Returns the document's scroll
// width and height and, when the page is wider than the viewport, a description of the element that pushes
// it out: the one whose right edge goes furthest past the viewport (first in document order on a tie, so
// the outermost). Elements inside a clipping or scrolling ancestor (overflow other than visible) do not
// widen the document and are skipped, so a table in its own scroll wrapper is not blamed.
const MEASURE_PAGE = `((vw) => {
  const se = document.scrollingElement || document.documentElement;
  const de = document.documentElement;
  const scrollWidth = Math.ceil(se.scrollWidth);
  let culprit = null;
  if (scrollWidth > vw + 1) {
    // Skipped: fixed elements and their descendants, and anything inside a clipping or scrolling ancestor.
    const skipped = (el) => {
      for (let p = el; p && p !== de; p = p.parentElement) {
        const cs = getComputedStyle(p);
        if (cs.position === 'fixed') return true;
        if (p !== el && cs.overflowX !== 'visible') return true;
      }
      return false;
    };
    const sx = window.scrollX || 0;
    let best = null, bestRight = vw + 1;
    for (const el of document.querySelectorAll('body, body *')) {
      const r = el.getBoundingClientRect();
      const right = r.right + sx;
      if (r.width === 0 || right <= bestRight) continue;
      if (skipped(el)) continue;
      best = el; bestRight = right;
    }
    if (best) {
      const cls = (best.getAttribute('class') || '').trim().split(/\\s+/)[0];
      const slot = best.getAttribute('data-slot');
      culprit = (best.tagName.toLowerCase() + (best.id ? '#' + best.id : '') + (cls ? '.' + cls : '') + (slot ? '[data-slot="' + slot + '"]' : '')).slice(0, 120);
    }
  }
  return { scrollWidth, culprit };
})`;
// Height is read on its own so a failed overflow measurement still gives a full-height shot.
const PAGE_HEIGHT = `(() => {
  const de = document.documentElement, b = document.body;
  return Math.max(de.scrollHeight, b ? b.scrollHeight : 0, de.clientHeight);
})()`;
const NO_TRANSITIONS = '*,*::before,*::after{transition:none!important}';
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

// The story's parameters.harness object (hover, theme), or null when there is none. One reader for every
// harness parameter, evaluated inside the story frame.
const readHarness = (page) =>
  page.evaluate(() => {
    try {
      return window.__STORYBOOK_PREVIEW__.currentRender.story.parameters.harness ?? null;
    } catch {
      return null;
    }
  });

const isName = (v) => typeof v === 'string' && v.trim() !== '';

// parameters.harness.theme says how <html> shows the theme. Absent: the "dark" class. {class} or {attribute}
// (optional values map) otherwise. There is no off switch, and a malformed value is an error, so a wrong-theme
// shot can never pass silently.
export function resolveThemeCheck(h) {
  const t = h && h.theme;
  if (t === undefined || t === null) return { kind: 'class', name: 'dark' };
  const bad = (why) =>
    new Error(`parameters.harness.theme is malformed: ${why}. Use { "class": "<name>" } or { "attribute": "<name>", "values": { "light": "<v>", "dark": "<v>" } }`);
  if (typeof t !== 'object' || Array.isArray(t)) throw bad('it must be an object');
  const hasClass = 'class' in t;
  const hasAttr = 'attribute' in t;
  if (hasClass && hasAttr) throw bad('set "class" or "attribute", not both');
  if (!hasClass && !hasAttr) throw bad('it needs a "class" or an "attribute" key');
  const extra = Object.keys(t).filter((k) => !['class', 'attribute', 'values'].includes(k));
  if (extra.length) throw bad(`unknown key "${extra[0]}"`);
  if (hasClass) {
    if (!isName(t.class)) throw bad('"class" must be a non-empty string');
    if ('values' in t) throw bad('"values" only applies to "attribute"');
    return { kind: 'class', name: t.class };
  }
  if (!isName(t.attribute)) throw bad('"attribute" must be a non-empty string');
  if (t.attribute.trim().toLowerCase() === 'data-theme') {
    throw bad('the harness sets data-theme itself, so checking it proves nothing; point "attribute" at the one your own theme code sets');
  }
  let values = { light: 'light', dark: 'dark' };
  if ('values' in t) {
    const v = t.values;
    if (!v || typeof v !== 'object' || Array.isArray(v) || !isName(v.light) || !isName(v.dark) || Object.keys(v).some((k) => k !== 'light' && k !== 'dark')) {
      throw bad('"values" must be { "light": "<v>", "dark": "<v>" } with non-empty strings');
    }
    values = { light: v.light, dark: v.dark };
  }
  return { kind: 'attribute', name: t.attribute, values };
}

// Fails the shot when <html> does not carry the requested theme, as the host's parameters.harness.theme
// describes it (default: the "dark" class). Storybook story-level globals override the URL global, so a
// mismatch is a failed capture, never a silent wrong-theme shot.
async function assertStoryTheme(page, theme, settleMs) {
  const check = resolveThemeCheck(await readHarness(page));
  const dark = theme === 'dark';
  const expected = check.kind === 'attribute' ? check.values[theme] : null;
  const matches = ([c, wantDark, wantValue]) => {
    const el = document.documentElement;
    return c.kind === 'class' ? el.classList.contains(c.name) === wantDark : el.getAttribute(c.name) === wantValue;
  };
  const arg = [check, dark, expected];
  try {
    if (settleMs) await page.waitForFunction(matches, arg, { timeout: settleMs });
  } catch {}
  if (await page.evaluate(matches, arg)) return;
  const why = `a story-level globals override or the theme decorator's mapping may be forcing it`;
  if (check.kind === 'class') {
    throw new Error(
      `Theme mismatch: requested ${theme} but <html> ${dark ? 'has no' : 'still has the'} "${check.name}" class after the story rendered (${why})`,
    );
  }
  const found = await page.evaluate((n) => document.documentElement.getAttribute(n), check.name);
  throw new Error(
    `Theme mismatch: requested ${theme} but <html> ${check.name} is ${found === null ? 'not set' : `"${found}"`}, expected "${expected}" (${why})`,
  );
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
    const h = await readHarness(page);
    want = h && h.hover !== undefined ? h.hover : null;
  }
  // parameters.harness.hover: a selector, true (first interactive), false (no hover at all, name fallback
  // included) or "" (a mistake, reported).
  if (want === false) return;
  if (want === '') throw new Error('parameters.harness.hover is an empty string: use a selector, true or false');
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
  } catch (err) {
    throw new Error(`Hover on ${selector === FIRST_INTERACTIVE ? 'the first-interactive fallback' : selector} failed: ${String(err.message).split('\n')[0]}`);
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
  // Finished phase. Checked against Storybook 10.6.7 (StoryRender.render, storybook/dist/_browser-chunks/
  // chunk-M6YZR3ZW.js ~1650-1715): a story runs
  //   preparing, loading, beforeEach, rendering, playing, played, completing, completed, afterEach, finished
  // and "finished" is the resting phase. "completed" and "errored" last microseconds, but Storybook 8 stops at
  // "completed", so any of finished, aborted, errored or completed ends the wait; after a completed or errored
  // we give "finished" up to 500ms more (best effort, never fails the shot). A phase alone cannot tell a play
  // or render error any more (a thrown play goes errored then finished), so errors are read from the
  // error display (renderException calls view.showErrorDisplay -> body.sb-show-errordisplay) and from the
  // channel hook (see CHANNEL_HOOK). If the preview global is absent (not a real Storybook frame) the content
  // checks above are all there is.
  const phase = () => {
    const r = window.__STORYBOOK_PREVIEW__ && window.__STORYBOOK_PREVIEW__.currentRender;
    return r ? r.phase : null;
  };
  if ((await page.evaluate(() => !!window.__STORYBOOK_PREVIEW__)) === false) return;
  try {
    await page.waitForFunction(
      () => {
        const r = window.__STORYBOOK_PREVIEW__ && window.__STORYBOOK_PREVIEW__.currentRender;
        return !!r && ['finished', 'aborted', 'errored', 'completed'].includes(r.phase);
      },
      null,
      { timeout: STORY_TIMEOUT },
    );
  } catch {
    throw new Error(`Storybook story did not finish: render phase is "${await page.evaluate(phase)}" after ${STORY_TIMEOUT}ms (play function still running?)`);
  }
  await page
    .waitForFunction(() => ['finished', 'aborted'].includes(window.__STORYBOOK_PREVIEW__.currentRender.phase), null, { timeout: 500 })
    .catch(() => {});
  const final = await page.evaluate(phase);
  if (final === 'aborted') throw new Error('Storybook story aborted: the render was cancelled before it finished (render phase "aborted")');
  if (await page.evaluate(() => document.body.classList.contains('sb-show-errordisplay'))) {
    throw new Error('Storybook story errored: error display is showing');
  }
  const reported = await page.evaluate(() => (window.__atelierStoryErrors || [])[0] || null);
  if (reported) throw new Error(`Storybook story errored: ${reported}`);
  if (final === 'errored') throw new Error('Storybook story errored: render phase ended on "errored"');
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
                // Motion is settled only now, after the finished phase (and after hover, which can start transitions).
                await page.evaluate(SETTLE_MOTION);
                await page.addStyleTag({ content: NO_TRANSITIONS });
                await page.evaluate(reapplyScript(theme));
                if (isStory) await assertStoryTheme(page, theme, 0);
                // Full page, but clipped to the viewport width: with fullPage alone Chromium makes the PNG as wide
                // as the document's scroll width when the page overflows horizontally. Playwright applies the
                // clip in document coordinates and trims it to the full page size.
                // A measurement that throws (a page that patches getComputedStyle, say) leaves overflowX unset and
                // the shot is still taken.
                let height = VIEWPORT_HEIGHT;
                try {
                  height = Math.max(Number(await page.evaluate(PAGE_HEIGHT)) || 0, VIEWPORT_HEIGHT);
                } catch {}
                try {
                  const m = await page.evaluate(`${MEASURE_PAGE}(${width})`);
                  const over = m.scrollWidth - width;
                  shot.overflowX = over > 1 ? over : 0;
                  if (shot.overflowX > 0 && m.culprit) shot.overflowBy = m.culprit;
                } catch {}
                await page.screenshot({
                  path: path.join(slugDir, file),
                  fullPage: true,
                  clip: { x: 0, y: 0, width, height },
                  animations: 'allow',
                });
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
