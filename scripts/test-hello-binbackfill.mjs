// hello EF — bin 백필 스위프 테스트 (2026-08-31 · 유입 시점 sticky 미인지 라인 재해석)
//
// 실행:  node scripts/test-hello-binbackfill.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL BIN-BACKFILL TESTS PASSED".
//
// 방식은 기존 스위트(test-invcollect-*)와 동일 — 판정 함수 2개(skuBinsQuery/primaryBinsBySku)를
// **원문 추출**해 실행하고, 스위프 블록의 배선(!inner·픽 제외·서버측 null 가드·commit 게이트·
// try/catch 격리·캡)은 정적 grep 으로 못박는다.
//
// 검증 ①~⑫:
//  ① skuBinsQuery — 종전 유입(assembleLine) URL 과 문자 단위 동일 (규칙이 갈리면 여기서 깨진다)
//  ② primaryBinsBySku — desc 정렬 입력의 SKU 별 첫 행 = assembleLine bins[0] 과 같은 선택
//  ③ 로직 두 벌 금지 — "wms_sku_bins?" 리터럴은 skuBinsQuery 안 1곳뿐, assembleLine 이 빌더 사용
//  ④ 대상 = BACKFILL_STATUSES(pending,picking) — 스위프가 VOID_ACTIVE_STATUSES 를 재사용하지 않는다
//  ⑤ !inner 임베드 필터 (빠지면 status 필터가 조용히 무력화 — 2026-08-14 실측 선례)
//  ⑥ 이미 픽된 라인 제외 (picked_base>0 대조 · 대조 실패 = 회차 전체 skip — 덜 채우는 쪽이 안전)
//  ⑦ PATCH 의 null 가드가 서버측 URL 필터 (&bin_location=is.null)
//  ⑧ commit 게이트 — dry-run 은 sbPatch 에 도달하지 않는다
//  ⑨ 블록 전체 try/catch 격리 — 스위프가 죽어도 회차는 응답까지 간다
//  ⑩ 캡(BACKFILL_MAX_LINES) 배선 + cap_hit 노출
//  ⑪ 응답 필드 5종 (backfill_candidates/filled/unresolved/skipped_picked/cap_hit)
//  ⑫ 쓰기는 bin_location·zone 두 키만 — line_flag·needs_review 무접촉

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SRC = "supabase/functions/hello/index.ts";
const src = readFileSync(SRC, "utf8");
let fails = 0;
const ok = (name, cond, detail = "") => {
  if (cond) console.log("PASS " + name);
  else { console.error("FAIL " + name + (detail ? " — " + detail : "")); fails++; }
};

function extract(name) {
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
const FNS = ["skuBinsQuery", "primaryBinsBySku"];
const dir = mkdtempSync(join(tmpdir(), "binbackfill-"));
writeFileSync(join(dir, "bb.ts"), FNS.map(extract).join("\n") + "\nexport { " + FNS.join(", ") + " };\n");
execSync(`npx --yes esbuild ${join(dir, "bb.ts")} --outfile=${join(dir, "bb.mjs")} --format=esm`, { stdio: "pipe" });
const { skuBinsQuery, primaryBinsBySku } = await import(join(dir, "bb.mjs"));

// 스위프 블록 텍스트 — 정적 검사 범위 (블록 마커부터 return json 앞까지)
const sweepStart = src.indexOf("── bin 백필 스위프 (2026-08-31 — 상단");
const sweepEnd = src.indexOf("return json({", sweepStart);
const SW = sweepStart > -1 && sweepEnd > sweepStart ? src.slice(sweepStart, sweepEnd) : "";
ok("(전제) sweep block located", SW.length > 0);

// ① 유입 URL 과 문자 단위 동일 — 이 리터럴은 2026-08-31 이전 assembleLine 의 원문이다
ok("① skuBinsQuery reproduces the intake URL byte-for-byte",
  skuBinsQuery("sku=eq.WTA00219", "toronto")
    === "wms_sku_bins?sku=eq.WTA00219&warehouse=eq.toronto&is_current=eq.true&order=available.desc"
  && skuBinsQuery('sku=in.("A","B")', "edmonton")
    === 'wms_sku_bins?sku=in.("A","B")&warehouse=eq.edmonton&is_current=eq.true&order=available.desc');

// ② SKU 별 첫 행 선택 = bins[0] (available desc 정렬 전제)
{
  const rows = [
    { sku: "A", bin: "A0101", zone: "A", available: 50 },
    { sku: "B", bin: "B0202", zone: "B", available: 30 },
    { sku: "A", bin: "A0909", zone: "A", available: 5 },   // 같은 SKU 두 번째 행 — 무시돼야
  ];
  const m = primaryBinsBySku(rows);
  ok("② first row per SKU wins (desc-sorted input = max available)",
    m.get("A")?.bin === "A0101" && m.get("B")?.bin === "B0202" && m.size === 2);
  ok("②b empty/null-safe", primaryBinsBySku([]).size === 0 && primaryBinsBySku(null).size === 0
    && primaryBinsBySku([{ bin: "X" }]).size === 0);   // sku 없는 행은 안 들어간다
}

// ③ 로직 두 벌 금지 — 테이블 리터럴은 빌더 안 1곳뿐 · assembleLine 이 빌더를 쓴다
ok("③ single source: \"wms_sku_bins?\" appears only inside skuBinsQuery",
  (src.match(/"wms_sku_bins\?"/g) ?? []).length === 1
  && src.includes('sbGet(skuBinsQuery("sku=eq." + encodeURIComponent(baseSku), warehouse))'));

// ④ 대상 status — 별도 상수 · 스위프가 VOID_ACTIVE_STATUSES 를 안 쓴다
ok("④ BACKFILL_STATUSES = pending,picking · sweep never reuses VOID_ACTIVE_STATUSES",
  src.includes('const BACKFILL_STATUSES = "pending,picking";')
  && SW.includes("BACKFILL_STATUSES")
  && !SW.includes("VOID_ACTIVE_STATUSES"));

// ⑤ !inner — 없으면 부모 잔존 + 임베드 null 로 조용히 틀린다 (2026-08-14 실측 선례)
ok("⑤ !inner embed filter on wms_orders",
  SW.includes("wms_orders!inner(status,warehouse)")
  && SW.includes("&wms_orders.status=in.(\" + BACKFILL_STATUSES + \")"));

// ⑥ 픽된 라인 제외 — picked_base>0 대조 + 실패 시 회차 skip
ok("⑥ picked lines excluded (ledger-bridge guarantee) · pick-check failure skips the whole run",
  SW.includes("picked_base=gt.0")
  && SW.includes("picked.has(Number(c.id))")
  && SW.includes("pick-check failed, sweep skipped this run"));

// ⑦ 서버측 null 가드 — PATCH URL 필터
ok("⑦ PATCH carries server-side &bin_location=is.null",
  SW.includes('sbPatch("wms_order_lines?id=eq." + c.id + "&bin_location=is.null"'));

// ⑧ commit 게이트 — dry-run 은 카운트만
{
  const gate = SW.indexOf("if (!commit) { backfillFilled++; continue; }");
  const patch = SW.indexOf("await sbPatch(");
  ok("⑧ dry-run counts only — gate sits before sbPatch", gate > -1 && patch > gate);
}

// ⑨ try/catch 격리 — 블록이 죽어도 응답은 나간다
ok("⑨ whole sweep wrapped in try/catch, failures land in errors[]",
  SW.includes("} catch (e) {")
  && SW.includes('errors.push({ order: "(bin backfill sweep)"'));

// ⑩ 캡 배선
ok("⑩ cap wired (limit=BACKFILL_MAX_LINES · cap_hit flag)",
  src.includes("const BACKFILL_MAX_LINES = 40;")
  && SW.includes('"&order=id.asc&limit=" + BACKFILL_MAX_LINES')
  && SW.includes("cand.length === BACKFILL_MAX_LINES"));

// ⑪ 응답 필드 5종
ok("⑪ response exposes the five backfill counters",
  ["backfill_candidates: backfillCandidates", "backfill_filled: backfillFilled",
   "backfill_unresolved: backfillUnresolved", "backfill_skipped_picked: backfillSkippedPicked",
   "backfill_cap_hit: backfillCapHit"].every((s) => src.includes(s)));

// ⑫ 쓰기 페이로드는 bin_location·zone 뿐 — line_flag·needs_review 무접촉
ok("⑫ write payload touches only bin_location+zone (line_flag/needs_review untouched)",
  SW.includes("{ bin_location: p.bin, zone: p.zone ?? null }")
  && (SW.match(/sbPatch\(/g) ?? []).length === 1
  && !SW.includes("line_flag:") && !SW.includes("needs_review:"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL BIN-BACKFILL TESTS PASSED");
