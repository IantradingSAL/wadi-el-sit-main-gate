# Play Store Publish-Day Checklist — Wadi El Sit

Once Google approves your developer identity (email from `googleplay-noreply@google.com`),
work through this list top-to-bottom. Total time: **~2 hours** if all prerequisites are ready.

> **Note:** This is the **Play Store submission** checklist. Separate from the app's own
> `LAUNCH_CHECKLIST.md` in the repo root, which covers database and function launch.

---

## Phase 1 — Prerequisites (do this NOW, while Google verifies you)

- [x] Web app live at `https://iantradingsal.github.io/wadi-el-sit-main-gate/`
- [x] `manifest.json`, `sw.js`, `icons/*` all served
- [x] Privacy policy at `https://iantradingsal.github.io/wadi-el-sit-main-gate/privacy.html`
- [x] Store listing copy (AR/EN/FR) in `store-assets/store-listings.md`
- [x] Feature graphic in `store-assets/feature-graphic-1024x500.png`
- [x] Mayor authorization letter template in `store-assets/mayor-authorization-letter.md`
- [ ] **Mayor's signed authorization letter as PDF** — print, sign, scan (needed for Government-app policy)
- [ ] **6 phone screenshots × 3 languages** (18 files total) in `playstore/screenshots/<lang>/`
- [ ] **2 test accounts** created in Supabase Auth (citizen + admin) — see `05_CONTENT_RATING_AND_DATA_SAFETY.md` §D
- [ ] **Decide the `assetlinks.json` hosting** — Option A (root of iantradingsal.github.io) or Option B (custom domain). See `04_TWA_BUILD.md`.

---

## Phase 2 — After Google approves your ID (email received)

### 2.1 Complete phone verification
- [ ] Play Console → **Setup** → **Verify your contact phone number** → SMS code

### 2.2 Finalise developer profile
- [ ] Play Console → **Setup** → **Developer profile** → confirm displayed name, contact address
- [ ] Play Console → **Setup** → **Payments profile** → complete tax info (needed even for free apps)

---

## Phase 3 — Build the .aab file

Choose ONE path from `04_TWA_BUILD.md`:

### If using PWABuilder (browser)
- [ ] Go to <https://www.pwabuilder.com>
- [ ] URL: `https://iantradingsal.github.io/wadi-el-sit-main-gate/` → Package for Android
- [ ] Package ID: `lb.wadielset.gate`
- [ ] Download ZIP → **BACK UP** `signing.keystore` + `signing-key-info.txt`
- [ ] Copy the SHA-256 fingerprint

### If using Bubblewrap CLI
- [ ] `npm i -g @bubblewrap/cli`
- [ ] `bubblewrap init --manifest=https://iantradingsal.github.io/wadi-el-sit-main-gate/manifest.json`
- [ ] `bubblewrap build` → produces `app-release-signed.aab`
- [ ] **BACK UP** `android.keystore` + passwords

## Phase 4 — Deploy Digital Asset Links (removes Chrome URL bar)

Per Option A OR Option B in `04_TWA_BUILD.md`. Whichever you pick:

- [ ] Paste your actual SHA-256 fingerprint into the `assetlinks.json` file
- [ ] Deploy so `https://iantradingsal.github.io/.well-known/assetlinks.json` returns 200 (Option A) OR `https://YOUR-CUSTOM-DOMAIN/.well-known/assetlinks.json` (Option B)
- [ ] Verify: `curl -sI https://.../.well-known/assetlinks.json`
- [ ] Verify with Google's tool: <https://developers.google.com/digital-asset-links/tools/generator>

---

## Phase 5 — Play Console: create the app

- [ ] Play Console → **Create app**
  - App name: `بلدية وادي الست`
  - Default language: `Arabic` (add English + French later)
  - App or game: **App**
  - Free or paid: **Free**
  - Accept declarations → **Create app**

## Phase 6 — Fill in Store listing (~45 min for 3 languages)

Use `store-assets/store-listings.md`:

- [ ] **Main store listing (Arabic default)** — paste AR strings
- [ ] Upload **App icon** = `icons/icon-512.png`
- [ ] Upload **Feature graphic** = `store-assets/feature-graphic-1024x500.png`
- [ ] Upload **Phone screenshots** = 6 files from `playstore/screenshots/ar/`
- [ ] **Add translation → English** → paste EN strings + 6 English screenshots
- [ ] **Add translation → French** → paste FR strings + 6 French screenshots

## Phase 7 — Fill in App content (~30 min)

Use answers from `05_CONTENT_RATING_AND_DATA_SAFETY.md`:

- [ ] **Privacy policy** → paste URL
- [ ] **App access** → provide the two reviewer accounts + walkthrough note
- [ ] **Ads** → No
- [ ] **Content rating** → complete IARC questionnaire (manifest already has an ID — you can reuse)
- [ ] **Target audience** → 13+
- [ ] **News app** → **Yes** (news module) → complete news publisher declaration
- [ ] **Data safety** → fill in per pre-filled answers
- [ ] **Government app** → **Yes** → upload the signed mayor authorization letter (PDF)
- [ ] **Financial features** → No
- [ ] **Health features** → No

## Phase 8 — Choose release track

**Personal accounts are REQUIRED to run closed testing for 14 days before Production.**

- [ ] **Testing → Closed testing → Create new track** ("Alpha")
- [ ] Upload `app-release-signed.aab`
- [ ] Add release notes (see below)
- [ ] Add **12+ testers** — village council members, staff, volunteers (real emails)
- [ ] Send each the opt-in link, ask them to install via Play Store
- [ ] **Wait 14 continuous days** with 12+ testers active
- [ ] After 14 days → Play Console will unlock **Production** track

### Sample release notes (AR / EN / FR — from store-listings.md)
```
🚀 إطلاق التطبيق الرسمي لبلدية وادي الست
🚀 Official launch of the Wadi El Sit Municipality app
🚀 Lancement officiel de l'app de la Municipalité de Wadi El Sit
```

## Phase 9 — Submit for review

- [ ] All left-hand sections in Play Console show a **green checkmark**
- [ ] **Send for review** button becomes active → click it
- [ ] Google review typically takes **1–7 days** for a new developer's first app
- [ ] **Government-app secondary review** may add 3–5 more days

---

## Post-launch

- [ ] Confirm app is live: `https://play.google.com/store/apps/details?id=lb.wadielset.gate`
- [ ] Announce via municipality's channels (Facebook, WhatsApp broadcast, mosque notice)
- [ ] Set up Play Console → **Statistics** → alerts for crashes and 1-star reviews
- [ ] Every time you push to `main`: nothing extra to do — TWA fetches latest automatically
- [ ] Every time you edit `twa-manifest.json` (icon, name, permissions):
  - Bump `appVersionCode` (+1) and `appVersionName`
  - Re-run `bubblewrap build`
  - Play Console → Production → **Create new release** → upload new `.aab`

---

## If something goes wrong

| Symptom | Fix |
|---|---|
| Chrome URL bar visible in the installed app | `assetlinks.json` not reachable at the ORIGIN root, wrong SHA-256, or wrong package_name — re-check per `04_TWA_BUILD.md` |
| Google rejects with "requires proof of government affiliation" | Upload the signed mayor authorization letter (PDF) in App content → Government app |
| Reviewer says "can't log in" | Reviewer credentials wrong or account was deactivated — recreate in Supabase and update in Play Console |
| Privacy policy URL fails validation | Must be HTTPS 200, publicly reachable (no login wall). Current URL should already work — check `privacy.html` is committed and Pages is redeployed |
| "Target API level too low" | Bump `targetSdkVersion` in Bubblewrap (`bubblewrap update` handles this) |
| Play Console rejects the .aab | Read the rejection email carefully — most rejections are about metadata (screenshots, description), not the binary |
