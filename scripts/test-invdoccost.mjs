// inv-doc-cost 계산 테스트 (2026-09-10 — buildDocCostRows/listDisposition/커서 판정)
//
// 실행:  node scripts/test-invdoccost.mjs
// 전부 통과하면 마지막 줄이 "ALL INV-DOC-COST TESTS PASSED".
//
// 방식은 scripts/test-invcost.mjs 와 동일 — 원본 파일에서 계산 핵심 구간을 원문 추출해(esbuild 로 타입 제거)
// node 로 실행한다. ⚠️ EF 자체(Deno.serve · Cin7 호출)는 여기서 돌지 않는다 — 로컬에 deno 도 Cin7 secret 도 없다.
// 픽스처는 GAS 프로브 실측(2026-09-10 · TR-03975·TR-04175)의 ManualJournals 원문 모양이다.
//
// 검증:
//  ① TR-03975 모양 — ARRAY(2) · [0] IsSystem=true(4878.11) 제외 · [1] 운송비 398.75 만 → 1행 · raw 에 배열 전체
//  ② TR-04175 모양 — ARRAY(1) · 시스템 저널 없음 · 그 1행이 운송비(배열 길이로 판단하지 않는다)
//  ③ ManualJournals 없음/빈 배열 → skip_no_journal
//  ④ IsSystem=true 만 → skip_system_only
//  ⑤ IsSystem=false 인데 Debit ≠ _59_ → skip_non_inventory_debit + 경고에 계정 코드 · 정상 행과 섞이면 processed + tally 1
//  ⑥ Reference 비었음 → skip_no_reference · 행 0 (유니크가 안 걸리므로 넣지 않는다)
//  ⑦ Amount 0 → skip_zero_amount · 음수는 넣는다(배분 가드가 차단)
//  ⑧ 같은 (ref, date) 두 줄 → 합산 1행 · mergedRows 1 · 경고
//  ⑨ listDisposition — From===To → skip_same_location · Status≠COMPLETED → skip_not_completed · GUID 없음 → skip_same_location
//  ⑩ 커서 — 키 정렬(코드유닛) · decideCursor: 비캡=회차시각 · 캡=마지막 키 · 캡인데 전진 없음=stalled
//  ⑪ 정적 — dry 기본(commit==="1") · writeDocCostRows 호출은 commit 블록 안 1곳 · on_conflict = inv_doc_cost_uq 순서 ·
//     SOURCE_KEY='cost_transfer' · 코드(주석 제외)에 inv_layer·inv_cost 참조 0 · Cin7 GET 만(cin7Get 외 cin7( 호출 없음)

import { readFileSync } from "node:fs";

const SRC = "supabase/functions/inv-doc-cost/index.ts";
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
  constLine("COLLECTOR_VERSION"),
  constLine("INVENTORY_DEBIT"),
  extractBlock("// ── 계산 핵심 (pure", "// ── 계산 핵심 끝 ──"),
  extractBlock("// ── 커서 tie-breaker", "// ── 회차 로그"),
  "export { buildDocCostRows, listDisposition, cursorKeyOf, cursorKeyCompare, decideCursor, countUpdatedTies };",
].join("\n");
const { mkdtempSync, writeFileSync } = await import("node:fs");
const { execSync } = await import("node:child_process");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const dir = mkdtempSync(join(tmpdir(), "invdoccost-"));
writeFileSync(join(dir, "c.ts"), code);
execSync(`npx --yes esbuild ${join(dir, "c.ts")} --outfile=${join(dir, "c.mjs")} --format=esm`, { stdio: "pipe" });
const { buildDocCostRows, listDisposition, cursorKeyOf, cursorKeyCompare, decideCursor, countUpdatedTies } = await import(join(dir, "c.mjs"));

const TOR = "f1ca3946-5a4e-4da7-b68a-ce7d3500f0be", EDM = "623edcaa-5f18-4682-aae1-b9016d977c11";
const row = (over = {}) => ({ TaskID: "t1", From: TOR, To: EDM, Status: "COMPLETED", Number: "TR-X", LastModifiedOn: "2026-09-10T15:32:06.049Z", CostDistributionType: "Cost", ...over });
const call = (mj, docNo = "TR-X") => buildDocCostRows({ docNo, det: { TaskID: "t1", Status: "COMPLETED", Number: docNo, ManualJournals: mj }, row: row({ Number: docNo }) });

// ① TR-03975 실측 원문
{
  const mj = [
    { Debit: "_1150040007_", Credit: "_59_", Reference: "TR-03975", Date: "2026-08-26T00:00:00", Amount: 4878.11, IsSystem: true },
    { Debit: "_59_", Credit: "_136_", Reference: "B6900109", Date: "2026-08-27T00:00:00", Amount: 398.75, IsSystem: false },
  ];
  const r = call(mj, "TR-03975");
  const x = r.rows[0];
  ok("① TR-03975 — 시스템 저널 제외 · 운송비 1행 · raw 배열 전체",
    r.disposition === "processed" && r.rows.length === 1 && x.amount === 398.75 && x.ref_number === "B6900109"
    && x.occurred_on === "2026-08-27" && x.debit_account === "_59_" && x.credit_account === "_136_"
    && x.doc_type === "transfer" && x.kind === "transfer_freight" && x.doc_number === "TR-03975"
    && x.raw.manual_journals.length === 2 && x.raw.doc.from === TOR && r.tally.system === 1 && r.tally.kept === 1 && r.warnings.length === 0,
    JSON.stringify(r));
}
// ② TR-04175 실측 원문 — 1행이고 그것이 운송비
{
  const r = call([{ Debit: "_59_", Credit: "_136_", Reference: "B6913286", Date: "2026-09-04T00:00:00", Amount: 249.33, IsSystem: false }], "TR-04175");
  ok("② TR-04175 — ARRAY(1) 이 운송비(길이로 판단하지 않는다)",
    r.disposition === "processed" && r.rows.length === 1 && r.rows[0].amount === 249.33 && r.rows[0].ref_number === "B6913286" && r.rows[0].occurred_on === "2026-09-04" && r.tally.system === 0,
    JSON.stringify(r.rows));
}
// ③ 저널 없음
{
  const a = call([]), b = buildDocCostRows({ docNo: "TR-X", det: { Number: "TR-X" }, row: row() });
  ok("③ ManualJournals 빈 배열/없음 → skip_no_journal", a.disposition === "skip_no_journal" && b.disposition === "skip_no_journal" && a.rows.length === 0 && b.rows.length === 0);
}
// ④ 시스템 저널만
{
  const r = call([{ Debit: "_1150040007_", Credit: "_59_", Reference: "TR-X", Date: "2026-08-26T00:00:00", Amount: 100, IsSystem: true }]);
  ok("④ IsSystem=true 만 → skip_system_only", r.disposition === "skip_system_only" && r.rows.length === 0 && r.tally.system === 1);
}
// ⑤ 비재고 Debit
{
  const a = call([{ Debit: "_95_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: 10, IsSystem: false }]);
  const b = call([
    { Debit: "_95_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: 10, IsSystem: false },
    { Debit: "_59_", Credit: "_136_", Reference: "B2", Date: "2026-09-01T00:00:00", Amount: 20, IsSystem: false },
  ]);
  ok("⑤ Debit ≠ _59_ → skip_non_inventory_debit + 경고에 계정 코드 · 섞이면 processed + tally",
    a.disposition === "skip_non_inventory_debit" && a.rows.length === 0 && a.warnings.some((w) => w.includes("'_95_'") && w.includes("skip_non_inventory_debit"))
    && b.disposition === "processed" && b.rows.length === 1 && b.rows[0].ref_number === "B2" && b.tally.non_inventory_debit === 1 && b.tally.kept === 1,
    JSON.stringify({ a: a.disposition, b: b.disposition, w: a.warnings }));
}
// ⑥ Reference 없음
{
  const r = call([{ Debit: "_59_", Credit: "_136_", Reference: "", Date: "2026-09-01T00:00:00", Amount: 10, IsSystem: false },
                  { Debit: "_59_", Credit: "_136_", Date: "2026-09-01T00:00:00", Amount: 11, IsSystem: false }]);
  ok("⑥ Reference 비었음 → skip_no_reference · 행 0", r.disposition === "skip_no_reference" && r.rows.length === 0 && r.tally.no_reference === 2 && r.warnings.length === 2, JSON.stringify(r));
}
// ⑦ Amount 0 · 음수
{
  const z = call([{ Debit: "_59_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: 0, IsSystem: false }]);
  const n = call([{ Debit: "_59_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: -5.5, IsSystem: false }]);
  ok("⑦ Amount 0 → skip_zero_amount · 음수는 넣는다", z.disposition === "skip_zero_amount" && z.rows.length === 0 && z.tally.zero_amount === 1
    && n.disposition === "processed" && n.rows.length === 1 && n.rows[0].amount === -5.5, JSON.stringify({ z: z.disposition, n: n.rows }));
}
// ⑧ 같은 (ref, date) 두 줄
{
  const r = call([{ Debit: "_59_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: 10.5, IsSystem: false },
                  { Debit: "_59_", Credit: "_136_", Reference: "B1", Date: "2026-09-01T00:00:00", Amount: 2.25, IsSystem: false },
                  { Debit: "_59_", Credit: "_136_", Reference: "B1", Date: "2026-09-02T00:00:00", Amount: 1, IsSystem: false }]);
  ok("⑧ 같은 (ref, date) 두 줄 → 합산 1행 · 다른 날짜는 별개 · mergedRows 1 · 경고",
    r.disposition === "processed" && r.rows.length === 2 && r.rows[0].amount === 12.75 && r.rows[1].amount === 1 && r.mergedRows === 1 && r.warnings.some((w) => w.includes("merged")),
    JSON.stringify(r.rows.map((x) => [x.occurred_on, x.amount])));
}
// ⑨ 목록 disposition
{
  ok("⑨ listDisposition — From===To / Status / GUID 없음 / 정상",
    listDisposition(row({ To: TOR })) === "skip_same_location"
    && listDisposition(row({ Status: "IN TRANSIT" })) === "skip_not_completed"
    && listDisposition(row({ From: "" })) === "skip_same_location"
    && listDisposition(row()) === "candidate" && listDisposition(row({ Status: "completed" })) === "candidate");
}
// ⑩ 커서
{
  const k1 = cursorKeyOf("2026-09-10T15:32:06.049Z", "TR-04175"), k2 = cursorKeyOf("2026-09-10T15:32:06.049Z", "TR-04176"), k0 = cursorKeyOf(null, "TR-1");
  const sorted = [k2, k1, k0].sort(cursorKeyCompare);
  const before = "2026-09-10T15:32:06.049Z|TR-04175";
  const a = decideCursor(false, k2, before, "2026-09-11T00:00:00.000Z");
  const b = decideCursor(true, k2, before, "2026-09-11T00:00:00.000Z");
  const c = decideCursor(true, k1, before, "2026-09-11T00:00:00.000Z");
  const d = decideCursor(true, null, before, "2026-09-11T00:00:00.000Z");
  ok("⑩ 커서 — 정렬(null 맨 앞) · 비캡=회차시각 · 캡=마지막 키 전진 · 동률 제자리/키 없음 = stalled",
    sorted[0] === null && sorted[1] === k1 && sorted[2] === k2
    && a.cursorWouldBe === "2026-09-11T00:00:00.000Z" && !a.cursorStalled
    && b.cursorWouldBe === k2 && !b.cursorStalled
    && c.cursorWouldBe === k1 && c.cursorStalled
    && d.cursorWouldBe === before && d.cursorStalled
    && countUpdatedTies([{ updated: "x" }, { updated: "x" }, { updated: "y" }]) === 2
    && k1 < "2026-09-11T00:00:00.000Z" && "2026-09-10T15:32:06.049Z|TR-04175" > "2026-09-10T15:32:06.049Z",   // 키 vs 맨 ISO 커서 비교 방향
    JSON.stringify({ sorted, a, b, c, d }));
}
// ⑪ 정적
{
  const codeOnly = src.split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");   // 주석 제거(문자열 안 // 는 없다)
  const writeCalls = (codeOnly.match(/writeDocCostRows\(/g) ?? []).length - 1;     // 정의 1 제외
  const commitIdx = codeOnly.indexOf("if (commit) {");
  const writeIdx = codeOnly.indexOf("await writeDocCostRows(");
  const endCommit = codeOnly.indexOf("// commit 블록 끝", commitIdx) > 0 ? codeOnly.indexOf("// commit 블록 끝", commitIdx) : src.indexOf("// commit 블록 끝");
  ok("⑪-a dry 기본 — commit 은 ?commit=1 에서만 · writeDocCostRows 호출 1곳 · commit 블록 안",
    /const commit = url\.searchParams\.get\("commit"\) === "1";/.test(src) && writeCalls === 1 && commitIdx > 0 && writeIdx > commitIdx && writeIdx < src.indexOf("// commit 블록 끝"),
    JSON.stringify({ writeCalls, commitIdx, writeIdx }));
  ok("⑪-b on_conflict = inv_doc_cost_uq 순서 · SOURCE_KEY 'cost_transfer' · 커서 읽기/쓰기 모두 SOURCE_KEY",
    /const DOC_CONFLICT = "doc_type,doc_number,kind,ref_number,occurred_on"/.test(src)
    && /const SOURCE_KEY = "cost_transfer"/.test(src)
    && codeOnly.includes('inv_sync_state?source_key=eq." + SOURCE_KEY') && codeOnly.includes("source_key: SOURCE_KEY"));
  const layerRefs = (codeOnly.match(/\binv_layer\b/g) ?? []).length, costRefs = (codeOnly.match(/\binv_cost\b/g) ?? []).length;
  ok("⑪-c 코드(주석 제외)에 inv_layer · inv_cost 참조 0 (배분하지 않는다 · 남의 표를 건드리지 않는다)", layerRefs === 0 && costRefs === 0, JSON.stringify({ layerRefs, costRefs }));
  const cin7Calls = (codeOnly.match(/cin7Get\(/g) ?? []).length, cin7Other = (codeOnly.match(/\bcin7\(/g) ?? []).length;
  ok("⑪-d Cin7 는 GET 만 — cin7Get 2곳(목록·상세) · cin7(method) 직접 호출 0", cin7Calls === 2 && cin7Other === 0, JSON.stringify({ cin7Calls, cin7Other }));
  ok("⑪-e 필터 조건 둘 — IsSystem === false · Debit === INVENTORY_DEBIT('_59_')",
    codeOnly.includes("j?.IsSystem === false") && codeOnly.includes("debit !== INVENTORY_DEBIT") && /const INVENTORY_DEBIT = "_59_"/.test(src));
  ok("⑪-f 목록은 Status=COMPLETED 서버 필터 + UpdatedSince 미사용(미확인 파라미터) · 페이싱 1200ms · 캡 40 · 120초",
    codeOnly.includes('"/stockTransferList?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT + "&Status="') && !codeOnly.includes("UpdatedSince")
    && /const DETAIL_SLEEP_MS = 1200;/.test(src) && /const MAX_DETAIL_PER_RUN = 40;/.test(src) && /const TIME_BUDGET_MS = 120_000;/.test(src));
}

if (fails) { console.error(fails + " FAILED"); process.exit(1); }
console.log("ALL INV-DOC-COST TESTS PASSED");
