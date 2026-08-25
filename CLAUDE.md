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
3. **A row on the user screen** — add the key to `UP_MODULES` in
   `dashboard.html`, in the module it belongs to, with `pk_<key>` labels in
   the `UP_T` dictionary in **all three languages** (ar/en/fr). This is what
   makes it grantable to one person without changing their role.
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
- **A decision taken anywhere closes the request everywhere.** The phonebook's
  own popup and the coop admin panel resolve records directly, and they predate
  the queue; migration 29 has the watchers mirror that outcome onto
  `approval_requests` (`حُسم من الشاشة الخاصة بالسجل`) so the 🔔 badge never
  counts something already settled.
- **`approval_decide()` is the only way to decide from the queue.** It moves the queue row and
  the thing it stands for in one call — approving a seller sets
  `coop_sellers.status`, approving an edit applies `proposed` onto the target —
  so the two can never disagree. The key is **`approvals_manage`**.
- Every trigger swallows its own errors: a registration must never fail because
  the queue or the mailer is having a bad day.
- **The notice names the subject, not the submitter.** A proposed directory edit
  resolves the person it is about (`approval_pb_person`) and carries the change
  field by field — `المهنة: — ← موظف` — with phone numbers already in `+961`
  form (`lb_phone_display`, migration 28). The first version said only "من
  IMAD", which told a reviewer nothing about whose record it was.
- **Every link lands on a record**: the email's button opens
  `dashboard.html#approval=<id>` — that one request with its decision buttons —
  and a directory row also carries `phonebook.html#contact=<id>` for the
  person's own card. `#review=<id>` opens the phonebook's review panel with the
  item highlighted.

## Who is told, and how (🔔 قنوات التنبيه)

- **The permission decides WHO is told; the preference decides HOW.** One row
  per person in **`user_notify_prefs`** (migration 33): a `phone` and a
  `channels` jsonb keyed by the `approval_requests.kind` values —
  `{"phonebook_edit":{"email":true,"push":true,"whatsapp":false}}` — so the
  queue's own kinds are the registry of events, and "Paul reviews the
  phonebook" never wakes him for a coop seller.
- Channels only ever *deliver*: e-mail and push reach a person exclusively
  while `user_has_perm(user,'approvals_manage')` holds. Losing the permission
  silences every channel with it — nothing to clean up, no stale recipients.
- `approval_recipients(kind)` = the `settings.approval_notify` list + the super
  admins (each may switch an event's 📧 off; the settings list itself is
  independent and always sends) + every reviewer who switched 📧 on for that
  kind. `approval_push_targets(kind)` are the reviewers' phones with 🔔 on;
  `approval_enqueue` fires the push once, deliberately outside the e-mail's
  retry sweep, through `push_notify` like every other push.
- **`whatsapp` and `sms` are stored and send nothing.** Neither service is
  connected; the keys exist so connecting a provider later activates everyone
  who already opted in, with no second round of setup.
- The matrix is edited from two views of the same rows: per person in the
  التنبيهات tab of the employee profile, and per event in the 🔔 توزيع
  التنبيهات tab of the user screen ("for the phonebook: Paul push+email, Imad
  email"). Both are behind
  its own key **`notify_prefs_edit`** (super_admin, mayor, admin by default),
  and the table's RLS asks the same key. The old 📧/💬 toggles in 🔐 تخصيص and
  the create-user form wrote `user_metadata` that nothing read — they are gone;
  both places now point here.

## Push notifications

- **`push_notify()` is the only way the database sends one.** Every trigger
  calls it and nothing else: a directory entry decided, a proposed edit applied,
  a coop seller or delivery agent accepted, an order confirmed or delivered, an
  irrigation turn due. It refuses a send with no audience — a bug that silently
  addressed *everybody* is the worst failure this feature has.
- **It authenticates with a secret of its own**, `push_internal_token` in the
  vault, checked back through `push_internal_auth()`. Deliberately not the
  service-role key: the `notify-i18n` trigger carries that key in plaintext
  inside its own definition, and this path does not repeat it. A caller who
  leaks the push token can send notifications and nothing else.
- **`push_log` says it was sent; `push_receipts` says what became of it.** One
  row per device, written by the edge function; the service worker then stamps
  `delivered_at` on the `push` event and `opened_at` on the tap, through
  `push_receipt_mark`, keyed on the device's own endpoint. The log id travels
  inside the payload as `logId` — a payload without one cannot be reported, so
  a notification queued before migration 31 reads «قبل التتبّع» rather than
  pretending it went unread.
- **أُرسل, وصل and فُتح are three different facts.** The push service accepting
  a message is not the phone receiving it, and neither is somebody reading it.
  📬 سجل الإشعارات keeps the three columns apart, behind **`push_log_view`** —
  its own key, because sending and seeing who read what are different powers.
- **The irrigation reminders have no event to hang off**, so they are a pg_cron
  sweep (`irr_push_sweep`, every 15 min) that recomputes the cycle the way
  water-admin.html draws it, in Beirut time, with `irr_push_sent` as the ledger
  that makes each reminder fire once. The four kinds and their default on/off
  state match the screen: tomorrow / morning / one_hour on, end off.
- **Targeting reads `user_role`, never `role`.** The table carries both; `role`
  is a dead column nothing reads (kept only until cached clients rotate).
  Registration goes through **`push_device_register`**, updates through
  **`push_device_update`** — both keyed on the device's own endpoint, because
  the table no longer accepts UPDATE or DELETE from `anon` (it used to accept
  both from anyone, which was enough to erase every subscription).
- **A sender must pass the signed-in user's access token**, not the anon key:
  `send-push` resolves the caller from that JWT and an outward send with no
  caller is refused 403 — silently, since a refusal writes no `push_log` row.
  That is exactly how the broadcast screens stopped working for three weeks.
- **`autoLink()` never defaults a role.** Passing `'citizen'` re-labelled staff
  phones on their next visit to a public page, and municipal alerts then matched
  no device. Its dedupe signature includes the role for the same reason.
- Phone targeting matches on the generated `phone_norm` (digits, no 961, no
  trunk 0), so `03…`, `3…` and `+9613…` all find the same device.
- Full findings: `AUDIT-2026-08-22-push.md`; the database half: migration 30.

## بطولة وادي الست (`games.html` · `games-screen.html`)

- Four knockout competitions: طاولة **فرنجية/محبوسة** (solo, 2 players a table,
  every round best-of-3) and ورق **طرنيب/أربعمية** (teams of two — optionally
  named — 2 teams a table, one decisive match). Fees: 10$/person, 20$/team,
  **5$ for a tawli player who brings a board** — a mandatory choice at
  registration. Registering makes the fee DUE; a no-show still owes it and the
  matches count as lost — stated on the card, the consent checkbox, the ticket,
  and applied by the referee's 🚫 غياب button (walkover + `attended=false`).
- **A table seat is issued like a sanad number**: `club_register()` under a
  per-game advisory lock — never twice, no cap (tables grow with demand). One
  entry per person per game, matched on `lb_phone_norm` including partners.
- Dates, deadline, fees and open/close are `settings.club_games`, edited from
  the page's ⚙️ admin sheet — never code. Setting `event_ts` arms the
  `club-push-sweep` reminders (غداً / قبل ساعة، once each via `club_push_sent`).
- **The bracket**: `club_generate_bracket` (locks registration first from the
  UI), byes auto-advance, `club_match_set` scores best-of-N and promotes the
  winner (a decided match is editable only until the next round's slot is
  touched), `club_match_walkover` applies absence. The TV page
  (`games-screen.html`) and the page read `club_bracket()` — **names and
  results only, never a phone**; the regs/matches tables have no anon access.
- Registration photos are optional and land in the **private `club-photos`
  bucket** (anon upload, read only by the key below via signed URLs). The
  consent line at registration says winners' photos go on our social pages —
  nothing is public before that.
- The key is **`club_games_manage`** (super_admin, mayor, admin by default):
  gates the page's admin sheet, the tables' RLS, the referee RPCs, and the
  organizer notifications — the `club_game_reg` event in the notify matrix
  (push + email via `notify-club-reg`), resolved per person like every other
  event. Registrants get a confirmation push on the phone they registered with.
- **The form knows the dalil** (migrations 36–37): a typed phone is looked up
  via `club_phone_lookup`, which answers only with what the public directory
  itself shows — approved entries plus registry people through
  `phonebook_public()`, whose own privacy makes a hidden phone match nothing —
  and the name pre-fills while typing. Unknown → the «هل أنت من وادي الست؟»
  popup: yes OPENS the dalil's own add form (`phonebook.html#add=<phone>|<name>`,
  pre-filled) in a new tab so the person registers themselves through the normal
  validation pipeline; no keeps them out of the dalil entirely. Tournament
  registration never waits for any of it.
- **📊 التقرير** in the admin sheet answers the organiser's three questions —
  how many came, who is from وادي الست, how much money — per game and overall.
  The wadi split reads `p1_from_wadi`/`p2_from_wadi` (migration 39), stamped at
  registration from what the form learned: in the dalil or answered «نعم» →
  `true`, answered «لا» → `false`, never asked → `null`, shown as «غير محدد»
  rather than guessed. المستحق is Σfee (a no-show still owes), المدفوع is Σfee
  where `paid`.
- **A table is two consecutive seats, grouped by number not by label.** `club_bracket`'s
  registration view groups on `ceil(seq/2)`, not on the stored `table_label`
  string, so a prefix that drifted between versions («ف1» vs «ف-1») can no
  longer split one table's two players into two cards. Migration 40 also
  repaired the drifted labels for any game whose bracket isn't generated yet.
- **The referee can rearrange seats before the bracket.** 🏆 الجدول tab, while
  still in registration, shows the tables as cards with two tappable seats;
  tap two players/teams to swap their places (across tables too). `club_seat_swap`
  exchanges the pair's `(seq, table_label, side)` under the game's advisory lock,
  refuses once any `club_matches` row exists for the game, and is gated by
  `has_perm('club_games_manage')`. Once the bracket is generated the same tab
  becomes the read-only scoring view.
- Deliberately **no home-page link** — the page is shared by URL.

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
