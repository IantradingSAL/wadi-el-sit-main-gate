-- ═══════════════════════════════════════════════════════════════════════════
-- 34 — بطولة وادي الست: طاولة وورق، تسجيل يحجز الطاولة، وحكم يسجل النتيجة
--
-- Four competitions on games.html: طاولة فرنجية ومحبوسة (فردي، لاعبان على كل
-- طاولة، وكل الأدوار «الغالب 2 من 3»)، وورق طرنيب وأربعمية (فريق من شخصين،
-- فريقان على كل طاولة، مباراة واحدة حاسمة).
--
-- The protocol, agreed with the club:
--   · 10$ per person (20$ a card team), DUE the moment you register. A tawli
--     player who brings their own board pays 5$ — chosen, mandatorily, at
--     registration. No-show: the fee stays due and the matches count as lost.
--   · Table numbers (ف-1، م-2، ط-3، ٤-1…) are assigned ATOMICALLY at
--     registration under an advisory lock per game — like a sanad number, a
--     table seat is never issued twice, whatever two phones do simultaneously.
--   · One entry per person per game, matched on lb_phone_norm (partner phones
--     included), any number of games per person. No table cap: tables grow.
--   · Event date and deadline are CONFIG (settings.club_games), editable from
--     the page's admin sheet by `club_games_manage` — not code.
--
-- Personal data stays where the house rule puts it: names and phones live in
-- tables with NO anon read; the page talks through security-definer functions,
-- and the only public reads (stats, bracket) carry names and results — never a
-- phone number. The big screen (games-screen.html) reads exactly that.
--
-- Per the standing rule, running the tournament is its own permission —
-- `club_games_manage` — with role defaults, a row on the user screen, RLS on
-- these tables asking the same key, and its own event in the notification
-- matrix (`club_game_reg`) so organizers pick push/email per person.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 0 · config ──────────────────────────────────────────────────────────────
insert into public.settings (key, value)
values ('club_games', jsonb_build_object(
  'open', true,
  'event_label',    'السبت 12 أيلول — 6:00 مساءً',
  'deadline_label', '11 أيلول',
  'event_ts',       null,          -- ISO timestamp; set from the admin sheet → reminders fire
  'fee_solo', 10, 'fee_board', 5, 'fee_team', 20))
on conflict (key) do nothing;

create or replace function public.club_config()
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce((select value from public.settings where key='club_games'), '{}'::jsonb);
$fn$;
grant execute on function public.club_config() to anon, authenticated;

create or replace function public.club_set_config(p jsonb)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if not public.has_perm('club_games_manage') then
    raise exception 'لا تملك صلاحية إدارة البطولة';
  end if;
  update public.settings set value = value || p, updated_at = now() where key='club_games';
  return public.club_config();
end;
$fn$;
grant execute on function public.club_set_config(jsonb) to authenticated;


-- ── 1 · the registrations ───────────────────────────────────────────────────
create table if not exists public.club_game_regs (
  id          uuid primary key default gen_random_uuid(),
  game        text not null check (game in ('frangieh','mahbouseh','tarneeb','arbaamie')),
  seq         integer not null,                 -- per game, 1-based; a card TEAM is one seq
  table_label text not null,                    -- ف-1 … — ceil(seq/2), two seq per table
  side        integer not null check (side in (1,2)),
  p1_name     text not null,
  p1_phone    text not null,
  p1_norm     text not null,
  p2_name     text,                             -- cards: the partner
  p2_phone    text,
  p2_norm     text,
  own_board   boolean not null default false,   -- tawli only: brought a board → 5$
  fee         integer not null,
  status      text not null default 'registered' check (status in ('registered','cancelled')),
  paid        boolean not null default false,
  attended    boolean,
  created_at  timestamptz not null default now(),
  unique (game, seq)
);
create index if not exists club_regs_game_idx  on public.club_game_regs(game, status);
create index if not exists club_regs_p1_idx    on public.club_game_regs(game, p1_norm);
create index if not exists club_regs_p2_idx    on public.club_game_regs(game, p2_norm);

alter table public.club_game_regs enable row level security;
-- names + phones: staff with the key read and mark paid/attended; nothing anon
drop policy if exists club_regs_read on public.club_game_regs;
create policy club_regs_read on public.club_game_regs
  for select to authenticated using (public.has_perm('club_games_manage'));
drop policy if exists club_regs_update on public.club_game_regs;
create policy club_regs_update on public.club_game_regs
  for update to authenticated
  using (public.has_perm('club_games_manage'))
  with check (public.has_perm('club_games_manage'));


-- ── 2 · the bracket ─────────────────────────────────────────────────────────
create table if not exists public.club_matches (
  id       uuid primary key default gen_random_uuid(),
  game     text not null check (game in ('frangieh','mahbouseh','tarneeb','arbaamie')),
  round    integer not null,          -- 1 = first round; max = the final
  slot     integer not null,          -- position within the round
  best_of  integer not null default 1,
  a_reg    uuid references public.club_game_regs(id) on delete cascade,
  b_reg    uuid references public.club_game_regs(id) on delete cascade,
  a_games  integer not null default 0,
  b_games  integer not null default 0,
  winner   uuid,
  status   text not null default 'pending' check (status in ('pending','live','done','walkover')),
  unique (game, round, slot)
);
alter table public.club_matches enable row level security;
drop policy if exists club_matches_read on public.club_matches;
create policy club_matches_read on public.club_matches
  for select to authenticated using (public.has_perm('club_games_manage'));
-- writes go only through the referee RPCs below

-- game metadata, in one place
create or replace function public.club_game_meta(p_game text)
returns table(prefix text, team boolean, best_of int, label text)
language sql immutable as $fn$
  select v.prefix, v.team, v.best_of, v.label from (values
    ('frangieh',  'ف', false, 3, 'طاولة — فرنجية'),
    ('mahbouseh', 'م', false, 3, 'طاولة — محبوسة'),
    ('tarneeb',   'ط', true,  1, 'ورق — طرنيب'),
    ('arbaamie',  '٤', true,  1, 'ورق — أربعمية (400)')
  ) v(g, prefix, team, best_of, label) where v.g = p_game;
$fn$;


-- ── 3 · registering: the seat is issued like a sanad number ─────────────────
create or replace function public.club_register(
  p_game text, p_name text, p_phone text,
  p_name2 text default null, p_phone2 text default null,
  p_own_board boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  cfg   jsonb := public.club_config();
  m     record;
  n1    text; n2 text;
  v_seq integer; v_tbl text; v_side integer; v_fee integer;
  r     public.club_game_regs%rowtype;
begin
  select * into m from public.club_game_meta(p_game);
  if not found then raise exception 'لعبة غير معروفة'; end if;
  if not coalesce((cfg->>'open')::boolean, true) then
    raise exception 'أُقفل التسجيل — نراكم في البطولة!';
  end if;

  if coalesce(btrim(p_name),'') = '' then raise exception 'الاسم مطلوب'; end if;
  n1 := public.lb_phone_norm(p_phone);
  if coalesce(n1,'') = '' or length(n1) < 7 then raise exception 'رقم الهاتف غير صالح'; end if;

  if m.team then
    if coalesce(btrim(p_name2),'') = '' then raise exception 'اسم الشريك مطلوب'; end if;
    n2 := public.lb_phone_norm(p_phone2);
    if coalesce(n2,'') = '' or length(n2) < 7 then raise exception 'رقم هاتف الشريك غير صالح'; end if;
    if n2 = n1 then raise exception 'رقما اللاعبَين متطابقان'; end if;
  else
    n2 := null;
  end if;

  -- one seat at a time per game: the same lock philosophy as sanad numbering
  perform pg_advisory_xact_lock(hashtext('club_' || p_game));

  if exists (select 1 from public.club_game_regs g
              where g.game = p_game and g.status = 'registered'
                and (g.p1_norm in (n1, n2) or g.p2_norm in (n1, n2))) then
    raise exception 'هذا الرقم مسجّل في هذه اللعبة مسبقاً — التسجيل مرة واحدة لكل لعبة';
  end if;

  select coalesce(max(seq),0) + 1 into v_seq from public.club_game_regs where game = p_game;
  v_tbl  := m.prefix || '-' || ceil(v_seq / 2.0)::int;
  v_side := 2 - (v_seq % 2);
  v_fee  := case when m.team then coalesce((cfg->>'fee_team')::int, 20)
                 when p_own_board then coalesce((cfg->>'fee_board')::int, 5)
                 else coalesce((cfg->>'fee_solo')::int, 10) end;

  insert into public.club_game_regs
    (game, seq, table_label, side, p1_name, p1_phone, p1_norm,
     p2_name, p2_phone, p2_norm, own_board, fee)
  values
    (p_game, v_seq, v_tbl, v_side, btrim(p_name), btrim(p_phone), n1,
     nullif(btrim(coalesce(p_name2,'')),''), nullif(btrim(coalesce(p_phone2,'')),''), n2,
     (not m.team) and coalesce(p_own_board,false), v_fee)
  returning * into r;

  return jsonb_build_object(
    'id', r.id, 'game', r.game, 'label', m.label,
    'table_label', r.table_label, 'side', r.side, 'seq', r.seq,
    'fee', r.fee, 'own_board', r.own_board,
    'waiting', r.side = 1,
    'event_label', cfg->>'event_label');
end;
$fn$;
grant execute on function public.club_register(text,text,text,text,text,boolean) to anon, authenticated;

-- a person's own tickets, by their phone — the coop_buyer_orders pattern
create or replace function public.club_my_regs(p_phone text)
returns table(game text, label text, table_label text, side int, fee int,
              own_board boolean, p1_name text, p2_name text, created_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp as $fn$
  select g.game, m.label, g.table_label, g.side, g.fee, g.own_board,
         g.p1_name, g.p2_name, g.created_at
    from public.club_game_regs g
    cross join lateral public.club_game_meta(g.game) m
   where g.status = 'registered'
     and public.lb_phone_norm(p_phone) <> ''
     and (g.p1_norm = public.lb_phone_norm(p_phone) or g.p2_norm = public.lb_phone_norm(p_phone))
   order by g.created_at;
$fn$;
grant execute on function public.club_my_regs(text) to anon, authenticated;

-- public counters: numbers only
create or replace function public.club_stats()
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(jsonb_object_agg(game, jsonb_build_object(
           'regs', n, 'tables', ceil(n / 2.0)::int)), '{}'::jsonb)
  from (select game, count(*)::int as n
          from public.club_game_regs where status='registered' group by game) t;
$fn$;
grant execute on function public.club_stats() to anon, authenticated;


-- ── 4 · the public bracket: names and results, never a phone ────────────────
create or replace function public.club_bracket(p_game text)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
declare
  v_matches jsonb;
  v_tables  jsonb;
begin
  select jsonb_agg(jsonb_build_object(
           'round', c.round, 'slot', c.slot, 'best_of', c.best_of,
           'a', case when ra.id is null then null else
                jsonb_build_object('name', ra.p1_name || coalesce(' + '||ra.p2_name,''), 'table', ra.table_label) end,
           'b', case when rb.id is null then null else
                jsonb_build_object('name', rb.p1_name || coalesce(' + '||rb.p2_name,''), 'table', rb.table_label) end,
           'a_games', c.a_games, 'b_games', c.b_games,
           'status', c.status,
           'winner_side', case when c.winner is null then null
                               when c.winner = c.a_reg then 'a' else 'b' end)
         order by c.round, c.slot)
    into v_matches
    from public.club_matches c
    left join public.club_game_regs ra on ra.id = c.a_reg
    left join public.club_game_regs rb on rb.id = c.b_reg
   where c.game = p_game;

  if v_matches is not null then
    return jsonb_build_object('stage','bracket','matches',v_matches);
  end if;

  -- before the referee locks the bracket: the tables as they filled up
  select jsonb_agg(jsonb_build_object('table', tl, 'players', ps) order by mn)
    into v_tables
    from (select table_label as tl, min(seq) as mn,
                 jsonb_agg((p1_name || coalesce(' + '||p2_name,'')) order by side) as ps
            from public.club_game_regs
           where game = p_game and status = 'registered'
           group by table_label) t;
  return jsonb_build_object('stage','registration','tables',coalesce(v_tables,'[]'::jsonb));
end;
$fn$;
grant execute on function public.club_bracket(text) to anon, authenticated;


-- ── 5 · the referee: lock, score 2-of-3, walkover ───────────────────────────
create or replace function public.club_generate_bracket(p_game text)
returns integer language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  m      record;
  ids    uuid[];
  n      integer;
  slots  integer;
  rnd    integer := 1;
  i      integer;
  made   integer := 0;
begin
  if not public.has_perm('club_games_manage') then
    raise exception 'لا تملك صلاحية إدارة البطولة';
  end if;
  select * into m from public.club_game_meta(p_game);
  if not found then raise exception 'لعبة غير معروفة'; end if;

  perform pg_advisory_xact_lock(hashtext('club_' || p_game));
  delete from public.club_matches where game = p_game;

  select array_agg(id order by seq) into ids
    from public.club_game_regs where game = p_game and status = 'registered';
  n := coalesce(array_length(ids,1), 0);
  if n < 2 then raise exception 'لا يكفي المسجّلون لإنشاء جدول (%)' , n; end if;

  -- round 1 from the registration pairs; an odd last entrant gets a bye
  slots := ceil(n / 2.0)::int;
  for i in 1..slots loop
    insert into public.club_matches(game, round, slot, best_of, a_reg, b_reg, winner, status)
    values (p_game, 1, i, m.best_of,
            ids[2*i-1],
            case when 2*i <= n then ids[2*i] else null end,
            case when 2*i <= n then null else ids[2*i-1] end,
            case when 2*i <= n then 'pending' else 'done' end);
    made := made + 1;
  end loop;

  -- the upper rounds, empty, down to the final
  while slots > 1 loop
    rnd := rnd + 1;
    slots := ceil(slots / 2.0)::int;
    for i in 1..slots loop
      insert into public.club_matches(game, round, slot, best_of)
      values (p_game, rnd, i, m.best_of);
      made := made + 1;
    end loop;
  end loop;

  -- byes flow upward immediately
  perform public.club__advance(c.id) from public.club_matches c
   where c.game = p_game and c.round = 1 and c.status = 'done';
  return made;
end;
$fn$;
grant execute on function public.club_generate_bracket(text) to authenticated;

-- winner moves into the next round's slot (a on odd slots, b on even)
create or replace function public.club__advance(p_match uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare c public.club_matches%rowtype;
begin
  select * into c from public.club_matches where id = p_match;
  if not found or c.winner is null then return; end if;
  if c.slot % 2 = 1 then
    update public.club_matches set a_reg = c.winner
     where game = c.game and round = c.round + 1 and slot = ceil(c.slot/2.0)::int;
  else
    update public.club_matches set b_reg = c.winner
     where game = c.game and round = c.round + 1 and slot = ceil(c.slot/2.0)::int;
  end if;
end;
$fn$;
revoke execute on function public.club__advance(uuid) from public, anon, authenticated;

create or replace function public.club_match_set(p_match uuid, p_a int, p_b int)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  c      public.club_matches%rowtype;
  nxt    public.club_matches%rowtype;
  needed integer;
begin
  if not public.has_perm('club_games_manage') then
    raise exception 'لا تملك صلاحية إدارة البطولة';
  end if;
  select * into c from public.club_matches where id = p_match for update;
  if not found then raise exception 'المباراة غير موجودة'; end if;
  if c.a_reg is null or c.b_reg is null then raise exception 'المباراة بلا طرفَيها بعد'; end if;

  needed := (c.best_of / 2) + 1;
  if p_a < 0 or p_b < 0 or p_a > needed or p_b > needed or (p_a = needed and p_b = needed) then
    raise exception 'نتيجة غير صالحة (الغالب % من %)', needed, c.best_of;
  end if;

  -- a decided match may be corrected only while its next slot is untouched
  if c.winner is not null then
    select * into nxt from public.club_matches
     where game = c.game and round = c.round + 1 and slot = ceil(c.slot/2.0)::int;
    if found and (nxt.a_games > 0 or nxt.b_games > 0 or nxt.winner is not null) then
      raise exception 'الدور التالي بدأ — لا يمكن تعديل هذه النتيجة';
    end if;
    if found then   -- pull the old winner back out of the next round
      if c.slot % 2 = 1 then update public.club_matches set a_reg = null where id = nxt.id;
      else                   update public.club_matches set b_reg = null where id = nxt.id; end if;
    end if;
  end if;

  update public.club_matches
     set a_games = p_a, b_games = p_b,
         winner = case when p_a = needed then a_reg when p_b = needed then b_reg else null end,
         status = case when p_a = needed or p_b = needed then 'done'
                       when p_a + p_b > 0 then 'live' else 'pending' end
   where id = p_match
   returning * into c;

  if c.winner is not null then perform public.club__advance(c.id); end if;
  return jsonb_build_object('status', c.status, 'a', c.a_games, 'b', c.b_games,
                            'decided', c.winner is not null);
end;
$fn$;
grant execute on function public.club_match_set(uuid,int,int) to authenticated;

-- الغياب: الرسم يبقى مستحقاً وتُحتسب المباراة خسارة — بضغطة واحدة
create or replace function public.club_match_walkover(p_match uuid, p_absent text)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare c public.club_matches%rowtype; v_absent uuid; v_winner uuid;
begin
  if not public.has_perm('club_games_manage') then
    raise exception 'لا تملك صلاحية إدارة البطولة';
  end if;
  if p_absent not in ('a','b') then raise exception 'absent must be a or b'; end if;
  select * into c from public.club_matches where id = p_match for update;
  if not found then raise exception 'المباراة غير موجودة'; end if;
  if c.winner is not null then raise exception 'المباراة محسومة مسبقاً'; end if;
  v_absent := case when p_absent = 'a' then c.a_reg else c.b_reg end;
  v_winner := case when p_absent = 'a' then c.b_reg else c.a_reg end;
  if v_winner is null then raise exception 'لا خصم بعد'; end if;

  update public.club_matches set winner = v_winner, status = 'walkover' where id = p_match;
  update public.club_game_regs set attended = false where id = v_absent;
  perform public.club__advance(p_match);
end;
$fn$;
grant execute on function public.club_match_walkover(uuid,text) to authenticated;


-- ── 6 · who is told (the club's own event in the notification matrix) ───────
-- Organizers = holders of club_games_manage; each picks push/email for the
-- `club_game_reg` event from the same matrix as everything else.
create or replace function public.club_reg_recipients()
returns text[] language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(array_agg(distinct u.email), array[]::text[])
    from public.user_notify_prefs np
    join auth.users u on u.id = np.user_id
   where u.email is not null
     and coalesce((np.channels -> 'club_game_reg' ->> 'email')::boolean, false)
     and public.user_has_perm(np.user_id, 'club_games_manage');
$fn$;
revoke execute on function public.club_reg_recipients() from public, anon, authenticated;
grant  execute on function public.club_reg_recipients() to service_role;

create or replace function public.club_reg_push_targets()
returns text[] language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(array_agg(distinct btrim(np.phone)), array[]::text[])
    from public.user_notify_prefs np
   where coalesce((np.channels -> 'club_game_reg' ->> 'push')::boolean, false)
     and coalesce(btrim(np.phone),'') <> ''
     and public.user_has_perm(np.user_id, 'club_games_manage');
$fn$;
revoke execute on function public.club_reg_push_targets() from public, anon, authenticated;

create or replace function public.club_tg_reg()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  m      record;
  v_who  text;
  v_ph   text;
begin
  select * into m from public.club_game_meta(new.game);
  v_who := new.p1_name || coalesce(' + ' || new.p2_name, '');

  -- the registrant's own confirmation, on the device their phone is linked to
  perform public.push_notify('club_game_reg_confirm',
    '🎟️ تم تسجيلك — بطولة وادي الست',
    m.label || ' · طاولتك ' || new.table_label || ' · الرسم ' || new.fee || '$'
      || case when new.own_board then ' (مع طاولتك)' else '' end,
    'games.html', new.p1_phone);
  if new.p2_phone is not null then
    perform public.push_notify('club_game_reg_confirm',
      '🎟️ تم تسجيل فريقك — بطولة وادي الست',
      m.label || ' · طاولتكم ' || new.table_label || ' · رسم الفريق ' || new.fee || '$',
      'games.html', new.p2_phone);
  end if;

  -- the organizers who switched 🔔 on for this event
  foreach v_ph in array public.club_reg_push_targets() loop
    perform public.push_notify('club_game_reg',
      '🎲 تسجيل جديد في البطولة',
      v_who || ' — ' || m.label || ' · طاولة ' || new.table_label,
      'games.html', v_ph);
  end loop;

  -- and by e-mail, resolved live by the edge function
  perform net.http_post(
    url     := 'https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/notify-club-reg',
    body    := jsonb_build_object('id', new.id),
    params  := '{}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 8000);
  return new;
exception when others then
  -- a notification must never break a registration
  raise warning 'club_tg_reg: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists club_reg_tg on public.club_game_regs;
create trigger club_reg_tg after insert on public.club_game_regs
  for each row execute function public.club_tg_reg();


-- ── 7 · the reminders: day before and hour before, once each ────────────────
create table if not exists public.club_push_sent (
  kind       text not null,          -- tomorrow | one_hour
  phone_norm text not null,
  sent_at    timestamptz not null default now(),
  primary key (kind, phone_norm)
);
alter table public.club_push_sent enable row level security;
drop policy if exists club_push_sent_read on public.club_push_sent;
create policy club_push_sent_read on public.club_push_sent
  for select to authenticated using (public.has_perm('club_games_manage'));

create or replace function public.club_push_sweep()
returns integer language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_ts   timestamptz;
  v_kind text;
  rec    record;
  n      integer := 0;
  cfg    jsonb := public.club_config();
begin
  begin v_ts := nullif(cfg->>'event_ts','')::timestamptz; exception when others then v_ts := null; end;
  if v_ts is null then return 0; end if;

  v_kind := case
    when v_ts - now() between interval '20 hours' and interval '24 hours' then 'tomorrow'
    when v_ts - now() between interval '45 minutes' and interval '75 minutes' then 'one_hour'
    else null end;
  if v_kind is null then return 0; end if;

  for rec in
    select distinct on (norm) norm, phone, who, tbl, lbl from (
      select g.p1_norm as norm, g.p1_phone as phone, g.p1_name as who,
             g.table_label as tbl, m.label as lbl
        from public.club_game_regs g cross join lateral public.club_game_meta(g.game) m
       where g.status = 'registered'
      union all
      select g.p2_norm, g.p2_phone, g.p2_name, g.table_label, m.label
        from public.club_game_regs g cross join lateral public.club_game_meta(g.game) m
       where g.status = 'registered' and g.p2_norm is not null
    ) t order by norm
  loop
    begin
      insert into public.club_push_sent(kind, phone_norm) values (v_kind, rec.norm);
    exception when unique_violation then continue; end;
    perform public.push_notify('club_game_' || v_kind,
      case v_kind when 'tomorrow' then '🎲 البطولة غداً!' else '⏰ البطولة تبدأ بعد ساعة' end,
      rec.who || '، موعدنا ' || coalesce(cfg->>'event_label','قريباً') || ' — طاولتك ' || rec.tbl
        || '. الغياب لا يُسقط الرسم وتُحتسب المباريات خسارة.',
      'games.html', rec.phone);
    n := n + 1;
  end loop;
  return n;
end;
$fn$;
revoke execute on function public.club_push_sweep() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'club-push-sweep') then
    perform cron.unschedule('club-push-sweep');
  end if;
  perform cron.schedule('club-push-sweep', '*/15 * * * *',
                        $c$select public.club_push_sweep()$c$);
end $$;


-- ── 8 · the permission ──────────────────────────────────────────────────────
-- Running the club tournament — dates, registrations, the bracket, the money
-- list — is its own authority, not a reuse of anything municipal.
update public.role_permissions
   set perms = perms || '{"club_games_manage":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"club_games_manage":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');
