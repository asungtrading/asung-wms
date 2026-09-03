// 결함 E — 커서 아래 최근 창 재조회 테스트 (2026-09-02 · ST-01283 실사고)
//
// 실행:  node scripts/test-invcollect-recheck-window.mjs   (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL RECHECK-WINDOW TESTS PASSED".
//
// 방식은 기존 스위트와 동일 — (a) 순수 함수(recheckListDate·recheckWindowJudge)와 ②-a
// 후보 선정(floor)·disposition 1차 결정·커서 전진 블록 **원문**을 추출·실행하고,
// (b) 배선은 정적 grep 으로 못박는다.
//
// 검증 ①~⑧ (지시서 §4):
//  ① ⭐ 커서 아래 + 최근 7일 → 후보에 남는다(recheck_window 집계)
//  ② 커서 아래 + 8일 전 → 종전대로 하한 스킵 (지시서 표현은 skip_since — 실물 메커니즘은
//     floor 드롭(skip_before_floor)이다: 커서 아래 문서는 원래 disposition 을 받기 전에 떨어진다)
//  ③ 커서 위 → 종전대로 처리(회귀 — 창 플래그 없음)
//  ④ ⭐ 재조회 문서가 커서를 뒤로 끌지도, 위쪽 전진을 막지도 않는다
//  ⑤ inv_doc_state 가 「안 바뀜」이면 상세를 안 부른다(재조회여도 skip 판정 성립 — 편집되면 불성립)
//  ⑥ 날짜를 못 얻으면 종전 동작으로 폴백 + 경고
//  ⑦ ②-b 는 무접촉(회귀)
//  ⑧ 배선 grep — 창 판정이 skip_since 분기 앞 + skip_since 에 !recheckWindow 가드
//     (+ 동적: 창으로 남긴 문서는 eff <= since 여도 skip_since 로 안 떨어진다)

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SRC = "supabase/functions/inv-collect/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

function extract(name) {
  const start = src.indexOf("function " + name);
  if (start < 0) { console.error("FAIL extract — " + name + " not found"); process.exit(1); }
  let depth = 0, end = start, started = false;
  for (let i = start; i < src.length; i++) {
    if (src[i] === "{") { depth++; started = true; }
    else if (src[i] === "}") { depth--; if (started && depth === 0) { end = i + 1; break; } }
  }
  return src.slice(start, end);
}
function extractConstArrow(name) {
  const start = src.indexOf("const " + name + " =");
  if (start < 0) { console.error("FAIL extract — const " + name + " not found"); process.exit(1); }
  const end = src.indexOf(";", src.indexOf("=>", start) < src.indexOf("{", start) && src.indexOf("{", start) > 0 && src.indexOf("{", start) < src.indexOf(";", start)
    ? src.indexOf("};", start) + 1 : start);
  // 단순화: 한 줄 화살표는 첫 ';', 블록 화살표는 '};' 까지
  const brace = src.indexOf("{", start);
  const semi = src.indexOf(";", start);
  if (brace > 0 && brace < semi) return src.slice(start, src.indexOf("};", start) + 2);
  return src.slice(start, semi + 1);
}

// 영역 분리 (②-a / ②-b) — 기존 스위트와 동일 마커
const aStart = src.indexOf("async function runSource(");
const bStart = src.indexOf("async function runDateSource(");
const bEnd = src.indexOf("for (const key of runKeys)");
const A = src.slice(aStart, bStart);
const B = src.slice(bStart, bEnd);
ok("(추출) ②-a/②-b 영역 분리", aStart > 0 && bStart > aStart && bEnd > bStart);

// ── 블록 원문 추출 ──
// floor(후보 선정): "type Cand = {" 부터 disposition 1차 결정 직전까지
const floorStart = A.indexOf("type Cand = {");
const dispoMarker = "// 상태·since 로 disposition 1차 결정";
const dispoStart = A.indexOf(dispoMarker);
const docstatePrep = A.indexOf("// ── 문서 상태 skip 준비");
const floorBlock = A.slice(floorStart, dispoStart);
const dispoBlock = A.slice(dispoStart, docstatePrep);
// 커서 전진 블록
const curStart = A.indexOf("let cursorAfter: string | null = floorUsed;");
const curEnd = A.indexOf("// 건너뜀·보류 내역 집계");
const cursorBlock = A.slice(curStart, curEnd);
ok("(추출) floor·dispo·cursor 블록", floorStart > 0 && dispoStart > floorStart && docstatePrep > dispoStart && curStart > 0 && curEnd > curStart);

const constLine = src.match(/const RECHECK_WINDOW_DAYS = \d+;/)?.[0];
ok("(상수) RECHECK_WINDOW_DAYS = 7", constLine === "const RECHECK_WINDOW_DAYS = 7;", "found " + constLine);

const dir = mkdtempSync(join(tmpdir(), "recheckwin-"));
writeFileSync(join(dir, "win.ts"),
  constLine + "\n" +
  extract("docNum") + "\n" +
  extractConstArrow("dateOnly") + "\n" +
  extractConstArrow("norm") + "\n" +
  extract("recheckListDate") + "\n" +
  extract("recheckWindowJudge") + "\n" +
  extract("docStateSkip") + "\n" +
  "\nexport function runFloorA(listRows: any, floorNum: any, key: any, numberOf: any, warnings: any) {\n" +
  floorBlock +
  "\nreturn { cands, skipBeforeFloor, recheckWindowKept, recheckWindowNoDate, recheckWindowSample, unparsableNumbers };\n}\n" +
  "\nexport function runDispoA(cands: any, key: any, since: any) {\n" +
  dispoBlock +
  "\nreturn cands;\n}\n" +
  "\nexport function runCursorA(cands: any, floorUsed: any) {\n" +
  cursorBlock +
  "\nreturn { cursorAfter, cursorHeldBy };\n}\n" +
  "export { recheckListDate, recheckWindowJudge, docStateSkip, docNum, dateOnly };\n");
execSync(`npx --yes esbuild ${join(dir, "win.ts")} --outfile=${join(dir, "win.mjs")} --format=esm`, { stdio: "pipe" });
const { runFloorA, runDispoA, runCursorA, recheckListDate, recheckWindowJudge, docStateSkip } =
  await import(join(dir, "win.mjs"));

const day = (n) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);   // n일 전 (UTC)
const numberOf = (row) => String(row?.DocNo ?? "").trim();
const FLOOR = 1289;   // 커서 = ST-01289 (실사고 그대로)

// ── ① 커서 아래 + 최근(2일 전) → 후보에 남는다 ──
{
  const warnings = [];
  const r = runFloorA(
    [{ DocNo: "ST-01283", Status: "COMPLETED", EffectiveDate: day(2) }],
    FLOOR, "adjustment", numberOf, warnings);
  const c = r.cands.find((x) => x.number === "ST-01283");
  ok("① 커서 아래 + 최근 → 후보(recheckWindow=true)", !!c && c.recheckWindow === true);
  ok("① recheck_window 집계 = 1", r.recheckWindowKept === 1 && r.recheckWindowSample.includes("ST-01283"));
  ok("① skip_before_floor 에 안 센다", r.skipBeforeFloor === 0);
}

// ── ② 커서 아래 + 8일 전 → 종전대로 하한 스킵 ──
{
  const warnings = [];
  const r = runFloorA(
    [{ DocNo: "ST-01283", Status: "COMPLETED", EffectiveDate: day(8) }],
    FLOOR, "adjustment", numberOf, warnings);
  ok("② 8일 전 → 후보 제외 + skip_before_floor", r.cands.length === 0 && r.skipBeforeFloor === 1 && r.recheckWindowKept === 0);
}

// ── ③ 커서 위 → 종전대로(창 플래그 없음 · 회귀) ──
{
  const warnings = [];
  const r = runFloorA(
    [{ DocNo: "ST-01290", Status: "COMPLETED", EffectiveDate: day(2) },
     { DocNo: "ST-01300", Status: "COMPLETED", EffectiveDate: day(40) }],
    FLOOR, "adjustment", numberOf, warnings);
  ok("③ 커서 위는 전부 후보 · 플래그 없음", r.cands.length === 2 && r.cands.every((c) => !c.recheckWindow) && r.recheckWindowKept === 0);
}

// ── ④ 커서 — 창 문서는 전진값도 hold 도 아니다 ──
{
  // (a) 창 문서가 processed 여도 커서가 그 번호(아래)로 후퇴하지 않는다
  const r1 = runCursorA([
    { number: "ST-01283", num: 1283, disposition: "processed", recheckWindow: true },
    { number: "ST-01290", num: 1290, disposition: "processed" },
    { number: "ST-01291", num: 1291, disposition: "hold_status:DRAFT" },
  ], "ST-01289");
  ok("④a 커서 후퇴 없음 — ST-01290 전진", r1.cursorAfter === "ST-01290", "got " + r1.cursorAfter);
  ok("④a hold 는 위쪽 문서(1291)", r1.cursorHeldBy && r1.cursorHeldBy.doc_number === "ST-01291");
  // (b) 창 문서가 hold(캡 등)로 남아도 위쪽 전진을 막지 않는다
  const r2 = runCursorA([
    { number: "ST-01283", num: 1283, disposition: "hold_capped", recheckWindow: true },
    { number: "ST-01290", num: 1290, disposition: "processed" },
  ], "ST-01289");
  ok("④b 창 문서 hold 가 전진을 안 막음", r2.cursorAfter === "ST-01290" && r2.cursorHeldBy == null, "got " + r2.cursorAfter);
  // (c) 창 문서뿐이면 커서는 floor 그대로
  const r3 = runCursorA([
    { number: "ST-01283", num: 1283, disposition: "processed", recheckWindow: true },
  ], "ST-01289");
  ok("④c 창 문서만 있으면 커서 무변(floor)", r3.cursorAfter === "ST-01289");
}

// ── ⑤ inv_doc_state 「안 바뀜」이면 skip 판정 성립(상세 미조회) · 편집되면 불성립 ──
{
  const state = new Map([["ST-01283", { lastModified: "2026-08-31T13:11:00Z", seenAt: "2026-08-31T13:11:00Z" }]]);
  ok("⑤ 안 바뀜 → skip(상세 안 부름)", docStateSkip(true, false, state, "ST-01283", "2026-08-31T13:11:00Z") === true);
  ok("⑤ 편집됨(LastModifiedOn 변경) → 조회", docStateSkip(true, false, state, "ST-01283", "2026-09-01T09:00:00Z") === false);
  // 배선: 상세 루프의 docStateSkip 호출 조건이 무변 — 창 문서도 disposition "process" 라 그대로 태워진다
  ok("⑤ 배선 — docStateSkip 호출부 무변",
    A.includes('docStateSkip(c.disposition === "process", recheck, docState, c.number, listLmOf(c.row))'));
}

// ── ⑥ 날짜를 못 얻으면 종전 동작 + 경고 ──
{
  const warnings = [];
  const r = runFloorA(
    [{ DocNo: "ST-01283", Status: "COMPLETED" }],   // EffectiveDate 없음
    FLOOR, "adjustment", numberOf, warnings);
  ok("⑥ 날짜 불명 → 후보 제외(종전) + no_date 집계", r.cands.length === 0 && r.skipBeforeFloor === 1 && r.recheckWindowNoDate === 1);
  ok("⑥ 경고 1회 집계(행 홍수 없음)", warnings.some((w) => String(w).includes("no usable list date")));
  // 모르는 축 → null (종전 동작)
  ok("⑥ 모르는 축은 null(종전)", recheckListDate("sale", { EffectiveDate: day(1) }) === null);
}

// ── ⑦ ②-b 무접촉(회귀) ──
ok("⑦ ②-b 에 창 코드 없음", !B.includes("recheckWindow") && !B.includes("RECHECK_WINDOW") && !B.includes("recheck_window"));

// ── ⑧ 배선 — 창 판정이 skip_since 앞 + 가드 ──
{
  const judgeIdx = A.indexOf("recheckWindowJudge(");
  const sinceIdx = A.indexOf('"skip_since"');
  ok("⑧ 창 판정이 skip_since 분기 앞", judgeIdx > 0 && sinceIdx > judgeIdx, `judge@${judgeIdx} since@${sinceIdx}`);
  const guards = (A.match(/&& !c\.recheckWindow\) \{ c\.disposition = "skip_since"/g) || []).length;
  ok("⑧ skip_since 두 분기(transfer·adjustment)에 !recheckWindow 가드", guards === 2, "found " + guards);
  // 동적 — 창으로 남긴 문서는 eff <= since 여도 skip_since 로 안 떨어진다
  const cands = [
    { number: "ST-01283", num: 1283, disposition: "", recheckWindow: true, row: { Status: "COMPLETED", EffectiveDate: day(2) } },
    { number: "ST-01290", num: 1290, disposition: "", row: { Status: "COMPLETED", EffectiveDate: day(2) } },
  ];
  runDispoA(cands, "adjustment", day(0));   // since = 오늘 → eff(2일 전) <= since
  ok("⑧ 동적 — 창 문서는 process 유지", cands[0].disposition === "process", "got " + cands[0].disposition);
  ok("⑧ 동적 — 비창 문서는 종전대로 skip_since(회귀)", cands[1].disposition === "skip_since", "got " + cands[1].disposition);
}

// ── 순수 판정·날짜 추출 단위 ──
ok("(판정) 창 안 → keep", recheckWindowJudge(day(3), day(7)) === "keep");
ok("(판정) 창 밖 → skip", recheckWindowJudge(day(9), day(7)) === "skip");
ok("(판정) 날짜 없음 → no_date", recheckWindowJudge(null, day(7)) === "no_date");
ok("(날짜) transfer = Departure/Completion 중 늦은 것",
  recheckListDate("transfer", { DepartureDate: day(5), CompletionDate: day(1) }) === day(1)
  && recheckListDate("transfer", { DepartureDate: day(1) }) === day(1));
ok("(날짜) assembly = Date → Completion → WIP 폴백",
  recheckListDate("assembly", { Date: day(2) }) === day(2)
  && recheckListDate("assembly", { CompletionDate: day(3) }) === day(3)
  && recheckListDate("assembly", { WIPDate: day(4) }) === day(4));

// ── 응답 배선 + 버전 ──
ok("(응답) recheck_window 필드 배선",
  A.includes("recheck_window: recheckWindowKept") && A.includes("recheck_window_days: RECHECK_WINDOW_DAYS")
  && A.includes("recheck_window_sample: recheckWindowSample"));
// 09-02.1(재조회 창) 이상이면 통과 — 뒤 배포(09-03.1 unkeyed 등)가 버전을 올려도 이 테스트가 깨지지 않게 하한으로 본다
ok("(버전) COLLECTOR_VERSION ≥ 09-02.1", (src.match(/const COLLECTOR_VERSION = "inv-collect@([^"]+)";/)?.[1] ?? "") >= "2026-09-02.1");

console.log(fails === 0 ? "ALL RECHECK-WINDOW TESTS PASSED" : fails + " TEST(S) FAILED");
process.exit(fails === 0 ? 0 : 1);
