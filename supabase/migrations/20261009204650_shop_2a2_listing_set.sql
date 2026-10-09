do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- shop-2a2 — Shopify 연동 ② 상품 보내기 · DB 뒤 절반 (2026-10-09 · 판정 404 · 405 · 406 · 410 · shop-2a1 회신 「2a2」 줄 · 2a1 20261009200731 위에)
--   ① 큐 넣기 속 함수 shop_queue_add(fids[], pids[], reason) — 켜진 listing 대상만 · 열린 줄 하나(not exists · 규칙 29) · 낱개 구성원 → 그 family · 낱개 → 그 세트도
--   ② 큐 트리거 *_shop_queue — AFTER STATEMENT(transition table) 16 개: product_u · product_family_u · product_price/image/tag/barcode i·u·d · ref_brand_u · ref_category_u(이름이 바뀔 때만)
--   ③ 창구 shop_listing_set(p_changes, p_commit, p_ack) — 문 ims_require_write('shopify') · op listing_on · listing_off · push_now · family_web_image_set
--   ④ 새벽 맞추기 shop_queue_all(p_store_id) — 켜진 listing 전부(reason nightly) · 실행권 service_role · cron 등록은 2b
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 큐 넣기 — 한 곳 ═══
create function public.shop_queue_add(p_fids uuid[], p_pids uuid[], p_reason text, p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_fids uuid[] := coalesce(p_fids, '{}');
  v_pids uuid[] := coalesce(p_pids, '{}');
  v_n    int;
begin
  if cardinality(v_fids) = 0 and cardinality(v_pids) = 0 then return 0; end if;
  -- 낱개 구성원이 바뀌면 그 family · 낱개가 바뀌면 그 세트(계산 가격)도 대상
  select v_fids || coalesce(array_agg(distinct p.family_id), '{}') into v_fids from public.product p where p.id = any(v_pids) and p.family_id is not null;
  select v_pids || coalesce(array_agg(x.id), '{}') into v_pids from public.product x where x.parent_product_id = any(v_pids);
  insert into public.shop_push_queue (store_id, family_id, product_id, reason)
  select l.store_id, l.family_id, l.product_id, p_reason
    from public.shop_listing l
   where l.is_on and (p_store_id is null or l.store_id = p_store_id)
     and ((l.family_id is not null and l.family_id = any(v_fids)) or (l.product_id is not null and l.product_id = any(v_pids)))
     and not exists (select 1 from public.shop_push_queue q where q.store_id = l.store_id and q.done_at is null
                        and q.family_id is not distinct from l.family_id and q.product_id is not distinct from l.product_id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.shop_queue_add(uuid[], uuid[], text, uuid) from public, anon, authenticated;
comment on function public.shop_queue_add(uuid[], uuid[], text, uuid) is 'shop-2a2: 큐 넣기 한 곳 — family id 들 · 상품 id 들(낱개 구성원은 그 family 로 · 낱개는 그 세트도) → 켜진 listing 이 있는 (스토어 × 대상)마다 열린 줄이 없을 때만 한 줄(규칙 29 · not exists) · 돌려주는 값 = 넣은 줄 수 · definer · 직접 실행권 없음(트리거 · 창구 · shop_queue_all 이 부른다)';

-- ═══ 2) 큐 트리거 — AFTER STATEMENT · transition table · 함수 하나(tg_argv[0] = 종류 · tg_op 로 n · o 를 가른다) ═══
--   product · product_family: UPDATE 만(새 행은 아직 listing 이 없다 · 지우기는 잠금) · 네 관계 표: i · u · d · ref_brand · ref_category: UPDATE 중 이름이 바뀐 행만
--   ⚠️ BEFORE ROW 문지기(product_description_guard · ims_touch)가 끝난 행을 본다 — 설명 칸이 되돌아가도 문장이 돌았으면 큐는 생긴다(hash 가 같으면 EF 가 skipped_same_hash)
--   ⚠️ 적재(ImsLoadProduct · 500 행 묶음 upsert)마다 켜진 대상만큼 큐가 생긴다 — 대상 수만큼이지 행 수만큼이 아니다(문장 하나 = insert 하나)
create function public.shop_queue_trigger() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_kind text := tg_argv[0];
  v_fids uuid[] := '{}';
  v_pids uuid[] := '{}';
begin
  if v_kind = 'product' then
    select coalesce(array_agg(distinct x.id), '{}'), coalesce(array_agg(distinct x.family_id) filter (where x.family_id is not null), '{}') into v_pids, v_fids
      from (select n.id, n.family_id from n union select o.id, o.family_id from o) x;
  elsif v_kind = 'product_family' then
    select coalesce(array_agg(distinct n.id), '{}') into v_fids from n;
  elsif v_kind in ('ref_brand', 'ref_category') then
    if v_kind = 'ref_brand' then
      select coalesce(array_agg(distinct p.id), '{}') into v_pids from public.product p where p.brand_id in (select n.id from n join o on o.id = n.id where o.name is distinct from n.name);
      select coalesce(array_agg(distinct f.id), '{}') into v_fids from public.product_family f where f.brand_id in (select n.id from n join o on o.id = n.id where o.name is distinct from n.name);
    else
      select coalesce(array_agg(distinct p.id), '{}') into v_pids from public.product p where p.category_id in (select n.id from n join o on o.id = n.id where o.name is distinct from n.name);
      select coalesce(array_agg(distinct f.id), '{}') into v_fids from public.product_family f where f.category_id in (select n.id from n join o on o.id = n.id where o.name is distinct from n.name);
    end if;
  else                                                                                            -- product_price · product_image · product_tag · product_barcode(product_id 칸)
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct n.product_id), '{}') into v_pids from n;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct o.product_id), '{}') into v_pids from o;
    else
      select coalesce(array_agg(distinct x.product_id), '{}') into v_pids from (select n.product_id from n union select o.product_id from o) x;
    end if;
  end if;
  perform public.shop_queue_add(v_fids, v_pids, v_kind);
  return null;
end;
$$;
revoke all on function public.shop_queue_trigger() from public, anon, authenticated;
comment on function public.shop_queue_trigger() is 'shop-2a2: 상품 계열 표의 AFTER STATEMENT 트리거 함수(tg_argv[0] = product | product_family | product_price | product_image | product_tag | product_barcode | ref_brand | ref_category) — transition table 에서 바뀐 상품 · family 를 모아 shop_queue_add(켜진 listing 대상만 · 열린 줄 하나) · ref_brand · ref_category 는 이름이 바뀐 행만 · 문장 하나 = 큐 insert 하나';

create trigger product_shop_queue_u         after update on public.product         referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product');
create trigger product_family_shop_queue_u  after update on public.product_family  referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product_family');
create trigger product_price_shop_queue_i   after insert on public.product_price   referencing new table as n                for each statement execute function public.shop_queue_trigger('product_price');
create trigger product_price_shop_queue_u   after update on public.product_price   referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product_price');
create trigger product_price_shop_queue_d   after delete on public.product_price   referencing old table as o                for each statement execute function public.shop_queue_trigger('product_price');
create trigger product_image_shop_queue_i   after insert on public.product_image   referencing new table as n                for each statement execute function public.shop_queue_trigger('product_image');
create trigger product_image_shop_queue_u   after update on public.product_image   referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product_image');
create trigger product_image_shop_queue_d   after delete on public.product_image   referencing old table as o                for each statement execute function public.shop_queue_trigger('product_image');
create trigger product_tag_shop_queue_i     after insert on public.product_tag     referencing new table as n                for each statement execute function public.shop_queue_trigger('product_tag');
create trigger product_tag_shop_queue_u     after update on public.product_tag     referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product_tag');
create trigger product_tag_shop_queue_d     after delete on public.product_tag     referencing old table as o                for each statement execute function public.shop_queue_trigger('product_tag');
create trigger product_barcode_shop_queue_i after insert on public.product_barcode referencing new table as n                for each statement execute function public.shop_queue_trigger('product_barcode');
create trigger product_barcode_shop_queue_u after update on public.product_barcode referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('product_barcode');
create trigger product_barcode_shop_queue_d after delete on public.product_barcode referencing old table as o                for each statement execute function public.shop_queue_trigger('product_barcode');
create trigger ref_brand_shop_queue_u       after update on public.ref_brand       referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('ref_brand');
create trigger ref_category_shop_queue_u    after update on public.ref_category    referencing old table as o new table as n for each statement execute function public.shop_queue_trigger('ref_category');

-- ═══ 3) 창구 shop_listing_set — 문 shopify(manager 이상) · 두 번 부르기 · op 넷 ═══
create function public.shop_listing_set(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_key      text;
  v_code     text;
  v_fsku     text;
  v_psku     text;
  v_seen     text[] := '{}';
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_s        public.shop_store%rowtype;
  v_f        public.product_family%rowtype;
  v_p        public.product%rowtype;
  v_l        public.shop_listing%rowtype;
  v_img      public.product_image%rowtype;
  v_pl       jsonb;
  v_b        text;
  v_qid      bigint;
  v_cur      text;
  c_ops      constant text[] := array['listing_on', 'listing_off', 'push_now', 'family_web_image_set'];
begin
  perform public.ims_require_write('shopify', 'saved');                                           -- ⭐ 유일한 문 — 첫 줄(권한 키 shopify · shop-1a)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 200 then raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if not (coalesce(v_c->>'op', '') = any(c_ops)) then
      raise exception 'Unknown op "%" — listing_on, listing_off, push_now or family_web_image_set — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_s := null; v_f := null; v_p := null; v_l := null; v_img := null;
    v_fsku := nullif(trim(coalesce(v_c->>'family_sku', '')), '');
    v_psku := nullif(trim(coalesce(v_c->>'sku', '')), '');
    v_code := lower(trim(coalesce(v_c->>'store_code', '')));
    v_key := coalesce(v_fsku, v_psku, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'store_code', v_code, 'family_sku', v_fsku, 'sku', v_psku, 'applied', false);
    if (v_fsku is null) = (v_psku is null) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_invalid', 'code', 'target_invalid', 'message', 'Give exactly one of family_sku or sku — nothing was saved');
      continue;
    end if;
    if v_fsku is not null then select * into v_f from public.product_family f where f.sku = v_fsku; else select * into v_p from public.product p where p.sku = v_psku; end if;
    if v_f.id is null and v_p.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_unknown', 'code', 'target_unknown', 'message', format('%s %s does not exist — nothing was saved', case when v_fsku is not null then 'Family' else 'SKU' end, v_key));
      continue;
    end if;

    if v_op = 'family_web_image_set' then
      if v_f.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_invalid', 'code', 'target_invalid', 'message', 'family_web_image_set needs family_sku — nothing was saved');
        continue;
      end if;
      if ('W|' || v_f.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:web_image', 'code', 'field_duplicate_in_call', 'message', format('Family %s web image is changed twice in this call — nothing was saved', v_key));
        continue;
      end if;
      v_seen := v_seen || ('W|' || v_f.id::text);
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:web_image', 'code', 'old_missing', 'message', format('Family %s: the old web image the screen saw is missing (null if none) — nothing was saved', v_key));
        continue;
      end if;
      if v_f.web_image_id::text is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:web_image', 'code', 'changed_elsewhere', 'message', format('Someone just changed the web image of family %s — check again — nothing was saved', v_key));
        continue;
      end if;
      if nullif(v_c->>'product_image_id', '') is not null then
        if (v_c->>'product_image_id') ~ '^[0-9a-fA-F-]{36}$' then
          select i.* into v_img from public.product_image i join public.product p on p.id = i.product_id where i.id = (v_c->>'product_image_id')::uuid and i.is_active and p.family_id = v_f.id and p.parent_product_id is null;
        end if;
        if v_img.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_in_family', 'code', 'image_not_in_family', 'message', format('Family %s: that image is not an active photo of one of its variants — nothing was saved', v_key));
        end if;
      end if;
      continue;
    end if;

    -- listing_on · listing_off · push_now — 스토어가 있어야 한다
    select * into v_s from public.shop_store s where s.code = v_code;
    if v_s.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store "%s" does not exist — nothing was saved', v_code));
      continue;
    end if;
    v_key := v_code || ':' || v_key;
    if ('L|' || v_s.id::text || '|' || coalesce(v_f.id, v_p.id)::text) = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('%s appears twice for store %s in this call — nothing was saved', coalesce(v_fsku, v_psku), v_code));
      continue;
    end if;
    v_seen := v_seen || ('L|' || v_s.id::text || '|' || coalesce(v_f.id, v_p.id)::text);
    select * into v_l from public.shop_listing l where l.store_id = v_s.id and l.family_id is not distinct from v_f.id and l.product_id is not distinct from v_p.id;
    if v_op in ('listing_on', 'listing_off') then
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('%s on store %s: the old on/off value the screen saw is missing (null if never listed) — nothing was saved', coalesce(v_fsku, v_psku), v_code));
        continue;
      end if;
      v_cur := case when v_l.id is null then null else v_l.is_on::text end;
      if v_cur is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the listing of %s on store %s (now %s) — check again — nothing was saved', coalesce(v_fsku, v_psku), v_code, coalesce(v_cur, 'not listed')));
        continue;
      end if;
    end if;
    if v_op = 'listing_on' then
      if not v_s.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_inactive', 'code', 'store_inactive', 'message', format('Store "%s" is switched off — nothing was saved', v_code));
        continue;
      end if;
      if v_l.id is not null and v_l.is_on then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_on', 'code', 'already_on', 'message', format('%s is already sent to store %s — nothing was saved', coalesce(v_fsku, v_psku), v_code));
        continue;
      end if;
      v_pl := public.shop_product_payload(v_s.id, v_f.id, v_p.id);                                 -- 켜기 조건 = payload 의 blocks(listing_missing 은 뺀다 · 판정 404 · 2a1)
      for v_b in select x #>> '{}' from jsonb_array_elements(v_pl->'blocks') x where (x #>> '{}') <> 'listing_missing' loop
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || v_b, 'code', split_part(v_b, ':', 1), 'detail', v_b, 'message',
          case split_part(v_b, ':', 1)
            when 'family_member_goes_with_family' then format('SKU %s belongs to a family — send the family instead — nothing was saved', v_psku)
            when 'set_not_sellable' then format('Set %s is not sellable — only sellable sets can be sent (ruling 404) — nothing was saved', v_psku)
            when 'no_variants' then format('Family %s has no single variants to send — nothing was saved', v_fsku)
            when 'no_price' then format('%s has no %s price — set it first — nothing was saved', split_part(v_b, ':', 2), (select t.name from public.ref_price_tier t where t.id = v_s.sale_tier_id))
            else format('%s cannot be sent (%s) — nothing was saved', coalesce(v_fsku, v_psku), v_b) end);
      end loop;
      if (v_pl->>'active_variants')::int = 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':no_active_variants', 'code', 'no_active_variants', 'message', format('%s has no active sellable variant — it will be sent as ARCHIVED until one is switched on', coalesce(v_fsku, v_psku)));
      end if;
    elsif v_op = 'listing_off' then
      if v_l.id is null or not v_l.is_on then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_off', 'code', 'already_off', 'message', format('%s is not sent to store %s — nothing was saved', coalesce(v_fsku, v_psku), v_code));
        continue;
      end if;
    else                                                                                            -- push_now
      if v_l.id is null or not v_l.is_on then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':listing_off', 'code', 'listing_off', 'message', format('%s is not sent to store %s — switch it on first — nothing was saved', coalesce(v_fsku, v_psku), v_code));
        continue;
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_fsku := nullif(trim(coalesce(v_c->>'family_sku', '')), ''); v_psku := nullif(trim(coalesce(v_c->>'sku', '')), '');
    v_f := null; v_p := null; v_qid := null;
    if v_fsku is not null then select * into v_f from public.product_family f where f.sku = v_fsku; else select * into v_p from public.product p where p.sku = v_psku; end if;
    if v_op = 'family_web_image_set' then
      update public.product_family set web_image_id = nullif(v_c->>'product_image_id', '')::uuid where id = v_f.id;    -- product_family_shop_queue_u 가 큐를 넣는다
    else
      select * into v_s from public.shop_store s where s.code = lower(trim(v_c->>'store_code'));
      if v_op = 'listing_on' then
        update public.shop_listing set is_on = true, turned_on_at = now(), turned_on_by = v_staff, turned_off_at = null, turned_off_by = null
         where store_id = v_s.id and family_id is not distinct from v_f.id and product_id is not distinct from v_p.id;
        if not found then
          insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, updated_by) values (v_s.id, v_f.id, v_p.id, true, now(), v_staff, v_staff);
        end if;
      end if;
      perform public.shop_queue_add(case when v_f.id is null then '{}'::uuid[] else array[v_f.id] end, case when v_p.id is null then '{}'::uuid[] else array[v_p.id] end, v_op, v_s.id);   -- listing_off 는 끄기 전에 넣는다(켜진 것만 큐에 들어가므로 · ARCHIVED 를 보내야 한다 · 판정 405)
      if v_op = 'listing_off' then
        update public.shop_listing set is_on = false, turned_off_at = now(), turned_off_by = v_staff
         where store_id = v_s.id and family_id is not distinct from v_f.id and product_id is not distinct from v_p.id;
      end if;
      select q.id into v_qid from public.shop_push_queue q where q.store_id = v_s.id and q.done_at is null and q.family_id is not distinct from v_f.id and q.product_id is not distinct from v_p.id order by q.id desc limit 1;
    end if;
    v_changes := jsonb_set(jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb), array[(v_i - 1)::text, 'queue_id'], coalesce(to_jsonb(v_qid), 'null'::jsonb));
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.shop_listing_set(jsonb, boolean, text[]) from public, anon;
grant execute on function public.shop_listing_set(jsonb, boolean, text[]) to authenticated;
comment on function public.shop_listing_set(jsonb, boolean, text[]) is
  '⭐ Shopify 보냄 표시 창구(shop-2a2 · 판정 404 · 405 · 406) — definer · 첫 줄 ims_require_write(shopify) · p_changes 최대 200 · op 넷: listing_on {store_code, family_sku | sku, old = 지금 is_on(true|false) 또는 null(아직 없음)} · listing_off {같음} · push_now {store_code, family_sku | sku}(켜진 것만) · family_web_image_set {family_sku, product_image_id | null, old = 지금 web_image_id | null}. 켜기 조건 = shop_product_payload 의 blocks(family_member_goes_with_family · set_not_sellable · no_variants · no_price:<sku>) · 막기 target_invalid · target_unknown · store_unknown · store_inactive · already_on · already_off · listing_off · old_missing · changed_elsewhere · field_duplicate_in_call · image_not_in_family · 알리기(ack) no_active_variants · 켜기 · 끄기 · push_now 는 큐에 한 줄(reason = op · changes[].queue_id) · 검사만(p_commit false) → 저장(p_commit true + p_ack)';

-- ═══ 4) 새벽 맞추기 — 켜진 listing 전부 큐에(열린 줄 있으면 건너뜀) · cron(2b) 또는 EF(service_role) ═══
create function public.shop_queue_all(p_store_id uuid default null) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_fids uuid[]; v_pids uuid[];
begin
  select coalesce(array_agg(l.family_id) filter (where l.family_id is not null), '{}'), coalesce(array_agg(l.product_id) filter (where l.product_id is not null), '{}')
    into v_fids, v_pids from public.shop_listing l where l.is_on and (p_store_id is null or l.store_id = p_store_id);
  return public.shop_queue_add(v_fids, v_pids, 'nightly', p_store_id);
end;
$$;
revoke all on function public.shop_queue_all(uuid) from public, anon, authenticated;
comment on function public.shop_queue_all(uuid) is 'shop-2a2 설계 §3-e 새벽 전체 맞추기: 켜진 listing 전부(스토어 하나 또는 전부)를 큐에(reason nightly · 열린 줄이 있으면 건너뜀) · 돌려주는 값 = 넣은 줄 수 · 실행권 service_role · postgres(cron)만 — cron 등록은 2b(supabase/ops/cron.sql)';
