// deno test supabase/functions/drive/drive_test.ts — Drive · DB · Storage · EF doc 무접촉(가짜) · drive-2 D1 ~ D9
import { driveError, driveStep, FolderCache, folderQuery, listUrl, multipartUpload, qEscape, stale, type Deps, type Job } from "../_shared/drive.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const ROOT = "0AM8jftaU51hyUk9PVA";
const CUST = (fid: string | null) => [{ scope: "customer", ref: "c-1", name: "DRIVE1-Cust", folder_id: fid, under: "Customers" }];
const PO = (sup: string | null, po: string | null) => [{ scope: "supplier", ref: "s-1", name: "Andis", folder_id: sup, under: "Suppliers" }, { scope: "po", ref: "p-1", name: "PO-02100", folder_id: po, under: "supplier" }];
const AONE = (a: string | null, m: string | null) => [{ scope: "aone", ref: "root", name: "aonebeauty", folder_id: a, under: null }, { scope: "aone_month", ref: "2026-11", name: "2026-11", folder_id: m, under: "aone" }];
const J = (o: Partial<Job>): Job => ({ job_id: "j", kind: "upload", status: "sending", attempts: 0, root_id: ROOT, target: { scope: "customer", ref: "c-1" }, folders: CUST(null), file_name: "20261103_INV_60001.pdf", description: "Invoice 60001",
  doc: null, file: { bucket: "documents", path: "final_invoice/60001-t6-x.pdf", bytes: 3, sha256: "ab", mime: "application/pdf" }, drive_file_id: null, shortcut_id: null, shortcut_target_drive_file_id: null, ...o });

type Log = string[];
function fake(calls: Log, jobsPerClaim: Job[][], opts: Partial<Deps> & { tokenFails?: boolean; clock?: () => number } = {}): Deps {
  let claimN = 0, created = 0;
  const known = new Map<string, string>();                                   // find 가 보는 「드라이브에 이미 있는」 폴더: parent|name → id
  return {
    token: async () => { calls.push("token"); if (opts.tokenFails) throw new Error("token endpoint 400 invalid_grant"); return "T"; },
    claim: async (n) => { calls.push("claim:" + n); const j = jobsPerClaim[claimN++] ?? []; return j; },
    render: async (kind, ref) => { calls.push("render:" + kind + ":" + JSON.stringify(ref)); return { ok: true, doc_file_id: "df-1" }; },
    pdfSet: async (id, df) => { calls.push("pdfSet:" + id + ":" + df); },
    findFolder: async (_t, _d, parent, name) => { calls.push("find:" + parent + ":" + name); return known.get(parent + "|" + name) ?? null; },
    createFolder: async (_t, parent, name) => { created++; const id = "F" + created; calls.push("create:" + parent + ":" + name + "=" + id); known.set(parent + "|" + name, id); return id; },
    folderSet: async (scope, ref, id, name) => { calls.push("folderSet:" + scope + ":" + ref + ":" + id + ":" + name); return id; },
    readFile: async (bucket, path) => { calls.push("read:" + bucket + ":" + path); return new Uint8Array([1, 2, 3]); },
    upload: async (_t, parent, name, mime, bytes, desc) => { calls.push("upload:" + parent + ":" + name + ":" + mime + ":" + bytes.length + ":" + (desc ?? "")); return "FILE-" + name; },
    shortcut: async (_t, parent, name, target) => { calls.push("shortcut:" + parent + ":" + name + "->" + target); return "SC-" + name; },
    rename: async (_t, id, name) => { calls.push("rename:" + id + ":" + name); },
    done: async (id, drive) => { calls.push("done:" + id + ":" + (drive ?? "null")); },
    failed: async (id, err) => { calls.push("failed:" + id + ":" + err.slice(0, 60)); },
    now: opts.clock ?? (() => 1000),
    log: () => {},
    ...opts,
  };
}
const O = { batch: 5, budgetMs: 40_000 };

Deno.test("D1 multipart 올리기 몸 — related · 경계 · JSON 메타(name · parents · mimeType · description) · 바이트 그대로 · 끝 경계", () => {
  const m = multipartUpload({ name: "a.pdf", parents: ["P"], mimeType: "application/pdf", description: "Invoice 60001" }, "application/pdf", new Uint8Array([0x25, 0x50, 0x44, 0x46]), "B1");
  eq(m.contentType, "multipart/related; boundary=B1", "content-type");
  const s = new TextDecoder().decode(m.body);
  ok(s.startsWith('--B1\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{"name":"a.pdf","parents":["P"],"mimeType":"application/pdf","description":"Invoice 60001"}\r\n--B1\r\nContent-Type: application/pdf\r\n\r\n%PDF'), "머리 · 메타 · 둘째 부분");
  ok(s.endsWith("%PDF\r\n--B1--"), "끝 경계");
  const m2 = multipartUpload({ name: "x", parents: ["P"], mimeType: "image/jpeg", description: undefined }, "image/jpeg", new Uint8Array(0), "B2");
  ok(!new TextDecoder().decode(m2.body).includes("description"), "설명 없으면 키도 없다");
});
Deno.test("D2 폴더 찾기 질의 — 따옴표 · 역슬래시 이스케이프 · 부모 · 휴지통 제외 · list URL(corpora drive · driveId · supportsAllDrives)", () => {
  eq(qEscape("O'Reilly \\ Co"), "O\\'Reilly \\\\ Co", "이스케이프");
  eq(folderQuery("P1", "Clore Inc. (BLW)"), "name = 'Clore Inc. (BLW)' and mimeType = 'application/vnd.google-apps.folder' and 'P1' in parents and trashed = false", "질의");
  const u = new URL(listUrl(ROOT, "q1"));
  eq(u.origin + u.pathname, "https://www.googleapis.com/drive/v3/files", "경로");
  eq([u.searchParams.get("corpora"), u.searchParams.get("driveId"), u.searchParams.get("includeItemsFromAllDrives"), u.searchParams.get("supportsAllDrives"), u.searchParams.get("q")], ["drive", ROOT, "true", "true", "q1"], "매개변수");
  ok(/token rejected \(401/.test(driveError("upload", 401, '{"error":{"message":"Invalid Credentials"}}')) && /Invalid Credentials/.test(driveError("upload", 401, '{"error":{"message":"Invalid Credentials"}}')), "401");
  ok(/forbidden \(403/.test(driveError("x", 403, "")) && /not found \(404/.test(driveError("x", 404, "")) && /rate limited/.test(driveError("x", 429, "")) && /server error \(503\)/.test(driveError("x", 503, "<html>")), "갈래");
  ok(driveError("x", 500, "a".repeat(900)).length <= 500, "500 자");
  ok(stale("2026-10-24T10:00:00Z", Date.parse("2026-10-24T10:31:00Z"), 30) && !stale("2026-10-24T10:00:00Z", Date.parse("2026-10-24T10:29:00Z"), 30), "오래됨 30 분");
});
Deno.test("D3 보관본 PDF — waiting_pdf → EF doc render(archive) → pdfSet · 토큰 없이(drive_enabled off 에서도) · render 실패 → failed", async () => {
  const calls: Log = [];
  const a = J({ job_id: "a1", kind: "archive", status: "waiting_pdf", doc: { kind: "final_invoice", ref: { invoice_id: "i-1" }, number: "60001", status: "issued" }, file: null });
  const out = await driveStep(fake(calls, [[a]]), O);
  eq(calls, ["claim:5", "render:final_invoice:" + JSON.stringify({ invoice_id: "i-1" }), "pdfSet:a1:df-1", "claim:5"], "토큰 없이 · render → pdfSet · 다음 claim 이 비어 끝");
  eq(out.counts.pdf_made, 1, "pdf_made");
  const calls2: Log = [];
  const out2 = await driveStep(fake(calls2, [[a]], { render: async () => ({ ok: false, error: "doc 500: Gotenberg did not answer in time" }) }), O);
  ok(calls2.some((c) => c.startsWith("failed:a1:doc 500")) && !calls2.some((c) => c.startsWith("pdfSet")), "render 실패 → failed · pdfSet 없음");
  eq(out2.counts.failed, 1, "failed 수");
});
Deno.test("D4 올리기 — 폴더 사슬(Customers 꼭대기 찾기 → 없으면 만들기 · 손님 폴더 만들고 folderSet) · Storage 읽기 → Drive 올리기 → done(drive id) · 같은 손님 둘째 문서는 캐시(찾기 0)", async () => {
  const calls: Log = [];
  const j1 = J({ job_id: "u1" }), j2 = J({ job_id: "u2", file_name: "20261103_INV_60002.pdf", description: "Invoice 60002" });
  const out = await driveStep(fake(calls, [[j1, j2]]), O);
  eq(calls, ["claim:5", "token", "find:" + ROOT + ":Customers", "create:" + ROOT + ":Customers=F1", "find:F1:DRIVE1-Cust", "create:F1:DRIVE1-Cust=F2", "folderSet:customer:c-1:F2:DRIVE1-Cust",
             "read:documents:final_invoice/60001-t6-x.pdf", "upload:F2:20261103_INV_60001.pdf:application/pdf:3:Invoice 60001", "done:u1:FILE-20261103_INV_60001.pdf",
             "read:documents:final_invoice/60001-t6-x.pdf", "upload:F2:20261103_INV_60002.pdf:application/pdf:3:Invoice 60002", "done:u2:FILE-20261103_INV_60002.pdf", "claim:5"], "순서 · 둘째는 찾기 · 만들기 0");
  eq([out.counts.uploaded, out.counts.failed, out.counts.claimed], [2, 0, 2], "셈");
  // folder_id 가 이미 있으면 찾기 · 만들기 · folderSet 없음(꼭대기만 한 번) · Drive 에 이미 있는 폴더는 찾아서 쓴다(중복 폴더 없음)
  const calls3: Log = [];
  const known = fake(calls3, [[J({ job_id: "u3", folders: CUST("FOLDc1") })]]);
  await driveStep(known, O);
  ok(calls3.includes("upload:FOLDc1:20261103_INV_60001.pdf:application/pdf:3:Invoice 60001") && !calls3.some((c) => c.startsWith("folderSet") || c.startsWith("find:F")), "folder_id 그대로");
  const calls4: Log = [];
  const d4 = fake(calls4, [[J({ job_id: "u4", folders: PO(null, null), file: { bucket: "po-documents", path: "po/p-1/a.pdf", bytes: 9, sha256: "x", mime: "image/jpeg" }, file_name: "20261022_BOL_12.jpg" })]]);
  await d4.createFolder("T", ROOT, "Suppliers");                              // 드라이브에 Suppliers 가 이미 있다(앱이 전에 만들었다)
  calls4.length = 0;
  await driveStep(d4, O);
  eq(calls4.slice(0, 8), ["claim:5", "token", "find:" + ROOT + ":Suppliers", "find:F1:Andis", "create:F1:Andis=F2", "folderSet:supplier:s-1:F2:Andis", "find:F2:PO-02100", "create:F2:PO-02100=F3"], "Suppliers 는 찾아서 · 공급처 · PO 는 만들어서");
  ok(calls4.includes("folderSet:po:p-1:F3:PO-02100") && calls4.includes("read:po-documents:po/p-1/a.pdf") && calls4.includes("upload:F3:20261022_BOL_12.jpg:image/jpeg:3:Invoice 60001"), "PO 폴더에 jpg 그대로");
});
Deno.test("D5 바로가기 — 원본 drive id 있으면 PO 폴더에 만들고 done · 없으면 failed(올리기가 먼저 끝나야) · aone 사슬(root 아래 aonebeauty → 달)", async () => {
  const calls: Log = [];
  const sc = J({ job_id: "s1", kind: "shortcut", folders: PO("FS", "FP"), file_name: "20261024_INV_FC-1.pdf", shortcut_id: "sc-1", shortcut_target_drive_file_id: "FILE-bill", file: null });
  const miss = J({ job_id: "s2", kind: "shortcut", folders: PO("FS", "FP"), file_name: "x.pdf", shortcut_id: "sc-2", shortcut_target_drive_file_id: null, file: null });
  await driveStep(fake(calls, [[sc, miss]]), O);
  ok(calls.includes("shortcut:FP:20261024_INV_FC-1.pdf->FILE-bill") && calls.includes("done:s1:SC-20261024_INV_FC-1.pdf"), "바로가기 · done");
  ok(calls.some((c) => c.startsWith("failed:s2:the original file is not on Drive yet")), "원본 없으면 failed");
  const calls2: Log = [];
  await driveStep(fake(calls2, [[J({ job_id: "u5", folders: AONE(null, null), file_name: "20261103_INV_60003_Kim.pdf" })]]), O);
  eq(calls2.slice(1, 8), ["token", "find:" + ROOT + ":aonebeauty", "create:" + ROOT + ":aonebeauty=F1", "folderSet:aone:root:F1:aonebeauty", "find:F1:2026-11", "create:F1:2026-11=F2", "folderSet:aone_month:2026-11:F2:2026-11"], "aone 사슬은 root 바로 아래");
  ok(calls2.includes("upload:F2:20261103_INV_60003_Kim.pdf:application/pdf:3:Invoice 60001"), "달 폴더에");
});
Deno.test("D6 이름 바꾸기 — files.update → done(null) · drive id 없는 rename 은 failed · 모르는 상태(queued 로 온 일)는 failed", async () => {
  const calls: Log = [];
  const r = J({ job_id: "r1", kind: "rename", drive_file_id: "FILE-x", file_name: "CANCELLED_20261103_INV_60001.pdf", file: null, folders: [] });
  const bad = J({ job_id: "r2", kind: "rename", drive_file_id: null, file_name: "x", file: null, folders: [] });
  const odd = J({ job_id: "q1", status: "queued" });
  await driveStep(fake(calls, [[r, bad, odd]]), O);
  ok(calls.includes("rename:FILE-x:CANCELLED_20261103_INV_60001.pdf") && calls.includes("done:r1:null"), "rename · done(null)");
  ok(calls.some((c) => c.startsWith("failed:r2:rename job without a drive id")) && calls.some((c) => c.startsWith("failed:q1:job upload is queued")), "failed 갈래");
});
Deno.test("D7 실패 — Drive 올리기 403 → failed(메시지) 하고 다음 일로 · Storage 빈 파일 → failed · failed 자체가 죽어도 회차는 간다", async () => {
  const calls: Log = [];
  let n = 0;
  const d = fake(calls, [[J({ job_id: "u1" }), J({ job_id: "u2", file_name: "b.pdf" }), J({ job_id: "u3", file_name: "c.pdf" })]], {
    upload: async (_t, _p, name) => { if (name === "20261103_INV_60001.pdf") throw new Error(driveError("upload", 403, '{"error":{"message":"The user does not have sufficient permissions"}}')); return "FILE-" + name; },
    readFile: async (_b, _p) => { n++; return n === 2 ? new Uint8Array(0) : new Uint8Array([1]); },
  });
  const out = await driveStep(d, O);
  ok(calls.some((c) => c.startsWith("failed:u1:upload: forbidden (403")) && calls.some((c) => c.startsWith("failed:u2:storage documents/") ) && calls.includes("done:u3:FILE-c.pdf"), "둘 failed · 셋째 done");
  eq([out.counts.failed, out.counts.uploaded], [2, 1], "셈");
  const calls2: Log = [];
  const out2 = await driveStep(fake(calls2, [[J({ job_id: "u9" })]], { upload: async () => { throw new Error("boom"); }, failed: async () => { throw new Error("rpc down"); } }), O);
  eq(out2.status, "done", "failed 창구가 죽어도 회차는 끝난다");
});
Deno.test("D8 열쇠 실패 — waiting_pdf 는 처리하고, 드라이브 쓰기 일은 태우지 않고 회차 오류(token_error) · 토큰은 회차에 한 번", async () => {
  const calls: Log = [];
  const a = J({ job_id: "a1", kind: "archive", status: "waiting_pdf", doc: { kind: "credit_note", ref: { credit_id: "c-1" } }, file: null });
  const out = await driveStep(fake(calls, [[a, J({ job_id: "u1" }), J({ job_id: "u2" })]], { tokenFails: true }), O);
  eq(out.status, "token_error", "회차 오류");
  ok(/invalid_grant/.test(out.error ?? ""), "이유");
  ok(calls.includes("pdfSet:a1:df-1") && !calls.some((c) => c.startsWith("failed") || c.startsWith("done")), "PDF 는 만들고 · 올리기 일은 안 태움");
  eq(calls.filter((c) => c === "token").length, 1, "토큰 한 번");
  const calls2: Log = [];
  await driveStep(fake(calls2, [[J({ job_id: "u1" }), J({ job_id: "u2" })]]), O);
  eq(calls2.filter((c) => c === "token").length, 1, "성공해도 한 번");
});
Deno.test("D9 예산 — 시간이 지나면 다음 claim 을 안 한다 · 집은 묶음 안에서도 멈춘다(남은 것은 10 분 잠금 뒤) · 빈 claim 이면 끝", async () => {
  let t = 0;
  const calls: Log = [];
  const out = await driveStep(fake(calls, [[J({ job_id: "u1" }), J({ job_id: "u2" })], [J({ job_id: "u3" })]], { clock: () => { t += 15_000; return t; } }), { batch: 5, budgetMs: 40_000 });
  ok(calls.includes("done:u1:FILE-20261103_INV_60001.pdf") && !calls.some((c) => c.startsWith("done:u3")), "셋째 묶음까지 안 간다");
  eq(calls.filter((c) => c.startsWith("claim")).length, 1, "claim 한 번");
  eq(out.status, "done", "status");
  const cache = new FolderCache(fake([], []), "T", ROOT);
  eq(await cache.resolve([]), ROOT, "빈 사슬 = root");
});
