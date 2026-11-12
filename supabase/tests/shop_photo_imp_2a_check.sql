-- shop-photo-imp-2a 검증 — supabase/migrations/20261112041229_shop_photo_imp_2a_plan.sql (Shopify 전용 사진 가져오기 계획 표 · 적재 · 실행 창구 · dry run · 판정 1180 ~ 1184 · 1195 ~ 1197 · 지시서 ~/asung/prompts/shop-photo-imp-2.md §1 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB · ⚠️ 토론토 17:00 뒤): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261112041229_shop_photo_imp_2a_plan.sql -f supabase/tests/shop_photo_imp_2a_check.sql 2>&1 | tee /tmp/shop_photo_imp_2a.out
--   확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 계획을 싣기 전 · 실은 뒤 둘 다 돈다(기대 수는 파일 끝) · 적용 전에는 못 돈다(표 · 창구가 없다)
--   ⚠️ 실제 행 무변: 재료는 전부 가짜 — 패밀리 둘(ZZIM2AFAM · ZZIM2BFAM) · 제품 여섯(ZZIM2 · ZZIM2-B · ZZIM2-C(꺼짐) · ZZIM3-A · ZZIM3-X(꺼짐) · ZZIM4) · 스토어 둘(zzim21 사진 보냄 · zzim20 안 보냄 · 실제 스토어 한 행의 복사)
--      가짜 계획 줄 · 짝(load_n 900000 대 · gid …/MediaImage/79000000xx) · 저장소 파일 행(product-images 상자 · 가짜 폴더) · 끝은 rollback · 시퀀스를 쓰는 창구는 부르지 않는다
--      shop_photo_claim 은 늘 p_only(가짜 줄 id)로만 부른다 — 실제 계획 줄을 claimed 로 바꾸지 않는다 · 계획이 이미 실려 있으면 가짜 적재(L1 · L3 · L4)는 하지 않고 실물 수를 본다
--      shop_photo_dry 는 창구 자체가 사진을 보내는 실제 listing 의 계획 줄을 되돌아가는 안쪽 블록에서 돌려 본다(저장 0 — D1 이 센다)
--   ⚠️ 잠금: 시험 적용의 끝(①-b FK)이 product · product_family · product_image · shop_store 에 SHARE ROW EXCLUSIVE 를 rollback 까지 잡는다(읽기는 안 막는다 · 그 표들의 쓰기가 기다린다) · lock_timeout 3 s · 검사는 pg_temp.run() 한 문장
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- 머리(begin 앞 · 잠금 없음)
select
  (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname = 'shop_photo_plan')::int as applied_head,
  (select count(*) from public.product_image)::text || '/' || (select count(*) from public.shop_media)::text || '/' || (select count(*) from public.shop_push_queue q where q.done_at is null)::text
    || '/' || (select count(*) from storage.objects o where o.bucket_id = 'product-images')::text as real_head,
  (select f.id::text from public.product_family f where f.is_active order by f.sku limit 1) as fsrc,
  (select p.id::text from public.product p where p.is_active and p.parent_product_id is null and p.family_id is null and p.sellable order by p.sku limit 1) as psrc,
  (select s.id::text from public.shop_store s where s.code = 'asung') as ssrc \gset
select 'head: applied ' || :applied_head || ' · product_image/shop_media/open queue/bucket objects ' || :'real_head';

create temp table t_ids (k text primary key, id uuid not null);
create temp table t_num (k text primary key, n bigint not null);
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.n(p_k text) returns bigint language sql as $$ select t.n from t_num t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 900)) $$;
create function pg_temp.cp(p_tbl regclass, p_row jsonb) returns void language plpgsql as $$
declare v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols from pg_attribute a where a.attrelid = p_tbl and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '';
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_tbl, v_cols, v_cols, p_tbl) using p_row;
end $$;
-- safeupdate 정적 셈(qbo_1c_check.sql · ar_2b_check.sql · shop_photo_imp_1_check.sql 과 같은 스캐너 · 깊이 0 WHERE 없는 update · delete 수)
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 창구를 부르고 예외는 'ERR <sqlstate>: <문장>' 글자로(그 호출의 쓰기는 되돌아간다)
create function pg_temp.call(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return coalesce(v_out, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.gid(p_n int) returns text language sql as $$ select 'gid://shopify/MediaImage/79000000' || lpad(p_n::text, 2, '0') $$;
create function pg_temp.img(p_k text, p_owner_col text, p_owner text, p_file text, p_primary boolean, p_sort int, p_active boolean) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into t_ids values (p_k, v_id);
  execute format('insert into public.product_image (id, %I, storage_path, content_type, is_primary, sort_order, is_active, source) values ($1, $2, $3, ''image/jpeg'', $4, $5, $6, ''manual'')', p_owner_col)
    using v_id, pg_temp.id(p_owner), pg_temp.id(p_owner)::text || '/' || p_file, p_primary, p_sort, p_active;
end $$;
-- 가짜 계획 줄(표에 직접) · 가짜 짝
create function pg_temp.pln(p_k text, p_owner text, p_fam boolean, p_rule text, p_seq int, p_no int) returns void language plpgsql as $$
declare v_n bigint;
begin
  insert into public.shop_photo_plan (load_n, pic_kind, rule, owner_sku, family_id, product_id, seq, md5_key, file_md5, byte_size, content_type, file_name, src_store_id, src_product_gid, src_media_gid, src_url, src_pos, storage_path)
  values (900000 + p_no, case p_rule when 'cover' then 'fam_cover' when 'variant' then 'variant' when 'single' then 'single' else 'fam_unassigned' end, p_rule, 'ZZIM2-' || p_k,
          case when p_fam then pg_temp.id(p_owner) end, case when not p_fam then pg_temp.id(p_owner) end, p_seq, md5(p_k), md5('f' || p_k), 1000 + p_no, 'image/jpeg', p_k || '.jpg',
          pg_temp.id('s1'), 'gid://shopify/Product/7900000001', 'gid://shopify/MediaImage/7900009' || lpad(p_no::text, 3, '0'), 'https://cdn.test.invalid/' || p_k || '.jpg?v=1', p_seq,
          pg_temp.id(p_owner)::text || '/shopify-' || md5(p_k) || '.jpg')
  returning id into v_n;
  insert into t_num values (p_k, v_n);
end $$;
create function pg_temp.pr(p_k text, p_store text, p_gid int, p_kind text, p_plan text, p_img text, p_status text) returns void language plpgsql as $$
declare v_n bigint;
begin
  insert into public.shop_photo_pair (store_id, product_gid, media_gid, url, pos, pair_kind, plan_id, product_image_id, how, status)
  values (pg_temp.id(p_store), 'gid://shopify/Product/7900000001', pg_temp.gid(p_gid), 'https://cdn.test.invalid/' || p_k || '.jpg', p_gid, p_kind, pg_temp.n(p_plan), pg_temp.id(p_img), case when p_kind = 'same' then 'same_md5' end, p_status)
  returning id into v_n;
  insert into t_num values (p_k, v_n);
end $$;
create function pg_temp.obj(p_plan text) returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name) select 'product-images', pl.storage_path from public.shop_photo_plan pl where pl.id = pg_temp.n(p_plan);
end $$;
create function pg_temp.fake_real() returns text language sql as $$                                 -- 가짜 폴더 · 가짜 스토어 밖의 실제 행 수(머리와 같은 꼴)
  select (select count(*) from public.product_image i where left(i.storage_path, 36) not in (select t.id::text from t_ids t))::text || '/'
      || (select count(*) from public.shop_media m where m.store_id not in (pg_temp.id('s1'), pg_temp.id('s0')))::text || '/'
      || (select count(*) from public.shop_push_queue q where q.done_at is null and q.store_id not in (pg_temp.id('s1'), pg_temp.id('s0')))::text || '/'
      || (select count(*) from storage.objects o where o.bucket_id = 'product-images' and left(o.name, 36) not in (select t.id::text from t_ids t))::text $$;
-- 저장 0 을 재는 지문(가짜 포함 전부) — plpgsql: 만들 때 표를 안 본다(시험 적용 앞에 정의)
create function pg_temp.state() returns text language plpgsql as $$
begin
  return (select count(*) from public.product_image)::text || '/' || (select count(*) from public.shop_media)::text || '/' || (select count(*) from public.shop_push_queue)::text
      || '/' || (select count(*) from storage.objects)::text || '/' || (select count(*) from public.shop_photo_run)::text
      || '/' || (select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.product_image_id::text, '') || coalesce(pl.verify_ok::text, ''), ',' order by pl.id), '')) from public.shop_photo_plan pl)
      || '/' || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr);
end $$;

begin;
set local lock_timeout = '3s';
select set_config('d.real_head', :'real_head', true), set_config('d.fsrc', :'fsrc', true), set_config('d.psrc', :'psrc', true), set_config('d.ssrc', :'ssrc', true), clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create function pg_temp.run() returns void language plpgsql as $$
declare
  c_mark constant timestamptz := '2001-01-01 00:00:00+00';
  v_fj jsonb; v_pj jsonb; v_sj jsonb; v_id uuid; k text; r text; r2 text; r3 text; r4 text; v_j jsonb; v_j2 jsonb; v_n int; v_n2 int; v_n3 int;
  v_fa uuid; v_fb uuid; v_real0 text; v_loaded boolean; v_plan jsonb; v_bad jsonb; v_fake bigint[]; v_st text; v_st2 text;
begin
  -- 실제 계획 줄의 지문(끝의 Z 와 견준다) · 이미 실려 있나
  select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.verify_ok::text, '') || pl.attempts::text, ',' order by pl.id), '')) || '/'
      || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr), count(*) > 0
    into v_real0, v_loaded from public.shop_photo_plan pl;

  -- ── 가짜 재료(문지기 · 큐 트리거를 끄고 넣는다 — 사진 행부터는 켠 채로) ──
  execute 'set local session_replication_role = replica';
  select to_jsonb(f) into v_fj from public.product_family f where f.id = current_setting('d.fsrc')::uuid;
  select to_jsonb(p) into v_pj from public.product p where p.id = current_setting('d.psrc')::uuid;
  select to_jsonb(s) into v_sj from public.shop_store s where s.id = current_setting('d.ssrc')::uuid;
  foreach k in array array['A', 'B'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('f' || k, v_id);
    perform pg_temp.cp('public.product_family', v_fj || jsonb_build_object('id', v_id, 'sku', 'ZZIM2' || k || 'FAM', 'name', 'imp-2a test family ' || k, 'cin7_id', null, 'web_image_id', null, 'is_active', true,
      'option1_name', 'Color', 'option2_name', null, 'option3_name', null, 'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  v_fa := pg_temp.id('fA');  v_fb := pg_temp.id('fB');
  for k, r, r2, r3 in select * from (values ('2', 'ZZIM2', 'A', 'true'), ('2b', 'ZZIM2-B', 'A', 'true'), ('2c', 'ZZIM2-C', 'A', 'false'), ('3', 'ZZIM3-A', 'B', 'true'), ('3x', 'ZZIM3-X', 'B', 'false'), ('4', 'ZZIM4', null, 'true')) as x(a, b, c, d) loop
    v_id := gen_random_uuid();  insert into t_ids values ('p' || k, v_id);
    perform pg_temp.cp('public.product', v_pj || jsonb_build_object('id', v_id, 'sku', r, 'name', 'imp-2a test ' || r, 'cin7_id', null, 'parent_product_id', null, 'family_id', case r2 when 'A' then v_fa when 'B' then v_fb end,
      'option1_value', case when r2 is null then null else k end, 'option2_value', null, 'option3_value', null, 'is_active', r3::boolean, 'sellable', true,
      'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  foreach k in array array['1', '0'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('s' || k, v_id);
    perform pg_temp.cp('public.shop_store', v_sj || jsonb_build_object('id', v_id, 'code', 'zzim2' || k, 'shop_domain', 'zzim2' || k || '-test.myshopify.com', 'label', 'imp-2a test store ' || k, 'secret_prefix', 'ZZIM2' || k,
      'is_active', true, 'send_images', k = '1', 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  insert into public.shop_listing (store_id, family_id, is_on, turned_on_at, turned_off_at) values (pg_temp.id('s1'), v_fa, true, now(), null);   -- shop_product 행 없음 = 사진을 보낸다(판정 1042)
  execute 'set local session_replication_role = origin';
  -- IMS 에 이미 있는 사진: ZZIM2 대표 pa1(순서 1) + 꺼진 pa7(순서 7) · 패밀리 A 의 꺼진 패밀리 사진 pf4(순서 4) · ZZIM3-A 의 pq1(켜짐) · pq2(꺼짐)
  perform pg_temp.img('pa1', 'product_id', 'p2', 'a1.jpg', true, 1, true);
  perform pg_temp.img('pa7', 'product_id', 'p2', 'a7.jpg', false, 7, false);
  perform pg_temp.img('pf4', 'family_id', 'fA', 'f4.jpg', false, 4, false);
  perform pg_temp.img('pq1', 'product_id', 'p3', 'q1.jpg', true, 1, true);
  perform pg_temp.img('pq2', 'product_id', 'p3', 'q2.jpg', false, 2, false);
  update public.shop_push_queue set done_at = now(), result = 'ok' where done_at is null and store_id in (pg_temp.id('s1'), pg_temp.id('s0'));

  -- ── L 적재(계획이 비어 있을 때만 가짜 적재 · 실려 있으면 실물 수) ──
  v_plan := jsonb_build_object('source', jsonb_build_object('test', 'imp-2a'),
    'pics', jsonb_build_array(
      jsonb_build_object('n', 0, 'kind', 'fam_cover', 'owner', 'ZZIM2AFAM', 'tgt', 'ZZIM2AFAM', 'gray', false, 'md5', md5('l0'), 'file_md5', md5('fl0'), 'size', 5000, 'ct', 'image/jpeg', 'w', 800, 'h', 800,
        'st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(20), 'url', 'https://cdn.test.invalid/ZZIM2AFAM.jpg?v=1', 'pos', 2, 'names', jsonb_build_array('ZZIM2AFAM'),
        'gids', jsonb_build_array(jsonb_build_object('st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(21), 'url', 'https://cdn.test.invalid/dupe.jpg?v=1', 'pos', 1),
                                  jsonb_build_object('st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(20), 'url', 'https://cdn.test.invalid/ZZIM2AFAM.jpg?v=1', 'pos', 2),
                                  jsonb_build_object('st', 'zzim20', 'g', 'gid://shopify/Product/7900000003', 'gid', pg_temp.gid(22), 'url', 'https://cdn.test.invalid/ZZIM2AFAM.jpg?v=2', 'pos', 1))))
      || (select jsonb_agg(jsonb_build_object('n', x.n, 'kind', x.kind, 'owner', x.owner, 'tgt', x.tgt, 'gray', x.n = 3, 'md5', case when x.n = 8 then 'u:https://cdn.test.invalid/l8' else md5('l' || x.n) end, 'file_md5', md5('fl' || x.n),
                    'size', x.size, 'ct', x.ct, 'w', 0, 'h', 0, 'st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(22 + x.n), 'url', 'https://cdn.test.invalid/' || x.names[1] || '.jpg?v=1', 'pos', 2 + x.n,
                    'names', to_jsonb(x.names),
                    'gids', jsonb_build_array(jsonb_build_object('st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(22 + x.n), 'url', 'https://cdn.test.invalid/' || x.names[1] || '.jpg?v=1', 'pos', 2 + x.n))) order by x.n)
            from (values (1, 'fam_unassigned', 'ZZIM2AFAM', 'ZZIM2AFAM', array['ZZIM2-B_3'], 5000, 'image/jpeg'),            -- ZZIM2(「-」) 와 ZZIM2-B(「_」) 둘 다 맞는다 → 더 긴 ZZIM2-B
                         (2, 'fam_unassigned', 'ZZIM2AFAM', 'ZZIM2AFAM', array['0aa0-not-a-sku', 'zzim2-c'], 5000, 'image/png'),    -- 꺼진 구성원(1196) · 대소문자 무시
                         (3, 'fam_unassigned', 'ZZIM2AFAM', 'ZZIM2AFAM', array['ZZIM2X_1'], 5000, 'image/jpeg'),             -- 「ZZIM2X」 는 ZZIM2 가 아니다 → 패밀리 자리
                         (4, 'fam_1var_unread', 'ZZIM2BFAM', 'ZZIM2BFAM', array['anything'], 5000, 'image/webp'),            -- 1180: 켜진 구성원 하나(ZZIM3-A · 꺼진 ZZIM3-X 는 안 센다)
                         (5, 'single', 'ZZIM4', 'ZZIM4', array['ZZIM4'], 5000, 'image/jpeg'),
                         (6, 'variant', 'ZZIM2AFAM', 'ZZIM2', array['ZZIM2'], 22819, 'image/gif'),                             -- 1184 type
                         (7, 'single', 'ZZIM4', 'ZZIM4', array['ZZIM4_2'], 5242881, 'image/png'),                              -- 1184 too_large(한 바이트 넘음)
                         (8, 'fam_unassigned', 'ZZIM2AFAM', 'ZZIM2AFAM', array['ZZIM2_2'], 5242880, 'image/jpeg')              -- 정확히 5 MB 는 받는다 · md5 를 못 센 줄(u:…)의 경로 열쇠 = file_md5
                 ) as x(n, kind, owner, tgt, names, size, ct)),
    'same', jsonb_build_array(
      jsonb_build_object('st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(40), 'url', 'https://cdn.test.invalid/s40.jpg', 'pos', 5, 'img', pg_temp.id('pa1'), 'how', 'same'),
      jsonb_build_object('st', 'zzim21', 'g', 'gid://shopify/Product/7900000002', 'gid', pg_temp.gid(41), 'url', 'https://cdn.test.invalid/s41.jpg', 'pos', 6, 'img', pg_temp.id('pa1'), 'how', 'same_md5'),
      jsonb_build_object('st', 'zzim20', 'g', 'gid://shopify/Product/7900000003', 'gid', pg_temp.gid(42), 'url', 'https://cdn.test.invalid/s42.jpg', 'pos', 2, 'img', pg_temp.id('pa1'), 'how', 'same_md5')),
    'expect', jsonb_build_object('total', 9, 'cover', 1, 'family', 1, 'r1180', 1, 'r1181', 3, 'variant', 1, 'single', 2, 'to_family', 2, 'to_product', 7, 'skipped', 2, 'gray', 1,
                                 'pair_same', 3, 'pair_same_planned', 2, 'pair_same_dup', 1, 'pair_import', 11, 'pair_import_planned', 8, 'pair_import_dup', 1, 'pair_import_skipped', 2));
  begin
    if v_loaded then
      select (select count(*) || '/' || count(*) filter (where pl.rule = 'cover') || '/' || count(*) filter (where pl.rule = 'family') || '/' || count(*) filter (where pl.rule = '1180') || '/' || count(*) filter (where pl.rule = 'variant')
                  || '/' || count(*) filter (where pl.rule = 'single') || '/' || count(*) filter (where pl.rule = '1181') || '/' || count(*) filter (where pl.skip_reason is not null) || '/' || count(*) filter (where pl.gray)
                from public.shop_photo_plan pl)
          || ' · ' || (select count(*) filter (where pr.pair_kind = 'same') || '/' || count(*) filter (where pr.pair_kind = 'import') from public.shop_photo_pair pr) into r;
      perform pg_temp.res('L1 적재(실물 · 판정 1196): 사진 822 = 패밀리 445 + 109 · 제품 65 + 61 + 36 + 106 · 건너뜀 4 · gray 84 · 짝 same 1,578 · 가져오기 1,764', r = '822/445/109/65/61/36/106/4/84 · 1578/1764', r);
    else
      r := pg_temp.call(format('select public.shop_photo_plan_load(%L::jsonb)::text', (jsonb_set(v_plan, '{expect,r1181}', '2'))::text));
      select count(*) into v_n from public.shop_photo_plan;
      r2 := pg_temp.call(format('select public.shop_photo_plan_load(%L::jsonb)::text', v_plan::text));
      select string_agg(pl.load_n || ':' || pl.rule || ':' || coalesce(f.sku, p.sku) || ':' || pl.status || coalesce('(' || pl.skip_reason || ')', '') || ':' || pl.seq, ' ' order by pl.load_n) into r3
        from public.shop_photo_plan pl left join public.product_family f on f.id = pl.family_id left join public.product p on p.id = pl.product_id;
      select string_agg(right(pr.media_gid, 2) || pr.status, ' ' order by pr.media_gid) into r4 from public.shop_photo_pair pr;
      perform pg_temp.res('L1 적재(가짜 계획): 수가 expect 와 같다 · 1180 켜진 구성원 하나 · 1181 더 긴 SKU · 꺼진 구성원(1196) · 맞는 SKU 없으면 패밀리 · 1184 gif · 5 MB 넘음 건너뜀 · 순서 표지 먼저 · dup 은 고른 것 · same_md5 를 남긴다',
        pg_temp.j(r2) @> (v_plan->'expect')
        and r3 = '0:cover:ZZIM2AFAM:planned:1 1:1181:ZZIM2-B:planned:1 2:1181:ZZIM2-C:planned:1 3:family:ZZIM2AFAM:planned:2 4:1180:ZZIM3-A:planned:1 5:single:ZZIM4:planned:1 6:variant:ZZIM2:skipped(type):1 7:single:ZZIM4:skipped(too_large):2 8:1181:ZZIM2:planned:2'
        and r4 = '20planned 21dup 22planned 23planned 24planned 25planned 26planned 27planned 28skipped 29skipped 30planned 40dup 41planned 42planned'
        and (select pl.storage_path = pg_temp.id('p2')::text || '/shopify-' || md5('fl8') || '.jpg' from public.shop_photo_plan pl where pl.load_n = 8)
        and (select pl.storage_path = v_fa::text || '/shopify-' || md5('l0') || '.jpg' and pl.file_name = 'ZZIM2AFAM.jpg' from public.shop_photo_plan pl where pl.load_n = 0),
        left(r2, 200) || ' ‖ ' || coalesce(r3, '(null)') || ' ‖ ' || coalesce(r4, '(null)'));
      perform pg_temp.res('L3 적재: 센 수가 expect 와 다르면(1181 을 2 로) 통째로 거부 — 계획 0 줄', r like 'ERR %does not add up%r1181: expected 2, counted 3%' and v_n = 0, 'rows ' || v_n || ' · ' || left(r, 300));
    end if;
  exception when others then perform pg_temp.res('L1 적재', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  if v_loaded then perform pg_temp.res('L3 적재: expect 어긋남 거부 — 계획이 이미 실려 있어 가짜 적재를 하지 않는다(실제 줄 무접촉) · 시험 적용 갈래가 본다', true, 'n/a'); end if;
  begin
    select count(*) into v_n from public.shop_photo_plan;
    r := pg_temp.call(format('select public.shop_photo_plan_load(%L::jsonb)::text', case when v_loaded then '{"pics":[],"same":[],"expect":{}}' else v_plan::text end));
    select count(*) into v_n2 from public.shop_photo_plan;
    if not v_loaded then r2 := pg_temp.call(format('select public.shop_photo_plan_load(%L::jsonb, true)::text', v_plan::text)); end if;
    perform pg_temp.res('L2 적재: 두 번째 적재는 거부(줄 수 그대로) · 아무것도 가져오기 전이면 p_replace 로 바꿔 싣는다(가짜 계획일 때만 시험)',
      r like 'ERR %already loaded%' and v_n = v_n2 and (v_loaded or (pg_temp.j(r2) @> (v_plan->'expect') and (select count(*) = 9 from public.shop_photo_plan) and (select count(*) = 2 from public.shop_photo_run where mode = 'load'))),
      left(r, 160) || ' ‖ replace ' || left(coalesce(r2, 'n/a'), 120));
  exception when others then perform pg_temp.res('L2 적재', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── 가짜 계획 줄 · 짝(표에 직접) ──
  perform pg_temp.pln('wc', 'fA', true, 'cover', 1, 1);     perform pg_temp.pln('wf2', 'fA', true, 'family', 2, 2);   perform pg_temp.pln('wf3', 'fA', true, 'family', 3, 3);
  perform pg_temp.pln('wb1', 'p2b', false, '1181', 1, 4);   perform pg_temp.pln('wb2', 'p2b', false, '1181', 2, 5);   perform pg_temp.pln('wa1', 'p2', false, 'variant', 1, 6);
  perform pg_temp.pln('wx', 'p4', false, 'single', 1, 7);   perform pg_temp.pln('wy', 'p4', false, 'single', 2, 8);   perform pg_temp.pln('wd', 'fA', true, 'family', 9, 9);
  select array_agg(t.n) into v_fake from t_num t;
  perform pg_temp.pr('k1', 's1', 1, 'import', 'wc', null, 'planned');   perform pg_temp.pr('k2', 's1', 2, 'import', 'wc', null, 'dup');   perform pg_temp.pr('k3', 's0', 3, 'import', 'wc', null, 'planned');
  perform pg_temp.pr('k4', 's1', 4, 'import', 'wb1', null, 'planned');  perform pg_temp.pr('k5', 's1', 5, 'import', 'wa1', null, 'planned');   perform pg_temp.pr('k6', 's1', 6, 'import', 'wd', null, 'planned');
  insert into public.shop_media (store_id, product_image_id, shopify_file_gid) values (pg_temp.id('s1'), pg_temp.id('pa1'), pg_temp.gid(5));   -- 이미 다른 짝: (s1 · pa1 · gid 05)
  perform pg_temp.pr('m10', 's1', 10, 'same', null, 'pa1', 'planned');  perform pg_temp.pr('m11', 's0', 11, 'same', null, 'pa1', 'planned');   perform pg_temp.pr('m12', 's0', 12, 'same', null, 'pq1', 'planned');
  perform pg_temp.pr('m13', 's0', 13, 'same', null, 'pq2', 'planned');  perform pg_temp.pr('m14', 's0', 14, 'same', null, 'pa1', 'dup');

  -- ── C 확인 → claim ──
  begin
    r  := pg_temp.call(format('select public.shop_photo_claim(60, 30, false, %L::bigint[])::text', v_fake));
    r2 := pg_temp.call(format('select public.shop_photo_verify_mark(%L::jsonb)::text',
            (select jsonb_agg(jsonb_build_object('id', t.n, 'ok', t.k <> 'wy', 'note', case when t.k = 'wy' then 'url changed' end)) from t_num t where t.k like 'w%' and t.k <> 'wd')::text));
    v_j := pg_temp.j(pg_temp.call(format('select public.shop_photo_claim(60, 30, false, %L::bigint[])::text', v_fake)));
    select string_agg(tn.k, ' ' order by x.o) into r3 from jsonb_array_elements(v_j) with ordinality as x(e, o) join t_num tn on tn.n = (x.e->>'id')::bigint;
    r4 := pg_temp.call(format('select public.shop_photo_claim(60, 30, false, %L::bigint[])::text', v_fake));
    perform pg_temp.res('C 확인 → claim: 확인 전에는 아무것도 안 내준다 · 확인 실패(wy) · 확인 안 한 줄(wd)은 빼고 내준다 · 주인별 계획 순서 · planned → claimed · 시도 1 · 다시 부르면 빈 배열 · 경로 · 크기 · md5 를 싣는다',
      r = '[]' and r2 = '8' and r4 = '[]' and jsonb_array_length(v_j) = 7
      and (select count(*) = 7 and bool_and(pl.attempts = 1 and pl.claimed_at is not null) from public.shop_photo_plan pl where pl.id = any(v_fake) and pl.status = 'claimed')
      and (select pl.status = 'planned' and pl.verify_ok is false and pl.verify_note = 'url changed' from public.shop_photo_plan pl where pl.id = pg_temp.n('wy'))
      and (select x.e->>'storage_path' = v_fa::text || '/shopify-' || md5('wc') || '.jpg' and x.e->>'file_md5' = md5('fwc') and x.e->>'byte_size' = '1001' and x.e->>'store' = 'zzim21' from jsonb_array_elements(v_j) x(e) where (x.e->>'id')::bigint = pg_temp.n('wc'))
      and array_position(string_to_array(r3, ' '), 'wc') < array_position(string_to_array(r3, ' '), 'wf2') and array_position(string_to_array(r3, ' '), 'wf2') < array_position(string_to_array(r3, ' '), 'wf3')
      and array_position(string_to_array(r3, ' '), 'wb1') < array_position(string_to_array(r3, ' '), 'wb2'),
      r || ' · marked ' || r2 || ' · order ' || coalesce(r3, '(null)') || ' · again ' || r4);
  exception when others then perform pg_temp.res('C 확인 → claim', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── Q · W 등록 ──
  begin
    perform pg_temp.obj(t.k) from t_num t where t.k in ('wc', 'wf2', 'wf3', 'wb1', 'wb2', 'wa1', 'wx');
    select count(*) into v_n from public.shop_push_queue q where q.done_at is null and q.store_id = pg_temp.id('s1') and q.family_id = v_fa;
    r := pg_temp.call(format('select public.shop_photo_done(%L::jsonb)::text',
           (select jsonb_agg(jsonb_build_object('id', t.n, 'byte_size', pl.byte_size, 'width', 640, 'height', 480) order by t.k desc) from t_num t join public.shop_photo_plan pl on pl.id = t.n where t.k in ('wc', 'wf2', 'wf3'))::text));
    select count(*) into v_n2 from public.shop_push_queue q where q.done_at is null and q.store_id = pg_temp.id('s1') and q.family_id = v_fa;
    perform pg_temp.res('Q 큐: 한 주인의 사진 세 장을 한 번에 등록 → 그 패밀리의 켜진 listing 에 열린 줄 하나(넣기 전 0)', v_n = 0 and v_n2 = 1 and pg_temp.j(r) @> '{"done":3,"already_done":0,"rejected":[]}', 'before ' || v_n || ' · after ' || v_n2 || ' · ' || left(r, 200));
    r2 := pg_temp.call(format('select public.shop_photo_done(%L::jsonb)::text', jsonb_build_array(
            jsonb_build_object('id', pg_temp.n('wb2'), 'byte_size', 1005), jsonb_build_object('id', pg_temp.n('wb1'), 'byte_size', 1004), jsonb_build_object('id', pg_temp.n('wa1'), 'byte_size', 1006),
            jsonb_build_object('id', pg_temp.n('wx'), 'byte_size', 999), jsonb_build_object('id', pg_temp.n('wy'), 'byte_size', 1008), jsonb_build_object('id', pg_temp.n('wd'), 'byte_size', 1009),
            jsonb_build_object('id', 0, 'byte_size', 1))::text));
    select string_agg(tn.k || ':' || i.source || ':' || i.is_primary || ':' || i.sort_order || ':' || (left(i.storage_path, 36) = coalesce(i.product_id, i.family_id)::text and i.storage_path = pl.storage_path) || ':' || (i.family_id is not null)
                      || ':' || coalesce(i.width::text, '-') || ':' || i.is_active, ' ' order by tn.k) into r3
      from t_num tn join public.shop_photo_plan pl on pl.id = tn.n join public.product_image i on i.id = pl.product_image_id where pl.status = 'done';
    perform pg_temp.res('W2 등록: 출처 shopify · 순서 = IMS 사진 뒤(꺼진 줄 포함 max — 패밀리 4 뒤 5 · 6 · 7 표지 먼저 · ZZIM2 는 7 뒤 8) · 패밀리 사진은 대표 아님 · 대표 없는 제품은 첫 장이 대표(1197) · 대표 있는 제품은 아님 · 폴더 = 주인 id',
      r3 = 'wa1:shopify:false:8:true:false:-:true wb1:shopify:true:1:true:false:-:true wb2:shopify:false:2:true:false:-:true wc:shopify:false:5:true:true:640:true wf2:shopify:false:6:true:true:640:true wf3:shopify:false:7:true:true:640:true'
      and (select count(*) = 1 from public.product_image i where i.product_id = pg_temp.id('p2') and i.is_active and i.is_primary)
      and pg_temp.j(r2)->>'done' = '3',
      coalesce(r3, '(null)') || ' ‖ ' || left(r2, 300));
    select string_agg(tn.k || ':' || pr.status, ' ' order by tn.k) into r4 from t_num tn join public.shop_photo_pair pr on pr.id = tn.n where tn.k like 'k%';
    perform pg_temp.res('W5 짝(1183): 사진 행과 같은 호출에서 스토어마다 shop_media 한 줄(두 스토어 = 두 줄) · dup 은 안 심는다 · 그 gid 가 이미 다른 사진의 짝이면 두고 conflict · 등록 안 한 줄의 짝은 planned 그대로',
      r4 = 'k1:done k2:dup k3:done k4:done k5:conflict k6:planned'
      and (select count(*) = 2 from public.shop_media m join public.shop_photo_plan pl on pl.product_image_id = m.product_image_id where pl.id = pg_temp.n('wc')
             and (m.store_id, m.shopify_file_gid) in ((pg_temp.id('s1'), pg_temp.gid(1)), (pg_temp.id('s0'), pg_temp.gid(3))))
      and (select m.product_image_id = pg_temp.id('pa1') from public.shop_media m where m.store_id = pg_temp.id('s1') and m.shopify_file_gid = pg_temp.gid(5))
      and (select count(*) = 4 from public.shop_media m where m.store_id in (pg_temp.id('s1'), pg_temp.id('s0'))),
      coalesce(r4, '(null)') || ' · shop_media(fake stores) ' || (select count(*) from public.shop_media m where m.store_id in (pg_temp.id('s1'), pg_temp.id('s0'))));
    perform pg_temp.res('W1 등록 거부: 크기가 계획과 다르면 · 저장소에 파일이 없으면 · claimed 가 아니면 · 모르는 id 면 그 줄만 거부하고 까닭을 돌려준다(나머지는 등록)',
      (select count(*) = 4 from jsonb_array_elements(pg_temp.j(r2)->'rejected'))
      and (select string_agg(tn.k || '=' || split_part(x.e->>'reason', ' ', 1), ' ' order by tn.k) from jsonb_array_elements(pg_temp.j(r2)->'rejected') x(e) join t_num tn on tn.n = (x.e->>'id')::bigint) = 'wd=not_claimed wx=byte_size wy=not_claimed'
      and pg_temp.j(r2)->'rejected' @> '[{"id":0,"reason":"unknown_id"}]'
      and (select pl.status = 'claimed' from public.shop_photo_plan pl where pl.id = pg_temp.n('wx')),
      left(r2, 500));
  exception when others then perform pg_temp.res('Q · W 등록', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── W3 멱등 ──
  begin
    v_st := pg_temp.state();
    r := pg_temp.call(format('select public.shop_photo_done(%L::jsonb)::text', (select jsonb_agg(jsonb_build_object('id', t.n, 'byte_size', pl.byte_size)) from t_num t join public.shop_photo_plan pl on pl.id = t.n where pl.status = 'done')::text));
    perform pg_temp.res('W3 멱등: 등록한 줄을 다시 부르면 already_done 6 · 사진 행 · 짝 · 큐 · 계획 줄 무변', pg_temp.j(r) @> '{"done":0,"already_done":6,"rejected":[]}' and pg_temp.state() = v_st, left(r, 200) || ' · state same ' || (pg_temp.state() = v_st));
  exception when others then perform pg_temp.res('W3 멱등', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── W4 실패 · 다시 ──
  begin
    r  := pg_temp.call(format('select public.shop_photo_fail(%s, %L)', pg_temp.n('wx'), 'download 503'));
    v_j := pg_temp.j(pg_temp.call(format('select public.shop_photo_claim(60, 30, false, %L::bigint[])::text', v_fake)));
    r2 := pg_temp.call(format('select public.shop_photo_fail(%s, %L, true)', pg_temp.n('wx'), 'md5 differs'));
    r3 := pg_temp.call(format('select public.shop_photo_claim(60, 30, false, %L::bigint[])::text', v_fake));
    v_j2 := pg_temp.j(pg_temp.call(format('select public.shop_photo_claim(60, 30, true, %L::bigint[])::text', v_fake)));
    update public.shop_photo_plan set claimed_at = now() - interval '2 hours' where id = pg_temp.n('wx');
    r4 := pg_temp.call(format('select jsonb_array_length(public.shop_photo_claim(60, 30, false, %L::bigint[]))::text', v_fake));
    perform pg_temp.res('W4 실패: fail → planned(다시 내준다 · 시도 2) · p_final → failed(안 내준다) · p_retry_failed 로 다시 내준다(나갈 길) · 30 분 넘게 claimed 로 멈춘 줄도 다시 · done 줄에는 not_claimed',
      r = 'planned' and jsonb_array_length(v_j) = 1 and v_j->0->>'attempts' = '2' and r2 = 'failed' and r3 = '[]' and jsonb_array_length(v_j2) = 1 and v_j2->0->>'attempts' = '3' and r4 = '1'
      and (select pl.attempts = 4 and pl.error is null from public.shop_photo_plan pl where pl.id = pg_temp.n('wx'))
      and pg_temp.call(format('select public.shop_photo_fail(%s, %L)', pg_temp.n('wc'), 'x')) = 'not_claimed',
      r || ' · ' || coalesce(v_j->0->>'attempts', '-') || ' · ' || r2 || ' · ' || r3 || ' · retry ' || coalesce(jsonb_array_length(v_j2)::text, '-') || ' · stale ' || r4);
  exception when others then perform pg_temp.res('W4 실패 · 다시', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── P same 짝 심기 ──
  begin
    v_plan := (select jsonb_agg(jsonb_build_object('id', t.n, 'present', t.k <> 'm12')) from t_num t where t.k like 'm%' or t.k = 'k6');
    r := pg_temp.call(format('select public.shop_photo_pair_mark(%L::jsonb)::text', v_plan::text));
    select string_agg(tn.k || ':' || pr.status, ' ' order by tn.k) into r2 from t_num tn join public.shop_photo_pair pr on pr.id = tn.n where tn.k like 'm%' or tn.k = 'k6';
    v_st := pg_temp.state();
    r3 := pg_temp.call(format('select public.shop_photo_pair_mark(%L::jsonb)::text', v_plan::text));
    perform pg_temp.res('P same 짝(1183): 있으면 shop_media 에 심는다(m11) · 그 사진이 이미 다른 gid 와 짝이면 두고 conflict(m10) · Shopify 에 없으면 gone(m12) · 꺼진 IMS 사진은 skipped(m13) · dup(m14) · import 짝(k6)은 그대로 · 다시 불러도 무변',
      pg_temp.j(r) = '{"gone":1,"image_off":1,"seeded":1,"conflict":1}' and r2 = 'k6:planned m10:conflict m11:done m12:gone m13:skipped m14:dup'
      and (select m.product_image_id = pg_temp.id('pa1') from public.shop_media m where m.store_id = pg_temp.id('s0') and m.shopify_file_gid = pg_temp.gid(11))
      and pg_temp.j(r3) @> '{"gone":0,"image_off":0,"seeded":0}' and pg_temp.state() = v_st,
      r || ' ‖ ' || coalesce(r2, '(null)') || ' ‖ again ' || r3);
  exception when others then perform pg_temp.res('P same 짝', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── D dry run ──
  begin
    v_st := pg_temp.state();
    v_j := public.shop_photo_dry();
    v_st2 := pg_temp.state();
    perform pg_temp.res('D1 dry run 저장 0: 사진 행 · shop_media · 큐 · 저장소 · run · 계획 줄 · 짝 지문이 부르기 앞뒤 같다 · 꼴 = plan · primary_new · pairs · dups · listings_sending_images{count, changed, unchanged}',
      v_st = v_st2 and v_j ?& array['plan', 'primary_new', 'pairs', 'dups', 'listings_sending_images'] and v_j->'plan' ?& array['total', 'to_family', 'to_product', 'by_rule', 'by_status', 'to_import', 'owners', 'gray', 'skipped', 'verify', 'failed']
      and v_j->'listings_sending_images' ?& array['count', 'changed', 'unchanged'] and v_j->'pairs' ?& array['zzim21', 'zzim20']
      and v_j->'pairs'->'zzim21'->'import'->>'conflict' = '1' and v_j->'pairs'->'zzim20'->'same'->>'gone' = '1'
      and v_j->'dups' @> '[{"store":"zzim21","kind":"import","sku":"ZZIM2AFAM"},{"store":"zzim20","kind":"same","sku":"ZZIM2"}]'
      and v_j->'plan'->'failed' @> jsonb_build_array(jsonb_build_object('id', pg_temp.n('wy'))) is not true
      and v_j->'plan'->'verify'->'failed' @> jsonb_build_array(jsonb_build_object('id', pg_temp.n('wy'), 'note', 'url changed')),
      'state same ' || (v_st = v_st2) || ' · keys ' || (select string_agg(x, ',') from jsonb_object_keys(v_j) x) || ' · pairs zzim21 ' || coalesce((v_j->'pairs'->'zzim21')::text, '(none)'));
    select x.e into v_j2 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) where x.e->>'store' = 'zzim21' and x.e->>'sku' = 'ZZIM2AFAM';
    select count(*) into v_n from public.shop_photo_plan pl where pl.status in ('planned', 'claimed', 'failed') and (pl.family_id = v_fa or pl.product_id in (pg_temp.id('p2'), pg_temp.id('p2b'), pg_temp.id('p2c')));
    perform pg_temp.res('D2 dry run(1195): 사진을 보내는 가짜 listing 이 changed 에 — 가져올 수 = 그 패밀리 · 구성원의 남은 계획 줄 · files 뒤 = 앞 + 새 사진 · 짝 있는 새 사진(wd)은 「keeps」 · 이미 있던 사진끼리의 순서 그대로 · 사진을 안 보내는 스토어는 목록에 없다',
      v_j2 is not null and (v_j2->>'photos_to_import')::int = v_n and v_n >= 1 and (v_j2->>'files_after')::int = (v_j2->>'files_before')::int + (v_j2->>'new_files')::int and (v_j2->>'new_files')::int = v_n
      and (v_j2->>'existing_order_kept')::boolean and (v_j2->>'first_photo_changes')::boolean is false
      and (select count(*) = 1 from jsonb_array_elements(v_j2->'files') x(e) where x.e->>'file' = 'shopify-' || md5('wd') || '.jpg' and (x.e->>'new')::boolean and x.e->>'shopify' like 'keeps%' and x.e->>'from' = 'https://cdn.test.invalid/wd.jpg?v=1' and x.e->>'photo_of' = 'ZZIM2AFAM')
      and (select count(*) = 3 from jsonb_array_elements(v_j2->'files') x(e) where not (x.e->>'new')::boolean and x.e->>'photo_of' = 'ZZIM2AFAM')
      and not exists (select 1 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) where x.e->>'store' = 'zzim20')
      and (select pl.status = 'planned' and pl.product_image_id is null from public.shop_photo_plan pl where pl.id = pg_temp.n('wd')),
      coalesce(left((v_j2 - 'files')::text, 400), '(fake listing not in changed)') || ' · plan rows left ' || v_n);
    select count(*) into v_n2 from public.shop_photo_plan pl join public.product_family f on f.id = pl.family_id where f.sku = 'ONO00140FAM' and pl.status in ('planned', 'claimed', 'failed');
    perform pg_temp.res('D3 dry run(1195 · 실물): 계획에 ONO00140FAM 이 남아 있으면 asung 의 그 listing 이 changed 에 있다(계획이 안 실렸거나 다 가져왔으면 n/a) · 사진을 보내는 실제 listing 수 = count − 가짜 1',
      (v_n2 = 0 or exists (select 1 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) where x.e->>'store' = 'asung' and x.e->>'sku' = 'ONO00140FAM' and (x.e->>'new_files')::int >= 1))
      and (v_j->'listings_sending_images'->>'count')::int - 1 = jsonb_array_length(v_j->'listings_sending_images'->'changed') + jsonb_array_length(v_j->'listings_sending_images'->'unchanged') - 1,
      'ONO plan rows ' || v_n2 || ' · listings ' || (v_j->'listings_sending_images'->>'count') || ' · changed ' || (select coalesce(string_agg((x.e->>'store') || ' ' || (x.e->>'sku') || ' +' || (x.e->>'new_files'), ', '), '(none)') from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e)));
  exception when others then perform pg_temp.res('D dry run', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── L4 · A · N · Z ──
  r := pg_temp.call(format('select public.shop_photo_plan_load(%L::jsonb, true)::text', '{"pics":[],"same":[],"expect":{}}'));
  perform pg_temp.res('L4 적재: 가져온 사진 · 심은 짝이 생긴 뒤에는 p_replace 로도 못 바꾼다', r like 'ERR %already in use%', left(r, 200));
  perform pg_temp.res('A 권한: 창구 아홉 = definer · anon · authenticated 실행 0 · service_role 은 일곱(plan_load · apply_ 는 아무도) · 표 셋 = RLS 켬 · service_role select 만 · anon · authenticated 0',
    (select count(*) = 9 and bool_and(p.prosecdef and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                                     and has_function_privilege('service_role', p.oid, 'execute') = (p.proname not in ('shop_photo_plan_load', 'shop_photo_apply_')))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%')
    and (select count(*) = 3 and bool_and(c.relrowsecurity and has_table_privilege('service_role', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'insert, update, delete')
                                     and not has_table_privilege('authenticated', c.oid, 'select, insert, update, delete') and not has_table_privilege('anon', c.oid, 'select, insert, update, delete'))
       from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('shop_photo_run', 'shop_photo_plan', 'shop_photo_pair')),
    (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '-'), ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'));
  perform pg_temp.res('N nowhere 정적(REST 두 겹 ①): 창구 아홉에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select count(*) = 9 and sum(pg_temp.nowhere(p.prosrc)) = 0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'),
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'));
  select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.verify_ok::text, '') || pl.attempts::text, ',' order by pl.id), '')) || '/'
      || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr where pr.store_id not in (pg_temp.id('s1'), pg_temp.id('s0')))
    into r from public.shop_photo_plan pl where coalesce(pl.family_id, pl.product_id) not in (select t.id from t_ids t);
  perform pg_temp.res('Z 실물 무접촉: 가짜 폴더 · 가짜 스토어 밖의 사진 행 · shop_media · 열린 큐 · 저장소 파일 수가 머리와 같다 · 실제 계획 줄 · 짝의 지문이 처음과 같다 · postgres',
    pg_temp.fake_real() = current_setting('d.real_head') and (not v_loaded or r = v_real0) and current_user = 'postgres',
    'head ' || current_setting('d.real_head') || ' · now ' || pg_temp.fake_real() || ' · plan loaded ' || v_loaded || ' · real plan same ' || coalesce((r = v_real0)::text, '(null)') || ' · user ' || current_user);
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
rollback;
\pset tuples_only off
\pset format aligned
-- 기대: 시험(-v mig) OK 18 · FAIL 0 · 확인(적용 뒤 · -v mig 없음) OK 18 · FAIL 0 — 계획을 싣기 전(가짜 적재 L1 · L3 · L2 의 p_replace 를 돈다) · 실은 뒤(L1 = 실물 수 822 … · L3 = n/a) 둘 다 18
--       적용 전 마른 실행은 못 돈다(표 · 창구가 없어 pg_temp.run() 이 첫 문장에서 멈춘다 — 새 객체만 만드는 차수라 재현할 옛 결함이 없다) · 첫 확인 통과는 Caleb 의 확인 실행
--       OK 줄 꼴 = 「OK <이름>」 · 끝 줄 「OK 18 · FAIL 0 · begin ~ 끝 …」 · 시험 begin ~ 끝 약 22 초(2026-11-11 23:3x 토론토 실측 22.3 s — 거의 다 마이그레이션 문장 왕복 · 마스터 표 잠금은 끝의 ①-b FK 부터 rollback 까지) · 확인 갈래는 잠금 없음 · 시퀀스 무접촉
--       변이(2026-11-11): 1181 「더 긴 SKU」 를 짧은 것으로 → FAIL 1(L1) · 멱등 가드(done 의 already_done + apply_ 의 상태 조건)를 뺀 판 → FAIL 1(W3) · 순서의 max 를 켜진 줄만으로 → FAIL 1(W2)
--       계획이 실린 상태 갈래(시험 적용 뒤 실제 계획을 같은 트랜잭션에서 싣고 돌림 · rollback): OK 18 · FAIL 0
