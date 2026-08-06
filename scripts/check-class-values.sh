#!/usr/bin/env bash
# 분류 값 검사: 코드의 wms_discrepancies.reason / wms_reports.kind 리터럴이
# DB CHECK 목록에 들어 있는지 대조한다 (2026-08-06, 규칙 41).
#
# 코드에 새 분류를 넣고 CHECK 마이그레이션을 빠뜨리면 첫 insert 가 400(23514)으로
# 죽는다 — 특히 EF 리시빙 discrepancy 선기록 실패는 Apply 중단(규칙 27 R12).
# 사람의 기억 대신 커밋 시점에 잡는다.
#
# CHECK 목록의 출처 = supabase/migrations/*.sql 파싱 (하드코딩 금지 — 두 곳이
# 갈라지면 검사가 거짓말을 한다). 같은 제약을 재정의(drop+add)하는 마이그레이션이
# 여러 개면 파일명 정렬상 마지막 정의가 이긴다 — DB 적용 순서와 같은 의미론
# (2026-08-06 사용자 결정). drop 만 하고 add 가 없으면 그 제약은 검사에서 빠진다.
# ⚠️ 모르면 멈춤: 마이그레이션이 제약 이름(wms_*_check)이나 대상 컬럼 CHECK 를
# 언급하는데 파서가 값 목록을 추출하지 못하면, 낡은 정의로 조용히 폴백하지 않고
# "이 파일의 CHECK 정의를 해석할 수 없다" 로 실패 처리한다 (exit 2 → 커밋 차단).
#
# 판정:
#   코드에 있는데 CHECK 에 없음  → FAIL (커밋 차단)
#   CHECK 에 있는데 코드에 없음  → 참고만 (폐기 후보일 수 있다 — 막지 않는다)
#
# ⚠️⚠️ 이 검사가 못 잡는 것 (통과 ≠ 완전 보장):
#   - 변수·함수 인자로 흘러 들어가는 값: const R="new_x"; insert({reason:R})
#     (단, `kindDb="box_barcode"` 같은 kind*/reason* 이름의 단순 대입은 잡는다)
#   - 테이블 참조(wms_discrepancies/discrepancies.push/wms_reports)에서 ±30줄 넘게
#     떨어진 곳에서 조립되는 값 — 근접 스코핑은 오탐(EF skip 사유, fulfillment 드래그
#     kind 등 DB 무관 reason:/kind: 리터럴)을 거르기 위한 것으로, 확실한 것만
#     실패로 처리한다는 원칙의 대가다
#   - 여러 줄에 걸친 삼항 등 한 줄을 벗어나는 표현식 (한 줄 삼항 `k?"a":"b"` 는 잡는다)
#   - PostgREST 필터 문자열(eq("reason",…)) — insert 가 아니므로 검사 대상 아님
#
# 사용법:
#   scripts/check-class-values.sh              # 워킹트리 전체 검사
#   scripts/check-class-values.sh --staged     # 스테이징된 코드만 (pre-commit hook)
#   scripts/check-class-values.sh path/to/file ...
#
# 종료 코드: 0 = 통과, 1 = CHECK 에 없는 값 존재, 2 = 파싱/읽기 실패
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
cd "$ROOT" || exit 2

MODE=worktree
FILES=()
for arg in "$@"; do
  case "$arg" in
    --staged) MODE=staged ;;
    -h|--help) sed -n '2,37p' "$0"; exit 0 ;;
    *) FILES+=("$arg") ;;
  esac
done

# ALL_CODE = 참고(역방향) 검사와 확장 스캔의 모집단. 추적 + 미추적(ignore 제외).
ALL_CODE=$(git ls-files -co --exclude-standard -- '*.html' '*.js' '*.ts')

if [ "$MODE" = staged ]; then
  MIGS=$(git ls-files -- 'supabase/migrations/*.sql')
  SCAN=$(git diff --cached --name-only --diff-filter=ACMR -- '*.html' '*.js' '*.ts')
  # 이번 커밋이 CHECK 마이그레이션을 건드리면 (목록이 좁아졌을 수 있으므로)
  # staged 파일만이 아니라 인덱스의 코드 전체를 대조한다.
  STAGED_MIGS=$(git diff --cached --name-only --diff-filter=ACMRD -- 'supabase/migrations/*.sql')
else
  # 워킹트리 모드는 아직 add 안 한 새 마이그레이션도 봐야 한다.
  MIGS=$(ls -1 supabase/migrations/*.sql 2>/dev/null)
  SCAN=$ALL_CODE
  STAGED_MIGS=""
fi
if [ ${#FILES[@]} -gt 0 ]; then
  SCAN=$(printf '%s\n' "${FILES[@]}")
fi

export MODE MIGS SCAN STAGED_MIGS ALL_CODE
python3 <<'PY'
import os, re, subprocess, sys

WINDOW = 30                      # 리터럴 ↔ 테이블 참조 허용 거리(줄)
mode   = os.environ.get("MODE", "worktree")

def env_list(name):
    return [l for l in os.environ.get(name, "").split("\n") if l.strip()]

def read(path):
    """staged 모드면 인덱스의 blob 을, 아니면 워킹트리 파일을 읽는다."""
    if mode == "staged":
        out = subprocess.run(["git", "show", f":{path}"], capture_output=True)
        if out.returncode != 0:
            return None
        return out.stdout.decode("utf-8", "replace")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None

# ── ① CHECK 목록: 마이그레이션 파싱 ──────────────────────────────
# 파일명 정렬 순서 = 적용 순서. 파일 안에서는 문장 위치 순서.
# drop 은 제약 이름으로 지우고, add 는 (테이블, 컬럼) 에 정의를 놓는다
# → 관례적 "drop if exists + add" 는 자연스럽게 마지막 add 가 남는다.
TARGETS = {("wms_discrepancies", "reason"), ("wms_reports", "kind")}
ADD  = re.compile(r'alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(\S+)\s+'
                  r'add\s+constraint\s+(\S+)\s+check\s*\(\s*\(?\s*'
                  r'(reason|kind)\s+in\s*\(([^()]*)\)', re.I | re.S)
DROP = re.compile(r'alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(\S+)\s+'
                  r'drop\s+constraint\s+(?:if\s+exists\s+)?([^\s;]+)', re.I)
# "모르면 멈춤" 신호: 이 패턴이 ADD/DROP 로 해석된 구간 밖에서 나타나면
# 파서가 그 정의를 놓친 것이다 → 낡은 목록으로 검사하는 대신 실패 처리.
SIGNALS = [re.compile(r'check\s*\(\s*\(*\s*(?:reason|kind)\b', re.I),      # = any 서식 포함
           re.compile(r'wms_(?:discrepancies_reason|reports_kind)_check', re.I)]

def norm_table(t):
    return t.strip().strip('"').split(".")[-1].strip('"')

def strip_sql_comments(text):
    return re.sub(r'--[^\n]*', '', text)

checks, errors = {}, []          # (table,col) -> {"values":[...], "src":file, "cname":name}
for path in sorted(env_list("MIGS")):
    text = read(path)
    if text is None:
        errors.append(f"{path}: 읽을 수 없음")
        continue
    text = strip_sql_comments(text)
    events = sorted(
        [(m.start(), "add", m) for m in ADD.finditer(text)] +
        [(m.start(), "drop", m) for m in DROP.finditer(text)])
    spans = [m.span() for _, _, m in events]
    if any(not any(a <= m.start() < b for a, b in spans)
           for sig in SIGNALS for m in sig.finditer(text)):
        errors.append(f"{path}: 이 파일의 CHECK 정의를 해석할 수 없다 "
                      f"(reason/kind 제약을 언급하지만 파서가 값 목록을 추출하지 못함 "
                      f"— SQL 서식이 파서 정규식과 어긋남, scripts/check-class-values.sh 수정 필요)")
    for _, typ, m in events:
        table = norm_table(m.group(1))
        if typ == "add":
            col = m.group(3).lower()
            if (table, col) in TARGETS:
                vals = re.findall(r"'([^']*)'", m.group(4))
                checks[(table, col)] = {"values": vals, "src": path,
                                        "cname": m.group(2).strip('"')}
        else:
            cname = m.group(2).strip('"')
            for key in [k for k, v in checks.items()
                        if k[0] == table and v["cname"] == cname]:
                del checks[key]

if not checks and not errors:
    # add 를 한 번도 못 봤다 = 제약이 정말 없거나 파서가 깨졌다.
    # 오늘(2026-08-06) 기준 제약은 존재하므로, 못 찾으면 검사 불능으로 막는다
    # — 조용히 통과시키면 "검사인 척" 이 된다.
    print("check-class-values: 마이그레이션에서 reason/kind CHECK 정의를 찾지 못했다.")
    print("  제약을 정말 없앴다면 이 스크립트를 함께 정리하고,")
    print("  아니라면 파서 정규식이 SQL 서식과 어긋난 것이다 (scripts/check-class-values.sh).")
    sys.exit(2)

# ── ② 코드 스캔 (정방향: 코드 → CHECK) ─────────────────────────
# reason:/kind: (또는 kindDb= 같은 파생 이름 대입) 뒤의 소문자 스네이크 리터럴만,
# 그것도 테이블 참조 ±WINDOW 줄 안에서만 센다. 한 줄 삼항의 양 갈래도 잡는다.
COLS = {"reason": ("wms_discrepancies", "reason"),
        "kind":   ("wms_reports", "kind")}
KEYED = {c: re.compile(r'(?<![\w-])' + c + r'[A-Za-z]*\s*[:=](?!=)\s*(["\'])([a-z][a-z0-9_]*)\1')
         for c in COLS}
TERNARY = {c: re.compile(r'(?<![\w-])' + c + r'[A-Za-z]*\s*:\s*[^,{}?\n]*\?\s*'
                         r'(["\'])([a-z][a-z0-9_]*)\1\s*:\s*(["\'])([a-z][a-z0-9_]*)\3')
           for c in COLS}
ANCHOR = {"reason": re.compile(r'wms_discrepancies|discrepancies\s*\.\s*push'),
          "kind":   re.compile(r'wms_reports')}

scan = env_list("SCAN")
staged_migs = env_list("STAGED_MIGS")
if staged_migs:
    touched = []
    for p in staged_migs:
        t = read(p)                      # 삭제된 파일이면 None → HEAD 쪽을 본다
        if t is None:
            out = subprocess.run(["git", "show", f"HEAD:{p}"], capture_output=True)
            t = out.stdout.decode("utf-8", "replace") if out.returncode == 0 else ""
        if re.search(r'(reason|kind)\s+in\s*\(', strip_sql_comments(t), re.I):
            touched.append(p)
    if touched:
        scan = env_list("ALL_CODE")
        print(f"참고: 이 커밋이 CHECK 마이그레이션을 건드려 코드 전체를 대조한다 "
              f"({', '.join(touched)})")

found = {}                       # (col, value) -> [ "file:line", ... ]
n_sites = {c: 0 for c in COLS}
for path in scan:
    text = read(path)
    if text is None:
        errors.append(f"{path}: 읽을 수 없음")
        continue
    lines = text.split("\n")
    anchors = {c: [i for i, l in enumerate(lines) if ANCHOR[c].search(l)]
               for c in COLS}
    for c in COLS:
        if not anchors[c]:
            continue
        for i, line in enumerate(lines):
            vals = [m.group(2) for m in KEYED[c].finditer(line)]
            for m in TERNARY[c].finditer(line):
                vals += [m.group(2), m.group(4)]
            if vals and any(abs(i - a) <= WINDOW for a in anchors[c]):
                for v in vals:
                    found.setdefault((c, v), []).append(f"{path}:{i + 1}")
                    n_sites[c] += 1

# ── ③ 판정 & 출력 ───────────────────────────────────────────────
label = " (staged)" if mode == "staged" else ""
print(f"분류값 검사{label} — 코드 리터럴 vs DB CHECK")
srcs = sorted({v["src"] for v in checks.values()})
for s in srcs:
    print(f"  CHECK 출처: {s}")

bad = []
for col, (table, _) in COLS.items():
    key = (table, col)
    if key not in checks:
        print(f"  {col:<6} ({table})  CHECK 없음(drop됨) → 검사 생략")
        continue
    allowed = set(checks[key]["values"])
    used = {v for (c, v) in found if c == col}
    unknown = sorted(used - allowed)
    state = "ok" if not unknown else f"FAIL  CHECK 에 없는 값 {len(unknown)}개"
    print(f"  {col:<6} ({table})  CHECK {len(allowed)}개 · 코드 {len(used)}값/{n_sites[col]}곳  {state}")
    for v in unknown:
        for site in found[(col, v)]:
            bad.append(f"  FAIL  {site}  {col} \"{v}\" — CHECK 목록에 없음")

# 역방향(참고만): CHECK 에 있는데 코드 어디에서도 안 보이는 값. 느슨한 전체 검색
# ("v"/'v' 부분 문자열)이라 삼항·변수 대입·라벨 맵까지 걸리고, 그래도 없으면 알린다.
universe = {}
for p in env_list("ALL_CODE"):
    t = read(p)
    if t is not None:
        universe[p] = t
for col, (table, _) in COLS.items():
    key = (table, col)
    if key not in checks:
        continue
    for v in checks[key]["values"]:
        if not any(f'"{v}"' in t or f"'{v}'" in t for t in universe.values()):
            print(f"  참고  {col} '{v}' 는 CHECK 에 있지만 코드에서 안 보인다 — "
                  f"폐기 후보인지 확인 (커밋은 막지 않음)")

for line in bad:
    print(line)
for e in errors:
    print(f"  ! {e}")

if bad:
    print()
    print("CHECK 에 없는 분류 값이 코드에 있다 — 이대로면 첫 insert 가 400(23514)으로 죽는다.")
    print("새 분류는 CHECK 를 바꾸는 마이그레이션이 코드보다 먼저다 (규칙 41):")
    print("  supabase migration new <name> → 제약 drop+add 재정의 → supabase db reset 으로 검증")
    print("  (supabase db push 는 사람이 직접)")
sys.exit(1 if bad else (2 if errors else 0))
PY
