#!/usr/bin/env bash
# 로컬 Supabase 에서 제품 적재 시험 한 바퀴 — 테스트 DB(Asung-IMS)가 아니라 127.0.0.1 만 · 끝나면 supabase stop 은 사람이
# 전제: supabase start -x edge-runtime,imgproxy,logflare,mailpit,postgres-meta,realtime,storage-api,studio,supavisor,vector
#       로컬 public 스키마 = 테스트 DB public 의 pg_dump --schema-only 복원 + service_role grant(ldfix-1a 보고 참조 · db reset 은 데이터 의존 마이그레이션에서 멈춘다)
set -euo pipefail
cd "$(dirname "$0")/../../../.."
L="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
export SUPABASE_IMS_URL=http://127.0.0.1:54321
export SUPABASE_IMS_SERVICE_KEY="$(supabase status -o env 2>/dev/null | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p')"
[ -n "$SUPABASE_IMS_SERVICE_KEY" ] || { echo "로컬 service key 를 못 읽었다 — supabase start 먼저"; exit 1; }
SC="${1:-main}"   # product: main | conflict
# 복원한 스키마에 아직 없는 마이그레이션을 로컬에만 차례로 적용 — 가드가 inv_config.db_role=test 를 보므로 표식 한 행(로컬만) · 채우기가 집는 행을 먼저 둔다 · 적용 여부는 마이그레이션마다 SQL 표지로
apply_mig() {   # $1 파일 · $2 「적용됐으면 1」 을 돌려주는 SQL
  if [ "$(psql "$L" -X -At -c "$2")" != "1" ]; then
    psql "$L" -X -q -v ON_ERROR_STOP=1 -c "insert into public.inv_config (key, value) values ('db_role', 'test') on conflict (key) do update set value = 'test';"
    psql "$L" -X -q -v ON_ERROR_STOP=1 -1 -f "$1"
    echo "로컬에 $1 적용"
  fi
}
# 1a2 — 채우기 대상 Sungeun Lee 행을 먼저 둔다
psql "$L" -X -q -v ON_ERROR_STOP=1 -c "insert into public.customer (name, cin7_id, source, is_active) select 'Asung Employee - Sungeun Lee', '2ca116b6-145b-455b-a3c1-7e0a30fc04fb', 'cin7', true where not exists (select 1 from public.customer where cin7_id = '2ca116b6-145b-455b-a3c1-7e0a30fc04fb');"
apply_mig supabase/migrations/20261024174246_ldfix_1a2_parent_source_ims.sql "select (prosrc ~ 'parent_source = ''cin7''')::int from pg_proc where proname = 'customer_parent_guard' and pronamespace = 'public'::regnamespace"
# 1c2 — 채우기 대상(updated_by 있는 cin7 공급처 5)을 먼저 둔다(이름은 아무거나 · 수만 5)
psql "$L" -X -q -v ON_ERROR_STOP=1 -c "insert into public.ims_staff (id, auth_user_id, email, name, role) values ('00000000-0000-4000-8000-000000000999', '10000000-0000-4000-8000-000000000009', 'harness-mig@local', 'Harness Mig', 'manager') on conflict (id) do nothing;" -c "insert into public.supplier (name, cin7_id, source, is_active, payment_term_name, account_payable_code, updated_by) select 'LDFIX1C2 backfill ' || g, gen_random_uuid(), 'cin7', true, '', '', '00000000-0000-4000-8000-000000000999' from generate_series(1, 5) g where (select count(*) from public.supplier where source = 'cin7' and updated_by is not null) < 5 and not exists (select 1 from information_schema.columns where table_name = 'supplier' and column_name = 'is_active_source');"
apply_mig supabase/migrations/20261024190442_ldfix_1c2_supplier_active_source_recalc.sql "select exists(select 1 from information_schema.columns where table_name = 'supplier' and column_name = 'is_active_source')::int"
node docs/probes/harness/local/make-seed-product.js "$SC" > docs/probes/harness/local/seed-product.sql
psql "$L" -X -q -v ON_ERROR_STOP=1 -f docs/probes/harness/local/seed-product.sql
node docs/probes/harness/run-product.js local "$SC"
if [ "$SC" = main ]; then psql "$L" -X -At -f docs/probes/harness/local/check-product.sql; fi
