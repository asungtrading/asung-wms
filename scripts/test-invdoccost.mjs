// inv-doc-cost 계산 테스트 (2026-09-10 — buildDocCostRows/listDisposition/커서 판정)
//
// 실행:  node scripts/test-invdoccost.mjs
// 전부 통과하면 마지막 줄이 "ALL INV-DOC-COST TESTS PASSED".
//
// 방식은 scripts/test-invcost.mjs 와 동일 — 원본 파일에서 계산 핵심 구간을 원문 추출해(esbuild 로 타입 제거)
// node 로 실행한다. ⚠️ EF 자체(Deno.serve · Cin7 호출)는 여기서 돌지 않는다 — 로컬에 deno 도 Cin7 secret 도 없다.
// 픽스처는 GAS 프로브 실측(2026-09-10 14:40 · TR-03975 · TR-04175 · TR-03976)의 ManualJournals **원문 그대로**(원소 키 11개)다.
// ⚠️⚠️ [정정 2026-09-10] 종전 픽스처는 `IsSystem` 을 담고 있었다 — 실물에 없는 필드(응답 전체 문자열 검색 0건 · 세 문서)다.
//   그 픽스처로 통과한 ①②④⑤⑥⑦⑧ 은 실물을 검증한 것이 아니었다: 실물 행(IsSystem 없음)은 `j?.IsSystem === false` 에서 전량 걸러져
//   전부 skip_system_only 가 됐을 것이다(다섯 회차 docs_processed 0 의 원인). ④(IsSystem=true 만 → skip_system_only)는 존재할 수 없는 모양이었다.
//
// 검증:
//  ① TR-03975 실측 원문 → 행 1건 · amount 398.75 · ref B6900109 · 2026-08-27 · raw 에 배열 전체(11키 원문)
//  ② TR-04175 실측 원문 → 행 1건 · amount 249.33 · ref B6913286
//  ②-b TR-03976 실측 원문 → 행 1건 · amount 229.2 · ref B6900109 — TR-03975 와 **같은 인보이스**를 다른 금액으로 나눠 갖는다(인보이스 1장 → 문서 여럿의 실물)
//  ③ ManualJournals 없음/빈 배열 → skip_no_journal
//  ④ Credit ≠ _136_ → skip_non_freight_credit + 경고에 계정 코드 · 정상 행과 섞이면 processed + tally 1 (⚠️ 옛 ④ skip_system_only 는 도달 불가능 — 제거)
//  ⑤ Debit ≠ _59_ → skip_non_inventory_debit + 경고에 계정 코드 · 정상 행과 섞이면 processed + tally 1
//  ⑥ Reference 비었음 → skip_no_reference · 행 0 (유니크가 안 걸리므로 넣지 않는다)
//  ⑦ Amount 0 → skip_zero_amount · 음수는 넣는다(배분 가드가 차단)
//  ⑧ 같은 (ref, date) 두 줄 → 합산 1행 · mergedRows 1 · 경고
//  ⑨ listDisposition — From===To → skip_same_location · Status≠COMPLETED → skip_not_completed · GUID 없음 → skip_same_location
//  ⑩ 커서 — 키 정렬(코드유닛) · decideCursor: 비캡=회차시각 · 캡=마지막 키 · 캡인데 전진 없음=stalled
//  ⑪ 정적 — dry 기본(commit==="1") · writeDocCostRows 호출은 commit 블록 안 1곳 · on_conflict = inv_doc_cost_uq 순서 ·
//     SOURCE_KEY='cost_transfer' · 코드(주석 제외)에 inv_layer·inv_cost 참조 0 · Cin7 GET 만(cin7Get 외 cin7( 호출 없음) ·
//     ⑪-e 필터 = Debit _59_ AND Credit _136_ · 코드에 IsSystem 참조 0 · skip_system_only 없음
// 2026-09-10 추가 — from_since/recheck_since 가 시각을 받는다 + LastModifiedOn 밀리초 자릿수 정규화 (prompt-from-since-time):
//  ⑫ parseFloor — 날짜 → T00:00:00.000Z · 시각(HH:MM · :SS · .mmmZ) → 그대로(정규화) · 잘못된 형식(2026-13-99 · hello · T99:99) → null(=400)
//  ⑬ normLmo — .9Z·.10Z·.373Z·.4Z·.0Z·소수부 없음을 섞어 정규화 뒤 코드유닛 정렬 = 시각 순서 · 원문 정렬은 뒤집힘(결함 재현) ·
//     커서 키·하한 비교가 정규화 값으로 옳게 판정(".3Z|TR-a" 커서 뒤의 ".373Z|TR-b" 를 건너뛰지 않는다)
//  ⑭ 정적 — 필터가 slice(0,10) 이 아니라 정규화 시각 비교 · 키는 normLmo 값으로 · 응답 키 lmo_floor(lmo_floor_date 없음) · 두 파라미터 모두 parseFloor · 실패 400
//  ⑮ 정적 — 진단 필드 skipped_docs(≤50 · mj_len)·skipped_docs_truncated·candidate_head(커서 필터 뒤 앞 10건)

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
  constLine("FREIGHT_CREDIT"),
  extractBlock("// ── 계산 핵심 (pure", "// ── 계산 핵심 끝 ──"),
  extractBlock("// ── 커서 tie-breaker", "// ── 회차 로그"),
  "export { buildDocCostRows, listDisposition, cursorKeyOf, cursorKeyCompare, decideCursor, countUpdatedTies, normLmo, parseFloor, LMO_RE };",
].join("\n");
const { mkdtempSync, writeFileSync } = await import("node:fs");
const { execSync } = await import("node:child_process");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const dir = mkdtempSync(join(tmpdir(), "invdoccost-"));
writeFileSync(join(dir, "c.ts"), code);
execSync(`npx --yes esbuild ${join(dir, "c.ts")} --outfile=${join(dir, "c.mjs")} --format=esm`, { stdio: "pipe" });
const { buildDocCostRows, listDisposition, cursorKeyOf, cursorKeyCompare, decideCursor, countUpdatedTies, normLmo, parseFloor, LMO_RE } = await import(join(dir, "c.mjs"));

const TOR = "f1ca3946-5a4e-4da7-b68a-ce7d3500f0be", EDM = "623edcaa-5f18-4682-aae1-b9016d977c11";
const row = (over = {}) => ({ TaskID: "t1", From: TOR, To: EDM, Status: "COMPLETED", Number: "TR-X", LastModifiedOn: "2026-09-10T15:32:06.049Z", CostDistributionType: "Cost", ...over });
const call = (mj, docNo = "TR-X") => buildDocCostRows({ docNo, det: { TaskID: "t1", Status: "COMPLETED", Number: docNo, ManualJournals: mj }, row: row({ Number: docNo }) });
// ⭐ 실측 원문 (GAS 프로브 2026-09-10 14:40) — 원소 키 11개 · IsSystem 없음. 저널 행 하나만 실제 값이고 나머지 키는 실측 그대로(빈 배열·null).
const MJ_03975 = [{ TaskID: "c456b86f-59e5-4953-8ef6-cb5db0b4e932", ID: "8ea9e56f-8e31-4cd8-9b1c-4ab10e21bbf4", Reference: "B6900109", Amount: 398.75, Date: "2026-08-27T00:00:00",
  Debit: "_59_", Credit: "_136_", ManualJournalsDistributedCosts: [], vDimensionDefaultValueStockTransferJournals: [], ValidationText: null, ValidationState: null }];
const MJ_04175 = [{ TaskID: "7c8bae31-3d9e-471f-b7da-8a274e1c16bb", ID: "id-04175", Reference: "B6913286", Amount: 249.33, Date: "2026-09-04T00:00:00",
  Debit: "_59_", Credit: "_136_", ManualJournalsDistributedCosts: [], vDimensionDefaultValueStockTransferJournals: [], ValidationText: null, ValidationState: null }];
const MJ_03976 = [{ TaskID: "task-03976", ID: "id-03976", Reference: "B6900109", Amount: 229.2, Date: "2026-08-27T00:00:00",
  Debit: "_59_", Credit: "_136_", ManualJournalsDistributedCosts: [], vDimensionDefaultValueStockTransferJournals: [], ValidationText: null, ValidationState: null }];
// 합성 행 헬퍼 — 실측 원문 모양(11키)에 값만 바꾼다. IsSystem 은 넣지 않는다(존재하지 않는 필드).
const mj = (o) => ({ TaskID: "t", ID: "i", Reference: "B1", Amount: 10, Date: "2026-09-01T00:00:00", Debit: "_59_", Credit: "_136_",
  ManualJournalsDistributedCosts: [], vDimensionDefaultValueStockTransferJournals: [], ValidationText: null, ValidationState: null, ...o });

// ① TR-03975 실측 원문 (11키 · IsSystem 없음)
{
  const r = call(MJ_03975, "TR-03975");
  const x = r.rows[0];
  ok("① TR-03975 실측 원문 → 1행 · 398.75 · B6900109 · 2026-08-27 · raw 에 원문 배열 전체",
    r.disposition === "processed" && r.rows.length === 1 && x.amount === 398.75 && x.ref_number === "B6900109"
    && x.occurred_on === "2026-08-27" && x.debit_account === "_59_" && x.credit_account === "_136_"
    && x.doc_type === "transfer" && x.kind === "transfer_freight" && x.doc_number === "TR-03975"
    && x.raw.manual_journals.length === 1 && Object.keys(x.raw.manual_journals[0]).length === 11 && x.raw.doc.from === TOR
    && r.tally.kept === 1 && r.tally.non_inventory_debit === 0 && r.tally.non_freight_credit === 0 && r.warnings.length === 0,
    JSON.stringify(r));
}
// ② TR-04175 실측 원문 — 이 문서가 다섯 회차 docs_processed 0 의 실사고 대상
{
  const r = call(MJ_04175, "TR-04175");
  ok("② TR-04175 실측 원문 → 1행 · 249.33 · B6913286 · 2026-09-04 (종전 IsSystem 필터면 skip 됐던 문서)",
    r.disposition === "processed" && r.rows.length === 1 && r.rows[0].amount === 249.33 && r.rows[0].ref_number === "B6913286" && r.rows[0].occurred_on === "2026-09-04",
    JSON.stringify(r.rows));
  const r2 = call(MJ_03976, "TR-03976");
  ok("②-b TR-03976 실측 원문 → 1행 · 229.2 · B6900109 — TR-03975 와 같은 인보이스를 나눠 갖는다(문서별 행 · 유니크 키에 doc_number 가 있어 공존)",
    r2.disposition === "processed" && r2.rows.length === 1 && r2.rows[0].amount === 229.2 && r2.rows[0].ref_number === "B6900109" && r2.rows[0].occurred_on === "2026-08-27",
    JSON.stringify(r2.rows));
}
// ③ 저널 없음
{
  const a = call([]), b = buildDocCostRows({ docNo: "TR-X", det: { Number: "TR-X" }, row: row() });
  ok("③ ManualJournals 빈 배열/없음 → skip_no_journal", a.disposition === "skip_no_journal" && b.disposition === "skip_no_journal" && a.rows.length === 0 && b.rows.length === 0);
}
// ④ Credit 화이트리스트 (2026-09-10 신설 · 옛 ④ skip_system_only 는 도달 불가능해 제거)
{
  const a = call([mj({ Credit: "_500_" })]);
  const b = call([mj({ Credit: "_500_", Reference: "B1" }), mj({ Reference: "B2", Amount: 20 })]);
  ok("④ Credit ≠ _136_ → skip_non_freight_credit + 경고에 계정 코드 · 섞이면 processed + tally 1",
    a.disposition === "skip_non_freight_credit" && a.rows.length === 0 && a.tally.non_freight_credit === 1 && a.warnings.some((w) => w.includes("'_500_'") && w.includes("skip_non_freight_credit"))
    && b.disposition === "processed" && b.rows.length === 1 && b.rows[0].ref_number === "B2" && b.tally.non_freight_credit === 1 && b.tally.kept === 1,
    JSON.stringify({ a: a.disposition, b: b.disposition, w: a.warnings }));
}
// ⑤ 비재고 Debit
{
  const a = call([mj({ Debit: "_95_" })]);
  const b = call([mj({ Debit: "_95_" }), mj({ Reference: "B2", Amount: 20 })]);
  ok("⑤ Debit ≠ _59_ → skip_non_inventory_debit + 경고에 계정 코드 · 섞이면 processed + tally",
    a.disposition === "skip_non_inventory_debit" && a.rows.length === 0 && a.warnings.some((w) => w.includes("'_95_'") && w.includes("skip_non_inventory_debit"))
    && b.disposition === "processed" && b.rows.length === 1 && b.rows[0].ref_number === "B2" && b.tally.non_inventory_debit === 1 && b.tally.kept === 1,
    JSON.stringify({ a: a.disposition, b: b.disposition, w: a.warnings }));
}
// ⑥ Reference 없음
{
  const r = call([mj({ Reference: "" }), mj({ Reference: undefined, Amount: 11 })]);
  ok("⑥ Reference 비었음 → skip_no_reference · 행 0", r.disposition === "skip_no_reference" && r.rows.length === 0 && r.tally.no_reference === 2 && r.warnings.length === 2, JSON.stringify(r));
}
// ⑦ Amount 0 · 음수
{
  const z = call([mj({ Amount: 0 })]);
  const n = call([mj({ Amount: -5.5 })]);
  ok("⑦ Amount 0 → skip_zero_amount · 음수는 넣는다", z.disposition === "skip_zero_amount" && z.rows.length === 0 && z.tally.zero_amount === 1
    && n.disposition === "processed" && n.rows.length === 1 && n.rows[0].amount === -5.5, JSON.stringify({ z: z.disposition, n: n.rows }));
}
// ⑧ 같은 (ref, date) 두 줄
{
  const r = call([mj({ Amount: 10.5 }), mj({ Amount: 2.25 }), mj({ Date: "2026-09-02T00:00:00", Amount: 1 })]);
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
  ok("⑪-e 필터 = Debit _59_ AND Credit _136_ 화이트리스트 · 코드(주석 제외)에 IsSystem 참조 0 · skip_system_only 없음 · 배열 전량 순회",
    !codeOnly.includes("IsSystem") && !codeOnly.includes("skip_system_only") && !codeOnly.includes("tally.system")
    && codeOnly.includes("debit !== INVENTORY_DEBIT") && codeOnly.includes("credit !== FREIGHT_CREDIT") && codeOnly.includes("for (const j of mjArr) {")
    && /const INVENTORY_DEBIT = "_59_"/.test(src) && /const FREIGHT_CREDIT = "_136_"/.test(src));
  ok("⑪-f 목록은 Status=COMPLETED 서버 필터 + UpdatedSince 미사용(미확인 파라미터) · 페이싱 1200ms · 캡 40 · 120초",
    codeOnly.includes('"/stockTransferList?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT + "&Status="') && !codeOnly.includes("UpdatedSince")
    && /const DETAIL_SLEEP_MS = 1200;/.test(src) && /const MAX_DETAIL_PER_RUN = 40;/.test(src) && /const TIME_BUDGET_MS = 120_000;/.test(src));
}

// ⑫ parseFloor — from_since / recheck_since 공용
{
  const ok1 = parseFloor("2026-08-26") === "2026-08-26T00:00:00.000Z";
  const ok2 = parseFloor("2026-08-26T20:50") === "2026-08-26T20:50:00.000Z";
  const ok3 = parseFloor("2026-08-26T20:51:06") === "2026-08-26T20:51:06.000Z";
  const ok4 = parseFloor("2026-08-26T20:51:06.373Z") === "2026-08-26T20:51:06.373Z";
  const ok5 = parseFloor("2026-08-26T20:51:06.4Z") === "2026-08-26T20:51:06.400Z";   // 1자리도 3자리로
  const bad = ["2026-13-99", "hello", "2026-08-26T99:99", "2026-08-26 20:50", "2026-02-30", ""].map((v) => parseFloor(v));
  ok("⑫ parseFloor — 날짜→T00:00:00.000Z · HH:MM · :SS · .mmmZ · .4Z→.400Z · 잘못된 형식 6종 → null(400)",
    ok1 && ok2 && ok3 && ok4 && ok5 && bad.every((v) => v === null),
    JSON.stringify({ a: parseFloor("2026-08-26"), b: parseFloor("2026-08-26T20:50"), bad }));
}
// ⑬ normLmo — 밀리초 자릿수 정규화 · 정렬 · 커서 판정
{
  const raw = ["2026-08-26T20:51:06.9Z", "2026-08-26T20:51:06.10Z", "2026-08-26T20:51:06.373Z", "2026-08-26T20:51:06.4Z", "2026-08-26T20:51:06.0Z", "2026-08-26T20:51:06Z", "2026-08-26T20:51:06.3Z"];
  const byTime = [...raw].sort((a, b) => Date.parse(a) - Date.parse(b));
  const byNorm = [...raw].sort((a, b) => cursorKeyCompare(normLmo(a), normLmo(b)));
  const byRaw  = [...raw].sort((a, b) => cursorKeyCompare(a, b));
  const normVals = raw.map(normLmo);
  ok("⑬-a normLmo — 3자리 패딩 · 소수부 없음 → .000Z · 정규화 뒤 코드유닛 정렬 == 시각 정렬",
    normLmo("2026-08-26T20:51:06.4Z") === "2026-08-26T20:51:06.400Z" && normLmo("2026-08-26T20:51:06Z") === "2026-08-26T20:51:06.000Z"
    && normLmo("2026-08-26T20:51:06.10Z") === "2026-08-26T20:51:06.100Z" && normLmo(null) === null
    && JSON.stringify(byNorm) === JSON.stringify(byTime) && normVals.every((v) => /\.\d{3}Z$/.test(v)),
    JSON.stringify({ byNorm, byTime }));
  ok("⑬-b 결함 재현 — 원문 정렬은 시각 순서와 다르다(짧은 소수부가 뒤로 감 · 이것이 고친 이유)",
    JSON.stringify(byRaw) !== JSON.stringify(byTime) && byRaw.indexOf("2026-08-26T20:51:06Z") > byRaw.indexOf("2026-08-26T20:51:06.4Z"),
    JSON.stringify(byRaw));
  // 커서 키 판정: 커서 = ".3Z|TR-a"(300ms) 뒤에 ".373Z|TR-b"(373ms) 가 와야 한다 — 원문 비교면 건너뛰고(key < cursor), 정규화면 처리된다
  const cursorRaw = "2026-08-26T20:51:06.3Z|TR-a", docRaw = cursorKeyOf("2026-08-26T20:51:06.373Z", "TR-b");
  const cursorN = cursorKeyOf(normLmo("2026-08-26T20:51:06.3Z"), "TR-a"), docN = cursorKeyOf(normLmo("2026-08-26T20:51:06.373Z"), "TR-b");
  ok("⑬-c 커서 판정 — 원문이면 373ms 문서가 300ms 커서보다 작아 건너뛰고(결함) · 정규화면 크다(처리) · 하한 비교도 정규화 값으로 옳다",
    (docRaw < cursorRaw) === true && (docN < cursorN) === false
    && normLmo("2026-08-26T20:51:06.373Z") >= parseFloor("2026-08-26T20:51:06.373Z") && normLmo("2026-08-26T20:51:06.4Z") >= parseFloor("2026-08-26T20:51:06.373Z")
    && normLmo("2026-08-26T20:51:06.3Z") < parseFloor("2026-08-26T20:51:06.373Z"),
    JSON.stringify({ docRaw, cursorRaw, docN, cursorN }));
  ok("⑬-d 예상 밖 형식은 원문 유지(LMO_RE 불일치) — 호출부가 lmo_unnormalized 로 센다", normLmo("2026-08-26 20:51:06") === "2026-08-26 20:51:06" && !LMO_RE.test("2026-08-26 20:51:06"));
}
// ⑭ 정적 — 세 비교 지점이 전부 정규화 값을 쓰는지 · 응답 키
{
  const codeOnly = src.split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");
  ok("⑭-a 하한 필터 — updated.slice(0,10) 날짜 절단 없음 · 정규화 updated < lmoFloor 비교 · updated = normLmo(rawLmo)",
    !codeOnly.includes("updated.slice(0, 10)") && codeOnly.includes("if (lmoFloor && updated && updated < lmoFloor)") && codeOnly.includes("const updated = normLmo(rawLmo);"));
  ok("⑭-b 커서 키 — cursorKeyOf(updated, …) 의 updated 가 정규화 값(같은 루프) · runStartIso 는 toISOString(3자리)",
    codeOnly.includes("cands.push({ row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) });") && codeOnly.includes("const runStartIso = new Date(t0).toISOString();"));
  ok("⑭-c 두 파라미터 모두 parseFloor · 실패 400 · 응답 키 lmo_floor(옛 lmo_floor_date 없음) · lmo_unnormalized 카운터",
    (codeOnly.match(/parseFloor\((fromSinceRaw|recheckSinceRaw)\)/g) ?? []).length === 2
    && codeOnly.includes('if (fromSinceRaw && !fromSince) return json(') && codeOnly.includes('if (recheckSinceRaw && !recheckSince) return json(')
    && codeOnly.includes("lmo_floor: lmoFloor,") && !codeOnly.includes("lmo_floor_date") && codeOnly.includes("lmo_unnormalized: lmoUnnormalized,"));   // 옛 키는 주석(헤더 경위)에만 남는다
}

// ⑮ 정적 — 진단 필드 (2026-09-10 · skip 된 문서번호를 남긴다)
{
  const codeOnly = src.split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");
  ok("⑮ 진단 — skipped_docs(processed 아닌 문서 · 상한 50 · mj_len) · skipped_docs_truncated · candidate_head(커서 필터 뒤 앞 10건 · doc_number+key)",
    codeOnly.includes('if (r.disposition !== "processed") {') && codeOnly.includes("const SKIPPED_DOCS_MAX = 50;")
    && codeOnly.includes("skippedDocs.push({ doc_number: docNo, disposition: r.disposition, mj_len: mjLenOf(det) })")
    && codeOnly.includes("skipped_docs: skippedDocs,") && codeOnly.includes("skipped_docs_truncated: skippedDocsTruncated,")
    && codeOnly.includes("const candidateHead = cands.slice(0, 10).map((cd, i) => ({ n: i + 1, doc_number: cursorDocIdent(cd.row), key: cd.key }));")
    && codeOnly.indexOf("const candidateHead") > codeOnly.indexOf("cands.push(...kept);")   // 커서 필터 뒤 = 실제 처리 순서
    && codeOnly.includes("candidate_head: candidateHead,"));
}

if (fails) { console.error(fails + " FAILED"); process.exit(1); }
console.log("ALL INV-DOC-COST TESTS PASSED");
