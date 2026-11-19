import { test, expect } from '@playwright/test';
import { runCli, mkTmp, cleanupTmp, fixtures } from './helpers.mjs';
import { writeFile, readFile } from 'node:fs/promises';
import path from 'node:path';

test.afterAll(cleanupTmp);

const WIDTH = { sm: 375, md: 768, lg: 1280 };
const size = (buf) => ({ w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) });

async function render(slug, pages) {
  const dir = await mkTmp();
  const planFile = path.join(dir, `plan-${slug}.json`);
  await writeFile(planFile, JSON.stringify({ baseUrl: 'http://fixture.test', slug, targets: pages.map((p) => ({ state: p, url: `/${p}.html` })) }));
  const out = path.join(dir, 'renders');
  const res = await runCli(['--plan', planFile, '--out', out, '--fixtures-dir', fixtures('viewport')]);
  const manifest = JSON.parse(await readFile(path.join(out, slug, 'manifest.json'), 'utf8'));
  const png = (file) => readFile(path.join(out, slug, file));
  return { res, manifest, png };
}
const shot = (m, state, theme, bp) => m.shots.find((s) => s.state === state && s.theme === theme && s.bp === bp);

test('a 731px table in a 375px viewport: PNG is 375 wide, overflow is reported as a fact', async () => {
  const { res, manifest, png } = await render('wide', ['wide']);
  expect(res.code, res.stdout + res.stderr).toBe(0); // overflow is information, not a failure
  for (const theme of ['light', 'dark']) {
    const s = shot(manifest, 'wide', theme, 'sm');
    expect(s.status).toBe('ok');
    expect(size(await png(`wide.${theme}.sm.png`)).w).toBe(375);
    expect(s.overflowX).toBe(356);
    expect(s.overflowBy).toBe('table#grid.data-grid[data-slot="table"]');
    expect(res.stdout).toContain(`OVERFLOW wide.${theme}.sm: page is 356px wider than 375\n`);
    // 731 fits in md and lg
    for (const bp of ['md', 'lg']) {
      const o = shot(manifest, 'wide', theme, bp);
      expect(o.overflowX).toBe(0);
      expect('overflowBy' in o).toBe(false);
      expect(size(await png(`wide.${theme}.${bp}.png`)).w).toBe(WIDTH[bp]);
    }
  }
  expect(manifest.overflow).toBe(2); // sm in 2 themes
  expect(res.stdout.match(/^OVERFLOW /gm)).toHaveLength(2);
});

test('a page that fits reports overflowX 0 and no overflow line', async () => {
  const { res, manifest, png } = await render('fits', ['fits']);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  for (const s of manifest.shots) {
    expect(s.overflowX).toBe(0);
    expect('overflowBy' in s).toBe(false);
  }
  expect(manifest.overflow).toBe(0);
  expect(res.stdout).not.toContain('OVERFLOW');
  expect(size(await png('fits.light.sm.png'))).toEqual({ w: 375, h: 800 });
});

test('a table inside its own scroll wrapper does not count as page overflow', async () => {
  const { manifest } = await render('scroller', ['scroller']);
  expect(shot(manifest, 'scroller', 'light', 'sm').overflowX).toBe(0);
  expect(manifest.overflow).toBe(0);
});

test('a tall page is still full height at the viewport width', async () => {
  const { manifest, png } = await render('tall', ['tall']);
  for (const [bp, w] of Object.entries(WIDTH)) {
    const got = size(await png(`tall.light.${bp}.png`));
    expect(got.w).toBe(w);
    expect(got.h).toBeGreaterThan(2000);
  }
  expect(manifest.overflow).toBe(0);
});

test('html scrolls but body clips overflow-x: the page cannot scroll, so no overflow is reported', async () => {
  const { res, manifest, png } = await render('clipbody', ['clipbody']);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const s = shot(manifest, 'clipbody', 'light', 'sm');
  expect(s.overflowX).toBe(0);
  expect('overflowBy' in s).toBe(false);
  expect(manifest.overflow).toBe(0);
  expect(size(await png('clipbody.light.sm.png')).w).toBe(375);
});

test('html{overflow-x:hidden} content that is cut off is still reported as overflow', async () => {
  const { manifest, png } = await render('cliphtml', ['cliphtml']);
  const s = shot(manifest, 'cliphtml', 'light', 'sm');
  expect(s.overflowX).toBe(356);
  expect(size(await png('cliphtml.light.sm.png')).w).toBe(375);
});

test('overflowBy names the element that really overflows, not a wrapped table or a fixed element', async () => {
  const { manifest } = await render('wrapperplus', ['wrapperplus']);
  const s = shot(manifest, 'wrapperplus', 'light', 'sm');
  expect(s.overflowX).toBeGreaterThan(0);
  expect(s.overflowBy).toBe('div#real.real');
});

test('a measurement that throws still gives an ok shot at the viewport width, without overflowX', async () => {
  const { res, manifest, png } = await render('throws', ['throws']);
  expect(res.code, res.stdout + res.stderr).toBe(0);
  const s = shot(manifest, 'throws', 'light', 'sm');
  expect(s.status).toBe('ok');
  expect(size(await png('throws.light.sm.png')).w).toBe(375);
  expect('overflowX' in s).toBe(false);
  expect(manifest.overflow).toBe(0);
});
