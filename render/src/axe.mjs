// axe-core pass and axe.json writer.
//
// axe.json:
// {
//   "slug": "<slug>",
//   "shots": [
//     { "state": "...", "theme": "light|dark", "bp": "sm|md|lg",
//       "violations": [ { "id": "<rule id>", "impact": "minor|moderate|serious|critical",
//                         "help": "<axe help text>", "nodes": <count of affected nodes> } ] }
//   ],
//   "totals": { "minor": n, "moderate": n, "serious": n, "critical": n }   // sum of violations per impact
// }
// Only shots that were actually loaded and analysed appear in "shots"; missing and
// errored shots are omitted. The same four counts are copied to manifest.json "axe".
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import AxeBuilder from '@axe-core/playwright';

export const IMPACTS = ['minor', 'moderate', 'serious', 'critical'];

export async function analyze(page) {
  const results = await new AxeBuilder({ page }).analyze();
  return results.violations.map((v) => ({
    id: v.id,
    impact: IMPACTS.includes(v.impact) ? v.impact : 'minor',
    help: v.help,
    nodes: v.nodes.length,
  }));
}

export function buildAxe(slug, shots) {
  const totals = { minor: 0, moderate: 0, serious: 0, critical: 0 };
  for (const s of shots) for (const v of s.violations) totals[v.impact] += 1;
  return { slug, shots, totals };
}

export async function writeAxe(dir, axe) {
  await mkdir(dir, { recursive: true });
  const file = path.join(dir, 'axe.json');
  await writeFile(file, JSON.stringify(axe, null, 2) + '\n');
  return file;
}

// One line per failing violation: "FAIL <state>.<theme>.<bp>: <rule id> (<impact>)"
export function failureLines(axe) {
  const lines = [];
  for (const s of axe.shots) {
    for (const v of s.violations) {
      if (v.impact === 'serious' || v.impact === 'critical') {
        lines.push(`FAIL ${s.state}.${s.theme}.${s.bp}: ${v.id} (${v.impact})`);
      }
    }
  }
  return lines;
}
