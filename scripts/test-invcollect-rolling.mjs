// 롤링 재확인 테스트 (2026-08-31 — last_modified 를 믿게 된 대가의 상시 검산)
//
// 실행:  node scripts/test-invcollect-rolling.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL ROLLING-RECHECK TESTS PASSED".
//
// 방식은 기존 스위트와 동일 — (a) 순수 함수(pickRollingRecheck·docStateSkip)와 **②-a 선정
// 블록 원문**을 추출·실행하고, (b) 루프 분기(재조회 ↔ skip)는 시뮬레이터 + 정적 grep 으로
// 배선을 못박는다.
//
// 검증 ①~⑧ (지시서 §4):
//  ① skip 예정 10건 · N=5 → seen_at 가장 오래된 5건이 재조회 대상
//  ② 재조회된 문서는 skipped_unchanged 에 세지 않는다
//  ③ ⭐ 회전 — 재조회분의 seen_at 이 갱신되면 다음 회차에 다음 5건이 뽑힌다
//  ④ skip 대상이 N 보다 적으면 전부 재조회(에러 없이)
//  ⑤ 기록 없는 문서(seen_at 없음)는 skip 대상이 아니므로 선정에 안 들어간다
//  ⑥ ⭐ 선정 로직이 throw 해도 수집이 계속된다 — 롤링만 꺼지고 평소 skip 으로 동작
//  ⑦ doc_state_oldest_seen 이 후보 중 최솟값을 보고한다
//  ⑧ ⚠️ 비종결 문서는 원래 skip 대상이 아니므로 롤링 선정과 무관(회귀)

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

// 영역 분리 (②-a / ②-b)
const aStart = src.indexOf("async function runSource(");
const bStart = src.indexOf("async function runDateSource(");
const bEnd = src.indexOf("for (const key of runKeys)");
const A = src.slice(aStart, bStart);
const B = src.slice(bStart, bEnd);

// ②-a 선정 블록 원문 추출 — 마커부터 「// 3) 상세」 직전까지
const selMarker = "// ── 롤링 재확인 대상 선정 (2026-08-31";
const selA = A.slice(A.indexOf(selMarker), A.indexOf("// 3) 상세 조회"));
ok("(추출) selection blocks exist in both loops", A.includes(selMarker) && B.includes(selMarker));

const constLine = src.match(/const ROLLING_RECHECK_PER_RUN = \d+;/)[0];
const dir = mkdtempSync(join(tmpdir(), "rolling-"));
writeFileSync(join(dir, "rolling.ts"),
  constLine + "\n" + extract("docStateSkip") + "\n" + extract("pickRollingRecheck") +
  "\nexport function runSelectionA(docState: any, recheck: any, cands: any, warnings: any, listLmOf: any) {\n" +
  selA +
  "\nreturn { rollingSet, rollingOldestSeen, rollingRechecked, rollingSample };\n}\nexport { docStateSkip, pickRollingRecheck };\n");
execSync(`npx --yes esbuild ${join(dir, "rolling.ts")} --outfile=${join(dir, "rolling.mjs")} --format=esm`, { stdio: "pipe" });
const { docStateSkip, pickRollingRecheck, runSelectionA } = await import(join(dir, "rolling.mjs"));

const N = Number(constLine.match(/\d+/)[0]);
ok("(상수) ROLLING_RECHECK_PER_RUN = 5", N === 5, "found " + N);

const seen = (h) => "2026-08-31T" + String(h).padStart(2, "0") + ":00:00+00:00";
const listLmOf = (row) => String(row?.LastModifiedOn ?? "").trim() || null;
// 후보: TR-01 이 가장 오래 안 봤고 TR-10 이 가장 최근
const mkWorld = (n = 10) => {
  const state = new Map();
  const cands = [];
  for (let i = 1; i <= n; i++) {
    const num = "TR-" + String(i).padStart(2, "0");
    state.set(num, { lastModified: "2026-08-2" + (i % 10) + "T00:00:00Z", seenAt: seen(i) });
    cands.push({ number: num, disposition: "process", row: { LastModifiedOn: state.get(num).lastModified } });
  }
  return { state, cands };
};

// ① skip 예정 10건 · N=5 → seen_at 최고령 5건 (②-a 선정 블록 원문으로)
{
  const { state, cands } = mkWorld(10);
  const r = runSelectionA(state, false, cands, [], listLmOf);
  ok("① oldest 5 of 10 selected",
    r.rollingSet.size === 5 && ["TR-01", "TR-02", "TR-03", "TR-04", "TR-05"].every((x) => r.rollingSet.has(x)),
    [...r.rollingSet].join(","));
  // ⑦ oldest_seen = 최솟값
  ok("⑦ doc_state_oldest_seen = min(seen_at)", r.rollingOldestSeen === seen(1), r.rollingOldestSeen);
}

// ③ ⭐ 회전 — 재조회분의 seen_at 갱신 → 다음 회차엔 다음 5건
{
  const { state, cands } = mkWorld(10);
  const r1 = runSelectionA(state, false, cands, [], listLmOf);
  for (const num of r1.rollingSet) state.set(num, { ...state.get(num), seenAt: seen(20) });   // 처리됨 = seen_at 갱신
  const r2 = runSelectionA(state, false, cands, [], listLmOf);
  ok("③ rotation: next round picks the next 5",
    ["TR-06", "TR-07", "TR-08", "TR-09", "TR-10"].every((x) => r2.rollingSet.has(x))
    && r2.rollingOldestSeen === seen(6), [...r2.rollingSet].join(","));
}

// ④ skip 대상 < N → 전부 재조회 · 에러 없음
{
  const { state, cands } = mkWorld(3);
  const r = runSelectionA(state, false, cands, [], listLmOf);
  ok("④ fewer than N → all selected, no error", r.rollingSet.size === 3);
  const empty = pickRollingRecheck([], 5);
  ok("④b empty eligible → empty set, null oldest", empty.set.size === 0 && empty.oldestSeen === null);
}

// ⑤ 기록 없는 문서 — skip 대상이 아니므로 선정에 안 들어간다
{
  const { state, cands } = mkWorld(4);
  cands.push({ number: "TR-NEW", disposition: "process", row: { LastModifiedOn: "2026-08-30T00:00:00Z" } });   // state 에 없음
  const r = runSelectionA(state, false, cands, [], listLmOf);
  ok("⑤ unrecorded doc never selected (it is fetched anyway)", !r.rollingSet.has("TR-NEW") && r.rollingSet.size === 4);
}

// ⑧ 비종결 — 최고령이어도 선정과 무관 (원래 skip 대상이 아니다)
{
  const { state, cands } = mkWorld(6);
  state.set("TR-IT", { lastModified: "2026-08-20T00:00:00Z", seenAt: seen(0) });   // 가장 오래됨
  cands.push({ number: "TR-IT", disposition: "process_nonterminal", row: { LastModifiedOn: "2026-08-20T00:00:00Z" } });
  const r = runSelectionA(state, false, cands, [], listLmOf);
  ok("⑧ nonterminal (oldest seen_at) never selected — always fetched anyway",
    !r.rollingSet.has("TR-IT") && r.rollingSet.has("TR-01") && r.rollingOldestSeen === seen(1));
}

// ⑥ ⭐ 선정 throw → 예외 무전파 · 롤링만 OFF · 경고
{
  const poisoned = { get() { throw new Error("boom"); }, size: 1 };   // docStateSkip 의 state.get 이 throw
  const warnings = [];
  let threw = false;
  let r = null;
  try {
    r = runSelectionA(poisoned, false, [{ number: "TR-01", disposition: "process", row: { LastModifiedOn: "x" } }], warnings, listLmOf);
  } catch { threw = true; }
  ok("⑥ selection throw → no propagation, rolling disabled, warning",
    !threw && r.rollingSet.size === 0
    && warnings.length === 1 && warnings[0].includes("rolling-recheck selection failed"));
}
// recheck 회차 → 선정 안 함 (전량 조회라 무의미)
{
  const { state, cands } = mkWorld(10);
  const r = runSelectionA(state, true, cands, [], listLmOf);
  ok("(보강) recheck round selects nothing (everything fetched anyway)", r.rollingSet.size === 0);
}

// ── ② + 정적 배선 — 재조회는 skipped_unchanged 로 세지 않는다 ──
// ②-a: skip-true 분기 안에서 rollingSet.has → rechecked++(계속 진행) / else → skip_unchanged
{
  const skipAt = A.indexOf('if (docStateSkip(c.disposition === "process"');
  const branch = A.slice(skipAt, A.indexOf("if (detailFetched >= MAX_DETAIL_PER_SOURCE)", skipAt));
  ok("② ②-a rolling branch fetches (no skip count), else-branch skips",
    branch.includes("if (rollingSet.has(c.number)) {")
    && branch.includes("rollingRechecked++")
    && branch.indexOf("skippedUnchanged++") > branch.indexOf("} else {")
    && branch.includes('c.disposition = "skip_unchanged"'));
}
// ②-b 동형
{
  const skipAt = B.indexOf("if (docStateSkip(true, recheck, docState, docIdent, cd.updated))");
  ok("② ②-b same wiring (docIdent)", skipAt > -1);
  const branch = B.slice(skipAt, B.indexOf("if (detailFetched >= MAX_DETAIL_PER_SOURCE)", skipAt));
  ok("②b ②-b rolling branch fetches, else-branch skips + advances cursor key",
    branch.includes("if (rollingSet.has(docIdent)) {")
    && branch.includes("rollingRechecked++")
    && branch.indexOf("skippedUnchanged++") > branch.indexOf("} else {")
    && branch.includes("lastProcessedKey = cd.key"));
}
// 응답 필드 3종 × 두 러너
for (const [tag, region] of [["②-a", A], ["②-b", B]]) {
  ok(`(응답) ${tag} exposes rolling_rechecked / sample / doc_state_oldest_seen`,
    region.includes("rolling_rechecked: rollingRechecked")
    && region.includes("rolling_recheck_sample: rollingSample")
    && region.includes("doc_state_oldest_seen: rollingOldestSeen ?? undefined"));
}
// ②-a 선정이 종결만 대상으로 한다 (⑧ 정적 절반)
ok("⑧b ②-a eligibility guard: disposition !== \"process\" excluded",
  selA.includes('if (c.disposition !== "process") continue;'));
// ②-b 한계 주석 · recheck cron 판단 주석
ok("(주석) ②-b recent-window limitation documented", B.includes("②-b 는 최근 창만 검산"));
ok("(주석) recheck stays manual, no cron", src.includes("cron 으로 돌리지 않는다(2026-08-31 결정"));
// loadDocState 가 seen_at 을 읽는다
ok("(배선) loadDocState selects seen_at", src.includes("select=doc_number,last_modified,seen_at"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL ROLLING-RECHECK TESTS PASSED");
