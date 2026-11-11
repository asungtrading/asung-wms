-- shop-photo-imp-1 검증 — supabase/migrations/20261111222252_shop_photo_imp_1_family_image.sql (패밀리 사진 자리 · 판정 1179 · 1186 ~ 1188 · 지시서 ~/asung/prompts/shop-photo-imp-1.md §1 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB · ⚠️ 토론토 18:00 뒤): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111222252_shop_photo_imp_1_family_image.sql -f supabase/tests/shop_photo_imp_1_check.sql
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 기대 수는 파일 끝
--   ⚠️ 실제 행 무변: 재료는 전부 가짜 — 패밀리 둘(ZZIMP1FAM · ZZIMP2FAM · 실제 패밀리 한 행의 복사) · 제품 셋(ZZIMP1-A · B 는 패밀리 1 의 구성원 · ZZIMP1-C 는 패밀리 밖) · 스토어 둘(zzimp1 사진 보냄 · zzimp0 안 보냄)
--      직원 셋(imp1-…@test.invalid · 가짜 auth uid) · 저장소 파일 행(product-images 상자 · 가짜 폴더) · 끝은 rollback · 시퀀스를 쓰는 창구는 부르지 않는다
--   ⚠️ 잠금: 시험 적용이 product_image(alter) · storage.objects(정책)에 ACCESS EXCLUSIVE 를 rollback 까지 잡는다 — 그 동안 사진 썸네일 · 모든 상자의 저장소 읽기 · 쓰기가 기다린다 · lock_timeout 3 s
--      마이그레이션은 함수(잠금 없음)를 먼저 · 표 · 정책을 끝에 두었다 · 검사는 pg_temp.run() 한 문장
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- 머리(begin 앞 · 잠금 없음): 적용 여부 · 실제 행 수 · 실제 대상 25 개쯤의 payload hash(사진을 보내는 덧씌우기 대상 전부 + 켜진 패밀리 listing 12)
select
  (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'product_image' and c.column_name = 'family_id')::int as applied_head,
  (select count(*) from public.product_image)::text || '/' || (select count(*) from public.product_family f where f.web_image_id is not null)::text || '/' || (select count(*) from public.shop_push_queue q where q.done_at is null)::text as real_head,
  (select f.id::text from public.product_family f where f.is_active order by f.sku limit 1) as fsrc,
  (select p.id::text from public.product p where p.is_active and p.parent_product_id is null and p.family_id is null and p.sellable order by p.sku limit 1) as psrc,
  (select s.id::text from public.shop_store s where s.code = 'asung') as ssrc \gset
select count(*)::text as real_hash_n, md5(coalesce(string_agg(x.k || x.h, ',' order by x.k), '')) as real_hash from (
  select l.store_id::text || '|' || coalesce(l.family_id::text, '') || '|' || coalesce(l.product_id::text, '') as k, public.shop_product_payload(l.store_id, l.family_id, l.product_id)->>'hash' as h
    from (select sp.store_id, sp.family_id, sp.product_id from public.shop_product sp where sp.send_images
          union (select l2.store_id, l2.family_id, l2.product_id from public.shop_listing l2 where l2.is_on and l2.family_id is not null order by l2.id limit 12)) l) x \gset
select 'head: applied ' || :applied_head || ' · product_image/web_image families/open queue ' || :'real_head' || ' · real payload hashes ' || :'real_hash_n' || ' md5 ' || :'real_hash';

create temp table t_ids (k text primary key, id uuid not null);
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 900)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 가짜 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_who text, p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', pg_temp.id('u' || p_who)), true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_out, '(null)');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 같은 신원으로 돌려받는 값이 없는 문장(RETURNING 은 SELECT 정책까지 본다 — 저장소 올리기 시험은 값 없이) → 'done' 또는 'ERR …'
create function pg_temp.asx(p_who text, p_sql text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', pg_temp.id('u' || p_who)), true);
  execute 'set local role authenticated';
  execute p_sql;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'done';
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.own(p_sql text) returns text language plpgsql as $$
declare v_n int;
begin
  execute p_sql;  get diagnostics v_n = row_count;
  return 'rows ' || v_n;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.cp(p_tbl regclass, p_row jsonb) returns void language plpgsql as $$
declare v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols from pg_attribute a where a.attrelid = p_tbl and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '';
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_tbl, v_cols, v_cols, p_tbl) using p_row;
end $$;
-- safeupdate 정적 셈(qbo_1c_check.sql · ar_2b_check.sql 과 같은 스캐너 · 깊이 0 WHERE 없는 update · delete 수)
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
-- 도우미: 창구 부르기(직원 신원) · payload 의 사진 id 목록 · 열린 큐 수 · 큐 비우기(가짜 스토어 것만)
create function pg_temp.fiu(p_who text, p_changes jsonb, p_commit boolean, p_ack text[]) returns text language sql as $$
  select pg_temp.asu(p_who, format('select public.family_image_update(%L::jsonb, %L, %L::text[])::text', p_changes::text, p_commit, p_ack)) $$;
create function pg_temp.wis(p_img uuid, p_old uuid, p_commit boolean) returns text language sql as $$
  select pg_temp.asu('S', format('select public.shop_listing_set(%L::jsonb, %L)::text', jsonb_build_array(jsonb_build_object('op', 'family_web_image_set', 'family_sku', 'ZZIMP1FAM', 'product_image_id', p_img, 'old', p_old))::text, p_commit)) $$;
create function pg_temp.fids(p_store text) returns text language sql as $$
  select coalesce(string_agg(kk.k, ' ' order by x.o), '(none)')
    from jsonb_array_elements(public.shop_product_payload(pg_temp.id(p_store), pg_temp.id('f1'), null)->'files') with ordinality as x(f, o)
    left join t_ids kk on kk.id = (x.f->>'product_image_id')::uuid $$;
create function pg_temp.qn(p_fam text) returns int language sql as $$
  select count(*)::int from public.shop_push_queue q where q.done_at is null and q.family_id = pg_temp.id(p_fam) and q.store_id in (pg_temp.id('s1'), pg_temp.id('s0')) $$;
create function pg_temp.qclear() returns void language sql as $$
  update public.shop_push_queue set done_at = now(), result = 'ok' where done_at is null and store_id in (pg_temp.id('s1'), pg_temp.id('s0')) $$;
create function pg_temp.img(p_k text, p_owner_col text, p_owner text, p_file text, p_primary boolean, p_sort int, p_active boolean) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into t_ids values (p_k, v_id);
  execute format('insert into public.product_image (id, %I, storage_path, content_type, is_primary, sort_order, is_active, source) values ($1, $2, $3, ''image/jpeg'', $4, $5, $6, ''manual'')', p_owner_col)
    using v_id, pg_temp.id(p_owner), pg_temp.id(p_owner)::text || '/' || p_file, p_primary, p_sort, p_active;
end $$;

begin;
set local lock_timeout = '3s';
select set_config('d.real_head', :'real_head', true), set_config('d.real_hash', :'real_hash', true), set_config('d.fsrc', :'fsrc', true), set_config('d.psrc', :'psrc', true), set_config('d.ssrc', :'ssrc', true), clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create function pg_temp.run() returns void language plpgsql as $$
declare
  c_mark constant timestamptz := '2001-01-01 00:00:00+00';
  v_fj jsonb; v_pj jsonb; v_sj jsonb; v_id uuid; k text; r text; r2 text; r3 text; r4 text; r5 text; r6 text; r7 text; v_j jsonb; v_j2 jsonb;
  v_f1 uuid; v_f2 uuid; v_prim0 text; v_var0 text; v_h1 text; v_h0 text; v_n int; v_n2 int; v_n3 int; v_n4 int; v_n5 int; v_key text; v_fa uuid; v_fb uuid;
begin
  -- ── 가짜 재료(문지기 · 큐 트리거를 끄고 넣는다 — 사진 행부터는 켠 채로) ──
  execute 'set local session_replication_role = replica';
  select to_jsonb(f) into v_fj from public.product_family f where f.id = current_setting('d.fsrc')::uuid;
  select to_jsonb(p) into v_pj from public.product p where p.id = current_setting('d.psrc')::uuid;
  select to_jsonb(s) into v_sj from public.shop_store s where s.id = current_setting('d.ssrc')::uuid;
  foreach k in array array['1', '2'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('f' || k, v_id);
    perform pg_temp.cp('public.product_family', v_fj || jsonb_build_object('id', v_id, 'sku', 'ZZIMP' || k || 'FAM', 'name', 'imp-1 test family ' || k, 'cin7_id', null, 'web_image_id', null, 'is_active', true,
      'option1_name', 'Color', 'option2_name', null, 'option3_name', null, 'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  v_f1 := pg_temp.id('f1');  v_f2 := pg_temp.id('f2');
  foreach k in array array['A', 'B', 'C'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('p' || k, v_id);
    perform pg_temp.cp('public.product', v_pj || jsonb_build_object('id', v_id, 'sku', 'ZZIMP1-' || k, 'name', 'imp-1 test ' || k, 'cin7_id', null, 'parent_product_id', null, 'family_id', case when k = 'C' then null else v_f1 end,
      'option1_value', case when k = 'C' then null else k end, 'option2_value', null, 'option3_value', null, 'is_active', true, 'sellable', true,
      'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  foreach k in array array['1', '0'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('s' || k, v_id);
    perform pg_temp.cp('public.shop_store', v_sj || jsonb_build_object('id', v_id, 'code', 'zzimp' || k, 'shop_domain', 'zzimp' || k || '-test.myshopify.com', 'label', 'imp-1 test store ' || k, 'secret_prefix', 'ZZIMP' || k,
      'is_active', true, 'send_images', k = '1', 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  insert into public.shop_listing (store_id, family_id, is_on, turned_on_at, turned_off_at) values
    (pg_temp.id('s1'), v_f1, true, now(), null), (pg_temp.id('s0'), v_f1, true, now(), null), (pg_temp.id('s1'), v_f2, false, now(), now());
  insert into public.shop_product (store_id, family_id, shopify_product_gid, origin) values (pg_temp.id('s0'), v_f1, 'gid://shopify/Product/990000000001', 'link');   -- 행이 있어야 스토어 값(send_images false)을 따른다(행 없음 = true · 판정 1042)
  execute 'set local session_replication_role = origin';
  for k, r in select * from (values ('M', '["ims","master"]'), ('S', '["ims","master","shopify"]'), ('N', '["ims","sales","shopify"]')) as x(a, b) loop
    v_id := gen_random_uuid();  insert into t_ids values ('u' || k, v_id);
    insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_id, 'imp1-' || lower(k) || '@test.invalid', 'imp-1 ' || k, 'worker', r::jsonb, '{}');
  end loop;
  -- 구성원 사진(제품 사진 · 예전 꼴): A 대표 pa1 · A 둘째 pa2 · B 대표 pb1 · 패밀리 밖 C 대표 pc1
  perform pg_temp.img('pa1', 'product_id', 'pA', 'a1.jpg', true, 1, true);
  perform pg_temp.img('pa2', 'product_id', 'pA', 'a2.jpg', false, 2, true);
  perform pg_temp.img('pb1', 'product_id', 'pB', 'b1.jpg', true, 1, true);
  perform pg_temp.img('pc1', 'product_id', 'pC', 'c1.jpg', true, 1, true);
  select string_agg(x::text, ' ' order by x.sku) into v_prim0 from public.product_image_primary(array['ZZIMP1-A', 'ZZIMP1-B', 'ZZIMP1-C']) x;
  v_j := public.shop_product_payload(pg_temp.id('s1'), v_f1, null);  v_var0 := (v_j->'variants')::text;  v_h1 := v_j->>'hash';
  v_h0 := public.shop_product_payload(pg_temp.id('s0'), v_f1, null)->>'hash';
  perform pg_temp.res('P0 패밀리 사진이 없을 때 payload: 사진 보내는 스토어 = 표지(기본 = SKU 순 첫 대표) → 변형 대표 → 나머지 · file 열쇠 다섯 · 안 보내는 스토어 = files []',
    pg_temp.fids('s1') = 'pa1 pb1 pa2' and (select bool_and((select count(*) from jsonb_object_keys(f)) = 5 and f ? 'product_id' and not f ? 'family_id' and not f ? 'sku') from jsonb_array_elements(v_j->'files') f)
    and pg_temp.fids('s0') = '(none)', pg_temp.fids('s1') || ' ‖ s0 ' || pg_temp.fids('s0') || ' ‖ ' || left((v_j->'files'->0)::text, 300));

  -- ── X 제약(한 번에 하나만 어긴다 · 넣는 행은 꺼진 채) ──
  begin
    r  := pg_temp.own(format('insert into public.product_image (storage_path, content_type, is_active) values (%L, %L, false)', gen_random_uuid()::text || '/x1.jpg', 'image/jpeg'));
    r2 := pg_temp.own(format('insert into public.product_image (product_id, family_id, storage_path, content_type, is_active) values (%L, %L, %L, %L, false)', pg_temp.id('pA'), v_f1, pg_temp.id('pA')::text || '/x2.jpg', 'image/jpeg'));
    r3 := pg_temp.own(format('insert into public.product_image (family_id, storage_path, content_type, is_active) values (%L, %L, %L, false)', v_f1, v_f1::text || '/x3.jpg', 'image/jpeg'));
    r4 := pg_temp.own(format('insert into public.product_image (product_id, storage_path, content_type, is_active) values (%L, %L, %L, false)', pg_temp.id('pB'), pg_temp.id('pB')::text || '/x4.jpg', 'image/jpeg'));
    r5 := pg_temp.own(format('insert into public.product_image (family_id, storage_path, content_type, is_active, is_primary) values (%L, %L, %L, false, true)', v_f1, v_f1::text || '/x5.jpg', 'image/jpeg'));
    r6 := pg_temp.own(format('insert into public.product_image (family_id, storage_path, content_type, is_active) values (%L, %L, %L, false)', v_f1, v_f2::text || '/x6.jpg', 'image/jpeg'));
    r7 := pg_temp.own(format('insert into public.product_image (product_id, storage_path, content_type, is_active) values (%L, %L, %L, false)', pg_temp.id('pB'), pg_temp.id('pA')::text || '/x7.jpg', 'image/jpeg'));
    perform pg_temp.res('X1 주인 하나(XOR): 둘 다 비움 · 둘 다 채움 → product_image_owner_ck 거부 · 패밀리만 · 제품만 → 받음',
      r like 'ERR 23514%product_image_owner_ck%' and r2 like 'ERR 23514%product_image_owner_ck%' and r3 = 'rows 1' and r4 = 'rows 1', left(r, 110) || ' ‖ ' || left(r2, 110) || ' ‖ ' || r3 || ' ‖ ' || r4);
    perform pg_temp.res('X2 패밀리 사진은 대표가 될 수 없다(family_primary_ck) · 폴더 = 주인 id(folder_ck — 패밀리 사진을 남의 패밀리 폴더에 · 제품 사진을 남의 제품 폴더에)',
      r5 like 'ERR 23514%product_image_family_primary_ck%' and r6 like 'ERR 23514%product_image_folder_ck%' and r7 like 'ERR 23514%product_image_folder_ck%', left(r5, 110) || ' ‖ ' || left(r6, 110) || ' ‖ ' || left(r7, 110));
    r  := pg_temp.own(format('insert into public.product_image (family_id, storage_path, content_type, is_active, source) values (%L, %L, %L, false, %L)', v_f1, v_f1::text || '/s1.jpg', 'image/jpeg', 'shopify'));
    r2 := pg_temp.own(format('insert into public.product_image (product_id, storage_path, content_type, is_active, source) values (%L, %L, %L, false, %L)', pg_temp.id('pB'), pg_temp.id('pB')::text || '/s2.jpg', 'image/jpeg', 'shopify'));
    r3 := pg_temp.own(format('insert into public.product_image (family_id, storage_path, content_type, is_active, source) values (%L, %L, %L, false, %L)', v_f1, v_f1::text || '/s3.jpg', 'image/jpeg', 'web'));
    perform pg_temp.res('S 출처: shopify 받음(패밀리 · 제품) · 모르는 값 거부(source_ck)', r = 'rows 1' and r2 = 'rows 1' and r3 like 'ERR 23514%product_image_source_ck%', r || ' ‖ ' || r2 || ' ‖ ' || left(r3, 110));
  exception when others then perform pg_temp.res('X · S 제약', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── T 저장소 정책(직원 신원으로 storage.objects 에 직접) ──
  begin
    r  := pg_temp.asx('M', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-images', v_f1::text || '/t-ok.jpg'));
    r2 := pg_temp.asx('M', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-images', gen_random_uuid()::text || '/t-stray.jpg'));
    r3 := pg_temp.asx('N', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-images', v_f1::text || '/t-nokey.jpg'));
    r4 := pg_temp.asx('M', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-images', pg_temp.id('pA')::text || '/t-prod.jpg'));
    perform pg_temp.res('T 저장소 정책: master 직원이 패밀리 폴더에 올림 받음 · 아무 uuid 폴더 거부 · master 없는 직원 거부 · 제품 폴더는 예전대로 받음',
      r = 'done' and r2 like 'ERR 42501%' and r3 like 'ERR 42501%' and r4 = 'done'
      and (select count(*) from storage.objects o where o.bucket_id = 'product-images' and o.name in (v_f1::text || '/t-ok.jpg', pg_temp.id('pA')::text || '/t-prod.jpg')) = 2, left(r, 60) || ' ‖ ' || left(r2, 110) || ' ‖ ' || left(r3, 110) || ' ‖ ' || left(r4, 60));
  exception when others then perform pg_temp.res('T 저장소 정책', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── O 패밀리 사진 창구(판정 1186) ──
  begin
    r := pg_temp.own(format('insert into storage.objects (bucket_id, name) values (%L, %L), (%L, %L)', 'product-images', v_f1::text || '/fa.jpg', 'product-images', v_f1::text || '/fb.png'));
    v_j := jsonb_build_array(
      jsonb_build_object('op', 'family_image_add', 'family_sku', 'ZZIMP1FAM', 'storage_path', v_f1::text || '/fa.jpg', 'content_type', 'image/jpeg', 'byte_size', 1000, 'width', 10, 'height', 10, 'file_name', 'fa.jpg'),
      jsonb_build_object('op', 'family_image_add', 'family_sku', 'ZZIMP1FAM', 'storage_path', v_f1::text || '/fb.png', 'content_type', 'image/png'));
    r2 := pg_temp.fiu('M', v_j, false, '{}');
    select count(*) into v_n from public.product_image i where i.family_id = v_f1 and i.is_active;
    perform pg_temp.res('O1 추가 미리 보기(p_commit false): 막기 0 · 저장 0', r = 'rows 2' and (pg_temp.j(r2)->>'committed') = 'false' and jsonb_array_length(pg_temp.j(r2)->'blocks') = 0 and v_n = 0, r || ' ‖ ' || left(r2, 400) || ' ‖ active family rows ' || v_n);
    r2 := pg_temp.fiu('M', v_j, true, '{}');
    select i.id into v_fa from public.product_image i where i.storage_path = v_f1::text || '/fa.jpg';
    select i.id into v_fb from public.product_image i where i.storage_path = v_f1::text || '/fb.png';
    insert into t_ids values ('fa', v_fa), ('fb', v_fb);
    select string_agg(coalesce(i.file_name, '-') || ' ' || (i.sort_order - (select min(q.sort_order) from public.product_image q where q.family_id = v_f1 and q.is_active) + 1)::text || ' ' || i.is_primary::text || ' ' || i.source || ' ' || (i.product_id is null)::text || ' ' || (i.updated_by is not null)::text, ' / ' order by i.sort_order) into r3 from public.product_image i where i.family_id = v_f1 and i.is_active;
    perform pg_temp.res('O2 추가 저장: 두 줄 · family_id 만 · 대표 아님 · 순서는 있던 줄(꺼진 것 포함) 뒤에 잇달아 · source manual · 저장한 사람', (pg_temp.j(r2)->>'committed') = 'true' and r3 = 'fa.jpg 1 false manual true true / - 2 false manual true true',
      left(r2, 200) || ' ‖ ' || coalesce(r3, '(null)'));
    r  := pg_temp.fiu('N', v_j, false, '{}');
    r2 := pg_temp.fiu('M', jsonb_build_array(jsonb_build_object('op', 'family_image_add', 'family_sku', 'ZZIMP2FAM', 'storage_path', v_f1::text || '/fa2.jpg', 'content_type', 'image/jpeg')), true, '{}');
    r3 := pg_temp.fiu('M', jsonb_build_array(jsonb_build_object('op', 'family_image_add', 'family_sku', 'ZZIMP1FAM', 'storage_path', v_f1::text || '/none.jpg', 'content_type', 'image/gif'),
                                             jsonb_build_object('op', 'family_image_add', 'family_sku', 'ZZIMP1FAM', 'storage_path', v_f1::text || '/fa.jpg', 'content_type', 'image/jpeg'),
                                             jsonb_build_object('op', 'family_image_off', 'family_sku', 'ZZIMP1FAM', 'image_id', pg_temp.id('pa1')),
                                             jsonb_build_object('op', 'family_image_order', 'family_sku', 'ZZIMP1FAM', 'image_ids', jsonb_build_array(v_fa, pg_temp.id('pa1'))),
                                             jsonb_build_object('op', 'family_image_off', 'family_sku', 'ZZNOPE', 'image_id', v_fa)), true, '{}');
    select string_agg(b->>'code', ' ' order by o) into r4 from jsonb_array_elements(pg_temp.j(r3)->'blocks') with ordinality as t(b, o);
    select string_agg(b->>'code', ' ' order by o) into r5 from jsonb_array_elements(pg_temp.j(r2)->'blocks') with ordinality as t(b, o);
    perform pg_temp.res('O3 거부: master 없는 직원 · 남의 패밀리 폴더 경로(image_path_mismatch) · 저장소에 없는 파일 · 형식 · 이미 등록 · 제품 사진을 패밀리 op 로 끄기 · 순서에 섞기 · 없는 패밀리 — 저장 0',
      r like 'ERR P0001: You cannot change master data%' and r5 like 'image_path_mismatch%' and r4 = 'image_type_invalid image_object_missing image_exists image_not_found image_not_found family_unknown'
      and (pg_temp.j(r3)->>'committed') = 'false' and (select count(*) from public.product_image i where i.family_id in (v_f1, v_f2) and i.is_active) = 2,
      left(r, 90) || ' ‖ ' || coalesce(r5, '(null)') || ' ‖ ' || coalesce(r4, left(r3, 300)));
    r := pg_temp.fiu('M', jsonb_build_array(jsonb_build_object('op', 'family_image_order', 'family_sku', 'ZZIMP1FAM', 'image_ids', jsonb_build_array(v_fb, v_fa))), true, '{}');
    select string_agg(k2.k || ' ' || i.sort_order, ' / ' order by i.sort_order) into r2 from public.product_image i join t_ids k2 on k2.id = i.id where i.family_id = v_f1 and i.is_active;
    perform pg_temp.res('O4 순서: fb 1 · fa 2', (pg_temp.j(r)->>'committed') = 'true' and r2 = 'fb 1 / fa 2', left(r, 200) || ' ‖ ' || coalesce(r2, '(null)'));
  exception when others then perform pg_temp.res('O 패밀리 사진 창구', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── G 웹 대표 가드(shop_listing_set op family_web_image_set) ──
  begin
    perform pg_temp.img('f2a', 'family_id', 'f2', 'z.jpg', false, 1, true);                     -- 다른 패밀리의 패밀리 사진
    perform pg_temp.img('foff', 'family_id', 'f1', 'off.jpg', false, 9, false);                  -- 이 패밀리의 꺼진 패밀리 사진
    r  := pg_temp.wis(pg_temp.id('pa2'), null, true);
    r2 := pg_temp.wis(pg_temp.id('fa'), pg_temp.id('pa2'), true);
    r3 := pg_temp.wis(pg_temp.id('f2a'), pg_temp.id('fa'), true);
    r4 := pg_temp.wis(pg_temp.id('foff'), pg_temp.id('fa'), true);
    r5 := pg_temp.wis(pg_temp.id('pc1'), pg_temp.id('fa'), true);
    perform pg_temp.res('G 웹 대표: 구성원 사진 받음 · 그 패밀리의 패밀리 사진 받음 · 다른 패밀리의 패밀리 사진 거부 · 꺼진 패밀리 사진 거부 · 패밀리 밖 제품 사진 거부(image_not_in_family) — 지금 web_image_id = fa',
      (pg_temp.j(r)->>'committed') = 'true' and (pg_temp.j(r2)->>'committed') = 'true'
      and (pg_temp.j(r3)->'blocks'->0->>'code') = 'image_not_in_family' and (pg_temp.j(r4)->'blocks'->0->>'code') = 'image_not_in_family' and (pg_temp.j(r5)->'blocks'->0->>'code') = 'image_not_in_family'
      and (select f.web_image_id from public.product_family f where f.id = v_f1) = pg_temp.id('fa'),
      left(r, 120) || ' ‖ ' || left(r2, 120) || ' ‖ ' || coalesce(pg_temp.j(r3)->'blocks'->0->>'code', left(r3, 150)) || ' ‖ ' || coalesce(pg_temp.j(r4)->'blocks'->0->>'code', left(r4, 150)) || ' ‖ ' || coalesce(pg_temp.j(r5)->'blocks'->0->>'code', left(r5, 150)));
  exception when others then perform pg_temp.res('G 웹 대표 가드', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── P payload(판정 1179 · 이견 1 · ⬜3) ──
  begin
    v_j := public.shop_product_payload(pg_temp.id('s1'), v_f1, null);
    v_j2 := public.shop_product_payload(pg_temp.id('s0'), v_f1, null);
    perform pg_temp.res('P1 순서: 표지(web_image_id = 패밀리 사진 fa) → 변형 대표(pa1 · pb1) → 구성원 나머지(pa2) → 패밀리 사진(fb) · 꺼진 것 · 다른 패밀리 것은 없다',
      pg_temp.fids('s1') = 'fa pa1 pb1 pa2 fb', pg_temp.fids('s1'));
    perform pg_temp.res('P2 file 꼴: 패밀리 사진 = product_id null · family_id · sku(패밀리 SKU) · alt 패밀리 이름 · 구성원 사진 = 예전 열쇠 다섯 그대로 · 변형 칸(image_id 포함)은 패밀리 사진이 생겨도 같다',
      (v_j->'files'->0->'product_id') = 'null'::jsonb and (v_j->'files'->0->>'family_id') = v_f1::text and (v_j->'files'->0->>'sku') = 'ZZIMP1FAM' and (v_j->'files'->0->>'alt') = 'imp-1 test family 1'
      and (v_j->'files'->0->>'image_path') = v_f1::text || '/fa.jpg'
      and (select bool_and((select count(*) from jsonb_object_keys(f)) = 5 and not f ? 'family_id' and not f ? 'sku' and (f->>'product_id') is not null) from jsonb_array_elements(v_j->'files') f where (f->>'product_image_id')::uuid in (pg_temp.id('pa1'), pg_temp.id('pb1'), pg_temp.id('pa2')))
      and (v_j->'variants')::text = v_var0, left((v_j->'files'->0)::text, 330) || ' ‖ ' || left((v_j->'files'->1)::text, 250) || ' ‖ variants same ' || ((v_j->'variants')::text = v_var0));
    perform pg_temp.res('P3a hash(사진 보내는 스토어 · send_images true + 패밀리 사진): 패밀리 사진이 생기면 hash 가 바뀐다(사진은 hash 안)',
      (v_j->>'hash') <> v_h1 and (v_j->>'send_images') = 'true', format('s1 %s → %s', v_h1, v_j->>'hash'));
    perform pg_temp.res('P3b hash(안 보내는 스토어 · send_images false): 패밀리 사진이 생겨도 files [] · 변형 image_id null · hash 그대로',
      (v_j2->'files') = '[]'::jsonb and (v_j2->>'hash') = v_h0 and (v_j2->>'send_images') = 'false'
      and (select bool_and((x->'image_id') = 'null'::jsonb) from jsonb_array_elements(v_j2->'variants') x),
      format('s0 %s → %s · s0 files %s', v_h0, v_j2->>'hash', v_j2->'files'));
  exception when others then perform pg_temp.res('P payload', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── W 웹 대표인 패밀리 사진 끄기(판정 1187) ──
  begin
    v_key := 'ZZIMP1FAM:family_web_image_off:' || pg_temp.id('fa')::text;
    v_j := jsonb_build_array(jsonb_build_object('op', 'family_image_off', 'family_sku', 'ZZIMP1FAM', 'image_id', pg_temp.id('fa')));
    r := pg_temp.fiu('M', v_j, true, '{}');
    select (i.is_active and f.web_image_id = i.id)::text into r2 from public.product_image i join public.product_family f on f.id = v_f1 where i.id = pg_temp.id('fa');
    perform pg_temp.res('W1 웹 대표 끄기 · 확인 없이: 저장 안 됨 · 경고 family_web_image_off · unacked 에 그 열쇠 · master 만 가진 직원(shopify 열쇠 없음)',
      (pg_temp.j(r)->>'committed') = 'false' and (pg_temp.j(r)->'warnings'->0->>'code') = 'family_web_image_off' and (pg_temp.j(r)->'unacked') = jsonb_build_array(v_key) and r2 = 'true', left(r, 420) || ' ‖ still on + web ' || coalesce(r2, '(null)'));
    r := pg_temp.fiu('M', v_j, true, array[v_key]);
    select (not i.is_active and f.web_image_id is null)::text into r2 from public.product_image i join public.product_family f on f.id = v_f1 where i.id = pg_temp.id('fa');
    perform pg_temp.res('W2 확인(ack)하고 끄기: 사진 꺼짐 + web_image_id 가 같은 호출에서 비워짐 · 다른 패밀리 사진(fb)은 그대로 · payload 표지는 기본값(pa1)',
      (pg_temp.j(r)->>'committed') = 'true' and r2 = 'true' and (select i.is_active from public.product_image i where i.id = pg_temp.id('fb')) and pg_temp.fids('s1') = 'pa1 pb1 pa2 fb', left(r, 160) || ' ‖ off + web null ' || coalesce(r2, '(null)') || ' ‖ ' || pg_temp.fids('s1'));
  exception when others then perform pg_temp.res('W 웹 대표 끄기', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── C 표지 굳히기(판정 1188) — web_image_id 를 창구 밖에서 꺼진 사진 · 떠난(패밀리 밖) 제품 사진으로 ──
  begin
    update public.product_family set web_image_id = pg_temp.id('fa') where id = v_f1;      r  := pg_temp.fids('s1');   -- 꺼진 패밀리 사진
    update public.product_family set web_image_id = pg_temp.id('pc1') where id = v_f1;     r2 := pg_temp.fids('s1');   -- 패밀리 밖 제품의 사진
    update public.product_image set is_active = false where id = pg_temp.id('pa2');
    update public.product_family set web_image_id = pg_temp.id('pa2') where id = v_f1;     r3 := pg_temp.fids('s1');   -- 꺼진 구성원 사진
    update public.product_image set is_active = true where id = pg_temp.id('pa2');          r4 := pg_temp.fids('s1');   -- 다시 켜면 표지
    update public.product_family set web_image_id = pg_temp.id('fb') where id = v_f1;      r5 := pg_temp.fids('s1');   -- 켜진 패밀리 사진
    perform pg_temp.res('C 표지(1188): web_image_id 가 꺼진 패밀리 사진 · 패밀리 밖 제품 사진 · 꺼진 구성원 사진 → 기본 표지(pa1) · 켜진 구성원 사진 · 켜진 패밀리 사진 → 그 사진이 맨 앞',
      r = 'pa1 pb1 pa2 fb' and r2 = 'pa1 pb1 pa2 fb' and r3 = 'pa1 pb1 fb' and r4 = 'pa2 pa1 pb1 fb' and r5 = 'fb pa1 pb1 pa2', r || ' ‖ ' || r2 || ' ‖ ' || r3 || ' ‖ ' || r4 || ' ‖ ' || r5);
  exception when others then perform pg_temp.res('C 표지 굳히기', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── Q 큐(문장 트리거 · product_image 전용 갈래) ──
  begin
    perform pg_temp.qclear();  perform pg_temp.img('q1', 'family_id', 'f1', 'q1.jpg', false, 5, true);        v_n  := pg_temp.qn('f1');
    perform pg_temp.qclear();  update public.product_image set sort_order = 6 where id = pg_temp.id('q1');     v_n2 := pg_temp.qn('f1');
    perform pg_temp.qclear();  delete from public.product_image where id = pg_temp.id('q1');                   v_n3 := pg_temp.qn('f1');
    perform pg_temp.qclear();  perform pg_temp.img('q2', 'family_id', 'f2', 'q2.jpg', false, 5, true);        v_n4 := pg_temp.qn('f2');
    perform pg_temp.qclear();  update public.product_image set sort_order = 3 where id = pg_temp.id('pa2');    v_n5 := pg_temp.qn('f1');
    perform pg_temp.res('Q 큐: 패밀리 사진 넣기 · 고치기 · 지우기 → 그 패밀리의 켜진 listing 마다 한 줄(스토어 둘 = 2) · listing 이 꺼진 패밀리는 0 · 구성원 사진(제품 갈래)은 예전대로 2',
      v_n = 2 and v_n2 = 2 and v_n3 = 2 and v_n4 = 0 and v_n5 = 2, format('i %s · u %s · d %s · off-listing family %s · member photo %s', v_n, v_n2, v_n3, v_n4, v_n5));
  exception when others then perform pg_temp.res('Q 큐', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── U 무접촉 · H 실제 hash · N 정적 · A 권한 · Z 실물 ──
  select string_agg(x::text, ' ' order by x.sku) into r from public.product_image_primary(array['ZZIMP1-A', 'ZZIMP1-B', 'ZZIMP1-C']) x;
  select string_agg(p.proname || ' ' || left(md5(p.prosrc), 8), ' · ' order by p.proname) into r2 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_update', 'product_image_primary', 'product_export', 'shop_variant_payload', 'shop_link_plan');
  perform pg_temp.res('U 무접촉: product_image_primary 결과가 패밀리 사진이 생기기 전과 같다 · 다섯 함수(product_update · product_image_primary · product_export · shop_variant_payload · shop_link_plan)의 몸 md5 그대로',
    r = v_prim0 and r2 = 'product_export 715c71cb · product_image_primary bb8974a4 · product_update 6d7ec9ff · shop_link_plan bccc29e5 · shop_variant_payload 12e18639', coalesce(r2, '(null)') || ' ‖ primary same ' || coalesce((r = v_prim0)::text, '(null)'));
  select md5(coalesce(string_agg(x.k || x.h, ',' order by x.k), '')) into r from (
    select l.store_id::text || '|' || coalesce(l.family_id::text, '') || '|' || coalesce(l.product_id::text, '') as k, public.shop_product_payload(l.store_id, l.family_id, l.product_id)->>'hash' as h
      from (select sp.store_id, sp.family_id, sp.product_id from public.shop_product sp where sp.send_images and sp.store_id not in (pg_temp.id('s1'), pg_temp.id('s0'))
            union (select l2.store_id, l2.family_id, l2.product_id from public.shop_listing l2 where l2.is_on and l2.family_id is not null and l2.store_id not in (pg_temp.id('s1'), pg_temp.id('s0')) order by l2.id limit 12)) l) x;
  perform pg_temp.res('H hash(기존 대상 · 패밀리 사진 없음): 실제 대상의 payload hash 가 begin 앞과 같다(사진을 보내는 덧씌우기 대상 전부 + 켜진 패밀리 listing 12 — 다시 push 되지 않는다)', r = current_setting('d.real_hash'), 'head ' || current_setting('d.real_hash') || ' · now ' || coalesce(r, '(null)'));
  perform pg_temp.res('N nowhere 정적: 새 창구 + 재발행 셋에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select count(*) = 4 and sum(pg_temp.nowhere(p.prosrc)) = 0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('family_image_update', 'shop_listing_set', 'shop_product_payload', 'shop_queue_trigger')),
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('family_image_update', 'shop_listing_set', 'shop_product_payload', 'shop_queue_trigger')));
  perform pg_temp.res('A 권한: family_image_update 는 authenticated 실행 · anon · service_role 없음 · definer · 재발행 셋의 권한 · definer 여부는 예전 그대로',
    (select count(*) = 1 and bool_and(p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'family_image_update')
    and (select string_agg(p.proname || ' ' || p.proacl::text || ' ' || p.prosecdef::text || ' ' || p.provolatile::text, ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_listing_set', 'shop_product_payload', 'shop_queue_trigger'))
        = 'shop_listing_set {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} true v ‖ shop_product_payload {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} false s ‖ shop_queue_trigger {postgres=X/postgres,service_role=X/postgres} true v',
    (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.prosecdef::text || ' ' || p.provolatile::text, ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('family_image_update', 'shop_listing_set', 'shop_product_payload', 'shop_queue_trigger')));
  select (select count(*) from public.product_image i where left(i.storage_path, 36) not in (select t.id::text from t_ids t))::text || '/'
      || (select count(*) from public.product_family f where f.web_image_id is not null and f.id not in (v_f1, v_f2))::text || '/'
      || (select count(*) from public.shop_push_queue q where q.done_at is null and q.store_id not in (pg_temp.id('s1'), pg_temp.id('s0')))::text into r;
  perform pg_temp.res('Z 실물 무접촉: 가짜 폴더 밖의 사진 행 수 · 웹 대표가 지정된 실제 패밀리 수 · 실제 스토어의 열린 큐 수가 머리와 같다 · claims 비었음 · postgres',
    r = current_setting('d.real_head') and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres', 'head ' || current_setting('d.real_head') || ' · now ' || r || ' · user ' || current_user);
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
rollback;
\pset tuples_only off
\pset format aligned
-- 기대: 시험(-v mig) OK 23 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 5(P0 · P3b · U · H · Z) · FAIL 15 · 확인(적용 뒤 · -v mig 없음) OK 23 · FAIL 0(확인 갈래는 적용 전에는 못 돈다 — 첫 통과는 Caleb 의 확인 실행)
--       OK 줄 꼴 = 「OK <이름>」 · 끝 줄 「OK 23 · FAIL 0 · begin ~ 끝 …」 · 시험 begin ~ 끝 약 7 ~ 8 초(2026-11-11 17:25 토론토 실측 7.98 s) · 시퀀스 무접촉
--       변이(2026-11-11): XOR CHECK 를 뺀 판 → FAIL 2(X1 · Z) · 웹 대표 가드를 옛것으로 둔 판 → FAIL 5(G · P1 · P2 · W1 · W2) · 패밀리 사진 순서를 맨 앞으로 바꾼 판 → FAIL 4(P1 · P2 · W2 · C)
