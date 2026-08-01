# Building the Android App (.aab) — Wadi El Sit

This turns the Wadi El Sit web app into a signed `.aab` file you upload to Play Console.

## ✅ Custom domain — already in place

The app now serves at **`https://app.municipality-wadi-el-sitt.org/`** (origin root), so Digital Asset Links "just work":

- `assetlinks.json` is served at `https://app.municipality-wadi-el-sitt.org/.well-known/assetlinks.json`
- `twa-manifest.json` uses `"host": "app.municipality-wadi-el-sitt.org"` and `"startUrl": "/"`
- No subpath hacks needed

See `playstore/06_DOMAIN_SWITCH.md` for the DNS/config history if you need to migrate again later.

The old URL `https://iantradingsal.github.io/wadi-el-sit-main-gate/` 301-redirects to the new domain — old bookmarks stay alive.

---

## Prerequisites

1. Site reachable at `https://app.municipality-wadi-el-sitt.org/` ✅
2. `manifest.json`, `sw.js`, `icons/*` served from origin root ✅
3. Package name chosen: **`lb.wadielset.gate`** (permanent once uploaded)

---

## Path 1 — PWABuilder (browser only, ~10 min)

1. Go to <https://www.pwabuilder.com>.
2. Paste: `https://app.municipality-wadi-el-sitt.org/` → **Start**.
3. Fix any red items in the PWA report (should be none — manifest is already very complete).
4. Click **Package for Stores** → **Android**.
5. Fill in:
   - **Package ID:** `lb.wadielset.gate`
   - **App name:** `بلدية وادي الست`
   - **Launcher name:** `وادي الست`
   - **Signing key:** *"Create new"* — **DOWNLOAD AND KEEP the `.keystore` file forever.**
   - **Host:** `app.municipality-wadi-el-sitt.org`
   - **Start URL:** `/`
6. Download the ZIP. It contains:
   - `app-release-signed.aab` ← upload this to Play Console
   - `assetlinks.json` ← **replace** the placeholder in the repo at `.well-known/assetlinks.json` with this real one (has the correct SHA-256 fingerprint), then push
   - `signing.keystore` ← **BACK THIS UP TO A PASSWORD MANAGER + SECONDARY LOCATION**

---

## Path 2 — Bubblewrap CLI (repeatable, scriptable)

### Install once
```bash
npm i -g @bubblewrap/cli
# Requires Java 17+. macOS: brew install openjdk@17. Ubuntu: sudo apt install openjdk-17-jdk
```

### Initialize
```bash
bubblewrap init --manifest=https://app.municipality-wadi-el-sitt.org/manifest.json
```
When it asks — accept the defaults but confirm:
- Package name: `lb.wadielset.gate`
- App name: `بلدية وادي الست`
- Launcher name: `وادي الست`
- Start URL: `/`
- Display mode: `standalone`

### Build
```bash
bubblewrap build
```
Produces `app-release-signed.aab` in the working directory. **Copy the printed SHA-256 fingerprint** — you paste it into `.well-known/assetlinks.json` (replacing the `REPLACE:WITH:SHA256:...` placeholder), commit, push. GitHub Pages redeploys within 2 minutes and Google's TWA link verifier picks it up on next check.

### Update later (bump version)
```bash
# 1) Edit twa-manifest.json: appVersionCode +1, appVersionName as needed
bubblewrap update
bubblewrap build
```

---

## Update assetlinks.json with the real fingerprint

After your first Bubblewrap or PWABuilder build, replace the placeholder in `.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "lb.wadielset.gate",
      "sha256_cert_fingerprints": ["AA:BB:CC:...:99"]
    }
  }
]
```

Commit + push → GitHub Pages redeploy → Google verifies within minutes.

Verify manually:
```bash
curl -s https://app.municipality-wadi-el-sitt.org/.well-known/assetlinks.json | jq .
```

---

## Version numbers

| Field | Value | Notes |
|---|---|---|
| `versionCode` | integer starting at 1, +1 each upload | Play Console REJECTS duplicates |
| `versionName` | display string, e.g. `1.0.0` | Users see this |

---

## Keystore backup — READ THIS

If you lose the `.keystore` file OR its passwords, **you can never update this app again**. You would have to publish a brand-new app under a new package name.

Save the keystore to:
1. A password manager (1Password / Bitwarden — attach the file).
2. An encrypted cloud drive folder.
3. Optionally, print the passwords on paper.

**Also enable Google Play App Signing on the first upload** — Google holds the signing key, you keep an upload key. If you lose the upload key, Google can reset it for you. Cannot be enabled later without friction.
