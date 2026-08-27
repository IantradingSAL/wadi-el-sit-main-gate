# Tiny Tummy — static site + Supabase dashboard

A self-contained rebuild of **tinytummylb.com** (Tiny Tummy, Lebanon — baby
purees, finger food and cakes) as plain HTML/CSS/JS, ready for GitHub Pages,
with a Supabase-backed production dashboard.

## What's here

| File | Purpose |
|---|---|
| `index.html` | Home — hero, categories, featured products, first-1000-days story |
| `products.html` | Full menu with category filters and WhatsApp ordering |
| `why-us.html` | Why Us — dietitian designed, chef crafted, Shark Tank |
| `how-it-works.html` | Pick → we cook → delivered (next-day before 3 PM) |
| `contact.html` | Phone / WhatsApp / email + message form |
| `dashboard.html` | **Production dashboard** — staff login, product CRUD, orders |
| `js/products-data.js` | Static catalog (fallback until Supabase is connected) |
| `js/supabase-config.js` | Paste your Supabase URL + anon key here |
| `supabase/schema.sql` | Tables, RLS policies and seed data for Supabase |
| `tools/get-photos.mjs` | Downloads the real product photos from the live store |
| `images/` | Photos live here, named `<handle>.jpg` |

## 1 · Get the photos

This was built in a sandbox that could not reach the live site, so photos are
not included. On your own computer:

```bash
cd tinytummy
node tools/get-photos.mjs     # Node 18+; pulls every product photo from the live store
```

Then add by hand (export from Instagram/Canva or the old site):
`images/hero.jpg`, `images/cat-purees.jpg`, `images/cat-meals.jpg`,
`images/cat-cakes.jpg`. Any missing photo shows a placeholder — nothing breaks.

## 2 · Publish on GitHub Pages

Put this folder in its own repository (recommended — don't mix it with other
projects), then: repo **Settings → Pages → Deploy from branch → main /(root)**.
The site is 100% static; no build step.

## 3 · Connect Supabase

1. Supabase → **SQL editor** → run `supabase/schema.sql` (creates `products`
   and `orders` with row-level security, and seeds the catalog).
2. **Project Settings → API** → copy the Project URL and the **anon** key into
   `js/supabase-config.js`. Never put the `service_role` key in this repo.
3. **Authentication → Users → Add user** → create your admin email + password.

From then on the public pages read the `products` table (falling back to the
static catalog if Supabase is unreachable), and `dashboard.html` is your
production panel: sign in, edit products, prices and availability, and watch
orders arrive.

## Notes

- Prices are `null` until you set them (the site just hides the price tag);
  set them in the dashboard or in `products-data.js`.
- Ordering currently goes through WhatsApp (+961 71 008 604). The `orders`
  table and dashboard are already in place if you later add a real cart.
- The dashboard page is `noindex` and useless without a valid staff login —
  RLS in Supabase is what actually protects the data.
