#!/usr/bin/env node
// Atelier render harness CLI.
//   node render/cli.mjs --plan <file> [--out <dir>] [--fixtures-dir <dir>]
// Exit codes: 0 ok, 1 axe found serious or critical violations, 2 bad plan, bad usage, nothing at the base URL, or the run could not complete.
import { parseArgs } from 'node:util';
import { loadPlan, PlanError } from './src/plan.mjs';
import { run, UnreachableError } from './src/run.mjs';
import { failureLines } from './src/axe.mjs';

function fail(message, code = 2) {
  process.stderr.write(String(message).split('\n')[0] + '\n');
  process.exit(code);
}

let args;
try {
  args = parseArgs({
    options: {
      plan: { type: 'string', default: '.atelier/render-plan.json' },
      out: { type: 'string', default: '.atelier/renders' },
      'fixtures-dir': { type: 'string' },
    },
    allowPositionals: false,
  }).values;
} catch (err) {
  fail(`Usage: node cli.mjs --plan <file> [--out <dir>] [--fixtures-dir <dir>] (${err.message})`);
}

try {
  const plan = await loadPlan(args.plan);
  const result = await run(plan, { outDir: args.out, fixturesDir: args['fixtures-dir'] });
  const counts = result.shots.reduce((a, s) => ((a[s.status] = (a[s.status] || 0) + 1), a), {});
  process.stdout.write(
    `Rendered ${result.shots.length} shots for ${plan.slug} -> ${result.slugDir} ` +
      Object.entries(counts).map(([k, v]) => `${k}:${v}`).join(' ') + '\n',
  );
  const failures = failureLines(result.axe);
  for (const line of failures) process.stdout.write(line + '\n');
  process.exit(failures.length ? 1 : 0);
} catch (err) {
  if (err instanceof PlanError || err instanceof UnreachableError) fail(err.message, 2);
  fail(`Render failed: ${err.message}`, 2);
}
