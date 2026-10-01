// deno test supabase/functions/ims-product-images/sync_core_test.ts — Cin7 · DB 무접촉 (img-2 ① ~ ⑩)
import { assessList, gate, newRowIsPrimary, plan, storagePath, timeLeft, withinSize, MAX_BYTES, type ImgRow, type ImsProd } from "./sync_core.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const A1 = "aaaaaaaa-0000-0000-0000-000000000001", A2 = "aaaaaaaa-0000-0000-0000-000000000002", A3 = "aaaaaaaa-0000-0000-0000-000000000003", A4 = "aaaaaaaa-0000-0000-0000-000000000004";
const P1 = "11111111-0000-0000-0000-000000000001", P2 = "11111111-0000-0000-0000-000000000002", P3 = "11111111-0000-0000-0000-000000000003";
const ims: ImsProd[] = [{ id: P1, sku: "CON19912", is_active: true }, { id: P2, sku: "ANU73725", is_active: true }, { id: P3, sku: "OLD00001", is_active: false }];
const att = (ID: string, ContentType = "image/jpeg", IsDefault = false, FileName = "x.jpg") => ({ ID, ContentType, IsDefault, FileName });
const row = (id: string, product_id: string, cin7: string | null, is_primary: boolean, is_active = true, source = "cin7"): ImgRow => ({ id, product_id, cin7_attachment_id: cin7, is_primary, is_active, source });

Deno.test("① 목록 한 쪽 모자람 → incomplete · 429 → rate_limited · 완전 → null", () => {
  eq(assessList({ productsSeen: 14717, listTotal: 14718, aborted: null }), "incomplete", "one short");
  eq(assessList({ productsSeen: 100, listTotal: 14718, aborted: "rate_limited" }), "rate_limited", "429");
  eq(assessList({ productsSeen: 14718, listTotal: 14718, aborted: null }), null, "complete");
  eq(assessList({ productsSeen: 0, listTotal: null, aborted: null }), "incomplete", "no total");
});

Deno.test("② 매칭 — 활성만 · 정확 일치 · 대소문자 안 접음 · Cin7 중복 SKU 는 첫 것", () => {
  const p = plan([{ SKU: "CON19912", Attachments: [att(A1)] }, { SKU: "con19912", Attachments: [att(A2)] }, { SKU: "OLD00001", Attachments: [att(A3)] }, { SKU: "CON19912", Attachments: [att(A4)] }], ims, [], true);
  eq(p.counts.matched, 1, "matched"); eq(p.counts.missing_in_ims, 2, "con19912 (case) and inactive OLD00001 are not matched");
  eq(p.counts.dup_cin7_sku, 1, "second CON19912 dropped"); eq(p.to_queue.map((q) => q.cin7_attachment_id), [A1], "only A1 queued");
  eq(p.missing_in_ims_sample, ["con19912", "OLD00001"], "sample");
});

Deno.test("③ 형식 — PDF · GIF 는 skips(type) · 큐에 안 간다", () => {
  const p = plan([{ SKU: "CON19912", Attachments: [att(A1, "application/pdf", true, "spec.pdf"), att(A2, "image/gif"), att(A3, "image/webp")] }], ims, [], true);
  eq(p.skips.map((s) => [s.cin7_attachment_id, s.reason, s.content_type]), [[A1, "type", "application/pdf"], [A2, "type", "image/gif"]], "skips");
  eq(p.to_queue.map((q) => q.cin7_attachment_id), [A3], "webp queued"); eq(p.counts.type_skipped, 2, "count");
  eq(p.counts.no_default, 1, "the PDF default does not count as a default image");
});

Deno.test("④ 크기 — 5 MB 초과는 못 옮긴다 · 0 바이트도", () => {
  eq(withinSize(MAX_BYTES), true, "exactly 5 MB ok"); eq(withinSize(MAX_BYTES + 1), false, "over"); eq(withinSize(0), false, "empty");
});

Deno.test("⑤ 이미 등록된 첨부(켜짐 · 꺼짐 모두)는 건너뛴다 · 두 번째 계획은 비어 있다(멱등)", () => {
  const rows = [row("r1", P1, A1, true), row("r2", P1, A2, false, false)];
  const p = plan([{ SKU: "CON19912", Attachments: [att(A1, "image/jpeg", true), att(A2), att(A3)] }], ims, rows, true);
  eq(p.counts.already_registered, 2, "A1 and the turned-off A2"); eq(p.to_queue.map((q) => q.cin7_attachment_id), [A3], "A3 new");
  const p2 = plan([{ SKU: "CON19912", Attachments: [att(A1, "image/jpeg", true), att(A2), att(A3)] }], ims, [...rows, row("r3", P1, A3, false)], true);
  eq(p2.to_queue, [], "nothing left"); eq(p2.to_off, [], "nothing to turn off");
});

Deno.test("⑥ 사라진 첨부 → 끄기 — 전체 목록 회차에서만 · cin7 줄 · 켜진 것 · 활성 상품만", () => {
  const rows = [row("r1", P1, A1, true), row("r2", P1, A2, false), row("r3", P3, A3, true), row("m1", P2, null, true, true, "manual"), row("r4", P2, A4, false, false)];
  const full = plan([{ SKU: "CON19912", Attachments: [att(A1, "image/jpeg", true)] }, { SKU: "ANU73725", Attachments: [] }], ims, rows, true);
  eq(full.to_off.map((o) => o.image_id), ["r2"], "A2 gone → r2 off · r3 (inactive product) untouched · manual untouched · r4 already off");
  const partial = plan([{ SKU: "CON19912", Attachments: [att(A1, "image/jpeg", true)] }], ims, rows, false);
  eq(partial.to_off, [], "count mode (partial) never turns off"); eq(partial.primary_moves, [], "nor moves primaries");
});

Deno.test("⑦ 대표 — manual 켜진 상품 무접촉 · Cin7 대표가 등록된 cin7 줄이면 그리로 · 새 줄은 켜진 사진이 없을 때 대표", () => {
  const rows = [row("r1", P1, A1, true), row("r2", P1, A2, false), row("m1", P2, null, true, true, "manual"), row("r4", P2, A4, false)];
  const p = plan([{ SKU: "CON19912", Attachments: [att(A1), att(A2, "image/jpeg", true)] }, { SKU: "ANU73725", Attachments: [att(A4, "image/jpeg", true)] }], ims, rows, true);
  eq(p.primary_moves, [{ product_id: P1, sku: "CON19912", image_id: "r2" }], "Cin7 default moved to A2 for CON19912");
  eq(p.counts.manual_protected, 1, "ANU73725 has a manual image → untouched");
  const item = { cin7_attachment_id: A3, product_id: P1, sku: "CON19912", content_type: "image/jpeg", file_name: null, is_default: false };
  eq(newRowIsPrimary(item, []), true, "first active image becomes primary");
  eq(newRowIsPrimary(item, [row("r1", P1, A1, true)]), false, "not default · another primary exists");
  eq(newRowIsPrimary({ ...item, is_default: true }, [row("r1", P1, A1, true)]), true, "Cin7 default replaces a cin7 primary");
  eq(newRowIsPrimary({ ...item, is_default: true }, [row("m1", P1, null, true, true, "manual")]), false, "manual primary is never replaced");
});

Deno.test("⑧ 시간 가드 — 예산 안이면 계속 · 넘으면 멈춤(쓰기 앞에서 index 가 본다)", () => {
  eq(timeLeft(1000, 1000 + 329_999, 330_000), true, "inside"); eq(timeLeft(1000, 1000 + 330_000, 330_000), false, "at budget");
});

Deno.test("⑨ 경로 — <상품 id>/<첨부 id 소문자>.<확장자> · 같은 첨부 id 가 두 상품에 오면 첫 것만", () => {
  eq(storagePath(P1, "AAAAAAAA-0000-0000-0000-000000000001", "image/PNG"), P1 + "/" + A1 + ".png", "path");
  const p = plan([{ SKU: "CON19912", Attachments: [att(A1)] }, { SKU: "ANU73725", Attachments: [att(A1)] }], ims, [], true);
  eq(p.to_queue.map((q) => q.product_id), [P1], "first product keeps it"); eq(p.counts.dup_attachment, 1, "counted");
});

Deno.test("⑩ 문 — 열쇠 미설정 500 · 틀린 열쇠 401 · db_role ≠ test 500 · 모르는 mode 400 · 통과 null", () => {
  eq(gate({ secret: "", header: "x", dbRole: "test", mode: "count" })?.status, 500, "no secret");
  eq(gate({ secret: "s", header: "x", dbRole: "test", mode: "count" })?.status, 401, "wrong key");
  eq(gate({ secret: "s", header: "s", dbRole: "prod", mode: "count" })?.status, 500, "not test");
  eq(gate({ secret: "s", header: "s", dbRole: null, mode: "count" })?.status, 500, "db_role missing");
  eq(gate({ secret: "s", header: "s", dbRole: "test", mode: "fly" })?.status, 400, "mode");
  eq(gate({ secret: "s", header: "s", dbRole: "test", mode: "move" }), null, "ok");
});
