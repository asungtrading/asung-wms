// 트랜스퍼 출발 bin 해결 테스트 (2026-08-31 — Reference 의 픽용 SO → WMS 픽 bin)
//
// 실행:  node scripts/test-invcollect-transferbin.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL TRANSFER-BIN TESTS PASSED".
//
// 방식은 기존 스위트와 동일 — 해결 함수 4개(parseTransferRefSOs/buildTransferBinMap/
// resolveTransferBin/loadTransferBinMap)를 **원문 추출**해 목(sbGetFn)과 함께 실행하고,
// 루프 배선(헤더 bin 우선 · 다리 2·3·4 무접촉 · try/catch)은 정적 grep 으로 못박는다.
// 보정 도구(fix-transfer-bins.mjs)는 같은 함수를 원문 추출하므로 별도 로직 검증이 필요 없다 —
// ⑩ 은 도구의 안전장치(--commit 게이트 · :binfix 재실행 안전)만 정적으로 확인한다.
//
// 검증 ①~⑩ (지시서 §5):
//  ① Reference 파싱 — 파트 번호 무시 · SO 전부 · 중복 제거
//  ② Reference 에 SO 없음 → 전부 bin='' · no_reference 경로
//  ③ SO 는 있는데 wms_orders 에 없음 → bin='' · so_missing
//  ④ ⭐ 정상 — SKU→bin 이 채워진다
//  ⑤ ⭐ 두 SO 에서 같은 SKU 가 다른 bin → 비워두고 conflict
//  ⑥ bin_location 이 빈 문자열/null → 비워둔다
//  ⑦ 헤더에 bin 이 있으면 WMS 조회를 하지 않는다(회귀)
//  ⑧ 도착 다리·IN_TRANSIT 다리 무접촉(회귀)
//  ⑨ 조회 throw → 해결만 끄고 수집 계속 · 경고만
//  ⑩ 보정 도구 — --commit 없으면 쓰기 0 · :binfix 재실행 안전 · ④⑤ 동시 · cin7 실재 시 ⑤ 생략
//  ⑪ 소멸 감지 「bin 변경」 예외 — bin 만 바뀐 행은 소멸 아님 · bin_changed 카운트
//  ⑫ line_ref 가 사라짐 → 종전대로 소멸 검출(회귀)
//  ⑬ bin 은 같고 sku 가 사라짐 → 종전대로 소멸 검출(회귀)

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SRC = "supabase/functions/inv-collect/index.ts";
const src = readFileSync(SRC, "utf8");
const tool = readFileSync("scripts/fix-transfer-bins.mjs", "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

function extract(name) {
  // async 함수는 "function <name>" 검색이 async 키워드를 떨어뜨린다 — async 우선 탐색
  let start = src.indexOf("async function " + name);
  if (start < 0) start = src.indexOf("function " + name);
  if (start < 0) { console.error("FAIL extract — " + name + " not found"); process.exit(1); }
  let depth = 0, end = start, started = false;
  for (let i = start; i < src.length; i++) {
    if (src[i] === "{") { depth++; started = true; }
    else if (src[i] === "}") { depth--; if (started && depth === 0) { end = i + 1; break; } }
  }
  return src.slice(start, end);
}
const FNS = ["parseTransferRefSOs", "buildTransferBinMap", "resolveTransferBin", "loadTransferBinMap", "partitionBinChanged"];
const dir = mkdtempSync(join(tmpdir(), "transferbin-"));
writeFileSync(join(dir, "tb.ts"), FNS.map(extract).join("\n") + "\nexport { " + FNS.join(", ") + " };\n");
execSync(`npx --yes esbuild ${join(dir, "tb.ts")} --outfile=${join(dir, "tb.mjs")} --format=esm`, { stdio: "pipe" });
const { parseTransferRefSOs, buildTransferBinMap, resolveTransferBin, loadTransferBinMap, partitionBinChanged } = await import(join(dir, "tb.mjs"));

// sbGetFn 목 — 경로에 따라 응답을 돌려준다
const mockSb = (orders, lines) => async (path) => {
  if (path.startsWith("wms_orders?")) return orders;
  if (path.startsWith("wms_order_lines?")) return lines;
  throw new Error("unexpected path: " + path);
};

// ① Reference 파싱 — 실물 다섯 문서의 형태 전부
ok("① reference parsing (parts ignored, all SOs, dedup)",
  JSON.stringify(parseTransferRefSOs("P2_(SO-15482-7,9,10,11,12 / SO-15834-1,2,3)")) === '["SO-15482","SO-15834"]'
  && JSON.stringify(parseTransferRefSOs("P1_(SO-15070-1,2,3,4,5,6,7)")) === '["SO-15070"]'
  && JSON.stringify(parseTransferRefSOs("P3_(SO-15071)")) === '["SO-15071"]'
  && JSON.stringify(parseTransferRefSOs("SO-15070 SO-15070")) === '["SO-15070"]');

// ② Reference 에 SO 없음 → map null · sos 빈 배열 (WMS 조회 자체를 안 한다)
{
  let called = 0;
  const r = await loadTransferBinMap("창고이동 8/28", async () => { called++; return []; });
  ok("② no SO in reference → null map, no WMS query", r.map === null && r.sos.length === 0 && called === 0);
  const r2 = await loadTransferBinMap(null, async () => { called++; return []; });
  ok("②b null reference → same", r2.map === null && called === 0);
}

// ③ SO 는 있는데 wms_orders 에 없음 → so_missing
{
  const r = await loadTransferBinMap("P1_(SO-99999-1)", mockSb([], []));
  ok("③ SO missing in wms_orders → null map + so_missing", r.map === null && JSON.stringify(r.soMissing) === '["SO-99999"]');
}

// ④ ⭐ 정상 — SKU→bin (BMA15710 실사고 모양)
{
  const r = await loadTransferBinMap("P1_(SO-15482-1,2,3)",
    mockSb([{ id: 7, order_number: "SO-15482" }], [{ base_sku: "BMA15710", bin_location: "E050202" }, { base_sku: "AS12345", bin_location: "F030101" }]));
  ok("④ normal: sku→bin resolved",
    resolveTransferBin(r.map, "BMA15710") === "E050202" && resolveTransferBin(r.map, "AS12345") === "F030101"
    && resolveTransferBin(r.map, "UNKNOWN-SKU") === "" && r.conflicts.length === 0 && !r.truncated);
}

// ⑤ ⭐ 두 SO 에서 같은 SKU 가 다른 bin → 비워두고 conflict
{
  const r = await loadTransferBinMap("P2_(SO-15482-7 / SO-15834-1)",
    mockSb([{ id: 7, order_number: "SO-15482" }, { id: 8, order_number: "SO-15834" }],
      [{ base_sku: "BMA15710", bin_location: "E050202" }, { base_sku: "BMA15710", bin_location: "E010101" },
       { base_sku: "AS12345", bin_location: "F030101" }, { base_sku: "AS12345", bin_location: "F030101" }]));   // 같은 bin 은 충돌 아님
  ok("⑤ conflicting bins across SOs → empty + conflict list",
    resolveTransferBin(r.map, "BMA15710") === "" && JSON.stringify(r.conflicts) === '["BMA15710"]'
    && resolveTransferBin(r.map, "AS12345") === "F030101");
}

// ⑥ bin_location 빈 문자열/null → 비워둔다
{
  const b = buildTransferBinMap([{ base_sku: "A", bin_location: "" }, { base_sku: "B", bin_location: null }, { base_sku: "", bin_location: "X" }]);
  ok("⑥ empty/null bin_location (and empty sku) never enter the map", b.map.size === 0 && b.conflicts.length === 0);
}

// (보강) 1000행 캡 → truncated · map null (잘린 맵으로 채우지 않는다)
{
  const many = Array.from({ length: 1000 }, (_, i) => ({ base_sku: "S" + i, bin_location: "B" + i }));
  const r = await loadTransferBinMap("P1_(SO-1)", mockSb([{ id: 1, order_number: "SO-1" }], many));
  ok("(보강) 1000-row cap → truncated, resolution disabled", r.truncated === true && r.map === null);
}

// ⑨(동적 절반) resolveTransferBin(null) = "" — 실패 시 비워두는 방향
ok("⑨a null map resolves to empty bin", resolveTransferBin(null, "BMA15710") === "");

// ── 정적 배선 ──
const aStart = src.indexOf("async function runSource(");
const bStart = src.indexOf("async function runDateSource(");
const A = src.slice(aStart, bStart);

// ⑦ 헤더 bin 우선 — 조회 게이트와 leg1 순서
ok("⑦ WMS lookup only when header gave no bin",
  A.includes('if (fromLoc.mapped && fromLoc.bin === "" && ((det?.Lines ?? []) as any[]).length)'));
ok("⑦b leg1 uses header bin first, WMS only as fill-in",
  A.includes("let depBin = fromLoc.bin;")
  && A.includes('if (depBin === "" && fromLoc.mapped) {')
  && A.includes("depBin = resolveTransferBin(transferBinMap, sku);"));

// ⑧ 다리 2·3·4 무접촉 (원문 그대로)
ok("⑧ legs 2·3·4 untouched",
  A.includes('rows.push(mk("transfer_in", IN_TRANSIT, "", q, dep, "2 into IN_TRANSIT departure"));')
  && A.includes('rows.push(mk("transfer_out", IN_TRANSIT, "", -q, comp, "3 out of IN_TRANSIT completion"));')
  && A.includes('rows.push(mk("transfer_in", toLoc.warehouse, toLoc.bin, q, comp, "4 to-warehouse completion"));'));

// ⑨(정적) 조회 throw → 해결만 끄고 경고 (수집 계속)
{
  const at = A.indexOf("const tb = await loadTransferBinMap(");
  const block = A.slice(A.lastIndexOf("try {", at), A.indexOf("}", A.indexOf("transfer-bin lookup failed", at)));
  ok("⑨b lookup wrapped in try/catch — disables resolution, warns only",
    at > -1 && block.includes("transferBinMap = null;") && block.includes("transfer-bin lookup failed (collection unaffected"));
}

// 응답 필드 5종 (transfer 전용)
ok("(응답) transfer_bin_* fields exposed",
  A.includes("transfer_bin_resolved: tbResolved")
  && A.includes("transfer_bin_unresolved: tbUnresolved")
  && A.includes("transfer_bin_no_reference: tbNoReference")
  && A.includes("transfer_bin_so_missing: tbSoMissing")
  && A.includes("transfer_bin_conflict: tbConflict"));

// ②③⑤(정적 절반) — 카운트 경로 배선
ok("(배선) no_reference / so_missing / conflict paths wired",
  A.includes("if (!tb.sos.length) tbPush(tbNoReference, c.number);")
  && A.includes("for (const so of tb.soMissing) tbPush(tbSoMissing, so);")
  && A.includes("for (const sk of tb.conflicts) tbPush(tbConflict, sk);"));

// ── 소멸 감지 「bin 변경」 예외 (⑪~⑬) ──
// A 키 = 원장 7키(\u0001 연결: doc_type,doc_number,line_ref,event_type,warehouse,bin,sku)
const K = (...p) => p.join("\u0001");
const bRow = (line_ref, warehouse, bin, sku) => ({ doc_type: "transfer", doc_number: "TR-04330", line_ref, event_type: "transfer_out", warehouse, bin, sku });
{
  // ⑪ 같은 라인이 bin='' → 'F020802' 로 바뀜 → 소멸 아님 · bin_changed 1
  const A = new Set([K("transfer", "TR-04330", "pid-1", "transfer_out", "Asung Trading Inc.", "F020802", "BMA15710")]);
  const r = partitionBinChanged([bRow("pid-1", "Asung Trading Inc.", "", "BMA15710")], A);
  ok("⑪ bin-only change → not missing, counted as bin_changed", r.kept.length === 0 && r.binChanged === 1);
  // 역방향(새 규칙 '' ← 옛 F020802)도 같은 판정 — bin 축 대칭
  const r2 = partitionBinChanged([bRow("pid-1", "Asung Trading Inc.", "F020802", "BMA15710")],
    new Set([K("transfer", "TR-04330", "pid-1", "transfer_out", "Asung Trading Inc.", "", "BMA15710")]));
  ok("⑪b symmetric (old bin → empty) also excused", r2.kept.length === 0 && r2.binChanged === 1);
}
{
  // ⑫ line_ref 가 사라짐(A 에 다른 line_ref 만) → 종전대로 소멸
  const A = new Set([K("transfer", "TR-04330", "pid-OTHER", "transfer_out", "Asung Trading Inc.", "F020802", "BMA15710")]);
  const r = partitionBinChanged([bRow("pid-1", "Asung Trading Inc.", "", "BMA15710")], A);
  ok("⑫ line_ref gone → still detected as missing (regression)", r.kept.length === 1 && r.binChanged === 0);
}
{
  // ⑬ bin 은 같고 sku 가 사라짐 → 종전대로 소멸
  const A = new Set([K("transfer", "TR-04330", "pid-1", "transfer_out", "Asung Trading Inc.", "F020802", "OTHER-SKU")]);
  const r = partitionBinChanged([bRow("pid-1", "Asung Trading Inc.", "F020802", "BMA15710")], A);
  ok("⑬ same bin, sku gone → still detected as missing (regression)", r.kept.length === 1 && r.binChanged === 0);
  // warehouse 가 다르면(IN_TRANSIT leg) 예외 미적용 — bin 축에만
  const r2 = partitionBinChanged([bRow("pid-1", "Asung Trading Inc.", "", "BMA15710")],
    new Set([K("transfer", "TR-04330", "pid-1", "transfer_out", "IN_TRANSIT", "F020802", "BMA15710")]));
  ok("⑬b different warehouse never excused (bin axis only)", r2.kept.length === 1 && r2.binChanged === 0);
}
// (정적) 배선 — 캡보다 앞에서 거르고, 응답 필드가 두 러너에 있다
ok("(배선) partitionBinChanged runs before caps · response field in both runners",
  src.indexOf("const part = partitionBinChanged(missing, d.keys);") < src.indexOf("missing.length > MISSING_MAX_PER_DOC")
  && (src.match(/missing_lines_bin_changed: missing \? missing\.binChanged : 0/g) ?? []).length === 2);

// ⑩ 보정 도구 — 안전장치
ok("⑩a tool: nothing written without --commit",
  tool.includes('process.argv.includes("--commit")')
  && tool.includes("if (!COMMIT) {")
  && tool.indexOf("if (!COMMIT) {") < tool.indexOf('method: "POST"'));
ok("⑩b tool: rerun-safe via existing :binfix rows",
  tool.includes("fixedKeys.has(") && tool.includes(":binfix"));
ok("⑩c tool: offset(④) and re-post(⑤) computed together, ⑤ skipped when cin7 row exists",
  tool.includes(':binfix", event_type: "manual_reversal"')
  && tool.includes(':binfixed", event_type: "transfer_out"')
  && tool.includes("alreadyKeys.has("));
ok("⑩d tool: same resolution functions extracted from EF (no second copy)",
  tool.includes('readFileSync(EF, "utf8")') && tool.includes('"parseTransferRefSOs", "buildTransferBinMap", "resolveTransferBin", "loadTransferBinMap"'));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL TRANSFER-BIN TESTS PASSED");
