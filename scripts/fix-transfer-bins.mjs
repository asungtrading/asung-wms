// 트랜스퍼 출발 bin 보정 도구 (2026-08-31 — 창고 간 이동의 bin='' 행 상쇄 + 재삽입)
//
// 왜 필요한가: 수집기(inv-collect@2026-08-31.4)는 **앞으로 들어올** transfer_out 의 출발 bin 을
// WMS 픽(bin_location)으로 채우지만, **과거 행은 자가 치유가 안 된다** — Reference 를 나중에
// 채워도 다음 회차가 새 bin 행을 추가할 뿐 옛 bin='' 행이 남아 **이중 계상**된다.
// ⇒ 이 도구가 옛 행을 상쇄(④)하고, 필요하면 올바른 bin 으로 재삽입(⑤)한다.
// 📌 과거 5문서(TR-04173·74·75·04330·04331) 정정에도, 앞으로 매니저가 Reference 를
//    빠뜨렸을 때(아침 점검 ⑧)에도 같은 도구를 쓴다.
//
// 사용:
//   node scripts/fix-transfer-bins.mjs                 # 계획만 출력 (아무것도 안 쓴다)
//   node scripts/fix-transfer-bins.mjs --doc TR-04330  # 한 문서만
//   node scripts/fix-transfer-bins.mjs --commit        # 실제 쓰기 (Caleb 만)
// 필요 env: SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY · CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY
//   (Reference 는 원장 raw 에 없어 Cin7 상세를 문서당 1콜 읽는다 — TaskID 는 원장 doc_task_id)
//
// 동작 (지시서 §3):
//   ① 대상 = inv_ledger: doc_type='transfer' · event_type='transfer_out' ·
//      warehouse<>'IN_TRANSIT' · bin='' · source='cin7'
//      ⚠️ 그중 **창고 간 이동만** — EF 와 같은 판정(isCrossWarehouseTransfer · det.From/To GUID 를
//      창고로 풀어 비교). 같은 창고(내부 풋어웨이 TR-04183~98 등)는 해결이 구조적으로 안 되는
//      소음이므로 목록에서 제외하고 skip_same_warehouse 로 카운트만 한다.
//   ② 해결 = inv-collect 의 parseTransferRefSOs/buildTransferBinMap/resolveTransferBin/
//      loadTransferBinMap/isCrossWarehouseTransfer 를 **원문 추출**해 그대로 쓴다 — 로직 두 벌 금지
//   ③ 계획 출력 — --commit 없으면 여기서 끝
//   ④ 상쇄: 해결된 행마다 source='manual' · event_type='manual_reversal' ·
//      line_ref=<원본>:binfix · qty=−원본 (FINAL-SALE 상쇄 관례)
//   ⑤ 재삽입: 같은 사건을 올바른 bin 으로 — source='manual' · line_ref=<원본>:binfixed
//      (⚠️ cin7 재수집과 키가 겹치면 안 된다 — 접미가 그 방어다)
//      ⚠️ 단, **cin7 재수집이 이미 올바른 bin 행을 썼으면 ⑤ 를 건너뛴다**(재삽입하면 이중 계상 —
//      IN TRANSIT 문서는 커서 위라 매 회차 재수집되므로 배포 뒤에는 이 경우가 기본이다).
//   ⑥ raw 에 근거 SO·원본 행 id·원본 bin(='')·해결 bin 을 담는다
// ⚠️ ④⑤는 한 문서 안에서 한 번에 계산해 함께 쓴다 — 상쇄만 하면 재고가 사라진다.
// ⚠️ 재실행 안전은 **접미 무관**이다: 같은 원본(doc_number·기본 line_ref·warehouse·sku·occurred_on)에
//    source='manual' 행이 **하나라도** 있으면 건너뛰고 skip_already_reversed 로 표시한다.
//    [실측 2026-08-31 계획 모드] :binfix 만 보던 판정이 TR-04175 를 195줄 전부 대상으로 잡았다 —
//    그중 138줄은 08-25 에 Cin7 에서 삭제돼 **이미 :reversal 로 상쇄된 라인**이라(manual 276행),
//    보정하면 중복 상쇄 + 삭제된 라인 되살리기가 된다(bin='' 에 +Q 유령 · 실제 bin 에 −Q 허위 차감).
// ⚠️ --commit 없으면 아무것도 쓰지 않는다.

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const COMMIT = process.argv.includes("--commit");
const docArgIdx = process.argv.indexOf("--doc");
const ONLY_DOC = docArgIdx > -1 ? process.argv[docArgIdx + 1] : null;
// 기준선 날짜 — 잔고 규칙(2026-09-01)의 스냅샷 키(<since>-initial) 파생.
// cron URL 의 since=2026-08-20 과 같은 끈이다 — 재기준선 때 --since 로 넘겨라.
const sinceArgIdx = process.argv.indexOf("--since");
const SINCE = sinceArgIdx > -1 ? process.argv[sinceArgIdx + 1] : "2026-08-20";
const FIXER = "fix-transfer-bins@2026-09-01.1";

const SB_URL = process.env.SUPABASE_URL ?? "";
const SB_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const C7_ACC = process.env.CIN7_ACCOUNT_ID ?? "";
const C7_KEY = process.env.CIN7_APPLICATION_KEY ?? "";
if (!SB_URL || !SB_KEY) { console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY env 가 필요하다"); process.exit(1); }
if (!C7_ACC || !C7_KEY) { console.error("CIN7_ACCOUNT_ID / CIN7_APPLICATION_KEY env 가 필요하다 (Reference 조회용)"); process.exit(1); }

const sbHeaders = { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" };
async function sbGet(path) {
  const r = await fetch(SB_URL + "/rest/v1/" + path, { headers: sbHeaders });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbGetAll(path) {   // Range 페이지네이션 — 1000행 캡 방어 (detectMissingLines 패턴)
  const out = [];
  for (let off = 0; ; off += 1000) {
    const r = await fetch(SB_URL + "/rest/v1/" + path, { headers: { ...sbHeaders, Range: off + "-" + (off + 999) } });
    if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
    const page = await r.json();
    out.push(...page);
    if (page.length < 1000) break;
  }
  return out;
}
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
async function cin7Get(path) {
  const r = await fetch("https://inventory.dearsystems.com/ExternalApi/v2" + path, {
    headers: { "api-auth-accountid": C7_ACC, "api-auth-applicationkey": C7_KEY, "Content-Type": "application/json" },
  });
  if (!r.ok) throw new Error("cin7Get " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}

// ── ② 해결 함수 원문 추출 (inv-collect 에서 — 로직 두 벌 금지) ──
const EF = "supabase/functions/inv-collect/index.ts";
const src = readFileSync(EF, "utf8");
function extract(name) {
  // async 함수는 "function <name>" 검색이 async 키워드를 떨어뜨린다 — async 우선 탐색
  let start = src.indexOf("async function " + name);
  if (start < 0) start = src.indexOf("function " + name);
  if (start < 0) { console.error("extract 실패 — " + name); process.exit(1); }
  let depth = 0, end = start, started = false;
  for (let i = start; i < src.length; i++) {
    if (src[i] === "{") { depth++; started = true; }
    else if (src[i] === "}") { depth--; if (started && depth === 0) { end = i + 1; break; } }
  }
  return src.slice(start, end);
}
const FNS = ["parseTransferRefSOs", "buildTransferBinMap", "resolveTransferBin", "loadTransferBinMap", "isCrossWarehouseTransfer", "buildBinBalances", "decideDepartureBin", "loadBinBalances"];
const dir = mkdtempSync(join(tmpdir(), "binfix-"));
const CHUNK_LINE = src.match(/^const BALANCE_SKU_CHUNK = .*$/m)[0];   // loadBinBalances 가 참조하는 모듈 상수
writeFileSync(join(dir, "resolve.ts"), CHUNK_LINE + "\n" + FNS.map(extract).join("\n") + "\nexport { " + FNS.join(", ") + " };\n");
execSync(`npx --yes esbuild ${join(dir, "resolve.ts")} --outfile=${join(dir, "resolve.mjs")} --format=esm`, { stdio: "pipe" });
const { resolveTransferBin, loadTransferBinMap, isCrossWarehouseTransfer, decideDepartureBin, loadBinBalances } = await import(join(dir, "resolve.mjs"));

// 재실행 안전 키 — **접미 무관** (테스트 ⑰ 이 원문 추출해 검증한다).
// line_ref 의 마지막 `:접미`(:reversal·:binfix·:binfixed·앞으로의 어떤 것이든)를 떼고 원본과 맞춘다
// (트랜스퍼 line_ref 는 ProductID GUID 라 콜론이 없다 — 원본에 적용해도 no-op).
// doc_type·event_type 은 키에 안 넣는다: 대상 필터가 transfer·transfer_out 으로 고정하고,
// IN_TRANSIT leg 의 상쇄 행은 warehouse 로 배제된다. (:binfixed 재삽입 행도 이 키를 만들지만
// 그 행은 :binfix 상쇄와 항상 함께 쓰였으므로 「건너뛴다」 판정이 여전히 옳다.)
function offsetBaseKey(docNumber, lineRef, warehouse, sku, occurredOn) {
  return [docNumber, String(lineRef).replace(/:[^:]+$/, ""), warehouse, sku, occurredOn].join("\u0001");
}
// det.From/To(GUID) → {warehouse, bin, mapped} — EF resolveLoc 의 코어 최소 재현
// (resolveLoc 자체는 핸들러 클로저(locMap·unmapped 수집에 묶임)라 원문 추출이 안 된다 —
//  판정(isCrossWarehouseTransfer)은 원문 추출로 쓰고, GUID → 부모 창고 해석만 여기서 한다.
//  테스트 ⑱ 이 이 함수를 원문 추출해 검증한다.)
function locRefOf(locMap, id) {
  const hit = locMap.get(String(id ?? "").trim());
  if (!hit) return { warehouse: "UNMAPPED(" + String(id ?? "no-id") + ")", bin: "", mapped: false };
  if (!hit.parentId) return { warehouse: hit.name, bin: "", mapped: true };
  const parent = locMap.get(hit.parentId);
  if (!parent) return { warehouse: "UNMAPPED(" + hit.parentId + ")", bin: "", mapped: false };
  return { warehouse: parent.name, bin: hit.name, mapped: true };
}

// ── ① 대상 조회 ──
const filter = "doc_type=eq.transfer&event_type=eq.transfer_out&warehouse=neq.IN_TRANSIT&bin=eq.&source=eq.cin7" +
  (ONLY_DOC ? "&doc_number=eq." + encodeURIComponent(ONLY_DOC) : "");
const targets = await sbGetAll("inv_ledger?select=id,doc_number,doc_task_id,line_ref,warehouse,bin,sku,qty_delta,occurred_on,amount&" + filter + "&order=id.asc");
if (!targets.length) { console.log("대상 0행 — 창고 간 transfer_out 에 빈 bin 이 없다. 정상."); process.exit(0); }

// 재실행 안전 — 같은 원본에 source='manual' 상쇄 행이 **하나라도** 있으면 건너뛴다 (접미 무관 — 파일 상단 ⚠️).
// line_ref 패턴 필터를 걸지 않는다: :binfix 만 보면 :reversal 로 상쇄된 삭제 라인을 되살린다.
const manualRows = await sbGetAll("inv_ledger?select=doc_number,line_ref,warehouse,sku,occurred_on&doc_type=eq.transfer&source=eq.manual&order=id.asc");
const offsetKeys = new Set(manualRows.map((r) => offsetBaseKey(r.doc_number, r.line_ref, r.warehouse, r.sku, r.occurred_on)));

// 창고 지도 — det.From/To(GUID)를 창고로 풀어 창고 간 이동만 남긴다 (EF 와 같은 ref/location 축)
const locMap = new Map();
{
  let locTotal = null, locReceived = 0;
  for (let page = 1; page <= 12; page++) {
    const j = await cin7Get("/ref/location?Page=" + page + "&Limit=1000");
    if (j?.Total != null) locTotal = Number(j.Total);
    const batch = j?.LocationList ?? [];
    locReceived += batch.length;
    for (const l of batch) {
      const id = String(l?.ID ?? "").trim();
      if (id) locMap.set(id, { name: String(l?.Name ?? "").trim(), parentId: l?.ParentID ? String(l.ParentID).trim() : null });
    }
    await sleep(1200);
    if (batch.length < 1000) break;
  }
  // 맵이 잘리면 창고 간 문서가 UNMAPPED → 「같은 창고」 오판으로 **조용히 제외**된다 — 중단이 맞다 (EF 와 같은 판단)
  if (locTotal != null && locReceived < locTotal) {
    console.error("location map truncated: " + locReceived + " of " + locTotal + " — 창고 판정 불가, 중단");
    process.exit(1);
  }
}

// ── ② 문서별 해결 ──
const byDoc = new Map();
for (const t of targets) {
  let g = byDoc.get(t.doc_number);
  if (!g) { g = []; byDoc.set(t.doc_number, g); }
  g.push(t);
}
console.log("대상: " + targets.length + "행 · " + byDoc.size + "문서" + (ONLY_DOC ? " (--doc " + ONLY_DOC + ")" : ""));

const inserts = [];   // ④⑤ 행 (commit 때만 쓴다)
let planResolved = 0, planSkipAlreadyReversed = 0, planSkipSameWh = 0, planUnresolved = 0, planReinsertSkipped = 0;
for (const [docNo, rows] of byDoc) {
  const taskId = String(rows[0].doc_task_id ?? "").trim();
  if (!taskId) { console.log(`\n${docNo}: ⚠️ doc_task_id 없음 — Reference 를 못 읽는다. 전부 미해결.`); planUnresolved += rows.length; continue; }
  let det;
  try {
    det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(taskId));
    await sleep(1200);   // 분당 50콜 페이싱 — 같은 키를 EF 들이 쓴다
  } catch (e) {
    console.log(`\n${docNo}: ⚠️ Cin7 상세 조회 실패 — 건너뜀: ${String(e).slice(0, 150)}`);
    planUnresolved += rows.length;
    continue;
  }
  // 창고 간 이동만 대상 — EF 와 같은 판정 (같은 창고 = 내부 풋어웨이·bin 이동, 해결 대상 아님)
  const fromLoc = locRefOf(locMap, det?.From), toLoc = locRefOf(locMap, det?.To);
  if (!isCrossWarehouseTransfer(fromLoc, toLoc)) {
    planSkipSameWh += rows.length;
    console.log(`\n${docNo}: skip_same_warehouse — ${fromLoc.warehouse} 안 이동(내부 풋어웨이 등) · ${rows.length}행 대상 제외`);
    continue;
  }
  const reference = det?.Reference ?? null;
  const tb = await loadTransferBinMap(reference, sbGet);
  console.log(`\n${docNo}  Reference=${JSON.stringify(reference)}  SO=[${tb.sos.join(",")}]` +
    (tb.soMissing.length ? `  ⚠️ wms_orders 에 없음: ${tb.soMissing.join(",")}` : "") +
    (tb.conflicts.length ? `  ⚠️ bin 충돌 SKU: ${tb.conflicts.join(",")}` : "") +
    (tb.truncated ? "  ⚠️ wms_order_lines 1000행 캡 — 해결 불가" : ""));
  const map = tb.truncated ? null : tb.map;

  // ── 그 시점 잔고 (2026-09-01 — EF 와 같은 함수 · 판정 순서 ①~⑤) ──
  // cutoff = 그 행들의 occurred_on(출발일 · leg1 은 문서 안에서 동일) · 자기 문서 제외.
  let binBalances = null;
  try {
    const docSkus = [...new Set(rows.map((t) => String(t.sku)))];
    const cutoff = String(rows[0].occurred_on);
    const bb = await loadBinBalances(SINCE + "-initial", String(rows[0].warehouse), docSkus, cutoff, docNo, sbGet);
    binBalances = bb.balances;
    if (bb.off) console.log(`  ⚠️ 잔고 규칙 OFF (WMS 값 폴백): ${bb.off}`);
  } catch (e) {
    binBalances = null;
    console.log(`  ⚠️ 잔고 조회 실패 (WMS 값 폴백): ${String(e).slice(0, 150)}`);
  }

  // ⑤ 건너뛰기 판정용 — cin7 재수집이 이미 쓴 「올바른 bin」 행의 키 집합
  const already = await sbGetAll("inv_ledger?select=line_ref,warehouse,bin,sku&doc_type=eq.transfer&doc_number=eq." +
    encodeURIComponent(docNo) + "&event_type=eq.transfer_out&source=eq.cin7&bin=neq.&order=id.asc");
  const alreadyKeys = new Set(already.map((r) => [r.line_ref, r.warehouse, r.bin, r.sku].join("")));

  for (const t of rows) {
    if (offsetKeys.has(offsetBaseKey(t.doc_number, t.line_ref, t.warehouse, t.sku, t.occurred_on))) {
      planSkipAlreadyReversed++;   // 재실행 안전 — source='manual' 상쇄 실재 (접미 무관: :binfix·:reversal·…)
      console.log(`  ⏭ ${t.sku}  skip_already_reversed — source='manual' 상쇄 행 실재(접미 무관) · 건너뜀`);
      continue;
    }
    // 판정 = EF 와 같은 규칙(2026-09-01): 잔고 유일 → 그 칸(WMS 와 어긋나면 stale 표시) ·
    // 다중 → WMS 로 가름 · 불명 → WMS 폴백 · 애매 → 비움
    const wmsBin = resolveTransferBin(map, String(t.sku));
    const d = decideDepartureBin(binBalances ? (binBalances.get(String(t.sku)) ?? new Map()) : null, wmsBin);
    const bin = d.bin;
    if (d.stale) console.log(`  ⭐ ${t.sku}  wms_stale — 잔고(${bin})가 WMS 값(${wmsBin})을 이겼다 (유입 이후 이동 부류)`);
    if (!bin) { planUnresolved++; console.log(`  ✗ ${t.sku}  bin 미해결 (${d.ambiguous ? "잔고 다중 · WMS 로도 못 가름" : "WMS 에 없음/충돌/Reference 없음"}) — 비워둔다`); continue; }
    planResolved++;
    const rawBase = {
      reason: "transfer departure bin fix - ghost bin='' offset (2026-08-31 bin-level compare)",
      basis: d.method,   // 'balance'(잔고 유일) | 'wms'(WMS 값 — 다중 가름/폴백)
      basis_so: tb.sos, reference, original_ledger_id: t.id, original_bin: "", resolved_bin: bin,
      collector: FIXER,
    };
    // ④ 상쇄 — 원본(bin='')의 역행
    inserts.push({
      doc_type: "transfer", doc_number: t.doc_number, doc_task_id: t.doc_task_id,
      line_ref: t.line_ref + ":binfix", event_type: "manual_reversal",
      warehouse: t.warehouse, bin: "", sku: t.sku,
      qty_delta: -Number(t.qty_delta), seq_hint: -Number(t.qty_delta) > 0 ? 1 : 2,
      occurred_on: t.occurred_on, amount: t.amount == null ? null : -Number(t.amount),
      source: "manual", raw: { ...rawBase, leg: "offset of ghost bin='' row" },
    });
    // ⑤ 재삽입 — cin7 재수집이 이미 올바른 bin 행을 썼으면 건너뛴다(이중 계상 방지)
    if (alreadyKeys.has([t.line_ref, t.warehouse, bin, t.sku].join(""))) {
      planReinsertSkipped++;
      console.log(`  ✓ ${t.sku}  '' → ${bin}   (상쇄만 — cin7 재수집이 이미 올바른 bin 행을 썼다)`);
    } else {
      inserts.push({
        doc_type: "transfer", doc_number: t.doc_number, doc_task_id: t.doc_task_id,
        line_ref: t.line_ref + ":binfixed", event_type: "transfer_out",
        warehouse: t.warehouse, bin, sku: t.sku,
        qty_delta: Number(t.qty_delta), seq_hint: Number(t.qty_delta) > 0 ? 1 : 2,
        occurred_on: t.occurred_on, amount: t.amount == null ? null : Number(t.amount),
        source: "manual", raw: { ...rawBase, leg: "re-post at resolved bin" },
      });
      console.log(`  ✓ ${t.sku}  '' → ${bin}   (상쇄 + 재삽입)`);
    }
  }
}

console.log("\n── 계획 ──");
console.log(`해결 ${planResolved}행 (재삽입 생략 ${planReinsertSkipped} — cin7 행 실재) · 미해결 ${planUnresolved}행 · skip_already_reversed ${planSkipAlreadyReversed}행 · skip_same_warehouse ${planSkipSameWh}행 · 쓸 행 ${inserts.length}`);
if (!COMMIT) { console.log("\n--commit 없음 — 아무것도 쓰지 않았다. 검토 후 --commit 으로 재실행."); process.exit(0); }
if (!inserts.length) { console.log("쓸 행이 없다."); process.exit(0); }

// ── ④⑤ 쓰기 — 한 번에 (ignore-duplicates: 유니크 키가 재실행 이중 방어) ──
const LEDGER_CONFLICT = "doc_type,doc_number,line_ref,event_type,warehouse,bin,sku";
let written = 0;
for (let i = 0; i < inserts.length; i += 500) {
  const batch = inserts.slice(i, i + 500);
  const r = await fetch(SB_URL + "/rest/v1/inv_ledger?on_conflict=" + LEDGER_CONFLICT + "&select=id", {
    method: "POST",
    headers: { ...sbHeaders, Prefer: "resolution=ignore-duplicates,return=representation" },
    body: JSON.stringify(batch),
  });
  if (!r.ok) { console.error("insert 실패 " + r.status + ": " + (await r.text()).slice(0, 400)); process.exit(1); }
  written += (await r.json()).length;
}
console.log(`\n✅ ${written}행 삽입 (시도 ${inserts.length} — 차이는 재실행 중복을 유니크 키가 흡수한 것).`);
console.log("⚠️ 다음: bin 단위 대조를 다시 돌려 토론토 어긋남이 1,201 → 200 근처인지 확인할 것.");
