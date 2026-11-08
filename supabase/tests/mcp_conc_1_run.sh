#!/bin/sh
# supabase/tests/mcp_conc_1_run.sh — mcp-conc-1 시험 실행기 [IMS 메인 · fazgmyvzzhqybtvtktyg · psql $(cat ~/.asung-testdb-url)]
#   자리 1 · 2 · 3 을 쥐는 psql 세션 셋(set application_name mcp_conc_1_holder_k → begin → pg_try_advisory_xact_lock → pg_sleep 90 → rollback)을 띄운 뒤 넷째 세션으로 mcp_conc_1_check.sql 을 돈다 · 끝나면 남은 세션을 끊는다
#   시험 갈래(Claude Code · rollback): MIG=supabase/migrations/20261108160000_mcp_conc_1_sales_slots.sql sh supabase/tests/mcp_conc_1_run.sh
#   확인 갈래(Caleb · 적용 뒤):          sh supabase/tests/mcp_conc_1_run.sh      — 기대 OK 수 같다(mcp_sales_same 은 적용 뒤 md5 기준이라 t) · ⚠️ 적용 뒤에는 자리를 쥐는 ≈ 10 s 동안 실제 커넥터 호출이 busy 를 받는다 — 호출 0 인 때에
#   되돌이(무거운 집계 없이): LIGHT_S1=1 MIG=… sh supabase/tests/mcp_conc_1_run.sh
set -u
cd "$(dirname "$0")/../.." || exit 1
URL="$(cat ~/.asung-testdb-url)"
for k in 1 2 3; do
  # ⚠️ application_name 은 SET 으로(PGAPPNAME 시작 인자는 pooler 를 지나며 사라진다 — 11-08 실측) · 자리는 begin 뒤에 쥐고 90 s 자거나 넷째가 pg_terminate_backend 로 끊는다
  printf "set application_name = 'mcp_conc_1_holder_%s';\nbegin;\nselect pg_try_advisory_xact_lock(hashtext('mcp_sales:slot:%s')) as got_slot_%s;\nselect pg_sleep(90);\nrollback;\n" "$k" "$k" "$k" \
    | psql "$URL" -X -q -v ON_ERROR_STOP=1 -f - >/dev/null 2>&1 &
done
sleep 2
LIGHT=""; [ -n "${LIGHT_S1:-}" ] && LIGHT="-v light=1"     # LIGHT_S1=1: 성공 길을 가짜 기간 2027-06 으로(되돌이 시험 — 무거운 실데이터 집계를 다시 안 돌린다)
if [ -n "${MIG:-}" ]; then
  MIG="$MIG" psql "$URL" -X -v ON_ERROR_STOP=1 -v mig="$MIG" $LIGHT -f supabase/tests/mcp_conc_1_check.sql; rc=$?
else
  psql "$URL" -X -v ON_ERROR_STOP=1 $LIGHT -f supabase/tests/mcp_conc_1_check.sql; rc=$?
fi
psql "$URL" -XAtq -c "select count(*) as holders_terminated from (select pg_terminate_backend(pid) from pg_stat_activity where application_name like 'mcp\_conc\_1\_holder\_%') x;"
wait
exit $rc
