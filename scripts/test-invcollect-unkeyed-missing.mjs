// 소멸 감지 사각지대 1단계 테스트 (2026-09-03 — 「판정은 하되 표에 넣지 않는다」)
//
// 실행:  node scripts/test-invcollect-unkeyed-missing.mjs
// 전부 통과하면 마지막 줄이 "ALL UNKEYED-MISSING TESTS PASSED".
//
// 배경: adjustment·assembly 목록엔 LastModifiedOn 이 없다(stockAdjustmentList · finishedGoodsList
// 실측). 종전 G4 는 그 문서를 판정에서 통째로 뺐다 — [실측 2026-09-02] skipped_no_lmo 33 =
// detail_fetched 33, 두 축의 라인 삭제·교체(ST-01283 편집 · FG-00133 취소)를 아무도 못 봤다.
// last_modified_on 은 inv_missing_lines 유니크 키의 일부라 값 없이 표에 넣으면 매 회차 같은 행이
// 새로 쌓여 회차 캡 500 을 소진한다(08-31 모양) ⇒ 1단계는 **판정만 하고 표에는 안 넣는다**(unkeyed).
//
// 방식은 scripts/test-invcollect-missing.mjs 와 동일 — 원문 추출 + esbuild + fetch 목.
//
// 검증 7:
//  ① lmo 없는 문서의 B−A 는 unkeyed 로 집계되고 rows(표 쓰기 대상)에서 빠진다 · sample 은 6키 모양
//  ② lmo 있는 문서는 종전대로 rows·detected 에 들어간다(회귀)
//  ③ 「bin 변경」 예외가 unkeyed 축에도 **먼저** 적용된다(동적 + 정적 순서)
//  ④ 200행 상한 — 넘으면 sample 은 잘리고 truncated true, 수(unkeyed)는 전량
//  ⑤ 회차 중단(detailCapped)이면 unkeyed 도 판정하지 않는다 — G3 유지(정적 배선)
//  ⑥ missing_lines_detected 는 표에 넣은 것만 — unkeyed 를 포함하지 않는다(혼합 문서 집합)
//  ⑦ 배선 — inv_missing_lines insert 대상(missing.rows)에서 unkeyed 문서가 제외된다 · 응답 필드 4개 배선

import { readFileSync } from "node:fs";

const SRC = "supabase/functions/inv-collect/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

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
  constLine("MISSING_UNKEYED_SAMPLE_MAX"),
  constLine("MISSING_UNKEYED_DOCS_MAX"),
  constLine("ledgerKeyOf"),
  "type BinChangedPartition = { kept: any[]; binChanged: number };",
  extractBlock("function partitionBinChanged", "async function detectMissingLines"),
  extractBlock("async function detectMissingLines", "// 쓰기는 commit"),
  "export { detectMissingLines, ledgerKeyOf, MISSING_UNKEYED_SAMPLE_MAX };",
].join("\n");
const { mkdtempSync, writeFileSync } = await import("node:fs");
const { execSync } = await import("node:child_process");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const dir = mkdtempSync(join(tmpdir(), "unkeyed-"));
writeFileSync(join(dir, "m.ts"), code);
execSync(`npx --yes esbuild ${join(dir, "m.ts")} --outfile=${join(dir, "m.mjs")} --format=esm`, { stdio: "pipe" });
const { detectMissingLines, MISSING_UNKEYED_SAMPLE_MAX } = await import(join(dir, "m.mjs"));

// ── fetch 목: inv_ledger GET 만 (표 쓰기는 이 테스트에서 일어나면 안 된다 → throw) ──
let ledgerDb = [];
globalThis.fetch = async (url, opts = {}) => {
  if (String(url).includes("/inv_ledger?")) {
    const range = (opts.headers?.Range ?? "0-999").split("-").map(Number);
    const u = new URL(url);
    const dt = decodeURIComponent((u.searchParams.get("doc_type") ?? "").replace("eq.", ""));
    const dn = decodeURIComponent((u.searchParams.get("doc_number") ?? "").replace("eq.", ""));
    let rows = ledgerDb.filter((r) => r.doc_type === dt && r.doc_number === dn && r.source === "cin7");
    return { ok: true, json: async () => rows.slice(range[0], range[1] + 1) };
  }
  throw new Error("unexpected fetch (unkeyed must never write): " + url);
};

// ST-01283 모양 — 조정 문서 · 완제품 3행이 재료 12행으로 통째로 교체됨(옛 3행 = B−A)
const mkRow = (dn, sku, i, extra = {}) => ({
  doc_type: "adjustment", doc_number: dn, line_ref: "p" + i, event_type: "adjustment",
  warehouse: "Asung - Edmonton", bin: "EU050402", sku, qty_delta: 2, occurred_on: "2026-08-31",
  id: 5000 + i, source: "cin7", ...extra,
});
const keyOfRow = (r) => [r.doc_type, r.doc_number, r.line_ref, r.event_type, r.warehouse, r.bin, r.sku].join("\u0001");

// ① lmo 없는 문서 — B−A 3행이 unkeyed 로, rows 에는 0
{
  ledgerDb = []; const keys = new Set();
  for (let i = 0; i < 3; i++) ledgerDb.push(mkRow("ST-01283", "UNF1825" + (9 + i), i));       // 옛 완제품 3행(B)
  for (let i = 10; i < 22; i++) keys.add(keyOfRow(mkRow("ST-01283", "MAT" + i, i)));         // 새 재료 12행(A)
  const w = [];
  const res = await detectMissingLines("adjustment", [{ docNumber: "ST-01283", lmo: null, docStatus: "COMPLETED", keys }], w);
  const s0 = res.unkeyedSample[0] ?? {};
  ok("① lmo 없음 → unkeyed 3 · rows 0 · detected 0 · docs [ST-01283] · sample 6키",
    res.unkeyed === 3 && res.rows.length === 0 && res.detected === 0 && !res.capped
      && res.unkeyedDocs.length === 1 && res.unkeyedDocs[0] === "ST-01283"
      && res.unkeyedSample.length === 3 && !res.unkeyedTruncated
      && Object.keys(s0).sort().join(",") === "bin,doc_number,event_type,line_ref,sku,warehouse"
      && s0.sku === "UNF18259" && w.length === 0,
    JSON.stringify({ unkeyed: res.unkeyed, rows: res.rows.length, detected: res.detected, docs: res.unkeyedDocs, s0 }));
}
// ② 회귀 — lmo 있는 문서는 종전대로 표에 들어간다
{
  ledgerDb = []; const keys = new Set();
  for (let i = 0; i < 5; i++) { const r = mkRow("TR-04175", "AS" + i, i, { doc_type: "transfer", event_type: "transfer_out" }); ledgerDb.push(r); if (i < 3) keys.add(keyOfRow(r)); }
  const res = await detectMissingLines("transfer", [{ docNumber: "TR-04175", lmo: "2026-08-24T14:15:51.06Z", docStatus: "COMPLETED", keys }], []);
  ok("② lmo 있음 → rows 2 · detected 2 · last_modified_on 박힘 · unkeyed 0",
    res.rows.length === 2 && res.detected === 2 && res.rows[0].last_modified_on === "2026-08-24T14:15:51.06Z"
      && res.unkeyed === 0 && res.unkeyedDocs.length === 0 && res.unkeyedSample.length === 0,
    JSON.stringify({ rows: res.rows.length, unkeyed: res.unkeyed }));
}
// ③ 「bin 변경」 예외가 unkeyed 축에도 먼저 — bin 만 다른 행이 A 에 있으면 소멸이 아니다
{
  ledgerDb = []; const keys = new Set();
  const old = mkRow("ST-X", "SKU1", 1, { bin: "" });           // 옛 bin="" 행(B)
  ledgerDb.push(old);
  keys.add(keyOfRow(mkRow("ST-X", "SKU1", 1, { bin: "EU050402" })));   // 같은 6키 · bin 만 다름(A)
  ledgerDb.push(mkRow("ST-X", "GONE", 2));                             // 진짜 소멸 1행
  const res = await detectMissingLines("adjustment", [{ docNumber: "ST-X", lmo: null, docStatus: null, keys }], []);
  const binFirst = src.indexOf("const part = partitionBinChanged(missing, d.keys);") < src.indexOf("if (d.lmo === null) {");
  ok("③ bin 변경 예외 먼저 (binChanged 1 · unkeyed 1=GONE) + 정적 순서",
    res.binChanged === 1 && res.unkeyed === 1 && res.unkeyedSample[0]?.sku === "GONE" && binFirst,
    JSON.stringify({ binChanged: res.binChanged, unkeyed: res.unkeyed, binFirst }));
}
// ④ 200행 상한 — 250행 소멸: unkeyed 250(전량) · sample 200 · truncated · 표 캡(capped)은 미발동
{
  ledgerDb = []; for (let i = 0; i < 250; i++) ledgerDb.push(mkRow("ST-BIG", "AS" + i, i));
  const res = await detectMissingLines("adjustment", [{ docNumber: "ST-BIG", lmo: null, docStatus: null, keys: new Set() }], []);
  ok("④ 200행 상한 (unkeyed 250 · sample 200 · truncated · capped 아님 · 상수 200)",
    res.unkeyed === 250 && res.unkeyedSample.length === 200 && res.unkeyedTruncated && !res.capped
      && res.detected === 0 && MISSING_UNKEYED_SAMPLE_MAX === 200,
    JSON.stringify({ unkeyed: res.unkeyed, sample: res.unkeyedSample.length, truncated: res.unkeyedTruncated, capped: res.capped }));
}
// ⑤ G3 유지 — 회차 중단이면 detectMissingLines 자체를 부르지 않는다(unkeyed 도 0/[]) — 정적 배선
{
  const A = src.slice(src.indexOf("async function runSource("), src.indexOf("async function runDateSource("));
  const gate = A.indexOf('else if (detailCapped) missingCheckSkipped = "detail_capped: "');
  const call = A.indexOf("missing = await detectMissingLines(cfg.docType, missingDocs, warnings);");
  const guarded = A.lastIndexOf("if (!missingCheckSkipped) {", call) > gate && gate > -1;
  const nullSafe = A.includes("missing_lines_unkeyed: missing ? missing.unkeyed : 0,")
    && A.includes("missing_lines_unkeyed_docs: missing ? missing.unkeyedDocs : [],")
    && A.includes("missing_lines_unkeyed_sample: missing ? missing.unkeyedSample : [],")
    && A.includes("missing_lines_unkeyed_truncated: missing ? missing.unkeyedTruncated : false,");
  ok("⑤ G3 유지 — detailCapped → missingCheckSkipped → detect 미호출 · unkeyed 필드는 missing null 에 0/[]/false",
    guarded && nullSafe, JSON.stringify({ gate, call, guarded, nullSafe }));
}
// ⑥ 혼합 — detected 는 표에 넣은 것만(lmo 문서 2행) · unkeyed 는 lmo 없는 문서 3행 · 서로 안 섞인다
{
  ledgerDb = [];
  for (let i = 0; i < 2; i++) ledgerDb.push(mkRow("TR-K", "K" + i, i, { doc_type: "adjustment" }));   // lmo 있음
  for (let i = 0; i < 3; i++) ledgerDb.push(mkRow("ST-U", "U" + i, i));                             // lmo 없음
  const res = await detectMissingLines("adjustment", [
    { docNumber: "TR-K", lmo: "L", docStatus: null, keys: new Set() },
    { docNumber: "ST-U", lmo: null, docStatus: null, keys: new Set() },
  ], []);
  ok("⑥ detected 2(표) ≠ unkeyed 3(로그) — rows 는 전부 TR-K · sample 은 전부 ST-U",
    res.detected === 2 && res.rows.length === 2 && res.rows.every((r) => r.doc_number === "TR-K")
      && res.unkeyed === 3 && res.unkeyedSample.every((r) => r.doc_number === "ST-U") && res.unkeyedDocs.join() === "ST-U",
    JSON.stringify({ detected: res.detected, unkeyed: res.unkeyed }));
}
// ⑦ 배선 — 표 insert 는 missing.rows(keyed 만)로만 · ②-a 가 lmo 없어도 missingDocs 에 넣는다 · skipped_no_lmo 카운터 유지
{
  const A = src.slice(src.indexOf("async function runSource("), src.indexOf("async function runDateSource("));
  const insertOnlyRows = /insertMissingLines\(missing\.rows\)/.test(A) && !/insertMissingLines\(missing\.unkeyed/.test(src);
  const pushAlways = A.includes("if (!lmoRaw) missingSkippedNoLmo++;\n") && A.includes("lmo: lmoRaw || null,")
    && !A.includes("else missingDocs.push({");   // 종전 「else push」가 사라졌어야 한다 — 없으면 판정 자체가 안 된다
  const counterKept = A.includes("missing_lines_skipped_no_lmo: missingSkippedNoLmo,");
  const noUnkeyedInOut = !/out\.push\([\s\S]{0,400}d\.lmo === null/.test(extractBlock("async function detectMissingLines", "// 쓰기는 commit"));
  ok("⑦ 배선 — insert(missing.rows) 만 · ②-a lmo 없어도 push · skipped_no_lmo 유지 · unkeyed 는 out 에 안 감",
    insertOnlyRows && pushAlways && counterKept && noUnkeyedInOut,
    JSON.stringify({ insertOnlyRows, pushAlways, counterKept, noUnkeyedInOut }));
}

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL UNKEYED-MISSING TESTS PASSED");
