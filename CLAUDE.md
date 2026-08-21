# wadi-el-sit-main-gate — working notes

The municipal portal for بلدية وادي الست. Static pages served by GitHub Pages
from the repository root (`CNAME` → `app.municipality-wadi-el-sitt.org`), on a
Supabase project shared with one other, unrelated application.

## Every new setting or feature goes into the user profile

**This is a standing rule, not a per-task instruction.** Whenever a change adds
a setting, an administrative screen, or any capability that not everyone should
have, it is not finished until all four of these are done:

1. **A permission key of its own** — `sandouk_series`, not a reuse of a broader
   one like `settings_edit`. If it is worth restricting, it is worth naming.
2. **A role default** in `role_permissions`, for *every* role — `true` for the
   roles that should hold it, an explicit `false` for the rest. Migrations
   `07`–`12` are the precedent.
3. **A row on the user screen** — add the key to `WP_GROUPS` in
   `dashboard.html`, in the group it belongs to, with an Arabic label. This is
   what makes it grantable to one person without changing their role.
4. **The database enforcing the same key** — a page gate alone is not a gate.
   Whatever table or key the feature writes, its RLS policy must ask
   `has_perm('<the same key>')`. `has_perm()` resolves *per-user override →
   role default → super_admin → false*, so a per-person grant works everywhere
   at once.

Then gate the UI on it (`WadiPerms.can('<key>')`) so the page and the database
agree about the same person.

## Cash box (`sandouk.html`)

- **Sanad numbers** are `PREFIX-YEAR-NNN` (`Q-2026-026`, `S-2026-003`). The
  prefix, and the number each year's series starts from, are configuration —
  ⚙️ الإعدادات → 🔢 ترقيم السندات, stored in `settings.sandouk_series`, guarded
  by `sandouk_series`. A configured start only ever moves a series forward; it
  can never reissue a number.
- The legacy plain numbers (the paper receipt book, income 472…1350) stay in
  the ledger as history and no longer drive the next number.
- **The changeover, for the record:** the municipality's paper receipt book
  closes at **1350**, and app numbering runs from **`Q-2026-001`** (income) and
  **`S-2026-001`** (expenses). The two series are deliberately parallel, not
  continuous — an auditor comparing the app to the book should expect exactly
  that, and this line is the record of why.
- **Vocabulary:** it is **إيصال**, never وصل — for the number, the date and the
  document. #83 standardised the cash box; the home page followed later.
- Row actions live behind one `⋯` menu per row; the signature and attachment
  counts stay visible on the السند column.

## Cooperative (`coop.html`)

- **Sellers and delivery agents hold a session token**, not a `localStorage`
  flag. Logging in (username *or* phone + password; agents: phone + PIN) calls
  `coop_seller_login_v2` / `coop_agent_login`, which mint an opaque token.
  Every order list and every status change goes through a security-definer
  function scoped by that token — `coop_seller_orders`, `coop_agent_orders`,
  `coop_order_set_status`, `coop_order_claim`, `coop_order_assign_agent`.
- **No email and no OTP.** The municipality does not want sellers validating an
  email address, and phone OTP means an SMS provider and a bill. The token
  gives real identity without either.
- **`coop_orders` is not readable by `anon`.** Buyers read their own orders
  through `coop_buyer_orders(phone)`; placing an order goes through
  `coop_place_order()` because `.insert().select()` needs to read the new row
  back, and there is deliberately no anon SELECT policy to allow it.
- The available-delivery queue blanks the buyer's name, phone and address until
  an agent actually claims the order.

## Nothing in the web root is protected

GitHub Pages serves every file in this repository to anyone who asks. There is
no login in front of it and row-level security cannot reach it, because it is
not in the database. Two files have had to be taken out of the web root for
exactly this reason — the tax archive, and `contacts-registry.js`, which
published 601 residents' names, parents, phones, addresses, birth dates and
religious sect.

So: **personal data belongs in a table, never in a file here.** If a page needs
it, the page asks the database for it through a function that decides what that
caller may see. A privacy switch enforced in JavaScript is not a privacy switch
— `phonebook_extras.entry_hidden` filtered the directory in the browser while
the hidden person stayed fully readable in the public file underneath.

## House rules

- **Migrations are numbered files at the repo root** (`07_…sql` … `12_…sql`),
  applied to the live project and committed. Never leave a live change
  unrecorded.
- **Validate before pushing**: `node --check` every inline `<script>` block of
  every page touched, and drive the change in Chromium against the real data
  shape.
- **Bump the service-worker cache** (`sw.js`, `CACHE_NAME`) whenever a page
  changes, or returning users keep the old copy.
- **Nothing unrelated in the web root.** Everything committed here is published
  on the municipality's domain. Stale copies and other projects' pages have
  been removed from it twice; don't add more.
