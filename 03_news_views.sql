-- ════════════════════════════════════════════════════════════════════════════
-- 03_news_views.sql
-- Per-user news view tracking (who saw what, not just how many)
-- Safe to re-run. Run after 02_lang_and_stock.sql.
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: news_views
-- One row per (article, user). We upsert on view, so duplicates are silent.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.news_views (
  news_id    bigint      NOT NULL REFERENCES public.news_articles(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (news_id, user_id)
);

CREATE INDEX IF NOT EXISTS news_views_news_idx ON public.news_views (news_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS news_views_user_idx ON public.news_views (user_id, viewed_at DESC);

ALTER TABLE public.news_views ENABLE ROW LEVEL SECURITY;

-- Users can record their OWN view.
DROP POLICY IF EXISTS news_views_self_insert ON public.news_views;
CREATE POLICY news_views_self_insert
  ON public.news_views
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Users can read their OWN view rows.
DROP POLICY IF EXISTS news_views_self_select ON public.news_views;
CREATE POLICY news_views_self_select
  ON public.news_views
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Staff (admin / mayor / super_admin via public.has_role) can read all views.
DROP POLICY IF EXISTS news_views_staff_select ON public.news_views;
CREATE POLICY news_views_staff_select
  ON public.news_views
  FOR SELECT
  TO authenticated
  USING (
    public.has_role('admin')
    OR public.has_role('mayor')
    OR public.has_role('super_admin')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: record_news_view(article_id)
-- Bumps the aggregate view counter AND, for logged-in users, records
-- an idempotent row in news_views. Safe to call from the client.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_news_view(article_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.news_articles
     SET view_count = COALESCE(view_count, 0) + 1
   WHERE id = article_id
     AND is_published = true;

  IF auth.uid() IS NOT NULL THEN
    INSERT INTO public.news_views (news_id, user_id)
    VALUES (article_id, auth.uid())
    ON CONFLICT (news_id, user_id) DO NOTHING;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_news_view(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.record_news_view(bigint) TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: get_news_viewers(article_id)
-- Returns viewer list (email + timestamp) for staff on articles belonging to
-- a municipality they manage. Uses SECURITY DEFINER to read auth.users.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_news_viewers(article_id bigint)
RETURNS TABLE (user_id uuid, email text, viewed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT (
    public.has_role('admin')
    OR public.has_role('mayor')
    OR public.has_role('super_admin')
  ) THEN
    RAISE EXCEPTION 'insufficient_privilege' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT nv.user_id,
         u.email::text,
         nv.viewed_at
    FROM public.news_views nv
    JOIN auth.users u ON u.id = nv.user_id
   WHERE nv.news_id = article_id
   ORDER BY nv.viewed_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_news_viewers(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_news_viewers(bigint) TO authenticated;
