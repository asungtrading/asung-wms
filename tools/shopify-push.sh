#!/usr/bin/env bash
# tools/shopify-push.sh — Caleb 이 터미널에서 직원 길로 Shopify ② 를 돌린다 (shop-2b · 2026-10-09)
#   로그인(이메일 · 비밀번호는 화면 · 기록 · 파일에 남기지 않는다 · tools/shopify-ping.sh 와 같은 길) → 아래 갈래 하나 → 응답 json.tool
#   ⚠️ 테스트 프로젝트만 — 주소에 운영 ref(gftpcnkxbdjzzfvzwcfl)가 보이면 멈춘다
#   쓰기:  bash tools/shopify-push.sh clean-check                       # 샘플 거르기(engine rules · 판정 412) + DB 판별 안전장치
#          bash tools/shopify-push.sh on --family ANN01001FAM           # 보냄 켜기(shop_listing_set listing_on · 두 번 부르기 · 경고는 보이고 ack)
#          bash tools/shopify-push.sh on --sku ANN01291
#          bash tools/shopify-push.sh off --sku ANN01291                # 보냄 끄기(큐 한 줄 · drain 이 ARCHIVED 로 보낸다)
#          bash tools/shopify-push.sh push --family ANN01001FAM [--force]   # 바로 보내기(큐를 거치지 않는다 · hash 같으면 skipped_same_hash · --force 로 강제)
#          bash tools/shopify-push.sh push --sku ANN03907
#          bash tools/shopify-push.sh drain                             # 열린 큐를 손으로 비운다(직원 길 · 보낸 건 ≤ 20 · skipped 는 안 센다 · 판정 424 ②)
#          bash tools/shopify-push.sh stock-drain                       # ⭐ stock-1b 재고 큐(shop_stock_queue)를 손으로 비운다(직원 길 · 시간 한도 40 s)
#          bash tools/shopify-push.sh stock-push --family ANN01001FAM   # ⭐ 대상 하나의 변형 전부를 force 로 바로(위치별 숫자 · 판정 415 결)
#          bash tools/shopify-push.sh stock-push --sku ANN03907
#          bash tools/shopify-push.sh order-read --name '#1001'          # ⭐ ord-1b 오더 하나 읽기(쓰기 0 · 보호된 손님 정보 가림 보고 · --gid gid://shopify/Order/123 도)
#          bash tools/shopify-push.sh webhooks-list                    # ⭐ 스토어의 웹훅 구독 목록 · 빠진 주제
#          bash tools/shopify-push.sh webhooks-subscribe               # ⭐ ORDERS_CREATE · UPDATED · CANCELLED 를 이 EF 주소로(없는 것만)
#          bash tools/shopify-push.sh orders-poll                      # ⭐ 주기 확인을 손으로(웹훅이 빠진 오더 줍기)
#          bash tools/shopify-push.sh orders-drain                     # ⭐ 받은 일 표를 손으로 비운다(GraphQL 다시 읽기 → ingest → process · ord-1b2: 받은 일 없는 received 도 process)
#          bash tools/shopify-push.sh fulfill-drain                    # ⭐ ful-2 발송 큐(shop_fulfill_queue · ship)를 손으로 비운다(직원 길 · ≤ 20 줄 · 40 s · Shopify 에 fulfillmentCreate · Ready for pickup)
#          bash tools/shopify-push.sh order-drain                      # ⭐ ful-4b 오더 큐(shop_order_queue · order_edit)를 손으로 비운다 — 나가지 않을 몫을 Shopify 오더에서 지운다(직원 길 · cron 과 같은 EF)
#          bash tools/shopify-push.sh order-edit-preview --order '#1011'   # ⭐ ful-4b 오더 고치기 미리 보기(begin 까지 · commit 없음) — live 줄 · can_ship · calc 줄 · 보낼 값
#          bash tools/shopify-push.sh order-edit-preview --order '#1011' --try-set   # ⭐ ful-4b2 try-set — 후보 ⓐ(editable − to_remove) · ⓑ(calc − to_remove) 를 세션 따로 열어 setQuantity 까지(commit 없음) · 응답 원문
#          bash tools/shopify-push.sh resolve-customer --order <shop_order_id> --customer <customer_id>   # ⭐ ord-1b2 확인 필요(손님 여럿) 풀기 — 직원 길 rpc shop_order_resolve_customer · 미리 보기 → y 로 저장 → 다음 분의 orders_drain 이 process(화면 ord-1c 전까지)
#          bash tools/shopify-push.sh link-read [--restart]           # ⭐ link-1b 기존 상품 잇기 ① — 스토어의 상품 전부를 bulk 로 읽기 시작(shop_link_run reading · --restart 면 reading 인 옛 판을 cancelled)
#          bash tools/shopify-push.sh link-poll --run <run_id>        # ⭐ link-1b ② — bulk 상태 · COMPLETED 면 JSONL 을 shop_link_item 에 적재(40 s 예산 · more 면 다시) · read 가 될 때까지 되풀이
#          bash tools/shopify-push.sh link-plan --run <run_id>        # ⭐ link-1a ③ — 판정(rpc shop_link_plan · 숫자만 · 잇지 않는다)
#   환경:  STORE(기본 test) · SUPABASE_URL · SUPABASE_ANON_KEY 를 주면 그것을 · 없으면 asung-ims/ims-config.js 의 테스트 값
set -euo pipefail
CMD="${1:-}"; shift || true
STORE="${STORE:-test}"; FAM=""; SKU=""; FORCE="false"; ORDER=""; SHOP_ORDER=""; CUST=""; TRYSET="false"; RUN=""; RESTART="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --family) FAM="$2"; shift 2 ;;
    --sku) SKU="$2"; shift 2 ;;
    --store) STORE="$2"; shift 2 ;;
    --force) FORCE="true"; shift ;;
    --name|--gid) ORDER="$2"; shift 2 ;;
    --order) SHOP_ORDER="$2"; shift 2 ;;
    --customer) CUST="$2"; shift 2 ;;
    --try-set) TRYSET="true"; shift ;;   # ful-4b2: order-edit-preview 에서 후보 ⓐ · ⓑ setQuantity 까지(commit 없음)
    --run) RUN="$2"; shift 2 ;;          # link-1b: shop_link_run id
    --restart) RESTART="true"; shift ;;  # link-1b: reading 인 옛 판을 버리고 다시
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
case "$CMD" in clean-check|on|off|push|drain|stock-drain|stock-push|order-read|webhooks-list|webhooks-subscribe|orders-poll|orders-drain|fulfill-drain|order-drain|order-edit-preview|ping|resolve-customer|link-read|link-poll|link-plan) ;; *) echo "usage: $0 clean-check | on --family X | on --sku X | off … | push … [--force] | drain | stock-drain | stock-push --family X | --sku X | order-read --name '#1001' | --gid G | webhooks-list | webhooks-subscribe | orders-poll | orders-drain | fulfill-drain | order-drain | order-edit-preview --order '#1011' [--try-set] | resolve-customer --order <shop_order_id> --customer <customer_id>" >&2; exit 2 ;; esac
case "$CMD" in on|off|push|stock-push) if { [ -z "$FAM" ] && [ -z "$SKU" ] || [ -n "$FAM" ] && [ -n "$SKU" ]; }; then echo "give exactly one of --family or --sku" >&2; exit 2; fi ;; order-read) if [ -z "$ORDER" ]; then echo "give --name '#1001' or --gid gid://shopify/Order/123" >&2; exit 2; fi ;; resolve-customer) if [ -z "$SHOP_ORDER" ] || [ -z "$CUST" ]; then echo "give --order <shop_order_id> and --customer <customer_id> (uuids from shop_order_list · its reasons[].candidates)" >&2; exit 2; fi ;; esac
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
  stock-drain) call_ef '{"action":"stock_drain"}' ;;
  orders-poll)  call_ef '{"action":"orders_poll"}' ;;
  orders-drain) call_ef '{"action":"orders_drain"}' ;;
  fulfill-drain) call_ef '{"action":"fulfill_drain"}' ;;
  order-drain)   call_ef '{"action":"order_drain"}' ;;
  ping)          call_ef "{\"action\":\"ping\",\"store\":\"$STORE\"}" ;;
  link-read)     call_ef "{\"action\":\"link_read\",\"store\":\"$STORE\",\"restart\":$RESTART}" ;;                    # link-1b
  link-poll)     [ -n "$RUN" ] || { echo "--run <shop_link_run id> is required" >&2; exit 2; }; call_ef "{\"action\":\"link_poll\",\"run\":\"$RUN\"}" ;;
  link-plan)     [ -n "$RUN" ] || { echo "--run <shop_link_run id> is required" >&2; exit 2; }; call_rpc shop_link_plan "{\"p_run_id\":\"$RUN\"}" ;;   # link-1a 창구
  order-edit-preview) call_ef "$(python3 -c 'import json,sys; print(json.dumps({"action":"order_edit_preview","order":sys.argv[1],"try_set":sys.argv[2]=="true"}))' "$SHOP_ORDER" "$TRYSET")" ;;   # ful-4b: --order <shop_order id 또는 #1011> · begin 까지만(commit 없음) · 실물 보기   # ful-4b: 권한 대조(missing_scopes 가 [] 이어야 write_order_edits 가 승인된 것)
  webhooks-list)      call_ef "{\"action\":\"webhooks_list\",\"store\":\"$STORE\"}" ;;
  webhooks-subscribe) call_ef "{\"action\":\"webhooks_subscribe\",\"store\":\"$STORE\"}" ;;
  order-read)  call_ef "$(python3 -c 'import json,sys; print(json.dumps({"action":"order_read","store":sys.argv[1],"order":sys.argv[2]}))' "$STORE" "$ORDER")" ;;
  resolve-customer)   # ord-1b2 — 두 번 부르기: 미리 보기(p_commit false) → y 면 저장(p_commit true · prepare → received → 다음 분의 orders_drain 이 process)
    ARGS=$(python3 -c 'import json,sys; print(json.dumps({"p_shop_order_id":sys.argv[1],"p_customer_id":sys.argv[2]}))' "$SHOP_ORDER" "$CUST")
    echo "── preview (p_commit false)"; call_rpc shop_order_resolve_customer "${ARGS%\}},\"p_commit\":false}"
    read -rp "save this customer on the order? [y/N] " YN; case "$YN" in y|Y) ;; *) echo "not saved"; exit 0 ;; esac
    echo "── save (p_commit true)"; call_rpc shop_order_resolve_customer "${ARGS%\}},\"p_commit\":true}" ;;
  stock-push)  call_ef "{\"action\":\"stock_push\",\"store\":\"$STORE\",$(target_json)}" ;;
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
