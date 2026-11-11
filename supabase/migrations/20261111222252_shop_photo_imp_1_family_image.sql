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

-- shop-photo-imp-1 — 패밀리 사진 자리: product_image.family_id(제품 XOR 패밀리) · 출처 shopify · 저장소 정책 · 패밀리 사진 쓰기 창구 · Shopify payload · 웹 대표 가드 · 큐
--   (판정 1179 ~ 1188 · Caleb 2026-11-11 · 지시서 ~/asung/prompts/shop-photo-imp-1.md · 이견 답 · deferred 387 가져오기 길 ①)
--   판정 1179  사진 한 장은 제품 또는 패밀리 하나에 — product_image 에 family_id 를 더하고 product_id XOR family_id
--   판정 1186  패밀리 사진 쓰기 = 새 창구 family_image_update(op family_image_add · family_image_off · family_image_order · 대상 family_sku · 문 master) — product_update 는 건드리지 않는다
--   판정 1187  웹 대표(product_family.web_image_id)인 패밀리 사진을 끄면 경고(family_web_image_off · ack 필요) → 확인하면 끄기 + web_image_id 를 같은 트랜잭션에서 비운다(끄기의 일부 — 문은 master 하나)
--   판정 1188  Shopify 표지 = web_image_id 가 켜진 후보(구성원 낱개의 켜진 사진 또는 이 패밀리의 켜진 패밀리 사진)일 때만 · 아니면 기본값(구성원 켜진 대표 사진 중 SKU 순 첫 장)
--   무엇:
--     ① shop_queue_trigger 재발행 — product_image 전용 갈래(product_id → 제품 · family_id → 패밀리) · 더한 줄만 · 트리거 셋은 그대로
--     ② shop_listing_set 재발행 — op family_web_image_set 이 그 패밀리의 켜진 패밀리 사진도 받는다(더한 세 줄 + 거부 글 한 줄)
--     ③ shop_product_payload 재발행 — 표지 검사(1188) · files 에 패밀리 사진(순서 표지 0 → 변형 대표 1 → 구성원 나머지 2 → 패밀리 사진 3 · sort_order)
--          ⚠️ 구성원 사진의 file 객체는 예전 그대로(열쇠 다섯) — 패밀리 사진이 없는 대상의 hash 는 바뀌지 않는다 · 패밀리 사진 file 에만 product_id null · family_id · sku(패밀리 SKU)
--     ④ family_image_update(새 창구 · definer · 문 = ims_require_write('master') 첫 줄 · 봉투 = product_update 와 같은 꼴 committed · changes · blocks · warnings · unacked)
--     ⑤ product_image — family_id(FK product_family · no action) · product_id nullable · CHECK 넷(주인 하나 · 패밀리 사진은 대표 아님 · 폴더 = 주인 id · 출처에 shopify) · 부분 인덱스
--          패밀리 사진의 is_primary 는 늘 false — 「대표 하나」(창구가 지킨다)는 제품 사진의 규칙 그대로 · 패밀리의 표지는 web_image_id 하나
--     ⑥ 저장소 정책 product_images_insert · update — 폴더 첫 칸 = 실재하는 product.id 또는 product_family.id(delete 정책은 그대로)
--   재발행 몸 = DB prosrc 원본(ⓞ 의 md5) + 고친 자리(-- shop-photo-imp-1 표지)만 · 순서: 함수(표 잠금 없음) 먼저 → 표 · 저장소 정책(ACCESS EXCLUSIVE)은 끝에 — 잠금 구간을 짧게
--   무접촉: product_update · product_image_primary · product_export · shop_variant_payload · shop_link_plan · shop_media · 버킷 설정 · 지금 있는 사진 행 · EF ims-product-images
--   컷오버 뒤라 지우는 순서 줄은 없다(product_image.family_id → product_family 는 마스터끼리 · 패밀리를 지우는 길은 없다)

-- ═══ ⓞ 재발행 원본 가드 ═══
do $$
declare v_bad text;
begin
  select string_agg(x.n, ', ') into v_bad
    from (values ('shop_queue_trigger()', '9a43559f605877fc4225b1172086c54b'), ('shop_listing_set(jsonb,boolean,text[])', '81a64fba2c34c5ca3cedf274976bda8d'), ('shop_product_payload(uuid,uuid,uuid)', 'f37e797073fa83540cd4c307ddfe982d')) as x(n, m)
   where (select md5(p.prosrc) from pg_proc p where p.oid = ('public.' || x.n)::regprocedure) is distinct from x.m;
  if v_bad is not null then
    raise exception 'shop-photo-imp-1 ⓞ % differs from what this migration was built on — rebuild from the current body first — nothing was changed', v_bad;
  end if;
end $$;

-- ═══ ① shop_queue_trigger ═══
create or replace function public.shop_queue_trigger()
  returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
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
  elsif v_kind = 'product_image' then                                                             -- shop-photo-imp-1(판정 1179): 사진은 제품(product_id) 또는 패밀리(family_id) 하나에 — 패밀리 사진은 그 패밀리 listing 으로(다른 표의 transition table 에는 family_id 가 없어 갈래를 따로 둔다)
    if tg_op = 'INSERT' then
      select coalesce(array_agg(distinct n.product_id) filter (where n.product_id is not null), '{}'), coalesce(array_agg(distinct n.family_id) filter (where n.family_id is not null), '{}') into v_pids, v_fids from n;
    elsif tg_op = 'DELETE' then
      select coalesce(array_agg(distinct o.product_id) filter (where o.product_id is not null), '{}'), coalesce(array_agg(distinct o.family_id) filter (where o.family_id is not null), '{}') into v_pids, v_fids from o;
    else
      select coalesce(array_agg(distinct x.product_id) filter (where x.product_id is not null), '{}'), coalesce(array_agg(distinct x.family_id) filter (where x.family_id is not null), '{}') into v_pids, v_fids
        from (select n.product_id, n.family_id from n union select o.product_id, o.family_id from o) x;
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
$function$;

-- ═══ ② shop_listing_set ═══
create or replace function public.shop_listing_set(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}'::text[])
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
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
          if v_img.id is null then                                                                 -- shop-photo-imp-1(판정 1179): 그 패밀리의 패밀리 사진(family_id)도 받는다 · 다른 패밀리의 것 · 꺼진 것은 그대로 거부
            select i.* into v_img from public.product_image i where i.id = (v_c->>'product_image_id')::uuid and i.is_active and i.family_id = v_f.id;
          end if;
        end if;
        if v_img.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_in_family', 'code', 'image_not_in_family', 'message', format('Family %s: that image is not an active photo of one of its variants or of the family itself — nothing was saved', v_key));
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
$function$;

-- ═══ ③ shop_product_payload ═══
create or replace function public.shop_product_payload(p_store_id uuid, p_family_id uuid default null::uuid, p_product_id uuid default null::uuid)
  returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $function$
declare
  v_s        public.shop_store%rowtype;
  v_f        public.product_family%rowtype;
  v_p        public.product%rowtype;
  v_l        public.shop_listing%rowtype;
  v_sp       public.shop_product%rowtype;                                                          -- shop-new-1: 이 (스토어, 대상)의 행 — 덧씌우기 · 있고 없음
  v_kind     text;
  v_title    text;
  v_desc     text;
  v_vendor   text;
  v_ptype    text;
  v_options  jsonb := '[]'::jsonb;
  v_variants jsonb := '[]'::jsonb;
  v_files    jsonb := '[]'::jsonb;
  v_tags     jsonb := '[]'::jsonb;
  v_blocks   jsonb := '[]'::jsonb;
  v_status   text;
  v_active   int := 0;
  v_cover    uuid;
  v_base     text := rtrim(coalesce(current_setting('app.settings.supabase_url', true), ''), '/');   -- 비어 있으면 EF 가 자기 SUPABASE_URL 로 채운다(url 은 경로만 · image_path)
  v_m        public.product%rowtype;
  v_out      jsonb;
begin
  if (p_family_id is null) = (p_product_id is null) then
    raise exception 'shop_product_payload: give exactly one of p_family_id, p_product_id';
  end if;
  select * into v_s from public.shop_store s where s.id = p_store_id;
  if v_s.id is null then raise exception 'shop_product_payload: store % not found', p_store_id; end if;
  -- shop-new-1(판정 가 · 나 · 이견 4): 실효값 = 행 없음(IMS 가 지금 만든다) → 둘 다 true · 행 있음 → coalesce(행, 스토어) — v_s 에 넣어 아래 몸과 shop_variant_payload(p_s)가 그대로 읽는다
  if p_family_id is not null then
    select * into v_sp from public.shop_product sp where sp.store_id = p_store_id and sp.family_id = p_family_id;
  else
    select * into v_sp from public.shop_product sp where sp.store_id = p_store_id and sp.product_id = p_product_id;
  end if;
  if v_sp.id is null then
    v_s.send_images := true;  v_s.send_tags := true;
  else
    v_s.send_images := coalesce(v_sp.send_images, v_s.send_images);  v_s.send_tags := coalesce(v_sp.send_tags, v_s.send_tags);
  end if;

  if p_family_id is not null then
    v_kind := 'family';
    select * into v_f from public.product_family f where f.id = p_family_id;
    if v_f.id is null then raise exception 'shop_product_payload: family % not found', p_family_id; end if;
    select * into v_l from public.shop_listing l where l.store_id = p_store_id and l.family_id = p_family_id;
    v_title := v_f.name; v_desc := coalesce(v_f.description_html, v_f.cin7_description); v_vendor := v_f.brand_name; v_ptype := v_f.category_name;
    select coalesce(jsonb_agg(jsonb_build_object('name', o.n, 'values', (select coalesce(jsonb_agg(x.v order by x.first_sku), '[]'::jsonb) from (select y.v, min(y.sku) as first_sku from (select p.sku, case o.i when 1 then p.option1_value when 2 then p.option2_value else p.option3_value end as v from public.product p where p.family_id = v_f.id and p.parent_product_id is null) y where y.v is not null group by y.v) x)) order by o.i), '[]'::jsonb)
      into v_options
      from (values (1, v_f.option1_name), (2, v_f.option2_name), (3, v_f.option3_name)) as o(i, n) where o.n is not null;
    for v_m in select p.* from public.product p where p.family_id = v_f.id and p.parent_product_id is null order by p.sku loop   -- 구성원 = family 의 낱개(세트는 family 로 안 보낸다 · 판정 404)
      v_variants := v_variants || public.shop_variant_payload(v_s, v_m, v_f);
      if v_m.is_active and v_m.sellable then v_active := v_active + 1; end if;
    end loop;
    if jsonb_array_length(v_variants) = 0 then v_blocks := v_blocks || to_jsonb('no_variants'::text); end if;
    if v_s.send_images then                                                                        -- shop-img-off-1 판정 890: 스토어가 사진을 안 보내면 files 는 [] (사진 조회도 안 한다 · 판정 559 꼴 · EF 가 files 키 · 변형 file 을 안 보낸다)
    v_cover := v_f.web_image_id;
    if v_cover is not null                                                                         -- shop-photo-imp-1(판정 1188): 표지는 web_image_id 가 「켜진 후보」(구성원 낱개의 켜진 사진 또는 이 패밀리의 켜진 패밀리 사진)일 때만 — 꺼진 사진 · 떠난 구성원의 사진이면 기본값으로
       and not exists (select 1 from public.product_image i join public.product p on p.id = i.product_id where i.id = v_cover and i.is_active and p.family_id = v_f.id and p.parent_product_id is null)
       and not exists (select 1 from public.product_image i where i.id = v_cover and i.is_active and i.family_id = v_f.id) then
      v_cover := null;
    end if;
    if v_cover is null then
      select i.id into v_cover from public.product_image i join public.product p on p.id = i.product_id
       where p.family_id = v_f.id and p.parent_product_id is null and i.is_active and i.is_primary order by p.sku limit 1;
    end if;
    -- shop-photo-imp-1(판정 1179 · 이견 1): 구성원 사진의 file 객체는 예전 그대로(열쇠 다섯 · hash 보존) · 패밀리 사진 file 에만 product_id null · family_id · sku(패밀리 SKU — EF 가 파일 이름 줄기로 쓴다) · 순서 = 표지 0 → 변형 대표 1 → 구성원 나머지 2 → 패밀리 사진 3(sort_order)
    select coalesce(jsonb_agg(case when x.family_id is null
                                   then jsonb_build_object('product_image_id', x.id, 'image_path', x.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || x.storage_path end, 'alt', x.alt, 'product_id', x.product_id)
                                   else jsonb_build_object('product_image_id', x.id, 'image_path', x.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || x.storage_path end, 'alt', x.alt, 'product_id', null, 'family_id', x.family_id, 'sku', v_f.sku) end
                              order by x.ord, x.sku, x.sort_order), '[]'::jsonb)
      into v_files
      from (select i.id, i.storage_path, i.sort_order, i.product_id, p.sku, p.name as alt,
                   case when i.id = v_cover then 0 when i.is_primary then 1 else 2 end as ord, null::uuid as family_id
              from public.product_image i join public.product p on p.id = i.product_id
             where p.family_id = v_f.id and p.parent_product_id is null and i.is_active
            union all
            select i.id, i.storage_path, i.sort_order, null::uuid, null::text, v_f.name,
                   case when i.id = v_cover then 0 else 3 end, i.family_id
              from public.product_image i
             where i.family_id = v_f.id and i.is_active) x;
    end if;
    select coalesce(jsonb_agg(distinct t.tag), '[]'::jsonb) into v_tags from public.product_tag t join public.product p on p.id = t.product_id where p.family_id = v_f.id;
  else
    v_kind := 'product';
    select * into v_p from public.product p where p.id = p_product_id;
    if v_p.id is null then raise exception 'shop_product_payload: product % not found', p_product_id; end if;
    select * into v_l from public.shop_listing l where l.store_id = p_store_id and l.product_id = p_product_id;
    v_title := v_p.name; v_desc := coalesce(v_p.description_html, v_p.cin7_description); v_vendor := v_p.brand_name; v_ptype := v_p.category_name;
    if v_p.family_id is not null then v_blocks := v_blocks || to_jsonb('family_member_goes_with_family'::text); end if;   -- family 구성원은 family 로만
    if v_p.parent_product_id is not null and not v_p.sellable then v_blocks := v_blocks || to_jsonb('set_not_sellable'::text); end if;   -- 판정 404
    v_variants := v_variants || public.shop_variant_payload(v_s, v_p, null);
    if v_p.is_active and v_p.sellable then v_active := 1; end if;
    if v_s.send_images then                                                                        -- shop-img-off-1 판정 890
    select coalesce(jsonb_agg(jsonb_build_object('product_image_id', i.id, 'image_path', i.storage_path, 'url', case when v_base = '' then null else v_base || '/storage/v1/object/public/product-images/' || i.storage_path end, 'alt', v_p.name, 'product_id', i.product_id) order by i.is_primary desc, i.sort_order), '[]'::jsonb)
      into v_files from public.product_image i where i.product_id = v_p.id and i.is_active;
    end if;
    select coalesce(jsonb_agg(distinct t.tag), '[]'::jsonb) into v_tags from public.product_tag t where t.product_id = v_p.id;
  end if;
  if jsonb_array_length(v_tags) = 0 then v_s.send_tags := false; end if;                           -- shop-new-1 판정 다(1043): IMS 태그 0 개면 tags 칸을 안 보낸다(559 의 태그판 · Shopify 태그를 지우지 않는다) · EF :103 이 send_tags 로 거른다

  if v_l.id is null then v_blocks := v_blocks || to_jsonb('listing_missing'::text); end if;
  select v_blocks || coalesce(jsonb_agg(to_jsonb('no_price:' || (x->>'sku'))), '[]'::jsonb) into v_blocks
    from jsonb_array_elements(v_variants) x where (x->>'is_active')::boolean and (x->>'sellable')::boolean and (x->>'price') is null;   -- 켜진 변형에 Price 가 없으면 못 보낸다 · shop-pol: 켜짐 = is_active and sellable(inventory_policy 는 이제 DENY 스토어 · 단종에서도 DENY · 판정 427 · 428)
  v_status := case when v_l.id is not null and v_l.is_on and v_active > 0 then 'ACTIVE' else 'ARCHIVED' end;              -- 판정 405
  v_out := jsonb_build_object(
    'kind', v_kind, 'store_code', v_s.code, 'family_id', p_family_id, 'product_id', p_product_id,
    'title', v_title, 'description_html', v_desc, 'vendor', v_vendor, 'product_type', v_ptype,
    'tags', v_tags, 'send_tags', v_s.send_tags, 'status', v_status, 'active_variants', v_active,
    'options', v_options, 'variants', v_variants, 'files', v_files,
    'listing_on', coalesce(v_l.is_on, false), 'blocks', v_blocks);
  return v_out || jsonb_build_object('send_images', v_s.send_images, 'origin', v_sp.origin, 'hash', md5((v_out - 'blocks' - 'listing_on')::text));   -- shop-img-off-1: send_images 는 hash 밖(켜진 스토어 hash 보존) · EF 두 번째 안전띠가 읽는다 · shop-new-1: origin 도 hash 밖(행 없음 = null · 보는 사람용)
end;
$function$;

-- ═══ ④ family_image_update — 패밀리 사진 쓰기 창구(판정 1186 · 1187) ═══
create function public.family_image_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_sku      text;
  v_key      text;
  v_fam      public.product_family%rowtype;
  v_img      record;
  v_iid      text;
  v_img_id   uuid;
  v_badl     boolean;
  v_ids      uuid[];
  v_path     text;
  v_fld      text;
  v_seen     text[] := '{}';          -- 'I|<경로>' · '<family id>|img|<사진 id>' · '<family id>|order'
  v_keys     text[];
  v_unacked  text[];
  c_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 1186 · product_update 와 같은 열쇠)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then
    raise exception 'No changes given — nothing was saved';
  end if;
  if v_n > 200 then
    raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', v_n;
  end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if coalesce(v_c->>'op', '') not in ('family_image_add', 'family_image_off', 'family_image_order') then
      raise exception 'Unknown op "%" — family_image_add, family_image_off or family_image_order — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_sku := trim(coalesce(v_c->>'family_sku', ''));
    v_key := case when v_sku = '' then '(family)' else v_sku end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'applied', false);
    v_fam := null;
    select * into v_fam from public.product_family f where f.sku = v_sku;
    if v_fam.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('Family %s does not exist — nothing was saved', v_key));
      continue;
    end if;

    if v_op = 'family_image_add' then
      -- {family_sku, storage_path, content_type, byte_size?, width?, height?, file_name?} — 경로는 <패밀리 id>/… · 저장소에 실재해야 등록 · 꺼진 같은 경로는 켠다 · 대표는 없다(표지 = web_image_id)
      v_path := trim(coalesce(v_c->>'storage_path', ''));
      if v_path = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_missing', 'sku', v_sku, 'code', 'image_path_missing', 'message', format('Family %s: the image has no storage path — nothing was saved', v_sku));
        continue;
      end if;
      if ('I|' || v_path) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_path, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s appears twice in this call — nothing was saved', v_path));
        continue;
      end if;
      v_seen := v_seen || ('I|' || v_path);
      if left(v_path, 37) <> v_fam.id::text || '/' or length(v_path) < 38 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_mismatch:' || v_path, 'sku', v_sku, 'code', 'image_path_mismatch', 'message', format('Image %s is not stored under the folder of family %s (%s/…) — nothing was saved', v_path, v_sku, v_fam.id));
      end if;
      if coalesce(v_c->>'content_type', '') not in ('image/jpeg', 'image/png', 'image/webp') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_type_invalid:' || v_path, 'sku', v_sku, 'code', 'image_type_invalid', 'message', format('Image %s: only JPEG, PNG and WebP are accepted (got %s) — nothing was saved', v_path, coalesce(v_c->>'content_type', 'nothing')));
      end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'product-images' and o.name = v_path) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_object_missing:' || v_path, 'sku', v_sku, 'code', 'image_object_missing', 'message', format('Image %s is not in the product-images bucket — upload it first — nothing was saved', v_path));
      end if;
      select i.id, i.is_active, i.family_id into v_img from public.product_image i where i.storage_path = v_path;
      if v_img.id is not null and (v_img.is_active or v_img.family_id is distinct from v_fam.id) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_exists:' || v_path, 'sku', v_sku, 'code', 'image_exists', 'message', format('Image %s is already registered — nothing was saved', v_path));
      end if;
      foreach v_fld in array array['byte_size', 'width', 'height'] loop
        if v_c ? v_fld and v_c->>v_fld is not null and ((v_c->>v_fld) !~ '^[0-9]{1,9}$' or (v_c->>v_fld)::bigint <= 0) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_fld || ':' || v_path, 'sku', v_sku, 'code', 'value_invalid', 'message', format('Image %s: %s must be a whole number above 0 — nothing was saved', v_path, v_fld));
        end if;
      end loop;

    elsif v_op = 'family_image_off' then
      -- {family_sku, image_id} — 켜진 줄만 · 끈다 = is_active false · 파일은 지우지 않는다(판정 188 꼴) · 웹 대표면 경고 뒤 web_image_id 도 비운다(판정 1187)
      v_iid := trim(coalesce(v_c->>'image_id', ''));
      v_img_id := null;
      if v_iid ~ c_uuid then
        select i.id into v_img_id from public.product_image i where i.family_id = v_fam.id and i.id = v_iid::uuid and i.is_active;
      end if;
      if v_img_id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:' || coalesce(nullif(v_iid, ''), '(none)'), 'sku', v_sku, 'code', 'image_not_found', 'message', format('Family %s has no active family image %s — nothing was saved', v_sku, coalesce(nullif(v_iid, ''), '(none)')));
        continue;
      end if;
      if (v_fam.id::text || '|img|' || v_img_id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_img_id::text, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s of family %s is changed twice in this call — nothing was saved', v_img_id, v_sku));
        continue;
      end if;
      v_seen := v_seen || (v_fam.id::text || '|img|' || v_img_id::text);
      if v_fam.web_image_id = v_img_id then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':family_web_image_off:' || v_img_id::text, 'sku', v_sku, 'code', 'family_web_image_off', 'message', format('Image %s is the web image of family %s — turning it off also clears the web image, and the web then shows the first variant photo until another one is picked', v_img_id, v_sku));
      end if;

    else
      -- family_image_order {family_sku, image_ids[]} — 적은 순서대로 sort_order 1, 2, 3 … · 전부 이 패밀리의 켜진 패밀리 사진이어야 한다
      if (v_fam.id::text || '|order') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:order', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Family %s: the image order is set twice in this call — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (v_fam.id::text || '|order');
      v_badl := jsonb_typeof(v_c->'image_ids') is distinct from 'array';                          -- or 는 짧게 끊지 않는다 — 꼴 검사와 길이 · 캐스트를 가른다
      if not v_badl then
        v_badl := jsonb_array_length(v_c->'image_ids') = 0 or exists (select 1 from jsonb_array_elements(v_c->'image_ids') as t(x) where jsonb_typeof(x) <> 'string' or trim(x #>> '{}') !~ c_uuid);
      end if;
      if v_badl then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:(none)', 'sku', v_sku, 'code', 'image_not_found', 'message', format('Family %s: family_image_order needs a list of image ids — nothing was saved', v_sku));
        continue;
      end if;
      select coalesce(array_agg(trim(x)::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(v_c->'image_ids') with ordinality as t(x, o);
      if (select count(distinct u) from unnest(v_ids) u) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:order', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Family %s: family_image_order lists an image twice — nothing was saved', v_sku));
        continue;
      end if;
      if (select count(*) from public.product_image i where i.family_id = v_fam.id and i.is_active and i.id = any(v_ids)) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:order', 'sku', v_sku, 'code', 'image_not_found', 'message', format('Family %s: family_image_order names an image that is not an active family image of this family — nothing was saved', v_sku));
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

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션
  v_i := 0;
  begin
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op';
      select * into v_fam from public.product_family f where f.sku = trim(v_c->>'family_sku');
      if v_op = 'family_image_add' then
        v_path := trim(v_c->>'storage_path');
        if exists (select 1 from public.product_image i where i.storage_path = v_path) then
          update public.product_image set is_active = true, content_type = v_c->>'content_type', byte_size = (v_c->>'byte_size')::bigint, width = (v_c->>'width')::int, height = (v_c->>'height')::int,
                 file_name = nullif(trim(v_c->>'file_name'), ''), updated_by = v_staff
           where storage_path = v_path and family_id = v_fam.id;
        else
          insert into public.product_image (family_id, storage_path, content_type, byte_size, width, height, file_name, source, updated_by, is_primary, sort_order)
          values (v_fam.id, v_path, v_c->>'content_type', (v_c->>'byte_size')::bigint, (v_c->>'width')::int, (v_c->>'height')::int, nullif(trim(v_c->>'file_name'), ''), 'manual', v_staff, false,
                  coalesce((select max(q.sort_order) + 1 from public.product_image q where q.family_id = v_fam.id), 1));
        end if;
      elsif v_op = 'family_image_off' then
        update public.product_image set is_active = false, updated_by = v_staff where family_id = v_fam.id and id = trim(v_c->>'image_id')::uuid;
        update public.product_family set web_image_id = null where id = v_fam.id and web_image_id = trim(v_c->>'image_id')::uuid;    -- 판정 1187: 끄기의 일부 · product_family_shop_queue_u 가 큐를 넣는다
      else
        select coalesce(array_agg(trim(x)::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(v_c->'image_ids') with ordinality as t(x, o);
        update public.product_image i set sort_order = u.o, updated_by = v_staff from unnest(v_ids) with ordinality as u(id, o) where i.id = u.id and i.family_id = v_fam.id;
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Someone just registered one of these images (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$function$;
revoke all on function public.family_image_update(jsonb, boolean, text[]) from public, anon, service_role;
grant execute on function public.family_image_update(jsonb, boolean, text[]) to authenticated;
comment on function public.family_image_update(jsonb, boolean, text[]) is
  '⭐ 패밀리 사진 쓰기 창구(shop-photo-imp-1 · 판정 1186 · 1187 · 2026-11-11) — 문 = master(첫 줄) · definer · p_commit false = 미리 보기 · 반환 {committed, changes, blocks, warnings, unacked}(product_update 와 같은 꼴) · op family_image_add {family_sku, storage_path, content_type, byte_size?, width?, height?, file_name?}(경로 <패밀리 id>/… · 저장소에 실재 · 꺼진 같은 경로는 켠다 · 대표 없음) · family_image_off {family_sku, image_id}(끄기 = is_active false · 파일은 남는다 · 웹 대표면 경고 family_web_image_off → ack 뒤 web_image_id 도 비운다) · family_image_order {family_sku, image_ids[]} · 제품 사진은 product_update 의 image_* op';

-- ═══ ⑤ product_image — family_id · 제약 (여기부터 ACCESS EXCLUSIVE) ═══
alter table public.product_image
  add column family_id uuid references public.product_family (id) on delete no action,
  alter column product_id drop not null,
  add constraint product_image_owner_ck          check ((product_id is null) <> (family_id is null)),
  add constraint product_image_family_primary_ck check (family_id is null or not is_primary),
  add constraint product_image_folder_ck         check (left(storage_path, 36) = coalesce(product_id, family_id)::text),
  drop constraint product_image_source_ck,
  add constraint product_image_source_ck         check (source in ('cin7', 'manual', 'shopify'));
create index product_image_family_idx on public.product_image (family_id) where family_id is not null;
comment on column public.product_image.family_id is '패밀리 사진의 주인(shop-photo-imp-1 · 판정 1179) — product_id XOR family_id(product_image_owner_ck) · 패밀리 사진은 is_primary 늘 false(표지는 product_family.web_image_id) · 경로 <패밀리 id>/<파일> · 쓰기는 family_image_update · source shopify = Shopify 에서 가져온 사진(deferred 387)';

-- ═══ ⑥ 저장소 정책 — 폴더 첫 칸 = product.id 또는 product_family.id (storage.objects ACCESS EXCLUSIVE · 한 문장) ═══
do $$
begin
  execute 'drop policy if exists product_images_insert on storage.objects';
  execute 'drop policy if exists product_images_update on storage.objects';
  execute $p$create policy product_images_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'product-images' and (select public.ims_can_write('master'))
                and (exists (select 1 from public.product p where p.id::text = (storage.foldername(objects.name))[1])
                     or exists (select 1 from public.product_family f where f.id::text = (storage.foldername(objects.name))[1])))$p$;
  execute $p$create policy product_images_update on storage.objects for update to authenticated
    using (bucket_id = 'product-images' and (select public.ims_can_write('master')))
    with check (bucket_id = 'product-images' and (select public.ims_can_write('master'))
                and (exists (select 1 from public.product p where p.id::text = (storage.foldername(objects.name))[1])
                     or exists (select 1 from public.product_family f where f.id::text = (storage.foldername(objects.name))[1])))$p$;
end $$;

-- ═══ ⑦ 착지 검사 ═══
do $$
declare v_n int; v_bad text;
begin
  select count(*) into v_n from pg_constraint c where c.conrelid = 'public.product_image'::regclass
     and c.conname in ('product_image_owner_ck', 'product_image_family_primary_ck', 'product_image_folder_ck', 'product_image_source_ck', 'product_image_family_id_fkey');
  if v_n <> 5 then raise exception 'shop-photo-imp-1 ⑦ product_image constraints: expected 5, found %', v_n; end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.product_image'::regclass and c.conname = 'product_image_source_ck') not like '%shopify%' then
    raise exception 'shop-photo-imp-1 ⑦ product_image_source_ck does not accept shopify';
  end if;
  if (select a.attnotnull from pg_attribute a where a.attrelid = 'public.product_image'::regclass and a.attname = 'product_id') then
    raise exception 'shop-photo-imp-1 ⑦ product_image.product_id is still NOT NULL';
  end if;
  select count(*) into v_n from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('product_images_insert', 'product_images_update') and with_check like '%product_family%';
  if v_n <> 2 then raise exception 'shop-photo-imp-1 ⑦ storage policies with the family folder: expected 2, found %', v_n; end if;
  select count(*) into v_n from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'product_images_delete';
  if v_n <> 1 then raise exception 'shop-photo-imp-1 ⑦ product_images_delete policy is gone'; end if;
  select string_agg(x.n, ', ') into v_bad
    from (values ('shop_queue_trigger()', 'ff5ccbdd39a3748be1ed4b7f1058c71d'), ('shop_listing_set(jsonb,boolean,text[])', '52c6a93374eb8ee0ccedb53edcf2c74a'), ('shop_product_payload(uuid,uuid,uuid)', '72a620cb1da4cca7394332d8008731a3')) as x(n, m)
   where (select md5(p.prosrc) from pg_proc p where p.oid = ('public.' || x.n)::regprocedure) is distinct from x.m;
  if v_bad is not null then raise exception 'shop-photo-imp-1 ⑦ republished body md5 mismatch: %', v_bad; end if;
  if not has_function_privilege('authenticated', 'public.family_image_update(jsonb,boolean,text[])', 'execute') or has_function_privilege('anon', 'public.family_image_update(jsonb,boolean,text[])', 'execute')
     or has_function_privilege('service_role', 'public.family_image_update(jsonb,boolean,text[])', 'execute') then
    raise exception 'shop-photo-imp-1 ⑦ family_image_update acl is %', (select p.proacl::text from pg_proc p where p.oid = 'public.family_image_update(jsonb,boolean,text[])'::regprocedure);
  end if;
  if (select count(*) from public.product_image i where i.family_id is not null) <> 0 then
    raise exception 'shop-photo-imp-1 ⑦ family images already exist — this migration expects none';
  end if;
end $$;
