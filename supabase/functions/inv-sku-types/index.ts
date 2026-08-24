// ============================================================
// inv-sku-types — 비재고 SKU 캐시 갱신 (2026-08-24 · pg_cron 일 1회)
// ------------------------------------------------------------
// 배경 [실사고 FINAL-SALE]: ⑥ 첫 대조의 unknown 1건 — Type=Non-inventory 품목의 판매를
//   수집이 재고 사건으로 잡아 -34 를 쌓았다. IsService 와 Type=Non-inventory 는 다른 축
//   (cin7-api 스킬 15번). 처방 = 비-Stock SKU 목록을 캐시하고 inv-collect 의 makeSink 가
//   게이트로 쓴다(fail-open — 캐시가 비어도 수집은 통과 + 경고. 대조가 안전망).
//
// 왜 별도 EF 인가 (2026-08-24 사용자 결정): inv-collect 안에 두면 6잡이 각자 갱신을 시도하고
//   (동시 실행 시 중복), 소스별 회차가 서로의 캐시 상태에 의존한다. 별도 EF 는 **실패가
//   격리된다** — 캐시 갱신이 죽어도 수집은 폴백으로 계속 돈다.
//
// 무엇을 하나: /product 전량 페이징 → Type !== 'Stock' 인 SKU 만 추려 inv_sku_types 를
//   통째 교체(delete-all + insert — [실측 2026-08-24] 5행: Non-inventory 2 + Service 3).
//   · Limit=1000 을 시도하고 첫 페이지 실제 반환 수로 자가 보정(500 은 Productmaster.js 가
//     매일 실사용해 확정 동작 — 1000 은 미실측. 1000 이면 ~15콜, 500 이면 ~30콜).
//   · all-or-nothing: 수신 < Total 이면 캐시 무접촉(부분 목록으로 교체하면 빠진 SKU 의
//     게이트가 조용히 풀린다 — inv-snapshot 과 같은 원칙).
//   · ⚠️ 기존 캐시와의 diff(added/removed/type_changed)를 **비교·보고만 한다 — 거르지 않는다**
//     (사용자 결정 Q-iii: Cin7 이 상품 마스터를 바꾸면 그것이 신호이지 우리가 판단할 일이
//     아니다). 불일치는 warnings + 카운트로 응답에 노출.
//
// 인증: x-wms-cron-key == WMS_CRON_SECRET (inv-snapshot 과 동일 — fail-closed).
// dry: ?dry=1 — 수집·diff 보고까지 하고 캐시는 무접촉.
// cron: 매일 03:26 UTC (supabase/ops/cron.sql 잡 14 — 분 26 은 빈 분: 전수 계산 확인.
//   30콜 × sleep 400ms ≈ 22초 — 그 분 안에서 끝난다).
// ============================================================

import { cin7Get, sleep } from "../_shared/cin7.ts";

const PAGE_SLEEP_MS = 400;       // inv-snapshot 과 동일 근거 (23~30콜은 60/60 한도에 여유)
const MAX_PAGES = 40;            // 폭주 방지 하드캡 (Limit 500 기준 Total 20,000 까지)
const TIME_BUDGET_MS = 100_000;  // 150초 idle timeout 앞에서 먼저 끊는다 (쓰기 없이)

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    // ── 인증 (fail-closed — inv-snapshot 과 동일) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) return json({ ok: false, error: "unauthorized" }, 401);

    const url = new URL(req.url);
    const dry = url.searchParams.get("dry") === "1";
    const warnings: string[] = [];

    // ── 1) /product 전량 — Type 분포 수집 ──
    let limit = 1000;   // 미실측 상한 — 첫 페이지 실제 반환 수로 보정 (500 은 실사용 확정)
    let page = 1, total: number | null = null, received = 0, calls = 0;
    let arrayKey: string | null = null;   // 응답 배열 키 — 추측하지 않고 첫 페이지에서 찾는다(아래)
    const typeCount: Record<string, number> = {};
    // 차단 대상 = Type !== 'Stock' ('Stock' 표기는 2026-08-24 프로브 실측 어휘).
    // ⚠️ 미지 타입이 나타나면 Stock 이 아니므로 차단 목록에 실린다 — 그 타입이 실은 재고를
    //   움직이는 것이면 원장이 행을 안 만들어 대조가 잡는다(어느 방향이든 대조가 최종 안전망).
    //   type_counts 로 어휘 전체가 매 회차 보이므로 새 타입 등장은 바로 드러난다.
    const nonStock: { sku: string; product_type: string; is_service: boolean }[] = [];
    while (true) {
      if (Date.now() - t0 > TIME_BUDGET_MS) return json({ ok: false, error: "time budget exceeded at page " + page, calls }, 500);
      if (page > MAX_PAGES) return json({ ok: false, error: "MAX_PAGES hard cap hit - Total grew past " + (MAX_PAGES * limit) + "?", calls }, 500);
      const j = await cin7Get("/product?Page=" + page + "&Limit=" + limit);
      calls++;
      total = Number(j?.Total ?? 0);
      // ⚠️ 응답 배열 키를 **추측하지 않는다** (2026-08-24 실사고 — 키 이름을 고정했다가 12페이지
      //   0행. finishedGoodsList→FinishedGoods 와 같은 계열: Cin7 은 목록 키가 엔드포인트마다
      //   제각각이다). 첫 페이지에서 배열형 키를 찾아 고정하고, 없으면 최상위 keys 를 실어 실패.
      if (arrayKey == null) {
        arrayKey = Object.keys(j ?? {}).find((k) => Array.isArray((j as any)[k])) ?? null;
        if (arrayKey == null) {
          return json({ ok: false, error: "no array key in /product response",
                        response_keys: Object.keys(j ?? {}), page, calls }, 500);
        }
      }
      const items = ((j as any)[arrayKey] ?? []) as any[];
      if (page === 1 && items.length < limit && items.length < total) limit = items.length;  // 실제 상한 보정
      if (!items.length) break;
      for (const p of items) {
        received++;
        const t = String(p?.Type ?? "").trim();
        typeCount[t || "(empty)"] = (typeCount[t || "(empty)"] ?? 0) + 1;
        const sku = String(p?.SKU ?? "").trim();
        if (!sku) continue;
        if (t !== "Stock") nonStock.push({ sku, product_type: t || "(empty)", is_service: p?.IsService === true });
      }
      if (received >= total || items.length < limit) break;
      page++;
      await sleep(PAGE_SLEEP_MS);
    }

    // ── 2) all-or-nothing — 불완전 수신이면 캐시 무접촉 ──
    if (total == null || received < total) {
      return json({ ok: false, error: "incomplete: received " + received + " of Total " + (total ?? "?") + " - cache untouched", calls }, 500);
    }

    // ── 3) 기존 캐시와 diff — 비교·보고만, 거르지 않는다 (Q-iii) ──
    // caps-ok: 비-Stock 품목만 저장하는 계약 테이블(마이그레이션 20260824140345 주석 · 실측 49행) —
    //   구조적 유계. 이 EF 자신이 그 계약의 집행자다(아래 교체가 Type!=='Stock' 만 넣는다).
    //   잘리면 diff 보고(added/removed)만 부정확 — 게이트 캐시 자체는 아래 교체가 전량으로 다시 쓴다.
    const curResp = await fetch(SB_URL() + "/rest/v1/inv_sku_types?select=sku,product_type", { headers: sbHeaders() });   // caps-ok: 비-Stock 계약 테이블(49행 — 이 EF 가 집행자) · 잘려도 diff 보고만 부정확, 캐시는 아래 교체가 전량
    if (!curResp.ok) throw new Error("read inv_sku_types " + curResp.status);
    const cur = (await curResp.json()) as { sku: string; product_type: string }[];
    const curMap = new Map(cur.map((r) => [r.sku, r.product_type]));
    const newMap = new Map(nonStock.map((r) => [r.sku, r.product_type]));
    const added = [...newMap.keys()].filter((s) => !curMap.has(s));
    const removed = [...curMap.keys()].filter((s) => !newMap.has(s));
    const typeChanged = [...newMap.keys()].filter((s) => curMap.has(s) && curMap.get(s) !== newMap.get(s));
    if (cur.length > 0) {   // 첫 적재(빈 캐시)는 전량 added 가 정상 — 경고 소음 방지
      if (added.length) warnings.push("non-stock SKU added in Cin7: " + added.join(", "));
      if (removed.length) warnings.push("SKU no longer non-stock in Cin7 (gate will stop filtering it): " + removed.join(", "));
      if (typeChanged.length) warnings.push("product_type changed: " + typeChanged.join(", "));
    }

    const summary = {
      ok: true, dry, calls, total, received,
      array_key: arrayKey,             // 실제 응답 배열 키 — 다음에 또 헤매지 않게 기록
      type_counts: typeCount,
      non_stock_rows: nonStock.length,
      non_stock: nonStock,             // [실측] 5행 규모 — 전량 노출이 곧 눈 검증
      added, removed, type_changed: typeChanged,
      warnings,
      duration_ms: 0 as number,
    };
    if (dry) { summary.duration_ms = Date.now() - t0; return json(summary); }

    // ── 4) 통째 교체 (delete-all → insert — 5행 규모라 diff-upsert 불요) ──
    const del = await fetch(SB_URL() + "/rest/v1/inv_sku_types?sku=neq.__none__", { method: "DELETE", headers: sbHeaders() });
    if (!del.ok) throw new Error("delete inv_sku_types " + del.status + ": " + (await del.text()).slice(0, 200));
    if (nonStock.length) {
      const ins = await fetch(SB_URL() + "/rest/v1/inv_sku_types", {
        method: "POST", headers: sbHeaders({ Prefer: "return=minimal" }),
        body: JSON.stringify(nonStock.map((r) => ({ ...r, refreshed_at: new Date().toISOString() }))),
      });
      if (!ins.ok) throw new Error("insert inv_sku_types " + ins.status + ": " + (await ins.text()).slice(0, 200));
    } else {
      warnings.push("no non-stock SKUs found - cache is now empty (gate inactive)");
    }
    summary.duration_ms = Date.now() - t0;
    return json(summary);
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});
