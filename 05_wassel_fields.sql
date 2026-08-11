-- ═══════════════════════════════════════════════════════════════════
-- 📄 صندوق البلدية — إضافة حقول الوصل (Wassel)
-- ═══════════════════════════════════════════════════════════════════
--
-- السند (sanad) يُنشأ فور تسجيل الحركة، أما الوصل (wassel) فيُعطى
-- للدافع/المستفيد لاحقاً بشكل يدوي، لذا يُخزَّن رقمه وتاريخه
-- في حقلين منفصلين قد يُملآن لاحقاً من الشاشة نفسها.
--
-- Idempotent — يمكن تشغيلها أكثر من مرة بأمان.

ALTER TABLE public.baladieh_finance
  ADD COLUMN IF NOT EXISTS wassel_number TEXT,
  ADD COLUMN IF NOT EXISTS wassel_date   DATE;

-- فهرس على رقم الوصل لتسريع البحث والتقارير "بدون وصل"
CREATE INDEX IF NOT EXISTS baladieh_finance_wassel_number_idx
  ON public.baladieh_finance (wassel_number)
  WHERE wassel_number IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ التحقّق
-- ═══════════════════════════════════════════════════════════════════

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'baladieh_finance'
  AND column_name IN ('wassel_number','wassel_date')
ORDER BY column_name;

SELECT
  COUNT(*)                                        AS total_entries,
  COUNT(wassel_number)                            AS with_wassel_no,
  COUNT(*) FILTER (WHERE wassel_number IS NULL)   AS without_wassel_no
FROM public.baladieh_finance;
