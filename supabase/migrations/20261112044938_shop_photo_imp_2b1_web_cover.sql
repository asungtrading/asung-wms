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

-- shop-photo-imp-2b-1 — 가져온 FAM 표지를 웹 대표로(판정 1198) · dry run 요약 한 줄 (Caleb 2026-11-11 · 지시서 ~/asung/prompts/shop-photo-imp-2b.md · 이견 답 2026-11-11 밤 · deferred 387 가져오기 길 ②-b 의 DB 몫)
--   판정 1198  가져오기 때 web_image_id 가 비어 있는 패밀리는 가져온 FAM 표지를 웹 대표로 지정한다(1139 그대로) · 한 패밀리에 표지 두 장이면 계획 순서 앞 하나만(BAB46708FAM = 계획 줄 173)
--              null 일 때만 — 앞 표지가 실패하고 뒤 표지가 먼저 들어오면 뒤 표지가 대표가 되고, 앞 표지가 나중에 와도 바꾸지 않는다 · 이미 사람이 지정한 패밀리는 무접촉
--   무엇:
--     ① shop_photo_apply_ 재발행 — 끝에 한 문장(product_family.web_image_id) · 사진 행 · 짝과 같은 트랜잭션 · shop_photo_done 과 shop_photo_dry 가 같은 몸을 부른다
--     ② shop_photo_dry 재발행 — 흉내를 따로 짓지 않는다(되돌아가는 블록에서 ① 을 그대로 돌리므로 first_photo_changes · 순서가 저절로 1198 뒤의 모습)
--          더한 것: web_cover_new {count, families[]}(웹 대표가 새로 설 패밀리) · changed 줄마다 cover_set(그 listing 의 패밀리 웹 대표가 이 가져오기로 서는가)
--   재발행 원본 = DB prosrc(2a `20261112041229`) — 아래 ⓪ 가 md5 로 지킨다(다르면 아무것도 안 바꾸고 멈춘다) · 원본에서 바뀐 줄은 더한 줄뿐(지운 줄 0 · 바꾼 줄 1 = dry 의 반환 한 줄에 열쇠 하나)
--   create or replace — 시그니처 · 권한(apply_ 실행권 없음 · dry service_role) · definer · search_path 그대로 · 표 · 색인 · 정책 무변 · 잠금 없음(plpgsql 은 만들 때 표를 안 본다)
--   무접촉: shop_photo_done · claim · fail · pair_mark · verify_mark · run_add · plan_load · product_update · family_image_update · shop_product_payload · shop_queue_trigger · shop_queue_add · EF(가드는 같은 차수의 _shared/shopify-product.ts — DB 와 따로 배포)
--   나갈 길: 잘못 선 웹 대표는 기존 창구 shop_listing_set 의 family_web_image_set(다른 사진으로 · 또는 비움)로 고친다 — 비운 뒤에는 다시 서지 않는다(가져온 줄은 done 이라 이 몸이 다시 돌지 않는다)

-- ═══ ⓪ 원본 지문 ═══
do $$
declare v_a text; v_d text;
begin
  select md5(p.prosrc) into v_a from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_apply_';
  select md5(p.prosrc) into v_d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_dry';
  if v_a is distinct from 'ebfe37b1fd2ced21a1a37e44f1053aaf' or v_d is distinct from 'ccecd751f5392979338d0596d8f9ebce' then
    raise exception 'shop-photo-imp-2b-1 ⓪ the functions to re-issue are not the 2a originals (shop_photo_apply_ %, shop_photo_dry %) - nothing was changed', coalesce(v_a, '<missing>'), coalesce(v_d, '<missing>');
  end if;
end $$;

-- ═══ ① shop_photo_apply_ ═══
create or replace function public.shop_photo_apply_(p_ids bigint[])
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
  -- shop-photo-imp-2b-1(판정 1198 · 1139): 웹 대표가 비어 있는 패밀리는 이번에 들어온 FAM 표지를 웹 대표로 — 표지가 둘이면 계획 순서 앞(seq · id) 하나만
  --   이미 지정된 패밀리는 무접촉(null 일 때만) · 켜진 그 패밀리의 패밀리 사진일 때만(family_web_image_set 의 「켜진 후보」 와 같은 조건) · 표지가 아닌 패밀리 사진(rule family)은 대표가 되지 않는다
  --   같은 트랜잭션 — product_family_shop_queue_u 가 큐를 깨우지만 사진 insert 가 이미 넣은 열린 줄이 있어 listing 마다 한 줄 그대로
  update public.product_family f set web_image_id = c.product_image_id
    from (select distinct on (pl.family_id) pl.family_id, pl.product_image_id
            from public.shop_photo_plan pl join public.product_image i on i.id = pl.product_image_id and i.is_active and i.family_id = pl.family_id
           where pl.id = any(p_ids) and pl.rule = 'cover' and pl.status = 'done'
           order by pl.family_id, pl.seq, pl.id) c
   where f.id = c.family_id and f.web_image_id is null;
end;
$function$;
comment on function public.shop_photo_apply_(bigint[]) is 'shop-photo-imp-2a 속 몸 — 계획 줄 → product_image(source shopify · 순서 IMS 뒤 · 대표 규칙 1197) + shop_media 짝(1183) + 웹 대표가 비어 있는 패밀리는 들어온 FAM 표지를 웹 대표로(shop-photo-imp-2b-1 · 판정 1198 · 표지 둘이면 계획 순서 앞 · null 일 때만) · 실행권 없음(shop_photo_done · shop_photo_dry 가 부른다)';

-- ═══ ② shop_photo_dry ═══
create or replace function public.shop_photo_dry()
  returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $function$
declare
  v_plan jsonb; v_pairs jsonb; v_dups jsonb; v_prim jsonb; v_changed jsonb := '[]'::jsonb; v_same text[] := '{}';
  v_l record; v_ids bigint[]; v_before jsonb; v_after jsonb; v_d jsonb; v_n int := 0;
  v_cover jsonb; v_web0 text;
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

  -- shop-photo-imp-2b-1(판정 1198): 가져오면 웹 대표가 새로 서는 패밀리 — 웹 대표가 비어 있고 아직 안 가져온 FAM 표지가 있는 곳(사진을 보내든 안 보내든 · IMS 의 패밀리 대표 사진이 바뀐다)
  select jsonb_build_object('count', count(*), 'families', coalesce(jsonb_agg(x.sku order by x.sku), '[]'::jsonb)) into v_cover
    from (select distinct f.sku from public.shop_photo_plan pl join public.product_family f on f.id = pl.family_id
           where pl.rule = 'cover' and pl.status in ('planned', 'claimed', 'failed') and f.web_image_id is null) x;

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
    select f.web_image_id::text into v_web0 from public.product_family f where f.id = v_l.family_id;   -- shop-photo-imp-2b-1: 가져오기 앞의 웹 대표(낱개 listing 은 null)
    begin                                                                                           -- 실제 쓰기와 같은 몸을 돌리고 결과만 예외 글로 꺼낸다 — 이 블록의 쓰기(사진 행 · 짝 · 큐)는 전부 되돌아간다
      perform public.shop_photo_apply_(v_ids);
      v_after := public.shop_product_payload(v_l.store_id, v_l.family_id, v_l.product_id)->'files';
      select jsonb_build_object('store', v_l.code, 'sku', v_l.sku, 'origin', v_l.origin, 'photos_to_import', cardinality(v_ids),
               'files_before', jsonb_array_length(v_before), 'files_after', jsonb_array_length(v_after),
               'new_files', count(*) filter (where b.o is null),
               'new_files_uploaded', count(*) filter (where b.o is null and m.id is null),
               'first_photo_changes', (v_before->0->>'product_image_id') is distinct from (v_after->0->>'product_image_id'),
               'cover_set', (select f.web_image_id::text from public.product_family f where f.id = v_l.family_id) is distinct from v_web0,
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
    'plan', v_plan, 'primary_new', v_prim, 'web_cover_new', v_cover, 'pairs', v_pairs, 'dups', v_dups,
    'listings_sending_images', jsonb_build_object('count', v_n, 'changed', v_changed, 'unchanged', to_jsonb(v_same)));
end;
$function$;
comment on function public.shop_photo_dry() is
  'shop-photo-imp-2a dry run(판정 1195 · 저장 0) — {plan(갈 곳 · 규칙 · 상태 · 건너뜀 · 확인), primary_new(1197 로 대표가 될 제품), web_cover_new{count, families[]}(shop-photo-imp-2b-1 · 판정 1198 로 웹 대표가 새로 설 패밀리), pairs(스토어별 짝 수 · dup · 충돌), dups(심지 않는 Shopify 사진 목록), listings_sending_images{count, changed[가져온 뒤 Shopify 로 갈 files — 새 사진 · 순서 앞뒤 · cover_set], unchanged[]}} · changed 는 실제 쓰기 몸(shop_photo_apply_)을 되돌아가는 블록에서 돌려 shop_product_payload 를 읽은 것 · service_role · postgres';

-- ═══ ③ 착지 ═══
do $$
declare v_bad text; v_n int;
begin
  select string_agg(p.proname || ' ' || md5(p.prosrc), ' · ') into v_bad
    from pg_proc p join (values ('shop_photo_apply_', 'f0c4cb1b585829d6033e84c9eea009de'), ('shop_photo_dry', '04b9ce79a3d16884ba3b9e834277e7b6'),
                                ('shop_photo_done', '852ab313a8d56ea370871d783621b86f'), ('shop_photo_claim', 'b4a91066ab55760d959361bdc610b21f'),
                                ('shop_product_payload', '72a620cb1da4cca7394332d8008731a3'), ('shop_queue_trigger', 'ff5ccbdd39a3748be1ed4b7f1058c71d'),
                                ('family_image_update', '6417e98d92fe22296daa568f4db272eb')) as w(n, m) on w.n = p.proname
   where p.pronamespace = 'public'::regnamespace and md5(p.prosrc) <> w.m;
  if v_bad is not null then raise exception 'shop-photo-imp-2b-1 ③ function bodies are not what this migration expects: %', v_bad; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_photo_apply_', 'shop_photo_dry');
  if v_n <> 2 then raise exception 'shop-photo-imp-2b-1 ③ expected one shop_photo_apply_ and one shop_photo_dry, found % functions', v_n; end if;
  select string_agg(p.proname || ':' || r.n, ' ') into v_bad
    from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) as r(n)
   where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_photo_apply_', 'shop_photo_dry')
     and (not p.prosecdef or has_function_privilege(r.n, p.oid, 'execute') is distinct from (r.n = 'service_role' and p.proname = 'shop_photo_dry'));
  if v_bad is not null then raise exception 'shop-photo-imp-2b-1 ③ function privileges are off: %', v_bad; end if;
end $$;
