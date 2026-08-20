-- ═══════════════════════════════════════════════════════════════════════════
-- 13 — real sessions for coop sellers and delivery agents, with no email and
--      nothing to validate
--
-- The problem this closes: sellers and delivery agents were identified from
-- `localStorage`, so the only way their order lists could work was to leave
-- `coop_orders` readable by `anon` — which published every buyer's name, phone
-- and address to anyone holding the public key.
--
-- Moving them onto Supabase Auth would have meant email confirmation, which
-- the municipality does not want: a village shop should not ask a seller to
-- validate an email address, and phone OTP means an SMS provider and a bill.
--
-- So: no email, no OTP, nothing to confirm. Logging in — with a username *or*
-- a phone number, and the password the seller already has — mints an opaque
-- session token. Every list and every status change goes through a function
-- that resolves that token server-side and returns only what belongs to the
-- holder. The token is unguessable, expires, and can be revoked.
--
-- What this migration does NOT do: it does not yet close the anon read on
-- `coop_orders`. That happens in 14, once the page is calling these functions,
-- so the shop never breaks in between.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the session store ──────────────────────────────────────────────────────
create table if not exists public.coop_sessions (
  token       uuid primary key default gen_random_uuid(),
  kind        text        not null check (kind in ('seller','agent')),
  subject_id  uuid        not null,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '30 days'
);
create index if not exists coop_sessions_subject on public.coop_sessions(kind, subject_id);

alter table public.coop_sessions enable row level security;
-- Nobody reads this table directly — not anon, not authenticated, not staff.
-- Only the security-definer functions below ever touch it.
revoke all on public.coop_sessions from anon, authenticated;

-- ── resolving a token ──────────────────────────────────────────────────────
create or replace function public.coop_session_subject(p_token uuid, p_kind text)
returns uuid language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if p_token is null then return null; end if;
  update public.coop_sessions
     set last_seen = now()
   where token = p_token and kind = p_kind and expires_at > now()
  returning subject_id into v_id;
  return v_id;
end;
$$;

-- ── seller login — username OR phone, same password ────────────────────────
create or replace function public.coop_seller_login_v2(p_login text, p_password text)
returns table(
  id uuid, username text, display_name text, phone text, email text, bio text,
  area text, avatar_url text, status text, balance numeric, whatsapp text,
  created_at timestamptz, business_hours jsonb, delivery_options jsonb,
  rating numeric, total_orders integer, session_token uuid)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_seller public.coop_sellers%rowtype;
        v_token  uuid;
        v_digits text;
begin
  if coalesce(btrim(p_login),'') = '' or coalesce(p_password,'') = '' then return; end if;

  -- the phone as digits only, so 03/649694, 03649694 and +961 3 649694 all match
  v_digits := regexp_replace(p_login, '[^0-9]', '', 'g');
  v_digits := regexp_replace(v_digits, '^961', '');
  v_digits := regexp_replace(v_digits, '^0', '');

  select s.* into v_seller
    from public.coop_sellers s
   where (lower(s.username) = lower(btrim(p_login))
          or (length(v_digits) >= 6 and regexp_replace(regexp_replace(regexp_replace(
                coalesce(s.phone,''), '[^0-9]', '', 'g'), '^961',''), '^0','') = v_digits))
     and s.password_hash = encode(extensions.digest(p_password, 'sha256'), 'hex')
   limit 1;

  if v_seller.id is null then return; end if;

  insert into public.coop_sessions(kind, subject_id) values ('seller', v_seller.id)
  returning token into v_token;

  return query select v_seller.id, v_seller.username, v_seller.display_name, v_seller.phone,
                      v_seller.email, v_seller.bio, v_seller.area, v_seller.avatar_url,
                      v_seller.status, v_seller.balance, v_seller.whatsapp, v_seller.created_at,
                      v_seller.business_hours, v_seller.delivery_options, v_seller.rating,
                      v_seller.total_orders, v_token;
end;
$$;

-- ── agent login — phone + PIN, as today, now with a token ──────────────────
create or replace function public.coop_agent_login(p_phone text, p_pin text)
returns table(agent_id uuid, name text, area text, vehicle text, status text, session_token uuid)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_agent public.coop_delivery_agents%rowtype;
        v_token uuid;
        v_digits text;
begin
  if coalesce(btrim(p_phone),'') = '' or coalesce(p_pin,'') = '' then return; end if;
  v_digits := regexp_replace(regexp_replace(regexp_replace(
                p_phone, '[^0-9]', '', 'g'), '^961',''), '^0','');

  select a.* into v_agent
    from public.coop_delivery_agents a
   where regexp_replace(regexp_replace(regexp_replace(
           coalesce(a.phone,''), '[^0-9]', '', 'g'), '^961',''), '^0','') = v_digits
     and a.pin_hash = encode(extensions.digest(p_pin, 'sha256'), 'hex')
   limit 1;

  if v_agent.id is null then return; end if;

  insert into public.coop_sessions(kind, subject_id) values ('agent', v_agent.id)
  returning token into v_token;

  return query select v_agent.id, v_agent.name, v_agent.area, v_agent.vehicle,
                      v_agent.status, v_token;
end;
$$;

-- ── the seller's own orders ────────────────────────────────────────────────
create or replace function public.coop_seller_orders(p_token uuid)
returns setof public.coop_orders
-- volatile, not stable: resolving the token stamps last_seen, and a stable
-- function may not write.
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_seller uuid;
begin
  v_seller := public.coop_session_subject(p_token, 'seller');
  if v_seller is null then return; end if;
  return query select o.* from public.coop_orders o
    where o.seller_id = v_seller order by o.created_at desc;
end;
$$;

-- ── the agent's queues ─────────────────────────────────────────────────────
-- 'mine'      — assigned to this agent and not yet delivered
-- 'done'      — delivered by this agent
-- 'available' — unassigned deliveries anyone may claim. Buyer contact details
--               are withheld until the order is actually claimed.
create or replace function public.coop_agent_orders(p_token uuid, p_scope text)
returns setof public.coop_orders
-- volatile, not stable: resolving the token stamps last_seen, and a stable
-- function may not write.
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_agent uuid;
begin
  v_agent := public.coop_session_subject(p_token, 'agent');
  if v_agent is null then return; end if;

  if p_scope = 'mine' then
    return query select o.* from public.coop_orders o
      where o.delivery_agent_id = v_agent
        and coalesce(o.delivery_status,'') <> 'delivered'
      order by o.delivery_assigned_at desc nulls last;

  elsif p_scope = 'done' then
    return query select o.* from public.coop_orders o
      where o.delivery_agent_id = v_agent
        and o.delivery_status = 'delivered'
      order by o.delivery_delivered_at desc nulls last limit 100;

  elsif p_scope = 'available' then
    -- The buyer's name, phone and address are blanked until someone actually
    -- claims the delivery. An open queue is not a reason to hand every agent
    -- in the village a resident's address. jsonb round-trip rather than hstore,
    -- which is not installed here.
    return query
      select (jsonb_populate_record(null::public.coop_orders,
                to_jsonb(o) || jsonb_build_object(
                  'buyer_name', null, 'buyer_phone', null, 'buyer_address', null,
                  'customer_name', null, 'customer_phone', null,
                  'customer_address', null, 'customer_email', null))).*
        from public.coop_orders o
       where o.delivery_method = 'delivery'
         and o.status in ('pending','confirmed')
         and o.delivery_agent_id is null
       order by o.created_at desc;
  end if;
end;
$$;

-- ── the buyer's own orders, by the phone they ordered with ─────────────────
create or replace function public.coop_buyer_orders(p_phone text)
returns setof public.coop_orders
-- No token here: the buyer proves nothing but the phone number they ordered
-- with, exactly as the paper receipt works.
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_digits text;
begin
  v_digits := regexp_replace(regexp_replace(regexp_replace(
                coalesce(p_phone,''), '[^0-9]', '', 'g'), '^961',''), '^0','');
  if length(v_digits) < 6 then return; end if;
  return query select o.* from public.coop_orders o
    where v_digits in (
            regexp_replace(regexp_replace(regexp_replace(
              coalesce(o.customer_phone,''), '[^0-9]', '', 'g'), '^961',''), '^0',''),
            regexp_replace(regexp_replace(regexp_replace(
              coalesce(o.buyer_phone,''), '[^0-9]', '', 'g'), '^961',''), '^0',''))
    order by o.created_at desc;
end;
$$;

-- ── status changes, scoped to the holder of the token ──────────────────────
create or replace function public.coop_order_set_status(
  p_token uuid, p_kind text, p_order uuid, p_status text)
returns boolean
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_subject uuid; v_n int;
begin
  v_subject := public.coop_session_subject(p_token, p_kind);
  if v_subject is null then return false; end if;

  if p_kind = 'seller' then
    if p_status not in ('pending','confirmed','out_for_delivery','delivered','cancelled') then
      return false;
    end if;
    update public.coop_orders set status = p_status
     where id = p_order and seller_id = v_subject;
    get diagnostics v_n = row_count;
    return v_n > 0;

  elsif p_kind = 'agent' then
    if p_status not in ('assigned','picked_up','delivered') then return false; end if;
    update public.coop_orders
       set delivery_status = p_status,
           delivery_delivered_at = case when p_status = 'delivered' then now()
                                        else delivery_delivered_at end
     where id = p_order and delivery_agent_id = v_subject;
    get diagnostics v_n = row_count;
    return v_n > 0;
  end if;
  return false;
end;
$$;

-- ── an agent claiming an unassigned delivery ───────────────────────────────
create or replace function public.coop_order_claim(p_token uuid, p_order uuid)
returns boolean
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $$
declare v_agent uuid; v_n int;
begin
  v_agent := public.coop_session_subject(p_token, 'agent');
  if v_agent is null then return false; end if;
  update public.coop_orders
     set delivery_agent_id = v_agent,
         delivery_status = 'assigned',
         delivery_assigned_at = now()
   where id = p_order
     and delivery_agent_id is null          -- never steal a claimed delivery
     and delivery_method = 'delivery';
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

-- ── signing out ────────────────────────────────────────────────────────────
create or replace function public.coop_session_end(p_token uuid)
returns void language sql volatile security definer
set search_path = public, pg_temp as $$
  delete from public.coop_sessions where token = p_token;
$$;

-- ── grants ─────────────────────────────────────────────────────────────────
grant execute on function public.coop_seller_login_v2(text,text) to anon, authenticated;
grant execute on function public.coop_agent_login(text,text)     to anon, authenticated;
grant execute on function public.coop_seller_orders(uuid)        to anon, authenticated;
grant execute on function public.coop_agent_orders(uuid,text)    to anon, authenticated;
grant execute on function public.coop_buyer_orders(text)         to anon, authenticated;
grant execute on function public.coop_order_set_status(uuid,text,uuid,text) to anon, authenticated;
grant execute on function public.coop_order_claim(uuid,uuid)     to anon, authenticated;
grant execute on function public.coop_session_end(uuid)          to anon, authenticated;
-- coop_session_subject is internal; it is not granted to anyone.
revoke execute on function public.coop_session_subject(uuid,text) from anon, authenticated;
