// deno test supabase/functions/ims-mcp/mcp_test.ts — Supabase(auth · rest) 무접촉(가짜 fetch) · mcp-2 M1 ~ M15 · mcp-1b M16(도구 ⑥ sales_summary) · mcp-cap-1 M17(⑥ offset · limit 500 · 설명 글)
import { ARGS_MAX_CHARS, clipArgs, handle, metadataDoc, TOOLS, validateArgs, type Deps } from "../_shared/mcp.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const SB = "https://fake.supabase.co", ANON = "anon-key", SVC = "service-key";
const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const TOKEN = "hh." + b64({ sub: "u-1", role: "authenticated", client_id: "claude-1", aud: "authenticated" }) + ".sig";
const EP = SB + "/functions/v1/ims-mcp";
type Call = { url: string; init: RequestInit };
type Fake = { calls: Call[]; warns: string[]; logs: unknown[]; rpc: (fn: string, body: unknown) => Response | Promise<Response>; auth: (token: string) => Response; logFail?: boolean };
function mk(over: Partial<Fake> = {}): { d: Deps; f: Fake } {
  const f: Fake = { calls: [], warns: [], logs: [], auth: (t) => t === TOKEN ? new Response(JSON.stringify({ id: "u-1" }), { status: 200 }) : new Response("{}", { status: 401 }),
    rpc: () => new Response(JSON.stringify({ found: true, so_number: "SO-25001" }), { status: 200 }), ...over };
  const d: Deps = { env: (n) => ({ SUPABASE_URL: SB, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SVC } as Record<string, string>)[n], now: () => 1000, warn: (m) => f.warns.push(m),
    fetch: async (url, init) => {
      f.calls.push({ url, init });
      if (url === SB + "/auth/v1/user") return f.auth(String((init.headers as Record<string, string>).Authorization).replace("Bearer ", ""));
      if (url === SB + "/rest/v1/rpc/mcp_log_add") { if (f.logFail) throw new Error("db down"); f.logs.push(JSON.parse(String(init.body))); return new Response("1", { status: 200 }); }
      const m = url.match(/\/rest\/v1\/rpc\/(mcp_\w+)$/); if (m) return await f.rpc(m[1], JSON.parse(String(init.body)));
      throw new Error("unexpected fetch " + url);
    } };
  return { d, f };
}
const post = (body: unknown, headers: Record<string, string> = { Authorization: "Bearer " + TOKEN }) => new Request(EP, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body) });
const rpcReq = (id: unknown, method: string, params?: unknown) => ({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) });
const noToken = (r: Response, label: string) => { eq(r.status, 401, label + " status"); eq(r.headers.get("WWW-Authenticate"), 'Bearer resource_metadata="' + EP + '/.well-known/oauth-protected-resource"', label + " header"); };

Deno.test("M1 메타데이터 GET — 인증 없이 · resource · authorization_servers · bearer_methods_supported", async () => {
  const { d, f } = mk();
  const r = await handle(new Request(EP + "/.well-known/oauth-protected-resource"), d);
  eq(r.status, 200, "status");
  eq(await r.json(), { resource: EP, authorization_servers: [SB + "/auth/v1"], bearer_methods_supported: ["header"] }, "doc");
  eq(f.calls.length, 0, "Supabase 호출 0");
  eq(metadataDoc(SB + "/").resource, EP, "끝 슬래시 정리");
});
Deno.test("M2 토큰 없음 · 무효 토큰 → 401 + WWW-Authenticate(JSON-RPC 오류 아님) · 기록 0", async () => {
  const { d, f } = mk();
  noToken(await handle(post(rpcReq(1, "initialize"), {}), d), "no token");
  noToken(await handle(post(rpcReq(1, "initialize"), { Authorization: "Bearer bad.token.x" }), d), "bad token");
  eq(f.logs.length, 0, "기록 0");
  ok(!JSON.stringify(f.warns).includes("bad.token"), "토큰이 warn 에 없다");
});
Deno.test("M3 GET 끝점 405 · DELETE 405 · OPTIONS 405 · 모르는 경로 404 — 토큰 확인 전", async () => {
  const { d, f } = mk();
  for (const method of ["GET", "DELETE", "OPTIONS"]) { const r = await handle(new Request(EP, { method }), d); eq(r.status, 405, method); eq(r.headers.get("Allow"), "POST", method + " Allow"); }
  eq((await handle(new Request(EP + "/other", { method: "POST" }), d)).status, 404, "404");
  eq(f.calls.length, 0, "Supabase 호출 0");
});
Deno.test("M4 배열(batch) → 400 + id 없는 오류 · 깨진 JSON → 400 -32700", async () => {
  const { d } = mk();
  const r = await handle(post([rpcReq(1, "ping")]), d); eq(r.status, 400, "batch status"); const j = await r.json(); eq(j.id, null, "id null"); eq(j.error.code, -32600, "code");
  const r2 = await handle(post("{not json"), d); eq(r2.status, 400, "parse status"); eq((await r2.json()).error.code, -32700, "parse code");
});
Deno.test("M5 initialize — 지원 버전 그대로 · 모르는 버전 → 2025-06-18 · capabilities tools · serverInfo · instructions", async () => {
  const { d } = mk();
  const a = (await (await handle(post(rpcReq(1, "initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "c", version: "1" } })), d)).json()).result;
  eq(a.protocolVersion, "2025-03-26", "echo"); eq(a.capabilities, { tools: {} }, "caps"); eq(a.serverInfo.name, "asung-ims", "name"); ok(a.instructions.includes("CAD"), "instructions");
  const b = (await (await handle(post(rpcReq(2, "initialize", { protocolVersion: "1.0.0" })), d)).json()).result; eq(b.protocolVersion, "2025-06-18", "fallback");
});
Deno.test("M6 MCP-Protocol-Version 머리 — 지원 밖 400 · 지원 안이면 통과 · 없어도 통과", async () => {
  const { d } = mk();
  eq((await handle(post(rpcReq(1, "ping"), { Authorization: "Bearer " + TOKEN, "MCP-Protocol-Version": "2024-01-01" }), d)).status, 400, "bad");
  eq((await handle(post(rpcReq(1, "ping"), { Authorization: "Bearer " + TOKEN, "MCP-Protocol-Version": "2025-06-18" }), d)).status, 200, "good");
  eq((await handle(post(rpcReq(1, "ping")), d)).status, 200, "absent");
});
Deno.test("M7 알림(notifications/initialized · cancelled) · 응답 객체 → 202 빈 몸 · Mcp-Session-Id 없음", async () => {
  const { d } = mk();
  for (const body of [{ jsonrpc: "2.0", method: "notifications/initialized" }, { jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: 1 } }, { jsonrpc: "2.0", id: 9, result: {} }]) {
    const r = await handle(post(body), d); eq(r.status, 202, JSON.stringify(body)); eq(await r.text(), "", "empty body"); eq(r.headers.get("Mcp-Session-Id"), null, "no session");
  }
});
Deno.test("M8 ping → {} · 모르는 메서드 → -32601 · jsonrpc 아님 → -32600", async () => {
  const { d } = mk();
  eq((await (await handle(post(rpcReq(1, "ping")), d)).json()).result, {}, "ping");
  eq((await (await handle(post(rpcReq(2, "resources/list")), d)).json()).error.code, -32601, "unknown");
  eq((await (await handle(post({ jsonrpc: "1.0", id: 3, method: "ping" }), d)).json()).error.code, -32600, "jsonrpc");
});
Deno.test("M9 tools/list — 여섯(mcp-1b 가 sales_summary 를 더함) · readOnlyHint · rpc · args 열쇠가 새지 않는다 · 배열 하나(TOOLS)", async () => {
  const { d } = mk();
  const t = (await (await handle(post(rpcReq(1, "tools/list")), d)).json()).result.tools;
  eq(t.map((x: { name: string }) => x.name), ["find_order", "stock", "customer_summary", "po_status", "backorders", "sales_summary"], "names");
  eq(TOOLS.length, 6, "TOOLS 6");
  for (const x of t) { eq(x.annotations, { readOnlyHint: true }, x.name + " annotations"); ok(!("rpc" in x) && !("args" in x), x.name + " 내부 열쇠 없음"); eq(x.inputSchema.type, "object", x.name + " schema"); }
});
Deno.test("M10 모르는 도구 · 인자 틀림 → JSON-RPC -32602 · 기록 error(unknown_tool · invalid_params) · rpc 호출 0", async () => {
  const { d, f } = mk();
  eq((await (await handle(post(rpcReq(1, "tools/call", { name: "delete_order", arguments: {} })), d)).json()).error.code, -32602, "unknown tool");
  eq((await (await handle(post(rpcReq(2, "tools/call", { name: "find_order", arguments: {} })), d)).json()).error.code, -32602, "missing so_number");
  eq((await (await handle(post(rpcReq(3, "tools/call", { name: "stock", arguments: { query: "x", limit: 99 } })), d)).json()).error.message, "Invalid arguments: arguments.limit must be at most 50", "limit 99");
  eq((await (await handle(post(rpcReq(4, "tools/call", { name: "backorders", arguments: { filters: { customer_id: "x" } } })), d)).json()).error.message, "Invalid arguments: arguments.filters.customer_id is not a known field", "filters key");
  eq((await (await handle(post(rpcReq(5, "tools/call", { name: "backorders", arguments: { filters: { state: "closed" } } })), d)).json()).error.code, -32602, "enum");
  eq(f.logs.map((l) => (l as { p_outcome: string; p_error_code: string }).p_outcome + ":" + (l as { p_error_code: string }).p_error_code), ["error:unknown_tool", "error:invalid_params", "error:invalid_params", "error:invalid_params", "error:invalid_params"], "logs");
  eq(f.calls.filter((c) => /rpc\/mcp_(order|stock|backorders)/.test(c.url)).length, 0, "rpc 0");
});
Deno.test("M11 42501(훅 꺼짐) · P0001(mcp_gate) → isError:true + 한 문장 · 기록 refused · 토큰이 기록 몸에 없다", async () => {
  const { d, f } = mk({ rpc: (fn) => new Response(JSON.stringify({ code: fn === "mcp_order" ? "42501" : "P0001", message: fn === "mcp_order" ? "permission denied for function mcp_order" : "Your account does not have the 'claude' permission — ask an admin to switch it on in Staff — nothing was read", details: null, hint: null }), { status: fn === "mcp_order" ? 403 : 400 }) });
  const a = (await (await handle(post(rpcReq(1, "tools/call", { name: "find_order", arguments: { so_number: "SO-25001" } })), d)).json());
  eq(a.result.isError, true, "isError"); ok(a.result.content[0].text.startsWith("IMS refused this call: permission denied for function mcp_order"), "문장: " + a.result.content[0].text); eq(a.error, undefined, "JSON-RPC 오류 아님");
  const b = (await (await handle(post(rpcReq(2, "tools/call", { name: "stock", arguments: { query: "LAC" } })), d)).json());
  eq(b.result.isError, true, "isError 2"); ok(b.result.content[0].text.startsWith("Your account does not have the 'claude' permission"), "mcp_gate 문장 그대로");
  const l = f.logs as Array<Record<string, unknown>>;
  eq(l.map((x) => [x.p_outcome, x.p_error_code, x.p_tool, x.p_auth_user_id, x.p_client_id, x.p_result_bytes]), [["refused", "42501", "find_order", "u-1", "claude-1", null], ["refused", "P0001", "stock", "u-1", "claude-1", null]], "logs");
  eq(l[0].p_args, { so_number: "SO-25001" }, "args 그대로");
  ok(!JSON.stringify(f.logs).includes(TOKEN) && !JSON.stringify(f.calls.map((c) => c.init.body)).includes(TOKEN), "토큰이 기록 몸에 없다");
});
Deno.test("M12 성공 — content text = rpc 의 JSON 글 · isError false · rpc 머리는 apikey ANON + 사용자 토큰(service_role 아님) · 인자 이름 매핑 · 기록 ok + result_bytes", async () => {
  const { d, f } = mk();
  const a = (await (await handle(post(rpcReq(1, "tools/call", { name: "stock", arguments: { query: "LAC", warehouse: "Edmonton" } })), d)).json());
  eq(a.result, { content: [{ type: "text", text: JSON.stringify({ found: true, so_number: "SO-25001" }) }], isError: false }, "result");
  const c = f.calls.find((x) => x.url.endsWith("/rpc/mcp_stock"))!; const h = c.init.headers as Record<string, string>;
  eq([h.apikey, h.Authorization], [ANON, "Bearer " + TOKEN], "headers"); eq(JSON.parse(String(c.init.body)), { p_q: "LAC", p_warehouse: "Edmonton", p_limit: 20 }, "arg map");
  const lh = (f.calls.find((x) => x.url.endsWith("/rpc/mcp_log_add"))!.init.headers as Record<string, string>); eq(lh.Authorization, "Bearer " + SVC, "기록은 service_role");
  const l = f.logs[0] as Record<string, unknown>; eq([l.p_outcome, l.p_result_bytes, l.p_error_code, l.p_error_message], ["ok", JSON.stringify({ found: true, so_number: "SO-25001" }).length, null, null], "log ok");
  const b = (await (await handle(post(rpcReq(2, "tools/call", { name: "backorders" })), d)).json()); eq(b.result.isError, false, "arguments 없음도 된다");
  eq(JSON.parse(String(f.calls.find((x) => x.url.endsWith("/rpc/mcp_backorders"))!.init.body)), { p_filters: {}, p_limit: 50 }, "backorders 기본");
});
Deno.test("M13 기록 실패(fetch 가 던짐 · 400)를 삼킨다 — 도구 응답은 그대로 · warn 한 줄", async () => {
  const { d, f } = mk({ logFail: true });
  const a = (await (await handle(post(rpcReq(1, "tools/call", { name: "po_status", arguments: { po_number: "02056" } })), d)).json());
  eq(a.result.isError, false, "응답 그대로"); eq(f.warns.length, 1, "warn 1"); ok(f.warns[0].startsWith("mcp_log_add threw"), f.warns[0]);
});
Deno.test("M14 args 2 KB 자르기 — 넘으면 {_truncated, chars, head} · 안 넘으면 그대로", () => {
  const big = { name: "x".repeat(3000) }; const c = clipArgs(big) as Record<string, unknown>;
  eq([c._truncated, c.chars, String(c.head).length], [true, JSON.stringify(big).length, 2000], "truncated");
  eq(clipArgs({ a: 1 }), { a: 1 }, "small"); ok(JSON.stringify(clipArgs({ k: "y".repeat(ARGS_MAX_CHARS - 10) })).length <= ARGS_MAX_CHARS, "경계");
  eq(validateArgs({ type: "object", properties: { n: { type: "integer", minimum: 1 } }, required: ["n"] }, { n: 1.5 }), "arguments.n must be integer", "integer");
});
Deno.test("M15 rpc 시간 초과 · 연결 실패 → isError + 기록 error(timeout · fetch) · 500 몸 → error 코드", async () => {
  const { d, f } = mk({ rpc: (fn) => { if (fn === "mcp_order") { const e = new Error("t"); e.name = "TimeoutError"; throw e; } if (fn === "mcp_po") throw new Error("ECONNRESET"); return new Response(JSON.stringify({ code: "57014", message: "canceling statement due to statement timeout" }), { status: 500 }); } });
  const a = (await (await handle(post(rpcReq(1, "tools/call", { name: "find_order", arguments: { so_number: "1" } })), d)).json()); eq(a.result.isError, true, "timeout isError"); ok(a.result.content[0].text.includes("9 seconds"), a.result.content[0].text);
  const b = (await (await handle(post(rpcReq(2, "tools/call", { name: "po_status", arguments: { po_number: "1" } })), d)).json()); eq(b.result.isError, true, "fetch isError");
  const c = (await (await handle(post(rpcReq(3, "tools/call", { name: "customer_summary", arguments: { name: "A" } })), d)).json()); eq(c.result.isError, true, "57014 isError"); ok(c.result.content[0].text.startsWith("IMS could not run this tool (57014)"), c.result.content[0].text);
  eq((f.logs as Array<Record<string, unknown>>).map((x) => x.p_outcome + ":" + x.p_error_code), ["error:timeout", "error:fetch", "error:57014"], "logs");
});
Deno.test("M16 mcp-1b sales_summary — 목록 여섯째 · enum · required · 인자 매핑(날짜 글자 그대로 · 없는 거르기는 null · limit 기본 50) · 틀린 인자 -32602 · 기록 ok · 원가 열쇠는 EF 가 안 만든다(919 는 DB)", async () => {
  const { d, f } = mk({ rpc: (fn) => new Response(JSON.stringify(fn === "mcp_sales" ? { period: { from: "2026-09-01", to: "2026-09-30" }, group: "brand", rows: [{ key: "ORS", sales: 1, credits: 0, net: 1, qty: 1, qty_credited: 0 }], totals: { sales: 1, credits: 0, net: 1, qty: 1, qty_credited: 0 } } : { found: true }), { status: 200 }) });
  const t = (await (await handle(post(rpcReq(1, "tools/list")), d)).json()).result.tools;
  const s = t[5]; eq(s.name, "sales_summary", "name"); eq(s.annotations, { readOnlyHint: true }, "readOnly"); eq(s.inputSchema.required, ["from", "to", "group"], "required");
  eq(s.inputSchema.properties.group.enum, ["brand", "customer", "month", "sku", "supplier"], "enum"); eq([s.inputSchema.properties.limit.minimum, s.inputSchema.properties.limit.maximum], [1, 500], "limit 1 ~ 500");
  ok(s.description.includes("Totals are computed by IMS") && s.description.includes("Does not return addresses"), "description");
  const a = (await (await handle(post(rpcReq(2, "tools/call", { name: "sales_summary", arguments: { from: "2026-09-01", to: "2026-09-30", group: "brand" } })), d)).json());
  eq(a.result.isError, false, "ok"); eq(JSON.parse(a.result.content[0].text).rows[0].key, "ORS", "content = rpc JSON");
  const c = f.calls.find((x) => x.url.endsWith("/rpc/mcp_sales"))!; eq(JSON.parse(String(c.init.body)), { p_from: "2026-09-01", p_to: "2026-09-30", p_group: "brand", p_brand: null, p_customer: null, p_sku: null, p_supplier: null, p_limit: 50, p_offset: 0 }, "arg map 기본");
  const b = (await (await handle(post(rpcReq(3, "tools/call", { name: "sales_summary", arguments: { from: "2026-01-01", to: "2026-10-31", group: "sku", brand: "Clore", customer: "Rex", sku: "ORS1", supplier: "Kim", limit: 500, offset: 120 } })), d)).json()); eq(b.result.isError, false, "ok 2");
  eq(JSON.parse(String(f.calls.filter((x) => x.url.endsWith("/rpc/mcp_sales"))[1].init.body)), { p_from: "2026-01-01", p_to: "2026-10-31", p_group: "sku", p_brand: "Clore", p_customer: "Rex", p_sku: "ORS1", p_supplier: "Kim", p_limit: 500, p_offset: 120 }, "arg map 전부");
  eq((await (await handle(post(rpcReq(4, "tools/call", { name: "sales_summary", arguments: { from: "2026-09-01", group: "brand" } })), d)).json()).error.message, "Invalid arguments: arguments.to is required", "to 빠짐");
  eq((await (await handle(post(rpcReq(5, "tools/call", { name: "sales_summary", arguments: { from: "2026-09-01", to: "2026-09-30", group: "week" } })), d)).json()).error.code, -32602, "enum 밖");
  eq((await (await handle(post(rpcReq(6, "tools/call", { name: "sales_summary", arguments: { from: "2026-09-01", to: "2026-09-30", group: "brand", limit: 501 } })), d)).json()).error.message, "Invalid arguments: arguments.limit must be at most 500", "limit 501");
  eq((await (await handle(post(rpcReq(7, "tools/call", { name: "sales_summary", arguments: { from: "2026-09-01", to: "2026-09-30", group: "brand", warehouse: "x" } })), d)).json()).error.code, -32602, "모르는 열쇠");
  eq((f.logs as Array<Record<string, unknown>>).map((x) => x.p_outcome + ":" + x.p_tool + ":" + x.p_error_code), ["ok:sales_summary:null", "ok:sales_summary:null", "error:sales_summary:invalid_params", "error:sales_summary:invalid_params", "error:sales_summary:invalid_params", "error:sales_summary:invalid_params"], "logs");
  eq(f.calls.filter((x) => x.url.endsWith("/rpc/mcp_sales")).length, 2, "rpc 2");
});
Deno.test("M17 mcp-cap-1 sales_summary offset — 스키마(integer · 최소 0 · 최대 없음) · 기본 0 · RPC 인자 p_offset · 음수 · 문자 · 소수 → -32602 · 설명 글의 핵심 낱말 · 기록", async () => {
  const { d, f } = mk({ rpc: (fn) => new Response(JSON.stringify(fn === "mcp_sales" ? { rows: [], page: { offset: 500, limit: 500, shown: 0, total_rows: 7, next_offset: null }, totals: { net: 1 } } : {}), { status: 200 }) });
  const t = (await (await handle(post(rpcReq(1, "tools/list")), d)).json()).result.tools;
  const o = t[5].inputSchema.properties.offset; eq([o.type, o.minimum, o.maximum], ["integer", 0, undefined], "offset schema"); eq(t[5].inputSchema.properties.limit.maximum, 500, "limit max 500");
  for (const w of ["at most 500 rows", "next_offset is not null", "offset = next_offset", "one page at a time", "never pages in parallel", "use totals once", "rows_truncated counts the rows not on this page", "instead of splitting by brand", "Does not return addresses"]) ok(t[5].description.includes(w), "description: " + w);
  const a = (await (await handle(post(rpcReq(2, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", offset: 500, limit: 500 } })), d)).json());
  eq(a.result.isError, false, "ok"); eq(JSON.parse(a.result.content[0].text).page.next_offset, null, "content = rpc JSON(자르지 않는다)");
  eq(JSON.parse(String(f.calls.find((x) => x.url.endsWith("/rpc/mcp_sales"))!.init.body)), { p_from: "2026-10-01", p_to: "2026-10-31", p_group: "sku", p_brand: null, p_customer: null, p_sku: null, p_supplier: null, p_limit: 500, p_offset: 500 }, "arg map offset");
  const b = (await (await handle(post(rpcReq(3, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", offset: 0 } })), d)).json()); eq(b.result.isError, false, "offset 0 ok");
  eq(JSON.parse(String(f.calls.filter((x) => x.url.endsWith("/rpc/mcp_sales"))[1].init.body)).p_offset, 0, "offset 0 그대로(?? 가 0 을 지우지 않는다)");
  eq((await (await handle(post(rpcReq(4, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", offset: -1 } })), d)).json()).error.message, "Invalid arguments: arguments.offset must be at least 0", "offset -1");
  eq((await (await handle(post(rpcReq(5, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", offset: "3" } })), d)).json()).error.message, "Invalid arguments: arguments.offset must be integer", "offset 문자");
  eq((await (await handle(post(rpcReq(6, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", offset: 1.5 } })), d)).json()).error.message, "Invalid arguments: arguments.offset must be integer", "offset 소수");
  eq((await (await handle(post(rpcReq(7, "tools/call", { name: "sales_summary", arguments: { from: "2026-10-01", to: "2026-10-31", group: "sku", limit: 500, offset: 100000 } })), d)).json()).result.isError, false, "큰 offset 은 EF 가 막지 않는다(DB 가 빈 쪽)");
  eq((f.logs as Array<Record<string, unknown>>).map((x) => x.p_outcome + ":" + x.p_error_code), ["ok:null", "ok:null", "error:invalid_params", "error:invalid_params", "error:invalid_params", "ok:null"], "logs");
  eq(f.calls.filter((x) => x.url.endsWith("/rpc/mcp_sales")).length, 3, "rpc 3");
});
