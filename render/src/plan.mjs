// Render plan loading and validation.
//
// Plan shape:
//   { baseUrl: string, slug: string, targets: [ { state: string, url: string, setup?: Step[] } ] }
// Setup steps (run in order after the page loads, before the screenshot):
//   { click: "<css selector>" }
//   { fill: ["<css selector>", "<value>"] }
//   { wait: <milliseconds, 0..30000> }
import { readFile } from 'node:fs/promises';

export const THEMES = ['light', 'dark'];
export const BREAKPOINTS = { sm: 375, md: 768, lg: 1280 };

export class PlanError extends Error {}

// File-name-safe form of a state name. Dots are replaced because the shot
// file name is <state>.<theme>.<bp>.png and must stay parseable.
export function slugify(value) {
  return String(value)
    .trim()
    .replace(/[^A-Za-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function validateStep(step, where) {
  if (!step || typeof step !== 'object' || Array.isArray(step)) {
    throw new PlanError(`${where}: a setup step must be an object like {"click":"#id"}`);
  }
  const keys = Object.keys(step);
  if (keys.length !== 1) {
    throw new PlanError(`${where}: a setup step must have exactly one key (click, fill or wait)`);
  }
  const [key] = keys;
  const val = step[key];
  if (key === 'click') {
    if (typeof val !== 'string' || !val) throw new PlanError(`${where}: click needs a selector string`);
  } else if (key === 'fill') {
    if (!Array.isArray(val) || val.length !== 2 || typeof val[0] !== 'string' || typeof val[1] !== 'string' || !val[0]) {
      throw new PlanError(`${where}: fill needs [selector, value] as two strings`);
    }
  } else if (key === 'wait') {
    if (typeof val !== 'number' || !Number.isFinite(val) || val < 0 || val > 30000) {
      throw new PlanError(`${where}: wait needs milliseconds between 0 and 30000`);
    }
  } else {
    throw new PlanError(`${where}: unknown setup step "${key}" (use click, fill or wait)`);
  }
}

// Returns a normalised copy of the plan. Throws PlanError with a single-line message.
export function validatePlan(plan) {
  if (!plan || typeof plan !== 'object' || Array.isArray(plan)) {
    throw new PlanError('Invalid plan: expected a JSON object');
  }
  for (const key of ['baseUrl', 'slug', 'targets']) {
    if (plan[key] === undefined || plan[key] === null || plan[key] === '') {
      throw new PlanError(`Invalid plan: missing "${key}"`);
    }
  }
  if (typeof plan.baseUrl !== 'string') throw new PlanError('Invalid plan: "baseUrl" must be a string');
  let base;
  try {
    base = new URL(plan.baseUrl);
  } catch {
    throw new PlanError(`Invalid plan: "baseUrl" is not a URL: ${plan.baseUrl}`);
  }
  if (base.protocol !== 'http:' && base.protocol !== 'https:') {
    throw new PlanError('Invalid plan: "baseUrl" must be http or https');
  }
  if (typeof plan.slug !== 'string' || slugify(plan.slug) !== plan.slug) {
    throw new PlanError('Invalid plan: "slug" may only contain letters, digits, "-" and "_"');
  }
  if (!Array.isArray(plan.targets) || plan.targets.length === 0) {
    throw new PlanError('Invalid plan: "targets" must be a non-empty array');
  }
  const seen = new Set();
  const targets = plan.targets.map((t, i) => {
    const where = `Invalid plan: targets[${i}]`;
    if (!t || typeof t !== 'object') throw new PlanError(`${where} must be an object`);
    if (typeof t.state !== 'string' || !t.state) throw new PlanError(`${where} is missing "state"`);
    if (typeof t.url !== 'string' || !t.url) throw new PlanError(`${where} is missing "url"`);
    const state = slugify(t.state);
    if (!state) throw new PlanError(`${where} "state" has no usable characters`);
    if (seen.has(state)) throw new PlanError(`Invalid plan: duplicate state "${state}"`);
    seen.add(state);
    if (t.setup !== undefined) {
      if (!Array.isArray(t.setup)) throw new PlanError(`${where} "setup" must be an array`);
      t.setup.forEach((s, j) => validateStep(s, `${where}.setup[${j}]`));
    }
    return { state, url: t.url, ...(t.setup ? { setup: t.setup } : {}) };
  });
  return { baseUrl: plan.baseUrl, slug: plan.slug, targets };
}

export async function loadPlan(file) {
  let text;
  try {
    text = await readFile(file, 'utf8');
  } catch {
    throw new PlanError(`Cannot read plan file: ${file}`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new PlanError(`Plan file is not valid JSON: ${file}`);
  }
  return validatePlan(json);
}
