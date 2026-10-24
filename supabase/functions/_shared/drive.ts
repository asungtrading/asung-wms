// _shared/drive.ts — EF drive(구글 드라이브 일꾼 · drive-2 · 2026-10-24 · 판정 688 ~ 708)의 순수 함수 · 흐름 — DB · Drive · Storage · EF doc 은 deps 로 받는다(시험은 가짜 · drive_test.ts)
//   한 회차: token(필요할 때 한 번) → drive_job_claim → 일마다
//     archive · waiting_pdf → EF doc render(reason archive · service 길) → drive_job_pdf_set            (drive_enabled 와 무관 · 발행 직후 · 판정 692 · 528)
//     archive · sending     → 폴더 사슬 보장 → Storage documents 에서 PDF → Drive 올리기 → drive_job_done(drive_file_id)
//     upload   · sending    → 폴더 사슬 → Storage po-documents 에서 파일 → 올리기 → done
//     shortcut · sending    → 원본의 drive id 가 있어야(없으면 failed · 10 분 뒤 다시) → 대상 PO 폴더에 바로가기 → done
//     rename   · sending    → files.update name → done(null)
//   실패는 drive_job_failed(메시지 500 자 · 3 번 뒤 failed) · 열쇠(토큰) 실패는 일을 태우지 않고 회차 오류(이견 10)
//   폴더 사슬(claim 의 folders[]): under 'Customers' | 'Suppliers' = root 아래 꼭대기 폴더(drive_folder 에 없다 · 이름으로 찾고 없으면 만든다 · 회차 안 캐시) · under 'supplier' | 'aone' = 바로 앞 폴더 아래 · under null = root 아래
//   Drive 쓰기 네 가지 전부 supportsAllDrives=true(시험 A · 702) · 만들기 전에 files.list 로 찾는다(이견 7 · 중복 폴더 막기)
export type Folder = { scope: string; ref: string; name: string; folder_id: string | null; under: string | null };
export type JobFile = { bucket: string; path: string; bytes: number; sha256: string; mime: string; doc_file_id?: string; po_doc_id?: string; drive_file_id?: string | null };
export type Job = {
  job_id: string; kind: "archive" | "upload" | "shortcut" | "rename"; status: string; attempts: number; root_id: string;
  target: { scope: string | null; ref: string | null }; folders: Folder[]; file_name: string | null; description: string | null;
  doc: { kind: string; ref: unknown; number?: string; status?: string } | null; file: JobFile | null;
  drive_file_id: string | null; shortcut_id: string | null; shortcut_target_drive_file_id: string | null;
};
export type Render = { ok: true; doc_file_id: string } | { ok: false; error: string };
export type Deps = {
  token: () => Promise<string>;                                              // 리프레시 → access token(회차 안 캐시) · 실패는 throw
  claim: (n: number) => Promise<Job[]>;
  render: (kind: string, ref: unknown) => Promise<Render>;                   // EF doc render reason archive
  pdfSet: (jobId: string, docFileId: string) => Promise<void>;
  findFolder: (token: string, driveId: string, parentId: string, name: string) => Promise<string | null>;
  createFolder: (token: string, parentId: string, name: string) => Promise<string>;
  folderSet: (scope: string, ref: string, folderId: string, name: string) => Promise<string>;   // drive_folder_set → 기록된 id(먼저 적힌 것이 이긴다)
  readFile: (bucket: string, path: string) => Promise<Uint8Array>;
  upload: (token: string, parentId: string, name: string, mime: string, bytes: Uint8Array, description: string | null) => Promise<string>;
  shortcut: (token: string, parentId: string, name: string, targetId: string) => Promise<string>;
  rename: (token: string, fileId: string, name: string) => Promise<void>;
  done: (jobId: string, driveId: string | null) => Promise<void>;
  failed: (jobId: string, error: string) => Promise<void>;
  now: () => number;
  log: (msg: string) => void;
};
export type StepOut = { ok: boolean; status: string; error?: string; counts: Record<string, number> };
export const TOP = { Customers: "Customers", Suppliers: "Suppliers" } as const;

// ── Drive 요청 재료(순수) ──
export const FOLDER_MIME = "application/vnd.google-apps.folder", SHORTCUT_MIME = "application/vnd.google-apps.shortcut";
export const qEscape = (s: string) => s.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
export function folderQuery(parentId: string, name: string): string {
  return `name = '${qEscape(name)}' and mimeType = '${FOLDER_MIME}' and '${qEscape(parentId)}' in parents and trashed = false`;
}
export function listUrl(driveId: string, q: string): string {
  const p = new URLSearchParams({ q, corpora: "drive", driveId, includeItemsFromAllDrives: "true", supportsAllDrives: "true", fields: "files(id,name)", pageSize: "5" });
  return "https://www.googleapis.com/drive/v3/files?" + p.toString();
}
export function multipartUpload(meta: Record<string, unknown>, mime: string, bytes: Uint8Array, boundary: string): { contentType: string; body: Uint8Array } {
  const enc = new TextEncoder();
  const head = enc.encode(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n--${boundary}\r\nContent-Type: ${mime}\r\n\r\n`);
  const tail = enc.encode(`\r\n--${boundary}--`);
  const body = new Uint8Array(head.length + bytes.length + tail.length);
  body.set(head, 0); body.set(bytes, head.length); body.set(tail, head.length + bytes.length);
  return { contentType: `multipart/related; boundary=${boundary}`, body };
}
export function driveError(what: string, status: number, text: string): string {           // Google 오류 본문의 message 만(비밀 없음)
  let msg = text.slice(0, 200);
  try { const j = JSON.parse(text); msg = String(j?.error?.message ?? j?.error_description ?? j?.error ?? msg); } catch { /* plain */ }
  const why = status === 401 ? "token rejected (401 — run tools/gdrive-oauth-ims.sh again if it keeps failing)"
    : status === 403 ? "forbidden (403 — Contributor cannot do this, or the Drive API quota)"
    : status === 404 ? "not found (404 — parent folder or target file)"
    : status === 429 ? "rate limited (429)" : status >= 500 ? `Drive server error (${status})` : `Drive ${status}`;
  return `${what}: ${why}: ${msg}`.slice(0, 500);
}
export const stale = (createdAt: string, now: number, minutes: number) => now - new Date(createdAt).getTime() > minutes * 60_000;

// ── 폴더 사슬 — root → (꼭대기 Customers | Suppliers) → … → 대상 · 회차 안 캐시(같은 손님의 둘째 문서는 찾기 0) ──
export class FolderCache {
  private top = new Map<string, string>();                 // 'Customers' · 'Suppliers' → id
  private byKey = new Map<string, string>();               // scope|ref → id
  constructor(private d: Deps, private token: string, private rootId: string) {}
  async topId(name: string): Promise<string> {
    const hit = this.top.get(name); if (hit) return hit;
    const id = (await this.d.findFolder(this.token, this.rootId, this.rootId, name)) ?? await this.d.createFolder(this.token, this.rootId, name);
    this.top.set(name, id); return id;
  }
  async resolve(folders: Folder[]): Promise<string> {
    let parent = this.rootId;
    for (const f of folders) {
      if (f.under === TOP.Customers || f.under === TOP.Suppliers) parent = await this.topId(f.under);
      // under 'supplier' · 'aone' = 앞 폴더 · null = root(parent 그대로)
      const key = f.scope + "|" + f.ref;
      let id = f.folder_id ?? this.byKey.get(key) ?? null;
      if (!id) {
        const found = await this.d.findFolder(this.token, this.rootId, parent, f.name);
        const made = found ?? await this.d.createFolder(this.token, parent, f.name);
        id = await this.d.folderSet(f.scope, f.ref, made, f.name);          // 먼저 적힌 것이 이긴다(경쟁)
      }
      this.byKey.set(key, id);
      parent = id;
    }
    return parent;
  }
}

// ── 흐름 ──
export async function driveStep(d: Deps, o: { batch: number; budgetMs: number }): Promise<StepOut> {
  const t0 = d.now(), counts: Record<string, number> = { pdf_made: 0, uploaded: 0, shortcuts: 0, renamed: 0, failed: 0, claimed: 0 };
  let token: string | null = null, cache: FolderCache | null = null;
  const tok = async (rootId: string) => { if (token === null) { token = await d.token(); cache = new FolderCache(d, token, rootId); } return token; };
  while (d.now() - t0 < o.budgetMs) {
    const jobs = await d.claim(o.batch);
    if (!jobs.length) break;
    counts.claimed += jobs.length;
    for (const j of jobs) {
      if (d.now() - t0 >= o.budgetMs) break;                                   // 집은 나머지는 10 분 잠금 뒤 다음 회차
      try {
        if (j.kind === "archive" && j.status === "waiting_pdf") {
          if (!j.doc) throw new Error("archive job without a document");
          const r = await d.render(j.doc.kind, j.doc.ref);
          if (!r.ok) { await d.failed(j.job_id, r.error); counts.failed++; d.log(`drive pdf failed (${j.doc.kind} attempt ${j.attempts + 1}): ${r.error}`); continue; }
          await d.pdfSet(j.job_id, r.doc_file_id); counts.pdf_made++; continue;
        }
        if (j.status !== "sending") throw new Error(`job ${j.kind} is ${j.status} — nothing to do`);
        let t: string;
        try { t = await tok(j.root_id); }
        catch (e) { return { ok: false, status: "token_error", error: String((e as Error)?.message ?? e).slice(0, 300), counts }; }   // 열쇠 문제 — 일을 태우지 않는다(이견 10)
        if (j.kind === "rename") {
          if (!j.drive_file_id || !j.file_name) throw new Error("rename job without a drive id or a new name");
          await d.rename(t, j.drive_file_id, j.file_name); await d.done(j.job_id, null); counts.renamed++; continue;
        }
        if (j.kind === "shortcut") {
          if (!j.shortcut_target_drive_file_id) throw new Error("the original file is not on Drive yet — its upload must finish first");
          if (!j.file_name) throw new Error("shortcut job without a name");
          const parent = await cache!.resolve(j.folders);
          const id = await d.shortcut(t, parent, j.file_name, j.shortcut_target_drive_file_id);
          await d.done(j.job_id, id); counts.shortcuts++; continue;
        }
        // archive(sending) · upload — 파일 올리기
        if (!j.file || !j.file_name) throw new Error(`${j.kind} job without a file or a name`);
        const parent = await cache!.resolve(j.folders);
        const bytes = await d.readFile(j.file.bucket, j.file.path);
        if (!bytes.length) throw new Error(`storage ${j.file.bucket}/${j.file.path} is empty`);
        const id = await d.upload(t, parent, j.file_name, j.file.mime, bytes, j.description);
        await d.done(j.job_id, id); counts.uploaded++;
      } catch (e) {
        const msg = String((e as Error)?.message ?? e).slice(0, 500);
        try { await d.failed(j.job_id, msg); } catch (e2) { d.log(`drive_job_failed itself failed: ${String((e2 as Error)?.message ?? e2).slice(0, 200)}`); }
        counts.failed++; d.log(`drive job ${j.kind} failed (attempt ${j.attempts + 1}): ${msg}`);
      }
    }
  }
  return { ok: true, status: "done", counts };
}
