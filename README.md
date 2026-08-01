# بلدية وادي الست · Wadi El Sit Municipality

Official PWA + native-app portal for the Municipality of Wadi El Sit (Chouf, Lebanon).

**🌐 Live app:** https://app.municipality-wadi-el-sitt.org
**📧 Municipality email:** management@municipality-wadi-el-sitt.org
**📞 Phone:** 03/649694
**👤 Mayor:** Jihad Maksoud

Trilingual (Arabic · English · French). Runs as a website, an installable PWA, and (in progress) as a native Android + iOS app.

---

## ✨ What's New — 2026-08-01

Big day. Full store-submission pack landed + the app moved to its permanent home on the official municipality domain.

### 🌐 Custom domain switch (Option 2B)

The app now serves at **`https://app.municipality-wadi-el-sitt.org`** instead of the GitHub Pages URL. The `.org` root still runs a separate WordPress site (untouched); the `app.` subdomain is a CNAME to GitHub Pages.

- ✅ DNS CNAME added at Hostinger — `app` → `iantradingsal.github.io`
- ✅ DNS propagated worldwide (verified via dnschecker.org)
- ✅ `CNAME` file at repo root activates the custom domain
- ✅ Let's Encrypt HTTPS cert provisioned by GitHub
- ✅ **Enforce HTTPS** enabled
- ✅ `manifest.json`, `twa-manifest.json`, `.well-known/assetlinks.json` updated for the new origin root
- ✅ Old `iantradingsal.github.io/wadi-el-sit-main-gate/` URL now 301-redirects to the new domain — no broken bookmarks

### 📦 Play Store submission pack

- New folder: `playstore/` — end-to-end publish-day docs
  - `00_PUBLISH_CHECKLIST.md` — publish-day checklist
  - `03_SCREENSHOTS.md` — capture guide (6 pages × 3 languages)
  - `04_TWA_BUILD.md` — PWABuilder + Bubblewrap paths
  - `05_CONTENT_RATING_AND_DATA_SAFETY.md` — pre-filled questionnaire answers
  - `06_DOMAIN_SWITCH.md` — the domain switch we just completed
- New/updated assets:
  - `store-assets/feature-graphic-1024x500.png` — Google Play required asset
  - `store-assets/logo-source.png` — master logo kept in-repo for future regeneration
  - `store-assets/store-listings.md` — AR/EN/FR listings, publisher URL now on new domain
- `twa-manifest.json` — Bubblewrap config, `packageId: lb.wadielset.gate`, host + startUrl at custom domain root
- `.well-known/assetlinks.json` — now at origin root, ready to receive the SHA-256 fingerprint after first Bubblewrap build

### 🍎 App Store submission pack

- New folder: `appstore/` — mirrors playstore/ for Apple
  - `00_APPSTORE_CHECKLIST.md` — end-to-end checklist including D-U-N-S + Organization enrollment
  - `01_LISTING.md` — App Store Connect fields (subtitle, promotional text, keywords, reviewer notes)
  - `02_IOS_BUILD.md` — PWABuilder iOS + Capacitor paths; Codemagic no-Mac option
  - `03_APP_PRIVACY_AND_REVIEW.md` — App Privacy nutrition label + age rating + reviewer notes
- New: `ios-assets/` — iOS-specific icons (full Apple size set) and splash screens (11 device sizes)
- iOS-specific PWA meta tags added to `index.html` (splash screens, apple-touch-icon 180)

### 🎨 Branding refresh from real logo

- All 10 PWA icons regenerated from `store-assets/logo-source.png`
- Emblem-only crop used for small square icons (Arabic title isn't legible at small sizes)
- Maskable variant on brand-blue `#1a6eb5` background, 60% safe zone (Android adaptive-icon-safe)
- Full logo (text + emblem) used on the Play Store feature graphic
- `apple-touch-icon.png` and `favicon-32.png` regenerated

### 📝 Mayor authorization letter

- Template in `store-assets/mayor-authorization-letter.md` — bilingual Arabic + English
- Signable Word (.docx) version generated separately with:
  - Municipality logo embedded at the top of both pages
  - Date, phone (03/649694), email (management@municipality-wadi-el-sitt.org), mayor name (Jihad Maksoud), app URL — all filled in
  - Covers Apple Developer Program, Google Play Console, and DUNS enrollment in one letter
- Sent to the mayor for signature + municipal seal

### 🔌 Infrastructure

- WordPress site installed and Jetpack-connected on `municipality-wadi-el-sitt.org` (root domain) — separate from the app subdomain
- WordPress.com MCP integration verified

---

## What still needs a human hand

- [ ] **Mayor signs + stamps** the printed authorization letter → scan as one PDF (200 DPI, color)
- [ ] **Apply for D-U-N-S number** — https://developer.apple.com/enroll/duns-lookup/ (2–5 business days for the municipality)
- [ ] **Apple Developer Program enrollment** (Organization) — 1–4 weeks, needs the D-U-N-S + signed letter
- [ ] **Google Play Console** — pay $25 once, wait for account verification
- [ ] **Capture 18 real screenshots** — 6 pages × 3 languages, guides in `playstore/03_SCREENSHOTS.md` and `appstore/04_SCREENSHOTS.md`
- [ ] **First `.aab` build** (PWABuilder or Bubblewrap) → paste real SHA-256 fingerprint into `.well-known/assetlinks.json` → push
- [ ] **First `.ipa` build** (PWABuilder + Codemagic if no Mac) → upload via App Store Connect → TestFlight → submit

---

## Repo layout

```
├── index.html + all page HTML     — the app itself
├── manifest.json + sw.js           — PWA config + service worker
├── CNAME                           — custom-domain configuration for GitHub Pages
├── icons/                          — PWA icons (10 sizes)
├── ios-assets/                     — iOS-specific icons and splash screens
├── store-assets/                   — cross-store: listings, feature graphic, logo source, mayor letter
├── playstore/                      — Google Play submission pack + domain switch guide
├── appstore/                       — Apple App Store submission pack
├── twa-manifest.json               — Bubblewrap TWA build config
├── .well-known/assetlinks.json     — Google Digital Asset Links (TWA verification)
└── privacy.html                    — hosted privacy policy
```

---

## Tech

- **Frontend:** vanilla HTML/JS/CSS, Bootstrap 5, RTL Arabic-first
- **Backend:** Supabase (Postgres + Auth + Edge Functions + Storage)
- **Hosting:** GitHub Pages, served on custom domain via CNAME
- **Email:** Hostinger mail + Brevo (transactional)
- **Push notifications:** Web Push API + Supabase Edge Functions
- **App packaging:** Bubblewrap (Android) + PWABuilder iOS / Capacitor (iOS)

---

_Generated by [Claude Code](https://claude.ai/code)_
