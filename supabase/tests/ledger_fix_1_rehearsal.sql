-- supabase/tests/ledger_fix_1_rehearsal.sql — ledger-fix-1 리허설(Claude Code · begin → \i → rollback · 실제 행 무변)
-- 실행(레포 뿌리에서): psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v rehearsal=1 -f supabase/tests/ledger_fix_1_rehearsal.sql
-- 마른 갈래(check 모드 · 적용 전이라 MISMATCH 가 나와야 정상): … -v rehearsal=1 -v check=1 -f …
select clock_timestamp() as t0 \gset
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
\i supabase/ops/ledger-fix-1.sql
select count(*) as in_tx_manual from public.inv_ledger where doc_number = 'PO-01382' and source = 'manual' \gset
rollback;
select count(*) as after_rb_manual from public.inv_ledger where doc_number = 'PO-01382' and source = 'manual' \gset
select round(extract(epoch from clock_timestamp() - :'t0'::timestamptz)::numeric, 2) as elapsed_s \gset
\echo '[REHEARSAL] 트랜잭션 안 manual 줄' :in_tx_manual '· rollback 뒤' :after_rb_manual '(0 이어야 한다 · 적용 전) · begin~rollback 포함 걸린 시간' :elapsed_s 's'
