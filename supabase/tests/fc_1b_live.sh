#!/usr/bin/env bash
# supabase/tests/fc_1b_live.sh — Caleb 이 배포 뒤 돌리는 Freightcom 실호출 시험 (fc-1b · 2026-10-28) — 상자 SO 하나 · 팔렛 SO 하나 · EF freightcom quote · DB 확인
#   로그인(이메일 · 비밀번호는 화면 · 기록 · 파일에 남기지 않는다 · tools/shopify-ping.sh 꼴) → POST /functions/v1/freightcom {action: quote, so_ids, options} → 응답 json.tool → psql 로 fc_quote.response 원문 일부 · fc_quote_rate · fc_call_log
#   ⚠️ 테스트 프로젝트만(URL 에 운영 ref 가 보이면 멈춘다) · 토큰은 EF 비밀값(FREIGHTCOM_API_KEY)에만 — 이 스크립트는 토큰을 모른다
#   쓰기:  bash supabase/tests/fc_1b_live.sh                    # 상자 · 팔렛 후보를 DB 에서 고르고 물어본 뒤 견적
#          bash supabase/tests/fc_1b_live.sh --so SO-25201       # 그 SO 하나만(쉼표로 여럿 = 한 발송)
#          bash supabase/tests/fc_1b_live.sh --status            # 비밀값 유무만(Freightcom 호출 없음)
#          bash supabase/tests/fc_1b_live.sh --services TOR      # 그 계정의 운송사 이름 목록(fc-1b4: 계정 = ref_warehouse.freightcom_account · 하나뿐이면 생략 가능)
#   환경:  SUPABASE_URL · SUPABASE_ANON_KEY 를 주면 그것을 · 없으면 asung-ims/ims-config.js 의 테스트 값 · DB 확인은 ~/.asung-testdb-url
set -euo pipefail
ACTION="quote"; SO_LIST=""; OPTIONS='{}'; ACCT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --so) SO_LIST="$2"; shift 2 ;;
    --options) OPTIONS="$2"; shift 2 ;;
    --status) ACTION="status"; shift ;;
    --services) ACTION="services"; if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then ACCT="$2"; shift 2; else shift; fi ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
CFG="${IMS_CONFIG_JS:-$HOME/asung/asung-ims/ims-config.js}"
URL="${SUPABASE_URL:-}"; ANON="${SUPABASE_ANON_KEY:-}"
if [ -z "$URL" ] && [ -f "$CFG" ]; then URL=$(grep -oE 'SUPABASE_URL: *"[^"]+"' "$CFG" | head -1 | sed -E 's/.*"([^"]+)"/\1/'); fi
if [ -z "$ANON" ] && [ -f "$CFG" ]; then ANON=$(grep -oE 'SUPABASE_ANON_KEY: *"[^"]+"' "$CFG" | head -1 | sed -E 's/.*"([^"]+)"/\1/'); fi
if [ -z "$URL" ]; then read -rp "Supabase URL (test project https://fazgmyvzzhqybtvtktyg.supabase.co): " URL; fi
if [ -z "$ANON" ]; then read -rp "Supabase anon key (test project): " ANON; fi
URL="${URL%/}"
case "$URL" in *gftpcnkxbdjzzfvzwcfl*) echo "STOP — this is the production WMS project. This script is for the test project (Asung-IMS) only." >&2; exit 3 ;; esac
case "$URL" in *fazgmyvzzhqybtvtktyg*) ;; *) echo "STOP — URL is not the test project (fazgmyvzzhqybtvtktyg): $URL" >&2; exit 3 ;; esac
DBURL="$(cat "$HOME/.asung-testdb-url")"
PSQL=(psql "$DBURL" -X -At -v ON_ERROR_STOP=1)
echo "project: $URL · action: $ACTION"

# 후보 SO — packed · 창고 있음 · 맨 위 유닛 전부 치수 · 무게 있음 · 살아 있는 발송 없음(있어도 된다 — 갈아 끼운다)
if [ "$ACTION" = "quote" ] && [ -z "$SO_LIST" ]; then
  echo "── 후보(상자 · 팔렛 각 5 · 치수 든 packed SO) —"
  "${PSQL[@]}" -F ' | ' <<'SQL'
set default_transaction_read_only = on;
with u as (select u.order_id, u.unit_type, count(*) n, count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) nodim
           from public.wms_pallets u where u.parent_id is null and u.order_id is not null group by 1, 2)
select u.unit_type, s.so_number, s.location_name, s.ship_to_city, s.ship_to_postal_code, u.n as units,
       (select count(*) from public.fc_shipment_so l where l.so_id = s.id and l.live) as live_shipments
from u join public.so s on s.id = u.order_id
where s.status = 'packed' and u.nodim = 0
  and not exists (select 1 from public.wms_pallets u2 where u2.order_id = s.id and u2.parent_id is null and u2.unit_type <> u.unit_type)
order by u.unit_type, s.created_at desc limit 10;
SQL
  read -rp "SO number(s) to quote (comma = one shipment): " SO_LIST
fi

read -rp "IMS login email: " EMAIL
read -rsp "IMS password (not shown): " PASSWORD; echo
LOGIN=$(curl -sS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
          --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "$EMAIL" "$PASSWORD")")
unset PASSWORD
TOKEN=$(printf '%s' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("access_token",""))' 2>/dev/null || true)
if [ -z "$TOKEN" ]; then echo "login failed: $(printf '%s' "$LOGIN" | head -c 200)" >&2; exit 4; fi
echo "login ok (token not shown)"

if [ "$ACTION" = "quote" ]; then
  IDS=$("${PSQL[@]}" -c "select coalesce(json_agg(id), '[]') from public.so where so_number = any (string_to_array(replace('$SO_LIST', ' ', ''), ','))")
  if [ "$IDS" = "[]" ]; then echo "no SO found for: $SO_LIST" >&2; exit 5; fi
  BODY=$(python3 -c 'import json,sys; print(json.dumps({"action": "quote", "so_ids": json.loads(sys.argv[1]), "options": json.loads(sys.argv[2])}))' "$IDS" "$OPTIONS")
else
  BODY=$(python3 -c 'import json,sys; b={"action": sys.argv[1]}; (sys.argv[2] and b.update(account=sys.argv[2])); print(json.dumps(b))' "$ACTION" "$ACCT")
fi
HTTP_FILE=$(mktemp); trap 'rm -f "$HTTP_FILE"' EXIT
T0=$(date +%s)
CODE=$(curl -sS -o "$HTTP_FILE" -w '%{http_code}' -X POST "$URL/functions/v1/freightcom" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "$BODY")
echo "HTTP $CODE · $(( $(date +%s) - T0 )) s"
python3 -m json.tool < "$HTTP_FILE" | head -150 || cat "$HTTP_FILE"
unset TOKEN LOGIN ANON

# pending 이면 Check again 을 한 번(request_id 로) — 화면의 단추와 같은 호출 · 토큰이 이미 지워졌으니 다시 로그인하지 않고 안내만
if [ "$ACTION" = "quote" ] && grep -q '"pending": true' "$HTTP_FILE"; then
  echo "── pending: the screen's Check again calls {action: quote_poll, shipment_id, request_id} — run again or wait for fc-1c"
fi

if [ "$ACTION" = "quote" ]; then
  echo "── DB 확인(읽기만) — 마지막 견적 · 줄 · 호출 기록 —"
  "${PSQL[@]}" -F ' | ' <<'SQL'
set default_transaction_read_only = on;
select 'quote', q.id, q.status, q.request_id, q.requested_at, q.done_at, left(q.error, 120), (q.request->'services') is not null as sent_services, q.request#>>'{details,packaging_type}' as ptype,
       q.response#>>'{status,total}' as total, q.response#>>'{status,complete}' as complete, jsonb_array_length(coalesce(q.response->'rates', '[]'::jsonb)) as rates
from public.fc_quote q order by q.requested_at desc limit 3;
select 'rate', r.service_id, r.carrier_name, r.carrier_id is not null as paired, r.base_cents, r.surcharge_cents, r.tax_cents, r.total_cents, r.pretax_cents, r.customer_charge_cents, r.totals_mismatch, r.avoided, r.preselected
from public.fc_quote_rate r where r.quote_id = (select id from public.fc_quote order by requested_at desc limit 1) order by r.pretax_cents limit 20;
select 'raw first rate', left((q.response->'rates'->0)::text, 600) from public.fc_quote q order by q.requested_at desc limit 1;
select 'call', c.called_at, c.action, c.ok, c.http_status, c.ms, left(c.error, 160) from public.fc_call_log c order by c.called_at desc limit 10;
SQL
fi
