#!/usr/bin/env bash
# tools/shopify-push.sh — Caleb 이 터미널에서 직원 길로 Shopify ② 를 돌린다 (shop-2b · 2026-10-09)
#   로그인(이메일 · 비밀번호는 화면 · 기록 · 파일에 남기지 않는다 · tools/shopify-ping.sh 와 같은 길) → 아래 갈래 하나 → 응답 json.tool
#   ⚠️ 테스트 프로젝트만 — 주소에 운영 ref(gftpcnkxbdjzzfvzwcfl)가 보이면 멈춘다
#   쓰기:  bash tools/shopify-push.sh clean-check                       # jsdom 이 Edge Runtime 에서 도는지 + 샘플 거르기(engine dompurify 기대)
#          bash tools/shopify-push.sh on --family ANN01001FAM           # 보냄 켜기(shop_listing_set listing_on · 두 번 부르기 · 경고는 보이고 ack)
#          bash tools/shopify-push.sh on --sku ANN01291
#          bash tools/shopify-push.sh off --sku ANN01291                # 보냄 끄기(큐 한 줄 · drain 이 ARCHIVED 로 보낸다)
#          bash tools/shopify-push.sh push --family ANN01001FAM [--force]   # 바로 보내기(큐를 거치지 않는다 · hash 같으면 skipped_same_hash · --force 로 강제)
#          bash tools/shopify-push.sh push --sku ANN03907
#          bash tools/shopify-push.sh drain                             # 열린 큐를 손으로 비운다(직원 길 · ≤ 20 건)
#   환경:  STORE(기본 test) · SUPABASE_URL · SUPABASE_ANON_KEY 를 주면 그것을 · 없으면 asung-ims/ims-config.js 의 테스트 값
set -euo pipefail
CMD="${1:-}"; shift || true
STORE="${STORE:-test}"; FAM=""; SKU=""; FORCE="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --family) FAM="$2"; shift 2 ;;
    --sku) SKU="$2"; shift 2 ;;
    --store) STORE="$2"; shift 2 ;;
    --force) FORCE="true"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
case "$CMD" in clean-check|on|off|push|drain) ;; *) echo "usage: $0 clean-check | on --family X | on --sku X | off … | push … [--force] | drain" >&2; exit 2 ;; esac
if [ "$CMD" != "clean-check" ] && [ "$CMD" != "drain" ] && { [ -z "$FAM" ] && [ -z "$SKU" ] || [ -n "$FAM" ] && [ -n "$SKU" ]; }; then echo "give exactly one of --family or --sku" >&2; exit 2; fi
CFG="${IMS_CONFIG_JS:-$HOME/asung/asung-ims/ims-config.js}"
URL="${SUPABASE_URL:-}"; ANON="${SUPABASE_ANON_KEY:-}"
if [ -z "$URL" ] && [ -f "$CFG" ]; then URL=$(grep -oE 'SUPABASE_URL: *"[^"]+"' "$CFG" | head -1 | sed -E 's/.*"([^"]+)"/\1/'); fi
if [ -z "$ANON" ] && [ -f "$CFG" ]; then ANON=$(grep -oE 'SUPABASE_ANON_KEY: *"[^"]+"' "$CFG" | head -1 | sed -E 's/.*"([^"]+)"/\1/'); fi
if [ -z "$URL" ]; then read -rp "Supabase URL (test project): " URL; fi
if [ -z "$ANON" ]; then read -rp "Supabase anon key (test project): " ANON; fi
URL="${URL%/}"
case "$URL" in *gftpcnkxbdjzzfvzwcfl*) echo "STOP — this is the production WMS project." >&2; exit 3 ;; esac
case "$URL" in *fazgmyvzzhqybtvtktyg*) ;; *) echo "STOP — URL is not the test project (fazgmyvzzhqybtvtktyg): $URL" >&2; exit 3 ;; esac
echo "project: $URL · store: $STORE · command: $CMD ${FAM:+family=$FAM}${SKU:+sku=$SKU}"
read -rp "IMS login email: " EMAIL
read -rsp "IMS password (not shown): " PASSWORD; echo
LOGIN=$(curl -sS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
          --data-binary "$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "$EMAIL" "$PASSWORD")")
unset PASSWORD
TOKEN=$(printf '%s' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("access_token",""))' 2>/dev/null || true)
if [ -z "$TOKEN" ]; then echo "login failed:" >&2; printf '%s\n' "$LOGIN" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("error_description") or j.get("msg") or j.get("error") or "unknown")' >&2 || true; exit 4; fi
echo "login ok (token not shown)"
OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT
call_ef() {   # $1 = JSON body
  local code; code=$(curl -sS -o "$OUT" -w '%{http_code}' -X POST "$URL/functions/v1/shopify" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "$1")
  echo "HTTP $code"; python3 -m json.tool < "$OUT" || cat "$OUT"
}
call_rpc() {  # $1 = fn · $2 = JSON args
  local code; code=$(curl -sS -o "$OUT" -w '%{http_code}' -X POST "$URL/rest/v1/rpc/$1" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "$2")
  echo "HTTP $code"; python3 -m json.tool < "$OUT" || cat "$OUT"
}
target_json() { if [ -n "$FAM" ]; then printf '"family_sku":"%s"' "$FAM"; else printf '"sku":"%s"' "$SKU"; fi; }
case "$CMD" in
  clean-check) call_ef '{"action":"clean_check"}' ;;
  drain)       call_ef '{"action":"drain"}' ;;
  push)        call_ef "{\"action\":\"push\",\"store\":\"$STORE\",$(target_json),\"force\":$FORCE}" ;;
  on|off)
    OP="listing_on"; [ "$CMD" = "off" ] && OP="listing_off"
    OLD="null"; [ "$CMD" = "off" ] && OLD='"true"'
    CH="[{\"op\":\"$OP\",\"store_code\":\"$STORE\",$(target_json),\"old\":$OLD}]"
    echo "── check (p_commit false)"; call_rpc shop_listing_set "{\"p_changes\":$CH,\"p_commit\":false,\"p_ack\":[]}"
    ACK=$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(json.dumps([w["key"] for w in j.get("warnings",[])]))' "$OUT" 2>/dev/null || echo '[]')
    BLOCKS=$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(len(j.get("blocks",[])))' "$OUT" 2>/dev/null || echo 1)
    if [ "$BLOCKS" != "0" ]; then echo "blocked — nothing saved (see blocks above)"; exit 5; fi
    echo "── save (p_commit true · ack $ACK)"; call_rpc shop_listing_set "{\"p_changes\":$CH,\"p_commit\":true,\"p_ack\":$ACK}" ;;
esac
unset TOKEN LOGIN ANON
