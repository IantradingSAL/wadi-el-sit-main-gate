# App Privacy + Review Answers (Apple)

Answers pre-filled for the Apple App Store equivalents of Google's Data Safety
and content-rating questionnaires. Match `../playstore/05_CONTENT_RATING_AND_DATA_SAFETY.md`.

---

## A. App Privacy (Nutrition Label)

App Store Connect → your app → App Privacy → Get Started.

### Data Collection — declare "Yes, we collect data"

For each data type below, pick a **Purpose** (all are "App Functionality"), and
mark **Data Linked to User**: **Yes** (users are logged in, so all data ties back
to the account).

| Data Type | Purpose | Linked? | Used for tracking? |
|---|---|---|---|
| Contact Info → Name | App Functionality | Yes | **No** |
| Contact Info → Email | App Functionality, Customer Support | Yes | **No** |
| Contact Info → Phone Number | App Functionality | Yes | **No** |
| Contact Info → Physical Address | *only if you add it* — skip for now | — | — |
| User Content → Photos or Videos | App Functionality *(citizen case attachments)* | Yes | **No** |
| User Content → Other User Content | App Functionality *(cases, comments, coop listings)* | Yes | **No** |
| Identifiers → User ID | App Functionality *(Supabase UID)* | Yes | **No** |
| Purchases → Purchase History | App Functionality *(coop orders — no payment info)* | Yes | **No** |

### Data NOT collected — say NO to these

- Financial Info (Payment info, credit info, other financial info) — coop orders don't process payments
- Location (Precise or Coarse)
- Contacts (device address book)
- Search History
- Browsing History
- Health & Fitness
- Sensitive Info (race, religion, sexual orientation, etc.)
- Diagnostics (crash logs, performance data) — you don't collect any
- Other Diagnostic Data
- Other Data Types

### "Do you or your third-party partners use this data to track users?"

**No — nothing is used for cross-app/site tracking.**

### Third-party partners

- **Supabase** (database/auth hosting) — categorize as "Analytics or Advertising"? → **No, backend service only**. Apple's flow accepts backend hosting under "Data linked to the user" without a special tracking declaration.

---

## B. Age rating questionnaire

App Store Connect → App Information → Age Rating → Edit.

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence | **None** |
| Prolonged Graphic or Sadistic Realistic Violence | **None** |
| Profanity or Crude Humor | **None** |
| Mature/Suggestive Themes | **None** |
| Horror/Fear Themes | **None** |
| Medical/Treatment Information | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Simulated Gambling | **None** |
| Sexual Content or Nudity | **None** |
| Graphic Sexual Content and Nudity | **None** |
| Contests | **None** |
| Unrestricted Web Access | **NO** ⚠️ Critical — see below |
| Gambling | **No** |
| Made for Kids | **No** |

**Expected rating:** `4+`.

### About "Unrestricted Web Access"

If Apple sees the app can load any URL (e.g. links open a browser widget with the full internet), rating jumps to **17+**. In your PWA-wrapper:

- ✅ Both PWABuilder iOS and Capacitor default to **scope-restricted WebKit** — only `iantradingsal.github.io/wadi-el-sit-main-gate/*` (and origins listed in `scope_extensions`) load inside the app.
- ✅ External links (news article external URLs, Supabase console links from admin) should open in the OS default browser via `window.open` or `<a target="_blank">`, NOT inside the app view.

If your app opens ANY external URL inside its own WebView, mark "Unrestricted Web Access" as **YES** and accept the 17+ rating.

---

## C. App Review Information (mandatory fields)

App Store Connect → your version → App Review Information.

| Field | Value |
|---|---|
| **Contact — First name** | *(your first name)* |
| **Contact — Last name** | *(your last name)* |
| **Contact — Phone** | *(a real number, only used by App Review if needed)* |
| **Contact — Email** | `imadaehn@gmail.com` *(will receive rejection/approval notices)* |
| **Sign-in required?** | ✅ **Yes** |
| **Demo account — Username** | `google-reviewer-admin@wadielset.local` |
| **Demo account — Password** | *(set a strong password, share only with Apple)* |
| **Notes** | See below |

### Notes to the App Reviewer (paste this)

```
Wadi El Sit is the official municipal services app of the village of Wadi El Sit
in Chouf, Lebanon. Interface is Arabic-first with English and French toggles.

FEATURES TO TEST:

1. Public browse (no login required)
   - Home page — 5 service tiles
   - News feed (news.html)
   - Cooperative store (coop.html) — browse products
   - Phonebook (phonebook.html) — village directory

2. Authenticated features (use the demo account above)
   - Submit a citizen request (citizen.html) — includes photo attachment
   - Admin panel (mayor role) — view submitted cases, respond, publish news
   - Coop admin panel — manage products
   - Water portal — irrigation schedule for the account

3. Web push notifications (iOS 16.4+)
   - After installing to home screen, users can opt in via the 🔔 button
   - Test broadcasts sent through admin-push.html

APP CATEGORY:
Municipality / Government app for a single village in Lebanon. Available to
residents, staff, and the mayor. Not intended for general-public use outside
the village but does not restrict downloads.

GOVERNMENT AFFILIATION:
A signed authorization letter from the mayor of Wadi El Sit is available
on request. Please email imadaehn@gmail.com if App Review requires it.

WHY IT IS NOT JUST A WEBSITE:
- Push notifications (municipal alerts, iOS 16.4+ web-push)
- Share target (share content INTO the citizen form from other apps)
- Home-screen shortcuts (directly to phonebook, water, coop)
- Offline mode (service worker caches app shell)
- Login-gated staff/admin flows

CONTENT MODERATION:
User-generated content (coop listings, citizen requests, comments) is
reviewed by the municipality's admins before it becomes visible to other
users. Report abuse: users can email imadaehn@gmail.com.
```

---

## D. Export Compliance

App Store Connect → your version → App Store → Encryption.

- **Does your app use encryption?** → **Yes**
- **Does your app qualify for any exemptions?** → **YES — only uses standard HTTPS/TLS provided by iOS**

This exempts you from the annual export compliance filing. Also add to `Info.plist` in your Xcode project:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

---

## E. Kids / Family sharing

- **Made for Kids?** → **No**
- **Family Sharing eligible?** → No (only relevant for paid apps)

---

## F. Government / Municipality declaration

Apple doesn't have a formal "government app" category like Google does, but if App Review challenges the branding (e.g. "prove you represent the Wadi El Sit municipality"):

- Email `appreview@apple.com` with your case ID
- Attach the signed mayor authorization letter (from `store-assets/mayor-authorization-letter.md` after signing + scanning)
- Reference in your reply: "Wadi El Sit is a real municipality in the Chouf district, Lebanon (verifiable via Lebanon's Ministry of Interior)."

Response typically arrives within 24-48h. Most municipality apps clear without needing this step.
