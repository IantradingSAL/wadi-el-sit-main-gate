# Business-logic, protocol and UX audit — 20 August 2026

**Scope:** all 25 pages, 9 shared scripts, 5 edge functions, 13 migrations, and the
live Supabase data behind them.
**Method:** static sweeps over the whole repository, plus queries against the live
database to see how the platform is *actually used* rather than how it is meant to
be used. Counts below are measured, not estimated.

This is a different audit from `AUDIT-2026-08-19.md`, which covered access and
security. Nothing here is a security finding; yesterday's remain closed.

---

## 1. What the numbers say about how the platform is used

This reframes everything below, so it comes first.

| module | volume | newest entry | reading |
|---|---|---|---|
| **Cash box** | 163 entries | **today** (all 163 within 11 days) | the working system — daily, real, load-bearing |
| **Citizen requests** | 39 total, **36 still `new`** | 10 days ago | intake works; the workflow behind it does not |
| **Cooperative** | 11 orders in 96 days | 11 days ago | effectively dormant |
| **Irrigation register** | **1 subscriber row** | — | never populated, yet the public page ships |
| **Directory** | 601 residents | — | healthy reference data |

**The single most important observation in this audit:** the municipality has one
system that is genuinely alive (the cash box) and three that are not. Effort spent
polishing the cooperative buys nothing today. Effort spent making citizen requests
*move* buys the most, because intake already works and 36 residents are waiting.

---

## 2. Business logic

### B1 · Requests are received and then nothing happens 🔴 — acted on

36 of 39 requests sit at `new`. The oldest is **96 days old**; the average open
request is **25 days old**; 6 are past 30 days.

**Correction to the first draft of this audit.** It claimed there was no owner
field and no assignment. That was wrong: `cases.assigned` exists, the detail
view has a dropdown that writes it, the change is recorded on the request's
timeline, the list shows it, and there is even a filter by assignee. The
tooling was there all along.

What the live data shows instead is sharper: **0 of 39 requests have ever been
assigned**, only 2 have any timeline entry beyond their creation, and just 4
were touched at all after being filed. The queue was not failing for want of a
field — it was failing because nothing on screen ever said a request was old,
and the view opened on *everything, newest first*, which put the 96-day-old
request on the last page.

**Done.** The queue now opens on **🔔 المفتوحة — oldest first**; every open
request carries an ageing badge (green under 7 days, amber under 30, red
beyond); and a request with no owner reads **«بلا مسؤول»** in amber instead of
a quiet dash. The 96-day request is now the first thing a clerk sees.

**Still recommended, not built:** a weekly digest to the mayor — opened, closed,
still waiting. It needs a scheduled sender, which is a different kind of change
from a page edit.

### B2 · The tracking screen has nothing to show 🟠 — corrected

**Correction.** The first draft said the tracking screen shows the citizen a
single word. It does not: it already renders the status, a progress bar keyed
to the stage, and the request's timeline.

The screen is fine. What is missing is anything to put in it — only 2 of 39
requests have a timeline entry beyond creation. A citizen tracking a request
sees an accurate picture of a request nobody has touched.

Fixing B1 is what fills this screen. No change was needed here.

### B3 · The irrigation register holds one row 🟠

`water.html` is public and reads `irr_owners`, which contains **1 subscriber**. The
page therefore presents an empty service to residents.

**Recommendation.** Decide: populate the register, or take the page out of the
public navigation until it is populated. A published page that shows nothing costs
credibility.

### B4 · The shop was not dormant — it was shut 🔴 — fixed

**The most serious correction in this audit.** The first draft read 11 orders in
three months as low demand, and concluded the cooperative wasn't worth the
effort. That was wrong, and the conclusion drawn from it was wrong too.

Probed as `anon` — which is what every buyer in the shop is:

```
anon INSERT on coop_orders → "new row violates row-level security policy"
```

**A resident could not place an order at all.** Every INSERT policy on
`coop_orders` carried `auth.uid() IS NOT NULL`. 10 of the 11 orders were placed
within the last 30 days and the newest is dated 8 August — this is not a quiet
shop, it is one that stopped taking orders. Sellers were in the same position
from the other side: an anonymous seller's UPDATE changed **0 rows** and the
page reported success, so confirming an order silently did nothing.

Meanwhile the reads were wide open: two SELECT policies were `using (true)` for
`anon`, so every buyer's name, phone and address was downloadable.

**Both are fixed, and the fix is the identity the audit said was blocked.** The
municipality's answer to the blocking question — *no email validation, keep it
simple, use the phone number* — made it possible:

- logging in (username **or** phone + password; agents phone + PIN) mints an
  opaque **session token**. No email, no OTP, no SMS provider, nothing to
  confirm;
- every list and every status change resolves that token server-side and
  returns or touches only what belongs to its holder;
- `coop_orders` is closed to `anon` entirely — buyers place orders through
  `coop_place_order()` and track them with `coop_buyer_orders(phone)`;
- the available-delivery queue blanks the buyer's name, phone and address until
  an agent claims the order.

Verified end to end against the live database: seller logs in by username and
by phone, agent by phone and PIN, a resident places an order as `anon`, the
seller sees and confirms it, the queue hides the address, the agent claims it,
the address appears, delivery completes, a stranger's token changes nothing,
the buyer tracks by phone. Every probe row was removed afterwards.

### B5 · The app's sanad series and the paper book now run in parallel 🟡

Today's change (#85) made the app continue its own `Q-2026-…` series, as asked. The
paper book's plain numbers (472…1350) remain in the ledger as history. That is
coherent, but an auditor comparing app to book will see two sequences.

**Done.** Recorded in `CLAUDE.md`: the book closes at 1350, app numbering runs
from `Q-2026-001` and `S-2026-001`, and the two series are deliberately
parallel. An auditor comparing the app to the book should expect exactly that.

### B6 · Two receipts whose number is ambiguous 🟡

`Q-2026-014` (533 vs ٥٣٤) and `Q-2026-020` (542 vs ٥٤٣) carried two different
receipt numbers. The duplicate field is now removed (#87) but the stored values
remain. **Only the paper book can settle these two.**

### B7 · The same fault, three more times 🔴 — fixed

The blocked shop was not a one-off. Every table the public pages write to was
probed as `anon` — the role those pages actually run as. Three more found:

| who | doing what | what actually happened |
|---|---|---|
| a seller | adding a product | `42501`, violates row-level security |
| a seller | editing their own product | **0 rows changed, reported as success** |
| a resident | signing up for a bus trip | `42501`, violates row-level security |
| any visitor | subscribing to notifications | `42501`, violates row-level security |

The last one means the notification system had stopped accepting new devices
altogether — the 23 subscriptions it has are all it could ever have.

Each was the same shape: a policy written `to authenticated`, or checking
`auth.uid() IS NOT NULL`, standing in front of something only an anonymous
visitor ever does. One was even named `allow_anyone_insert` while allowing
nobody anonymous.

**Fixed in 16.** Devices manage their own subscription; residents sign up for
trips and can see how many seats are taken but not who took them; sellers write
their own products through their session token. Stock also comes off inside
`coop_place_order()` now — it used to be the buyer's browser issuing an UPDATE
against the seller's product row, refused by RLS and swallowed by an empty
catch, so stock never moved.

**Probed and found healthy**, for the avoidance of doubt: filing a municipal
request, registering as a seller, submitting a directory entry.

---

## 3. Protocol and architecture

### P1 · The app can replace itself while someone is typing 🔴

`sw.js` calls `skipWaiting()` on install and `clients.claim()` on activate, and
`CACHE_NAME` is bumped **by hand** on every change. Two failure modes follow:

- **forget the bump** → returning users keep running the old app against the new
  database, which is exactly how "it works on my phone but not hers" starts;
- **remember the bump** → the new version takes over immediately, and a cashier
  half-way through a sanad can have the page swapped underneath them.

**Recommendation.** Keep `skipWaiting` for the *first* install, but on an update
show the standard prompt — «نسخة جديدة متوفّرة — تحديث» — and only then post
`SKIP_WAITING`. Stamp `CACHE_NAME` automatically (see P2) so it can never be
forgotten.

### P2 · Nothing is checked before it reaches the municipality's domain 🔴

No CI, no tests, no build step. Every safeguard is a human remembering to run
`node --check` and open Chromium. This repository publishes straight to a
government domain on push.

**Recommendation.** One GitHub Action, ~20 lines, on every push:
`node --check` each inline `<script>`, fail on a duplicate element id, and stamp
`CACHE_NAME` from the commit sha. That is the cheapest quality win available here
and it removes P1's "forgotten bump" entirely.

### P3 · Expired sessions are not handled anywhere 🟠

`onAuthStateChange` appears in **1 of 25 pages** (`reset-password.html`). Tokens
refresh automatically while a tab is open, so this bites only when a refresh fails
— device asleep for a day, session revoked, offline — and then the user gets a raw
error or nothing.

**Recommendation.** One shared guard in `auth-common.js`: on `SIGNED_OUT` or a
failed refresh, show «انتهت الجلسة — يرجى تسجيل الدخول» and route to login.

### P4 · 237 errors are discarded silently 🟠

237 empty `catch {}` blocks across the repository. Some are correct — cleaning up a
storage object, an optional analytics ping. Many are not: they turn a failed write
into a screen that looks like it worked.

**Recommendation.** Adopt the rule the cash box already follows (49 of its paths
surface the error): silence is only for work whose failure genuinely does not
matter, and every silent catch carries a comment saying why.

### P4b · The user screen and the server disagreed about who may manage users 🔴 — fixed

The `admin-user` edge function authorised on a row in `employees` with role
`manager` — a fourth identity system, and one nothing else consults.

| account | role | `users_create` | manager row | before | after |
|---|---|---|---|---|---|
| imadaehn | super_admin | true | yes | allowed | allowed |
| **mmerhej** | **admin** | **true** | **no** | **refused: «Managers only»** | **allowed** |
| darghamf | mayor | false | no | refused | refused |
| eliac | sandouk | false | no | refused | refused |
| finance | finance | false | no | refused | refused |
| m.merhej | water_only | false | no | refused | refused |

So the dashboard showed the admin account user management, and the server
refused every call. One account in the municipality — the owner's — had a
manager row, which meant only the owner could ever create or delete a user,
whatever the user screen said.

**Fixed.** The function now asks `user_has_perm(caller, 'users_create')` — the
same resolution as `has_perm()`, for an explicit user id. Exactly one account
gains what the user screen already promised it; nobody else gains anything.
Recorded as `17_user_has_perm.sql`, and the function's source is now in the
repository at `supabase/functions/admin-user/index.ts` — it had never been
committed anywhere.

### P5 · Three identity systems, down from five 🟡

Supabase Auth + `user_roles` now governs the staff pages (10 files) — a real
improvement from yesterday. The outliers are the cooperative's `localStorage`
seller and the delivery agent's PIN. `employees` is no longer read by any page,
only by the `admin-user` edge function.

**Recommendation.** Finish the job when B4 is decided, and retire `employees` as an
identity source at the same time.

### P6 · Everything lives in one file per page 🟡

`coop.html` is 356 KB and 4,682 lines of inline JavaScript; `dashboard.html` 328 KB
/ 4,545; `phonebook.html` 256 KB / 3,481. The same helpers — money formatting,
toasts, the Supabase client, date handling — are re-implemented per page.

The extraction has already begun and works: `wadi-perms.js`, `number-format.js`,
`i18n.js`, `auth-common.js`.

**Recommendation.** Continue it deliberately, one helper at a time, in the order
that removes the most duplication: the Supabase client + auth guard, then toasts,
then dates. **Do not attempt a rewrite** — this codebase's strength is that any
page can be opened and understood on its own.

### P7 · One language preference stored under three keys 🟡

Pages write `lang`, `language` *and* `wadi_lang` — 32 writes across the repository.
A resident switching language on one page can find it unchanged on another.

**Done.** `wadi_lang` is now the only key written — 20 redundant writes removed
across five pages. Measured first: `language` was written ten times and **read
nowhere**; `lang` was written ten times and read once, by a line that already
tried `wadi_lang` first. That one reader keeps `lang` as a fallback for anyone
whose browser still holds the old key.

### P8 · Translation is split three ways 🟡

`i18n.js` covers 6 public pages; `coop.html` carries its own inline ar/en/fr
dictionary; every staff page (dashboard, sandouk, water-admin, mrs, news-admin,
admin-push, inbox) is Arabic-only.

Arabic-only for staff is a legitimate choice — say so explicitly, and fold coop's
dictionary into `i18n.js` so the public side has one home.

### P9 · The web root published the entire tax archive 🔴 — fixed the same day

What began as a tidiness item turned out to be the most serious finding of the
audit, so it is recorded at its true weight.

`mrs-import.html` was 3.5 MB, of which **3.28 MB was a single `const DATA={…}`
literal**: 28 tables, **30,258 rows** of the municipal tax archive — taxpayer
names, addresses, telephone numbers, emails and tax identifiers, 3,595
assessments, 5,215 payment transactions, 1,615 receipts.

It was a **static file on the municipality's public domain**, readable with no
login, no session and no row-level security. Migration `09` locked the `mrs_*`
tables behind `mrs_view` — a policy cannot protect a file. Two doors, one
locked.

Every embedded table matched the live database row for row, so the one-off
import it was written for had long since completed and nothing operational
depended on it.

**Fixed the same day:** the file is deleted and `mrs.html`'s empty-state hint no
longer points at it. **Not fixed by deletion:** this repository is *public*, so
the file remains in git history until the history is rewritten or the
repository is made private. That is the owner's decision and it is still open.

The rest of the sweep, corrected:

| file | verdict |
|---|---|
| `bus-trip` (37 KB, no extension) | out-of-date copy of `bus-trip.html`, nothing linked to it — **deleted** |
| `wadi-el-sit-demo.html` | **not stray** — it is the جولة إرشادية, linked from the home page and part of the cached app shell. The audit was wrong to list it; kept |
| `wadi-dashboard.html`, `water-finance.html` | sub-kilobyte redirect stubs that catch old bookmarks; they cost nothing — kept |

---

### P10 · Both document buckets were open to anyone 🔴 — fixed

Probed as `anon`, with no session at all:

| bucket | what it holds | listable by anyone |
|---|---|---|
| `case-documents` | what residents attach to a request | **74 documents** |
| `sandouk-docs` | receipts, invoices, signed vouchers | **59 attachments** |

`case-documents` carried a policy named **«Allow all storage» — cmd ALL, role
public**: an anonymous visitor could read, overwrite and **delete** every
document a resident had ever attached. Paths are `<case_id>/<timestamp>_n.jpg`
and case ids are sequential, so the set could be walked — probing `199/`
returned its document.

`sandouk-docs` was a public bucket with a SELECT policy for `anon`.

Closing the anonymous read on the cash box was not enough on its own:
`sandouk_docs_auth_all` granted ALL to *any* authenticated account, so the
water-only account could still open all 59 — the same "logged in, therefore
allowed" pattern this platform has been shedding all week.

**Fixed in 18.** Reading and removing documents now asks the same permissions
the pages do (`cases_view` / `cases_edit` / `cases_delete`, `sandouk_view` /
`sandouk_add` / `sandouk_edit`). Uploading stays open for residents filing a
request. Verified afterwards: not signed in → 0 of either; water-only → 0;
clerk → 59 and 0; mayor → 59 and 74. Product photos stay public, which is what
a shop window is for.

The pages sign a link at the moment it is clicked, for the person clicking it,
expiring in five minutes.

---

## 4. UI and UX

### U1 · 101 native dialogs, two of them collecting passwords 🔴

101 `alert` / `confirm` / `prompt` call sites. In an installed PWA these are
unstyled, LTR-centred, and block the whole app — the clearest "this is a web page,
not an app" signal the portal gives.

Two are worse than cosmetic:

```
sandouk.html:3096   prompt('كلمة المرور الجديدة (8 أحرف على الأقل):')
dashboard.html:2742 prompt('كلمة المرور الجديدة لـ '+name+' …')
```

A password typed into `prompt()` is **shown in clear text** on screen — the second
one is an administrator typing *someone else's* new password, in an office, in
plain view.

**Recommendation.** Both password paths become proper masked forms with a confirm
field — that is a small, self-contained job worth doing on its own. The remaining
dialogs migrate to the toast and modal patterns the pages already have; the cash
box is the reference.

### U2 · Loading and empty states — withdrawn

**Correction.** The first draft reported that `news.html` had no loading state
at all. It has one: a spinner with a refreshing label, and an error block
beside it. The original sweep counted only «جاري التحميل» and ⏳ and missed
`class="spin"`.

Re-measured properly, **every page has both a loading and an empty or error
state**. `inbox.html` is the thinnest of them, and even that is serviceable.
This finding is withdrawn.

### U3 · Terminology drifted back on the home page 🟡

`#83` standardised the cash box on **إيصال**. `index.html` still uses **وصل** in 4
places alongside إيصال in 4 others.

**Done.** All five occurrences on the home page now read إيصال, and `CLAUDE.md`
carries the rule — «it is إيصال, never وصل» — so it stops recurring.

### U4 · Number formatting is not uniform 🟡

`number-format.js` is loaded by 4 pages (sandouk, dashboard, coop, water-admin);
elsewhere `toLocaleString` is called directly, whose digit shapes and separators
depend on the browser's locale rather than the municipality's choice. The exposure
is small — the other pages show few amounts — but the inconsistency is visible
where they do.

### U5 · What is already good, and should be the template 🟢

Worth stating plainly, because the rest of this document is about what is wrong:

- the cash box's **⋯ row menu**, sticky columns and horizontal-scroll wrappers are
  a correct mobile answer to a wide table;
- the **audit trail** (who did what, when) is better than most municipal software;
- **signature capture**, the **paged PDF report**, and the new **⚙️ الإعدادات** tab
  are all coherent;
- the dashboard is **card-based on screen** — its only `<table>`s are print
  templates, which is the right call for a phone;
- `viewport` and `dir="rtl"` are present on every real page.

The cash box is the standard the other modules should be measured against.

---

## 5. What to do, in order

| # | Action | Effort | Why now |
|---|---|---|---|
| 1 | **Masked password forms** replacing the two `prompt()` calls | hours | passwords are on screen in clear text today |
| 2 | **CI on push** — `node --check`, duplicate-id check, auto-stamp `CACHE_NAME` | hours | nothing checks the government domain today; also fixes P1's forgotten bump |
| 3 | ~~Assignee~~ (it already existed) + **ageing badge + open-first default** — **done** | done | the 96-day request is now the first row, not the last page |
| 4 | **Update prompt** in the service worker instead of silent takeover | hours | stops the app changing under a cashier mid-entry |
| 5 | **Session-expiry guard** in `auth-common.js` | hours | one place, all 25 pages |
| 6 | ~~**Clean the web root** (P9)~~ — **done**, and it was a data exposure, not tidiness | done | the tax archive was public; the git-history question remains open |
| 7 | ~~Citizen timeline~~ — **it already exists**; B1 is what fills it | — | no change needed |
| 8 | **Decide the irrigation register**: populate or unpublish | decision | a public page showing one row |
| 9 | **Language key** — **done** (one key, 20 redundant writes removed). Coop dictionary — deferred, see P8 | part done | a preference that follows the resident between pages |
| 10 | **Cooperative real accounts** | project | unblocks B4 and P5 together; needs the auth decision first |

Items 1, 2, 4, 5 and 6 are all small, independent, and can ship this week. Item 3 is
the one that changes what residents experience.

---

## 6. Two things this audit deliberately does not recommend

- **A rewrite.** The single-file pages are large, but each is independently
  readable and independently deployable, and the extraction to shared scripts is
  already working. Continue it; do not restart it.
- **Polishing the cooperative.** 11 orders in three months. Fix identity when it is
  decided; until then the effort belongs on citizen requests.
