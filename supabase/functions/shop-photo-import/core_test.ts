// deno test supabase/functions/shop-photo-import/core_test.ts — Shopify · CDN · 저장소 · DB 무접촉(가짜 Io) · shop-photo-imp-2b-2 ① ~ ⑨
import { batches, buildSkuMap, judgePlan, md5Hex, parseProducts, pickBody, PRODUCT_CHUNK, PRODUCT_NODES_QUERY, resumeAfter, runCheck, runMove, runPairs, selftest, sniff, stemClash, targets, TIME_BUDGET_MS, verifyDownload, type ClaimRow, type Ctx, type Io, type PairRow, type PlanRow, type Prod } from "./core.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const S1 = { id: "s1000000-0000-0000-0000-000000000000", code: "asung" }, S2 = { id: "s2000000-0000-0000-0000-000000000000", code: "aone" };
const PG = (n: number) => "gid://shopify/Product/" + n, MG = (n: number) => "gid://shopify/MediaImage/" + n, CDN = (name: string) => "https://cdn.shopify.com/s/files/1/0/files/" + name + "?v=1";
const JPG = (seed: number, len = 64) => { const b = new Uint8Array(len).fill(seed); b.set([0xff, 0xd8, 0xff, 0xe0]); return b; };
const PNG = (seed: number) => { const b = new Uint8Array(64).fill(seed); b.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]); return b; };
const plan = (id: number, store: typeof S1, p: number, m: number, name: string, rule = "variant", status = "planned"): PlanRow => ({ id, rule, status, src_store_id: store.id, src_product_gid: PG(p), src_media_gid: MG(m), src_url: CDN(name) });
const pair = (id: number, store: typeof S1, p: number, m: number, kind = "same", status = "planned", plan_id: number | null = null): PairRow => ({ id, store_id: store.id, product_gid: PG(p), media_gid: MG(m), pair_kind: kind, status, plan_id });
const prod = (p: number, media: Array<[number, string]>, variants = 2, complete = true): Prod => ({ gid: PG(p), variants, complete, media: media.map(([m, name]) => ({ gid: MG(m), url: CDN(name) })) });

// 가짜 Io — 부른 것을 전부 적는다 · 시계는 손으로 민다
type Fake = Io & { calls: Array<{ fn: string; args: any }>; reads: string[][]; uploads: string[]; clock: number; slept: number };
function fake(o: { ctx?: Partial<Ctx>; prods?: Prod[]; readFail?: (gids: string[]) => string | null; rpc?: (fn: string, args: any, f: Fake) => unknown; files?: Record<string, Uint8Array | number>; uploadFail?: (path: string) => boolean; tick?: number } = {}): Fake {
  const f: Fake = {
    calls: [], reads: [], uploads: [], clock: 0, slept: 0,
    now: () => f.clock,
    sleep: (ms) => { f.slept += ms; return Promise.resolve(); },
    context: (only) => Promise.resolve({ stores: [S1, S2], mediaGids: [], skus: {}, pairs: [], ...o.ctx, plan: (o.ctx?.plan ?? []).filter((r) => !only || only.includes(r.id)) }),
    readProducts: (_store, gids) => { f.reads.push(gids); f.clock += o.tick ?? 0; const e = o.readFail?.(gids); return Promise.resolve(e ? { ok: false as const, error: e } : { ok: true as const, prods: (o.prods ?? []).filter((p) => gids.includes(p.gid)) }); },
    rpc: (fn, args) => { f.calls.push({ fn, args }); return Promise.resolve(o.rpc ? o.rpc(fn, args, f) : fn === "shop_photo_verify_mark" ? (args.p_rows as unknown[]).length : {}); },
    download: (url) => { f.clock += o.tick ?? 0; const x = o.files?.[url]; return Promise.resolve(x instanceof Uint8Array ? { bytes: x, status: 200 } : { bytes: null, status: typeof x === "number" ? x : 404 }); },
    upload: (path) => { f.uploads.push(path); return Promise.resolve(o.uploadFail?.(path) ? { ok: false, error: "http 500 boom" } : { ok: true }); },
    remaining: () => Promise.resolve(7),
  };
  return f;
}
const rpcOf = (f: Fake, fn: string) => f.calls.filter((c) => c.fn === fn).map((c) => c.args);

Deno.test("① selftest · md5 · sniff — 이 런타임의 md5 가 맞다 · 앞 바이트로 jpeg · png · webp · gif · 모르는 것", () => {
  eq(selftest(), { ok: true, md5_of_a: "0cc175b9c0f1b6a831c399e269772661", sniff_jpeg: "image/jpeg", sniff_png: "image/png" }, "selftest");
  eq(md5Hex(new TextEncoder().encode("The quick brown fox jumps over the lazy dog")), "9e107d9d372bb6826bd81d3542a419d6", "md5 known vector");
  eq([sniff(JPG(1)), sniff(PNG(1)), sniff(new TextEncoder().encode("RIFF0000WEBPVP8 ")), sniff(new TextEncoder().encode("GIF89a")), sniff(new TextEncoder().encode("<html>")), sniff(new Uint8Array(0))],
     ["image/jpeg", "image/png", "image/webp", "image/gif", null, null], "sniff");
});

Deno.test("② verifyDownload — 크기 · md5 · 형식이 계획과 같아야 한다 · 다르면 final(다시 해도 같다)", () => {
  const b = JPG(7), row = { byte_size: b.byteLength, file_md5: md5Hex(b), content_type: "image/jpeg" };
  eq(verifyDownload(row, b), { ok: true }, "same bytes");
  const size = verifyDownload(row, JPG(7, 65)) as any, md5 = verifyDownload(row, JPG(8)) as any, fmt = verifyDownload({ ...row, content_type: "image/png" }, b) as any;
  eq([size.ok, size.final, size.error.startsWith("byte size 65 differs")], [false, true, true], "size");
  eq([md5.ok, md5.final, md5.error.startsWith("md5 " + md5Hex(JPG(8)) + " differs")], [false, true, true], "md5");
  eq([fmt.ok, fmt.final, fmt.error], [false, true, "the file is image/jpeg but the plan says image/png"], "format (the plan says png, the bytes are jpeg)");
  const html = new TextEncoder().encode("<html>blocked</html>"), hr = verifyDownload({ byte_size: html.byteLength, file_md5: md5Hex(html), content_type: "image/jpeg" }, html) as any;
  eq(hr.error, "the file is not an image IMS knows but the plan says image/jpeg", "not an image");
});

Deno.test("③ pickBody · resumeAfter — 모드 · only · owners 거르기 · 이어 달리기 자리(only · restart 면 처음부터)", () => {
  eq(pickBody({ mode: "move" }), { mode: "move", only: null, owners: 60, retryFailed: false, restart: false }, "defaults");
  eq(pickBody({ mode: "check", only: [37, 88, 37], owners: 5, retry_failed: true, restart: true }), { mode: "check", only: [37, 88], owners: 5, retryFailed: true, restart: true }, "only de-duplicated");
  eq([pickBody(null), pickBody({ mode: "drain" })].map((x: any) => x.error), Array(2).fill("mode must be one of: selftest, check, pairs, move"), "unknown mode");
  eq([pickBody({ mode: "move", only: [] }), pickBody({ mode: "move", only: [1.5] }), pickBody({ mode: "move", only: "37" }), pickBody({ mode: "move", only: [0] })].map((x: any) => !!x.error), [true, true, true, true], "bad only");
  eq([pickBody({ mode: "move", owners: 0 }), pickBody({ mode: "move", owners: 61 }), pickBody({ mode: "move", owners: "x" })].map((x: any) => !!x.error), [true, true, true], "bad owners");
  const last = { counts: { remaining: 12, next_after: "asung|" + PG(5) } };
  eq(resumeAfter(last, { only: null, restart: false }), "asung|" + PG(5), "continue after the last product");
  eq([resumeAfter(last, { only: [1], restart: false }), resumeAfter(last, { only: null, restart: true }), resumeAfter({ counts: { remaining: 0, next_after: "x" } }, { only: null, restart: false }), resumeAfter(null, { only: null, restart: false })], [null, null, null, null], "from the start");
});

Deno.test("④ parseProducts · targets · batches — 없는 상품(null)은 빠진다 · media 100 넘으면 다 못 읽음 · 스토어 코드 · gid 순 · 꺼진 스토어 제외 · 10 개씩 · 스토어가 바뀌면 새 묶음", () => {
  const data = { nodes: [null, { id: PG(1), variants: { nodes: [{ id: "v1" }] }, media: { pageInfo: { hasNextPage: false }, nodes: [{ id: MG(1), image: { url: CDN("a.jpg") } }, { id: "gid://shopify/Video/9" }] } }, {}, { id: PG(2), variants: { nodes: [{}, {}] }, media: { pageInfo: { hasNextPage: true }, nodes: [] } }] };
  eq(parseProducts(data), [{ gid: PG(1), variants: 1, complete: true, media: [{ gid: MG(1), url: CDN("a.jpg") }, { gid: "gid://shopify/Video/9", url: null }] }, { gid: PG(2), variants: 2, complete: false, media: [] }], "parse");
  eq(parseProducts(null), [], "no data");
  eq(PRODUCT_NODES_QUERY.includes("nodes(ids: $ids)") && PRODUCT_NODES_QUERY.includes("media(first: 100)") && !/mutation/i.test(PRODUCT_NODES_QUERY), true, "read-only query");
  const list = [{ store_id: S1.id, gid: PG(2) }, { store_id: S2.id, gid: PG(9) }, { store_id: S1.id, gid: PG(1) }, { store_id: S1.id, gid: PG(2) }, { store_id: "off", gid: PG(3) }];
  eq(targets(list, [S1, S2], null).map((t) => t.key), ["aone|" + PG(9), "asung|" + PG(1), "asung|" + PG(2)], "sorted · distinct · switched-off store left out");
  eq(targets(list, [S1, S2], "asung|" + PG(1)).map((t) => t.key), ["asung|" + PG(2)], "after the resume point");
  const many = targets([...Array.from({ length: 12 }, (_, i) => ({ store_id: S1.id, gid: PG(100 + i) })), { store_id: S2.id, gid: PG(1) }], [S1, S2], null);
  eq(batches(many).map((b) => b.length + b[0].store.code), ["1aone", PRODUCT_CHUNK + "asung", "2asung"], "batches");
});

Deno.test("⑤ judgePlan · stemClash · buildSkuMap — 사라진 media · url 바뀜 · 1180 변형 수 · 다 못 읽음 · 상품 없음 · 이름 줄기 겹침(정확히 · _n · _<uuid> 만)", () => {
  const p = prod(1, [[1, "a.jpg"], [2, "b.jpg"]], 1);
  eq(judgePlan(plan(10, S1, 1, 1, "a.jpg", "1180"), p), { id: 10, ok: true, note: null, why: "ok" }, "ok");
  eq(judgePlan(plan(11, S1, 1, 3, "c.jpg"), p).why, "gone", "media gone");
  eq(judgePlan(plan(12, S1, 1, 3, "c.jpg"), { ...p, complete: false }).why, "unsure", "not found but not fully read → unsure, not gone");
  eq(judgePlan(plan(13, S1, 1, 2, "b.jpg"), { ...p, complete: false }).why, "ok", "found although not fully read");
  eq(judgePlan({ ...plan(14, S1, 1, 1, "a.jpg"), src_url: CDN("a.jpg").replace("v=1", "v=2") }, p).why, "url_changed", "?v= differs");
  eq([judgePlan(plan(15, S1, 1, 1, "a.jpg", "1180"), { ...p, variants: 2 }).why, judgePlan(plan(16, S1, 1, 1, "a.jpg", "variant"), { ...p, variants: 2 }).why], ["variants_changed", "ok"], "variant count matters for rule 1180 only");
  eq([judgePlan(plan(17, S1, 1, 1, "a.jpg"), undefined).why, judgePlan(plan(17, S1, 1, 1, "a.jpg"), undefined).ok], ["product_missing", false], "product missing");
  const U = "0a1b2c3d-0000-4000-8000-000000000000";
  const q = prod(2, [[1, "ONO00140FAM.jpg"], [2, "ONO00140FAM_2_" + U + ".png"], [3, "ONO00141.jpg"], [4, "ONO001410.jpg"], [5, "IMG_1.jpg"], [6, "ONO00141_3.jpg"], [7, "ono00141_x.jpg"]]);
  eq(stemClash(q, new Set([MG(6)]), ["ONO00140FAM", "ONO00141"]).map((x) => x.media_gid.split("/").pop() + ":" + x.sku), ["1:ONO00140FAM", "2:ONO00140FAM", "3:ONO00141"], "exact · _n_<uuid> · not the longer SKU · not other names · the paired one (6) is safe");
  eq(stemClash(q, new Set(), []), [], "no SKUs → nothing");
  const map = buildSkuMap([{ store_id: S1.id, family_id: "F", product_id: null, shopify_product_gid: PG(1) }, { store_id: S1.id, family_id: null, product_id: "P", shopify_product_gid: PG(2) }], [{ id: "F", sku: "ZFAM" }], [{ sku: "Z1", family_id: "F" }, { sku: "Z2", family_id: "F" }], [{ id: "P", sku: "Z9" }]);
  eq(map, { [S1.id + "|" + PG(1)]: ["ZFAM", "Z1", "Z2"], [S1.id + "|" + PG(2)]: ["Z9"] }, "sku map");
});

Deno.test("⑥ runCheck — 줄마다 확인을 적는다 · 못 읽은 묶음의 줄은 안 적는다 · 계획 · 짝 밖 사진(extra) · 이름 줄기 겹침 · only 면 그 줄의 상품만", async () => {
  const ctx: Partial<Ctx> = {
    plan: [plan(1, S1, 1, 11, "a.jpg"), plan(2, S1, 1, 12, "b.jpg"), plan(3, S1, 2, 21, "c.jpg", "1180"), plan(4, S2, 3, 31, "d.jpg"), plan(5, S1, 1, 13, "done.jpg", "cover", "done"), plan(6, S1, 4, 41, "e.jpg")],
    pairs: [pair(1, S1, 1, 11, "import", "planned", 1), pair(2, S1, 1, 12, "import", "planned", 2), pair(3, S1, 1, 14, "same", "dup"), pair(4, S1, 5, 51, "same")],
    mediaGids: [{ store_id: S1.id, shopify_file_gid: MG(15) }],
    skus: { [S1.id + "|" + PG(1)]: ["ANN01001"] },
  };
  const prods = [prod(1, [[11, "a.jpg"], [14, "ANN01001_2.jpg"], [15, "ANN01001.jpg"], [16, "IMG_7.jpg"]]), prod(2, [[21, "c.jpg"]], 2), prod(3, [[31, "d.jpg"]]), prod(5, [[51, "x.jpg"]])];
  const f = fake({ ctx, prods, readFail: (gids) => (gids.includes(PG(3)) ? "graphql HTTP 502" : null) });
  const c = await runCheck(f, { only: null }, 0, null) as any;
  eq(f.reads, [[PG(3)], [PG(1), PG(2), PG(4), PG(5)]], "aone first (code order) · one read per store batch · products of plan rows and pair rows");
  eq(rpcOf(f, "shop_photo_verify_mark"), [{ p_rows: [{ id: 1, ok: true, note: null }, { id: 2, ok: false, note: "the photo is not on the Shopify product any more" }, { id: 3, ok: false, note: "the Shopify product now has more than one variant (rule 1180 planned for one)" }, { id: 6, ok: false, note: "the Shopify product is not there any more" }] }], "verdicts written once for the batch · done row (5) and the failed batch (4) are not written");
  eq([c.products, c.products_read, c.read_errors, c.rows_checked, c.marked, c.ok, c.gone, c.variants_changed, c.product_missing, c.remaining, c.stopped], [5, 4, 1, 4, 4, 1, 1, 1, 1, 0, null], "counts");
  eq(c.error_list, [{ store: "aone", products: [PG(3)], error: "graphql HTTP 502" }], "read error listed");
  eq([c.extra_media, c.extra_list.map((x: any) => x.media_gid)], [1, [MG(16)]], "extra = on Shopify, in neither the pair plan nor shop_media");
  eq([c.stem_clash, c.stem_clash_list.map((x: any) => x.media_gid + " " + x.sku)], [1, [MG(14) + " ANN01001"]], "stem clash = unpaired (dup) photo with an IMS-style name · the paired ANN01001 (15) is not listed");
  const g = fake({ ctx, prods });
  const c2 = await runCheck(g, { only: [3] }, 0, null) as any;
  eq([g.reads, rpcOf(g, "shop_photo_verify_mark")[0].p_rows.map((r: any) => r.id), c2.products], [[[PG(2)]], [3], 1], "only → just that row's product");
});

Deno.test("⑦ runCheck · runPairs 시간 가드 · 이어 달리기 — 읽기 앞에서 끊는다 · 남은 수 · 다음 자리 · 그 자리 뒤부터 다시", async () => {
  const rows = Array.from({ length: 25 }, (_, i) => plan(i + 1, S1, 100 + i, 500 + i, "p" + i + ".jpg"));
  const prods = rows.map((r, i) => prod(100 + i, [[500 + i, "p" + i + ".jpg"]]));
  const f = fake({ ctx: { plan: rows }, prods, tick: 200_000 });                                   // 읽기 한 번에 200 초 → 두 번째 읽기 뒤 가드
  const c = await runCheck(f, { only: null }, 0, null) as any;
  eq([f.reads.length, c.products_read, c.remaining, c.stopped, c.next_after, c.ok], [2, 20, 5, "time", "asung|" + PG(119), 20], "stopped before the third read");
  const after = resumeAfter({ counts: c }, { only: null, restart: false });
  const g = fake({ ctx: { plan: rows }, prods });
  const c2 = await runCheck(g, { only: null }, 0, after) as any;
  eq([g.reads.map((x) => x.length), c2.remaining, c2.stopped, c2.ok], [[5], 0, null, 5], "the next call reads only what was left");
  eq(TIME_BUDGET_MS, 330_000, "budget");
  const prs = Array.from({ length: 15 }, (_, i) => pair(i + 1, S1, 200 + i, 700 + i));
  const h = fake({ ctx: { pairs: prs }, prods: prs.map((_, i) => prod(200 + i, [[700 + i, "x.jpg"]])), tick: 331_000 });
  const c3 = await runPairs(h, { only: null }, 0, null) as any;
  eq([h.reads.length, c3.rows_sent, c3.remaining, c3.stopped], [1, 10, 5, "time"], "pairs: same guard");
});

Deno.test("⑧ runPairs — 있으면 present · 다 읽었는데 없으면 absent(gone) · 다 못 읽었으면 적지 않는다 · 상품을 못 찾으면 적지 않고 목록 · 끝난 짝(done · gone)은 안 본다 · only", async () => {
  const ctx: Partial<Ctx> = {
    plan: [plan(1, S1, 1, 11, "a.jpg")],
    pairs: [pair(1, S1, 1, 11, "import", "planned", 1), pair(2, S1, 1, 12, "same", "planned"), pair(3, S1, 1, 13, "same", "dup"), pair(4, S1, 2, 21, "same"), pair(5, S1, 3, 31, "same"), pair(6, S1, 1, 19, "same", "done"), pair(7, S1, 9, 91, "same", "gone")],
  };
  const prods = [prod(1, [[11, "a.jpg"], [13, "c.jpg"]]), prod(2, [], 1, false)];
  const f = fake({ ctx, prods, rpc: (fn) => (fn === "shop_photo_pair_mark" ? { gone: 1, image_off: 0, seeded: 1, conflict: 0 } : {}) });
  const c = await runPairs(f, { only: null }, 0, null) as any;
  eq(f.reads, [[PG(1), PG(2), PG(3)]], "only products with open pair rows");
  eq(rpcOf(f, "shop_photo_pair_mark"), [{ p_rows: [{ id: 1, present: true }, { id: 2, present: false }, { id: 3, present: true }] }], "rows sent");
  eq([c.present, c.absent, c.unsure, c.product_missing, c.gone, c.seeded, c.missing_list], [2, 1, 1, 1, 1, 1, [{ store: "asung", product_gid: PG(3), pair_rows: 1 }]], "counts · the missing product is listed, not marked gone");
  const g = fake({ ctx: { ...ctx, pairs: [...ctx.pairs!, pair(8, S1, 5, 51, "same")] }, prods });
  await runPairs(g, { only: [1] }, 0, null);
  eq(g.reads, [[PG(1)]], "only → the products of those plan rows");
});

Deno.test("⑨ runMove — 내려받기 → 대조 → 올리기 → 주인마다 한 번 등록 · 실패 갈래 · 등록 거부 → fail · 시간 가드는 잡은 줄을 놓는다 · only · 주인 한도 · 두 번 불러도 한 장", async () => {
  const mk = (id: number, owner: string, bytes: Uint8Array, ct = "image/jpeg"): ClaimRow => ({ id, owner_id: owner, src_url: CDN("m" + id), file_md5: md5Hex(bytes), byte_size: bytes.byteLength, content_type: ct, storage_path: owner + "/shopify-" + id + (ct === "image/png" ? ".png" : ".jpg"), attempts: 1 });
  const rows = [mk(1, "A", JPG(1)), mk(2, "A", PNG(2), "image/png"), mk(3, "B", JPG(3)), mk(4, "B", JPG(4)), mk(5, "B", JPG(5)), mk(6, "C", JPG(6)), mk(7, "C", JPG(7)), mk(8, "D", JPG(8))];
  const files: Record<string, Uint8Array | number> = { [CDN("m1")]: JPG(1), [CDN("m2")]: PNG(2), [CDN("m3")]: 503, [CDN("m4")]: JPG(99), [CDN("m5")]: PNG(5), [CDN("m6")]: JPG(6), [CDN("m7")]: JPG(7), [CDN("m8")]: JPG(8) };
  rows[4] = { ...rows[4], file_md5: md5Hex(PNG(5)), byte_size: 64 };                                // 5: 바이트는 계획과 같은데 계획은 jpeg · 파일은 png
  let handed = false;
  const rpc = (fn: string, args: any) => {
    if (fn === "shop_photo_claim") { if (handed) return []; handed = true; return rows; }
    if (fn === "shop_photo_fail") return args.p_final ? "failed" : "planned";
    if (fn === "shop_photo_done") return { done: args.p_rows.filter((r: any) => r.id !== 7).length, already_done: 0, rejected: args.p_rows.filter((r: any) => r.id === 7).map((r: any) => ({ id: r.id, reason: "object_missing (x)" })) };
    return {};
  };
  const f = fake({ files, rpc, uploadFail: (p) => p.startsWith("D/") });
  const c = await runMove(f, { only: [1, 2, 3], owners: 60, retryFailed: true }, 0) as any;
  eq(rpcOf(f, "shop_photo_claim")[0], { p_owners: 5, p_stale_minutes: 30, p_retry_failed: true, p_only: [1, 2, 3] }, "claim: five owners at a time · only and retry_failed passed on");
  eq(rpcOf(f, "shop_photo_done"), [{ p_rows: [{ id: 1, byte_size: 64 }, { id: 2, byte_size: 64 }] }, { p_rows: [{ id: 6, byte_size: 64 }, { id: 7, byte_size: 64 }] }], "one done call per owner · nothing for B and D");
  eq(rpcOf(f, "shop_photo_fail").map((a) => a.p_id + ":" + a.p_final + ":" + String(a.p_error).split(" ").slice(0, 2).join(" ")), ["3:false:download failed", "4:true:md5 " + md5Hex(JPG(99)), "5:true:the file", "7:false:not registered:", "8:false:storage upload"], "failure branches · md5 and format are final · download · upload · done-rejected are retried");
  eq(f.uploads, ["A/shopify-1.jpg", "A/shopify-2.png", "C/shopify-6.jpg", "C/shopify-7.jpg", "D/shopify-8.jpg"], "nothing is uploaded before the bytes are verified");
  eq([c.owners, c.claimed, c.uploaded, c.done, c.failed, c.back_to_planned, c.remaining, c.stopped, rpcOf(f, "shop_photo_claim").length], [4, 8, 4, 3, 2, 3, 7, null, 2], "counts · the second claim comes back empty");
  eq(f.slept >= 8 * 300 && f.slept <= 8 * 500, true, "0.3 - 0.5 s between downloads");
  // 두 번 부름: claim 이 빈 배열 → 아무것도 안 한다
  const again = fake({ files, rpc: (fn) => (fn === "shop_photo_claim" ? [] : {}) });
  const c0 = await runMove(again, { only: null, owners: 60, retryFailed: false }, 0) as any;
  eq([again.uploads, rpcOf(again, "shop_photo_done"), c0.claimed], [[], [], 0], "nothing claimed → nothing written");
  // 시간 가드: 내려받기 한 번에 200 초 → 셋째 줄부터는 시도하지 않고 놓는다 · 등록은 올린 것만
  let once = false;
  const t = fake({ files, tick: 200_000, rpc: (fn, args) => (fn === "shop_photo_claim" ? (once ? [] : (once = true, [rows[0], rows[1], rows[5], rows[6]])) : fn === "shop_photo_fail" ? "planned" : fn === "shop_photo_done" ? { done: args.p_rows.length } : {}) });
  const ct = await runMove(t, { only: null, owners: 60, retryFailed: false }, 0) as any;
  eq([t.uploads, rpcOf(t, "shop_photo_done"), rpcOf(t, "shop_photo_fail").map((a) => a.p_id + ":" + a.p_final), ct.stopped, ct.not_attempted, rpcOf(t, "shop_photo_claim").length],
     [["A/shopify-1.jpg", "A/shopify-2.png"], [{ p_rows: [{ id: 1, byte_size: 64 }, { id: 2, byte_size: 64 }] }], ["6:false", "7:false"], "time", 2, 1], "time guard before each download · claimed rows are released · no further claim");
  // 주인 한도 7: 5 + 2
  const asked: number[] = [];
  const o = fake({ rpc: (fn, args) => { if (fn !== "shop_photo_claim") return {}; asked.push(args.p_owners); return asked.length > 2 ? [] : Array.from({ length: args.p_owners }, (_, i) => ({ ...mk(100 + asked.length * 10 + i, "O" + asked.length + i, JPG(1)), src_url: "nope" })); } });
  const co = await runMove(o, { only: null, owners: 7, retryFailed: false }, 0) as any;
  eq([asked, co.owners], [[5, 2], 7], "owners budget");
  // 등록이 통째로 실패하면 줄을 놓지 않는다(30 분 뒤 다시 내준다) · 다음 주인은 계속
  let n = 0;
  const d = fake({ files, rpc: (fn) => { if (fn === "shop_photo_claim") return n++ ? [] : [rows[0], rows[5]]; if (fn === "shop_photo_done") { if (rpcOf(d, "shop_photo_done").length === 1) throw new Error("rpc shop_photo_done 500"); return { done: 1 }; } return "planned"; } });
  const cd = await runMove(d, { only: null, owners: 60, retryFailed: false }, 0) as any;
  eq([cd.done_errors, cd.done, rpcOf(d, "shop_photo_fail").length], [1, 1, 0], "done error → rows stay claimed · the next owner still goes");
});
