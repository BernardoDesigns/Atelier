import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp, fixtures } from './helpers.mjs';
import { writeFile, readFile, readdir, mkdir, symlink } from 'node:fs/promises';
import path from 'node:path';
import { validatePlan } from '../src/plan.mjs';

test.afterAll(cleanupTmp);

async function render(fixture, slug, targets, { dir, env } = {}) {
  dir = dir || (await mkTmp());
  const planFile = path.join(dir, `plan-${slug}.json`);
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug, targets }));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fixtures(fixture)], { env });
  const read = async (f) => JSON.parse(await readFile(path.join(out, slug, f), 'utf8').catch(() => 'null'));
  return { res, dir, out, manifest: await read('manifest.json'), axe: await read('axe.json') };
}

test('theme markers are on <html> before the page scripts run (dark shot saw them at load)', async () => {
  const { res, manifest, axe } = await render('theme-load', 'themed', [{ state: 'page', url: '/index.html' }]);
  // If the markers arrived late, the page inserts an image with no alt at load and the dark shots fail image-alt.
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(manifest.shots.every((s) => s.status === 'ok')).toBe(true);
  expect(axe.totals).toEqual({ minor: 0, moderate: 0, serious: 0, critical: 0 });
  expect(axe.shots.length).toBe(6);
});

test('a rerun with a renamed state leaves no stale PNG, manifest or axe from the first run', async () => {
  const first = await render('ok', 'rerun', [{ state: 'alpha', url: '/index.html' }]);
  expect(first.res.code).toBe(0);
  const second = await render('ok', 'rerun', [{ state: 'beta', url: '/index.html' }], { dir: first.dir });
  expect(second.res.code).toBe(0);
  const files = await readdir(path.join(second.out, 'rerun'));
  expect(files.filter((f) => f.startsWith('alpha.'))).toEqual([]);
  expect(files.filter((f) => f.endsWith('.png')).length).toBe(6);
  expect(second.manifest.shots.every((s) => s.state === 'beta')).toBe(true);
  expect(second.axe.shots.every((s) => s.state === 'beta')).toBe(true);
});

test('zero ok shots exits 2 with one stderr line; manifest and axe.json are still written', async () => {
  const { res, manifest, axe } = await render('ok', 'allgone', [
    { state: 'a', url: '/nope-a.html' },
    { state: 'b', url: '/nope-b.html' },
  ]);
  expect(res.code).toBe(2);
  expect(res.stderr.split('\n').filter(Boolean).length).toBe(1);
  expect(res.stderr).toMatch(/No shot rendered ok/);
  expect(manifest.shots.length).toBe(12);
  expect(manifest.shots.every((s) => s.status === 'missing')).toBe(true);
  expect(axe).not.toBeNull();
});

test('storybook frame: shot waits for story content injected after load', async () => {
  const { res, axe } = await render('storybook', 'late', [
    { state: 'late-noalt', url: '/iframe.html?id=late--noalt&viewMode=story' },
  ]);
  // The image without alt only exists after the load event, so axe seeing it proves the wait happened first.
  expect(res.code).toBe(1);
  expect(res.stdout).toContain('FAIL late-noalt.dark.sm: image-alt (critical)');
  expect(axe.totals.critical).toBeGreaterThanOrEqual(1);
});

test('storybook frame that never renders is marked error with a reason, not ok', async () => {
  const { res, manifest } = await render(
    'storybook',
    'never',
    [
      { state: 'fine', url: '/iframe.html?id=fine--story&viewMode=story' },
      { state: 'stuck', url: '/iframe.html?id=stuck--never&viewMode=story' },
    ],
    { env: { ATELIER_RENDER_STORY_TIMEOUT_MS: '600' } },
  );
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const stuck = manifest.shots.filter((s) => s.state === 'stuck');
  expect(stuck.length).toBe(6);
  for (const s of stuck) {
    expect(s.status).toBe('error');
    expect(s.error).toMatch(/Storybook story did not render/);
  }
  expect(manifest.shots.filter((s) => s.state === 'fine').every((s) => s.status === 'ok')).toBe(true);
});

test('--out must be relative without ".." unless --allow-outside (both subcommands)', async () => {
  const dir = await mkTmp();
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug: 's', targets: [{ state: 'a', url: '/index.html' }] }));
  for (const out of [path.join(dir, 'abs'), '../up']) {
    const r = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fixtures('ok')], { strictOut: true });
    expect(r.code).toBe(2);
    expect(r.stderr.split('\n').filter(Boolean).length).toBe(1);
    expect(r.stderr).toMatch(/--allow-outside/);
    const sb = await runCli(
      ['storybook', '--index', path.join(fixtures('storybook'), 'index.json'), '--base-url', 'http://x.test', '--slug', 's', '--out', out],
      { strictOut: true },
    );
    expect(sb.code).toBe(2);
    expect(sb.stderr.split('\n').filter(Boolean).length).toBe(1);
  }
});

test('strict CSP page (style-src self, no unsafe-inline): shots are ok, not error', async () => {
  const { res, manifest } = await render('strict-csp', 'csp', [{ state: 'page', url: '/index.html' }]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(manifest.shots.length).toBe(6);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots[0])).toBe(true);
});

test('portal-only story (empty #storybook-root, content appended to body) is ok', async () => {
  const { res, manifest } = await render('storybook', 'portal', [
    { state: 'dialog', url: '/iframe.html?id=overlay-dialog--portal&viewMode=story' },
  ]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(manifest.shots.every((s) => s.status === 'ok'), JSON.stringify(manifest.shots[0])).toBe(true);
});

test('symlinked slug folder or out dir is refused: exit 2, nothing in the target touched', async () => {
  const dir = await mkTmp();
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug: 'linked', targets: [{ state: 'a', url: '/index.html' }] }));

  // Slug folder is a symlink to a folder holding files the harness would otherwise delete.
  const victim = path.join(dir, 'victim');
  await mkdir(victim);
  await writeFile(path.join(victim, 'keep.png'), 'x');
  await writeFile(path.join(victim, 'manifest.json'), '{}');
  const out = path.join(dir, 'renders');
  await mkdir(out);
  await symlink(victim, path.join(out, 'linked'));
  let res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fixtures('ok')]);
  expect(res.code).toBe(2);
  expect(res.stderr.split('\n').filter(Boolean).length).toBe(1);
  expect(res.stderr).toMatch(/symbolic link/);
  expect((await readdir(victim)).sort()).toEqual(['keep.png', 'manifest.json']);
  expect(await readFile(path.join(victim, 'manifest.json'), 'utf8')).toBe('{}');

  // The out dir itself is a symlink.
  const outLink = path.join(dir, 'outlink');
  await symlink(victim, outLink);
  res = await runCli(['--plan', planFile, '--out', outLink, '--fixtures-dir', fixtures('ok')]);
  expect(res.code).toBe(2);
  expect(res.stderr).toMatch(/symbolic link/);
  expect((await readdir(victim)).sort()).toEqual(['keep.png', 'manifest.json']);
});

test('state names that differ only by case are duplicates', () => {
  expect(() => validatePlan({
    baseUrl: 'http://fixture.test', slug: 's',
    targets: [{ state: 'Home', url: '/a' }, { state: 'home', url: '/b' }],
  })).toThrow(/duplicate state/);
});
