import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp, fixtures } from './helpers.mjs';
import { writeFile, readFile } from 'node:fs/promises';
import path from 'node:path';
import { validatePlan, PlanError } from '../src/plan.mjs';
import { storyUrl } from '../src/run.mjs';

test.afterAll(cleanupTmp);

async function render(slug, targets, { env } = {}) {
  const dir = await mkTmp();
  const planFile = path.join(dir, `plan-${slug}.json`);
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug, targets }));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fixtures('storybook')], { env });
  const read = async (f) => JSON.parse(await readFile(path.join(out, slug, f), 'utf8').catch(() => 'null'));
  return { res, out, manifest: await read('manifest.json'), axe: await read('axe.json') };
}
const story = (state, id) => ({ state, url: `/iframe.html?id=${id}&viewMode=story` });
const png = async (out, slug, file) => readFile(path.join(out, slug, file));
const size = (buf) => ({ w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) });
const byState = (manifest, state) => manifest.shots.filter((s) => s.state === state);

test('storyUrl sets the theme global, keeps other globals, replaces a theme already in the URL', () => {
  const base = 'http://x.test';
  const g = (u) => new URL(u).searchParams.get('globals');
  expect(g(storyUrl('/iframe.html?id=a--b&viewMode=story', base, 'dark'))).toBe('theme:dark');
  expect(g(storyUrl('/iframe.html?id=a--b&viewMode=story', base, 'light'))).toBe('theme:light');
  expect(g(storyUrl('/iframe.html?id=a--b&globals=locale:fr;theme:dark', base, 'light'))).toBe('locale:fr;theme:light');
  expect(new URL(storyUrl('/iframe.html?id=a--b&viewMode=story', base, 'dark')).searchParams.get('id')).toBe('a--b');
});

test('theme comes from the URL global: dark and light shots of a class-stripping frame are ok', async () => {
  const { res, manifest } = await render('theme', [story('plain', 'plain--story')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(manifest.shots.length).toBe(6);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots)).toBe(true);
});

test('a story whose own globals override the theme fails the mismatching shots, loudly', async () => {
  const { res, manifest } = await render('override', [story('forced', 'forced-override--story')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const dark = manifest.shots.filter((s) => s.theme === 'dark');
  const light = manifest.shots.filter((s) => s.theme === 'light');
  expect(dark.length).toBe(3);
  for (const s of dark) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/Theme mismatch: requested dark/);
  }
  expect(light.every((s) => s.status === 'ok')).toBe(true);
});

test('parameters.harness.theme attribute form passes on a host that only sets the attribute, never a dark class', async () => {
  const { res, manifest } = await render('mantine', [story('m', 'mantine--story')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(manifest.shots.length).toBe(6);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots)).toBe(true);
});

test('attribute form fails with a message naming the attribute and the value found', async () => {
  const { manifest } = await render('mantinewrong', [story('w', 'mantinewrong--story')]);
  const dark = manifest.shots.filter((s) => s.theme === 'dark');
  expect(dark.length).toBe(3);
  for (const s of dark) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/Theme mismatch: requested dark but <html> data-mantine-color-scheme is "light", expected "dark"/);
  }
  expect(manifest.shots.filter((s) => s.theme === 'light').every((s) => s.status === 'ok')).toBe(true);
});

test('attribute form maps theme names with values; a custom class name works', async () => {
  const { manifest } = await render('themeother', [story('n', 'nightday--story'), story('c', 'modeclass--story')]);
  expect(manifest.shots.length).toBe(12);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots)).toBe(true);
});

test('the default class check names the class it looked for', async () => {
  const { manifest } = await render('override2', [story('forced', 'forced-override--story')]);
  const dark = manifest.shots.filter((s) => s.theme === 'dark');
  for (const s of dark) expect(s.error).toMatch(/requested dark but <html> has no "dark" class/);
});

test('a malformed parameters.harness.theme marks the shot error, naming the parameter', async () => {
  for (const id of ['badstring', 'badboth', 'badnone', 'badnonstr', 'badvalues']) {
    const { manifest } = await render(id, [story('b', `${id}--story`)]);
    expect(manifest.shots.length, id).toBe(6);
    for (const s of manifest.shots) {
      expect(s.status, id).toBe('error');
      expect(s.error, id).toMatch(/^parameters\.harness\.theme is malformed: /);
      expect(s.error, id).not.toContain('\n');
    }
  }
});

test('attribute "data-theme" is rejected (case-insensitive) because the harness writes it itself', async () => {
  const { manifest } = await render('baddatatheme', [story('d', 'baddatatheme--story')]);
  expect(manifest.shots.length).toBe(6);
  for (const s of manifest.shots) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/^parameters\.harness\.theme is malformed: the harness sets data-theme itself/);
  }
});

test('waits for the finished phase: content added when play completes is in the shot and axe', async () => {
  const { res, axe } = await render('slowplay', [story('slow', 'slowplay--story')]);
  expect(res.code).toBe(1);
  expect(res.stdout).toContain('FAIL slow.dark.sm: image-alt (critical)');
  expect(axe.shots.length).toBe(6);
});

test('a play function error is a failed capture (status error), not a shot', async () => {
  const { res, manifest } = await render('playerr', [story('bad', 'playerr--story'), story('fine', 'fine--story')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  for (const s of byState(manifest, 'bad')) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/error display is showing/);
  }
  expect(byState(manifest, 'fine').every((s) => s.status === 'ok')).toBe(true);
});

test('a play error with no error display (throwPlayFunctionExceptions:false) is still error, via the channel', async () => {
  const { manifest } = await render('quiet', [story('q', 'quiet--story'), story('fine', 'fine--story')]);
  for (const s of byState(manifest, 'q')) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/play function threw: quiet boom in play/);
  }
  expect(byState(manifest, 'fine').every((s) => s.status === 'ok')).toBe(true);
});

test('storyFinished with status error and nothing on screen is error', async () => {
  const { manifest } = await render('finerr', [story('f', 'finerr--story')]);
  for (const s of manifest.shots) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/storyFinished reported status "error"/);
  }
});

test('a render that ends on the aborted phase is error', async () => {
  const { manifest } = await render('abort', [story('ab', 'abort--story'), story('fine', 'fine--story')]);
  for (const s of byState(manifest, 'ab')) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/aborted/);
  }
  expect(byState(manifest, 'fine').every((s) => s.status === 'ok')).toBe(true);
});

test('a play function that never finishes is error with a reason after the story timeout', async () => {
  const { manifest } = await render('hang', [story('stuck', 'hang--story'), story('fine', 'fine--story')], {
    env: { ATELIER_RENDER_STORY_TIMEOUT_MS: '700' },
  });
  for (const s of byState(manifest, 'stuck')) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/did not finish: render phase is "playing"/);
  }
});

test('hover is a real pointer move: named state, story parameter, and setup step each pick their element', async () => {
  const { res, manifest } = await render('hover', [
    story('btn-hover', 'hover--story'), // state name token "hover": first interactive element (#b1)
    story('param', 'hoverparam--story'), // parameters.harness.hover = "#b2"
    { ...story('stepped', 'hover--story'), setup: [{ hover: '#b2' }] },
    story('plain', 'hover--story'), // no hover requested
  ]);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots)).toBe(true);
  expect(res.code).toBe(1);
  const lines = res.stdout.split('\n');
  expect(lines).toContain('FAIL btn-hover.dark.sm: image-alt (critical)');
  expect(lines.some((l) => l.startsWith('FAIL btn-hover.') && l.includes('label'))).toBe(false);
  expect(lines.some((l) => l.startsWith('FAIL param.dark.sm: label'))).toBe(true);
  expect(lines.some((l) => l.startsWith('FAIL param.') && l.includes('image-alt'))).toBe(false);
  expect(lines.some((l) => l.startsWith('FAIL stepped.dark.sm: label'))).toBe(true);
  expect(lines.some((l) => l.startsWith('FAIL plain.'))).toBe(false);
});

test('parameters.harness.hover = false turns the state-name fallback off; "" is an error', async () => {
  const { res, manifest } = await render('hoveroff', [
    story('x-hover', 'hovernone--story'),
    story('y-hover', 'hoverempty--story'),
  ]);
  expect(res.stdout).not.toContain('FAIL x-hover');
  expect(byState(manifest, 'x-hover').every((s) => s.status === 'ok')).toBe(true);
  for (const s of byState(manifest, 'y-hover')) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/parameters\.harness\.hover is an empty string/);
  }
});

test('a hover that cannot be performed keeps the cause (covered by an overlay), not "no element matched"', async () => {
  const { manifest } = await render('hovercover', [story('c-hover', 'hovercover--story')], {
    env: { ATELIER_RENDER_STEP_TIMEOUT_MS: '400' },
  });
  for (const s of manifest.shots) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/^Hover on .* failed: /);
    expect(s.error).not.toMatch(/no hoverable element matched/);
  }
});

test('hover requested but nothing to hover is error, not a silent un-hovered shot', async () => {
  const { manifest } = await render('nohover', [story('x-hover', 'plain--story')]);
  for (const s of manifest.shots) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/Hover requested but no hoverable element/);
  }
});

test('the capture path never clicks or presses the mouse (frame adds an empty button on mousedown or click)', async () => {
  const { res } = await render('noclick', [story('a', 'plain--story'), story('b-hover', 'hover--story')]);
  expect(res.stdout).not.toContain('button-name');
});

test('finite animations show their END state (not the base style); an infinite one is held at its first frame', async () => {
  const { res, out } = await render('anim', [
    story('end', 'endblue--box'), story('blue', 'solidblue--box'),
    story('loop', 'loopgreen--box'), story('green', 'solidgreen--box'),
  ]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const same = async (x, y) => (await png(out, 'anim', `${x}.light.sm.png`)).equals(await png(out, 'anim', `${y}.light.sm.png`));
  expect(await same('end', 'blue')).toBe(true);
  expect(await same('loop', 'green')).toBe(true);
});

test('full-page shots at the requested width; a fixed 100vh element stays viewport sized', async () => {
  const { res, out } = await render('fixedpos', [story('sheet', 'fixed--sheet'), story('long', 'tall--page')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  for (const [file, w] of [['sm', 375], ['md', 768], ['lg', 1280]]) {
    expect(size(await png(out, 'fixedpos', `sheet.light.${file}.png`))).toEqual({ w, h: 800 });
    const tall = size(await png(out, 'fixedpos', `long.light.${file}.png`));
    expect(tall.w).toBe(w);
    expect(tall.h).toBeGreaterThan(2000);
  }
});

test('plan accepts a hover setup step and rejects an empty one', () => {
  const t = (setup) => ({ baseUrl: 'http://x.test', slug: 's', targets: [{ state: 'a', url: '/a', setup }] });
  expect(() => validatePlan(t([{ hover: '#b' }]))).not.toThrow();
  expect(() => validatePlan(t([{ hover: '' }]))).toThrow(PlanError);
});
