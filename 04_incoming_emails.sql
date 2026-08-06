-- ════════════════════════════════════════════════════════════════════════════
-- 04_incoming_emails.sql
-- Inbox log for messages arriving via the Hostinger email webhook.
-- Populated by the hostinger-inbound-email edge function.
-- Safe to re-run. Run after 03_news_views.sql.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.incoming_emails (
  id              bigserial   PRIMARY KEY,
  mun_id          uuid        NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
  mailbox         text        NOT NULL,
  folder          text        NOT NULL DEFAULT 'INBOX',
  message_uid     text        NOT NULL,
  message_id      text,
  from_email      text        NOT NULL,
  from_name       text,
  to_emails       text[]      NOT NULL DEFAULT '{}',
  subject         text,
  snippet         text,
  received_at     timestamptz NOT NULL DEFAULT now(),
  category        text        NOT NULL DEFAULT 'general'
                              CHECK (category IN ('water','coop','bus','mrs','general','internal')),
  ticket_id       text        UNIQUE,
  is_auto_reply   boolean     NOT NULL DEFAULT false,
  replied         boolean     NOT NULL DEFAULT false,
  handled_by      uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  handled_at      timestamptz,
  raw_headers     jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (mailbox, folder, message_uid)
);

CREATE INDEX IF NOT EXISTS incoming_emails_received_idx
  ON public.incoming_emails (received_at DESC);
CREATE INDEX IF NOT EXISTS incoming_emails_category_idx
  ON public.incoming_emails (category, received_at DESC);
CREATE INDEX IF NOT EXISTS incoming_emails_replied_idx
  ON public.incoming_emails (replied, received_at DESC) WHERE replied = false;
CREATE INDEX IF NOT EXISTS incoming_emails_from_idx
  ON public.incoming_emails (from_email);

ALTER TABLE public.incoming_emails ENABLE ROW LEVEL SECURITY;

-- Admins / mayors / super-admins can read every message.
DROP POLICY IF EXISTS incoming_emails_staff_select ON public.incoming_emails;
CREATE POLICY incoming_emails_staff_select
  ON public.incoming_emails
  FOR SELECT
  TO authenticated
  USING (
    public.has_role('admin')
    OR public.has_role('mayor')
    OR public.has_role('super_admin')
  );

-- Same staff can mark handled/replied.
DROP POLICY IF EXISTS incoming_emails_staff_update ON public.incoming_emails;
CREATE POLICY incoming_emails_staff_update
  ON public.incoming_emails
  FOR UPDATE
  TO authenticated
  USING (
    public.has_role('admin')
    OR public.has_role('mayor')
    OR public.has_role('super_admin')
  )
  WITH CHECK (
    public.has_role('admin')
    OR public.has_role('mayor')
    OR public.has_role('super_admin')
  );

-- Inserts only via service role (edge function); no policy for anon/authenticated.

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: next_email_ticket_id() -> 'WES-YYYYMMDD-nnn'
-- Sequential per day; called by the edge function.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS public.incoming_emails_ticket_seq;

CREATE OR REPLACE FUNCTION public.next_email_ticket_id()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  today_key text := to_char(now() AT TIME ZONE 'Asia/Beirut', 'YYYYMMDD');
  n         bigint;
BEGIN
  n := nextval('public.incoming_emails_ticket_seq');
  RETURN 'WES-' || today_key || '-' || lpad((n % 1000)::text, 3, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.next_email_ticket_id() FROM public;
GRANT EXECUTE ON FUNCTION public.next_email_ticket_id() TO service_role;
