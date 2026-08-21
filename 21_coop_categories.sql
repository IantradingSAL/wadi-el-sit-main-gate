-- ═══════════════════════════════════════════════════════════════════════════
-- 21_coop_categories.sql — applied to the live project on 2026-08-21
--
-- `coop_categories` had its permissions exactly backwards.
--
--   SELECT   pub_read              TO public   USING (auth.uid() IS NOT NULL)
--   INSERT   coop_cat_anon_insert  TO anon, authenticated
--   UPDATE   coop_cat_anon_update  TO anon, authenticated  USING (true)
--   DELETE   coop_cat_anon_delete  TO anon, authenticated  USING (true)
--
-- So a shopper arriving at the village shop could not see a single one of the
-- ten categories — the storefront's whole navigation was invisible to anyone
-- not signed in — while any stranger on the internet, holding nothing but the
-- public key printed in the page source, could rename them or delete them all.
--
-- Migration 08 replaced this pattern everywhere else and missed this table.
--
-- Categories are now read by everyone and written only by a signed-in seller,
-- through the same token-scoped, security-definer route that products already
-- use (coop_product_save / coop_product_delete, migration 13). coop.html no
-- longer writes the table directly.
--
-- Category management is shop-wide rather than per-seller — that is the
-- existing design, and any approved seller may edit the shared list. What
-- changes is that they must now be a seller at all.
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists pub_read             on public.coop_categories;
drop policy if exists coop_cat_anon_insert on public.coop_categories;
drop policy if exists coop_cat_anon_update on public.coop_categories;
drop policy if exists coop_cat_anon_delete on public.coop_categories;

create policy coop_cat_public_read on public.coop_categories
  for select to anon, authenticated using (true);

create or replace function public.coop_category_save(p_token uuid, p_category jsonb)
returns public.coop_categories
language plpgsql security definer
set search_path to 'public','extensions','pg_temp'
as $$
declare v_seller uuid; v_row public.coop_categories;
begin
  v_seller := public.coop_session_subject(p_token, 'seller');
  if v_seller is null then
    raise exception 'not signed in as a seller' using errcode = '42501';
  end if;
  insert into public.coop_categories as c (id, label, icon, sort_order, name_i18n, color, image_url)
  values (
    coalesce(nullif(p_category->>'id',''), 'cat_' || substr(md5(random()::text),1,10)),
    coalesce(p_category->>'label',''),
    coalesce(p_category->>'icon','📦'),
    coalesce((p_category->>'sort_order')::int, 1),
    p_category->'name_i18n',
    p_category->>'color',
    p_category->>'image_url'
  )
  on conflict (id) do update
    set label = excluded.label, icon = excluded.icon, sort_order = excluded.sort_order,
        name_i18n = excluded.name_i18n, color = excluded.color, image_url = excluded.image_url
  returning c.* into v_row;
  return v_row;
end $$;

create or replace function public.coop_category_delete(p_token uuid, p_id text)
returns boolean
language plpgsql security definer
set search_path to 'public','extensions','pg_temp'
as $$
declare v_seller uuid; v_n int;
begin
  v_seller := public.coop_session_subject(p_token, 'seller');
  if v_seller is null then return false; end if;
  delete from public.coop_categories where id = p_id;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

revoke execute on function public.coop_category_save(uuid, jsonb)  from public;
revoke execute on function public.coop_category_delete(uuid, text) from public;
grant  execute on function public.coop_category_save(uuid, jsonb)  to anon, authenticated;
grant  execute on function public.coop_category_delete(uuid, text) to anon, authenticated;

-- Measured after applying, as anon:
--   read categories                    10 rows   (was 0)
--   INSERT                             refused   42501
--   DELETE                             refused   42501
--   coop_category_delete(bad token)    false
