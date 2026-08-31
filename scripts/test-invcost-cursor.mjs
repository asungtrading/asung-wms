// inv-cost 커서 tie-breaker 테스트 (2026-08-31 · 결함 C 방어 이식 + 회차 로그)
//
// 실행:  node scripts/test-invcost-cursor.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL INV-COST CURSOR TESTS PASSED".
//
// 방식은 test-invcollect-cursor.mjs · test-invcollect-runlog.mjs 와 동일 —
//  (a) 순수 함수(cursorDocIdent/cursorKeyOf/cursorKeyCompare/countUpdatedTies/decideCursor)를
//      **inv-cost 원본에서** 추출·실행하고(⚠️ inv-collect 의 복제본이므로 이쪽을 검증해야 한다),
//  (b) 회차 로그 호출부 블록을 원문 그대로 잘라 목과 함께 실행하며(⑨ dry 미기록 · ⑩ throw 무전파),
//  (c) 정적 grep 으로 루프 배선(정렬·필터·커서 저장·가드·commit 차단)을 못박는다.
//
// 검증 ①~⑩ (지시서 §5) — 타임스탬프는 발주 실물 형식(⚠️ Z 접미 없음)으로 돌린다:
//  ① 동률 없음 — 종전과 동일 동작(회귀)
//  ② ⭐ 동률 5건 · 캡 2 → 회차마다 커서 전진 · 동결 없음 (순전진은 캡−1 — < 필터의 경계 재조회)
//  ③ ⭐ 하위 호환 — 맨 커서일 때 동률 문서가 걸러지지 않고 재처리(안전 방향)
//  ④ Updated 없는 문서 → 맨 앞 처리 · 거르지 않음
//  ⑤ 비캡 회차 → 커서 = runStartIso
//  ⑥ ⭐ cursorStalled → 경고 + commit 차단 (정적 배선 포함)
//  ⑦ updated_ties 카운트
//  ⑧ 정렬이 코드유닛 비교(localeCompare 미사용 — 정적)
//  ⑨ 회차 로그: dry 는 쓰지 않는다
//  ⑩ 회차 로그 쓰기가 throw 해도 원가 수집이 계속된다

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SRC = "supabase/functions/inv-cost/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

// ── 원문 추출: function <name> … 균형 중괄호 ──
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
// 회차 로그 호출부 블록 — 마커 주석부터 return json(out); 직전까지
const rlMarker = "// 회차 로그 (2026-08-31 · inv_collect_runs source_key='cost'";
const rlAt = src.indexOf(rlMarker);
const rlEnd = src.indexOf("return json(out);", rlAt);
const rlBlock = src.slice(rlAt, rlEnd);

const versionLine = src.match(/const COLLECTOR_VERSION = "[^"]+"/)[0] + ";";
const FNS = ["cursorDocIdent", "cursorKeyOf", "cursorKeyCompare", "countUpdatedTies", "decideCursor", "buildCostRun"];
const dir = mkdtempSync(join(tmpdir(), "invcost-cursor-"));
writeFileSync(join(dir, "cursor.ts"),
  versionLine + "\n" + FNS.map(extract).join("\n") +
  "\nexport async function runLogBlock(commit: any, writeCollectRun: any, buildCostRunFn: any, out: any, warnings: any, t0: any) {\n" +
  rlBlock.replace(/buildCostRun\(/g, "buildCostRunFn(") +
  "\nreturn out;\n}\nexport { " + FNS.join(", ") + " };\n");
execSync(`npx --yes esbuild ${join(dir, "cursor.ts")} --outfile=${join(dir, "cursor.mjs")} --format=esm`, { stdio: "pipe" });
const { cursorDocIdent, cursorKeyOf, cursorKeyCompare, countUpdatedTies, decideCursor, buildCostRun, runLogBlock } =
  await import(join(dir, "cursor.mjs"));

// ── 회차 시뮬레이터 — inv-cost 의 후보→정렬→정밀도 필터→캡 루프→커서 결정과 같은 배선
//    (배선 동일성은 아래 정적 grep 이 못박는다) ──
function simulateRound(docs, cursorBefore, cap, runStartIso) {
  const cands = docs.map((row) => {
    const updated = String(row?.LastUpdatedDate ?? "").trim() || null;
    return { row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) };
  });
  let noUpdated = 0;
  for (const cd of cands) if (!cd.updated) noUpdated++;
  cands.sort((a, b) => cursorKeyCompare(a.key, b.key));
  let precisionSkipped = 0;
  let kept = cands;
  if (cursorBefore && cursorBefore.length > 10) {
    kept = [];
    for (const cd of cands) {
      if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }
      kept.push(cd);
    }
  }
  const updatedTies = countUpdatedTies(kept);
  const processed = [];
  let lastProcessedKey = null;
  let detailCapped = false;
  for (let i = 0; i < kept.length; i++) {
    if (processed.length >= cap) { detailCapped = true; break; }
    const cd = kept[i];
    processed.push(cd);
    if (cd.key) lastProcessedKey = cd.key;
  }
  const { cursorWouldBe, cursorStalled } = decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso);
  return { processed, precisionSkipped, noUpdated, updatedTies, detailCapped, cursorWouldBe, cursorStalled };
}
const orderOf = (r) => r.processed.map((c) => c.row.OrderNumber ?? "(none)");

const T = "2026-08-28T12:59:44.05";   // ⚠️ 발주 실물 형식 — Z 접미 없음
const RUN = "2026-08-31T12:00:00.000Z";
const doc = (order, updated) => ({ OrderNumber: order, ID: order ? "guid-" + order : "", LastUpdatedDate: updated });

// ① 동률 없음 — 회귀: 오름차순 · 비캡 커서 = runStartIso · 맨 커서의 <(미만) 필터 유지
{
  const docs = [doc("PO-3", "2026-08-28T12:59:46.05"), doc("PO-1", "2026-08-28T12:59:44.05"), doc("PO-2", "2026-08-28T12:59:45.05")];
  const r = simulateRound(docs, null, 10, RUN);
  ok("①a no ties: ascending, uncapped cursor = runStartIso",
    orderOf(r).join(",") === "PO-1,PO-2,PO-3" && !r.detailCapped && r.cursorWouldBe === RUN
    && r.updatedTies === 0 && !r.cursorStalled, JSON.stringify(orderOf(r)));
  const r2 = simulateRound(docs, "2026-08-28T12:59:45.05", 10, RUN);
  ok("①b bare cursor filters strictly-before only (regression)",
    orderOf(r2).join(",") === "PO-2,PO-3" && r2.precisionSkipped === 1, JSON.stringify(orderOf(r2)));
}

// ② ⭐ 동률 5건 · 캡 2 — 매 캡 회차 커서 전진 · 전량 처리 · 동결 없음 (결함 C 본체)
{
  const five = [1, 2, 3, 4, 5].map((n) => doc("PO-0" + n, T));
  let cursor = null;
  const seen = new Set();
  let rounds = 0, frozen = false;
  for (; rounds < 10; rounds++) {
    const r = simulateRound(five, cursor, 2, RUN);
    for (const o of orderOf(r)) seen.add(o);
    if (r.detailCapped && cursor != null && !(r.cursorWouldBe > cursor)) { frozen = true; break; }
    ok("② round " + (rounds + 1) + " not stalled", !r.cursorStalled);
    cursor = r.cursorWouldBe;
    if (!r.detailCapped) break;
  }
  ok("② ties(5) cap(2): cursor advances every round, all processed, no freeze",
    !frozen && seen.size === 5 && cursor === RUN && rounds === 3,   // 순전진 = 캡−1 → 4회차에 비캡 종료
    "frozen=" + frozen + " seen=" + seen.size + " rounds=" + (rounds + 1) + " cursor=" + cursor);
}

// ③ ⭐ 하위 호환 — 맨 커서(구형)일 때 같은 시각의 동률 문서가 걸러지지 않는다(재처리 = 안전)
{
  const docs = [doc("PO-A", T), doc("PO-B", T), doc("PO-old", "2026-08-28T12:59:44.04")];
  const r = simulateRound(docs, T, 10, RUN);
  ok("③ bare cursor: tie docs at that instant KEPT (safe), earlier skipped",
    orderOf(r).join(",") === "PO-A,PO-B" && r.precisionSkipped === 1, JSON.stringify(orderOf(r)));
}

// ④ Updated 없는 문서 — key=null: 맨 앞 처리 · 카운트 · 키 커서에도 필터 미적용
{
  const docs = [doc("PO-C", T), doc("PO-noupd", null)];
  const r = simulateRound(docs, T + "|PO-A", 10, RUN);
  ok("④ no-Updated doc first, counted, never precision-filtered",
    orderOf(r)[0] === "PO-noupd" && r.noUpdated === 1 && r.precisionSkipped === 0, JSON.stringify(orderOf(r)));
}

// ⑤ 비캡 회차 — 커서 = runStartIso
{
  const r = simulateRound([doc("PO-D", T)], T + "|PO-A", 10, RUN);
  ok("⑤ uncapped round cursor = runStartIso", !r.detailCapped && r.cursorWouldBe === RUN);
  ok("⑤b runStartIso > any earlier no-Z key", RUN > T + "|PO-ZZZZZ");
}

// ⑥ ⭐ 가드 — 커서가 안 나가면 stalled
{
  ok("⑥a capped, key == cursorBefore → stalled", decideCursor(true, T + "|PO-A", T + "|PO-A", RUN).cursorStalled === true);
  ok("⑥b capped, no key processed → stalled (B 도 증상으로 잡힌다)", decideCursor(true, null, T + "|PO-A", RUN).cursorStalled === true);
  ok("⑥c capped, key advances → not stalled", decideCursor(true, T + "|PO-B", T + "|PO-A", RUN).cursorStalled === false);
  ok("⑥d uncapped → not stalled", decideCursor(false, null, T + "|PO-A", RUN).cursorStalled === false);
}

// ⑦ updated_ties
{
  ok("⑦a 3 tied + 1 distinct + 1 null → 3",
    countUpdatedTies([{ updated: T }, { updated: T }, { updated: T }, { updated: "2026-08-29T00:00:00.05" }, { updated: null }]) === 3);
  ok("⑦b all distinct → 0", countUpdatedTies([{ updated: "a" }, { updated: "b" }]) === 0);
}

// ⑨ 회차 로그 — dry(=commit 아님) → 호출 0 · logged=false
{
  let calls = 0;
  const out = {};
  await runLogBlock(false, async () => { calls++; }, (o, w, d) => ({ o }), out, [], Date.now());
  ok("⑨ dry writes no run log (0 calls, logged=false)", calls === 0 && out.collect_run_logged === false);
}
// commit 정상 경로 — 실물 buildCostRun 으로 1회 기록
{
  let calls = 0, got = null;
  const out = { detail_capped: true, detail_capped_reason: "max_detail", detail_capped_remaining: 7,
    cursor_before: T + "|PO-A", cursor_after: T + "|PO-B", cursor_stalled_alert: undefined,
    list_total: 250, candidates: 47, precision_skipped: 3, docs_processed: 40, detail_fetched: 40,
    dispositions: { processed: 40, skip_service: 5 }, samples: [{ sku: "X" }], warnings: ["w"] };
  await runLogBlock(true, async (row) => { calls++; got = row; }, buildCostRun, out, ["w"], Date.now());
  ok("⑨b commit logs once — source_key=cost, mapping from response",
    calls === 1 && out.collect_run_logged === true && got.source_key === "cost"
    && got.detail_capped === true && got.detail_capped_remaining === 7 && got.hold_capped === null
    && got.cursor_before === T + "|PO-A" && got.cursor_after === T + "|PO-B"
    && got.candidates === 47 && got.precision_skipped === 3 && got.ledger_rows === null
    && got.ok === true && !("samples" in got.summary), JSON.stringify(got).slice(0, 200));
  const blocked = buildCostRun({ write_skipped: "list truncated" }, [], 1);
  ok("⑨c write_skipped → ok=false", blocked.ok === false && blocked.write_skipped === "list truncated");
  const manyWarn = Array.from({ length: 80 }, (_, i) => "w" + i);
  const capped = buildCostRun({ warnings: manyWarn }, manyWarn, 1);
  ok("⑨d warnings truncated to 50 (column + summary copy)",
    capped.warnings.length === 50 && capped.summary.warnings.length === 50);
}
// ⑩ 로그 쓰기 throw → 예외 무전파 · collect_run_error · 경고 push
{
  const out = {};
  const warnings = [];
  let threw = false;
  try {
    await runLogBlock(true, async () => { throw new Error("insert failed 500"); }, (o) => ({ o }), out, warnings, Date.now());
  } catch { threw = true; }
  ok("⑩ log failure does not propagate — collect_run_error only, cost run continues",
    !threw && out.collect_run_logged === false
    && String(out.collect_run_error).includes("insert failed 500")
    && warnings.length === 1 && warnings[0].includes("cost collection unaffected"));
}

// ── 정적 배선 검사 — 시뮬레이터와 실물이 같은 함수·같은 식을 쓰는지 못박는다 ──
ok("⑧a sort uses cursorKeyCompare on keys", src.includes("cands.sort((a, b) => cursorKeyCompare(a.key, b.key))"));
ok("⑧b no localeCompare CALL remains (comments warning against it are fine)", !src.includes(".localeCompare("));
ok("⑧c precision filter compares cd.key (old cd.updated form gone)",
  src.includes("if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }")
  && !src.includes("cd.updated && cd.updated < cursorBefore"));
ok("⑧d cursor saves last processed KEY", src.includes("if (cd.key) lastProcessedKey = cd.key;") && !src.includes("lastProcessedUpdated"));
ok("⑧e key built from list row OrderNumber/ID", src.includes("cursorKeyOf(updated, cursorDocIdent(row))"));
ok("⑧f decideCursor wired with loop state", src.includes("decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso)"));
ok("⑥e stalled guard: warning + commit block + response alert",
  src.includes("CURSOR STALLED - capped and cursor would not advance")
  && src.includes("else if (cursorStalled) writeSkipped =")
  && src.includes("cursor_stalled_alert: cursorStalled"));
ok("⑥f defect-B guard kept as-is (more specific diagnosis)",
  src.includes("cappedNoUpdated = detailCapped && lastProcessedKey == null")
  && src.includes('else if (cappedNoUpdated) writeSkipped = "capped with no usable LastUpdatedDate'));
ok("(보강) updated_ties exposed in response", src.includes("updated_ties: updatedTies"));
ok("(보강) run-log insert plain POST to inv_collect_runs",
  extract("writeCollectRun").includes('"/rest/v1/inv_collect_runs"') && !extract("writeCollectRun").includes("on_conflict")
  && (src.match(/await writeCollectRun\(/g) ?? []).length === 1);
ok("(보강) updated_since_requested still cursor-date based (first 10 chars — '|' 무영향)",
  src.includes("dateOnly(sinceUsed) ?? sinceUsed.slice(0, 10)"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL INV-COST CURSOR TESTS PASSED");
