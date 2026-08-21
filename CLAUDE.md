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
- **A report is its scope, whole.** 📊 التقارير has its own filter bar
  (نطاق التقرير), and every output built there — the summary tables, the PDF, the
  CSV, the WhatsApp text — reads the same filtered rows and prints the scope on
  the page. Before that, the summaries and the CSV covered the whole box while
  the PDF's ledger pages followed the *ledger* tab's filters, so one document
  disagreed with itself. The ledger's own فلاتر stay separate; 📊 تقرير بهذه
  الفلاتر carries them over on purpose.
- **An attachment opens; it does not download.** A signed Storage link only
  carries `?download=<name>` for the ⬇️ button. Asking for it on the view link is
  what made every tap save the file instead of showing it, and the tab is opened
  synchronously inside the click so a popup blocker still lets it through.
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

## Staff activity (📊 تتبع نشاط الموظفين)

- Activity rows live in **`app_activity`** (migration 26), not in
  `localStorage`. The screen showed zeros for exactly that reason: it was
  reading the supervisor's own browser, and every employee's actions stayed on
  their own device.
- The key is **`activity_view`** — super_admin, mayor and admin by default,
  explicit `false` for every other role, grantable per person from the user
  screen. The read policy asks `has_perm('activity_view')`; INSERT is limited to
  `actor_id = auth.uid()`, and there is no UPDATE or DELETE policy.
- **`public.audit_log` on this project is not ours.** Its pages are inventory,
  suppliers, invoices and employees — it belongs to the other application
  sharing the Supabase project. Never point a municipality screen at it.

## Anything awaiting validation (🔔 طلبات التحقق)

- A coop seller, a delivery agent, a phonebook entry, a proposed phonebook edit
  and a new account all queue a row in **`approval_requests`** (migration 27)
  from a **database trigger**, and `approval_notify()` hands it to `pg_net`,
  which calls the `notify-approval` edge function (Brevo). The browser is not in
  that path on purpose: `coop.html` used to fire the old
  `notify-coop-registration` itself, so a closed tab lost the notification.
- Recipients are `settings.approval_notify` **plus every super_admin**, resolved
  live by `approval_recipients()`. `notified_at` is stamped only on a successful
  send, and the `approval-notify-sweep` pg_cron job retries the rest for a week.
- **`approval_decide()` is the only way to decide.** It moves the queue row and
  the thing it stands for in one call — approving a seller sets
  `coop_sellers.status`, approving an edit applies `proposed` onto the target —
  so the two can never disagree. The key is **`approvals_manage`**.
- Every trigger swallows its own errors: a registration must never fail because
  the queue or the mailer is having a bad day.

## Phone numbers are Lebanese, and `number-format.js` owns the rule

- One shape everywhere: **`+961 3 922 209`**, **`+961 76 789 039`**. Lebanon
  writes a number nationally with a trunk **0** (03, 70, 71, 76, 78, 79, 81,
  01/04–09) and that 0 is **dropped** after the country code. Keeping it is what
  printed `+961 0 392 2209` in the directory — a number no phone can dial.
- `phoneDisplay()` / `phoneE164()` / `phoneWa()` / `phoneValid()` live in
  `number-format.js`; every page that shows or takes a number loads it. Storage
  is `+9613922209`, display is grouped, `wa.me` gets bare digits.
- **`data-phone` on an input** opens it with `+961 ` already there and formats it
  on blur (not on every keystroke — that fights the caret). PIN boxes are
  `type=tel` too: they carry `inputmode="numeric"` and are deliberately skipped.
- The security-definer RPCs (`coop_agent_login`, `coop_buyer_orders`,
  `citizen_track_case`, `coop_seller_login_v2`) already compare
  digits-minus-961-minus-0 on both sides, so old national values and new
  international ones match each other. Keep any new phone lookup on that rule.

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
