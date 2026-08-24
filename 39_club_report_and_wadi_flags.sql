-- ═══════════════════════════════════════════════════════════════════════════
-- 39 — التسجيل يحفظ جواب «هل أنت من وادي الست؟»، والتقرير يقرأه
--
-- The admin sheet gains a 📊 report: how many players, how many attended, how
-- many are from Wadi El Sitt and how many from outside, and the money — due
-- and collected, in dollars. "From Wadi El Sitt" is recorded per PLAYER at
-- registration: found in the dalil counts as yes, otherwise it is the answer
-- the person gave the popup; no answer stays null and reports as غير محدد.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.club_game_regs add column if not exists p1_from_wadi boolean;
alter table public.club_game_regs add column if not exists p2_from_wadi boolean;

drop function if exists public.club_register(text,text,text,text,text,boolean,text,text,text);

create or replace function public.club_register(
  p_game text, p_name text, p_phone text,
  p_name2 text default null, p_phone2 text default null,
  p_own_board boolean default false,
  p_team_name text default null,
  p_photo text default null, p_photo2 text default null,
  p_from_wadi boolean default null, p_from_wadi2 boolean default null)
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
     team_name, p1_photo, p2_photo, p1_from_wadi, p2_from_wadi)
  values
    (p_game, v_seq, v_tbl, v_side, btrim(p_name), btrim(p_phone), n1,
     nullif(btrim(coalesce(p_name2,'')),''), nullif(btrim(coalesce(p_phone2,'')),''), n2,
     (not m.team) and coalesce(p_own_board,false), v_fee,
     case when m.team then nullif(btrim(coalesce(p_team_name,'')),'') end,
     nullif(btrim(coalesce(p_photo,'')),''), nullif(btrim(coalesce(p_photo2,'')),''),
     p_from_wadi, case when m.team then p_from_wadi2 end)
  returning * into r;

  return jsonb_build_object(
    'id', r.id, 'game', r.game, 'label', m.label,
    'table_label', r.table_label, 'side', r.side, 'seq', r.seq,
    'fee', r.fee, 'own_board', r.own_board, 'team_name', r.team_name,
    'waiting', r.side = 1,
    'event_label', cfg->>'event_label');
end;
$fn$;
grant execute on function public.club_register(text,text,text,text,text,boolean,text,text,text,boolean,boolean) to anon, authenticated;
