-- supabase/tests/wms_balance_perf_1_capture.sql — wms-balance-perf-1 ①(deferred 450) 결과 받기(파일 diff 용 · 이견 6 Caleb 답) (2026-11-02)
-- [메인 IMS · Asung-IMS] 옛 결과(적용 전)와 새 결과(적용 뒤)를 같은 입력으로 파일에 받아 diff 한다 — 트랜잭션 없음(문장마다 자동 커밋 읽기 · 세션 read only) · 10 초 넘는 잠금 없음
--   장부 지문(ledger max(id) · count · snapshot count · 계획 칸 행 수 · 보관용 행 수)을 파일 머리 · 꼬리에 적는다 — diff 때 지문이 다르면 MISMATCH 로 읽지 말고 그 입력의 옛 결과를 다시 받는다(밤에도 Shopify 오더 · 크론이 돈다)
--   입력 = 열린 픽 과제 전부(하나씩) + 열린 팩 과제 전부 + at_wms · picking 문서 전부 + TRF-00003(324 줄) + 콤보 줄 있는 문서 + ims_last_bin(창고마다 TRF-00003 제품 · 날카로운 집합 1 · 10 · 500) — 입력 목록 자체도 파일에 적는다
--   쓰기 0 — 전부 읽기 창구 · product_bom_set 은 부르지 않는다(definer · 직원 열쇠 — 그 한 줄은 _check.sql K7)
--   Claude Code(적용 전): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v out=<파일> -f supabase/tests/wms_balance_perf_1_capture.sql   (결과는 out 파일 · 호출마다 ms 는 stdout 의 Time: 줄)
--   Caleb(적용 뒤): 같은 명령에 다른 out → diff <옛> <새>
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
-- 입력 목록 임시 표(read only 로 가기 전에 만든다 — 읽기 전용 트랜잭션은 create temp table 도 막는다 · insert 는 된다)
create temp table t_in (ord serial, name text, sql text);
set default_transaction_read_only = on;
set statement_timeout = '20s';
\o :out
-- ⚠️ \o :out 는 열 때마다 파일을 비운다 — 여기서 한 번만 열고 끝까지 둔다(Time: 줄은 stdout)
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || '/' || (select count(*) from public.product_bin_overflow) || ' functions ' ||
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_lines', 'so_pick_plan', 'ims_last_bin', 'product_bom_set', 'ims_inv_balance_of'));
-- 입력 목록 → 임시 표(문장마다 따로 돈다 · \gexec)
insert into t_in (name, sql)
  select 'PICK task ' || t.id || ' ' || d.doc_number, format('select %L || '' '' || public.wms_pick_lines(array[%s]::bigint[])::text', 'PICK task ' || t.id, t.id)
  from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.status in ('pending', 'in_progress') order by t.id;
insert into t_in (name, sql)
  select 'PACK task ' || k.id, format('select %L || '' '' || public.wms_pick_lines(null, %s)::text', 'PACK task ' || k.id, k.id)
  from public.wms_pack_tasks k where k.status not in ('completed', 'cancelled') order by k.id;
insert into t_in (name, sql)
  select 'PLAN ' || d.doc_number, format('select %L || '' '' || public.so_pick_plan(%L::uuid)::text', 'PLAN ' || d.doc_number, d.doc_id)
  from public.wms_order_doc d where d.status in ('at_wms', 'picking') or d.doc_number = 'TRF-00003' or exists (select 1 from public.so_line sl where sl.so_id = d.doc_id and sl.combo_line_id is not null)
  order by d.doc_number;
insert into t_in (name, sql)
  select 'LASTBIN ' || w.name || ' ' || s.label,
         format('select %L || '' '' || public.ims_last_bin(%L::uuid[], %L::uuid)::text', 'LASTBIN ' || w.name || ' ' || s.label, s.pids, w.id)
  from public.ref_warehouse w
  cross join lateral (
    select 'TRF-00003 products' as label, (select array_agg(distinct l.stock_product_id) from public.wms_order_doc_line l join public.wms_order_doc d on d.doc_id = l.doc_id where d.doc_number = 'TRF-00003') as pids
    union all select 'sharp 500', (select array_agg(pid) from (
        (select p.id as pid from public.ref_bin rb join public.inv_balance b on b.warehouse = w.name and b.bin = rb.name and rb.warehouse_id = w.id join public.product p on p.sku = b.sku where rb.is_bgrade and b.qty <> 0 order by p.sku limit 50)
        union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.bin = '' and b.qty <> 0 order by p.sku limit 150)
        union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by p.sku limit 150)
        union (select p.id from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and exists (select 1 from public.product c where c.parent_product_id = p.id) order by p.sku limit 150)) x)
    union all select 'sharp 10', (select array_agg(pid) from (select p.id as pid from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty <> 0 order by p.sku limit 10) x)
    union all select 'one', (select array_agg(pid) from (select p.id as pid from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty > 0 order by b.qty desc, p.sku limit 1) x)
  ) s
  where w.name in ('Asung Trading Inc.', 'Asung - Edmonton') and s.pids is not null
  order by w.name, s.label;
select 'INPUT ' || ord || ' ' || name from t_in order by ord;
\timing on
select sql from t_in order by ord \gexec
\timing off
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || '/' || (select count(*) from public.product_bin_overflow) || ' (end)';
select 'inputs ' || count(*) from t_in;
