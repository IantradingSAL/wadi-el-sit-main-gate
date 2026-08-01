# iOS Assets — Wadi El Sit

Generated from `store-assets/logo-source.png` — the real municipality logo.

## Layout

```
ios-assets/
  ├── icons/
  │   ├── AppIcon-1024-1024.png     ← App Store marketing icon (required)
  │   ├── AppIcon-60@3x-180.png     ← iPhone home screen (@3x)
  │   ├── AppIcon-60@2x-120.png     ← iPhone home screen (@2x)
  │   ├── AppIcon-83.5@2x-167.png   ← iPad Pro home screen (@2x)
  │   ├── AppIcon-76@2x-152.png     ← iPad home screen (@2x)
  │   ├── AppIcon-76-76.png         ← iPad home screen (@1x)
  │   ├── AppIcon-40@3x-120.png     ← iPhone Spotlight (@3x)
  │   ├── AppIcon-40@2x-80.png      ← iPad Spotlight (@2x)
  │   ├── AppIcon-40-40.png         ← Spotlight / iPad Notifications
  │   ├── AppIcon-29@3x-87.png      ← iPhone Settings (@3x)
  │   ├── AppIcon-29@2x-58.png      ← Settings (@2x)
  │   ├── AppIcon-29-29.png         ← Settings (@1x)
  │   ├── AppIcon-20@3x-60.png      ← iPhone Notifications (@3x)
  │   ├── AppIcon-20@2x-40.png      ← iPhone Notifications (@2x)
  │   └── AppIcon-20-20.png         ← Notifications (@1x)
  └── splash/
      ├── splash-iPhone-15-Pro-Max-1290x2796.png     (+ landscape variant)
      ├── splash-iPhone-15-Pro-1179x2556.png         (+ landscape)
      ├── splash-iPhone-14-Plus-1284x2778.png        (+ landscape)
      ├── splash-iPhone-14-1170x2532.png             (+ landscape)
      ├── splash-iPhone-13-mini-1125x2436.png        (+ landscape)
      ├── splash-iPhone-11-828x1792.png              (+ landscape)
      ├── splash-iPhone-8-750x1334.png               (+ landscape)
      ├── splash-iPad-Pro-12.9-2048x2732.png         (+ landscape)
      ├── splash-iPad-Pro-11-1668x2388.png           (+ landscape)
      ├── splash-iPad-Air-10.9-1640x2360.png         (+ landscape)
      └── splash-iPad-9.7-1536x2048.png              (+ landscape)
```

## How iOS uses these

- **App icons** — Copied into your Xcode project's `Assets.xcassets/AppIcon.appiconset/`. PWABuilder does this automatically when packaging. Capacitor: run `npx capacitor-assets generate --ios --iconPath ios-assets/icons/AppIcon-1024-1024.png`.
- **Splash screens** — Referenced by `pwa-ios.js` via `<link rel="apple-touch-startup-image">` when a user adds the site to their iPhone/iPad home screen from Safari. Also used inside the Xcode project as launch images.

## When to regenerate

If the source logo changes, regenerate everything:
1. Replace `store-assets/logo-source.png` with the new hi-res logo
2. Re-run the generator scripts (kept in `scratchpad/` locally, not in repo)
3. Repackage the .ipa with the new icons

## Design specs used

- **Icons:** full-bleed white background, emblem (trees + sun + wadi curves) centered with 8% padding. iOS applies its own corner mask.
- **Splash:** full logo (Arabic title + emblem) centered on cream background `#f5f7fa` (matches manifest `background_color`).
- **Maskable icon** (Android-only, in `../icons/icon-maskable-512.png`): emblem on brand blue `#1a6eb5` with 60% safe zone.
