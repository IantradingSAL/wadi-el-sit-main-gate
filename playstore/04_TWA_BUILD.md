# Building the Android App (.aab) — Wadi El Sit

This turns the Wadi El Sit web app into a signed `.aab` file you upload to Play Console.

## 🚨 Read this FIRST — assetlinks placement (subpath vs. custom domain)

The Wadi app lives at `https://iantradingsal.github.io/wadi-el-sit-main-gate/` — a **subpath** under a GitHub-owned host. This affects how Android verifies the app links.

Android reads `assetlinks.json` **only from the origin root**, i.e.:
```
https://iantradingsal.github.io/.well-known/assetlinks.json
```
It does **NOT** read it from `.../wadi-el-sit-main-gate/.well-known/assetlinks.json`.

You have two options — pick one before you build.

### Option A — Publish `assetlinks.json` at the origin root (fastest, free)

You need to serve `assetlinks.json` from `https://iantradingsal.github.io/.well-known/assetlinks.json`.

Because GitHub Pages serves that URL from the `iantradingsal.github.io` **repository** (not this one), you must:

1. Create a repo called **`iantradingsal.github.io`** if it doesn't exist (or open it if it does).
2. Add the file at path `.well-known/assetlinks.json` with the same content as `/.well-known/assetlinks.json` in this repo.
3. Commit and push — GitHub Pages will serve it at the correct URL automatically.
4. Verify: `curl -sI https://iantradingsal.github.io/.well-known/assetlinks.json` → 200

**Downside:** the TWA verifies the whole `iantradingsal.github.io` origin, so any OTHER project you host at `iantradingsal.github.io/*` is also delegated to the app. Fine for a personal account.

### Option B — Use a custom domain (recommended for a real launch, ~$10-15/yr)

1. Buy `wadielset.lb` or `wadielset.com` (or similar).
2. Point it to GitHub Pages: repo Settings → Pages → Custom domain.
3. Move the site so it serves at `https://wadielset.lb/` (root, not a subpath).
4. `assetlinks.json` then lives at `https://wadielset.lb/.well-known/assetlinks.json` — cleaner, exclusive to this app.

Also update:
- `twa-manifest.json` → `"host": "wadielset.lb"`, `"startUrl": "/"`, all icon URLs
- `manifest.json` → `"scope": "/"`, `"start_url": "/"`, `scope_extensions` entries

**Recommendation:** Go with **Option A** now to publish quickly; migrate to Option B later once the app is live.

---

## Prerequisites (both paths)

1. Your web app is deployed and reachable at `https://iantradingsal.github.io/wadi-el-sit-main-gate/`  ✅ (already done)
2. `manifest.json`, `sw.js`, `icons/*` are served — ✅ (already in repo root)
3. You have chosen a **package name**. Recommended: `lb.wadielset.gate` — permanent once uploaded.

---

## Path 1 — PWABuilder (browser only, ~10 min)

1. Go to <https://www.pwabuilder.com>.
2. Paste: `https://iantradingsal.github.io/wadi-el-sit-main-gate/` → **Start**.
3. Fix any red items in the PWA report (should be none — your manifest is already very complete).
4. Click **Package for Stores** → **Android**.
5. Fill in:
   - **Package ID:** `lb.wadielset.gate`
   - **App name:** `بلدية وادي الست`
   - **Launcher name:** `وادي الست`
   - **Signing key:** *"Create new"* — **DOWNLOAD AND KEEP the `.keystore` file forever.**
   - **Host:** `iantradingsal.github.io`
   - **Start URL:** `/wadi-el-sit-main-gate/`
6. Download the ZIP. It contains:
   - `app-release-signed.aab` ← upload this to Play Console
   - `assetlinks.json` ← host per Option A or B above
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
bubblewrap init --manifest=https://iantradingsal.github.io/wadi-el-sit-main-gate/manifest.json
```
When it asks — accept the defaults but confirm:
- Package name: `lb.wadielset.gate`
- App name: `بلدية وادي الست`
- Launcher name: `وادي الست`
- Start URL: `/wadi-el-sit-main-gate/`
- Display mode: `standalone`

### Build
```bash
bubblewrap build
```
Produces `app-release-signed.aab` in the working directory. Also prints the SHA-256 fingerprint you need for `assetlinks.json`.

### Update later (bump version)
```bash
# 1) Edit twa-manifest.json: appVersionCode +1, appVersionName as needed
bubblewrap update
bubblewrap build
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
