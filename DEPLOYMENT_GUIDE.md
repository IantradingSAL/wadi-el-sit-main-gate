# 🚀 PWA Setup — Complete Guide

## 📦 Files you just received

| File | Purpose | Where it goes |
|---|---|---|
| `index.html` | Master landing page (with PWA integration) | **Root** of repo (replace old one) |
| `manifest.json` | PWA app config | **Root** of repo |
| `sw.js` | Service worker (caching + updates) | **Root** of repo |
| `ICON_GUIDE.md` | How to make icons | Keep on your computer |
| `INSTALLATION_GUIDE_AR.md` | Guide for citizens | Share with users (PDF) |

---

## 🎯 Final repo structure (what you're aiming for)

```
📦 your-new-repo/
├── 📄 index.html             ← NEW (updated with PWA)
├── 📄 manifest.json          ← NEW
├── 📄 sw.js                  ← NEW
├── 📄 README.md
├── 📁 icons/                 ← NEW (you create this, 8 PNGs inside)
│   ├── icon-72.png
│   ├── icon-96.png
│   ├── icon-128.png
│   ├── icon-144.png
│   ├── icon-152.png
│   ├── icon-192.png
│   ├── icon-384.png
│   └── icon-512.png
├── 📁 water/
│   └── ... (your water files)
└── 📁 coop/
    └── ... (your coop files)
```

---

## ✅ STEP-BY-STEP deployment

### Step 1️⃣ — Replace the old `index.html`
1. On GitHub → open your repo
2. Click on the existing `index.html` file
3. Click **"Delete this file"** (trash icon) → commit
4. Click **"Add file"** → **"Upload files"** → drag the new `index.html`
5. Commit message: `"PWA-ready index"` → **Commit**

### Step 2️⃣ — Upload `manifest.json` and `sw.js`
1. **"Add file"** → **"Upload files"**
2. Drag both files together
3. Commit message: `"Add PWA config"` → **Commit**

### Step 3️⃣ — Create icons (see `ICON_GUIDE.md`)
1. Generate 8 PNG icons using https://www.pwabuilder.com/imageGenerator
2. Upload them to repo → file name: `icons/icon-72.png` (GitHub auto-creates the folder!)
3. Upload all 8 → commit: `"Add app icons"`

### Step 4️⃣ — Test the PWA 🧪

1. Open your live URL in **Chrome** on desktop: `https://iantradingsal.github.io/your-repo/`
2. Press `F12` to open DevTools
3. Go to **Application** tab → **Manifest** (left sidebar)
4. You should see:
   - ✅ Name: بلدية وادي الست
   - ✅ Theme: #1a6eb5
   - ✅ Icons: all 8 showing
   - ✅ No errors (no red text)
5. Go to **Service Workers** tab
   - ✅ `sw.js` should show "activated and running"

### Step 5️⃣ — Try installing on your phone!

**Android:**
- Open Chrome → your URL → bottom banner "Install app" → Install ✅

**iPhone:**
- Open Safari → your URL → Share button → Add to Home Screen ✅

---

## 🎨 About updates

### ✅ What syncs automatically (no APK rebuild needed):
- HTML, CSS, JS changes
- New pages
- Content updates
- Bug fixes

**When user opens the PWA/APK, they see the latest version within seconds thanks to the smart service worker.**

### ⚠️ What requires APK rebuild:
- Changing app icon
- Changing app name
- Changing theme color
- Changing app permissions

These are very rare once the app is stable.

---

## 🛠️ Troubleshooting

### Problem: "Install app" button doesn't appear
**Cause:** Missing icons or manifest error
**Fix:** Check DevTools → Application → Manifest for errors

### Problem: Old content showing after update
**Cause:** Service worker caching
**Fix:** Tell users to close/reopen app. Or bump `CACHE_NAME` in `sw.js` to force update.

### Problem: Icons not showing
**Cause:** Wrong filename or folder
**Fix:** Ensure folder is `icons/` (lowercase, s at end) and filenames match exactly

### Problem: 404 on manifest.json
**Cause:** File in wrong location
**Fix:** Must be at REPO ROOT, not inside a folder

---

## 📦 Generate APK (after PWA works)

### PWABuilder (easiest, free, no code)

1. Go to: **https://www.pwabuilder.com/**
2. Paste your GitHub Pages URL
3. Click **Start**
4. Review the scores (should see green ✅)
5. Click **Package For Stores** → **Android**
6. Configure:
   - **Package ID:** `com.baladiye.wadi.elsit`
   - **App name:** بلدية وادي الست
   - **Signing:** Let PWABuilder generate (save the key!)
7. Click **Generate Package**
8. Download the ZIP → extract → find the `.apk` file
9. ✅ Share the APK via WhatsApp, website, etc.

### Testing the APK

1. Transfer APK to an Android phone
2. Enable "Install from unknown sources" in Android settings
3. Tap the APK file → Install
4. Open the app → should look identical to your website, but native-style!

---

## 🎉 You're done!

After all these steps:
- ✅ Website is PWA-enabled
- ✅ Users can install on iPhone (via Safari)
- ✅ Users can install on Android (via Chrome)
- ✅ APK can be distributed for direct install
- ✅ Updates sync automatically

---

**Any issues — come back to me with:**
- What step you're on
- What error/problem you see
- Screenshot if possible

🚀 Good luck!
