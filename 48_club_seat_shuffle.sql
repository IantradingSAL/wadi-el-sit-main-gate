-- ═══════════════════════════════════════════════════════════════════════════
-- 48 — 🎲 القرعة العشوائية: النظام يوزّع الطاولات بنفسه قبل إنشاء الجدول
--
-- الترتيب الافتراضي هو ترتيب التسجيل، فمن سجّل بعدك مباشرة صار خصمك. القرعة
-- تعيد توزيع كل المقاعد عشوائياً بضغطة واحدة — أمام الجميع على شاشة القاعة —
-- فلا يقال إن أحداً اختار خصمه. تبديل المقاعد اليدوي (40) يبقى متاحاً بعدها
-- للمس الأخير، وكلاهما يُرفض بعد إنشاء الجدول.
--
-- تُبادَل قيم seq الموجودة نفسها بين المسجّلين (لا ترقيم من جديد): قيد
-- unique(game,seq) لا يصطدم بتسلسل تسجيل ملغى، وتقسيم الطاولات لا يتغيّر —
-- يتغيّر فقط مَن يجلس أين.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.club_seat_shuffle(p_game text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_prefix text;
  v_n      integer;
begin
  if not public.has_perm('club_games_manage') then
    return jsonb_build_object('ok', false, 'error', 'لا صلاحية لإدارة البطولة');
  end if;
  select m.prefix into v_prefix from public.club_game_meta(p_game) m;
  if v_prefix is null then
    return jsonb_build_object('ok', false, 'error', 'لعبة غير معروفة');
  end if;
  if exists (select 1 from public.club_matches c where c.game = p_game) then
    return jsonb_build_object('ok', false, 'error', 'لا قرعة بعد إنشاء الجدول');
  end if;

  perform pg_advisory_xact_lock(hashtext('club_' || p_game));

  -- تحرير التسلسلات مؤقتاً على قيم سالبة كي لا يكسر التبادل قيد unique(game,seq)
  update public.club_game_regs
     set seq = -seq
   where game = p_game and status = 'registered';

  with mine as (
    select id, -seq as old_seq
      from public.club_game_regs
     where game = p_game and status = 'registered'
  ), perm as (
    -- كل تسجيل يأخذ واحدة من قيم seq القائمة نفسها، بترتيب عشوائي
    select shuffled.id, seqs.old_seq as new_seq
      from (select id, row_number() over (order by random()) rn from mine) shuffled
      join (select old_seq, row_number() over (order by old_seq) rn from mine) seqs
        using (rn)
  )
  update public.club_game_regs r
     set seq         = p.new_seq,
         table_label = v_prefix || ceil(p.new_seq / 2.0)::int,
         side        = case when p.new_seq % 2 = 1 then 1 else 2 end
    from perm p
   where r.id = p.id;
  get diagnostics v_n = row_count;

  if v_n < 2 then
    return jsonb_build_object('ok', false, 'error', 'لا يكفي مسجّل واحد لقرعة');
  end if;
  return jsonb_build_object('ok', true, 'count', v_n);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$fn$;
revoke execute on function public.club_seat_shuffle(text) from public, anon;
grant  execute on function public.club_seat_shuffle(text) to authenticated;
