// 문서 상태 skip 테스트 (2026-08-31 · 결함 D — 변경 없는 문서는 상세를 부르지 않는다)
//
// 실행:  node scripts/test-invcollect-docstate.mjs      (esbuild 는 npx 로 자동 — 네트워크 1회)
// 전부 통과하면 마지막 줄이 "ALL DOC-STATE TESTS PASSED".
//
// 방식은 test-invcollect-cursor.mjs 와 동일 — **원본에서 순수 함수(docStateSkip) 원문 추출** 후
// node 실행 + **정적 grep 으로 루프 배선**(skip 위치·커서 전진·dry 미기록·upsert 형식·
// recheck·소멸 감지 제외)을 못박는다. loadDocState 는 fetch 를 품어 추출 실행이 어렵다 —
// 읽기 실패 경로(⑧)는 「판정 함수의 null 맵 = 조회」(동적) + try/catch·doc_state_error 배선(정적)으로 검증.
//
// 검증 ①~⑩ (지시서 §4):
//  ① 변경 없음 + 완료 → skip (상세 미조회 — 정적: skip 분기가 상세 조회보다 앞)
//  ② 값이 다름 → 정상 조회
//  ③ 상태 기록 없음(첫 관측) → 정상 조회
//  ④ 비종결(process_nonterminal) + 값 동일 → skip 하지 않는다 (동적 + 정적: ②-a 호출부의
//     terminal 인자가 c.disposition === "process")
//  ⑤ skip 한 문서도 커서 전진에 포함 (②-a: skip_unchanged 가 커서 통과 목록에 ·
//     ②-b: skip 분기가 lastProcessedKey 를 갱신)
//  ⑥ dry 에서 inv_doc_state 쓰기 0 (두 call site 모두 if (commit) 블록 안 · 원장 쓰기 성공 뒤)
//  ⑦ upsert 가 on_conflict=source_key,doc_number + merge-duplicates
//  ⑧ 판정 조회 실패 → 전량 조회로 동작 + doc_state_error 보고 (수집은 계속)
//  ⑨ ?recheck=1 → 값이 같아도 전부 조회
//  ⑩ 소멸 감지: skip 한 문서는 A 집합(missingDocs)에 안 들어간다 — skip 분기가 축적 지점보다 앞

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

// ── 원문 추출: function <name> … 균형 중괄호 (시그니처에 { 가 없도록 원본이 작성돼 있다) ──
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
const dir = mkdtempSync(join(tmpdir(), "docstate-"));
writeFileSync(join(dir, "docstate.ts"), extract("docStateSkip") + "\nexport { docStateSkip };\n");
execSync(`npx --yes esbuild ${join(dir, "docstate.ts")} --outfile=${join(dir, "docstate.mjs")} --format=esm`, { stdio: "pipe" });
const { docStateSkip } = await import(join(dir, "docstate.mjs"));

// 2026-08-31 롤링 재확인 이후 맵 값은 DocStateRec({ lastModified, seenAt }) — loadDocState 가
// seen_at 도 읽는다. docStateSkip 은 lastModified 만 본다(seenAt 은 pickRollingRecheck 용).
const rec = (lm, seen = "2026-08-31T10:00:00+00:00") => ({ lastModified: lm, seenAt: seen });
const M = new Map([["TR-04200", rec("2026-08-27T10:00:00.123Z")], ["PO-01130", rec("2026-08-19T13:04:50.803")]]);

// ── 동적 — 판정 함수 ──
// ① 변경 없음 + 완료 → skip
ok("① unchanged terminal doc skips",
  docStateSkip(true, false, M, "TR-04200", "2026-08-27T10:00:00.123Z") === true
  && docStateSkip(true, false, M, "PO-01130", "2026-08-19T13:04:50.803") === true);   // Z 없는 발주 형식도 문자열 일치로

// ② 값이 다름 → 조회
ok("② changed value fetches",
  docStateSkip(true, false, M, "TR-04200", "2026-08-28T09:00:00.000Z") === false);

// ③ 첫 관측(기록 없음) → 조회
ok("③ unknown doc fetches",
  docStateSkip(true, false, M, "TR-04330", "2026-08-28T12:00:00.000Z") === false);

// ④ 비종결 + 값 동일 → 절대 skip 하지 않는다
ok("④ nonterminal never skips",
  docStateSkip(false, false, M, "TR-04200", "2026-08-27T10:00:00.123Z") === false);

// ⑧(동적 절반) 맵 없음(읽기 실패) = 전량 조회 · 값/식별자 결손도 조회
ok("⑧a null map (read failure) fetches all",
  docStateSkip(true, false, null, "TR-04200", "2026-08-27T10:00:00.123Z") === false
  && docStateSkip(true, false, M, "", "2026-08-27T10:00:00.123Z") === false
  && docStateSkip(true, false, M, "TR-04200", null) === false);

// ⑨(동적 절반) recheck → 값이 같아도 조회
ok("⑨a recheck bypasses skip",
  docStateSkip(true, true, M, "TR-04200", "2026-08-27T10:00:00.123Z") === false);

// ── 정적 — 루프 배선 ──
// 함수 영역 분리
const aStart = src.indexOf("async function runSource(");
const bStart = src.indexOf("async function runDateSource(");
const bEnd = src.indexOf("for (const key of runKeys)");
if (aStart < 0 || bStart < 0 || bEnd < 0 || !(aStart < bStart && bStart < bEnd)) {
  console.error("FAIL region split — runSource/runDateSource boundaries not found"); process.exit(1);
}
const A = src.slice(aStart, bStart);   // ②-a runSource
const B = src.slice(bStart, bEnd);     // ②-b runDateSource

// ①(정적) skip 분기가 상세 조회(cin7Get)보다 앞 — skip 하면 상세 미조회
ok("①b skip branch precedes detail fetch (both loops)",
  A.indexOf('c.disposition = "skip_unchanged"') > -1
  && A.indexOf('c.disposition = "skip_unchanged"') < A.indexOf("det = await cin7Get(cfg.detailPath")
  && B.indexOf("docStateSkip(true, recheck") > -1
  && B.indexOf("docStateSkip(true, recheck") < B.indexOf("det = await cin7Get(path)"));

// ④(정적) ②-a 호출부의 terminal 인자 = c.disposition === "process" (nonterminal 은 구조적으로 false)
ok("④b ②-a passes terminal = (disposition === \"process\")",
  A.includes('docStateSkip(c.disposition === "process", recheck, docState, c.number, listLmOf(c.row))'));

// ⑤ 커서 전진 — ②-a 통과 목록에 skip_unchanged · ②-b skip 분기가 lastProcessedKey 갱신
ok("⑤a ②-a cursor pass-list includes skip_unchanged",
  A.includes('d === "skip_unchanged") { cursorAfter = c.number; continue; }'));
{
  const skipAt = B.indexOf("docStateSkip(true, recheck");
  const branch = B.slice(skipAt, B.indexOf("continue;", skipAt) + 9);
  ok("⑤b ②-b skip branch advances lastProcessedKey", branch.includes("lastProcessedKey = cd.key"));
}

// ⑥ dry 미기록 — inv_doc_state 쓰기는 정확히 2곳, 둘 다 if (commit) 블록 안 · 원장 쓰기 성공 뒤
const upsertCalls = (src.match(/sbUpsert\("inv_doc_state"/g) ?? []).length;
ok("⑥a exactly 2 inv_doc_state upsert call sites", upsertCalls === 2, "found " + upsertCalls);
function commitBlock(region) {   // if (commit) { … } 균형 추출
  const at = region.indexOf("if (commit) {");
  if (at < 0) return "";
  let depth = 0, started = false;
  for (let i = at; i < region.length; i++) {
    if (region[i] === "{") { depth++; started = true; }
    else if (region[i] === "}") { depth--; if (started && depth === 0) return region.slice(at, i + 1); }
  }
  return "";
}
for (const [tag, region] of [["②-a", A], ["②-b", B]]) {
  const cb = commitBlock(region);
  const up = cb.indexOf('sbUpsert("inv_doc_state"');
  ok(`⑥b ${tag} doc-state write inside commit block, after ledger write`,
    up > -1 && up > cb.indexOf("writeLedgerDetectingConflicts(sink.rows"),
    "upsert@" + up);
  // ⑧(정적) 읽기 try/catch → 판정 OFF + 경고 + 응답 doc_state_error
  ok(`⑧b ${tag} read failure disables judging + reports doc_state_error`,
    region.includes("doc-state read failed - skip judging disabled")
    && region.includes("doc_state_error: docStateError ?? undefined")
    && region.includes("skipped_unchanged: skippedUnchanged")
    && region.includes("doc_state_known: docState ? docState.size : 0"));
  // 쓰기 실패도 수집을 막지 않는다 (try/catch + 경고)
  ok(`⑥c ${tag} doc-state write failure only warns`,
    cb.includes("doc-state upsert failed (collection unaffected)"));
}

// ⑦ upsert 형식 — on_conflict=source_key,doc_number + merge-duplicates(sbUpsert 공용 헬퍼)
ok("⑦ on_conflict=source_key,doc_number + merge-duplicates",
  (src.match(/sbUpsert\("inv_doc_state", "source_key,doc_number"/g) ?? []).length === 2
  && extract("sbUpsert").includes('"?on_conflict=" + conflictCol')
  && extract("sbUpsert").includes("resolution=merge-duplicates"));

// ⑨(정적) recheck 파라미터가 파싱되고 두 판정 호출 모두에 전달된다
ok("⑨b recheck param parsed and wired into both judgments",
  src.includes('url.searchParams.get("recheck") === "1"')
  && A.includes("docStateSkip(c.disposition === \"process\", recheck")
  && B.includes("docStateSkip(true, recheck"));

// ⑩ 소멸 감지 — skip 분기(continue)가 A 집합 축적(missingDocs.push)보다 앞 = skip 문서는 검출 대상 제외
ok("⑩ skipped docs never reach missingDocs accumulation (both loops)",
  A.indexOf('c.disposition = "skip_unchanged"') < A.indexOf("missingDocs.push")
  && B.indexOf("docStateSkip(true, recheck") < B.indexOf("missingDocs.push"));

// ②-b 기록 게이트 — docIncomplete 문서는 기록하지 않는다(비종결 원칙의 ②-b 판)
ok("(보강) ②-b records only !docIncomplete docs",
  B.includes("if (!docIncomplete) {\n          const ident = cursorDocIdent(row);"));

if (fails) { console.error(fails + " FAILURE(S)"); process.exit(1); }
console.log("ALL DOC-STATE TESTS PASSED");
