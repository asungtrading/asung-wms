-- supabase/ops/cutover-delete.sql — 컷오버 날 거래 지우기 (deferred 332 · 판정 746 ~ 754 · cutdel-1 · 2026-10-26)
-- [테스트 · Asung-IMS — 2026-11-01 부터 메인 시스템(판정 617)]
--
-- 무엇: 거래와 거기 딸린 것 79 표를 truncate 한 문장으로 비운다(판정 746 · cascade 없음 · 빠진 표가 있으면 PostgreSQL 이 오류로 멈춘다).
--       설정 · 마스터 · hist_ · 스토어 연결 기록 · 진단 로그(판정 751 · 752)는 그대로. 원장 · 레이어는 재적재(reload-procedure §P → §E 컷오버판 · §H)가 맡는다.
--       시험 마스터(판정 750 · ⑧)와 Roux 19 줄(판정 756 · ⑨)도 이 파일이 한다(cutdel-2).
-- 꼴:  마이그레이션 아님 · 함수 아님(운영 DB 에 「거래 전부 지우기」 를 부를 수 있게 남기지 않는다) · 컷오버 날 한 번.
-- 실행(컷오버 날 · Caleb · 레포 뿌리에서):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/cutover-delete.sql > ~/cutover-delete.log 2>&1; echo "exit=$?"
-- 리허설(Claude Code · begin → rollback): supabase/tests/cutover_delete_rehearsal.sql 이 이 파일을 -v rehearsal=1 로 \i 한다.
--   rehearsal 갈래 = 관문 ② 는 찍기만 · ⑥ setval 은 「부를 값」 만 찍는다(setval 은 rollback 되지 않는다). 나머지는 같다.
-- ⚠️ 이 파일에 begin · commit 없음(-1 이 한 트랜잭션) · cascade 없음 · session_replication_role 안 씀 · 운영(asung-WMS) 주소는 쓰지 않는다.
-- 차례: ① 이 DB 확인 → ② 관문 → ③ 분류 대조 → ④ 남김 지문(전) → ⑤ truncate → ⑥ 번호 → ⑦ 뒤 검산 → ⑧ 750 시험 마스터 delete → ⑨ 756 Roux 19 줄 → ⑧ · ⑨ 검산
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
--    [2026-10-28 · fc-1a] D + 4(fc_quote_rate fc_quote fc_shipment_so fc_shipment · d11) · K + 2(customer_carrier_avoid fc_call_log · k10) → 178 표 = D 83 · K 75 · R 20 (reload-procedure §P 는 문서 차수에서)
--    [2026-10-28 · fc-1b3] K + 1(ref_carrier_fc_name · k10) → 179 표 = D 83 · K 76 · R 20
--    [2026-10-28 · fc-2a] K + 1(ref_carrier_pickup · k10 · 운송사 × 창고 픽업 설정 — 마스터) → 180 표 = D 83 · K 77 · R 20 · fc-2b 가 fc_label(D · documents 버킷 fc_label/ 객체는 이 스크립트가 안 지운다 — 메모) · fc_booking(D) 을 더한다
--    [2026-10-28 · fc-2b] D + 2(fc_label fc_booking · d11 · 둘 다 fc_shipment 와 서로 FK — 한 truncate 묶음) → 182 표 = D 85 · K 77 · R 20 · ⚠️ documents 버킷의 fc_label/ 객체는 이 스크립트가 지우지 않는다(컷오버 날 storage 에서 따로)
--    [2026-10-29 · qbo-1a] K + 3(qbo_connection qbo_oauth_state qbo_call_log · k11 · QuickBooks 연결 설정 · CSRF state · 호출 기록 — 거래 아님 · 거래 표 FK 0 · 토큰은 Vault 라 이 스크립트 밖 · 샌드박스 → 운영은 운영 키를 받은 날 「끊기 → QBO_ENV=production → 연결」) → 185 표 = D 85 · K 80 · R 20
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
\set d11 'fc_quote_rate fc_quote fc_shipment_so fc_shipment fc_label fc_booking'
\set dall :d1 ' ' :d2 ' ' :d3 ' ' :d4 ' ' :d5 ' ' :d6 ' ' :d7 ' ' :d8 ' ' :d9 ' ' :d10 ' ' :d11
\set k1 'bgrade_price customer customer_address customer_contact doc_setting doc_template doc_template_active doc_template_event'
\set k2 'drive_folder hist_po hist_po_line hist_so hist_so_line ims_image_sync_queue ims_image_sync_runs ims_image_sync_skips'
\set k3 'ims_staff inv_config price_formula price_fx price_tier_rule product product_barcode product_bin_overflow'
\set k4 'product_bom product_family product_image product_price product_supplier product_tag pur_override_history pur_setting'
\set k5 'pur_sku_link pur_supplier_setting ref_account ref_bin ref_brand ref_carrier ref_category ref_currency'
\set k6 'ref_embed_host ref_payment_term ref_price_tier ref_region_alias ref_service ref_tax_region ref_tax_rule ref_unit'
\set k7 'ref_warehouse shop_call_log shop_customer shop_link_item shop_link_run shop_listing shop_location shop_media'
\set k8 'shop_product shop_stock_sent shop_store shop_variant so_deal so_deal_customer_rule so_deal_line so_deal_target'
\set k9 'so_deal_tier so_payment_account_default so_surcharge_group supplier supplier_address supplier_contact supplier_discount wms_drop_locations'
\set k10 'wms_zone_sequence customer_carrier_avoid fc_call_log ref_carrier_fc_name ref_carrier_pickup'
\set k11 'qbo_connection qbo_oauth_state qbo_call_log'
\set kall :k1 ' ' :k2 ' ' :k3 ' ' :k4 ' ' :k5 ' ' :k6 ' ' :k7 ' ' :k8 ' ' :k9 ' ' :k10 ' ' :k11
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

-- ⑧ 판정 750 — 시험 마스터 지우기 (cutdel-2 · Caleb 표시 2026-10-26) · delete(truncate 아님 · 문지기 · 트리거 켜 둔 채)
--    키로 고른다(SKU · 제품군 SKU · 손님 이름 · 공급처 이름 · 딜 이름) — id 를 박지 않는다 · 키마다 정확히 한 행이 아니면 그 키를 대고 멈춘다.
--    순서(실물 FK 전부 no action · cutdel-2 이견 2): 스토어 짝(listing · product · variant · media · stock_sent) 먼저 — 가격 · 태그 · 바코드 · 사진의 delete 트리거(shop_queue_trigger)가
--    켜진 listing 의 제품을 shop_push_queue 에 넣으므로 listing 이 사라진 뒤에 지운다 → 가격 · 태그 · 바코드 · 제품-공급처 · BOM · 사진 → 제품(부모 · -6 자식 한 문장) → 제품군
--    → 딜(target → line → tier → customer_rule → so_deal) → 손님(address · contact · shop_customer → customer) → 공급처(address · contact · discount · formula · pur → supplier).
--    문지기 product_delete_lock(product_sku_lock): 원장 · 레이어에 SKU 가 있으면 IM175 — 지우기 전에 0 을 확인한다(끄지 않는다). 딜 · 태그 트리거는 so 에만 쓴다(⑤ 뒤 비어 있음 · 무해).
--    사진 파일은 SQL 로 못 지운다 — 경로 목록을 로그에 찍고 §P 의 Storage 단계(748 의 7 개와 함께)에서 지운다.
\set p1 'AAA00001 AAA00001-6 AAA00002 AAA00002-6 AAA00003 AS85234 CON99901 CON99901-12'
\set p2 'TBR00182 TBR00182-12 TBR16260 TBR16260-6 TBR39231 TBR39231-12 TBR43447 TBR43447-6'
\set p3 'TBR63096 TBR63096-6 TBR66303 TBR66303-6 TBR79321 TBR79321-6 TBR81130 TBR81130-6'
\set p750 :p1 ' ' :p2 ' ' :p3
\set f750 'AAA00001FAM TBR16260FAM TBR66303FAM'
\set c750 'TEST IMS Shopify'
\set s750 'TEST Supplier-Canada'
\set d750 'TEST POS SALE 15|DR TEST line|DR TEST order|October Monthly Sale|Coupon Test|COUPON TEST 2|Less Discount-TEST|Test Promo (UOM)|Sale: Weekly Flash - Gummy Professional Flash Sale (Oct 15 ~ 28)|TEST-ADC96507'
-- 남는 것(검산용): 제품 AS85203 계열 3 · 손님 「Asung Employee - Donghyo Shin」 · 딜 5
\set keep_p 'AS85203 AS85203-6 AS85203-72'
\set keep_c 'Asung Employee - Donghyo Shin'
\set keep_d 'Hera Beauty (GPR-12, RON-21)|REX Deal Price|UOM Discount|Sale: Blowout Sale|PZ Wholesale - Kim & C 30% DC'
select set_config('cut.keep_p', :'keep_p', true), set_config('cut.keep_c', :'keep_c', true), set_config('cut.keep_d', :'keep_d', true);

create temp table cut_key (kind text, key text, ids uuid[], primary key (kind, key));
insert into cut_key select 'product',  k, (select coalesce(array_agg(id), '{}') from public.product        where sku  = k) from unnest(string_to_array(:'p750', ' ')) k;
insert into cut_key select 'family',   k, (select coalesce(array_agg(id), '{}') from public.product_family where sku  = k) from unnest(string_to_array(:'f750', ' ')) k;
insert into cut_key select 'customer', k, (select coalesce(array_agg(id), '{}') from public.customer       where name = k) from unnest(array[:'c750']) k;
insert into cut_key select 'supplier', k, (select coalesce(array_agg(id), '{}') from public.supplier       where name = k) from unnest(array[:'s750']) k;
insert into cut_key select 'deal',     k, (select coalesce(array_agg(id), '{}') from public.so_deal        where name = k) from unnest(string_to_array(:'d750', '|')) k;
create temp view cut_p as select ids[1] as id from cut_key where kind = 'product';
create temp view cut_f as select ids[1] as id from cut_key where kind = 'family';
create temp view cut_c as select ids[1] as id from cut_key where kind = 'customer';
create temp view cut_s as select ids[1] as id from cut_key where kind = 'supplier';
create temp view cut_d as select ids[1] as id from cut_key where kind = 'deal';

do $$
declare v_bad text; v_n int;
begin
  select string_agg(kind || ' ' || key || ' (' || cardinality(ids) || ')', ', ' order by kind, key) into v_bad from cut_key where cardinality(ids) <> 1;
  if v_bad is not null then
    raise exception '750 KEY: each key must match exactly one row - these do not: % - nothing was changed', v_bad;
  end if;
  select count(*) into v_n from cut_key where kind = 'product';
  if v_n <> 24 then raise exception '750 KEY: expected 24 product keys, found % - nothing was changed', v_n; end if;
  -- 제품군의 구성원이 전부 지우는 제품인가
  select string_agg(p.sku, ', ') into v_bad from public.product p where p.family_id in (select id from cut_f) and p.id not in (select id from cut_p);
  if v_bad is not null then
    raise exception '750 FAMILY: family member(s) not in the delete list: % - nothing was changed', v_bad;
  end if;
  -- 문지기 product_delete_lock 이 볼 것 — 원장 · 레이어에 그 SKU 가 있으면 지울 수 없다(IM175)
  select string_agg(distinct x.sku, ', ') into v_bad from (
    select e.sku from public.inv_ledger e where e.sku in (select p.sku from public.product p join cut_p on cut_p.id = p.id)
    union all select l.sku from public.inv_layer l where l.sku in (select p.sku from public.product p join cut_p on cut_p.id = p.id)) x;
  if v_bad is not null then
    raise exception '750 LOCK: SKU(s) have ledger or layer rows and cannot be deleted (product_delete_lock): % - nothing was changed', v_bad;
  end if;
  -- 남는 것이 지금 있는가(검산의 기준)
  select string_agg(k, ', ') into v_bad from unnest(string_to_array(current_setting('cut.keep_p'), ' ')) k where (select count(*) from public.product where sku = k) <> 1;
  if v_bad is not null then raise exception '750 KEEP: kept product key(s) not exactly one row: % - nothing was changed', v_bad; end if;
  if (select count(*) from public.customer where name = current_setting('cut.keep_c')) <> 1 then
    raise exception '750 KEEP: kept customer key not exactly one row - nothing was changed'; end if;
  select string_agg(k, ', ') into v_bad from unnest(string_to_array(current_setting('cut.keep_d'), '|')) k where (select count(*) from public.so_deal where name = k) <> 1;
  if v_bad is not null then raise exception '750 KEEP: kept deal key(s) not exactly one row: % - nothing was changed', v_bad; end if;
  raise notice '⑧ 키 통과 — 제품 24 · 제품군 3 · 손님 1 · 공급처 1 · 딜 10 각 한 행 · 제품군 구성원 전부 목록 안 · 원장 · 레이어 0 · 남는 것(제품 3 · 손님 1 · 딜 5) 있음';
end $$;

\echo '⑧ 사진 파일 — product-images 버킷에서 Storage 화면으로 지울 경로(§P 6 단계 · 748 의 7 개와 함께)'
select p.sku, i.storage_path, i.is_primary from public.product_image i join public.product p on p.id = i.product_id join cut_p on cut_p.id = p.id order by 1, 2;

create temp table cut_del (tbl text primary key, n bigint not null);
-- 스토어 짝 먼저(이견 2)
with d as (delete from public.shop_media       x where x.product_image_id in (select i.id from public.product_image i join cut_p on cut_p.id = i.product_id) returning 1) insert into cut_del select 'shop_media', count(*) from d;
with d as (delete from public.shop_variant     x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'shop_variant', count(*) from d;
with d as (delete from public.shop_product     x where x.product_id in (select id from cut_p) or x.family_id in (select id from cut_f) returning 1) insert into cut_del select 'shop_product', count(*) from d;
with d as (delete from public.shop_listing     x where x.product_id in (select id from cut_p) or x.family_id in (select id from cut_f) returning 1) insert into cut_del select 'shop_listing', count(*) from d;
with d as (delete from public.shop_stock_sent  x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'shop_stock_sent', count(*) from d;
with d as (delete from public.shop_link_item   x where x.ims_product_id in (select id from cut_p) or x.ims_family_id in (select id from cut_f) returning 1) insert into cut_del select 'shop_link_item', count(*) from d;
-- 제품에 딸린 것
with d as (delete from public.product_price    x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_price', count(*) from d;
with d as (delete from public.product_tag      x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_tag', count(*) from d;
with d as (delete from public.product_barcode  x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_barcode', count(*) from d;
with d as (delete from public.product_supplier x where x.product_id in (select id from cut_p) or x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'product_supplier', count(*) from d;
with d as (delete from public.product_bom      x where x.parent_product_id in (select id from cut_p) or x.component_product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_bom', count(*) from d;
with d as (delete from public.product_image    x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_image', count(*) from d;
with d as (delete from public.bgrade_price     x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'bgrade_price', count(*) from d;
with d as (delete from public.product_bin_overflow x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'product_bin_overflow', count(*) from d;
with d as (delete from public.ims_image_sync_queue x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'ims_image_sync_queue', count(*) from d;
with d as (delete from public.ims_image_sync_skips x where x.product_id in (select id from cut_p) returning 1) insert into cut_del select 'ims_image_sync_skips', count(*) from d;
-- 제품(부모와 -6 자식을 한 문장 · no action 은 문장 끝에 검사) → 제품군
with d as (delete from public.product          x where x.id in (select id from cut_p) returning 1) insert into cut_del select 'product', count(*) from d;
with d as (delete from public.product_family   x where x.id in (select id from cut_f) returning 1) insert into cut_del select 'product_family', count(*) from d;
-- 딜
with d as (delete from public.so_deal_target   x where x.line_id in (select l.id from public.so_deal_line l where l.deal_id in (select id from cut_d)) returning 1) insert into cut_del select 'so_deal_target', count(*) from d;
with d as (delete from public.so_deal_line     x where x.deal_id in (select id from cut_d) returning 1) insert into cut_del select 'so_deal_line', count(*) from d;
with d as (delete from public.so_deal_tier     x where x.deal_id in (select id from cut_d) returning 1) insert into cut_del select 'so_deal_tier', count(*) from d;
with d as (delete from public.so_deal_customer_rule x where x.deal_id in (select id from cut_d) or x.customer_id in (select id from cut_c) returning 1) insert into cut_del select 'so_deal_customer_rule', count(*) from d;
with d as (delete from public.so_deal          x where x.id in (select id from cut_d) returning 1) insert into cut_del select 'so_deal', count(*) from d;
-- 손님
with d as (delete from public.customer_address x where x.customer_id in (select id from cut_c) returning 1) insert into cut_del select 'customer_address', count(*) from d;
with d as (delete from public.customer_contact x where x.customer_id in (select id from cut_c) returning 1) insert into cut_del select 'customer_contact', count(*) from d;
with d as (delete from public.shop_customer    x where x.customer_id in (select id from cut_c) returning 1) insert into cut_del select 'shop_customer', count(*) from d;
with d as (delete from public.customer         x where x.id in (select id from cut_c) returning 1) insert into cut_del select 'customer', count(*) from d;
-- 공급처
with d as (delete from public.supplier_address x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'supplier_address', count(*) from d;
with d as (delete from public.supplier_contact x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'supplier_contact', count(*) from d;
with d as (delete from public.supplier_discount x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'supplier_discount', count(*) from d;
with d as (delete from public.price_formula    x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'price_formula', count(*) from d;
with d as (delete from public.pur_supplier_setting x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'pur_supplier_setting', count(*) from d;
with d as (delete from public.pur_override_history x where x.supplier_id in (select id from cut_s) returning 1) insert into cut_del select 'pur_override_history', count(*) from d;
with d as (delete from public.supplier         x where x.id in (select id from cut_s) returning 1) insert into cut_del select 'supplier', count(*) from d;
\echo '⑧ 표마다 지운 행 수'
select tbl, n from cut_del order by n desc, tbl;
select count(*) as tables_touched, sum(n) as rows_deleted from cut_del where n > 0;

-- ⑨ 판정 756 — Roux Laboratories 의 product_supplier 19 줄(source manual · cin7_id 있음 · IMS 가 끈 Cin7 줄)을 재적재가 덮게 source 를 cin7 으로 되돌린다.
--    근거(ImsLoadProductSupplier.gs :245 ~ 246 · :291): 적재는 source=manual 을 읽어 cin7_id 가 있으면 그 Cin7 줄을 「보내지 않는다」(skipManual). source 가 cin7 이면 upsert(충돌 키 cin7_id)가
--    supplier_sku · cost · fixed_cost · currency · last_supplied · is_active 를 옛 시스템 값으로 덮는다(켜질 수 있다 — Caleb 확인 2026-10-26). ims_touch 가 updated_by 를 null 로 둔다(auth.uid() 없음).
--    확인은 컷오버 날 7 단계 Dry 로그 「보내지 않은 줄(IMS 가 정한 Cin7 줄)」 이 19 → 0. 기본 공급처는 7 단계 끝의 재계산이 정한다. 수가 다르면 멈춘다(roux_expected).
\set roux_expected 19
select set_config('cut.roux_expected', :'roux_expected', true);
\echo '⑨ 되돌릴 줄(전)'
select p.sku, ps.supplier_sku, ps.cost, ps.fixed_cost, ps.is_active, ps.is_default, ps.updated_at::date
from public.product_supplier ps join public.product p on p.id = ps.product_id
where ps.source = 'manual' and ps.cin7_id is not null and ps.supplier_id = (select id from public.supplier where name = 'Roux Laboratories') order by 1;
do $$
declare v_n int; v_sup uuid;
begin
  select id into v_sup from public.supplier where name = 'Roux Laboratories';
  if v_sup is null then raise exception '756 ROUX: supplier Roux Laboratories not found - nothing was changed'; end if;
  select count(*) into v_n from public.product_supplier where source = 'manual' and cin7_id is not null and supplier_id = v_sup;
  if v_n <> current_setting('cut.roux_expected')::int then
    raise exception '756 ROUX: expected % rows (source manual, cin7_id set, Roux) but found % - look at the list above and change roux_expected if that is right - nothing was changed', current_setting('cut.roux_expected')::int, v_n;
  end if;
  if (select count(*) from public.product_supplier where source = 'manual' and cin7_id is not null and supplier_id <> v_sup) > 0 then
    raise exception '756 ROUX: there are manual rows with cin7_id for other suppliers - decide those first (ruling 756 is Roux only) - nothing was changed';
  end if;
end $$;
create temp table cut_roux (n bigint);
with u as (update public.product_supplier ps set source = 'cin7'
           where ps.source = 'manual' and ps.cin7_id is not null and ps.supplier_id = (select id from public.supplier where name = 'Roux Laboratories') returning 1)
insert into cut_roux select count(*) from u;
select n as roux_rows_reset from cut_roux;

-- ⑧ · ⑨ 뒤 검산 — 지운 키 0 · 남는 것 그대로 · 지움 79 표 여전히 0(큐 트리거가 줄을 넣지 않았다) · 남김 표 행 수 = ⑦ 값 − 지운 수 · 지운 수 0 인 남김 표는 해시도 같다(⑨ 의 product_supplier 만 예외) · 다시 맞춤 무변
select pg_temp.cut_fp_take('post9');
do $$
declare v_bad text; v_roux int; v_rows bigint; v_tbls int;
begin
  select n into v_roux from cut_roux;
  if v_roux <> current_setting('cut.roux_expected')::int then
    raise exception 'POST9: roux update changed % rows, expected % - the transaction is rolled back', v_roux, current_setting('cut.roux_expected')::int;
  end if;
  if (select count(*) from public.product_supplier where source = 'manual' and cin7_id is not null and supplier_id = (select id from public.supplier where name = 'Roux Laboratories')) <> 0 then
    raise exception 'POST9: roux rows still manual - the transaction is rolled back';
  end if;
  -- 지운 키 0
  select string_agg(kind || ' ' || key, ', ') into v_bad from cut_key k where
       (k.kind = 'product'  and exists (select 1 from public.product        where sku  = k.key))
    or (k.kind = 'family'   and exists (select 1 from public.product_family where sku  = k.key))
    or (k.kind = 'customer' and exists (select 1 from public.customer       where name = k.key))
    or (k.kind = 'supplier' and exists (select 1 from public.supplier       where name = k.key))
    or (k.kind = 'deal'     and exists (select 1 from public.so_deal        where name = k.key));
  if v_bad is not null then raise exception 'POST8: key(s) still present: % - the transaction is rolled back', v_bad; end if;
  -- 남는 것 그대로
  select string_agg(k, ', ') into v_bad from unnest(string_to_array(current_setting('cut.keep_p'), ' ')) k where (select count(*) from public.product where sku = k and source = 'manual') <> 1;
  if v_bad is not null then raise exception 'POST8: kept product(s) missing: % - the transaction is rolled back', v_bad; end if;
  if (select count(*) from public.customer where name = current_setting('cut.keep_c')) <> 1 then raise exception 'POST8: kept customer missing - the transaction is rolled back'; end if;
  select string_agg(k, ', ') into v_bad from unnest(string_to_array(current_setting('cut.keep_d'), '|')) k where (select count(*) from public.so_deal where name = k) <> 1;
  if v_bad is not null then raise exception 'POST8: kept deal(s) missing: % - the transaction is rolled back', v_bad; end if;
  -- 지움 79 표 여전히 0
  select string_agg(tbl || '=' || n, ', ' order by tbl) into v_bad from cut_fp where phase = 'post9' and cls = 'D' and n > 0;
  if v_bad is not null then raise exception 'POST8: deleted table(s) got rows back (a queue trigger?): % - the transaction is rolled back', v_bad; end if;
  -- 남김 · 다시 맞춤: 행 수 = ⑦ − 지운 수 · 지운 수 0 이면 해시 같음(product_supplier 는 ⑨ 로 해시만 바뀐다)
  select string_agg(a.tbl || ' ' || a.n || '-' || coalesce(d.n, 0) || ' <> ' || b.n, ', ' order by a.tbl) into v_bad
  from cut_fp a join cut_fp b on b.tbl = a.tbl and b.phase = 'post9' left join cut_del d on d.tbl = a.tbl
  where a.phase = 'post' and a.cls in ('K', 'R') and b.n <> a.n - coalesce(d.n, 0);
  if v_bad is not null then raise exception 'POST8: row count(s) off: % - the transaction is rolled back', v_bad; end if;
  select string_agg(a.tbl, ', ' order by a.tbl) into v_bad
  from cut_fp a join cut_fp b on b.tbl = a.tbl and b.phase = 'post9' left join cut_del d on d.tbl = a.tbl
  where a.phase = 'post' and a.cls in ('K', 'R') and coalesce(d.n, 0) = 0 and a.tbl <> 'product_supplier' and a.h is distinct from b.h;
  if v_bad is not null then raise exception 'POST8: untouched kept table(s) changed: % - the transaction is rolled back', v_bad; end if;
  select count(*), sum(n) into v_tbls, v_rows from cut_del where n > 0;
  raise notice '⑧ · ⑨ 검산 통과 — 시험 마스터 % 표 % 행 지움 · 키 39 전부 0 · 남는 것(제품 3 · 손님 1 · 딜 5) 그대로 · 지움 79 표 0 유지 · 남김 행 수 = ⑦ − 지운 수 · Roux % 줄 source cin7', v_tbls, v_rows, v_roux;
end $$;
select 'cutover-delete 8-9' as result, (select count(*) from cut_del where n > 0) as master_tables, (select sum(n) from cut_del) as master_rows_deleted, (select n from cut_roux) as roux_rows_reset,
       (select sum(n) from cut_fp where phase = 'post9' and cls = 'K') as kept_rows_now, (clock_timestamp() - :'t_trunc'::timestamptz) as truncate_to_end;
-- 끝 — 여기서 -1 트랜잭션이 commit 된다(컷오버 날) / 장치가 rollback 한다(리허설).
