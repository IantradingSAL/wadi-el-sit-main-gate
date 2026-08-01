# Building the iOS App — Wadi El Sit

Two viable paths for turning this PWA into an iOS `.ipa` file. Pick one.

## ⚠️ Read this first — App Store Guideline 4.2 risk

Apple's **App Review Guideline 4.2** rejects apps that are "just a repackaged website" with no native value. For a PWA-wrapper, they look for:

1. Substantial in-app functionality beyond just displaying pages
2. Native platform integrations (push, share, files, background)
3. Reason the user needs the app instead of the mobile website

**Wadi El Sit strengths that pass 4.2:**
- ✅ Web Push notifications (iOS 16.4+) — municipal alerts
- ✅ PWA share_target (users share into the citizen form from other apps)
- ✅ Offline mode via service worker
- ✅ Login-gated admin panels
- ✅ Government/official app status (Apple has a soft-approval bias for municipal apps)
- ✅ Coop store with orders (transactional)
- ✅ File attachment on citizen cases
- ✅ Custom government domain — served from `app.municipality-wadi-el-sitt.org`, subdomain of the mayor's official `.org` (matches the email `management@municipality-wadi-el-sitt.org`)

**What to add if Apple rejects on 4.2:**
- Attach the mayor authorization letter (proof this is the official app of a real government body)
- Point out push, share_target, offline, and login as native-only features
- Mention the app is used daily by staff for municipal services

Most municipality PWA wrappers pass. Have the appeal text ready in case.

---

## Path A — PWABuilder iOS (recommended, no Mac needed)

PWABuilder generates a Swift/Xcode project **and** offers a Cloud Build service that produces the signed `.ipa` for you.

### Prerequisites
- Apple Developer Program account ($99/year) — https://developer.apple.com/programs/enroll/
- Your Team ID (from developer.apple.com → Membership)
- Your Bundle Identifier — recommended: `lb.wadielset.gate` (must match your Google Play package name for consistency; NOT required by Apple)

### Steps
1. Go to <https://www.pwabuilder.com>.
2. Paste `https://app.municipality-wadi-el-sitt.org/` → **Start**.
3. Click **Package for Stores** → **iOS**.
4. Fill in:
   - **App name:** `بلدية وادي الست`
   - **Bundle ID:** `lb.wadielset.gate`
   - **URL:** `https://app.municipality-wadi-el-sitt.org/`
   - **Image URL for splash icon:** `https://app.municipality-wadi-el-sitt.org/icons/icon-512.png`
   - **Status bar color:** `#1a6eb5`
   - **Splash color:** `#f5f7fa`
5. Download the ZIP → contains a full Xcode project.
6. Two sub-paths from here:

#### A1 — You have a Mac
```bash
open Wadi\ El\ Sit.xcodeproj
# In Xcode: sign in with your Apple ID, select your Team,
# Product → Archive → Distribute App → App Store Connect → Upload
```

#### A2 — You don't have a Mac
Use **Codemagic** or **Bitrise** (free tier is enough for a small app):
1. Push the extracted Xcode project to a GitHub repo (e.g. a new repo `wadi-el-sit-ios`).
2. Sign up at <https://codemagic.io>.
3. New project → import the GitHub repo.
4. Add your Apple Developer credentials (Team ID + App-specific password from appleid.apple.com).
5. Trigger build → Codemagic archives + uploads to App Store Connect.

---

## Path B — Capacitor (more native features, needs more work)

Better if you plan to add native features later (barcode scanning, biometric auth, background sync).

### Steps
```bash
# 1. Install
npm i -g @capacitor/cli
npm init -y
npm i @capacitor/core @capacitor/ios

# 2. Init (from a fresh working folder, NOT this repo)
npx cap init "Wadi El Sit" lb.wadielset.gate --web-dir=./

# 3. Point webDir at your live site
# In capacitor.config.json:
{
  "appId": "lb.wadielset.gate",
  "appName": "بلدية وادي الست",
  "server": {
    "url": "https://app.municipality-wadi-el-sitt.org/",
    "cleartext": false
  }
}

# 4. Add iOS platform
npx cap add ios

# 5. Copy icons + splash from ios-assets/ into ios/App/App/Assets.xcassets/
#    See ios-assets/README.md for the exact xcassets structure

# 6. Open Xcode + submit (requires Mac + Xcode)
npx cap open ios
```

Capacitor still needs a Mac + Xcode to build and submit (no Codemagic short-cut like PWABuilder). Skip B unless you already have those.

---

## iOS-specific meta tags — enhance PWA launch (optional but recommended)

Your `index.html` already has the essentials (`apple-mobile-web-app-capable`, `apple-touch-icon`, etc.). To get proper splash screens when users **Add to Home Screen** on Safari, append these link tags before `</head>`:

```html
<!-- iOS splash screens — put in <head> AFTER the manifest link -->
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-15-Pro-Max-1290x2796.png"
      media="(device-width: 430px) and (device-height: 932px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-15-Pro-1179x2556.png"
      media="(device-width: 393px) and (device-height: 852px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-14-Plus-1284x2778.png"
      media="(device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-14-1170x2532.png"
      media="(device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-13-mini-1125x2436.png"
      media="(device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-11-828x1792.png"
      media="(device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPhone-8-750x1334.png"
      media="(device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPad-Pro-12.9-2048x2732.png"
      media="(device-width: 1024px) and (device-height: 1366px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPad-Pro-11-1668x2388.png"
      media="(device-width: 834px) and (device-height: 1194px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPad-Air-10.9-1640x2360.png"
      media="(device-width: 820px) and (device-height: 1180px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
<link rel="apple-touch-startup-image" href="ios-assets/splash/splash-iPad-9.7-1536x2048.png"
      media="(device-width: 768px) and (device-height: 1024px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)">
```

You can add these to just `index.html` (users install from the home page) or share via `pwa.js` for every page. Skipping them is fine — iOS just shows a generic white launch screen.

Also worth upgrading your existing `apple-touch-icon` link to 180×180 (Apple's current preferred size):
```html
<link rel="apple-touch-icon" sizes="180x180" href="ios-assets/icons/AppIcon-60@3x-180.png">
```

---

## What Apple asks that Google doesn't

1. **Screenshots for TWO device sizes minimum** (iPhone 6.9" AND 6.5" — not just one)
2. **App Preview videos** are optional but boost conversion — skip for v1
3. **Annual renewal** — the $99/year lapses if not renewed → app is pulled from the Store
4. **App-specific password** for Xcode uploads (from appleid.apple.com → Security)
5. **Encryption declaration** every year (marked exempt via `ITSAppUsesNonExemptEncryption: false` in Info.plist — see listing doc)

---

## Version numbers

| Field | Value | Notes |
|---|---|---|
| `CFBundleShortVersionString` | `1.0.0` | User-facing marketing version |
| `CFBundleVersion` | integer, +1 each upload | Apple REJECTS duplicates |

Set both in `Info.plist` inside the Xcode project.

---

## Signing certificate — READ THIS

Apple's Xcode Cloud / Codemagic pipelines handle the certificate for you. If you're managing manually:
- Keep a backup of your **App Store Distribution certificate** (`.p12` + password) in a password manager.
- Losing it doesn't lock you out (Apple lets you revoke and re-issue), but it interrupts uploads.
- Your **Apple Developer Team ID** is permanent — write it down when you enroll.
