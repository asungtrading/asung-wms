#!/usr/bin/env bash
# tools/shopify-oauth-exchange.sh — 조직 밖 스토어(aonebeauty.com)의 설치 코드를 영구 offline 토큰으로 한 번 바꿔 테스트 프로젝트 비밀에 넣는다 (shop-live-1 · 2026-10-27 · 판정 809 · 812 · 813 · 816)
#   순서(Caleb):
#     1. Dev Dashboard → 앱(전용 · 예 「Asung IMS Aone」 · 판정 812) → Settings/Configuration → Redirect URLs 에 https://ims.asung.ca/ 를 넣고 저장 · 권한(scope 11 · _shared/shopify.ts REQUIRED_SCOPES)을 Release
#     2. 그 앱의 설치 링크(custom distribution)로 aonebeauty.com(admin 핸들 aone-beauty-health) 에 설치 → 승인 뒤 주소창이 https://ims.asung.ca/?code=…&hmac=…&shop=…&state=… 로 돌아온다 → code= 뒤 값을 복사(짧게 산다 — 곧바로 3)
#     3. 바로 이 스크립트: bash tools/shopify-oauth-exchange.sh --shop <도메인>.myshopify.com --prefix SHOPIFY_AONE --client-id <client id>
#        → client secret · code 는 묻는다(read -s · 화면 · 기록 · 파일에 남지 않는다) → POST https://<도메인>/admin/oauth/access_token {client_id, client_secret, code}
#        → 응답의 access_token 은 출력하지 않고 supabase secrets set --env-file <(…) --project-ref fazgmyvzzhqybtvtktyg 로 <PREFIX>_ACCESS_TOKEN · <PREFIX>_CLIENT_ID · <PREFIX>_CLIENT_SECRET(웹훅 HMAC 용) 셋을 넣는다 · 성공이면 scope 글만 찍는다
#     4. IMS: Settings → Shopify Stores 에 스토어 행(secret_prefix = 같은 PREFIX · token mode stored_token · live 는 꺼진 채) → ping(missing_scopes [] · domain_mismatch 없음) → 위치 짝 → 잇기 읽기 · 판정 → 컷오버 날 Go live(orders_from = 컷 시각 · 판정 814)
#   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg = 컷오버 뒤 운영 · 판정 617)만 — 운영 WMS ref(gftpcnkxbdjzzfvzwcfl)가 보이면 멈춘다
#   ⚠️ 영구 토큰도 앱 삭제 · 앱 비밀 교체면 죽는다(Shopify 문서) — 그러면 2 ~ 3 을 다시(EF 는 401 에 다시 받지 않고 사람 말로 멈춘다 · _shared/shopify.ts storedTokenDeadSentence)
#   ⚠️ 셸 기록: 이 스크립트는 비밀을 인자로 받지 않는다(client id 만 인자 — 비밀이 아니다) · 끝에 변수를 unset · history 는 이 스크립트 안에서 끈다
#   확인: supabase secrets list --project-ref fazgmyvzzhqybtvtktyg | grep <PREFIX>_   (이름만 보인다 · 값은 안 보인다)
set -euo pipefail
set +o history 2>/dev/null || true
SHOP=""; PREFIX=""; CLIENT_ID=""; REF="fazgmyvzzhqybtvtktyg"
while [ $# -gt 0 ]; do
  case "$1" in
    --shop) SHOP="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --project-ref) REF="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; echo "usage: $0 --shop <name>.myshopify.com --prefix SHOPIFY_AONE --client-id <client id> [--project-ref fazgmyvzzhqybtvtktyg]" >&2; exit 2 ;;
  esac
done
case "$REF" in *gftpcnkxbdjzzfvzwcfl*) echo "STOP — this is the production WMS project. Secrets for the Shopify EF live on the test project (Asung-IMS · fazgmyvzzhqybtvtktyg)." >&2; exit 3 ;; esac
case "$REF" in fazgmyvzzhqybtvtktyg) ;; *) echo "STOP — project ref is not the test project (fazgmyvzzhqybtvtktyg): $REF" >&2; exit 3 ;; esac
if ! printf '%s' "$SHOP" | grep -qE '^[a-z0-9][a-z0-9-]*\.myshopify\.com$'; then echo "STOP — --shop must be the myshopify domain (lowercase · name.myshopify.com · Settings → Domains in that store's admin — it is not the admin handle): '$SHOP'" >&2; exit 2; fi
if ! printf '%s' "$PREFIX" | grep -qE '^[A-Z][A-Z0-9_]*$'; then echo "STOP — --prefix must be CAPITALS, digits or _ (e.g. SHOPIFY_AONE) and must equal shop_store.secret_prefix: '$PREFIX'" >&2; exit 2; fi
if [ -z "$CLIENT_ID" ]; then echo "STOP — --client-id is required (Dev Dashboard → the app → Client ID)" >&2; exit 2; fi
command -v supabase >/dev/null || { echo "STOP — supabase CLI not found (secrets set needs it)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "STOP — python3 not found" >&2; exit 2; }
echo "shop: $SHOP · prefix: $PREFIX · project: $REF · secrets to set: ${PREFIX}_ACCESS_TOKEN · ${PREFIX}_CLIENT_ID · ${PREFIX}_CLIENT_SECRET"

read -rsp "App client secret (not shown): " CLIENT_SECRET; echo
read -rsp "Install code from the redirect URL (code=… · not shown): " CODE; echo
if [ -z "$CLIENT_SECRET" ] || [ -z "$CODE" ]; then echo "STOP — client secret and code are both required" >&2; unset CLIENT_SECRET CODE; exit 2; fi

BODY_FILE=$(mktemp); RESP_FILE=$(mktemp); ENV_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$RESP_FILE" "$ENV_FILE"' EXIT
chmod 600 "$BODY_FILE" "$RESP_FILE" "$ENV_FILE"
python3 -c 'import json,sys; print(json.dumps({"client_id": sys.argv[1], "client_secret": sys.argv[2], "code": sys.argv[3]}))' "$CLIENT_ID" "$CLIENT_SECRET" "$CODE" > "$BODY_FILE"
HTTP=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X POST "https://$SHOP/admin/oauth/access_token" -H "Content-Type: application/json" -H "Accept: application/json" --data-binary @"$BODY_FILE")
unset CODE
rm -f "$BODY_FILE"
if [ "$HTTP" != "200" ]; then
  echo "token exchange failed: HTTP $HTTP" >&2
  python3 -c 'import json,sys
try:
  j=json.load(open(sys.argv[1])); print("  error:", j.get("error"), "·", j.get("error_description") or "")
except Exception: print("  (non-JSON body · not shown)")' "$RESP_FILE" >&2 || true
  echo "  invalid_request / invalid_grant usually = the code was already used or expired → reinstall (install link) and run again at once" >&2
  unset CLIENT_SECRET; exit 4
fi
SCOPE=$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("scope",""))' "$RESP_FILE")
HAS_TOKEN=$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print("yes" if j.get("access_token") else "no")' "$RESP_FILE")
EXPIRES=$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("expires_in","none"))' "$RESP_FILE")
if [ "$HAS_TOKEN" != "yes" ]; then echo "STOP — response has no access_token (not shown)" >&2; unset CLIENT_SECRET; exit 4; fi
if [ "$EXPIRES" != "none" ]; then echo "⚠️ the token carries expires_in=$EXPIRES — this is an EXPIRING offline token, not the permanent one (판정 809 wants no expiry) · check the app's token setting (expiring=0 default) and the install request" >&2; fi
# .env 모양: 값은 화면에 찍지 않고 파일 → supabase secrets set --env-file
python3 -c 'import json,sys
j=json.load(open(sys.argv[1])); p=sys.argv[2]
print(p+"_ACCESS_TOKEN="+j["access_token"]); print(p+"_CLIENT_ID="+sys.argv[3]); print(p+"_CLIENT_SECRET="+sys.argv[4])' "$RESP_FILE" "$PREFIX" "$CLIENT_ID" "$CLIENT_SECRET" > "$ENV_FILE"
rm -f "$RESP_FILE"
unset CLIENT_SECRET
supabase secrets set --env-file "$ENV_FILE" --project-ref "$REF"
rm -f "$ENV_FILE"
echo "ok — token exchanged for $SHOP and stored as ${PREFIX}_ACCESS_TOKEN (+ _CLIENT_ID · _CLIENT_SECRET) on $REF"
echo "scope: ${SCOPE:-(none in response — ping will read currentAppInstallation.accessScopes)}"
echo "next: Settings → Shopify Stores → store row with secret_prefix $PREFIX · token mode stored_token → ping (expect missing_scopes [] · no domain_mismatch) · the EF does not need a redeploy for a new secret"
