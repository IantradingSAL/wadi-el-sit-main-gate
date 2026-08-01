# Apple App Store Checklist — Wadi El Sit

The Apple-specific version of `../playstore/00_PUBLISH_CHECKLIST.md`.
Do both if you're launching on both stores.

---

## Phase 1 — Prerequisites (do NOW, before enrolling)

- [ ] Confirm the app is live at `https://iantradingsal.github.io/wadi-el-sit-main-gate/`
- [ ] Confirm `manifest.json`, `sw.js`, `pwa.js`, `pwa-ios.js` load without errors (DevTools → Network)
- [ ] Privacy policy live at `https://iantradingsal.github.io/wadi-el-sit-main-gate/privacy.html`
- [ ] Store listing copy in `store-assets/store-listings.md` (already done — reused for App Store)
- [ ] iOS icons in `ios-assets/icons/` (already generated)
- [ ] iOS splash screens in `ios-assets/splash/` (already generated)
- [ ] Mayor authorization letter signed + scanned as PDF (only if App Review challenges the government claim)
- [ ] 2 reviewer test accounts in Supabase Auth (same as Play — see `../playstore/05_CONTENT_RATING_AND_DATA_SAFETY.md` §D)

## Phase 2 — Enroll in Apple Developer Program (~$99, ~24-48h approval)

- [ ] Go to <https://developer.apple.com/programs/enroll/>
- [ ] Choose **Individual** enrollment (simpler, faster) OR **Organization** (requires D-U-N-S number, more paperwork, appears as company name in the Store)
- [ ] Pay $99 USD (annual, non-refundable)
- [ ] Complete identity verification (passport / driver's license)
- [ ] Wait for approval email (usually 24-48h; can take up to 7 days)

Once approved, sign in at <https://appstoreconnect.apple.com>.

## Phase 3 — App Store Connect setup (30 min)

- [ ] App Store Connect → **My Apps** → **+** → **New App**
  - Platform: **iOS**
  - Name: `بلدية وادي الست`
  - Primary language: `Arabic`
  - Bundle ID: **create new** → `lb.wadielset.gate` (must match packaging step)
  - SKU: `wadi-el-sit-gate` (internal, any string)
  - User Access: Full Access
- [ ] Fill in **App Information** — from `01_LISTING.md`
- [ ] Fill in **Pricing and Availability** — Free, all countries
- [ ] Fill in **App Privacy** — from `03_APP_PRIVACY_AND_REVIEW.md` §A
- [ ] Complete **Age Rating** questionnaire — from `03_APP_PRIVACY_AND_REVIEW.md` §B
- [ ] Add **Localizations** — English, French — from `01_LISTING.md`
- [ ] Fill in **App Review Information** — from `03_APP_PRIVACY_AND_REVIEW.md` §C

## Phase 4 — Build the .ipa file

Pick a path from `02_IOS_BUILD.md`:

### A — PWABuilder + Codemagic (no Mac needed)
- [ ] <https://www.pwabuilder.com> → paste live URL → Package → iOS → download Xcode project ZIP
- [ ] Push the Xcode project to a new GitHub repo
- [ ] Sign up at <https://codemagic.io> → import that repo
- [ ] Add Apple credentials (Team ID + app-specific password)
- [ ] Trigger build → Codemagic uploads to App Store Connect

### B — PWABuilder + Local Mac
- [ ] Extract Xcode project
- [ ] Open in Xcode → sign in with your Apple ID → select Team
- [ ] Product → Archive → Distribute App → App Store Connect → Upload

### C — Capacitor + Local Mac
- [ ] Follow steps in `02_IOS_BUILD.md` Path B
- [ ] `npx cap open ios` → Archive → Distribute in Xcode

## Phase 5 — TestFlight (Apple's equivalent of Play closed testing)

- [ ] App Store Connect → **TestFlight** tab → wait for the build to process (~15 min)
- [ ] Add yourself as an **Internal Tester** (no review needed) → install from TestFlight iOS app
- [ ] Smoke test on real iPhone + iPad:
  - Launch, splash screen appears
  - Login works
  - Push notifications work (iOS 16.4+)
  - Share target works
  - Language toggle works AR/EN/FR
  - Coop checkout works
- [ ] Fix anything broken → rebuild → re-upload
- [ ] Optional: invite **External Testers** (up to 10,000; requires Apple's beta review — 24h)

## Phase 6 — Submit for App Review

- [ ] App Store Connect → **1.0 Prepare for Submission** → confirm all green
- [ ] Choose "Automatically release this version" (recommended for first launch)
- [ ] Attach the build you tested in TestFlight
- [ ] **Submit for Review**
- [ ] Review typically takes **24-72h** (much faster than Google's first-app review)

## Phase 7 — Post-approval

- [ ] Confirm live: `https://apps.apple.com/app/idXXXXXXX` (the URL appears in App Store Connect)
- [ ] Share the link — municipality Facebook, WhatsApp, printed QR code at the town hall
- [ ] Set up **App Analytics** in App Store Connect → optional but useful
- [ ] Annual reminder: renew Apple Developer Program (~30 days before expiry — App Store Connect emails you)

---

## Common rejection reasons (and how to fix)

| Rejection | Fix |
|---|---|
| **Guideline 4.2** "Minimum functionality — repackaged website" | Reply pointing out: push, share_target, offline, login. Attach mayor letter as gov proof. Usually resolved in 1 round. |
| **Guideline 5.1.1(v)** "Data collection without justification" | Update App Privacy → mark all data as "App Functionality" purpose (not "Analytics") |
| **Guideline 2.1** "App crashes at launch" | Test on TestFlight first — reproduce, fix, re-upload |
| **Guideline 2.3.7** "Metadata references other platforms" | Search description for "Android" or "Google Play" — remove any mention |
| **Guideline 4.0** "Design — placeholder content" | Take fresh screenshots with real data, not empty forms |
| **Missing IPv6 support** | GitHub Pages already serves IPv6 — never an issue for TWA-style apps |
| **"App must be more than a web view"** | Same as 4.2 above — reply, don't refactor |

---

## What Google needs that Apple doesn't

- 14-day closed testing window (Apple has no equivalent — TestFlight is optional)
- Feature graphic 1024×500 (Apple uses screenshots as the visual)
- Data Safety separate form (Apple's App Privacy covers same ground)
- Government-app proof letter mandatory (Apple only asks if challenged)

## What Apple needs that Google doesn't

- Yearly $99 renewal
- Screenshots for TWO device sizes minimum (Google accepts one)
- App-specific password for Xcode uploads
- Encryption exemption declaration in Info.plist
- Reviewer notes text (Google accepts sparse notes)

---

Once both stores approve, you'll have:
- `https://play.google.com/store/apps/details?id=lb.wadielset.gate`
- `https://apps.apple.com/app/idXXXXXXX`

QR code them side-by-side on a printed flyer for the town hall wall.
