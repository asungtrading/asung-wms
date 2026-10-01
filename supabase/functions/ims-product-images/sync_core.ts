// ============================================================
// ASUNG IMS — ims-product-images 의 순수 판단 모듈 (img-2 · 2026-10-01 · 판정 195 ~ 197)
//   Cin7 첨부 목록 + IMS 활성 상품 + product_image 줄 → 무엇을 옮기고 · 끄고 · 대표를 옮길지.
//   네트워크 · DB 없음 — index.ts 가 받아 온 것을 넣고, 결과대로 쓴다. deno test 가 이 파일만 본다.
//   ⚠️ index.ts 를 import 하지 말 것 — 최상위 Deno.serve 라 테스트가 서버를 띄운다(receiving/po_clamp_test 와 같은 분리).
// 규칙(운영 product-images EF 의 원칙을 IMS 표 모양으로 옮긴 것):
//   · all-or-nothing 은 목록에 — 수신 == Total · 429 없음 · non-200 없음 — 하나라도 어긋나면 큐 · 끄기 · 대표 어느 것도 안 쓴다(assessList)
//   · SKU 정확 일치 · 활성 상품만(판정 196) · base 폴백 없음 · Cin7 쪽 같은 SKU 둘이면 첫 것(dup_cin7_sku)
//   · JPEG · PNG · WebP 만(표 CHECK 와 같다) · 그 밖은 skips(type)
//   · 처음 보는 첨부만 큐에(cin7_attachment_id) · 이미 등록된 줄은 켜져 있든 꺼져 있든 건드리지 않는다(IMS 에서 끈 것을 되살리지 않는다 · 판정 132 태도)
//   · 사라진 첨부 = 전체 목록 회차에서만 · cin7 줄 · 켜진 것 · 활성 상품만 끈다(판정 188 · 파일은 남는다 · ⬜6)
//   · 대표 — manual 사진이 하나라도 켜져 있는 상품은 무접촉 · 그 밖은 Cin7 IsDefault 인 cin7 줄을 대표로(등록된 것만) · Cin7 대표 없음은 정상(무접촉)
//   · 크기는 내려받을 때 잰다(withinSize · 5 MB · 판정 197) — 목록에는 크기 칸이 없다(⬜3)
// ============================================================

export const MAX_BYTES = 5 * 1024 * 1024;                           // 상자 한도와 같다(img-1)
export const IMAGE_EXT: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
export const DOWNLOAD_BASE = "https://inventory.dearsystems.com/Product/Download?id=";

export type Cin7Att = { ID?: string; ContentType?: string; FileName?: string; IsDefault?: boolean };
export type Cin7Prod = { SKU?: string; Attachments?: Cin7Att[] };
export type ImsProd = { id: string; sku: string; is_active: boolean };
export type ImgRow = { id: string; product_id: string; cin7_attachment_id: string | null; is_primary: boolean; is_active: boolean; source: string };
export type QueueItem = { cin7_attachment_id: string; product_id: string; sku: string; content_type: string; file_name: string | null; is_default: boolean };
export type Skip = { cin7_attachment_id: string; product_id: string | null; sku: string; reason: "type" | "too_large" | "download_failed" | "upload_failed" | "insert_failed"; content_type: string | null; byte_size: number | null; note: string | null };
export type PrimaryMove = { product_id: string; sku: string; image_id: string };
export type Plan = {
  counts: Record<string, number>;
  to_queue: QueueItem[];
  to_off: { image_id: string; product_id: string; sku: string }[];
  primary_moves: PrimaryMove[];
  skips: Skip[];
  missing_in_ims_sample: string[];
};

// ── 문 — 비밀 열쇠 · 테스트 프로젝트 확인 · mode (동기 구간의 판정만 · 응답은 index 가 만든다) ──
export function gate(i: { secret: string; header: string; dbRole: string | null; mode: string }): { status: number; error: string } | null {
  if (!i.secret) return { status: 500, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" };
  if (i.header !== i.secret) return { status: 401, error: "unauthorized" };
  if (i.dbRole !== "test") return { status: 500, error: "inv_config.db_role is " + String(i.dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" };
  if (!["count", "scan", "move"].includes(i.mode)) return { status: 400, error: "mode must be count, scan or move" };
  return null;
}

// ── all-or-nothing 관문 — 목록이 완전할 때만 null · 아니면 사유 ──
export function assessList(a: { productsSeen: number; listTotal: number | null; aborted: string | null }): string | null {
  if (a.aborted) return a.aborted;
  if (a.listTotal == null || a.productsSeen !== a.listTotal) return "incomplete";
  return null;
}

export const extFor = (ct: string) => IMAGE_EXT[ct.toLowerCase()] ?? null;
export const withinSize = (bytes: number) => bytes > 0 && bytes <= MAX_BYTES;
export const timeLeft = (t0: number, now: number, budgetMs: number) => now - t0 < budgetMs;
export const storagePath = (productId: string, attId: string, ct: string) => productId + "/" + attId.toLowerCase() + "." + extFor(ct);

// ── 계획 — 목록이 완전하다는 전제(assessList 통과) · fullList=false(count 모드 부분 집계)면 끄기 · 대표를 내지 않는다 ──
export function plan(cin7: Cin7Prod[], ims: ImsProd[], rows: ImgRow[], fullList: boolean): Plan {
  const counts: Record<string, number> = {
    products_seen: 0, matched: 0, missing_in_ims: 0, dup_cin7_sku: 0, no_attachments: 0, attachments_seen: 0, dup_attachment: 0,
    type_skipped: 0, already_registered: 0, to_queue: 0, no_default: 0, to_off: 0, primary_moves: 0, manual_protected: 0,
  };
  const imsBySku = new Map<string, ImsProd>();
  for (const p of ims) if (p.is_active) imsBySku.set(p.sku, p);                    // 정확 일치 — 접지 않는다
  const rowsByAtt = new Map<string, ImgRow>();
  const rowsByProduct = new Map<string, ImgRow[]>();
  for (const r of rows) {
    if (r.cin7_attachment_id) rowsByAtt.set(r.cin7_attachment_id.toLowerCase(), r);
    const l = rowsByProduct.get(r.product_id) ?? []; l.push(r); rowsByProduct.set(r.product_id, l);
  }
  const seenSku = new Set<string>();
  const seenAtt = new Set<string>();
  const presentAtt = new Set<string>();                                               // 이번 목록에 있는 첨부 전부(끄기 판정)
  const out: Plan = { counts, to_queue: [], to_off: [], primary_moves: [], skips: [], missing_in_ims_sample: [] };

  for (const p of cin7) {
    counts.products_seen++;
    const sku = String(p?.SKU ?? "").trim();
    if (!sku) continue;
    if (seenSku.has(sku)) { counts.dup_cin7_sku++; continue; }
    seenSku.add(sku);
    const atts = (p?.Attachments ?? []).filter((a) => a && a.ID);
    for (const a of atts) presentAtt.add(String(a.ID).toLowerCase());
    const prod = imsBySku.get(sku);
    if (!prod) { counts.missing_in_ims++; if (out.missing_in_ims_sample.length < 8) out.missing_in_ims_sample.push(sku); continue; }
    counts.matched++;
    if (!atts.length) { counts.no_attachments++; continue; }
    let defaultAtt: string | null = null;
    for (const a of atts) {
      const id = String(a.ID).toLowerCase();
      counts.attachments_seen++;
      if (seenAtt.has(id)) { counts.dup_attachment++; continue; }                   // ⬜8 같은 첨부 id 가 두 상품에 — 첫 것만
      seenAtt.add(id);
      const ct = String(a.ContentType ?? "").toLowerCase();
      if (!extFor(ct)) {
        counts.type_skipped++;
        out.skips.push({ cin7_attachment_id: id, product_id: prod.id, sku, reason: "type", content_type: ct || null, byte_size: null, note: a.FileName ?? null });
        continue;
      }
      if (a.IsDefault === true && !defaultAtt) defaultAtt = id;
      if (rowsByAtt.has(id)) { counts.already_registered++; continue; }
      counts.to_queue++;
      out.to_queue.push({ cin7_attachment_id: id, product_id: prod.id, sku, content_type: ct, file_name: a.FileName ?? null, is_default: a.IsDefault === true });
    }
    if (!defaultAtt) counts.no_default++;
    // 대표 — 전체 목록 회차에서만 · manual 켜진 사진 있으면 무접촉 · Cin7 대표가 등록된 cin7 줄이고 켜져 있으면 그것을 대표로
    if (fullList && defaultAtt) {
      const mine = rowsByProduct.get(prod.id) ?? [];
      if (mine.some((r) => r.is_active && r.source === "manual")) { counts.manual_protected++; continue; }
      const want = rowsByAtt.get(defaultAtt);
      if (want && want.is_active && want.product_id === prod.id && !want.is_primary) {
        counts.primary_moves++;
        out.primary_moves.push({ product_id: prod.id, sku, image_id: want.id });
      }
    }
  }
  // 사라진 첨부 — 전체 목록 회차에서만 · cin7 줄 · 켜진 것 · 활성 상품(IMS 에 있는 상품)만(⬜6 · 비활성 상품의 줄은 건드리지 않는다)
  if (fullList) {
    const activeIds = new Set(ims.filter((p) => p.is_active).map((p) => p.id));
    for (const r of rows) {
      if (r.source !== "cin7" || !r.is_active || !r.cin7_attachment_id) continue;
      if (!activeIds.has(r.product_id)) continue;
      if (presentAtt.has(r.cin7_attachment_id.toLowerCase())) continue;
      counts.to_off++;
      out.to_off.push({ image_id: r.id, product_id: r.product_id, sku: ims.find((p) => p.id === r.product_id)?.sku ?? "?" });
    }
  }
  return out;
}

// 새 줄이 대표가 되는가 — Cin7 대표이거나(그 상품에 켜진 manual 이 없을 때) · 켜진 사진이 하나도 없을 때(img-1 자동 대표 규칙과 같다)
export function newRowIsPrimary(item: QueueItem, activeRowsOfProduct: ImgRow[]): boolean {
  const active = activeRowsOfProduct.filter((r) => r.is_active);
  if (!active.length) return true;
  if (active.some((r) => r.source === "manual")) return false;
  return item.is_default && !active.some((r) => r.is_primary && r.source === "cin7" && r.cin7_attachment_id === item.cin7_attachment_id);
}
