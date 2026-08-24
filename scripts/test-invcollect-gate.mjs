// 비재고 SKU 게이트 테스트 (2026-08-24 · FINAL-SALE 실사고 후속)
//
// 실행:  node scripts/test-invcollect-gate.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL GATE TESTS PASSED".
//
// 왜 supabase/tests(SQL)가 아닌가: 게이트는 EF(inv-collect) 안의 JS 함수(makeSink)라
// psql 로 부를 수 없다. 대신 **원본 파일에서 makeSink 를 원문 그대로 추출**해 node 로
// 실행한다 — 실행 시마다 다시 추출하므로 코드가 바뀌면 테스트가 최신 구현을 검증한다
// (deno 미설치 환경 대응 · scripts/test-caps-hook.sh 와 같은 성격의 자립 테스트).
//
// 검증 4+3:
//  [동적 — 추출 실행]
//   ① FINAL-SALE(캐시에 있음) 차단 + non_inventory_skipped/sample 기록 — SO-15097 실사고 모양
//   ② Stock 품목 통과
//   ③ 캐시 비었을 때(fail-open) 전부 통과 — 수집이 멈추지 않는 것이 설계의 핵심
//   ④ 기존 동작 무회귀 — since 경계일 제외 · 유니크 키 합산(merged_lines)
//  [정적 — 배선 grep]
//   ⑤ sink.push 호출이 정확히 2곳(②-a 공유 루프 = 조정·이동·조립 / ②-b = 판매·발주·반품)
//     — 게이트가 makeSink 안이므로 이 2곳 = 6소스 전부. 3곳 이상이면 우회 배출구 신설 의심.
//   ⑥ makeSink 호출 2곳 모두 nonStockSkus 를 전달
//   ⑦ 폴백 경고 3분기(EMPTY/STALE/UNREADABLE — 조용한 폴백 금지)와 응답 노출(non_stock_gate) 존재

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

// ── 원문 추출: function makeSink … 균형 중괄호 ──
const start = src.indexOf("function makeSink");
if (start < 0) { console.error("FAIL extract — makeSink not found"); process.exit(1); }
let depth = 0, end = start;
for (let i = start; i < src.length; i++) {
  if (src[i] === "{") depth++;
  else if (src[i] === "}") { depth--; if (depth === 0) { end = i + 1; break; } }
}
const dir = mkdtempSync(join(tmpdir(), "gate-"));
writeFileSync(join(dir, "makeSink.ts"), src.slice(start, end) + "\nexport { makeSink };\n");
execSync(`npx --yes esbuild ${join(dir, "makeSink.ts")} --outfile=${join(dir, "makeSink.mjs")} --format=esm`, { stdio: "pipe" });
const { makeSink } = await import(join(dir, "makeSink.mjs"));

const mk = (sku, qty, ref) => ({ doc_type: "sale", doc_number: "SO-15097", line_ref: ref ?? "f1:" + sku,
  event_type: "sale_out", warehouse: "Asung Trading Inc.", bin: "", sku, qty_delta: qty,
  occurred_on: "2026-08-21", seq_hint: 2, amount: null, raw: { line: {} } });
const CACHE = new Set(["FINAL-SALE", "AS91437-BLK", "OrderTotalDiscount", "AMZ00101", "AMZ00102"]);

// ① 실사고 모양 — FINAL-SALE 차단·기록
const s1 = makeSink(null, CACHE);
s1.push([mk("FINAL-SALE", -34), mk("AS12345", -5)]);
ok("① FINAL-SALE blocked", s1.rows.length === 1 && s1.rows[0].sku === "AS12345"
  && s1.stats.non_inventory_skipped === 1
  && s1.stats.non_inventory_sample[0]?.sku === "FINAL-SALE"
  && s1.stats.non_inventory_sample[0]?.doc === "SO-15097", JSON.stringify(s1.stats));

// ② Stock 통과 (①에서 함께 확인됐지만 단독으로도)
const s2 = makeSink(null, CACHE);
s2.push([mk("AS99999", -3)]);
ok("② stock SKU passes", s2.rows.length === 1 && s2.stats.non_inventory_skipped === 0);

// ③ fail-open — 빈 캐시(Set 비어 있음/미전달)면 전부 통과, 수집 무중단
const s3a = makeSink(null, new Set());
s3a.push([mk("FINAL-SALE", -34)]);
const s3b = makeSink(null, undefined);
s3b.push([mk("FINAL-SALE", -34)]);
ok("③ fail-open (empty/undefined cache passes all)",
  s3a.rows.length === 1 && s3b.rows.length === 1 && s3a.stats.non_inventory_skipped === 0);

// ④ 무회귀 — since 경계일 제외 + 같은 키 합산
const s4 = makeSink("2026-08-21", CACHE);
s4.push([mk("AS12345", -5)]);                       // occurred_on == since → 제외
ok("④a since boundary unchanged", s4.rows.length === 0 && s4.stats.since_filtered_rows === 1);
const s5 = makeSink(null, CACHE);
s5.push([mk("AS12345", -5, "same"), mk("AS12345", -7, "same")]);   // 같은 유니크 키 → 합산
ok("④b merge unchanged", s5.rows.length === 1 && s5.rows[0].qty_delta === -12 && s5.stats.merged_lines === 1);

// ── 정적 배선 검사 ──
const pushCalls = (src.match(/sink\.push\(/g) ?? []).length;
ok("⑤ sink.push exactly 2 call sites (6 sources via 2 shared loops)", pushCalls === 2, "found " + pushCalls);
const sinkCtors = (src.match(/makeSink\(since, nonStockSkus\)/g) ?? []).length;
ok("⑥ both makeSink calls pass nonStockSkus", sinkCtors === 2, "found " + sinkCtors);
ok("⑦ fallback warnings + response exposure present",
  src.includes("gate INACTIVE (run inv-sku-types EF)")      // EMPTY
  && src.includes("cache STALE")                             // STALE
  && src.includes("cache UNREADABLE")                        // UNREADABLE
  && src.includes("non_stock_gate: { skus: nonStockSkus.size, warnings: skuTypeWarnings }"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL GATE TESTS PASSED");
