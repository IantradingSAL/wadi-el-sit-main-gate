# Screenshots Guide — Wadi El Sit

Google Play requires **2–8 phone screenshots** per language.
**Recommended: 1080×1920 (portrait 9:16), PNG.**

You can (and should) upload one set per language (AR, EN, FR) so users see the app in their own tongue.

## Take these 6 shots — per language

Capture from a real Android phone OR Chrome DevTools mobile emulator (Pixel 6/7 works well).

| # | Page (from live site) | What to show | Filename |
|---|---|---|---|
| 1 | `/wadi-el-sit-main-gate/` | Home portal with all the module tiles | `01-home.png` |
| 2 | `/wadi-el-sit-main-gate/phonebook.html` | Yellow Pages directory with a few names visible | `02-phonebook.png` |
| 3 | `/wadi-el-sit-main-gate/coop.html` | Coop store with 3-4 products | `03-coop.png` |
| 4 | `/wadi-el-sit-main-gate/water.html` | Irrigation schedule / water page | `04-water.png` |
| 5 | `/wadi-el-sit-main-gate/news.html` | News feed with 2-3 items | `05-news.png` |
| 6 | `/wadi-el-sit-main-gate/citizen.html` | Citizen request form | `06-citizen.png` |

Save each into `playstore/screenshots/<lang>/` — for example:
```
playstore/screenshots/ar/01-home.png
playstore/screenshots/en/01-home.png
playstore/screenshots/fr/01-home.png
```

The `screenshots/` folder is already created for you.

## How to capture from Chrome DevTools (fastest, no phone needed)

1. Open `https://iantradingsal.github.io/wadi-el-sit-main-gate/` in Chrome.
2. Press `F12` → click the phone icon (top-left of DevTools).
3. Choose **"Pixel 7"** (1080×2400) or set custom **1080 × 1920**.
4. Use the AR/EN/FR toggle at the top of the app to set the language you're capturing.
5. Navigate to each page → `⌘/Ctrl + Shift + P` → type **"Capture full size screenshot"** → Enter.
6. Rename each PNG per the table above.
7. Repeat for the other two languages.

## Framing tips

- Show **realistic (or real anonymized) data** — Google rejects empty templates.
- Do NOT show real personal info (real phone numbers, real names, real addresses) unless the person consented.
- Use the same test dataset across all three languages for consistency.
- Don't overlay marketing frames or text — Google's automated review sometimes flags these.
- Include the top status bar area (Android renders one there anyway in the TWA).

## What Play Console does with these

- Play Console → Store listing per language → Screenshots → drag in the 6 files for that language.
- You can add up to 8; 6 is a good sweet spot.
- First screenshot appears as the "hero" in search results — make it the strongest one (probably `01-home.png`).

## Optional: tablet screenshots

Play Console has separate slots for 7" and 10" tablets. **OPTIONAL** — skip for day 1, add post-launch without needing a new release.
