import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp } from './helpers.mjs';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validatePlan } from '../src/plan.mjs';

test.afterAll(cleanupTmp);

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.resolve(here, '..', 'cli.mjs');
const fx = path.join(here, 'fixtures', 'storybook');

async function adapt(extra = [], index = 'index.json') {
  const dir = await mkTmp();
  const planFile = path.join(dir, 'plan.json');
  const res = await runCli([
    'storybook', '--index', path.join(fx, index), '--base-url', 'http://storybook.test',
    '--slug', 'sb', '--out', planFile, ...extra,
  ]);
  return { dir, planFile, res };
}

test('fixture index yields 3 story targets, docs excluded, ids slugged', async () => {
  const { planFile, res } = await adapt();
  expect(res.code, res.stderr).toBe(0);
  const plan = JSON.parse(await readFile(planFile, 'utf8'));
  expect(plan.targets.length).toBe(3);
  expect(plan.targets.map((t) => t.url)).toEqual([
    '/iframe.html?id=example-button--primary&viewMode=story',
    '/iframe.html?id=example-button--secondary&viewMode=story',
    '/iframe.html?id=forms-input--with.dots%20v2&viewMode=story',
  ]);
  expect(plan.targets.map((t) => t.state)).toEqual([
    'example-button--primary', 'example-button--secondary', 'forms-input--with-dots-v2',
  ]);
  expect(() => validatePlan(plan)).not.toThrow();
});

test('--exclude removes matching stories, --include narrows', async () => {
  const ex = await adapt(['--exclude', 'example-button--sec*']);
  expect(JSON.parse(await readFile(ex.planFile, 'utf8')).targets.length).toBe(2);
  const inc = await adapt(['--include', 'forms-*']);
  expect(JSON.parse(await readFile(inc.planFile, 'utf8')).targets.length).toBe(1);
});

test('empty index exits 2 with one line', async () => {
  const { res } = await adapt([], 'empty-index.json');
  expect(res.code).toBe(2);
  expect(res.stderr.trim().split('\n').length).toBe(1);
  expect(res.stderr).toMatch(/No stories found/);
});

test('produced plan is accepted by the harness against fixtures', async () => {
  const { dir, planFile } = await adapt();
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fx]);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const files = await readdir(path.join(out, 'sb'));
  expect(files.filter((f) => f.endsWith('.png')).length).toBe(18);
  const manifest = JSON.parse(await readFile(path.join(out, 'sb', 'manifest.json'), 'utf8'));
  expect(manifest.shots.every((s) => s.status === 'ok')).toBe(true);
});
