#!/usr/bin/env bash
# 분류 값 검사: 코드의 wms_discrepancies.reason / wms_reports.kind 리터럴이
# DB CHECK 목록에 들어 있는지 대조한다 (2026-08-06, 규칙 41).
#
# 코드에 새 분류를 넣고 CHECK 마이그레이션을 빠뜨리면 첫 insert 가 400(23514)으로
# 죽는다 — 특히 EF 리시빙 discrepancy 선기록 실패는 Apply 중단(규칙 27 R12).
# 사람의 기억 대신 커밋 시점에 잡는다.
#
# CHECK 목록의 출처 = supabase/migrations/*.sql 파싱 (하드코딩 금지 — 두 곳이
# 갈라지면 검사가 거짓말을 한다). 인식하는 서식은 둘: `alter table … add constraint …
# check (col in (…))` 와 `create table … ( … constraint … check (col in (…)) … )` 인라인
# (2026-09-08 — inv_layer 가 reason/kind 컬럼을 인라인으로 정의해 검사 불능이 났다.
# 대상 테이블이 아니면 TARGETS 필터에서 자연히 빠진다). 같은 제약을 재정의(drop+add)하는 마이그레이션이
# 여러 개면 파일명 정렬상 마지막 정의가 이긴다 — DB 적용 순서와 같은 의미론
# (2026-08-06 사용자 결정). drop 만 하고 add 가 없으면 그 제약은 검사에서 빠진다.
# ⚠️ 모르면 멈춤: 마이그레이션이 제약 이름(wms_*_check)이나 대상 컬럼 CHECK 를
# 언급하는데 파서가 값 목록을 추출하지 못하면, 낡은 정의로 조용히 폴백하지 않고
# "이 파일의 CHECK 정의를 해석할 수 없다" 로 실패 처리한다 (exit 2 → 커밋 차단).
#   ⚠️ [2026-09-18] 그 신호가 **표 이름을 안 봐서** IMS 표에 걸렸다 — po_receipt_diff 의 둘째 CHECK
#   `((kind = 'off_po') = (po_line_id is null))` 은 값 목록이 아니라 파서가 못 읽는 것이 맞지만, 대상 두 표와 무관하다
#   (같은 표의 `kind in (…)` 는 인라인 파서가 읽었다 — 걸린 것은 값 목록 CHECK 가 아니었다). 그날 --no-verify 로 두 번 지나갔다.
#   ⇒ 좁혔다(끄지 않았다): 신호가 속한 **문장**(앞 ';' 부터)의 머리가 create/alter table 이고 그 표가 대상 둘이 아니면
#   신호로 치지 않는다. 문장 머리에서 표를 못 읽으면(함수 본문 안 · 낯선 서식) 전과 같이 멈춘다 — "모르면 멈춤" 은 그대로다.
#   IMS 에 reason·kind 칸이 또 생겨도 create/alter table 안에 있으면 훅을 고칠 일이 없다.
#   ⚠️ [2026-09-30 · 판정 127 · 미룬 ㉟] **짝 조건** — 20260930172829 의 `wms_reports_bins_kind_ck`
#   `check (kind = 'wrong_location' or (planned_bin is null and found_bin is null and bin_qty is null))` 은 값 목록이 아니고
#   어떤 kind 값도 막지 않는데(세 칸이 비면 모든 kind 통과) 신호에 걸려 커밋 두 번을 --no-verify 로 지나갔다(판정 125 · 126).
#   ⇒ 좁게 알아본다(끄지 않았다): SIGNALS[0] 이 대상 표 문장에서 구간 밖에 나타나면 멈추기 전에 ① 그 `check (` 부터 짝 괄호까지를 식으로
#   뗀다(문자열 안 괄호 · '' 이스케이프 무시 · 짝 없으면 멈춤) ② 맨 바깥 깊이의 `or` 로 나눈다(감싼 괄호 한 겹은 벗긴다 · 문자열 안 or 무시 ·
#   갈래가 하나면 멈춤) ③ 문자열을 지운 식에 그 칸이 **정확히 한 번** ④ 그 갈래가 괄호를 벗기면 정확히 `칸 = '값'` 또는 `칸 <> '값'`(`!=` 도)
#   ⑤ 통과하면 구간으로 치고 (표, 칸, 값, 제약 이름)을 짝 조건으로 기록 — 값이 그 (표, 칸)의 **최종 허용 목록**에 없으면 FAIL(exit 1 ·
#   파싱은 됐고 값이 확실히 틀렸다) · 목록이 drop 돼 없으면 exit 2. 그 밖은 전처럼 멈춘다 — 계속 멈추는 모양: `kind <> 'image_missing'` 단독(값 하나를
#   조용히 뺀다) · `kind = 'a' or kind = 'b'`(모양만 다른 목록) · `kind is null` · `kind in (…) or …` · `lower(kind) = …` · 바깥 `and`.
#   ⚠️ 한계: 다른 갈래가 늘 거짓인 식(`kind = 'x' or false`)은 사실상 값을 막지만 알아보지 못한다(갈래의 참·거짓을 셈하지 않는다 · 쓸 일 없음) ·
#   SIGNALS[0] 은 칸이 `check (` 바로 뒤에 올 때만 신호라 `check (found_bin is null or kind = 'x')` 는 전부터 조용히 지나간다(넓히지 않았다).
#   자기 시험: scripts/test-class-values-hook.sh (T0 = 옛 판으로 결함 재현 · T1 ~ T18).
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
# create table 인라인 제약 (2026-09-08). 두 단계: 헤더에서 테이블명 → 본문(다음 ';' 까지)
# 안의 `constraint <name> check ((reason|kind) in (…))` 전부. 한 테이블에 둘 이상도 잡는다.
# 매치는 ADD 와 같은 인터페이스(start/span/group 1~4)로 감싸 events 에 **동일하게** 들어간다
# — spans 에만 넣고 값을 버리면 앞으로 대상 테이블을 인라인으로 정의할 때 목록이 비게 된다.
CREATE = re.compile(r'create\s+table\s+(?:if\s+not\s+exists\s+)?(\S+)\s*\(', re.I)
INLINE = re.compile(r'constraint\s+(\S+)\s+check\s*\(\s*\(?\s*'
                    r'(reason|kind)\s+in\s*\(([^()]*)\)', re.I | re.S)

class InlineMatch:
    """CREATE 헤더 + INLINE 매치를 ADD 매치 모양으로: group(1)=테이블 · 2=제약명 · 3=컬럼 · 4=값 목록."""
    def __init__(self, table, m, offset):
        self._table, self._m, self._off = table, m, offset
    def start(self):
        return self._off + self._m.start()
    def span(self):
        return (self._off + self._m.start(), self._off + self._m.end())
    def group(self, n):
        return self._table if n == 1 else self._m.group(n - 1)

def inline_adds(text):
    out = []
    for c in CREATE.finditer(text):
        body_start = c.end()
        end = text.find(";", body_start)
        body = text[body_start:(end if end >= 0 else len(text))]
        for m in INLINE.finditer(body):
            out.append((body_start + m.start(), "add", InlineMatch(c.group(1), m, body_start)))
    return out
# "모르면 멈춤" 신호: 이 패턴이 ADD/DROP 로 해석된 구간 밖에서 나타나면
# 파서가 그 정의를 놓친 것이다 → 낡은 목록으로 검사하는 대신 실패 처리.
SIGNALS = [re.compile(r'check\s*\(\s*\(*\s*(?:reason|kind)\b', re.I),      # = any 서식 포함 · ⚠️ 표 이름을 안 본다 → signal_table 로 좁힌다(2026-09-18)
           re.compile(r'wms_(?:discrepancies_reason|reports_kind)_check', re.I)]   # 제약 이름에 표가 들어 있다 — 그대로
TARGET_TABLES = {t for t, _ in TARGETS}
# 신호가 속한 문장의 머리 — create table X ( … / alter table X … 에서 X 를 읽는다. 이름 뒤에 바로 '(' 가 붙어도(foo() 잡히지 않게 [^\s(]+.
STMT_TABLE = re.compile(r'^\s*(?:create\s+table\s+(?:if\s+not\s+exists\s+)?|'
                        r'alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?)([^\s(]+)', re.I)

def signal_table(text, pos):
    """신호 위치가 속한 문장(앞 ';' 다음부터)의 머리에서 표 이름을 읽는다. create/alter table 문장이 아니면 None = 모른다."""
    start = text.rfind(";", 0, pos) + 1
    m = STMT_TABLE.match(text[start:pos])
    return norm_table(m.group(1)) if m else None

def is_signal(idx, text, m, spans):
    """해석된 구간 안이면 신호 아님. SIGNALS[0] 은 그 문장의 표가 대상 둘이 아니라고 **확인되면** 신호 아님(다른 모듈 표의 reason/kind CHECK 는
    이 스크립트의 일이 아니다). 표를 못 읽으면 신호다 — 모르면 멈춤."""
    if any(a <= m.start() < b for a, b in spans):
        return False
    if idx == 0:
        t = signal_table(text, m.start())
        if t is not None and t not in TARGET_TABLES:
            return False
    return True

def norm_table(t):
    return t.strip().strip('"').split(".")[-1].strip('"')

# ── 짝 조건(판정 127) — 대상 표의 CHECK 가 값 목록이 아니고 값을 하나도 막지 않는 한 모양만 넘긴다 ──
TARGET_COL = dict(TARGETS)                                   # 표 → 대상 칸
CNAME_BEFORE = re.compile(r'constraint\s+(\S+)\s*$', re.I | re.S)   # 신호 앞 … constraint <name>  (없으면 인라인 칸 제약)
PAIR_BRANCH = re.compile(r"^\s*(reason|kind)\s*(?:=|<>|!=)\s*'((?:[^']|'')*)'\s*$", re.I | re.S)
OR_TOKEN = re.compile(r'(?<![\w])or(?![\w])', re.I)
COL_TOKEN = re.compile(r'\b(?:reason|kind)\b', re.I)

def check_paren_span(text, pos):
    """pos(= 'check' 의 위치) 뒤 첫 '(' 부터 짝이 맞는 ')' 까지 (i, j) — 문자열 안 괄호는 세지 않는다 · '' 이스케이프 · 짝 없으면 None."""
    i = text.find("(", pos)
    if i < 0:
        return None
    depth, j, in_str = 0, i, False
    while j < len(text):
        c = text[j]
        if in_str:
            if c == "'":
                if j + 1 < len(text) and text[j + 1] == "'":
                    j += 2
                    continue
                in_str = False
        elif c == "'":
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return (i, j + 1)
        j += 1
    return None

def mask_strings(expr):
    """작은따옴표 문자열의 속을 공백으로(길이 유지 · 위치 대응) — or · 괄호 · 칸 이름을 셀 때 쓴다."""
    out, i, in_str = [], 0, False
    while i < len(expr):
        c = expr[i]
        if in_str:
            if c == "'" and i + 1 < len(expr) and expr[i + 1] == "'":
                out.append("  "); i += 2; continue
            if c == "'":
                in_str = False; out.append(c)
            else:
                out.append(" ")
        else:
            if c == "'":
                in_str = True
            out.append(c)
        i += 1
    return "".join(out)

def strip_outer(expr, masked):
    """식 전체를 감싼 괄호 한 겹을 벗긴다(여는 괄호의 짝이 맨 끝일 때만) · (expr, masked) 를 함께 돌려준다."""
    e, m = expr.strip(), masked.strip()
    while e.startswith("(") and e.endswith(")"):
        depth = 0
        for k, c in enumerate(m):
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0 and k != len(m) - 1:
                    return e, m
        e, m = e[1:-1].strip(), m[1:-1].strip()
    return e, m

def split_top_or(expr, masked):
    """맨 바깥 깊이의 or 로 나눈다 — [(갈래 원문, 갈래 마스크)] · 문자열 안 or 는 마스크에 없다."""
    parts, cuts, depth, last, k = [], [], 0, 0, 0
    while k < len(masked):
        c = masked[k]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif depth == 0 and c in "oO":
            mo = OR_TOKEN.match(masked, k)
            if mo:
                cuts.append((k, mo.end()))
                k = mo.end()
                continue
        k += 1
    for a, b in cuts:
        parts.append((expr[last:a], masked[last:a])); last = b
    parts.append((expr[last:], masked[last:]))
    return parts

def pair_condition(text, m, path):
    """SIGNALS[0] 매치 m 이 「짝 조건」이면 (span, record) · 아니면 None(= 전처럼 멈춘다)."""
    table = signal_table(text, m.start())
    if table is None or table not in TARGET_COL:
        return None
    col = TARGET_COL[table]
    sp = check_paren_span(text, m.start())                       # ① 짝 괄호
    if sp is None:
        return None
    expr = text[sp[0] + 1:sp[1] - 1]
    expr, masked = strip_outer(expr, mask_strings(expr))
    branches = split_top_or(expr, masked)                        # ② 맨 바깥 or
    if len(branches) < 2:
        return None
    if len(COL_TOKEN.findall(masked)) != 1:                      # ③ 칸이 정확히 한 번(문자열 제외)
        return None
    hit = [b for b in branches if COL_TOKEN.search(b[1])]
    if len(hit) != 1:
        return None
    be, bm = strip_outer(hit[0][0], hit[0][1])
    pm = PAIR_BRANCH.match(be)                                   # ④ 정확히 칸 = '값' / 칸 <> '값'
    if pm is None or pm.group(1).lower() != col:
        return None
    value = pm.group(2).replace("''", "'")
    stmt_start = text.rfind(";", 0, m.start()) + 1
    cm = CNAME_BEFORE.search(text[stmt_start:m.start()])
    cname = cm.group(1).strip('"') if cm else "(이름 없음)"
    return (m.start(), sp[1]), {"table": table, "col": col, "value": value, "src": path, "cname": cname}   # 구간은 신호(check) 부터 닫는 괄호까지 — is_signal 이 m.start() 로 본다

def strip_sql_comments(text):
    return re.sub(r'--[^\n]*', '', text)

checks, errors = {}, []          # (table,col) -> {"values":[...], "src":file, "cname":name}
pairs = []                       # 짝 조건(판정 127): {"table","col","value","src","cname"} — 값은 최종 목록과 대조(아래 ③)
for path in sorted(env_list("MIGS")):
    text = read(path)
    if text is None:
        errors.append(f"{path}: 읽을 수 없음")
        continue
    text = strip_sql_comments(text)
    events = sorted(
        [(m.start(), "add", m) for m in ADD.finditer(text)] +
        inline_adds(text) +
        [(m.start(), "drop", m) for m in DROP.finditer(text)])
    spans = [m.span() for _, _, m in events]
    for m in SIGNALS[0].finditer(text):                          # ⑤ 짝 조건이면 구간으로 치고 기록 — 그 밖은 아래 신호 판정으로(전처럼 멈춤)
        if is_signal(0, text, m, spans):
            pc = pair_condition(text, m, path)
            if pc is not None:
                spans.append(pc[0])
                pairs.append(pc[1])
    if any(is_signal(i, text, m, spans)
           for i, sig in enumerate(SIGNALS) for m in sig.finditer(text)):
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
if pairs:                        # 짝 조건 — 몇 개를 넘겼는지 · 값이 최종 목록 안인지
    cnt = {}
    for p in pairs:
        k = f'{p["table"]}.{p["col"]}'
        cnt[k] = cnt.get(k, 0) + 1
    pair_bad = []
    for p in pairs:
        key = (p["table"], p["col"])
        if key not in checks:
            errors.append(f'{p["src"]}: 짝 조건 {p["cname"]} ({p["col"]} "{p["value"]}") 을 대조할 CHECK 목록이 없다(drop 됨) — 무엇과 대조할지 모른다')
        elif p["value"] not in set(checks[key]["values"]):
            pair_bad.append(f'  FAIL  {p["src"]}  {p["cname"]}  {p["col"]} "{p["value"]}" — 짝 조건의 값이 CHECK 목록에 없음')
    state = "값 확인 ok" if not pair_bad else f"FAIL {len(pair_bad)}개"
    print(f'  짝 조건 {len(pairs)}개 ({" · ".join(f"{k} {n}" for k, n in sorted(cnt.items()))}) — 목록 정의 아님 · {state}')
    bad += pair_bad
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
