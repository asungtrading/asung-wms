-- supabase/tests/wms_balance_perf_3_capture.sql — wms-balance-perf-3 ③(deferred 450) 결과 받기(파일 diff 용 · ① · ②-a 캡처와 같은 꼴) (2026-11-02)
-- [메인 IMS · Asung-IMS] 트랜잭션 없음(문장마다 자동 커밋 읽기 · 세션 read only) · 지문 머리 · 꼬리(다르면 그 입력의 옛 결과를 다시 받는다)
--   입력 = wms_pick_shelf(창고마다 TRF-00003 sku · 잔고 있는 300 · 세트 + 모르는 + 빈 + 음수) · bgrade_stock(null · 창고마다) · inv_move_bin_contents(창고마다 재고 많은 활성 칸 10 · B급 칸 · 비활성 칸 — 거부는 거부 글로) ·
--          ref_bin_bgrade_set 의 장부 줄 직접(같은 칸들 · count · sum — 함수는 volatile 이라 부르지 않는다) — 직원 문은 request.jwt.claims 에 활성 admin sub
--   Claude Code(적용 전): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v out=<파일> -f supabase/tests/wms_balance_perf_3_capture.sql   (호출마다 ms 는 stdout 의 Time: 줄)
--   Caleb(적용 뒤): 같은 명령에 다른 out → diff <옛> <새>  (기대 차이 = 첫 FP 줄의 functions md5 · indexes 수 뿐)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
create temp table t_in (ord serial, name text, sql text);
create temp table t_bin (warehouse_id uuid, whn text, bin_id uuid, bin text, kind text);                 -- read only 로 가기 전에(읽기 전용 트랜잭션은 create · create function 을 막는다 · insert 는 된다)
create function pg_temp.mv(p_wh uuid, p_bin uuid) returns text language plpgsql as $$
begin return public.inv_move_bin_contents(p_wh, p_bin)::text; exception when others then return 'ERR ' || sqlerrm; end $$;
set default_transaction_read_only = on;
set statement_timeout = '20s';
select set_config('request.jwt.claim.sub', s.auth_user_id::text, false), set_config('request.jwt.claims', json_build_object('sub', s.auth_user_id, 'role', 'authenticated')::text, false)
  from (select auth_user_id from public.ims_staff where is_active and auth_user_id is not null and role = 'admin' order by created_at limit 1) s;
\o :out
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || ' functions ' ||
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_shelf', 'bgrade_stock', 'inv_move_bin_contents', 'ref_bin_bgrade_set')) ||
       ' indexes ' || (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('inv_ledger_wh_bin_sku_idx', 'inv_snapshot_key_wh_bin_sku_idx'));
insert into t_in (name, sql)
  select 'SHELF ' || w.name || ' ' || k.lbl, format('select %L || '' '' || public.wms_pick_shelf(%L::uuid, %L::text[])::text', 'SHELF ' || w.name || ' ' || k.lbl, w.id, k.skus)
  from public.ref_warehouse w
  cross join lateral (
    select 'TRF-00003 skus' as lbl, (select array_agg(distinct l.sku order by l.sku) from public.wms_order_doc_line l join public.wms_order_doc d on d.doc_id = l.doc_id where d.doc_number = 'TRF-00003') as skus
    union all select 'top 300', (select array_agg(x.sku) from (select b.sku from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty <> 0 order by b.sku limit 300) x)
    union all select 'sets+unknown+blank+negative', (select array_agg(x.sku) from (select c.sku from public.product c where c.parent_product_id is not null and exists (select 1 from public.inv_balance b where b.sku = (select pp.sku from public.product pp where pp.id = c.parent_product_id) and b.warehouse = w.name and b.qty <> 0) order by c.sku limit 20) x)
                                                     || array['ZZZ-NOPE-1', ' ', ''] || (select array_agg(x.sku) from (select b.sku from public.inv_balance b join public.product p on p.sku = b.sku where b.warehouse = w.name and b.qty < 0 order by b.sku limit 20) x)
  ) k
  where w.is_active and k.skus is not null order by w.name, k.lbl;
insert into t_in (name, sql) values ('BGRADE all', 'select ''BGRADE all '' || public.bgrade_stock(null)::text');
insert into t_in (name, sql) select 'BGRADE ' || w.name, format('select %L || '' '' || public.bgrade_stock(%L::uuid)::text', 'BGRADE ' || w.name, w.id) from public.ref_warehouse w where w.is_active order by w.name;
insert into t_bin
  select w.id as warehouse_id, w.name as whn, rb.id as bin_id, rb.name as bin, k.kind
  from public.ref_warehouse w
  cross join lateral (
    (select rb.id, 'top' as kind from public.ref_bin rb join (select b.bin, count(*) as n from public.inv_balance b where b.warehouse = w.name and b.qty <> 0 and b.bin <> '' group by 1) c on c.bin = rb.name where rb.warehouse_id = w.id and rb.is_active and not rb.is_bgrade order by c.n desc, rb.name limit 10)
    union all (select rb.id, 'bgrade' from public.ref_bin rb where rb.warehouse_id = w.id and rb.is_bgrade order by rb.name limit 1)
    union all (select rb.id, 'inactive' from public.ref_bin rb where rb.warehouse_id = w.id and not rb.is_active order by rb.name limit 1)
  ) k join public.ref_bin rb on rb.id = k.id
  where w.is_active;
insert into t_in (name, sql)
  select 'MOVE ' || b.whn || ' ' || b.kind || ' ' || b.bin, format('select %L || '' '' || pg_temp.mv(%L::uuid, %L::uuid)', 'MOVE ' || b.whn || ' ' || b.kind || ' ' || b.bin, b.warehouse_id, b.bin_id) from t_bin b order by b.whn, b.kind, b.bin;
insert into t_in (name, sql)
  select 'BGSET-LINE ' || b.whn || ' ' || b.kind || ' ' || b.bin, format('select %L || '' '' || (select jsonb_build_array(count(*), coalesce(sum(x.qty), 0)) from public.inv_balance x where x.warehouse = %L and x.bin = %L and x.qty <> 0)::text', 'BGSET-LINE ' || b.whn || ' ' || b.kind || ' ' || b.bin, b.whn, b.bin) from t_bin b where b.kind in ('top', 'bgrade') order by b.whn, b.kind, b.bin;
select 'INPUT ' || ord || ' ' || name from t_in order by ord;
\timing on
select sql from t_in order by ord \gexec
\timing off
select 'FP ' || (select max(id) from public.inv_ledger) || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.wms_pick_line_bins) || ' (end)';
select 'inputs ' || count(*) from t_in;
