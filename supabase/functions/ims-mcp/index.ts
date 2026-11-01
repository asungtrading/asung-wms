// ============================================================
// ASUNG IMS — Edge Function: ims-mcp (mcp-2 · 2026-11-01 · 판정 917 ~ 924 · 순수 처리 ../_shared/mcp.ts · 시험 ./mcp_test.ts)
//   Claude 커스텀 커넥터(원격 MCP · Streamable HTTP · 2025-06-18)의 서버 — 도구 5(find_order · stock · customer_summary · po_status · backorders) · 읽기 전용 · 무상태(세션 없음 · SSE 없음)
//   ⚠️ 이 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg)가 메인(617) · 배포: supabase functions deploy ims-mcp --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.ims-mcp] verify_jwt=false — 게이트웨이 401 에는 WWW-Authenticate 를 못 붙인다)
//   길: GET …/ims-mcp/.well-known/oauth-protected-resource(인증 없음 · RFC 9728 문서) · POST …/ims-mcp(JSON-RPC 한 건 · Bearer 토큰 → /auth/v1/user 로 확인 · 도구는 rpc/mcp_* 를 그 토큰으로) · 그 밖 405
//   기록: tools/call 마다 mcp_log_add(service_role · 924) · 비밀: 없음(SUPABASE_* 자동 주입만) · 토큰은 응답 · 기록 · console 어디에도 안 남는다
// ============================================================
import { handle, type Deps } from "../_shared/mcp.ts";

const deps: Deps = {
  env: (name) => Deno.env.get(name),
  fetch: (url, init) => fetch(url, init),
  now: () => Date.now(),
  warn: (msg) => console.warn("[ims-mcp] " + msg.slice(0, 500)),
};

Deno.serve(async (req) => {
  try { return await handle(req, deps); }
  catch (e) {
    console.error("[ims-mcp] unhandled: " + String((e as Error)?.message ?? e).slice(0, 300));
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32603, message: "Internal error" } }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
