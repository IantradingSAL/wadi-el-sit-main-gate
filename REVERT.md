# How to undo the pre-launch audit

Written 21 August 2026, immediately before merging the audit corrections.
If something goes wrong after the merge, everything below reverses it.

**Nothing was deleted from the cash box.** `baladieh_finance` (168 rows), its
audit trail (247) and its saved views (2) were never touched by any of this
work, and a dated copy of all three sits in the database anyway. The same is
true of the water committee's cash box and the irrigation register.

---

## 1. The website

Every audit correction went in through **pull request #96**. The state of the
site *before* any of it is the commit that pull request branched from:

```
16f7d39   edge functions: authorise send-push, withdraw the two GitHub-token endpoints (#95)
```

That commit is permanently on `main` — it cannot be lost.

**To undo everything, in one click:** open pull request #96 on GitHub and press
**Revert**. GitHub opens a new pull request that puts every file back.

**Or from a terminal:**

```bash
git revert -m 1 <the merge commit of #96>     # undo the merge, keep the history
git push origin main
```

**To look at the old site without changing anything:**

```bash
git checkout 16f7d39
```

Undoing the website does **not** undo the database. Do section 2 as well, or
the pages and the database will disagree.

---

## 2. The database

A dated snapshot of every table this work could affect was taken before the
merge, into the schema **`backup_20260821`**:

| table | rows at snapshot |
|---|---|
| `baladieh_finance` | 168 |
| `baladieh_finance_audit` | 247 |
| `sandouk_views` | 2 |
| `settings` | 1 |
| `water_finance` | 27 |
| `irr_owners` · `irr_config` | 1 · 1 |
| `phonebook_registry` | 601 |
| `phonebook_extras` · `phonebook_entries` | 11 · 7 |
| `coop_sellers` · `coop_delivery_agents` · `coop_categories` · `coop_admins` | 3 · 2 · 10 · 1 |
| `cases` | 39 |
| `role_permissions` · `user_roles` · `user_permissions` | 11 · 10 · 0 |

### Put one table back

```sql
begin;
  delete from public.baladieh_finance;
  insert into public.baladieh_finance select * from backup_20260821.baladieh_finance;
commit;
```

Substitute any table name from the list above. Do it inside `begin; … commit;`
so a mistake rolls back instead of half-applying.

### Put the coop test data back

The 11 orders, 13 transactions and 1 product removed before launch are in their
own archive tables, kept separately because they were deleted deliberately
rather than snapshotted:

```sql
begin;
  insert into public.coop_products     select * from public._archive_coop_products;
  insert into public.coop_orders       select * from public._archive_coop_orders;
  insert into public.coop_transactions select * from public._archive_coop_transactions;
commit;
```

Order matters — products, then orders, then transactions — because of the
foreign keys between them.

### Undo the three migrations

`20_close_unused_rpc_surface.sql`, `21_coop_categories.sql` and
`22_phonebook_registry.sql` are already applied to the live project.

- **22** only adds things: a table, two functions, one permission key. Leaving
  it in place breaks nothing, even if the website is reverted. To remove it:
  `drop table public.phonebook_registry cascade;`
- **21** changed how the shop's categories are written. Reverting the website
  without reverting this leaves the coop admin unable to edit categories, so
  either revert both or neither.
- **20** closed functions to `anon` and dropped three that nothing calls. To
  reopen one: `grant execute on function public.<name>(<args>) to anon;`

---

## 3. The backups that are not ours

The snapshot above lives in the same database it is protecting, which makes it
the right tool for "a migration went wrong" and the wrong tool for "the
database is gone".

For that, use Supabase's own backups — **Dashboard → Database → Backups** — and
check they are actually enabled. For a municipality's cash box it is worth
taking a manual export as well:

**Dashboard → Table Editor → `baladieh_finance` → Export → CSV**

Keep that file somewhere that is not Supabase and not this repository. It takes
about ten seconds and it is the only copy that survives losing the account.

---

## 4. What can never be undone

Two things are already public and no revert reaches them:

- The old `contacts-registry.js`, with 601 residents' sect, gender and full
  birth dates, is in this repository's git history, and the repository is
  public. Removing the file today does not unpublish what was already served.
- The tax archive, for the same reason.

Both were raised in the audit. Making the repository private is the only
measure that limits further exposure.
