#!/usr/bin/env bash
# check-class-values.sh 의 자기 검증 (ccv-fix-1 · 판정 127 · 미룬 ㉟)
# ─────────────────────────────────────────────────────────────
# ⚠️ 핵심은 **소급 검증**(T0)이다: 옛 판(HEAD 의 스크립트)이 20260930172829 의 짝 조건
#    `wms_reports_bins_kind_ck` 에서 exit 2 로 멈추던 결함을 재현하고, 새 판은 그 하나만 넘긴다.
#    나머지는 「모르면 멈춤」이 약해지지 않았는지 — 값 목록 모양(kind = 'a' or kind = 'b') · 값 하나 빼기(kind <> 'x' 단독) ·
#    is null · in · 함수 · 바깥 and 는 전부 exit 2 그대로 · 값이 목록 밖인 짝 조건은 exit 1.
# 방법: 경우마다 임시 git 레포(mktemp · git init)에 스크립트와 마이그레이션 전부를 복사하고 가짜 마이그레이션
#    29991231000000_fake.sql(정렬상 마지막)을 더해 worktree 모드로 돌린다. html/js 가 없어 코드 스캔은 빈다(그대로 둔다).
# ⚠️ T16 · T17 은 이 차수 밖의 기존 한계를 고정한다(kind in ('x') or … 는 ADD 정규식이 값 목록으로 읽고 · lower(kind) 는 신호가 안 난다) — 판정 127 「넓히지 마라」.
# 실행: bash scripts/test-class-values-hook.sh   (전부 PASS 여야 커밋 훅을 신뢰할 수 있다)
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel) || exit 1
NEW="$ROOT/scripts/check-class-values.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0

OLD="$TMP/old-check-class-values.sh"
git -C "$ROOT" show HEAD:scripts/check-class-values.sh > "$OLD" || { echo "FAIL  옛 판(HEAD)을 읽지 못했다"; exit 1; }

expect(){ # expect <want:0|1|2> <label> <script> [fake-migration-sql]
  local want=$1 label=$2 script=$3 fake=${4-}
  local repo="$TMP/repo"; rm -rf "$repo"; mkdir -p "$repo/scripts" "$repo/supabase/migrations"
  git init -q "$repo"
  cp "$script" "$repo/scripts/check-class-values.sh"
  cp "$ROOT"/supabase/migrations/*.sql "$repo/supabase/migrations/"
  if [ -n "$fake" ]; then printf '%s\n' "$fake" > "$repo/supabase/migrations/29991231000000_fake.sql"; fi
  (cd "$repo" && bash scripts/check-class-values.sh > "$TMP/out.txt" 2>&1); got=$?
  if [ "$got" -eq "$want" ]; then echo "PASS  $label"; else echo "FAIL  $label (want exit $want, got $got)"; sed 's/^/        | /' "$TMP/out.txt"; fail=1; fi
}

# ── T0 소급: 옛 판은 현재 마이그레이션(짝 조건 하나)에서 멈춘다 ──
expect 2 "T0 옛 판(HEAD) · 가짜 없음 → 결함 재현(exit 2)" "$OLD"

# ── 새 판 ──
expect 0 "T1 새 판 · 가짜 없음 → 통과(짝 조건 1개 · 값 확인 ok)" "$NEW"
expect 1 "T2 짝 조건의 값이 목록 밖(no_such_kind) → FAIL exit 1" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind = 'no_such_kind' or (planned_bin is null));"
expect 2 "T3 kind = 'a' or kind = 'b' (모양만 다른 목록) → 멈춤" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind = 'wrong_location' or kind = 'barcode_mismatch');"
expect 2 "T4 kind <> 'image_mismatch' 단독(값 하나 빼기) → 멈춤" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind <> 'image_mismatch');"
expect 0 "T5 kind <> 'wrong_location' or found_bin is null → 통과" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind <> 'wrong_location' or found_bin is null);"
expect 0 "T6 wms_discrepancies reason = 'recv_short' or note is not null → 통과" "$NEW" \
  "alter table public.wms_discrepancies add constraint f2 check (reason = 'recv_short' or note is not null);"
expect 0 "T7 대상 표 아님(po_receipt_diff · 9/18 좁힘 유지) → 통과" "$NEW" \
  "alter table public.po_receipt_diff add constraint f3 check (kind = 'zzz' or bin_id is null);"
expect 0 "T8 괄호 두른 갈래 ((kind = 'wrong_location') or (found_bin is null)) → 통과" "$NEW" \
  "alter table public.wms_reports add constraint f1 check ((kind = 'wrong_location') or (found_bin is null));"
expect 2 "T9 바깥 and → 멈춤" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind = 'wrong_location' and found_bin is not null);"
expect 2 "T10 kind 두 번(… or kind is null) → 멈춤" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind = 'wrong_location' or kind is null);"
expect 0 "T11 문자열 안 kind · or 무시(note <> 'kind or x') → 통과" "$NEW" \
  "alter table public.wms_reports add constraint f1 check (kind = 'wrong_location' or note <> 'kind or x');"
expect 2 "T12 한 문장에 둘 — f4 통과 · f5(kind <> 'box_barcode' 단독)가 멈춘다" "$NEW" \
  "alter table public.wms_reports add constraint f4 check (kind = 'wrong_location' or found_bin is null), add constraint f5 check (kind <> 'box_barcode');"
expect 0 "T13 여러 줄 CHECK · 문자열 안 '' 이스케이프와 (kind or) → 통과" "$NEW" \
  "alter table public.wms_reports
  add constraint f6 check (
    kind = 'wrong_location'
    or (note <> 'it''s (kind or)' and found_bin is null)
  );"
expect 0 "T14 괄호 두 겹 ((kind = 'wrong_location' or found_bin is null)) → 통과" "$NEW" \
  "alter table public.wms_reports add constraint f7 check ((kind = 'wrong_location' or found_bin is null));"
expect 0 "T15 한계 고정 — kind = 'wrong_location' or false 는 알아보지 못하고 넘어간다(머리 주석)" "$NEW" \
  "alter table public.wms_reports add constraint f8 check (kind = 'wrong_location' or false);"
# ── 이 차수 밖(판정 127 「넓히지 마라」) — 기존 파서의 한계를 고정한다(머리 주석 · 옛 판은 오늘 마이그레이션에서 늘 exit 2 라 대조 불가) ──
expect 0 "T16 kind in ('x') or … — 기존 ADD 정규식이 값 하나짜리 목록으로 읽는다(짝 조건은 신호가 안 나면 돌지 않는다)" "$NEW" \
  "alter table public.wms_reports add constraint f9 check (kind in ('wrong_location') or found_bin is null);"
expect 0 "T17 lower(kind) = … — SIGNALS[0] 은 check ( 바로 뒤의 칸만 신호라 지나간다(넓히지 않았다)" "$NEW" \
  "alter table public.wms_reports add constraint f10 check (lower(kind) = 'wrong_location' or found_bin is null);"
expect 0 "T18 kind != 'stock_short' or found_bin is null → 통과(!= 도 같게)" "$NEW" \
  "alter table public.wms_reports add constraint f11 check (kind != 'stock_short' or found_bin is null);"

[ $fail -eq 0 ] && echo "── 전부 PASS" || { echo "── 실패 있음"; exit 1; }
