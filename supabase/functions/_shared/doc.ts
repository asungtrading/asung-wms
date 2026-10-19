// _shared/doc.ts — EF doc(서버 PDF · doc-2 · 2026-10-19)의 순수 함수 · 흐름 — DB · Gotenberg · Storage 는 deps 로 받는다(시험은 가짜 · doc_test.ts)
//   판정 523(Gotenberg · Cloud Run 토론토 · 기본 인증 · JavaScript 끔) · doc-0 Q5(남긴다 · 발행 때의 판으로 다시) · doc-1b2 이견 7(service 길은 ship_ready 불가)
//   그리기 = 화면(ims-doc.js)과 같은 mustache 4.2.0 · 판은 <meta> 를 못 두니(doc_template_check) 보내기 직전 <head> 맨 앞에 charset 을 끼운다
//   Gotenberg 8 「Convert HTML」 = POST {url}/forms/chromium/convert/html · multipart files · 주 파일 이름 index.html 필수 · preferCssPageSize(판의 @page) · printBackground
//   (gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf · 2026-10-19 읽음 — 200 PDF + Gotenberg-Trace · 400 폼 · 403 바깥 주소 거름 · 409 쪽 실패 · 503 시간 초과 · 오류는 text/plain)
import Mustache from "npm:mustache@4.2.0";

export const KINDS = ["final_invoice", "credit_note", "sales_order", "ship_ready", "internal_receipt"] as const;
export type Kind = typeof KINDS[number];
export const REASONS = ["print", "send", "reprint", "preview"] as const;
export type Auth = { mode: "staff"; jwt: string } | { mode: "service" };
export type RenderReq = { kind: string; ref: unknown; reason: string; template_id?: string | null };
export type Template = { id: string; kind: string; version: number; body: string; ok: boolean };
export type DocData = { docs: unknown[]; groups?: { group: string; so_ids?: unknown }[] };
export type GOutcome = { kind: "http"; status: number; bytes: Uint8Array; text: string; trace: string | null } | { kind: "timeout" } | { kind: "network"; message: string };
export type Classified = { ok: true; bytes: Uint8Array } | { ok: false; error: string; status: number | null };
export type FileRow = { kind: string; ref: unknown; doc_number: string | null; template_id: string; path: string; bytes: number; sha256: string; pages: number | null; reason: string; made_by: string | null; note: string | null };
export type Deps = {
  getTemplate: (kind: Kind, templateId: string | null) => Promise<Template>;
  getData: (kind: Kind, ref: unknown) => Promise<DocData>;
  convert: (html: string) => Promise<GOutcome>;
  upload: (path: string, bytes: Uint8Array) => Promise<void>;
  addFile: (row: FileRow) => Promise<{ id: string }>;
  sign: (path: string) => Promise<string>;
  now: () => Date;
  staffId: string | null;
};
export const MAX_DOCS = 20;                   // 한 번에 만드는 장수(ship_ready 묶음 · 그 밖은 1)
export const MAX_PDF_BYTES = 10 * 1024 * 1024; // 버킷 한도와 같다
export const SIGN_SECONDS = 120;               // 짧은 서명 URL

// ── 문 ──
export function isKind(k: unknown): k is Kind { return typeof k === "string" && (KINDS as readonly string[]).includes(k); }
export function gate(req: RenderReq, auth: Auth): string | null {
  if (!isKind(req.kind)) return `kind must be one of ${KINDS.join(", ")}`;
  if (!REASONS.includes(req.reason as typeof REASONS[number])) return `reason must be one of ${REASONS.join(", ")}`;
  if (req.ref === null || typeof req.ref !== "object" || Array.isArray(req.ref)) return "ref must be a JSON object";
  if (auth.mode === "service" && req.kind === "ship_ready") return "ship_ready needs a staff login — the finalize preview asks for sales permission (doc-1b2)";   // 이견 7
  if (req.template_id != null && !/^[0-9a-f-]{36}$/i.test(String(req.template_id))) return "template_id must be a uuid";
  return null;
}

// ── 그리기 ──
export function renderHtml(body: string, doc: unknown): string { return Mustache.render(String(body ?? ""), doc ?? {}); }   // 부분 판 없음 · 구분자 기본 · 화면과 같은 판
export function ensureMeta(html: string): string {
  if (/<meta[^>]*charset/i.test(html)) return html;                                        // 이미 있다(판 검사가 막지만 두 번 넣지 않는다)
  const m = /<head[^>]*>/i.exec(html);
  if (m) return html.slice(0, m.index + m[0].length) + '<meta charset="utf-8">' + html.slice(m.index + m[0].length);
  return '<meta charset="utf-8">' + html;                                                  // <head> 없는 판 — 맨 앞(파서가 head 로 올린다)
}

// ── 이름 ──
const str = (v: unknown) => (typeof v === "string" ? v : v == null ? "" : String(v));
export function docNumber(kind: Kind, doc: unknown): string | null {
  const d = (doc ?? {}) as Record<string, Record<string, unknown>>;
  const n = kind === "final_invoice" || kind === "internal_receipt" ? str(d.invoice?.number) : kind === "credit_note" ? str(d.credit?.number) : kind === "sales_order" ? str(d.so?.number) : "";
  return n.trim() === "" ? null : n.trim();
}
export const safeName = (s: string) => s.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "doc";
export function stamp(now: Date): string { return now.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z"); }   // 20261019T181014Z
export function fileName(kind: Kind, number: string | null, version: number, now: Date, index: number): string {
  const base = number ? safeName(number) : `${kind === "ship_ready" ? "shipready" : kind}-${stamp(now).slice(0, 8)}-${index + 1}`;
  return `${kind}/${base}-t${version}-${stamp(now)}${number ? "" : ""}.pdf`;
}

// ── Gotenberg 요청 · 응답 ──
export function basicAuth(user: string, pass: string): string { return "Basic " + btoa(`${user}:${pass}`); }
export function gotenbergRequest(baseUrl: string, user: string, pass: string, html: string): { url: string; headers: Record<string, string>; form: FormData } {
  const form = new FormData();
  form.append("files", new File([html], "index.html", { type: "text/html" }), "index.html");   // 주 파일 이름 index.html 필수
  form.append("preferCssPageSize", "true");                                                     // 판의 @page(Letter · 여백 · 쪽 번호)를 따른다
  form.append("printBackground", "true");
  return { url: baseUrl.replace(/\/+$/, "") + "/forms/chromium/convert/html", headers: { Authorization: basicAuth(user, pass) }, form };
}
export function isPdf(bytes: Uint8Array): boolean { return bytes.length > 5 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46 && bytes[4] === 0x2d; }   // %PDF-
export function classifyGotenberg(o: GOutcome): Classified {
  if (o.kind === "timeout") return { ok: false, error: "Gotenberg did not answer in time (Cloud Run may be waking up — try again)", status: null };
  if (o.kind === "network") return { ok: false, error: `could not reach Gotenberg: ${o.message}`.slice(0, 300), status: null };
  const tr = o.trace ? ` (trace ${o.trace})` : "";
  if (o.status >= 200 && o.status < 300) return isPdf(o.bytes) ? { ok: true, bytes: o.bytes } : { ok: false, error: `Gotenberg answered ${o.status} but not a PDF${tr}`, status: o.status };
  if (o.status === 401) return { ok: false, error: `Gotenberg refused the login (401) — check GOTENBERG_USER / GOTENBERG_PASS${tr}`, status: 401 };
  if (o.status === 403) return { ok: false, error: `Gotenberg blocked an outside address in the document (403 — outbound URL filtering): ${o.text.slice(0, 160)}${tr}`, status: 403 };
  if (o.status === 400) return { ok: false, error: `Gotenberg rejected the request (400): ${o.text.slice(0, 160)}${tr}`, status: 400 };
  if (o.status === 409) return { ok: false, error: `Gotenberg could not render the page (409): ${o.text.slice(0, 160)}${tr}`, status: 409 };
  return { ok: false, error: `Gotenberg ${o.status}: ${o.text.slice(0, 160)}${tr}`, status: o.status };
}
export function pdfPages(bytes: Uint8Array): number | null {                                     // 짐작 — /Type /Page 객체 수(객체 스트림으로 눌린 PDF 는 못 센다 → null)
  let s = "";
  for (let i = 0; i < bytes.length; i += 65536) s += String.fromCharCode(...bytes.subarray(i, Math.min(i + 65536, bytes.length)));
  const n = (s.match(/\/Type\s*\/Page(?![s\w])/g) ?? []).length;
  return n > 0 ? n : null;
}
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes.slice()));   // slice: Uint8Array<ArrayBuffer>(BufferSource 타입)
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("");
}

// ── 흐름 ──
export type Made = { doc_file_id: string; path: string; bytes: number; pages: number | null; doc_number: string | null; group: string | null; signed_url: string; expires_in: number };
export async function renderAll(d: Deps, req: RenderReq, auth: Auth): Promise<{ template_id: string; template_version: number; files: Made[] }> {
  const g = gate(req, auth);
  if (g) throw new Error(g);
  const kind = req.kind as Kind;
  const t = await d.getTemplate(kind, req.template_id ?? null);                                   // 판: 주어진 판(「발행 때의 판으로 다시」) · 없으면 쓰는 판
  if (t.kind !== kind) throw new Error(`layout version is for ${t.kind}, not ${kind}`);
  if (!t.ok) throw new Error(`layout version ${t.version} of ${kind} did not pass its checks`);
  const data = await d.getData(kind, req.ref);
  const docs = Array.isArray(data.docs) ? data.docs : [];
  if (docs.length === 0) throw new Error("the document has no pages to render");
  if (docs.length > MAX_DOCS) throw new Error(`too many documents in one request (${docs.length} — the limit is ${MAX_DOCS})`);
  const files: Made[] = [];
  for (let i = 0; i < docs.length; i++) {
    const html = ensureMeta(renderHtml(t.body, docs[i]));
    const c = classifyGotenberg(await d.convert(html));
    if (!c.ok) throw new Error(c.error);                                                        // 아무것도 남기지 않는다(이 장은) · 앞 장은 이미 남았다(묶음 둘일 때 — 보고)
    if (c.bytes.length > MAX_PDF_BYTES) throw new Error(`the PDF is ${c.bytes.length} bytes — the limit is ${MAX_PDF_BYTES}`);
    const number = docNumber(kind, docs[i]);
    const group = data.groups?.[i]?.group ?? null;
    const path = fileName(kind, number, t.version, d.now(), i);
    await d.upload(path, c.bytes);
    const row = await d.addFile({ kind, ref: kind === "ship_ready" && group != null ? { ...(req.ref as Record<string, unknown>), group, so_ids: data.groups?.[i]?.so_ids ?? null } : req.ref,
                                  doc_number: number, template_id: t.id, path, bytes: c.bytes.length, sha256: await sha256Hex(c.bytes), pages: pdfPages(c.bytes), reason: req.reason, made_by: d.staffId, note: null });
    files.push({ doc_file_id: row.id, path, bytes: c.bytes.length, pages: pdfPages(c.bytes), doc_number: number, group, signed_url: await d.sign(path), expires_in: SIGN_SECONDS });
  }
  return { template_id: t.id, template_version: t.version, files };
}
