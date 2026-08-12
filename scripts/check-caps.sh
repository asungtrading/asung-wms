#!/usr/bin/env bash
# PostgREST 1000행 캡 함정 검사 (2026-08-12 — 규칙 20 캡 함정 5건 이후 도입)
# ─────────────────────────────────────────────────────────────
# PostgREST 는 요청하지 않아도 1000행에서 자른다. 오름차순이면 최신이 조용히 사라진다.
# 실사고 5건: purchaseList · saleList SO-14106 · packer donePick(3호) · fulfillment 완료 팩(4호) ·
# admin pallet_items(5호 — 이미 2517/1000 초과 상태로 발견).
#
# 검사 단위 = Supabase 쿼리 세그먼트(sb.from( / sbGet( / sbSelect( 각각 — ⚠️ Promise.all 안의
# 형제 쿼리가 서로의 .limit 으로 통과되지 않게 토큰 단위로 쪼갠다. 시제품에서 실측한 오판정).
#
# 통과 조건(하나라도):
#   .limit( · .range( · count: · single()/maybeSingle() · head:true
#   .eq(/.in( 의 **식별자 컬럼**("...id" | sku | base_sku | barcode | email)
#     ⚠️ .eq("status") 는 통과가 아니다 — 행 수를 한정하지 않는다. 원안(아무 컬럼 통과)은
#        소급 검증("이 훅이 있었으면 그 사고를 막았는가")에서 5건 중 4건을 놓쳤다.
#   caps-ok 주석(세그먼트 안 또는 바로 윗줄): // caps-ok: <사유>  — 사유 필수
#
# 사용: check-caps.sh            → 레포 전체
#       check-caps.sh --staged   → 스테이징된 파일만 (pre-commit 이 쓰는 모드)
#       check-caps.sh <파일...>  → 지정 파일
# TODO 추적: grep -rn "caps-ok: TODO" *.html supabase/functions | wc -l  (줄어야 정상)
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

FILES=()
if [ "${1:-}" = "--staged" ]; then
  while IFS= read -r f; do
    case "$f" in *.html|supabase/functions/*.ts) [ -f "$f" ] && FILES+=("$f");; esac
  done < <(git diff --cached --name-only --diff-filter=ACM)
elif [ $# -gt 0 ]; then
  FILES=("$@")
else
  while IFS= read -r f; do FILES+=("$f"); done \
    < <(git ls-files '*.html' 'supabase/functions/*.ts' 2>/dev/null)
fi
[ ${#FILES[@]} -eq 0 ] && exit 0

python3 - "${FILES[@]}" <<'PY'
import re, sys

START = re.compile(r'sb\s*\.\s*from\(|sbGet\(\s*["\']|sbSelect\(\s*["\']')
PASS_ANY = re.compile(r'\.limit\(|\.range\(|count\s*:|\bsingle\(\)|maybeSingle\(\)|head\s*:\s*true')
PASS_ID  = re.compile(r'\.(eq|in)\(\s*["\']([a-z0-9_]*id|sku|base_sku|barcode|email)["\']')
PASS_URL = re.compile(r'=eq\.|=in\.\(|[?&][lL]imit=')
IS_WRITE = re.compile(r'\.(insert|update|delete|upsert)\(')
CAPS_OK  = re.compile(r'caps-ok:\s*\S')

bad = []
for path in sys.argv[1:]:
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    starts = [m.start() for m in START.finditer(text)]
    for i, s in enumerate(starts):
        end = starts[i+1] if i+1 < len(starts) else min(len(text), s+1500)
        seg = text[s:min(end, s+1500)]
        url_style = seg.startswith(("sbGet", "sbSelect"))
        if url_style:
            if PASS_URL.search(seg) or CAPS_OK.search(seg):
                continue
        else:
            if IS_WRITE.search(seg.split(".select(")[0]) or ".select(" not in seg:
                continue  # 쓰기 체인 / select 없는 조각
            if PASS_ANY.search(seg) or PASS_ID.search(seg) or CAPS_OK.search(seg):
                continue
        # 바로 윗줄의 caps-ok 도 통과
        line_no = text.count("\n", 0, s) + 1
        lines = text.splitlines()
        prev = lines[line_no-2] if line_no >= 2 else ""
        if CAPS_OK.search(prev):
            continue
        snippet = re.sub(r'\s+', ' ', seg)[:110]
        bad.append((path, line_no, snippet))

if bad:
    print("커밋 중단: PostgREST 1000행 캡에 걸릴 수 있는 조회 —")
    print("  PostgREST 는 요청하지 않아도 1000행에서 자른다. 오름차순이면 최신이 조용히 사라진다.")
    print("  (실사고 5건 — 규칙 20 캡 함정. 처방: 내림차순+.limit / 식별자 .eq·.in / .range 페이지네이션)")
    print("  의도된 무제한이면 사유를 달 것: // caps-ok: <왜 안 자라는지>")
    print()
    for p, ln, sn in bad:
        print(f"  {p}:{ln}\t{sn}")
    sys.exit(1)
sys.exit(0)
PY
