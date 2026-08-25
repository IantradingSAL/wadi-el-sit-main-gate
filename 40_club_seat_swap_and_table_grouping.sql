-- ═══════════════════════════════════════════════════════════════════════════
-- 40 — طاولة واحدة تجمع لاعبَيها، والحكم يبدّل المقاعد قبل انطلاق البطولة
--
-- كان لاعبان على الطاولة نفسها يظهران في بطاقتين لأن `table_label` انجرف
-- شكله عبر النسخ («ف1» مقابل «ف-1»)، و club_bracket كان يجمّع على النص الحرفي.
-- الآن يُجمّع على رقم الطاولة المشتقّ من التسلسل (ceil(seq/2)) فلا يفرّقهما أي
-- اختلاف في الشكل، والتسمية المعروضة تُبنى من البادئة الحالية.
--
-- كما يضيف club_seat_swap: نقل/تبديل لاعب أو فريق بين طاولتين — قبل إنشاء
-- الجدول فقط — بيد من يملك club_games_manage.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · إصلاح الانجراف: توحيد التسمية والجهة للألعاب التي لم يُنشأ جدولها بعد ──
update public.club_game_regs r
   set table_label = (select m.prefix from public.club_game_meta(r.game) m) || ceil(r.seq / 2.0)::int,
       side        = case when r.seq % 2 = 1 then 1 else 2 end
 where r.status = 'registered'
   and not exists (select 1 from public.club_matches c where c.game = r.game);

-- ── 2 · التجميع على رقم الطاولة، لا على النص ──────────────────────────────────
create or replace function public.club_bracket(p_game text)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $function$
declare
  v_matches jsonb;
  v_tables  jsonb;
  v_prefix  text;
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

  select m.prefix into v_prefix from public.club_game_meta(p_game) m;

  -- طاولة = كل مقعدين متتاليين (ceil(seq/2))، فيجتمع اللاعبان مهما اختلف نص التسمية
  select jsonb_agg(jsonb_build_object('table', coalesce(v_prefix,'') || tno, 'players', ps) order by tno)
    into v_tables
    from (
      select ceil(seq / 2.0)::int as tno,
             jsonb_agg(coalesce(team_name, p1_name || coalesce(' + '||p2_name,'')) order by side, seq) as ps
        from public.club_game_regs
       where game = p_game and status = 'registered'
       group by ceil(seq / 2.0)::int
    ) t;
  return jsonb_build_object('stage','registration','tables',coalesce(v_tables,'[]'::jsonb));
end;
$function$;

-- ── 3 · تبديل مقعدَي لاعبَين/فريقَين قبل إنشاء الجدول ─────────────────────────
create or replace function public.club_seat_swap(p_game text, p_a uuid, p_b uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare a public.club_game_regs%rowtype; b public.club_game_regs%rowtype;
begin
  if not public.has_perm('club_games_manage') then
    return jsonb_build_object('ok', false, 'error', 'لا صلاحية لإدارة البطولة');
  end if;
  if p_a = p_b then
    return jsonb_build_object('ok', false, 'error', 'اختر تسجيلَين مختلفَين');
  end if;
  if exists (select 1 from public.club_matches c where c.game = p_game) then
    return jsonb_build_object('ok', false, 'error', 'لا يمكن تبديل المقاعد بعد إنشاء الجدول');
  end if;

  perform pg_advisory_xact_lock(hashtext('club_' || p_game));

  select * into a from public.club_game_regs where id = p_a and game = p_game and status = 'registered';
  select * into b from public.club_game_regs where id = p_b and game = p_game and status = 'registered';
  if a.id is null or b.id is null then
    return jsonb_build_object('ok', false, 'error', 'تسجيل غير موجود');
  end if;

  -- ثلاث خطوات لتفادي كسر قيد unique(game,seq): إيقاف a مؤقتاً على تسلسل سالب
  update public.club_game_regs set seq = -a.seq where id = a.id;
  update public.club_game_regs set seq = a.seq, table_label = a.table_label, side = a.side where id = b.id;
  update public.club_game_regs set seq = b.seq, table_label = b.table_label, side = b.side where id = a.id;

  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$fn$;
revoke execute on function public.club_seat_swap(text,uuid,uuid) from public, anon;
grant  execute on function public.club_seat_swap(text,uuid,uuid) to authenticated;
