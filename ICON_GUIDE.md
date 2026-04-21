# 🎨 Icon Generation Guide — دليل إنشاء الأيقونات

## What you need

You need to create **8 PNG icons** in different sizes and put them in an `icons/` folder at the root of your repo.

```
📦 your-repo/
├── index.html
├── manifest.json
├── sw.js
└── 📁 icons/                  ← Create this folder!
    ├── icon-72.png
    ├── icon-96.png
    ├── icon-128.png
    ├── icon-144.png
    ├── icon-152.png
    ├── icon-192.png
    ├── icon-384.png
    └── icon-512.png
```

---

## 🚀 FASTEST Method — Free online generator (5 minutes)

### Option 1 — PWA Builder Icon Maker ⭐ RECOMMENDED
1. Go to: **https://www.pwabuilder.com/imageGenerator**
2. Upload your municipality logo (at least 512x512 px, PNG with transparent background ideal)
3. Set:
   - **Padding:** 0% (or 10% for safer look)
   - **Background color:** `#1a6eb5` (your blue) OR transparent
4. Click **"Download"**
5. Extract the ZIP → you get ALL sizes at once!
6. Rename if needed to match: `icon-72.png`, `icon-96.png`, etc.

### Option 2 — RealFaviconGenerator
1. Go to: **https://realfavicongenerator.net/**
2. Upload your logo
3. Customize for Android/iOS
4. Download package

### Option 3 — Favicon.io (simple)
1. Go to: **https://favicon.io/favicon-converter/**
2. Upload your image
3. Download

---

## 🎨 Don't have a logo? Quick options:

### A) Create one with text (FREE, 2 min)
Use https://www.favicon.io/favicon-generator/ 
- Text: **و.س** (short for وادي الست)
- Background: `#1a6eb5` (blue)
- Font color: white
- Shape: rounded or circle
- Generate & download

### B) Use a free icon + text
1. Find a government/city icon on: https://www.flaticon.com/
2. Add "بلدية وادي الست" text using Canva or similar
3. Feed to PWA Builder generator above

---

## 📐 Icon Design Tips

✅ **DO:**
- Use a **square** image (1:1 ratio)
- Start at **512x512 or 1024x1024 px**
- Keep design **simple and readable at small sizes**
- Use **high contrast** (easy to see)
- Include **some padding** around the edges (icons get clipped on Android)

❌ **DON'T:**
- Use thin text (won't read at 72px)
- Use complex illustrations
- Leave edges too close to the border (they get clipped)
- Use low-resolution source images

---

## 📤 How to upload icons to GitHub

1. On your new repo → **"Add file"** → **"Upload files"**
2. Create a folder first by typing in the filename box: `icons/icon-72.png`
3. Then drag all 8 PNG files in
4. OR simpler: drag the entire `icons` folder from your computer
5. Commit message: `"Add PWA icons"` → **Commit**

---

## ✅ Verify after upload

Your repo should have:
```
📦 your-repo/
├── index.html
├── manifest.json
├── sw.js
├── 📁 icons/
│   ├── icon-72.png
│   ├── icon-96.png
│   ├── ... (8 total)
├── 📁 water/
└── 📁 coop/
```

---

**Once icons are uploaded, the PWA is fully functional!** 🎉
