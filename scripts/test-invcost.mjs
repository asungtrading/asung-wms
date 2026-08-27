// inv-cost 계산 테스트 (2026-08-27 — buildCostRows/listDisposition)
//
// 실행:  node scripts/test-invcost.mjs
// 전부 통과하면 마지막 줄이 "ALL INV-COST TESTS PASSED".
//
// 방식은 scripts/test-invcollect-missing.mjs 와 동일 — 원본 파일에서 계산 핵심 구간을
// 원문 추출해 node 로 실행(실행 시마다 재추출이라 구현이 바뀌면 테스트가 따라온다).
// 산술 근거는 docs/sessions/2026-08-27-landed-cost-investigation.md (다시 조사하지 말 것).
//
// 검증 17 (지시서 §4 + 2026-08-27 I&R·amount_orig·SR 화이트리스트·raw.invoice·입고비율·세전축 정정):
//  ① PO-00853 모양 — goods 2날짜 + landed 1날짜, 배분 합계 == IM 순액
//  ② 재평가 — 같은 (pid,date)에 +A/−A/+B 세 행 → 순액 B 로 합산
//  ③ landed 를 여러 입고일·여러 bin 에 수량 비례 배분 (잔액은 마지막 라인)
//  ④ IsServiceOnly 스킵 (listDisposition — 상세 조회 전 게이트)
//  ⑤ qty=0 라인 스킵 + 카운트
//  ⑥ 배분 불가(PA/SR 수량 불일치) → 문서 스킵 + 경고
//  ⑦ upsert URL 이 on_conflict 8키 + merge-duplicates 를 싣는지 (정적)
//  ⑧ dry=1 에서 쓰기 0 — writeCostRows 호출이 if (commit) 블록 안 한 곳뿐 (정적)
//  ⑨ 같은 SKU 가 두 I&R 에 걸쳐 입고 — 각각 다른 CurrencyRate 로 배분 (PO-01130 모양)
//  ⑩ I&R 없는 블록 → 그 블록만 스킵(skip_ir_unmatched) · 나머지 블록 정상 처리
//  ⑪ 두 bin 으로 갈린 goods — 행마다 |amount − (amount_orig/lines_total_all)×net_total×fx| ≤ 0.01 ·
//     amount_orig 합 == 인보이스 제품 라인 Total 합 (행 단위 배분 · 잔액은 마지막 라인)
//  ⑫ SR 블록 DRAFT 인데 수량이 PA 와 일치 → 정상 처리 (SR 화이트리스트 제거 — PO-01117 실측)
//  ⑬ SR 블록 VOIDED → 그 블록만 제외 (sr:VOIDED)
//  ⑭ 인보이스 −0.5% 할인(Account=_59_) — 재계산 항등식 성립 + raw.invoice 에 3값
//  ⑮ 부분 입고(주문 100 · 입고 63) — Σ amount_orig == lineTotal × 0.63 · 재계산 항등식 성립
//  ⑯ 같은 제품 두 날짜 분할 입고(40+60, 주문 100) — Σ amount_orig == lineTotal (이중 계상 회귀 방지)
//  ⑰ 세금 있는 인보이스(HST 13%) — net_total 은 TotalBeforeTax(세전) · ratio 1 (PO-00967 회귀 가드)

import { readFileSync } from "node:fs";

const SRC = "supabase/functions/inv-cost/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

// ── 원문 추출: 계산 핵심 구간(마커 쌍) + COLLECTOR_VERSION ──
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
  extractBlock("// ── 계산 핵심 (pure", "// ── 계산 핵심 끝 ──"),
  "export { buildCostRows, listDisposition, round6 };",
].join("\n");
// 타입 제거는 esbuild (missing 테스트와 동일 — 정규식 스트리핑은 여러 줄 타입에서 깨진다)
const { mkdtempSync, writeFileSync } = await import("node:fs");
const { execSync } = await import("node:child_process");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const dir = mkdtempSync(join(tmpdir(), "invcost-"));
writeFileSync(join(dir, "c.ts"), code);
execSync(`npx --yes esbuild ${join(dir, "c.ts")} --outfile=${join(dir, "c.mjs")} --format=esm`, { stdio: "pipe" });
const { buildCostRows, listDisposition, round6 } = await import(join(dir, "c.mjs"));

// 목 resolveLoc — 매핑 항상 성공, bin = line.Location 그대로 (실제 EF 는 ref/location ID 맵)
const mockLoc = (line) => ({ warehouse: "Asung Trading Inc.", bin: String(line?.Location ?? ""), mapped: true });
const call = (det, since = null) => buildCostRows({ docNo: "PO-TEST", det, since, loc: mockLoc });

// ① PO-00853 모양 — 상품가는 입고일(SR 일치 = goods) · 통관비는 SR 없는 앞선 날짜(= landed)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.4, Lines: [
      { ProductID: "p1", Total: 100, Quantity: 10 }, { ProductID: "p2", Total: 300, Quantity: 30 },
    ] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 },
      { ProductID: "p2", Date: "2026-06-16T00:00:00", Quantity: 30 },
    ] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "BIN1" },
      { ProductID: "p2", SKU: "SKU2", CardID: "c2", Quantity: 30, Date: "2026-06-16T00:00:00", LocationID: "L2", Location: "BIN2" },
    ] }],
    InventoryMovements: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 140 },   // goods (SR 있음)
      { ProductID: "p2", Date: "2026-06-16T00:00:00", COGS: 420 },   // goods
      { ProductID: "p1", Date: "2026-06-12T00:00:00", COGS: 22.5 },  // landed (SR 없는 앞선 날짜)
      { ProductID: "p2", Date: "2026-06-12T00:00:00", COGS: 67.5 },  // landed
    ],
    ManualJournals: [{ Reference: "16667", Amount: 90, IsSystem: false }],
  };
  const r = call(det);
  const goods = r.rows.filter((x) => x.cost_kind === "goods");
  const landed = r.rows.filter((x) => x.cost_kind === "landed");
  const g1 = goods.find((x) => x.sku === "SKU1");
  const l1 = landed.find((x) => x.sku === "SKU1");
  ok("① PO-00853 모양 (goods 2 + landed 2 · 합계 일치 · 날짜 소급 유지)",
    r.disposition === "processed" && goods.length === 2 && landed.length === 2
    && g1.amount === 140 && g1.unit_cost === 14 && g1.occurred_on === "2026-06-15"
    && g1.fx_rate === 1.4 && g1.amount_orig === 100 && g1.currency_orig === "USD"
    && l1.amount === 22.5 && l1.occurred_on === "2026-06-12"   // ⚠️ landed 는 IM 날짜 그대로(입고일로 끌어오지 않는다)
    && l1.fx_rate === null && l1.amount_orig === null
    && l1.raw.alloc.mj_user_lines[0].reference === "16667"
    && !r.warnMergedLanded,
    JSON.stringify({ d: r.disposition, g: goods.length, l: landed.length, w: r.warnings }));
}
// ② 재평가 상쇄 — +A/−A/+B 세 행 → 순액 B (PO-00005 실측 모양)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 2173.366402, Quantity: 100 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2025-11-03T00:00:00", Quantity: 100 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 100, Date: "2025-11-03T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [
      { ProductID: "p1", Date: "2025-11-03T00:00:00", COGS: 2173.366080 },
      { ProductID: "p1", Date: "2025-11-03T00:00:00", COGS: -2173.366080 },
      { ProductID: "p1", Date: "2025-11-03T00:00:00", COGS: 2173.366402 },
    ],
  };
  const r = call(det);
  ok("② 재평가 +A/−A/+B → 순액 B", r.disposition === "processed" && r.rows.length === 1
    && r.rows[0].amount === 2173.366402 && r.rows[0].raw.im.im_rows === 3,
    JSON.stringify(r.rows.map((x) => x.amount)));
}
// ③ landed 를 여러 입고일·여러 bin 에 수량 비례 (6:4 → 6 CAD : 4 CAD · occurred_on = IM 날짜)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 6 },
      { ProductID: "p1", Date: "2026-06-16T00:00:00", Quantity: 4 },
    ] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 6, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "BIN-A" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 4, Date: "2026-06-16T00:00:00", LocationID: "L2", Location: "BIN-B" },
    ] }],
    InventoryMovements: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 60 },
      { ProductID: "p1", Date: "2026-06-16T00:00:00", COGS: 40 },
      { ProductID: "p1", Date: "2026-06-12T00:00:00", COGS: 10 },   // landed — 두 입고일·두 bin 에 걸친다
    ],
  };
  const r = call(det);
  const landed = r.rows.filter((x) => x.cost_kind === "landed");
  const sum = landed.reduce((s, x) => s + x.amount, 0);
  ok("③ landed 수량 비례 (6:4 · 두 bin · IM 날짜)", r.disposition === "processed" && landed.length === 2
    && landed.find((x) => x.bin === "BIN-A").amount === 6 && landed.find((x) => x.bin === "BIN-B").amount === 4
    && landed.every((x) => x.occurred_on === "2026-06-12") && sum === 10,
    JSON.stringify(landed.map((x) => [x.bin, x.amount])));
}
// ④ IsServiceOnly 스킵 — 상세 조회 전 목록 게이트 (129건 중 53건 = 41% 절약)
{
  ok("④ IsServiceOnly → skip_service (+ Simple/미지 Type 스킵)",
    listDisposition({ IsServiceOnly: true, Type: "Service Purchase", Status: "COMPLETED" }) === "skip_service"
    && listDisposition({ IsServiceOnly: false, Type: "Advanced Purchase", Status: "COMPLETED" }) === "advanced"
    && listDisposition({ IsServiceOnly: false, Type: "Simple Purchase", Status: "COMPLETED" }) === "skip_simple_unverified"
    && listDisposition({ IsServiceOnly: false, Type: "???", Status: "COMPLETED" }) === "skip_unknown_type"
    && listDisposition({ IsServiceOnly: false, Type: "Advanced Purchase", Status: "VOIDED" }) === "skip_voided");
}
// ⑤ qty=0 라인 — 건너뛰고 카운트 (unit_cost 0 나눗셈 방지)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "B1" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c0", Quantity: 0, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 100 }],
  };
  const r = call(det);
  ok("⑤ qty=0 라인 스킵 + 카운트", r.disposition === "processed" && r.zeroQtyLines === 1
    && r.rows.length === 1 && r.rows[0].amount === 100);
}
// ⑥ 자기검증 실패(PA 8 ≠ SR 10) → 문서 스킵 + 경고 (다른 문서 격리 — rows 비움)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 8, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 100 }],
  };
  const r = call(det);
  ok("⑥ PA/SR 수량 불일치 → skip_check_failed + 경고 + rows 0",
    r.disposition === "skip_check_failed" && r.rows.length === 0
    && r.warnings.some((w) => w.includes("qty mismatch")),
    JSON.stringify({ d: r.disposition, w: r.warnings }));
}
// ⑦ upsert URL — on_conflict 8키(inv_cost_uq 순서) + merge-duplicates (정적)
{
  ok("⑦ upsert on_conflict 8키 + merge-duplicates",
    src.includes('const COST_CONFLICT = "doc_type,doc_number,line_ref,warehouse,bin,sku,cost_kind,occurred_on"')
    && /rest\/v1\/inv_cost\?on_conflict=" \+ COST_CONFLICT/.test(src)
    && /writeCostRows[\s\S]{0,600}resolution=merge-duplicates/.test(src));
}
// ⑧ dry=1 에서 쓰기 0 — writeCostRows 호출이 if (commit) 블록 안 한 곳뿐 (정적)
{
  const commitStart = src.indexOf("if (commit) {");
  const commitEnd = src.indexOf("// commit 블록 끝", commitStart);
  const inside = src.slice(commitStart, commitEnd);
  const outside = src.slice(0, commitStart) + src.slice(commitEnd);
  const defs = (outside.match(/async function writeCostRows/g) ?? []).length;
  const outsideCalls = (outside.match(/writeCostRows\(/g) ?? []).length - defs;   // 정의 1곳 제외
  ok("⑧ dry 는 절대 쓰지 않는다 (호출이 commit 블록 안 1곳뿐)",
    commitStart > 0 && commitEnd > commitStart
    && (inside.match(/await writeCostRows\(/g) ?? []).length === 1
    && outsideCalls === 0
    && src.includes('const commit = url.searchParams.get("commit") === "1"'),
    JSON.stringify({ commitStart, commitEnd, outsideCalls }));
}
// ⑨ 같은 SKU 두 I&R — 회차별 환율로 배분 (PO-01130 모양: rate 1.40275 / 1.39342)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.40275, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] },
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-2", CurrencyRate: 1.39342, Lines: [{ ProductID: "p1", Total: 200, Quantity: 20 }] },
    ],
    StockReceived: [
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 }] },
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-2", Lines: [{ ProductID: "p1", Date: "2026-06-16T00:00:00", Quantity: 20 }] },
    ],
    PutAway: [
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [{ ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "B1" }] },
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-2", Lines: [{ ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 20, Date: "2026-06-16T00:00:00", LocationID: "L2", Location: "B2" }] },
    ],
    InventoryMovements: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 140.275 },
      { ProductID: "p1", Date: "2026-06-16T00:00:00", COGS: 278.684 },
    ],
  };
  const r = call(det);
  const r1 = r.rows.find((x) => x.line_ref === "c1");
  const r2 = r.rows.find((x) => x.line_ref === "c2");
  ok("⑨ 같은 SKU 두 I&R — 회차별 환율 (PO-01130 모양)",
    r.disposition === "processed" && r.rows.length === 2 && r.irUnmatchedBlocks === 0
    && r1.fx_rate === 1.40275 && r1.amount_orig === 100 && r1.amount === 140.275
    && r2.fx_rate === 1.39342 && r2.amount_orig === 200 && r2.amount === 278.684
    && r1.raw.invoice.ir === "IR-1" && r2.raw.invoice.ir === "IR-2",
    JSON.stringify({ d: r.disposition, rows: r.rows.map((x) => [x.line_ref, x.fx_rate]), w: r.warnings }));
}
// ⑩ I&R 없는 블록 → 그 블록만 스킵 — 회차의 SR·IM 도 함께 제외돼 나머지 블록은 정상 처리
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 },
      { ProductID: "p2", Date: "2026-06-16T00:00:00", Quantity: 5 },
    ] }],
    PutAway: [
      { Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [{ ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "B1" }] },
      { Status: "AUTHORISED", Lines: [{ ProductID: "p2", SKU: "SKU2", CardID: "c2", Quantity: 5, Date: "2026-06-16T00:00:00", LocationID: "L2", Location: "B2" }] },   // I&R 없음
    ],
    InventoryMovements: [
      { ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 100 },
      { ProductID: "p2", Date: "2026-06-16T00:00:00", COGS: 50 },   // 스킵 회차의 goods — 함께 제외돼야 한다
    ],
  };
  const r = call(det);
  ok("⑩ I&R 없는 블록만 스킵 — 나머지 정상 (p1 만 기표 · p2 회차 제외)",
    r.disposition === "processed" && r.rows.length === 1 && r.rows[0].sku === "SKU1"
    && r.irUnmatchedBlocks === 1 && r.blocksSkipped["putaway:ir_unmatched"] === 1
    && r.warnings.some((w) => w.includes("skip_ir_unmatched")),
    JSON.stringify({ d: r.disposition, rows: r.rows.length, ir: r.irUnmatchedBlocks, w: r.warnings }));
}
// ⑪ 두 bin 으로 갈린 goods — amount_orig 행 단위 배분 (반올림이 실제로 발생하는 값으로)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.4, TotalBeforeTax: 101.11, Lines: [{ ProductID: "p1", Total: 101.11, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 7, Date: "2026-06-15T00:00:00", LocationID: "L1", Location: "BIN-A" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 3, Date: "2026-06-15T00:00:00", LocationID: "L2", Location: "BIN-B" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-06-15T00:00:00", COGS: 141.554 }],   // = 101.11 × 1.4
  };
  const r = call(det);
  // 재계산 항등식 — AdditionalCharges 유무와 무관하게 성립하는 일반형 (⑭가 할인 케이스)
  const recalc = (x) => (x.amount_orig / x.raw.invoice.lines_total_all) * x.raw.invoice.net_total * x.fx_rate;
  const aligned = r.rows.every((x) => Math.abs(x.amount - recalc(x)) <= 0.01);
  const origSum = round6(r.rows.reduce((s2, x) => s2 + x.amount_orig, 0));
  // ⚠️ 「Σ amount_orig == lineTotal」 단언은 **전량 입고**(주문 10 = 입고 10)일 때만 성립 — 부분 입고는 ⑮
  ok("⑪ goods 두 bin — 행 단위 amount_orig (정렬 ≤0.01 · 전량 입고라 합 == lineTotal)",
    r.disposition === "processed" && r.rows.length === 2 && aligned && origSum === 101.11
    && r.rows.every((x) => x.raw.invoice.line_total_sum === 101.11),   // raw 에는 배분 전 원본 유지
    JSON.stringify(r.rows.map((x) => [x.bin, x.amount, x.amount_orig])));
}
// ⑫ SR 블록 status="DRAFT" — 정상 처리 (PO-01117 모양: DRAFT 인데 SR=PA=IM 완전 일치)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.39207, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [{ Status: "DRAFT", Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 139.207 }],
  };
  const r = call(det);
  ok("⑫ SR DRAFT 인데 수량 일치 → 정상 처리 (스킵 없음)",
    r.disposition === "processed" && r.rows.length === 1 && r.rows[0].cost_kind === "goods"
    && r.rows[0].amount === 139.207 && Object.keys(r.blocksSkipped).length === 0,
    JSON.stringify({ d: r.disposition, bs: r.blocksSkipped, w: r.warnings }));
}
// ⑬ SR 블록 VOIDED — 그 블록만 제외 (취소는 실재하지 않는다 · 안 빼면 (b)가 SR 109 vs PA 10 으로 오탐)
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "CAD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1, Lines: [{ ProductID: "p1", Total: 100, Quantity: 10 }] }],
    StockReceived: [
      { Status: "DRAFT",  Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 10 }] },
      { Status: "VOIDED", Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 99 }] },
    ],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 100 }],
  };
  const r = call(det);
  ok("⑬ SR VOIDED 블록만 제외 (sr:VOIDED · 나머지 정상)",
    r.disposition === "processed" && r.rows.length === 1 && r.rows[0].amount === 100
    && r.blocksSkipped["sr:VOIDED"] === 1,
    JSON.stringify({ d: r.disposition, bs: r.blocksSkipped, w: r.warnings }));
}
// ⑭ 인보이스 −0.5% 할인(Account=_59_) — PO-01198 모양: COGS 는 순액 기준, 원본 3값으로 재계산 가능
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.4,
      TotalBeforeTax: 199,   // = 200 − 1 (할인 반영 후 · 세전 순액 — 배분에 쓰인 값)
      Lines: [{ ProductID: "p1", Total: 200, Quantity: 10 }],
      AdditionalCharges: [{ Description: "Volume DC", Account: "_59_discount", Total: -1 }],
    }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 7, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "BIN-A" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 3, Date: "2026-08-20T00:00:00", LocationID: "L2", Location: "BIN-B" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 278.6 }],   // = 199 × 1.4
  };
  const r = call(det);
  const recalc = (x) => (x.amount_orig / x.raw.invoice.lines_total_all) * x.raw.invoice.net_total * x.fx_rate;
  const aligned = r.rows.every((x) => Math.abs(x.amount - recalc(x)) <= 0.01);
  const inv0 = r.rows[0].raw.invoice;
  ok("⑭ −0.5% 할인(_59_) — 재계산 항등식 + raw.invoice 3값",
    r.disposition === "processed" && r.rows.length === 2 && aligned
    && inv0.lines_total_all === 200 && inv0.net_total === 199
    && inv0.additional.length === 1 && String(inv0.additional[0].account).includes("_59_")
    && Math.abs(r.rows[0].amount / (r.rows[0].amount_orig * r.rows[0].fx_rate) - 0.995) < 0.0001,   // 실측의 0.994999 비율
    JSON.stringify(r.rows.map((x) => [x.bin, x.amount, x.amount_orig, x.raw.invoice.net_total])));
}
// ⑮ 부분 입고 (PO-00805 모양) — 주문 100 중 63 입고: amount_orig 은 입고 비율로 스케일된다
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.38449,
      TotalBeforeTax: 1000, Lines: [{ ProductID: "p1", Total: 1000, Quantity: 100 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 63 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 40, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "BIN-A" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 23, Date: "2026-08-20T00:00:00", LocationID: "L2", Location: "BIN-B" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 872.2287 }],   // = 1000 × 0.63 × 1.38449
  };
  const r = call(det);
  const recalc = (x) => (x.amount_orig / x.raw.invoice.lines_total_all) * x.raw.invoice.net_total * x.fx_rate;
  const aligned = r.rows.every((x) => Math.abs(x.amount - recalc(x)) <= 0.01);
  const origSum = round6(r.rows.reduce((s2, x) => s2 + x.amount_orig, 0));
  ok("⑮ 부분 입고 — Σ amount_orig == lineTotal × 0.63 · 항등식 성립",
    r.disposition === "processed" && r.rows.length === 2 && aligned
    && origSum === 630   // = 1000 × (63/100) — 잔액 몰기가 있었다면 1000 으로 부풀었을 값
    && r.rows[0].raw.invoice.line_qty_sum === 100 && r.invQtyMissing === 0,
    JSON.stringify(r.rows.map((x) => [x.bin, x.amount, x.amount_orig])));
}
// ⑯ 같은 제품 두 날짜 분할 입고 — 회귀 방지: 잔액 몰기 시절 코드는 allocate 가 (pid,date) 키마다
//    불리며 매번 lineTotal 전액을 배분해 Σ amount_orig = lineTotal × 2 가 됐다. 입고 비율 방식은
//    키와 무관하게 행별 (qty ÷ 주문수량) 이라 정확히 lineTotal 로 닫힌다.
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.4,
      TotalBeforeTax: 1000, Lines: [{ ProductID: "p1", Total: 1000, Quantity: 100 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [
      { ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 40 },
      { ProductID: "p1", Date: "2026-08-22T00:00:00", Quantity: 60 },
    ] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 40, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "B1" },
      { ProductID: "p1", SKU: "SKU1", CardID: "c2", Quantity: 60, Date: "2026-08-22T00:00:00", LocationID: "L2", Location: "B2" },
    ] }],
    InventoryMovements: [
      { ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 560 },   // = 1000 × 0.4 × 1.4
      { ProductID: "p1", Date: "2026-08-22T00:00:00", COGS: 840 },   // = 1000 × 0.6 × 1.4
    ],
  };
  const r = call(det);
  const recalc = (x) => (x.amount_orig / x.raw.invoice.lines_total_all) * x.raw.invoice.net_total * x.fx_rate;
  const aligned = r.rows.every((x) => Math.abs(x.amount - recalc(x)) <= 0.01);
  const origSum = round6(r.rows.reduce((s2, x) => s2 + x.amount_orig, 0));
  ok("⑯ 두 날짜 분할 입고 — Σ amount_orig == lineTotal (2× 이중 계상 없음)",
    r.disposition === "processed" && r.rows.length === 2 && aligned
    && origSum === 1000   // ⚠️ 잔액 몰기 회귀가 살아나면 2000 이 나온다
    && new Set(r.rows.map((x) => x.occurred_on)).size === 2,
    JSON.stringify(r.rows.map((x) => [x.occurred_on, x.amount, x.amount_orig])));
}
// ⑰ 세금 있는 인보이스 (PO-00967 모양: 국내 매입 HST 13%) — net_total = 세전. 옛 코드(Total 세후)면
//    ratio = 1/1.13 = 0.884956 이 나온다. 매입세액은 재고 원가가 아니다(amount 는 원래 정확했다).
{
  const det = {
    Type: "Advanced Purchase", SupplierCurrency: "USD",
    Invoice: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", CurrencyRate: 1.42,
      TotalBeforeTax: 6156, Tax: 800.28, Total: 6956.28,
      Lines: [{ ProductID: "p1", Total: 6156, Quantity: 10 }] }],
    StockReceived: [{ Status: "AUTHORISED", Lines: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", Quantity: 10 }] }],
    PutAway: [{ Status: "AUTHORISED", InvoicingAndReceivingNumber: "IR-1", Lines: [
      { ProductID: "p1", SKU: "SKU1", CardID: "c1", Quantity: 10, Date: "2026-08-20T00:00:00", LocationID: "L1", Location: "B1" },
    ] }],
    InventoryMovements: [{ ProductID: "p1", Date: "2026-08-20T00:00:00", COGS: 8741.52 }],   // = 6,156 × 1.42 (세금 미포함)
  };
  const r = call(det);
  const x = r.rows[0];
  const ratio = x.amount / ((x.amount_orig / x.raw.invoice.lines_total_all) * x.raw.invoice.net_total * x.fx_rate);
  ok("⑰ HST 13% — net_total 세전 · ratio 1 (세후 Total 이면 0.884956)",
    r.disposition === "processed" && r.rows.length === 1
    && x.raw.invoice.net_total === 6156 && x.raw.invoice.tax === 800.28
    && Math.abs(ratio - 1) < 0.0001 && r.netTotalMissing === 0,
    JSON.stringify({ ratio, nt: x.raw.invoice.net_total, tax: x.raw.invoice.tax }));
}

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL INV-COST TESTS PASSED");
