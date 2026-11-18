// Render runner. Never starts a server: it probes baseUrl, and in test mode
// answers baseUrl requests from disk through context.route.
import { mkdir, readFile, readdir, rm } from 'node:fs/promises';
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
    else if ('wait' in step) await page.waitForTimeout(step.wait);
  }
}

// Theme markers on <html>: a "dark" class and a data-theme attribute.
const applyBody = (theme) => `
  const el = document.documentElement;
  el.classList.toggle('dark', ${theme === 'dark'});
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

// Waits until the page is worth photographing. Throws a one-line Error to mark the shot "error".
async function waitUntilReady(page, target, baseUrl) {
  // Short cap; hitting it is fine (pages with long polling never go idle).
  await page.waitForLoadState('networkidle', { timeout: 2000 }).catch(() => {});
  if (!isStoryFrame(target.url, baseUrl)) return;
  try {
    await page.waitForSelector('#storybook-root > *', { state: 'attached', timeout: STORY_TIMEOUT });
  } catch {
    throw new Error(`Storybook story did not render: #storybook-root stayed empty for ${STORY_TIMEOUT}ms`);
  }
  try {
    await page.waitForFunction(() => !document.body.classList.contains('sb-show-preparing-story'), null, { timeout: STORY_TIMEOUT });
  } catch {
    throw new Error(`Storybook story did not render: still preparing after ${STORY_TIMEOUT}ms`);
  }
  if (await page.evaluate(() => document.body.classList.contains('sb-show-errordisplay'))) {
    throw new Error('Storybook story did not render: error display is showing');
  }
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
              response = await page.goto(new URL(target.url, plan.baseUrl).href, { waitUntil: 'load' });
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
                await waitUntilReady(page, target, plan.baseUrl);
                await applySetup(page, target.setup);
                await page.addStyleTag({ content: KILL_MOTION });
                await page.evaluate(reapplyScript(theme));
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
