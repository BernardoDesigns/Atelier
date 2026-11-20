# Vetting record: Awwwards MCP

Vetted 2026-11-20 against `guardrails/VETTING.md`. **Verdict: pass, with the notes below.** Re-vet on any version bump in `../servers.json`: a clean 1.21.1 says nothing about the next one.

## What was vetted

| Item | Pinned to | Identity |
|---|---|---|
| `awwwards-mcp` | 1.21.1 | git commit `93c4d41dfef00225b4593494ee411d7e40b1d361` (tag `v1.21.1`), npm integrity `sha512-iIe7Mkydoz7/e41S13TxhlE4+px/cWaXBfZIC5UNH1GA4AYgaUrNaqOf8TiwiFXQsTOZeV/t8JZt2vRRrMXJrg==` |
| awwwards skills (9) | `skills-v2026.11.19` | tag object `3376c0a580bd4f4074e2efae72578d7866d02430` |
| `ffmpeg-static` | 5.3.0 | install script allowed; downloads ffmpeg release `b6.1.1` |
| `playwright` | 1.65.1 | Microsoft, not re-vetted here |

## Checklist

1. **SKILL.md, top to bottom.** All 9 read in full (atlas, design-md, doctor, inspiration, motion-study, section-loop, setup, motion-authoring, recreate). Nothing tells the model to ignore its rules, hide actions, or fetch and run code. Several add guardrails of their own: respect robots.txt, refuse private addresses, never `rm -rf` the cache, ask before pruning, never claim rights to reuse assets. `v2-routing.md` is byte-identical across all 9; `_memory/techniques.json` is data (methods and citations), no commands.
2. **Every script and hook.** The package has no `preinstall`/`install`/`postinstall` hook and 3 runtime dependencies. All 139 `dist/` files (about 77k lines) were scanned for process spawns, `eval`/`new Function`, dynamic imports, credential paths, base64 blobs, env reads and network calls, and every file with a hit was read:
   - `version-check.js`: once a day, reads `registry.npmjs.org/awwwards-mcp/latest`. Self-update only with `AWWWARDS_AUTO_UPDATE=1` (off here, keep it off so the pin holds), and only after the version string passes a strict semver check, no shell.
   - `env-check.js`: once a day, launches `node -e` probes that import playwright and ffmpeg-static. Fixed strings, no input.
   - `perf-live.js`: launches headless Chrome with a fresh profile (`--headless --no-first-run --disable-extensions`, no user data dir), so never your signed-in profile.
   - `motion.js`, `motion-sheet.js`: run ffmpeg with fixed argument lists and a 60s timeout.
   - `scene-verify.js`: one `new Function` over a constant image-diff routine evaluated in a blank browser page. No user input reaches it.
   - `scene-capture.js`: `createRequire` only resolves the optional `spectorjs` bundle.
   - No reads of `~/.ssh`, `~/.aws`, `.npmrc`, `.netrc`, `.env`, the keychain or browser profiles. No encoded blobs. Env vars read: its own `AWWWARDS_*`/`ATLAS_*` plus `PATH`.
   - The one bundled skill script, `awwwards-design-md/scripts/validate-design-md.mjs`, reads the two files you pass it and runs `python3 -c` with a fixed YAML-parse script.
3. **Tools and scopes.** 41 tools in the default `full` profile (45 with Atlas, 13 in `core`). Not read-only: they launch a headless browser and write to the cache. Hosts contacted: `www.awwwards.com`, `assets.awwwards.com`, `registry.npmjs.org`, localhost for its own browser, plus whatever URL you ask it to capture. A public-network guard refuses private, loopback and metadata addresses. No Awwwards tool is auto-allowed in `~/.claude/settings*.json`, so Claude Code asks per call.
4. **What it writes and where.** `~/.awwwards-mcp/` (cache, preferences, captures) and temp dirs. Two exceptions write where the agent points them, inside a containment check that refuses paths escaping the chosen folder: `build_project` (`--out`) and the motion-sheet output. **Flag:** keep those on ask, never auto-allow them.
5. **Origin.** One maintainer (npm `7nsane`), MIT, repo created 2026-09-18, 893 stars, 58 forks, pushed 2026-11-19, 29 releases in two months. Fast cadence, so re-vet each bump. 1.21.1 carries an npm SLSA provenance attestation: built by `.github/workflows/release.yml` from tag `v1.21.1`, commit `93c4d41`, which matches the repo tag, and the attested sha512 matches the registry integrity npm verifies on install.
6. **Pinned.** Packages to `x.y.z`, skills to a tag, enforced by `mcp/tests/check.sh`.
7. **Throwaway trial.** Not done before install. It was installed on the main machine first, then vetted. The installer itself was tested against stubs and a temp `HOME`.
8. **Understood all of it.** Yes for every file with a risk primitive. The remaining `dist/` files were scanned, not read line by line.

## Notes to carry

- `ffmpeg-static`'s install script downloads the ffmpeg binary from its own GitHub release over HTTPS without a checksum. Long-standing, widely used, but it trusts GitHub.
- `awwwards-inspiration` tells the model to `curl` element videos from the Awwwards CDN. The Atelier network guardrail asks before curl reaches a non-local host.
- `awwwards-design-md` suggests an optional `npx --yes @google/design.md` lint, which runs an unpinned package. Decline it or pin it.
- `recreate` copies a reference site's real assets for a local study build and requires a "do not publish" disclaimer in every output. Keep that disclaimer.
- The skills' "close the flywheel" step writes learned rules into the installed SKILL.md files, but only through a dev script that is not shipped. Re-installing from the pinned tag resets them.
