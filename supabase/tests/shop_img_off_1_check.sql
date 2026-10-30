-- supabase/tests/shop_img_off_1_check.sql — shop-img-off-1 스토어마다 「사진 보내기」 스위치 · asung · aone 은 끈다 (2026-10-30 · 판정 890)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5 · 실제 test 스토어 listing 하나의 hash · 실제 스토어 열린 큐 수) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 IMG1-(가짜 스토어 둘 on · off · 가짜 상품 하나 · 사진 하나 · listing 둘)
--   → A(payload: 꺼진 스토어 files [] · image_id null · 켜진 스토어 그대로 · 실제 test 스토어 hash 보존) · B(hash: 사진 insert 로 안 바뀜 · 값 바꾸면 바뀜) · C(트리거: false → true 큐 · true → false 0 · 실제 스토어 끌 때 0) · D(재발행 diff · 시험 갈래만) · E(nowhere 정적) · F(속성 · md5 · 무접촉) → rollback → Z1 실제 행 무변 · Z2 md5 복귀 · Z3 칸 사라짐(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030192911_shop_img_off_1_send_images.sql -f supabase/tests/shop_img_off_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) EXPECT_OK 아래 · 확인(적용 뒤) 그보다 D 만큼 적다 · Z1 ~ Z3 는 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · 시퀀스(shop_push_queue.id)는 돌아오지 않는다(번호 구멍 · 무해)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback) · alter table shop_store add column … default true 는 PG 11+ 메타만(짧다) · lock_timeout 3s
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 26
\else
\set EXPECT_OK 23
\endif
\pset pager off
select (select count(*) from public.shop_store) as n_store0, (select count(*) from public.shop_listing) as n_list0, (select count(*) from public.product) as n_prod0, (select count(*) from public.product_image) as n_img0,
       (select count(*) from public.shop_push_queue) as n_q0, (select count(*) from public.shop_push_queue where done_at is null) as n_qopen0, (select count(*) from public.shop_product) as n_sp0,
       (select count(*) from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where s.code = 'asung' and q.done_at is null) as q_asung0,
       (select count(*) from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where s.code = 'aone' and q.done_at is null) as q_aone0,
       (select string_agg(code || ':' || live::text || ':' || send_tags::text || ':' || oos_policy || ':' || is_active::text, ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')) as stores0,
       (select id::text from public.shop_store where code = 'test') as test_sid,
       (select coalesce(family_id::text, 'null') from public.shop_listing l where l.store_id = (select id from public.shop_store where code = 'test') and l.is_on order by l.family_id nulls last, l.product_id limit 1) as test_fid,
       (select coalesce(product_id::text, 'null') from public.shop_listing l where l.store_id = (select id from public.shop_store where code = 'test') and l.is_on order by l.family_id nulls last, l.product_id limit 1) as test_pid,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') as pp_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload') as vp_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger') as tg_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save') as save_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add') as qa_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_all') as qall_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_trigger') as qt_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply') as la_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_push_batch') as pb_md5_0 \gset
select public.shop_product_payload(:'test_sid'::uuid, nullif(:'test_fid', 'null')::uuid, nullif(:'test_pid', 'null')::uuid)->>'hash' as h_test0 \gset
select id::text as tier from public.ref_price_tier where name = 'Regular CAD' \gset
\echo '── 기준: shop_store' :n_store0 '· listing' :n_list0 '· product_image' :n_img0 '· 열린 큐' :n_qopen0 '(asung' :q_asung0 '· aone' :q_aone0 ') · payload md5' :pp_md5_0 '· test listing hash' :h_test0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5, array_length(string_to_array(prosrc, E'\n'), 1) as n_lines from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_product_payload', 'shop_variant_payload', 'shop_store_queue_trigger');
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- payload 를 run() 으로(새 갈래가 없는 DB 에서도 MISMATCH 로 끝나게) · 결과는 jsonb 글
create function pg_temp.pay(p_store uuid, p_pid uuid) returns text language sql as $$ select pg_temp.run(format('select public.shop_product_payload(%L::uuid, null, %L::uuid)::text', p_store, p_pid)); $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end; $$;
create function pg_temp.openq(p_store uuid) returns text language sql as $$ select count(*)::text || '/' || coalesce(string_agg(distinct reason, '+'), '-') from public.shop_push_queue where store_id = p_store and done_at is null; $$;
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

-- ── 가짜 재료 IMG1- (rollback 됨) — 사진은 listing 전에(사진 insert 트리거가 켜진 listing 에만 줄을 세우므로 여기서는 줄 0) ──
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('img1on', 'img1-on.myshopify.com', 'IMG1 on', 'asung', :'tier'::uuid) returning id::text as s_on \gset
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('img1off', 'img1-off.myshopify.com', 'IMG1 off', 'asung', :'tier'::uuid) returning id::text as s_off \gset
update public.shop_store set send_images = false where id = :'s_off'::uuid;                           -- 꺼진 스토어(칸이 없는 DB 면 여기서 멈춘다 = 적용 전)
insert into public.product (sku, name, source, brand_name, is_active, sellable) values ('IMG1-P1', 'IMG1 fake single', 'manual', 'Annie', true, true) returning id::text as p1 \gset
insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values (:'p1'::uuid, :'p1' || '/a.jpg', 'image/jpeg', true, 1, 'manual') returning id::text as i1 \gset
insert into public.shop_listing (store_id, product_id) values (:'s_on'::uuid, :'p1'::uuid), (:'s_off'::uuid, :'p1'::uuid);
select pg_temp.pay(:'s_off'::uuid, :'p1'::uuid) as pay_off0 \gset
select pg_temp.pay(:'s_on'::uuid, :'p1'::uuid) as pay_on0 \gset

-- ── A) payload — 꺼진 스토어 사진 없음 · 켜진 스토어 있음 · 실제 test 스토어 hash 보존 ──
select pg_temp.chk('A1 off store: files [] · variants[0].image_id null · send_images false · blocks [no_price] (fake has no price · not in hash) · status ACTIVE',
  (select (p->'files')::text || '/' || coalesce(p->'variants'->0->>'image_id', 'null') || '/' || coalesce(p->>'send_images', 'missing') || '/' || (p->'blocks')::text || '/' || (p->>'status') from pg_temp.j(:'pay_off0') p), '[]/null/false/["no_price:IMG1-P1"]/ACTIVE');
select pg_temp.chk('A2 on store: files 1 (= the fake image) · variants[0].image_id = image · send_images true',
  (select jsonb_array_length(p->'files')::text || '/' || (p->'files'->0->>'product_image_id' = :'i1')::text || '/' || (p->'variants'->0->>'image_id' = :'i1')::text || '/' || (p->>'send_images') from pg_temp.j(:'pay_on0') p), '1/true/true/true');
select pg_temp.chk('A3 off ≠ on hash (files · image_id differ) · everything else equal (title · variants minus image_id · tags · status)',
  (select ((a->>'hash') <> (b->>'hash'))::text || '/' || ((a - 'files' - 'hash' - 'send_images' - 'variants' - 'store_code') = (b - 'files' - 'hash' - 'send_images' - 'variants' - 'store_code'))::text || '/' || ((a->'variants'->0) - 'image_id' = (b->'variants'->0) - 'image_id')::text
     from pg_temp.j(:'pay_off0') a, pg_temp.j(:'pay_on0') b), 'true/true/true');
select pg_temp.chk('A4 hash excludes send_images (hash of off payload = md5 of payload minus blocks · listing_on · hash · send_images)',
  (select ((p->>'hash') = md5((p - 'blocks' - 'listing_on' - 'hash' - 'send_images')::text))::text from pg_temp.j(:'pay_off0') p), 'true');
select pg_temp.chk('A5 real test store (send_images true): first on-listing hash unchanged by the re-issue (begin 앞 = 지금)',
  (public.shop_product_payload(:'test_sid'::uuid, nullif(:'test_fid', 'null')::uuid, nullif(:'test_pid', 'null')::uuid)->>'hash' = :'h_test0')::text, 'true');

-- ── B) hash — 사진만 바뀌면 꺼진 스토어 hash 그대로(push 거리 없음) · 켜진 스토어는 바뀜 · 값이 바뀌면 둘 다 바뀜 ──
insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values (:'p1'::uuid, :'p1' || '/b.jpg', 'image/jpeg', false, 2, 'manual');
select pg_temp.pay(:'s_off'::uuid, :'p1'::uuid) as pay_off1 \gset
select pg_temp.pay(:'s_on'::uuid, :'p1'::uuid) as pay_on1 \gset
select pg_temp.chk('B1 off store: image insert → hash same · files still []', (select ((a->>'hash') = (b->>'hash'))::text || '/' || (b->'files')::text from pg_temp.j(:'pay_off0') a, pg_temp.j(:'pay_off1') b), 'true/[]');
select pg_temp.chk('B2 on store: image insert → hash changed · files 2', (select ((a->>'hash') <> (b->>'hash'))::text || '/' || jsonb_array_length(b->'files')::text from pg_temp.j(:'pay_on0') a, pg_temp.j(:'pay_on1') b), 'true/2');
select pg_temp.chk('B3 the image insert queued one line per store (reason product_image) — off store line will end skipped_same_hash in drain (hash unchanged · Shopify call 0)',
  pg_temp.openq(:'s_off'::uuid) || ' | ' || pg_temp.openq(:'s_on'::uuid), '1/product_image | 1/product_image');
update public.product_image set is_primary = true, sort_order = 0 where storage_path = :'p1' || '/b.jpg';   -- 순서 · 표지 바뀜
select pg_temp.pay(:'s_off'::uuid, :'p1'::uuid) as pay_off2 \gset
select pg_temp.chk('B4 off store: primary/order change → hash still same', (select ((a->>'hash') = (b->>'hash'))::text from pg_temp.j(:'pay_off0') a, pg_temp.j(:'pay_off2') b), 'true');
update public.product set name = 'IMG1 fake single renamed' where id = :'p1'::uuid;
select pg_temp.pay(:'s_off'::uuid, :'p1'::uuid) as pay_off3 \gset
select pg_temp.chk('B5 off store: name change → hash changed (values still travel)', (select ((a->>'hash') <> (b->>'hash'))::text || '/' || (b->>'title') from pg_temp.j(:'pay_off0') a, pg_temp.j(:'pay_off3') b), 'true/IMG1 fake single renamed');

-- ── C) 스토어 트리거 — false → true 큐 · true → false 0 · 다른 칸 0 · 실제 스토어 끌 때 0 ──
delete from public.shop_push_queue where store_id in (:'s_off'::uuid, :'s_on'::uuid);                 -- 가짜 줄 비우기(rollback 됨)
update public.shop_store set send_images = true where id = :'s_off'::uuid;                            -- 켜기
select pg_temp.chk('C1 off → on: queued the on-listings of that store (1 · reason store) · the other store 0', pg_temp.openq(:'s_off'::uuid) || ' | ' || pg_temp.openq(:'s_on'::uuid), '1/store | 0/-');
update public.shop_store set send_images = true where id = :'s_off'::uuid;                            -- 같은 값
select pg_temp.chk('C2 on → on (no change): nothing new (not exists keeps 1)', pg_temp.openq(:'s_off'::uuid), '1/store');
delete from public.shop_push_queue where store_id in (:'s_off'::uuid, :'s_on'::uuid);
update public.shop_store set send_images = false where id in (:'s_off'::uuid, :'s_on'::uuid);        -- 둘 다 끄기(문장 하나 · 두 행)
select pg_temp.chk('C3 on → off (two stores in one statement): queue 0', pg_temp.openq(:'s_off'::uuid) || ' | ' || pg_temp.openq(:'s_on'::uuid), '0/- | 0/-');
update public.shop_store set label = 'IMG1 off renamed', note = 'x' where id = :'s_off'::uuid;
select pg_temp.chk('C4 other columns (label · note): queue 0', pg_temp.openq(:'s_off'::uuid), '0/-');
update public.shop_store set send_images = true, send_tags = true where id in (:'s_off'::uuid, :'s_on'::uuid);   -- 두 스토어 함께 켜기 + send_tags 도
select pg_temp.chk('C5 off → on for both stores in one statement (+ send_tags): 1 line each · reason store', pg_temp.openq(:'s_off'::uuid) || ' | ' || pg_temp.openq(:'s_on'::uuid), '1/store | 1/store');
select pg_temp.chk('C6 real stores after the migration: asung · aone send_images false · test true · open queue asung/aone as before the begin · other store columns unchanged',
  (select string_agg(code || ':' || send_images::text, ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')) || ' / ' ||
  (select count(*) from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where s.code = 'asung' and q.done_at is null)::text || '/' ||
  (select count(*) from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where s.code = 'aone' and q.done_at is null)::text || ' / ' ||
  ((select string_agg(code || ':' || live::text || ':' || send_tags::text || ':' || oos_policy || ':' || is_active::text, ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')) = :'stores0')::text,
  'aone:false,asung:false,test:true / ' || :'q_asung0' || '/' || :'q_aone0' || ' / true');

-- ── D) 재발행 diff — 옛(begin 앞 prosrc) = 새 대조 · 시험 갈래만 · 줄 글자(다중집합)로 비교 ──
\if :{?mig}
create temp table t_diff as
  with o as (select t.proname, l, count(*) as c from t_pre t, regexp_split_to_table(t.prosrc, E'\n') as l group by 1, 2),
       w as (select p.proname, l, count(*) as c from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') as l where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_product_payload', 'shop_variant_payload', 'shop_store_queue_trigger') group by 1, 2)
  select o.proname, 'removed' as side, o.l, o.c - coalesce(w.c, 0) as c from o left join w on w.proname = o.proname and w.l = o.l where o.c > coalesce(w.c, 0)
  union all
  select w.proname, 'added', w.l, w.c - coalesce(o.c, 0) from w left join o on o.proname = w.proname and o.l = w.l where w.c > coalesce(o.c, 0);
select pg_temp.chk('D0 begin 앞 prosrc = 마지막 정의(shop_pol_oos_policy: payload 7dc83d55/83 · variant 7a843c86/20 · trigger 70a44010/15)',
  (select string_agg(proname || '=' || left(md5, 8) || '/' || n_lines, ' ' order by proname) from t_pre), 'shop_product_payload=7dc83d55/83 shop_store_queue_trigger=70a44010/15 shop_variant_payload=7a843c86/20');
select pg_temp.chk('D1 line counts: payload 83 → 87 (removed 1 · added 5) · variant 20 → 20 (1 · 1) · trigger 15 → 16 (1 · 2)',
  (select string_agg(p.proname || '=' || array_length(string_to_array(p.prosrc, E'\n'), 1)::text || '/' || coalesce((select sum(c) from t_diff d where d.proname = p.proname and d.side = 'removed'), 0)::text || '/' || coalesce((select sum(c) from t_diff d where d.proname = p.proname and d.side = 'added'), 0)::text, ' ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_product_payload', 'shop_variant_payload', 'shop_store_queue_trigger')),
  'shop_product_payload=87/1/5 shop_store_queue_trigger=16/1/2 shop_variant_payload=20/1/1');
select pg_temp.chk('D2 payload added lines = if v_s.send_images then ×2 (two comments → two lines) · end if ×2 · return with send_images · removed = old return · nothing else',
  (select string_agg(side || '=' || left(regexp_replace(btrim(l), '\s+--.*$', ''), 50) || '×' || c, ' || ' order by side desc, btrim(l) collate "C") from t_diff where proname = 'shop_product_payload'),
  'removed=return v_out || jsonb_build_object(''hash'', md5((v_×1 || added=end if;×2 || added=if v_s.send_images then×1 || added=if v_s.send_images then×1 || added=return v_out || jsonb_build_object(''send_images'', ×1');
\echo '── D 참고: 재발행 diff 전부(줄 글자 · 주석 뺀 앞 120 자)'
select proname, side, c, left(regexp_replace(btrim(l), '\s+--.*$', ''), 120) as line from t_diff order by proname, side desc, btrim(l) collate "C";
\endif

-- ── E) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE(재발행 셋에는 update · delete 가 없다 → 0) ──
select pg_temp.chk('E0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('E1 last definitions: WHERE-less update · delete = 0 for shop_product_payload · shop_variant_payload · shop_store_queue_trigger',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' / ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_product_payload', 'shop_variant_payload', 'shop_store_queue_trigger')),
  'shop_product_payload 0 / shop_store_queue_trigger 0 / shop_variant_payload 0');

-- ── F) 속성 · md5 · 무접촉 ──
select pg_temp.chk('F1 shop_store.send_images: boolean · not null · default true · comment has 판정 890',
  coalesce((select data_type || '/' || is_nullable || '/' || coalesce(column_default, 'none') from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'send_images'), 'column missing') || '/' ||
  (coalesce(col_description('public.shop_store'::regclass, (select attnum from pg_attribute where attrelid = 'public.shop_store'::regclass and attname = 'send_images')), '') like '%판정 890%')::text, 'boolean/NO/true/true');
select pg_temp.chk('F2 shop_store_queue_trigger: definer · authenticated no · anon no · one · comment 890 · trigger shop_store_shop_queue_u still AFTER UPDATE STATEMENT with transition tables',
  coalesce((select prosecdef::text || '/' || has_function_privilege('authenticated', oid, 'execute')::text || '/' || has_function_privilege('anon', oid, 'execute')::text || '/' || (coalesce(obj_description(oid, 'pg_proc'), '') like '%판정 890%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger'), 'fn missing') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger')::text || ' / ' ||
  coalesce((select (tgtype & 1 = 0)::text || '/' || (tgtype & 16 = 16)::text || '/' || (tgoldtable is not null and tgnewtable is not null)::text from pg_trigger where tgrelid = 'public.shop_store'::regclass and tgname = 'shop_store_shop_queue_u'), 'trigger missing'),
  'true/false/false/true/1 / true/true/true');
select pg_temp.chk('F3 shop_product_payload: stable · plpgsql · search_path · one · comment 890 / shop_variant_payload: stable · sql · one · comment 890',
  (select provolatile::text || '/' || (select lanname from pg_language where oid = prolang) || '/' || array_to_string(proconfig, ';') || '/' || (coalesce(obj_description(oid, 'pg_proc'), '') like '%판정 890%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload')::text || ' / ' ||
  (select provolatile::text || '/' || (select lanname from pg_language where oid = prolang) || '/' || (coalesce(obj_description(oid, 'pg_proc'), '') like '%판정 890%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload')::text,
  's/plpgsql/search_path=public, pg_temp/true/1 / s/sql/true/1');
select pg_temp.chk('F4 untouched (md5 begin 앞 = 지금): shop_store_save · shop_queue_add · shop_queue_all · shop_queue_trigger · shop_link_apply · shop_link_push_batch',
  (select md5(prosrc) = :'save_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save')::text || '/' || (select md5(prosrc) = :'qa_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add')::text || '/' ||
  (select md5(prosrc) = :'qall_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_all')::text || '/' || (select md5(prosrc) = :'qt_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_trigger')::text || '/' ||
  (select md5(prosrc) = :'la_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply')::text || '/' || (select md5(prosrc) = :'pb_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_push_batch')::text,
  'true/true/true/true/true/true');
select pg_temp.chk('F5 real rows inside the trial: shop_product count same · shop_media untouched by payload (count same as begin) · product_image = begin + 2 fake',
  (select count(*) from public.shop_product)::text || '/' || (select count(*) from public.product_image)::text, :'n_sp0' || '/' || (:n_img0 + 2)::text);

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.shop_store) = :n_store0 and (select count(*) from public.shop_listing) = :n_list0 and (select count(*) from public.product) = :n_prod0 and (select count(*) from public.product_image) = :n_img0
            and (select count(*) from public.shop_push_queue) = :n_q0 and (select count(*) from public.shop_push_queue where done_at is null) = :n_qopen0 and (select count(*) from public.shop_product) = :n_sp0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') = :'pp_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload') = :'vp_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger') = :'tg_md5_0'
       then 'Z2 OK three functions back to before (md5)' else 'Z2 MISMATCH functions not restored' end as z2;
select case when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'send_images') then 'Z3 OK send_images column gone' else 'Z3 MISMATCH column stayed' end as z3;
\endif
