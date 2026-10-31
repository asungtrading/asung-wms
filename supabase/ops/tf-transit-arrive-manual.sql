-- supabase/ops/tf-transit-arrive-manual.sql — 대비책 (가): 트럭이 창구(tf-transit-1)보다 먼저 와서 IMS 문서 없이 받아야 할 때 · 한 장의 도착 줄을 원장에 SQL 로 쓴다 (판정 896 · 2026-10-31)
-- [운영 · Asung-IMS fazgmyvzzhqybtvtktyg] ⚠️ 만들고 시험만 했다 — 실행은 그때 Caleb. IMS 문서가 이미 열려 있으면(tf-transit-1 뒤) 이 스크립트가 아니라 받기 화면으로 받는다(이 스크립트는 그 경우 거부한다).
--
-- 무엇: 그 문서(Cin7 번호)의 원장 IN_TRANSIT 들어감 줄(source cin7)을 SKU 마다 도착 창고의 한 칸으로 옮긴다 —
--       IN_TRANSIT transfer_out −EA(seq 2 · leg 3) + 도착 창고 칸 transfer_in +EA(seq 1 · leg 4) · source manual · 같은 문서 번호 · line_ref = ProductID || ':arrive:manual' · 날짜 = 인자 ·
--       원가는 같은 트랜잭션에서 inv_layer_post_transfer_arrive(문서 번호 범위 IN_TRANSIT 레이어 → 도착 창고 레이어 · 실시간 도착과 같은 함수)로 잇는다. 재생성(inv_layer_apply)은 source manual 줄을 불러온 축으로 읽어 같은 결과를 다시 세운다(같은 날 · 같은 문서).
-- 인자(psql -v): doc = 'TR-06398' · bin = 도착 창고의 활성 칸 이름(Caleb 이 정할 하나 · 예 'EA010101') · on = 도착일 'YYYY-MM-DD'
-- 실행(Caleb · 레포 뿌리에서):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v doc=TR-06398 -v bin=EA010101 -v on=2026-11-02 -f supabase/ops/tf-transit-arrive-manual.sql > ~/tf-transit-arrive-TR-06398.log 2>&1; echo "exit=$?"
-- 리허설(Claude Code · begin → rollback · -v rehearsal=1): 검산 어긋남은 찍기만 · raise 없음.
-- 되돌리기(적용 뒤): delete from public.inv_ledger where doc_number = :'doc' and source = 'manual' and raw ->> 'prompt' = 'tf-transit-arrive-manual';  + 레이어는 §H 재생성(inv_layer_apply)로 다시.
-- 부분 도착 · 모자람 · 남음은 이 스크립트에 없다(전량 도착만) — 그 경우는 IMS 문서를 열고(tf-transit-1) 받기 화면으로.
-- 차례: ① 이 DB 확인 → ② 인자 · 전제 → ③ 기준값(전) → ④ 원장 두 줄씩 + 레이어 → ⑤ 검산 → ⑥ 결과

-- ① 이 DB 확인 — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄)
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

\if :{?rehearsal}
\echo '[REHEARSAL] rehearsal=1 — 검산 어긋남은 찍기만(raise 없음)'
\else
set local lock_timeout = '3s';
set local statement_timeout = '120s';
\endif

-- ② 인자 · 전제
\if :{?doc}
\else
\echo 'STOP — -v doc=TR-xxxxx 가 없다'
\quit 2
\endif
\if :{?bin}
\else
\echo 'STOP — -v bin=<도착 창고 칸 이름> 가 없다'
\quit 2
\endif
\if :{?on}
\else
\echo 'STOP — -v on=YYYY-MM-DD 가 없다'
\quit 2
\endif
\echo '② 문서' :'doc' '· 칸' :'bin' '· 도착일' :'on'

create temp table t_res (n int generated always as identity, name text, ok boolean) on commit drop;
create function pg_temp.chk(p_name text, p_ok boolean) returns void language sql as $$ insert into t_res (name, ok) values (p_name, coalesce(p_ok, false)) $$;

-- 전제: 원장에 cin7 들어감 줄이 있다 · IMS 문서가 없다(있으면 받기 화면으로) · 도착 다리가 아직 없다 · 칸은 raw.header.to 창고의 활성 칸 · 날짜는 출발일 이후
create temp table t_src on commit drop as
  select e.sku, sum(e.qty_delta) as qty_ea, min(e.line_ref) as product_id_ref, min(e.doc_task_id) as doc_task_id, min(e.occurred_on) as departed_on,
         min(e.raw -> 'header' ->> 'from') as from_cin7, min(e.raw -> 'header' ->> 'to') as to_cin7
    from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = :'doc' and e.warehouse = 'IN_TRANSIT' and e.event_type = 'transfer_in' and e.source = 'cin7'
   group by e.sku;
select count(*) as src_n, coalesce(sum(qty_ea), 0) as src_ea, coalesce(min(departed_on)::text, '1900-01-01') as src_on, count(distinct departed_on) as src_days from t_src \gset
select count(*) as pre_ims_doc from public.inv_transfer where transfer_number = :'doc' \gset
select count(*) as pre_arrival from public.inv_ledger where doc_type = 'transfer' and doc_number = :'doc' and ((warehouse = 'IN_TRANSIT' and event_type = 'transfer_out') or (warehouse <> 'IN_TRANSIT' and event_type = 'transfer_in')) \gset
select coalesce((select w.name from public.ref_warehouse w where w.cin7_id = (select to_cin7::uuid from t_src limit 1) and w.is_active), '') as to_wh,
       coalesce((select w.id::text from public.ref_warehouse w where w.cin7_id = (select to_cin7::uuid from t_src limit 1) and w.is_active), '') as to_wh_id,
       coalesce((select w.name from public.ref_warehouse w where w.cin7_id = (select from_cin7::uuid from t_src limit 1) and w.is_active), '') as from_wh \gset
select coalesce((select b.id::text from public.ref_bin b where b.warehouse_id = nullif(:'to_wh_id', '')::uuid and b.name = :'bin' and b.is_active and not coalesce(b.is_bgrade, false)), '') as bin_id,
       coalesce((select b.name from public.ref_bin b where b.warehouse_id = nullif(:'to_wh_id', '')::uuid and b.name = :'bin' and b.is_active and not coalesce(b.is_bgrade, false)), '') as bin_name \gset
\echo '② 원장: SKU' :src_n '· EA' :src_ea '· 출발일' :src_on '· 창고' :'from_wh' '→' :'to_wh' '· 칸' :'bin_name' '· IMS 문서' :pre_ims_doc '· 도착 다리' :pre_arrival

\o /dev/null
select pg_temp.chk('② 원장에 cin7 IN_TRANSIT 들어감 줄이 있다', :src_n > 0 and :src_ea > 0);
select pg_temp.chk('② IMS 문서 없음(있으면 받기 화면으로 — 이 스크립트 아님)', :pre_ims_doc = 0);
select pg_temp.chk('② 도착 다리 아직 없음', :pre_arrival = 0);
select pg_temp.chk('② 도착 창고 · 칸(활성 · B급 아님)이 풀렸다', :'to_wh' <> '' and :'from_wh' <> '' and :'bin_id' <> '');
select pg_temp.chk('② 도착일 ≥ 출발일', date :'on' >= date :'src_on');
select pg_temp.chk('② SKU 마다 들어감 줄이 한 날(출발일 하나)', :src_days = 1);
\o
do $$ begin
  if (select count(*) from t_res where not ok) > 0 then
    raise exception 'tf-transit-arrive-manual: precondition failed — nothing was saved (see t_res)';
  end if;
end $$;

-- ③ 기준값(전)
select count(*) as pre_ledger from public.inv_ledger \gset
select coalesce(sum(qty_delta), 0) as pre_transit_doc from public.inv_ledger where doc_number = :'doc' and warehouse = 'IN_TRANSIT' \gset
select coalesce(sum(b.qty), 0) as pre_bin_qty from public.inv_balance b where b.warehouse = :'to_wh' and b.bin = :'bin' and b.sku in (select sku from t_src) \gset
select count(*) as pre_layer_dest from public.inv_layer where origin_type = 'transfer' and doc_number = :'doc' and warehouse = :'to_wh' \gset

-- ④ 원장 두 줄씩(leg 3 IN_TRANSIT − · leg 4 칸 +) + 레이어
with hdr as (
  select jsonb_build_object('doc_number', :'doc', 'from_warehouse', :'from_wh', 'to_warehouse', :'to_wh', 'bin', :'bin_name', 'bin_id', :'bin_id', 'arrived_on', :'on',
                            'departed_on', :'src_on', 'by', 'caleb', 'decision', 896, 'prompt', 'tf-transit-arrive-manual',
                            'rule_note', 'Cin7 transfer VOIDED at cutover; goods arrived before the IMS document existed — arrival written straight to the stock book (all sent units, one bin)') as h
), ins as (
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
  select date :'on', 2, s.sku, 'IN_TRANSIT', '', -s.qty_ea, 'transfer_out', 'transfer', :'doc', s.doc_task_id, s.product_id_ref || ':arrive:manual', null::numeric, 'manual',
         jsonb_build_object('kind', 'transfer', 'leg', 3, 'poster', 'tf-transit-arrive-manual@2026-10-31.1', 'prompt', 'tf-transit-arrive-manual', 'header', hdr.h,
                            'line', jsonb_build_object('product_id', s.product_id_ref, 'sku', s.sku, 'qty_ea', s.qty_ea),
                            'rule', format('transfer %s → %s leg 3 (manual arrival): −%s EA out of IN_TRANSIT', :'from_wh', :'to_wh', s.qty_ea))
    from t_src s cross join hdr
  union all
  select date :'on', 1, s.sku, :'to_wh', :'bin_name', s.qty_ea, 'transfer_in', 'transfer', :'doc', s.doc_task_id, s.product_id_ref || ':arrive:manual', null::numeric, 'manual',
         jsonb_build_object('kind', 'transfer', 'leg', 4, 'poster', 'tf-transit-arrive-manual@2026-10-31.1', 'prompt', 'tf-transit-arrive-manual', 'header', hdr.h,
                            'line', jsonb_build_object('product_id', s.product_id_ref, 'sku', s.sku, 'qty_ea', s.qty_ea, 'bin', :'bin_name', 'bin_id', :'bin_id'),
                            'rule', format('transfer %s → %s leg 4 (manual arrival): +%s EA into %s / %s', :'from_wh', :'to_wh', s.qty_ea, :'to_wh', :'bin_name'))
    from t_src s cross join hdr
  returning 1)
select count(*) as ins_n from ins \gset

create temp table t_cost on commit drop as
  select s.sku, s.qty_ea, public.inv_layer_post_transfer_arrive(:'doc', s.product_id_ref || ':arrive:manual', s.sku, :'to_wh', s.qty_ea, date :'on', null) as r
    from t_src s order by s.sku;
select count(*) as cost_n, coalesce(sum((r ->> 'layers')::int), 0) as cost_layers, coalesce(sum((r ->> 'short_qty')::numeric), 0) as cost_short, coalesce(round(sum((r ->> 'amount')::numeric), 2), 0) as cost_amount from t_cost \gset

-- ⑤ 검산
select count(*) as post_ledger from public.inv_ledger \gset
select coalesce(sum(qty_delta), 0) as post_transit_doc from public.inv_ledger where doc_number = :'doc' and warehouse = 'IN_TRANSIT' \gset
select coalesce(sum(b.qty), 0) as post_bin_qty from public.inv_balance b where b.warehouse = :'to_wh' and b.bin = :'bin' and b.sku in (select sku from t_src) \gset
select count(*) as post_layer_dest, coalesce(sum(qty), 0) as post_layer_dest_qty from public.inv_layer where origin_type = 'transfer' and doc_number = :'doc' and warehouse = :'to_wh' \gset

\echo '⑤ 원가 — SKU 마다 레이어 · short'
select sku, qty_ea, (r ->> 'layers')::int as layers, (r ->> 'short_qty')::numeric as short_qty, round((r ->> 'amount')::numeric, 2) as amount from t_cost where (r ->> 'short_qty')::numeric > 0 or (r ->> 'layers')::int = 0 order by sku;

\o /dev/null
select pg_temp.chk('④ 원장에 SKU × 2 줄이 들어갔다', :ins_n = :src_n * 2 and :post_ledger = :pre_ledger + :ins_n);
select pg_temp.chk('⑤ 이 문서의 IN_TRANSIT 잔고 = 0', :post_transit_doc = 0 and :pre_transit_doc = :src_ea);
select pg_temp.chk('⑤ 도착 칸 잔고가 EA 만큼 늘었다', :post_bin_qty = :pre_bin_qty + :src_ea);
select pg_temp.chk('⑤ 도착 창고 레이어 수량 = EA − short(원가 미상 레이어 없음)', :post_layer_dest_qty = :src_ea - :cost_short and :pre_layer_dest = 0);
select pg_temp.chk('⑤ 레이어 short 0(TR-06397 은 18 이 기준)', case when :'doc' = 'TR-06397' then :cost_short = 18 else :cost_short = 0 end);
\o

\echo '⑤ 레이어: SKU' :cost_n '· 레이어' :cost_layers '· short' :cost_short '· 금액 CAD' :cost_amount '· 도착 창고 레이어 수량' :post_layer_dest_qty
\echo '⑥ 검산'
select n, case when ok then 'OK      ' else 'MISMATCH' end as verdict, name from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as mismatch_n from t_res \gset
\echo '⑥ OK' :ok_n '· MISMATCH' :mismatch_n

\if :{?rehearsal}
\echo '[REHEARSAL] raise 없음 — 위 판정을 읽는다'
\else
do $$ begin
  if (select count(*) from t_res where not ok) > 0 then
    raise exception 'tf-transit-arrive-manual: % check(s) failed — nothing was saved', (select count(*) from t_res where not ok);
  end if;
end $$;
\echo '⑥ 끝 —' :'doc' '전량이' :'to_wh' '/' :'bin_name' '에 들어왔다 · IMS 문서는 만들지 않았다(이 문서는 창구 inv_transfer_open_in_transit 이 「도착 다리 있음」 으로 거부한다)'
\endif
