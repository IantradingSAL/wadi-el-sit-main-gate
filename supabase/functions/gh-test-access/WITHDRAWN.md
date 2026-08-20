# `gh-test-access` — withdrawn 20 August 2026

## What it was

A diagnostic left running with **`verify_jwt: false`**, holding the same
**hardcoded GitHub personal access token**. To anyone who asked, it returned:

- the token's account details,
- the full list of every repository that token could reach,
- confirmation of write access to the municipality's own repository.

**Reconnaissance handed out for free, from an anonymous URL.**

## What was done

The body was replaced with a `410 Gone` stub holding no token, and `verify_jwt`
was turned back on. The function was not deleted, so the change is visible and
reversible.

## What this does **not** fix

The token itself. It must be revoked on GitHub — Settings → Developer settings
→ Personal access tokens. The same token was also embedded in:

- `gh-deploy-admin-panel` — withdrawn at the same time; it published a page to
  the municipality's live site on an anonymous POST
- `gh-upload` — still deployed in this Supabase project. It writes to a
  repository belonging to a different application, not to this one, which is
  why it was left running; it is nonetheless the last place the token is still
  readable, and it does not belong in the municipality's project at all

Until the token is revoked it remains valid wherever else it exists.

## If deployment from a function is ever wanted again

It belongs in CI, triggered by a reviewed pull request, with a short-lived
token from a secret — never behind an anonymous URL carrying a permanent one.
