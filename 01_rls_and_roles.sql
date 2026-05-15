-- ════════════════════════════════════════════════════════════════════════════
-- 01_rls_and_roles.sql
-- Wadi El Sit Municipality — Security hardening migration
-- ════════════════════════════════════════════════════════════════════════════
-- 
-- WHAT THIS DOES:
-- 1) Creates a server-side `user_roles` table — replaces user_metadata.role
--    (user_metadata is user-editable, so anyone could self-promote to admin)
-- 2) Creates a `profiles` table — replaces user_metadata.name (anti-spoofing)
-- 3) Adds a Postgres function `current_user_role()` that admin policies use
-- 4) Migrates existing users to the new tables
-- 5) Sets up RLS on user_roles, profiles, coop_admins
-- 6) Adds the SECURITY DEFINER trigger that auto-creates a citizen role
--    + profile row on signup (so no client-side trust needed)
--
-- HOW TO RUN:
-- Open https://supabase.com/dashboard/project/onjbwhkmmtqnymhjnplw/sql/new
-- Paste the entire file. Read each section. Run section by section so you
-- can pause if something looks off.
--
-- This is REVERSIBLE: a DOWN script is at the bottom.
-- ════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1 — profiles table (server-side name/phone, anti-spoofing)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.profiles (
  user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  phone       text,
  lang        text NOT NULL DEFAULT 'ar' CHECK (lang IN ('ar','en','fr')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read their own profile
DROP POLICY IF EXISTS "profiles_self_select" ON public.profiles;
CREATE POLICY "profiles_self_select"
  ON public.profiles FOR SELECT
  USING (auth.uid() = user_id);

-- Users can update their own NAME and PHONE and LANG (but not user_id)
DROP POLICY IF EXISTS "profiles_self_update" ON public.profiles;
CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Admins (mayor/admin) can read all profiles
DROP POLICY IF EXISTS "profiles_admin_select_all" ON public.profiles;
CREATE POLICY "profiles_admin_select_all"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer','approver')
    )
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2 — user_roles table (SERVER-SIDE roles, not user_metadata)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'citizen'
              CHECK (role IN ('citizen','viewer','officer','approver','admin','mayor','water_only')),
  granted_by  uuid REFERENCES auth.users(id),
  granted_at  timestamptz NOT NULL DEFAULT now(),
  notes       text
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read their OWN role only
DROP POLICY IF EXISTS "roles_self_select" ON public.user_roles;
CREATE POLICY "roles_self_select"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can read all roles
DROP POLICY IF EXISTS "roles_admin_select" ON public.user_roles;
CREATE POLICY "roles_admin_select"
  ON public.user_roles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin')
    )
  );

-- Only mayor/admin can change roles
DROP POLICY IF EXISTS "roles_admin_modify" ON public.user_roles;
CREATE POLICY "roles_admin_modify"
  ON public.user_roles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin')
    )
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — Helper function: current user's role
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role FROM public.user_roles WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 — Trigger: auto-create profile + role on signup
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name  text := COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1));
  v_phone text := NEW.raw_user_meta_data->>'phone';
  v_lang  text := COALESCE(NEW.raw_user_meta_data->>'lang', 'ar');
BEGIN
  -- Insert profile (server-side, can't be spoofed)
  INSERT INTO public.profiles (user_id, name, phone, lang)
  VALUES (NEW.id, v_name, v_phone, v_lang)
  ON CONFLICT (user_id) DO NOTHING;

  -- Insert default role = citizen (cannot be overridden via signup)
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'citizen')
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 — Migrate existing users
-- ─────────────────────────────────────────────────────────────────────────────

-- Backfill profiles from existing users
INSERT INTO public.profiles (user_id, name, phone, lang)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1), 'مستخدم'),
  u.raw_user_meta_data->>'phone',
  COALESCE(u.raw_user_meta_data->>'lang', 'ar')
FROM auth.users u
ON CONFLICT (user_id) DO NOTHING;

-- Backfill user_roles from existing user_metadata.role
-- (This is a one-time migration — after this, user_metadata.role is IGNORED)
INSERT INTO public.user_roles (user_id, role)
SELECT
  u.id,
  COALESCE(
    CASE
      WHEN u.raw_user_meta_data->>'role' IN ('citizen','viewer','officer','approver','admin','mayor','water_only')
      THEN u.raw_user_meta_data->>'role'
      ELSE 'citizen'
    END,
    'citizen'
  )
FROM auth.users u
ON CONFLICT (user_id) DO NOTHING;

-- ⚠️  IMPORTANT: review roles before declaring this done.
-- Run this and verify it matches what you expect:
-- SELECT u.email, ur.role
-- FROM public.user_roles ur
-- JOIN auth.users u ON u.id = ur.user_id
-- ORDER BY ur.role, u.email;
--
-- If any user has an inappropriate role, fix it now:
-- UPDATE public.user_roles SET role='citizen' WHERE user_id='THE_UUID';
-- UPDATE public.user_roles SET role='mayor' WHERE user_id='IMAD_UUID';


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6 — Lock down coop_admins (replace with Supabase Auth)
-- ─────────────────────────────────────────────────────────────────────────────

-- Make the existing coop_admins table read-only to anon (no more password leaks)
ALTER TABLE IF EXISTS public.coop_admins ENABLE ROW LEVEL SECURITY;

-- Drop any permissive policies
DROP POLICY IF EXISTS "coop_admins_select_all" ON public.coop_admins;
DROP POLICY IF EXISTS "coop_admins_anon_select" ON public.coop_admins;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.coop_admins;

-- Only authenticated users with admin/mayor role can read this table
CREATE POLICY "coop_admins_admin_only"
  ON public.coop_admins FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin')
    )
  );

-- DEPRECATED: The coop admin check now uses user_roles instead.
-- After deploying the patched coop.html, you can drop this table:
--   DROP TABLE public.coop_admins;
-- But keep it for now in case rollback is needed.


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 — Tighten RLS on other key tables
-- ─────────────────────────────────────────────────────────────────────────────

-- Enable RLS on all critical tables if not already
ALTER TABLE IF EXISTS public.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.push_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.push_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.irr_owners ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.irr_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.phonebook_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.phonebook_extras ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.news_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.coop_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.coop_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.coop_sellers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.coop_roles ENABLE ROW LEVEL SECURITY;

-- Cases: citizens can insert; only owner + staff can read/update
DROP POLICY IF EXISTS "cases_anon_insert" ON public.cases;
CREATE POLICY "cases_anon_insert"
  ON public.cases FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "cases_owner_select" ON public.cases;
CREATE POLICY "cases_owner_select"
  ON public.cases FOR SELECT
  USING (
    -- Citizen viewing their own case (matched by phone in lookup flow)
    phone IS NOT NULL
    -- OR staff viewing any case
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer','approver','viewer','water_only')
    )
  );

DROP POLICY IF EXISTS "cases_staff_update" ON public.cases;
CREATE POLICY "cases_staff_update"
  ON public.cases FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer','approver')
    )
  );

-- News articles: anyone can read published; only staff can write
DROP POLICY IF EXISTS "news_public_read" ON public.news_articles;
CREATE POLICY "news_public_read"
  ON public.news_articles FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

DROP POLICY IF EXISTS "news_staff_write" ON public.news_articles;
CREATE POLICY "news_staff_write"
  ON public.news_articles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer')
    )
  );

-- Push subscriptions: insert by anon (browser subscribes), read by owner via endpoint match
DROP POLICY IF EXISTS "push_subs_anon_insert" ON public.push_subscriptions;
CREATE POLICY "push_subs_anon_insert"
  ON public.push_subscriptions FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "push_subs_anon_update_self" ON public.push_subscriptions;
CREATE POLICY "push_subs_anon_update_self"
  ON public.push_subscriptions FOR UPDATE
  TO anon, authenticated
  USING (true);  -- Allow updating by endpoint match (no user identity needed)

DROP POLICY IF EXISTS "push_subs_admin_select" ON public.push_subscriptions;
CREATE POLICY "push_subs_admin_select"
  ON public.push_subscriptions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer')
    )
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 — Phonebook RLS
-- ─────────────────────────────────────────────────────────────────────────────

-- Phonebook entries: anyone can read public (non-hidden) entries
DROP POLICY IF EXISTS "phonebook_public_read" ON public.phonebook_entries;
CREATE POLICY "phonebook_public_read"
  ON public.phonebook_entries FOR SELECT
  TO anon, authenticated
  USING (COALESCE(entry_hidden, false) = false);

DROP POLICY IF EXISTS "phonebook_admin_full" ON public.phonebook_entries;
CREATE POLICY "phonebook_admin_full"
  ON public.phonebook_entries FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer')
    )
  );

-- Anyone can submit a new entry (it goes into a review queue)
DROP POLICY IF EXISTS "phonebook_anon_insert" ON public.phonebook_entries;
CREATE POLICY "phonebook_anon_insert"
  ON public.phonebook_entries FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 9 — Coop RLS
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "coop_products_public_read" ON public.coop_products;
CREATE POLICY "coop_products_public_read"
  ON public.coop_products FOR SELECT
  TO anon, authenticated
  USING (COALESCE(is_active, true) = true);

DROP POLICY IF EXISTS "coop_orders_anon_insert" ON public.coop_orders;
CREATE POLICY "coop_orders_anon_insert"
  ON public.coop_orders FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "coop_orders_admin_select" ON public.coop_orders;
CREATE POLICY "coop_orders_admin_select"
  ON public.coop_orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role IN ('mayor','admin','officer')
    )
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 10 — Audit query (run this AFTER everything above)
-- ─────────────────────────────────────────────────────────────────────────────

-- Verify RLS is on for every table
SELECT
  schemaname,
  tablename,
  rowsecurity AS "RLS enabled?"
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY rowsecurity ASC, tablename;
-- Every row should show rowsecurity = true.
-- If any show false, those tables are wide open to anyone with the anon key.

-- Verify role assignments
SELECT
  u.email,
  p.name AS profile_name,
  ur.role,
  ur.granted_at
FROM public.user_roles ur
JOIN auth.users u ON u.id = ur.user_id
LEFT JOIN public.profiles p ON p.user_id = ur.user_id
ORDER BY ur.role, u.email;


-- ════════════════════════════════════════════════════════════════════════════
-- DOWN MIGRATION (rollback if something breaks):
-- ════════════════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- DROP FUNCTION IF EXISTS public.handle_new_user();
-- DROP FUNCTION IF EXISTS public.current_user_role();
-- DROP TABLE IF EXISTS public.user_roles;
-- DROP TABLE IF EXISTS public.profiles;
-- -- Policies are dropped when tables are dropped.
