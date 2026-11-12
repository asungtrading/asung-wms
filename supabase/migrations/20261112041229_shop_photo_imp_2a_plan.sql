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

-- shop-photo-imp-2a — Shopify 전용 사진 가져오기: 계획 표 · 적재 · 실행 창구 · DB dry run (판정 1180 ~ 1184 · 1195 ~ 1197 · Caleb 2026-11-11 · 지시서 ~/asung/prompts/shop-photo-imp-2.md · 이견 답 · deferred 387 가져오기 길 ②-a)
--   판정 1180  변형이 하나뿐인 패밀리 상품의 사진(표지 제외)은 그 변형(제품)으로 — 「하나」 = 켜진 구성원이 정확히 하나
--   판정 1181 · 1196  패밀리 미지정 사진의 파일 이름이 같은 패밀리 구성원 SKU(`SKU` · `SKU_…` · `SKU-…` · 겹치면 더 긴 SKU · **꺼진 구성원도 포함**)면 그 제품으로 · 없으면 패밀리 자리
--   판정 1182  가져오기 = 계획 표(노트북 조사 결과를 한 번 적재) + EF(2b · 실행 날 Shopify 를 다시 읽어 확인)
--   판정 1183  짝(shop_media): 가져온 사진은 원래 스토어마다 한 줄 · IMS 에 이미 있는 「same」 사진도 스토어마다 — 한 스토어에서 한 IMS 사진에 Shopify 사진이 여럿이면 하나만 심고 나머지는 dup(목록으로 보인다 · 1053)
--   판정 1184  IMS 가 못 받는 사진(gif · 5 MB 넘음)은 건너뛰고 표시만(skip_reason) · 판정 1141 gray 도 표시만
--   판정 1195  dry run 은 사진을 보내는 켜진 listing 마다 가져온 뒤 Shopify 로 갈 files 가 어떻게 달라지는지 보인다 — 실제 쓰기 창구와 같은 몸(shop_photo_apply_)을 되돌아가는 안쪽 블록에서 돌려 payload 를 읽는다(저장 0)
--   판정 1197  켜진 대표가 없는 제품은 처음 가져온 사진이 대표(product_update image_add 와 같은 규칙) · 패밀리 사진은 늘 대표 아님
--   무엇:
--     ① 표 셋 — shop_photo_plan(가져올 사진 한 줄씩) · shop_photo_pair(Shopify media ↔ 계획 줄 또는 IMS 사진) · shop_photo_run(적재 · 회차 기록)
--          RLS 켬 · 정책 없음 · 권한은 service_role select 뿐(EF 가 REST 로 읽는다) · 쓰기는 아래 창구만
--     ② shop_photo_plan_load(p_plan, p_replace) — 적재(postgres 만 · psql) · 갈 곳 · 건너뜀 · dup 을 DB 가 셈하고 p_plan.expect 와 다르면 통째로 거부 · 두 번 적재 거부
--          나갈 길: 아직 아무것도 가져오지 않았으면(claimed · done 0 · 짝 done 0) p_replace => true 로 바꿔 싣는다
--     ③ shop_photo_verify_mark · shop_photo_claim · shop_photo_done · shop_photo_fail · shop_photo_pair_mark · shop_photo_run_add — EF(service_role) 창구
--          사진 행(product_image · source shopify)과 짝(shop_media)은 shop_photo_apply_ 한 몸 · 한 트랜잭션 — 큐 트리거가 깨운 push 가 짝 없는 사진을 새로 올리지 않게
--          failed 의 나갈 길: shop_photo_claim(p_retry_failed => true) · 확인 실패(verify_ok false)의 나갈 길: shop_photo_verify_mark 를 다시
--     ④ shop_photo_dry() — 읽기(저장 0 · service_role · postgres)
--   경로 = <주인 id>/shopify-<열쇠 md5>.<확장자>(IMS 내부 이름 · Shopify 로 올리는 이름 SKU · SKU_2(1052)와 무관 · 결정적이라 두 번 써도 한 줄)
--   순서(1140): 그 주인의 지금 max(sort_order · 꺼진 줄 포함) 뒤에 계획 순서(표지 먼저 → Shopify 순서)
--   무접촉: product_update · family_image_update · shop_product_payload · shop_queue_trigger · shop_media 표 꼴 · 지금 있는 사진 행 · 버킷 설정 · EF
--   컷오버 뒤라 거래 표 FK 는 없다(product · product_family · product_image · shop_store · ims_staff 마스터끼리) — 지우는 순서: shop_photo_pair → shop_photo_plan → shop_photo_run · product_image 행을 지우려면 앞 둘이 먼저
--   순서: 함수(잠금 없음 · plpgsql 은 만들 때 표를 안 본다)를 먼저 → 표(FK 가 product · product_family · product_image · shop_store 에 SHARE ROW EXCLUSIVE 를 잡는다)는 끝에 — 잠금 구간을 짧게

-- ═══ ② 적재 ═══
create function public.shop_photo_plan_load(p_plan jsonb, p_replace boolean default false)
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare
  v_e jsonb; v_kind text; v_owner text; v_fam uuid; v_prod uuid; v_rule text; v_ids uuid[]; v_store uuid;
  v_ct text; v_size bigint; v_key text; v_ext text; v_skip text; v_n int; v_counts jsonb; v_bad text;
begin
  if jsonb_typeof(p_plan->'pics') is distinct from 'array' or jsonb_typeof(p_plan->'same') is distinct from 'array' or jsonb_typeof(p_plan->'expect') is distinct from 'object' then
    raise exception 'The plan must be an object with pics[], same[] and expect{} — nothing was loaded';
  end if;
  select count(*) into v_n from public.shop_photo_plan;
  if v_n > 0 then
    if not p_replace then
      raise exception 'The Shopify photo plan is already loaded (% photos) — loading it twice is refused. To replace a plan nothing has been imported from yet, call shop_photo_plan_load(plan, p_replace => true) — nothing was changed', v_n;
    end if;
    if exists (select 1 from public.shop_photo_plan pl where pl.status in ('claimed', 'done')) or exists (select 1 from public.shop_photo_pair pr where pr.status = 'done') then
      raise exception 'The Shopify photo plan is already in use (photos imported or pairs written) — it cannot be replaced any more — nothing was changed';
    end if;
    delete from public.shop_photo_pair where id > 0;
    delete from public.shop_photo_plan where id > 0;
  end if;

  for v_e in select x.e from jsonb_array_elements(p_plan->'pics') as x(e) loop
    v_kind := v_e->>'kind';  v_owner := v_e->>'owner';  v_fam := null;  v_prod := null;  v_rule := null;
    select s.id into v_store from public.shop_store s where s.code = v_e->>'st';
    if v_store is null then raise exception 'Photo %: store "%" is not in shop_store — nothing was loaded', v_e->>'n', v_e->>'st'; end if;
    if v_kind in ('fam_cover', 'fam_unassigned', 'fam_1var_unread') then
      select f.id into v_fam from public.product_family f where f.sku = v_owner;
      if v_fam is null then raise exception 'Photo %: family % is not in IMS — nothing was loaded', v_e->>'n', v_owner; end if;
      if v_kind = 'fam_cover' then
        v_rule := 'cover';
      elsif v_kind = 'fam_1var_unread' then                                                        -- 판정 1180: 켜진 구성원이 정확히 하나
        select array_agg(p.id) into v_ids from public.product p where p.family_id = v_fam and p.parent_product_id is null and p.is_active;
        if coalesce(cardinality(v_ids), 0) <> 1 then
          raise exception 'Photo %: family % was read as a one-variant product but has % active members in IMS — nothing was loaded', v_e->>'n', v_owner, coalesce(cardinality(v_ids), 0);
        end if;
        v_prod := v_ids[1];  v_fam := null;  v_rule := '1180';
      else                                                                                         -- 판정 1181 · 1196: 파일 이름 = 구성원 SKU · SKU_… · SKU-…(겹치면 더 긴 SKU · 꺼진 구성원 포함)
        select array_agg(distinct h.id) into v_ids
          from jsonb_array_elements_text(v_e->'names') as nm(fn)
          cross join lateral (select p.id from public.product p
                               where p.family_id = v_fam and p.parent_product_id is null
                                 and (upper(nm.fn) = upper(p.sku) or left(upper(nm.fn), length(p.sku) + 1) in (upper(p.sku) || '_', upper(p.sku) || '-'))
                               order by length(p.sku) desc, p.sku limit 1) h;
        if coalesce(cardinality(v_ids), 0) > 1 then
          raise exception 'Photo %: the file names of this picture point at % different members of family % — nothing was loaded', v_e->>'n', cardinality(v_ids), v_owner;
        elsif coalesce(cardinality(v_ids), 0) = 1 then
          v_prod := v_ids[1];  v_fam := null;  v_rule := '1181';
        else
          v_rule := 'family';
        end if;
      end if;
    elsif v_kind in ('variant', 'single') then
      select p.id into v_prod from public.product p where p.sku = v_e->>'tgt';
      if v_prod is null then raise exception 'Photo %: product % is not in IMS — nothing was loaded', v_e->>'n', v_e->>'tgt'; end if;
      v_rule := v_kind;
    else
      raise exception 'Photo %: unknown kind "%" — nothing was loaded', v_e->>'n', coalesce(v_kind, '(none)');
    end if;
    v_ct := lower(coalesce(v_e->>'ct', ''));  v_size := (v_e->>'size')::bigint;
    v_ext := case v_ct when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end;
    v_skip := case when v_ext is null then 'type' when v_size > 5242880 then 'too_large' end;                 -- 판정 1184: 버킷 product-images 가 받는 것만(jpeg · png · webp · 5 MB)
    v_key := case when (v_e->>'md5') ~ '^[0-9a-f]{32}$' then v_e->>'md5' else v_e->>'file_md5' end;
    insert into public.shop_photo_plan (load_n, pic_kind, rule, owner_sku, family_id, product_id, gray, md5_key, file_md5, byte_size, content_type, width, height, file_name,
                                        src_store_id, src_product_gid, src_media_gid, src_url, src_pos, storage_path, status, skip_reason)
    values ((v_e->>'n')::int, v_kind, v_rule, v_owner, v_fam, v_prod, coalesce((v_e->>'gray')::boolean, false), v_e->>'md5', v_e->>'file_md5', v_size, v_ct,
            nullif((v_e->>'w')::int, 0), nullif((v_e->>'h')::int, 0), regexp_replace(split_part(v_e->>'url', '?', 1), '^.*/', ''),
            v_store, v_e->>'g', v_e->>'gid', v_e->>'url', (v_e->>'pos')::int,
            case when v_ext is not null then coalesce(v_prod, v_fam)::text || '/shopify-' || v_key || '.' || v_ext end,
            case when v_skip is null then 'planned' else 'skipped' end, v_skip);
  end loop;
  -- 순서: 주인마다 표지 먼저 → Shopify 순서
  update public.shop_photo_plan pl set seq = x.rn
    from (select q.id, row_number() over (partition by coalesce(q.family_id, q.product_id) order by (q.rule = 'cover') desc, q.src_pos, q.id) as rn from public.shop_photo_plan q) x
   where pl.id = x.id;

  -- 짝: 가져올 사진의 스토어별 media
  insert into public.shop_photo_pair (store_id, product_gid, media_gid, url, pos, pair_kind, plan_id)
  select s.id, g.x->>'g', g.x->>'gid', g.x->>'url', (g.x->>'pos')::int, 'import', pl.id
    from jsonb_array_elements(p_plan->'pics') as e(x)
    cross join lateral jsonb_array_elements(e.x->'gids') as g(x)
    join public.shop_photo_plan pl on pl.load_n = (e.x->>'n')::int
    join public.shop_store s on s.code = g.x->>'st';
  get diagnostics v_n = row_count;
  if v_n <> (select coalesce(sum(jsonb_array_length(e.x->'gids')), 0) from jsonb_array_elements(p_plan->'pics') as e(x)) then
    raise exception 'Import pairs: % rows were written but the plan has a different number (unknown store code?) — nothing was loaded', v_n;
  end if;
  -- 짝: IMS 에 이미 있는 사진(same)
  insert into public.shop_photo_pair (store_id, product_gid, media_gid, url, pos, pair_kind, product_image_id, how)
  select s.id, e.x->>'g', e.x->>'gid', e.x->>'url', (e.x->>'pos')::int, 'same', i.id, e.x->>'how'
    from jsonb_array_elements(p_plan->'same') as e(x)
    join public.shop_store s on s.code = e.x->>'st'
    join public.product_image i on i.id = (e.x->>'img')::uuid;
  get diagnostics v_n = row_count;
  if v_n <> jsonb_array_length(p_plan->'same') then
    raise exception 'Same pairs: % of % rows found their store and IMS photo — the rest point at a photo that is not in IMS any more — nothing was loaded', v_n, jsonb_array_length(p_plan->'same');
  end if;
  -- dup: 한 스토어에서 같은 그림(같은 계획 줄 · 같은 IMS 사진)에 Shopify media 가 여럿이면 하나만 남긴다(shop_media 는 스토어 × 사진 하나)
  update public.shop_photo_pair pr set status = 'dup', note = 'another Shopify image of this store is the same picture - only one can be paired'
    from (select q.id, row_number() over (partition by q.store_id, q.plan_id order by (q.store_id = pl.src_store_id and q.media_gid = pl.src_media_gid) desc, q.pos, q.media_gid) as rn
            from public.shop_photo_pair q join public.shop_photo_plan pl on pl.id = q.plan_id where q.pair_kind = 'import') x
   where pr.id = x.id and x.rn > 1;
  update public.shop_photo_pair pr set status = 'dup', note = 'another Shopify image of this store matches the same IMS photo - only one can be paired'
    from (select q.id, row_number() over (partition by q.store_id, q.product_image_id order by (q.how = 'same_md5') desc, q.pos, q.media_gid) as rn
            from public.shop_photo_pair q where q.pair_kind = 'same') x
   where pr.id = x.id and x.rn > 1;
  update public.shop_photo_pair pr set status = 'skipped', note = 'the photo is not imported (' || pl.skip_reason || ')'
    from public.shop_photo_plan pl
   where pl.id = pr.plan_id and pl.status = 'skipped';

  select jsonb_build_object(
      'total', count(*), 'cover', count(*) filter (where pl.rule = 'cover'), 'family', count(*) filter (where pl.rule = 'family'), 'r1180', count(*) filter (where pl.rule = '1180'),
      'r1181', count(*) filter (where pl.rule = '1181'), 'variant', count(*) filter (where pl.rule = 'variant'), 'single', count(*) filter (where pl.rule = 'single'),
      'to_family', count(*) filter (where pl.family_id is not null), 'to_product', count(*) filter (where pl.product_id is not null),
      'skipped', count(*) filter (where pl.status = 'skipped'), 'gray', count(*) filter (where pl.gray)) into v_counts
    from public.shop_photo_plan pl;
  select v_counts || jsonb_build_object(
      'pair_same', count(*) filter (where pr.pair_kind = 'same'), 'pair_same_planned', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'planned'), 'pair_same_dup', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'dup'),
      'pair_import', count(*) filter (where pr.pair_kind = 'import'), 'pair_import_planned', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'planned'),
      'pair_import_dup', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'dup'), 'pair_import_skipped', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'skipped')) into v_counts
    from public.shop_photo_pair pr;
  select string_agg(format('%s: expected %s, counted %s', e.key, e.value, coalesce(v_counts->>e.key, '(none)')), ' · ' order by e.key) into v_bad
    from jsonb_each_text(p_plan->'expect') e where (v_counts->>e.key) is distinct from e.value;
  if v_bad is not null then
    raise exception 'The plan does not add up to what was decided — % — nothing was loaded', v_bad;
  end if;
  insert into public.shop_photo_run (mode, finished_at, ok, counts) values ('load', now(), true, v_counts || jsonb_build_object('source', p_plan->'source', 'replaced', p_replace));
  return v_counts;
end;
$function$;
revoke all on function public.shop_photo_plan_load(jsonb, boolean) from public, anon, authenticated, service_role;
comment on function public.shop_photo_plan_load(jsonb, boolean) is
  'Shopify 전용 사진 가져오기 계획 적재(shop-photo-imp-2a · 판정 1180 · 1181 · 1184 · 1196) — postgres(psql)만 · p_plan {source, expect, pics[], same[]}(scripts/shop-photo-plan-build.py 가 만든다) · 갈 곳 · 건너뜀 · dup 을 DB 가 셈하고 expect 와 다르면 통째로 거부 · 이미 적재돼 있으면 거부(아무것도 가져오기 전이면 p_replace => true 로 바꿔 싣는다) · 반환 = 센 수';

-- ═══ ③ 실행 창구(EF · service_role) ═══
-- 속 몸: 계획 줄 → 사진 행(source shopify) + 짝(shop_media) — 한 문장의 insert 라 큐 트리거는 한 번 · 실행권 없음(done · dry 가 definer 로 부른다)
create function public.shop_photo_apply_(p_ids bigint[])
  returns void
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
begin
  -- 같은 경로의 사진 행이 이미 있으면 그 행을 받아들인다(두 번 쓰지 않는다)
  update public.shop_photo_plan pl set status = 'done', done_at = now(), product_image_id = i.id, error = null
    from public.product_image i
   where i.storage_path = pl.storage_path and pl.id = any(p_ids) and pl.status not in ('done', 'skipped');
  with ins as (
    insert into public.product_image (product_id, family_id, storage_path, content_type, byte_size, width, height, file_name, source, is_primary, sort_order)
    select pl.product_id, pl.family_id, pl.storage_path, pl.content_type, pl.byte_size, pl.width, pl.height, pl.file_name, 'shopify',
           -- 판정 1197: 켜진 대표가 없는 제품은 처음 가져온 사진이 대표 · 패밀리 사진은 늘 대표 아님
           pl.product_id is not null
             and row_number() over (partition by coalesce(pl.family_id, pl.product_id) order by pl.seq, pl.id) = 1
             and not exists (select 1 from public.product_image q where q.product_id = pl.product_id and q.is_active and q.is_primary),
           -- 판정 1140: IMS 사진 뒤에(꺼진 줄 포함 max) 계획 순서대로
           coalesce((select max(q.sort_order) from public.product_image q where q.product_id = pl.product_id or q.family_id = pl.family_id), 0)
             + row_number() over (partition by coalesce(pl.family_id, pl.product_id) order by pl.seq, pl.id)
      from public.shop_photo_plan pl
     where pl.id = any(p_ids) and pl.status not in ('done', 'skipped')
    returning id, storage_path)
  update public.shop_photo_plan pl set status = 'done', done_at = now(), product_image_id = ins.id, error = null
    from ins
   where pl.storage_path = ins.storage_path;
  -- 짝(판정 1183): 그 사진이 있던 스토어마다 한 줄 — shop_media 가 이미 그 gid 나 그 사진을 다른 짝으로 갖고 있으면 두고 conflict
  insert into public.shop_media (store_id, product_image_id, shopify_file_gid)
  select pr.store_id, pl.product_image_id, pr.media_gid
    from public.shop_photo_pair pr join public.shop_photo_plan pl on pl.id = pr.plan_id
   where pr.plan_id = any(p_ids) and pr.status = 'planned' and pl.status = 'done'
     and not exists (select 1 from public.shop_media m where m.store_id = pr.store_id and (m.shopify_file_gid = pr.media_gid or m.product_image_id = pl.product_image_id));
  update public.shop_photo_pair pr
     set status = case when exists (select 1 from public.shop_media m where m.store_id = pr.store_id and m.shopify_file_gid = pr.media_gid and m.product_image_id = pl.product_image_id) then 'done' else 'conflict' end,
         note = case when exists (select 1 from public.shop_media m where m.store_id = pr.store_id and m.shopify_file_gid = pr.media_gid and m.product_image_id = pl.product_image_id) then null
                     else 'shop_media already pairs this Shopify image or this IMS photo with something else in this store' end,
         done_at = now()
    from public.shop_photo_plan pl
   where pl.id = pr.plan_id and pr.plan_id = any(p_ids) and pr.status = 'planned' and pl.status = 'done';
end;
$function$;
revoke all on function public.shop_photo_apply_(bigint[]) from public, anon, authenticated, service_role;
comment on function public.shop_photo_apply_(bigint[]) is 'shop-photo-imp-2a 속 몸 — 계획 줄 → product_image(source shopify · 순서 IMS 뒤 · 대표 규칙 1197) + shop_media 짝(1183) · 실행권 없음(shop_photo_done · shop_photo_dry 가 부른다)';

create function public.shop_photo_verify_mark(p_rows jsonb)
  returns integer
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_n int;
begin
  update public.shop_photo_plan pl set verified_at = now(), verify_ok = x.ok, verify_note = case when x.ok then null else left(coalesce(x.note, 'not confirmed'), 500) end
    from jsonb_to_recordset(p_rows) as x(id bigint, ok boolean, note text)
   where pl.id = x.id and x.ok is not null and pl.status in ('planned', 'failed');
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;
revoke all on function public.shop_photo_verify_mark(jsonb) from public, anon, authenticated;
grant execute on function public.shop_photo_verify_mark(jsonb) to service_role;
comment on function public.shop_photo_verify_mark(jsonb) is 'shop-photo-imp-2a — EF 가 실행 날 Shopify 를 다시 읽은 결과를 계획 줄에 적는다 [{id, ok, note}] · ok true 인 줄만 shop_photo_claim 이 내준다 · 다시 부르면 덮어쓴다(확인 실패의 나갈 길) · service_role 만';

create function public.shop_photo_claim(p_owners integer default 60, p_stale_minutes integer default 30, p_retry_failed boolean default false, p_only bigint[] default null)
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_ids bigint[]; v_out jsonb;
begin
  select array_agg(c.id) into v_ids
    from (select pl.id
            from public.shop_photo_plan pl
           where pl.verify_ok and (p_only is null or pl.id = any(p_only))
             and (pl.status = 'planned' or (pl.status = 'claimed' and pl.claimed_at < now() - make_interval(mins => greatest(p_stale_minutes, 1))) or (p_retry_failed and pl.status = 'failed'))
             and coalesce(pl.family_id, pl.product_id) in (
                   select o.owner from (select coalesce(q.family_id, q.product_id) as owner, min(q.id) as first_id
                                          from public.shop_photo_plan q
                                         where q.verify_ok and (p_only is null or q.id = any(p_only)) and (q.status = 'planned' or (q.status = 'claimed' and q.claimed_at < now() - make_interval(mins => greatest(p_stale_minutes, 1))) or (p_retry_failed and q.status = 'failed'))
                                         group by 1 order by 2 limit greatest(least(p_owners, 500), 1)) o)
           order by pl.id
             for update of pl skip locked) c;
  if v_ids is null then return '[]'::jsonb; end if;
  update public.shop_photo_plan pl set status = 'claimed', claimed_at = now(), attempts = pl.attempts + 1, error = null where pl.id = any(v_ids);
  select coalesce(jsonb_agg(jsonb_build_object('id', pl.id, 'owner_id', coalesce(pl.family_id, pl.product_id), 'family_id', pl.family_id, 'product_id', pl.product_id, 'seq', pl.seq,
           'store', s.code, 'src_url', pl.src_url, 'src_media_gid', pl.src_media_gid, 'file_md5', pl.file_md5, 'byte_size', pl.byte_size, 'content_type', pl.content_type,
           'storage_path', pl.storage_path, 'attempts', pl.attempts) order by coalesce(pl.family_id, pl.product_id), pl.seq, pl.id), '[]'::jsonb) into v_out
    from public.shop_photo_plan pl join public.shop_store s on s.id = pl.src_store_id
   where pl.id = any(v_ids);
  return v_out;
end;
$function$;
revoke all on function public.shop_photo_claim(integer, integer, boolean, bigint[]) from public, anon, authenticated;
grant execute on function public.shop_photo_claim(integer, integer, boolean, bigint[]) to service_role;
comment on function public.shop_photo_claim(integer, integer, boolean, bigint[]) is 'shop-photo-imp-2a — 가져올 사진을 주인(패밀리 · 제품) 단위로 내준다(p_owners 곳 · 확인된 줄만 · planned → claimed · 시도 수 + 1) · p_stale_minutes 넘게 claimed 로 멈춘 줄은 다시 내준다 · p_retry_failed = failed 도 다시(failed 의 나갈 길) · p_only = 그 계획 줄만(몇 곳만 먼저 · 시험은 가짜 줄 id 로만) · service_role 만';

create function public.shop_photo_done(p_rows jsonb)
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_ok bigint[]; v_rej jsonb; v_already int;
begin
  perform 1 from public.shop_photo_plan pl where pl.id in (select (x.e->>'id')::bigint from jsonb_array_elements(p_rows) as x(e)) order by pl.id for update;
  select coalesce(array_agg(t.id) filter (where t.why is null), '{}'),
         coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'reason', t.why)) filter (where t.why is not null and t.why <> 'already_done'), '[]'::jsonb),
         count(*) filter (where t.why = 'already_done')
    into v_ok, v_rej, v_already
    from (select distinct on (x.id) x.id,
                 case when pl.id is null then 'unknown_id'
                      when pl.status = 'done' then 'already_done'
                      when pl.status <> 'claimed' then 'not_claimed (' || pl.status || ')'
                      when x.byte_size is distinct from pl.byte_size then format('byte_size %s differs from the plan (%s)', coalesce(x.byte_size::text, 'missing'), pl.byte_size)
                      when not exists (select 1 from storage.objects o where o.bucket_id = 'product-images' and o.name = pl.storage_path) then 'object_missing (' || pl.storage_path || ')'
                 end as why
            from jsonb_to_recordset(p_rows) as x(id bigint, byte_size bigint, width int, height int)
            left join public.shop_photo_plan pl on pl.id = x.id
           order by x.id) t;
  update public.shop_photo_plan pl set width = coalesce(x.width, pl.width), height = coalesce(x.height, pl.height)
    from jsonb_to_recordset(p_rows) as x(id bigint, byte_size bigint, width int, height int)
   where pl.id = x.id and pl.id = any(v_ok);
  perform public.shop_photo_apply_(v_ok);
  return jsonb_build_object('done', cardinality(v_ok), 'already_done', v_already, 'rejected', v_rej);
end;
$function$;
revoke all on function public.shop_photo_done(jsonb) from public, anon, authenticated;
grant execute on function public.shop_photo_done(jsonb) to service_role;
comment on function public.shop_photo_done(jsonb) is 'shop-photo-imp-2a — 저장소에 올린 사진을 등록 [{id, byte_size, width?, height?}] · claimed 줄만 · 저장소 객체가 실재하고 크기가 계획과 같아야 한다 · 사진 행(source shopify)과 shop_media 짝을 한 트랜잭션에 · 이미 done 인 줄은 다시 쓰지 않는다 · 반환 {done, already_done, rejected[{id, reason}]} · service_role 만';

create function public.shop_photo_fail(p_id bigint, p_error text, p_final boolean default false)
  returns text
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_status text;
begin
  update public.shop_photo_plan pl
     set status = case when p_final or pl.attempts >= 5 then 'failed' else 'planned' end, claimed_at = null, error = left(coalesce(p_error, 'failed'), 500)
   where pl.id = p_id and pl.status = 'claimed'
  returning pl.status into v_status;
  return coalesce(v_status, 'not_claimed');
end;
$function$;
revoke all on function public.shop_photo_fail(bigint, text, boolean) from public, anon, authenticated;
grant execute on function public.shop_photo_fail(bigint, text, boolean) to service_role;
comment on function public.shop_photo_fail(bigint, text, boolean) is 'shop-photo-imp-2a — claimed 줄을 놓는다: 다시 해 볼 것은 planned 로 · p_final 이거나 다섯 번째 시도면 failed(나갈 길 = shop_photo_claim(p_retry_failed => true)) · 반환 = 새 상태 · service_role 만';

create function public.shop_photo_pair_mark(p_rows jsonb)
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_gone int; v_off int; v_seed int; v_conflict int;
begin
  update public.shop_photo_pair pr set status = 'gone', note = 'not on the Shopify product any more', done_at = now()
    from jsonb_to_recordset(p_rows) as x(id bigint, present boolean)
   where pr.id = x.id and x.present is false and pr.status in ('planned', 'dup');
  get diagnostics v_gone = row_count;
  update public.shop_photo_pair pr set status = 'skipped', note = 'the IMS photo is switched off', done_at = now()
    from jsonb_to_recordset(p_rows) as x(id bigint, present boolean)
   where pr.id = x.id and x.present and pr.pair_kind = 'same' and pr.status = 'planned'
     and exists (select 1 from public.product_image i where i.id = pr.product_image_id and not i.is_active);
  get diagnostics v_off = row_count;
  insert into public.shop_media (store_id, product_image_id, shopify_file_gid)
  select pr.store_id, pr.product_image_id, pr.media_gid
    from public.shop_photo_pair pr join jsonb_to_recordset(p_rows) as x(id bigint, present boolean) on x.id = pr.id
   where x.present and pr.pair_kind = 'same' and pr.status = 'planned'
     and not exists (select 1 from public.shop_media m where m.store_id = pr.store_id and (m.shopify_file_gid = pr.media_gid or m.product_image_id = pr.product_image_id));
  get diagnostics v_seed = row_count;
  update public.shop_photo_pair pr
     set status = case when exists (select 1 from public.shop_media m where m.store_id = pr.store_id and m.shopify_file_gid = pr.media_gid and m.product_image_id = pr.product_image_id) then 'done' else 'conflict' end,
         note = case when exists (select 1 from public.shop_media m where m.store_id = pr.store_id and m.shopify_file_gid = pr.media_gid and m.product_image_id = pr.product_image_id) then null
                     else 'shop_media already pairs this Shopify image or this IMS photo with something else in this store' end,
         done_at = now()
    from jsonb_to_recordset(p_rows) as x(id bigint, present boolean)
   where pr.id = x.id and x.present and pr.pair_kind = 'same' and pr.status = 'planned';
  get diagnostics v_conflict = row_count;
  select count(*) into v_conflict from public.shop_photo_pair pr join jsonb_to_recordset(p_rows) as x(id bigint, present boolean) on x.id = pr.id where pr.status = 'conflict';
  return jsonb_build_object('gone', v_gone, 'image_off', v_off, 'seeded', v_seed, 'conflict', v_conflict);
end;
$function$;
revoke all on function public.shop_photo_pair_mark(jsonb) from public, anon, authenticated;
grant execute on function public.shop_photo_pair_mark(jsonb) to service_role;
comment on function public.shop_photo_pair_mark(jsonb) is 'shop-photo-imp-2a — EF 가 Shopify 상품의 media 를 다시 읽은 결과 [{id, present}] · 없으면 gone · same 짝이 있으면 shop_media 에 심는다(이미 같은 짝이면 done · 다른 짝이 있으면 그대로 두고 conflict · IMS 사진이 꺼졌으면 skipped) · import 짝은 present 면 그대로(사진을 등록할 때 심는다) · 반환 {gone, image_off, seeded, conflict} · service_role 만';

create function public.shop_photo_run_add(p_mode text, p_ok boolean, p_counts jsonb default '{}'::jsonb, p_error text default null, p_started_at timestamptz default null)
  returns bigint
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare v_id bigint;
begin
  if p_mode not in ('check', 'pairs', 'move') then raise exception 'mode must be check, pairs or move'; end if;
  insert into public.shop_photo_run (mode, started_at, finished_at, ok, counts, error_note)
  values (p_mode, coalesce(p_started_at, now()), now(), p_ok, coalesce(p_counts, '{}'::jsonb), left(p_error, 1000)) returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.shop_photo_run_add(text, boolean, jsonb, text, timestamptz) from public, anon, authenticated;
grant execute on function public.shop_photo_run_add(text, boolean, jsonb, text, timestamptz) to service_role;
comment on function public.shop_photo_run_add(text, boolean, jsonb, text, timestamptz) is 'shop-photo-imp-2a — EF 회차 기록 한 줄(check · pairs · move) · service_role 만';

-- ═══ ④ dry run(저장 0) ═══
create function public.shop_photo_dry()
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare
  v_plan jsonb; v_pairs jsonb; v_dups jsonb; v_prim jsonb; v_changed jsonb := '[]'::jsonb; v_same text[] := '{}';
  v_l record; v_ids bigint[]; v_before jsonb; v_after jsonb; v_d jsonb; v_n int := 0;
begin
  select jsonb_build_object(
      'total', count(*), 'to_family', count(*) filter (where pl.family_id is not null), 'to_product', count(*) filter (where pl.product_id is not null),
      'by_rule', jsonb_build_object('cover', count(*) filter (where pl.rule = 'cover'), 'family', count(*) filter (where pl.rule = 'family'), '1180', count(*) filter (where pl.rule = '1180'),
                                    '1181', count(*) filter (where pl.rule = '1181'), 'variant', count(*) filter (where pl.rule = 'variant'), 'single', count(*) filter (where pl.rule = 'single')),
      'by_status', jsonb_build_object('planned', count(*) filter (where pl.status = 'planned'), 'claimed', count(*) filter (where pl.status = 'claimed'), 'done', count(*) filter (where pl.status = 'done'),
                                      'failed', count(*) filter (where pl.status = 'failed'), 'skipped', count(*) filter (where pl.status = 'skipped')),
      'to_import', count(*) filter (where pl.status <> 'skipped'), 'owners', count(distinct coalesce(pl.family_id, pl.product_id)) filter (where pl.status <> 'skipped'),
      'gray', count(*) filter (where pl.gray),
      'skipped', coalesce(jsonb_agg(jsonb_build_object('id', pl.id, 'sku', coalesce(f.sku, p.sku), 'reason', pl.skip_reason, 'content_type', pl.content_type, 'byte_size', pl.byte_size, 'url', pl.src_url) order by pl.id)
                            filter (where pl.status = 'skipped'), '[]'::jsonb),
      'verify', jsonb_build_object('not_checked', count(*) filter (where pl.status <> 'skipped' and pl.verified_at is null), 'ok', count(*) filter (where pl.verify_ok),
                                   'failed', coalesce(jsonb_agg(jsonb_build_object('id', pl.id, 'sku', coalesce(f.sku, p.sku), 'note', pl.verify_note, 'url', pl.src_url) order by pl.id) filter (where pl.verify_ok is false), '[]'::jsonb)),
      'failed', coalesce(jsonb_agg(jsonb_build_object('id', pl.id, 'sku', coalesce(f.sku, p.sku), 'error', pl.error, 'attempts', pl.attempts) order by pl.id) filter (where pl.status = 'failed'), '[]'::jsonb))
    into v_plan
    from public.shop_photo_plan pl left join public.product_family f on f.id = pl.family_id left join public.product p on p.id = pl.product_id;
  -- 판정 1197: 켜진 대표가 없어 처음 가져온 사진이 대표가 될 제품
  select coalesce(jsonb_agg(x.sku order by x.sku), '[]'::jsonb) into v_prim
    from (select distinct p.sku from public.shop_photo_plan pl join public.product p on p.id = pl.product_id
           where pl.status in ('planned', 'claimed', 'failed')
             and not exists (select 1 from public.product_image q where q.product_id = pl.product_id and q.is_active and q.is_primary)) x;
  select coalesce(jsonb_object_agg(t.code, t.j), '{}'::jsonb) into v_pairs
    from (select s.code, jsonb_build_object(
                   'import', jsonb_build_object('planned', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'planned'), 'done', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'done'),
                                                'dup', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'dup'), 'skipped', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'skipped'),
                                                'gone', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'gone'), 'conflict', count(*) filter (where pr.pair_kind = 'import' and pr.status = 'conflict')),
                   'same', jsonb_build_object('planned', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'planned'), 'done', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'done'),
                                              'dup', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'dup'), 'skipped', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'skipped'),
                                              'gone', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'gone'), 'conflict', count(*) filter (where pr.pair_kind = 'same' and pr.status = 'conflict')),
                   -- 지금 심으면 shop_media 의 다른 짝과 부딪칠 planned 줄(same 은 사진 · gid 둘 다 · import 는 gid)
                   'would_conflict', count(*) filter (where pr.status = 'planned' and exists (
                        select 1 from public.shop_media m where m.store_id = pr.store_id
                           and ((m.shopify_file_gid = pr.media_gid and m.product_image_id is distinct from pr.product_image_id)
                             or (pr.product_image_id is not null and m.product_image_id = pr.product_image_id and m.shopify_file_gid <> pr.media_gid)))),
                   'shop_media_now', (select count(*) from public.shop_media m where m.store_id = s.id)) as j
            from public.shop_photo_pair pr join public.shop_store s on s.id = pr.store_id group by s.id, s.code) t;
  -- dup 목록: 심지 않는 Shopify 사진(사진을 보내기 시작하면 그 상품에서 빠진다 · 1053)
  select coalesce(jsonb_agg(jsonb_build_object('store', s.code, 'kind', pr.pair_kind, 'sku', coalesce(f.sku, p.sku, ip.sku), 'product_gid', pr.product_gid, 'media_gid', pr.media_gid, 'url', pr.url)
                            order by s.code, coalesce(f.sku, p.sku, ip.sku), pr.pos), '[]'::jsonb) into v_dups
    from public.shop_photo_pair pr join public.shop_store s on s.id = pr.store_id
    left join public.shop_photo_plan pl on pl.id = pr.plan_id left join public.product_family f on f.id = pl.family_id left join public.product p on p.id = pl.product_id
    left join public.product_image i on i.id = pr.product_image_id left join public.product ip on ip.id = i.product_id
   where pr.status = 'dup';

  -- 판정 1195: 사진을 보내는 켜진 listing 마다 — 가져온 뒤 Shopify 로 갈 files(행이 없으면 보냄 · 있으면 상품 칸 → 스토어 칸 · shop_product_payload 와 같은 규칙)
  for v_l in
    select l.store_id, s.code, l.family_id, l.product_id, coalesce(f.sku, p.sku) as sku, coalesce(spf.origin, spp.origin) as origin
      from public.shop_listing l join public.shop_store s on s.id = l.store_id and s.is_active
      left join public.shop_product spf on spf.store_id = l.store_id and spf.family_id = l.family_id
      left join public.shop_product spp on spp.store_id = l.store_id and spp.product_id = l.product_id
      left join public.product_family f on f.id = l.family_id left join public.product p on p.id = l.product_id
     where l.is_on
       and case when spf.id is null and spp.id is null then true else coalesce(spf.send_images, spp.send_images, s.send_images) end
     order by s.code, coalesce(f.sku, p.sku)
  loop
    v_n := v_n + 1;
    select array_agg(pl.id order by pl.id) into v_ids
      from public.shop_photo_plan pl
     where pl.status in ('planned', 'claimed', 'failed')
       and ((v_l.family_id is not null and (pl.family_id = v_l.family_id or pl.product_id in (select m.id from public.product m where m.family_id = v_l.family_id)))
         or (v_l.product_id is not null and pl.product_id = v_l.product_id));
    if v_ids is null then
      if cardinality(v_same) < 300 then v_same := v_same || (v_l.code || ' ' || v_l.sku); end if;
      continue;
    end if;
    v_before := public.shop_product_payload(v_l.store_id, v_l.family_id, v_l.product_id)->'files';
    begin                                                                                           -- 실제 쓰기와 같은 몸을 돌리고 결과만 예외 글로 꺼낸다 — 이 블록의 쓰기(사진 행 · 짝 · 큐)는 전부 되돌아간다
      perform public.shop_photo_apply_(v_ids);
      v_after := public.shop_product_payload(v_l.store_id, v_l.family_id, v_l.product_id)->'files';
      select jsonb_build_object('store', v_l.code, 'sku', v_l.sku, 'origin', v_l.origin, 'photos_to_import', cardinality(v_ids),
               'files_before', jsonb_array_length(v_before), 'files_after', jsonb_array_length(v_after),
               'new_files', count(*) filter (where b.o is null),
               'new_files_uploaded', count(*) filter (where b.o is null and m.id is null),
               'first_photo_changes', (v_before->0->>'product_image_id') is distinct from (v_after->0->>'product_image_id'),
               -- 이미 있던 사진끼리의 순서가 그대로인가(새 사진이 사이에 끼어 자리 번호가 밀리는 것은 was_pos 로 보인다)
               'existing_order_kept', (select array_agg(a2.f->>'product_image_id' order by a2.o) from jsonb_array_elements(v_after) with ordinality as a2(f, o)
                                        where exists (select 1 from jsonb_array_elements(v_before) as b2(f) where b2.f->>'product_image_id' = a2.f->>'product_image_id'))
                                      is not distinct from (select array_agg(b3.f->>'product_image_id' order by b3.o) from jsonb_array_elements(v_before) with ordinality as b3(f, o)),
               'files', jsonb_agg(jsonb_build_object('pos', a.o, 'was_pos', b.o, 'new', b.o is null, 'photo_of', coalesce(a.f->>'sku', pm.sku), 'file', regexp_replace(a.f->>'image_path', '^.*/', ''),
                          'from', pl.src_url,
                          'shopify', case when m.id is not null then 'keeps the Shopify image it is paired with' else 'no pair - matched by file name or uploaded as a new file' end) order by a.o))
        into v_d
        from jsonb_array_elements(v_after) with ordinality as a(f, o)
        left join jsonb_array_elements(v_before) with ordinality as b(f, o) on b.f->>'product_image_id' = a.f->>'product_image_id'
        left join public.product pm on pm.id = (a.f->>'product_id')::uuid
        left join public.shop_photo_plan pl on pl.storage_path = a.f->>'image_path'
        left join public.shop_media m on m.store_id = v_l.store_id and m.product_image_id = (a.f->>'product_image_id')::uuid;
      raise exception using errcode = 'P7777', message = coalesce(v_d, '{}'::jsonb)::text;
    exception when sqlstate 'P7777' then
      v_d := sqlerrm::jsonb;
    end;
    v_changed := v_changed || v_d;
  end loop;

  return jsonb_build_object(
    'plan', v_plan, 'primary_new', v_prim, 'pairs', v_pairs, 'dups', v_dups,
    'listings_sending_images', jsonb_build_object('count', v_n, 'changed', v_changed, 'unchanged', to_jsonb(v_same)));
end;
$function$;
revoke all on function public.shop_photo_dry() from public, anon, authenticated;
grant execute on function public.shop_photo_dry() to service_role;
comment on function public.shop_photo_dry() is
  'shop-photo-imp-2a dry run(판정 1195 · 저장 0) — {plan(갈 곳 · 규칙 · 상태 · 건너뜀 · 확인), primary_new(1197 로 대표가 될 제품), pairs(스토어별 짝 수 · dup · 충돌), dups(심지 않는 Shopify 사진 목록), listings_sending_images{count, changed[가져온 뒤 Shopify 로 갈 files — 새 사진 · 순서 앞뒤], unchanged[]}} · changed 는 실제 쓰기 몸(shop_photo_apply_)을 되돌아가는 블록에서 돌려 shop_product_payload 를 읽은 것 · service_role · postgres';

-- ═══ ① 표(FK 는 맨 끝 ①-b — 그때까지 다른 표를 잠그지 않는다) ═══
create table public.shop_photo_run (
  id          bigint generated always as identity primary key,
  mode        text not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  ok          boolean,
  counts      jsonb not null default '{}'::jsonb,
  error_note  text,
  constraint shop_photo_run_mode_ck check (mode in ('load', 'check', 'pairs', 'move'))
);
comment on table public.shop_photo_run is 'Shopify 전용 사진 가져오기 기록(shop-photo-imp-2a) — 적재(load) 한 줄 + EF 회차(check · pairs · move)마다 한 줄 · 쓰기는 shop_photo_plan_load · shop_photo_run_add';

create table public.shop_photo_plan (
  id               bigint generated always as identity primary key,
  load_n           integer not null,
  pic_kind         text not null,
  rule             text not null,
  owner_sku        text not null,
  family_id        uuid,
  product_id       uuid,
  seq              integer not null default 0,
  gray             boolean not null default false,
  md5_key          text not null,
  file_md5         text not null,
  byte_size        bigint not null,
  content_type     text not null,
  width            integer,
  height           integer,
  file_name        text,
  src_store_id     uuid not null,
  src_product_gid  text not null,
  src_media_gid    text not null,
  src_url          text not null,
  src_pos          integer not null,
  storage_path     text,
  status           text not null default 'planned',
  skip_reason      text,
  attempts         integer not null default 0,
  claimed_at       timestamptz,
  done_at          timestamptz,
  error            text,
  product_image_id uuid,
  verified_at      timestamptz,
  verify_ok        boolean,
  verify_note      text,
  created_at       timestamptz not null default now(),
  constraint shop_photo_plan_owner_ck  check ((family_id is null) <> (product_id is null)),
  constraint shop_photo_plan_pic_ck    check (pic_kind in ('fam_cover', 'fam_unassigned', 'fam_1var_unread', 'variant', 'single')),
  constraint shop_photo_plan_rule_ck   check (rule in ('cover', 'family', '1180', '1181', 'variant', 'single')),
  constraint shop_photo_plan_status_ck check (status in ('planned', 'skipped', 'claimed', 'done', 'failed')),
  constraint shop_photo_plan_skip_ck   check ((status = 'skipped') = (skip_reason is not null)),
  constraint shop_photo_plan_done_ck   check ((status = 'done') = (product_image_id is not null)),
  constraint shop_photo_plan_path_ck   check (skip_reason is not null or (storage_path is not null and left(storage_path, 36) = coalesce(family_id, product_id)::text)),
  constraint shop_photo_plan_fmd5_ck   check (file_md5 ~ '^[0-9a-f]{32}$'),
  constraint shop_photo_plan_size_ck   check (byte_size > 0)
);
create unique index shop_photo_plan_owner_key_uk on public.shop_photo_plan ((coalesce(family_id, product_id)), md5_key);
create unique index shop_photo_plan_path_uk on public.shop_photo_plan (storage_path) where storage_path is not null;
create index shop_photo_plan_status_idx on public.shop_photo_plan (status, id);
create index shop_photo_plan_family_idx on public.shop_photo_plan (family_id) where family_id is not null;
create index shop_photo_plan_product_idx on public.shop_photo_plan (product_id) where product_id is not null;
create index shop_photo_plan_image_idx on public.shop_photo_plan (product_image_id) where product_image_id is not null;
create index shop_photo_plan_store_idx on public.shop_photo_plan (src_store_id);
comment on table public.shop_photo_plan is 'Shopify 전용 사진 가져오기 계획(shop-photo-imp-2a · 판정 1180 ~ 1184 · 1196) — 사진 한 장 = 한 줄(두 스토어에 같은 그림이면 한 줄) · 갈 곳 = family_id XOR product_id · rule = 어느 규칙으로 정했나 · status planned → claimed → done | failed · skipped(1184) · 쓰기는 창구만(shop_photo_plan_load · claim · done · fail · verify_mark)';
comment on column public.shop_photo_plan.md5_key is '같은 그림 열쇠 — 메타 뺀 그림 바이트 md5(조사 shop-photo-dup-1) · 못 센 것은 u:<url>';
comment on column public.shop_photo_plan.file_md5 is 'Shopify CDN 통파일 md5(Accept 헤더 없이 받은 바이트) — EF 가 내려받은 바이트와 대조한다(byte_size 와 함께)';
comment on column public.shop_photo_plan.gray is '판정 1141 — 조사에서 같은지 애매했던 사진(가져오고 디자이너가 보고 지운다) · 표시만';
comment on column public.shop_photo_plan.seq is '그 주인 안의 순서 — 표지 먼저 · 그다음 Shopify 순서(판정 1140) · IMS 사진 뒤에 이 순서로 붙는다';

create table public.shop_photo_pair (
  id               bigint generated always as identity primary key,
  store_id         uuid not null,
  product_gid      text not null,
  media_gid        text not null,
  url              text not null,
  pos              integer not null,
  pair_kind        text not null,
  plan_id          bigint,
  product_image_id uuid,
  how              text,
  status           text not null default 'planned',
  note             text,
  done_at          timestamptz,
  created_at       timestamptz not null default now(),
  constraint shop_photo_pair_store_gid_uk unique (store_id, media_gid),
  constraint shop_photo_pair_gid_ck    check (media_gid ~ '^gid://shopify/MediaImage/[0-9]+$'),
  constraint shop_photo_pair_kind_ck   check (pair_kind in ('import', 'same')),
  constraint shop_photo_pair_target_ck check ((pair_kind = 'import' and plan_id is not null and product_image_id is null) or (pair_kind = 'same' and plan_id is null and product_image_id is not null)),
  constraint shop_photo_pair_status_ck check (status in ('planned', 'done', 'dup', 'gone', 'conflict', 'skipped'))
);
create index shop_photo_pair_plan_idx on public.shop_photo_pair (plan_id) where plan_id is not null;
create index shop_photo_pair_image_idx on public.shop_photo_pair (product_image_id) where product_image_id is not null;
create index shop_photo_pair_status_idx on public.shop_photo_pair (pair_kind, status, id);
comment on table public.shop_photo_pair is 'Shopify media ↔ IMS 사진 짝 계획(shop-photo-imp-2a · 판정 1183) — import = 가져올 사진(계획 줄)의 스토어별 Shopify media · same = IMS 에 이미 있는 사진과 같은 Shopify media · status planned → done(shop_media 에 심음) | gone(Shopify 에서 사라짐) | conflict(shop_media 가 이미 다른 짝) · dup = 같은 스토어의 같은 그림이 여럿이라 안 심는 줄(사진을 보내기 시작하면 Shopify 에서 빠진다 · 1053) · skipped = 가져오지 않는 사진 · 꺼진 IMS 사진';

alter table public.shop_photo_run  enable row level security;
alter table public.shop_photo_plan enable row level security;
alter table public.shop_photo_pair enable row level security;
revoke all on table public.shop_photo_run, public.shop_photo_plan, public.shop_photo_pair from public, anon, authenticated, service_role;
grant select on table public.shop_photo_run, public.shop_photo_plan, public.shop_photo_pair to service_role;
revoke all on sequence public.shop_photo_run_id_seq, public.shop_photo_plan_id_seq, public.shop_photo_pair_id_seq from public, anon, authenticated, service_role;

-- ═══ ①-b FK(마스터 표에 SHARE ROW EXCLUSIVE — 여기서부터 끝까지만 잠근다) ═══
alter table public.shop_photo_plan
  add constraint shop_photo_plan_family_id_fkey        foreign key (family_id)        references public.product_family(id),
  add constraint shop_photo_plan_product_id_fkey       foreign key (product_id)       references public.product(id),
  add constraint shop_photo_plan_src_store_id_fkey     foreign key (src_store_id)     references public.shop_store(id),
  add constraint shop_photo_plan_product_image_id_fkey foreign key (product_image_id) references public.product_image(id);
alter table public.shop_photo_pair
  add constraint shop_photo_pair_store_id_fkey         foreign key (store_id)         references public.shop_store(id),
  add constraint shop_photo_pair_plan_id_fkey          foreign key (plan_id)          references public.shop_photo_plan(id),
  add constraint shop_photo_pair_product_image_id_fkey foreign key (product_image_id) references public.product_image(id);

-- ═══ ⑤ 착지 ═══
do $$
declare v_n int; v_bad text;
begin
  select count(*) into v_n from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('shop_photo_run', 'shop_photo_plan', 'shop_photo_pair') and c.relkind = 'r' and c.relrowsecurity;
  if v_n <> 3 then raise exception 'shop-photo-imp-2a ⑤ tables with RLS: expected 3, found %', v_n; end if;
  select string_agg(t.n || ':' || r.n, ' ') into v_bad
    from (values ('shop_photo_run'), ('shop_photo_plan'), ('shop_photo_pair')) as t(n) cross join (values ('anon'), ('authenticated'), ('service_role')) as r(n)
   where has_table_privilege(r.n, 'public.' || t.n, 'select') is distinct from (r.n = 'service_role')
      or has_table_privilege(r.n, 'public.' || t.n, 'insert') or has_table_privilege(r.n, 'public.' || t.n, 'update') or has_table_privilege(r.n, 'public.' || t.n, 'delete');
  if v_bad is not null then raise exception 'shop-photo-imp-2a ⑤ table privileges are off: %', v_bad; end if;
  select string_agg(p.proname || ':' || r.n, ' ') into v_bad
    from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) as r(n)
   where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'
     and has_function_privilege(r.n, p.oid, 'execute') is distinct from (r.n = 'service_role' and p.proname not in ('shop_photo_plan_load', 'shop_photo_apply_'));
  if v_bad is not null then raise exception 'shop-photo-imp-2a ⑤ function privileges are off: %', v_bad; end if;
  select count(*) into v_n from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.shop_photo_plan'::regclass, 'public.shop_photo_pair'::regclass);
  if v_n <> 7 then raise exception 'shop-photo-imp-2a ⑤ foreign keys: expected 7, found %', v_n; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%' and p.prosecdef;
  if v_n <> 9 then raise exception 'shop-photo-imp-2a ⑤ definer functions: expected 9, found %', v_n; end if;
end $$;
