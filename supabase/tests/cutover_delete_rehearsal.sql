-- supabase/tests/cutover_delete_rehearsal.sql — cutover-delete.sql 리허설 장치 (cutdel-1 · 2026-10-26 · 판정 746 ~ 754)
-- [테스트 · Asung-IMS] begin → set local lock_timeout 3s → \i supabase/ops/cutover-delete.sql (rehearsal=1) → rollback
-- 실행(Claude Code · 레포 뿌리에서 · Caleb 허락 2026-10-26):
--   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -f supabase/tests/cutover_delete_rehearsal.sql > /tmp/<이름>.out 2>&1; echo "rc=$?"
-- 보는 것: 번호 시퀀스 여덟 · id 시퀀스 다섯의 전후 원문(같아야 한다 · setval 은 안 부른다 · restart identity 는 rollback 된다)
--          public 172 표 행 수 전후(모두 같아야 한다 — 실제 행 무변 · cron 이 그 사이 쓴 표는 따로 밝힌다) · 걸린 시간 · 잠근 시간(truncate ~ rollback) · 그 시각의 cron 실행 기록
-- ⚠️ 끝은 반드시 rollback · commit 없음 · 리허설 갈래는 관문을 찍기만 하고 setval 을 부르지 않는다.
\set ON_ERROR_STOP on
\set rehearsal 1
\pset pager off
\timing on

\echo '── 전: 번호 시퀀스 여덟(직접 읽음) · id 시퀀스 다섯'
select 'before' as phase, 'so_number_seq' as seq, last_value, is_called from public.so_number_seq
union all select 'before', 'so_invoice_number_seq', last_value, is_called from public.so_invoice_number_seq
union all select 'before', 'so_credit_number_seq', last_value, is_called from public.so_credit_number_seq
union all select 'before', 'po_number_seq', last_value, is_called from public.po_number_seq
union all select 'before', 'po_receipt_number_seq', last_value, is_called from public.po_receipt_number_seq
union all select 'before', 'inv_adjust_number_seq', last_value, is_called from public.inv_adjust_number_seq
union all select 'before', 'inv_move_number_seq', last_value, is_called from public.inv_move_number_seq
union all select 'before', 'inv_transfer_number_seq', last_value, is_called from public.inv_transfer_number_seq
union all select 'before', 'wms_pick_tasks_id_seq', last_value, is_called from public.wms_pick_tasks_id_seq
union all select 'before', 'mail_outbox_event_id_seq', last_value, is_called from public.mail_outbox_event_id_seq
union all select 'before', 'shop_stock_queue_id_seq', last_value, is_called from public.shop_stock_queue_id_seq
union all select 'before', 'shop_order_inbox_id_seq', last_value, is_called from public.shop_order_inbox_id_seq
union all select 'before', 'wms_rollback_archive_id_seq', last_value, is_called from public.wms_rollback_archive_id_seq;

\echo '── 전: public 172 표 행 수(트랜잭션 밖 임시 표 — rollback 뒤에도 남는다)'
create temp table rh_before as
select c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) c from public.%I', c.relname), false, true, '')))[1]::text::bigint as n
from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r';
select count(*) as tables, sum(n) as rows_before from rh_before;

select clock_timestamp() as t_begin \gset
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
\i supabase/ops/cutover-delete.sql
\echo '── 트랜잭션 안: 지움 표 행 수(0 이어야) · 되돌리기 전'
select count(*) filter (where n = 0) as zero_tables, count(*) as d_tables from cut_fp where phase = 'post' and cls = 'D';
select 'in_txn' as phase, 'wms_pick_tasks_id_seq' as seq, last_value, is_called from public.wms_pick_tasks_id_seq
union all select 'in_txn', 'mail_outbox_event_id_seq', last_value, is_called from public.mail_outbox_event_id_seq;
rollback;
select clock_timestamp() as t_rb \gset

\echo '── 후: 번호 시퀀스 여덟 · id 시퀀스 다섯(전과 같아야 한다)'
select 'after' as phase, 'so_number_seq' as seq, last_value, is_called from public.so_number_seq
union all select 'after', 'so_invoice_number_seq', last_value, is_called from public.so_invoice_number_seq
union all select 'after', 'so_credit_number_seq', last_value, is_called from public.so_credit_number_seq
union all select 'after', 'po_number_seq', last_value, is_called from public.po_number_seq
union all select 'after', 'po_receipt_number_seq', last_value, is_called from public.po_receipt_number_seq
union all select 'after', 'inv_adjust_number_seq', last_value, is_called from public.inv_adjust_number_seq
union all select 'after', 'inv_move_number_seq', last_value, is_called from public.inv_move_number_seq
union all select 'after', 'inv_transfer_number_seq', last_value, is_called from public.inv_transfer_number_seq
union all select 'after', 'wms_pick_tasks_id_seq', last_value, is_called from public.wms_pick_tasks_id_seq
union all select 'after', 'mail_outbox_event_id_seq', last_value, is_called from public.mail_outbox_event_id_seq
union all select 'after', 'shop_stock_queue_id_seq', last_value, is_called from public.shop_stock_queue_id_seq
union all select 'after', 'shop_order_inbox_id_seq', last_value, is_called from public.shop_order_inbox_id_seq
union all select 'after', 'wms_rollback_archive_id_seq', last_value, is_called from public.wms_rollback_archive_id_seq;

\echo '── 후: public 172 표 행 수 대조(다른 표 0 이어야 · 있으면 cron 이 그 사이 쓴 표인지 밝힌다)'
create temp table rh_after as
select c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) c from public.%I', c.relname), false, true, '')))[1]::text::bigint as n
from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r';
select count(*) as tables, sum(n) as rows_after from rh_after;
select b.relname, b.n as before_n, a.n as after_n from rh_before b full join rh_after a using (relname) where b.n is distinct from a.n order by 1;
select count(*) as tables_changed from rh_before b full join rh_after a using (relname) where b.n is distinct from a.n;

\echo '── 시간: begin → rollback · 잠근 시간(truncate → rollback)'
select :'t_begin'::timestamptz as t_begin, :'t_trunc'::timestamptz as t_truncate, :'t_rb'::timestamptz as t_rollback,
       (:'t_rb'::timestamptz - :'t_begin'::timestamptz) as begin_to_rollback,
       (:'t_rb'::timestamptz - :'t_trunc'::timestamptz) as lock_window_truncate_to_rollback;

\echo '── 그 시각 앞뒤의 cron 실행 기록(begin − 1 분 ~ 지금)'
select j.jobname, d.status, count(*), max(d.end_time - d.start_time) as max_elapsed, left(max(d.return_message), 60) as msg
from cron.job_run_details d join cron.job j using (jobid)
where d.start_time >= :'t_begin'::timestamptz - interval '1 minute'
group by 1, 2 order by 1, 2;
