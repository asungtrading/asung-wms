// 회차 로그 테스트 (2026-08-31 · inv_collect_runs — 수집 밀림 감지)
//
// 실행:  node scripts/test-invcollect-runlog.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL RUN-LOG TESTS PASSED".
//
// 방식은 test-invcollect-docstate.mjs 와 동일 — **원본에서 원문 추출** 후 node 실행:
//  (a) 매핑 순수 함수 buildCollectRun 을 추출·실행해 컬럼 매핑을 검증하고,
//  (b) 호출부 블록(// 회차 로그 마커 ~ results[key] = R;)을 그대로 잘라 async 함수로 감싸
//      목(writeCollectRun stub)과 함께 실행한다 — dry 미기록·throw 무전파를 실물 코드로 검증.
//  (c) 정적 grep 으로 배선(2곳 · results[key]=R 직전 · try/catch)을 못박는다.
//
// 검증 ①~⑧ (지시서 §5):
//  ① R 의 값이 컬럼에 그대로 매핑된다(detail_capped·hold_capped·cursor_* 포함)
//  ② dry(=commit 아님)면 쓰지 않는다 — writeCollectRun 호출 0 · collect_run_logged false
//  ③ 로그 쓰기가 throw 해도 수집이 계속된다 — collect_run_error 만 남고 예외가 안 올라간다
//  ④ write_skipped 가 있으면 ok=false
//  ⑤ hold_capped 는 ②-a(dispositions 有)만 채워지고 ②-b(無)는 null
//  ⑥ summary 에 samples 가 들어가지 않는다
//  ⑦ warnings 가 50개를 넘으면 잘린다 (컬럼 + summary 사본 양쪽)
//  ⑧ 배선 grep — 호출이 results[key] = R 직전 2곳(②-a·②-b)이고 각각 try/catch 안

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

// ── 원문 추출: function <name> … 균형 중괄호 ──
function extract(name) {
  const start = src.indexOf("function " + name);
  if (start < 0) { console.error("FAIL extract — " + name + " not found"); process.exit(1); }
  let depth = 0, end = start, started = false;
  for (let i = start; i < src.length; i++) {
    if (src[i] === "{") { depth++; started = true; }
    else if (src[i] === "}") { depth--; if (started && depth === 0) { end = i + 1; break; } }
  }
  return src.slice(start, end);
}
// 호출부 블록 추출 — 마커 주석부터 results[key] = R; 직전까지 (2곳)
function extractCallSites() {
  const marker = "// 회차 로그 (2026-08-31 · inv_collect_runs";
  const blocks = [];
  let from = 0;
  for (;;) {
    const at = src.indexOf(marker, from);
    if (at < 0) break;
    const end = src.indexOf("results[key] = R;", at);
    blocks.push(src.slice(at, end));
    from = end;
  }
  return blocks;
}

const versionLine = src.match(/const COLLECTOR_VERSION = "[^"]+";/)[0];
const dir = mkdtempSync(join(tmpdir(), "runlog-"));
const callSites = extractCallSites();
ok("⑧a exactly 2 call-site blocks, right before results[key] = R", callSites.length === 2, "found " + callSites.length);

writeFileSync(join(dir, "runlog.ts"),
  versionLine + "\n" + extract("buildCollectRun") +
  "\nexport async function runBlock(commit: any, writeCollectRun: any, buildCollectRunFn: any, key: any, R: any, warnings: any, t0: any) {\n" +
  callSites[0].replace(/buildCollectRun\(/g, "buildCollectRunFn(") +
  "\nreturn R;\n}\nexport { buildCollectRun };\n");
execSync(`npx --yes esbuild ${join(dir, "runlog.ts")} --outfile=${join(dir, "runlog.mjs")} --format=esm`, { stdio: "pipe" });
const { buildCollectRun, runBlock } = await import(join(dir, "runlog.mjs"));

// ── (a) 매핑 순수 함수 ──
const R_2a = {   // ②-a 모양 (transfer · 결함 D 발현 당시 값)
  list_total: 3990, list_received: 3990, pages: 4, truncated: false, list_aborted: null,
  cursor_before: "TR-04172", cursor_after: "TR-04172", cursor_after_would_be: "TR-04172",
  dispositions: { processed: 36, processed_nonterminal: 3, hold_capped: 120, skip_since: 200 },
  detail_fetched: 39, docs_processed: 39, detail_capped: true, detail_capped_reason: "time",
  detail_capped_remaining: 120, skipped_unchanged: 0, ledger_rows: 383,
  written: 12, insert_skipped: 371, samples: [{ sku: "BMA15710" }], warnings: ["w1"],
};
const row1 = buildCollectRun("transfer", R_2a, ["w1"], 4321);

// ① 매핑 그대로
ok("① R values map straight to columns",
  row1.source_key === "transfer" && row1.detail_capped === true
  && row1.detail_capped_reason === "time" && row1.detail_capped_remaining === 120
  && row1.hold_capped === 120 && row1.cursor_before === "TR-04172" && row1.cursor_after === "TR-04172"
  && row1.list_total === 3990 && row1.detail_fetched === 39 && row1.docs_processed === 39
  && row1.ledger_rows === 383 && row1.inserted === 12 && row1.insert_skipped === 371
  && row1.skipped_unchanged === 0 && row1.duration_ms === 4321 && row1.ok === true
  && row1.collector === versionLine.match(/"([^"]+)"/)[1],
  JSON.stringify(row1).slice(0, 300));
// cursor_after 폴백: cursor_after 없으면 would_be
const rowFb = buildCollectRun("transfer", { ...R_2a, cursor_after: undefined }, [], 1);
ok("①b cursor_after falls back to cursor_after_would_be", rowFb.cursor_after === "TR-04172");

// ④ write_skipped → ok=false
const row4 = buildCollectRun("sale", { write_skipped: "UNMAPPED location in 2 row(s)" }, [], 1);
ok("④ write_skipped forces ok=false", row4.ok === false && row4.write_skipped === "UNMAPPED location in 2 row(s)");

// ⑤ hold_capped — ②-b(무 dispositions)는 null · ②-a 에서 캡 없으면 null
const R_2b = { candidates: 145, precision_skipped: 179, cursor_stalled_alert: "stalled", cursor_frozen_alert: null, detail_capped: false };
const row5 = buildCollectRun("sale", R_2b, [], 1);
ok("⑤ hold_capped: ②-b null · ②-a without cap null · alerts mapped",
  row5.hold_capped === null && row5.candidates === 145 && row5.precision_skipped === 179
  && row5.cursor_stalled_alert === "stalled" && row5.cursor_frozen_alert === null
  && buildCollectRun("transfer", { dispositions: { processed: 3 } }, [], 1).hold_capped === null);

// ⑥ summary 에 samples 제외 (나머지 키는 보존)
ok("⑥ summary excludes samples, keeps the rest",
  !("samples" in row1.summary) && row1.summary.detail_capped === true && row1.summary.dispositions.hold_capped === 120);

// ⑦ warnings 50개 초과 절단 — 컬럼 + summary 사본 양쪽
const manyWarn = Array.from({ length: 120 }, (_, i) => "w" + i);
const row7 = buildCollectRun("transfer", { warnings: manyWarn }, manyWarn, 1);
ok("⑦ warnings truncated to 50 (column and summary copy)",
  row7.warnings.length === 50 && row7.summary.warnings.length === 50 && row7.warnings[49] === "w49");

// ── (b) 호출부 블록 실물 실행 ──
// ② dry(=commit 아님) → 호출 0 · collect_run_logged=false
{
  let calls = 0;
  const R = {};
  await runBlock(false, async () => { calls++; }, (k, r, w, d) => ({ k }), "transfer", R, [], Date.now());
  ok("② dry writes nothing (0 calls, logged=false)", calls === 0 && R.collect_run_logged === false);
}
// commit 정상 경로 → 1회 호출 · logged=true
{
  let calls = 0, got = null;
  const R = { detail_capped: false };
  await runBlock(true, async (row) => { calls++; got = row; }, buildCollectRun, "transfer", R, ["w"], Date.now());
  ok("②b commit logs once (logged=true, row built from R)",
    calls === 1 && R.collect_run_logged === true && got.source_key === "transfer" && R.collect_run_error === undefined);
}
// ③ throw → 예외 무전파 · collect_run_error · 경고 push · logged=false
{
  const R = {};
  const warnings = [];
  let threw = false;
  try {
    await runBlock(true, async () => { throw new Error("insert failed 500"); }, (k) => ({ k }), "sale", R, warnings, Date.now());
  } catch { threw = true; }
  ok("③ log failure does not propagate — collect_run_error only",
    !threw && R.collect_run_logged === false
    && String(R.collect_run_error).includes("insert failed 500")
    && warnings.length === 1 && warnings[0].includes("collection unaffected"));
}

// ── (c) 정적 배선 ──
// ⑧ 두 블록 모두: if (commit) 가드 · try/catch · catch 에 throw 없음 · 직후가 results[key] = R
for (const [i, b] of callSites.entries()) {
  const tag = i === 0 ? "②-a" : "②-b";
  const catchBody = b.slice(b.indexOf("} catch"));
  ok(`⑧b ${tag} call site guarded by if (commit) + try/catch, no rethrow`,
    b.includes("if (commit) {") && b.includes("await writeCollectRun(buildCollectRun(key, R, warnings, Date.now() - t0))")
    && b.includes("} catch (e: any) {") && !catchBody.includes("throw")
    && b.includes('else R.collect_run_logged = false;'));
}
// writeCollectRun 호출은 정확히 그 2곳뿐 (함수 정의 제외)
const callCount = (src.match(/await writeCollectRun\(/g) ?? []).length;
ok("⑧c writeCollectRun awaited exactly twice", callCount === 2, "found " + callCount);
// insert 형식 — return=minimal 단순 INSERT (upsert 아님 — 회차마다 새 행)
const wcr = extract("writeCollectRun");
ok("⑧d insert is plain POST to inv_collect_runs (no on_conflict)",
  wcr.includes('"/rest/v1/inv_collect_runs"') && wcr.includes("return=minimal") && !wcr.includes("on_conflict"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL RUN-LOG TESTS PASSED");
