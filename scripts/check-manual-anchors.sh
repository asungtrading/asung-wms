#!/usr/bin/env bash
# 매뉴얼 앵커 대조 — docs/manual/en 과 docs/manual/ko 의 목차가 어긋나지 않게 (판정 710 · manual-1a · 2026-10-25)
# ─────────────────────────────────────────────────────────────
# 검사 (FAIL = 멈춤 · WARN = 알리기만):
#   1 en/*.md 와 ko/*.md 의 파일 이름 집합이 같다                         FAIL
#   2 파일마다 앵커(<a id="…"></a>) 목록이 순서까지 같다 — 갈리는 자리를 줄로  FAIL
#   3 앵커 꼴 ^[a-z0-9]+(-[a-z0-9]+)*$ · 한 언어 안에서 겹침 없음             FAIL
#   4 앵커 바로 아래(빈 줄 · 제목 줄 건너) <!-- screen: … --> 가 있다          WARN
#     그 절의 <!-- who: … --> 가 있고 어휘가 manager · admin · accounting ·
#     office · sales · warehouse · all 안이다                                 WARN
#   5 문서 안 링크 ](#…) · ](파일.md#…) · ](파일.md) 가 실제 자리를 가리킨다   FAIL
#     (en · ko 원고와 README · http 링크는 보지 않는다)
#   6 docs/manual 아래 .md 어디에도 「cin7」(대소문자 무관)이 없다(판정 714)    FAIL
# ⚠️ 앵커는 제목에서 만들지 않는다 — 한국어 제목이면 영 · 한이 달라진다. 제목 바로 위 <a id> 로 박는다.
# ⚠️ ``` 코드 블록 · <!-- 주석 --> 안의 앵커 · 링크는 세지 않는다(README 의 예시가 걸리지 않게).
#
# 사용: scripts/check-manual-anchors.sh              → 레포의 docs/manual
#       scripts/check-manual-anchors.sh <매뉴얼 폴더>  → 그 폴더(시험용 사본)
# 끝 줄: ANCHORS_OK <en+ko 파일 수> <en+ko 앵커 수>  |  ANCHORS_FAIL <걸린 수> (exit 1)
# 쓰는 것: bash + python3(표준 라이브러리만)
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DIR="${1:-$ROOT/docs/manual}"
if [ ! -d "$DIR" ]; then echo "no such folder: $DIR"; echo "ANCHORS_FAIL 1"; exit 1; fi
command -v python3 >/dev/null || { echo "python3 not found"; echo "ANCHORS_FAIL 1"; exit 1; }

python3 -I - "$DIR" <<'PY'
import os, re, sys

base = sys.argv[1]
LANGS = ["en", "ko"]
WHO = {"manager", "admin", "accounting", "office", "sales", "warehouse", "all"}
ANCHOR_RE = re.compile(r'<a id="([^"]*)"></a>')
FORM_RE = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
LINK_RE = re.compile(r'\]\(([^)\s]+)\)')
fails, warns = [], []

def strip(lines):
    """코드 블록 · 주석 안은 빈 줄로 바꾼 사본(줄 번호는 그대로)."""
    out, fence, comment = [], False, False
    for ln in lines:
        s = ln
        if s.lstrip().startswith("```"):
            fence = not fence; out.append(""); continue
        if fence: out.append(""); continue
        keep = ""
        i = 0
        while i < len(s):
            if comment:
                j = s.find("-->", i)
                if j < 0: i = len(s); break
                comment = False; i = j + 3
            else:
                j = s.find("<!--", i)
                if j < 0: keep += s[i:]; break
                keep += s[i:j]; comment = True; i = j + 4
        out.append(keep)
    return out

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read().split("\n")

def anchors_of(lines):
    res = []
    for n, ln in enumerate(strip(lines), 1):
        for m in ANCHOR_RE.finditer(ln):
            res.append((m.group(1), n))
    return res

# ── 1 파일 이름 집합 ─────────────────────────────
files = {}
for lg in LANGS:
    d = os.path.join(base, lg)
    files[lg] = sorted(f for f in os.listdir(d) if f.endswith(".md")) if os.path.isdir(d) else []
    if not os.path.isdir(d):
        fails.append(f"[1] missing folder: {lg}/")
only_en = sorted(set(files["en"]) - set(files["ko"]))
only_ko = sorted(set(files["ko"]) - set(files["en"]))
for f in only_en: fails.append(f"[1] en/{f} has no ko/{f}")
for f in only_ko: fails.append(f"[1] ko/{f} has no en/{f}")

texts, anchors = {}, {}
for lg in LANGS:
    for f in files[lg]:
        lines = read(os.path.join(base, lg, f))
        texts[(lg, f)] = lines
        anchors[(lg, f)] = anchors_of(lines)

# ── 2 앵커 목록 · 순서 ───────────────────────────
for f in sorted(set(files["en"]) & set(files["ko"])):
    a, b = anchors[("en", f)], anchors[("ko", f)]
    if [x for x, _ in a] == [x for x, _ in b]:
        continue
    for i in range(max(len(a), len(b))):
        ea = a[i] if i < len(a) else None
        kb = b[i] if i < len(b) else None
        if ea is None or kb is None or ea[0] != kb[0]:
            e_s = f'"{ea[0]}" (en line {ea[1]})' if ea else "(none)"
            k_s = f'"{kb[0]}" (ko line {kb[1]})' if kb else "(none)"
            fails.append(f"[2] {f}: anchor #{i+1} differs — en {e_s} · ko {k_s}")
            break
    if len(a) != len(b):
        fails.append(f"[2] {f}: en has {len(a)} anchors · ko has {len(b)}")

# ── 3 앵커 꼴 · 겹침 ─────────────────────────────
for lg in LANGS:
    seen = {}
    for f in files[lg]:
        for aid, n in anchors[(lg, f)]:
            if not FORM_RE.match(aid):
                fails.append(f'[3] {lg}/{f}:{n}: anchor "{aid}" is not lower-case ASCII words joined by "-"')
            if aid in seen:
                fails.append(f'[3] {lg}/{f}:{n}: anchor "{aid}" already used at {seen[aid]}')
            else:
                seen[aid] = f"{lg}/{f}:{n}"

# ── 4 screen · who 주석 ─────────────────────────
for (lg, f), lines in texts.items():
    al = anchors[(lg, f)]
    for k, (aid, n) in enumerate(al):
        end = al[k + 1][1] - 1 if k + 1 < len(al) else len(lines)
        i = n  # 앵커 다음 줄(0 기반 n)
        while i < end and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
            i += 1
        if i >= end or not lines[i].strip().startswith("<!-- screen:"):
            warns.append(f"[4] {lg}/{f}:{n}: #{aid} has no <!-- screen: … --> right under its heading")
        who = None
        for j in range(n, end):
            m = re.match(r'\s*<!--\s*who:\s*(.*?)\s*-->', lines[j])
            if m: who = m.group(1); break
        if who is None:
            warns.append(f"[4] {lg}/{f}:{n}: #{aid} has no <!-- who: … -->")
        else:
            bad = [w for w in (x.strip() for x in who.split(",")) if w not in WHO]
            if bad:
                warns.append(f"[4] {lg}/{f}:{n}: #{aid} who has words outside the list: {', '.join(bad)}")

# ── 5 링크 ──────────────────────────────────────
targets = [(lg, f, os.path.join(base, lg, f)) for lg in LANGS for f in files[lg]]
readme = os.path.join(base, "README.md")
if os.path.isfile(readme):
    targets.append(("", "README.md", readme))
anchor_cache = {}
def anchor_set(path):
    path = os.path.normpath(path)
    if path not in anchor_cache:
        anchor_cache[path] = {a for a, _ in anchors_of(read(path))} if os.path.isfile(path) else None
    return anchor_cache[path]
for lg, f, path in targets:
    label = f"{lg}/{f}" if lg else f
    for n, ln in enumerate(strip(read(path)), 1):
        for m in LINK_RE.finditer(ln):
            t = m.group(1)
            if re.match(r'^[a-z]+:', t):      # http: · mailto: …
                continue
            file_part, _, frag = t.partition("#")
            dest = path if file_part == "" else os.path.join(os.path.dirname(path), file_part)
            if file_part and not os.path.exists(dest):
                fails.append(f"[5] {label}:{n}: link ({t}) — file not found")
                continue
            if frag:
                aset = anchor_set(dest)
                if aset is None or frag not in aset:
                    fails.append(f"[5] {label}:{n}: link ({t}) — no anchor \"{frag}\"")

# ── 6 cin7 ──────────────────────────────────────
for dp, _, fs in os.walk(base):
    for fn in sorted(fs):
        if not fn.endswith(".md"): continue
        p = os.path.join(dp, fn)
        for n, ln in enumerate(read(p), 1):
            if "cin7" in ln.lower():
                fails.append(f"[6] {os.path.relpath(p, base)}:{n}: the word cin7 is not allowed in the manual (ruling 714)")

# ── 끝 ──────────────────────────────────────────
for w in warns: print("WARN " + w)
for x in fails: print("FAIL " + x)
nfiles = len(files["en"]) + len(files["ko"])
nanch = sum(len(v) for v in anchors.values())
print(f"checked: en {len(files['en'])} files · ko {len(files['ko'])} files · {nanch} anchors · {len(warns)} warnings")
if fails:
    print(f"ANCHORS_FAIL {len(fails)}"); sys.exit(1)
print(f"ANCHORS_OK {nfiles} {nanch}")
PY
