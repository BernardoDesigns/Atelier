#!/usr/bin/env node
// Atelier render harness CLI.
//   node render/cli.mjs --plan <file> [--out <dir>] [--fixtures-dir <dir>] [--allow-outside]
//   node render/cli.mjs storybook --index <file-or-http-url> --base-url <url> --slug <slug>
//                                 [--out <plan.json>] [--include <glob>]... [--exclude <glob>]... [--allow-outside]
// Exit codes: 0 ok, 1 axe found serious or critical violations, 2 bad plan, bad usage, nothing at the base URL, no shot rendered ok, or the run could not complete.
import path from 'node:path';
import { parseArgs } from 'node:util';
import { loadPlan, PlanError } from './src/plan.mjs';
import { run, UnreachableError } from './src/run.mjs';
import { failureLines } from './src/axe.mjs';
import { indexToPlan, readIndex, writePlan } from './src/storybook.mjs';

function fail(message, code = 2) {
  process.stderr.write(String(message).split('\n')[0] + '\n');
  process.exit(code);
}

function parse(options, argv) {
  try {
    return parseArgs({ options, args: argv, allowPositionals: false }).values;
  } catch (err) {
    return fail(`Usage error: ${err.message}. See render/README.md`);
  }
}

// --out must stay inside the working tree unless --allow-outside is given.
function checkOut(out, allowOutside) {
  if (allowOutside) return;
  if (path.isAbsolute(out) || out.split(/[\\/]/).includes('..')) {
    throw new PlanError(`--out must be a relative path without ".." (got ${out}); pass --allow-outside to override`);
  }
}

async function renderCommand(argv) {
  const args = parse(
    {
      plan: { type: 'string', default: '.atelier/render-plan.json' },
      out: { type: 'string', default: '.atelier/renders' },
      'fixtures-dir': { type: 'string' },
      'allow-outside': { type: 'boolean', default: false },
    },
    argv,
  );
  checkOut(args.out, args['allow-outside']);
  const plan = await loadPlan(args.plan);
  const result = await run(plan, { outDir: args.out, fixturesDir: args['fixtures-dir'] });
  const counts = result.shots.reduce((a, s) => ((a[s.status] = (a[s.status] || 0) + 1), a), {});
  process.stdout.write(
    `Rendered ${result.shots.length} shots for ${plan.slug} -> ${result.slugDir} ` +
      Object.entries(counts).map(([k, v]) => `${k}:${v}`).join(' ') + '\n',
  );
  if (!result.shots.some((s) => s.status === 'ok')) {
    // Files are already written; the caller must not read this as success.
    fail(`No shot rendered ok for ${plan.slug} (${result.shots[0].error || 'see manifest.json'}); see ${result.manifestPath}`, 2);
  }
  const failures = failureLines(result.axe);
  for (const line of failures) process.stdout.write(line + '\n');
  return failures.length ? 1 : 0;
}

async function storybookCommand(argv) {
  const args = parse(
    {
      index: { type: 'string' },
      'base-url': { type: 'string' },
      slug: { type: 'string' },
      out: { type: 'string', default: '.atelier/render-plan.json' },
      include: { type: 'string', multiple: true },
      exclude: { type: 'string', multiple: true },
      'allow-outside': { type: 'boolean', default: false },
    },
    argv,
  );
  for (const k of ['index', 'base-url', 'slug']) {
    if (!args[k]) throw new PlanError(`Usage error: storybook needs --${k}`);
  }
  checkOut(args.out, args['allow-outside']);
  const index = await readIndex(args.index);
  const plan = indexToPlan(index, {
    baseUrl: args['base-url'],
    slug: args.slug,
    include: args.include,
    exclude: args.exclude,
  });
  await writePlan(args.out, plan);
  process.stdout.write(`Wrote ${plan.targets.length} targets to ${args.out}\n`);
  return 0;
}

try {
  const [first, ...rest] = process.argv.slice(2);
  const code = first === 'storybook' ? await storybookCommand(rest) : await renderCommand(process.argv.slice(2));
  process.exit(code);
} catch (err) {
  if (err instanceof PlanError || err instanceof UnreachableError) fail(err.message, 2);
  fail(`Render failed: ${err.message}`, 2);
}
