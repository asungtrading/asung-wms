-- supabase/ops/tf-transit-1.sql — 컷오버 날 떠나 있던 Cin7 트랜스퍼 4 장(TR-06396 ~ 06399 · 2026-10-26 · 한 트럭 팔렛 넷)을 IMS 트랜스퍼 「가는 중」 으로 연다 (판정 896 · tf-transit-1 · 2026-10-31)
-- [운영 · Asung-IMS fazgmyvzzhqybtvtktyg — 판정 617 로 이 프로젝트가 메인 · 마이그레이션 20261031180000_tf_transit_1 적용 뒤]
--
-- 무엇: 네 장은 Cin7 에서 VOIDED 됐지만 물건은 실제로 떠났고(토론토 → 에드먼턴) 아직 도착 전. 원장에는 cin7 출발(출발 창고 −  · IN_TRANSIT +)만 있다.
--       창구 inv_transfer_open_in_transit 이 장마다 IMS 문서 하나(번호 = Cin7 번호 그대로 · 상태 in_transit · 출발일 10-26 · 줄 = 원장 IN_TRANSIT 들어감 SKU × 수량)를 만든다.
--       에드먼턴은 IMS 받기 화면(wms-receiver.html · Transfers)에서 평소대로 받는다 → tf_arrive → inv_post_transfer_arrive 가 IN_TRANSIT − · 에드먼턴 칸 + · 원가(같은 번호의 IN_TRANSIT 레이어)를 잇는다.
-- 안 하는 것: 원장 쓰기 0 · 재고 · 가용 · 레이어 변화 0 · TR-06397 의 bin 변경 이중 기입 18(LAC73891-3 · LAC74507-9)은 893 조정 몫 · TR-03975 · 03976(08-26 기준선 잔재)은 손대지 않는다.
--       Shopify 큐: 줄 트리거가 제품을 큐에 넣는다(의도 · 끄지 않는다) — 보낼 값은 안 바뀌어 drain 이 skipped_same 으로 닫는다(판정 896 결정 ③ · 아래 검산 ⑤ 가 전후 payload 를 견준다).
-- 꼴:  마이그레이션 아님 · 한 번 · begin · commit 없음(-1 이 한 트랜잭션) · 검산이 하나라도 어긋나면 raise → 네 장 전부 되돌아간다 · jwt claims = Caleb(admin).
-- 실행(Caleb · 레포 뿌리에서):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/tf-transit-1.sql > ~/tf-transit-1.log 2>&1; echo "exit=$?"
-- 확인 실행(적용 뒤 · 쓰기 0 · 열기 · voided 닫기를 건너뛰고 검산만):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v check=1 -f supabase/ops/tf-transit-1.sql
-- 리허설(Claude Code · begin → rollback · -v rehearsal=1): 검산 어긋남은 찍기만 · raise 없음 · 잠금 시간은 장치가 정한다.
-- 되돌리기(적용 뒤 · 받기 시작 전): delete from public.inv_transfer where transfer_number in ('TR-06396','TR-06397','TR-06398','TR-06399') and status = 'in_transit';  — 줄은 cascade ·
--   update public.inv_voided_docs set resolved_at = null, resolution_note = null where id = 3772;  — 받기 시작(receiving) 뒤에는 되돌리지 않는다(입고 · 원장이 붙는다).
-- 차례: ① 이 DB 확인 → ② 기준값(전) → ③ 네 장 열기 → ④ voided 3772 닫기 → ⑤ 검산 → ⑥ 결과

-- ① 이 DB 확인 (1/2) — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄)
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

-- ① 이 DB 확인 (2/2) — 창구가 있어야 한다(마이그레이션 20261031180000 적용 뒤)
do $$ begin
  if to_regproc('public.inv_transfer_open_in_transit') is null then
    raise exception using errcode = 'WM501', message = 'STOP - inv_transfer_open_in_transit is missing - apply migration 20261031180000_tf_transit_1_open_in_transit first. Nothing was changed.';
  end if;
end $$;

\if :{?rehearsal}
\echo '[REHEARSAL] rehearsal=1 — 검산 어긋남은 찍기만(raise 없음)'
\else
set local lock_timeout = '3s';
set local statement_timeout = '120s';
\endif
\if :{?check}
\echo '[CHECK] check=1 — ③ 열기 · ④ voided 닫기는 건너뛴다 · 검산만(적용 뒤 확인 실행)'
\endif

-- jwt claims = Caleb(admin · ims_require_admin 이 auth.uid() 로 본다) · 트랜잭션 안에서만
select set_config('request.jwt.claims', (select jsonb_build_object('sub', s.auth_user_id, 'role', 'authenticated')::text from public.ims_staff s where s.email = 'caleb@asung.ca' and s.is_active), true) as claims \gset
\if :{?rehearsal}
\else
do $$ begin if not public.ims_is_admin() then raise exception 'STOP - jwt claims did not resolve to an active admin (caleb@asung.ca). Nothing was changed.'; end if; end $$;
\endif

create temp table t_res (n int generated always as identity, name text, ok boolean) on commit drop;
create function pg_temp.chk(p_name text, p_ok boolean) returns void language sql as $$ insert into t_res (name, ok) values (p_name, coalesce(p_ok, false)) $$;

-- 기대값(대화 · 2026-10-31 실측 · 원장 IN_TRANSIT 들어감 줄 수 · 수량 합 · 팔렛)
create temp table t_exp (doc text primary key, pallet text, lines int, qty_ea numeric) on commit drop;
insert into t_exp values ('TR-06396', 'P1', 186, 1512), ('TR-06397', 'P2', 293, 1821), ('TR-06398', 'P3', 32, 349), ('TR-06399', 'P4', 88, 1343);

-- ② 기준값(전) — 손대지 않아야 하는 것들의 지문
select count(*) as pre_ledger from public.inv_ledger \gset
select count(*) as pre_layer from public.inv_layer \gset
select count(*) as pre_consume from public.inv_layer_consume \gset
select count(*) as pre_queue from public.shop_stock_queue \gset
select count(*) as pre_tf from public.inv_transfer \gset
select count(*) as pre_tf_ours from public.inv_transfer where transfer_number in (select doc from t_exp) \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as pre_bal_md5 from public.inv_balance where qty <> 0 \gset
create temp table t_pids on commit drop as
  select distinct p.id from public.product p join public.inv_ledger e on e.sku = p.sku where e.doc_number in (select doc from t_exp) and e.warehouse = 'IN_TRANSIT';
select count(*) as pre_pids from t_pids \gset
create temp table t_pay_pre on commit drop as
  select x.store_id, x.product_id, x.warehouse_id, x.quantity, x.is_off, x.blocks
    from public.shop_store s cross join lateral public.shop_stock_payload(s.id, (select array_agg(id) from t_pids)) x
   where s.is_active and s.live;
select coalesce(md5(string_agg(store_id || '|' || product_id || '|' || coalesce(warehouse_id::text, '') || '|' || coalesce(quantity::text, '') || '|' || is_off || '|' || blocks::text, ',' order by store_id, product_id, warehouse_id)), '(none)') as pre_pay_md5, count(*) as pre_pay_n from t_pay_pre \gset
select coalesce((select (resolved_at is not null)::int from public.inv_voided_docs where id = 3772 and doc_type = 'transfer' and doc_number = 'TR-06397'), -1) as pre_voided_closed \gset
\echo '② 전: 원장' :pre_ledger '· 레이어' :pre_layer '· 소진' :pre_consume '· 큐' :pre_queue '· inv_transfer' :pre_tf '(우리 번호' :pre_tf_ours ') · 제품' :pre_pids '· payload 행' :pre_pay_n '· voided 3772 닫힘' :pre_voided_closed

\o /dev/null
select pg_temp.chk('② 우리 번호의 IMS 문서 없음(멱등 — check 모드는 4)', case when :{?check} then :pre_tf_ours = 4 else :pre_tf_ours = 0 end);
select pg_temp.chk('② 원장 IN_TRANSIT 들어감 줄 수 · 수량이 기대와 같다(4 장)',
  (select count(*) from t_exp x join (select doc_number, count(*) n, sum(qty_delta) q from public.inv_ledger where warehouse = 'IN_TRANSIT' and event_type = 'transfer_in' and source = 'cin7' and doc_number in (select doc from t_exp) group by 1) l
     on l.doc_number = x.doc and l.n = x.lines and l.q = x.qty_ea) = 4);
select pg_temp.chk('② 도착 다리 없음(IN_TRANSIT 나감 · 창고 들어감 0)', (select count(*) from public.inv_ledger where doc_number in (select doc from t_exp) and ((warehouse = 'IN_TRANSIT' and event_type = 'transfer_out') or (warehouse <> 'IN_TRANSIT' and event_type = 'transfer_in'))) = 0);
select pg_temp.chk('② voided 3772 = TR-06397 · 열림(멱등 — check 모드는 닫힘)', case when :{?check} then :pre_voided_closed = 1 else :pre_voided_closed = 0 end);
\o

-- ③ 네 장 열기 — 창구가 줄을 원장에서 스스로 만든다 · 한 장이라도 거부면 전부 되돌아간다(-1)
\if :{?check}
\echo '③ 건너뜀(check)'
\else
select public.inv_transfer_open_in_transit('TR-06396', 'Cin7 TR-06396 · pallet P1 of 4 (one truck Toronto → Edmonton) · VOIDED in Cin7 at cutover · shipped 2026-10-26 · opened from the stock book (decision 896 · tf-transit-1)') as r1 \gset
select public.inv_transfer_open_in_transit('TR-06397', 'Cin7 TR-06397 · pallet P2 of 4 (one truck Toronto → Edmonton) · VOIDED in Cin7 at cutover · shipped 2026-10-26 · opened from the stock book (decision 896 · tf-transit-1) · 6 SKUs (LAC73891-3 · LAC74507-9) carry a bin-change double entry of 3 each in the stock book — settled in the 893 adjustment round') as r2 \gset
select public.inv_transfer_open_in_transit('TR-06398', 'Cin7 TR-06398 · pallet P3 of 4 (one truck Toronto → Edmonton) · VOIDED in Cin7 at cutover · shipped 2026-10-26 · opened from the stock book (decision 896 · tf-transit-1)') as r3 \gset
select public.inv_transfer_open_in_transit('TR-06399', 'Cin7 TR-06399 · pallet P4 of 4 (one truck Toronto → Edmonton) · VOIDED in Cin7 at cutover · shipped 2026-10-26 · opened from the stock book (decision 896 · tf-transit-1)') as r4 \gset
\echo '③ 열림:' :r1
\echo '③ 열림:' :r2
\echo '③ 열림:' :r3
\echo '③ 열림:' :r4
\endif

-- ④ voided 3772 닫기 — 상쇄 안 함 · IMS 트랜스퍼로 이어 받음 · 수집기 감지 기록이라 행을 지우지 않고 닫기만 · 나머지 셋은 행이 없고 만들지 않는다
\if :{?check}
select 1 as voided_n \gset
\else
with u as (
  update public.inv_voided_docs
     set resolved_at = now(),
         resolution_note = 'tf-transit-1 (decision 896 · 2026-10-31): not reversed — the goods physically left Toronto 2026-10-26 (one truck, pallets P1-P4 = TR-06396..06399, all VOIDED in Cin7 at cutover). Opened as IMS transfer TR-06397 (in transit, same number) and received at Edmonton through the IMS receiving screen. ledger_net -18 = bin-change double entry on 6 SKUs (LAC73891-3 · LAC74507-9 · 2 departure rows each), handled in the 893 adjustment round. The other three pallets have no row here (detector never saw them) and none is created.'
   where id = 3772 and doc_type = 'transfer' and doc_number = 'TR-06397' and resolved_at is null
   returning id)
select count(*) as voided_n from u \gset
\endif

-- ⑤ 검산
select count(*) as post_ledger from public.inv_ledger \gset
select count(*) as post_layer from public.inv_layer \gset
select count(*) as post_consume from public.inv_layer_consume \gset
select count(*) as post_queue from public.shop_stock_queue \gset
select count(*) as post_tf from public.inv_transfer \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as post_bal_md5 from public.inv_balance where qty <> 0 \gset
create temp table t_pay_post on commit drop as
  select x.store_id, x.product_id, x.warehouse_id, x.quantity, x.is_off, x.blocks
    from public.shop_store s cross join lateral public.shop_stock_payload(s.id, (select array_agg(id) from t_pids)) x
   where s.is_active and s.live;
select coalesce(md5(string_agg(store_id || '|' || product_id || '|' || coalesce(warehouse_id::text, '') || '|' || coalesce(quantity::text, '') || '|' || is_off || '|' || blocks::text, ',' order by store_id, product_id, warehouse_id)), '(none)') as post_pay_md5 from t_pay_post \gset

\echo '⑤ 장마다 — 줄 수 · 수량 합(EA) · 상태 · 출발일(토론토) · 기대'
select x.transfer_number, x.status, (x.departed_at at time zone 'America/Toronto')::date as departed_on_toronto, fw.name as from_wh, tw.name as to_wh,
       (select count(*) from public.inv_transfer_line l where l.transfer_id = x.id) as line_count,
       (select sum(l.qty_sent * l.pack_factor) from public.inv_transfer_line l where l.transfer_id = x.id) as sent_ea,
       e.pallet, e.lines as exp_lines, e.qty_ea as exp_ea, left(x.note, 40) as note_head
  from public.inv_transfer x join t_exp e on e.doc = x.transfer_number
  join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
 order by x.transfer_number;

\o /dev/null
select pg_temp.chk('⑤ 네 장 모두 in_transit · 줄 수 · 수량 합 = 기대 · 토론토 → 에드먼턴 · 출발일 2026-10-26',
  (select count(*) from public.inv_transfer x join t_exp e on e.doc = x.transfer_number
    join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
   where x.status = 'in_transit' and fw.name = 'Asung Trading Inc.' and tw.name = 'Asung - Edmonton' and (x.departed_at at time zone 'America/Toronto')::date = date '2026-10-26' and x.confirmed_at is not null
     and (select count(*) from public.inv_transfer_line l where l.transfer_id = x.id) = e.lines
     and (select sum(l.qty_sent * l.pack_factor) from public.inv_transfer_line l where l.transfer_id = x.id) = e.qty_ea
     and (select count(*) from public.inv_transfer_line l where l.transfer_id = x.id and l.qty = l.qty_sent) = e.lines) = 4);
select pg_temp.chk('⑤ 줄마다 수량 = 원장 그 SKU 의 IN_TRANSIT 들어감 합(599 줄 전부)',
  (select count(*) from public.inv_transfer_line l join public.inv_transfer x on x.id = l.transfer_id
     join (select doc_number, sku, sum(qty_delta) q from public.inv_ledger where warehouse = 'IN_TRANSIT' and event_type = 'transfer_in' and source = 'cin7' group by 1, 2) g
       on g.doc_number = x.transfer_number and g.sku = l.sku
    where x.transfer_number in (select doc from t_exp) and l.qty_sent * l.pack_factor = g.q) = (select sum(lines) from t_exp));
select pg_temp.chk('⑤ 원장 줄 수 변화 0', :post_ledger = :pre_ledger);
select pg_temp.chk('⑤ 레이어 · 소진 변화 0', :post_layer = :pre_layer and :post_consume = :pre_consume);
select pg_temp.chk('⑤ 잔고(inv_balance) 지문 동일', :'post_bal_md5' = :'pre_bal_md5');
select pg_temp.chk('⑤ Shopify 보낼 값(shop_stock_payload · 599 제품 · 라이브 스토어) 전후 동일', :'post_pay_md5' = :'pre_pay_md5');
select pg_temp.chk('⑤ inv_transfer 가 4 늘었다(check 모드는 0)', case when :{?check} then :post_tf = :pre_tf else :post_tf = :pre_tf + 4 end);
select pg_temp.chk('④ voided 3772 닫힘(1 행)', :voided_n = 1 and (select resolved_at is not null and resolution_note like 'tf-transit-1%' from public.inv_voided_docs where id = 3772));
select pg_temp.chk('④ 나머지 셋은 inv_voided_docs 에 행 없음', (select count(*) from public.inv_voided_docs where doc_number in ('TR-06396', 'TR-06398', 'TR-06399')) = 0);
\o

\echo '⑤ 큐: 전' :pre_queue '→ 후' :post_queue '(줄 트리거 · 보낼 값은 같아 drain 이 skipped_same 으로 닫는다)'

-- ⑥ 결과
\echo '⑥ 검산'
select n, case when ok then 'OK      ' else 'MISMATCH' end as verdict, name from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as mismatch_n from t_res \gset
\echo '⑥ OK' :ok_n '· MISMATCH' :mismatch_n

\if :{?rehearsal}
\echo '[REHEARSAL] raise 없음 — 위 판정을 읽는다'
\else
do $$ begin
  if (select count(*) from t_res where not ok) > 0 then
    raise exception 'tf-transit-1: % check(s) failed — nothing was saved (see verdict list above)', (select count(*) from t_res where not ok);
  end if;
end $$;
\echo '⑥ tf-transit-1 끝 — 네 장이 「가는 중」 · 에드먼턴 받기 화면(Transfers)에 보인다'
\endif
