-- shop-photo-imp-2b-1 검증 — supabase/migrations/20261112044938_shop_photo_imp_2b1_web_cover.sql (가져온 FAM 표지를 웹 대표로 · 판정 1198 · dry run 요약 · 지시서 ~/asung/prompts/shop-photo-imp-2b.md §1 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB · ⚠️ 토론토 17:00 뒤): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261112044938_shop_photo_imp_2b1_web_cover.sql -f supabase/tests/shop_photo_imp_2b1_check.sql 2>&1 | tee /tmp/shop_photo_imp_2b1.out
--   확인(적용 뒤 · Caleb) · 마른 실행(적용 전): 같은 명령에서 -v mig=… 만 뺀다 — 기대 수는 파일 끝
--   2a 회귀: 2a 검증 파일을 이 마이그레이션 위에서 그대로 돌린다(-v mig=<이 마이그레이션> -f supabase/tests/shop_photo_imp_2a_check.sql) — 기대 OK 18 · FAIL 0(멱등 W3 · 순서 W2 · 대표 1197 · 짝 · dry)
--   ⚠️ 실제 행 무변: 재료는 전부 가짜 — 패밀리 여섯(ZZIBAFAM ~ ZZIBFFAM) · 제품 하나(ZZIB-F1) · 스토어 하나(zzib1 사진 보냄 · 실제 스토어 한 행의 복사) · 가짜 계획 줄(load_n 910000 대) · 저장소 파일 행(가짜 폴더)
--      끝은 rollback · 시퀀스를 쓰는 창구는 부르지 않는다 · shop_photo_claim 은 늘 p_only(가짜 줄 id)로만 · shop_photo_dry 는 창구 자체가 실제 listing 의 계획 줄을 되돌아가는 안쪽 블록에서 돌려 본다(저장 0 — D1 이 센다)
--   ⚠️ 잠금: 마이그레이션은 함수 둘의 재발행뿐(표 잠금 없음) · 가짜 행만 쓴다 · lock_timeout 3 s · 검사는 pg_temp.run() 한 문장
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- 머리(begin 앞 · 잠금 없음)
select
  (select count(*) from public.product_image)::text || '/' || (select count(*) from public.shop_media)::text || '/' || (select count(*) from public.shop_push_queue q where q.done_at is null)::text
    || '/' || (select count(*) from storage.objects o where o.bucket_id = 'product-images')::text
    || '/' || (select count(*) filter (where f.web_image_id is not null)::text || ':' || md5(coalesce(string_agg(f.id::text || coalesce(f.web_image_id::text, '-') || f.updated_at::text, ',' order by f.id), '')) from public.product_family f) as real_head,
  (select count(distinct pl.family_id) from public.shop_photo_plan pl join public.product_family f on f.id = pl.family_id
    where pl.rule = 'cover' and pl.status in ('planned', 'claimed', 'failed') and f.web_image_id is null)::int as cover_head,
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('shop_photo_done', 'shop_photo_claim', 'shop_photo_fail', 'shop_photo_pair_mark', 'shop_photo_verify_mark', 'shop_photo_run_add', 'shop_photo_plan_load', 'shop_product_payload', 'shop_queue_trigger', 'shop_queue_add', 'family_image_update', 'shop_listing_set', 'product_update')) as fn_head,
  (select f.id::text from public.product_family f where f.is_active order by f.sku limit 1) as fsrc,
  (select p.id::text from public.product p where p.is_active and p.parent_product_id is null and p.family_id is null and p.sellable order by p.sku limit 1) as psrc,
  (select s.id::text from public.shop_store s where s.code = 'asung') as ssrc \gset
select 'head: product_image/shop_media/open queue/bucket objects/families with a web image ' || left(:'real_head', 60) || ' · families a cover import would give a web image ' || :cover_head;

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
-- safeupdate 정적 셈(shop_photo_imp_2a_check.sql 과 같은 스캐너 · 깊이 0 WHERE 없는 update · delete 수)
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
create function pg_temp.call(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return coalesce(v_out, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.img(p_k text, p_owner_col text, p_owner text, p_file text, p_primary boolean, p_sort int, p_active boolean) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into t_ids values (p_k, v_id);
  execute format('insert into public.product_image (id, %I, storage_path, content_type, is_primary, sort_order, is_active, source) values ($1, $2, $3, ''image/jpeg'', $4, $5, $6, ''manual'')', p_owner_col)
    using v_id, pg_temp.id(p_owner), pg_temp.id(p_owner)::text || '/' || p_file, p_primary, p_sort, p_active;
end $$;
-- 가짜 계획 줄(패밀리 자리 · 표에 직접)
create function pg_temp.pln(p_k text, p_owner text, p_rule text, p_seq int, p_no int) returns void language plpgsql as $$
declare v_n bigint;
begin
  insert into public.shop_photo_plan (load_n, pic_kind, rule, owner_sku, family_id, seq, md5_key, file_md5, byte_size, content_type, file_name, src_store_id, src_product_gid, src_media_gid, src_url, src_pos, storage_path)
  values (910000 + p_no, case p_rule when 'cover' then 'fam_cover' else 'fam_unassigned' end, p_rule, 'ZZIB-' || p_k, pg_temp.id(p_owner), p_seq, md5('b1' || p_k), md5('fb1' || p_k), 2000 + p_no, 'image/jpeg', p_k || '.jpg',
          pg_temp.id('s1'), 'gid://shopify/Product/7910000001', 'gid://shopify/MediaImage/7910009' || lpad(p_no::text, 3, '0'), 'https://cdn.test.invalid/b1-' || p_k || '.jpg?v=1', p_seq,
          pg_temp.id(p_owner)::text || '/shopify-' || md5('b1' || p_k) || '.jpg')
  returning id into v_n;
  insert into t_num values (p_k, v_n);
end $$;
-- 가짜 줄을 등록(저장소 파일 행 + shop_photo_done) — 준 순서대로 한 호출
create function pg_temp.done(p_ks text[]) returns text language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name) select 'product-images', pl.storage_path from public.shop_photo_plan pl join t_num t on t.n = pl.id
   where t.k = any(p_ks) and not exists (select 1 from storage.objects o where o.bucket_id = 'product-images' and o.name = pl.storage_path);
  return pg_temp.call(format('select public.shop_photo_done(%L::jsonb)::text',
    (select jsonb_agg(jsonb_build_object('id', t.n, 'byte_size', pl.byte_size) order by array_position(p_ks, t.k)) from t_num t join public.shop_photo_plan pl on pl.id = t.n where t.k = any(p_ks))::text));
end $$;
create function pg_temp.web(p_fam text) returns text language sql as $$                               -- 그 가짜 패밀리의 웹 대표가 어느 가짜 줄(또는 가짜 사진)인가
  select coalesce((select t.k from t_num t join public.shop_photo_plan pl on pl.id = t.n where pl.product_image_id = f.web_image_id), (select t.k from t_ids t where t.id = f.web_image_id), case when f.web_image_id is null then '(null)' else '(other)' end)
    from public.product_family f where f.id = pg_temp.id(p_fam) $$;
create function pg_temp.fake_real() returns text language sql as $$                                 -- 가짜 폴더 · 가짜 스토어 · 가짜 패밀리 밖의 실제 행(머리와 같은 꼴)
  select (select count(*) from public.product_image i where left(i.storage_path, 36) not in (select t.id::text from t_ids t))::text || '/'
      || (select count(*) from public.shop_media m where m.store_id <> pg_temp.id('s1'))::text || '/'
      || (select count(*) from public.shop_push_queue q where q.done_at is null and q.store_id <> pg_temp.id('s1'))::text || '/'
      || (select count(*) from storage.objects o where o.bucket_id = 'product-images' and left(o.name, 36) not in (select t.id::text from t_ids t))::text || '/'
      || (select count(*) filter (where f.web_image_id is not null)::text || ':' || md5(coalesce(string_agg(f.id::text || coalesce(f.web_image_id::text, '-') || f.updated_at::text, ',' order by f.id), ''))
            from public.product_family f where f.id not in (select t.id from t_ids t)) $$;
create function pg_temp.state() returns text language plpgsql as $$                                 -- 저장 0 을 재는 지문(가짜 포함 전부)
begin
  return (select count(*) from public.product_image)::text || '/' || (select count(*) from public.shop_media)::text || '/' || (select count(*) from public.shop_push_queue)::text
      || '/' || (select count(*) from storage.objects)::text || '/' || (select count(*) from public.shop_photo_run)::text
      || '/' || (select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.product_image_id::text, '') || coalesce(pl.verify_ok::text, ''), ',' order by pl.id), '')) from public.shop_photo_plan pl)
      || '/' || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr)
      || '/' || (select md5(coalesce(string_agg(f.id::text || coalesce(f.web_image_id::text, '-') || f.updated_at::text, ',' order by f.id), '')) from public.product_family f);
end $$;

begin;
set local lock_timeout = '3s';
select set_config('d.real_head', :'real_head', true), set_config('d.cover_head', :'cover_head', true), set_config('d.fn_head', :'fn_head', true),
       set_config('d.fsrc', :'fsrc', true), set_config('d.psrc', :'psrc', true), set_config('d.ssrc', :'ssrc', true), clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create function pg_temp.run() returns void language plpgsql as $$
declare
  c_mark constant timestamptz := '2001-01-01 00:00:00+00';
  v_fj jsonb; v_pj jsonb; v_sj jsonb; v_id uuid; k text; r text; r2 text; r3 text; v_j jsonb; v_j2 jsonb; v_j3 jsonb; v_n int; v_n2 int;
  v_real0 text; v_fake bigint[]; v_st text; v_st2 text;
begin
  select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.verify_ok::text, '') || pl.attempts::text || coalesce(pl.product_image_id::text, ''), ',' order by pl.id), '')) || '/'
      || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr)
    into v_real0 from public.shop_photo_plan pl;

  -- ── 가짜 재료(문지기 · 큐 트리거를 끄고 넣는다 — 계획 줄부터는 켠 채로) ──
  execute 'set local session_replication_role = replica';
  select to_jsonb(f) into v_fj from public.product_family f where f.id = current_setting('d.fsrc')::uuid;
  select to_jsonb(p) into v_pj from public.product p where p.id = current_setting('d.psrc')::uuid;
  select to_jsonb(s) into v_sj from public.shop_store s where s.id = current_setting('d.ssrc')::uuid;
  foreach k in array array['A', 'B', 'C', 'D', 'E', 'F'] loop
    v_id := gen_random_uuid();  insert into t_ids values ('f' || k, v_id);
    perform pg_temp.cp('public.product_family', v_fj || jsonb_build_object('id', v_id, 'sku', 'ZZIB' || k || 'FAM', 'name', 'imp-2b-1 test family ' || k, 'cin7_id', null, 'web_image_id', null, 'is_active', true,
      'option1_name', 'Color', 'option2_name', null, 'option3_name', null, 'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  v_id := gen_random_uuid();  insert into t_ids values ('pF', v_id);
  perform pg_temp.cp('public.product', v_pj || jsonb_build_object('id', v_id, 'sku', 'ZZIB-F1', 'name', 'imp-2b-1 test ZZIB-F1', 'cin7_id', null, 'parent_product_id', null, 'family_id', pg_temp.id('fF'),
    'option1_value', 'f1', 'option2_value', null, 'option3_value', null, 'is_active', true, 'sellable', true, 'description_html', null, 'description_edited_at', null, 'description_edited_by', null, 'created_at', c_mark, 'updated_at', c_mark));
  v_id := gen_random_uuid();  insert into t_ids values ('s1', v_id);
  perform pg_temp.cp('public.shop_store', v_sj || jsonb_build_object('id', v_id, 'code', 'zzib1', 'shop_domain', 'zzib1-test.myshopify.com', 'label', 'imp-2b-1 test store', 'secret_prefix', 'ZZIB1',
    'is_active', true, 'send_images', true, 'created_at', c_mark, 'updated_at', c_mark));
  insert into public.shop_listing (store_id, family_id, is_on, turned_on_at, turned_off_at) values (pg_temp.id('s1'), pg_temp.id('fA'), true, now(), null), (pg_temp.id('s1'), pg_temp.id('fF'), true, now(), null);   -- shop_product 행 없음 = 사진을 보낸다
  -- IMS 에 이미 있는 사진: 패밀리 B 의 켜진 패밀리 사진 ib(사람이 지정한 웹 대표) · 패밀리 E 의 꺼진 패밀리 사진 ie(계획 줄 e1 과 같은 경로) · ZZIB-F1 의 대표 pf1
  perform pg_temp.img('ib', 'family_id', 'fB', 'b-manual.jpg', false, 1, true);
  perform pg_temp.img('ie', 'family_id', 'fE', 'shopify-' || md5('b1e1') || '.jpg', false, 1, false);
  perform pg_temp.img('pf1', 'product_id', 'pF', 'f1.jpg', true, 1, true);
  update public.product_family set web_image_id = pg_temp.id('ib') where id = pg_temp.id('fB');
  execute 'set local session_replication_role = origin';
  -- 계획 줄: A 표지 + 패밀리 사진 · B 표지(+ 안 가져올 표지 b2) · C 표지 둘 · D 표지 둘 · E 표지(꺼진 사진과 같은 경로) + 패밀리 사진 · F 표지(가져오지 않는다 — dry 가 본다)
  perform pg_temp.pln('a1', 'fA', 'cover', 1, 1);   perform pg_temp.pln('a2', 'fA', 'family', 2, 2);
  perform pg_temp.pln('b1', 'fB', 'cover', 1, 3);   perform pg_temp.pln('b2', 'fB', 'cover', 2, 4);
  perform pg_temp.pln('c1', 'fC', 'cover', 1, 5);   perform pg_temp.pln('c2', 'fC', 'cover', 2, 6);
  perform pg_temp.pln('d1', 'fD', 'cover', 1, 7);   perform pg_temp.pln('d2', 'fD', 'cover', 2, 8);
  perform pg_temp.pln('e1', 'fE', 'cover', 1, 9);   perform pg_temp.pln('e2', 'fE', 'family', 2, 10);
  perform pg_temp.pln('f1', 'fF', 'cover', 1, 11);
  select array_agg(t.n) into v_fake from t_num t where t.k not in ('b2', 'f1');
  perform public.shop_photo_verify_mark((select jsonb_agg(jsonb_build_object('id', x, 'ok', true)) from unnest(v_fake) x));
  select jsonb_array_length(public.shop_photo_claim(60, 30, false, v_fake)) into v_n;
  update public.shop_push_queue set done_at = now(), result = 'ok' where done_at is null and store_id = pg_temp.id('s1');

  -- ── T 판정 1198 ──
  begin
    r := pg_temp.done(array['a2', 'a1']);
    select count(*) into v_n2 from public.shop_push_queue q where q.done_at is null and q.store_id = pg_temp.id('s1') and q.family_id = pg_temp.id('fA');
    perform pg_temp.res('T1 1198: 웹 대표가 비어 있는 패밀리에 표지를 등록 → 그 표지가 웹 대표(같은 호출) · 표지 아닌 패밀리 사진(a2)은 아님 · 패밀리 사진은 대표(is_primary) 아님 · 큐는 그 listing 에 열린 줄 하나(사진 넣기 + 패밀리 갱신)',
      v_n = 9 and pg_temp.j(r) @> '{"done":2,"rejected":[]}' and pg_temp.web('fA') = 'a1' and v_n2 = 1
      and (select bool_and(i.family_id = pg_temp.id('fA') and i.is_active and not i.is_primary and i.source = 'shopify') and count(*) = 2 from public.product_image i join public.shop_photo_plan pl on pl.product_image_id = i.id where pl.id in (pg_temp.n('a1'), pg_temp.n('a2'))),
      'claimed ' || v_n || ' · ' || left(r, 120) || ' · web ' || pg_temp.web('fA') || ' · open queue ' || v_n2);
  exception when others then perform pg_temp.res('T1 1198', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    r := pg_temp.done(array['b1']);
    perform pg_temp.res('T2 1198 무접촉: 이미 사람이 지정한 패밀리는 표지를 가져와도 웹 대표 · updated_at 그대로(패밀리 행을 건드리지 않는다)',
      pg_temp.j(r) @> '{"done":1}' and pg_temp.web('fB') = 'ib' and (select f.updated_at = c_mark from public.product_family f where f.id = pg_temp.id('fB'))
      and (select pl.status = 'done' from public.shop_photo_plan pl where pl.id = pg_temp.n('b1')),
      left(r, 120) || ' · web ' || pg_temp.web('fB') || ' · updated_at ' || (select f.updated_at::text from public.product_family f where f.id = pg_temp.id('fB')));
  exception when others then perform pg_temp.res('T2 1198 무접촉', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    r := pg_temp.done(array['c2', 'c1']);
    perform pg_temp.res('T3 1198 표지 두 장: 한 호출에 둘 다 등록(뒤 표지를 먼저 적어 보냄) → 계획 순서 앞(seq 1) 하나만 웹 대표 · 둘 다 사진 행은 생긴다',
      pg_temp.j(r) @> '{"done":2}' and pg_temp.web('fC') = 'c1' and (select count(*) = 2 from public.product_image i where i.family_id = pg_temp.id('fC') and i.is_active),
      left(r, 120) || ' · web ' || pg_temp.web('fC'));
  exception when others then perform pg_temp.res('T3 1198 표지 두 장', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    r := pg_temp.done(array['d2']);   r2 := pg_temp.web('fD');
    r3 := pg_temp.done(array['d1']);
    perform pg_temp.res('T4 1198 null 일 때만: 뒤 표지만 먼저 들어오면 그것이 웹 대표 · 앞 표지가 나중에 와도 바꾸지 않는다',
      pg_temp.j(r) @> '{"done":1}' and r2 = 'd2' and pg_temp.j(r3) @> '{"done":1}' and pg_temp.web('fD') = 'd2',
      'after d2: ' || r2 || ' · after d1: ' || pg_temp.web('fD') || ' · ' || left(r3, 100));
  exception when others then perform pg_temp.res('T4 1198 null 일 때만', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    r := pg_temp.done(array['e1', 'e2']);
    perform pg_temp.res('T5 1198 켜진 후보만: 같은 경로의 사진 행이 이미 있고 꺼져 있으면 그 행을 받아들이되 웹 대표로 세우지 않는다 · 표지 아닌 패밀리 사진만으로도 서지 않는다',
      pg_temp.j(r) @> '{"done":2}' and pg_temp.web('fE') = '(null)' and (select pl.product_image_id = pg_temp.id('ie') from public.shop_photo_plan pl where pl.id = pg_temp.n('e1'))
      and (select not i.is_active from public.product_image i where i.id = pg_temp.id('ie')),
      left(r, 120) || ' · web ' || pg_temp.web('fE'));
  exception when others then perform pg_temp.res('T5 1198 켜진 후보만', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    v_st := pg_temp.state();
    r := pg_temp.done(array['a1', 'a2', 'b1', 'c1', 'c2', 'd1', 'd2', 'e1', 'e2']);
    perform pg_temp.res('T6 멱등: 등록한 아홉 줄을 다시 부르면 already_done 9 · 사진 행 · 짝 · 큐 · 계획 줄 · 패밀리 웹 대표 무변', pg_temp.j(r) @> '{"done":0,"already_done":9,"rejected":[]}' and pg_temp.state() = v_st, left(r, 160) || ' · state same ' || (pg_temp.state() = v_st));
  exception when others then perform pg_temp.res('T6 멱등', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── D dry run ──
  begin
    v_st := pg_temp.state();
    v_j := public.shop_photo_dry();
    v_st2 := pg_temp.state();
    perform pg_temp.res('D1 dry run 저장 0: 사진 행 · shop_media · 큐 · 저장소 · run · 계획 줄 · 짝 · 패밀리 웹 대표 지문이 부르기 앞뒤 같다 · 꼴에 web_cover_new{count, families} · 가져오지 않은 가짜 패밀리 F 의 웹 대표는 그대로 비어 있다',
      v_st = v_st2 and v_j ?& array['plan', 'primary_new', 'web_cover_new', 'pairs', 'dups', 'listings_sending_images'] and v_j->'web_cover_new' ?& array['count', 'families'] and pg_temp.web('fF') = '(null)',
      'state same ' || (v_st = v_st2) || ' · keys ' || (select string_agg(x, ',') from jsonb_object_keys(v_j) x) || ' · web F ' || pg_temp.web('fF'));
    perform pg_temp.res('D2 dry run 요약(1198): 웹 대표가 새로 설 패밀리 수 = 머리의 실물 수 + 가짜 F 하나 · 목록에 F 가 있다 · 이미 지정된 B(안 가져온 표지 b2 가 남아 있다) · 이미 선 A · C · D · 표지를 다 가져온 E 는 없다',
      (v_j->'web_cover_new'->>'count')::int = current_setting('d.cover_head')::int + 1 and jsonb_array_length(v_j->'web_cover_new'->'families') = (v_j->'web_cover_new'->>'count')::int
      and v_j->'web_cover_new'->'families' ? 'ZZIBFFAM' and not v_j->'web_cover_new'->'families' ?| array['ZZIBAFAM', 'ZZIBBFAM', 'ZZIBCFAM', 'ZZIBDFAM', 'ZZIBEFAM'],
      'count ' || (v_j->'web_cover_new'->>'count') || ' · head ' || current_setting('d.cover_head') || ' · fake in list ' || (select coalesce(string_agg(x, ','), '(none)') from jsonb_array_elements_text(v_j->'web_cover_new'->'families') x where x like 'ZZIB%'));
    select x.e into v_j2 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) where x.e->>'store' = 'zzib1' and x.e->>'sku' = 'ZZIBFFAM';
    perform pg_temp.res('D3 dry run(1195 · 1198 · 가짜 listing F): 가져올 표지 한 장이 첫 사진이 된다(first_photo_changes · cover_set) · 새 표지 pos 1 · 이미 있던 사진(구성원 대표)은 was_pos 1 → pos 2 · 이미 있던 사진끼리의 순서 그대로 · files 뒤 = 앞 + 1',
      v_j2 is not null and (v_j2->>'first_photo_changes')::boolean and (v_j2->>'cover_set')::boolean and (v_j2->>'existing_order_kept')::boolean
      and (v_j2->>'files_before')::int = 1 and (v_j2->>'files_after')::int = 2 and (v_j2->>'new_files')::int = 1
      and v_j2->'files'->0 @> jsonb_build_object('pos', 1, 'new', true, 'photo_of', 'ZZIBFFAM', 'file', 'shopify-' || md5('b1f1') || '.jpg')
      and v_j2->'files'->1 @> jsonb_build_object('pos', 2, 'was_pos', 1, 'new', false, 'photo_of', 'ZZIB-F1', 'file', 'f1.jpg'),
      coalesce(left(v_j2::text, 700), '(fake listing F not in changed)'));
    select x.e into v_j3 from jsonb_array_elements(v_j->'listings_sending_images'->'unchanged') x(e) where x.e #>> '{}' = 'zzib1 ZZIBAFAM';
    perform pg_temp.res('D4 dry run: 다 가져온 가짜 listing A 는 unchanged(더 올 사진 없음) · changed 줄마다 cover_set 열쇠가 있다 · 낱개 listing 의 cover_set 은 늘 false',
      v_j3 is not null and (select coalesce(bool_and(x.e ? 'cover_set'), true) from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e))
      and not exists (select 1 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) join public.product p on p.sku = x.e->>'sku' where (x.e->>'cover_set')::boolean),
      'A unchanged ' || (v_j3 is not null) || ' · changed ' || (select coalesce(string_agg((x.e->>'store') || ' ' || (x.e->>'sku') || ' cover_set ' || coalesce(x.e->>'cover_set', '(missing)'), ', '), '(none)') from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e)));
    select x.e into v_j2 from jsonb_array_elements(v_j->'listings_sending_images'->'changed') x(e) where x.e->>'store' = 'asung' and x.e->>'sku' = 'ONO00140FAM';
    select count(*) into v_n from public.shop_photo_plan pl join public.product_family f on f.id = pl.family_id where f.sku = 'ONO00140FAM' and pl.rule = 'cover' and pl.status in ('planned', 'claimed', 'failed') and f.web_image_id is null;
    perform pg_temp.res('D5 dry run(실물 · ONO00140FAM · 저장 0): 표지를 아직 안 가져왔고 웹 대표가 비어 있으면 asung 의 그 listing 에서 새 표지가 1 번 · 기존 사진은 순서 그대로 한 칸씩 뒤 · files 뒤 = 앞 + 새 사진 · cover_set — 아니면 n/a',
      v_n = 0 or (v_j2 is not null and (v_j2->>'first_photo_changes')::boolean and (v_j2->>'cover_set')::boolean and (v_j2->>'existing_order_kept')::boolean
        and (v_j2->>'files_after')::int = (v_j2->>'files_before')::int + (v_j2->>'new_files')::int and (v_j2->>'new_files')::int = (v_j2->>'photos_to_import')::int
        and v_j2->'files'->0 @> '{"pos":1,"new":true,"photo_of":"ONO00140FAM"}' and v_j2->'files'->0->>'file' like 'shopify-%'
        and (select bool_and((x.e->>'was_pos')::int = (x.e->>'pos')::int - (v_j2->>'new_files')::int) from jsonb_array_elements(v_j2->'files') x(e) where not (x.e->>'new')::boolean)
        and v_j->'web_cover_new'->'families' ? 'ONO00140FAM'),
      case when v_n = 0 then 'n/a (cover already imported or web image already set)' else coalesce(left((v_j2 - 'files')::text, 300) || ' · order ' || (select string_agg(coalesce(x.e->>'was_pos', 'new') || '→' || (x.e->>'pos'), ' ' order by (x.e->>'pos')::int) from jsonb_array_elements(v_j2->'files') x(e)), '(ONO00140FAM not in changed)') end);
  exception when others then perform pg_temp.res('D dry run', false, 'ERR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- ── A · N · M · Z ──
  perform pg_temp.res('A 권한: shop_photo_ 창구 아홉 = definer · anon · authenticated 실행 0 · service_role 은 일곱(plan_load · apply_ 는 아무도) — 재발행 뒤에도 그대로',
    (select count(*) = 9 and bool_and(p.prosecdef and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                                     and has_function_privilege('service_role', p.oid, 'execute') = (p.proname not in ('shop_photo_plan_load', 'shop_photo_apply_')))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'),
    (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '-'), ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'));
  perform pg_temp.res('N nowhere 정적(REST 두 겹 ①): 창구 아홉에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select count(*) = 9 and sum(pg_temp.nowhere(p.prosrc)) = 0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'),
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'shop\_photo\_%'));
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) into r from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('shop_photo_done', 'shop_photo_claim', 'shop_photo_fail', 'shop_photo_pair_mark', 'shop_photo_verify_mark', 'shop_photo_run_add', 'shop_photo_plan_load', 'shop_product_payload', 'shop_queue_trigger', 'shop_queue_add', 'family_image_update', 'shop_listing_set', 'product_update');
  perform pg_temp.res('M 무접촉 함수 열셋: 몸(prosrc md5)이 머리와 같다 · 고친 둘(apply_ · dry)에는 1198 줄이 있다',
    r = current_setting('d.fn_head')
    and (select p.prosrc like '%set web_image_id = c.product_image_id%' and p.prosrc like '%f.web_image_id is null%' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_apply_')
    and (select p.prosrc like '%''web_cover_new'', v_cover%' and p.prosrc like '%''cover_set''%' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_dry'),
    'same ' || (r = current_setting('d.fn_head')) || ' · apply_ ' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_apply_')
      || ' · dry ' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_photo_dry'));
  select md5(coalesce(string_agg(pl.id::text || pl.status || coalesce(pl.verify_ok::text, '') || pl.attempts::text || coalesce(pl.product_image_id::text, ''), ',' order by pl.id), '')) || '/'
      || (select md5(coalesce(string_agg(pr.id::text || pr.status, ',' order by pr.id), '')) from public.shop_photo_pair pr where pr.store_id <> pg_temp.id('s1'))
    into r from public.shop_photo_plan pl where pl.family_id is null or pl.family_id not in (select t.id from t_ids t);
  perform pg_temp.res('Z 실물 무접촉: 가짜 밖의 사진 행 · shop_media · 열린 큐 · 저장소 파일 수 · 실제 패밀리의 웹 대표 · updated_at 지문이 머리와 같다 · 실제 계획 줄 · 짝의 지문이 처음과 같다 · postgres',
    pg_temp.fake_real() = current_setting('d.real_head') and r = v_real0 and current_user = 'postgres',
    'head ' || left(current_setting('d.real_head'), 60) || ' · now ' || left(pg_temp.fake_real(), 60) || ' · real plan same ' || coalesce((r = v_real0)::text, '(null)') || ' · user ' || current_user);
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
rollback;
\pset tuples_only off
\pset format aligned
-- 기대: 시험(-v mig) OK 15 · FAIL 0 · 확인(적용 뒤 · -v mig 없음) OK 15 · FAIL 0 — 갈래마다 다른 검사 없음(D2 의 수는 머리의 실물 수 + 가짜 하나 · M 은 머리와 같음)
--       마른 실행(적용 전 · -v mig 없음) OK 6 · FAIL 9(T1 · T3 · T4 · D1 ~ D5 · M — 1198 이 없는 2a 몸: 웹 대표가 안 서고 dry 에 web_cover_new · cover_set 이 없고 ONO00140FAM 새 표지가 맨 뒤) — 결함 재현
--       OK 줄 꼴 = 「OK <이름>」 · 끝 줄 「OK 15 · FAIL 0 · begin ~ 끝 …」 · 시험 begin ~ 끝 약 4 초(2026-11-11 23:5x 토론토 실측 4.1 s) · 표 잠금 없음(함수 재발행 둘 · 가짜 행) · 시퀀스 무접촉
--       2a 회귀(2a 검증 파일을 이 마이그레이션 위에서): OK 18 · FAIL 0(4.3 s)
--       변이(2026-11-11): 1198 의 「null 일 때만」 을 뺀 판 → FAIL 3(T2 · T4 · M) · dry 요약 셈에서 「웹 대표 비어 있음」 을 뺀 판 → FAIL 1(D2) · 표지 둘의 순서를 거꾸로 → FAIL 1(T3)
--       회차: 1 회차 FAIL 1(T6 — 검사 파일 결함: 도우미가 저장소 파일 행을 두 번 넣음 · 「없을 때만」 으로 고침) → 2 회차 OK 15
