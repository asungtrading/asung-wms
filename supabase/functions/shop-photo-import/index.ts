// ============================================================
// ASUNG IMS — Edge Function: shop-photo-import (shop-photo-imp-2b-2 · 2026-11-12 · 판정 1182 · 1183 · 1185 · 1198 · deferred 387 가져오기 길 ②-b)
//   Shopify 에만 있던 사진 818 장을 IMS(저장소 product-images + product_image · source shopify)로 — 계획(shop_photo_plan · 2a)대로 · 실행 날 Shopify 를 다시 읽어 확인한 줄만
//   POST { mode, only?, owners?, retry_failed?, restart? }
//     selftest  바깥 호출 0 — 이 런타임의 md5 · 형식 판별이 맞는지(200 으로 바로 답한다)
//     check     계획 줄 확인 + 계획 · 짝 밖 Shopify 사진 · 이름 줄기 겹침 목록      (202 · 결과는 shop_photo_run)
//     pairs     짝 줄 확인 → 없으면 gone · same 짝은 shop_media 에 심는다               (202 · 결과는 shop_photo_run)
//     move      claim → CDN → 대조 → 저장소 → 등록(사진 행 + 짝 + 웹 대표 한 몸)        (202 · 결과는 shop_photo_run)
//     only = 계획 줄 id 목록(몇 곳만 먼저 · check · pairs · move 모두) · owners = move 한 회차의 주인 수(1 ~ 60) · retry_failed = failed 줄도 다시 · restart = 이어 달리기 자리를 버리고 처음부터
//   문(shopify EF 와 같은 두 길 — 같은 꼴을 여기 복사): cron 길 x-ims-cron-key == IMS_CRON_SECRET(미설정 500 fail-closed) · 직원 길 세션 JWT → rpc/ims_can_write('shopify')
//   cron 등록 없음 — 사람이 부르고 「남은 0」 까지 다시 부른다(check · pairs 는 직전 회차가 남긴 자리 뒤부터 · move 는 claim 이 남은 줄을 내준다)
//   Shopify 에는 읽기만(product media) · 쓰기는 IMS 저장소와 2a 창구(shop_photo_verify_mark · pair_mark · claim · done · fail · run_add — service_role · EF 안에서만) · 표 직접 쓰기 0
//   ⚠️ 이 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg)가 메인 · 시작 때 inv_config.db_role = test 확인 · 배포: supabase functions deploy shop-photo-import --project-ref fazgmyvzzhqybtvtktyg
//   판단 · 흐름은 전부 ./core.ts(순수 · deno test) — 이 파일은 문 · 실제 Io · 기록
// ============================================================
import { shopifyGql, sleep, type StoreRow } from "../_shared/shopify.ts";
import { buildSkuMap, chunk, parseProducts, pickBody, PRODUCT_NODES_QUERY, resumeAfter, runCheck, runMove, runPairs, selftest, type Ctx, type Io } from "./core.ts";

const BUCKET = "product-images";
const STORE_COLS = "id,code,shop_domain,secret_prefix,is_active,live,auth_mode,label,kind";
const ID_CHUNK = 50;                                                         // id=in.() 한 번의 수(URL 길이 · 판정 894 꼴)
const DOWNLOAD_TIMEOUT_MS = 30_000;
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
let running = false;

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const json = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } });
const sbHeaders = (extra: Record<string, string> = {}): HeadersInit => ({ apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json", ...extra });
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbAll(path: string, order = "id.asc"): Promise<any[]> {                              // PostgREST 1,000 행 캡
  const out: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    const rows = await sbGet(path + (path.includes("?") ? "&" : "?") + "order=" + order + "&limit=1000&offset=" + offset);
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}
async function sbRpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers: sbHeaders(), body: JSON.stringify(args) });
  if (!r.ok) throw new Error("rpc " + fn + " " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
const inList = async (path: string, col: string, ids: string[], order: string): Promise<any[]> => (await Promise.all(chunk([...new Set(ids)], ID_CHUNK).map((part) => sbAll(path + "&" + col + "=in.(" + part.join(",") + ")", order)))).flat();

// ── 문(shopify/index.ts 의 gate 와 같은 꼴) ──
async function gate(req: Request): Promise<{ kind: "cron" | "staff" } | Response> {
  const cronKey = req.headers.get("x-ims-cron-key");
  if (cronKey !== null) {
    const secret = Deno.env.get("IMS_CRON_SECRET") ?? "";
    if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
    if (cronKey !== secret) return json(401, { ok: false, error: "unauthorized" });
    return { kind: "cron" };
  }
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
  const r = await fetch(SB_URL() + "/rest/v1/rpc/ims_can_write", { method: "POST", headers: { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" }, body: JSON.stringify({ p_screen: "shopify" }) });
  if (r.status === 401) return json(401, { ok: false, error: "Invalid session — sign in again" });
  if (!r.ok) return json(502, { ok: false, error: "Permission check failed (ims_can_write): " + (await r.text()).slice(0, 200) });
  if ((await r.json()) !== true) return json(403, { ok: false, error: "Not allowed — you need the 'shopify' permission (manager and above) to import Shopify photos" });
  return { kind: "staff" };
}

// ── 실제 Io ──
const stores = new Map<string, StoreRow>();
async function loadContext(only: number[] | null, withSkus: boolean): Promise<Ctx> {
  const st = (await sbGet("shop_store?select=" + STORE_COLS + "&is_active=eq.true")) as StoreRow[];
  stores.clear(); for (const s of st) stores.set(s.id, s);
  const planCols = "shop_photo_plan?select=id,rule,status,src_store_id,src_product_gid,src_media_gid,src_url";
  const plan = only ? await inList(planCols, "id", only.map(String), "id.asc") : await sbAll(planCols);
  const pairs = await sbAll("shop_photo_pair?select=id,store_id,product_gid,media_gid,pair_kind,status,plan_id");
  const mediaGids = await sbAll("shop_media?select=store_id,shopify_file_gid");
  let skus: Record<string, string[]> = {};
  if (withSkus) {                                                                                   // 이름 줄기 겹침용: 읽을 상품의 IMS SKU(패밀리 + 구성원 낱개 · 또는 그 제품)
    const want = new Set([...plan.map((r: any) => r.src_store_id + "|" + r.src_product_gid), ...(only ? [] : pairs.map((p: any) => p.store_id + "|" + p.product_gid))]);
    const sp = (await sbAll("shop_product?select=store_id,family_id,product_id,shopify_product_gid")).filter((r: any) => want.has(r.store_id + "|" + r.shopify_product_gid));
    const fids = sp.map((r: any) => r.family_id).filter(Boolean), pids = sp.map((r: any) => r.product_id).filter(Boolean);
    skus = buildSkuMap(sp, await inList("product_family?select=id,sku", "id", fids, "id.asc"), await inList("product?select=id,sku,family_id&parent_product_id=is.null", "family_id", fids, "id.asc"), await inList("product?select=id,sku", "id", pids, "id.asc"));
  }
  return { stores: st.map((s) => ({ id: s.id, code: s.code })), plan, pairs, mediaGids, skus };
}
const io: Io = {
  now: () => Date.now(),
  sleep: async (ms) => { await sleep(ms); },
  context: loadContext,
  readProducts: async (store, gids) => {
    const row = stores.get(store.id);
    if (!row) return { ok: false, error: "store " + store.code + " is not switched on" };
    const g = await shopifyGql(row, PRODUCT_NODES_QUERY, { ids: gids });
    if (!g.ok) return { ok: false, error: "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : "") };
    return { ok: true, prods: parseProducts(g.data) };
  },
  rpc: sbRpc,
  download: async (url) => {                                                                        // Accept 를 따로 붙이지 않는다(계획의 md5 는 Accept 없이 받은 바이트) — Deno 가 넣는 기본값이 다른 바이트를 받게 하면 md5 대조가 막는다
    const r = await fetch(url, { signal: AbortSignal.timeout(DOWNLOAD_TIMEOUT_MS) });
    if (!r.ok) { await r.body?.cancel(); return { bytes: null, status: r.status }; }
    return { bytes: new Uint8Array(await r.arrayBuffer()), status: r.status };
  },
  upload: async (path, contentType, bytes) => {                                                     // x-upsert: 같은 경로를 다시 올려도 한 파일(경로는 계획이 정한다 · 결정적)
    const r = await fetch(SB_URL() + "/storage/v1/object/" + BUCKET + "/" + path.split("/").map(encodeURIComponent).join("/"), { method: "POST", headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": contentType, "x-upsert": "true" }, body: new Blob([bytes as BlobPart], { type: contentType }) });
    return r.ok ? { ok: true } : { ok: false, error: "http " + r.status + " " + (await r.text()).slice(0, 200) };
  },
  remaining: async () => Number((await fetch(SB_URL() + "/rest/v1/shop_photo_plan?select=id&status=in.(planned,claimed)&verify_ok=is.true&limit=1", { method: "HEAD", headers: sbHeaders({ Prefer: "count=exact" }) })).headers.get("content-range")?.split("/")[1] ?? 0),
};

async function run(mode: "check" | "pairs" | "move", opts: Exclude<ReturnType<typeof pickBody>, { error: string }>, t0: number, startedAt: string): Promise<void> {
  let counts: Record<string, unknown> = {}, err: string | null = null;
  try {
    if (mode === "move") counts = await runMove(io, opts, t0);
    else {
      const last = (await sbGet("shop_photo_run?select=counts&mode=eq." + mode + "&order=id.desc&limit=1"))[0] ?? null;
      const after = resumeAfter(last, opts);
      counts = mode === "check" ? await runCheck(io, opts, t0, after) : await runPairs(io, opts, t0, after);
      counts.resumed_after = after;
    }
  } catch (e) { err = String((e as Error)?.message ?? e).slice(0, 900); }
  counts.only = opts.only; counts.ms = Date.now() - t0;
  try { await sbRpc("shop_photo_run_add", { p_mode: mode, p_ok: err === null, p_counts: counts, p_error: err, p_started_at: startedAt }); }
  catch (e) { console.warn("shop_photo_run_add failed:", String(e).slice(0, 300), JSON.stringify(counts).slice(0, 1500)); }
  running = false;
}

Deno.serve(async (req) => {
  const t0 = Date.now(), startedAt = new Date().toISOString();
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    if (dbRole !== "test") return json(500, { ok: false, error: "inv_config.db_role is " + String(dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" });
    const caller = await gate(req);
    if (caller instanceof Response) return caller;
    const opts = pickBody(await req.json().catch(() => null));
    if ("error" in opts) return json(400, { ok: false, error: opts.error });
    if (opts.mode === "selftest") return json(200, { ...selftest(), mode: "selftest", caller: caller.kind });
    if (running) return json(409, { ok: false, error: "A run is already going in this instance — wait for its line in shop_photo_run and call again" });
    const er = (globalThis as unknown as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
    if (!er?.waitUntil) return json(500, { ok: false, error: "EdgeRuntime.waitUntil unavailable - cannot run in the background" });
    running = true;
    er.waitUntil(run(opts.mode, opts, t0, startedAt));
    return json(202, { accepted: true, mode: opts.mode, only: opts.only, started_at: startedAt, hint: "running in the background - the result lands in shop_photo_run (mode, ok, counts, error_note); call again until counts.remaining is 0" });
  } catch (e) { return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) }); }
});
