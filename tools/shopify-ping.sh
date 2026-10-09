#!/usr/bin/env bash
# tools/shopify-ping.sh — Caleb 이 터미널에서 직원 길로 Shopify EF 의 ping 을 부른다 (shop-1b · 2026-10-09)
#   로그인(이메일 · 비밀번호는 화면 · 기록 · 파일에 남기지 않는다) → POST /functions/v1/shopify {action: ping, store} → 응답 json.tool
#   ⚠️ 테스트 프로젝트만 — 주소에 운영 ref(gftpcnkxbdjzzfvzwcfl)가 보이면 멈춘다
#   쓰기:  bash tools/shopify-ping.sh                 # store test · ping
#          bash tools/shopify-ping.sh --store asung   # 다른 store code
#          bash tools/shopify-ping.sh --no-token      # 거부 시험 — 토큰 없이 → 401 기대
#          bash tools/shopify-ping.sh --store nope    # 거부 시험 — 없는 store → 404 사람 말
#   환경:  SUPABASE_URL · SUPABASE_ANON_KEY 를 주면 그것을 · 없으면 asung-ims/ims-config.js 의 테스트 값을 읽는다 · 그것도 없으면 묻는다
set -euo pipefail
STORE="test"; NO_TOKEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --store) STORE="$2"; shift 2 ;;
    --no-token) NO_TOKEN=1; shift ;;
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
echo "project: $URL · store: $STORE · action: ping"

TOKEN=""
if [ "$NO_TOKEN" -eq 0 ]; then
  read -rp "IMS login email: " EMAIL
  read -rsp "IMS password (not shown): " PASSWORD; echo
  LOGIN=$(curl -sS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
            --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "$EMAIL" "$PASSWORD")")
  unset PASSWORD
  TOKEN=$(printf '%s' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("access_token",""))' 2>/dev/null || true)
  if [ -z "$TOKEN" ]; then echo "login failed:" >&2; printf '%s\n' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("error_description") or j.get("msg") or j.get("error") or "unknown")' >&2 || true; exit 4; fi
  echo "login ok (token not shown)"
fi

HTTP_FILE=$(mktemp); trap 'rm -f "$HTTP_FILE"' EXIT
if [ -n "$TOKEN" ]; then
  BODY=$(curl -sS -o "$HTTP_FILE" -w '%{http_code}' -X POST "$URL/functions/v1/shopify" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
           --data-binary "{\"action\":\"ping\",\"store\":\"$STORE\"}")
else
  BODY=$(curl -sS -o "$HTTP_FILE" -w '%{http_code}' -X POST "$URL/functions/v1/shopify" -H "apikey: $ANON" -H "Content-Type: application/json" \
           --data-binary "{\"action\":\"ping\",\"store\":\"$STORE\"}")
fi
echo "HTTP $BODY"
python3 -m json.tool < "$HTTP_FILE" || cat "$HTTP_FILE"
unset TOKEN LOGIN ANON
