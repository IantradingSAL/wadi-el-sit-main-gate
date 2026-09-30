-- ═══════════════════════════════════════════════════════════════════════════
-- 49 — الموازنة (ميزانية 2027 وما بعدها): بنود الموازنة، والمصروف الفعلي عليها
--
-- The cash box records what WAS spent and received; this table records what
-- the council VOTED to spend and expects to receive, one row per budget line
-- (باب/فصل/بند — «5-2-1 سهرة وادي الست»). A line names the cash-box
-- categories that feed it, so «spent against 5-2-1» is simply the vouchers of
-- that year filed under those categories: no second ledger, nothing to keep
-- in step by hand.
--
--   budget_lines   the budget itself. Read behind budget_view, written behind
--                  budget_manage — two keys, because looking at the budget
--                  and changing a voted amount are different powers.
--
-- The actuals are not stored: sandouk.html computes them from
-- baladieh_finance, which it already reads under its own RLS (sandouk_view).
--
-- Both keys follow the standing four-part rule: their own names, defaults for
-- every role, rows on the user screen (dashboard.html, 💰 module), and the RLS
-- below asking the very same keys.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.budget_lines (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid(),
  year        int  not null check (year between 2000 and 2100),
  kind        text not null check (kind in ('income','expense')),
  code        text not null,                 -- «5-2-1» — باب-فصل-بند
  title       text not null,
  amount      numeric(16,2) not null default 0 check (amount >= 0),
  currency    text not null default 'LBP' check (currency in ('LBP','USD')),
  categories  text[] not null default '{}',  -- cash-box categories that feed it
  notes       text,
  unique (year, kind, code)
);
create index if not exists budget_lines_year_idx on public.budget_lines(year, kind);

-- A category feeds at most one line of a given year and kind: otherwise the
-- same voucher would be counted twice and the budget would add up to more
-- than the cash box ever paid. The page says so first; the database refuses.
create or replace function public.budget_lines_guard()
returns trigger language plpgsql as $fn$
declare v_dup text;
begin
  new.code       := btrim(new.code);
  new.title      := btrim(new.title);
  new.categories := coalesce(array(select distinct btrim(c) from unnest(new.categories) c
                                    where btrim(c) <> ''), '{}');
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  select c into v_dup
    from public.budget_lines b, unnest(b.categories) c
   where b.year = new.year and b.kind = new.kind and b.id <> new.id
     and c = any(new.categories)
   limit 1;
  if v_dup is not null then
    raise exception 'الفئة «%» مربوطة ببند آخر في موازنة % — الفئة الواحدة تغذّي بنداً واحداً', v_dup, new.year;
  end if;
  return new;
end;
$fn$;
drop trigger if exists budget_lines_guard on public.budget_lines;
create trigger budget_lines_guard before insert or update
  on public.budget_lines for each row execute function public.budget_lines_guard();

alter table public.budget_lines enable row level security;
drop policy if exists budget_lines_read  on public.budget_lines;
drop policy if exists budget_lines_write on public.budget_lines;
create policy budget_lines_read on public.budget_lines
  for select to authenticated
  using (public.has_perm('budget_view') or public.has_perm('budget_manage'));
create policy budget_lines_write on public.budget_lines
  for all to authenticated
  using (public.has_perm('budget_manage'))
  with check (public.has_perm('budget_manage'));
-- no anon access at all: the budget is published by the council, not by this table.

-- ── role defaults — every role, explicitly ────────────────────────────────
update public.role_permissions
   set perms = perms || '{"budget_view":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin','finance','sandouk');
update public.role_permissions
   set perms = perms || '{"budget_view":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin','finance','sandouk');
update public.role_permissions
   set perms = perms || '{"budget_manage":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"budget_manage":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');
