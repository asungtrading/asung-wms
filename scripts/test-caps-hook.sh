#!/usr/bin/env bash
# check-caps.sh 의 자기 검증 (2026-08-12)
# ─────────────────────────────────────────────────────────────
# ⚠️ 핵심은 **소급 검증**이다: "이 훅이 있었으면 과거 사고를 막았는가"가 유일한 시험.
#    원안(.eq/.in 아무 컬럼 통과)은 5건 중 4건(3호·4호·#6·#7)을 놓쳤다 — .eq("status") 가
#    행 수를 한정하지 않는데 통과됐기 때문. 그래서 식별자 컬럼만 통과(B안)로 채택했고,
#    이 테스트가 그 소급 검증을 고정한다(규칙 20 캡 함정 절).
# 실행: bash scripts/test-caps-hook.sh   (전부 PASS 여야 커밋 훅을 신뢰할 수 있다)
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel) || exit 1
CHECK="$ROOT/scripts/check-caps.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0

expect(){ # expect <want:0|1> <label> <file>
  bash "$CHECK" "$3" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$1" ]; then echo "PASS  $2"; else echo "FAIL  $2 (want exit $1, got $got)"; fail=1; fi
}

# ── 소급 5건: 전부 거부(exit 1)돼야 한다 ──
cat > "$TMP/incident1.html" <<'EOF'
// 1호 purchaseList 상당 — 상태 필터만, 무LIMIT
const r=await sb.from("wms_receipts").select("*").eq("status","completed").order("created_at");
EOF
expect 1 "소급 1호: 상태 필터만(purchaseList 상당)" "$TMP/incident1.html"

cat > "$TMP/incident2.html" <<'EOF'
// 2호 saleList SO-14106 상당 — 오름차순 무LIMIT
const r=await sb.from("wms_orders").select("*").order("imported_at");
EOF
expect 1 "소급 2호: 오름차순 무LIMIT(saleList 상당)" "$TMP/incident2.html"

cat > "$TMP/incident3.html" <<'EOF'
// 3호 packer donePick 원형
const donePick=await sb.from("wms_pick_tasks").select("id,batch_label,order_id").eq("status","completed").order("completed_at");
EOF
expect 1 "소급 3호: donePick 원형(.eq status 는 한정이 아니다)" "$TMP/incident3.html"

cat > "$TMP/incident4.html" <<'EOF'
// 4호 fulfillment 완료 팩 원형
const packs=await sb.from("wms_pack_tasks").select("order_id").eq("status","completed");
EOF
expect 1 "소급 4호: fulfillment 완료 팩 원형" "$TMP/incident4.html"

cat > "$TMP/incident5.html" <<'EOF'
// 5호 admin pallet_items 원형 — 무필터 전량
const its=await sb.from("wms_pallet_items").select("order_id");
EOF
expect 1 "소급 5호: pallet_items 전량" "$TMP/incident5.html"

# ── Promise.all 형제 쿼리 분리: 형제의 .limit 이 나를 통과시키면 안 된다 ──
cat > "$TMP/siblings.html" <<'EOF'
const [a,b]=await Promise.all([
  sb.from("wms_orders").select("*").order("updated_at",{ascending:false}).limit(40),
  sb.from("wms_pick_tasks").select("status"),
]);
EOF
expect 1 "세그먼트 분리: 형제의 .limit 이 옆 쿼리를 통과시키지 않음" "$TMP/siblings.html"

# ── 통과해야 하는 것들 ──
cat > "$TMP/ok.html" <<'EOF'
const a=await sb.from("wms_pick_tasks").select("*").eq("status","completed").order("completed_at",{ascending:false}).limit(1000);
const b=await sb.from("wms_orders").select("*").eq("id",42);
const c=await sb.from("wms_pick_task_lines").select("*").in("pick_task_id",ids);
const d=await sb.from("wms_pack_tasks").select("id",{count:"exact",head:true});
const e=await sb.from("wms_orders").select("*").eq("id",1).maybeSingle();
const f=await sb.from("wms_pallet_items").select("order_id").in("order_id",oids).order("id").range(0,999);
const g=await sb.from("wms_zone_sequence").select("*");   // caps-ok: 존 마스터 — 수십 행
// caps-ok: 윗줄 주석 형태도 통과
const h=await sb.from("wms_staff").select("*").order("name");
EOF
expect 0 "통과: limit/식별자 eq·in/count/single/range/caps-ok(같은 줄·윗줄)" "$TMP/ok.html"

# ── 사유 없는 caps-ok 는 통과 못 함 ──
cat > "$TMP/nocause.html" <<'EOF'
const a=await sb.from("wms_pick_tasks").select("status");   // caps-ok:
EOF
expect 1 "사유 없는 caps-ok 거부" "$TMP/nocause.html"

# ── 레포 전체가 깨끗해야 한다(기존 파일 커밋이 막히지 않게 — caps-ok 부착 상태 검증) ──
expect 0 "레포 전체 클린(기존 13+14곳 caps-ok 부착 확인)" ""

[ $fail -eq 0 ] && echo "── 전부 PASS" || { echo "── 실패 있음"; exit 1; }
