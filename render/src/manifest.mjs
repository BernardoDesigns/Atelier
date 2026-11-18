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
//       "error": "<reason, only when status is not ok>" }
//   ],
//   "axe": null | { "minor": n, "moderate": n, "serious": n, "critical": n }
// }
//
// "axe" stays null until the axe pass has run (L5-02 fills it in).
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

export function buildManifest({ plan, shots, axe = null, generatedAt = new Date().toISOString() }) {
  return { slug: plan.slug, baseUrl: plan.baseUrl, generatedAt, shots, axe };
}

export async function writeManifest(dir, manifest) {
  await mkdir(dir, { recursive: true });
  const file = path.join(dir, 'manifest.json');
  await writeFile(file, JSON.stringify(manifest, null, 2) + '\n');
  return file;
}
