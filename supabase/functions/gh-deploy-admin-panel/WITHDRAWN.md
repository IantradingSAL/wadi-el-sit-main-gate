# `gh-deploy-admin-panel` — withdrawn 20 August 2026

## What it was

An edge function with **`verify_jwt: false`** — callable by anyone on the
internet — holding a **hardcoded GitHub personal access token** (a classic
`ghp_…` PAT). It fetched HTML from the `coop-admin-ui` function and committed
it as `admin-panel.html` to `IantradingSAL/wadi-el-sit-main-gate` on `main`.

`main` is the branch GitHub Pages publishes to
`app.municipality-wadi-el-sitt.org`.

**So one anonymous POST published a page to the municipality's website.** No
key, no session, no check of any kind.

## What was done

The body was replaced with a `410 Gone` stub holding no token, and `verify_jwt`
was turned back on. The function was not deleted, so the change is visible and
reversible.

## What this does **not** fix

The token itself. It must be revoked on GitHub — Settings → Developer settings
→ Personal access tokens. The same token was also embedded in:

- `gh-test-access` — withdrawn at the same time; it returned the token's
  account and every repository it could reach, to anyone who asked
- `gh-upload` — still deployed in this Supabase project. It writes to a
  repository belonging to a different application, not to this one, which is
  why it was left running; it is nonetheless the last place the token is still
  readable, and it does not belong in the municipality's project at all

Until the token is revoked it remains valid wherever else it exists.

## If deployment from a function is ever wanted again

It belongs in CI, triggered by a reviewed pull request, with a short-lived
token from a secret — never behind an anonymous URL carrying a permanent one.
