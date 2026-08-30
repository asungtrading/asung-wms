// ②-b 커서 tie-breaker 테스트 (2026-08-30 · 결함 C — Updated 동률 그룹 > 캡 = 커서 동결)
//
// 실행:  node scripts/test-invcollect-cursor.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL CURSOR TESTS PASSED".
//
// 방식은 test-invcollect-gate.mjs 와 동일 — **원본에서 순수 함수 원문 추출** 후 node 실행.
// 커서 로직은 runDateSource 루프에 흩어져 있어 함수째 추출이 어렵다 → 키 생성·정렬·필터·
// 커서 결정을 순수 함수(cursorDocIdent/cursorKeyOf/cursorKeyCompare/countUpdatedTies/
// decideCursor)로 뽑아 두었고, 여기서는 (a) 그 함수들을 추출·실행해 동작을 검증하고
// (b) 정적 grep 으로 루프 배선(정렬·필터·커서 저장·가드·응답 필드)이 그 함수를 실제로
// 쓰는지 못박는다 — 시뮬레이터가 실물과 어긋나면 (b)가 잡는다.
//
// 검증 ①~⑦ (지시서 §4) + 정적 배선:
//  ① 동률 없음 — 종전과 동일하게 동작(회귀)
//  ② 동률 5건 · 캡 2 → 매 회차 커서 전진 · 전량 처리 · 동결 없음
//     ⚠️ 커서 경계 문서(key == cursor)는 정밀도 필터의 「= 은 남긴다」 규칙(유실 방지 —
//     <= 로 바꾸지 말 것)대로 다음 회차에 재조회된다(유니크 키가 흡수) — 그래서 회차당
//     순전진은 캡−1 건이고, 지시서의 3회차 대신 4회차에 끝난다. 동결 없음이 본질.
//  ③ 하위 호환 — 맨 ISO 커서(구형)일 때 동률 문서가 걸러지지 않고 재처리(안전 방향)
//  ④ Updated 없는 문서 — 종전대로 맨 앞 처리 · no_updated_field 카운트 · 필터 미적용
//  ⑤ 비캡 회차 — 커서가 runStartIso(맨 ISO)로 감
//  ⑥ 가드 — 커서가 안 나가는 상황에서 cursorStalled true (+ 정적: alert·commit 차단 배선)
//  ⑦ updated_ties 가 동률 수를 맞게 세는지

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

// ── 원문 추출: function <name> … 균형 중괄호 (시그니처에 { 가 없도록 원본이 작성돼 있다) ──
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
const FNS = ["cursorDocIdent", "cursorKeyOf", "cursorKeyCompare", "countUpdatedTies", "decideCursor"];
const dir = mkdtempSync(join(tmpdir(), "cursor-"));
writeFileSync(join(dir, "cursor.ts"),
  FNS.map(extract).join("\n") + "\nexport { " + FNS.join(", ") + " };\n");
execSync(`npx --yes esbuild ${join(dir, "cursor.ts")} --outfile=${join(dir, "cursor.mjs")} --format=esm`, { stdio: "pipe" });
const { cursorDocIdent, cursorKeyOf, cursorKeyCompare, countUpdatedTies, decideCursor } =
  await import(join(dir, "cursor.mjs"));

// ── 회차 시뮬레이터 — runDateSource 의 후보→정렬→정밀도 필터→캡 루프→커서 결정과 같은 배선
//    (배선 동일성은 아래 정적 grep 이 못박는다) ──
function simulateRound(docs, cursorBefore, cap, runStartIso) {
  const cands = docs.map((row) => {
    const updated = String(row?.Updated ?? "").trim() || null;
    return { row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) };
  });
  let noUpdatedField = 0;
  for (const cd of cands) if (!cd.updated) noUpdatedField++;
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
  return { processed, precisionSkipped, noUpdatedField, updatedTies, detailCapped, cursorWouldBe, cursorStalled };
}
const orderOf = (r) => r.processed.map((c) => c.row.OrderNumber ?? "(none)");

const T = "2026-08-28T15:25:33.383Z";   // 실사고의 동률 시각
const RUN = "2026-08-30T12:00:00.000Z";
const doc = (order, updated) => ({ OrderNumber: order, SaleID: order ? "guid-" + order : "", Updated: updated });

// ① 동률 없음 — 회귀: 오름차순 처리 · 비캡 커서 = runStartIso · 구형 맨 커서의 <(미만) 필터 유지
{
  const docs = [doc("SO-3", "2026-08-28T15:25:35.000Z"), doc("SO-1", "2026-08-28T15:25:33.000Z"), doc("SO-2", "2026-08-28T15:25:34.000Z")];
  const r = simulateRound(docs, null, 10, RUN);
  ok("①a no ties: ascending order, uncapped cursor = runStartIso",
    orderOf(r).join(",") === "SO-1,SO-2,SO-3" && !r.detailCapped && r.cursorWouldBe === RUN
    && r.updatedTies === 0 && !r.cursorStalled, JSON.stringify(orderOf(r)));
  // 구형 맨 ISO 커서(SO-2 의 Updated) — 종전과 같은 문서 집합: 미만만 제외·같은 시각은 남긴다
  const r2 = simulateRound(docs, "2026-08-28T15:25:34.000Z", 10, RUN);
  ok("①b no ties: bare cursor filters strictly-before only (regression)",
    orderOf(r2).join(",") === "SO-2,SO-3" && r2.precisionSkipped === 1, JSON.stringify(orderOf(r2)));
}

// ② ⭐ 동률 5건 · 캡 2 — 매 캡 회차 커서 전진 · 전량 처리 · 동결 없음 (결함 C 본체)
{
  const five = [1, 2, 3, 4, 5].map((n) => doc("SO-0" + n, T));
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
    !frozen && seen.size === 5 && cursor === RUN && rounds === 3,   // 4회차(0-index 3)에 비캡 종료
    "frozen=" + frozen + " seen=" + seen.size + " rounds=" + (rounds + 1) + " cursor=" + cursor);
}

// ③ ⭐ 하위 호환 — 커서가 맨 ISO(구형)일 때 같은 시각의 동률 문서가 걸러지지 않는다(재처리 = 안전)
{
  const docs = [doc("SO-A", T), doc("SO-B", T), doc("SO-old", "2026-08-28T15:25:33.382Z")];
  const r = simulateRound(docs, T, 10, RUN);   // 응급조치 전의 맨 커서 모양
  ok("③ bare-ISO cursor: tie docs at that instant are KEPT (safe), earlier ones skipped",
    orderOf(r).join(",") === "SO-A,SO-B" && r.precisionSkipped === 1, JSON.stringify(orderOf(r)));
}

// ④ Updated 없는 문서 — key=null: 맨 앞 처리 · 카운트 · 키 커서에도 필터 미적용
{
  const docs = [doc("SO-C", T), doc("SO-noupd", null)];
  const r = simulateRound(docs, T + "|SO-A", 10, RUN);
  ok("④ no-Updated doc first, counted, never precision-filtered",
    orderOf(r)[0] === "SO-noupd" && r.noUpdatedField === 1 && r.precisionSkipped === 0, JSON.stringify(r));
}

// ⑤ 비캡 회차 — 커서 = runStartIso (맨 ISO — 모든 이전 키보다 크다)
{
  const r = simulateRound([doc("SO-D", T)], T + "|SO-A", 10, RUN);
  ok("⑤ uncapped round cursor = runStartIso", !r.detailCapped && r.cursorWouldBe === RUN);
  ok("⑤b runStartIso(bare) > any earlier key", RUN > T + "|SO-ZZZZZ");
}

// ⑥ ⭐ 가드 — 커서가 안 나가면 stalled (decideCursor 직접 + 시뮬레이션)
{
  ok("⑥a capped, key == cursorBefore → stalled", decideCursor(true, T + "|SO-A", T + "|SO-A", RUN).cursorStalled === true);
  ok("⑥b capped, no key processed → stalled (B 도 증상으로 잡힌다)", decideCursor(true, null, T + "|SO-A", RUN).cursorStalled === true);
  ok("⑥c capped, key advances → not stalled", decideCursor(true, T + "|SO-B", T + "|SO-A", RUN).cursorStalled === false);
  ok("⑥d uncapped → not stalled", decideCursor(false, null, T + "|SO-A", RUN).cursorStalled === false);
  // 인위적 동결: 식별자 없는 동률 문서만(키가 전부 "<T>|") → 커서 무전진 → stalled
  const noIdent = [{ Updated: T }, { Updated: T }, { Updated: T }];
  const r = simulateRound(noIdent, T + "|", 2, RUN);
  ok("⑥e simulated freeze (all-empty idents) raises stalled", r.detailCapped && r.cursorStalled === true, JSON.stringify(r.cursorWouldBe));
}

// ⑦ updated_ties — 동률 문서 수 (중복된 Updated 를 가진 문서의 개수)
{
  ok("⑦a 3 tied + 1 distinct + 1 no-Updated → 3",
    countUpdatedTies([{ updated: T }, { updated: T }, { updated: T }, { updated: "2026-08-29T00:00:00.000Z" }, { updated: null }]) === 3);
  ok("⑦b all distinct → 0", countUpdatedTies([{ updated: "a" }, { updated: "b" }]) === 0);
  ok("⑦c two pairs → 4", countUpdatedTies([{ updated: "a" }, { updated: "a" }, { updated: "b" }, { updated: "b" }]) === 4);
}

// ── 정적 배선 검사 — 시뮬레이터와 실물이 같은 함수·같은 식을 쓰는지 못박는다 ──
ok("⑧a sort uses cursorKeyCompare on keys", src.includes("cands.sort((a, b) => cursorKeyCompare(a.key, b.key))"));
ok("⑧b precision filter compares cd.key (old cd.updated form gone)",
  src.includes("if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }")
  && !src.includes("cd.updated && cd.updated < cursorBefore"));
ok("⑧c cursor saves last processed KEY", src.includes("if (cd.key) lastProcessedKey = cd.key;") && !src.includes("lastProcessedUpdated"));
ok("⑧d key built from list row OrderNumber/ID", src.includes("cursorKeyOf(updated, cursorDocIdent(row))"));
ok("⑧e decideCursor wired with loop state", src.includes("decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso)"));
ok("⑧f stalled guard: response alert + warning + commit block",
  src.includes("cursor_stalled_alert: cursorStalled")
  && src.includes("CURSOR STALLED - capped and cursor would not advance")
  && src.includes("else if (cursorStalled) blocked ="));
ok("⑧g updated_ties exposed in response", src.includes("updated_ties: updatedTies"));
ok("⑧h defect-B guard kept as-is (more specific diagnosis)",
  src.includes("cappedNoUpdated = detailCapped && lastProcessedKey == null") && src.includes("cursor_frozen_alert: cappedNoUpdated"));
ok("⑧i updated_since_requested still cursor-date based (first 10 chars — '|' 무영향)",
  src.includes("updated_since_requested: updatedSinceReq") && src.includes("dateOnly(sinceUsed) ?? sinceUsed.slice(0, 10)"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL CURSOR TESTS PASSED");
