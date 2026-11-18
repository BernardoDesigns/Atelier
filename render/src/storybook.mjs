// Storybook index.json -> render plan. Does not start Storybook.
//
// Fields relied on (Storybook index v5, written by `storybook build` as
// storybook-static/index.json):
//   index.entries: { "<story id>": { type: "story" | "docs", id, ... } }
// Older indexes (v3/v4) key the same objects under "stories" and may omit
// "type"; an entry with no type is treated as a story.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { PlanError, slugify, validatePlan } from './plan.mjs';

// Simple glob: "*" matches any run of characters, "?" matches one. Whole id must match.
export function globToRegExp(glob) {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
  return new RegExp(`^${escaped}$`);
}

export function indexToPlan(index, { baseUrl, slug, include = [], exclude = [] } = {}) {
  const entries = index && (index.entries ?? index.stories);
  if (!entries || typeof entries !== 'object') {
    throw new PlanError('Storybook index has no "entries" object');
  }
  const inc = [].concat(include).filter(Boolean).map(globToRegExp);
  const exc = [].concat(exclude).filter(Boolean).map(globToRegExp);
  const targets = [];
  for (const [key, entry] of Object.entries(entries)) {
    if (!entry || (entry.type !== undefined && entry.type !== 'story')) continue;
    const id = entry.id || key;
    if (inc.length && !inc.some((r) => r.test(id))) continue;
    if (exc.some((r) => r.test(id))) continue;
    targets.push({ state: slugify(id), url: `/iframe.html?id=${encodeURIComponent(id)}&viewMode=story` });
  }
  if (targets.length === 0) throw new PlanError('No stories found in the Storybook index (after filters)');
  return validatePlan({ baseUrl, slug, targets });
}

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]', '::1']);

export async function readIndex(source) {
  let text;
  if (/^https?:\/\//i.test(source)) {
    const url = new URL(source);
    if (!LOCAL_HOSTS.has(url.hostname)) throw new PlanError(`Index URL must be localhost: ${source}`);
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(10000), redirect: 'error' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      text = await res.text();
    } catch (err) {
      throw new PlanError(`Cannot fetch Storybook index at ${source} (${err?.cause?.code || err.message})`);
    }
  } else {
    try {
      text = await readFile(source, 'utf8');
    } catch {
      throw new PlanError(`Cannot read Storybook index file: ${source}`);
    }
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new PlanError(`Storybook index is not valid JSON: ${source}`);
  }
}

export async function writePlan(file, plan) {
  await mkdir(path.dirname(path.resolve(file)), { recursive: true });
  await writeFile(file, JSON.stringify(plan, null, 2) + '\n');
}
