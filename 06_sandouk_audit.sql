-- ═══════════════════════════════════════════════════════════════════════════
-- 06_sandouk_audit.sql — سجل عمليات صندوق البلدية (audit trail)
--
-- Applied to the live project on 2026-08-19. Every create / update / void /
-- unvoid / sign / delete on public.baladieh_finance is written by an AFTER
-- trigger, so the log cannot be bypassed by any client. UI-only actions
-- (exporting, sharing, printing, adding a phonebook name) are appended by
-- sandouk.html with source = 'ui'.
--
-- The log is append-only for clients: SELECT is open to authenticated users,
-- INSERT is limited to rows marked source = 'ui', and there is no UPDATE or
-- DELETE policy at all.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.baladieh_finance_audit (
  id          uuid primary key default gen_random_uuid(),
  entry_id    uuid,
  receipt_no  text,
  entry_date  date,
  action      text not null,                       -- create | update | void | unvoid | sign | delete | ui action
  changes     jsonb not null default '{}'::jsonb,  -- field -> {from, to}  (large columns -> {changed:true})
  snapshot    jsonb,                               -- key fields at the time of the action
  actor_email text,
  actor_id    uuid,
  source      text not null default 'db',          -- db (trigger) | ui (client) | seed (backfill)
  detail      text,
  created_at  timestamptz not null default now()
);

create index if not exists bfa_created_idx on public.baladieh_finance_audit(created_at desc);
create index if not exists bfa_entry_idx   on public.baladieh_finance_audit(entry_id);
create index if not exists bfa_actor_idx   on public.baladieh_finance_audit(actor_email);

alter table public.baladieh_finance_audit enable row level security;

drop policy if exists bfa_read_auth on public.baladieh_finance_audit;
create policy bfa_read_auth on public.baladieh_finance_audit
  for select to authenticated using (true);

drop policy if exists bfa_insert_ui on public.baladieh_finance_audit;
create policy bfa_insert_ui on public.baladieh_finance_audit
  for insert to authenticated with check (source = 'ui');

create or replace function public.baladieh_finance_audit_fn()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_action  text;
  v_changes jsonb := '{}'::jsonb;
  v_old     jsonb;
  v_new     jsonb;
  v_snap    jsonb;
  v_row     record;
  v_email   text;
  v_uid     uuid;
  k         text;
begin
  begin
    begin
      v_email := nullif(coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'email', '');
    exception when others then v_email := null; end;
    begin v_uid := auth.uid(); exception when others then v_uid := null; end;

    if tg_op = 'INSERT' then
      v_action := 'create'; v_row := new;
    elsif tg_op = 'DELETE' then
      v_action := 'delete'; v_row := old;
    else
      v_row := new;
      v_old := to_jsonb(old);
      v_new := to_jsonb(new);
      for k in select * from jsonb_object_keys(v_new) loop
        if (v_old -> k) is distinct from (v_new -> k) then
          if k in ('documents','signatures','signature') then
            v_changes := v_changes || jsonb_build_object(k, jsonb_build_object('changed', true));
          else
            v_changes := v_changes || jsonb_build_object(k, jsonb_build_object('from', v_old -> k, 'to', v_new -> k));
          end if;
        end if;
      end loop;
      if v_changes = '{}'::jsonb then
        return new;
      end if;
      if coalesce(old.voided,false) = false and coalesce(new.voided,false) = true then
        v_action := 'void';
      elsif coalesce(old.voided,false) = true and coalesce(new.voided,false) = false then
        v_action := 'unvoid';
      elsif (select bool_and(x in ('signatures','signature','signed_at')) from jsonb_object_keys(v_changes) x) then
        v_action := 'sign';
      else
        v_action := 'update';
      end if;
    end if;

    v_snap := jsonb_build_object(
      'entry_type',     v_row.entry_type,
      'entry_date',     v_row.entry_date,
      'receipt_no',     v_row.receipt_no,
      'wassel_number',  v_row.wassel_number,
      'amount',         v_row.amount,
      'currency',       v_row.currency,
      'category',       v_row.category,
      'person',         v_row.person,
      'description',    v_row.description,
      'payment_method', v_row.payment_method,
      'voided',         v_row.voided);

    insert into public.baladieh_finance_audit(
      entry_id, receipt_no, entry_date, action, changes, snapshot, actor_email, actor_id, source)
    values (
      v_row.id, v_row.receipt_no, v_row.entry_date, v_action, v_changes, v_snap,
      coalesce(v_email, case when tg_op = 'INSERT' then new.created_by
                             when tg_op = 'UPDATE' then coalesce(new.voided_by, new.created_by)
                             else old.created_by end),
      v_uid, 'db');
  exception when others then
    null;  -- auditing must never block a cash-box write
  end;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$fn$;

drop trigger if exists baladieh_finance_audit_trg on public.baladieh_finance;
create trigger baladieh_finance_audit_trg
  after insert or update or delete on public.baladieh_finance
  for each row execute function public.baladieh_finance_audit_fn();

-- ── backfill the history that predates the trigger, from the columns the rows carry ──
insert into public.baladieh_finance_audit(entry_id, receipt_no, entry_date, action, changes, snapshot, actor_email, source, detail, created_at)
select f.id, f.receipt_no, f.entry_date, 'create', '{}'::jsonb,
       jsonb_build_object('entry_type',f.entry_type,'entry_date',f.entry_date,'receipt_no',f.receipt_no,
         'wassel_number',f.wassel_number,'amount',f.amount,'currency',f.currency,'category',f.category,
         'person',f.person,'description',f.description,'payment_method',f.payment_method,'voided',f.voided),
       f.created_by, 'seed', 'مُستنتج من تاريخ الإنشاء (قبل تفعيل السجل)', f.created_at
from public.baladieh_finance f
where not exists (select 1 from public.baladieh_finance_audit a where a.entry_id = f.id and a.action = 'create');

insert into public.baladieh_finance_audit(entry_id, receipt_no, entry_date, action, changes, snapshot, actor_email, source, detail, created_at)
select f.id, f.receipt_no, f.entry_date, 'void',
       jsonb_build_object('voided', jsonb_build_object('from', false, 'to', true),
                          'void_reason', jsonb_build_object('from', null, 'to', to_jsonb(f.void_reason))),
       jsonb_build_object('receipt_no',f.receipt_no,'amount',f.amount,'currency',f.currency,'voided',true),
       f.voided_by, 'seed', 'مُستنتج من تاريخ الإلغاء (قبل تفعيل السجل)', coalesce(f.voided_at, f.created_at)
from public.baladieh_finance f
where f.voided = true
  and not exists (select 1 from public.baladieh_finance_audit a where a.entry_id = f.id and a.action = 'void');
