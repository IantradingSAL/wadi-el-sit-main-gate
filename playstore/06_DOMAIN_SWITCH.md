# 06 — Domain switch to `app.municipality-wadi-el-sitt.org`

> **Goal:** serve the Wadi El Sit municipality app from `https://app.municipality-wadi-el-sitt.org` (a subdomain of the mayor's official `.org` domain) instead of `https://iantradingsal.github.io/wadi-el-sit-main-gate/`.
>
> **Why it matters:** matches the mayor's email domain, strengthens Apple/Google publisher verification, gives a clean origin-root for Digital Asset Links (fixes the subpath problem documented in `04_TWA_BUILD.md`), and keeps the root `municipality-wadi-el-sitt.org` free for a separate WordPress website.
>
> **What stays unchanged:** the WordPress site at the root domain, the `management@municipality-wadi-el-sitt.org` email, and the old GitHub Pages URL (which will 301-redirect to the new subdomain).

---

## Prerequisite

You need access to the **DNS control panel** for `municipality-wadi-el-sitt.org`. That's the same place someone configured the MX records for the mayor's email — usually one of:

- The domain registrar (GoDaddy, Namecheap, Cloudflare, Google Domains, Squarespace, Porkbun, …)
- The hosting panel (cPanel, Plesk, DirectAdmin)
- A DNS-only provider (Cloudflare, DNSimple, Route 53)
- A Lebanese registrar (IDM, TerraNet, Cyberia, hosting.com.lb)

If you don't know where DNS is managed, whoever set up the mayor's email address knows.

---

## Step 1 — Add ONE DNS record

Add this single **CNAME** record. Do **NOT** change anything else — leave the existing `@` (root) A record, MX records, TXT/SPF records, and DKIM records alone.

| Field | Value |
|---|---|
| Type | `CNAME` |
| Name / Host / Subdomain | `app` |
| Target / Value / Points to | `iantradingsal.github.io` |
| TTL | `3600` (or "Automatic" / "Default") |
| Proxy (Cloudflare only) | **OFF** — DNS-only (grey cloud, not orange) |

**⚠️ Common gotcha:** some panels want just `app` in the Host field; others want the full `app.municipality-wadi-el-sitt.org`. If unsure, try `app` first — most panels auto-append the domain.

**⚠️ Do NOT add a trailing dot** to the target unless the panel says to. `iantradingsal.github.io` is correct in every panel I've seen.

---

## Step 2 — Click-by-click for common registrars

### GoDaddy (dcc.godaddy.com)
1. My Products → Domain → `municipality-wadi-el-sitt.org` → **DNS** button
2. Scroll to the DNS records table → **Add New Record**
3. Type: `CNAME` · Name: `app` · Value: `iantradingsal.github.io` · TTL: `1 Hour` · **Save**

### Namecheap (ap.www.namecheap.com)
1. Domain List → `municipality-wadi-el-sitt.org` → **Manage**
2. **Advanced DNS** tab
3. **Add New Record** → Type: `CNAME Record` · Host: `app` · Value: `iantradingsal.github.io.` (Namecheap requires the trailing dot) · TTL: `Automatic` · **✓** to save

### Cloudflare (dash.cloudflare.com)
1. Select the `municipality-wadi-el-sitt.org` zone
2. **DNS** → **Records** → **Add record**
3. Type: `CNAME` · Name: `app` · Target: `iantradingsal.github.io` · **Proxy status: DNS only** (grey cloud, NOT orange) · TTL: `Auto` · **Save**

### Google Domains / Squarespace Domains
1. My domains → `municipality-wadi-el-sitt.org` → **DNS**
2. Custom records → Add
3. Host: `app` · Type: `CNAME` · TTL: `3600` · Data: `iantradingsal.github.io` · **Save**

### cPanel (Zone Editor)
1. Advanced → **Zone Editor** → Manage next to `municipality-wadi-el-sitt.org`
2. **Add Record** → dropdown → **Add CNAME Record**
3. Name: `app.municipality-wadi-el-sitt.org.` (with trailing dot) · CNAME: `iantradingsal.github.io.` · TTL: `14400` · **Add Record**

### Zoho DNS Manager (Domains → DNS)
1. Sign in at `mailadmin.zoho.com` → Domains → the domain → **DNS Manager**
2. **Add Record** → Type: `CNAME` · Hostname: `app` · Value: `iantradingsal.github.io` · **Add**

---

## Step 3 — Wait for DNS propagation

- Usually 5–30 minutes
- Occasionally up to 2 hours
- Very rarely up to 24 hours (only if you set a huge TTL somewhere)

**Verify it's live:**
```bash
dig app.municipality-wadi-el-sitt.org +short
# Should return:
# iantradingsal.github.io.
# 185.199.108.153
# 185.199.109.153
# 185.199.110.153
# 185.199.111.153
```

Or use https://dnschecker.org — enter `app.municipality-wadi-el-sitt.org`, choose `CNAME`, hit Search. Green checks worldwide = propagated.

**⚠️ Do NOT proceed to Step 4 until DNS is resolving.** Enabling the custom domain in GitHub before DNS resolves will break the site.

---

## Step 4 — Ping this chat: "DNS is live"

At that point I run the code-side switch as a single commit to `main` (via a follow-up PR or directly on this branch). Below is exactly what changes.

---

## What I change on switch day (reference — you don't do this)

### 4a. Add `CNAME` file at repo root
```
app.municipality-wadi-el-sitt.org
```

### 4b. Enable custom domain in GitHub Pages
Repo → Settings → Pages → Custom domain: `app.municipality-wadi-el-sitt.org` → Save → wait 5–30 min for Let's Encrypt cert → tick **Enforce HTTPS**.

### 4c. Update `manifest.json`
- `start_url`: `/wadi-el-sit-main-gate/` → `/`
- `scope`: `/wadi-el-sit-main-gate/` → `/`
- Every shortcut `url`: strip the `/wadi-el-sit-main-gate` prefix
- `share_target.action`: same strip

### 4d. Update `sw.js`
- Cache path from `/wadi-el-sit-main-gate/*` to `/*`
- Bump SW version to force refresh on installed PWAs

### 4e. Update `twa-manifest.json`
- `host`: `iantradingsal.github.io` → `app.municipality-wadi-el-sitt.org`
- `startUrl`: `/wadi-el-sit-main-gate/` → `/`
- `webManifestUrl`: `https://app.municipality-wadi-el-sitt.org/manifest.json`

### 4f. Move `.well-known/assetlinks.json`
- From subpath to origin root — served at `https://app.municipality-wadi-el-sitt.org/.well-known/assetlinks.json`
- No more Option A/B hack from `04_TWA_BUILD.md` — this is Option A, cleanly.

### 4g. Update `store-assets/store-listings.md`
- Publisher URL (AR/EN/FR): all → `https://app.municipality-wadi-el-sitt.org`

### 4h. Update `store-assets/mayor-authorization-letter.md`
- Website line → `https://app.municipality-wadi-el-sitt.org`
- (The .docx version already reflects this.)

### 4i. Update every hardcoded absolute URL in the HTML pages
- `og:url` meta tags
- `<link rel="canonical">`
- Structured data JSON-LD `url` fields
- Any absolute internal `<a href>`

### 4j. Update the App Store submission docs (`applestore/` — if that pack lands before switch day)
- Publisher URL → `https://app.municipality-wadi-el-sitt.org`
- Universal Links `apple-app-site-association` file goes at the origin root of the new domain

---

## Rollback (if anything breaks)

**Undo Step 1 (DNS)** — delete the `app` CNAME record. Within ~1 hour, `app.municipality-wadi-el-sitt.org` stops resolving. Root domain (WordPress) and email are unaffected because we never touched them.

**Undo Steps 4a–4j (code)** — `git revert <commit-sha>` and force-push, or open a new PR that reverses the changes. GitHub Pages goes back to serving at `iantradingsal.github.io/wadi-el-sit-main-gate/`.

Nothing about this migration is one-way.

---

## Timeline expectation

| Step | Wall-clock |
|---|---|
| Add CNAME record in your registrar | 2 minutes |
| DNS propagation | 5 min – 2 hours |
| I make the code-side commit | 5 minutes |
| GitHub Pages Let's Encrypt cert issue | 5–30 minutes |
| First successful load at `app.municipality-wadi-el-sitt.org` | Same day, most likely within 1 hour of DNS being live |

Full end-to-end: **under 3 hours** on a normal day.

---

## Checklist for you

- [ ] Find out where DNS is managed for `municipality-wadi-el-sitt.org` (Section: Prerequisite)
- [ ] Log in to that panel
- [ ] Add the ONE CNAME record from Step 1
- [ ] Verify via `dig` or dnschecker.org that it resolves
- [ ] Come back and say "DNS is live"
- [ ] I run the code-side switch in one commit
- [ ] Verify by visiting `https://app.municipality-wadi-el-sitt.org` — should show the app
- [ ] Verify the old `https://iantradingsal.github.io/wadi-el-sit-main-gate/` — should 301 redirect to the new URL

Once these boxes are all ticked, we build the `.aab` (Bubblewrap) and iOS wrapper against the new host — clean, one-shot, no re-submission cycle.
