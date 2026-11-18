import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const cli = path.resolve(here, '..', 'cli.mjs');
export const fixtures = (name) => path.join(here, 'fixtures', name);

// Runs the CLI. Tests write to mktemp dirs, so --allow-outside is added unless strictOut is set.
export function runCli(args, { strictOut = false, env = {} } = {}) {
  const full = strictOut ? args : [...args, '--allow-outside'];
  return new Promise((resolve) => {
    execFile(process.execPath, [cli, ...full], { timeout: 120000, env: { ...process.env, ...env } }, (err, stdout, stderr) => {
      resolve({ code: err ? (typeof err.code === 'number' ? err.code : 1) : 0, stdout, stderr });
    });
  });
}

const made = [];
export async function mkTmp() {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'atelier-render-'));
  made.push(dir);
  return dir;
}

// Call from afterAll. Node's fs.rm on directories this test run created itself.
export async function cleanupTmp() {
  while (made.length) await rm(made.pop(), { recursive: true, force: true });
}
