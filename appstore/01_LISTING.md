# App Store Listing — Wadi El Sit (Apple)

Copy each field below into App Store Connect → your app → App Information / Version.
All limits are Apple's official maximums.

Uses the same Arabic / English / French copy as Google Play (in `store-assets/store-listings.md`) with fields adapted to App Store Connect's structure.

---

## App name (max 30 chars, per language)

- **Arabic (default):** `بلدية وادي الست`
- **English:** `Wadi El Sit Municipality`
- **French:** `Municipalité Wadi El Sit`

## Subtitle (max 30 chars, per language — App Store's second-line under the name)

- **Arabic:** `دليل · خدمات · ري · أخبار`
- **English:** `Directory · News · Coop · Water`
- **French:** `Annuaire · Actus · Eau · Coop`

*(App Store's subtitle is 30 chars — Google Play's short description is 80. Keep them separate.)*

## Promotional text (max 170 chars — editable without a new version)

- **Arabic:** `التطبيق الرسمي لبلدية وادي الست — كل خدمات البلدية في مكان واحد: دليل الأهالي، الري، التعاونية، الشكاوى، وأخبار البلدة الفورية.`
- **English:** `The official Wadi El Sit Municipality app — village directory, irrigation, cooperative, citizen requests, and instant municipal news, all in one place.`
- **French:** `L'app officielle de la Municipalité de Wadi El Sit — annuaire, irrigation, coopérative, requêtes citoyennes et actualités instantanées.`

## Description (max 4000 chars — reuse from `store-assets/store-listings.md`)

Copy the AR/EN/FR long descriptions from `store-assets/store-listings.md` **as-is** — they fit App Store's 4000-char limit and the emoji-headed sections read well on iOS.

## Keywords (max 100 chars total, English field, comma-separated, NO SPACES after commas)

```
municipality,wadi,elsit,lebanon,phonebook,yellow,pages,coop,irrigation,news,chouf
```
*(97 chars including commas — under the 100 limit)*

App Store doesn't use a separate keywords field for AR/FR — search there is powered by the localized name + description text.

## Support URL

```
https://app.municipality-wadi-el-sitt.org/
```

## Marketing URL (optional)

Leave blank until you have a dedicated marketing page. The support URL is fine as landing.

## Privacy Policy URL

```
https://app.municipality-wadi-el-sitt.org/privacy.html
```

---

## Category

- **Primary:** `Utilities` *(App Store equivalent of Play's "Communication")*
- **Secondary:** `News`

## Content rights

- Does your app contain, show, or access third-party content? → **No** (Coop products belong to the municipality/village sellers, not third-party licensed content)

## Age Rating

Complete the App Store Connect questionnaire — expected result: **4+**

Match answers from `../playstore/05_CONTENT_RATING_AND_DATA_SAFETY.md` §A, adapted:

| App Store question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Contests | None |
| Unrestricted Web Access | **NO** (WebKit view is restricted to the app's own origin — critical, see App Guideline 4.2 in the build guide) |
| Made for Kids | **No** |

Expected: **Rated 4+**.

## App Privacy (Nutrition Label)

Mirror the answers from `../playstore/05_CONTENT_RATING_AND_DATA_SAFETY.md` §B. In Apple's terminology, declare **Data Linked to You**:

- Contact Info → Name, Email, Phone Number (used for App Functionality, linked to identity)
- User Content → Photos, Other user content (case attachments, coop listings) — App Functionality
- Identifiers → User ID (Supabase UID) — App Functionality
- Purchases → Purchase History (coop orders) — App Functionality

**Data NOT collected:** Financial info, Location, Contacts, Health & Fitness, Sensitive Info, Browsing History, Search History, Diagnostics, Advertising Data.

Include in the "third parties" section:
- **Supabase** — database hosting, EU region, GDPR compliant

---

## Sensitive content declarations

| Question | Answer |
|---|---|
| Uses encryption? | **Yes — HTTPS/TLS only** *(counts as "exempt" — no ITSAppUsesNonExemptEncryption)* |
| Uses IDFA (advertising identifier)? | **No** |
| Uses location services? | **No** |
| Uses background modes (audio, VoIP, location)? | **No** *(push works via web-push which does NOT require iOS background modes)* |

## Encryption export compliance

Add this key to your app's `Info.plist` when packaging (Bubblewrap for iOS / Capacitor sets this):
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
This lets App Store Connect skip the annual export declaration for TLS-only apps.

---

## App Review Information (mandatory)

| Field | Value |
|---|---|
| **First name** | `Imad` |
| **Last name** | `Abi El Hessen` |
| **Phone number** | `+961 3 649 694` *(municipality line — used only if Apple's reviewer has a question)* |
| **Email** | `management@municipality-wadi-el-sitt.org` *(primary)*; backup: `imadaehn@gmail.com` |
| **Sign-in required?** | **Yes** — admin panels are login-gated |
| **Demo account username** | `google-reviewer@wadielset.local` *(same reviewer accounts as Google — create both)* |
| **Demo account password** | *(the password you set)* |
| **Notes** | Provide a short paragraph — see below |

### Notes to reviewer (paste this)

```
Wadi El Sit is the official municipal services app of the village of Wadi El Sit
in the Chouf district, Lebanon. Interface is Arabic-first with English and French
toggles in the top bar.

To review admin/mayor features, please sign in on citizen.html with the admin
demo account above. Public browse (news, coop, phonebook) works without login.

Government-app documentation: a signed authorization letter from the Mayor of
Wadi El Sit (Jihad Maksoud) is available on request — please email
management@municipality-wadi-el-sitt.org if App Review requires it.

Web push notifications require the user to install the app to their home
screen first (iOS 16.4+) — this is standard iOS behavior for web push.

App homepage: https://app.municipality-wadi-el-sitt.org
```

---

## Localizations

App Store Connect requires you to add each language explicitly. Order:

1. **Arabic** (primary — matches manifest `lang: ar`)
2. **English (US)** — required for App Review
3. **French (France)**

For each localization, fill: App name, subtitle, promotional text, description, keywords, screenshots, and marketing/support URLs.

---

## Assets checklist

| Asset | Size | Source |
|---|---|---|
| 1024×1024 App Icon | 1 file, RGB PNG no alpha | `ios-assets/icons/AppIcon-1024-1024.png` ✅ |
| iPhone screenshots 6.9" | 1290×2796 (min 3, max 10) | Take from `iPhone-15-Pro-Max` frame in DevTools |
| iPhone screenshots 6.5" | 1284×2778 (min 3, max 10) — **REQUIRED** | Use `iPhone-14-Plus` splash size as target |
| iPad Pro screenshots 12.9" | 2048×2732 (min 3, max 10) — **REQUIRED if you support iPad** | Use `iPad-Pro-12.9` size |
| Preview videos (optional) | 15-30s, per size class | Skip for v1 |

**Do NOT support iPad in the packaging step** if you want to skip the iPad screenshots — that halves the asset work.

---

## Version numbers

- `CFBundleShortVersionString` (marketing version) = `1.0.0` (shown to users)
- `CFBundleVersion` (build number) = `1` (must increase every upload)

---

## Release notes (What's New in this Version)

Same as Play — reuse from `store-assets/store-listings.md`:

```
🚀 إطلاق التطبيق الرسمي لبلدية وادي الست
🚀 Official launch of the Wadi El Sit Municipality app
🚀 Lancement officiel de l'app de la Municipalité de Wadi El Sit
```
