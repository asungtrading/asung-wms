// ============================================================
// ASUNG 재고 원장 — Edge Function: inv-cost (2026-08-27)
//   Cin7 landed cost(COGS) → inv_cost — 원장 행 단위(bin·CardID)로 배분해 담는다
//   조사 정본: docs/sessions/2026-08-27-landed-cost-investigation.md (⚠️ 다시 조사하지 말 것)
//   스키마: 20260827184936_inv_cost.sql · 방향 정본: docs/design/ims-principles.md —
//   **원가가 깨져도 재고 원장은 멀쩡해야 한다**(inv_ledger·inv-collect 무접촉 · 실패는 문서 단위 격리)
// ------------------------------------------------------------
// 무엇을 하나: purchaseList(UpdatedSince 커서 · source_key='cost') → advanced-purchase 상세 →
//   InventoryMovements(제품×날짜×COGS — 수량·SKU·bin 없음)를 (ProductID, Date)로 **합산**해
//   순액을 얻고, SR 수량으로 나눠 단위원가 → PutAway 라인(bin·CardID)에 곱해 원장 행 단위로.
//
// ⚠️⚠️ upsert 다 — 원장과 달리 append-only 가 아니다(마이그레이션 헤더가 근거 정본).
//   Cin7 은 재평가로 같은 (제품·날짜)에 +A/−A/+B 행을 추가한다 — 합산이 최종값이고,
//   우리는 그 결과를 베끼므로 재수집 = 덮어쓰기가 맞다(다시 만들 수 있는 것).
//
// ⚠️ goods/landed 판정: IM 키에 대응하는 SR 키가 있으면 goods · 없으면 landed.
//   비용은 SR 없는 날짜(입고보다 앞선 인보이스 날짜)에 뜬다 — occurred_on 은 IM 날짜 그대로.
//   ⚠️ ?since= 는 **문서 선택에만** 쓴다(skip_no_recent_receipt) — 행의 occurred_on 을 거르면
//   소급된 비용이 유실된다(조사 §7 — UpdatedSince 축과 이벤트 날짜는 독립).
//
// ⚠️ 환율은 Invoice[].CurrencyRate — 헤더 CurrencyRate 금지(PO-01130: 회차별 1.40275/1.39342).
// ⚠️ Invoice·StockReceived·PutAway 는 배열 — [0] 만 보면 틀린다(조사 §1 · PO-01130 실사고).
// ⚠️ Simple Purchase 는 미검증(2026-08-27 표본 없음) — skip_simple_unverified + 경고만.
//   상세를 부르기 **전에** 목록 Type 으로 거른다: Simple 을 advanced-purchase 로 부르면
//   200 + 빈 껍데기(조용함 — inv-collect 실측)라 부르고 나서는 못 알아챈다.
// ⚠️ 창고·bin 은 원장의 resolveLoc 와 동일 규칙(ref/location ID 맵 · 콜론 파싱 금지) —
//   값이 다르면 원장 행과 조인이 안 된다. UNMAPPED 는 commit 차단(inv-collect 와 동일).
//
// 인증·페이싱·dry/commit·커서(②-b 시각 커서·캡 보정·정밀도 필터)는 inv-collect 관례 그대로 —
//   커서 단위는 <Updated>|<문서식별자> tie-breaker(2026-08-31 결함 C 이식 · 아래 커서 절)이고
//   증상 가드 cursorStalled 가 commit 을 차단한다. 회차는 inv_collect_runs 에 source_key='cost' 로
//   남는다(하루 1회 cron 이라 응답을 볼 기회가 없다 — 가드가 울려도 테이블에 남아야 보인다).
// _shared/cin7.ts 무변(바꾸면 소비 함수 전부 재배포).
import { cin7Get, sleep } from "../_shared/cin7.ts";

const COLLECTOR_VERSION = "inv-cost@2026-08-31.1";   // 08-31.1 = 결함 C 방어 이식(커서 <Updated>|<식별자> tie-breaker + cursorStalled 증상 가드 — inv-collect 08-30.1 의 복제) + 회차 로그 inv_collect_runs(source_key=cost). 원가 계산·배분 규칙은 무변 · 이전 08-27.1 = 최초 배포
const LIST_PAGE_LIMIT = 1000;
const MAX_LIST_PAGES = 12;
const LIST_SLEEP_MS = 400;
const DETAIL_SLEEP_MS = 1200;    // 분당 50콜 — 60/60 한도의 여유분(hello·receiving·inv-collect 6잡과 키 공유)
const MAX_DETAIL_PER_RUN = 40;   // 1,200ms × 40 = 48초 < 60초 창. ⚠️ 지시서 명칭은 MAX_DETAIL_PER_DOC 이었으나
                                 //   문서당 상세는 정확히 1콜이라 실체는 **회차** 캡 — 이름만 바로잡았다(값·의미 동일)
const TIME_BUDGET_MS = 120_000;  // 150초 idle timeout 앞에서 먼저 끊는다
const INSERT_BATCH = 500;        // PostgREST 삽입도 배치 — 1,000행 캡
const COST_CONFLICT = "doc_type,doc_number,line_ref,warehouse,bin,sku,cost_kind,occurred_on";   // = inv_cost_uq 순서
const KNOWN_WAREHOUSES = new Set(["Asung Trading Inc.", "Asung - Edmonton"]);

// ── Supabase REST 헬퍼 (inv-collect 와 같은 형태 — service_role 자동주입) ──
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
// inv_cost 쓰기 — ⚠️ upsert(merge-duplicates)다. append 가 아니다(파일 상단·마이그레이션 헤더).
//   refreshed_at 을 매 행 명시해 보낸다 — merge 는 payload 에 있는 컬럼만 갱신하므로
//   DB default 에 맡기면 기존 행의 refreshed_at 이 낡은 채 남는다.
async function writeCostRows(rows: Record<string, unknown>[], runIso: string): Promise<number> {
  let written = 0;
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    const batch = rows.slice(i, i + INSERT_BATCH).map((r) => ({ ...r, refreshed_at: runIso }));
    const r = await fetch(SB_URL() + "/rest/v1/inv_cost?on_conflict=" + COST_CONFLICT, {
      method: "POST",
      headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
      body: JSON.stringify(batch),
    });
    if (!r.ok) throw new Error("sbUpsert inv_cost " + r.status + ": " + (await r.text()).slice(0, 400));
    written += batch.length;
  }
  return written;
}

// ── 계산 핵심 (pure — scripts/test-invcost.mjs 가 이 구간을 원문 추출해 검증한다) ──
const dateOnly = (s: unknown): string | null => {
  const t = String(s ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null;
};
const norm = (s: unknown) => String(s ?? "").trim().toUpperCase();
const round6 = (x: number) => Math.round(x * 1e6) / 1e6;
const QTY_EPS = 1e-6;                 // 소수 수량 실재(5.25) — 부동소수 비교 여유
const ALLOC_TOLERANCE = 0.01;         // 자기검증: 배분 합계 vs IM 순액 (지시서 명시값)
const MERGED_LANDED_TOLERANCE = 1.0;  // 자기검증(d): goods IM 이 인보이스 환산 합을 이만큼 넘으면
                                      //   비용이 같은 날짜에 섞인 것 — 경고만(오탐이 아니라 알려진 한계).
                                      //   환율 곱 반올림 오차는 라인당 ~1e-4 라 1 CAD 는 충분히 위

type CostRow = {
  doc_type: string; doc_number: string; line_ref: string; sku: string;
  warehouse: string; bin: string; occurred_on: string; cost_kind: string;
  qty: number; amount: number; unit_cost: number;
  currency_orig: string | null; amount_orig: number | null; fx_rate: number | null;
  collector: string; raw: Record<string, unknown>;
};

// 목록 레벨 disposition — 상세 조회 전에 정한다(조사 §5: IsServiceOnly 는 IM 0건 + 소속 PO 불명 —
// 129건 중 53건(41%)이라 상세 호출을 크게 아낀다). ⚠️ VOID 는 지시서에 없지만 inv-collect
// purchase 목록 게이트와 동일하게 건너뛴다 — 취소된 발주의 원가를 담을 이유가 없다.
function listDisposition(row: any): string {
  if (norm(row?.Status).includes("VOID")) return "skip_voided";
  if (row?.IsServiceOnly === true) return "skip_service";
  const t = norm(row?.Type);
  if (t.includes("ADVANCED")) return "advanced";
  if (t.includes("SIMPLE")) return "skip_simple_unverified";   // ⚠️ Simple 축(SR)은 미검증 — 생기면 그때 확인
  return "skip_unknown_type";
}

// 문서 하나의 원가 행 계산 — 조사 문서 §3(산술)·§6(사슬) 그대로.
// 자기검증에 하나라도 걸리면 rows=[] + disposition 으로 문서째 격리(다른 문서는 계속).
function buildCostRows(input: {
  docNo: string;
  det: any;
  since: string | null;   // 문서 선택 게이트 전용 — 행 필터 아님
  loc: (line: any) => { warehouse: string; bin: string; mapped: boolean };
}): {
  rows: CostRow[]; disposition: string; warnings: string[];
  goodsRows: number; landedRows: number; zeroQtyLines: number; mergedRows: number;
  warnMergedLanded: boolean; blocksSkipped: Record<string, number>; unmappedLines: number;
  irUnmatchedBlocks: number; invQtyMissing: number; netTotalMissing: number;
} {
  const { docNo, det, since, loc } = input;
  const warnings: string[] = [];
  const blocksSkipped: Record<string, number> = {};
  let zeroQtyLines = 0, unmappedLines = 0, irUnmatchedBlocks = 0, invQtyMissing = 0, netTotalMissing = 0;
  const fail = (reason: string, disposition = "skip_check_failed") => {
    warnings.push(docNo + " skipped (" + reason + ")");
    return { rows: [] as CostRow[], disposition, warnings, goodsRows: 0, landedRows: 0,
             zeroQtyLines, mergedRows: 0, warnMergedLanded: false, blocksSkipped, unmappedLines,
             irUnmatchedBlocks, invQtyMissing, netTotalMissing };
  };

  // 블록 정규화 — ⚠️ 전부 배열이다([0]만 보면 틀린다 · PO-01130 Invoice 2·SR 2·PA 2)
  const asBlocks = (v: any) => (Array.isArray(v) ? v : v ? [v] : []);
  // 화이트리스트(AUTHORISED)는 **PutAway 만** — 확정 축이므로 원장 수집과 같은 부분집합을 본다
  // (원가 행은 AUTHORISED PA 로 만든 원장 행에 붙어야 한다).
  // ⚠️ SR 블록은 화이트리스트를 걸지 않는다 — VOIDED 만 제외 (2026-08-27 정정):
  //   [실측] SR status="DRAFT" 인데 데이터가 완전히 정확하다 — PO-01117 SR qty 8,664 = PA 8,664 ·
  //   29,548.45 × 1.39207 = 41,133.51 = IM 순액(오차 0 · 헤더는 StockReceivedStatus=AUTHORISED ·
  //   FULLY RECEIVED) / PO-00896 동일 패턴(PARTIALLY RECEIVED — IM 이 인보이스 일부만 덮는 것은 정상).
  //   AUTHORISED 화이트리스트가 dry 첫 회차에서 skip_check_failed 8건(전부 "SR 0 vs PA N")을
  //   만들었다 — 물건이 안 들어온 게 아니라 우리가 SR 블록을 버린 것이다. SR 의 Status 는
  //   stock receiving 워크플로 상태지 재고 반영 여부가 아니다(asung-inv-ledger 확정 사실 —
  //   원장 수집도 Advanced 에서 SR 상태를 판정에 안 쓴다).
  const keepBlocks = (v: any, tag: string) => asBlocks(v).filter((b: any) => {
    const st = norm(b?.Status);
    if (st === "AUTHORISED") return true;
    blocksSkipped[tag + ":" + (st || "(empty)")] = (blocksSkipped[tag + ":" + (st || "(empty)")] ?? 0) + 1;
    return false;
  });
  const srBlocks = asBlocks(det?.StockReceived).filter((b: any) => {
    if (norm(b?.Status) === "VOIDED") { blocksSkipped["sr:VOIDED"] = (blocksSkipped["sr:VOIDED"] ?? 0) + 1; return false; }
    return true;   // DRAFT·NOT AVAILABLE·빈 문자열 전부 통과 — 수량이 틀리면 자기검증 (b)가 잡는다
  });
  const paBlocks = keepBlocks(det?.PutAway, "putaway");
  // Invoice 는 VOIDED 만 제외(어휘 미실측이라 화이트리스트 대신 블랙리스트 최소형 — 분포는 raw 로)
  const invBlocks = asBlocks(det?.Invoice).filter((b: any) => {
    const st = norm(b?.Status);
    if (st.includes("VOID")) { blocksSkipped["invoice:" + st] = (blocksSkipped["invoice:" + st] ?? 0) + 1; return false; }
    return true;
  });
  const im = (det?.InventoryMovements ?? []) as any[];

  // ── 인보이스 ↔ 입고 회차 대응: **InvoicingAndReceivingNumber(I&R)** 로 맞춘다 (2026-08-27 정정) ──
  //   Invoice[]·StockReceived[]·PutAway[] 세 배열 모두에 이 필드가 있다(조사 §1 응답 구조) —
  //   WMS 의 Apply to Cin7 이 하나로 유지하는 바로 그 축이다.
  //   ~~제품이 한 인보이스에만 나오면 그것, 둘 이상이면 문서 스킵(skip_invoice_ambiguous)~~ 폐기 —
  //   같은 SKU 가 두 입고 회차에 걸치면(분할 입고의 가장 흔한 모양 · PO-01130) 문서 전체를 버렸다.
  const irOf = (b: any) => String(b?.InvoicingAndReceivingNumber ?? "").trim();
  //   raw.invoice 재계산 3값 (2026-08-27 추가 — [실측 PO-01198] 0.5% 할인(_59_)이 COGS 에 반영돼
  //   amount/(amount_orig×fx)=0.994999 인데 할인 정보가 어디에도 안 남았다. 재계산식:
  //   amount = (라인 Total ÷ lines_total_all) × net_total × fx_rate — 괄호 두 값이 없으면 불가):
  //   · lines_total_all = 전체 라인 Total 합(배분 분모 — AdditionalCharges 전)
  //   · net_total       = **Invoice.TotalBeforeTax** (AdditionalCharges 반영 후 · 배분에 쓰인 순액)
  //     ⚠️ Total(세후)이 아니다 — [실측 PO-00967] 국내 매입은 HST 13% 가 붙어 Total 을 쓰면
  //     재계산 ratio = 0.884956(=1/1.13)로 어긋난다. 그동안 안 보인 이유: 수입 PO 는
  //     TaxRule="Zero-rated (Purchase)" 라 Tax=0. 저장 amount 는 정확하다(매입세액은 재고
  //     원가가 아니다 — 6,156 × 1.42 = 8,741.52 실측) — 틀린 것은 감사용 net_total 하나였다.
  //     tax 도 함께 남긴다(왜 Total 과 다른지 나중에 알 수 있게). TotalBeforeTax 가 없으면
  //     **null + net_total_missing 카운트** — Total 로 대체하지 않는다(잘못된 축으로 조용히
  //     채우느니 비워두는 게 낫다).
  //   · additional      = AdditionalCharges 요약 — ⚠️ Account 가 재고 여부를 가른다(_59_ 재고 · 그 외 손익)
  const invoiceByIr = new Map<string, { idx: number; rate: number; linesByPid: Map<string, { total: number; qty: number }>;
    linesTotalAll: number; netTotal: number | null; tax: number | null;
    additional: { description: unknown; account: unknown; total: unknown }[] }>();
  let invLinesTotalCad = 0;   // 자기검증 (d)의 기대값 — Σ(인보이스 라인 Total 합 × 그 인보이스 CurrencyRate)
  for (let idx = 0; idx < invBlocks.length; idx++) {
    const inv = invBlocks[idx];
    const rate = Number(inv?.CurrencyRate ?? 0);   // ⚠️ 회차별 환율 — 헤더 CurrencyRate 금지
    const linesByPid = new Map<string, { total: number; qty: number }>();
    let linesTotalAll = 0;
    for (const line of (inv?.Lines ?? []) as any[]) {
      const pid = String(line?.ProductID ?? "").trim();
      const total = Number(line?.Total ?? 0);
      linesTotalAll += total;   // 배분 분모 — pid 없는 라인도 Cin7 분모에는 들어간다
      if (!pid) continue;
      invLinesTotalCad += total * (rate || 1);
      const cur = linesByPid.get(pid) ?? { total: 0, qty: 0 };
      cur.total += total;
      cur.qty += Number(line?.Quantity ?? 0);   // amount_orig 입고 비율의 분모(주문수량) — PO-00805 정정
      linesByPid.set(pid, cur);
    }
    const ir = irOf(inv);
    if (!ir) continue;   // I&R 없는 인보이스는 대응 불가 — PA 쪽이 짝을 못 찾으면 그 블록이 스킵된다
    if (invoiceByIr.has(ir)) { warnings.push(docNo + ": duplicate invoice I&R '" + ir + "' - first one kept"); continue; }
    if (inv?.TotalBeforeTax == null) netTotalMissing++;
    invoiceByIr.set(ir, {
      idx, rate, linesByPid,
      linesTotalAll: round6(linesTotalAll),
      netTotal: inv?.TotalBeforeTax == null ? null : Number(inv.TotalBeforeTax),
      tax: inv?.Tax == null ? null : Number(inv.Tax),
      additional: ((inv?.AdditionalCharges ?? []) as any[]).map((c) => ({
        description: c?.Description ?? null, account: c?.Account ?? null, total: c?.Total ?? null })),
    });
  }
  // PA 블록 분류 — 짝 없는 블록은 **그 블록만** 건너뛴다(skip_ir_unmatched · 문서 전체를 버리지 않는다).
  //   ⚠️ 그 회차의 SR 수량·IM 순액도 함께 제외해야 나머지 회차가 산다 — 안 빼면 자기검증 (b)
  //   (PA↔SR 수량)가 문서를 통째로 죽이고, 그 회차의 goods IM 이 SR 짝을 잃어 landed 로 오분류돼
  //   남은 라인에 번진다. 회차의 키 = 스킵된 PA 블록 라인들의 (ProductID, Date) — I&R 없는
  //   블록도 이 키로 제외할 수 있다(SR 블록을 I&R 로 다시 찾을 필요가 없다).
  const keptPa: any[] = [];
  const excludedRoundKeys = new Set<string>();
  for (const b of paBlocks) {
    const ir = irOf(b);
    if (ir && invoiceByIr.has(ir)) { keptPa.push(b); continue; }
    irUnmatchedBlocks++;
    blocksSkipped["putaway:ir_unmatched"] = (blocksSkipped["putaway:ir_unmatched"] ?? 0) + 1;
    let keyCount = 0;
    for (const line of (b?.Lines ?? []) as any[]) {
      const pid = String(line?.ProductID ?? "").trim();
      const d = dateOnly(line?.Date);
      if (pid && d) { excludedRoundKeys.add(pid + "\u0001" + d); keyCount++; }
    }
    warnings.push(docNo + ": PutAway block " + (ir ? "I&R '" + ir + "' has no matching invoice" : "without I&R")
      + " - block skipped (skip_ir_unmatched), " + keyCount + " (product,date) key(s) excluded from SR/IM");
  }

  // ── 2) SR 수량 맵 (ProductID, Date) — 스킵된 I&R 회차의 키는 제외 ──
  const srQty = new Map<string, number>();          // "pid\u0001date" → qty 합
  const srQtyByPid = new Map<string, number>();
  const srDates: string[] = [];
  for (const b of srBlocks) {
    for (const line of (b?.Lines ?? []) as any[]) {
      const pid = String(line?.ProductID ?? "").trim();
      const d = dateOnly(line?.Date);
      const q = Number(line?.Quantity ?? 0);
      if (!pid || !d) return fail("SR line without ProductID/Date");
      const k = pid + "\u0001" + d;
      if (excludedRoundKeys.has(k)) continue;   // 짝 없는 회차 — PA·SR·IM 세 축에서 함께 뺀다
      srQty.set(k, (srQty.get(k) ?? 0) + q);
      srQtyByPid.set(pid, (srQtyByPid.get(pid) ?? 0) + q);
      srDates.push(d);
    }
  }

  // ── 문서 게이트 7: SR 날짜가 전부 since 이하 = 기초 스냅샷에 녹은 물량(원장에 대응 행 없음) ──
  //   첫 시딩에서 이것이 다수인 것이 정상이다 — 8/20 에 회계가 129건을 일괄 마감(상태만 변경).
  if (since && srDates.length && srDates.every((d) => d <= since)) {
    return { rows: [], disposition: "skip_no_recent_receipt", warnings, goodsRows: 0, landedRows: 0,
             zeroQtyLines, mergedRows: 0, warnMergedLanded: false, blocksSkipped, unmappedLines,
             irUnmatchedBlocks, invQtyMissing, netTotalMissing };
  }

  // ── 1) IM 순액 맵 — ⚠️ 같은 (pid,date)에 행이 여럿(재평가 상쇄 +A/−A/+B) → 반드시 합산 ──
  const imNet = new Map<string, { net: number; imRows: number }>();
  for (const m of im) {
    const pid = String(m?.ProductID ?? "").trim();
    const d = dateOnly(m?.Date);
    const cogs = Number(m?.COGS ?? 0);
    if (!pid || !d || !isFinite(cogs)) return fail("IM row without ProductID/Date/COGS");
    const k = pid + "\u0001" + d;
    if (excludedRoundKeys.has(k)) continue;   // 짝 없는 I&R 회차의 goods — SR 과 함께 제외(landed 오분류 방지)
    const cur = imNet.get(k) ?? { net: 0, imRows: 0 };
    cur.net += cogs; cur.imRows++;
    imNet.set(k, cur);
  }

  // ── PutAway 라인 (bin·CardID — 원장 line_ref 와 잇는 축) ──
  type PaLine = { pid: string; sku: string; cardId: string; qty: number; date: string; wh: string; bin: string; ir: string };
  const paLines: PaLine[] = [];
  const paQtyByPidDate = new Map<string, number>();
  const paQtyByPid = new Map<string, number>();
  for (const b of keptPa) {   // 짝 있는 I&R 블록만 — 스킵 블록의 회차는 SR·IM 에서도 함께 뺐다
    for (const line of (b?.Lines ?? []) as any[]) {
      const q = Number(line?.Quantity ?? 0);
      if (q === 0) { zeroQtyLines++; continue; }   // 자기검증: qty=0 은 unit_cost 계산 불가 — 건너뛰고 카운트
      const pid = String(line?.ProductID ?? "").trim();
      const d = dateOnly(line?.Date);
      const cardId = String(line?.CardID ?? "").trim();
      if (!pid || !d) return fail("PA line without ProductID/Date");
      if (!cardId) return fail("PA line without CardID (line_ref would collide)");
      const l = loc(line);
      if (!l.mapped) unmappedLines++;
      const k = pid + "\u0001" + d;
      // 스킵된 회차와 (제품,날짜)가 겹치면 IM 순액을 회차별로 가를 수 없다 — 문서째 격리(드묾)
      if (excludedRoundKeys.has(k)) return fail("kept round overlaps an unmatched-I&R round on (product,date) " + pid + " @ " + d);
      paLines.push({ pid, sku: String(line?.SKU ?? "").trim(), cardId, qty: q, date: d, wh: l.warehouse, bin: l.bin, ir: irOf(b) });
      paQtyByPidDate.set(k, (paQtyByPidDate.get(k) ?? 0) + q);
      paQtyByPid.set(pid, (paQtyByPid.get(pid) ?? 0) + q);
    }
  }

  // ── 자기검증 (b) PutAway 수량 합 == SR 수량 합 (제품별) ──
  for (const pid of new Set([...srQtyByPid.keys(), ...paQtyByPid.keys()])) {
    const s = srQtyByPid.get(pid) ?? 0, p = paQtyByPid.get(pid) ?? 0;
    if (Math.abs(s - p) > QTY_EPS) return fail("PA/SR qty mismatch for " + pid + ": SR " + s + " vs PA " + p);
  }
  // ── 자기검증 (c) PutAway 날짜 == SR 날짜 ([실측 PO-00853] 불일치 0건) ──
  for (const k of new Set([...srQty.keys(), ...paQtyByPidDate.keys()])) {
    if (!srQty.has(k) || !paQtyByPidDate.has(k)) {
      return fail("PA/SR date mismatch on key " + k.replace("\u0001", " @ "));
    }
  }

  // ── 3) goods / landed 판정 — SR 키가 있으면 goods, 없으면 landed ──
  const goodsKeys: string[] = [], landedKeys: string[] = [];
  for (const k of imNet.keys()) (srQty.has(k) ? goodsKeys : landedKeys).push(k);

  // ── 4)·5) 배분 — 키 안 마지막 라인에 잔액을 몰아 합계 == IM 순액을 보장(반올림 잔차 처리) ──
  const rows: CostRow[] = [];
  const currency = String(det?.SupplierCurrency ?? "").trim() || null;
  const mjArr = Array.isArray(det?.ManualJournals) ? det.ManualJournals
    : Array.isArray(det?.ManualJournals?.Lines) ? det.ManualJournals.Lines : [];
  const mjUser = mjArr.filter((l: any) => l?.IsSystem === false)
    .map((l: any) => ({ reference: l?.Reference ?? null, amount: l?.Amount ?? null }));
  function allocate(key: string, kind: "goods" | "landed", net: number, imRows: number, lines: PaLine[]): boolean {
    const [pid, imDate] = key.split("\u0001");
    const totalQty = lines.reduce((s, l) => s + l.qty, 0);
    if (totalQty === 0) { warnings.push(docNo + " skipped (" + kind + " IM for " + pid + " @ " + imDate + " has no PutAway lines to allocate to)"); return false; }
    let allocated = 0;
    const noInvLineWarned = new Set<string>();
    // amount_orig — 행 단위 · **입고 수량 비율** (2026-08-27 재정정 · [실측 PO-00805]):
    //   amount_orig = lineTotal × (행.qty ÷ 인보이스 라인 주문수량). 분모는 그 키의 totalQty 가
    //   **아니다** — 부분 입고에서 amount 는 그 날짜 입고분만 덮는데 lineTotal 은 주문 전체 금액이라
    //   입고 비율(LOT18305: 0.6346)로 스케일해야 행과 정렬된다. ~~I&R 별 잔액 몰기~~ 제거 —
    //   부분 입고의 정답은 Σ amount_orig = lineTotal × (입고합 ÷ 주문) 이고 잔액을 몰면 깨진다.
    //   (같은 제품이 두 날짜에 걸치면 allocate 가 키마다 불려 종전 방식은 lineTotal×2 이중 계상.)
    //   행별 직접 계산으로 충분하다 — 반올림 드리프트는 행당 1e-6 이하.
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      // goods 의 배분 전 원본: 이 라인이 속한 회차(I&R)의 인보이스 — keptPa 라인은 짝이 보장된다.
      //   그 인보이스에 이 제품 라인이 없거나 주문수량이 0/없으면 원본 3필드만 null + 카운트
      //   (배분액 자체는 IM 이 정본이라 유지).
      const invRef = kind === "goods" ? (invoiceByIr.get(l.ir) ?? null) : null;
      const invLine = invRef ? (invRef.linesByPid.get(pid) ?? null) : null;
      const lineTotal = invLine ? invLine.total : null;
      if (kind === "goods" && lineTotal == null && !noInvLineWarned.has(l.ir + "|" + pid)) {
        noInvLineWarned.add(l.ir + "|" + pid);
        warnings.push(docNo + ": goods product " + pid + " has no line in invoice I&R '" + l.ir + "' - currency fields null");
      }
      const amount = i === lines.length - 1 ? round6(net - allocated) : round6(net * (l.qty / totalQty));
      allocated = round6(allocated + amount);
      let amountOrig: number | null = null;
      if (lineTotal != null) {
        if (invLine!.qty > 0) amountOrig = round6(lineTotal * (l.qty / invLine!.qty));
        else {
          invQtyMissing++;
          if (!noInvLineWarned.has(l.ir + "|" + pid + "|qty")) {
            noInvLineWarned.add(l.ir + "|" + pid + "|qty");
            warnings.push(docNo + ": invoice line qty missing/0 for " + pid + " in I&R '" + l.ir + "' - currency fields null");
          }
        }
      }
      rows.push({
        doc_type: "purchase", doc_number: docNo, line_ref: l.cardId, sku: l.sku,
        warehouse: l.wh, bin: l.bin,
        occurred_on: kind === "goods" ? l.date : imDate,   // landed 는 IM 날짜 그대로(소급 유지)
        cost_kind: kind, qty: l.qty, amount, unit_cost: round6(amount / l.qty),
        currency_orig: amountOrig != null ? currency : null,
        amount_orig: amountOrig,                           // 행 단위 · 입고 비율 — Σ = lineTotal × (입고합 ÷ 주문수량)
        fx_rate: amountOrig != null ? invRef!.rate : null, // ⚠️ 회차별 환율 — I&R 로 맞춘 그 인보이스의 값
        collector: COLLECTOR_VERSION,
        raw: {
          im: { product_id: pid, date: imDate, net: round6(net), im_rows: imRows },
          alloc: kind === "goods"
            ? { rule: "unit = im_net / sr_qty; amount = unit x pa_line_qty (remainder on last)", sr_qty: srQty.get(key) ?? null }
            : { rule: "qty-proportional across ALL PutAway lines of the product (remainder on last)", pa_total_qty: totalQty, mj_user_lines: mjUser },
          invoice: invRef ? { ir: l.ir, idx: invRef.idx, rate: invRef.rate, line_total_sum: lineTotal,
                              line_qty_sum: invLine ? invLine.qty : null,
                              lines_total_all: invRef.linesTotalAll, net_total: invRef.netTotal,
                              tax: invRef.tax, additional: invRef.additional } : null,
          collector: COLLECTOR_VERSION,
        },
      });
    }
    // 자기검증 (a) 배분 합계 == IM 순액 (잔액 몰기로 보장되지만 NaN·오버플로 방어로 재확인)
    if (Math.abs(allocated - net) > ALLOC_TOLERANCE || !isFinite(allocated)) {
      warnings.push(docNo + " skipped (allocation sum " + allocated + " != IM net " + net + " for " + pid + " @ " + imDate + ")");
      return false;
    }
    return true;
  }
  let goodsRows = 0, landedRows = 0, goodsNetTotal = 0;
  for (const k of goodsKeys) {
    const { net, imRows } = imNet.get(k)!;
    goodsNetTotal += net;
    const [pid, d] = k.split("\u0001");
    const before = rows.length;
    // goods: 단위원가 = IM순액 ÷ SR수량 → 같은 (pid,date)의 PA 라인에 수량 곱 = 수량 비례와 동치
    if (!allocate(k, "goods", net, imRows, paLines.filter((l) => l.pid === pid && l.date === d))) return fail("goods allocation failed");
    goodsRows += rows.length - before;
  }
  for (const k of landedKeys) {
    const { net, imRows } = imNet.get(k)!;
    const pid = k.split("\u0001")[0];
    const before = rows.length;
    // landed: 그 제품의 PA 라인 **전체**에 수량 비례(여러 입고일·여러 bin 에 걸칠 수 있다)
    if (!allocate(k, "landed", net, imRows, paLines.filter((l) => l.pid === pid))) return fail("landed allocation failed");
    landedRows += rows.length - before;
  }

  // ── 자기검증 (d) goods IM 순액 ≈ 인보이스 라인 환산 합 — 크게 초과 = 비용이 입고일에 섞임 ──
  //   분리할 수 없으므로 경고만 하고 goods 로 담는다. 오탐이 아니라 알려진 한계다(지시서 2-d 6).
  const warnMergedLanded = goodsNetTotal - invLinesTotalCad > MERGED_LANDED_TOLERANCE;
  if (warnMergedLanded) {
    warnings.push(docNo + ": goods IM net " + round6(goodsNetTotal) + " exceeds invoice-line CAD sum " +
      round6(invLinesTotalCad) + " - cost likely merged into a receipt date (warn_merged_landed, kept as goods)");
  }

  // ── 유니크 키 중복 합산 — upsert 페이로드 안에서 같은 키가 두 번이면 PostgREST 가 거부한다
  //   ("cannot affect row a second time"). 0 이 아니면 CardID 유일성 가정이 깨졌다는 신호.
  const byKey = new Map<string, CostRow>();
  let mergedRows = 0;
  for (const r of rows) {
    const k = [r.doc_type, r.doc_number, r.line_ref, r.warehouse, r.bin, r.sku, r.cost_kind, r.occurred_on].join("\u0001");
    const cur = byKey.get(k);
    if (cur) {
      mergedRows++;
      cur.qty += r.qty;
      cur.amount = round6(cur.amount + r.amount);
      cur.unit_cost = round6(cur.amount / cur.qty);
    } else byKey.set(k, r);
  }
  if (mergedRows) warnings.push(docNo + ": " + mergedRows + " duplicate cost key(s) merged - CardID uniqueness assumption broken, inspect");

  return { rows: [...byKey.values()], disposition: "processed", warnings, goodsRows, landedRows,
           zeroQtyLines, mergedRows, warnMergedLanded, blocksSkipped, unmappedLines, irUnmatchedBlocks, invQtyMissing, netTotalMissing };
}
// ── 계산 핵심 끝 ──

// UpdatedSince = 커서 − 1일 (겹침 수신 — 경계 유실 방지, 중복은 upsert 가 흡수)
function minusOneDay(d: string): string {
  const t = new Date(d + "T00:00:00Z");
  t.setUTCDate(t.getUTCDate() - 1);
  return t.toISOString().slice(0, 10);
}

// ── ②-b 커서 tie-breaker (2026-08-31 결함 C 이식 — ⚠️ inv-collect 의 복제) ──
// 원본: supabase/functions/inv-collect/index.ts 「②-b 커서 tie-breaker (2026-08-30 결함 C)」 절.
// 파일이 분리돼 있어 복제가 된다 — 규칙이 바뀌면 양쪽을 함께 고칠 것.
// [실사고 2026-08-29] Cin7 플랫폼 일괄 갱신이 판매 238건의 Updated 를 밀리초까지 같은 값으로
//   올렸다(History 무기록 — 실제 거래 아님 · 반복된다: 08-07 40건 · 08-13 52건 · 08-28 238건 =
//   주 1회꼴). 동률 그룹 > 캡이면 캡 회차 커서(=마지막 처리 문서의 시각)가 그 안에서 영원히
//   제자리 = 영구 동결. 새 데이터가 없어 처음엔 조용하고, 뒤에 온 진짜 거래가 못 들어와서야
//   드러난다. [실측 2026-08-31] purchaseList 의 동률은 0 — 그러나 판매를 치는 갱신이 발주를
//   안 친다는 보장이 없고, inv-cost 는 하루 1회(cron 16)라 멈추면 더 늦게 드러난다.
// 커서 형식: <Updated>|<문서식별자> — Updated = purchaseList 의 LastUpdatedDate 원문
//   (⚠️ 발주 타임스탬프에는 Z 접미가 없다 — 문자열 그대로 다루고 절대 시각으로 파싱하지 말 것).
//   · 하위 호환 — 마이그레이션 불필요: 기존 맨 커서는 「그 시각 동률 그룹 맨 앞」으로 해석돼
//     동률 문서를 건너뛰지 않고 재처리한다(upsert 가 흡수 — 안전 방향).
//   · '|' 근거: [실측 2026-08-30] inv_ledger.doc_number 중 '|' 포함 0건 · ASCII 124.
//   · updated_since_requested 는 커서 앞 10자 — '|' 가 붙어도 앞 10자는 날짜라 무변.
type CursorCand = { updated: string | null };
function cursorDocIdent(row: any): string {
  // 목록 행의 OrderNumber → 없으면 ID 폴백 → 둘 다 없으면 "" (그 문서는 실질 tie-breaker 없이
  // 동작 — 키 "<Updated>|" 는 그 시각 동률 그룹 맨 앞 = 유실 방지). ⚠️ inv-collect 판의 SaleID
  // 폴백은 판매 전용이라 뺐다 — purchaseList 행엔 SaleID 가 없어 동작 동일.
  return String(row?.OrderNumber ?? "").trim() || String(row?.ID ?? "").trim();
}
function cursorKeyOf(updated: string | null, ident: string): string | null {
  // updated 없으면 key 도 null — 정렬 맨 앞·정밀도 필터 미적용(종전 동작 유지 = 유실 방지)
  return updated ? updated + "|" + ident : null;
}
function cursorKeyCompare(a: string | null, b: string | null): number {
  // ⚠️ 코드유닛 비교 — 정밀도 필터·커서 저장이 쓰는 < 와 같은 순서여야 한다
  //   (localeCompare 는 '|' 같은 문장부호 취급이 로케일·ICU 에 좌우된다 — 두 순서가 어긋나면
  //   문서가 유실된다). null(=Updated 없음)은 맨 앞.
  const ka = a ?? "", kb = b ?? "";
  return ka < kb ? -1 : ka > kb ? 1 : 0;
}
function countUpdatedTies(cands: CursorCand[]): number {
  // 이번 회차 후보 중 Updated 가 중복된 문서 수 — 동률 그룹의 존재를 평소에도 보이게(조기 신호)
  const freq = new Map<string, number>();
  for (const cd of cands) if (cd.updated) freq.set(cd.updated, (freq.get(cd.updated) ?? 0) + 1);
  let n = 0;
  for (const cd of cands) if (cd.updated && (freq.get(cd.updated) ?? 0) > 1) n++;
  return n;
}
// 커서 결정 + 증상 가드 — 결함 A·B·C 가 전부 「캡에 걸렸는데 커서가 안 나갔다」로 나타났다:
// 원인별 가드는 매번 사촌을 놓치므로 증상을 직접 본다. stalled 면 commit 차단(호출부 4).
// 기존 cappedNoUpdated(결함 B — 더 구체적인 진단)는 그대로 유지한다.
function decideCursor(detailCapped: boolean, lastProcessedKey: string | null, cursorBefore: string | null, runStartIso: string) {
  const cursorWouldBe = detailCapped ? (lastProcessedKey ?? cursorBefore) : runStartIso;
  const cursorStalled = detailCapped && String(cursorWouldBe ?? "") <= String(cursorBefore ?? "");
  return { cursorWouldBe, cursorStalled };
}

// ── 회차 로그 (2026-08-31 · inv_collect_runs 에 source_key='cost' 로 — ⚠️ inv-collect 의 복제) ──
// 원본: supabase/functions/inv-collect/index.ts 「회차 로그」 절(buildCollectRun/writeCollectRun ·
// 마이그레이션 20260831153314_inv_collect_runs). 파일이 분리돼 있어 복제 — 규칙 변경은 양쪽 함께.
// inv-cost 는 하루 1회(cron 16 · 04:33 UTC)라 응답을 볼 기회가 거의 없다 — 가드가 울려도
// 테이블에 남아야 아침 점검이 본다(결함 C·D 를 하루 늦게 안 이유가 정확히 그것이었다).
// ⚠️ dry 미기록(수동 조사가 기준선 오염) · 차단 회차도 기록(ok=false) ·
// ⚠️ 로그 실패가 수집을 막지 않는다 — 호출부 try/catch, 실패는 응답 collect_run_error 만.
// 매핑: inv-cost 에 없는 개념(hold_capped·skipped_unchanged·cursor_frozen_alert 응답 필드)은 null.
//   ledger_rows/inserted/insert_skipped 도 null — 실제 응답 필드는 rows_built(원가 행)·
//   rows_written(upsert 시도 행수)라 이름·의미가 달라 매핑하지 않는다(원본은 summary 에 남는다).
// summary = 응답 전체 — 단 samples 제외(행이 커진다) · warnings 는 잘린 사본으로 대체(같은 이유).
function buildCostRun(out: Record<string, unknown>, warnings: string[], durationMs: number): Record<string, unknown> {
  const num = (v: unknown) => (v == null ? null : Number(v));
  const warnCapped = warnings.slice(0, 50);   // ⚠️ 길면 앞 50개 — jsonb 행 폭주 방지
  const summary: Record<string, unknown> = {};
  for (const k of Object.keys(out)) if (k !== "samples") summary[k] = k === "warnings" ? warnCapped : out[k];
  return {
    source_key: "cost",
    ok: out.write_skipped ? false : true,
    collector: COLLECTOR_VERSION,
    detail_capped: out.detail_capped === true,
    detail_capped_reason: out.detail_capped_reason ?? null,
    detail_capped_remaining: num(out.detail_capped_remaining) ?? 0,
    hold_capped: null,                                   // ②-a 전용 개념 — inv-cost 에 없다
    cursor_before: out.cursor_before ?? null,
    cursor_after: out.cursor_after ?? out.cursor_after_would_be ?? null,
    cursor_stalled_alert: out.cursor_stalled_alert ?? null,
    cursor_frozen_alert: null,                           // 응답에 그 이름의 필드가 없다(cappedNoUpdated 는 write_skipped 로 남는다)
    list_total: num(out.list_total),
    list_received: num(out.list_received),
    pages: num(out.pages),
    truncated: out.truncated ?? null,
    list_aborted: out.list_aborted ?? null,
    candidates: num(out.candidates),
    docs_processed: num(out.docs_processed),
    detail_fetched: num(out.detail_fetched),
    ledger_rows: null,
    inserted: null,
    insert_skipped: null,
    skipped_unchanged: null,
    precision_skipped: num(out.precision_skipped),
    write_skipped: out.write_skipped ?? null,
    dispositions: out.dispositions ?? null,
    warnings: warnCapped,
    summary,
    duration_ms: durationMs,
  };
}
async function writeCollectRun(row: Record<string, unknown>): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/inv_collect_runs", {
    method: "POST",
    headers: sbHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify([row]),
  });
  if (!r.ok) throw new Error("sbInsert inv_collect_runs " + r.status + ": " + (await r.text()).slice(0, 400));
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "x-wms-cron-key, content-type" } });
    }
    // ── 인증 (fail-closed — inv-collect 동일 · WMS_CRON_SECRET 공유) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) return json({ ok: false, error: "unauthorized" }, 401);

    // ── 파라미터 (inv-collect 관례: 기본 dry · ?commit=1 이 있어야 쓴다) ──
    const url = new URL(req.url);
    const commit = url.searchParams.get("commit") === "1";
    const since = (url.searchParams.get("since") ?? "").trim() || null;          // 문서 선택 게이트 전용
    if (since && !/^\d{4}-\d{2}-\d{2}$/.test(since)) return json({ ok: false, error: "since must be YYYY-MM-DD" }, 400);
    const fromSince = (url.searchParams.get("from_since") ?? "").trim() || null; // 커서 첫 시딩(=2026-08-20 — 스냅샷 축)
    if (fromSince && !/^\d{4}-\d{2}-\d{2}$/.test(fromSince)) return json({ ok: false, error: "from_since must be YYYY-MM-DD" }, 400);
    const timeLeft = () => TIME_BUDGET_MS - (Date.now() - t0);
    const warnings: string[] = [];
    if (!since) warnings.push("NO SINCE - skip_no_recent_receipt gate inactive; pre-snapshot docs will be written (pass ?since=2026-08-20)");

    // ── 창고 맵: ref/location 전량 — 원장 resolveLoc 와 동일 규칙(inv-collect 원문 이식) ──
    const locMap = new Map<string, { name: string; parentId: string | null }>();
    let locTotal: number | null = null, locReceived = 0;
    for (let page = 1; page <= MAX_LIST_PAGES; page++) {
      const j = await cin7Get("/ref/location?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT);
      if (j?.Total != null) locTotal = Number(j.Total);
      const batch = (j?.LocationList ?? []) as any[];
      locReceived += batch.length;
      for (const l of batch) {
        const id = String(l?.ID ?? "").trim();
        if (id) locMap.set(id, { name: String(l?.Name ?? "").trim(), parentId: l?.ParentID ? String(l.ParentID).trim() : null });
      }
      if (batch.length < LIST_PAGE_LIMIT) break;
      await sleep(LIST_SLEEP_MS);
    }
    if (locTotal != null && locReceived < locTotal) {
      return json({ ok: false, error: "location map truncated: " + locReceived + " of " + locTotal, duration_ms: Date.now() - t0 }, 500);
    }
    const unexpectedWarehouses = new Map<string, number>();
    let unmappedTotal = 0;
    function resolveLoc(line: any): { warehouse: string; bin: string; mapped: boolean } {
      const key = String(line?.LocationID ?? "").trim();
      const hit = key ? locMap.get(key) : undefined;
      const markWh = (name: string) => { if (!KNOWN_WAREHOUSES.has(name)) unexpectedWarehouses.set(name, (unexpectedWarehouses.get(name) ?? 0) + 1); };
      if (hit) {
        if (!hit.parentId) { markWh(hit.name); return { warehouse: hit.name, bin: "", mapped: true }; }
        const parent = locMap.get(hit.parentId);
        if (parent) { markWh(parent.name); return { warehouse: parent.name, bin: hit.name, mapped: true }; }
      }
      unmappedTotal++;
      const fb = String(line?.Location ?? "").trim() || null;
      return { warehouse: fb ?? "UNMAPPED(" + (key || "no-id") + ")", bin: "", mapped: false };
    }

    // ── 커서 (inv_sync_state · source_key='cost' — ②-b 시각 커서와 동형) ──
    const stateRows = await sbGet("inv_sync_state?source_key=eq.cost&select=source_key,last_cursor");
    const cursorBefore: string | null = stateRows[0]?.last_cursor ?? null;
    let sinceUsed: string | null = null;
    let sinceSource: "state" | "param" | "none" = "none";
    if (cursorBefore) { sinceUsed = cursorBefore; sinceSource = "state"; }
    else if (fromSince) { sinceUsed = fromSince; sinceSource = "param"; }
    if (sinceSource === "none") warnings.push("NO CURSOR - pulling the full purchase list (pass ?from_since=2026-08-20 or seed inv_sync_state 'cost')");
    const sinceDate = sinceUsed ? (dateOnly(sinceUsed) ?? sinceUsed.slice(0, 10)) : null;
    const updatedSinceReq = sinceDate ? minusOneDay(sinceDate) : null;

    // ── 1) 목록 — purchaseList UpdatedSince 증분 ──
    let listTotal: number | null = null, listReceived = 0, pages = 0;
    const listRows: any[] = [];
    let listAborted: string | null = null;
    let rateLimited = false;
    for (let page = 1; page <= MAX_LIST_PAGES; page++) {
      if (timeLeft() < 0) { listAborted = "time"; break; }
      let j: any;
      try {
        j = await cin7Get("/purchaseList?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT +
          (updatedSinceReq ? "&UpdatedSince=" + encodeURIComponent(updatedSinceReq) : ""));
      } catch (e: any) {
        if (Number(e?.status) === 429) { rateLimited = true; listAborted = "rate_limited"; }
        else listAborted = "page_error: " + String(e?.message ?? e).slice(0, 200);
        break;
      }
      pages++;
      if (j?.Total != null) listTotal = Number(j.Total);
      const batch = (j?.PurchaseList ?? []) as any[];
      listReceived += batch.length;
      listRows.push(...batch);
      if (batch.length < LIST_PAGE_LIMIT) break;
      await sleep(LIST_SLEEP_MS);
    }
    const truncated = listTotal == null ? null : listReceived < listTotal;

    // ── 2) 목록 레벨 게이트 → 후보 (상세는 Advanced 만 · Updated 오름차순 · 정밀도 필터) ──
    const dispositions: Record<string, number> = {};
    const tally = (k: string) => { dispositions[k] = (dispositions[k] ?? 0) + 1; };
    let simpleWarned = false;
    const cands: { row: any; updated: string | null; key: string | null }[] = [];
    for (const row of listRows) {
      const d = listDisposition(row);
      if (d !== "advanced") {
        tally(d);
        if (d === "skip_simple_unverified" && !simpleWarned) {
          simpleWarned = true;
          warnings.push("Simple Purchase encountered (e.g. " + String(row?.OrderNumber ?? "?") + ") - SR-axis cost path is UNVERIFIED (2026-08-27, no specimen); skipped, verify when one appears");
        }
        continue;
      }
      const updated = String(row?.LastUpdatedDate ?? "").trim() || null;
      cands.push({ row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) });
    }
    // ⚠️ 키(<Updated>|<식별자>) 오름차순 · 코드유닛 비교 — 정밀도 필터의 < 와 같은 순서
    //   (localeCompare 금지 — 커서 tie-breaker 절 · 2026-08-31 결함 C 이식)
    cands.sort((a, b) => cursorKeyCompare(a.key, b.key));
    // 정밀도 필터 (inv-collect 결함 A 차단과 동일): 커서가 시각 정밀도면 우리 쪽에서 전체 정밀도로
    // 거른다 — 안 거르면 캡 회차 다음 회차가 같은 앞 40건만 반복(완전히 조용한 정체).
    // (2026-08-31 결함 C 이식) 비교 단위는 updated 가 아니라 키 — 맨 커서(구형·비캡 회차의
    //   runStartIso)는 같은 시각의 키보다 작아(짧은 쪽이 작다) 동률 문서가 걸러지지 않고
    //   재처리된다(upsert 흡수 — 안전 방향). key=null(Updated 없음)은 거르지 않는다(유실 방지).
    let precisionSkipped = 0;
    if (cursorBefore && cursorBefore.length > 10) {
      const kept: typeof cands = [];
      for (const cd of cands) {
        if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }
        kept.push(cd);
      }
      cands.length = 0;
      cands.push(...kept);
    }
    // 동률 관측 (결함 C 조기 신호 — 응답 updated_ties): 후보 확정(필터) 후에 센다
    const updatedTies = countUpdatedTies(cands);

    // ── 3) 상세 → 원가 행 ──
    const allRows: CostRow[] = [];
    let detailFetched = 0, docsProcessed = 0, rowsGoods = 0, rowsLanded = 0, zeroQtyLines = 0, mergedRows = 0, invoiceQtyMissing = 0, netTotalMissingAll = 0;
    let detailCapped = false, detailCapReason: string | null = null, cappedRemaining = 0;
    let lastProcessedKey: string | null = null;
    const blocksSkippedAll: Record<string, number> = {};
    const mergedLandedDocs: string[] = [];
    for (let i = 0; i < cands.length; i++) {
      if (detailFetched >= MAX_DETAIL_PER_RUN) { detailCapped = true; detailCapReason = "max_detail"; cappedRemaining = cands.length - i; break; }
      if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; cappedRemaining = cands.length - i; break; }
      const cd = cands[i];
      const id = String(cd.row?.ID ?? "").trim();
      let det: any;
      try {
        // ⚠️ 파라미터는 ID 다(TaskID 는 not found) · /purchase 는 Advanced 미지원("deprecated" 400)
        det = await cin7Get("/advanced-purchase?ID=" + encodeURIComponent(id));
        detailFetched++;
        await sleep(DETAIL_SLEEP_MS);
      } catch (e: any) {
        // 상세 오류 = 캡과 같은 정지 — 시각 커서는 재방문이 없어, 지나치면 그 문서가 조용히 유실된다
        if (Number(e?.status) === 429) { rateLimited = true; detailCapReason = "rate_limited"; }
        else { detailCapReason = "detail_error"; warnings.push("detail error " + String(cd.row?.OrderNumber ?? id) + ": " + String(e?.message ?? e).slice(0, 200)); }
        detailCapped = true;
        cappedRemaining = cands.length - i;
        break;
      }
      const docNo = String(det?.OrderNumber ?? cd.row?.OrderNumber ?? "").trim();
      const r = buildCostRows({ docNo, det, since, loc: resolveLoc });
      tally(r.disposition);
      warnings.push(...r.warnings);
      zeroQtyLines += r.zeroQtyLines;
      mergedRows += r.mergedRows;
      invoiceQtyMissing += r.invQtyMissing;
      netTotalMissingAll += r.netTotalMissing;
      for (const [k, n] of Object.entries(r.blocksSkipped)) blocksSkippedAll[k] = (blocksSkippedAll[k] ?? 0) + n;
      if (r.warnMergedLanded) mergedLandedDocs.push(docNo);
      // ⚠️ 블록 수 기준 — 다른 disposition(문서 수)과 단위가 다르다(문서는 processed 로도 함께 센다)
      if (r.irUnmatchedBlocks) dispositions.skip_ir_unmatched = (dispositions.skip_ir_unmatched ?? 0) + r.irUnmatchedBlocks;
      if (r.disposition === "processed") {
        docsProcessed++;
        rowsGoods += r.goodsRows;
        rowsLanded += r.landedRows;
        allRows.push(...r.rows);
      }
      if (cd.key) lastProcessedKey = cd.key;
    }

    // ── 커서 (inv-collect ②-b 와 동형 · 2026-08-31 결함 C 이식): 비캡 회차 = 회차 시작 시각 ·
    //    캡 회차 = 마지막 처리 문서의 키 <Updated>|<식별자> (동률 그룹 안에서도 식별자로 전진) ──
    const runStartIso = new Date(t0).toISOString();
    const { cursorWouldBe, cursorStalled } = decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso);
    // 결함 B 가드 — 「시각이 없다」만 보는 더 구체적인 진단이라 그대로 두고, cursorStalled 가
    // A·B·C 와 미래의 사촌까지 증상으로 잡는다.
    const cappedNoUpdated = detailCapped && lastProcessedKey == null;
    if (cursorStalled) warnings.push("CURSOR STALLED - capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - cost collection is frozen; commit is blocked");

    // ── 4) commit — 쓰기 성공 뒤에만 커서 전진 (실패 회차는 다음 회차가 같은 창을 다시 받는다) ──
    let rowsWritten: number | null = null;
    let writeSkipped: string | null = null;
    if (commit) {
      if (listAborted) writeSkipped = "list_aborted: " + listAborted;
      else if (truncated) writeSkipped = "list truncated";
      else if (unmappedTotal > 0) writeSkipped = "UNMAPPED location in " + unmappedTotal + " line(s) - fix map first (rows would never join the ledger)";
      else if (cappedNoUpdated) writeSkipped = "capped with no usable LastUpdatedDate - cursor would freeze";
      else if (cursorStalled) writeSkipped = "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - cost collection is frozen";
      if (!writeSkipped) {
        rowsWritten = await writeCostRows(allRows as unknown as Record<string, unknown>[], new Date().toISOString());
        await sbUpsert("inv_sync_state", "source_key", [{
          source_key: "cost",
          last_cursor: cursorWouldBe,
          last_run_at: new Date().toISOString(),
          last_ok_at: new Date().toISOString(),
          note: COLLECTOR_VERSION + " rows=" + allRows.length + (detailCapped ? " capped" : ""),
        }]);
      }
    }
    // commit 블록 끝 — ⚠️ writeCostRows 호출은 위 블록 안 한 곳뿐이다(dry 는 절대 쓰지 않는다)

    const out: Record<string, unknown> = {
      ok: true,
      mode: commit ? "commit" : "dry",
      collector_version: COLLECTOR_VERSION,
      since,
      list_total: listTotal,
      list_received: listReceived,
      pages,
      truncated,
      list_aborted: listAborted,
      rate_limited: rateLimited,
      dispositions,
      candidates: cands.length,
      precision_skipped: precisionSkipped,
      updated_ties: updatedTies,   // ⚠️ 동률 그룹 조기 신호 — 캡보다 커지면 결함 C 상황(가드가 잡는다)
      detail_fetched: detailFetched,
      detail_capped: detailCapped,
      detail_capped_reason: detailCapReason,
      detail_capped_remaining: cappedRemaining,
      docs_processed: docsProcessed,
      rows_built: allRows.length,
      rows_written: rowsWritten,
      write_skipped: writeSkipped ?? undefined,
      goods_rows: rowsGoods,
      landed_rows: rowsLanded,
      zero_qty_lines: zeroQtyLines,
      merged_rows: mergedRows,
      invoice_qty_missing_lines: invoiceQtyMissing,   // 원본 3필드 null 로 남은 goods 행(주문수량 0/없음)
      net_total_missing: netTotalMissingAll,          // TotalBeforeTax 없는 인보이스 블록 수(raw.net_total null)

      merged_landed_docs: mergedLandedDocs,          // warn_merged_landed — 알려진 한계(비용·입고 동일 날짜)
      blocks_skipped: blocksSkippedAll,
      cursor_before: cursorBefore,
      cursor_after: commit && !writeSkipped ? cursorWouldBe : cursorBefore,   // dry·차단 회차는 커서 무변
      cursor_after_would_be: cursorWouldBe,
      cursor_held_by: detailCapped ? "capped:" + detailCapReason + " - cursor held at last processed doc's cursor key" : null,
      cursor_stalled_alert: cursorStalled
        ? "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - cost collection is frozen; commit is blocked"
        : undefined,
      cursor_source: sinceSource,
      updated_since_requested: updatedSinceReq,
      unexpected_warehouses: [...unexpectedWarehouses].map(([name, hits]) => ({ name, hits })),
      unmapped_lines: unmappedTotal,
      samples: allRows.slice(0, 5),                  // 5행 전체 필드
      warnings,
      duration_ms: Date.now() - t0,
    };

    // 회차 로그 (2026-08-31 · inv_collect_runs source_key='cost' — dry 미기록 · 차단 회차도 기록 · 실패는 경고만)
    if (commit) {
      try {
        await writeCollectRun(buildCostRun(out, warnings, Date.now() - t0));
        out.collect_run_logged = true;
      } catch (e: any) {
        out.collect_run_logged = false;
        out.collect_run_error = String(e?.message ?? e).slice(0, 200);
        warnings.push("collect-run log failed (cost collection unaffected): " + out.collect_run_error);
      }
    } else out.collect_run_logged = false;
    return json(out);
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
