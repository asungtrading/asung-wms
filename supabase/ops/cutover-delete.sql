-- supabase/ops/cutover-delete.sql — 컷오버 날 거래 지우기 (deferred 332 · 판정 746 ~ 754 · cutdel-1 · 2026-10-26)
-- [테스트 · Asung-IMS — 2026-11-01 부터 메인 시스템(판정 617)]
--
-- 무엇: 거래와 거기 딸린 것 79 표를 truncate 한 문장으로 비운다(판정 746 · cascade 없음 · 빠진 표가 있으면 PostgreSQL 이 오류로 멈춘다).
--       설정 · 마스터 · hist_ · 스토어 연결 기록 · 진단 로그(판정 751 · 752)는 그대로. 원장 · 레이어는 재적재(reload-procedure §P → §E 컷오버판 · §H)가 맡는다.
--       시험 마스터(판정 750)는 이 파일에 없다 — 자리만(⑧) · 다음 차수.
-- 꼴:  마이그레이션 아님 · 함수 아님(운영 DB 에 「거래 전부 지우기」 를 부를 수 있게 남기지 않는다) · 컷오버 날 한 번.
-- 실행(컷오버 날 · Caleb · 레포 뿌리에서):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/cutover-delete.sql > ~/cutover-delete.log 2>&1; echo "exit=$?"
-- 리허설(Claude Code · begin → rollback): supabase/tests/cutover_delete_rehearsal.sql 이 이 파일을 -v rehearsal=1 로 \i 한다.
--   rehearsal 갈래 = 관문 ② 는 찍기만 · ⑥ setval 은 「부를 값」 만 찍는다(setval 은 rollback 되지 않는다). 나머지는 같다.
-- ⚠️ 이 파일에 begin · commit 없음(-1 이 한 트랜잭션) · cascade 없음 · session_replication_role 안 씀 · 운영(asung-WMS) 주소는 쓰지 않는다.
-- 차례: ① 이 DB 확인 → ② 관문 → ③ 분류 대조 → ④ 남김 지문(전) → ⑤ truncate → ⑥ 번호 → ⑦ 뒤 검산 → ⑧ 750 자리
--
-- ① 이 DB 확인 (1/2) — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄).
--    ⚠️ inv_config.db_role 은 컷오버 뒤에도 'test' 로 둔다(cutdel-1 이견 3) — 이 표식은 「IMS 프로젝트」 라는 뜻이고 모든 마이그레이션 가드가 본다.
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

-- ① 이 DB 확인 (2/2) — reload-procedure §C 꼴: po_line(IMS 전용 표) · hist_so(승격될 DB 에만 있는 이력)
do $$ begin
  if to_regclass('public.po_line') is null or to_regclass('public.hist_so') is null then
    raise exception using errcode = 'WM501',
      message = 'STOP - not Asung-IMS: po_line or hist_so missing - this is not the IMS project. Nothing was changed.';
  end if;
end $$;

\if :{?rehearsal}
\echo '[REHEARSAL] rehearsal=1 — 관문은 찍기만 · setval 은 부르지 않는다 · 잠금 시간은 장치가 정한다'
\else
set local lock_timeout = '10s';
set local statement_timeout = '120s';
\endif

-- ② 관문 — 어기면 멈춘다(리허설은 찍기만). 각 관문의 「푸는 법」 은 raise 문장에.
select (select count(*) from cron.job where active)                                                              as g_cron,
       (select count(*) from public.mail_outbox where status in ('waiting_pdf', 'queued', 'sending'))              as g_mail,
       (select count(*) from public.drive_job   where status in ('waiting_pdf', 'queued', 'sending'))              as g_drive,
       (select count(*) from public.shop_store  where is_active)                                                  as g_store
\gset
\echo '② 관문 — cron active' :g_cron '· mail open' :g_mail '· drive open' :g_drive '· store active' :g_store '(전부 0 이어야 한다)'
\if :{?rehearsal}
\echo '   [REHEARSAL] 지금 이 관문은 닫혀 있다 / 열려 있다 를 찍기만 한다 — 컷오버 날 실행에서는 0 이 아니면 멈춘다'
\else
do $$
declare v_cron int; v_mail int; v_drive int; v_store int;
begin
  select count(*) into v_cron  from cron.job where active;
  select count(*) into v_mail  from public.mail_outbox where status in ('waiting_pdf', 'queued', 'sending');
  select count(*) into v_drive from public.drive_job   where status in ('waiting_pdf', 'queued', 'sending');
  select count(*) into v_store from public.shop_store  where is_active;
  if v_cron > 0 then
    raise exception 'GATE cron: % job(s) still active - run  select cron.alter_job(jobid, active := false) from cron.job;  then retry - nothing was changed', v_cron;
  end if;
  if v_mail > 0 then
    raise exception 'GATE mail: % mail(s) still open (waiting_pdf/queued/sending) - let ims-mail-* drain them before stopping cron, or cancel them (doc_mail_cancel) - nothing was changed', v_mail;
  end if;
  if v_drive > 0 then
    raise exception 'GATE drive: % drive job(s) still open - let ims-drive (cron 58) finish before stopping cron - nothing was changed', v_drive;
  end if;
  if v_store > 0 then
    raise exception 'GATE store: % Shopify store(s) still active - turn the test store off in Settings > Shopify Stores (ruling 751) - nothing was changed', v_store;
  end if;
end $$;
\endif

-- ③ 분류 대조 — public 의 모든 표가 지움(D) · 남김(K) · 다시 맞춤(R) 중 정확히 하나에 있어야 한다. 아니면 그 표 이름을 대고 멈춘다.
--    (컷오버 전에 새 표가 생기면 여기서 잡힌다 — deferred 332 의 「거래 표에 FK 거는 새 표」 규칙의 그물)
--    목록은 cutdel-0 · cutdel-1 실측(2026-10-26 · 172 표 = D 79 · K 73 · R 20). ⚠️ 표를 더하거나 뺄 때 이 목록과 reload-procedure §P 를 함께 고친다.
\set d1 'doc_file doc_mail_skip drive_job drive_shortcut inv_adjust inv_adjust_line inv_cost_adjust inv_move'
\set d2 'inv_move_line inv_transfer inv_transfer_line inv_transfer_settle mail_backorder_line mail_outbox mail_outbox_event mail_run'
\set d3 'mail_run_error po po_charge po_charge_alloc po_discount po_doc po_invoice po_invoice_discount'
\set d4 'po_invoice_line po_line po_payment po_payment_alloc po_receipt po_receipt_cost po_receipt_diff po_receipt_line'
\set d5 'po_receipt_post po_receipt_work shop_fulfill_queue shop_fulfillment shop_fulfillment_line shop_order shop_order_inbox shop_order_line'
\set d6 'shop_order_line_unshipped shop_order_queue shop_order_transaction shop_push_queue shop_stock_queue so so_backorder_close so_charge'
\set d7 'so_coupon so_credit so_credit_alloc so_credit_line so_demand_flag so_invoice so_invoice_line so_invoice_order'
\set d8 'so_line so_line_merge_source so_payment so_payment_alloc so_payment_order so_reserve so_stock_short_check wms_order_finalize'
\set d9 'wms_order_review wms_pack_task_lines wms_pack_tasks wms_pallet_items wms_pallets wms_pick_line_bins wms_pick_task_lines wms_pick_tasks'
\set d10 'wms_receipt_complete wms_reports wms_rollback_archive wms_rollback_log wms_task_holds wms_waves wms_worker_mistakes'
\set dall :d1 ' ' :d2 ' ' :d3 ' ' :d4 ' ' :d5 ' ' :d6 ' ' :d7 ' ' :d8 ' ' :d9 ' ' :d10
\set k1 'bgrade_price customer customer_address customer_contact doc_setting doc_template doc_template_active doc_template_event'
\set k2 'drive_folder hist_po hist_po_line hist_so hist_so_line ims_image_sync_queue ims_image_sync_runs ims_image_sync_skips'
\set k3 'ims_staff inv_config price_formula price_fx price_tier_rule product product_barcode product_bin_overflow'
\set k4 'product_bom product_family product_image product_price product_supplier product_tag pur_override_history pur_setting'
\set k5 'pur_sku_link pur_supplier_setting ref_account ref_bin ref_brand ref_carrier ref_category ref_currency'
\set k6 'ref_embed_host ref_payment_term ref_price_tier ref_region_alias ref_service ref_tax_region ref_tax_rule ref_unit'
\set k7 'ref_warehouse shop_call_log shop_customer shop_link_item shop_link_run shop_listing shop_location shop_media'
\set k8 'shop_product shop_stock_sent shop_store shop_variant so_deal so_deal_customer_rule so_deal_line so_deal_target'
\set k9 'so_deal_tier so_payment_account_default so_surcharge_group supplier supplier_address supplier_contact supplier_discount wms_drop_locations'
\set k10 'wms_zone_sequence'
\set kall :k1 ' ' :k2 ' ' :k3 ' ' :k4 ' ' :k5 ' ' :k6 ' ' :k7 ' ' :k8 ' ' :k9 ' ' :k10
\set r1 'inv_balance_diffs inv_bin_notes inv_collect_runs inv_compare inv_compare_runs inv_conflicts inv_cost inv_doc_cost'
\set r2 'inv_doc_state inv_layer inv_layer_consume inv_layer_cost_add inv_ledger inv_missing_docs inv_missing_lines inv_sku_types'
\set r3 'inv_snapshot inv_snapshot_runs inv_sync_state inv_voided_docs'
\set rall :r1 ' ' :r2 ' ' :r3

create temp table cut_class (tbl text primary key, cls text not null check (cls in ('D', 'K', 'R')));
insert into cut_class select t, 'D' from unnest(string_to_array(:'dall', ' ')) t;
insert into cut_class select t, 'K' from unnest(string_to_array(:'kall', ' ')) t;
insert into cut_class select t, 'R' from unnest(string_to_array(:'rall', ' ')) t;

do $$
declare v_missing text; v_gone text; v_fk text; v_seq text; v_d int; v_k int; v_r int;
begin
  -- a) public 표인데 목록에 없다
  select string_agg(c.relname, ', ' order by c.relname) into v_missing
  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
    and not exists (select 1 from cut_class x where x.tbl = c.relname);
  if v_missing is not null then
    raise exception 'CLASS: table(s) in public not classified - decide D/K/R and add to the lists: % - nothing was changed', v_missing;
  end if;
  -- b) 목록에 있는데 표가 없다(이름이 바뀌었거나 사라짐)
  select string_agg(x.tbl, ', ' order by x.tbl) into v_gone
  from cut_class x where to_regclass('public.' || quote_ident(x.tbl)) is null;
  if v_gone is not null then
    raise exception 'CLASS: listed table(s) do not exist in public: % - nothing was changed', v_gone;
  end if;
  -- c) 지움 밖 표가 지움 표를 가리키는 FK — 있으면 truncate 가 설 뿐 아니라 그 표도 거래다(분류를 다시)
  select string_agg(c1.relname || '.' || con.conname || ' -> ' || c2.relname, ', ' order by 1) into v_fk
  from pg_constraint con
  join pg_class c1 on c1.oid = con.conrelid join pg_class c2 on c2.oid = con.confrelid
  join cut_class p on p.tbl = c2.relname and p.cls = 'D'
  left join cut_class ch on ch.tbl = c1.relname and c1.relnamespace = 'public'::regnamespace
  where con.contype = 'f' and c2.relnamespace = 'public'::regnamespace and coalesce(ch.cls, '?') <> 'D';
  if v_fk is not null then
    raise exception 'CLASS: foreign key(s) from a non-deleted table into a deleted table: % - classify that table first - nothing was changed', v_fk;
  end if;
  -- d) 번호 시퀀스 여덟이 있다(⑥ 이 setval 한다)
  select string_agg(s, ', ') into v_seq from unnest(array['so_number_seq', 'so_invoice_number_seq', 'so_credit_number_seq', 'po_number_seq',
    'po_receipt_number_seq', 'inv_adjust_number_seq', 'inv_move_number_seq', 'inv_transfer_number_seq']) s
  where to_regclass('public.' || s) is null;
  if v_seq is not null then
    raise exception 'CLASS: number sequence(s) missing: % - nothing was changed', v_seq;
  end if;
  select count(*) filter (where cls = 'D'), count(*) filter (where cls = 'K'), count(*) filter (where cls = 'R') into v_d, v_k, v_r from cut_class;
  raise notice '③ 분류 대조 통과 — D % · K % · R % · public 표 전부 하나에만 · 지움 밖 → 지움 FK 0 · 번호 시퀀스 8 있음', v_d, v_k, v_r;
end $$;

-- ④ 남김 지문(전) — 남김 표마다 행 수 + 내용 해시(순서 무관 합 · cutdel-1 이견 4: 정렬 md5 보다 3 배 싸다 · 73 표 약 4 ~ 5 s)
--    지움 · 다시 맞춤 표는 행 수만(기록용 · ⑦ 요약에 쓴다)
create temp table cut_fp (phase text, cls text, tbl text, n bigint, h numeric, primary key (phase, tbl));
create function pg_temp.cut_fp_take(p_phase text) returns void language plpgsql as $$
declare r record; v_n bigint; v_h numeric;
begin
  for r in select tbl, cls from cut_class order by cls, tbl loop
    if r.cls = 'K' then
      execute format('select count(*), coalesce(sum((''x'' || left(md5(t::text), 15))::bit(60)::bigint), 0) from public.%I t', r.tbl) into v_n, v_h;
    else
      execute format('select count(*) from public.%I', r.tbl) into v_n; v_h := null;
    end if;
    insert into cut_fp values (p_phase, r.cls, r.tbl, v_n, v_h);
  end loop;
end $$;
select clock_timestamp() as t_fp_pre_start \gset
select pg_temp.cut_fp_take('pre');
select cls, count(*) as tables, sum(n) as rows_now from cut_fp where phase = 'pre' group by cls order by cls;
select tbl, n from cut_fp where phase = 'pre' and cls = 'D' and n > 0 order by n desc, tbl;

-- ⑤ truncate 한 문장 — 지움 목록 전부(③ 의 D 와 같은 한 원천) · restart identity · cascade 없음
select string_agg(format('public.%I', tbl), ', ' order by tbl) as dtrunc from cut_class where cls = 'D'
\gset
\echo '⑤ truncate table' :dtrunc 'restart identity;'
select clock_timestamp() as t_trunc \gset
truncate table :dtrunc restart identity;

-- ⑥ 번호 — 판정 749: 다음 번호가 SO-20000 · 60000 · CR-01000 · PO-02000 · RCV/ADJ/MV/TRF-00001 이 되게 setval(값, false).
--    (채번 함수는 SO- · CR- · PO- · RCV- · ADJ- · MV- · TRF- + lpad 5 · 인보이스는 접두어 없음 — 실물 prosrc 2026-10-26)
--    여덟 시퀀스는 어느 표에도 딸리지 않아 restart identity 로는 돌아오지 않는다.
\if :{?rehearsal}
\echo '⑥ [REHEARSAL] setval 은 부르지 않는다(rollback 되지 않고 다른 세션에 즉시 보인다) — 컷오버 날 부를 값: so 20000 · invoice 60000 · credit 1000 · po 2000 · receipt 1 · adjust 1 · move 1 · transfer 1 (is_called false)'
\else
select setval('public.so_number_seq',           20000, false) as so_next,
       setval('public.so_invoice_number_seq',   60000, false) as invoice_next,
       setval('public.so_credit_number_seq',     1000, false) as credit_next,
       setval('public.po_number_seq',            2000, false) as po_next,
       setval('public.po_receipt_number_seq',       1, false) as receipt_next,
       setval('public.inv_adjust_number_seq',       1, false) as adjust_next,
       setval('public.inv_move_number_seq',         1, false) as move_next,
       setval('public.inv_transfer_number_seq',     1, false) as transfer_next;
\endif
select 'so_number_seq' as seq, last_value, is_called from public.so_number_seq
union all select 'so_invoice_number_seq', last_value, is_called from public.so_invoice_number_seq
union all select 'so_credit_number_seq', last_value, is_called from public.so_credit_number_seq
union all select 'po_number_seq', last_value, is_called from public.po_number_seq
union all select 'po_receipt_number_seq', last_value, is_called from public.po_receipt_number_seq
union all select 'inv_adjust_number_seq', last_value, is_called from public.inv_adjust_number_seq
union all select 'inv_move_number_seq', last_value, is_called from public.inv_move_number_seq
union all select 'inv_transfer_number_seq', last_value, is_called from public.inv_transfer_number_seq;

-- ⑦ 뒤 검산 — 지움 표 전부 0 · 남김 지문 무변 · 다시 맞춤 표 무변(행 수) · 결과 한 줄
select pg_temp.cut_fp_take('post');
do $$
declare v_bad text; v_d int; v_d_rows bigint; v_k int; v_k_rows bigint; v_r int; v_r_rows bigint;
begin
  select string_agg(tbl || '=' || n, ', ' order by tbl) into v_bad from cut_fp where phase = 'post' and cls = 'D' and n > 0;
  if v_bad is not null then
    raise exception 'POST: deleted table(s) still have rows: % - the transaction is rolled back', v_bad;
  end if;
  select string_agg(a.tbl || ' ' || a.n || '/' || coalesce(a.h::text, '-') || ' -> ' || b.n || '/' || coalesce(b.h::text, '-'), ', ' order by a.tbl) into v_bad
  from cut_fp a join cut_fp b on b.tbl = a.tbl and b.phase = 'post'
  where a.phase = 'pre' and a.cls in ('K', 'R') and (a.n <> b.n or a.h is distinct from b.h);
  if v_bad is not null then
    raise exception 'POST: kept table(s) changed inside this transaction: % - the transaction is rolled back', v_bad;
  end if;
  select count(*), sum(n) into v_d, v_d_rows from cut_fp where phase = 'pre' and cls = 'D';
  select count(*), sum(n) into v_k, v_k_rows from cut_fp where phase = 'post' and cls = 'K';
  select count(*), sum(n) into v_r, v_r_rows from cut_fp where phase = 'post' and cls = 'R';
  raise notice '⑦ 검산 통과 — 지움 % 표 % 행 → 0 · 남김 % 표 % 행 지문 무변 · 다시 맞춤 % 표 % 행 무변(재적재 몫)', v_d, v_d_rows, v_k, v_k_rows, v_r, v_r_rows;
end $$;
select clock_timestamp() as t_post_end \gset
select 'cutover-delete' as result,
       (select count(*) from cut_fp where phase = 'pre'  and cls = 'D') as deleted_tables,
       (select sum(n)   from cut_fp where phase = 'pre'  and cls = 'D') as deleted_rows,
       (select count(*) from cut_fp where phase = 'post' and cls = 'K') as kept_tables,
       (select sum(n)   from cut_fp where phase = 'post' and cls = 'K') as kept_rows,
       (select count(*) from cut_fp where phase = 'post' and cls = 'R') as reload_tables,
       (select sum(n)   from cut_fp where phase = 'post' and cls = 'R') as reload_rows,
       :'t_trunc'::timestamptz as truncate_at,
       (:'t_post_end'::timestamptz - :'t_trunc'::timestamptz) as truncate_to_check_done;

-- ⑧ 판정 750 자리 — 시험 마스터(손님 2 · 공급처 1 · 제품 27 · 딜 15 와 딸린 것)는 Caleb 의 줄마다 표시가 온 뒤 다음 차수가 따로 짓는다. 이 파일은 손대지 않는다.
-- 끝 — 여기서 -1 트랜잭션이 commit 된다(컷오버 날) / 장치가 rollback 한다(리허설).
