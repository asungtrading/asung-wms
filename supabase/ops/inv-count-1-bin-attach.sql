-- supabase/ops/inv-count-1-bin-attach.sql — bin 없는 잔고 넷을 실사(2026-11-03 토론토)로 찾은 칸에 붙인다 (판정 907 · deferred 422 · inv-count-1 · 2026-11-09)
-- [Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ 옛 운영 asung-WMS 에 돌리지 않는다(⓪ 가드가 막는다)
--
-- 무엇: inv_balance 의 bin '' 칸에 남은 수량 넷(IMS = 실물 · 수량 조정 없음)을 실사로 찾은 칸으로 옮긴다 — 창고 합 무변 · 원가 무변.
--   AIA03588 토론토 '' 6 → Z010101 · EBI03960 토론토 '' 6 → F020502(14 + 6 = 20 = 실물) · UNF18259 토론토 '' 2 → E030803(콤보) · UNF18155 에드먼턴 '' 1 → EU050402(콤보)
-- 왜 ops 인가: 조정 창구 inv_adjust_line_set 은 활성 bin 이 반드시 있어야 해서 bin '' 잔고는 화면 · 창구로 못 고친다(판정 907 · 스킬 null_bin_nonzero).
-- 꼴(inv-count-0 ⬜1 · 받음): 문서 MANUAL-907-BIN · doc_type adjustment · source manual · 두 다리 모두 event_type adjust_existing · 같은 날(occurred_on = ims_today() · 적용하는 날)
--   · + 다리 seq 1(그 칸) · − 다리 seq 2('' 칸) · line_ref sku|창고(두 다리는 bin 이 달라 inv_ledger_event_uq 를 지나간다) · amount null · raw.count_on 2026-11-03(실사한 날 · Caleb 확인)
--   왜 adjust_existing 짝인가: 재생성 inv_layer_apply_adjust(라이브 = 20260930144905)는 (doc, sku, 창고, event_type) 로 순액을 내고 adjust_existing 순액 0 이면 아무것도 하지 않는다 = 레이어 효과 0.
--   왜 transfer 꼴이 아닌가: inv_layer_apply 가 bin_move 를 지나치는 조건은 source ims 뿐 — manual transfer_in/out 은 Cin7 트랜스퍼 갈래로 간다(코드).
--   하루 원가 장(qbo_cost_expected scope = source 'ims' 문서만) 범위 밖 · 레이어 0 → 장 0 · QBO 0.
-- 트리거(inv_ledger): inv_ledger_bgrade_guard 는 source ims 만 본다(manual 통과) · shop_stock_queue_trigger 가 listing 있는 제품 × live 스토어에 열린 줄을 세우지만 창고 합이 같아 drain 이 skipped_same 으로 건너뛴다(판정 422).
-- 안 하는 것: 레이어 · 원가 · 수량 조정 · 콤보 되돌리기(화면 조정 두 장 · 이 차수 뒤 Caleb) · 다른 칸 옮기기(AS92087 · PRO00124 · PAL04170 · 화면 inv_move) · 다른 행은 바꾸지 않는다.
-- 꼴: 마이그레이션 아님 · 함수 아님 · 한 번 · begin/commit 없음(-1 이 한 트랜잭션) · 검산이 하나라도 어긋나면 raise → 전부 되돌아간다.
-- ⚠️ 문장 수를 아낀다 — 이 DB(pooler · ca-central-1)는 문장마다 왕복 ≈ 0.3 s 라 질의 비용이 아니라 문장 수가 시간이다(첫 판 65 문장 = 21 s → 16 문장 · 시험 1 회차 ≈ 6 s).
--    inv_balance 는 원장 10 만 행을 합치는 뷰(≈ 0.5 s) — 전 · 후 한 번씩 temp 표로 굳혀 읽는다.
-- 실행(Caleb · 레포 뿌리에서):
--   시험(끝에 rollback · Claude Code 가 돌린다):
--     psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -c 'begin' -f supabase/ops/inv-count-1-bin-attach.sql -c 'rollback'
--   적용(commit):
--     psql "$(cat ~/.asung-testdb-url)" -X -1 -v ON_ERROR_STOP=1 -c "set local lock_timeout = '3s'" -f supabase/ops/inv-count-1-bin-attach.sql > ~/inv-count-1.log 2>&1; echo "exit=$?"
--   확인(적용 뒤 · 쓰기 0 · 넣기를 건너뛰고 넣은 것을 센다): 위 적용 명령에 -v check=1
-- 되돌리기(적용 뒤): delete from public.inv_ledger where source = 'manual' and doc_number = 'MANUAL-907-BIN' and raw ->> 'prompt' = 'inv-count-1';
--   (before-delete 트리거 없음 · after-delete 는 Shopify 큐뿐 · 레이어 · done 표는 건드린 것이 없다 · 시퀀스 무접촉 — identity 는 되돌려도 번호가 비는 것뿐)
-- 차례: ⓪ 이 DB 확인 → ① 계획 넷 · 기준 지문 → ② 넣기 전 확인(raise) → ③ 넣기 8 행 → ④ 검산 → ⑤ 읽기(보고만) → 결과

-- ⓪ 이 DB 확인 (1/2) — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄)
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

-- ⓪ 이 DB 확인 (2/2) — po_line(IMS 전용 표) · 함께: 타임아웃 · 결과 표 · chk · 계획 넷(문장 하나로)
do $$ begin
  if to_regclass('public.po_line') is null then
    raise exception using errcode = 'WM501', message = 'STOP - not Asung-IMS: po_line missing - this is not the IMS project. Nothing was changed.';
  end if;
  perform set_config('lock_timeout', '3s', true);
  perform set_config('statement_timeout', '60s', true);
  create temp table t_res (n int generated always as identity, name text, ok boolean) on commit drop;
  create function pg_temp.chk(p_name text, p_ok boolean) returns void language sql as 'insert into t_res (name, ok) values (p_name, coalesce(p_ok, false))';
  -- ① 계획 넷(하드코딩 · inv-count-0 회신 · 실사 2026-11-03)
  create temp table t_plan on commit drop as
  select * from (values ('AIA03588', 'Asung Trading Inc.', 'Z010101',  6::numeric),
                        ('EBI03960', 'Asung Trading Inc.', 'F020502',  6),
                        ('UNF18259', 'Asung Trading Inc.', 'E030803',  2),
                        ('UNF18155', 'Asung - Edmonton',   'EU050402', 1)) v(sku, warehouse, bin_to, qty);
  -- ① 기준 지문(전) — 잔고 뷰를 한 번 굳힌다
  create temp table t_bal_pre on commit drop as select * from public.inv_balance;
end $$;

\if :{?check}
\echo '[CHECK] check=1 — ③ 넣기는 건너뛴다 · 넣은 것을 센다(적용 뒤 확인 실행)'
\endif

-- ═══ ① 넷의 '' 잔고 · 도착 칸 · 창고 합 · 칸 · 제품 상태(t_bal_pre 에서) ═══
create temp table t_pre on commit drop as
select p.sku, p.warehouse, p.bin_to, p.qty,
       coalesce((select b.qty from t_bal_pre b where b.sku = p.sku and b.warehouse = p.warehouse and b.bin = ''), 0) as nobin_qty,
       coalesce((select b.qty from t_bal_pre b where b.sku = p.sku and b.warehouse = p.warehouse and b.bin = p.bin_to), 0) as dest_qty,
       coalesce((select sum(b.qty) from t_bal_pre b where b.sku = p.sku and b.warehouse = p.warehouse), 0) as wh_qty,
       (select rb.is_active from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where w.name = p.warehouse and rb.name = p.bin_to) as bin_active,
       (select rb.is_bgrade from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where w.name = p.warehouse and rb.name = p.bin_to) as bin_bgrade,
       (select pr.is_active from public.product pr where pr.sku = p.sku) as prod_active,
       (select pr.sellable from public.product pr where pr.sku = p.sku) as prod_sellable
  from t_plan p;
\echo '① 넣기 전'
select sku, warehouse, bin_to, qty, nobin_qty, dest_qty, wh_qty, bin_active, bin_bgrade, prod_active, prod_sellable from t_pre order by 1;

select to_char(public.ims_today(), 'YYYY-MM-DD') as today,
       (select count(*) from public.inv_ledger) as pre_ledger,
       (select count(*) from public.inv_ledger where doc_number = 'MANUAL-907-BIN') as pre_doc,
       (select count(*) from public.shop_stock_queue where done_at is null) as pre_queue,
       (select count(*) from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.done_at is null and p.sku not in (select sku from t_plan)) as pre_queue_other,
       (select count(*) from public.shop_store where is_active and live) as live_stores,
       (select coalesce(md5(string_agg(b.sku || '|' || b.warehouse || '|' || b.bin || '|' || b.qty, ',' order by b.sku, b.warehouse, b.bin)), '(none)')
          from t_bal_pre b where b.qty <> 0 and not exists (select 1 from t_plan p where p.sku = b.sku and p.warehouse = b.warehouse)) as pre_other_md5,
       (select coalesce(md5(string_agg(x.id || '|' || x.qty || '|' || v.remaining_qty || '|' || v.remaining_value, ',' order by x.id)), '(none)')
          from public.inv_layer x cross join lateral public.inv_layer_value(x.id) v where x.sku in (select sku from t_plan)) as pre_layer_md5,
       (select count(*) from public.inv_layer x where x.sku in (select sku from t_plan)) as pre_layer_n,
       (select coalesce(sum(qty), 0) from t_bal_pre where warehouse = 'IN_TRANSIT') as pre_transit,
       (select count(*) filter (where not (prod_active and prod_sellable)) from t_pre) as pre_prod_off,
       (select count(*) filter (where not coalesce(bin_active, false)) from t_pre) as pre_bin_off,
       (select count(*) filter (where coalesce(bin_bgrade, false)) from t_pre) as pre_bin_bgrade,
       (select count(*) filter (where nobin_qty <> qty) from t_pre) as pre_nobin_mismatch,
       (select count(*) filter (where nobin_qty <> 0) from t_pre) as pre_nobin_nonzero \gset
\echo '① 오늘(토론토 · occurred_on)' :today '· 실사 count_on 2026-11-03 · 원장 행' :pre_ledger '· 문서 행' :pre_doc '· 열린 큐' :pre_queue '(네 제품 밖' :pre_queue_other ') · live 스토어' :live_stores '· 레이어 행(네 SKU)' :pre_layer_n

-- ═══ ② 넣기 전 확인 — 하나라도 어긋나면 넣지 않는다 ═══
\o /dev/null
select pg_temp.chk('② 도착 칸 넷 활성(ref_bin.is_active)', :pre_bin_off = 0),
       pg_temp.chk('② 도착 칸 넷 B급 아님', :pre_bin_bgrade = 0),
       pg_temp.chk('② 네 제품 is_active · sellable(막지는 않는다 · 보고용)', :pre_prod_off = 0),
       pg_temp.chk('② '''' 잔고 = 계획 수량 6 · 6 · 2 · 1(check 모드는 0)', case when :{?check} then :pre_nobin_nonzero = 0 else :pre_nobin_mismatch = 0 end),
       pg_temp.chk('② 문서 MANUAL-907-BIN 아직 없다(check 모드는 8 행)', case when :{?check} then :pre_doc = 8 else :pre_doc = 0 end);
\o
\if :{?check}
\else
-- (psql 변수는 $$ 안에서 치환되지 않는다 — 표를 다시 읽는다)
do $$
declare v_doc int; v_mis int; v_off int;
begin
  select count(*) into v_doc from public.inv_ledger where doc_number = 'MANUAL-907-BIN';
  select count(*) filter (where nobin_qty <> qty), count(*) filter (where not coalesce(bin_active, false)) into v_mis, v_off from t_pre;
  if v_doc > 0 then
    raise exception using errcode = 'IM907', message = format('STOP - MANUAL-907-BIN already has %s rows - run with -v check=1 to verify. Nothing was changed.', v_doc);
  end if;
  if v_mis > 0 or v_off > 0 then
    raise exception using errcode = 'IM907', message = format('STOP - precondition failed: %s cell(s) whose no-bin balance differs from the plan, %s inactive destination bin(s). Nothing was changed.', v_mis, v_off);
  end if;
end $$;
\endif

-- ═══ ③ 넣기 — 8 행(SKU 마다 + 다리 · − 다리) ═══
\if :{?check}
\set ins_n 0
\else
with ins as (
  insert into public.inv_ledger (doc_type, doc_number, source, event_type, sku, warehouse, bin, line_ref, qty_delta, occurred_on, seq_hint, amount, raw)
  select 'adjustment', 'MANUAL-907-BIN', 'manual', 'adjust_existing', p.sku, p.warehouse, leg.bin, p.sku || '|' || p.warehouse, leg.qty, public.ims_today(), leg.seq, null,
         jsonb_build_object(
           'rule', 'stock that the ledger held with no bin was found in a real bin at the 2026-11-03 count (Toronto); quantity unchanged (IMS = physical), warehouse total unchanged, no layer or cost effect (adjust_existing pair nets to 0 per doc/sku/warehouse — inv_layer_apply_adjust)',
           'reason', format('inv-count-1: %s @ %s — move %s from (no bin) to %s', p.sku, p.warehouse, p.qty, p.bin_to),
           'leg', leg.name, 'bin_to', p.bin_to, 'count_on', '2026-11-03',
           'prompt', 'inv-count-1', 'decision', 907, 'deferred', 422, 'by', 'caleb', 'at', to_char(public.ims_today(), 'YYYY-MM-DD'))
    from t_plan p
    cross join lateral (values (p.bin_to, p.qty, 1::smallint, 'in'), ('', -p.qty, 2::smallint, 'out')) as leg(bin, qty, seq, name)
  returning id)
select count(*) as ins_n from ins \gset
\endif
\echo '③ 넣은 행' :ins_n

-- ═══ ④ 검산 — 잔고 뷰를 다시 한 번 굳힌다(문장 하나) ═══
do $$ begin
create temp table t_bal_post on commit drop as select * from public.inv_balance;
create temp table t_post on commit drop as
select p.sku, p.warehouse, p.bin_to, p.qty, p.nobin_qty as pre_nobin, p.dest_qty as pre_dest, p.wh_qty as pre_wh,
       coalesce((select b.qty from t_bal_post b where b.sku = p.sku and b.warehouse = p.warehouse and b.bin = ''), 0) as nobin_qty,
       coalesce((select b.qty from t_bal_post b where b.sku = p.sku and b.warehouse = p.warehouse and b.bin = p.bin_to), 0) as dest_qty,
       coalesce((select sum(b.qty) from t_bal_post b where b.sku = p.sku and b.warehouse = p.warehouse), 0) as wh_qty,
       (select count(*) from public.inv_ledger l where l.doc_number = 'MANUAL-907-BIN' and l.sku = p.sku and l.warehouse = p.warehouse) as doc_rows,
       (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = 'MANUAL-907-BIN' and l.sku = p.sku and l.warehouse = p.warehouse and l.event_type = 'adjust_existing') as doc_net,
       (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = 'MANUAL-907-BIN' and l.sku = p.sku and l.warehouse = p.warehouse and l.bin = p.bin_to) as doc_in,
       (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = 'MANUAL-907-BIN' and l.sku = p.sku and l.warehouse = p.warehouse and l.bin = '') as doc_out
  from t_pre p;
end $$;
\echo '④ 넣은 뒤'
select sku, warehouse, bin_to, qty, nobin_qty, pre_dest, dest_qty, pre_wh, wh_qty, doc_rows, doc_in, doc_out, doc_net from t_post order by 1;

select (select count(*) from public.inv_ledger) as post_ledger,
       (select count(*) from public.inv_ledger where doc_number = 'MANUAL-907-BIN') as post_doc,
       (select count(*) from public.inv_ledger where doc_number = 'MANUAL-907-BIN' and source = 'manual' and doc_type = 'adjustment' and event_type = 'adjust_existing'
           and raw ->> 'prompt' = 'inv-count-1' and raw ->> 'count_on' = '2026-11-03' and amount is null) as post_doc_shape,
       (select count(distinct occurred_on) from public.inv_ledger where doc_number = 'MANUAL-907-BIN') as post_doc_days,
       (select count(*) from public.inv_ledger where doc_number = 'MANUAL-907-BIN' and seq_hint = 1 and qty_delta > 0 and bin <> '') as post_in,
       (select count(*) from public.inv_ledger where doc_number = 'MANUAL-907-BIN' and seq_hint = 2 and qty_delta < 0 and bin = '') as post_out,
       (select count(*) from public.shop_stock_queue where done_at is null) as post_queue,
       (select count(*) from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.done_at is null and p.sku not in (select sku from t_plan)) as post_queue_other,
       (select count(*) from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.done_at is null and p.sku in (select sku from t_plan) and q.reason <> 'inv_ledger') as post_queue_plan_bad,
       (select coalesce(md5(string_agg(b.sku || '|' || b.warehouse || '|' || b.bin || '|' || b.qty, ',' order by b.sku, b.warehouse, b.bin)), '(none)')
          from t_bal_post b where b.qty <> 0 and not exists (select 1 from t_plan p where p.sku = b.sku and p.warehouse = b.warehouse)) as post_other_md5,
       (select coalesce(md5(string_agg(x.id || '|' || x.qty || '|' || v.remaining_qty || '|' || v.remaining_value, ',' order by x.id)), '(none)')
          from public.inv_layer x cross join lateral public.inv_layer_value(x.id) v where x.sku in (select sku from t_plan)) as post_layer_md5,
       (select count(*) from public.inv_layer x where x.sku in (select sku from t_plan)) as post_layer_n,
       (select coalesce(sum(qty), 0) from t_bal_post where warehouse = 'IN_TRANSIT') as post_transit,
       (select count(*) from t_bal_post b join t_plan p on p.sku = b.sku and p.warehouse = b.warehouse where b.bin = '' and b.qty <> 0) as nobin_left,
       (select count(*) from t_post where nobin_qty <> 0) as post_nobin_nonzero,
       (select count(*) from t_post where doc_in <> qty) as post_in_bad,
       (select count(*) from t_post where dest_qty <> pre_dest + qty) as post_dest_bad,
       (select count(*) from t_post where wh_qty <> pre_wh) as post_wh_bad,
       (select count(*) from t_post where doc_net <> 0 or doc_rows <> 2) as post_net_bad \gset

-- 재생성 흉내 — inv_layer_apply_adjust 를 네 키의 첫 다리로 직접 부른다(done 표는 temp · inv_layer_apply_reset_done 이 만든다)
--   plpgsql 예외 블록 = 서브트랜잭션: 결과를 메시지에 실어 raise → 잡아서 읽는다 = 안의 쓰기(있다면 · done temp 표 포함)는 전부 되돌아간다(쓰기 0 보장 · 문장 하나)
do $$
declare v jsonb;
begin
  begin
    perform public.inv_layer_apply_reset_done();
    select jsonb_build_object('keys', count(*), 'processed', coalesce(sum(a.o_processed), 0), 'layers', coalesce(sum(a.o_layers), 0), 'rows', coalesce(sum(a.o_rows), 0),
                              'short', coalesce(sum(a.o_short), 0), 'unknown', coalesce(sum(a.o_unknown), 0)) into v
      from (select min(l.id) as id from public.inv_ledger l where l.doc_number = 'MANUAL-907-BIN' group by l.sku, l.warehouse) k
      cross join lateral public.inv_layer_apply_adjust(k.id, null) a;
    v := v || jsonb_build_object('doc_layers', (select count(*) from public.inv_layer where doc_number = 'MANUAL-907-BIN'));
    raise exception using errcode = 'IM9R0', message = v::text;                 -- 되돌리기용(결과를 실어 나른다)
  exception when sqlstate 'IM9R0' then
    v := sqlerrm::jsonb;
  end;
  raise notice '④ 재생성 흉내 — %', v;
  perform pg_temp.chk('④ 재생성 흉내 — 키 4 · processed 4 · layers 0 · rows 0 · short 0 · unknown 0 · 문서 레이어 0',
    (v ->> 'keys')::int = 4 and (v ->> 'processed')::int = 4 and (v ->> 'layers')::int = 0 and (v ->> 'rows')::int = 0
    and (v ->> 'short')::int = 0 and (v ->> 'unknown')::int = 0 and (v ->> 'doc_layers')::int = 0);
end $$;

\o /dev/null
select pg_temp.chk('④ 문서 8 행 · 꼴(manual · adjustment · adjust_existing · prompt · count_on · amount null) 8 · 한 날', :post_doc = 8 and :post_doc_shape = 8 and :post_doc_days = 1),
       pg_temp.chk('④ + 다리 4(seq 1 · 그 칸) · − 다리 4(seq 2 · '''')', :post_in = 4 and :post_out = 4),
       pg_temp.chk('④ 네 SKU '''' 잔고 0', :nobin_left = 0 and :post_nobin_nonzero = 0),
       pg_temp.chk('④ 도착 칸 = 전 + n(check 모드: 문서 + 다리 = n)', case when :{?check} then :post_in_bad = 0 else :post_dest_bad = 0 end),
       pg_temp.chk('④ 창고 합 무변(SKU × 창고)', :post_wh_bad = 0),
       pg_temp.chk('④ (doc, sku, 창고, adjust_existing) 순액 0 × 4 · 키마다 2 행', :post_net_bad = 0),
       pg_temp.chk('④ 네 SKU 밖 칸 전체 무변(md5)', :'pre_other_md5' = :'post_other_md5'),
       pg_temp.chk('④ 레이어 무변 — 네 SKU 행 · 남은 수량 · 남은 가치(md5)', :'pre_layer_md5' = :'post_layer_md5' and :pre_layer_n = :post_layer_n),
       pg_temp.chk('④ IN_TRANSIT 무변', :pre_transit = :post_transit),
       pg_temp.chk('④ 원장 행 = 전 + 8(check 모드는 전 그대로)', case when :{?check} then :post_ledger = :pre_ledger else :post_ledger = :pre_ledger + 8 end),
       pg_temp.chk('④ Shopify 큐 — 네 제품 밖 열린 줄 무변 · 새 줄은 네 제품 × live 스토어 이하(reason inv_ledger · drain 이 skipped_same 으로 건너뛴다)', :post_queue_other = :pre_queue_other and :post_queue - :pre_queue <= 4 * :live_stores and (:{?check} or :post_queue_plan_bad = 0));
\o

-- ═══ ⑤ 읽기(보고만 · 손대지 않는다) — EDM UNF18049 칸별(실물 6) · EDM ORS11030 실사 11-03 의 잔고(occurred_on ≤ 11-03) · 그 뒤 사건 ═══
\echo '⑤ 읽기'
select 'UNF18049 EDM bins' as what,
       (select string_agg(coalesce(nullif(b.bin, ''), '(no bin)') || '=' || b.qty, ' · ' order by b.bin) from t_bal_post b where b.sku = 'UNF18049' and b.warehouse = 'Asung - Edmonton') as value
union all
select 'ORS11030 EDM on 2026-11-03 / now',
       ((select coalesce(sum(s.qty), 0) from public.inv_snapshot s where s.snapshot_key = (select value from public.inv_config where key = 'baseline_snapshot_key') and s.sku = 'ORS11030' and s.warehouse = 'Asung - Edmonton')
        + (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.sku = 'ORS11030' and l.warehouse = 'Asung - Edmonton' and l.occurred_on <= date '2026-11-03'))::text
       || ' / ' || (select coalesce(sum(b.qty), 0) from t_bal_post b where b.sku = 'ORS11030' and b.warehouse = 'Asung - Edmonton')::text
union all
select 'ORS11030 EDM after 2026-11-03',
       (select string_agg(l.occurred_on || ' ' || l.event_type || ' ' || l.doc_number || ' ' || l.bin || ' ' || l.qty_delta, ' · ' order by l.occurred_on, l.seq_hint, l.id)
          from public.inv_ledger l where l.sku = 'ORS11030' and l.warehouse = 'Asung - Edmonton' and l.occurred_on > date '2026-11-03');

-- ═══ 결과 ═══
\echo '═══ 결과 ═══'
select n, case when ok then 'OK ' else 'MISMATCH' end as r, name from t_res order by n;
do $$
declare v_ok int; v_bad int;
begin
  select count(*) filter (where ok), count(*) filter (where not ok) into v_ok, v_bad from t_res;
  raise notice 'OK % · MISMATCH %', v_ok, v_bad;
  if v_bad > 0 then
    raise exception using errcode = 'IM907', message = format('%s check(s) failed - everything rolled back. Nothing was changed.', v_bad);
  end if;
end $$;
