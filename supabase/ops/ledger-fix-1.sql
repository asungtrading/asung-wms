-- supabase/ops/ledger-fix-1.sql — PO-01382 의 LAC793xx 옛 벌(10-15 · 14 줄 · 1,314) 을 원장에서 상쇄한다 (판정 892 · ledger-fix-1 · 2026-10-30)
-- [테스트 · Asung-IMS — 컷오버판 원장(§E · 2026-10-30) 위에서 · Go live 전]
--
-- 무엇: Cin7 이 PO-01382 의 L.A. COLORS 파운데이션 14 줄의 SKU 를 LAC793xx → LAC593xx 로 바꿨다. 수집기는 10-15 에 LAC793xx 로 한 벌,
--       10-19 에 같은 줄 GUID · 같은 ProductID 로 LAC593xx 한 벌을 더 썼고 첫 벌을 거두지 않았다(유니크 키에 sku 가 들어 충돌이 아니다).
--       ⇒ 원장에 없는 재고 1,314(LAC793xx · Cin7 0 · product 표에도 없는 SKU)가 남았다(layer-gap-0 결론 2 · 3).
--       10-15 벌 각 줄을 선례(2026-09-25 PO-01361 · docs/sessions/2026-09-25-undone-re-keying.md §B-3) 와 같은 꼴로 되돌린다:
--       source manual · 원래 event_type(po_in) · line_ref = 원래 GUID || ':reversal' · qty_delta 부호 반전 · occurred_on · seq_hint · bin · warehouse 원행 그대로.
--       날짜를 원래 날짜(2026-10-15)로 두는 이유: ① 선례와 같다 ② as-of 잔고(p_until)가 10-15 ~ 10-29 구간에서도 맞는다 ③ A 차수(§H 재생성 · po_in 순액)가 같은 날 안에서 상쇄해 레이어가 서지 않는다.
-- 안 하는 것: 레이어(inv_layer*)는 건드리지 않는다 — A 차수(inv_layer_apply_po_in 순액) 뒤 §H 가 다시 만든다. 10-19 벌(LAC593xx) · 다른 356 줄 · 음수 21 칸 · 다른 unknown 칸은 범위 밖.
-- 꼴:  마이그레이션 아님 · 함수 아님 · 한 번. begin · commit 없음(-1 이 한 트랜잭션) · 검산이 하나라도 어긋나면 raise → 전부 되돌아간다.
-- 실행(Caleb · 레포 뿌리에서):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/ledger-fix-1.sql > ~/ledger-fix-1.log 2>&1; echo "exit=$?"
-- 확인 실행(적용 뒤 · 쓰기 0 · 넣는 문장을 건너뛰고 검산만):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v check=1 -f supabase/ops/ledger-fix-1.sql
-- 리허설(Claude Code · begin → rollback): supabase/tests/ledger_fix_1_rehearsal.sql 이 이 파일을 -v rehearsal=1 로 \i 한다(검산 어긋남은 찍기만 · raise 없음).
-- 되돌리기(적용 뒤): delete from inv_ledger where doc_number = 'PO-01382' and source = 'manual' and raw ->> 'prompt' = 'ledger-fix-1';  — 14 줄 · 그 뒤 §H 를 다시 돌린 적이 있으면 §H 도 다시.
-- 차례: ① 이 DB 확인 → ② 대조(전) · 기준값 → ③ 상쇄 줄 넣기 → ④ 검산 → ⑤ 결과

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

-- ① 이 DB 확인 (2/2) — po_line(IMS 전용 표)
do $$ begin
  if to_regclass('public.po_line') is null then
    raise exception using errcode = 'WM501', message = 'STOP - not Asung-IMS: po_line missing - this is not the IMS project. Nothing was changed.';
  end if;
end $$;

\if :{?rehearsal}
\echo '[REHEARSAL] rehearsal=1 — 검산 어긋남은 찍기만(raise 없음) · 잠금 시간은 장치가 정한다'
\else
set local lock_timeout = '3s';
set local statement_timeout = '60s';
\endif
\if :{?check}
\echo '[CHECK] check=1 — ③ 넣기는 건너뛴다 · 검산만(적용 뒤 확인 실행)'
\endif

create temp table t_res (n int generated always as identity, name text, ok boolean) on commit drop;
create function pg_temp.chk(p_name text, p_ok boolean) returns void language sql as $$ insert into t_res (name, ok) values (p_name, coalesce(p_ok, false)) $$;

-- ② 대조(전) — 옛 벌 후보: PO-01382 · cin7 · 10-15 벌 · 같은 GUID 로 뒤에 다른 sku 의 벌이 또 있는 줄 · 아직 :reversal 이 없는 줄
create temp table t_stale on commit drop as
select e.id, e.doc_type, e.doc_number, e.event_type, e.sku, e.warehouse, e.bin, e.line_ref, e.qty_delta, e.occurred_on, e.seq_hint, e.created_at,
       n.sku as new_sku, n.qty_delta as new_qty, n.created_at as new_created_at
  from public.inv_ledger e
  join public.inv_ledger n
    on n.doc_number = e.doc_number and n.line_ref = e.line_ref and n.event_type = e.event_type and n.warehouse = e.warehouse
   and n.source = 'cin7' and n.sku <> e.sku and n.created_at > e.created_at
 where e.doc_type = 'purchase' and e.doc_number = 'PO-01382' and e.event_type = 'po_in' and e.source = 'cin7'
   and e.created_at < timestamptz '2026-10-16 00:00+00'
   and e.sku ~ '^LAC793(5[1-9]|6[0-4])$';

\echo '② 옛 벌 ↔ 새 벌 짝(GUID 로) — 14 줄 · 1,314 이어야 한다'
select left(line_ref, 8) as guid, sku as old_sku, qty_delta as old_qty, created_at::date as old_on, new_sku, new_qty, new_created_at::date as new_on, occurred_on, seq_hint, bin,
       (select coalesce(sum(b.qty), 0) from public.inv_balance b where b.sku = s.sku and b.warehouse = s.warehouse) as old_sku_balance,
       (select coalesce(sum(b.qty), 0) from public.inv_balance b where b.sku = s.new_sku and b.warehouse = s.warehouse) as new_sku_balance,
       (select c.cin7_qty from public.inv_compare c where c.checked_on = date '2026-10-30' and c.sku = s.sku and c.warehouse = s.warehouse) as old_sku_cin7_1030,
       (select c.cin7_qty from public.inv_compare c where c.checked_on = date '2026-10-30' and c.sku = s.new_sku and c.warehouse = s.warehouse) as new_sku_cin7_1030
  from t_stale s order by sku;

select count(*) as pre_stale, coalesce(sum(qty_delta), 0) as pre_stale_qty from t_stale \gset
select count(*) as pre_already from public.inv_ledger r join t_stale s on r.doc_number = s.doc_number and r.line_ref = s.line_ref || ':reversal' and r.sku = s.sku \gset
\echo '② 후보' :pre_stale '줄 ·' :pre_stale_qty '· 이미 :reversal 이 있는 줄' :pre_already

-- 기준값(전) — 손대지 않아야 하는 것들의 지문
select count(*) as pre_ledger from public.inv_ledger \gset
select count(*) as pre_queue from public.shop_stock_queue \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as pre_bal_md5
  from public.inv_balance where qty <> 0 and sku !~ '^LAC793(5[1-9]|6[0-4])$' \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as pre_593_md5
  from public.inv_balance where sku ~ '^LAC593(5[1-9]|6[0-4])$' \gset
select coalesce(md5(string_agg(a.stock_pid || '|' || a.qty_ea || '|' || a.sales_alloc_ea || '|' || a.transfer_alloc_ea || '|' || a.bgrade_ea, ',' order by a.stock_pid)), '(none)') as pre_avail_md5
  from public.inv_available_base((select id from public.ref_warehouse where name = 'Asung Trading Inc.'),
                                 (select array_agg(id) from public.product where sku ~ '^LAC593(5[1-9]|6[0-4])$')) a \gset
select count(*) as pre_793_product from public.product where sku ~ '^LAC793(5[1-9]|6[0-4])$' \gset
select count(*) as pre_other_dup
  from (select doc_number, line_ref from public.inv_ledger where doc_number = 'PO-01382' and event_type = 'po_in' group by 1, 2 having count(distinct sku) > 1) d
 where not exists (select 1 from t_stale s where s.line_ref = d.line_ref) \gset

\o /dev/null
select pg_temp.chk('② 후보 14 줄', :pre_stale = 14);
select pg_temp.chk('② 후보 합 1,314', :pre_stale_qty = 1314);
select pg_temp.chk('② 아직 :reversal 없음(멱등 — check 모드는 14)', case when :{?check} then :pre_already = 14 else :pre_already = 0 end);
select pg_temp.chk('② LAC793xx 는 product 표에 없다(0)', :pre_793_product = 0);
select pg_temp.chk('② PO-01382 의 다른 줄에는 같은 GUID 두 sku 가 없다(0)', :pre_other_dup = 0);
select pg_temp.chk('② 후보 전부 같은 창고 · bin · 수량으로 새 벌과 짝이다', (select count(*) from t_stale where new_qty = qty_delta and bin = 'Z010101' and warehouse = 'Asung Trading Inc.' and occurred_on = date '2026-10-15' and seq_hint = 1) = :pre_stale);
\o

-- ③ 상쇄 줄 넣기 — 선례(09-25 PO-01361 §B-3) 와 같은 꼴
\if :{?check}
select :pre_already as ins_n, 0 as ins_qty \gset
\else
with ins as (
  insert into public.inv_ledger
    (doc_type, doc_number, source, event_type, sku, warehouse, bin, line_ref, qty_delta, occurred_on, seq_hint, raw)
  select s.doc_type, s.doc_number, 'manual', s.event_type, s.sku, s.warehouse, s.bin,
         s.line_ref || ':reversal',
         -s.qty_delta,
         s.occurred_on, s.seq_hint,
         jsonb_build_object(
           'rule',   'PO line SKU re-keyed in Cin7: PO-01382 lines for 14 L.A. COLORS Truly Matte Liquid Foundation shades were collected 2026-10-15 under SKU LAC793xx; Cin7 then renamed the products to LAC593xx and the collector wrote a second set 2026-10-19 under the same line GUIDs and ProductIDs without absorbing the first. reverse the stale 10-15 set',
           'reason', 'layer-gap-0 (2026-10-30): inv_compare 2026-10-30 LAC793xx ledger 99 / cin7 0 (unknown) and product has no LAC793xx row; same GUID carries LAC593xx 99 on 10-19 with inv_cost. decision 892 (ledger quantity only; layers rebuilt in the next round)',
           'original_line_ref', s.line_ref,
           'stale_written_at',  to_char(s.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
           'new_sku',           s.new_sku,
           'prompt',            'ledger-fix-1',
           'decision',          892,
           'by', 'caleb', 'at', '2026-10-30')
    from t_stale s
   where not exists (select 1 from public.inv_ledger r where r.doc_number = s.doc_number and r.line_ref = s.line_ref || ':reversal' and r.sku = s.sku)
  returning qty_delta)
select count(*) as ins_n, coalesce(sum(qty_delta), 0) as ins_qty from ins \gset
\endif
\echo '③ 넣은 줄' :ins_n '· 합' :ins_qty

-- ④ 검산 — 쓰기와 읽기는 다른 문장(위 \gset 뒤)
select count(*) as post_ledger from public.inv_ledger \gset
select count(*) as post_queue from public.shop_stock_queue \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as post_bal_md5
  from public.inv_balance where qty <> 0 and sku !~ '^LAC793(5[1-9]|6[0-4])$' \gset
select coalesce(md5(string_agg(sku || '|' || warehouse || '|' || bin || '|' || qty, ',' order by sku, warehouse, bin)), '(none)') as post_593_md5
  from public.inv_balance where sku ~ '^LAC593(5[1-9]|6[0-4])$' \gset
select coalesce(md5(string_agg(a.stock_pid || '|' || a.qty_ea || '|' || a.sales_alloc_ea || '|' || a.transfer_alloc_ea || '|' || a.bgrade_ea, ',' order by a.stock_pid)), '(none)') as post_avail_md5
  from public.inv_available_base((select id from public.ref_warehouse where name = 'Asung Trading Inc.'),
                                 (select array_agg(id) from public.product where sku ~ '^LAC593(5[1-9]|6[0-4])$')) a \gset
select count(*) as post_rev, coalesce(sum(r.qty_delta), 0) as post_rev_qty
  from public.inv_ledger r where r.doc_number = 'PO-01382' and r.source = 'manual' and r.event_type = 'po_in' and r.line_ref like '%:reversal' and r.sku ~ '^LAC793(5[1-9]|6[0-4])$' \gset
select count(*) as post_pairs
  from t_stale s join public.inv_ledger r
    on r.doc_number = s.doc_number and r.line_ref = s.line_ref || ':reversal' and r.sku = s.sku and r.warehouse = s.warehouse and r.bin = s.bin
   and r.event_type = s.event_type and r.source = 'manual' and r.qty_delta = -s.qty_delta and r.occurred_on = s.occurred_on and r.seq_hint = s.seq_hint
   and r.raw ->> 'original_line_ref' = s.line_ref and r.raw ->> 'prompt' = 'ledger-fix-1' \gset
select count(*) as post_793_nonzero from public.inv_balance where sku ~ '^LAC793(5[1-9]|6[0-4])$' and qty <> 0 \gset
select count(*) as post_793_cells, coalesce(sum(qty), 0) as post_793_qty from public.inv_balance where sku ~ '^LAC793(5[1-9]|6[0-4])$' \gset
select count(*) as post_793_pid_null from public.ims_inv_balance where sku ~ '^LAC793(5[1-9]|6[0-4])$' and product_id is null \gset

\o /dev/null
select pg_temp.chk('③ 넣은 줄 14 (check 모드는 이미 있던 14)', :ins_n = 14);
select pg_temp.chk('③ 넣은 합 −1,314 (check 모드는 0)', case when :{?check} then :ins_qty = 0 else :ins_qty = -1314 end);
select pg_temp.chk('④ :reversal 줄 14 · 합 −1,314', :post_rev = 14 and :post_rev_qty = -1314);
select pg_temp.chk('④ 옛 벌 14 줄 모두 선례 꼴의 짝이 하나씩(창고 · bin · 날짜 · seq · 부호 반전 · raw)', :post_pairs = 14);
select pg_temp.chk('④ LAC793xx 토론토 잔고 전부 0(잔고 ≠ 0 인 칸 0)', :post_793_nonzero = 0);
select pg_temp.chk('④ LAC793xx 잔고 합 0 (= Cin7 0)', :post_793_qty = 0);
select pg_temp.chk('④ LAC593xx 잔고 무변', :'pre_593_md5' = :'post_593_md5');
select pg_temp.chk('④ 다른 모든 칸(LAC793xx 밖) 잔고 무변', :'pre_bal_md5' = :'post_bal_md5');
select pg_temp.chk('④ 원장 줄 수 = 전 + 14 (check 모드는 + 0)', case when :{?check} then :post_ledger = :pre_ledger else :post_ledger = :pre_ledger + 14 end);
select pg_temp.chk('④ shop_stock_queue 줄 수 무변(LAC793xx 는 product 가 없어 트리거가 넣을 pid 가 없다)', :post_queue = :pre_queue);
select pg_temp.chk('④ inv_available_base(토론토 · LAC593xx) 무변', :'pre_avail_md5' = :'post_avail_md5');
select pg_temp.chk('④ ims_inv_balance 의 LAC793xx 칸은 product_id null(가용 셈에 든 적 없음)', :post_793_pid_null = :post_793_cells);
\o

-- ⑤ 결과
\echo '⑤ 검산'
select n, case when ok then 'OK' else 'MISMATCH' end as verdict, name from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as all_n from t_res \gset
\echo '⑤ OK' :ok_n '/' :all_n '· MISMATCH' :bad_n
\if :{?rehearsal}
\echo '[REHEARSAL] 끝 — 래퍼가 rollback 한다'
\else
do $$ begin
  if (select count(*) from t_res where not ok) > 0 then
    raise exception using errcode = 'WM502', message = format('ledger-fix-1: %s check(s) MISMATCH - nothing is kept (transaction rolls back)', (select count(*) from t_res where not ok));
  end if;
end $$;
\echo 'ledger-fix-1 끝 — 검산 전부 OK'
\endif
