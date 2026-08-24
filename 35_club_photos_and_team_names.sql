-- ═══════════════════════════════════════════════════════════════════════════
-- 35 — صورة اختيارية مع التسجيل، واسم فريق للورق
--
-- Two asks from the club, minutes after 34: a registrant may attach a photo —
-- with the notice, shown AT registration, that winners' photos will be
-- published on the club's social media — and a card team may pick a team name
-- that the bracket does the big screen show instead of "لاعب + لاعب".
--
-- The photos follow the house rule for personal data: a PRIVATE bucket
-- (`club-photos`, 5MB, images only). Anyone may upload — registration is
-- public — but only `club_games_manage` may read, through signed URLs from
-- the admin sheet. Nothing is public until the club itself posts it on its
-- own pages, which is exactly what the consent line says.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.club_game_regs add column if not exists team_name text;
alter table public.club_game_regs add column if not exists p1_photo text;
alter table public.club_game_regs add column if not exists p2_photo text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('club-photos','club-photos', false, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists club_photos_upload on storage.objects;
create policy club_photos_upload on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'club-photos');

drop policy if exists club_photos_read on storage.objects;
create policy club_photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'club-photos' and public.has_perm('club_games_manage'));

-- one registration function: the old signature goes, the new one carries the
-- team name and the photo paths
drop function if exists public.club_register(text,text,text,text,text,boolean);

create or replace function public.club_register(
  p_game text, p_name text, p_phone text,
  p_name2 text default null, p_phone2 text default null,
  p_own_board boolean default false,
  p_team_name text default null,
  p_photo text default null, p_photo2 text default null)
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
     p2_name, p2_phone, p2_norm, own_board, fee,
     team_name, p1_photo, p2_photo)
  values
    (p_game, v_seq, v_tbl, v_side, btrim(p_name), btrim(p_phone), n1,
     nullif(btrim(coalesce(p_name2,'')),''), nullif(btrim(coalesce(p_phone2,'')),''), n2,
     (not m.team) and coalesce(p_own_board,false), v_fee,
     case when m.team then nullif(btrim(coalesce(p_team_name,'')),'') end,
     nullif(btrim(coalesce(p_photo,'')),''), nullif(btrim(coalesce(p_photo2,'')),''))
  returning * into r;

  return jsonb_build_object(
    'id', r.id, 'game', r.game, 'label', m.label,
    'table_label', r.table_label, 'side', r.side, 'seq', r.seq,
    'fee', r.fee, 'own_board', r.own_board, 'team_name', r.team_name,
    'waiting', r.side = 1,
    'event_label', cfg->>'event_label');
end;
$fn$;
grant execute on function public.club_register(text,text,text,text,text,boolean,text,text,text) to anon, authenticated;

-- الفريق يظهر باسمه إن اختار واحداً، وإلا باسمَي لاعبَيه
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
                jsonb_build_object('name', coalesce(ra.team_name, ra.p1_name || coalesce(' + '||ra.p2_name,'')), 'table', ra.table_label) end,
           'b', case when rb.id is null then null else
                jsonb_build_object('name', coalesce(rb.team_name, rb.p1_name || coalesce(' + '||rb.p2_name,'')), 'table', rb.table_label) end,
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

  select jsonb_agg(jsonb_build_object('table', tl, 'players', ps) order by mn)
    into v_tables
    from (select table_label as tl, min(seq) as mn,
                 jsonb_agg(coalesce(team_name, p1_name || coalesce(' + '||p2_name,'')) order by side) as ps
            from public.club_game_regs
           where game = p_game and status = 'registered'
           group by table_label) t;
  return jsonb_build_object('stage','registration','tables',coalesce(v_tables,'[]'::jsonb));
end;
$fn$;
grant execute on function public.club_bracket(text) to anon, authenticated;

drop function if exists public.club_my_regs(text);
create or replace function public.club_my_regs(p_phone text)
returns table(game text, label text, table_label text, side int, fee int,
              own_board boolean, team_name text, p1_name text, p2_name text, created_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp as $fn$
  select g.game, m.label, g.table_label, g.side, g.fee, g.own_board,
         g.team_name, g.p1_name, g.p2_name, g.created_at
    from public.club_game_regs g
    cross join lateral public.club_game_meta(g.game) m
   where g.status = 'registered'
     and public.lb_phone_norm(p_phone) <> ''
     and (g.p1_norm = public.lb_phone_norm(p_phone) or g.p2_norm = public.lb_phone_norm(p_phone))
   order by g.created_at;
$fn$;
grant execute on function public.club_my_regs(text) to anon, authenticated;
