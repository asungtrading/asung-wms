#!/usr/bin/env bash
# 로컬 Supabase 에서 손님 적재 시험 한 바퀴 — 테스트 DB(Asung-IMS)가 아니라 127.0.0.1 만 · 끝나면 supabase stop 은 사람이
# 전제: supabase start -x edge-runtime,imgproxy,logflare,mailpit,postgres-meta,realtime,storage-api,studio,supavisor,vector
#       로컬 public 스키마 = 테스트 DB public 의 pg_dump --schema-only 복원 + service_role grant(ldfix-1a 보고 참조 · db reset 은 데이터 의존 마이그레이션에서 멈춘다)
set -euo pipefail
cd "$(dirname "$0")/../../../.."
L="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
export SUPABASE_IMS_URL=http://127.0.0.1:54321
export SUPABASE_IMS_SERVICE_KEY="$(supabase status -o env 2>/dev/null | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p')"
[ -n "$SUPABASE_IMS_SERVICE_KEY" ] || { echo "로컬 service key 를 못 읽었다 — supabase start 먼저"; exit 1; }
SC="${1:-main}"
node docs/probes/harness/local/make-seed.js "$SC" > docs/probes/harness/local/seed-customer.sql
psql "$L" -X -q -v ON_ERROR_STOP=1 -f docs/probes/harness/local/seed-customer.sql
node docs/probes/harness/run-customer.js local "$SC"
[ "$SC" = main ] && psql "$L" -X -At -f docs/probes/harness/local/check-customer.sql
