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

test('a target whose URL 404s is marked missing, the other target is ok', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'atelier-missing-'));
  const planFile = path.join(dir, 'plan.json');
  await writeFile(planFile, JSON.stringify({
    baseUrl: 'http://fixture.test',
    slug: 'gap',
    targets: [
      { state: 'real', url: '/index.html' },
      { state: 'ghost', url: '/does-not-exist.html' },
    ],
  }));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', path.join(here, 'fixtures', 'missing-target')]);
  // A missing target is reported in the manifest; it is not an axe failure.
  expect(res.code, res.stdout + res.stderr).toBe(0);

  const manifest = JSON.parse(await readFile(path.join(out, 'gap', 'manifest.json'), 'utf8'));
  expect(manifest.shots.length).toBe(12);
  const ghost = manifest.shots.filter((s) => s.state === 'ghost');
  const real = manifest.shots.filter((s) => s.state === 'real');
  expect(ghost.length).toBe(6);
  expect(ghost.every((s) => s.status === 'missing' && /404/.test(s.error))).toBe(true);
  expect(real.length).toBe(6);
  expect(real.every((s) => s.status === 'ok')).toBe(true);

  const pngs = (await readdir(path.join(out, 'gap'))).filter((f) => f.endsWith('.png'));
  expect(pngs.length).toBe(6);
  expect(pngs.every((f) => f.startsWith('real.'))).toBe(true);
});
