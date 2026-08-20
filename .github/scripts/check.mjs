#!/usr/bin/env node
/**
 * check.mjs — the checks that used to live in someone's memory.
 *
 * Run it before pushing:   node .github/scripts/check.mjs
 * CI runs the same file, so local and CI can never disagree.
 *
 * 1. Every inline <script> in every page parses.
 * 2. No page repeats an element id (getElementById silently takes the first,
 *    which is how a button ends up wired to the wrong field).
 * 3. If a published page changed, sw.js CACHE_NAME changed too — otherwise
 *    returning users keep the old copy. Skipped when not run against a base.
 */
import { readFileSync, readdirSync, writeFileSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const problems = [];
const note = (file, msg) => problems.push(`${file}: ${msg}`);

const pages = readdirSync('.').filter(f => f.endsWith('.html'));
const scripts = readdirSync('.').filter(f => f.endsWith('.js'));

// ── 1. every inline script parses ──────────────────────────────────────────
const INLINE = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let blocks = 0;
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  let m, i = 0;
  while ((m = INLINE.exec(html))) {
    const body = m[1];
    if (!body.trim()) continue;
    // JSON-LD and templates are not JavaScript
    if (/type\s*=\s*["'](application\/(ld\+json|json)|text\/template)["']/.test(m[0])) continue;
    const tmp = join(tmpdir(), `wadi-check-${process.pid}-${blocks}.js`);
    writeFileSync(tmp, body);
    try {
      execFileSync(process.execPath, ['--check', tmp], { stdio: 'pipe' });
    } catch (e) {
      const first = String(e.stderr || e.message).split('\n').slice(0, 4).join(' | ');
      note(page, `inline script #${i} does not parse — ${first}`);
    } finally {
      try { unlinkSync(tmp); } catch {}
    }
    blocks++; i++;
  }
}

// ── 2. standalone scripts parse too ────────────────────────────────────────
for (const s of scripts) {
  try {
    execFileSync(process.execPath, ['--check', s], { stdio: 'pipe' });
  } catch (e) {
    note(s, `does not parse — ${String(e.stderr || e.message).split('\n')[0]}`);
  }
}

// ── 3. no duplicate element ids ────────────────────────────────────────────
const ID = /\sid\s*=\s*["']([^"']+)["']/g;
for (const page of pages) {
  const html = readFileSync(page, 'utf8').replace(INLINE, '');   // markup only
  const seen = new Map();
  let m;
  while ((m = ID.exec(html))) seen.set(m[1], (seen.get(m[1]) || 0) + 1);
  const dupes = [...seen].filter(([, n]) => n > 1).map(([id, n]) => `${id} ×${n}`);
  if (dupes.length) note(page, `duplicate element id — ${dupes.join(', ')}`);
}

// ── 4. a changed page means a changed cache name ───────────────────────────
const base = process.env.BASE_REF;                    // set by CI; skipped locally
if (base) {
  let changed = [];
  try {
    changed = execFileSync('git', ['diff', '--name-only', `${base}...HEAD`], { encoding: 'utf8' })
      .split('\n').map(s => s.trim()).filter(Boolean);
  } catch { changed = []; }
  const published = changed.filter(f =>
    (f.endsWith('.html') || f.endsWith('.js')) && f !== 'sw.js' && !f.startsWith('.github/'));
  if (published.length && !changed.includes('sw.js')) {
    note('sw.js', `CACHE_NAME not bumped, but these ship to users: ${published.join(', ')}`);
  }
}

// ── report ─────────────────────────────────────────────────────────────────
console.log(`checked ${pages.length} pages (${blocks} inline scripts) and ${scripts.length} scripts`);
if (problems.length) {
  console.error(`\n✗ ${problems.length} problem${problems.length > 1 ? 's' : ''}:\n`);
  for (const p of problems) console.error('  ' + p);
  process.exit(1);
}
console.log('✓ all checks passed');
