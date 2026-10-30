-- supabase/tests/shop_cut_1_check.sql — shop-cut-1 컷 전 웹 오더는 ims-import 태그를 단 것만 받는다 (2026-10-30 · 판정 889)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 CUT1-(가짜 스토어 셋 · 짝 창고 둘 · 가짜 오더 · 실제 손님 하나 읽기만)
--   → A(태그 함수) · B(Go live 트리거) · C(ingest 막기 ① ~ ⑧ · SO 수) · D(재발행 diff · 시험 갈래만) · E(nowhere 정적) · F(속성 · md5 · 무접촉) → rollback → Z1 실제 행 무변 · Z2 md5 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030165351_shop_cut_1_before_cut_import_tag.sql -f supabase/tests/shop_cut_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 25 · 확인(적용 뒤) 22 — D0 ~ D2(옛 = 새 대조)는 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · SO 번호 시퀀스는 so_create 가 당긴다(rollback 돼도 시퀀스는 안 돌아온다 — 번호 구멍 둘 · 앞 차수 ord-1b2 와 같다)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다) · alter table shop_store 는 짧다(칸 하나 · 기본값 없음)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 25
\else
\set EXPECT_OK 22
\endif
\pset pager off
select (select count(*) from public.shop_store) as n_store0, (select count(*) from public.shop_location) as n_loc0, (select count(*) from public.shop_order) as n_ord0, (select count(*) from public.shop_order_line) as n_oline0,
       (select count(*) from public.shop_order_inbox) as n_inbox0, (select count(*) from public.shop_customer) as n_scust0, (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.customer) as n_cust0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') as ing_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_prepare') as prep_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_process') as proc_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_inbox_add') as inbox_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save') as save_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_resolve_customer') as rc_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_resolve_lines') as rl_md5_0 \gset
\echo '── 기준: shop_store' :n_store0 '· shop_order' :n_ord0 '· so' :n_so0 '· customer' :n_cust0 '· shop_order_ingest md5' :ing_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5, array_length(string_to_array(prosrc, E'\n'), 1) as n_lines from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 창구 호출: 성공이면 쓰기가 남고(바깥 트랜잭션 · rollback 됨) 결과 글자 · 오류면 ERR 글자(서브트랜잭션이 되돌린다) · null 은 '(null)'
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end; $$;
create function pg_temp.tagged(p jsonb) returns text language sql as $$ select pg_temp.run(format('select public.shop_order_import_tagged(%L::jsonb)::text', p)); $$;
-- ingest · process 를 run() 으로(새 갈래가 없는 DB 에서도 MISMATCH 로 끝나게) · 결과는 jsonb 글
create function pg_temp.ing(p_store uuid, p_order jsonb) returns text language sql as $$ select pg_temp.run(format('select public.shop_order_ingest(%L::uuid, %L::jsonb)::text', p_store, p_order)); $$;
create function pg_temp.proc(p_id text) returns text language sql as $$ select pg_temp.run(format('select public.shop_order_process(%L::uuid)::text', p_id)); $$;
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
-- 오더 원문 — ① 모양(ord-1a2-verify 의 pg_temp.ord 그대로) · p_lines = [{sku, qty, list, unit}] · p_extra 로 createdAt · updatedAt · tags 를 덮는다
create function pg_temp.ord(p_gid text, p_name text, p_email text, p_cust_gid text, p_prov text, p_lines jsonb, p_tax text, p_fin text default 'PENDING', p_ship jsonb default null, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select (jsonb_build_object('id', p_gid, 'name', p_name, 'createdAt', '2026-10-10T20:00:00Z', 'updatedAt', '2026-10-10T20:00:00Z', 'cancelledAt', null, 'test', true,
            'displayFinancialStatus', p_fin, 'sourceName', '2627105', 'email', p_email, 'phone', '555-0100', 'poNumber', 'PO-' || p_name, 'note', 'leave at door',
            'customer', case when p_cust_gid is null then null else jsonb_build_object('id', p_cust_gid, 'firstName', 'Debi', 'lastName', 'Blair', 'displayName', 'Debi Blair', 'defaultEmailAddress', jsonb_build_object('emailAddress', p_email)) end,
            'shippingAddress', jsonb_build_object('name', 'Debi Blair', 'company', 'Debi Salon', 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', p_prov, 'zip', 'A1A 1A1', 'countryCodeV2', 'CA', 'phone', '555-0100'),
            'billingAddress', jsonb_build_object('name', 'Debi Blair', 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', coalesce(p_prov, 'ON'), 'zip', 'A1A 1A1', 'countryCodeV2', 'CA'),
            'currencyCode', 'CAD',
            'subtotalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum((l->>'unit')::numeric * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l), 'FM999999990.00'))),
            'totalDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum(((l->>'list')::numeric - (l->>'unit')::numeric) * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l), 'FM999999990.00'))),
            'totalShippingPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', coalesce(p_ship->>'disc', '0.00'))),
            'totalTaxSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_tax)),
            'totalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((select sum((l->>'unit')::numeric * (l->>'qty')::numeric) from jsonb_array_elements(p_lines) l) + coalesce((p_ship->>'disc')::numeric, 0) + p_tax::numeric, 'FM999999990.00'))),
            'shippingLines', jsonb_build_object('nodes', case when p_ship is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('title', coalesce(p_ship->>'title', 'Standard'), 'originalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_ship->>'orig')), 'discountedPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_ship->>'disc')))) end),
            'lineItems', jsonb_build_object('nodes', (select coalesce(jsonb_agg(jsonb_build_object('id', 'gid://shopify/LineItem/' || t.n, 'sku', l->>'sku', 'name', 'Item ' || (l->>'sku'), 'quantity', (l->>'qty')::numeric,
                              'originalUnitPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', l->>'list')), 'discountedUnitPriceAfterAllDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', l->>'unit')),
                              'totalDiscountSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char(((l->>'list')::numeric - (l->>'unit')::numeric) * (l->>'qty')::numeric, 'FM999999990.00'))))), '[]'::jsonb) from jsonb_array_elements(p_lines) with ordinality as t(l, n))))
         ) || p_extra;
$$;
-- 가짜 오더 한 벌: gid 번호 · createdAt · tags(jsonb 또는 null = 칸 없음) · updatedAt · 결제
create function pg_temp.o(p_n int, p_created text, p_tags jsonb default null, p_updated text default null, p_fin text default 'PENDING') returns jsonb language sql as $$
  select pg_temp.ord('gid://shopify/Order/920000000' || lpad(p_n::text, 3, '0'), 'CUT1-T' || lpad(p_n::text, 4, '0'), '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/720000000001', 'AB',
                     '[{"sku":"AAL10925","qty":1,"list":"7.89","unit":"7.89"}]'::jsonb, to_char(public.so_tax_amount(7.89, 5), 'FM999999990.00'), p_fin, null,
                     jsonb_build_object('createdAt', p_created, 'updatedAt', coalesce(p_updated, p_created)) || case when p_tags is null then '{}'::jsonb else jsonb_build_object('tags', p_tags) end);
$$;
create function pg_temp.st(p_gid text) returns text language sql as $$
  select coalesce((select o.status || '/' || (o.so_id is not null)::text from public.shop_order o where o.shopify_order_gid = p_gid), 'no-row');
$$;

-- ── 재료(가짜 CUT1- · rollback) — 스토어 셋(cut1 막기 시험 · cut2 · cut3 트리거 시험) · cut1 에 짝 창고 둘(실제 Edmonton · 토론토) · 실제 손님(이메일 하나)은 읽기만 ──
select id::text as tier from public.shop_store where code = 'test' \gset
select id::text as wh_e from public.ref_warehouse where is_active and name ilike '%edmonton%' order by name limit 1 \gset
select id::text as wh_t from public.ref_warehouse where is_active and name not ilike '%edmonton%' order by name limit 1 \gset
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, is_active, live, orders_polled_at)
values ('cut1', 'cut1-check.myshopify.com', 'CUT1 check', 'asung', (select sale_tier_id from public.shop_store where code = 'test'), 'SHOPIFY_IMS', true, true, '2026-10-30 22:00:00+00'),
       ('cut2', 'cut2-check.myshopify.com', 'CUT2 check', 'asung', (select sale_tier_id from public.shop_store where code = 'test'), 'SHOPIFY_IMS', true, false, null),
       ('cut3', 'cut3-check.myshopify.com', 'CUT3 check', 'asung', (select sale_tier_id from public.shop_store where code = 'test'), 'SHOPIFY_IMS', true, false, null);
select id::text as s1 from public.shop_store where code = 'cut1' \gset
insert into public.shop_location (store_id, shopify_location_gid, shopify_name, warehouse_id, is_active)
values (:'s1'::uuid, 'gid://shopify/Location/920000000001', 'CUT1 Edmonton', :'wh_e'::uuid, true), (:'s1'::uuid, 'gid://shopify/Location/920000000002', 'CUT1 Toronto', :'wh_t'::uuid, true);
-- 컷 시각은 run() 으로(마른 갈래 = 칸이 없어 ERR → 뒤의 C 가 MISMATCH 로 드러난다)
select pg_temp.run('update public.shop_store set orders_cut_at = ''2026-10-30 22:00:00+00'' where code = ''cut1'' returning orders_cut_at::text') as cut_set \gset
\echo '── cut1 orders_cut_at:' :cut_set
select count(*)::text as n_so_in from public.so \gset

-- ── A) 태그 함수 — 낱말 하나 · 빈칸 · 대소문자 · 쉼표 글 · 없음 ──
select pg_temp.chk('A1 shop_order_import_tagged: ["foo","ims-import"] true · [" IMS-Import "] true · ["ims-importx"] false · ["ims-import-x"] false · string "a, IMS-IMPORT ,b" true · string "ims-importx,x" false · no tags false · tags null false · tags 5 false · [] false',
  pg_temp.tagged('{"tags":["foo","ims-import"]}') || '/' || pg_temp.tagged('{"tags":[" IMS-Import "]}') || '/' || pg_temp.tagged('{"tags":["ims-importx"]}') || '/' || pg_temp.tagged('{"tags":["ims-import-x"]}') || '/' ||
  pg_temp.tagged('{"tags":"a, IMS-IMPORT ,b"}') || '/' || pg_temp.tagged('{"tags":"ims-importx,x"}') || '/' || pg_temp.tagged('{}') || '/' || pg_temp.tagged('{"tags":null}') || '/' || pg_temp.tagged('{"tags":5}') || '/' || pg_temp.tagged('{"tags":[]}'),
  'true/true/false/false/true/false/false/false/false/false');

-- ── B) Go live 트리거 — live false → true 에서 비어 있으면 orders_polled_at 을 베낀다 · 한 번만 · live 없는 갱신은 무접촉 ──
select pg_temp.chk('B1 cut2: live false → true with orders_polled_at (store_live 모양) → orders_cut_at = that moment',
  pg_temp.run('update public.shop_store set live = true, orders_polled_at = ''2026-10-30 22:00:00+00'' where code = ''cut2'' returning orders_cut_at::text'), '2026-10-30 22:00:00+00');
select pg_temp.run('update public.shop_store set live = false where code = ''cut2'' returning live::text') as b2_off \gset
select pg_temp.chk('B2 cut2: live off → on again with a later orders_from → the first cut stays (coalesce · 한 번만)',
  :'b2_off' || '/' || pg_temp.run('update public.shop_store set live = true, orders_polled_at = ''2026-11-01 00:00:00+00'' where code = ''cut2'' returning orders_cut_at::text'), 'false/2026-10-30 22:00:00+00');
select pg_temp.chk('B3 cut3: live false → true without orders_polled_at → cut stays null (막기 꺼짐) · then orders_polled_at alone (live not in SET) → still null',
  pg_temp.run('update public.shop_store set live = true where code = ''cut3'' returning coalesce(orders_cut_at::text, ''null'')') || '/' ||
  pg_temp.run('update public.shop_store set orders_polled_at = ''2026-10-31 00:00:00+00'' where code = ''cut3'' returning coalesce(orders_cut_at::text, ''null'')'), 'null/null');
select pg_temp.chk('B4 cut1 (inserted live · cut set by SQL): touching orders_polled_at (what orders_poll does every 15 min) leaves the cut alone',
  pg_temp.run('update public.shop_store set orders_polled_at = ''2026-10-31 03:00:00+00'' where code = ''cut1'' returning orders_cut_at::text'), '2026-10-30 22:00:00+00');

-- ── C) ingest 막기 — cut1 컷 2026-10-30 22:00+00 · ① ~ ⑧ ──
select pg_temp.ing(:'s1'::uuid, pg_temp.o(1, '2026-10-29T20:00:00Z')) as c1 \gset
select pg_temp.chk('C1 ① before the cut · no tag → status before_cut · action skipped · shop_order_id null · message names the tag · no shop_order row · no shop_order_line · SO count unchanged',
  coalesce(pg_temp.j(:'c1')->>'status', left(:'c1', 60)) || '/' || coalesce(pg_temp.j(:'c1')->>'action', '-') || '/' || coalesce(pg_temp.j(:'c1')->>'shop_order_id', 'null') || '/' ||
  (coalesce(pg_temp.j(:'c1')->>'message', '') like 'Shopify order CUT1-T0001 was created 2026-10-29 16:00, before the IMS cut-over of store cut1 (2026-10-30 18:00), and has no ims-import tag%add the tag ims-import%')::text || '/' ||
  pg_temp.st('gid://shopify/Order/920000000001') || '/' || (select count(*) from public.shop_order_line l join public.shop_order o on o.id = l.shop_order_id where o.store_id = :'s1'::uuid)::text || '/' || ((select count(*) from public.so) - :n_so_in)::text,
  'before_cut/skipped/null/true/no-row/0/0');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(2, '2026-10-30T23:00:00Z')) as c2 \gset
select pg_temp.proc(pg_temp.j(:'c2')->>'shop_order_id') as c2p \gset
select pg_temp.chk('C2 ② after the cut · no tag → received → process created → SO +1 (평소대로)',
  coalesce(pg_temp.j(:'c2')->>'status', left(:'c2', 60)) || '/' || coalesce(pg_temp.j(:'c2p')->>'status', left(:'c2p', 60)) || '/' || pg_temp.st('gid://shopify/Order/920000000002') || '/' || ((select count(*) from public.so) - :n_so_in)::text,
  'received/created/created/true/1');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(3, '2026-10-29T20:00:00Z', '["wholesale","ims-import"]'::jsonb)) as c3 \gset
select pg_temp.proc(pg_temp.j(:'c3')->>'shop_order_id') as c3p \gset
select pg_temp.chk('C3 ③ before the cut · tag ims-import → received → process created → SO +1 (손님 잇기 · 값 · 세금 · 확정 평소대로)',
  coalesce(pg_temp.j(:'c3')->>'status', left(:'c3', 60)) || '/' || coalesce(pg_temp.j(:'c3p')->>'status', left(:'c3p', 60)) || '/' || pg_temp.st('gid://shopify/Order/920000000003') || '/' || ((select count(*) from public.so) - :n_so_in)::text,
  'received/created/created/true/2');
select so_id::text as so3 from public.shop_order where shopify_order_gid = 'gid://shopify/Order/920000000003' \gset
select pg_temp.ing(:'s1'::uuid, pg_temp.o(3, '2026-10-29T20:00:00Z', '["wholesale","ims-import"]'::jsonb, '2026-10-31T01:00:00Z')) as c4 \gset
select pg_temp.chk('C4 ④ ③ read again (updatedAt moved · tag kept) → action updated_after_created · same SO · SO count unchanged (멱등)',
  coalesce(pg_temp.j(:'c4')->>'action', left(:'c4', 60)) || '/' || (select (so_id::text = :'so3')::text || '/' || status from public.shop_order where shopify_order_gid = 'gid://shopify/Order/920000000003') || '/' || ((select count(*) from public.so) - :n_so_in)::text,
  'updated_after_created/true/created/2');
select pg_temp.run('update public.shop_store set orders_cut_at = null where code = ''cut1'' returning coalesce(orders_cut_at::text, ''null'')') as c5_off \gset
select pg_temp.ing(:'s1'::uuid, pg_temp.o(6, '2026-10-29T20:00:00Z')) as c5 \gset
select pg_temp.run('update public.shop_store set orders_cut_at = ''2026-10-30 22:00:00+00'' where code = ''cut1'' returning orders_cut_at::text') as c5_on \gset
select pg_temp.chk('C5 ⑤ orders_cut_at null → gate off: a before-cut untagged order comes in as received (지금 동작 그대로) · cut restored',
  :'c5_off' || '/' || coalesce(pg_temp.j(:'c5')->>'status', left(:'c5', 60)) || '/' || pg_temp.st('gid://shopify/Order/920000000006') || '/' || :'c5_on', 'null/received/received/false/2026-10-30 22:00:00+00');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(7, '2026-10-29T20:00:00Z', '[" IMS-Import "]'::jsonb)) as c6a \gset
select pg_temp.ing(:'s1'::uuid, pg_temp.o(8, '2026-10-29T20:00:00Z', '["ims-importx"]'::jsonb)) as c6b \gset
select pg_temp.ing(:'s1'::uuid, pg_temp.o(9, '2026-10-29T20:00:00Z', '"retail, IMS-IMPORT"'::jsonb)) as c6c \gset
select pg_temp.chk('C6 ⑥ tag " IMS-Import " → received · "ims-importx" → before_cut (no row) · comma string "retail, IMS-IMPORT" → received',
  coalesce(pg_temp.j(:'c6a')->>'status', left(:'c6a', 60)) || '/' || coalesce(pg_temp.j(:'c6b')->>'status', left(:'c6b', 60)) || '/' || pg_temp.st('gid://shopify/Order/920000000008') || '/' || coalesce(pg_temp.j(:'c6c')->>'status', left(:'c6c', 60)),
  'received/before_cut/no-row/received');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(1, '2026-10-29T20:00:00Z', null, '2026-11-15T15:00:00Z', 'PAID')) as c7 \gset
select pg_temp.chk('C7 ⑦ ① captured / refunded later (updatedAt moved · PAID) and read again → still before_cut · still no row · SO count unchanged',
  coalesce(pg_temp.j(:'c7')->>'status', left(:'c7', 60)) || '/' || pg_temp.st('gid://shopify/Order/920000000001') || '/' || ((select count(*) from public.so) - :n_so_in)::text, 'before_cut/no-row/2');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(3, '2026-10-29T20:00:00Z', '[]'::jsonb, '2026-11-15T15:00:00Z')) as c8 \gset
select pg_temp.chk('C8 ⑧ ③ tag removed later and read again → the linked order follows Shopify as usual (updated_after_created · warning updated_after_so) · same SO · no new SO',
  coalesce(pg_temp.j(:'c8')->>'action', left(:'c8', 60)) || '/' || (select (so_id::text = :'so3')::text || '/' || exists (select 1 from jsonb_array_elements(warnings) w where w->>'code' = 'updated_after_so')::text from public.shop_order where shopify_order_gid = 'gid://shopify/Order/920000000003') || '/' || ((select count(*) from public.so) - :n_so_in)::text,
  'updated_after_created/true/true/2');
select pg_temp.ing(:'s1'::uuid, pg_temp.o(10, '2026-10-30T22:00:00Z')) as c9a \gset
select pg_temp.ing(:'s1'::uuid, pg_temp.o(11, '2026-10-29T20:00:00Z') || '{"createdAt": null}'::jsonb) as c9b \gset
select pg_temp.chk('C9 edges: createdAt = cut exactly → not blocked (strict <) · createdAt missing → not blocked (cannot compare · 안전 쪽은 받기)',
  coalesce(pg_temp.j(:'c9a')->>'status', left(:'c9a', 60)) || '/' || coalesce(pg_temp.j(:'c9b')->>'status', left(:'c9b', 60)), 'received/received');
select pg_temp.chk('C10 before-cut untagged order that is cancelled in Shopify → still before_cut (no row · no cancelled row either)',
  coalesce(pg_temp.j(pg_temp.ing(:'s1'::uuid, pg_temp.o(12, '2026-10-29T20:00:00Z') || '{"cancelledAt": "2026-10-31T01:00:00Z"}'::jsonb))->>'status', 'ERR') || '/' || pg_temp.st('gid://shopify/Order/920000000012'), 'before_cut/no-row');

-- ── D) 재발행 diff — 옛(begin 앞 prosrc) = 새 대조 · 시험 갈래만 · 줄 글자(다중집합)로 비교 ──
\if :{?mig}
create temp table t_diff as
  with o as (select l, count(*) as c from t_pre t, regexp_split_to_table(t.prosrc, E'\n') as l group by l),
       w as (select l, count(*) as c from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') as l where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_ingest' group by l)
  select 'removed' as side, o.l, o.c - coalesce(w.c, 0) as c from o left join w on w.l = o.l where o.c > coalesce(w.c, 0)
  union all
  select 'added', w.l, w.c - coalesce(o.c, 0) from w left join o on o.l = w.l where w.c > coalesce(o.c, 0);
select pg_temp.chk('D0 begin 앞 prosrc = 마지막 정의(stk_r1:38 · md5 · 250 줄)', (select md5 || '/' || n_lines from t_pre), '54bda045cb87405fa8df6ba3711821e8/250');
select pg_temp.chk('D1 new = old + 4 lines · removed 0 · added 4', (select array_length(string_to_array(prosrc, E'\n'), 1)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') || '/' ||
  (select coalesce(sum(c) filter (where side = 'removed'), 0)::text || '/' || coalesce(sum(c) filter (where side = 'added'), 0)::text from t_diff), '254/0/4');
select pg_temp.chk('D2 added = the gate line (row missing · cut set · createdAt < cut · not tagged) + return before_cut + its message + end if · nothing else',
  (select string_agg(side || '=' || left(regexp_replace(btrim(l), '\s+--.*$', ''), 60), ' || ' order by side desc, btrim(l) collate "C") from t_diff),
  'added=''message'', format(''Shopify order %s was created %s, before t' ||
  ' || added=end if;' ||
  ' || added=if v_o.id is null and v_s.orders_cut_at is not null and null' ||
  ' || added=return jsonb_build_object(''shop_order_id'', null, ''action'', ''');
\endif

-- ── E) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE ──
select pg_temp.chk('E0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('E1 last definitions: WHERE-less update · delete = 0 for shop_order_ingest · shop_store_cut_on_live',
  (select 'ingest ' || pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') || ' / ' ||
  coalesce((select 'trigger ' || pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_cut_on_live'), 'trigger missing'), 'ingest 0 / trigger 0');

-- ── F) 속성 · md5 · 무접촉 ──
select pg_temp.chk('F1 shop_order_ingest: definer · volatile · search_path · authenticated no · anon no · exactly one · comment has 889 · calls shop_order_import_tagged(p_order) once · before_cut once',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || ((length(prosrc) - length(replace(prosrc, 'shop_order_import_tagged(p_order)', ''))) / length('shop_order_import_tagged(p_order)'))::text || '/' ||
          ((length(prosrc) - length(replace(prosrc, '''before_cut''', ''))) / length('''before_cut'''))::text
     from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') || '/' ||
  has_function_privilege('authenticated', 'public.shop_order_ingest(uuid, jsonb)', 'execute')::text || '/' || has_function_privilege('anon', 'public.shop_order_ingest(uuid, jsonb)', 'execute')::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') || '/' || (coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') like '%판정 889%')::text,
  'true/v/search_path=public, pg_temp/1/1/false/false/1/true');
select pg_temp.chk('F2 shop_order_import_tagged: immutable · authenticated no · anon no · one · comment 889 / trigger shop_store_cut_on_live: before update of live · row · function comment 889 / shop_store.orders_cut_at: timestamptz · nullable · no default · comment 889',
  coalesce((select provolatile::text || '/' || has_function_privilege('authenticated', oid, 'execute')::text || '/' || has_function_privilege('anon', oid, 'execute')::text || '/' || (coalesce(obj_description(oid, 'pg_proc'), '') like '%판정 889%')::text
              from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_import_tagged'), 'fn missing') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_import_tagged')::text || ' / ' ||
  coalesce((select (tgtype & 2 = 2)::text || '/' || (tgtype & 1 = 1)::text || '/' || (tgtype & 16 = 16)::text || '/' || (select attname from pg_attribute where attrelid = t.tgrelid and attnum = any(t.tgattr::int2[]))
              from pg_trigger t where t.tgrelid = 'public.shop_store'::regclass and t.tgname = 'shop_store_cut_on_live'), 'trigger missing') || '/' ||
  coalesce((select (coalesce(obj_description(oid, 'pg_proc'), '') like '%판정 889%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_cut_on_live'), 'fn missing') || ' / ' ||
  coalesce((select data_type || '/' || is_nullable || '/' || coalesce(column_default, 'none') from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'orders_cut_at'), 'column missing') || '/' ||
  (coalesce(col_description('public.shop_store'::regclass, (select attnum from pg_attribute where attrelid = 'public.shop_store'::regclass and attname = 'orders_cut_at')), '') like '%판정 889%')::text,
  'i/false/false/true/1 / true/true/true/live/true / timestamp with time zone/YES/none/true');
select pg_temp.chk('F3 shop_order_inbox.result comment mentions before_cut', (coalesce(col_description('public.shop_order_inbox'::regclass, (select attnum from pg_attribute where attrelid = 'public.shop_order_inbox'::regclass and attname = 'result')), '') like '%before_cut%')::text, 'true');
select pg_temp.chk('F4 untouched (md5 begin 앞 = 지금): shop_order_prepare · shop_order_process · shop_order_inbox_add · shop_store_save · shop_order_resolve_customer · shop_order_resolve_lines',
  (select md5(prosrc) = :'prep_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_prepare')::text || '/' || (select md5(prosrc) = :'proc_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_process')::text || '/' ||
  (select md5(prosrc) = :'inbox_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_inbox_add')::text || '/' || (select md5(prosrc) = :'save_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save')::text || '/' ||
  (select md5(prosrc) = :'rc_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_resolve_customer')::text || '/' || (select md5(prosrc) = :'rl_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_resolve_lines')::text,
  'true/true/true/true/true/true');
select pg_temp.chk('F5 the real stores were not touched inside the trial (asung · aone · test rows: live · orders_polled_at as before the begin)',
  (select string_agg(code || ':' || live::text || ':' || coalesce(orders_polled_at::text, 'null'), ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')),
  (select string_agg(code || ':' || live::text || ':' || coalesce(orders_polled_at::text, 'null'), ',' order by code) from public.shop_store where code in ('asung', 'aone', 'test')));

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.shop_store) = :n_store0 and (select count(*) from public.shop_location) = :n_loc0 and (select count(*) from public.shop_order) = :n_ord0 and (select count(*) from public.shop_order_line) = :n_oline0
            and (select count(*) from public.shop_order_inbox) = :n_inbox0 and (select count(*) from public.shop_customer) = :n_scust0 and (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.customer) = :n_cust0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_ingest') = :'ing_md5_0'
       then 'Z2 OK shop_order_ingest back to before (md5)' else 'Z2 MISMATCH shop_order_ingest not restored' end as z2;
\endif
