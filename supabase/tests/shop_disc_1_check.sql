-- supabase/tests/shop_disc_1_check.sql — shop-disc-1 asung.ca 웹 줄 할인 반올림을 들여올 때 IMS 셈으로 (2026-11-03 · 판정 996 · 999 · 1001 ~ 1008 · 이견 1 ~ 12)
-- [테스트 · Asung-IMS = IMS 메인(617) · ⚠️ 운영 · 창고 시간] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5) → begin → 옛 prosrc 담기 → (-v mig 면 \i)
--   → A(① 식 진리표) → R(실물 raw 재생 · 가짜 gid: SO-20856 · AS-6971 · SO-20002 · SO-20855 · 이견 1 의 6.29 꼴 한 줄 · 기대값은 파일 안에서 셈)
--   → C(② 창구: 거부 8 · 30 분 손 안 댄 picking · packed 실물 줄에서 섬(없으면 SKIP) · 멱등 · 수량 · 예약 Σ 무변 · updated_by = 시스템 직원 · authenticated 42501)
--   → D(재발행 diff · 시험 갈래만) → G(aone 한 장 옛 = 새 · 시험 갈래만) → E(nowhere 정적) → F(권한 · 무변 md5 · comment) → rollback → Z1 시험 흔적 0(행 수는 정보 · 창고 시간엔 움직인다) · Z2 md5 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103080000_shop_disc_1_web_discount_rule.sql -f supabase/tests/shop_disc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 39 · 확인(적용 뒤) 34 — D0 ~ D2 · G1 · G2 는 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   쓰기 0 — 재생 SO · 초안 · 실물 줄 고침은 전부 rollback · SO 번호 시퀀스는 so_create 가 당긴다(번호 구멍 일곱 · 앞 차수와 같다)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다) · ② 를 부르는 실물 오더(창고가 30 분 안 만진 것 · \echo 로 찍힘)는 ② 부터 rollback 까지 잠긴다(끝에 lock_info) · 돌리기 직전에 Caleb 에게 묻는다
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 39
\else
\set EXPECT_OK 34
\endif
\pset pager off
select (select count(*) from public.shop_order) as n_ord0, (select count(*) from public.shop_order_line) as n_oline0, (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0,
       (select count(*) from public.so_reserve) as n_res0, (select count(*) from public.so_payment) as n_pay0, (select count(*) from public.so_invoice_order) as n_inv0,
       (select md5(prosrc) from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure) as proc_md5_0,
       (select md5(prosrc) from pg_proc where oid = 'public.so_line_set_shopify(uuid, numeric, numeric)'::regprocedure) as set_md5_0,
       (select md5(prosrc) from pg_proc where oid = 'public.so_line_quote(public.so, uuid, numeric)'::regprocedure) as quote_md5_0,
       (select md5(prosrc) from pg_proc where oid = 'public.so_line_bgrade_guard()'::regprocedure) as bg_md5_0 \gset
\echo '── 기준: shop_order' :n_ord0 '· so' :n_so0 '· so_line' :n_line0 '· so_reserve' :n_res0 '· shop_order_process md5' :proc_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5, array_length(string_to_array(prosrc, E'\n'), 1) as n_lines from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미(shop_cut_1_check 그대로) ──
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
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end; $$;
create function pg_temp.ing(p_store uuid, p_order jsonb) returns text language sql as $$ select pg_temp.run(format('select public.shop_order_ingest(%L::uuid, %L::jsonb)::text', p_store, p_order)); $$;
create function pg_temp.proc(p_id text) returns text language sql as $$ select pg_temp.run(format('select public.shop_order_process(%L::uuid)::text', p_id)); $$;
create function pg_temp.rule(p_line text, p_pct text) returns text language sql as $$ select pg_temp.run(format('select to_jsonb(public.so_line_set_shopify_rule(%L::uuid, %s))::text', p_line, p_pct)); $$;
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
-- 실물 raw 재생 — 같은 스토어 · 가짜 gid 930000000NNN · 이름 DISC1-TNNNN · p_patch 로 raw 를 덮고 p_strip 열쇠를 뺀다(totalTaxSet 없으면 ⑥ 세금 대조 없음) → ingest → process · 결과 jsonb 글
create function pg_temp.gid(p_n int) returns text language sql as $$ select 'gid://shopify/Order/930000000' || lpad(p_n::text, 3, '0'); $$;
create function pg_temp.replay(p_name text, p_n int, p_patch jsonb default '{}'::jsonb, p_strip text default null) returns text language plpgsql as $$
declare v_o public.shop_order%rowtype; v_raw jsonb; v_res text; v_id text;
begin
  select o.* into v_o from public.shop_order o join public.shop_store s on s.id = o.store_id where o.name = p_name and s.code in ('asung', 'aone') order by o.shopify_created_at desc limit 1;
  if v_o.id is null then return 'ERR no real order ' || p_name; end if;
  v_raw := v_o.raw || jsonb_build_object('id', pg_temp.gid(p_n), 'name', 'DISC1-T' || lpad(p_n::text, 4, '0')) || p_patch;
  if p_strip is not null then v_raw := v_raw - p_strip; end if;
  v_res := pg_temp.ing(v_o.store_id, v_raw);
  v_id := pg_temp.j(v_res)->>'shop_order_id';
  if v_id is null then return 'ERR ingest: ' || left(v_res, 300); end if;
  return pg_temp.proc(v_id);
end $$;
-- 줄 하나의 Shopify 원문 노드(실물 노드 꼴 · 앱 할인 없음)
create function pg_temp.node(p_sku text, p_qty numeric, p_list text, p_unit text) returns jsonb language sql as $$
  select jsonb_build_object('id', 'gid://shopify/LineItem/93000000001', 'sku', p_sku, 'name', 'Item ' || p_sku, 'quantity', p_qty, 'currentQuantity', p_qty, 'discountAllocations', '[]'::jsonb, 'taxLines', '[]'::jsonb,
                            'originalUnitPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_list, 'currencyCode', 'CAD')),
                            'discountedUnitPriceAfterAllDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', p_unit, 'currencyCode', 'CAD')),
                            'totalDiscountSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char((p_list::numeric - p_unit::numeric) * p_qty, 'FM999999990.00'), 'currencyCode', 'CAD')));
$$;
-- 재생된 오더의 줄마다 기대값(파일 안에서 셈 · ① 함수에 기대지 않는 식) ↔ 실제
--   fit = round(Shopify 정가 × (1 − p/100), 2) = Shopify 단가 · fix_exp = fit ∧ 정가 같음 ∧ (지금 % ≠ p ∨ 단가 ≠ 정가 × (1 − p/100)) · 기대 % · 단가 · 줄 금액 · line_diff = IMS 금액 − Shopify 금액
create function pg_temp.lines(p_gid text) returns table (line_no int, sku text, qty numeric, s_list numeric, s_unit numeric, s_pct numeric, p numeric, q_list numeric, fit boolean, fix_exp boolean,
                                                           exp_pct numeric, exp_unit numeric, got_pct numeric, got_unit numeric, got_src text, got_qty numeric, exp_total numeric, got_total numeric, line_diff numeric, upd_by uuid, ok boolean)
language sql as $$
  with b as (
    select sol.line_no, sol.sku, sol.quantity as qty, sol.list_price as s_list, sol.unit_price as s_unit,
           case when coalesce(sol.list_price, 0) > 0 then greatest(0, least(100, round((sol.list_price - coalesce(sol.unit_price, 0)) / sol.list_price * 100, 2))) else 0 end as s_pct,
           coalesce(q.discount_pct, 0) as p, q.list_price as q_list, l.discount_pct as got_pct, l.unit_price as got_unit, l.discount_source as got_src, l.qty_ordered as got_qty, public.so_line_total(l) as got_total, l.updated_by as upd_by
    from public.shop_order o join public.shop_order_line sol on sol.shop_order_id = o.id join public.so_line l on l.id = sol.so_line_id join public.so s on s.id = l.so_id
    cross join lateral public.so_line_quote(s, l.product_id, sol.quantity) q
    where o.shopify_order_gid = p_gid and sol.match = 'ok'
  ), c as (
    select b.*, (b.s_list is not null and b.s_unit is not null and b.s_list > 0 and round(b.s_list * (1 - b.p / 100), 2) = round(b.s_unit, 2)) as fit from b
  ), d as (
    select c.*, (c.fit and c.q_list is not null and c.s_list is not null and abs(c.q_list - c.s_list) <= 0.005 and (c.s_pct <> c.p or round(c.s_unit, 7) <> round(c.s_list * (1 - c.p / 100), 7))) as fix_exp from c
  ), e as (
    select d.*, case when d.fix_exp then d.p else d.s_pct end as exp_pct, case when d.fix_exp then round(d.s_list * (1 - d.p / 100), 7) else round(coalesce(d.s_unit, 0), 7) end as exp_unit,
           round(d.qty * coalesce(d.s_list, 0) * (1 - d.p / 100), 2) - round(d.qty * coalesce(d.s_unit, 0), 2) as line_diff from d
  )
  select e.line_no, e.sku, e.qty, e.s_list, e.s_unit, e.s_pct, e.p, e.q_list, e.fit, e.fix_exp, e.exp_pct, e.exp_unit, e.got_pct, e.got_unit, e.got_src, e.got_qty,
         case when e.fix_exp then round(e.got_qty * e.s_list * (1 - e.p / 100), 2) else round(e.got_qty * coalesce(e.s_unit, 0), 2) end as exp_total, e.got_total, e.line_diff, e.upd_by,   -- 줄 금액은 지금 qty_ordered 로(so_confirm 이 재고 부족 줄을 나누면 준다 · p · line_diff 는 받은 수량)
         (e.got_pct = e.exp_pct and e.got_unit = e.exp_unit and e.got_src = 'shopify'
          and e.got_total = case when e.fix_exp then round(e.got_qty * e.s_list * (1 - e.p / 100), 2) else round(e.got_qty * coalesce(e.s_unit, 0), 2) end) as ok
  from e order by e.line_no;
$$;
-- 한 오더의 판정 글 — 실제(got) 와 기대(want) 를 같은 꼴로
create function pg_temp.got(p_gid text) returns text language sql as $$
  with o as (select o.*, s.status as so_status, s.order_discount_pct as od_pct, s.order_discount_source as od_src from public.shop_order o left join public.so s on s.id = o.so_id where o.shopify_order_gid = p_gid),
       w as (select w from o, jsonb_array_elements(o.warnings) w),
       r as (select w from w where w->>'code' = 'web_discount_rounded'),
       ln as (select * from pg_temp.lines(p_gid))
  select (select status from o) || '/' || (select so_status from o)
      || '/lines ' || (select count(*) from ln) || ' ok ' || (select count(*) filter (where ok) from ln)
      || '/fixed ' || (select count(*) filter (where fix_exp) from ln) || ' rounded ' || coalesce((select (w->>'lines') || ':' || jsonb_array_length(w->'detail') || ':' || (w->'settled_at' is not null)::text || ':' || (w->>'total_diff') from r), 'none')
      || '/mismatch ' || (select count(*) from w where w->>'code' = 'discount_mismatch') || ' keyed ' || (select count(*) from w where w->>'code' = 'discount_mismatch' and w ? 'shopify_unit' and w ? 'ims_unit' and w ? 'line_diff')
      || ' diffs ' || coalesce((select string_agg((w->>'line_no') || '=' || (w->>'line_diff'), ',' order by (w->>'line_no')::int) from w where w->>'code' = 'discount_mismatch'), '-')
      || '/detail ' || coalesce((select string_agg((d->>'line_no') || '=' || (d->>'line_diff') || '@' || (d->>'ims_unit'), ',' order by (d->>'line_no')::int) from r, jsonb_array_elements(r.w->'detail') d), '-')
      || '/tax ' || (select count(*) from w where w->>'code' = 'tax_mismatch') || '/list ' || (select count(*) from w where w->>'code' = 'list_price_mismatch')
      || '/od ' || coalesce((select od_pct::text || ' ' || od_src from o), 'null')
      || '/updby ' || coalesce((select string_agg(distinct coalesce(upd_by::text, 'null'), ',') from ln where fix_exp), '-');
$$;
create function pg_temp.want(p_gid text, p_sys uuid, p_tax int default 0) returns text language sql as $$
  with ln as (select * from pg_temp.lines(p_gid)), f as (select * from ln where fix_exp), m as (select * from ln where not fit)
  select 'created/confirmed'
      || '/lines ' || (select count(*) from ln) || ' ok ' || (select count(*) from ln)
      || '/fixed ' || (select count(*) from f) || ' rounded ' || case when (select count(*) from f) = 0 then 'none' else (select count(*) from f) || ':' || (select count(*) from f) || ':true:' || (select sum(line_diff) from f) end
      || '/mismatch ' || (select count(*) from m) || ' keyed ' || (select count(*) from m)
      || ' diffs ' || coalesce((select string_agg(line_no || '=' || line_diff, ',' order by line_no) from m), '-')
      || '/detail ' || coalesce((select string_agg(line_no || '=' || line_diff || '@' || exp_unit, ',' order by line_no) from f), '-')
      || '/tax ' || p_tax || '/list ' || (select count(*) from ln where q_list is not null and s_list is not null and abs(q_list - s_list) > 0.005)
      || '/od ' || case when exists (select 1 from public.shop_order o, jsonb_array_elements(o.warnings) w where o.shopify_order_gid = p_gid and w->>'code' = 'order_discount_dropped') then '0 manual' else 'null' end
      || '/updby ' || case when (select count(*) from f) = 0 then '-' else p_sys::text end;
$$;

-- ── 재료 ──
select id as s_asung from public.shop_store where code = 'asung' \gset
select id as s_aone from public.shop_store where code = 'aone' \gset
select s.id as sys_staff from public.ims_staff s where s.is_system and s.is_active order by s.created_at limit 1 \gset
select (select count(*) from public.so) as n_so_in \gset

-- ── A) ① 식 진리표 — 단가 꼴(보고서 이견 8 의 실물 둘 · 1 센트 줄 · null · 정가 0) ──
select pg_temp.chk('A1 fit: half-cent 50 % (10.99 → 5.50 · 4.89 → 2.45) true · 1-cent lines (6.49 → 6.03 · 24.99 → 23.23) false · 7 % (1.49 → 1.39 · 13.99 → 13.01) true · 20 % (1.19 → 0.95) true',
  public.shop_line_rule_fit(10.99, 5.50, 50)::text || public.shop_line_rule_fit(4.89, 2.45, 50)::text || public.shop_line_rule_fit(6.49, 6.03, 7)::text || public.shop_line_rule_fit(24.99, 23.23, 7)::text
  || public.shop_line_rule_fit(1.49, 1.39, 7)::text || public.shop_line_rule_fit(13.99, 13.01, 7)::text || public.shop_line_rule_fit(1.19, 0.95, 20)::text, 'truetruefalsefalsetruetruetrue');
select pg_temp.chk('A2 fit: null list · null unit · null pct · list 0 · pct 101 · pct −1 → all false · p 0 (list = unit) true · 6.29 → 5.85 @ 7 true (이견 1 꼴)',
  public.shop_line_rule_fit(null, 1.39, 7)::text || public.shop_line_rule_fit(1.49, null, 7)::text || public.shop_line_rule_fit(1.49, 1.39, null)::text || public.shop_line_rule_fit(0, 0, 7)::text
  || public.shop_line_rule_fit(1.49, 1.39, 101)::text || public.shop_line_rule_fit(1.49, 1.39, -1)::text || public.shop_line_rule_fit(7.89, 7.89, 0)::text || public.shop_line_rule_fit(6.29, 5.85, 7)::text, 'falsefalsefalsefalsefalsefalsetruetrue');
select pg_temp.chk('A3 fit is immutable · parallel safe · executable by authenticated, not anon', (select provolatile::text || proparallel::text from pg_proc where oid = 'public.shop_line_rule_fit(numeric, numeric, numeric)'::regprocedure)
  || '/' || has_function_privilege('authenticated', 'public.shop_line_rule_fit(numeric, numeric, numeric)', 'execute')::text || '/' || has_function_privilege('anon', 'public.shop_line_rule_fit(numeric, numeric, numeric)', 'execute')::text, 'is/true/false');

-- ── R) 실물 raw 재생(가짜 gid · rollback) — 기대값은 lines() 가 파일 안에서 셈 ──
select pg_temp.replay('AS-7402', 1) as r1 \gset
select pg_temp.chk('R1 SO-20856(AS-7402 · 7 % · 20 % 딜 · GUMMY 1 센트 줄): process result created · confirmed', coalesce(pg_temp.j(:'r1')->>'status', left(:'r1', 120)) || '/' || coalesce(pg_temp.j(:'r1')->>'confirmed', '-'), 'created/true');
select pg_temp.chk('R1b SO-20856 replay: every line = expected (fixed → p · list × (1 − p/100) · IMS total; out of range → Shopify kept + amount warning) · rounded element · tax 0 · od as ④ left it (null · 0 manual if a deal was dropped) · updated_by = system',
  pg_temp.got(pg_temp.gid(1)), pg_temp.want(pg_temp.gid(1), :'sys_staff'::uuid));
\echo '── R1 SO-20856 재생 줄(fix_exp · 범위 밖 · 기대 ↔ 실제)'
select line_no, sku, qty, s_list, s_unit, s_pct, p, fit, fix_exp, exp_pct, got_pct, exp_unit, got_unit, exp_total, got_total, line_diff, ok from pg_temp.lines(pg_temp.gid(1));
select pg_temp.replay('AS-6971', 2) as r2 \gset
select pg_temp.chk('R2 AS-6971(+0.60): created · confirmed', coalesce(pg_temp.j(:'r2')->>'status', left(:'r2', 120)) || '/' || coalesce(pg_temp.j(:'r2')->>'confirmed', '-'), 'created/true');
select pg_temp.chk('R2b AS-6971 replay: lines · rounded · warnings as expected', pg_temp.got(pg_temp.gid(2)), pg_temp.want(pg_temp.gid(2), :'sys_staff'::uuid));
select pg_temp.replay('AS-7328', 3) as r3 \gset
select pg_temp.chk('R3 SO-20002(AS-7328 · MAC00011 50 % 반 센트): created · confirmed', coalesce(pg_temp.j(:'r3')->>'status', left(:'r3', 120)) || '/' || coalesce(pg_temp.j(:'r3')->>'confirmed', '-'), 'created/true');
select pg_temp.chk('R3b SO-20002 replay: lines · rounded · warnings as expected', pg_temp.got(pg_temp.gid(3)), pg_temp.want(pg_temp.gid(3), :'sys_staff'::uuid));
select pg_temp.replay('AS-7401', 4) as r4 \gset
select pg_temp.chk('R4 SO-20855(AS-7401 · 1 센트 줄 · 46 줄): created · confirmed', coalesce(pg_temp.j(:'r4')->>'status', left(:'r4', 120)) || '/' || coalesce(pg_temp.j(:'r4')->>'confirmed', '-'), 'created/true');
select pg_temp.chk('R4b SO-20855 replay: lines · rounded · warnings as expected', pg_temp.got(pg_temp.gid(4)), pg_temp.want(pg_temp.gid(4), :'sys_staff'::uuid));
\echo '── R2 ~ R4 재생 요약(line_no · sku · fit · fix_exp · line_diff · ok)'
select 'R2' as r, line_no, sku, qty, s_list, s_unit, s_pct, p, fit, fix_exp, got_pct, got_unit, line_diff, ok from pg_temp.lines(pg_temp.gid(2))
union all select 'R3', line_no, sku, qty, s_list, s_unit, s_pct, p, fit, fix_exp, got_pct, got_unit, line_diff, ok from pg_temp.lines(pg_temp.gid(3))
union all select 'R4', line_no, sku, qty, s_list, s_unit, s_pct, p, fit, fix_exp, got_pct, got_unit, line_diff, ok from pg_temp.lines(pg_temp.gid(4)) where fix_exp or not fit order by 1, 2;
-- R5 이견 1 꼴 — SO-20855 손님(7 %) 에 ANN00377 6.29 × 3 · Shopify 단가 5.85(= round(6.29 × 0.93, 2) · % = round(0.44/6.29 × 100, 2) = 7.00 = p) 인데 단가 ≠ 5.8497 → 고쳐져야 한다 · totalTaxSet 을 빼서 세금 대조 없음
select pg_temp.replay('AS-7401', 5, jsonb_build_object('lineItems', jsonb_build_object('nodes', jsonb_build_array(pg_temp.node('ANN00377', 3, '6.29', '5.85')))), 'totalTaxSet') as r5 \gset
select pg_temp.chk('R5 이견 1: % equal to p but unit differs (6.29 · 7 % · 5.85 vs 5.8497) → fixed', coalesce(pg_temp.j(:'r5')->>'status', left(:'r5', 120)) || '/' || (select s_pct || '=' || p || '/' || fit || '/' || fix_exp || '/' || got_unit || '/' || ok from pg_temp.lines(pg_temp.gid(5))), 'created/7.00=7/true/true/5.8497000/true');
select pg_temp.chk('R5b 이견 1 order: rounded element lines 1 · total_diff 0.00 · no discount_mismatch · no tax check', pg_temp.got(pg_temp.gid(5)), pg_temp.want(pg_temp.gid(5), :'sys_staff'::uuid));
select pg_temp.chk('R0 replays made 5 root SOs (ref DISC1-T · not split) · 5 shop_orders created with so_id', (select count(*) from public.so where ref like 'DISC1-T%' and split_from_id is null)::text || '/' || (select count(*) from public.shop_order where shopify_order_gid in (pg_temp.gid(1), pg_temp.gid(2), pg_temp.gid(3), pg_temp.gid(4), pg_temp.gid(5)) and status = 'created' and so_id is not null), '5/5');
select pg_temp.chk('R6 split backorder SOs (so_confirm stock-short · after ⑥-b) carry the values: moved lines (same id · linked from shop_order_line · checked in R1b~R5b) source shopify · total = round(qty × unit) · copied lines (split_from_line_id) pct · unit · list · source = origin · components unit 0 · pct null',
  (with ch as (select c.* from public.so s join public.so p on p.id = s.split_from_id join public.so_line c on c.so_id = s.id where p.ref like 'DISC1-T%'),
        k as (select case when ch.combo_line_id is not null then 'component' when ch.split_from_line_id is not null then 'copied' else 'moved' end as kind,
                     case when ch.combo_line_id is not null then (ch.unit_price = 0 and ch.discount_pct is null and ch.discount_source is null)
                          when ch.split_from_line_id is not null then exists (select 1 from public.so_line o where o.id = ch.split_from_line_id and o.discount_pct is not distinct from ch.discount_pct and o.unit_price = ch.unit_price and o.list_price is not distinct from ch.list_price and o.discount_source = 'shopify' and ch.discount_source = 'shopify')
                          else (ch.discount_source = 'shopify' and exists (select 1 from public.shop_order_line sol join public.shop_order o on o.id = sol.shop_order_id where sol.so_line_id = ch.id and o.shopify_order_gid like 'gid://shopify/Order/930000000%')) end
                     and public.so_line_total(ch) = round(ch.qty_ordered * ch.unit_price, 2) as ok
              from ch)
   select 'moved ' || count(*) filter (where kind = 'moved') || '/' || count(*) filter (where kind = 'moved' and ok) || ' · copied ' || count(*) filter (where kind = 'copied') || '/' || count(*) filter (where kind = 'copied' and ok)
       || ' · component ' || count(*) filter (where kind = 'component') || '/' || count(*) filter (where kind = 'component' and ok) from k),
  (with ch as (select c.* from public.so s join public.so p on p.id = s.split_from_id join public.so_line c on c.so_id = s.id where p.ref like 'DISC1-T%')
   select 'moved ' || count(*) filter (where combo_line_id is null and split_from_line_id is null) || '/' || count(*) filter (where combo_line_id is null and split_from_line_id is null)
       || ' · copied ' || count(*) filter (where combo_line_id is null and split_from_line_id is not null) || '/' || count(*) filter (where combo_line_id is null and split_from_line_id is not null)
       || ' · component ' || count(*) filter (where combo_line_id is not null) || '/' || count(*) filter (where combo_line_id is not null) from ch));
\echo '── R6 나눔 줄(자식 ↔ 원 줄)'
select s.so_number, c.line_no, c.sku, c.qty_ordered, c.discount_pct, c.unit_price, o.discount_pct as o_pct, o.unit_price as o_unit, o.qty_ordered as o_qty from public.so s join public.so p on p.id = s.split_from_id join public.so_line c on c.so_id = s.id left join public.so_line o on o.id = c.split_from_line_id where p.ref like 'DISC1-T%' order by 1, 2;
\echo '── R0 so_confirm 의 재고 부족 나눔(rollback · 정보)'
select s.so_number, s.status, s.split_reason, p.so_number as parent, (select count(*) from public.so_line l where l.so_id = s.id) as n_lines from public.so s join public.so p on p.id = s.split_from_id where p.ref like 'DISC1-T%' order by 1;

-- ── C) ② 창구 — 시스템 신원(shop_system_enter · 트랜잭션 끝까지) · 거부 8 · picking · packed 줄에서 섬 · 멱등 · 무접촉 · 42501 ──
--   C9 · C10 의 실물 오더 = 지금 창고가 만지지 않는 것만: 상태 picking · packed ∧ 유효 인보이스 없음 ∧ shopify 줄(구성품 · 무상 아님) ∧ 그 오더 · 줄 · so_reserve · WMS 과제(pick · pack · 과제 줄 · 팔레트)에 최근 30 분 손댄 흔적 없음 · 가장 오래 쉰 것부터 · 없으면 SKIP
select public.shop_system_enter() as prev_claims \gset
create function pg_temp.quiet(p_status text) returns table (so_number text, line_id uuid, qty numeric, list numeric, p numeric, last_touch timestamptz) language sql as $$
  with cand as (
    select s.id, s.so_number,
           greatest(s.updated_at, s.created_at,
                    coalesce((select max(greatest(l.updated_at, l.created_at)) from public.so_line l where l.so_id = s.id), '-infinity'),
                    coalesce((select max(greatest(r.updated_at, r.created_at, r.allocated_at, coalesce(r.released_at, '-infinity'))) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id), '-infinity'),
                    coalesce((select max(greatest(t.created_at, coalesce(t.started_at, '-infinity'), coalesce(t.completed_at, '-infinity'), coalesce(t.heartbeat_at, '-infinity'))) from public.wms_pick_tasks t where t.order_id = s.id), '-infinity'),
                    coalesce((select max(greatest(t.created_at, coalesce(t.started_at, '-infinity'), coalesce(t.completed_at, '-infinity'), coalesce(t.heartbeat_at, '-infinity'))) from public.wms_pack_tasks t where t.order_id = s.id), '-infinity'),
                    coalesce((select max(greatest(x.created_at, coalesce(x.picked_at, '-infinity'))) from public.wms_pick_task_lines x join public.wms_pick_tasks t on t.id = x.pick_task_id where t.order_id = s.id), '-infinity'),
                    coalesce((select max(greatest(x.created_at, coalesce(x.verified_at, '-infinity'))) from public.wms_pack_task_lines x join public.wms_pack_tasks t on t.id = x.pack_task_id where t.order_id = s.id), '-infinity'),
                    coalesce((select max(greatest(w.created_at, coalesce(w.completed_at, '-infinity'))) from public.wms_pallets w where w.order_id = s.id), '-infinity')) as last_touch
    from public.so s
    where s.status = p_status and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id)
      and exists (select 1 from public.so_line l where l.so_id = s.id and l.discount_source = 'shopify' and l.combo_line_id is null and l.free_reason is null and not l.price_override and l.bgrade_bin_id is null)
  )
  select c.so_number, l.id, l.qty_ordered, l.list_price, q.discount_pct, c.last_touch
  from cand c cross join lateral (select l.* from public.so_line l where l.so_id = c.id and l.discount_source = 'shopify' and l.combo_line_id is null and l.free_reason is null and not l.price_override and l.bgrade_bin_id is null order by l.line_no limit 1) l
  cross join lateral public.so_line_quote((select s from public.so s where s.id = c.id), l.product_id, l.qty_ordered) q
  where c.last_touch < now() - interval '30 minutes'
  order by c.last_touch, c.so_number limit 1;
$$;
select coalesce(q.so_number, 'none') as so_pick, coalesce(q.line_id::text, 'none') as l_pick, coalesce(q.qty::text, '0') as q_pick, coalesce(q.list::text, '0') as lp_pick, coalesce(q.p::text, '0') as p_pick, coalesce(q.last_touch::text, '-') as t_pick, (q.so_number is not null)::text as pick_ok
  from (select 1) d left join pg_temp.quiet('picking') q on true \gset
select coalesce(q.so_number, 'none') as so_pack, coalesce(q.line_id::text, 'none') as l_pack, coalesce(q.qty::text, '0') as q_pack, coalesce(q.list::text, '0') as lp_pack, coalesce(q.p::text, '0') as p_pack, coalesce(q.last_touch::text, '-') as t_pack, (q.so_number is not null)::text as pack_ok
  from (select 1) d left join pg_temp.quiet('packed') q on true \gset
\echo '── C9 · C10 고른 실물 오더(30 분 손 안 댄 것): picking' :so_pick '마지막 손댐' :t_pick '· packed' :so_pack '마지막 손댐' :t_pack
select l.id as l_inv from public.so_line l join public.so s on s.id = l.so_id where s.so_number = 'SO-20856' and l.discount_source = 'shopify' order by l.line_no limit 1 \gset
select l.id as l_comp from public.so_line l join public.so s on s.id = l.so_id where l.combo_line_id is not null and s.status in ('confirmed', 'picking', 'packed') and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id) order by s.so_number limit 1 \gset
select l.id as l_ims from public.so_line l join public.so s on s.id = l.so_id where l.discount_source in ('customer', 'deal') and not l.price_override and s.status in ('confirmed', 'picking', 'packed') and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id) order by s.so_number limit 1 \gset
select l.id as l_ovr from public.so_line l join public.so s on s.id = l.so_id where l.price_override and l.free_reason is null and l.combo_line_id is null and s.status in ('confirmed', 'picking', 'packed') and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id) order by s.so_number limit 1 \gset
select l.id as l_cxl from public.so_line l join public.so s on s.id = l.so_id where l.discount_source = 'shopify' and s.status = 'cancelled' order by s.so_number limit 1 \gset
-- 거부 시험용 shopify 줄(C7 · C8 — 거부라 쓰기 0 · 잠금은 서브트랜잭션 안에서 풀린다): 재생 SO-20856(gid 1) 의 첫 줄
select l.id as l_any from public.shop_order o join public.shop_order_line sol on sol.shop_order_id = o.id join public.so_line l on l.id = sol.so_line_id where o.shopify_order_gid = pg_temp.gid(1) and l.combo_line_id is null and l.free_reason is null order by sol.line_no limit 1 \gset
-- 무상 줄 재료 — 초안 하나에 무상 줄(실물에 무상 shopify 줄 0 · rollback)
select (public.so_create((select customer_id from public.so where so_number = 'SO-20856'), 'warehouse', 'manual', (select location_id from public.so where so_number = 'SO-20856'), 'DISC1 free-line fixture'))->>'id' as so_free \gset
select (public.so_line_add(:'so_free'::uuid, (select product_id from public.so_line where id = :'l_any'::uuid), 1, 0, null, 'sample', null, false))->'line'->>'id' as l_free \gset
select pg_temp.chk('C1 invoiced order (real SO-20856 line) → refused', left(pg_temp.rule(:'l_inv', '7'), 60), 'ERR P0001: Order SO-20856 is invoiced — web lines are not re');
select pg_temp.chk('C2 combo component → refused', (select regexp_replace(pg_temp.rule(:'l_comp', '7'), 'Line [0-9]+ \([^)]*\)', 'Line N (SKU)')), 'ERR P0001: Line N (SKU) is a combo component — it has no price of its own — nothing was saved');
select pg_temp.chk('C3 free line (draft fixture) → refused', (select regexp_replace(pg_temp.rule(:'l_free', '7'), 'Line [0-9]+ \([^)]*\)', 'Line N (SKU)')), 'ERR P0001: Line N (SKU) is a free line (sample) — it is not re-priced — nothing was saved');
select pg_temp.chk('C4 IMS-priced line (customer · deal) → refused', (select regexp_replace(regexp_replace(pg_temp.rule(:'l_ims', '7'), 'Line [0-9]+ \([^)]*\)', 'Line N (SKU)'), 'source (customer|deal)', 'source X')), 'ERR P0001: Line N (SKU) is not a Shopify-priced line (discount source X) — nothing was saved');
select pg_temp.chk('C5 hand-priced line (price_override) → refused', (select regexp_replace(pg_temp.rule(:'l_ovr', '7'), 'Line [0-9]+ \([^)]*\)', 'Line N (SKU)')), 'ERR P0001: Line N (SKU) has a hand price — nothing was saved');
select pg_temp.chk('C6 cancelled order → refused', (select regexp_replace(pg_temp.rule(:'l_cxl', '7'), 'SO-[0-9]+[a-z]*', 'SO-N')), 'ERR P0001: Order SO-N is cancelled — its lines are not re-priced — nothing was saved');
select pg_temp.chk('C7 pct out of range · null · unknown line → refused', (pg_temp.rule(:'l_any', '101') like 'ERR P0001: so_line_set_shopify_rule: discount_pct 101 must be between 0 and 100%')::text || '/' || (pg_temp.rule(:'l_any', 'null') like 'ERR P0001: so_line_set_shopify_rule: discount_pct <NULL> must be between 0 and 100%')::text
  || '/' || (pg_temp.rule('00000000-0000-4000-a000-00000000dead', '7') like 'ERR P0001: so_line_set_shopify_rule: line 00000000-0000-4000-a000-00000000dead not found%')::text, 'true/true/true');
select pg_temp.chk('C8 p = 100 (unit would be 0 → free line) → refused', (select regexp_replace(pg_temp.rule(:'l_any', '100'), 'Line [0-9]+ \([^)]*\)', 'Line N (SKU)')), 'ERR P0001: Line N (SKU): a 100 % discount would make it a free line — nothing was saved');
-- ② 직전 기준(이 뒤로 ② 가 그 오더를 잠근다 · C13 이 대조) · 잠근 시각
select (select string_agg(l.id::text || ':' || l.sku || ':' || l.qty_ordered || ':' || l.unit_price || ':' || coalesce(l.discount_pct::text, '-'), ',' order by l.so_id, l.line_no) from public.so_line l join public.so s on s.id = l.so_id where s.so_number in (:'so_pick', :'so_pack')) as real_lines_1,
       (select sum(r.qty_allocated) from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id where s.so_number in (:'so_pick', :'so_pack') and r.released_at is null) as res_before,
       (select string_agg(s.so_number || ':' || s.status, ',' order by s.so_number) from public.so s where s.so_number in (:'so_pick', :'so_pack')) as st_before, clock_timestamp() as t_lock \gset
\if :pick_ok
select pg_temp.rule(:'l_pick', :'p_pick') as c9 \gset
select pg_temp.chk('C9 picking line (quiet real order · see echo) → set: pct = p · unit = list × (1 − p/100) · source shopify · deal null · override false · qty same · updated_by = system staff',
  coalesce((pg_temp.j(:'c9')->>'discount_pct') || '/' || (pg_temp.j(:'c9')->>'unit_price') || '/' || (pg_temp.j(:'c9')->>'discount_source') || '/' || coalesce(pg_temp.j(:'c9')->>'deal_line_id', 'null') || '/' || (pg_temp.j(:'c9')->>'price_override') || '/' || (pg_temp.j(:'c9')->>'qty_ordered') || '/' || (pg_temp.j(:'c9')->>'updated_by'), left(:'c9', 160)),
  :'p_pick' || '/' || round(:'lp_pick'::numeric * (1 - :'p_pick'::numeric / 100), 7) || '/shopify/null/false/' || :'q_pick' || '/' || :'sys_staff');
\else
select pg_temp.chk('C9 picking line → SKIP (no picking order untouched for 30 minutes)', 'SKIP', 'SKIP');
\endif
\if :pack_ok
select pg_temp.rule(:'l_pack', :'p_pack') as c10 \gset
select pg_temp.rule(:'l_pack', :'p_pack') as c10b \gset
select pg_temp.chk('C10 packed line (quiet real order · see echo) → set · second call idempotent (same row values)',
  coalesce((pg_temp.j(:'c10')->>'discount_pct') || '/' || (pg_temp.j(:'c10')->>'unit_price') || '/' || (pg_temp.j(:'c10')->>'discount_source'), left(:'c10', 160)) || '|' || coalesce((pg_temp.j(:'c10') - 'updated_at' = pg_temp.j(:'c10b') - 'updated_at')::text, left(:'c10b', 160)),
  :'p_pack' || '/' || round(:'lp_pack'::numeric * (1 - :'p_pack'::numeric / 100), 7) || '/shopify|true');
\else
select pg_temp.chk('C10 packed line → SKIP (no packed order untouched for 30 minutes)', 'SKIP', 'SKIP');
\endif
select pg_temp.chk('C11 after ② on real lines: order status · open reserve Σ · qty · line totals = round(qty × unit, 2) unchanged/true',
  coalesce((select string_agg(s.so_number || ':' || s.status, ',' order by s.so_number) from public.so s where s.so_number in (:'so_pick', :'so_pack')), '-') || '/' ||
  coalesce((select sum(r.qty_allocated) from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.so s on s.id = l.so_id where s.so_number in (:'so_pick', :'so_pack') and r.released_at is null)::text, '-') || '/' ||
  coalesce((select bool_and(l.qty_ordered = split_part(x, ':', 3)::numeric and public.so_line_total(l) = round(l.qty_ordered * l.unit_price, 2))::text from unnest(string_to_array(:'real_lines_1', ',')) x join public.so_line l on l.id = split_part(x, ':', 1)::uuid), '-'),
  coalesce(nullif(:'st_before', ''), '-') || '/' || coalesce(nullif(:'res_before', ''), '-') || '/' || case when :'real_lines_1' = '' then '-' else 'true' end);
set local role authenticated;
select pg_temp.chk('C12 authenticated cannot call ② (42501) · nor shop_order_process', left(pg_temp.rule(:'l_any', '7'), 9) || '/' || left(pg_temp.proc('00000000-0000-4000-a000-00000000dead'), 9), 'ERR 42501/ERR 42501');
reset role;
select pg_temp.chk('C13 lines of the two quiet orders: only the two ② targets changed (others byte-equal to the snapshot taken right before ②)',
  (select count(*) from (select l.id::text || ':' || l.sku || ':' || l.qty_ordered || ':' || l.unit_price || ':' || coalesce(l.discount_pct::text, '-') as x, l.id from public.so_line l join public.so s on s.id = l.so_id where s.so_number in (:'so_pick', :'so_pack')) n
   where n.x <> all (string_to_array(:'real_lines_1', ',')) and n.id::text not in (:'l_pick', :'l_pack'))::text, '0');

\if :{?mig}
-- ── D) 재발행 diff — 옛 prosrc(begin 앞) ↔ 새 prosrc · 더한 줄만 ──
create temp table t_diff as
  with o as (select l, count(*) as c from t_pre t, regexp_split_to_table(t.prosrc, E'\n') as l group by l),
       w as (select l, count(*) as c from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') as l where p.oid = 'public.shop_order_process(uuid)'::regprocedure group by l)
  select 'removed' as side, o.l, o.c - coalesce(w.c, 0) as c from o left join w on w.l = o.l where o.c > coalesce(w.c, 0)
  union all
  select 'added', w.l, w.c - coalesce(o.c, 0) from w left join o on o.l = w.l where w.c > coalesce(o.c, 0);
select pg_temp.chk('D0 begin 앞 prosrc = 마지막 정의(20261103020000:487 · md5 fac48d11 · 171 줄)', (select md5 || '/' || n_lines from t_pre), 'fac48d1123643c5a2a51aaa167ec924e/171');
select pg_temp.chk('D1 new = old + 26 lines · removed 0 · added 26', (select array_length(string_to_array(prosrc, E'\n'), 1)::text from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure) || '/' ||
  (select coalesce(sum(c) filter (where side = 'removed'), 0)::text || '/' || coalesce(sum(c) filter (where side = 'added'), 0)::text from t_diff), '197/0/26');
select pg_temp.chk('D2 added lines = exactly the shop-disc-1 lines (md5 of the sorted added lines) · all inside v_s.kind = asung guards or the declare line',
  (select md5(string_agg(x.l, E'\n' order by x.l collate "C")) from (select l from t_diff, generate_series(1, c) where side = 'added') x), '05e7e24677e8f49aa276d638a7c4ccae');
\echo '── D 더한 줄(앞 110 자)'
select left(l, 110) as added_line from t_diff where side = 'added' order by l collate "C";
-- ── G) aone 한 장 — 옛 몸(pg_temp 에 같은 바이트로) ↔ 새 몸 · 같은 raw 를 두 번(gid 931 · 932) · 줄 · 경고(시각 제외) · 결제 · 결과 같음 ──
do $$ begin execute format('create function pg_temp.proc_old(p_shop_order_id uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L', (select prosrc from t_pre)); end $$;
create function pg_temp.replay_old(p_name text, p_n int) returns text language plpgsql as $$
declare v_o public.shop_order%rowtype; v_res text; v_id text;
begin
  select o.* into v_o from public.shop_order o join public.shop_store s on s.id = o.store_id where o.name = p_name and s.code = 'aone' order by o.shopify_created_at desc limit 1;
  v_res := pg_temp.ing(v_o.store_id, v_o.raw || jsonb_build_object('id', pg_temp.gid(p_n), 'name', 'DISC1-T' || lpad(p_n::text, 4, '0')));
  v_id := pg_temp.j(v_res)->>'shop_order_id';
  if v_id is null then return 'ERR ingest: ' || left(v_res, 300); end if;
  return pg_temp.run(format('select pg_temp.proc_old(%L::uuid)::text', v_id));
end $$;
create function pg_temp.shape(p_gid text) returns text language sql as $$
  with o as (select o.*, s.status as so_status, s.order_discount_pct as od from public.shop_order o left join public.so s on s.id = o.so_id where o.shopify_order_gid = p_gid)
  select (select status || '/' || so_status || '/' || coalesce(od::text, 'null') from o)
      || '/lines ' || (select string_agg(l.sku || ':' || l.qty_ordered || ':' || coalesce(l.list_price::text, '-') || ':' || coalesce(l.discount_pct::text, '-') || ':' || l.unit_price || ':' || coalesce(l.discount_source, '-') || ':' || coalesce(l.free_reason, '-'), ',' order by l.line_no) from o join public.so_line l on l.so_id = o.so_id)
      || '/warn ' || (select coalesce(string_agg((w - 'at' - 'settled_at' - 'so_payment_ids' - 'message')::text, '|' order by ord), '-') from o, jsonb_array_elements(o.warnings) with ordinality as x(w, ord))
      || '/pay ' || (select coalesce(string_agg(p.amount || ':' || p.method, ',' order by p.amount), '-') from o join public.so_payment_order po on po.so_id = o.so_id join public.so_payment p on p.id = po.payment_id)
      || '/charges ' || (select coalesce(string_agg(c.amount::text || ':' || coalesce(c.discount_pct::text, '-'), ',' order by c.amount), '-') from o join public.so_charge c on c.so_id = o.so_id);
$$;
select pg_temp.replay_old('AO-17350', 31) as g_old \gset
select pg_temp.replay('AO-17350', 32) as g_new \gset
select pg_temp.chk('G1 aone AO-17350: old body and new body both created', coalesce(pg_temp.j(:'g_old')->>'status', left(:'g_old', 100)) || '/' || coalesce(pg_temp.j(:'g_new')->>'status', left(:'g_new', 100)), 'created/created');
select pg_temp.chk('G2 aone AO-17350: old = new (so status · od · lines list/pct/unit/source · warnings minus timestamps · payments · charges) · no web_discount_rounded', pg_temp.shape(pg_temp.gid(32)) || '/' || (pg_temp.shape(pg_temp.gid(32)) like '%web_discount_rounded%')::text, pg_temp.shape(pg_temp.gid(31)) || '/false');
\echo '── G aone 모양(새)'
select pg_temp.shape(pg_temp.gid(32));
\endif

-- ── E) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE ──
select pg_temp.chk('E0 scanner self-test: no-where update 1 · where 0 · then-update-no-where 1', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where id = 2;')::text || pg_temp.nowhere('if x then update t set a = (select 1 where y); end if;')::text, '101');
select pg_temp.chk('E1 so_line_set_shopify_rule · shop_order_process: every update · delete has a WHERE (depth 0)',
  pg_temp.nowhere((select prosrc from pg_proc where oid = 'public.so_line_set_shopify_rule(uuid, numeric)'::regprocedure))::text || '/' || pg_temp.nowhere((select prosrc from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure))::text, '0/0');

-- ── F) 속성 · 권한 · 무변 ──
select pg_temp.chk('F1 ② is definer · volatile · not executable by authenticated · anon · executable by service_role', (select prosecdef::text || provolatile::text from pg_proc where oid = 'public.so_line_set_shopify_rule(uuid, numeric)'::regprocedure)
  || '/' || has_function_privilege('authenticated', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute')::text || '/' || has_function_privilege('service_role', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute')::text, 'truev/false/false/true');
select pg_temp.chk('F2 untouched (md5 begin 앞 = 지금): so_line_set_shopify · so_line_quote · so_line_bgrade_guard · so_line discount_source CHECK still the 5 values',
  (select md5(prosrc) = :'set_md5_0' from pg_proc where oid = 'public.so_line_set_shopify(uuid, numeric, numeric)'::regprocedure)::text || '/' || (select md5(prosrc) = :'quote_md5_0' from pg_proc where oid = 'public.so_line_quote(public.so, uuid, numeric)'::regprocedure)::text
  || '/' || (select md5(prosrc) = :'bg_md5_0' from pg_proc where oid = 'public.so_line_bgrade_guard()'::regprocedure)::text || '/' || (select pg_get_constraintdef(oid) like '%''customer''%''deal''%''manual''%''set''%''shopify''%' from pg_constraint where conname = 'so_line_discount_source_ck')::text, 'true/true/true/true');
select pg_temp.chk('F3 comments: ② mentions 997 · 1008 · service_role · process comment appended with shop-disc-1 · ① mentions 1001',
  (coalesce(obj_description('public.so_line_set_shopify_rule(uuid, numeric)'::regprocedure, 'pg_proc'), '') like '%997%1008%service_role%')::text || '/' || (coalesce(obj_description('public.shop_order_process(uuid)'::regprocedure, 'pg_proc'), '') like '%ord-1a2%shop-disc-1%web_discount_rounded%')::text
  || '/' || (coalesce(obj_description('public.shop_line_rule_fit(numeric, numeric, numeric)'::regprocedure, 'pg_proc'), '') like '%1001%')::text, 'true/true/true');
select pg_temp.chk('F4 process prosrc: asung guard twice (loop ② · ⑥-b) · calls so_line_set_shopify_rule once · old 0.1 % line still present once · ⑥-b sits after tax_mismatch and before ⑦',
  (select (length(prosrc) - length(replace(prosrc, 'if v_s.kind = ''asung''', ''))) / length('if v_s.kind = ''asung''') || '/' || (length(prosrc) - length(replace(prosrc, 'public.so_line_set_shopify_rule(', ''))) / length('public.so_line_set_shopify_rule(')
          || '/' || (length(prosrc) - length(replace(prosrc, 'if abs(v_pct - v_ims_pct) > 0.1 then', ''))) / length('if abs(v_pct - v_ims_pct) > 0.1 then')
          || '/' || (position('''tax_mismatch''' in prosrc) < position('⑥-b' in prosrc) and position('⑥-b' in prosrc) < position('-- ⑦ 결제' in prosrc))::text
   from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure), '2/1/1/true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.so where ref like 'DISC1-T%') = 0 and (select count(*) from public.shop_order where shopify_order_gid like 'gid://shopify/Order/930000000%') = 0 and (select count(*) from public.so where comments = 'DISC1 free-line fixture') = 0
       then 'Z1 OK no trial artifacts remain (DISC1-T SOs 0 · fake-gid shop_orders 0 · fixture draft 0)' else 'Z1 MISMATCH trial artifacts remain' end as z1;
select 'info: row counts before begin → after rollback (warehouse activity, not the trial): shop_order ' || :n_ord0 || '→' || (select count(*) from public.shop_order) || ' · so ' || :n_so0 || '→' || (select count(*) from public.so) || ' · so_line ' || :n_line0 || '→' || (select count(*) from public.so_line)
    || ' · so_reserve ' || :n_res0 || '→' || (select count(*) from public.so_reserve) || ' · so_payment ' || :n_pay0 || '→' || (select count(*) from public.so_payment) || ' · so_invoice_order ' || :n_inv0 || '→' || (select count(*) from public.so_invoice_order) as z1_info;
select 'info: ② locked orders ' || :'so_pick' || ' · ' || :'so_pack' || ' from ' || :'t_lock' || ' until rollback (' || (clock_timestamp() - :'t_lock'::timestamptz)::text || ' incl. this line)' as lock_info;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure) = :'proc_md5_0' and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_line_rule_fit', 'so_line_set_shopify_rule')) = 0
       then 'Z2 OK shop_order_process back to before (md5) · new functions gone' else 'Z2 MISMATCH not restored' end as z2;
\endif
