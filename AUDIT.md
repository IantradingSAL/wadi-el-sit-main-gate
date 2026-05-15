# 🚨 PRE-LAUNCH AUDIT — Wadi El Sit Municipality Platform

**Date:** 15 May 2026  
**Auditor:** Claude  
**Scope:** Full system review across `index.html`, `citizen.html`, `coop.html`, `phonebook.html`, `water.html`, `news.html`, `news-detail.html`, `pwa.js`, and the Supabase backend.  
**Target launch:** 2 days from now.

---

## 🔴 LAUNCH BLOCKERS — Fix these BEFORE going live

### 🔴 C1. Hardcoded super-admin password in client-side JavaScript
**File:** `coop.html` lines 2582-2590  
**Severity:** CRITICAL — Anyone can read your admin password from the page source.

```js
// coop.html — anyone can View Source and see this:
if(u==='imad'){
  const expected = SHA256('wadi@2026');  // 👈 Password in plain JS source code
  if(hash===expected){
    currentAdmin = {username:'imad', is_super:true};
    localStorage.setItem('coop_admin', JSON.stringify(currentAdmin));
    ...
  }
}
```

**Impact:** Any visitor can:
1. Open DevTools → View Source → see `'wadi@2026'`
2. Or open Console → run `localStorage.setItem('coop_admin', '{"username":"imad","is_super":true}')` → reload → they're super admin
3. They now see and can manipulate orders, sellers, all coop data

**This is exactly what your user reported** — "logged in to admin as my name."

**Fix:** See `fixes/coop.html-patched` — removes hardcoded password, requires real Supabase Auth.

---

### 🔴 C2. `user_metadata.role` is user-editable — anyone can self-promote to mayor/admin
**Files:** `citizen.html` line 637, `phonebook.html` line 2535-2536  
**Severity:** CRITICAL

```js
// citizen.html — signup
sb.auth.signUp({
  email, password: pw,
  options: { data: { name, phone, role: 'citizen' } }   // 👈 user_metadata
});

// phonebook.html — admin check
userRole = data.user?.user_metadata?.role || null;       // 👈 reads user_metadata
isAdmin = ADMIN_ROLES.includes(userRole);                // 👈 trusts it
```

`user_metadata` is **editable by the user themselves**. After signing up, any user can run in DevTools console:

```js
await window.sb.auth.updateUser({ data: { role: 'mayor' } });
location.reload();
// They are now "mayor" and pass all isAdmin checks.
```

**Fix:** Use `app_metadata` (admin-only) OR a separate `user_roles` table with RLS. SQL in `fixes/01_rls_and_roles.sql`.

---

### 🔴 C3. Display-name spoofing — "logged in as Imad"
**File:** `citizen.html` line 656  
**Severity:** HIGH — Identity confusion / social engineering risk

```js
const name = citUser?.user_metadata?.name || citUser?.email?.split('@')[0] || 'مواطن';
```

The name is read from `user_metadata` which the user controls. A malicious user can sign up, then `updateUser({ data: { name: 'عماد بطرس' } })` — now every page shows "Welcome Imad" and any case they submit appears under your real name.

**Fix:** Store the name in a server-side `profiles` table on signup. Read it from there (not from user_metadata).

---

### 🔴 C4. `coop_admins` password hashing is weak (plain SHA-256, no salt)
**File:** `coop.html` line 2594  
**Severity:** HIGH

```js
const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(pw));
// ... if(res.data.password_hash === hash) ...
```

SHA-256 is a **fast** hash — not a password hash. With a database leak, all passwords can be cracked via rainbow tables in seconds. Also: no salt → identical passwords get identical hashes → patterns visible.

**Fix:** Use Supabase Auth for all coop admins. Delete the `coop_admins` custom table. SQL in `fixes/01_rls_and_roles.sql`.

---

### 🔴 C5. RLS likely misconfigured on `coop_admins` (and possibly other tables)
**Severity:** CRITICAL if RLS is off; medium if RLS is on but policies are wrong.

The client does:
```js
sb.from('coop_admins').select('*').eq('username', u).maybeSingle();
```

If RLS is OFF or has a permissive SELECT policy, **anyone can `select *` from `coop_admins`** with the anon key — including reading the `password_hash` column. This was your own memory's "RLS gotcha" — but for `coop_admins` it appears the table was made queryable to allow this login flow to work.

**You MUST verify in Supabase Dashboard:**

```sql
-- Run this in Supabase SQL Editor:
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname='public'
ORDER BY tablename;
```

Every table should show `rowsecurity = true`. For `coop_admins`, there should be NO `SELECT FOR anon` policy.

**Fix:** SQL migrations in `fixes/01_rls_and_roles.sql`.

---

## 🟠 HIGH PRIORITY — Fix before public marketing push

### 🟠 H1. Hard-coded VAPID/Supabase keys in JS
**Files:** Multiple HTML pages, `pwa.js`  
**Severity:** HIGH

The Supabase anon key and VAPID public key are in client code. The anon key is **meant** to be public, BUT only if RLS is properly configured. If RLS is missing on any table, the anon key gives full read/write to that table.

**Action:** Verify EVERY table has RLS enabled (see SQL in fixes/).

### 🟠 H2. Missing email/push language preference
**Severity:** HIGH for user experience

When the system sends an email or push, it sends Arabic only — even if the citizen is using the English/French UI.

**Fix:** I built `functions/notify-i18n/index.ts` and `functions/send-push-i18n/index.ts` that:
1. Read `lang` from the citizen's record (added to `cases.lang` and `push_subscriptions.lang`)
2. Send the message in their preferred language
3. Everything is in code — no Brevo templates needed

### 🟠 H3. `coop.html` `cat.name` is used after we made it an object
**File:** `coop.html` (introduced by the i18n patch)  
**Severity:** MEDIUM — but will cause runtime errors on render.

In my coop.html patch I changed `CATEGORIES` items from `name:'أطعمة'` to `name:{ar:'أطعمة', en:'Food', fr:'Alimentation'}` and added a global `cat.name` → `pickLang(cat.name)` regex. The regex was aggressive — it touched code that uses `c.name` for other things (products, sellers). The fix is included in this audit.

### 🟠 H4. Coop session conflates roles
**File:** `coop.html`  
**Severity:** MEDIUM

`currentSeller` and `currentAdmin` are both stored in localStorage and read independently. There's no check that they refer to the same identity. A user could log in as a seller, then independently log in as admin, ending up with split state.

**Fix:** Tie admin to Supabase Auth + a `coop_admins` table keyed on `auth.users.id`. Same for seller. See SQL.

---

## 🟡 MEDIUM PRIORITY — Polish before launch

### 🟡 M1. Coop checkout doesn't verify stock or duplicate prevention
Users can submit the same cart twice (no idempotency token). Stock isn't decremented atomically.  
**Fix:** Add `order_idem_key` column + UNIQUE index. Decrement stock in a Postgres function with row-level lock.

### 🟡 M2. Coop "become a seller" has no email verification
Anyone can register as seller with a fake email and start listing products.  
**Fix:** Require Supabase Auth email confirmation for sellers, or add an admin approval step (already partially in schema but not enforced in UI).

### 🟡 M3. Phonebook admin panel exposes contact deletion to anyone with `isAdmin=true`
Tied to C2. Once C2 is fixed, this is automatically resolved.

### 🟡 M4. Push subscription lacks user identity link in some flows
`pwa.js` `linkToUser()` exists but isn't always called. Some subscriptions end up with `user_phone = null`, making targeted notifications impossible.  
**Fix:** Updated `pwa.js` in this audit always links if identity is known via `localStorage.wadi_user`.

### 🟡 M5. No CSP or rate limiting on submission forms
Citizen form submission has no rate limit — spammable.  
**Fix:** Add a Supabase Edge Function `cases-submit` that throttles by IP / phone (5 submissions per hour). Or add a Postgres trigger that counts recent submissions before INSERT.

### 🟡 M6. `index.html` What's New modal still mentions "Edge Function `send-push`" — confirm it exists in Supabase Functions dashboard
You mentioned this in your memory. Verify it's deployed and the secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` are set.

---

## ✅ AUDIT SUMMARY TABLE

| # | Severity | Issue | Status | Fix file |
|---|---|---|---|---|
| C1 | 🔴 CRITICAL | Hardcoded coop admin pwd in JS | Patched | `fixes/coop.html-patched.html` |
| C2 | 🔴 CRITICAL | `user_metadata.role` is user-editable | Patched | `fixes/01_rls_and_roles.sql` + `fixes/citizen.html-patch.txt` |
| C3 | 🔴 HIGH | Display name spoofing | Patched | `fixes/01_rls_and_roles.sql` (profiles table) |
| C4 | 🔴 HIGH | Weak password hashing | Patched | `fixes/01_rls_and_roles.sql` (use Supabase Auth) |
| C5 | 🔴 CRITICAL | RLS verify | Action needed | See checklist below |
| H1 | 🟠 HIGH | RLS audit | Action needed | See checklist below |
| H2 | 🟠 HIGH | Email/push not multilingual | Built | `functions/notify-i18n/index.ts`, `functions/send-push-i18n/index.ts` |
| H3 | 🟠 MED | `cat.name` runtime bug in coop | Patched | `fixes/coop.html-patched.html` |
| H4 | 🟠 MED | Coop role conflation | Patched | `fixes/coop.html-patched.html` |
| M1 | 🟡 MED | Stock race condition | Documented | SQL function in `fixes/02_stock_idem.sql` |
| M2 | 🟡 MED | Seller email verification | Schema flag exists | Enforce in UI |
| M3 | 🟡 MED | Phonebook admin actions | Auto-fixed by C2 | — |
| M4 | 🟡 MED | Push identity link | Patched | `fixes/pwa.js-patched` |
| M5 | 🟡 MED | No rate limiting on submissions | Documented | Use Edge Function |
| M6 | ℹ️ INFO | Verify `send-push` deployed | Action needed | Supabase dashboard |

---

## 📋 PRE-LAUNCH CHECKLIST — Do this in order

### Day 1 (today)
- [ ] **C1**: Replace `coop.html` with `fixes/coop.html-patched.html` — pushes to GitHub
- [ ] **C2 + C3 + C4 + C5**: Run `fixes/01_rls_and_roles.sql` in Supabase SQL Editor (read the comments before running)
- [ ] **C2 follow-up**: Patch `citizen.html` per `fixes/citizen.html-patch.txt` (removes role from signup)
- [ ] **H2**: Deploy `functions/notify-i18n/index.ts` as a Supabase Edge Function called `notify-i18n`
- [ ] **H2**: Deploy `functions/send-push-i18n/index.ts` as a Supabase Edge Function called `send-push-i18n`
- [ ] **H2**: Run `fixes/03_lang_columns.sql` to add `lang` columns to `cases`, `push_subscriptions`, `coop_orders`
- [ ] **M4**: Replace `pwa.js` with `fixes/pwa.js-patched` (saves user language to push_subscriptions)
- [ ] **C5**: Run the RLS audit query and screenshot the result

### Day 2 (tomorrow)
- [ ] **Test C1 fix**: Try to log in as admin without correct password — should fail. Try `localStorage.setItem('coop_admin', ...)` hack — should be ignored.
- [ ] **Test C2 fix**: Sign up as a new citizen. Open DevTools console. Run `await window.sb.auth.updateUser({ data: { role: 'mayor' } })`. Refresh phonebook. Should NOT show admin panel. (Role now comes from server-side `user_roles` table.)
- [ ] **Test multilingual email**: Submit a citizen case while UI is in English. Check email — should be in English.
- [ ] **Test multilingual push**: Subscribe to push in French mode. Send a test notification from admin-push.html. Should arrive in French.
- [ ] **Test on real devices**: iPhone Safari, Android Chrome, desktop Chrome/Firefox.

### Day of launch
- [ ] Final check: hit every page in every language, click everything that's clickable.
- [ ] Have a non-technical friend try to submit a request and watch them.
- [ ] Have your phone ready for any breaking issue in the first hour.

---

## 🎯 WHAT I CAN AND CANNOT TEST FROM HERE

**I CAN:** Read code, find logic bugs, build patches, write SQL, build edge functions.

**I CANNOT:**
- Run actual penetration tests against your live Supabase
- Send a real email through Brevo to verify delivery
- Trigger a real push to a real phone
- Verify your RLS policies are actually enabled (you must run the audit query and tell me what it returns)
- Confirm Brevo / Twilio / VAPID secrets are correctly set in Supabase

For those, you need to run the verification steps in the checklist above and tell me the results.

---

## 🌐 ABOUT THE MULTILINGUAL EMAIL/PUSH SYSTEM

You asked for everything to be done in **GitHub + Supabase** with no Brevo templates. Done:

- **Email templates are inline in the Edge Function code** (`notify-i18n/index.ts`). All three languages (AR/EN/FR) are defined as inline HTML. Brevo just delivers the bytes — no template IDs needed.
- **Push templates are inline in `send-push-i18n/index.ts`** — same pattern.
- **Language source of truth:**
  - For cases: `cases.lang` (new column, populated from the citizen's `localStorage.wadi_lang` when they submit)
  - For push: `push_subscriptions.lang` (new column, populated when they subscribe)
  - For coop orders: `coop_orders.lang` (new column)
- **Fallback:** If no lang set → Arabic (your primary audience).

See `functions/` for the edge functions and `fixes/03_lang_columns.sql` for the schema additions.
