-- doc-hand-price-1 검증 — supabase/migrations/20261102190000_doc_hand_price_1.sql (판정 976 · 977 · 이견 답 1 ㉡ · 2 · 3 ⓑ · asung-doc §2 · so-module §66)
--   시험 적용 + 검증(Claude Code · rollback): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102190000_doc_hand_price_1.sql -f supabase/tests/doc_hand_price_1_check.sql 2>&1 | tee /tmp/doc_hand_price_1.out
--   확인 실행(Caleb · 적용 뒤 · -v mig 없음): 같은 명령에서 -v mig 만 뺀다 · 갈래는 DB 의 doc_data_invoice_fmt prosrc md5 로 가른다(옛 판 6a2fe901 = doc-sr-1 · 새 판 = doc-hand-price-1)
--   OK 줄 꼴: 'OK <태그>'(앞 빈칸 없음) → grep -cE '^ ?OK ' · MISMATCH 줄 꼴: 'MISMATCH (<태그>): <자세히>'
--   EXPECT: 시험(-v mig) OK 22 · MISMATCH 0 · 확인(적용 뒤 · -v mig 없음) OK 16 — 파일 끝 「기대 OK」 주석
--   ⚠️ 재료: 실물은 읽기만(SO-20843 Draft 손 가격 15 줄 · SO-20841b 손님 7 % · SO-20899a Shopify · 인보이스 60023(Shopify 20 줄) · 60024(손님 8 줄) · CR-01008) · 가짜(rollback)는 직원 1(sales) 뿐 · 그리기 직접은 중립 jsonb
--   ⚠️ 테스트 DB 는 IMS 운영(판정 617) · cron 이 돈다 — 반드시 rollback · doc_mail_* 는 부르지 않는다 · 시퀀스는 당기지 않는다 · 잠금 규칙 ④: 무거운 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다
\set ON_ERROR_STOP on
\pset pager off
-- ── 머리(잠금 없음) — 함수 판 · ACL · 재료 열쇠 · 실물 스냅샷 ──
select (select value from public.inv_config where key = 'db_role') as db_role;
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace), '(none)') as fmt_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_so' and pronamespace = 'public'::regnamespace), '(none)') as so_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_credit' and pronamespace = 'public'::regnamespace), '(none)') as cr_md5_head \gset
select (:'fmt_md5_head' = '6a2fe901b2d006e1ea1d8314c7991f84')::int as is_old \gset
select ((:{?mig}) or :is_old = 0)::int as expect_pass \gset
select :'fmt_md5_head' as fmt_md5_head, :'so_md5_head' as so_md5_head, :'cr_md5_head' as cr_md5_head, :is_old as is_old, :expect_pass as expect_pass;
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '(none)') as so_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure), '(none)') as cr_acl_head \gset
select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.list_price::text, '') || ':' || coalesce(t.discount_pct::text, '') || ':' || coalesce(t.unit_price::text, '') || ':' || t.price_override::text || ':' || coalesce(t.discount_source, ''), '|' order by t.id), '')) || ' ' || count(*) as snap_sl from public.so_line t \gset
select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.list_price::text, '') || ':' || coalesce(t.discount_pct::text, '') || ':' || coalesce(t.unit_price::text, ''), '|' order by t.id), '')) || ' ' || count(*) as snap_il from public.so_invoice_line t \gset
select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.unit_price::text, '') || ':' || coalesce(t.amount::text, ''), '|' order by t.id), '')) || ' ' || count(*) as snap_cl from public.so_credit_line t \gset
select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) as snap_ta from public.doc_template_active t \gset
select (select count(*) from public.ims_staff) as n_staff_head, (select count(*) from public.so_line where price_override and free_reason is null and combo_line_id is null) as n_hand_head \gset
select coalesce((select id::text from public.so where so_number = 'SO-20843'), '') as so_hand \gset
select coalesce((select id::text from public.so where so_number = 'SO-20841b'), '') as so_disc \gset
select coalesce((select s.id::text from public.so s where s.status in ('confirmed', 'fulfilled', 'picking', 'packed') and exists (select 1 from public.so_line l where l.so_id = s.id and l.discount_source = 'shopify') order by s.so_number desc limit 1), '') as so_shop \gset
select coalesce((select so_number from public.so where id = nullif(:'so_shop', '')::uuid), '(없음)') as so_shop_number \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60023' and status = 'issued'), '') as inv_shop \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60024' and status = 'issued'), '') as inv_cust \gset
select coalesce((select id::text from public.so_credit where credit_number = 'CR-01008'), '') as cr_s \gset
select (:'so_hand' <> '')::int as has_hand, (:'so_disc' <> '')::int as has_disc, (:'so_shop' <> '')::int as has_shop, (:'inv_shop' <> '' and :'inv_cust' <> '')::int as has_inv, (:'cr_s' <> '')::int as has_cr \gset
select :has_hand as has_so_20843, :has_disc as has_so_20841b, :has_shop as has_shopify_so, :'so_shop_number' as shopify_so, :has_inv as has_60023_60024, :has_cr as has_cr_01008, :n_hand_head as hand_lines_now;
select jsonb_build_object('so_id', :'so_hand')::text as r_hand, jsonb_build_object('so_id', :'so_disc')::text as r_disc, jsonb_build_object('so_id', :'so_shop')::text as r_shop,
       jsonb_build_object('invoice_id', :'inv_shop')::text as r_is, jsonb_build_object('invoice_id', :'inv_cust')::text as r_ic, jsonb_build_object('credit_id', :'cr_s')::text as r_cr \gset

-- chk 는 트랜잭션 밖에서 만든다 — rollback 뒤의 Z2 도 부른다(트랜잭션 안의 pg_temp 함수는 rollback 으로 사라진다)
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\pset format unaligned
\pset tuples_only on
-- 가짜 직원(sales) 신원으로 창구를 부른다 · 예외는 'ERR <sqlstate>: <문장>' 글자로
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000d5976","role":"authenticated"}', true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v_out;
exception when others then
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.dd(p_kind text, p_ref jsonb) returns jsonb language sql as $$ select pg_temp.j(pg_temp.asu(format('select public.doc_data(%L, %L)::text', p_kind, p_ref))) $$;
-- 줄 목록: sales_order · credit_note = docs[0].lines · 인보이스 꼴 = docs[0].orders[*].lines 를 이어서
create function pg_temp.lines(p jsonb) returns jsonb language sql as $$
  select case when (p->'docs'->0) ? 'orders' then (select coalesce(jsonb_agg(l order by (l->>'no')::int), '[]'::jsonb) from jsonb_array_elements(p->'docs'->0->'orders') o cross join lateral jsonb_array_elements(o->'lines') l)
              else coalesce(p->'docs'->0->'lines', '[]'::jsonb) end $$;
-- 비교용: doc.printed_at 을 떼고 · 줄에서 list_price · discount_pct · is_free 를 뗀 것(그 둘만 바뀌어야 한다)
create function pg_temp.strip_doc(p jsonb) returns jsonb language sql as $$
  select (select coalesce(jsonb_agg(jsonb_set(d, '{doc}', coalesce(d->'doc', '{}'::jsonb) - 'printed_at') order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;
create function pg_temp.strip_cells(p jsonb) returns jsonb language plpgsql as $$
declare v jsonb := p; d jsonb; o jsonb; i int; k int; v_docs jsonb := '[]'::jsonb; v_ord jsonb; v_lines jsonb;
begin
  for d in select x from jsonb_array_elements(p->'docs') x loop
    if d ? 'orders' then
      v_ord := '[]'::jsonb;
      for o in select x from jsonb_array_elements(d->'orders') x loop
        select coalesce(jsonb_agg(l - 'list_price' - 'discount_pct' - 'is_free' order by (l->>'no')::int), '[]'::jsonb) into v_lines from jsonb_array_elements(o->'lines') l;
        v_ord := v_ord || jsonb_set(o, '{lines}', v_lines);
      end loop;
      d := jsonb_set(d, '{orders}', v_ord);
    elsif d ? 'lines' then
      select coalesce(jsonb_agg(l - 'list_price' - 'discount_pct' - 'is_free' order by (l->>'no')::int), '[]'::jsonb) into v_lines from jsonb_array_elements(d->'lines') l;
      d := jsonb_set(d, '{lines}', v_lines);
    end if;
    v_docs := v_docs || jsonb_set(d, '{doc}', coalesce(d->'doc', '{}'::jsonb) - 'printed_at');
  end loop;
  return v_docs;
end $$;
create function pg_temp.paths(p jsonb, p_pre text default '') returns setof text language plpgsql as $$
declare k text; e jsonb;
begin
  if jsonb_typeof(p) = 'object' then
    for k in select x from jsonb_object_keys(p) x loop
      if jsonb_typeof(p->k) = 'object' then return query select * from pg_temp.paths(p->k, p_pre || k || '.');
      elsif jsonb_typeof(p->k) = 'array' then return next p_pre || k; return query select * from pg_temp.paths(p->k, p_pre || k || '.');
      else return next p_pre || k; end if;
    end loop;
  elsif jsonb_typeof(p) = 'array' then
    for e in select x from jsonb_array_elements(p) x loop return query select * from pg_temp.paths(e, p_pre); end loop;
  end if;
  return;
end $$;
create function pg_temp.pset(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(distinct x order by x), '{}') from pg_temp.paths(p) x $$;
-- 줄 한 줄 요약(실물 보고용): sku · 단가 칸 · 할인 칸 · 금액
create function pg_temp.row3(p jsonb) returns text language sql as $$ select format('%s %s · %s · %s', rpad(p->>'sku', 9), lpad(p->>'list_price', 7), lpad(coalesce(nullif(p->>'discount_pct', ''), '(blank)'), 7), lpad(p->>'amount', 8)) $$;
-- 문서 줄 ↔ 표 줄 대조(같은 so 의 so_line · sku 로 잇는다): 문서 list_price = 정가 꼴 · discount_pct = 할인 꼴 인 줄 수 / 전체
create function pg_temp.so_match(p_lines jsonb, p_so uuid) returns text language sql as $$
  select count(*) filter (where (l->>'list_price') = public.doc_fmt_money(sl.list_price) and (l->>'discount_pct') = public.doc_fmt_pct(sl.discount_pct)) || '/' || count(*)
  from jsonb_array_elements(p_lines) l join public.so_line sl on sl.so_id = p_so and sl.sku = l->>'sku' and sl.combo_line_id is null $$;
create function pg_temp.inv_match(p_lines jsonb, p_inv uuid) returns text language sql as $$
  select count(*) filter (where (l->>'list_price') = public.doc_fmt_money(il.list_price) and (l->>'discount_pct') = public.doc_fmt_pct(il.discount_pct)) || '/' || count(*)
  from jsonb_array_elements(p_lines) l join public.so_invoice_line il on il.invoice_id = p_inv and il.kind = 'product' and il.sku = l->>'sku' $$;

-- ── 가짜 재료(replica · 트리거 없이) — 직원 1 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values ('00000000-0000-4000-8000-0000000d5976', 'dochp1-sa@example.invalid', 'dochp1 sales', 'worker', '["sales"]', true) returning id::text as st \gset
set local session_replication_role = origin;

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 판 — 옛 출력을 받아 둔다 ──
select pg_temp.dd('sales_order', :'r_hand'::jsonb)::text as o_hand, pg_temp.dd('sales_order', :'r_disc'::jsonb)::text as o_disc, pg_temp.dd('sales_order', :'r_shop'::jsonb)::text as o_shop,
       pg_temp.dd('final_invoice', :'r_is'::jsonb)::text as o_is, pg_temp.dd('final_invoice', :'r_ic'::jsonb)::text as o_ic, pg_temp.dd('internal_receipt', :'r_ic'::jsonb)::text as o_ir, pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as o_cr \gset
select pg_temp.chk('O1 시험에서만: 적용 전 = doc-sr-1 fmt(6a2fe901) · od-1 so(904414a2) · hcr-1 credit(017c7f9b) · doc_price_cells 없음 · 옛 출력 일곱이 JSON · SO-20843 옛 줄 3 = 「21.59 · (빈칸) · 194.04」(정가가 찍힌다 · 셈이 안 맞아 보이는 실물) · CR-01008 옛 제품 줄 list_price 전부 ""(Unit price 빈칸 실물)',
  :is_old = 1 and :'so_md5_head' = '904414a209c081eb2900bfe5daa935c3' and :'cr_md5_head' = '017c7f9b5111995d418a6d5888d27bda'
  and not exists (select 1 from pg_proc where proname = 'doc_price_cells' and pronamespace = 'public'::regnamespace)
  and left(:'o_hand', 1) = '{' and left(:'o_disc', 1) = '{' and left(:'o_shop', 1) = '{' and left(:'o_is', 1) = '{' and left(:'o_ic', 1) = '{' and left(:'o_ir', 1) = '{' and left(:'o_cr', 1) = '{'
  and (:has_hand = 0 or (select (l->>'list_price') = '21.59' and (l->>'discount_pct') = '' and (l->>'amount') = '194.04' and (l->>'unit_price') = '16.17' from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'o_hand'))) l where (l->>'no') = '3'))
  and (:has_cr = 0 or (select bool_and((l->>'list_price') = '') and count(*) = 2 from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'o_cr'))) l)),
  format('fmt %s so %s cr %s | hand %s | disc %s | cr %s', :'fmt_md5_head', :'so_md5_head', :'cr_md5_head', left(:'o_hand', 60), left(:'o_disc', 60), left(:'o_cr', 60)));
select 'O1-실물(적용 전) SO-20843 줄 3: ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'o_hand'))) l where (l->>'no') = '3';
select 'O1-실물(적용 전) CR-01008 줄 ' || (l->>'no') || ': ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'o_cr'))) l;
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 셋 다 새 몸(md5 바뀜) · doc_price_cells 생김 · 함수 하나씩 · 셋 다 몸에 doc_price_cells',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> '6a2fe901b2d006e1ea1d8314c7991f84'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> '904414a209c081eb2900bfe5daa935c3'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure) <> '017c7f9b5111995d418a6d5888d27bda'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_data_so', 'doc_data_credit', 'doc_price_cells') and pronamespace = 'public'::regnamespace) = 4
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_data_so', 'doc_data_credit') and pronamespace = 'public'::regnamespace and prosrc ~ 'doc_price_cells') = 3,
  format('fmt %s so %s cr %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure)));
\else
select pg_temp.chk('G0 확인 실행: doc_data_invoice_fmt 가 있다 · 판 = ' || case when :is_old = 1 then '옛(doc-sr-1 · 적용 전 — 아래 갈래는 돌지 않는다)' else '새(doc-hand-price-1 · 통과 갈래)' end,
  :'fmt_md5_head' <> '(none)', :'fmt_md5_head');
\endif
\if :expect_pass
-- ── 새 출력 ──
select pg_temp.dd('sales_order', :'r_hand'::jsonb)::text as n_hand, pg_temp.dd('sales_order', :'r_disc'::jsonb)::text as n_disc, pg_temp.dd('sales_order', :'r_shop'::jsonb)::text as n_shop,
       pg_temp.dd('final_invoice', :'r_is'::jsonb)::text as n_is, pg_temp.dd('final_invoice', :'r_ic'::jsonb)::text as n_ic, pg_temp.dd('internal_receipt', :'r_ic'::jsonb)::text as n_ir, pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as n_cr \gset
select pg_temp.chk('N0 새 출력 일곱이 다 JSON(가짜 직원 sales 로 doc_data — sales_order 셋 · final_invoice 둘 · internal_receipt · credit_note)',
  left(:'n_hand', 1) = '{' and left(:'n_disc', 1) = '{' and left(:'n_shop', 1) = '{' and left(:'n_is', 1) = '{' and left(:'n_ic', 1) = '{' and left(:'n_ir', 1) = '{' and left(:'n_cr', 1) = '{',
  format('hand %s | disc %s | shop %s | is %s | ic %s | ir %s | cr %s', left(:'n_hand', 80), left(:'n_disc', 80), left(:'n_shop', 80), left(:'n_is', 80), left(:'n_ic', 80), left(:'n_ir', 80), left(:'n_cr', 80)));
-- ── T1 SO-20843(손 가격 15 줄): 줄마다 단가 칸 = 손 가격(unit_price 열쇠와 같은 글자) · 할인 빈칸 · 줄 3 「16.17 · (빈칸) · 194.04」 ──
select pg_temp.chk('T1 SO-20843(Draft · 손 가격 15 줄 · price_override): 줄 15 · 모든 줄 list_price = unit_price(손 가격) · discount_pct "" · 줄 3 = 「16.17 · (빈칸) · 194.04」 · unit_price "16.17" · net_unit_price ""',
  :has_hand = 1 and (select count(*) = 15 and bool_and((l->>'list_price') = (l->>'unit_price') and (l->>'discount_pct') = '' and (l->>'list_price') <> '') from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand'))) l)
  and (select (l->>'list_price') = '16.17' and (l->>'discount_pct') = '' and (l->>'amount') = '194.04' and (l->>'unit_price') = '16.17' and (l->>'net_unit_price') = '' and (l->>'sku') = 'ONO00017' from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand'))) l where (l->>'no') = '3'),
  format('n %s | line3 %s', (select count(*) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand')))), (select l::text from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand'))) l where (l->>'no') = '3')));
select 'T1-실물 SO-20843 줄 3: ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand'))) l where (l->>'no') = '3';
select 'T1-실물 SO-20843 줄 ' || lpad(l->>'no', 2) || ': ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_hand'))) l order by (l->>'no')::int;
\if :{?mig}
select pg_temp.chk('T1b 시험에서만: SO-20843 옛 = 새 — 줄의 list_price · discount_pct 만 다르다(두 칸 · 시각 떼면 같음 · totals 같음) · 열쇠 집합 같음',
  :has_hand = 1 and pg_temp.strip_cells(pg_temp.j(:'n_hand')) = pg_temp.strip_cells(pg_temp.j(:'o_hand'))
  and (pg_temp.j(:'n_hand')->'docs'->0->'totals') = (pg_temp.j(:'o_hand')->'docs'->0->'totals')
  and pg_temp.pset(pg_temp.j(:'n_hand')->'docs'->0) = pg_temp.pset(pg_temp.j(:'o_hand')->'docs'->0),
  format('old totals %s | new totals %s', (pg_temp.j(:'o_hand')->'docs'->0->'totals')::text, (pg_temp.j(:'n_hand')->'docs'->0->'totals')::text));
\endif
-- ── T2 SO-20841b(손님 7 %) · T3 Shopify SO: 지금처럼 정가 · 할인 % — 표 so_line 과 글자 대조 ──
select pg_temp.chk('T2 SO-20841b(손님 할인 7 % · discount_source customer): 줄 1 = 「10.69 · 7% · 29.83」 · unit_price "9.94" · 모든 줄 list_price = 정가 꼴 · discount_pct = 할인 꼴(so_line 대조)' || case when :{?mig} then ' · 시험: 옛 = 새(시각만 떼고 글자 그대로)' else '' end,
  :has_disc = 1 and (select (l->>'list_price') = '10.69' and (l->>'discount_pct') = '7%' and (l->>'amount') = '29.83' and (l->>'unit_price') = '9.94' from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_disc'))) l where (l->>'no') = '1')
  and split_part(pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_disc')), :'so_disc'::uuid), '/', 1) = split_part(pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_disc')), :'so_disc'::uuid), '/', 2)
  and jsonb_array_length(pg_temp.lines(pg_temp.j(:'n_disc'))) >= 1,
  format('line1 %s | match %s', (select l::text from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_disc'))) l where (l->>'no') = '1'), pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_disc')), :'so_disc'::uuid)));
select 'T2-실물 SO-20841b 줄 1: ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_disc'))) l where (l->>'no') = '1';
select pg_temp.chk('T3 Shopify SO ' || :'so_shop_number' || '(discount_source shopify · so_line_manual true 지만 할인 % 가 있다 → 손 줄 아님): 모든 줄 list_price = 정가 꼴 · discount_pct = 할인 꼴(so_line 대조) · 줄 1 이상',
  :has_shop = 1 and split_part(pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_shop')), :'so_shop'::uuid), '/', 1) = split_part(pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_shop')), :'so_shop'::uuid), '/', 2)
  and jsonb_array_length(pg_temp.lines(pg_temp.j(:'n_shop'))) >= 1,
  format('match %s | lines %s', pg_temp.so_match(pg_temp.lines(pg_temp.j(:'n_shop')), :'so_shop'::uuid), pg_temp.lines(pg_temp.j(:'n_shop'))::text));
\if :{?mig}
select pg_temp.chk('T2b·T3b 시험에서만: SO-20841b · Shopify SO 출력이 적용 전과 같다(doc.printed_at 만 떼고 글자 그대로 — 시스템 줄은 한 글자도 안 바뀐다)',
  :has_disc = 1 and :has_shop = 1 and pg_temp.strip_doc(pg_temp.j(:'n_disc')) = pg_temp.strip_doc(pg_temp.j(:'o_disc')) and pg_temp.strip_doc(pg_temp.j(:'n_shop')) = pg_temp.strip_doc(pg_temp.j(:'o_shop')),
  format('disc %s=%s | shop %s=%s', left(md5(pg_temp.strip_doc(pg_temp.j(:'o_disc'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'n_disc'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'o_shop'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'n_shop'))::text), 8)));
\endif
-- ── T4 발행 인보이스 60023(Shopify 20 줄) · 60024(손님 8 줄) · internal_receipt 60024: 제품 줄 전부 so_invoice_line 의 정가 · 할인 꼴(손 줄 없음 · 발행 인보이스에 손 가격 줄 0 장) ──
select pg_temp.chk('T4 final_invoice 60023(Shopify 20 줄) · 60024(손님 8 줄) · internal_receipt 60024: 줄 수 20 · 8 · 8 · 모든 제품 줄 list_price = 정가 꼴 · discount_pct = 할인 꼴(so_invoice_line 대조)' || case when :{?mig} then ' · 시험: 셋 다 옛 = 새(시각만 떼고 글자 그대로)' else '' end,
  :has_inv = 1 and jsonb_array_length(pg_temp.lines(pg_temp.j(:'n_is'))) = 20 and jsonb_array_length(pg_temp.lines(pg_temp.j(:'n_ic'))) = 8 and jsonb_array_length(pg_temp.lines(pg_temp.j(:'n_ir'))) = 8
  and pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_is')), :'inv_shop'::uuid) = '20/20' and pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_ic')), :'inv_cust'::uuid) = '8/8' and pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_ir')), :'inv_cust'::uuid) = '8/8',
  format('is %s | ic %s | ir %s', pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_is')), :'inv_shop'::uuid), pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_ic')), :'inv_cust'::uuid), pg_temp.inv_match(pg_temp.lines(pg_temp.j(:'n_ir')), :'inv_cust'::uuid)));
\if :{?mig}
select pg_temp.chk('T4b 시험에서만: 60023 · 60024 · internal_receipt 60024 출력이 적용 전과 같다(doc.printed_at 만 떼고 글자 그대로)',
  :has_inv = 1 and pg_temp.strip_doc(pg_temp.j(:'n_is')) = pg_temp.strip_doc(pg_temp.j(:'o_is')) and pg_temp.strip_doc(pg_temp.j(:'n_ic')) = pg_temp.strip_doc(pg_temp.j(:'o_ic')) and pg_temp.strip_doc(pg_temp.j(:'n_ir')) = pg_temp.strip_doc(pg_temp.j(:'o_ir')),
  format('is %s=%s | ic %s=%s | ir %s=%s', left(md5(pg_temp.strip_doc(pg_temp.j(:'o_is'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'n_is'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'o_ic'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'n_ic'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'o_ir'))::text), 8), left(md5(pg_temp.strip_doc(pg_temp.j(:'n_ir'))::text), 8)));
\endif
-- ── T5 CR-01008(issued · Shopify 0 % 두 줄 · 인보이스 줄 있음): 제품 줄 = 인보이스 줄의 정가 · 할인 꼴 → 「2.99 · (빈칸) · 5.98」 ──
select pg_temp.chk('T5 CR-01008(issued · RON02584 · RON02322 2 × 2.99 · 인보이스 줄 Shopify 0 %): 줄 2 · 둘 다 list_price "2.99"(빈칸 아님) · discount_pct "" · amount "5.98" · unit_price "2.99" · is_free false · charges · totals 는 그대로' || case when :{?mig} then ' · 시험: 옛 = 새(줄의 list_price · discount_pct · is_free · 시각만 떼고)' else '' end,
  :has_cr = 1 and (select count(*) = 2 and bool_and((l->>'list_price') = '2.99' and (l->>'discount_pct') = '' and (l->>'amount') = '5.98' and (l->>'unit_price') = '2.99' and (l->>'is_free')::boolean = false) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_cr'))) l),
  format('lines %s', pg_temp.lines(pg_temp.j(:'n_cr'))::text));
select 'T5-실물 CR-01008 줄 ' || (l->>'no') || ': ' || pg_temp.row3(l) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'n_cr'))) l order by (l->>'no')::int;
\if :{?mig}
select pg_temp.chk('T5b 시험에서만: CR-01008 옛 = 새 — 줄의 list_price("" → "2.99") 밖에 다르지 않다(discount_pct · is_free 도 같다 · totals · charges · refunds 같음 · 열쇠 집합 같음)',
  :has_cr = 1 and pg_temp.strip_cells(pg_temp.j(:'n_cr')) = pg_temp.strip_cells(pg_temp.j(:'o_cr'))
  and (select bool_and((l->>'discount_pct') = '' and (l->>'is_free')::boolean = false) from jsonb_array_elements(pg_temp.lines(pg_temp.j(:'o_cr'))) l)
  and (pg_temp.j(:'n_cr')->'docs'->0->'totals') = (pg_temp.j(:'o_cr')->'docs'->0->'totals') and (pg_temp.j(:'n_cr')->'docs'->0->'charges') = (pg_temp.j(:'o_cr')->'docs'->0->'charges')
  and pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0) = pg_temp.pset(pg_temp.j(:'o_cr')->'docs'->0),
  format('old lines %s | new lines %s', pg_temp.lines(pg_temp.j(:'o_cr'))::text, pg_temp.lines(pg_temp.j(:'n_cr'))::text));
\endif
-- ── T6 판별식 = price_override — 모든 so_line(구성품 · 무상 · 가격 없음 제외) · 모든 so_invoice_line 제품 줄(so_line 조인) ──
select (select count(*) from public.so_line l where l.combo_line_id is null and l.free_reason is null and l.unit_price is not null and (coalesce(public.so_line_manual(l), false) and l.discount_pct is null) <> coalesce(l.price_override, false)) as bad_sl,
       (select count(*) from public.so_line l where l.combo_line_id is null and l.free_reason is null and l.unit_price is not null) as n_sl,
       (select count(*) from public.so_invoice_line il join public.so_line sl on sl.id = il.so_line_id where il.kind = 'product' and sl.free_reason is null and il.unit_price is not null and (coalesce(public.so_line_manual(sl), false) and il.discount_pct is null) <> coalesce(sl.price_override, false)) as bad_il,
       (select count(*) from public.so_invoice_line il join public.so_line sl on sl.id = il.so_line_id where il.kind = 'product' and sl.free_reason is null and il.unit_price is not null) as n_il,
       (select count(*) from public.so_line l where coalesce(l.price_override, false) and l.free_reason is null and l.combo_line_id is null and l.discount_pct is null and l.discount_source is null) as n_hand_ok \gset
select pg_temp.chk('T6 판별식(manual ∧ discount_pct is null) = price_override — 모든 so_line(구성품 · 무상 · 가격 없음 제외 · ' || :n_sl || ' 줄) 어긋남 0 · 모든 so_invoice_line 제품 줄(so_line 조인 · ' || :n_il || ' 줄) 어긋남 0 · 손 가격 줄 ' || :n_hand_head || ' 은 전부 source · pct null(CHECK 의 결)',
  :bad_sl = 0 and :bad_il = 0 and :n_hand_ok = :n_hand_head and :n_sl > 1000 and :n_il > 100,
  format('bad so_line %s / %s · bad so_invoice_line %s / %s · hand ok %s / %s', :bad_sl, :n_sl, :bad_il, :n_il, :n_hand_ok, :n_hand_head));
-- ── T7 열쇠 — 출력 열쇠 집합은 kind 마다 그대로(카탈로그 무변 · 카탈로그 ↔ 출력 대조 무변) ──
select pg_temp.chk('T7 열쇠: sales_order · credit_note · final_invoice 출력 열쇠에 list_price · discount_pct · unit_price · net_unit_price 가 그대로 있고 새 열쇠(hand · display_*) 없음 · 카탈로그 다섯 kind md5 = 7b8e242a(doc-sr-1 · 무변)' || case when :{?mig} then ' · 시험: 열쇠 집합 옛 = 새(셋)' else '' end,
  pg_temp.pset(pg_temp.j(:'n_hand')->'docs'->0) @> array['lines.list_price', 'lines.discount_pct', 'lines.unit_price', 'lines.net_unit_price']
  and pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0) @> array['lines.list_price', 'lines.discount_pct', 'lines.unit_price', 'lines.net_unit_price']
  and pg_temp.pset(pg_temp.j(:'n_is')->'docs'->0) @> array['orders.lines.list_price', 'orders.lines.discount_pct', 'orders.lines.unit_price', 'orders.lines.net_unit_price']
  and not exists (select 1 from unnest(pg_temp.pset(pg_temp.j(:'n_hand')->'docs'->0) || pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0) || pg_temp.pset(pg_temp.j(:'n_is')->'docs'->0)) k where k ~ '(hand|display_|manual)')
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = '7b8e242a8aa48ee66986e75758395c5e',
  format('hand keys %s', pg_temp.pset(pg_temp.j(:'n_hand')->'docs'->0)::text));
\if :{?mig}
select pg_temp.chk('T7b 시험에서만: 열쇠 집합 옛 = 새 — SO-20843 · CR-01008 · 60023',
  pg_temp.pset(pg_temp.j(:'n_hand')->'docs'->0) = pg_temp.pset(pg_temp.j(:'o_hand')->'docs'->0) and pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0) = pg_temp.pset(pg_temp.j(:'o_cr')->'docs'->0) and pg_temp.pset(pg_temp.j(:'n_is')->'docs'->0) = pg_temp.pset(pg_temp.j(:'o_is')->'docs'->0),
  format('old %s | new %s', pg_temp.pset(pg_temp.j(:'o_cr')->'docs'->0)::text, pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0)::text));
\endif
-- ── D 그리기 직접 · 진리표 · 판 검사 ──
select pg_temp.chk('D1 doc_price_cells 진리표: 손(21.59 · null · 16.17 · manual) → 16.17 · "" | 손님 7 %(10.69 · 7 · 9.9417) → 10.69 · 7% | Shopify 0 %(2.99 · 0 · manual) → 2.99 · "" | 손 할인 25 %(manual · 25) → 21.59 · 25% | 무상(10 · null · 0 · manual · free) → 10.00 · "" | 가격 없음(5 · null · null) → 5.00 · "" | 정가 없는 손 줄(null · null · 16.17 · manual) → 16.17 · "" | manual null → 정가',
  public.doc_price_cells(21.59, null, 16.17, true, false) = '{"list_price": "16.17", "discount_pct": ""}'::jsonb
  and public.doc_price_cells(10.69, 7, 9.9417, false, false) = '{"list_price": "10.69", "discount_pct": "7%"}'::jsonb
  and public.doc_price_cells(2.99, 0, 2.99, true, false) = '{"list_price": "2.99", "discount_pct": ""}'::jsonb
  and public.doc_price_cells(21.59, 25, 16.1925, true, false) = '{"list_price": "21.59", "discount_pct": "25%"}'::jsonb
  and public.doc_price_cells(10, null, 0, true, true) = '{"list_price": "10.00", "discount_pct": ""}'::jsonb
  and public.doc_price_cells(5, null, null, false, false) = '{"list_price": "5.00", "discount_pct": ""}'::jsonb
  and public.doc_price_cells(null, null, 16.17, true, false) = '{"list_price": "16.17", "discount_pct": ""}'::jsonb
  and public.doc_price_cells(21.59, null, 16.17, null, null) = '{"list_price": "21.59", "discount_pct": ""}'::jsonb,
  format('%s %s %s %s %s', public.doc_price_cells(21.59, null, 16.17, true, false)::text, public.doc_price_cells(10.69, 7, 9.9417, false, false)::text, public.doc_price_cells(2.99, 0, 2.99, true, false)::text, public.doc_price_cells(10, null, 0, true, true)::text, public.doc_price_cells(5, null, null, false, false)::text));
select public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
         '{"header":{},"charges":[],"payments":[],"totals":{"total":10,"amount_due":10},"orders":[{"so_number":"SO-1","order_discount_pct":10,"lines":[
            {"sku":"H","qty":12,"list_price":21.59,"discount_pct":null,"unit_price":16.17,"amount":194.04,"tax_amount":0,"is_free":false,"no_price":false,"manual":true},
            {"sku":"C","qty":3,"list_price":10.69,"discount_pct":7,"unit_price":9.9417,"amount":29.83,"tax_amount":0,"is_free":false,"no_price":false,"manual":false},
            {"sku":"S","qty":2,"list_price":2.99,"discount_pct":0,"unit_price":2.99,"amount":5.98,"tax_amount":0,"is_free":false,"no_price":false,"manual":true},
            {"sku":"F","qty":1,"list_price":10,"discount_pct":null,"unit_price":0,"amount":0,"tax_amount":0,"is_free":true,"no_price":false,"manual":true},
            {"sku":"N","qty":1,"list_price":5,"discount_pct":null,"unit_price":null,"amount":null,"tax_amount":0,"is_free":false,"no_price":true,"manual":false}]}]}'::jsonb)::text as d_fmt \gset
select pg_temp.chk('D2 그리기 직접(postgres · 중립 jsonb · ship_ready · 오더 할인 10 %): 손 줄 16.17 · "" · unit 16.17 · net ""(손 줄은 오더 할인 몫 0 · od-1) | 손님 줄 10.69 · 7% · unit 9.94 · net 8.95 | Shopify 줄 2.99 · "" · net "" | 무상 줄 10.00 · "" · unit 0.00 · is_free | 가격 없음 5.00 · "" · unit "" · no_price | 줄 열쇠 16 그대로',
  (select jsonb_array_length(l) = 5
     and (l->0->>'list_price') = '16.17' and (l->0->>'discount_pct') = '' and (l->0->>'unit_price') = '16.17' and (l->0->>'net_unit_price') = '' and (l->0->>'amount') = '194.04'
     and (l->1->>'list_price') = '10.69' and (l->1->>'discount_pct') = '7%' and (l->1->>'unit_price') = '9.94' and (l->1->>'net_unit_price') = '8.95'
     and (l->2->>'list_price') = '2.99' and (l->2->>'discount_pct') = '' and (l->2->>'unit_price') = '2.99' and (l->2->>'net_unit_price') = ''
     and (l->3->>'list_price') = '10.00' and (l->3->>'discount_pct') = '' and (l->3->>'unit_price') = '0.00' and (l->3->>'is_free')::boolean
     and (l->4->>'list_price') = '5.00' and (l->4->>'discount_pct') = '' and (l->4->>'unit_price') = '' and (l->4->>'no_price')::boolean
     and (select array_agg(k order by k) from jsonb_object_keys(l->0) k) = array['amount', 'comment', 'description', 'discount_pct', 'final_sale', 'is_free', 'list_price', 'net_unit_price', 'no', 'no_price', 'qty', 'sku', 'tax_amount', 'unit', 'unit_price', 'upc']
   from (select pg_temp.j(:'d_fmt')->'orders'->0->'lines' as l) t),
  (pg_temp.j(:'d_fmt')->'orders'->0->'lines')::text);
select body as v_tpl_so from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'sales_order') \gset
select body as v_tpl_cr from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'credit_note') \gset
select body as v_tpl_fi from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice') \gset
select pg_temp.chk('D3 판 무변: 쓰는 판 sales_order v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'sales_order')) || ' · credit_note v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'credit_note')) || ' · final_invoice v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice')) || ' 이 doc_template_check 를 여전히 통과 · 셋 다 제품 줄 단가 칸에 {{list_price}} · 할인 칸에 {{discount_pct}} 를 찍는다(그래서 doc_data 만 고치면 종이가 바뀐다)',
  (public.doc_template_check('sales_order', :'v_tpl_so', 'template')->>'ok')::boolean and (public.doc_template_check('credit_note', :'v_tpl_cr', 'template')->>'ok')::boolean and (public.doc_template_check('final_invoice', :'v_tpl_fi', 'template')->>'ok')::boolean
  and :'v_tpl_so' ~ '\{\{\^no_price\}\}\{\{list_price\}\}\{\{/no_price\}\}' and :'v_tpl_cr' ~ '\{\{\^no_price\}\}\{\{list_price\}\}\{\{/no_price\}\}' and :'v_tpl_fi' ~ '\{\{\^no_price\}\}\{\{list_price\}\}\{\{/no_price\}\}'
  and (select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) from public.doc_template_active t) = :'snap_ta',
  format('so %s | cr %s | fi %s', left(public.doc_template_check('sales_order', :'v_tpl_so', 'template')::text, 100), left(public.doc_template_check('credit_note', :'v_tpl_cr', 'template')::text, 100), left(public.doc_template_check('final_invoice', :'v_tpl_fi', 'template')::text, 100)));
select pg_temp.chk('L1 함수 모양(새 판): fmt · so · credit STABLE · doc_price_cells IMMUTABLE · 셋의 ACL 머리와 같다(service 만 · authenticated · anon 못 부른다) · doc_price_cells 도 service 만 · comment 넷에 976 · 함수 하나씩',
  (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 's' and (select provolatile from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) = 's' and (select provolatile from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)'::regprocedure) = 'i'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') = :'fmt_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '(none)') = :'so_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure), '(none)') = :'cr_acl_head'
  and not has_function_privilege('authenticated', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute') and not has_function_privilege('anon', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute') and has_function_privilege('service_role', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.doc_data_so(uuid, jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.doc_data_credit(uuid, jsonb)', 'execute')
  and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '976' and obj_description('public.doc_data_so(uuid, jsonb)'::regprocedure, 'pg_proc') ~ '976' and obj_description('public.doc_data_credit(uuid, jsonb)'::regprocedure, 'pg_proc') ~ '976' and obj_description('public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)'::regprocedure, 'pg_proc') ~ '976'
  and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '874'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_data_so', 'doc_data_credit', 'doc_price_cells') and pronamespace = 'public'::regnamespace) = 4,
  format('fmt acl %s | so acl %s | cr acl %s | cells acl %s', (select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)'::regprocedure)));
-- ── T8 REST 첫 겹(정적): 다시 낸 함수 몸에 update · delete 문이 있는가 ──
select (select count(*) from pg_proc where oid in ('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'public.doc_data_so(uuid, jsonb)'::regprocedure, 'public.doc_data_credit(uuid, jsonb)'::regprocedure, 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)'::regprocedure) and prosrc ~* '(^|[\s;])(update|delete|insert)\s') as n_ud \gset
select pg_temp.chk('T8 REST 첫 겹(정적): 다시 낸 넷의 몸에 update · delete · insert 문 0 → WHERE 깊이 검사 해당 없음(전부 읽기만)', :n_ud = 0, format('쓰기 문이 있는 함수 %s', :n_ud));
\endif
-- ── Z 무접촉 ──
select pg_temp.chk('Z1 무접촉: doc_data_invoice(5fcac178) · so_invoice_preview(6a36efcb) · doc_data_ship_ready(446fa345) · doc_field_catalog(7b8e242a) · doc_data(400358fa) · doc_template_check(26b1075a) · doc_unit_prices(6b3f5387) · so_line_manual(47eef933) · so_proforma(93b5fcaf) · 쓰는 판 다섯 · so_line · so_invoice_line · so_credit_line 가격 칸 스냅샷 머리와 같다',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) = '5fcac178ab84816f339e1b8c6b9a82dd'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) = '6a36efcbd4de5f06cb4d818ab12233ab'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_ship_ready(jsonb, jsonb)'::regprocedure) = '446fa345c99b64ba39ed0d67bdceeaac'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = '7b8e242a8aa48ee66986e75758395c5e'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data(text, jsonb)'::regprocedure) = '400358fa6e488d514039cdc9705e6d39'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_template_check(text, text, text)'::regprocedure) = '26b1075a117087a42a061531c785f821'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_unit_prices(numeric, numeric, text)'::regprocedure) = '6b3f53876150837a43615f59b0a8172b'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_line_manual(so_line)'::regprocedure) = '47eef933952c63162d0e3e5c29736811'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_proforma(uuid[])'::regprocedure) = '93b5fcaf3789cba10c9e6b267e296673'
  and (select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) from public.doc_template_active t) = :'snap_ta'
  and (select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.list_price::text, '') || ':' || coalesce(t.discount_pct::text, '') || ':' || coalesce(t.unit_price::text, '') || ':' || t.price_override::text || ':' || coalesce(t.discount_source, ''), '|' order by t.id), '')) || ' ' || count(*) from public.so_line t) = :'snap_sl'
  and (select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.list_price::text, '') || ':' || coalesce(t.discount_pct::text, '') || ':' || coalesce(t.unit_price::text, ''), '|' order by t.id), '')) || ' ' || count(*) from public.so_invoice_line t) = :'snap_il'
  and (select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.unit_price::text, '') || ':' || coalesce(t.amount::text, ''), '|' order by t.id), '')) || ' ' || count(*) from public.so_credit_line t) = :'snap_cl',
  format('inv %s pv %s cat %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- ── rollback 뒤 — 가짜 흔적 0 · 함수 판 머리 그대로 ──
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('Z2 rollback 뒤: 가짜 직원 0 · 직원 수 그대로 · fmt · so · credit md5 머리 그대로' || case when :{?mig} then ' · doc_price_cells 없음(시험은 되돌아갔다)' else '' end,
  (select count(*) from public.ims_staff where email like 'dochp1-%') = 0 and (select count(*) from public.ims_staff) = :n_staff_head
  and coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace), '(none)') = :'fmt_md5_head'
  and coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_so' and pronamespace = 'public'::regnamespace), '(none)') = :'so_md5_head'
  and coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_credit' and pronamespace = 'public'::regnamespace), '(none)') = :'cr_md5_head'
  and (not (:{?mig}) or not exists (select 1 from pg_proc where proname = 'doc_price_cells' and pronamespace = 'public'::regnamespace)),
  format('staff %s | fmt %s', (select count(*) from public.ims_staff where email like 'dochp1-%'), (select left(md5(prosrc), 8) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace)));
\pset tuples_only off
\pset format aligned
-- 기대 OK: 시험(-v mig) 22(O1 G1 N0 T1 T1b T2 T3 T2b·T3b T4 T4b T5 T5b T6 T7 T7b D1 D2 D3 L1 T8 Z1 Z2) · MISMATCH 0 · begin ~ rollback 1.5 초 안팎
--          확인 실행(적용 뒤) 16(G0 N0 T1 T2 T3 T4 T5 T6 T7 D1 D2 D3 L1 T8 Z1 Z2) · 시험 전용 7(O1 G1 T1b T2b·T3b T4b T5b T7b)은 돌지 않는다
--   실측 2026-11-02(Claude Code · 시험 3 회차 · 사이 띄움 · 전부 rollback): OK 22 · MISMATCH 0 × 3 · begin ~ rollback 1.51 s · 1.97 s · 1.74 s
