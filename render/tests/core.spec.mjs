import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp } from './helpers.mjs';
import { writeFile, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test.afterAll(cleanupTmp);

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.resolve(here, '..', 'cli.mjs');
const okFixtures = path.join(here, 'fixtures', 'ok');

async function tmp() {
  return mkTmp();
}

const okPlan = {
  baseUrl: 'http://fixture.test',
  slug: 'ok',
  targets: [
    { state: 'home', url: '/index.html' },
    { state: 'home open', url: '/index.html', setup: [{ click: '#open' }, { fill: ['#name', 'Ada'] }, { wait: 10 }] },
  ],
};

test('fixture plan with 2 targets writes 12 PNGs plus manifest', async () => {
  const dir = await tmp();
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify(okPlan));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', okFixtures]);
  expect(res.code, res.stderr).toBe(0);

  const files = (await readdir(path.join(out, 'ok'))).sort();
  const pngs = files.filter((f) => f.endsWith('.png'));
  expect(pngs.length).toBe(okPlan.targets.length * 6);
  expect(files).toContain('manifest.json');
  expect(pngs).toContain('home.dark.sm.png');
  expect(pngs).toContain('home-open.light.lg.png');

  const manifest = JSON.parse(await readFile(path.join(out, 'ok', 'manifest.json'), 'utf8'));
  expect(manifest.slug).toBe('ok');
  expect(manifest.baseUrl).toBe(okPlan.baseUrl);
  expect(manifest.shots.length).toBe(12);
  for (const s of manifest.shots) {
    expect(s.status).toBe('ok');
    expect(pngs).toContain(s.path);
    expect(s.path).toBe(`${s.state}.${s.theme}.${s.bp}.png`);
  }
});

test('bad plan exits 2 with one stderr line', async () => {
  const dir = await tmp();
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', targets: [] }));
  const res = await runCli(['--plan', planFile, '--out', path.join(dir, 'r'), '--fixtures-dir', okFixtures]);
  expect(res.code).toBe(2);
  expect(res.stderr.trim().split('\n').length).toBe(1);
  expect(res.stderr).toContain('"slug"');
});

test('nothing answering at base URL exits 2 with one line', async () => {
  const dir = await tmp();
  const planFile = path.join(dir, 'plan.json');
  // Port 9 (discard) is not served on dev machines; connection is refused.
  await writeFile(planFile, JSON.stringify({ ...okPlan, baseUrl: 'http://127.0.0.1:9' }));
  const res = await runCli(['--plan', planFile, '--out', path.join(dir, 'r')]);
  expect(res.code).toBe(2);
  expect(res.stderr.trim().split('\n').length).toBe(1);
  expect(res.stderr).toMatch(/^Nothing answering at http:\/\/127\.0\.0\.1:9/);
});
