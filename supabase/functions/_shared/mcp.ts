// ============================================================
// ASUNG IMS — _shared/mcp.ts: Claude 커넥터 MCP 서버의 순수 처리 (mcp-2 · 2026-11-01 · 판정 917 ~ 924 · DB mcp-1a 20261031233700 · mcp-2 20261101000546 · mcp-1b 20261101014251 도구 ⑥ sales_summary · mcp-cap-1 2026-11-07 ⑥ 에 offset · limit 500 — DB 20261107051447 · mcp-conc-1 2026-11-08 ⑥ busy 재시도 — DB 20261108160000 자리 3)
//   mcp-conc-1(판정 1105 ~ 1110): DB mcp_sales 는 자리 3 칸(직원 전체) · 다 차면 기다리지 않고 즉시 PT429(HTTP 429 · 몸 code "PT429") · 이 EF 가 0.3 · 0.6 · 1.2 s 기다렸다 다시(최대 3 번 · busyRetry 도구만 = sales_summary) · 그래도 busy 면 isError + BUSY_TEXT(하나씩 · offset 으로) · 기록(924)은 마지막 결과 한 줄 — outcome error · error_code busy · ms 는 재시도 포함(1107)
//   EF ims-mcp/index.ts 가 Deno.serve + deps 주입만 · 시험 ims-mcp/mcp_test.ts 가 fetch 를 가짜로(qbo · freightcom 꼴)
//   규격: modelcontextprotocol.io 2025-06-18 — Streamable HTTP(POST 한 건 · 배열(batch) 없음 · 알림 · 응답은 202 빈 몸 · GET 은 SSE 없으면 405 · DELETE 405 MAY · Mcp-Session-Id 는 MAY → 안 낸다 · MCP-Protocol-Version 머리가 지원 밖이면 400)
//         인증: 토큰 없음 · 무효 → HTTP 401 + WWW-Authenticate: Bearer resource_metadata="<보호 자원 문서>"(RFC 9728) · 문서는 GET …/ims-mcp/.well-known/oauth-protected-resource(인증 없이)
//         ⚠️ 권한 거절(42501 · mcp_gate P0001)은 401 이 아니다 — 401 이면 Claude 가 로그인을 무한히 돈다 → tools/call 결과 isError:true + 직원이 읽을 한 문장 · 모르는 도구 · 인자 틀림 → JSON-RPC -32602(규격 Protocol Errors)
//   토큰: GET /auth/v1/user(apikey ANON + 그 토큰)가 유효하다고 한 뒤에만 같은 토큰의 payload(client_id · sub)를 읽는다 · 도구는 POST /rest/v1/rpc/mcp_*(apikey ANON · Authorization = 받은 토큰 그대로 · service_role 금지 · 9 초 abort)
//   기록(924): tools/call 마다 끝에서 mcp_log_add 를 service_role 로 · 입력값은 2 KB(넘으면 {_truncated, chars, head}) · 결과 내용은 적지 않는다(바이트 수만) · 기록 실패는 삼키고 warn
//   ⚠️ 토큰은 로그 · 기록 · 응답 · 오류 글 어디에도 싣지 않는다
// ============================================================
export const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26"] as const;
export const DEFAULT_PROTOCOL = "2025-06-18";
export const SERVER_INFO = { name: "asung-ims", title: "Asung IMS", version: "mcp-conc-1" };
export const INSTRUCTIONS = "Asung IMS, read only. Amounts are CAD. Warehouses: Asung Trading Inc. (Toronto) and Asung - Edmonton. Anything not in a result is not available through this connector — check the IMS screens.";
export const RPC_TIMEOUT_MS = 9_000;
export const ARGS_MAX_CHARS = 2_048;
export const ERROR_MESSAGE_MAX = 200;
export const FUNCTION_PATH = "/functions/v1/ims-mcp";
export const BUSY_RETRY_MS = [300, 600, 1200] as const;                                              // mcp-conc-1(1109): busy(PT429) 면 이만큼 기다렸다 다시 — 최대 3 번 · DB 연결은 쥐지 않는다
export const BUSY_TEXT = "IMS is busy with other sales reports right now (at most 3 sales summaries run at once across all staff). Wait about 10 seconds and call sales_summary again — one call at a time, waiting for each result — and page with offset instead of splitting by brand or supplier.";
const isBusy = (status: number, code: string) => status === 429 || code === "PT429";                   // PostgREST: raise … errcode PT429 → HTTP 429 · 몸 code "PT429"

type Schema = { type: string | string[]; properties?: Record<string, Schema>; required?: string[]; additionalProperties?: boolean; enum?: unknown[]; minimum?: number; maximum?: number; description?: string };
export type ToolDef = { name: string; title: string; description: string; inputSchema: Schema; annotations: { readOnlyHint: true }; rpc: string; args: (a: Record<string, unknown>) => Record<string, unknown>; busyRetry?: true };   // busyRetry: DB 자리표가 있는 도구만(mcp-conc-1 · 1108 — sales_summary)
const NO_CONTACT = " Does not return addresses, phone numbers, emails, notes or costs.";
// ⭐ 도구 목록은 이 배열 하나 — mcp-1b 가 ⑥ sales_summary(mcp_sales) 를 더했다(2026-11-01)
export const TOOLS: ToolDef[] = [
  { name: "find_order", title: "Find a sales order", description: "Look up one IMS sales order by its number (SO-25001 or just 25001): status, dates, customer name, lines with prices and quantities, totals, tax, invoice, carrier and tracking number." + NO_CONTACT,
    inputSchema: { type: "object", properties: { so_number: { type: "string", description: "Sales order number, e.g. SO-25001" } }, required: ["so_number"], additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_order", args: (a) => ({ p_so_number: a.so_number }) },
  { name: "stock", title: "Stock availability", description: "Search stock by SKU, barcode, product name or brand: on hand, allocated, available, on order, in transit — per warehouse or both warehouses combined. Use for 'do we have X', 'how many Y in Edmonton'." + NO_CONTACT,
    inputSchema: { type: "object", properties: { query: { type: "string", description: "SKU, barcode, product name or brand" }, warehouse: { type: "string", description: "Warehouse name or city (Toronto, Edmonton). Omit for both." }, limit: { type: "integer", minimum: 1, maximum: 50, description: "Rows to return (default 20, max 50)" } }, required: ["query"], additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_stock", args: (a) => ({ p_q: a.query, p_warehouse: a.warehouse ?? null, p_limit: a.limit ?? 20 }) },
  { name: "customer_summary", title: "Customer summary", description: "Find a customer by name: price tier, payment term, currency, default warehouse, bill-to and parent names, account balance, overdue invoices and the 10 most recent sales orders. If the name is not unique you get up to 5 candidates to choose from." + NO_CONTACT,
    inputSchema: { type: "object", properties: { name: { type: "string", description: "Customer name (full or partial)" } }, required: ["name"], additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_customer", args: (a) => ({ p_q: a.name }) },
  { name: "po_status", title: "Purchase order status", description: "Look up one purchase order by its number (PO-02056 or just 02056): status, supplier name, dates, lines with ordered / received / remaining quantities and the receipts. No prices, costs, invoices, payments or supplier contacts.",
    inputSchema: { type: "object", properties: { po_number: { type: "string", description: "Purchase order number, e.g. PO-02056" } }, required: ["po_number"], additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_po", args: (a) => ({ p_po_number: a.po_number }) },
  { name: "backorders", title: "Backorders", description: "List backordered and pre-ordered sales lines, optionally filtered by customer, brand, warehouse, SKU, state (open, ended, all), kind (backorder, preorder), owed or arrived. Names that are not unique come back as candidates." + NO_CONTACT,
    inputSchema: { type: "object", properties: {
      filters: { type: "object", additionalProperties: false, properties: { customer: { type: "string" }, brand: { type: "string" }, warehouse: { type: "string" }, sku: { type: "string" }, state: { type: "string", enum: ["open", "ended", "all"] }, kind: { type: "string", enum: ["backorder", "preorder"] }, owed: { type: "boolean" }, arrived: { type: "boolean" } } },
      limit: { type: "integer", minimum: 1, maximum: 100, description: "Rows to return (default 50, max 100)" } }, additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_backorders", args: (a) => ({ p_filters: a.filters ?? {}, p_limit: a.limit ?? 50 }) },
  // ⑥ mcp-1b(판정 918 ~ 920 · 925 ~ 930): 날짜는 글자 그대로 DB 로(검사 · 영어 한 문장은 mcp_sales 가) · 원가 열쇠가 없으면 결과에 cogs · gp 열쇠 자체가 없다(919)
  //    mcp-cap-1(2026-11-07): offset(≥ 0 · 기본 0) · limit 최대 500 · 응답 page{offset, limit, shown, total_rows, next_offset} · rows_truncated = 이 쪽에 안 보인 줄 전부(앞 + 뒤) · 설명 글이 「next_offset 이 null 이 아니면 차례로 · 동시에 부르지 마라」 를 Claude 에게 말한다 · 응답은 자르지 않는다
  { name: "sales_summary", title: "Sales summary", description: "Sales for a date range grouped by brand, customer, month, sku or supplier, optionally filtered by brand, customer, SKU or supplier name: sales, credits, net, quantities, and (only if your account may see costs) COGS, gross profit and GP %. Product lines only, CAD, before tax; freight, services, order discounts and adjustments are listed separately under 'other'. Customer rows combine a head office with its accounts. Totals are computed by IMS — do not add rows yourself. Names that are not unique come back as candidates. Paging: at most 500 rows per call; the response's 'page' has offset, limit, shown, total_rows and next_offset. If next_offset is not null, call again with offset = next_offset to get the following rows — one page at a time, never pages in parallel (each page re-runs the whole aggregation on the live database and takes a few seconds; ask for the next page only when you need more rows). 'totals', 'other' and 'rows_truncated' describe the whole result, not just this page: use totals once, and rows_truncated counts the rows not on this page. If you need every SKU, page through one call instead of splitting by brand. Does not return addresses, phone numbers, emails or notes.",
    inputSchema: { type: "object", properties: {
      from: { type: "string", description: "Start date YYYY-MM-DD (inclusive)" }, to: { type: "string", description: "End date YYYY-MM-DD (inclusive, at most 3 years after from)" },
      group: { type: "string", enum: ["brand", "customer", "month", "sku", "supplier"], description: "How to group the rows" },
      brand: { type: "string", description: "Brand name (full or partial)" }, customer: { type: "string", description: "Customer name (full or partial); an account name limits to that account, a head office includes its accounts" },
      sku: { type: "string", description: "SKU (exact or partial)" }, supplier: { type: "string", description: "Supplier name (full or partial); uses each product's default supplier" },
      limit: { type: "integer", minimum: 1, maximum: 500, description: "Rows to return in this page (default 50, max 500); rows not on this page are summarized in rows_truncated" },
      offset: { type: "integer", minimum: 0, description: "Rows to skip (default 0); pass next_offset from the previous page to continue" } }, required: ["from", "to", "group"], additionalProperties: false },
    annotations: { readOnlyHint: true }, rpc: "mcp_sales", busyRetry: true, args: (a) => ({ p_from: a.from, p_to: a.to, p_group: a.group, p_brand: a.brand ?? null, p_customer: a.customer ?? null, p_sku: a.sku ?? null, p_supplier: a.supplier ?? null, p_limit: a.limit ?? 50, p_offset: a.offset ?? 0 }) },
];

export type Deps = {
  env: (name: string) => string | undefined;                                                         // SUPABASE_URL · SUPABASE_ANON_KEY · SUPABASE_SERVICE_ROLE_KEY
  fetch: (url: string, init: RequestInit) => Promise<Response>;                                      // Supabase 만(auth · rest)
  now: () => number;
  warn: (msg: string) => void;                                                                       // 토큰 없는 글만 온다
  sleep: (ms: number) => Promise<void>;                                                              // mcp-conc-1: busy 재시도 사이 기다림(시험은 가짜)
};
export type LogRow = { p_auth_user_id: string | null; p_client_id: string | null; p_tool: string; p_args: unknown; p_ms: number; p_outcome: "ok" | "refused" | "error"; p_error_code: string | null; p_error_message: string | null; p_result_bytes: number | null };

// ── 순수 도우미 ──
const sbUrl = (d: Deps) => (d.env("SUPABASE_URL") ?? "").replace(/\/+$/, "");
export const resourceUrl = (supabaseUrl: string): string => supabaseUrl.replace(/\/+$/, "") + FUNCTION_PATH;
export const metadataUrl = (supabaseUrl: string): string => resourceUrl(supabaseUrl) + "/.well-known/oauth-protected-resource";
export const metadataDoc = (supabaseUrl: string) => ({ resource: resourceUrl(supabaseUrl), authorization_servers: [supabaseUrl.replace(/\/+$/, "") + "/auth/v1"], bearer_methods_supported: ["header"] });
export const isMetadataPath = (pathname: string): boolean => /\/\.well-known\/oauth-protected-resource\/?$/.test(pathname);
export const isMcpPath = (pathname: string): boolean => /(^|\/)ims-mcp\/?$/.test(pathname);
export function decodePayload(jwt: string): Record<string, unknown> | null {
  try {
    const p = jwt.split(".")[1]; if (!p) return null;
    const b = atob(p.replace(/-/g, "+").replace(/_/g, "/").padEnd(p.length + (4 - p.length % 4) % 4, "="));
    const j = JSON.parse(new TextDecoder().decode(Uint8Array.from(b, (c) => c.charCodeAt(0))));
    return j && typeof j === "object" ? j : null;
  } catch { return null; }
}
export function clipArgs(args: unknown): unknown {
  const s = JSON.stringify(args ?? {});
  return s.length <= ARGS_MAX_CHARS ? (args ?? {}) : { _truncated: true, chars: s.length, head: s.slice(0, 2000) };
}
// 작은 JSON Schema 검사(type · required · additionalProperties · enum · minimum · maximum) — 틀리면 사람 말 한 문장 · 맞으면 null
export function validateArgs(schema: Schema, value: unknown, path = "arguments"): string | null {
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  const t = value === null ? "null" : Array.isArray(value) ? "array" : typeof value;
  const okType = types.some((x) => x === t || (x === "integer" && t === "number" && Number.isInteger(value)) || (x === "number" && t === "number"));
  if (!okType) return `${path} must be ${types.join(" or ")}`;
  if (schema.enum && !schema.enum.includes(value)) return `${path} must be one of ${schema.enum.join(", ")}`;
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) return `${path} must be at least ${schema.minimum}`;
    if (schema.maximum !== undefined && value > schema.maximum) return `${path} must be at most ${schema.maximum}`;
  }
  if (t === "object") {
    const o = value as Record<string, unknown>;
    for (const k of schema.required ?? []) if (o[k] === undefined) return `${path}.${k} is required`;
    for (const [k, v] of Object.entries(o)) {
      const sub = schema.properties?.[k];
      if (!sub) { if (schema.additionalProperties === false) return `${path}.${k} is not a known field`; continue; }
      const e = validateArgs(sub, v, `${path}.${k}`); if (e) return e;
    }
  }
  return null;
}
const json = (status: number, obj: unknown, extra: Record<string, string> = {}): Response => new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", ...extra } });
const rpcErr = (id: unknown, code: number, message: string, data?: unknown) => ({ jsonrpc: "2.0", id: id ?? null, error: data === undefined ? { code, message } : { code, message, data } });
const rpcOk = (id: unknown, result: unknown) => ({ jsonrpc: "2.0", id, result });
const unauthorized = (d: Deps, why: string): Response => json(401, { error: "unauthorized", message: why }, { "WWW-Authenticate": `Bearer resource_metadata="${metadataUrl(sbUrl(d))}"` });
const methodNotAllowed = (): Response => new Response(null, { status: 405, headers: { Allow: "POST" } });

// ── 토큰 → 신원: /auth/v1/user 가 유효하다고 한 뒤에만 payload 를 읽는다 ──
type Who = { token: string; authUserId: string; clientId: string | null };
async function whoIs(req: Request, d: Deps): Promise<Who | Response> {
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return unauthorized(d, "Missing bearer token");
  let r: Response;
  try { r = await d.fetch(sbUrl(d) + "/auth/v1/user", { method: "GET", headers: { apikey: d.env("SUPABASE_ANON_KEY") ?? "", Authorization: "Bearer " + token } }); }
  catch (e) { return json(502, { error: "auth_unreachable", message: "IMS could not verify the token right now: " + String((e as Error)?.message ?? e).slice(0, 120) }); }
  if (r.status === 401 || r.status === 403) return unauthorized(d, "Token is invalid or expired");
  if (!r.ok) return json(502, { error: "auth_failed", message: "IMS token check failed (" + r.status + ")" });
  const uid = String(((await r.json()) as { id?: unknown })?.id ?? "");
  const p = decodePayload(token);
  const sub = p ? String(p.sub ?? p.user_id ?? "") : "";                                           // Supabase 문서: OAuth 토큰 클레임 = user_id · role · client_id(sub 는 짐작) — 있으면 /auth/v1/user 의 id 와 같아야 한다
  if (!uid || !p || (sub && sub !== uid)) return unauthorized(d, "Token subject mismatch");
  return { token, authUserId: uid, clientId: typeof p.client_id === "string" ? p.client_id : null };
}

async function logCall(d: Deps, row: LogRow): Promise<void> {
  try {
    const svc = d.env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const r = await d.fetch(sbUrl(d) + "/rest/v1/rpc/mcp_log_add", { method: "POST", headers: { apikey: svc, Authorization: "Bearer " + svc, "Content-Type": "application/json" }, body: JSON.stringify(row) });
    if (!r.ok) d.warn("mcp_log_add failed " + r.status + ": " + (await r.text()).slice(0, 200));
  } catch (e) { d.warn("mcp_log_add threw: " + String((e as Error)?.message ?? e).slice(0, 200)); }
}

// ── tools/call — 인자 검사 → rpc(사용자 토큰) → content text · isError · 기록 한 줄 ──
async function callTool(d: Deps, who: Who, id: unknown, params: Record<string, unknown>): Promise<Response> {
  const t0 = d.now();
  const name = String(params?.name ?? "");
  const args = (params?.arguments && typeof params.arguments === "object" && !Array.isArray(params.arguments) ? params.arguments : {}) as Record<string, unknown>;
  const tool = TOOLS.find((t) => t.name === name);
  const base = { p_auth_user_id: who.authUserId, p_client_id: who.clientId, p_tool: name || "(none)", p_args: clipArgs(args), p_result_bytes: null as number | null };
  if (!tool) {
    await logCall(d, { ...base, p_ms: d.now() - t0, p_outcome: "error", p_error_code: "unknown_tool", p_error_message: "Unknown tool: " + name.slice(0, 80) });
    return json(200, rpcErr(id, -32602, "Unknown tool: " + name.slice(0, 80)));
  }
  const bad = validateArgs(tool.inputSchema, args);
  if (bad) {
    await logCall(d, { ...base, p_ms: d.now() - t0, p_outcome: "error", p_error_code: "invalid_params", p_error_message: bad.slice(0, ERROR_MESSAGE_MAX) });
    return json(200, rpcErr(id, -32602, "Invalid arguments: " + bad));
  }
  let outcome: LogRow["p_outcome"] = "error", code: string | null = null, msg: string | null = null, text = "";
  try {
    // mcp-conc-1(1109): busy(PT429 / 429) 면 busyRetry 도구만 0.3 · 0.6 · 1.2 s 기다렸다 다시(최대 3 번 · 회차마다 9 초 abort) · 그래도 busy 면 BUSY_TEXT · 기록은 마지막 결과 한 줄(ms 는 재시도 포함)
    for (let attempt = 0; ; attempt++) {
      const r = await d.fetch(sbUrl(d) + "/rest/v1/rpc/" + tool.rpc, { method: "POST", headers: { apikey: d.env("SUPABASE_ANON_KEY") ?? "", Authorization: "Bearer " + who.token, "Content-Type": "application/json" }, body: JSON.stringify(tool.args(args)), signal: AbortSignal.timeout(RPC_TIMEOUT_MS) });
      const body = await r.text();
      if (r.ok) { outcome = "ok"; text = body; code = null; msg = null; break; }                       // 재시도 뒤 ok 면 앞 회차의 busy code · msg 를 지운다(기록은 마지막 결과 한 줄)
      let j: { code?: unknown; message?: unknown } = {};
      try { j = JSON.parse(body); } catch { /* 글자 그대로 */ }
      code = String(j.code ?? r.status); msg = String(j.message ?? body.slice(0, 200));
      if (isBusy(r.status, code)) {
        if (tool.busyRetry && attempt < BUSY_RETRY_MS.length) { await d.sleep(BUSY_RETRY_MS[attempt]); continue; }
        outcome = "error"; code = "busy"; msg = BUSY_TEXT; break;
      }
      outcome = code === "42501" || code === "P0001" ? "refused" : "error";
      if (code === "42501") msg = "IMS refused this call: " + msg + " — the Claude connector role is not active for this login (connector not switched on, or this OAuth client is not registered) — ask an admin";
      else if (outcome === "error") msg = "IMS could not run this tool (" + code + "): " + msg;
      break;
    }
  } catch (e) {
    const aborted = (e as Error)?.name === "TimeoutError" || (e as Error)?.name === "AbortError";
    code = aborted ? "timeout" : "fetch"; msg = aborted ? "IMS took longer than " + RPC_TIMEOUT_MS / 1000 + " seconds — try a narrower question" : "IMS unreachable: " + String((e as Error)?.message ?? e).slice(0, 120);
  }
  await logCall(d, { ...base, p_ms: d.now() - t0, p_outcome: outcome, p_error_code: code, p_error_message: msg ? msg.slice(0, ERROR_MESSAGE_MAX) : null, p_result_bytes: outcome === "ok" ? text.length : null });
  return outcome === "ok" ? json(200, rpcOk(id, { content: [{ type: "text", text }], isError: false }))
                          : json(200, rpcOk(id, { content: [{ type: "text", text: msg ?? "IMS error" }], isError: true }));
}

// ── 입구 ──
export async function handle(req: Request, d: Deps): Promise<Response> {
  const url = new URL(req.url);
  if (req.method === "GET" && isMetadataPath(url.pathname)) return json(200, metadataDoc(sbUrl(d)));
  if (!isMcpPath(url.pathname)) return json(404, { error: "not_found" });
  if (req.method !== "POST") return methodNotAllowed();                                              // GET(SSE 없음) · DELETE(세션 없음) · OPTIONS → 405
  const who = await whoIs(req, d); if (who instanceof Response) return who;
  const pv = req.headers.get("MCP-Protocol-Version");
  if (pv && !(PROTOCOL_VERSIONS as readonly string[]).includes(pv)) return json(400, rpcErr(null, -32600, "Unsupported MCP-Protocol-Version: " + pv.slice(0, 40), { supported: PROTOCOL_VERSIONS }));
  let m: unknown;
  try { m = await req.json(); } catch { return json(400, rpcErr(null, -32700, "Parse error: body must be one JSON-RPC 2.0 message")); }
  if (Array.isArray(m)) return json(400, rpcErr(null, -32600, "JSON-RPC batching is not supported (MCP 2025-06-18)"));
  if (!m || typeof m !== "object") return json(400, rpcErr(null, -32600, "Invalid request"));
  const msg = m as { jsonrpc?: unknown; id?: unknown; method?: unknown; params?: unknown; result?: unknown; error?: unknown };
  if (msg.method === undefined) return new Response(null, { status: 202 });                        // 클라이언트의 응답(result · error) — 서버가 요청을 보내지 않으니 버린다
  if (msg.id === undefined || msg.id === null) return new Response(null, { status: 202 });          // 알림(notifications/initialized · cancelled · …)
  const id = msg.id, method = String(msg.method), params = (msg.params && typeof msg.params === "object" ? msg.params : {}) as Record<string, unknown>;
  if (msg.jsonrpc !== "2.0") return json(200, rpcErr(id, -32600, "jsonrpc must be \"2.0\""));
  switch (method) {
    case "initialize": {
      const asked = String(params.protocolVersion ?? "");
      const v = (PROTOCOL_VERSIONS as readonly string[]).includes(asked) ? asked : DEFAULT_PROTOCOL;
      return json(200, rpcOk(id, { protocolVersion: v, capabilities: { tools: {} }, serverInfo: SERVER_INFO, instructions: INSTRUCTIONS }));
    }
    case "ping": return json(200, rpcOk(id, {}));
    case "tools/list": return json(200, rpcOk(id, { tools: TOOLS.map(({ name, title, description, inputSchema, annotations }) => ({ name, title, description, inputSchema, annotations })) }));
    case "tools/call": return await callTool(d, who, id, params);
    default: return json(200, rpcErr(id, -32601, "Method not found: " + method.slice(0, 60)));
  }
}
