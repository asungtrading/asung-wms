// doc — 서버 PDF 일꾼(doc-2 · 2026-10-19 · 판정 523) — 판(doc_template) + 데이터(doc_data) → mustache → Gotenberg(Cloud Run 토론토) → 비공개 버킷 documents + doc_file 한 줄 → 짧은 서명 URL
//   ⚠️ 테스트 프로젝트(fazgmyvzzhqybtvtktyg)에 먼저 · 운영은 컷오버 때 · config.toml [functions.doc] verify_jwt = false(문은 여기서 — 두 길)
//   문 둘: ① 직원 JWT(Authorization: Bearer <access_token>) — 그 JWT 로 DB 를 부른다(doc_data · doc_template_get 의 문 · RLS 가 그대로 걸린다 · ship_ready 도 된다)
//          ② service(x-ims-cron-key == secret IMS_CRON_SECRET · 뒤 차수 doc-3 메일 일꾼) — service_role 로 DB · ship_ready 는 거부(doc-1b2 이견 7)
//   POST {"action": "render", "kind", "ref", "reason", "template_id"?}  → {ok, template_id, template_version, files: [{doc_file_id, path, bytes, pages, doc_number, group, signed_url, expires_in}]}
//        {"action": "url", "doc_file_id"}                                 → {ok, path, signed_url, expires_in}(문 = doc_file_get 을 부르는 쪽의 신원)
//        {"action": "status"}                                             → {ok, secrets: {…: true|false}, gotenberg: {reachable, status, body}}
//   비밀: GOTENBERG_URL · GOTENBERG_USER · GOTENBERG_PASS(tools/gotenberg-secrets.sh) · IMS_CRON_SECRET(기존) — 값은 로그 · 응답 · DB 어디에도 남기지 않는다
//   저장: documents/<kind>/<번호>-t<판>-<시각>.pdf · doc_file_add(service_role) · 서명 URL = POST /storage/v1/object/sign/documents/<path> {expiresIn}(supabase/storage getSignedURL.ts · 2026-10-19 읽음)
import { gate, isKind, renderAll, SIGN_SECONDS, type Auth, type Deps, type GOutcome, type Kind, type Template } from "../_shared/doc.ts";

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS } });
const GOTENBERG_TIMEOUT_MS = 58_000, STORAGE_TIMEOUT_MS = 30_000;   // Cloud Run 60 s · 첫 호출 4 s 실측(0 대에서 깨어남)

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
function authOf(req: Request): Auth | null {
  const key = req.headers.get("x-ims-cron-key"), secret = Deno.env.get("IMS_CRON_SECRET") ?? "";
  if (key !== null) return secret && sameSecret(key, secret) ? { mode: "service" } : null;
  const tok = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!tok || tok === ANON()) return null;                                                    // anon 키를 Bearer 로 내민 것은 로그인이 아니다
  return { mode: "staff", jwt: tok };
}
function dbHeaders(auth: Auth): HeadersInit {
  return auth.mode === "service" ? { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" }
                                 : { apikey: ANON(), Authorization: "Bearer " + auth.jwt, "Content-Type": "application/json" };
}
async function rpc(auth: Auth, fn: string, args: Record<string, unknown>): Promise<any> {
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers: dbHeaders(auth), body: JSON.stringify(args) });
  const text = await r.text();
  if (!r.ok) {
    let msg = text.slice(0, 300);
    try { msg = JSON.parse(text)?.message ?? msg; } catch { /* plain */ }
    throw new Error(`${fn}: ${msg}`);
  }
  return text ? JSON.parse(text) : null;
}
async function gotenberg(html: string): Promise<GOutcome> {
  const url = Deno.env.get("GOTENBERG_URL") ?? "", user = Deno.env.get("GOTENBERG_USER") ?? "", pass = Deno.env.get("GOTENBERG_PASS") ?? "";
  if (!url || !user || !pass) throw new Error("Gotenberg secrets are not set (GOTENBERG_URL · GOTENBERG_USER · GOTENBERG_PASS)");
  const { gotenbergRequest } = await import("../_shared/doc.ts");
  const q = gotenbergRequest(url, user, pass, html);
  try {
    const r = await fetch(q.url, { method: "POST", headers: q.headers, body: q.form, signal: AbortSignal.timeout(GOTENBERG_TIMEOUT_MS) });
    const trace = r.headers.get("gotenberg-trace");
    if (r.ok) return { kind: "http", status: r.status, bytes: new Uint8Array(await r.arrayBuffer()), text: "", trace };
    return { kind: "http", status: r.status, bytes: new Uint8Array(0), text: (await r.text()).slice(0, 500), trace };
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    return name === "TimeoutError" || name === "AbortError" ? { kind: "timeout" } : { kind: "network", message: String((e as Error)?.message ?? e).slice(0, 200) };
  }
}
async function upload(path: string, bytes: Uint8Array): Promise<void> {
  const r = await fetch(SB_URL() + "/storage/v1/object/documents/" + path, { method: "POST", headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/pdf" }, body: bytes.slice(), signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });   // slice: BodyInit 타입(Uint8Array<ArrayBuffer>)
  if (!r.ok) throw new Error(`storage upload ${r.status}: ${(await r.text()).slice(0, 200)}`);
}
async function sign(path: string): Promise<string> {
  const r = await fetch(SB_URL() + "/storage/v1/object/sign/documents/" + path, { method: "POST", headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" }, body: JSON.stringify({ expiresIn: SIGN_SECONDS }), signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });
  if (!r.ok) throw new Error(`storage sign ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const s = String(j?.signedURL ?? "");
  if (!s) throw new Error("storage sign: no signedURL in the answer");
  return s.startsWith("http") ? s : SB_URL() + "/storage/v1" + (s.startsWith("/") ? "" : "/") + s;
}
async function staffIdOf(auth: Auth): Promise<string | null> {
  if (auth.mode === "service") return null;
  const r = await fetch(SB_URL() + "/rest/v1/ims_staff?select=id&is_active=is.true&limit=1", { headers: { apikey: ANON(), Authorization: "Bearer " + auth.jwt } });   // RLS 가 자기 행만 보이면 그것 · 아니면 doc_data 의 문이 이미 걸렀다
  if (!r.ok) return null;
  const rows = await r.json();
  return rows.length === 1 ? String(rows[0].id) : null;
}
function deps(auth: Auth, staffId: string | null): Deps {
  const svc: Auth = { mode: "service" };
  return {
    getTemplate: async (kind: Kind, templateId: string | null): Promise<Template> => {
      let id = templateId;
      if (!id) {
        const cfg = await rpc(auth, "doc_config", {});
        id = cfg?.active?.[kind]?.template_id ?? null;
        if (!id) throw new Error(`no layout is in use for ${kind} — publish one in Settings → Documents`);
      }
      const t = await rpc(auth, "doc_template_get", { p_template_id: id });
      if (!t) throw new Error("layout version not found");
      return { id: t.id, kind: t.kind, version: t.version, body: t.body, ok: t.check_result?.ok === true };
    },
    getData: (kind: Kind, ref: unknown) => rpc(auth, "doc_data", { p_kind: kind, p_ref: ref }),
    convert: gotenberg,
    upload,
    addFile: async (row) => { const r = await rpc(svc, "doc_file_add", { p: row }); return { id: String(r.id) }; },
    sign,
    now: () => new Date(),
    staffId,
  };
}

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    const auth = authOf(req);
    if (!auth) return json(401, { ok: false, error: "unauthorized — send a staff login (Authorization: Bearer) or the service key header" });
    const body = await req.json().catch(() => ({}));
    if (body.action === "status") {
      const url = Deno.env.get("GOTENBERG_URL") ?? "";
      let g: Record<string, unknown> = { reachable: false, status: null, body: "GOTENBERG_URL not set" };
      if (url) {
        try {
          const { basicAuth } = await import("../_shared/doc.ts");
          const r = await fetch(url.replace(/\/+$/, "") + "/health", { headers: { Authorization: basicAuth(Deno.env.get("GOTENBERG_USER") ?? "", Deno.env.get("GOTENBERG_PASS") ?? "") }, signal: AbortSignal.timeout(20_000) });
          g = { reachable: true, status: r.status, body: (await r.text()).slice(0, 300) };
        } catch (e) { g = { reachable: false, status: null, body: String((e as Error)?.message ?? e).slice(0, 200) }; }
      }
      return json(200, { ok: true, auth: auth.mode, secrets: { GOTENBERG_URL: !!url, GOTENBERG_USER: !!Deno.env.get("GOTENBERG_USER"), GOTENBERG_PASS: !!Deno.env.get("GOTENBERG_PASS"), IMS_CRON_SECRET: !!Deno.env.get("IMS_CRON_SECRET") }, gotenberg: g });
    }
    if (body.action === "url") {
      if (!/^[0-9a-f-]{36}$/i.test(String(body.doc_file_id ?? ""))) return json(400, { ok: false, error: "doc_file_id must be a uuid" });
      const f = await rpc(auth, "doc_file_get", { p_id: body.doc_file_id });                 // 문 = 부르는 쪽의 신원(활성 직원 · service)
      return json(200, { ok: true, doc_file_id: f.id, path: f.path, bytes: f.bytes, pages: f.pages, signed_url: await sign(String(f.path)), expires_in: SIGN_SECONDS });
    }
    if (body.action === "render") {
      const r = { kind: String(body.kind ?? ""), ref: body.ref, reason: String(body.reason ?? ""), template_id: body.template_id ?? null };
      const g = gate(r, auth);
      if (g) return json(400, { ok: false, error: g });
      if (!isKind(r.kind)) return json(400, { ok: false, error: "kind" });
      const out = await renderAll(deps(auth, await staffIdOf(auth)), r, auth);
      return json(200, { ok: true, ...out });
    }
    return json(400, { ok: false, error: "action must be render, url or status" });
  } catch (e) {
    const msg = String((e as Error)?.message ?? e).slice(0, 400);
    console.error("doc failed:", msg);
    return json(500, { ok: false, error: msg });
  }
});
