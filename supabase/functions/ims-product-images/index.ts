// ============================================================
// ASUNG IMS — Edge Function: ims-product-images (img-2 · 2026-10-01 · 판정 195 ~ 197)
//   Cin7 상품 첨부 → 테스트 프로젝트(Asung-IMS) 의 Storage 상자 product-images + product_image 표(source cin7).
//   ⚠️ 테스트 프로젝트 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다(마이그레이션 가드와 같은 뜻 · ⬜5).
//   ⚠️ 운영 EF product-images(wms_sku_snapshot.image_url) 와 다른 함수다 — 운영 무접촉.
// 세 모드(?mode=):
//   count — Cin7 148 쪽을 읽고 **세기만**(아무것도 안 쓴다 · runs 한 줄) · 쿨다운 밖(마른 실행을 여러 번 돌릴 수 있게 · ⬜9)
//   scan  — 목록 전체(all-or-nothing) → 새 첨부를 큐(ims_image_sync_queue)에 · 사라진 첨부 끄기 · 대표 옮기기 · 형식 밖은 skips · 쿨다운 20h(매일 1회)
//   move  — Cin7 목록 없이 큐를 소비(내려받기 → 크기 → 저장소 put → product_image insert) · 회차 장수 한도 + 시간 가드(쓰기 앞) · 인플라이트 가드만
//   왜 scan 과 move 를 가르나(⬜2): 목록 148 쪽 ≈ 3분 32초(운영 실측)라 400초 안에 내려받기까지 같이 못 한다 · 큐가 곧 커서(status pending → done | skipped)
// 운영 EF 의 교훈 그대로: 150초 IDLE(202 즉시 + waitUntil) · 시간 가드는 쓰기 앞 · 페이싱 1100ms · 원문 비누적 · 결과는 응답이 아니라 runs 표로
// 인증: x-ims-cron-key == secret IMS_CRON_SECRET(verify_jwt=false · 미설정이면 500 fail-closed) · 값은 supabase secrets set --project-ref fazgmyvzzhqybtvtktyg 로만(시크릿 위치 규칙 · asung-wms 스킬)
// 쓰는 길: service_role 로 표 · 저장소에 직접(창구 product_update 는 직원 신원이 있어야 열린다 · prod-3 이견 1) — 막기 규칙은 표 제약(경로 · 형식 · source)과 sync_core 가 지킨다
// 판단은 전부 ./sync_core.ts(순수 · deno test) — 이 파일은 받아 오고 · 쓰고 · 기록한다.
import { cin7Get, cin7Headers, sleep } from "../_shared/cin7.ts";
import { assessList, DOWNLOAD_BASE, gate, newRowIsPrimary, plan, storagePath, timeLeft, withinSize, type Cin7Prod, type ImgRow, type ImsProd, type Plan, type QueueItem, type Skip } from "./sync_core.ts";

const PAGE_LIMIT = 100, PAGE_SLEEP_MS = 1100, MAX_PAGES = 200;
const TIME_BUDGET_MS = 330_000;            // t0 기준 · 쓰기 앞에서만 끊는다(운영과 같다)
const MOVE_PER_RUN = 300;                  // 회차 장수 한도 — 내려받기 + 올리기 ≈ 1초/장 짐작 · 첫 채우기는 회차를 여러 번
const COOLDOWN_MS = 20 * 3_600_000;        // scan 만
const RUNS_KEEP_DAYS = 90;
const BUCKET = "product-images";
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
let running = false;

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const sbHeaders = (extra: Record<string, string> = {}): HeadersInit => ({ apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra });
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbAll(path: string, order: string): Promise<any[]> {          // PostgREST 1000행 캡 — limit/offset
  const out: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    const rows = await sbGet(path + "&order=" + order + "&limit=1000&offset=" + offset);
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}
async function sbWrite(method: string, path: string, body?: unknown, prefer = "return=minimal"): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method, headers: sbHeaders({ Prefer: prefer }), body: body === undefined ? undefined : JSON.stringify(body) });
  if (!r.ok) throw new Error("sb " + method + " " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
async function recordRun(row: Record<string, unknown>): Promise<void> {
  try {
    await sbWrite("POST", "ims_image_sync_runs", row);
    try { await sbWrite("DELETE", "ims_image_sync_runs?started_at=lt." + encodeURIComponent(new Date(Date.now() - RUNS_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("runs purge failed:", String(e).slice(0, 200)); }
  } catch (e) { console.warn("recordRun failed:", String(e).slice(0, 300)); }
}
async function putSkips(skips: Skip[]): Promise<void> {                    // 되풀이 횟수는 DB 트리거가 올린다(upsert 키 cin7_attachment_id)
  for (let i = 0; i < skips.length; i += 500) {
    await sbWrite("POST", "ims_image_sync_skips?on_conflict=cin7_attachment_id", skips.slice(i, i + 500).map((s) => ({ ...s, last_seen_at: new Date().toISOString() })), "resolution=merge-duplicates,return=minimal");
  }
}

// ── Cin7 목록 148 쪽 — 원문 비누적 · 429 는 회차 포기 · 시간 가드는 fetch 앞 ──
async function listCin7(t0: number, diag: Record<string, unknown>): Promise<{ products: Cin7Prod[]; aborted: string | null }> {
  const products: Cin7Prod[] = [];
  let listTotal: number | null = null, seen = 0, pages = 0, aborted: string | null = null, note: string | null = null;
  for (let page = 1; page <= MAX_PAGES; page++) {
    if (!timeLeft(t0, Date.now(), TIME_BUDGET_MS)) { aborted = "time"; note = "time budget exceeded at page " + page; break; }
    let j: any;
    try { j = await cin7Get("/product?Page=" + page + "&Limit=" + PAGE_LIMIT + "&IncludeAttachments=true"); }
    catch (e: any) { aborted = Number(e?.status) === 429 ? "rate_limited" : "page_error"; note = String(e?.message ?? e).slice(0, 300); break; }
    pages++;
    if (j?.Total != null) listTotal = Number(j.Total);
    const batch = (j?.Products ?? []) as any[];
    seen += batch.length;
    for (const p of batch) products.push({ SKU: p?.SKU, Attachments: (p?.Attachments ?? []).map((a: any) => ({ ID: a?.ID, ContentType: a?.ContentType, FileName: a?.FileName, IsDefault: a?.IsDefault })) });   // 첨부 넷만 남긴다(메모리)
    if (batch.length < PAGE_LIMIT) break;
    await sleep(PAGE_SLEEP_MS);
  }
  const verdict = assessList({ productsSeen: seen, listTotal, aborted });
  Object.assign(diag, { pages_scanned: pages, list_total: listTotal, products_seen: seen, list_aborted: verdict, abort_note: note });
  return { products, aborted: verdict };
}

async function loadIms(): Promise<{ ims: ImsProd[]; rows: ImgRow[] }> {
  const ims = (await sbAll("product?select=id,sku,is_active&is_active=eq.true", "sku.asc")) as ImsProd[];
  const rows = (await sbAll("product_image?select=id,product_id,cin7_attachment_id,is_primary,is_active,source", "id.asc")) as ImgRow[];
  return { ims, rows };
}

// ── scan · count ──
async function runScan(t0: number, startedAt: string, mode: "count" | "scan"): Promise<void> {
  const diag: Record<string, unknown> = {};
  let ok = false, err: string | null = null, p: Plan | null = null;
  try {
    const { products, aborted } = await listCin7(t0, diag);
    const { ims, rows } = await loadIms();
    diag.ims_active = ims.length; diag.image_rows = rows.length;
    p = plan(products, ims, rows, aborted === null);           // 부분 목록이면 끄기 · 대표를 내지 않는다(count 집계는 남긴다)
    Object.assign(diag, p.counts, { missing_in_ims_sample: p.missing_in_ims_sample, mode });
    if (aborted) { err = aborted + (diag.abort_note ? " - " + diag.abort_note : ""); }
    else if (mode === "scan") {
      if (!timeLeft(t0, Date.now(), TIME_BUDGET_MS)) throw new Error("time budget exceeded before writing");
      for (let i = 0; i < p.to_queue.length; i += 500) await sbWrite("POST", "ims_image_sync_queue?on_conflict=cin7_attachment_id", p.to_queue.slice(i, i + 500).map((q) => ({ ...q, status: "pending" })), "resolution=ignore-duplicates,return=minimal");
      for (const o of p.to_off) await sbWrite("PATCH", "product_image?id=eq." + o.image_id, { is_active: false, is_primary: false });
      for (const m of p.primary_moves) {
        await sbWrite("PATCH", "product_image?product_id=eq." + m.product_id + "&is_primary=is.true", { is_primary: false });
        await sbWrite("PATCH", "product_image?id=eq." + m.image_id, { is_primary: true });
      }
      await putSkips(p.skips);
      ok = true;
    } else ok = true;
  } catch (e) { err = String(e).slice(0, 400); }
  diag.duration_ms = Date.now() - t0;
  await recordRun({ started_at: startedAt, finished_at: new Date().toISOString(), ok, mode, pages: diag.pages_scanned ?? 0, products_seen: diag.products_seen ?? 0, matched: p?.counts.matched ?? 0,
    new_attachments: p?.counts.to_queue ?? 0, moved: 0, turned_off: ok && mode === "scan" ? p?.counts.to_off ?? 0 : 0, primary_moved: ok && mode === "scan" ? p?.counts.primary_moves ?? 0 : 0, skipped: p?.skips.length ?? 0, failed: 0, error_note: err, diag });
  running = false;
}

// ── move — 큐 소비 · 한 장 = 내려받기 → 크기 → 저장소 put → product_image insert → 큐 done ──
async function download(attId: string): Promise<{ bytes: Uint8Array | null; status: number; ct: string | null }> {
  const url = DOWNLOAD_BASE + attId;
  let r = await fetch(url);                                                                   // ⬜4 — 먼저 헤더 없이(브라우저 <img> 가 그렇게 받는다 · 운영 실측)
  if (r.status === 401 || r.status === 403) r = await fetch(url, { headers: cin7Headers() });  // 막히면 API 헤더로 한 번 더(짐작)
  if (!r.ok) return { bytes: null, status: r.status, ct: null };
  return { bytes: new Uint8Array(await r.arrayBuffer()), status: r.status, ct: r.headers.get("content-type") };
}
async function runMove(t0: number, startedAt: string): Promise<void> {
  const diag: Record<string, unknown> = { mode: "move" };
  let moved = 0, skipped = 0, failed = 0, err: string | null = null;
  const skips: Skip[] = [];
  try {
    const queue = (await sbGet("ims_image_sync_queue?select=*&status=eq.pending&order=enqueued_at.asc,cin7_attachment_id.asc&limit=" + MOVE_PER_RUN)) as (QueueItem & { attempts: number })[];
    diag.queue_taken = queue.length;
    diag.queue_pending_before = Number((await fetch(SB_URL() + "/rest/v1/ims_image_sync_queue?select=cin7_attachment_id&status=eq.pending&limit=1", { headers: sbHeaders({ Prefer: "count=exact" }), method: "HEAD" })).headers.get("content-range")?.split("/")[1] ?? -1);
    for (const q of queue) {
      if (!timeLeft(t0, Date.now(), TIME_BUDGET_MS)) { diag.stopped = "time"; break; }   // 쓰기 앞
      const mark = async (status: string, extra: Record<string, unknown> = {}) => sbWrite("PATCH", "ims_image_sync_queue?cin7_attachment_id=eq." + q.cin7_attachment_id, { status, attempts: (q.attempts ?? 0) + 1, updated_at: new Date().toISOString(), ...extra });
      const skip = async (reason: Skip["reason"], byte_size: number | null, note: string | null) => { skipped++; skips.push({ cin7_attachment_id: q.cin7_attachment_id, product_id: q.product_id, sku: q.sku, reason, content_type: q.content_type, byte_size, note }); await mark("skipped", { last_error: reason + (note ? " - " + note : "") }); };
      try {
        const d = await download(q.cin7_attachment_id);
        if (!d.bytes) { await skip("download_failed", null, "http " + d.status); continue; }
        if (!withinSize(d.bytes.byteLength)) { await skip("too_large", d.bytes.byteLength, null); continue; }   // 판정 197
        const path = storagePath(q.product_id, q.cin7_attachment_id, q.content_type);
        const up = await fetch(SB_URL() + "/storage/v1/object/" + BUCKET + "/" + path, { method: "POST", headers: { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": q.content_type, "x-upsert": "true" }, body: new Blob([d.bytes as BlobPart], { type: q.content_type }) });
        if (!up.ok) { await skip("upload_failed", d.bytes.byteLength, "http " + up.status + " " + (await up.text()).slice(0, 200)); continue; }
        const mine = (await sbGet("product_image?select=id,product_id,cin7_attachment_id,is_primary,is_active,source&product_id=eq." + q.product_id)) as ImgRow[];
        const primary = newRowIsPrimary(q, mine);
        if (primary) await sbWrite("PATCH", "product_image?product_id=eq." + q.product_id + "&is_primary=is.true", { is_primary: false });
        const sort = mine.length + 1;
        try {
          await sbWrite("POST", "product_image", { product_id: q.product_id, storage_path: path, content_type: q.content_type, byte_size: d.bytes.byteLength, file_name: q.file_name, source: "cin7", cin7_attachment_id: q.cin7_attachment_id, is_primary: primary, sort_order: sort });
        } catch (e) { await skip("insert_failed", d.bytes.byteLength, String(e).slice(0, 200)); continue; }
        moved++;
        await mark("done", { byte_size: d.bytes.byteLength, last_error: null });
      } catch (e) { failed++; await mark("failed", { last_error: String(e).slice(0, 300) }); }
    }
    await putSkips(skips);
  } catch (e) { err = String(e).slice(0, 400); }
  diag.duration_ms = Date.now() - t0;
  await recordRun({ started_at: startedAt, finished_at: new Date().toISOString(), ok: err === null, mode: "move", pages: 0, products_seen: 0, matched: 0, new_attachments: 0, moved, turned_off: 0, primary_moved: 0, skipped, failed, error_note: err, diag });
  running = false;
}

Deno.serve(async (req) => {
  const t0 = Date.now(), startedAt = new Date().toISOString();
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    const mode = new URL(req.url).searchParams.get("mode") ?? "count";
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    const g = gate({ secret: Deno.env.get("IMS_CRON_SECRET") ?? "", header: req.headers.get("x-ims-cron-key") ?? "", dbRole, mode });
    if (g) return json({ ok: false, error: g.error }, g.status);
    if (mode === "scan") {                                                                        // 쿨다운 — scan 만(⬜9)
      const last = await sbGet("ims_image_sync_runs?ok=is.true&mode=eq.scan&order=started_at.desc&limit=1&select=started_at");
      if (last[0] && Date.now() - Date.parse(last[0].started_at) < COOLDOWN_MS) return json({ mode: "SKIPPED", skipped: "cooldown", last_ok_at: last[0].started_at });
    }
    if (running) return json({ mode: "SKIPPED", skipped: "in_flight" });
    const er = (globalThis as unknown as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
    if (!er?.waitUntil) return json({ ok: false, error: "EdgeRuntime.waitUntil unavailable - cannot run in background" }, 500);
    running = true;
    er.waitUntil(mode === "move" ? runMove(t0, startedAt) : runScan(t0, startedAt, mode as "count" | "scan"));
    return json({ accepted: true, mode, started_at: startedAt, hint: "running in background - result lands in ims_image_sync_runs (ok/error_note/diag)" }, 202);
  } catch (e) { return json({ ok: false, error: String(e) }, 500); }
});
function json(obj: unknown, status = 200): Response { return new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } }); }
