-- ═══════════════════════════════════════════════════════════════════════════
-- 44 — اسم الفريق بيد أصحابه، وكل تصحيح آخر بيد الإدارة
--
-- Two edit paths, deliberately unequal:
--   · A PARTICIPANT, identified the way تسجيلاتي always identified them —
--     their phone — may do exactly one thing: add or change THEIR card
--     team's name. Nothing else: not players, not phones, not fees.
--     club_team_name_set() verifies the registration belongs to that phone
--     and that the game is a team game, in the database, not the browser.
--   · The ADMIN (club_games_manage, the tournament key) corrects whatever
--     needs correcting from the 🛠️ panel: player names, phones, team name.
--     club_reg_admin_update() recomputes the phone norms and re-checks the
--     one-entry-per-person rule, so a corrected phone can never duplicate
--     an existing registration.
--
-- club_my_regs gains the row id — تسجيلاتي needs it to say WHICH team to
-- rename. Names and phones still go only to the person whose phone matches.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0 · تسجيلاتي تعيد المعرّف ────────────────────────────────────────────────
drop function if exists public.club_my_regs(text);
create or replace function public.club_my_regs(p_phone text)
returns table(id uuid, game text, label text, table_label text, side int, fee int,
              own_board boolean, team_name text, p1_name text, p2_name text, created_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp as $fn$
  select g.id, g.game, m.label, g.table_label, g.side, g.fee, g.own_board,
         g.team_name, g.p1_name, g.p2_name, g.created_at
    from public.club_game_regs g
    cross join lateral public.club_game_meta(g.game) m
   where g.status = 'registered'
     and public.lb_phone_norm(p_phone) <> ''
     and (g.p1_norm = public.lb_phone_norm(p_phone) or g.p2_norm = public.lb_phone_norm(p_phone))
   order by g.created_at;
$fn$;
grant execute on function public.club_my_regs(text) to anon, authenticated;

-- ── 1 · المشارك يسمّي فريقه — فقط ───────────────────────────────────────────
create or replace function public.club_team_name_set(p_phone text, p_reg uuid, p_name text)
returns text language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_norm text := public.lb_phone_norm(p_phone);
  v_reg  public.club_game_regs%rowtype;
  v_team boolean;
  v_name text := nullif(btrim(coalesce(p_name,'')), '');
begin
  if v_norm = '' then
    raise exception 'رقم الهاتف غير صالح';
  end if;
  select * into v_reg from public.club_game_regs
   where id = p_reg and status = 'registered'
     and (p1_norm = v_norm or p2_norm = v_norm)
   for update;
  if not found then
    raise exception 'هذا التسجيل ليس لرقمك';
  end if;
  select m.team into v_team from public.club_game_meta(v_reg.game) m;
  if not coalesce(v_team, false) then
    raise exception 'اسم الفريق للعبات الورق فقط';
  end if;
  if v_name is not null and length(v_name) > 40 then
    raise exception 'اسم الفريق طويل — 40 حرفاً كحدّ أقصى';
  end if;
  update public.club_game_regs set team_name = v_name where id = p_reg;
  return coalesce(v_name, '');
end;
$fn$;
grant execute on function public.club_team_name_set(text, uuid, text) to anon, authenticated;

-- ── 2 · الإدارة تصحّح ما يلزم — خلف مفتاح البطولة ───────────────────────────
create or replace function public.club_reg_admin_update(p_reg uuid, p jsonb)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_reg      public.club_game_regs%rowtype;
  v_p1_name  text;
  v_p2_name  text;
  v_p1_phone text;
  v_p2_phone text;
  v_p1_norm  text;
  v_p2_norm  text;
  v_team     text;
begin
  if not public.has_perm('club_games_manage') then
    raise exception 'لا تملك صلاحية إدارة البطولة';
  end if;
  select * into v_reg from public.club_game_regs where id = p_reg for update;
  if not found then
    raise exception 'التسجيل غير موجود';
  end if;

  v_p1_name  := coalesce(nullif(btrim(p->>'p1_name'),''),  v_reg.p1_name);
  v_p2_name  := case when p ? 'p2_name'
                     then coalesce(nullif(btrim(p->>'p2_name'),''), v_reg.p2_name)
                     else v_reg.p2_name end;
  v_p1_phone := coalesce(nullif(btrim(p->>'p1_phone'),''), v_reg.p1_phone);
  v_p2_phone := case when p ? 'p2_phone'
                     then coalesce(nullif(btrim(p->>'p2_phone'),''), v_reg.p2_phone)
                     else v_reg.p2_phone end;
  v_team     := case when p ? 'team_name'
                     then nullif(btrim(p->>'team_name'),'')
                     else v_reg.team_name end;

  v_p1_norm := public.lb_phone_norm(v_p1_phone);
  if v_p1_norm = '' then raise exception 'رقم اللاعب الأول غير صالح'; end if;
  if v_p2_phone is not null then
    v_p2_norm := public.lb_phone_norm(v_p2_phone);
    if v_p2_norm = '' then raise exception 'رقم اللاعب الثاني غير صالح'; end if;
  end if;

  -- القاعدة التي فرضها التسجيل تبقى بعد التصحيح: شخص واحد، تسجيل واحد، لكل لعبة
  if exists (select 1 from public.club_game_regs g
              where g.game = v_reg.game and g.status = 'registered' and g.id <> p_reg
                and (g.p1_norm in (v_p1_norm, v_p2_norm) or g.p2_norm in (v_p1_norm, v_p2_norm)))
  then
    raise exception 'الرقم مسجّل مسبقاً في هذه اللعبة باسم آخر';
  end if;

  update public.club_game_regs
     set p1_name = v_p1_name, p2_name = v_p2_name,
         p1_phone = v_p1_phone, p2_phone = v_p2_phone,
         p1_norm = v_p1_norm, p2_norm = v_p2_norm,
         team_name = v_team
   where id = p_reg;

  return jsonb_build_object('ok', true, 'p1_name', v_p1_name, 'p2_name', v_p2_name,
                            'p1_phone', v_p1_phone, 'p2_phone', v_p2_phone, 'team_name', v_team);
end;
$fn$;
grant execute on function public.club_reg_admin_update(uuid, jsonb) to authenticated;
