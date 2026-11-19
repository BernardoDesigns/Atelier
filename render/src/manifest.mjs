// manifest.json writer.
//
// {
//   "slug": "<slug>",
//   "baseUrl": "<baseUrl>",
//   "generatedAt": "<ISO time>",
//   "shots": [
//     { "state": "<slugged state>", "theme": "light|dark", "bp": "sm|md|lg",
//       "path": "<state>.<theme>.<bp>.png",   // relative to the manifest's folder
//       "status": "ok|missing|error",
//       "error": "<reason, only when status is not ok>",
//       "overflowX": n,          // only on shots with a PNG: px the document is wider than the viewport, 0 when none
//       "overflowBy": "<desc>" }  // only when overflowX > 0 and an element could be named
//   ],
//   "axe": null | { "minor": n, "moderate": n, "serious": n, "critical": n },
//   "overflow": n                // number of shots with overflowX > 0
// }
//
// "axe" is the per-impact violation totals from axe.json (same four counts); null only if no axe pass ran.
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

export function buildManifest({ plan, shots, axe = null, generatedAt = new Date().toISOString() }) {
  return { slug: plan.slug, baseUrl: plan.baseUrl, generatedAt, shots, axe, overflow: shots.filter((s) => s.overflowX > 0).length };
}

export async function writeManifest(dir, manifest) {
  await mkdir(dir, { recursive: true });
  const file = path.join(dir, 'manifest.json');
  await writeFile(file, JSON.stringify(manifest, null, 2) + '\n');
  return file;
}
