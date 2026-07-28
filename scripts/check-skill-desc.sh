#!/usr/bin/env bash
# .claude/skills/*/SKILL.md 의 YAML frontmatter description 길이 검사.
#
# claude.ai 스킬 업로드는 description 을 1024 "문자" 로 제한한다
# (실측: 1201자/1782바이트 → "must be at most 1024 characters" 거부).
# 바이트가 아니라 문자로 세는 것으로 보이지만 확증은 없으므로 둘 다 출력한다.
# 실패 판정은 문자 수 기준, 바이트 수는 참고용.
#
# 사용법:
#   scripts/check-skill-desc.sh              # 워킹트리 전체 검사
#   scripts/check-skill-desc.sh --staged     # 스테이징된 SKILL.md 만 (pre-commit hook)
#   scripts/check-skill-desc.sh path/to/SKILL.md ...
#
# 종료 코드: 0 = 통과, 1 = 1024자 초과 존재, 2 = 파싱 실패
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
cd "$ROOT" || exit 2

MODE=worktree
FILES=()
for arg in "$@"; do
  case "$arg" in
    --staged) MODE=staged ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) FILES+=("$arg") ;;
  esac
done

CHANGED=""
# 인자로 파일을 직접 준 경우엔 그 파일들이 차단 대상
if [ ${#FILES[@]} -gt 0 ]; then
  CHANGED=$(printf '%s\n' "${FILES[@]}")
fi
if [ ${#FILES[@]} -eq 0 ]; then
  if [ "$MODE" = staged ]; then
    # 인덱스에 있는 스킬 전부를 재고, 이번 커밋이 건드린 것만 차단 대상으로 삼는다.
    # (예전에 --no-verify 로 넘어간 초과 파일도 조용히 묻히지 않게 하되,
    #  무관한 커밋을 붙잡지는 않는다.)
    CHANGED=$(git diff --cached --name-only --diff-filter=ACMR -- '.claude/skills/*/SKILL.md')
    while IFS= read -r f; do
      [ -n "$f" ] && FILES+=("$f")
    done < <(git ls-files -- '.claude/skills/*/SKILL.md' | sort)
  else
    while IFS= read -r f; do
      [ -n "$f" ] && FILES+=("$f")
    done < <(find .claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md | sort)
  fi
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "check-skill-desc: 검사할 SKILL.md 가 없다."
  exit 0
fi

MODE="$MODE" CHANGED="$CHANGED" python3 - "${FILES[@]}" <<'PY'
import os, subprocess, sys

LIMIT = 1024
WARN  = 950          # 여유 74자 미만이면 경고 (한글 문구 한 줄이 대략 그 정도)
mode  = os.environ.get("MODE", "worktree")

def read(path):
    """staged 모드면 인덱스의 blob 을, 아니면 워킹트리 파일을 읽는다."""
    if mode == "staged":
        out = subprocess.run(["git", "show", f":{path}"],
                             capture_output=True)
        if out.returncode != 0:
            return None
        return out.stdout.decode("utf-8")
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def frontmatter(text):
    """--- 로 감싼 첫 블록만 돌려준다."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            # 끝 개행을 붙여 둔다: > 블록의 clip chomping 이 마지막 줄바꿈 1개를
            # 보존하므로, 붙이지 않으면 파서에 따라 1자 적게 나온다. 큰 쪽으로 센다.
            return "\n".join(lines[1:i]) + "\n"
    return None

def parse_fallback(fm):
    """PyYAML 이 없는 머신용 최소 파서.
    description 의 단일행 / >,>-,|,|- 블록 / 들여쓴 plain 여러 줄을 처리한다."""
    lines = fm.split("\n")
    for i, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        head = line[len("description:"):].strip()
        raw = []                            # 들여쓰기만 벗긴 원본 줄 (끝 공백 보존)
        for nxt in lines[i + 1:]:
            if nxt.strip() == "":
                raw.append("")
                continue
            if not nxt[:1].isspace():      # 다음 최상위 키 → 끝
                break
            raw.append(nxt)
        if head[:1] in (">", "|"):
            fold = head[0] == ">"        # > 는 줄바꿈을 공백으로 접는다, | 는 보존
            while raw and raw[-1] == "":
                raw.pop()
            indent = next((len(r) - len(r.lstrip()) for r in raw if r.strip()), 0)
            block = [r[indent:] if r.strip() else "" for r in raw]
            if fold:
                out = [""]
                for b in block:
                    if b == "":
                        out.append("")           # 빈 줄은 실제 줄바꿈으로 남는다
                    elif out[-1]:
                        # 줄 끝 공백은 YAML 이 보존한다 (fold 공백과 별개)
                        out[-1] += " " + b
                    else:
                        out[-1] = b
                s = "\n".join(out)
            else:
                s = "\n".join(block)
            # chomping: - 는 끝 줄바꿈 제거, 기본/+ 는 유지
            return s if head.rstrip().endswith("-") else s + "\n"
        # 단일행(따옴표 가능) + plain 이어쓰기
        s = " ".join([head] + [r.strip() for r in raw if r.strip()])
        if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
            s = s[1:-1]
        return s
    return None

try:
    import yaml
    def get_desc(fm):
        data = yaml.safe_load(fm)
        if not isinstance(data, dict):
            return None
        return data.get("description")
    parser = "PyYAML"
except ImportError:
    get_desc = parse_fallback
    parser = "fallback(stdlib)"

paths = sys.argv[1:]
# staged 모드에서 이번 커밋이 실제로 건드린 파일 = 차단 대상.
# 나머지 스킬은 초과해도 알리기만 한다 (무관한 커밋을 막지 않는다).
changed = {p for p in os.environ.get("CHANGED", "").split("\n") if p}
rows, errors, bad, stale = [], [], 0, 0

for path in paths:
    text = read(path)
    if text is None:
        errors.append(f"{path}: 읽을 수 없음")
        continue
    fm = frontmatter(text)
    if fm is None:
        errors.append(f"{path}: YAML frontmatter(---) 없음")
        continue
    try:
        desc = get_desc(fm)
    except Exception as exc:                       # noqa: BLE001
        errors.append(f"{path}: frontmatter 파싱 실패 — {exc}")
        continue
    if not isinstance(desc, str):
        errors.append(f"{path}: description 키가 없거나 문자열이 아님")
        continue
    name = os.path.basename(os.path.dirname(path))
    rows.append((name, path, len(desc), len(desc.encode("utf-8"))))

width = max([len(r[0]) for r in rows], default=6)
label = " (staged)" if mode == "staged" else ""
print(f"description 길이 검사{label} — 한도 {LIMIT}자 · 파서 {parser}")
print(f"{'skill'.ljust(width)}  {'chars':>5}  {'bytes':>5}  상태")

for name, path, chars, byts in sorted(rows, key=lambda r: -r[2]):
    if chars > LIMIT:
        over = chars - LIMIT
        if mode == "staged" and path not in changed:
            # 이번 커밋과 무관한 기존 초과 — 알리되 커밋은 막지 않는다
            state = f"기존초과  {over}자 초과 (이 커밋과 무관, 별도로 고칠 것)"
            stale += 1
        else:
            state = f"FAIL  {over}자 초과 → {over}자 이상 줄여야 함"
            bad += 1
    elif chars > WARN:
        state = f"WARN  여유 {LIMIT - chars}자"
    else:
        state = f"ok    여유 {LIMIT - chars}자"
    print(f"{name.ljust(width)}  {chars:>5}  {byts:>5}  {state}")

for e in errors:
    print(f"  ! {e}")

if bad:
    print(f"\n{bad}개 스킬의 description 이 {LIMIT}자를 넘는다. "
          "업로드가 거부되니 frontmatter 를 줄일 것 "
          "(트리거 키워드는 남기고 일반어·중복어부터 제거).")
if stale:
    print(f"\n참고: 이 커밋과 무관한 스킬 {stale}개가 이미 {LIMIT}자를 넘겨 있다. "
          "업로드하려면 따로 고쳐야 한다.")
sys.exit(1 if bad else (2 if errors else 0))
PY
