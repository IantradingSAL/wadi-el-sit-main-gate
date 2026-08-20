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

### B1 · Citizen requests are received and then nothing happens 🔴

36 of 39 requests sit at `new`. The oldest is **96 days old**; the average open
request is **25 days old**; 6 are past 30 days.

The status vocabulary is not the problem — seven states exist
(`new`, `in-progress`, `pending-approval`, `approved`, `rejected`, `resolved`,
`closed`) and `citizen.html` and `dashboard.html` agree on all of them. What is
missing is everything that makes a queue move:

- **no owner** — no assignment field, so no request is anybody's job;
- **no age** — nothing on screen says a request has been waiting 96 days;
- **no escalation** — nothing changes when it has.

**Recommendation.** Three small additions, in this order:
1. an **assignee** on each request, set from the dashboard;
2. an **ageing badge** on the request card — green under 7 days, amber under 30,
   red beyond — and a default dashboard filter of *"open, oldest first"*;
3. a weekly digest to the mayor: opened, closed, still waiting.

Nothing here needs new infrastructure — push notification on status change is
already wired (`dashboard.html` → `PWA.sendPush`).

### B2 · The tracking screen tells the citizen nothing 🔴

Yesterday's work made request tracking safe (phone verification moved into the
database). But because of B1, a citizen who tracks a request almost always sees
`new` — the same answer on day 1 and day 96. A tracking feature that never changes
its answer trains people to stop using it, and to phone the municipality instead,
which is the cost the portal exists to remove.

**Recommendation.** Fix B1, and show the citizen a dated timeline
(received → under review → decision) rather than a single word.

### B3 · The irrigation register holds one row 🟠

`water.html` is public and reads `irr_owners`, which contains **1 subscriber**. The
page therefore presents an empty service to residents.

**Recommendation.** Decide: populate the register, or take the page out of the
public navigation until it is populated. A published page that shows nothing costs
credibility.

### B4 · The cooperative cannot grow past trust 🟠

Sellers and delivery agents are identified from `localStorage`; only the admin path
uses real authentication. Two consequences already recorded in yesterday's audit
stand: buyer name, phone and address remain readable by anyone, and any signed-in
account can modify any product or order.

With 11 orders in three months this is not urgent — but it is the reason the shop
cannot be promoted to the whole village. It stays a decision, not a task: giving
sellers real accounts changes how every seller signs in.

### B5 · The app's sanad series and the paper book now run in parallel 🟡

Today's change (#85) made the app continue its own `Q-2026-…` series, as asked. The
paper book's plain numbers (472…1350) remain in the ledger as history. That is
coherent, but an auditor comparing app to book will see two sequences.

**Recommendation.** Record the changeover once — a dated note in the ledger, or a
line in the annual report — stating that app numbering starts at `Q-2026-001` and
the book closes at 1350. One sentence now prevents a long conversation later.

### B6 · Two receipts whose number is ambiguous 🟡

`Q-2026-014` (533 vs ٥٣٤) and `Q-2026-020` (542 vs ٥٤٣) carried two different
receipt numbers. The duplicate field is now removed (#87) but the stored values
remain. **Only the paper book can settle these two.**

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

**Recommendation.** `wadi_lang` wins; the other two become read-only fallbacks for
one release, then go.

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

### U2 · Loading and empty states are uneven 🟡

`dashboard.html` (27 indicators), `coop.html` (23) and `citizen.html` (21) are well
covered; `phonebook.html` has 3, `water.html` 4, and **`news.html` has none** — on a
slow village connection it shows an empty page with no explanation.

Empty states matter more than usual here because three modules genuinely have
almost no data (B3, B4): "لا توجد بيانات بعد" is a better answer than blankness.

### U3 · Terminology drifted back on the home page 🟡

`#83` standardised the cash box on **إيصال**. `index.html` still uses **وصل** in 4
places alongside إيصال in 4 others.

**Recommendation.** One pass over `index.html`; add the pair to a short glossary in
`CLAUDE.md` so it stops recurring.

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
| 3 | **Assignee + ageing badge + oldest-first** on citizen requests | 1–2 days | 36 residents waiting, 6 of them over a month |
| 4 | **Update prompt** in the service worker instead of silent takeover | hours | stops the app changing under a cashier mid-entry |
| 5 | **Session-expiry guard** in `auth-common.js` | hours | one place, all 25 pages |
| 6 | ~~**Clean the web root** (P9)~~ — **done**, and it was a data exposure, not tidiness | done | the tax archive was public; the git-history question remains open |
| 7 | **Citizen timeline** instead of a single status word | days | makes tracking worth using |
| 8 | **Decide the irrigation register**: populate or unpublish | decision | a public page showing one row |
| 9 | **Language key + coop dictionary consolidation** | days | one preference, one translation home |
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
