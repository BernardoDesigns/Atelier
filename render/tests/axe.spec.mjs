import { test, expect } from '@playwright/test';
import { execFile } from 'node:child_process';
import { mkdtemp, writeFile, readFile, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.resolve(here, '..', 'cli.mjs');

function runCli(args) {
  return new Promise((resolve) => {
    execFile(process.execPath, [cli, ...args], { timeout: 120000 }, (err, stdout, stderr) => {
      resolve({ code: err ? (typeof err.code === 'number' ? err.code : 1) : 0, stdout, stderr });
    });
  });
}

async function renderFixture(fixture, slug, targets) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'atelier-axe-'));
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug, targets }));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', path.join(here, 'fixtures', fixture)]);
  const read = async (f) => JSON.parse(await readFile(path.join(out, slug, f), 'utf8'));
  return { res, axe: await read('axe.json'), manifest: await read('manifest.json'), files: await readdir(path.join(out, slug)) };
}

test('clean fixture: axe.json written, totals zero, exit 0', async () => {
  const { res, axe, manifest } = await renderFixture('ok', 'clean', [{ state: 'detail', url: '/detail.html' }]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(axe.totals).toEqual({ minor: 0, moderate: 0, serious: 0, critical: 0 });
  expect(axe.shots.length).toBe(6);
  expect(manifest.axe).toEqual(axe.totals);
});

test('contrast fixture: exit 1, names the dark shot, files still written', async () => {
  const { res, axe, manifest, files } = await renderFixture('contrast-fail', 'contrast', [{ state: 'page', url: '/index.html' }]);
  expect(res.code).toBe(1);
  const failLines = res.stdout.split('\n').filter((l) => l.startsWith('FAIL '));
  expect(failLines).toContain('FAIL page.dark.sm: color-contrast (serious)');
  expect(failLines.every((l) => l.includes('.dark.'))).toBe(true);
  expect(axe.totals.serious).toBeGreaterThanOrEqual(1);
  expect(manifest.axe).toEqual(axe.totals);
  expect(files).toContain('axe.json');
  expect(files).toContain('manifest.json');
  expect(files.filter((f) => f.endsWith('.png')).length).toBe(6);
  // Light shots stay clean.
  for (const s of axe.shots.filter((x) => x.theme === 'light')) expect(s.violations).toEqual([]);
});

test('missing target is not an axe failure', async () => {
  const { res, axe } = await renderFixture('ok', 'gone', [
    { state: 'detail', url: '/detail.html' },
    { state: 'nope', url: '/nope.html' },
  ]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  expect(axe.shots.length).toBe(6);
});
