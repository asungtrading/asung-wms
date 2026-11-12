// ============================================================
// ASUNG IMS — shop-photo-import 의 판단 · 흐름(shop-photo-imp-2b-2 · 2026-11-12 · 판정 1182 · 1183 · 1185 · 1198 · deferred 387 가져오기 길 ②-b)
//   순수(deno test) — 바깥(Shopify · CDN · 저장소 · DB)은 전부 Io 로 받는다 · index.ts 는 문 · 실제 Io · 기록만
//   check  상품마다 media 를 한 번 읽어 계획 줄을 확인(gid 가 아직 있나 · url 이 같나 · 1180 줄은 변형이 하나인가) → shop_photo_verify_mark
//          + 계획에도 짝에도 없는 Shopify 사진(extra — 사진을 보내기 시작하면 그 상품에서 빠진다) + 이름 줄기 겹침(stem_clash — 짝 없는 Shopify 사진의 파일 이름이 IMS 줄기 꼴 · 목록만 · 판정은 Caleb)
//   pairs  짝 줄(planned · dup)의 gid 가 아직 있나 → shop_photo_pair_mark(없으면 gone · same 은 shop_media 에 심는다)
//   move   claim(주인 단위) → CDN 내려받기 → 크기 · md5 · 형식 대조 → 저장소 올리기 → shop_photo_done(사진 행 + 짝 + 웹 대표 1198 한 몸) · 실패는 shop_photo_fail
//   모르면 안 쓴다: 못 읽은 상품 · media 를 다 못 읽은 상품의 「없음」 은 적지 않는다(세기만) · Shopify 에는 읽기만 · 시간 가드는 쓰기 앞
// ============================================================
import { createHash } from "node:crypto";
import { skuStem, urlStem } from "../_shared/shopify-product.ts";

export const TIME_BUDGET_MS = 330_000;          // t0 기준 · 쓰기 앞에서만 끊는다(ims-product-images 와 같다)
export const PRODUCT_CHUNK = 10;                // nodes(ids:) 한 번의 상품 수
export const MEDIA_FIRST = 100;                 // 상품 하나의 media 읽기 한도 — 넘으면 「다 못 읽음」
export const OWNERS_MAX = 60;                   // move 한 회차의 주인 한도(첫 회차 실측 뒤 조정)
export const CLAIM_OWNERS = 5;                  // claim 한 번의 주인 수 — 시간에 걸려도 묶인 줄이 적다
export const STALE_MINUTES = 30;
export const LIST_CAP = 300;                    // 목록(extra · stem_clash · 못 읽은 상품)은 300 까지 · 수는 전부
export const MODES = ["selftest", "check", "pairs", "move"] as const;
export type Mode = typeof MODES[number];
export const PRODUCT_NODES_QUERY = `query ImsPhotoImport($ids: [ID!]!) { nodes(ids: $ids) { ... on Product { id variants(first: 2) { nodes { id } } media(first: ${MEDIA_FIRST}) { pageInfo { hasNextPage } nodes { id ... on MediaImage { image { url } } } } } } }`;

export type Store = { id: string; code: string };
export type PlanRow = { id: number; rule: string; status: string; src_store_id: string; src_product_gid: string; src_media_gid: string; src_url: string };
export type PairRow = { id: number; store_id: string; product_gid: string; media_gid: string; pair_kind: string; status: string; plan_id: number | null };
export type Prod = { gid: string; variants: number; complete: boolean; media: Array<{ gid: string; url: string | null }> };
export type ClaimRow = { id: number; owner_id: string; src_url: string; file_md5: string; byte_size: number; content_type: string; storage_path: string; attempts: number };
export type Ctx = { stores: Store[]; plan: PlanRow[]; pairs: PairRow[]; mediaGids: Array<{ store_id: string; shopify_file_gid: string }>; skus: Record<string, string[]> };
export type Io = {
  now(): number;
  sleep(ms: number): Promise<void>;
  context(only: number[] | null, withSkus: boolean): Promise<Ctx>;
  readProducts(store: Store, gids: string[]): Promise<{ ok: true; prods: Prod[] } | { ok: false; error: string }>;
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
  download(url: string): Promise<{ bytes: Uint8Array | null; status: number }>;
  upload(path: string, contentType: string, bytes: Uint8Array): Promise<{ ok: boolean; error?: string }>;
  remaining(): Promise<number>;
};

export const timeLeft = (t0: number, now: number, budget = TIME_BUDGET_MS) => now - t0 < budget;
export const md5Hex = (bytes: Uint8Array): string => createHash("md5").update(bytes).digest("hex");
export function chunk<T>(a: T[], n: number): T[][] { const out: T[][] = []; for (let i = 0; i < a.length; i += n) out.push(a.slice(i, i + n)); return out; }
const capPush = <T>(list: T[], x: T) => { if (list.length < LIST_CAP) list.push(x); };

// 앞 바이트로 형식(계획은 jpeg · png 뿐 — gif 는 1184 로 건너뛴 줄)
export function sniff(b: Uint8Array): string | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return "image/png";
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return "image/webp";
  if (b.length >= 4 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) return "image/gif";
  return null;
}
// 내려받은 바이트 = 계획의 그 파일인가 — 크기 · md5 · 형식 · 다르면 다시 해도 같으니 final(나갈 길 = check 를 다시 → shop_photo_claim(p_retry_failed))
export function verifyDownload(row: Pick<ClaimRow, "byte_size" | "file_md5" | "content_type">, bytes: Uint8Array): { ok: true } | { ok: false; final: boolean; error: string } {
  if (bytes.byteLength !== Number(row.byte_size)) return { ok: false, final: true, error: "byte size " + bytes.byteLength + " differs from the plan (" + row.byte_size + ") - the Shopify image is not the one that was planned" };
  const m = md5Hex(bytes);
  if (m !== row.file_md5) return { ok: false, final: true, error: "md5 " + m + " differs from the plan (" + row.file_md5 + ") - the Shopify image is not the one that was planned" };
  const ct = sniff(bytes);
  if (ct !== row.content_type) return { ok: false, final: true, error: "the file is " + (ct ?? "not an image IMS knows") + " but the plan says " + row.content_type };
  return { ok: true };
}

export function selftest() {
  const a = md5Hex(new TextEncoder().encode("a"));
  const jpg = sniff(new Uint8Array([0xff, 0xd8, 0xff, 0xe0])), png = sniff(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return { ok: a === "0cc175b9c0f1b6a831c399e269772661" && jpg === "image/jpeg" && png === "image/png", md5_of_a: a, sniff_jpeg: jpg, sniff_png: png };
}

// 호출 몸 — 모르는 값은 거부(사람 말)
export type Opts = { mode: Mode; only: number[] | null; owners: number; retryFailed: boolean; restart: boolean };
export function pickBody(body: unknown): Opts | { error: string } {
  const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const mode = String(b.mode ?? "");
  if (!(MODES as readonly string[]).includes(mode)) return { error: "mode must be one of: " + MODES.join(", ") };
  let only: number[] | null = null;
  if (b.only !== undefined && b.only !== null) {
    if (!Array.isArray(b.only) || !b.only.length || b.only.length > 500 || b.only.some((x) => !Number.isInteger(x) || (x as number) <= 0)) return { error: "only must be a list of 1 to 500 plan row ids (whole numbers)" };
    only = [...new Set(b.only as number[])];
  }
  const owners = b.owners === undefined ? OWNERS_MAX : Number(b.owners);
  if (!Number.isInteger(owners) || owners < 1 || owners > OWNERS_MAX) return { error: "owners must be a whole number from 1 to " + OWNERS_MAX };
  return { mode: mode as Mode, only, owners, retryFailed: b.retry_failed === true, restart: b.restart === true };
}
// 이어 달리기: 직전 같은 모드 회차가 시간에 걸려 남겼으면 그 자리 뒤부터 — only · restart 면 처음부터
export function resumeAfter(last: { counts?: Record<string, unknown> | null } | null | undefined, opts: Pick<Opts, "only" | "restart">): string | null {
  if (opts.only || opts.restart || !last?.counts) return null;
  const c = last.counts;
  return Number(c.remaining ?? 0) > 0 && typeof c.next_after === "string" && c.next_after ? c.next_after : null;
}

// Shopify 응답 → 상품(없는 id 는 null 로 온다 — 목록에 안 넣는다)
export function parseProducts(data: unknown): Prod[] {
  const nodes = ((data as { nodes?: unknown[] } | null)?.nodes ?? []) as Array<{ id?: string; variants?: { nodes?: unknown[] }; media?: { pageInfo?: { hasNextPage?: boolean }; nodes?: Array<{ id: string; image?: { url?: string | null } | null }> } } | null>;
  return nodes.filter((n) => !!n?.id).map((n) => ({
    gid: n!.id!, variants: n!.variants?.nodes?.length ?? 0, complete: n!.media?.pageInfo?.hasNextPage !== true,
    media: (n!.media?.nodes ?? []).map((m) => ({ gid: m.id, url: m.image?.url ?? null })),
  }));
}
// 읽을 상품 — 스토어 코드 · gid 순(이어 달리기의 자리) · 꺼진 스토어의 것은 뺀다
export type Target = { key: string; store: Store; gid: string };
export function targets(pairs: Array<{ store_id: string; gid: string }>, stores: Store[], after: string | null): Target[] {
  const byId = new Map(stores.map((s) => [s.id, s])), seen = new Map<string, Target>();
  for (const p of pairs) { const s = byId.get(p.store_id); if (!s) continue; const key = s.code + "|" + p.gid; if (!seen.has(key)) seen.set(key, { key, store: s, gid: p.gid }); }
  return [...seen.values()].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)).filter((t) => !after || t.key > after);
}
export function batches(ts: Target[]): Target[][] {
  const out: Target[][] = [];
  for (const t of ts) { const cur = out[out.length - 1]; if (cur && cur.length < PRODUCT_CHUNK && cur[0].store.id === t.store.id) cur.push(t); else out.push([t]); }
  return out;
}
// 계획 줄 하나의 확인 — ok 가 아니면 claim 이 내주지 않는다(나갈 길 = check 를 다시)
export function judgePlan(row: PlanRow, prod: Prod | undefined): { id: number; ok: boolean; note: string | null; why: "ok" | "product_missing" | "gone" | "unsure" | "url_changed" | "variants_changed" } {
  if (!prod) return { id: row.id, ok: false, note: "the Shopify product is not there any more", why: "product_missing" };
  const m = prod.media.find((x) => x.gid === row.src_media_gid);
  if (!m) return prod.complete ? { id: row.id, ok: false, note: "the photo is not on the Shopify product any more", why: "gone" }
                               : { id: row.id, ok: false, note: "the product has more than " + MEDIA_FIRST + " photos - could not read them all", why: "unsure" };
  if (m.url !== row.src_url) return { id: row.id, ok: false, note: "the photo's address changed on Shopify (" + String(m.url).slice(0, 200) + ")", why: "url_changed" };
  if (row.rule === "1180" && prod.variants !== 1) return { id: row.id, ok: false, note: "the Shopify product now has more than one variant (rule 1180 planned for one)", why: "variants_changed" };
  return { id: row.id, ok: true, note: null, why: "ok" };
}
// 이름 줄기 겹침: 짝이 없을 Shopify 사진의 파일 이름이 그 상품의 IMS 줄기 꼴(<SKU> · <SKU>_<n> · 뒤 _<uuid>) — 사진을 보내기 시작하면 이름으로 짝이 지어질 수 있다
const TAIL = /^(?:_\d+)?(?:_(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32}))?$/;
export function stemClash(prod: Prod, safeGids: Set<string>, skus: string[]): Array<{ media_gid: string; url: string | null; sku: string }> {
  const stems = skus.map((s) => ({ sku: s, e: (skuStem(s) ?? "").toLowerCase() })).filter((x) => x.e).sort((a, b) => b.e.length - a.e.length);
  const out: Array<{ media_gid: string; url: string | null; sku: string }> = [];
  for (const m of prod.media) {
    if (safeGids.has(m.gid)) continue;
    const st = urlStem(m.url); if (!st) continue;
    const hit = stems.find((x) => st.startsWith(x.e) && TAIL.test(st.slice(x.e.length)));
    if (hit) out.push({ media_gid: m.gid, url: m.url, sku: hit.sku });
  }
  return out;
}
// 상품 gid → IMS SKU 들(패밀리 SKU + 구성원 낱개 · 또는 그 제품) — 열쇠 = store_id|gid
export function buildSkuMap(shopProducts: Array<{ store_id: string; family_id: string | null; product_id: string | null; shopify_product_gid: string }>, families: Array<{ id: string; sku: string }>, members: Array<{ sku: string; family_id: string }>, products: Array<{ id: string; sku: string }>): Record<string, string[]> {
  const fam = new Map(families.map((f) => [f.id, f.sku])), prod = new Map(products.map((p) => [p.id, p.sku])), mem = new Map<string, string[]>();
  for (const m of members) mem.set(m.family_id, [...(mem.get(m.family_id) ?? []), m.sku]);
  const out: Record<string, string[]> = {};
  for (const sp of shopProducts) {
    const list = sp.family_id ? [fam.get(sp.family_id), ...(mem.get(sp.family_id) ?? [])] : [sp.product_id ? prod.get(sp.product_id) : undefined];
    out[sp.store_id + "|" + sp.shopify_product_gid] = list.filter((x): x is string => !!x);
  }
  return out;
}

// ── check ──
export async function runCheck(io: Io, opts: Pick<Opts, "only">, t0: number, after: string | null): Promise<Record<string, unknown>> {
  const ctx = await io.context(opts.only, true);
  const plan = ctx.plan.filter((r) => r.status === "planned" || r.status === "failed");
  const ts = targets([...plan.map((r) => ({ store_id: r.src_store_id, gid: r.src_product_gid })), ...(opts.only ? [] : ctx.pairs.map((p) => ({ store_id: p.store_id, gid: p.product_gid })))], ctx.stores, after);
  const pairGids = new Set([...ctx.pairs.map((p) => p.store_id + "|" + p.media_gid), ...ctx.plan.map((r) => r.src_store_id + "|" + r.src_media_gid)]);   // 짝 계획 · 계획 줄이 아는 사진
  const safe = new Set([...ctx.pairs.filter((p) => p.status === "planned" || p.status === "done").map((p) => p.store_id + "|" + p.media_gid), ...ctx.mediaGids.map((m) => m.store_id + "|" + m.shopify_file_gid)]);
  const c = { products: ts.length, products_read: 0, read_errors: 0, rows_checked: 0, marked: 0, ok: 0, gone: 0, url_changed: 0, variants_changed: 0, product_missing: 0, unsure: 0, extra_media: 0, stem_clash: 0, remaining: ts.length, next_after: after as string | null, stopped: null as string | null };
  const extra_list: unknown[] = [], stem_clash_list: unknown[] = [], error_list: unknown[] = [];
  for (const b of batches(ts)) {
    if (!timeLeft(t0, io.now())) { c.stopped = "time"; break; }                                   // 쓰기 앞
    const store = b[0].store, r = await io.readProducts(store, b.map((t) => t.gid));
    c.remaining -= b.length; c.next_after = b[b.length - 1].key;
    if (!r.ok) { c.read_errors += b.length; capPush(error_list, { store: store.code, products: b.map((t) => t.gid), error: r.error.slice(0, 300) }); continue; }   // 못 읽은 상품의 줄은 적지 않는다(확인 안 됨으로 남는다)
    const byGid = new Map(r.prods.map((p) => [p.gid, p]));
    c.products_read += b.length;
    const verdicts = plan.filter((row) => row.src_store_id === store.id && b.some((t) => t.gid === row.src_product_gid)).map((row) => judgePlan(row, byGid.get(row.src_product_gid)));
    for (const v of verdicts) { c.rows_checked++; if (v.why === "ok") c.ok++; else c[v.why]++; }
    if (verdicts.length) c.marked += Number(await io.rpc("shop_photo_verify_mark", { p_rows: verdicts.map((v) => ({ id: v.id, ok: v.ok, note: v.note })) }) ?? 0);
    for (const p of r.prods) {
      for (const m of p.media) if (!pairGids.has(store.id + "|" + m.gid) && !safe.has(store.id + "|" + m.gid)) { c.extra_media++; capPush(extra_list, { store: store.code, product_gid: p.gid, media_gid: m.gid, url: m.url, read_all: p.complete }); }
      const safeHere = new Set(p.media.filter((m) => safe.has(store.id + "|" + m.gid)).map((m) => m.gid));
      for (const x of stemClash(p, safeHere, ctx.skus[store.id + "|" + p.gid] ?? [])) { c.stem_clash++; capPush(stem_clash_list, { store: store.code, product_gid: p.gid, ...x }); }
    }
  }
  return { ...c, extra_list, stem_clash_list, error_list };
}

// ── pairs ──
export async function runPairs(io: Io, opts: Pick<Opts, "only">, t0: number, after: string | null): Promise<Record<string, unknown>> {
  const ctx = await io.context(opts.only, false);
  const onlyGids = opts.only ? new Set(ctx.plan.map((r) => r.src_store_id + "|" + r.src_product_gid)) : null;
  const rows = ctx.pairs.filter((p) => (p.status === "planned" || p.status === "dup") && (!onlyGids || onlyGids.has(p.store_id + "|" + p.product_gid)));
  const ts = targets(rows.map((p) => ({ store_id: p.store_id, gid: p.product_gid })), ctx.stores, after);
  const c = { products: ts.length, products_read: 0, read_errors: 0, rows_sent: 0, present: 0, absent: 0, unsure: 0, product_missing: 0, gone: 0, image_off: 0, seeded: 0, conflict: 0, remaining: ts.length, next_after: after as string | null, stopped: null as string | null };
  const missing_list: unknown[] = [], error_list: unknown[] = [];
  for (const b of batches(ts)) {
    if (!timeLeft(t0, io.now())) { c.stopped = "time"; break; }
    const store = b[0].store, r = await io.readProducts(store, b.map((t) => t.gid));
    c.remaining -= b.length; c.next_after = b[b.length - 1].key;
    if (!r.ok) { c.read_errors += b.length; capPush(error_list, { store: store.code, products: b.map((t) => t.gid), error: r.error.slice(0, 300) }); continue; }
    const byGid = new Map(r.prods.map((p) => [p.gid, p]));
    c.products_read += b.length;
    const send: Array<{ id: number; present: boolean }> = [];
    for (const t of b) {
      const p = byGid.get(t.gid), mine = rows.filter((x) => x.store_id === store.id && x.product_gid === t.gid);
      if (!p) { c.product_missing += mine.length; capPush(missing_list, { store: store.code, product_gid: t.gid, pair_rows: mine.length }); continue; }   // 상품을 못 찾으면 「없음」 으로 적지 않는다(gone 은 되돌릴 길이 없다) — 목록으로
      const on = new Set(p.media.map((m) => m.gid));
      for (const x of mine) { if (on.has(x.media_gid)) { c.present++; send.push({ id: x.id, present: true }); } else if (p.complete) { c.absent++; send.push({ id: x.id, present: false }); } else c.unsure++; }
    }
    if (send.length) {
      const res = (await io.rpc("shop_photo_pair_mark", { p_rows: send }) ?? {}) as Record<string, number>;
      c.rows_sent += send.length; c.gone += Number(res.gone ?? 0); c.image_off += Number(res.image_off ?? 0); c.seeded += Number(res.seeded ?? 0); c.conflict += Number(res.conflict ?? 0);
    }
  }
  return { ...c, missing_list, error_list };
}

// ── move ──
export async function runMove(io: Io, opts: Pick<Opts, "only" | "owners" | "retryFailed">, t0: number): Promise<Record<string, unknown>> {
  const c = { owners: 0, claimed: 0, uploaded: 0, done: 0, already_done: 0, back_to_planned: 0, failed: 0, not_attempted: 0, done_errors: 0, remaining: 0, stopped: null as string | null };
  const failed_list: unknown[] = [];
  const fail = async (id: number, error: string, final: boolean) => {
    const st = String(await io.rpc("shop_photo_fail", { p_id: id, p_error: error, p_final: final }) ?? "");
    if (st === "failed") c.failed++; else c.back_to_planned++;
    capPush(failed_list, { id, error: error.slice(0, 200), status: st });
  };
  let left = opts.owners;
  while (left > 0 && !c.stopped) {
    if (!timeLeft(t0, io.now())) { c.stopped = "time"; break; }
    const rows = (await io.rpc("shop_photo_claim", { p_owners: Math.min(CLAIM_OWNERS, left), p_stale_minutes: STALE_MINUTES, p_retry_failed: opts.retryFailed, p_only: opts.only }) ?? []) as ClaimRow[];
    if (!rows.length) break;
    c.claimed += rows.length;
    const owners = [...new Set(rows.map((r) => r.owner_id))];
    left -= owners.length; c.owners += owners.length;
    for (const owner of owners) {
      const ok: Array<{ id: number; byte_size: number }> = [];
      for (const row of rows.filter((r) => r.owner_id === owner)) {
        if (c.stopped || !timeLeft(t0, io.now())) { c.stopped = "time"; c.not_attempted++; await fail(row.id, "time budget reached - not attempted in this run", false); continue; }   // 쓰기 앞 · 잡은 줄은 놓는다
        try {
          const d = await io.download(row.src_url);
          const v = d.bytes ? verifyDownload(row, d.bytes) : null;
          if (!d.bytes) await fail(row.id, "download failed (http " + d.status + ")", false);
          else if (v && !v.ok) await fail(row.id, v.error, v.final);                               // 대조가 올리기 앞 — 틀린 파일은 저장소에 가지 않는다
          else {
            const up = await io.upload(row.storage_path, row.content_type, d.bytes);
            if (!up.ok) await fail(row.id, "storage upload failed: " + String(up.error ?? "").slice(0, 200), false);
            else { c.uploaded++; ok.push({ id: row.id, byte_size: d.bytes.byteLength }); }
          }
        } catch (e) { await fail(row.id, "error: " + String((e as Error)?.message ?? e).slice(0, 200), false); }
        await io.sleep(300 + (row.id * 37) % 201);                                                // CDN 간격 0.3 ~ 0.5 초 — 실패한 내려받기 뒤에도
      }
      if (!ok.length) continue;
      try {                                                                                       // 주인 하나의 사진을 한 번에 — 사진 행 · 짝 · 웹 대표가 한 트랜잭션 · 큐 한 줄
        const res = (await io.rpc("shop_photo_done", { p_rows: ok }) ?? {}) as { done?: number; already_done?: number; rejected?: Array<{ id: number; reason: string }> };
        c.done += Number(res.done ?? 0); c.already_done += Number(res.already_done ?? 0);
        for (const rej of res.rejected ?? []) await fail(rej.id, "not registered: " + rej.reason, false);
      } catch (e) { c.done_errors++; capPush(failed_list, { owner, error: "shop_photo_done failed - the rows stay claimed and are handed out again after " + STALE_MINUTES + " minutes: " + String((e as Error)?.message ?? e).slice(0, 200) }); }
    }
  }
  c.remaining = await io.remaining();
  return { ...c, failed_list };
}
