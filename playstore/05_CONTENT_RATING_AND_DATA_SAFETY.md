# Pre-filled Answers — Content Rating & Data Safety (Wadi El Sit)

Google Play requires two mandatory questionnaires before you can publish. Below are
the recommended answers for **Wadi El Sit Municipality** — a public-facing municipal
services app for residents of the Wadi El Sit village.

Your manifest already carries an **IARC rating ID** (`e58c174a-81d2-5c3c-32cc-34308ef2b16e`), which suggests you've completed the questionnaire before. Re-verify below.

---

## A. Content rating questionnaire (IARC)

**Category to select:** *Utility, Productivity, Communication, or Other*

Answer **No** to all of the following:

| Question | Answer |
|---|---|
| Does your app contain any violence? | **No** |
| Does your app contain sexual content or nudity? | **No** |
| Does your app contain profanity or crude humor? | **No** |
| Does your app contain references to controlled substances? | **No** |
| Does your app simulate gambling? | **No** |
| Does your app include user-generated content (UGC) that could be shared publicly? | **Yes** — Coop sellers list products, citizens can post cases and comments, news moderators can post news. UGC IS moderated by municipality admins. |
| Does your app share the user's precise location with other users? | **No** |
| Does your app allow users to interact or exchange content with strangers? | **Limited** — Coop store connects buyers and sellers within the village; citizen cases go to municipal staff only. Not a general chat platform. |
| Does your app collect, use, or transmit any personal information? | **Yes** — name, phone, email, submitted requests. See Data Safety below. |
| Is your app intended for or targeted at children? | **No** |
| Does the app include social features (chat, forums)? | **No public chat**, but citizens can comment on their own cases and reply to mayor/admin responses. |

**Expected rating:** Everyone / PEGI 3 (UGC in a moderated, small-community setting doesn't push the rating higher).

**IMPORTANT — UGC declaration:**
Because you accept user-generated content (coop listings, citizen cases), Google requires you to declare:
- ✅ You have a system to moderate UGC (mayor/admin roles review before publishing).
- ✅ You provide users a way to report inappropriate content (email `imadaehn@gmail.com`).
- ✅ You block users who violate terms.

If any of those isn't true today, add it before submission (even a simple "report abuse" mailto link on user-facing pages is enough).

---

## B. Data Safety form

### Data collection & sharing summary
- **Does your app collect or share any of the required user data types?** → **Yes**
- **Is all of the user data collected by your app encrypted in transit?** → **Yes** (HTTPS/TLS via Supabase + GitHub Pages)
- **Do you provide a way for users to request that their data is deleted?** → **Yes** (via `privacy.html` — verify the deletion contact is listed)

### Data types — answer per type

| Data type | Collected? | Shared? | Purpose | Optional? |
|---|---|---|---|---|
| **Name** | Yes | No | Account management, App functionality (attach to submitted cases and coop orders) | Required |
| **Email address** | Yes | No | Account management, Communications *(status emails)* | Required |
| **Phone number** | Yes | No | App functionality *(coop orders, case follow-up)* | Optional in some flows |
| **User IDs** (Supabase user ID) | Yes | No | Account management | Required |
| **Photos** | Yes *(if the citizen attaches one to a case)* | No | App functionality | Optional |
| **Purchase history** | Yes *(coop orders)* | No | App functionality | Required for coop use |
| **Other actions** (case submissions, comments, reactions, push subscription) | Yes | No | App functionality | Required |
| **App activity — page views** | No *(no analytics)* | — | — | — |
| **App info & performance — Crash logs / Diagnostics** | No | — | — | — |
| **Device or other IDs** | No | — | — | — |
| **Precise location** | No | — | — | — |
| **Approximate location** | No | — | — | — |
| **Contacts / calendar / SMS / call logs** | No | — | — | — |
| **Health & fitness** | No | — | — | — |
| **Financial info** | No *(coop orders record product+qty+phone, not payment info)* | — | — | — |
| **Web browsing history** | No | — | — | — |
| **Messages** | No | — | — | — |
| **Files & docs** | Yes *(if attached to citizen cases)* | No | App functionality | Optional |
| **Notifications data** (push tokens) | Yes | No | Send municipal alerts | Optional (opt-in) |

### Security practices
- ✅ Data encrypted in transit
- ✅ Users can request data deletion
- ✅ Follows Play Families policy: **N/A** (not for children)
- ✅ Independent security review: **No** *(optional — check if you have one)*
- ✅ Data collection follows a published privacy policy: **Yes** → `https://iantradingsal.github.io/wadi-el-sit-main-gate/privacy.html`

---

## C. App content declarations

| Question | Answer |
|---|---|
| **Privacy policy URL** | https://iantradingsal.github.io/wadi-el-sit-main-gate/privacy.html |
| **App access** — is any functionality behind a login? | **Yes** — admin/mayor features are gated. Provide a reviewer test account (see below). |
| **Ads** | **No, my app does not contain ads** |
| **Content rating** | Complete the questionnaire above (IARC ID already in manifest) |
| **Target audience and content** | Age group: **13+** (municipal services); not primarily for children: **Yes** |
| **News app** | **Yes** — the app has a news module. This unlocks a separate short review by Google's news team. Nothing to fix — just answer honestly. |
| **COVID-19 contact tracing** | **No** |
| **Data safety** | Complete section B above |
| **Government app** | **Yes** — it represents the Wadi El Sit municipality. Google may ask for **proof of authorization** — use `store-assets/mayor-authorization-letter.md` (get it signed and scanned as PDF). |
| **Financial features** | **No** *(coop orders don't process payments in-app)* |
| **Health features** | **No** |

---

## D. Test account for Google reviewers

Create these accounts in Supabase Auth **before submitting**:

### Citizen reviewer account (for basic access)
```
Email:    google-reviewer@wadielset.local
Password: (strong, only shared with Google)
Role:     citizen (default)
```

### Admin reviewer account (for admin features)
```
Email:    google-reviewer-admin@wadielset.local
Password: (strong, different from above)
Role:     admin (via public.user_roles)
```

Provide these credentials in Play Console → App content → **App access** → "All or some functionality in my app is restricted".

Include a short walkthrough in the same field:
> The app has an Arabic-first interface with EN/FR toggle in the top bar. To review admin features, sign in as `google-reviewer-admin@wadielset.local`. Coop and news pages have public browse mode.

Without this, Google's manual review will fail and your submission will be rejected within 1-3 days.

---

## E. Government app extra step (important)

Because this is a municipality app, Google's Government app policy applies:
- You'll be asked to upload a **letter of authorization** from the municipality.
- `store-assets/mayor-authorization-letter.md` is a template — print it, get the mayor to sign, scan as PDF, keep ready to upload during submission.
- Without it, Google will reject the submission within a few days with a "requires proof of government affiliation" note.
