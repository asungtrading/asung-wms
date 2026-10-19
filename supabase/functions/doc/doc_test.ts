// deno test supabase/functions/doc/doc_test.ts — Gotenberg · DB · Storage 무접촉(가짜) · doc-2 E1 ~ E5
import { classifyGotenberg, docNumber, ensureMeta, fileName, gate, gotenbergRequest, isPdf, pdfPages, renderAll, renderHtml, safeName, sha256Hex, stamp, type Deps, type GOutcome, type RenderReq } from "../_shared/doc.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const PDF = new TextEncoder().encode("%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\n2 0 obj << /Type /Pages /Count 2 >> endobj\n3 0 obj << /Type /Page >> endobj\n4 0 obj << /Type /Page >> endobj\n%%EOF");
const BODY = '<html><head><style>@page{size:Letter}</style></head><body><h1>{{doc.title}}</h1><p>{{bill_to.name}}</p>{{#orders}}<table><thead><tr><th>SKU</th></tr></thead>{{#lines}}<tr><td>{{sku}}</td></tr>{{/lines}}</table>{{/orders}}</body></html>';
const DOC = { doc: { title: "FINAL INVOICE" }, invoice: { number: "60009" }, bill_to: { name: "Maple <Café> & Co" }, orders: [{ lines: [{ sku: "AAA-1" }, { sku: "BBB-2" }] }] };

Deno.test("E1 meta 끼우기 — <head> 있는 판 · 없는 판 · 이미 charset 이 있는 판(두 번 안 넣음) · 그리기는 이스케이프", () => {
  const h = ensureMeta('<html><head><style>x</style></head><body>a</body></html>');
  eq(h, '<html><head><meta charset="utf-8"><style>x</style></head><body>a</body></html>', "head 바로 뒤");
  eq(ensureMeta("<p>no head</p>"), '<meta charset="utf-8"><p>no head</p>', "head 없으면 맨 앞");
  const already = '<html><head><meta charset="utf-8"></head></html>';
  eq(ensureMeta(already), already, "이미 있으면 그대로");
  eq((ensureMeta(already).match(/charset/g) ?? []).length, 1, "하나만");
  const r = renderHtml(BODY, DOC);
  ok(r.includes("Maple &lt;Café&gt; &amp; Co") && !r.includes("<Café>"), "mustache 이스케이프");
  ok(r.includes("<td>AAA-1</td>") && r.includes("<td>BBB-2</td>"), "목록 섹션");
});

Deno.test("E2 요청 꼴 — 경로 · Basic 머리 · multipart files=index.html · preferCssPageSize · printBackground · 이름 · 번호", async () => {
  const q = gotenbergRequest("https://g.example.run.app/", "ims", "p@ss:word", "<p>x</p>");
  eq(q.url, "https://g.example.run.app/forms/chromium/convert/html", "경로(끝 / 정리)");
  eq(q.headers.Authorization, "Basic " + btoa("ims:p@ss:word"), "Basic ims:pass");
  const files = q.form.getAll("files");
  eq(files.length, 1, "files 하나");
  const f = files[0] as File;
  eq(f.name, "index.html", "주 파일 이름");
  eq(await f.text(), "<p>x</p>", "본문");
  eq(q.form.get("preferCssPageSize"), "true", "판의 @page");
  eq(q.form.get("printBackground"), "true", "배경");
  const now = new Date("2026-10-19T18:10:14.123Z");
  eq(stamp(now), "20261019T181014Z", "시각");
  eq(fileName("final_invoice", "60009", 5, now, 0), "final_invoice/60009-t5-20261019T181014Z.pdf", "번호 있는 이름");
  eq(fileName("ship_ready", null, 2, now, 1), "ship_ready/shipready-20261019-2-t2-20261019T181014Z.pdf", "번호 없는 이름(묶음 2)");
  eq(fileName("credit_note", "CR-01000", 1, now, 0), "credit_note/CR-01000-t1-20261019T181014Z.pdf", "크레딧");
  eq(safeName("SO-25003 / é"), "SO-25003", "이름 정리");
  eq(docNumber("final_invoice", DOC), "60009", "번호");
  eq(docNumber("ship_ready", DOC), null, "ship_ready 는 번호 없음");
  eq(docNumber("sales_order", { so: { number: " SO-1 " } }), "SO-1", "SO");
});

Deno.test("E3 응답 갈래 — 200 PDF · 200 아닌 것 · 401 · 403 · 400 · 409 · 503 · 시간 초과 · 네트워크 · 쪽 수 · sha256", async () => {
  ok(isPdf(PDF) && !isPdf(new TextEncoder().encode("<html>")), "%PDF- 머리");
  const c = classifyGotenberg({ kind: "http", status: 200, bytes: PDF, text: "", trace: "t1" });
  ok(c.ok && c.bytes === PDF, "200 PDF");
  const nb = classifyGotenberg({ kind: "http", status: 200, bytes: new TextEncoder().encode("<html>oops"), text: "", trace: "t2" });
  ok(!nb.ok && /not a PDF/.test(nb.error) && /trace t2/.test(nb.error), "200 but HTML");
  const x = (o: GOutcome) => { const r = classifyGotenberg(o); return r.ok ? "OK" : r.error; };
  ok(/401/.test(x({ kind: "http", status: 401, bytes: new Uint8Array(0), text: "Unauthorized", trace: null })) && /GOTENBERG_USER/.test(x({ kind: "http", status: 401, bytes: new Uint8Array(0), text: "", trace: null })), "401");
  ok(/403/.test(x({ kind: "http", status: 403, bytes: new Uint8Array(0), text: "filtered https://evil", trace: "t3" })), "403");
  ok(/400/.test(x({ kind: "http", status: 400, bytes: new Uint8Array(0), text: "bad form", trace: null })), "400");
  ok(/409/.test(x({ kind: "http", status: 409, bytes: new Uint8Array(0), text: "console", trace: null })), "409");
  ok(/503/.test(x({ kind: "http", status: 503, bytes: new Uint8Array(0), text: "timeout", trace: null })), "503");
  ok(/did not answer in time/.test(x({ kind: "timeout" })), "timeout");
  ok(/could not reach/.test(x({ kind: "network", message: "dns" })), "network");
  eq(pdfPages(PDF), 2, "쪽 수 2(/Type /Page 둘 · /Pages 는 안 센다)");
  eq(pdfPages(new TextEncoder().encode("%PDF-1.7 compressed")), null, "못 세면 null");
  eq(await sha256Hex(new TextEncoder().encode("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256");
});

function fakeDeps(calls: string[], opts: { convert?: (html: string) => GOutcome; docs?: unknown[]; groups?: { group: string; so_ids?: unknown }[]; ok?: boolean; kind?: string } = {}): Deps {
  const docs = opts.docs ?? [DOC];
  return {
    getTemplate: async (kind, id) => { calls.push("template:" + kind + ":" + (id ?? "active")); return { id: "11111111-1111-4111-8111-111111111111", kind: opts.kind ?? kind, version: 5, body: BODY, ok: opts.ok ?? true }; },
    getData: async (kind, ref) => { calls.push("data:" + kind + ":" + JSON.stringify(ref)); return { docs, groups: opts.groups }; },
    convert: async (html) => { calls.push("convert:" + html.length); return (opts.convert ?? (() => ({ kind: "http", status: 200, bytes: PDF, text: "", trace: "tr" })))(html); },
    upload: async (path, bytes) => { calls.push("upload:" + path + ":" + bytes.length); },
    addFile: async (row) => { calls.push("add:" + row.path + ":" + row.sha256.slice(0, 8) + ":" + row.reason + ":" + (row.doc_number ?? "null") + ":" + JSON.stringify(row.ref)); return { id: "f-" + calls.length }; },
    sign: async (path) => { calls.push("sign:" + path); return "https://x/sign/" + path + "?token=t"; },
    now: () => new Date("2026-10-19T18:10:14Z"),
    staffId: "staff-1",
  };
}
const REQ: RenderReq = { kind: "final_invoice", ref: { invoice_id: "i-1" }, reason: "print" };

Deno.test("E4 흐름 — 판 · 데이터 · 변환 · 올리기 · 한 줄 · 서명 순서 · docs 둘(ship_ready 묶음)이면 파일 둘 · ref 에 group · so_ids", async () => {
  const calls: string[] = [];
  const out = await renderAll(fakeDeps(calls), REQ, { mode: "staff", jwt: "j" });
  eq(out.template_version, 5, "판 번호");
  eq(out.files.length, 1, "파일 하나");
  eq(out.files[0].path, "final_invoice/60009-t5-20261019T181014Z.pdf", "경로");
  eq(out.files[0].pages, 2, "쪽");
  ok(out.files[0].signed_url.includes("60009-t5"), "서명 URL");
  eq(calls.map((c) => c.split(":")[0]), ["template", "data", "convert", "upload", "add", "sign"], "순서");
  ok(calls[4].includes(':print:60009:{"invoice_id":"i-1"}'), "doc_file 행");
  const calls2: string[] = [];
  const two = await renderAll(fakeDeps(calls2, { docs: [DOC, { ...DOC, invoice: { number: "" } }], groups: [{ group: "c1|g1", so_ids: ["a"] }, { group: "c1|g2", so_ids: ["b"] }] }),
                              { kind: "ship_ready", ref: { orders: [{ so_id: "a" }, { so_id: "b" }] }, reason: "preview" }, { mode: "staff", jwt: "j" });
  eq(two.files.length, 2, "묶음 둘 → 파일 둘");
  eq(two.files.map((f) => f.group), ["c1|g1", "c1|g2"], "group");
  ok(two.files[0].path.startsWith("ship_ready/shipready-20261019-1-t5-") && two.files[1].path.startsWith("ship_ready/shipready-20261019-2-t5-"), "번호 없는 이름 1 · 2");
  ok(calls2.some((c) => c.startsWith("add:") && c.includes('"group":"c1|g2"') && c.includes('"so_ids":["b"]')), "ref 에 group · so_ids");
  const calls3: string[] = [];
  await renderAll(fakeDeps(calls3), { ...REQ, template_id: "22222222-2222-4222-8222-222222222222" }, { mode: "staff", jwt: "j" });
  ok(calls3[0] === "template:final_invoice:22222222-2222-4222-8222-222222222222", "주어진 판으로(발행 때의 판으로 다시)");
});

Deno.test("E5 문 · 실패 — service 길의 ship_ready 거부 · 모르는 kind · reason · ref 모양 · 변환 실패면 올리기 · 한 줄 없음 · 검사 통과 못 한 판 · kind 어긋난 판 · 빈 docs", async () => {
  eq(gate({ kind: "ship_ready", ref: { orders: [] }, reason: "send" }, { mode: "service" }), "ship_ready needs a staff login — the finalize preview asks for sales permission (doc-1b2)", "service + ship_ready");
  eq(gate({ kind: "ship_ready", ref: { orders: [] }, reason: "send" }, { mode: "staff", jwt: "j" }), null, "staff + ship_ready");
  ok(/kind must be/.test(gate({ kind: "invoice", ref: {}, reason: "print" }, { mode: "staff", jwt: "j" }) ?? ""), "kind");
  ok(/reason must be/.test(gate({ kind: "final_invoice", ref: {}, reason: "x" }, { mode: "staff", jwt: "j" }) ?? ""), "reason");
  ok(/ref must be/.test(gate({ kind: "final_invoice", ref: [], reason: "print" }, { mode: "staff", jwt: "j" }) ?? ""), "ref");
  ok(/template_id/.test(gate({ ...REQ, template_id: "nope" }, { mode: "staff", jwt: "j" }) ?? ""), "template_id");
  const calls: string[] = [];
  let err = "";
  try { await renderAll(fakeDeps(calls, { convert: () => ({ kind: "http", status: 401, bytes: new Uint8Array(0), text: "", trace: null }) }), REQ, { mode: "staff", jwt: "j" }); } catch (e) { err = String(e); }
  ok(/401/.test(err) && !calls.some((c) => c.startsWith("upload") || c.startsWith("add")), "변환 실패 → 아무것도 안 남김");
  err = ""; try { await renderAll(fakeDeps([], { ok: false }), REQ, { mode: "staff", jwt: "j" }); } catch (e) { err = String(e); }
  ok(/did not pass its checks/.test(err), "실패 판");
  err = ""; try { await renderAll(fakeDeps([], { kind: "credit_note" }), REQ, { mode: "staff", jwt: "j" }); } catch (e) { err = String(e); }
  ok(/is for credit_note, not final_invoice/.test(err), "kind 어긋난 판");
  err = ""; try { await renderAll(fakeDeps([], { docs: [] }), REQ, { mode: "staff", jwt: "j" }); } catch (e) { err = String(e); }
  ok(/no pages/.test(err), "빈 docs");
  err = ""; try { await renderAll(fakeDeps([]), { kind: "ship_ready", ref: { orders: [] }, reason: "send" }, { mode: "service" }); } catch (e) { err = String(e); }
  ok(/staff login/.test(err), "renderAll 도 service + ship_ready 거부");
});
