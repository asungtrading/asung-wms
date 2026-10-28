#!/usr/bin/env bash
# supabase/tests/fc_2_live.sh — Caleb 이 배포 뒤 돌리는 Freightcom 예약 실호출 시험 (fc-2c · 2026-10-28) — 상자 예약 → 라벨 a6 · letter → 취소 · 팔렛(maritime) 예약 → 취소 · 단계마다 DB 확인
#   ⚠️ 돈이 드는 쓰기 — Freightcom TEST 환경(FREIGHTCOM_BASE_URL 이 테스트 주소)인지 --status 로 먼저 보고 · 예약마다 바로 취소한다 · 운영 ref 가 URL 에 보이면 멈춘다 · 토큰은 EF 비밀값에만
#   앞 조건: 그 SO 가 견적 → 고르기(selected)까지 끝나 있어야 한다(fc_1b_live.sh 또는 화면) · 로그인한 사람에게 freight_booking 열쇠(또는 admin · supervisor) · 2a 메모 ②(Staff 화면에서 켜지 말고 SQL 로 perms 에 넣는다)
#   쓰기:  bash supabase/tests/fc_2_live.sh --status                       # 비밀값 · 계정 · base url(Freightcom 호출 없음)
#          bash supabase/tests/fc_2_live.sh --so SO-25201                   # 그 SO 의 살아 있는 발송을 예약 → 라벨 → 취소 (상자 · 팔렛 공통 · 정기 픽업 설정대로)
#          bash supabase/tests/fc_2_live.sh --so SO-25201 --no-cancel       # 취소하지 않는다(⚠️ 진짜 예약으로 남는다 — 테스트 환경에서만)
#          bash supabase/tests/fc_2_live.sh --so SO-25201 --pickup '{"date":"2026-10-30","ready_at":"10:00","ready_until":"16:00"}'
#              ⭐ 짐작 닫기: 비정기 픽업(ref_carrier_pickup.regular_pickup false 또는 행 없음) 상자에서 pickup_details {pre_scheduled_pickup:false, date:{year,month,day}, ready_at:{hour,minute}, ready_until:{hour,minute}} 를 Freightcom 이 받는지 — 202 뒤 200 이면 닫힘 · 400 이면 그 몸을 보고 fc-2b prepare 의 꼴을 고친다
#          bash supabase/tests/fc_2_live.sh --cancel SO-25201               # 예약만 돼 있는 발송을 취소만
#          bash supabase/tests/fc_2_live.sh --poll <booking_id>             # pending 으로 끝났을 때 이어 묻기
#   환경:  SUPABASE_URL · SUPABASE_ANON_KEY 를 주면 그것을 · 없으면 asung-ims/ims-config.js 의 테스트 값 · DB 확인은 ~/.asung-testdb-url
set -euo pipefail
ACTION="book"; SO=""; PICKUP='{}'; CANCEL=1; POLL_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --so) SO="$2"; shift 2 ;;
    --pickup) PICKUP="$2"; shift 2 ;;
    --no-cancel) CANCEL=0; shift ;;
    --status) ACTION="status"; shift ;;
    --cancel) ACTION="cancel"; SO="$2"; shift 2 ;;
    --poll) ACTION="book_poll"; POLL_ID="$2"; shift 2 ;;
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
PSQL=(psql "$DBURL" -X -At -v ON_ERROR_STOP=1 -F ' | ')
echo "project: $URL · action: $ACTION"
if [ "$ACTION" != "status" ] && [ "$ACTION" != "book_poll" ] && [ -z "$SO" ]; then
  echo "── 후보(selected 발송 · 고른 줄 · 운송사 · 정기 픽업 · 마감) —"
  "${PSQL[@]}" <<'SQL'
set default_transaction_read_only = on;
select f.status, s.so_number, w.name as warehouse, f.packaging_type, r.carrier_name, r.service_id, coalesce(to_char(r.cutoff, 'HH24:MI'), '-') as cutoff, coalesce(pk.regular_pickup::text, '-') as regular_pickup, f.freightcom_account
from public.fc_shipment f join public.so s on s.id = f.charge_so_id join public.ref_warehouse w on w.id = f.origin_warehouse_id
left join public.fc_quote_rate r on r.id = f.selected_rate_id left join public.ref_carrier_pickup pk on pk.carrier_id = r.carrier_id and pk.warehouse_id = f.origin_warehouse_id
where f.status in ('selected', 'booked') order by f.updated_at desc limit 10;
SQL
  read -rp "SO number to book (its live shipment must be selected): " SO
fi

read -rp "IMS login email: " EMAIL
read -rsp "IMS password (not shown): " PASSWORD; echo
LOGIN=$(curl -sS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
          --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "$EMAIL" "$PASSWORD")")
unset PASSWORD
TOKEN=$(printf '%s' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("access_token",""))' 2>/dev/null || true)
if [ -z "$TOKEN" ]; then echo "login failed: $(printf '%s' "$LOGIN" | head -c 200)" >&2; exit 4; fi
echo "login ok (token not shown)"
HTTP_FILE=$(mktemp); trap 'rm -f "$HTTP_FILE"' EXIT
call() {   # call <json body> → 응답을 $HTTP_FILE 에 · HTTP 코드 · 걸린 초 · 150 줄까지 찍는다
  local T0; T0=$(date +%s)
  CODE=$(curl -sS -o "$HTTP_FILE" -w '%{http_code}' -X POST "$URL/functions/v1/freightcom" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "$1")
  echo "HTTP $CODE · $(( $(date +%s) - T0 )) s"
  python3 -m json.tool < "$HTTP_FILE" | head -150 || cat "$HTTP_FILE"
}
jget() { python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); v=j
for k in sys.argv[2].split("."):
    v = v.get(k) if isinstance(v, dict) else None
print("" if v is None else v)' "$HTTP_FILE" "$1" 2>/dev/null || true; }
dbcheck() {   # dbcheck <shipment_id> — 예약 이력 · SO 칸 · 라벨 · 호출 기록
  echo "── DB 확인(읽기만) — 발송 $1 —"
  "${PSQL[@]}" -v sid="$1" <<'SQL'
set default_transaction_read_only = on;
select 'shipment', f.status, f.booking_id, f.packaging_type, f.freightcom_account from public.fc_shipment f where f.id = :'sid'::uuid;
select 'booking', b.attempt, b.status, b.unique_id, b.freightcom_shipment_id, b.state, b.transaction_number, b.tracking_number, b.tracking_numbers, b.bol_number, left(coalesce(b.error, b.cancel_error, ''), 120) as err,
       (b.request->'pickup_details')::text as pickup_details, (b.request->'dispatch_details')::text as dispatch_details, jsonb_array_length(coalesce(b.labels, '[]'::jsonb)) as labels
from public.fc_booking b where b.shipment_id = :'sid'::uuid order by b.attempt;
select 'so', s.so_number, s.status, s.carrier, s.tracking_number from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = :'sid'::uuid and l.live order by s.so_number;
select 'label', l.size, l.padded, l.path, l.bytes, l.pages, l.fetched_at from public.fc_label l where l.shipment_id = :'sid'::uuid order by l.fetched_at;
select 'call', c.called_at, c.action, c.ok, c.http_status, c.ms, left(c.error, 140) from public.fc_call_log c where c.shipment_id = :'sid'::uuid order by c.called_at desc limit 12;
SQL
}

if [ "$ACTION" = "status" ]; then call '{"action": "status"}'; unset TOKEN LOGIN ANON; exit 0; fi
if [ "$ACTION" = "book_poll" ]; then
  call "$(python3 -c 'import json,sys; print(json.dumps({"action": "book_poll", "booking_id": sys.argv[1]}))' "$POLL_ID")"
  SID=$("${PSQL[@]}" -c "select shipment_id from public.fc_booking where id = '$POLL_ID'"); [ -n "$SID" ] && dbcheck "$SID"
  unset TOKEN LOGIN ANON; exit 0
fi
SID=$("${PSQL[@]}" -c "select f.id from public.fc_shipment f join public.fc_shipment_so l on l.shipment_id = f.id and l.live join public.so s on s.id = l.so_id where s.so_number = '$SO' limit 1")
if [ -z "$SID" ]; then echo "no live shipment for $SO — quote and choose a rate first (fc_1b_live.sh)" >&2; exit 5; fi
echo "shipment: $SID"

if [ "$ACTION" = "book" ]; then
  echo "══ 1 book (pickup $PICKUP) ══"
  call "$(python3 -c 'import json,sys; print(json.dumps({"action": "book", "shipment_id": sys.argv[1], "pickup": json.loads(sys.argv[2])}))' "$SID" "$PICKUP")"
  dbcheck "$SID"
  if [ "$(jget pending)" = "True" ]; then
    echo "── pending: run  bash supabase/tests/fc_2_live.sh --poll $(jget booking_id)  then  --cancel $SO"; unset TOKEN LOGIN ANON; exit 0
  fi
  if [ "$CODE" != "200" ]; then echo "── booking did not land (HTTP $CODE) — nothing to label or cancel (a failed attempt stays in fc_booking)"; unset TOKEN LOGIN ANON; exit 0; fi
  echo "══ 2 labels (signed URL per saved label · 120 s) ══"
  for LID in $("${PSQL[@]}" -c "select id from public.fc_label where shipment_id = '$SID' order by size"); do
    call "$(python3 -c 'import json,sys; print(json.dumps({"action": "label", "label_id": sys.argv[1]}))' "$LID")"
    SU=$(jget signed_url); if [ -n "$SU" ]; then echo "   → $(curl -sS -o /dev/null -w 'GET signed url: HTTP %{http_code} · %{size_download} bytes · %{content_type}' "$SU")"; fi
  done
  if [ "$CANCEL" = "0" ]; then echo "── --no-cancel: the booking stays (test environment) — cancel later with --cancel $SO"; unset TOKEN LOGIN ANON; exit 0; fi
fi
echo "══ 3 cancel ══"
call "$(python3 -c 'import json,sys; print(json.dumps({"action": "cancel", "shipment_id": sys.argv[1]}))' "$SID")"
dbcheck "$SID"
unset TOKEN LOGIN ANON
echo "── done · expected: booking cancelled · shipment selected · SO carrier/tracking back to the values before booking (unless someone changed them) · labels stay in documents/fc_label/"
