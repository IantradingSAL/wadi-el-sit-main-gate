-- 42 — بطولة وادي الست: مسح بيانات التجربة قبل النشر العلني (2026-09-02)
--
-- كل التسجيلات المخزّنة كانت تجارب داخلية (10 تسجيلات، 24–29 آب: فرنجية 5،
-- أربعمية 2، طرنيب 2، محبوسة 1) وصورتان في club-photos. لا bracket مولّد
-- (club_matches فارغ) ولا تذكيرات مُرسلة (club_push_sent فارغ) — حُذفا احتياطاً.
-- بعد المسح يبدأ ترقيم المقاعد من 1 لكل لعبة.
--
-- طُبّق على المشروع الحي يدوياً؛ هذا الملف هو السجل. آمن لإعادة التطبيق فقط
-- قبل فتح التسجيل الحقيقي — لا تشغّله بعد ذلك.

begin;

delete from public.club_matches;
delete from public.club_push_sent;
delete from public.club_game_regs;

-- صور التسجيل التجريبية: storage.objects محمي من DELETE المباشر
-- (storage.protect_delete)، والمفتاح الموثّق في الدالة نفسها يرفعه لهذه الجلسة.
set local "storage.allow_delete_query" = 'true';
delete from storage.objects where bucket_id = 'club-photos';

commit;
