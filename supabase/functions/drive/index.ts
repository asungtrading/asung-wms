// drive — 구글 공유 드라이브 일꾼(drive-2 · 2026-10-24 · 판정 688 ~ 708 · 미룬 260) — ⚠️ 테스트 프로젝트(fazgmyvzzhqybtvtktyg)에 먼저 · 운영은 컷오버 때
//   문: x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed · mail · doc 과 같은 꼴) · config.toml [functions.drive] verify_jwt = false
//   POST {"action":"run"}     drive_job_claim(5) → archive·waiting_pdf 는 EF doc render(reason archive · service 길) → drive_job_pdf_set / sending 은 폴더 사슬 → Storage → Drive(올리기 · 바로가기 · 이름 바꾸기) → drive_job_done · 실패 drive_job_failed
//                             ⚠️ 보관본 PDF 만들기는 drive_enabled 와 무관(발행 직후 · 판정 692) · 드라이브 쓰기는 claim 이 drive_enabled=on 일 때만 준다
//        {"action":"status"}  비밀 이름 · 토큰 교환(token_ok) · files.list 가 drive.file 범위로 보이는지(list_ok · 이견 7 · 꼭대기 폴더 수) · drive_status() · 30 분 넘은 waiting_pdf 수
//   비밀: GDRIVE_OAUTH_CLIENT_ID · GDRIVE_OAUTH_CLIENT_SECRET · GDRIVE_REFRESH_TOKEN_IMS(tools/gdrive-oauth-ims.sh 가 넣는다 · 범위 drive.file 하나 · 702) · IMS_CRON_SECRET(EF doc 을 부를 때도 같은 열쇠)
//   ⚠️ 비밀 값은 로그 · 응답 · DB 어디에도 남기지 않는다(오류는 Google 의 error 코드 · 설명만)
//   Drive API(2026-10-24 읽음 · 시험 A 실측): files.create(폴더 · 바로가기) · /upload/drive/v3/files?uploadType=multipart · files.update(name) · files.list(corpora=drive · driveId) — 전부 supportsAllDrives=true
import { driveError, driveStep, FOLDER_MIME, folderQuery, listUrl, multipartUpload, SHORTCUT_MIME, stale, type Job, type Render } from "../_shared/drive.ts";

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const sbHeaders = (): HeadersInit => ({ apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" });
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const BATCH = 5, BUDGET_MS = 40_000, DOC_TIMEOUT_MS = 70_000, DRIVE_TIMEOUT_MS = 30_000, STORAGE_TIMEOUT_MS = 30_000, STALE_MIN = 30;   // mail pdf 와 같은 예산(EF doc 장마다 Gotenberg 58 s)
const DRIVE = "https://www.googleapis.com/drive/v3", UPLOAD = "https://www.googleapis.com/upload/drive/v3/files";

async function sbRpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers: sbHeaders(), body: JSON.stringify(args) });
  const text = await r.text();
  if (!r.ok) { let msg = text.slice(0, 300); try { msg = JSON.parse(text)?.message ?? msg; } catch { /* plain */ } throw new Error(`rpc/${fn}: ${msg}`); }
  return text ? JSON.parse(text) : null;
}
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error(`GET ${path.split("?")[0]} ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return await r.json();
}

// ── 열쇠 — 리프레시 토큰 → access token(회차 안 캐시 · mail 의 gmailToken 꼴) ──
let cached: { token: string; until: number } | null = null;
async function driveToken(): Promise<string> {
  if (cached && cached.until > Date.now() + 60_000) return cached.token;
  const id = Deno.env.get("GDRIVE_OAUTH_CLIENT_ID") ?? "", secret = Deno.env.get("GDRIVE_OAUTH_CLIENT_SECRET") ?? "", refresh = Deno.env.get("GDRIVE_REFRESH_TOKEN_IMS") ?? "";
  if (!id || !secret || !refresh) throw new Error("Drive OAuth secrets are not set (GDRIVE_OAUTH_CLIENT_ID · GDRIVE_OAUTH_CLIENT_SECRET · GDRIVE_REFRESH_TOKEN_IMS) — run tools/gdrive-oauth-ims.sh");
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: id, client_secret: secret, refresh_token: refresh, grant_type: "refresh_token" }), signal: AbortSignal.timeout(15_000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error(`token endpoint ${r.status} ${j.error ?? ""}${j.error_description ? ": " + j.error_description : ""}${j.error === "invalid_grant" ? " — run tools/gdrive-oauth-ims.sh again (consent as ims@asung.ca)" : ""}`);
  cached = { token: j.access_token, until: Date.now() + Number(j.expires_in ?? 3600) * 1000 };
  return j.access_token;
}
const gHeaders = (token: string): HeadersInit => ({ Authorization: "Bearer " + token, "Content-Type": "application/json" });
async function gFetch(what: string, url: string, init: RequestInit): Promise<any> {
  const r = await fetch(url, { ...init, signal: AbortSignal.timeout(DRIVE_TIMEOUT_MS) });
  const text = await r.text();
  if (!r.ok) throw new Error(driveError(what, r.status, text));
  return text ? JSON.parse(text) : {};
}
async function findFolder(token: string, driveId: string, parentId: string, name: string): Promise<string | null> {
  const j = await gFetch("files.list", listUrl(driveId, folderQuery(parentId, name)), { headers: gHeaders(token) });
  const f = Array.isArray(j?.files) ? j.files.find((x: any) => x?.name === name) ?? j.files[0] : null;
  return f?.id ? String(f.id) : null;
}
async function createFolder(token: string, parentId: string, name: string): Promise<string> {
  const j = await gFetch("files.create(folder)", DRIVE + "/files?supportsAllDrives=true&fields=id", { method: "POST", headers: gHeaders(token), body: JSON.stringify({ name, mimeType: FOLDER_MIME, parents: [parentId] }) });
  if (!j?.id) throw new Error("files.create(folder): no id in the answer");
  return String(j.id);
}
async function upload(token: string, parentId: string, name: string, mime: string, bytes: Uint8Array, description: string | null): Promise<string> {
  const m = multipartUpload({ name, parents: [parentId], mimeType: mime, description: description ?? undefined }, mime, bytes, "ims-drive-" + crypto.randomUUID());
  const j = await gFetch("upload", UPLOAD + "?uploadType=multipart&supportsAllDrives=true&fields=id", { method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": m.contentType }, body: m.body.slice() });
  if (!j?.id) throw new Error("upload: no id in the answer");
  return String(j.id);
}
async function shortcut(token: string, parentId: string, name: string, targetId: string): Promise<string> {
  const j = await gFetch("files.create(shortcut)", DRIVE + "/files?supportsAllDrives=true&fields=id", { method: "POST", headers: gHeaders(token), body: JSON.stringify({ name, mimeType: SHORTCUT_MIME, parents: [parentId], shortcutDetails: { targetId } }) });
  if (!j?.id) throw new Error("files.create(shortcut): no id in the answer");
  return String(j.id);
}
async function rename(token: string, fileId: string, name: string): Promise<void> {
  await gFetch("files.update(name)", DRIVE + "/files/" + encodeURIComponent(fileId) + "?supportsAllDrives=true&fields=id", { method: "PATCH", headers: gHeaders(token), body: JSON.stringify({ name }) });
}
async function readFile(bucket: string, path: string): Promise<Uint8Array> {
  const r = await fetch(SB_URL() + "/storage/v1/object/" + bucket + "/" + String(path).replace(/^\/+/, ""), { headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE() }, signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });
  if (!r.ok) throw new Error(`storage ${bucket} ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return new Uint8Array(await r.arrayBuffer());
}
async function docRender(kind: string, ref: unknown): Promise<Render> {                     // EF doc · service 길 · reason archive(이미 있으면 existing — 두 번 불러도 하나)
  try {
    const r = await fetch(SB_URL() + "/functions/v1/doc", { method: "POST", headers: { "Content-Type": "application/json", "x-ims-cron-key": Deno.env.get("IMS_CRON_SECRET") ?? "" },
      body: JSON.stringify({ action: "render", kind, ref, reason: "archive" }), signal: AbortSignal.timeout(DOC_TIMEOUT_MS) });
    const text = await r.text();
    let j: any = {}; try { j = JSON.parse(text); } catch { /* plain */ }
    if (!r.ok || !j?.ok) return { ok: false, error: `doc ${r.status}: ${String(j?.error ?? text).slice(0, 300)}` };
    const id = j?.files?.[0]?.doc_file_id;
    if (!id || j.files.length !== 1) return { ok: false, error: `doc answered with ${j?.files?.length ?? 0} files — one was expected` };
    return { ok: true, doc_file_id: String(id) };
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    return { ok: false, error: name === "TimeoutError" || name === "AbortError" ? `doc did not answer in ${DOC_TIMEOUT_MS / 1000} s (Gotenberg may be waking up)` : `doc: ${String((e as Error)?.message ?? e).slice(0, 200)}` };
  }
}

async function doRun(): Promise<Response> {
  const out = await driveStep({
    token: driveToken,
    claim: async (n) => ((await sbRpc("drive_job_claim", { p_limit: n })) ?? []) as Job[],
    render: docRender,
    pdfSet: async (jobId, docFileId) => { await sbRpc("drive_job_pdf_set", { p_job_id: jobId, p_doc_file_id: docFileId }); },
    findFolder, createFolder,
    folderSet: async (scope, ref, folderId, name) => { const f = await sbRpc("drive_folder_set", { p_scope: scope, p_ref: ref, p_folder_id: folderId, p_name: name }); return String(f?.folder_id ?? folderId); },
    readFile, upload, shortcut, rename,
    done: async (jobId, driveId) => { await sbRpc("drive_job_done", { p_job_id: jobId, p_drive_file_id: driveId }); },
    failed: async (jobId, error) => { await sbRpc("drive_job_failed", { p_job_id: jobId, p_error: error }); },
    now: () => Date.now(),
    log: (msg) => console.error(msg),
  }, { batch: BATCH, budgetMs: BUDGET_MS });
  return json(out.ok ? 200 : 500, out);
}
async function doStatus(): Promise<Response> {
  const secrets = { GDRIVE_OAUTH_CLIENT_ID: !!Deno.env.get("GDRIVE_OAUTH_CLIENT_ID"), GDRIVE_OAUTH_CLIENT_SECRET: !!Deno.env.get("GDRIVE_OAUTH_CLIENT_SECRET"), GDRIVE_REFRESH_TOKEN_IMS: !!Deno.env.get("GDRIVE_REFRESH_TOKEN_IMS"), IMS_CRON_SECRET: !!Deno.env.get("IMS_CRON_SECRET") };
  let db: any = null, dbError: string | null = null;
  try { db = await sbRpc("drive_status", {}); } catch (e) { dbError = String((e as Error)?.message ?? e).slice(0, 200); }
  let token_ok = false, token_error: string | null = null, list_ok: boolean | null = null, list_error: string | null = null, top_folders: string[] = [];
  try {
    const t = await driveToken(); token_ok = true;
    const root = String(db?.root_id ?? "");
    if (root) {
      try {
        const j = await gFetch("files.list", listUrl(root, `mimeType = '${FOLDER_MIME}' and '${root}' in parents and trashed = false`), { headers: gHeaders(t) });
        list_ok = Array.isArray(j?.files); top_folders = (j?.files ?? []).map((f: any) => String(f?.name ?? "")).slice(0, 20);   // drive.file 은 앱이 만든 폴더만 보인다 — 처음엔 0 개가 정상 · 거부(403)면 list_ok false
      } catch (e) { list_ok = false; list_error = String((e as Error)?.message ?? e).slice(0, 200); }
    }
  } catch (e) { token_error = String((e as Error)?.message ?? e).slice(0, 200); }
  let stale_waiting_pdf = 0;
  try { const rows = await sbGet("drive_job?select=created_at&status=eq.waiting_pdf&kind=eq.archive&limit=200"); stale_waiting_pdf = rows.filter((r) => stale(String(r.created_at), Date.now(), STALE_MIN)).length; } catch { /* db 쪽 오류는 dbError 에 */ }
  const warn: string[] = [];
  if (!token_ok) warn.push("token");
  if (list_ok === false) warn.push("files.list refused — drive.file scope cannot see the drive (ruling 702 assumption broken)");
  if (stale_waiting_pdf > 0) warn.push(`${stale_waiting_pdf} archive PDF(s) waiting more than ${STALE_MIN} min`);
  if (Array.isArray(db?.failed) && db.failed.length) warn.push(`${db.failed.length} failed job(s)`);
  return json(200, { ok: true, secrets, token_ok, token_error, list_ok, list_error, top_folders, stale_waiting_pdf, warn, db, db_error: dbError });
}

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    const key = req.headers.get("x-ims-cron-key"), secret = Deno.env.get("IMS_CRON_SECRET") ?? "";
    if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
    if (!key || !sameSecret(key, secret)) return json(401, { ok: false, error: "unauthorized" });
    const body = await req.json().catch(() => ({}));
    if (body.action === "run") return await doRun();
    if (body.action === "status") return await doStatus();
    return json(400, { ok: false, error: "action must be run or status" });
  } catch (e) {
    console.error("drive failed:", String((e as Error)?.message ?? e).slice(0, 500));
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 300) });
  }
});
