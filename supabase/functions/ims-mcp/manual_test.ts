// deno test --allow-net=raw.githubusercontent.com supabase/functions/ims-mcp/manual_test.ts — mcp-more-1(판정 1211) 매뉴얼 도구 둘 · N1 ~ N10 은 가짜 fetch(Supabase · GitHub 무접촉) · N11 만 실제 GitHub raw(main) 를 읽는다(--allow-net 이 없으면 건너뛴다 · 구조만 본다 — 원고 글은 다른 창이 고칠 수 있다)
import { handle, TOOLS, type Deps } from "../_shared/mcp.ts";
import { chapterFiles, cleanAnchor, loadManual, MANUAL_CACHE_MS, MANUAL_MAX_HITS, MANUAL_RAW, MANUAL_UNAVAILABLE, manualCacheClear, readManual, searchManual, snippet, splitChapter, stem, tokenize, type Manual } from "../_shared/mcp-manual.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }

// ── 가짜 원고(README 꼴 그대로 · 실제 이름 없음) ──
const README = ["# IMS user manual", "```", '<a id="sales-ship-invoice"></a>', "## Ship & invoice", "```", "## Contents", "| # | Chapter | English | Korean |", "|---|---|---|---|",
  "| 0 | Getting started | [en/00-getting-started.md](en/00-getting-started.md) | [ko/00-getting-started.md](ko/00-getting-started.md) |",
  "| 1 | Sales | [en/01-sales.md](en/01-sales.md) | [ko/01-sales.md](ko/01-sales.md) |",
  "| 1 | Sales again | [en/01-sales.md](en/01-sales.md) | x |",
  "| 9 | Bad | [a](en/../secret.md) [b](en/1-short.md) [c](en/02-UPPER.md) [d](https://evil.example/en/03-x.md) [e](fr/04-x.md) |"].join("\n");
const EN00 = ["# 0. Getting started", "", "<!-- chapter note -->", "Intro text that is not a section — signing words here must not be found.", "",
  '<a id="start-sign-in"></a>', "## Sign in", "<!-- screen: index.html · BUILD 2026-10-01 · home v1 -->", "<!-- who: all -->", "", "**What it is**", "Open IMS and sign in with your email and password.", "",
  "<!-- SCREENSHOT: start-sign-in-1 · the sign-in box -->", "", "", "", "If you forgot the password, see [FAQ](09-faq.md#faq-sign-in).", ""].join("\r\n");
const EN01 = ["# 1. Sales", "", '<a id="sales-ship-invoice"></a>', "## Ship & invoice", "<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->", "<!-- who: office, accounting -->", "",
  "**What it is**", "After the warehouse finalized the order, the office opens the **Ship & invoice** window, checks the freight and issues the invoice for Customer A on SO-99001.", "",
  '<a id="sales-change-ship-to"></a>', "## Change the ship-to of a packed order", "<!-- screen: so.html · BUILD 2026-11-12 · so shipto v1 -->", "<!-- who: office -->", "",
  "**What it is**", "When the customer gives a new delivery address after the warehouse finalized the order, the office changes it in the **Ship & invoice** window.", "",
  "**Steps**", "1. Open the order.", "2. Press **Change ship-to**.", "3. " + "Pick the saved address and confirm it carefully. ".repeat(12), "",
  '<a id="sales-empty"></a>', "## Not written", "<!-- who: sales -->", "", "<!-- rulings: 1200, 1201 -->", ""].join("\n");
const KO00 = ["# 0. 시작하기", "", '<a id="start-sign-in"></a>', "## 로그인", "<!-- who: all -->", "", "이메일과 비밀번호로 로그인합니다.", ""].join("\n");
const KO01 = ["# 1. 판매", "", '<a id="sales-ship-invoice"></a>', "## 출고와 인보이스", "<!-- who: office, accounting -->", "", "창고가 오더를 마감한 뒤 오피스가 인보이스를 발행합니다.", "",
  '<a id="sales-change-ship-to"></a>', "## 포장된 오더의 배송지 바꾸기", "<!-- who: office -->", "", "손님이 새 배송지를 알려 주면 오피스가 배송지를 바꿉니다.", "",
  '<a id="sales-empty"></a>', "## 아직", "<!-- who: sales -->", ""].join("\n");
const FILES: Record<string, string> = { "README.md": README, "en/00-getting-started.md": EN00, "en/01-sales.md": EN01, "ko/00-getting-started.md": KO00, "ko/01-sales.md": KO01 };
const fixture = (lang: "en" | "ko"): Manual => {
  const files = chapterFiles(README, lang);
  return { lang, files, sections: files.flatMap((f) => splitChapter(FILES[lang + "/" + f + ".md"], f)) };
};

// ── 가짜 Supabase + 가짜 GitHub ──
const SB = "https://fake.supabase.co", ANON = "anon-key", SVC = "service-key";
const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const TOKEN = "hh." + b64({ sub: "u-1", role: "ims_connector", client_id: "claude-1", aud: "authenticated" }) + ".sig";
const EP = SB + "/functions/v1/ims-mcp";
type Fake = { order: string[]; rpcCalls: Array<{ fn: string; headers: Record<string, string>; body: unknown }>; gh: string[]; warns: string[]; logs: Array<Record<string, unknown>>; clock: number; gate: () => Response; github: (path: string) => Response | Promise<Response> };
function mk(over: Partial<Fake> = {}): { d: Deps; f: Fake } {
  manualCacheClear();
  const f: Fake = { order: [], rpcCalls: [], gh: [], warns: [], logs: [], clock: 1_000_000, gate: () => new Response("true", { status: 200 }),
    github: (p) => p in FILES ? new Response(FILES[p], { status: 200 }) : new Response("404: Not Found", { status: 404 }), ...over };
  const d: Deps = { env: (n) => ({ SUPABASE_URL: SB, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SVC } as Record<string, string>)[n], now: () => f.clock, warn: (m) => f.warns.push(m), sleep: async () => {},
    fetch: async (url, init) => {
      if (url === SB + "/auth/v1/user") return new Response(JSON.stringify({ id: "u-1" }), { status: 200 });
      if (url === SB + "/rest/v1/rpc/mcp_log_add") { f.logs.push(JSON.parse(String(init.body))); return new Response("1", { status: 200 }); }
      const m = url.match(/\/rest\/v1\/rpc\/(mcp_\w+)$/);
      if (m && url.startsWith(SB)) { f.order.push("rpc:" + m[1]); f.rpcCalls.push({ fn: m[1], headers: init.headers as Record<string, string>, body: JSON.parse(String(init.body)) }); return m[1] === "mcp_manual_gate" ? f.gate() : new Response(JSON.stringify({ rows: [] }), { status: 200 }); }
      if (url.startsWith(MANUAL_RAW)) { const p = url.slice(MANUAL_RAW.length); f.order.push("gh:" + p); f.gh.push(p); ok(init.method === "GET" && init.signal instanceof AbortSignal && !init.headers, "GitHub 에는 GET · 상한 신호 · 머리 없음(토큰 · apikey 가 나가지 않는다)"); return await f.github(p); }
      throw new Error("unexpected fetch " + url);
    } };
  return { d, f };
}
const call = async (d: Deps, id: number, name: string, args: unknown) => await (await handle(new Request(EP, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + TOKEN }, body: JSON.stringify({ jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } }) }), d)).json();

Deno.test("N1 장 목록 — README Contents 에서 그 언어의 링크만 · 순서 그대로 · 겹치면 한 번 · 꼴이 틀린 이름(.. · 한 자리 · 대문자 · 바깥 주소 · 다른 언어)은 버린다", () => {
  eq(chapterFiles(README, "en"), ["00-getting-started", "01-sales"], "en");
  eq(chapterFiles(README, "ko"), ["00-getting-started", "01-sales"], "ko");
  eq(chapterFiles("no table here", "en"), [], "없으면 빈 배열");
});
Deno.test("N2 원고 쪼개기 — 절 경계(앵커 줄 ~ 다음 앵커 앞) · 장 머리는 절이 아님 · 숨은 주석 전부 뺌(screen · SCREENSHOT · rulings) · who 는 배열 · 제목 줄은 body 에서 빠짐 · CRLF · 빈 줄 접기 · 본문 없는 절", () => {
  const a = splitChapter(EN00, "00-getting-started");
  eq(a.length, 1, "절 하나(머리 글은 절이 아니다)");
  eq([a[0].anchor, a[0].file, a[0].chapter, a[0].title, a[0].who], ["start-sign-in", "00-getting-started", "0. Getting started", "Sign in", ["all"]], "칸");
  eq(a[0].body, "**What it is**\nOpen IMS and sign in with your email and password.\n\nIf you forgot the password, see [FAQ](09-faq.md#faq-sign-in).", "body(CRLF · 주석 · 빈 줄 3 → 1 · 링크 그대로)");
  const b = splitChapter(EN01, "01-sales");
  eq(b.map((s) => s.anchor), ["sales-ship-invoice", "sales-change-ship-to", "sales-empty"], "앵커 셋 · 순서");
  eq(b.map((s) => s.who), [["office", "accounting"], ["office"], ["sales"]], "who");
  eq(b[0].title, "Ship & invoice", "제목"); ok(!b[0].body.includes("Change the ship-to"), "다음 절의 글이 섞이지 않는다");
  eq([b[2].title, b[2].body], ["Not written", ""], "본문 없는 절 · 끝의 rulings 주석도 빠진다");
  for (const s of [...a, ...b]) ok(!/<!--|-->|BUILD|SCREENSHOT|rulings|so csv|<a id/.test(s.body + s.title), s.anchor + " 에 숨은 주석 · 앵커 줄이 남지 않는다");
  eq(splitChapter("# X\n\nno anchors", "x"), [], "앵커 없는 장 → 절 0");
});
Deno.test("N3 낱말 — 흔한 말 빼기 · 어미 떼기(finalized = finalize · shipped = ship · changes = change) · 짧은 낱말 · 한글 · 겹침 한 번 · 200 자", () => {
  eq(tokenize("How do I change the ship-to on a finalized order?"), ["chang", "ship", "finaliz", "order"], "질문");
  eq([stem("finalize"), stem("finalized"), stem("finalizing"), stem("shipped"), stem("changes"), stem("address"), stem("po"), stem("배송지")], ["finaliz", "finaliz", "finaliz", "ship", "chang", "addres", "po", "배송지"], "stem");
  eq(tokenize("PO po Po 배송지 바꾸기 x"), ["po", "배송지", "바꾸기"], "대소문자 무시 · 한글 · 한 글자 영문 버림");
  eq(tokenize("how do i the"), [], "흔한 말뿐이면 0");
  eq(tokenize("a".repeat(250) + " invoice"), ["a".repeat(200)], "200 자에서 자른다");
});
Deno.test("N4 찾기 — 순위(앵커 · 제목이 본문보다 무겁다) · 후보 꼴(anchor · chapter · title · who · snippet · url) · 발췌 길이 · 대소문자 무시 · 0 건 → 목차 · 빈 질문 → 목차 · 한글", () => {
  const m = fixture("en");
  const r = searchManual(m, "How do I change the ship-to on a finalized order?") as { hits: Array<Record<string, unknown>>; total_matches: number; contents?: unknown };
  eq(r.hits[0].anchor, "sales-change-ship-to", "첫 후보"); eq(r.hits[1].anchor, "sales-ship-invoice", "둘째(ship · finalized · order 는 맞지만 change 가 없다)");
  eq(Object.keys(r.hits[0]), ["anchor", "chapter", "title", "who", "snippet", "url"], "열쇠 여섯");
  eq([r.hits[0].chapter, r.hits[0].title, r.hits[0].who, r.hits[0].url], ["1. Sales", "Change the ship-to of a packed order", ["office"], "https://ims.asung.ca/help.html?lang=en#sales-change-ship-to"], "칸");
  const sn = String(r.hits[0].snippet); ok(sn.length <= 206 && sn.endsWith(" …") && !sn.includes("\n"), "발췌 ≈ 200 자 · 한 줄: " + sn.length);
  eq(r.contents, undefined, "맞으면 목차 없음"); ok(r.hits.length <= MANUAL_MAX_HITS, "최대 8");
  eq((searchManual(m, "INVOICE") as { hits: Array<{ anchor: string }> }).hits.map((h) => h.anchor), ["sales-ship-invoice", "sales-change-ship-to"], "대소문자 무시 · 앵커 · 제목에 있는 절이 본문에만 있는 절보다 앞");
  ok(!(searchManual(m, "signing") as { hits: Array<{ anchor: string }> }).hits.some((h) => h.anchor !== "start-sign-in"), "장 머리 글은 찾기 대상이 아니다");
  const z = searchManual(m, "zebra unicorn") as { hits: unknown[]; contents: Array<Record<string, string>>; note: string };
  eq(z.hits, [], "0 건"); eq(z.contents.map((c) => c.anchor), ["start-sign-in", "sales-ship-invoice", "sales-change-ship-to", "sales-empty"], "목차 = 절 전부 · 순서"); eq(Object.keys(z.contents[0]), ["anchor", "chapter", "title"], "목차 열쇠"); ok(z.note.includes("manual_read"), "안내");
  eq((searchManual(m, "  how do I  ") as { hits: unknown[]; contents: unknown[] }).contents.length, 4, "흔한 말뿐 → 목차");
  eq((searchManual(m, "배송지 바꾸기") as { hits: unknown[] }).hits, [], "en 원고에 한글 질문 → 0 건(목차)");
  const k = searchManual(fixture("ko"), "배송지 바꾸기") as { hits: Array<Record<string, unknown>> };
  eq([k.hits[0].anchor, k.hits[0].url, k.hits.length], ["sales-change-ship-to", "https://ims.asung.ca/help.html?lang=ko#sales-change-ship-to", 1], "ko — 조사 붙은 낱말도 포함으로 찾는다(배송지를)");
  eq(snippet("short body", ["x"]), "short body", "짧으면 그대로");
});
Deno.test("N5 읽기 — 그 절 본문 · who · url · '#앵커' · 주소 · 대문자도 받는다 · 본문 없는 절 · 없는 앵커 → 비슷한 후보(오타 · 낱말) · 전혀 다르면 후보 0", () => {
  const m = fixture("en");
  const r = readManual(m, "sales-change-ship-to");
  eq(Object.keys(r), ["found", "lang", "anchor", "chapter", "title", "who", "url", "body"], "열쇠");
  eq([r.found, r.lang, r.anchor, r.chapter, r.title, r.who, r.url], [true, "en", "sales-change-ship-to", "1. Sales", "Change the ship-to of a packed order", ["office"], "https://ims.asung.ca/help.html?lang=en#sales-change-ship-to"], "칸");
  ok(String(r.body).startsWith("**What it is**\nWhen the customer gives") && String(r.body).includes("2. Press **Change ship-to**.") && !String(r.body).includes("<!--") && !String(r.body).includes("Not written"), "본문 통째 · 자르지 않는다 · 다음 절 없음");
  eq([cleanAnchor("#Sales-Change-Ship-To "), cleanAnchor("https://ims.asung.ca/help.html?lang=en#start-sign-in")], ["sales-change-ship-to", "start-sign-in"], "앵커 다듬기");
  eq(readManual(m, " #SALES-change-ship-to").found, true, "다듬은 뒤 찾는다");
  eq(readManual(m, "sales-empty").body, "(This part of the manual is not written yet.)", "본문 없는 절");
  const t = readManual(m, "sales-change-shipto") as { found: boolean; candidates: Array<Record<string, string>> };
  eq([t.found, t.candidates[0].anchor, Object.keys(t.candidates[0])], [false, "sales-change-ship-to", ["anchor", "chapter", "title"]], "오타 → 첫 후보");
  eq((readManual(m, "sign-in") as { candidates: Array<{ anchor: string }> }).candidates[0].anchor, "start-sign-in", "일부만 → 후보");
  const n = readManual(m, "zzzzzzzzzzzzzzzzzzzz") as { found: boolean; candidates: unknown[]; note: string };
  eq([n.found, n.candidates], [false, []], "전혀 다르면 0"); ok(n.note.includes("manual_search"), "안내");
});
Deno.test("N6 도구 호출(성공) — 문(rpc/mcp_manual_gate · 사용자 토큰 · apikey ANON · 몸 {})이 GitHub 보다 먼저 · README → 장 · content = JSON 글 · 기록 ok + result_bytes · args 그대로", async () => {
  const { d, f } = mk();
  const a = await call(d, 1, "manual_search", { query: "change ship-to finalized order" });
  eq(a.result.isError, false, "isError"); const j = JSON.parse(a.result.content[0].text); eq([j.lang, j.hits[0].anchor], ["en", "sales-change-ship-to"], "결과");
  eq(f.order, ["rpc:mcp_manual_gate", "gh:README.md", "gh:en/00-getting-started.md", "gh:en/01-sales.md"], "순서 — 문이 먼저");
  eq([f.rpcCalls[0].headers.apikey, f.rpcCalls[0].headers.Authorization, f.rpcCalls[0].body], [ANON, "Bearer " + TOKEN, {}], "문은 사용자 토큰으로(service_role 아님) · 인자 없음");
  eq([f.logs[0].p_tool, f.logs[0].p_outcome, f.logs[0].p_error_code, f.logs[0].p_result_bytes, f.logs[0].p_args], ["manual_search", "ok", null, a.result.content[0].text.length, { query: "change ship-to finalized order" }], "기록");
  const b = await call(d, 2, "manual_read", { anchor: "sales-change-ship-to", lang: "ko" });
  const r = JSON.parse(b.result.content[0].text); eq([b.result.isError, r.found, r.lang, r.title, r.url], [false, true, "ko", "포장된 오더의 배송지 바꾸기", "https://ims.asung.ca/help.html?lang=ko#sales-change-ship-to"], "read ko");
  const c = await call(d, 3, "manual_read", { anchor: "nope-nope" }); eq([c.result.isError, JSON.parse(c.result.content[0].text).found, f.logs[2].p_outcome], [false, false, "ok"], "없는 앵커는 오류가 아니라 후보(isError false)");
  ok(!JSON.stringify(f.logs).includes(TOKEN), "토큰이 기록에 없다");
});
Deno.test("N7 문이 거절(P0001 열쇠 꺼짐 · 42501 훅 꺼짐) → 여섯 도구와 같은 꼴(isError + 문장 · 기록 refused) · GitHub 호출 0 · 캐시가 있어도 문은 매번", async () => {
  const P = "Your account does not have the 'claude' permission — ask an admin to switch it on in Staff — nothing was read";
  let mode = "ok";
  const { d, f } = mk({ gate: () => mode === "ok" ? new Response("true", { status: 200 }) : mode === "P0001" ? new Response(JSON.stringify({ code: "P0001", message: P }), { status: 400 }) : new Response(JSON.stringify({ code: "42501", message: "permission denied for function mcp_manual_gate" }), { status: 403 }) });
  mode = "P0001";
  const a = await call(d, 1, "manual_search", { query: "invoice" });
  eq([a.result.isError, a.result.content[0].text, f.gh.length], [true, P, 0], "거절 문장 그대로 · 원고를 읽지 않았다");
  eq([f.logs[0].p_outcome, f.logs[0].p_error_code, f.logs[0].p_result_bytes], ["refused", "P0001", null], "기록 refused");
  mode = "ok"; eq((await call(d, 2, "manual_read", { anchor: "start-sign-in" })).result.isError, false, "열쇠가 있으면 읽는다(캐시가 찬다)"); const n = f.gh.length; ok(n > 0, "읽었다");
  mode = "P0001"; const b = await call(d, 3, "manual_read", { anchor: "start-sign-in" });
  eq([b.result.isError, b.result.content[0].text, f.gh.length - n], [true, P, 0], "⭐ 캐시에 원고가 있어도 열쇠를 끄면 다음 질문부터 거절(921)");
  mode = "42501"; const c = await call(d, 4, "manual_search", { query: "invoice" });
  ok(c.result.isError && c.result.content[0].text.startsWith("IMS refused this call: permission denied for function mcp_manual_gate"), "42501 문장"); eq(f.logs[3].p_outcome, "refused", "42501 기록");
  eq(f.order.filter((x) => x === "rpc:mcp_manual_gate").length, 4, "문은 호출마다 한 번");
});
Deno.test("N8 GitHub 실패 — 장 하나 404 · README 500 · 연결 실패 · 시간 초과 · 장 0 · 절 0 → isError + MANUAL_UNAVAILABLE · 기록 error/manual_unavailable · warn 에 까닭 · 실패는 캐시하지 않는다 · 다른 도구 무영향", async () => {
  let bad: (p: string) => Response | null = () => null;
  const { d, f } = mk({ github: (p) => bad(p) ?? new Response(FILES[p], { status: 200 }) });
  const expectFail = async (id: number, label: string, warnHas: string) => {
    const a = await call(d, id, "manual_search", { query: "invoice" });
    eq([a.result.isError, a.result.content[0].text], [true, MANUAL_UNAVAILABLE], label);
    const l = f.logs[f.logs.length - 1]; eq([l.p_outcome, l.p_error_code, l.p_error_message, l.p_result_bytes], ["error", "manual_unavailable", MANUAL_UNAVAILABLE.slice(0, 200), null], label + " 기록");
    ok(f.warns[f.warns.length - 1].includes(warnHas), label + " warn: " + f.warns[f.warns.length - 1]);
  };
  bad = (p) => p === "en/01-sales.md" ? new Response("404: Not Found", { status: 404 }) : null; await expectFail(1, "장 하나 404 → 일부만으로 답하지 않는다", "en/01-sales.md — HTTP 404");
  bad = (p) => p === "README.md" ? new Response("oops", { status: 500 }) : null; await expectFail(2, "README 500", "README.md — HTTP 500");
  bad = () => { throw new TypeError("network down"); }; await expectFail(3, "연결 실패", "network down");
  bad = () => { throw new DOMException("Signal timed out.", "TimeoutError"); }; await expectFail(4, "시간 초과", "TimeoutError");
  bad = (p) => p === "README.md" ? new Response("# no contents", { status: 200 }) : null; await expectFail(5, "README 에 장 0", "no chapters");
  bad = (p) => p !== "README.md" ? new Response("# empty chapter", { status: 200 }) : null; await expectFail(6, "절 0", "no sections");
  ok(MANUAL_UNAVAILABLE.includes("? help on the IMS screen"), "문장이 화면 도움말을 가리킨다");
  const s = await call(d, 7, "stock", { query: "LAC" }); eq(s.result.isError, false, "다른 도구는 그대로");
  bad = () => null; const g = await call(d, 8, "manual_search", { query: "invoice" }); eq(g.result.isError, false, "실패는 담지 않는다 — 다음 호출이 다시 읽어 성공");
});
Deno.test("N9 캐시 — 5 분 안에는 GitHub 를 다시 읽지 않는다(search → read 한 쌍 = 한 번) · 언어마다 따로 · 5 분이 지나면 다시 · 읽는 주소는 고정 머리 + 꼴에 맞는 이름뿐", async () => {
  const { d, f } = mk();
  await call(d, 1, "manual_search", { query: "invoice" }); eq(f.gh.length, 3, "첫 호출 README + 장 2");
  f.clock += 60_000; await call(d, 2, "manual_read", { anchor: "sales-ship-invoice" }); eq(f.gh.length, 3, "1 분 뒤 read — 캐시");
  await call(d, 3, "manual_search", { query: "배송지", lang: "ko" }); eq(f.gh.slice(3), ["README.md", "ko/00-getting-started.md", "ko/01-sales.md"], "ko 는 따로 읽는다");
  f.clock += MANUAL_CACHE_MS - 60_000 - 1; await call(d, 4, "manual_search", { query: "invoice" }); eq(f.gh.length, 6, "en 5 분 직전 — 아직 캐시");
  f.clock += 1; await call(d, 5, "manual_search", { query: "invoice" }); eq(f.gh.length, 9, "en 5 분 — 다시 읽는다");
  for (const p of f.gh) ok(p === "README.md" || /^(en|ko)\/\d\d-[a-z0-9-]+\.md$/.test(p), "주소 꼴: " + p);
  eq(MANUAL_RAW, "https://raw.githubusercontent.com/asungtrading/asung-wms/main/docs/manual/", "help.html:93 과 같은 주소");
});
Deno.test("N10 스키마 · 설명 — 도구 둘 · rpc 는 문 하나 · lang enum · required · 틀린 인자 → -32602(문 · GitHub 호출 0) · 설명 글이 언제 쓰는지 · 데이터는 다른 도구라고 말한다", async () => {
  const s = TOOLS.find((t) => t.name === "manual_search")!, r = TOOLS.find((t) => t.name === "manual_read")!;
  eq([s.rpc, r.rpc, s.args({ query: "x" }), r.args({ anchor: "y" }), typeof s.run, typeof r.run, s.busyRetry, s.annotations], ["mcp_manual_gate", "mcp_manual_gate", {}, {}, "function", "function", undefined, { readOnlyHint: true }], "꼴");
  eq([s.inputSchema.required, r.inputSchema.required, s.inputSchema.properties!.lang.enum, r.inputSchema.properties!.lang.enum, s.inputSchema.additionalProperties], [["query"], ["anchor"], ["en", "ko"], ["en", "ko"], false], "스키마");
  ok(s.description.includes("how do I") && s.description.includes("manual_read") && s.description.includes("not live data") && r.description.includes("anchor"), "설명 글");
  ok(TOOLS.filter((t) => t.run).length === 2 && TOOLS.filter((t) => !t.run).every((t) => t.rpc !== "mcp_manual_gate"), "run 은 매뉴얼 둘뿐 · 다른 도구는 문 함수를 부르지 않는다");
  const { d, f } = mk();
  for (const [i, args] of [{ query: "x", lang: "fr" }, { lang: "en" }, { query: 5 }, { query: "x", extra: 1 }].entries()) { const a = await call(d, i, "manual_search", args); eq(a.error?.code, -32602, "틀린 인자 " + JSON.stringify(args)); }
  eq((await call(d, 9, "manual_read", {})).error?.code, -32602, "anchor 없음");
  eq([f.order.length, f.logs.map((l) => l.p_error_code)], [0, ["invalid_params", "invalid_params", "invalid_params", "invalid_params", "invalid_params"]], "문 · GitHub 호출 0 · 기록 invalid_params");
});

const NET = Deno.permissions.querySync({ name: "net", host: "raw.githubusercontent.com" }).state === "granted";
Deno.test({ name: "N11 ⭐ 실제 GitHub raw(main) — en · ko 를 읽는다 · 절 ≥ 100 · en = ko 앵커(같은 순서) · 숨은 주석 0 · who 가 README 낱말 · 질문 「How do I change the ship-to on a finalized order?」 후보에 sales-change-ship-to", ignore: !NET, fn: async () => {
  manualCacheClear();
  const d = { fetch: (u: string, i: RequestInit) => fetch(u, i), now: () => Date.now() };
  const t0 = Date.now(); const en = await loadManual(d, "en"); const ms = Date.now() - t0; const ko = await loadManual(d, "ko");
  ok(en.files.length >= 10 && en.sections.length >= 100, "장 · 절 수: " + en.files.length + " · " + en.sections.length);
  eq(ko.sections.map((s) => s.anchor), en.sections.map((s) => s.anchor), "en = ko 앵커 · 순서");
  eq(new Set(en.sections.map((s) => s.anchor)).size, en.sections.length, "앵커 겹침 0");
  const WHO = ["manager", "admin", "accounting", "office", "sales", "warehouse", "all"];
  for (const s of [...en.sections, ...ko.sections]) { ok(!/<!--|-->|<a id=/.test(s.body) && s.title.length > 0, s.anchor + " 숨은 주석 · 앵커 줄 0"); ok(s.who.every((w) => WHO.includes(w)), s.anchor + " who " + s.who.join(",")); }
  const hits = (searchManual(en, "How do I change the ship-to on a finalized order?") as { hits: Array<{ anchor: string }> }).hits.map((h) => h.anchor);
  ok(hits.includes("sales-change-ship-to"), "후보: " + hits.join(" "));
  const r = readManual(en, "sales-change-ship-to"); ok(r.found === true && String(r.body).length > 300, "read");
  const big = [...en.sections].sort((p, q) => q.body.length - p.body.length)[0];
  console.log(`  N11 실측: 장 ${en.files.length} · 절 en ${en.sections.length} ko ${ko.sections.length} · who 없는 절 ${en.sections.filter((s) => !s.who.length).length} · en 읽기 ${ms} ms · 가장 큰 절 ${big.anchor} ${big.body.length} 자 · 질문 후보: ${hits.join(" > ")}`);
} });
