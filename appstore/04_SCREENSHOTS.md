# App Store Screenshots Guide — Wadi El Sit

Apple requires screenshots for **at least two iPhone size classes** — the 6.9" and 6.5" slots are both mandatory. iPad screenshots are only required if you support iPad (recommend YES for a municipality app — village elders often use iPads).

Per language (AR/EN/FR), take:

## Required sizes

| Slot | Size (px) | Which device to emulate | # min | # max |
|---|---|---|---|---|
| iPhone 6.9" | **1290 × 2796** | iPhone 15 Pro Max | 3 | 10 |
| iPhone 6.5" | **1284 × 2778** | iPhone 14 Plus | 3 | 10 |
| iPad Pro 12.9" (3rd gen+) | **2048 × 2732** | iPad Pro 12.9" | 3 | 10 |

## Which pages to shoot (same 6 as Play Store)

| # | Page | What to show |
|---|---|---|
| 1 | `/` | Home portal with all module tiles |
| 2 | `phonebook.html` | Yellow Pages directory |
| 3 | `coop.html` | Cooperative store, 3-4 products visible |
| 4 | `water.html` | Irrigation schedule |
| 5 | `news.html` | News feed with 2-3 items |
| 6 | `citizen.html` | Citizen request form |

## Fastest capture workflow — Chrome DevTools

1. Open `https://iantradingsal.github.io/wadi-el-sit-main-gate/` in Chrome
2. Press `F12` → phone icon → **Device toolbar**
3. **Custom device size** → set width × height per the table above (e.g. `1290 × 2796` for the 6.9" slot). Set DPR = 3.
4. Toggle AR/EN/FR at the top of the app to match your capture language
5. Navigate to each page → `⌘/Ctrl + Shift + P` → "Capture full size screenshot" → Enter
6. Save into `appstore/screenshots/<size>/<lang>/` per the layout below
7. Repeat for the other two slots (6.5" and iPad Pro)

## Folder layout to save into

```
appstore/screenshots/
  ├── iphone-6.9/
  │   ├── ar/  (6 PNG files)
  │   ├── en/  (6 PNG files)
  │   └── fr/  (6 PNG files)
  ├── iphone-6.5/
  │   ├── ar/
  │   ├── en/
  │   └── fr/
  └── ipad-12.9/
      ├── ar/
      ├── en/
      └── fr/
```

Total = 54 screenshots if you support iPad, 36 if iPhone-only.

## Rules Apple enforces (2026)

- **No status bar** with wrong time — Apple's automated review flags mismatches. Chrome DevTools captures without the phone status bar which is fine (Apple doesn't require one).
- **No frames or borders** overlaid on the shot — the raw viewport only.
- **No text overlays that look like OS UI** (e.g. fake notification badges) — Apple sees this as deceptive.
- **Real data or realistic mock data** — empty templates get rejected under Guideline 4.0.
- **No mention of "Android" or "Google Play"** anywhere visible in the shot.

## Faster alternative — real device

If you have an iPhone 14 Plus or newer:
1. Open the live site in Safari, "Add to Home Screen", launch the PWA
2. Take screenshots with `Volume Up + Side button`
3. AirDrop to Mac or export via iCloud Photos
4. Sort into the folder layout above

Real-device screenshots often look better than DevTools captures because they include the true safe-area padding and native font rendering.

## Optional — App Previews (video)

15-30s screen recordings. Boost conversion by ~15% but skip for v1 to keep the launch scope small. If you want them later:
- Use QuickTime on Mac → File → New Movie Recording → connect iPhone → record → export
- One per size class per language = 9 videos → a lot of work

## Placement in App Store Connect

App Store Connect → your version → **Screenshots** section per localization:
- Drag the 6 PNGs per slot into the correct box
- The FIRST screenshot becomes the hero card in Search — make it your strongest (usually `01-home.png`)
- Reorder by dragging
