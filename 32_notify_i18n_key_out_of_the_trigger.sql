-- ═══════════════════════════════════════════════════════════════════════════
-- 32 — مفتاح الخدمة يخرج من تعريف المُشغّل
--
-- The `notify-i18n` trigger on public.cases was created through the dashboard's
-- webhook helper, which writes the Authorization header — and therefore the
-- **service-role key, in plaintext** — into the trigger's own definition:
--
--   CREATE TRIGGER "notify-i18n" AFTER INSERT OR UPDATE ON public.cases
--     … supabase_functions.http_request('…/notify-i18n', 'POST',
--        '{"Authorization":"Bearer eyJ…"}', '{}', '5000')
--
-- `pg_get_triggerdef()` is readable by any role that can read the catalogue,
-- and that key is not a notification key: it is the key that bypasses every
-- row-level security policy in this project. Migration 31 deliberately did not
-- reuse it — `push_notify()` carries a token of its own that can do nothing but
-- send a notification. This migration finishes the job for the older path.
--
-- The key now lives in `vault`, encrypted, and a plpgsql trigger reads it at
-- call time. The catalogue holds nothing but a function name.
--
-- The body is the same shape the dashboard helper sent, because `notify-i18n`
-- reads `record` / `old_record` / `type` and nothing else changes on its side.
--
-- Rotating the key remains the owner's to do from the Supabase dashboard.
-- After a rotation the only thing to update is the vault secret:
--   select vault.update_secret(
--            (select id from vault.secrets where name = 'edge_service_key'),
--            '<the new key>');
-- ═══════════════════════════════════════════════════════════════════════════

-- ── move the key, without it ever being printed ───────────────────────────
do $$
declare v_def text; v_key text; v_id uuid;
begin
  select pg_get_triggerdef(t.oid) into v_def
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'cases' and t.tgname = 'notify-i18n';

  if v_def is null then
    raise notice 'notify-i18n trigger not found — nothing to move';
    return;
  end if;

  v_key := (regexp_match(v_def, 'Bearer\s+([A-Za-z0-9_.\-]{40,})'))[1];
  if v_key is null then
    raise exception 'no bearer token in the notify-i18n trigger definition — refusing to guess';
  end if;

  select id into v_id from vault.secrets where name = 'edge_service_key';
  if v_id is null then
    perform vault.create_secret(v_key, 'edge_service_key',
      'مفتاح الخدمة الذي تناديه به دوال الحافة — كان مكتوباً نصّاً داخل مُشغّل notify-i18n');
  else
    perform vault.update_secret(v_id, v_key);
  end if;
end $$;

-- ── the dispatcher ────────────────────────────────────────────────────────
-- Same call, same body, same fire-and-forget behaviour — the key is simply
-- read from the vault instead of being baked into the catalogue.
create or replace function public.notify_i18n_dispatch()
returns trigger language plpgsql security definer
set search_path = public, vault, pg_temp as $fn$
declare v_key text;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'edge_service_key';
  if v_key is null then
    raise warning 'notify_i18n_dispatch: no edge_service_key in the vault';
    return coalesce(new, old);
  end if;

  perform net.http_post(
    url     := 'https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/notify-i18n',
    body    := jsonb_build_object(
                 'type',       tg_op,
                 'table',      tg_table_name,
                 'schema',     tg_table_schema,
                 'record',     to_jsonb(new),
                 'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end),
    params  := '{}'::jsonb,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 5000);

  return new;
exception when others then
  -- a citizen must never fail to file a request because the mailer is down
  raise warning 'notify_i18n_dispatch: %', sqlerrm;
  return new;
end;
$fn$;
revoke execute on function public.notify_i18n_dispatch() from public, anon, authenticated;

drop trigger if exists "notify-i18n" on public.cases;
create trigger "notify-i18n"
  after insert or update on public.cases
  for each row execute function public.notify_i18n_dispatch();

-- After applying, the catalogue no longer carries the key:
--   select pg_get_triggerdef(oid) … → EXECUTE FUNCTION public.notify_i18n_dispatch()
-- and a status change still e-mails the citizen and pushes to their phone.
