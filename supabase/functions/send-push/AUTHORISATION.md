# `send-push` — what changed on 20 August 2026

## What it was

`verify_jwt: false`, and **no authorisation of its own**.

It has to run with JWT verification off: a resident filing a request calls it
to tell the municipality, and that resident has no session. But nothing else
stood in the way either.

So anyone who knew the URL could POST:

```json
{ "mun_id": "…", "title": "…", "body": "…" }
```

…and the notification arrived on **every resident's phone, as the
municipality**. `mun_id` is in the page source. Nothing else was needed.

## What it is now

Each request is classified, and `push_send_allowed()` in the database decides
— the same permission model as everything else on the platform:

| scope | meaning | who may |
|---|---|---|
| **inward** | `to_role` is a municipal role, no topics, no phone — telling the municipality something | anyone; it is what the citizen page does when a request is filed, and the worst it can do is bother the staff |
| **outward** | everyone, a topic, a non-municipal role, or one resident's phone | requires `push_send` |

The caller is resolved from their own JWT. `pwa.js` now offers the signed-in
staff member's access token when there is a session, and falls back to the anon
key when there is not — which is exactly the inward case.

Measured after applying:

```
the anon key (what an attacker holds)   outward   refused
the anon key                            inward    allowed
sandouk clerk / finance / water-only    outward   refused
mayor / admin / super admin             outward   allowed
```

## Not verified from here

The decision table was tested in SQL. The deployed function was **not** called
over HTTP — this environment's proxy blocks requests to the project. Worth one
real test: send a notification from an account holding `push_send`, and file a
request as a resident to confirm staff are still notified.
