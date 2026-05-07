-- ═══════════════════════════════════════════════════════════════════
-- 🔔 PUSH SUBSCRIPTIONS — ضمان الأعمدة لربط الاشتراك بهويّة المستخدم
-- ═══════════════════════════════════════════════════════════════════

-- إضافة الأعمدة (idempotent)
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS user_phone TEXT;
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS user_name TEXT;
ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS user_role TEXT DEFAULT 'citizen';

-- index على user_phone لتسريع البحث
CREATE INDEX IF NOT EXISTS idx_push_user_phone ON push_subscriptions(user_phone);

-- RLS — السماح بالـ PATCH من anon (لتحديث الاسم بعد الاشتراك)
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone_read_subs" ON push_subscriptions;
CREATE POLICY "anyone_read_subs" ON push_subscriptions
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anyone_insert_subs" ON push_subscriptions;
CREATE POLICY "anyone_insert_subs" ON push_subscriptions
  FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "anyone_update_subs" ON push_subscriptions;
CREATE POLICY "anyone_update_subs" ON push_subscriptions
  FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anyone_delete_subs" ON push_subscriptions;
CREATE POLICY "anyone_delete_subs" ON push_subscriptions
  FOR DELETE TO anon, authenticated USING (true);

-- ─── (اختياري) حذف الاشتراكات القديمة المجهولة الهويّة ───
-- لتجبر المستخدمين على إعادة الاشتراك مع تسجيل اسمهم تلقائياً
-- DELETE FROM push_subscriptions WHERE user_name IS NULL OR user_name = '';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ التحقّق
-- ═══════════════════════════════════════════════════════════════════

SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'push_subscriptions' ORDER BY ordinal_position;

SELECT 
  COUNT(*) AS total,
  COUNT(user_name) AS with_name,
  COUNT(*) - COUNT(user_name) AS anonymous
FROM push_subscriptions;

-- ═══════════════════════════════════════════════════════════════════
-- 🎯 ملاحظات:
-- 1. الاشتراكات الموجودة بدون اسم ستُحدَّث تلقائياً عند فتح المستخدم 
--    للموقع التالي (autoLink ستشغّل linkToUser تلقائياً)
-- 2. إذا أردت تنظيف بيانات قديمة فوراً، أزل التعليق عن DELETE أعلاه
-- ═══════════════════════════════════════════════════════════════════
