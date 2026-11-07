-- supabase/tests/shop_new_1_check.sql — shop-new-1 상품 단위 사진 · 태그 보내기: IMS 가 만든 상품 자동 · 관리자 덧씌우기 (2026-11-06 · 판정 1042 · 1043)
-- [운영 메인 · Asung-IMS] 시험 적용 장치 틀 — ⚠️ 운영 왕복 0.33 s 라 txn 안은 문장을 아낀다: 기준 · 스냅샷 · 도우미 · t_pre · t_ctx 는 **begin 앞**(잠금 없음) · txn 안 = begin → \i → DO 블록 하나(A ~ K 전부) → 결과 → rollback(약 19 왕복)
--   준비(begin 앞): 실제 행 수 · 함수 md5 · ABE10612 asung · aone hash · before hash 스냅샷 t_before(-v full=1 이면 전수 9,502 행 17 s · 아니면 스토어마다 300 행) · t_pre(옛 prosrc) · t_ctx(psql 변수 → DO 블록이 읽는다)
--   DO 안: 가짜 재료 NEW1-(직원 둘 admin · manager · 상품 둘 P1 사진 1 태그 1 · P2 사진 0 태그 0 · asung listing 둘 · shop_product 행 없음)
--   → A(칸 셋 · 기존 행 link · null · null) · B(기존 link 상품 ABE10612: send_images f · send_tags f · files 0 · image_id null · hash 무변) · ⭐ C(전수 또는 표본: hash 무변 · last_hash 와 다른 행 수 무변)
--   → D(창구 admin · asung ABE10612 사진만 + 큐: files 1 · image_id · send_tags f · hash 바뀜 · 큐 1 · aone 무접촉) · E(태그만: aone ABE10612 tags 5 · asung 태그 0 상품은 실효 f · hash 무변)
--   → F(행 없음 = 신제품: P1 둘 다 t · files 1 · tags 1 / P2 files 0 · send_tags f) · G(origin ims 행 · 두 번째: 둘 다 t · 태그 지우면 f · check) · H(끄기 null → hash 원래 값) · I(false = 스토어가 켜도 안 보냄 · test 스토어)
--   → J(문: manager 거부 · 행 없음 거부 · 모르는 스토어 · 대상 둘 · 없음 · anon) · K(재발행 diff: variant payload md5 무변 · product payload 뺀 줄 1(return) · 더한 줄 9 · 무접촉 넷 md5 · 실제 행) → rollback → Z1 실제 행 무변 · Z2 md5 복귀 · Z3 칸 · 창구 사라짐(시험 갈래만)
--   Claude Code(시험 · 전수 한 회차만 · 잠금 약 25 초 예외 허락 2026-11-06 — 17 s 전수 + 왕복): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261106232039_shop_new_1_send_override.sql -v full=1 -f supabase/tests/shop_new_1_check.sql
--   Claude Code(시험 · 표본 · 10 초 안): 같은 명령에서 -v full=1 만 뺀다
--   Caleb(확인 · 적용 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v full=1 -f supabase/tests/shop_new_1_check.sql   (-v mig 없음 · 전수 · 적용 뒤라 잠금 없음)
--   기대 OK: 시험(-v mig) EXPECT_OK 아래 · 확인(적용 뒤) 그보다 K1 ~ K5 만큼 적다 · Z 는 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · 시퀀스(shop_push_queue.id)는 돌아오지 않는다(번호 구멍 · 무해)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 45
\else
\set EXPECT_OK 40
\endif
\pset pager off
select (select count(*) from public.shop_store) as n_store0, (select count(*) from public.shop_listing) as n_list0, (select count(*) from public.product) as n_prod0, (select count(*) from public.product_image) as n_img0,
       (select count(*) from public.product_tag) as n_tag0, (select count(*) from public.ims_staff) as n_staff0,
       (select count(*) from public.shop_push_queue) as n_q0, (select count(*) from public.shop_push_queue where done_at is null) as n_qopen0, (select count(*) from public.shop_product) as n_sp0,
       (select count(*) from public.shop_product sp join public.shop_store s on s.id = sp.store_id where s.code in ('asung', 'aone')) as n_real0,
       (select string_agg(code || ':' || send_images::text || ':' || send_tags::text, ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')) as stores0,
       (select id::text from public.shop_store where code = 'asung') as s_asung,
       (select id::text from public.shop_store where code = 'aone') as s_aone,
       (select id::text from public.shop_store where code = 'test') as s_test,
       (select id::text from public.product where sku = 'ABE10612') as p_abe,
       (select p.id::text from public.shop_product sp join public.shop_store s on s.id = sp.store_id join public.product p on p.id = sp.product_id
         where s.code = 'asung' and not exists (select 1 from public.product_tag t where t.product_id = p.id) order by p.sku limit 1) as p_notag,
       (select p.id::text from public.shop_product sp join public.shop_store s on s.id = sp.store_id join public.product p on p.id = sp.product_id join public.shop_listing l on l.store_id = sp.store_id and l.product_id = sp.product_id and l.is_on
         where s.code = 'test' and exists (select 1 from public.product_image i where i.product_id = p.id and i.is_active) order by p.sku limit 1) as p_test,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') as pp_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload') as vp_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger') as tg_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add') as qa_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_all') as qall_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply') as la_md5_0,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_send_override') as n_win0 \gset
select public.shop_product_payload(:'s_asung'::uuid, null, :'p_abe'::uuid)->>'hash' as h_abe_asung0, public.shop_product_payload(:'s_aone'::uuid, null, :'p_abe'::uuid)->>'hash' as h_abe_aone0,
       public.shop_product_payload(:'s_test'::uuid, null, :'p_test'::uuid)->>'hash' as h_test0,
       (select count(*) from public.product_tag where product_id = :'p_abe'::uuid)::text as abe_tags, (select count(*) from public.product_image where product_id = :'p_abe'::uuid and is_active)::text as abe_imgs \gset
-- ⭐ before 스냅샷(잠금 없음 · 표 밖): 전수(-v full=1) 또는 스토어마다 300 행 표본 — begin 전 temp 표라 txn 안에서 읽고 rollback 뒤에도 남는다
\if :{?full}
\echo '── before 스냅샷: 전수(asung · aone · test) …'
create temp table t_before as
  select sp.id, s.code, sp.last_hash, public.shop_product_payload(sp.store_id, sp.family_id, sp.product_id)->>'hash' as h
    from public.shop_product sp join public.shop_store s on s.id = sp.store_id;
\else
\echo '── before 스냅샷: 표본 300/스토어 …'
create temp table t_before as
  select x.id, x.code, x.last_hash, public.shop_product_payload(x.store_id, x.family_id, x.product_id)->>'hash' as h
    from (select sp.*, s.code, row_number() over (partition by sp.store_id order by sp.id) as rn from public.shop_product sp join public.shop_store s on s.id = sp.store_id) x where x.rn <= 300;
\endif
select count(*) as n_before, count(*) filter (where h = last_hash) as n_before_same, count(*) filter (where h is distinct from last_hash) as n_before_diff from t_before \gset
\echo '── 스냅샷에서 이미 last_hash 와 다른 행(옛 함수로도 다름 · nightly 가 보낼 것 · 이 차수와 무관):'
select b.code, coalesce(p.sku, 'family:' || sp.family_id::text) as target, sp.last_pushed_at, sp.updated_at from t_before b join public.shop_product sp on sp.id = b.id left join public.product p on p.id = sp.product_id where b.h is distinct from b.last_hash order by 1, 2;
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_product_payload', 'shop_variant_payload');
create temp table t_ctx as select * from (values
  ('s_asung', :'s_asung'), ('s_aone', :'s_aone'), ('s_test', :'s_test'), ('p_abe', :'p_abe'), ('p_notag', :'p_notag'), ('p_test', :'p_test'),
  ('h_abe_asung0', :'h_abe_asung0'), ('h_abe_aone0', :'h_abe_aone0'), ('h_test0', :'h_test0'), ('abe_tags', :'abe_tags'),
  ('n_sp0', :'n_sp0'::text), ('n_prod0', :'n_prod0'::text), ('n_qopen0', :'n_qopen0'::text), ('n_real0', :'n_real0'::text), ('n_before', :'n_before'::text), ('n_before_diff', :'n_before_diff'::text),
  ('pp_md5_0', :'pp_md5_0'), ('vp_md5_0', :'vp_md5_0'), ('tg_md5_0', :'tg_md5_0'), ('qa_md5_0', :'qa_md5_0'), ('qall_md5_0', :'qall_md5_0'), ('la_md5_0', :'la_md5_0'),
  ('full', case when :{?full} then '1' else '0' end), ('mig', case when :{?mig} then '1' else '0' end)) as v(k, v);
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
-- ── 도우미(begin 앞 · temp 라 세션에 남는다 · 창구는 \i 뒤에 생기므로 동적 SQL) ──
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.ctx(p_k text) returns text language sql stable as $$ select v from t_ctx where k = p_k; $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.pay(p_store uuid, p_pid uuid) returns text language sql as $$ select pg_temp.run(format('select public.shop_product_payload(%L::uuid, null, %L::uuid)::text', p_store, p_pid)); $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end; $$;
-- payload 요약: send_images/send_tags/files 수/tags 수/변형 image_id 있음/origin
create function pg_temp.sum(p_store uuid, p_pid uuid) returns text language sql as $$
  select coalesce((select (j->>'send_images') || '/' || (j->>'send_tags') || '/' || jsonb_array_length(j->'files') || '/' || jsonb_array_length(j->'tags') || '/' || ((j->'variants'->0->>'image_id') is not null)::text || '/' || coalesce(j->>'origin', 'null')
                   from pg_temp.j(pg_temp.pay(p_store, p_pid)) j), pg_temp.pay(p_store, p_pid));
$$;
create function pg_temp.ovr(p_store text, p_pid uuid, p_img boolean, p_tag boolean, p_q boolean) returns text language sql as $$
  select pg_temp.run(format('select public.shop_product_send_override(%L, null, %L::uuid, %s, %s, %s)::text', p_store, p_pid, coalesce(p_img::text, 'null'), coalesce(p_tag::text, 'null'), p_q::text));
$$;
create function pg_temp.openq(p_store uuid, p_pid uuid) returns text language sql as $$ select count(*)::text || '/' || coalesce(string_agg(distinct reason, '+'), '-') from public.shop_push_queue where store_id = p_store and product_id = p_pid and done_at is null; $$;
-- 역할 바꾸기(DO 안에서): 가짜 직원의 auth uid 로 authenticated 가 된다 · 되돌리기
create function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_me() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
\echo '── 기준: shop_product' :n_sp0 '(asung+aone' :n_real0 ') · 스토어' :stores0 '· payload md5' :pp_md5_0 '· ABE10612 asung' :h_abe_asung0 '· aone' :h_abe_aone0 '(태그' :abe_tags '· 사진' :abe_imgs ') · 스냅샷' :n_before '행(last_hash 와 같음' :n_before_same '· 다름' :n_before_diff ')'
begin;
select set_config('lock_timeout', '2s', true) as lt, clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ═══ A ~ K 전부 한 블록(왕복 1) ═══
do $suite$
declare
  s_asung uuid := pg_temp.ctx('s_asung')::uuid;  s_aone uuid := pg_temp.ctx('s_aone')::uuid;  s_test uuid := pg_temp.ctx('s_test')::uuid;
  p_abe uuid := pg_temp.ctx('p_abe')::uuid;  p_notag uuid := pg_temp.ctx('p_notag')::uuid;  p_test uuid := pg_temp.ctx('p_test')::uuid;
  h_abe_asung0 text := pg_temp.ctx('h_abe_asung0');  h_abe_aone0 text := pg_temp.ctx('h_abe_aone0');  h_test0 text := pg_temp.ctx('h_test0');  abe_tags text := pg_temp.ctx('abe_tags');
  n_sp0 int := pg_temp.ctx('n_sp0')::int;  n_prod0 int := pg_temp.ctx('n_prod0')::int;  n_qopen0 int := pg_temp.ctx('n_qopen0')::int;  n_real0 int := pg_temp.ctx('n_real0')::int;
  n_before text := pg_temp.ctx('n_before');  n_before_diff text := pg_temp.ctx('n_before_diff');  is_full boolean := pg_temp.ctx('full') = '1';  is_mig boolean := pg_temp.ctx('mig') = '1';
  u_adm uuid := gen_random_uuid();  u_mgr uuid := gen_random_uuid();
  p1 uuid;  p2 uuid;  r text;  r2 text;  t0 timestamptz;
begin
  -- ── 가짜 재료 NEW1- ──
  insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
    (u_adm, 'shopnew1-admin@test.invalid', 'shopnew1 admin', 'admin', '[]', true),
    (u_mgr, 'shopnew1-mgr@test.invalid',   'shopnew1 manager', 'manager', '["shopify"]', true);
  insert into public.product (sku, name, source, brand_name, is_active, sellable) values ('NEW1-P1', 'NEW1 fake new single with photo and tag', 'manual', 'Annie', true, true) returning id into p1;
  insert into public.product (sku, name, source, brand_name, is_active, sellable) values ('NEW1-P2', 'NEW1 fake new single bare', 'manual', 'Annie', true, true) returning id into p2;
  insert into public.product_image (product_id, storage_path, content_type, is_primary, sort_order, source) values (p1, p1::text || '/a.jpg', 'image/jpeg', true, 1, 'manual');
  insert into public.product_tag (product_id, tag, source) values (p1, 'NEW1TAG', 'manual');
  insert into public.shop_listing (store_id, product_id, is_on) values (s_asung, p1, true), (s_asung, p2, true);

  -- ── A 칸 셋 ──
  perform pg_temp.chk('A1 shop_product.send_images · send_tags boolean null · origin text not null default link · check',
    (select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, '-'), ',' order by column_name) from information_schema.columns where table_schema = 'public' and table_name = 'shop_product' and column_name in ('send_images', 'send_tags', 'origin'))
    || ' ' || (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.shop_product'::regclass and conname = 'shop_product_origin_ck'),
    'origin:text:NO:''link''::text,send_images:boolean:YES:-,send_tags:boolean:YES:- CHECK ((origin = ANY (ARRAY[''link''::text, ''ims''::text])))');
  perform pg_temp.chk('A2 every existing row: origin link · send_images null · send_tags null', (select count(*)::text from public.shop_product where origin = 'link' and send_images is null and send_tags is null), n_sp0::text);

  -- ── B 기존 link 상품(ABE10612) — 덧씌움 없음 ──
  perform pg_temp.chk('B1 asung ABE10612 payload: send_images f · send_tags f · files 0 · tags ' || abe_tags || ' · image_id null · origin link', pg_temp.sum(s_asung, p_abe), 'false/false/0/' || abe_tags || '/false/link');
  perform pg_temp.chk('B2 asung ABE10612 hash unchanged', (select j->>'hash' from pg_temp.j(pg_temp.pay(s_asung, p_abe)) j), h_abe_asung0);
  perform pg_temp.chk('B3 aone ABE10612 hash unchanged · send_images f', (select (j->>'hash') || ' ' || (j->>'send_images') from pg_temp.j(pg_temp.pay(s_aone, p_abe)) j), h_abe_aone0 || ' false');
  perform pg_temp.chk('B4 test store (send_images t · send_tags t) row: hash unchanged · send_images t', (select (j->>'hash') || ' ' || (j->>'send_images') from pg_temp.j(pg_temp.pay(s_test, p_test)) j), h_test0 || ' true');

  -- ── ⭐ C 전수(또는 표본) hash 무변 — before 스냅샷과 같고 last_hash 와 다른 행 수도 그대로 ──
  t0 := clock_timestamp();
  create temp table t_after as select b.id, b.code, b.last_hash, b.h as h0, public.shop_product_payload(sp.store_id, sp.family_id, sp.product_id)->>'hash' as h1 from t_before b join public.shop_product sp on sp.id = b.id;
  perform pg_temp.chk('C1 hash unchanged for every snapshot row (mismatch vs before / rows)' || case when is_full then ' · FULL' else ' · sample' end, (select count(*) filter (where h1 is distinct from h0)::text || '/' || count(*)::text from t_after), '0/' || n_before);
  perform pg_temp.chk('C2 rows whose new hash ≠ last_hash = rows that already differed before (nightly resend adds 0)', (select count(*) filter (where h1 is distinct from last_hash)::text || '/' || count(*)::text from t_after), n_before_diff || '/' || n_before);
  perform pg_temp.chk('C3 snapshot covers asung + aone rows' || case when is_full then ' (full)' else ' (sample 300 each)' end, (select count(*)::text from t_after where code in ('asung', 'aone')), case when is_full then n_real0::text else '600' end);
  raise notice 'C compare: % rows in % · per store %', (select count(*) from t_after), clock_timestamp() - t0, (select string_agg(code || '=' || n || '(changed ' || c || ')', ' ' order by code) from (select code, count(*) n, count(*) filter (where h1 is distinct from h0) c from t_after group by code) x);

  -- ── D 창구(admin) — asung ABE10612 사진만 켜고 큐 ──
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('asung', p_abe, true, null, true);
  perform pg_temp.as_me();
  perform pg_temp.chk('D1 override images only + queue: effective images t · tags f · files 1 · hash_changed · queued 1 · origin link',
    (select (j->'after'->>'effective_images') || '/' || (j->'after'->>'effective_tags') || '/' || (j->>'files') || '/' || (j->>'hash_changed') || '/' || (j->>'queued') || '/' || (j->>'origin') from pg_temp.j(r) j), 'true/false/1/true/1/link');
  perform pg_temp.chk('D2 asung ABE10612 payload now: send_images t · send_tags f · files 1 · image_id set', pg_temp.sum(s_asung, p_abe), 'true/false/1/' || abe_tags || '/true/link');
  perform pg_temp.chk('D3 asung ABE10612 hash changed (variant image_id in hash)', (select ((j->>'hash') <> h_abe_asung0)::text from pg_temp.j(pg_temp.pay(s_asung, p_abe)) j), 'true');
  perform pg_temp.chk('D4 queue: one open line reason override for (asung, ABE10612)', pg_temp.openq(s_asung, p_abe), '1/override');
  perform pg_temp.chk('D5 row columns: send_images true · send_tags null · updated_by = admin', (select send_images::text || '/' || coalesce(send_tags::text, 'null') || '/' || (updated_by = (select id from public.ims_staff where auth_user_id = u_adm))::text from public.shop_product where store_id = s_asung and product_id = p_abe), 'true/null/true');
  perform pg_temp.chk('D6 aone ABE10612 untouched: hash same · send_images f · no queue line', (select (j->>'hash' = h_abe_aone0)::text || ' ' || (j->>'send_images') from pg_temp.j(pg_temp.pay(s_aone, p_abe)) j) || ' ' || pg_temp.openq(s_aone, p_abe), 'true false 0/-');
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('asung', p_abe, true, null, true);
  perform pg_temp.as_me();
  perform pg_temp.chk('D7 same override again + queue: hash_changed false · queued 0 (line already open)', (select (j->>'hash_changed') || '/' || (j->>'queued') from pg_temp.j(r) j), 'false/0');

  -- ── E 태그만 ──
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('aone', p_abe, null, true, false);
  r2 := pg_temp.ovr('asung', p_notag, null, true, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('E1 aone ABE10612 tags only: effective images f · tags t · files 0 · tags ' || abe_tags || ' · hash_changed · queued 0',
    (select (j->'after'->>'effective_images') || '/' || (j->'after'->>'effective_tags') || '/' || (j->>'files') || '/' || (j->>'tags') || '/' || (j->>'hash_changed') || '/' || (j->>'queued') from pg_temp.j(r) j), 'false/true/0/' || abe_tags || '/true/0');
  perform pg_temp.chk('E2 aone ABE10612 payload: send_tags t · tags ' || abe_tags, (select (j->>'send_tags') || '/' || jsonb_array_length(j->'tags') from pg_temp.j(pg_temp.pay(s_aone, p_abe)) j), 'true/' || abe_tags);
  perform pg_temp.chk('E3 asung product with 0 IMS tags, tags override on: effective tags f · tags 0 · hash unchanged (1043)',
    (select (j->'after'->>'send_tags') || '/' || (j->'after'->>'effective_tags') || '/' || (j->>'tags') || '/' || (j->>'hash_changed') from pg_temp.j(r2) j), 'true/false/0/false');
  perform pg_temp.chk('E4 that row hash still = last_hash', (select (sp.last_hash = (public.shop_product_payload(sp.store_id, null, sp.product_id)->>'hash'))::text from public.shop_product sp where sp.store_id = s_asung and sp.product_id = p_notag), 'true');

  -- ── F 행 없음 = IMS 가 지금 만드는 상품 ──
  perform pg_temp.chk('F1 NEW1-P1 (no shop_product row · photo 1 · tag 1): send_images t · send_tags t · files 1 · tags 1 · image_id set · origin null', pg_temp.sum(s_asung, p1), 'true/true/1/1/true/null');
  perform pg_temp.chk('F2 NEW1-P2 (no row · photo 0 · tag 0): send_images t · files 0 · send_tags f (tags 0 → 1043) · image_id null', pg_temp.sum(s_asung, p2), 'true/false/0/0/false/null');
  perform pg_temp.chk('F3 NEW1-P1 blocks carry no listing_missing (listing on) · hash present', (select ((j->'blocks') ? 'listing_missing')::text || '/' || (length(j->>'hash') = 32)::text from pg_temp.j(pg_temp.pay(s_asung, p1)) j), 'false/true');
  perform pg_temp.chk('F4 NEW1-P1 on aone (no listing · no row): still send_images t · send_tags t (flags do not depend on listing)', (select (j->>'send_images') || '/' || (j->>'send_tags') || '/' || ((j->'blocks') ? 'listing_missing')::text from pg_temp.j(pg_temp.pay(s_aone, p1)) j), 'true/true/true');

  -- ── G origin ims 행(EF 가 만든 뒤) — 두 번째 보내기 ──
  insert into public.shop_product (store_id, product_id, shopify_product_gid, handle, shopify_status, last_status, origin, send_images, send_tags) values (s_asung, p1, 'gid://shopify/Product/990000000001', 'new1-p1', 'ACTIVE', 'ok', 'ims', true, true);
  perform pg_temp.chk('G1 NEW1-P1 with origin ims row (true · true): send_images t · send_tags t · files 1 · tags 1 · origin ims', pg_temp.sum(s_asung, p1), 'true/true/1/1/true/ims');
  delete from public.product_tag where product_id = p1;
  perform pg_temp.chk('G2 same row after its only IMS tag is removed: send_tags f (1043) · send_images still t', pg_temp.sum(s_asung, p1), 'true/false/1/0/true/ims');
  perform pg_temp.chk('G3 origin check rejects other values', pg_temp.run(format('update public.shop_product set origin = %L where product_id = %L::uuid returning origin', 'shopify', p1)), 'ERR 23514: new row for relation "shop_product" violates check constraint "shop_product_origin_ck"');

  -- ── H 끄기(null) → 원래대로 ──
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('asung', p_abe, null, null, false);
  r2 := pg_temp.ovr('aone', p_abe, null, null, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('H1 asung ABE10612 off: effective images f · hash back to original', (select (j->'after'->>'effective_images') || '/' || ((j->'after'->>'hash') = h_abe_asung0)::text from pg_temp.j(r) j), 'false/true');
  perform pg_temp.chk('H2 aone ABE10612 off: effective tags f · hash back to original', (select (j->'after'->>'effective_tags') || '/' || ((j->'after'->>'hash') = h_abe_aone0)::text from pg_temp.j(r2) j), 'false/true');
  perform pg_temp.chk('H3 both rows: columns null · null', (select count(*)::text from public.shop_product where product_id = p_abe and send_images is null and send_tags is null and store_id in (s_asung, s_aone)), '2');

  -- ── I false = 스토어가 켜도 안 보냄(test 스토어 send_images t · send_tags t) ──
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('test', p_test, false, false, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('I1 test store row false · false: effective images f · tags f · files 0 · hash_changed', (select (j->'after'->>'effective_images') || '/' || (j->'after'->>'effective_tags') || '/' || (j->>'files') || '/' || (j->>'hash_changed') from pg_temp.j(r) j), 'false/false/0/true');
  perform pg_temp.chk('I2 test store row payload: send_images f · image_id null', (select (j->>'send_images') || '/' || ((j->'variants'->0->>'image_id') is not null)::text from pg_temp.j(pg_temp.pay(s_test, p_test)) j), 'false/false');
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('test', p_test, null, null, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('I3 test store row back to null: hash = original', (select ((j->'after'->>'hash') = h_test0)::text || '/' || (j->'after'->>'effective_images') from pg_temp.j(r) j), 'true/true');

  -- ── J 문 ──
  perform pg_temp.as_user(u_mgr);
  r := pg_temp.ovr('asung', p_abe, true, null, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('J1 manager (shopify perm · not admin) rejected · nothing saved', (r like 'ERR P0001: Only an admin can change Shopify send override%')::text || ' ' || (select coalesce(send_images::text, 'null') from public.shop_product where store_id = s_asung and product_id = p_abe), 'true null');
  perform pg_temp.as_user(u_adm);
  r := pg_temp.ovr('asung', p2, true, true, true);
  r2 := pg_temp.ovr('nope', p_abe, true, null, false);
  perform pg_temp.as_me();
  perform pg_temp.chk('J2 no shop_product row (NEW1-P2) rejected · no queue line', (r like 'ERR P0001: shop_product_send_override: no shop_product row for this target in store asung%')::text || ' ' || pg_temp.openq(s_asung, p2), 'true 0/-');
  perform pg_temp.chk('J3 unknown store rejected', r2, 'ERR P0001: shop_product_send_override: store nope not found');
  perform pg_temp.as_user(u_adm);
  r := pg_temp.run(format('select public.shop_product_send_override(%L, %L::uuid, %L::uuid, true, null, false)::text', 'asung', p_abe, p_abe));
  r2 := pg_temp.run(format('select public.shop_product_send_override(%L, null, null, true, null, false)::text', 'asung'));
  perform pg_temp.as_me();
  perform pg_temp.chk('J4 · J5 both targets · neither target rejected', (r like 'ERR P0001: shop_product_send_override: give exactly one of p_family_id, p_product_id%')::text || '/' || (r2 like 'ERR P0001: shop_product_send_override: give exactly one of p_family_id, p_product_id%')::text, 'true/true');
  perform pg_temp.chk('J6 anon has no execute on the window', (select has_function_privilege('anon', 'public.shop_product_send_override(text, uuid, uuid, boolean, boolean, boolean)', 'execute'))::text, 'false');

  -- ── K 재발행 diff · 무접촉 ──
  if is_mig then
    perform pg_temp.chk('K1 shop_variant_payload not re-issued (md5 same) · trigger · queue_add · queue_all · link_apply same',
      (select md5(prosrc) = pg_temp.ctx('vp_md5_0') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload')::text || '/' ||
      (select md5(prosrc) = pg_temp.ctx('tg_md5_0') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_queue_trigger')::text || '/' ||
      (select md5(prosrc) = pg_temp.ctx('qa_md5_0') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add')::text || '/' ||
      (select md5(prosrc) = pg_temp.ctx('qall_md5_0') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_all')::text || '/' ||
      (select md5(prosrc) = pg_temp.ctx('la_md5_0') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_link_apply')::text, 'true/true/true/true/true');
    perform pg_temp.chk('K2 shop_product_payload re-issued: md5 changed · lines removed from 10-30 body = 1 (the return line)',
      (select (md5(prosrc) <> pg_temp.ctx('pp_md5_0'))::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') || '/' ||
      (select count(*)::text from (select unnest(string_to_array(prosrc, E'\n')) as l from t_pre where proname = 'shop_product_payload') o
        where o.l not in (select unnest(string_to_array(prosrc, E'\n')) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload')), 'true/1');
    perform pg_temp.chk('K3 lines added to shop_product_payload (new body − old body · else · end if · if p_family_id … already exist)',
      (select count(*)::text from (select unnest(string_to_array(prosrc, E'\n')) as l from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') n
        where n.l not in (select unnest(string_to_array(prosrc, E'\n')) from t_pre where proname = 'shop_product_payload')), '9');
    perform pg_temp.chk('K4 window: definer · search_path · one definition', (select prosecdef::text || '/' || (proconfig::text like '%search_path=public, pg_temp%')::text || '/' || count(*) over () from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_send_override' limit 1), 'true/true/1');
    perform pg_temp.chk('K5 payload stays non-definer · stable (reads shop_product under caller RLS: authenticated select all)', (select (not prosecdef)::text || '/' || provolatile::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload'), 'true/s');
  end if;
  perform pg_temp.chk('K6 real rows inside the trial: shop_product = begin + 1 fake(ims) · product = begin + 2 · queue open = begin + 2 (D4 + K7)',
    (select count(*) from public.shop_product)::text || '/' || (select count(*) from public.product)::text || '/' || (select count(*) from public.shop_push_queue where done_at is null)::text, (n_sp0 + 1)::text || '/' || (n_prod0 + 2)::text || '/' || (n_qopen0 + 2)::text);
  perform pg_temp.chk('K7 G2 tag delete queued NEW1-P1 through the product_tag trigger (existing behaviour · listing on)', pg_temp.openq(s_asung, p1), '1/product_tag');
end $suite$;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, clock_timestamp() - :'t_begin'::timestamptz as begin_to_here from t_res;
rollback;
select case when (select count(*) from public.shop_store) = :n_store0 and (select count(*) from public.shop_listing) = :n_list0 and (select count(*) from public.product) = :n_prod0 and (select count(*) from public.product_image) = :n_img0
            and (select count(*) from public.product_tag) = :n_tag0 and (select count(*) from public.ims_staff) = :n_staff0
            and (select count(*) from public.shop_push_queue) = :n_q0 and (select count(*) from public.shop_push_queue where done_at is null) = :n_qopen0 and (select count(*) from public.shop_product) = :n_sp0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1, clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') = :'pp_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_variant_payload') = :'vp_md5_0'
       then 'Z2 OK payload functions back to before (md5)' else 'Z2 MISMATCH functions not restored' end as z2;
select case when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shop_product' and column_name in ('send_images', 'send_tags', 'origin'))
             and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_send_override') = :n_win0
       then 'Z3 OK columns and window gone' else 'Z3 MISMATCH column or window stayed' end as z3;
\endif
