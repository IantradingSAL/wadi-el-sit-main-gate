#!/usr/bin/env node
/*
 * Downloads the product photos from the live Shopify store into images/,
 * named by product handle so the site picks them up automatically.
 *
 * Run this ON YOUR OWN COMPUTER (needs normal internet access + Node 18+):
 *
 *     cd tinytummy
 *     node tools/get-photos.mjs
 *
 * It reads the store's public products.json, saves the first photo of each
 * product as images/<handle>.jpg, and prints anything it could not match.
 * Re-run any time; existing files are overwritten with the latest photo.
 */
import { writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const STORE = 'https://www.tinytummylb.com';
const here = path.dirname(fileURLToPath(import.meta.url));
const imagesDir = path.join(here, '..', 'images');

const res = await fetch(`${STORE}/products.json?limit=250`);
if (!res.ok) {
  console.error(`Could not read ${STORE}/products.json — HTTP ${res.status}`);
  process.exit(1);
}
const { products } = await res.json();
await mkdir(imagesDir, { recursive: true });

console.log(`Found ${products.length} products on the live store.\n`);
for (const p of products) {
  const img = p.images && p.images[0];
  if (!img) { console.log(`  (no photo)  ${p.handle}`); continue; }
  const out = path.join(imagesDir, `${p.handle}.jpg`);
  const r = await fetch(img.src);
  if (!r.ok) { console.log(`  (failed ${r.status})  ${p.handle}`); continue; }
  await writeFile(out, Buffer.from(await r.arrayBuffer()));
  console.log(`  saved  images/${p.handle}.jpg  ← ${p.title}`);
}

console.log(`
Done. Also drop in, by hand if you like:
  images/hero.jpg        (home page hero photo)
  images/cat-purees.jpg  images/cat-meals.jpg  images/cat-cakes.jpg
Any missing photo shows a friendly placeholder until the file exists.

If your catalog on the live store differs from js/products-data.js,
update that file (or the Supabase products table) so handles match
the downloaded file names.`);
