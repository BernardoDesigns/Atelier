import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp } from './helpers.mjs';
import { writeFile, readFile, readdir } from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test.afterAll(cleanupTmp);

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const cli = path.join(root, 'cli.mjs');

// True when something accepts a TCP connection on the port. This only connects; it never listens.
function answers(port) {
  return new Promise((resolve) => {
    const sock = net.connect({ port, host: '127.0.0.1' });
    sock.setTimeout(1000);
    sock.once('connect', () => { sock.destroy(); resolve(true); });
    sock.once('timeout', () => { sock.destroy(); resolve(false); });
    sock.once('error', () => resolve(false));
  });
}

async function unusedPort() {
  for (let i = 0; i < 50; i++) {
    const port = 20000 + Math.floor(Math.random() * 40000);
    if (!(await answers(port))) return port;
  }
  throw new Error('could not find an unused port');
}

async function planFile(baseUrl, targets) {
  const dir = await mkTmp();
  const file = path.join(dir, 'plan.json');
  await writeFile(file, JSON.stringify({ baseUrl, slug: 'ns', targets }));
  return { dir, file };
}

test('no fixtures dir and nothing on the port: exit 2, exactly one stderr line', async () => {
  const port = await unusedPort();
  const { dir, file } = await planFile(`http://127.0.0.1:${port}`, [{ state: 'home', url: '/' }]);
  const res = await runCli(['--plan', file, '--out', path.join(dir, 'renders')]);
  expect(res.code).toBe(2);
  const lines = res.stderr.split('\n').filter(Boolean);
  expect(lines.length).toBe(1);
  expect(lines[0]).toContain(`Nothing answering at http://127.0.0.1:${port}`);
  expect(await answers(port)).toBe(false);
});

test('ok fixture run: shot count is targets x 6 and no port is opened', async () => {
  const port = await unusedPort();
  const targets = [
    { state: 'home', url: '/index.html' },
    { state: 'detail', url: '/detail.html' },
  ];
  const { dir, file } = await planFile(`http://fixture.test:${port}`, targets);
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', file, '--out', out, '--fixtures-dir', path.join(here, 'fixtures', 'ok')]);
  expect(res.code, res.stdout + res.stderr).toBe(0);

  const pngs = (await readdir(path.join(out, 'ns'))).filter((f) => f.endsWith('.png'));
  expect(pngs.length).toBe(targets.length * 6);
  const manifest = JSON.parse(await readFile(path.join(out, 'ns', 'manifest.json'), 'utf8'));
  expect(manifest.shots.length).toBe(targets.length * 6);

  // Fixtures were answered by route interception: nothing is listening on the plan's port.
  expect(await answers(port)).toBe(false);
});

test('harness source never creates a server', async () => {
  const files = [cli, ...(await readdir(path.join(root, 'src'))).map((f) => path.join(root, 'src', f))];
  for (const f of files) {
    const text = await readFile(f, 'utf8');
    expect(text, f).not.toMatch(/createServer|\.listen\(|webServer/);
  }
});
