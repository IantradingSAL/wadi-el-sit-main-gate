# 🚀 PRE-LAUNCH CHECKLIST — Wadi El Sit Municipality

**Launch date:** 2 days from today.  
**Do the steps in order. Do not skip.**

---

## ⏱ PHASE 1 — Database hardening (15 min)

### Step 1.1 — Run the role+RLS migration
Open the Supabase SQL Editor:  
`https://supabase.com/dashboard/project/onjbwhkmmtqnymhjnplw/sql/new`

Open `fixes/01_rls_and_roles.sql` and read the comments. Then paste it ALL and click **Run**.

**Expected output:** The bottom of the file has two SELECT queries that print:
1. A list of `public.*` tables with `rowsecurity = true` for every row
2. A list of every user, their profile name, and their role

**If any row shows `rowsecurity = false`** → that table is wide open. Either turn RLS on with policies, or check why it was left off.

### Step 1.2 — Promote yourself (Imad) to mayor
Run in SQL Editor:
```sql
-- Replace YOUR_EMAIL with your real login email
UPDATE public.user_roles ur
SET role = 'mayor'
FROM auth.users u
WHERE u.id = ur.user_id
  AND u.email = 'imadaehn@gmail.com';

-- Verify:
SELECT u.email, ur.role FROM public.user_roles ur
JOIN auth.users u ON u.id = ur.user_id
WHERE u.email = 'imadaehn@gmail.com';
```

### Step 1.3 — Run the language + stock migration
Paste `fixes/02_lang_and_stock.sql` into SQL Editor → **Run**.

Verify the bottom SELECT shows `lang` columns on `cases`, `push_subscriptions`, `coop_orders`.

---

## ⏱ PHASE 2 — Deploy the new Edge Functions (15 min)

### Step 2.1 — Multilingual email
Save `functions/notify-i18n/index.ts` to your local repo at `supabase/functions/notify-i18n/index.ts`.

From terminal:
```bash
supabase functions deploy notify-i18n --project-ref onjbwhkmmtqnymhjnplw
```

Then in Supabase Dashboard → Edge Functions → `notify-i18n` → **Secrets**:
- `BREVO_API_KEY` = (your Brevo API key)
- `MUNICIPALITY_EMAIL` = `noreply@wadi-elset.lb` (or whatever sender you verified in Brevo)
- (optional) `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM` if you want WhatsApp

Now repoint the database webhook to this new function:

Supabase Dashboard → Database → Webhooks → (the webhook on `cases` table):
- **URL:** `https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/notify-i18n`
- **Method:** POST
- **Trigger on:** INSERT, UPDATE
- **Authorization header:** `Bearer <SERVICE_ROLE_KEY>`

You can leave the old `notify` function deployed as a fallback for now — once you confirm the new one works, delete the old one.

### Step 2.2 — Multilingual push
Save `functions/send-push-i18n/index.ts` to `supabase/functions/send-push-i18n/index.ts`.

```bash
supabase functions deploy send-push-i18n --project-ref onjbwhkmmtqnymhjnplw
```

Secrets:
- `VAPID_PUBLIC_KEY` = `BJjyBXyjL0fkAxlgyu715TXCkqDfTqCFwahiodJsBVtWpQ4fa3ouup8wu89sDyeWrgd5i-wirk-EfQPNzWG1-NQ`
- `VAPID_PRIVATE_KEY` = (your existing private key)
- `VAPID_SUBJECT` = `mailto:admin@wadi-elset.lb`
- `SUPABASE_URL` = `https://onjbwhkmmtqnymhjnplw.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY` = (your service role key)

Update `admin-push.html` to call the new endpoint (change `/functions/v1/send-push` to `/functions/v1/send-push-i18n`).

---

## ⏱ PHASE 3 — Push the new frontend files to GitHub (5 min)

Upload the entire contents of `/mnt/user-data/outputs/` to your repo `IantradingSAL/wadi-el-sit-main-gate`:

- `i18n.js` (shared multilingual core)
- `index.html`, `citizen.html`, `water.html`, `news.html`, `news-detail.html`, `coop.html`, `phonebook.html` (multilingual + security patches)
- `pwa.js` (saves user lang to push subscriptions)

After pushing, **hard-refresh** on your phone and laptop (`Ctrl+Shift+R`, or clear PWA cache).

---

## ⏱ PHASE 4 — Verification tests (30 min)

### Test A — Security (5 tests, all should FAIL = behavior is correct)

**A1: Old hardcoded coop admin password**
1. Open coop.html → Settings → Admin Panel
2. Type username `imad`, password `wadi@2026`
3. ❌ **Should fail** with "use email to login" or "wrong credentials"
4. ✅ This means the hardcoded path is gone.

**A2: localStorage admin spoofing**
1. Open coop.html in DevTools
2. Console: `localStorage.setItem('coop_admin', JSON.stringify({username:'imad',is_super:true})); location.reload();`
3. Try to enter the admin panel
4. ❌ **Should not enter** — `restoreAdminSession` re-validates against the server.

**A3: Self-promote via user_metadata**
1. Sign up as a new citizen on `citizen.html` with a brand-new email
2. DevTools console: `await sb.auth.updateUser({ data: { role: 'mayor' } }); location.reload();`
3. Navigate to phonebook.html → click admin badge
4. ❌ **Should NOT show admin panel** — role now comes from `user_roles` (server-side).

**A4: Display name spoofing**
1. As that new citizen: `await sb.auth.updateUser({ data: { name: 'عماد بطرس' } });`
2. Submit a case
3. Check the case in dashboard → name should be the original signup name (from `profiles.name`), NOT the spoofed one
   - **NOTE:** This only works if dashboard.html is updated to read from `profiles`. If it still reads from `cases.name` (which the user submitted), the spoof DOES work via the case form. Dashboard read-from-profiles is a separate fix beyond launch scope.

**A5: RLS audit**
1. SQL Editor:
```sql
SELECT tablename FROM pg_tables 
WHERE schemaname='public' AND rowsecurity=false;
```
2. ❌ **Should return zero rows.**

### Test B — Multilingual email

1. On `citizen.html`, switch language to **English** via the AR/EN/FR pill
2. Submit a test case with YOUR email
3. Within 30 seconds, check your inbox
4. ✅ Email subject/body should be in English
5. Repeat for **French**.

### Test C — Multilingual push

1. On any page (e.g. news.html), switch to **English**
2. Enable push notifications (click 🔔 banner)
3. Open `admin-push.html`, send a test broadcast
4. ✅ The push notification on your phone should arrive in English
5. Now switch language to **French** on the page
6. Send another broadcast from admin-push
7. ✅ Push should arrive in French (the `pwa.js` hook updates `push_subscriptions.lang` when language changes)

### Test D — Push works perfectly (device-specific)

- [ ] **iPhone Safari** (iOS 16.4+): Add to Home Screen → open as standalone app → enable notifications → send test → arrives
- [ ] **Android Chrome**: enable notifications → send test → arrives
- [ ] **Desktop Chrome**: enable → send → arrives in OS notification area
- [ ] **Desktop Firefox**: same
- [ ] **Locked screen**: notification still shows with title + body in correct language
- [ ] **Click action**: tapping the notification opens the right page (citizen.html, water.html, etc.)

### Test E — Coop functionality

- [ ] Browse home → categories show in current language
- [ ] Switch to EN → categories flip to English
- [ ] Search a product → results work
- [ ] Add to cart → cart badge updates
- [ ] Checkout → fill name/phone → submit → order is created in `coop_orders` with `lang` set
- [ ] Become a seller → signup → list a product → product appears in shop
- [ ] Stock decrement: order a product with stock=1, then try to order the same product again → second order should fail with "out_of_stock" (the `place_coop_order` SQL function handles this — call it instead of plain insert if you want this safety)
- [ ] Admin login: real email + password → admin panel opens (only for users with `role IN ('mayor','admin')`)

### Test F — Submit a case in each language (end-to-end)

For each of AR, EN, FR:
1. Switch UI to that language
2. Submit a request with a real email + phone
3. Verify email arrived in that language
4. Mark the case as "in-progress" in the dashboard
5. Verify the status-change email also arrived in that language

---

## ⏱ PHASE 5 — Coop polish (optional, do if time permits)

These are the medium-priority items from the audit:

1. **Idempotent checkout** — Switch coop.html to call the new `place_coop_order(...)` RPC instead of plain insert. This prevents duplicate orders + atomically decrements stock. SQL is in `02_lang_and_stock.sql`.

2. **Seller email verification** — In Supabase Auth settings, enable "Confirm email" for signup. This blocks fake sellers from listing without confirming a real email.

3. **Rate limiting on submissions** — Add a Postgres trigger that counts recent cases by phone+IP. Beyond launch scope but easy to add later.

---

## 🎯 GO/NO-GO CHECKLIST (Day of launch)

You can launch when ALL of these are true:

- [ ] `01_rls_and_roles.sql` ran successfully and the audit query shows RLS on for every table
- [ ] Your `imadaehn@gmail.com` has role `mayor` in `user_roles`
- [ ] `02_lang_and_stock.sql` ran and `lang` columns exist on `cases`, `push_subscriptions`, `coop_orders`
- [ ] `notify-i18n` edge function deployed, webhook points to it
- [ ] `send-push-i18n` edge function deployed
- [ ] All 9 files pushed to GitHub (i18n.js, pwa.js, 7 HTML pages)
- [ ] Test A1, A2, A3, A5 all pass (security)
- [ ] Test B (multilingual email) passes for AR, EN, FR
- [ ] Test C (multilingual push) passes for AR, EN, FR
- [ ] Test D (real-device push) passes on at least iPhone + Android
- [ ] Test E (coop checkout) passes

If any item is unchecked, **do not launch** — fix that item first.

---

## 📞 IF SOMETHING BREAKS DURING LAUNCH

**Email not sending:**
- Check Edge Function logs in Supabase Dashboard → Functions → notify-i18n → Logs
- Check that `BREVO_API_KEY` is set in secrets
- Check Brevo dashboard for delivery status / domain authentication

**Push not arriving:**
- Check `push_subscriptions` table — does the row exist? `is_active=true`?
- Check Edge Function logs for `send-push-i18n`
- On iOS: the app must be installed via "Add to Home Screen", NOT just bookmarked
- On Android: notification permission must be granted in OS settings, not just browser

**Admin login broken:**
- Verify user exists in `auth.users`
- Verify they have a row in `user_roles` with role `mayor` or `admin`
- Verify RLS policy `roles_self_select` exists on `user_roles`

**Language not switching:**
- Hard refresh — old `i18n.js` may be cached
- Check that `i18n.js` is loaded (DevTools → Network)
- Check browser console for errors

**Rollback:**
If everything breaks, the SQL files have DOWN scripts at the bottom. Run them and revert the frontend by checking out the previous git commit.

---

Good luck with the launch! 🌐🚀
