// 라인 소멸 감지 테스트 (2026-08-25 · TR-04175 실사고 후속 — detectMissingLines/insertMissingLines)
//
// 실행:  node scripts/test-invcollect-missing.mjs
// 전부 통과하면 마지막 줄이 "ALL MISSING-LINE TESTS PASSED".
//
// 방식은 scripts/test-invcollect-gate.mjs 와 동일 — 원본 파일에서 함수·상수를 원문 추출해
// node 로 실행(실행 시마다 재추출이라 구현이 바뀌면 테스트가 따라온다). Supabase REST 는
// globalThis.fetch 목으로 대체 — 쿼리 파라미터(G2 source=eq.cin7 · on_conflict 키)까지 검사.
//
// 검증 7:
//  ① B−A 집합 뺄셈 — 삭제된 라인만 검출(TR-04175 모양: 195행 중 138행 소멸)
//  ② 삭제 없음(B⊆A) = 0건 · ③ B 조회가 source=eq.cin7 을 요구(G2 — manual 상쇄 행 제외)
//  ④ 문서당 캡 1500 · ⑤ 회차 캡 500 · ⑥ 1000행 Range 페이지네이션(대형 문서)
//  ⑦ insert 가 on_conflict=7키+last_modified_on & ignore-duplicates (재검출 do-nothing 의 전제)

import { readFileSync } from "node:fs";

const SRC = "supabase/functions/inv-collect/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

// ── 원문 추출: 시작~끝 마커 (⚠️ 균형 중괄호는 반환 타입 Promise<{...}> 의 {} 에서 일찍 닫힌다) ──
function extractBlock(startMarker, endMarker) {
  const start = src.indexOf(startMarker);
  if (start < 0) throw new Error("marker not found: " + startMarker);
  const end = src.indexOf(endMarker, start);
  if (end < 0) throw new Error("end marker not found: " + endMarker);
  return src.slice(start, end);
}
const constLine = (name) => {
  const m = src.match(new RegExp("^const " + name + " = .*$", "m"));
  if (!m) throw new Error("const not found: " + name);
  return m[0];
};
const code = [
  'const SB_URL = () => "http://mock";',
  "const sbHeaders = (extra: Record<string, string> = {}): HeadersInit => ({ ...extra });",
  'const COLLECTOR_VERSION = "test";',
  "const INSERT_BATCH = 500;",
  "type MissingDocCheck = { docNumber: string; lmo: string | null; docStatus: string | null; keys: Set<string> };",
  constLine("LEDGER_CONFLICT"),
  constLine("MISSING_MAX_PER_DOC"),
  constLine("MISSING_MAX_PER_RUN"),
  constLine("MISSING_CONFLICT"),
  constLine("MISSING_UNKEYED_SAMPLE_MAX"),   // 2026-09-03 사각지대 1단계 — detectMissingLines 가 참조
  constLine("MISSING_UNKEYED_DOCS_MAX"),
  constLine("ledgerKeyOf"),
  // 「bin 변경」 예외 (2026-08-31) — detectMissingLines 가 호출한다. 동작 검증은
  // test-invcollect-transferbin.mjs ⑪~⑬ · 여기서는 링크만 채운다.
  "type BinChangedPartition = { kept: any[]; binChanged: number };",
  extractBlock("function partitionBinChanged", "async function detectMissingLines"),
  extractBlock("async function detectMissingLines", "// 쓰기는 commit"),
  extractBlock("async function insertMissingLines", "async function sbUpsert"),
  "export { detectMissingLines, insertMissingLines, ledgerKeyOf };",
].join("\n");
// 타입 제거는 esbuild (게이트 테스트와 동일 — 정규식 타입 스트리핑은 여러 줄 반환 타입에서 깨진다)
const { mkdtempSync, writeFileSync } = await import("node:fs");
const { execSync } = await import("node:child_process");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const dir = mkdtempSync(join(tmpdir(), "missing-"));
writeFileSync(join(dir, "m.ts"), code);
execSync(`npx --yes esbuild ${join(dir, "m.ts")} --outfile=${join(dir, "m.mjs")} --format=esm`, { stdio: "pipe" });
const { detectMissingLines, insertMissingLines } = await import(join(dir, "m.mjs"));

// ── fetch 목: inv_ledger GET 은 ledgerDb 에서, inv_missing_lines POST 는 기록 ──
let ledgerDb = [];            // {doc_type,...,qty_delta,occurred_on,id}
let getUrls = [], postCalls = [];
globalThis.fetch = async (url, opts = {}) => {
  if (String(url).includes("/inv_ledger?")) {
    getUrls.push(String(url));
    const range = (opts.headers?.Range ?? "0-999").split("-").map(Number);
    const u = new URL(url);
    const dt = decodeURIComponent((u.searchParams.get("doc_type") ?? "").replace("eq.", ""));
    const dn = decodeURIComponent((u.searchParams.get("doc_number") ?? "").replace("eq.", ""));
    const srcFilter = u.searchParams.get("source");   // "eq.cin7" 이어야 G2
    let rows = ledgerDb.filter((r) => r.doc_type === dt && r.doc_number === dn && (srcFilter !== "eq.cin7" || r.source === "cin7"));
    rows = rows.slice(range[0], range[1] + 1);
    return { ok: true, json: async () => rows };
  }
  if (String(url).includes("/inv_missing_lines?")) {
    const body = JSON.parse(opts.body);
    postCalls.push({ url: String(url), prefer: opts.headers?.Prefer ?? "", n: body.length });
    return { ok: true, json: async () => body };   // 전부 신규 삽입으로 가정
  }
  throw new Error("unexpected fetch: " + url);
};

const mkRow = (dn, sku, i, extra = {}) => ({
  doc_type: "transfer", doc_number: dn, line_ref: "p" + i, event_type: "transfer_out",
  warehouse: "Asung Trading Inc.", bin: "", sku, qty_delta: -3, occurred_on: "2026-08-21",
  id: 1000 + i, source: "cin7", ...extra,
});
const keyOfRow = (r) => [r.doc_type, r.doc_number, r.line_ref, r.event_type, r.warehouse, r.bin, r.sku].join("\u0001");

// ① TR-04175 모양 — 원장 195행, 상세는 57행만 (138 소멸)
{
  ledgerDb = []; getUrls = [];
  const keys = new Set();
  for (let i = 0; i < 195; i++) {
    const r = mkRow("TR-04175", "AS" + i, i);
    ledgerDb.push(r);
    if (i < 57) keys.add(keyOfRow(r));   // 앞 57개만 아직 문서에 있음
  }
  const w = [];
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-04175", lmo: "2026-08-24T14:15:51.06Z", docStatus: "COMPLETED", keys }], w);
  ok("① B−A 집합 뺄셈 (195−57=138 검출)", res.detected === 138 && res.rows.every((r) => Number(r.sku.slice(2)) >= 57)
    && res.rows[0].last_modified_on === "2026-08-24T14:15:51.06Z" && res.rows[0].existing_ledger_id >= 1000,
    "detected=" + res.detected);
}
// ② 삭제 없음 = 0
{
  ledgerDb = [];
  const keys = new Set();
  for (let i = 0; i < 10; i++) { const r = mkRow("TR-04174", "AS" + i, i); ledgerDb.push(r); keys.add(keyOfRow(r)); }
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-04174", lmo: "2026-08-21T18:50:55.247Z", docStatus: "COMPLETED", keys }], []);
  ok("② 삭제 없음 = 0건", res.detected === 0 && !res.capped);
}
// ③ G2 — manual 상쇄 행은 B 에서 제외 (쿼리가 source=eq.cin7 을 실어야 하고, 목이 그걸로 거른다)
{
  ledgerDb = [mkRow("TR-04175", "GONE", 1), mkRow("TR-04175", "MANUAL", 2, { source: "manual" })];
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-04175", lmo: "L", docStatus: null, keys: new Set() }], []);
  ok("③ G2 source=cin7 만 (manual 상쇄 행 미검출)", res.detected === 1 && res.rows[0].sku === "GONE"
    && getUrls.every((u) => u.includes("source=eq.cin7")));
}
// ④ 문서당 캡 200→1500 회귀 (2026-08-25 검토): TR-04175 실물 B−A=276 이 옛 캡 200 에서는
//    76건 잘렸다 — 이제 전량 검출·캡 미발동이어야 한다. ⚠️ 문서 캡(1500) > 회차 캡(500)이라
//    문서 캡 단독 발동은 구조적으로 불가(회차 캡이 항상 먼저 — 상위 방어, 사용자 확정) —
//    동적 검증 대신 상수값을 정적으로 확인한다.
{
  ledgerDb = []; for (let i = 0; i < 276; i++) ledgerDb.push(mkRow("TR-04175", "AS" + i, i));
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-04175", lmo: "L", docStatus: null, keys: new Set() }], []);
  ok("④ 문서 캡 1500 (실물 276 전량 검출·캡 미발동 + 상수 정적 확인)",
    res.detected === 276 && !res.capped && /MISSING_MAX_PER_DOC = 1500;/.test(src),
    "detected=" + res.detected);
}
// ⑤ 회차 캡 500 (문서 3개 × 200 후보)
{
  ledgerDb = [];
  const docs = [];
  for (const dn of ["TR-A", "TR-B", "TR-C"]) {
    for (let i = 0; i < 200; i++) ledgerDb.push(mkRow(dn, "AS" + i, i));
    docs.push({ docNumber: dn, lmo: "L", docStatus: null, keys: new Set() });
  }
  const w = [];
  const res = await detectMissingLines("transfer", docs, w);
  ok("⑤ 회차 캡 500", res.detected === 500 && res.capped, "detected=" + res.detected);
}
// ⑥ Range 페이지네이션 — 1,376행/문서(대형 트랜스퍼 실측 규모)를 2페이지로 전량 수신
{
  ledgerDb = []; const keys = new Set();
  for (let i = 0; i < 1376; i++) { const r = mkRow("TR-HUGE", "AS" + i, i); ledgerDb.push(r); if (i !== 700) keys.add(keyOfRow(r)); }
  getUrls = [];
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-HUGE", lmo: "L", docStatus: null, keys }], []);
  ok("⑥ Range 페이지네이션 (1,376행 · 2페이지 · 701번째만 검출)", res.detected === 1 && res.rows[0].sku === "AS700" && getUrls.length === 2);
}
// ⑦ insert — on_conflict 8키 + ignore-duplicates
{
  postCalls = [];
  const n = await insertMissingLines([{ doc_type: "t", doc_number: "d", line_ref: "l", event_type: "e", warehouse: "w", bin: "", sku: "s", last_modified_on: "L", existing_qty: 1, existing_occurred_on: "2026-08-21", existing_ledger_id: 1, doc_status: null, collector: "test" }]);
  ok("⑦ insert on_conflict+ignore-duplicates", n === 1 && postCalls.length === 1
    && postCalls[0].url.includes("on_conflict=doc_type,doc_number,line_ref,event_type,warehouse,bin,sku,last_modified_on")
    && postCalls[0].prefer.includes("resolution=ignore-duplicates"), JSON.stringify(postCalls));
}

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL MISSING-LINE TESTS PASSED");
