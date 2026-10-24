// 태그 재료 — Cin7 제품(product · Tags · LastModifiedOn) + 우리 표 상태(db) · ldfix-1d 시나리오 main · bigdel
'use strict';
const U = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');     // 우리 id
const C = n => 'c0000000-0000-4000-8000-' + String(n).padStart(12, '0');     // Cin7 GUID
const T_OLD = '2026-10-06T13:00:00.000+00:00', T_NEW = '2026-10-22T10:00:00.000+00:00';
const MOD_OLD = '2026-10-01T00:00:00Z', MOD_NEW = '2026-10-20T10:00:00Z';   // 기본 적재 시각(IPT_LAST_APPLY_DEFAULT 2026-10-10T18:52:00Z) 앞 · 뒤
const P = (n, sku, extra) => Object.assign({ ID: C(n), SKU: sku, Name: 'Product ' + sku, Status: 'Active', Tags: null, LastModifiedOn: MOD_OLD }, extra || {});
function dbP(n, sku, extra) {
  return Object.assign({ id: U(n), cin7_id: C(n), name: 'Product ' + sku, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, sku, family_id: null, parent_product_id: null, sellable: true, updated_by: null }, extra || {});
}
const tag = (n, pid, t, extra) => Object.assign({ id: U(500 + n), cin7_id: null, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, updated_by: null, product_id: pid, tag: t }, extra || {});

function build(scenario) {
  const product = [
    P(1, 'S1', { Tags: 'Clearance, Brand X' }),                     // IMS cin7: Brand X 만 → Clearance 넣기 · 수정일 앞 → 「뗀 것 짐작」 · 켜진 딜 ⚠️
    P(2, 'S2', { Tags: 'NewTag, OffDeal', LastModifiedOn: MOD_NEW }), // IMS cin7 0 → NewTag(변화 가능 · 딜 없음) · OffDeal(꺼진 딜)
    P(3, 'S3', { Tags: 'Clearance' }),                                // IMS 제품 created_at 이 적재 뒤 → 「새 제품」 · 켜진 딜 ⚠️
    P(4, 'S4', { Tags: 'hair care' }),                                // IMS manual 'Hair Care' → 철자는 manual 이 이김 · manual 겹침이라 건너뜀(넣기 0)
    P(5, 'S5', { Tags: 'Household' }),                                // IMS cin7: Household(그대로) · Gone Tag(Cin7 에 없음 · 수정일 앞 → 어긋남)
    P(6, 'S6', { Tags: '', LastModifiedOn: MOD_NEW }),                // IMS cin7: DISC_YesSale → 지우기 · 수정일 뒤 → 「Cin7 변화 가능」 · 켜진 딜 ⚠️
    P(7, 'S7', { Tags: 'Q4 2026' }),                                  // IMS cin7: 'q4 2026' → 철자 바뀜(지우기 + 넣기 짝)
    P(9, 'S9', { Tags: 'Clearance, Zed' }),                           // IMS 에 없는 Cin7 제품 → 판정 418 목록
    P(10, 'S10', { Tags: 'SkuOnly' })                                 // IMS 에 cin7_id 없이 SKU 만 같은 제품 → 쓰지 않고 센다
  ];
  const db = {
    product: [
      dbP(1, 'S1'), dbP(2, 'S2'), dbP(3, 'S3', { created_at: T_NEW }), dbP(4, 'S4'), dbP(5, 'S5'), dbP(6, 'S6'), dbP(7, 'S7'),
      dbP(8, 'S8'),                                                       // Cin7 에 제품이 없다(지워짐) → 그 cin7 태그는 「Cin7 에 제품 없음」
      dbP(10, 'S10', { cin7_id: null, source: 'manual' })
    ],
    product_tag: [
      tag(1, U(1), 'Brand X'),
      tag(2, U(1), 'AOS', { source: 'manual' }),                          // manual · Cin7 에 없어도 안 지운다
      tag(3, U(4), 'Hair Care', { source: 'manual' }),                    // manual · 철자 정본
      tag(4, U(5), 'Household'),
      tag(5, U(5), 'Gone Tag'),
      tag(6, U(6), 'DISC_YesSale'),
      tag(7, U(7), 'q4 2026'),
      tag(8, U(8), 'OldOnly')
    ],
    ref_currency: [{ id: U(699), code: 'CAD', name: 'Canadian Dollar' }],
    ref_price_tier: [{ id: U(700), code: 1, name: 'Wholesale', purpose: 'sale', currency_id: U(699) }],
    shop_store: [{ id: U(701), code: 'asung', shop_domain: 'asung-harness.myshopify.com', label: 'Asung', kind: 'asung', sale_tier_id: U(700) }],
    shop_listing: [{ id: U(702), store_id: U(701), family_id: null, product_id: U(1), is_on: true }],
    so_deal: [
      { id: U(801), cin7_id: null, source: 'manual', name: 'Sale: Blowout Sale', is_active: true, is_order_level: false, kind: 'pct' },
      { id: U(802), cin7_id: null, source: 'manual', name: 'Old Promo', is_active: false, is_order_level: false, kind: 'pct' }
    ],
    so_deal_line: [
      { id: U(811), cin7_id: null, source: 'manual', deal_id: U(801), line_no: 1, pct: 10, min_qty_mode: 'none', is_active: true },
      { id: U(812), cin7_id: null, source: 'manual', deal_id: U(802), line_no: 1, pct: 5, min_qty_mode: 'none', is_active: true }
    ],
    so_deal_target: [
      { id: U(821), cin7_id: null, source: 'manual', line_id: U(811), kind: 'include', target: 'tag', tag: 'Clearance' },
      { id: U(822), cin7_id: null, source: 'manual', line_id: U(811), kind: 'include', target: 'tag', tag: 'DISC_YesSale' },
      { id: U(823), cin7_id: null, source: 'manual', line_id: U(812), kind: 'include', target: 'tag', tag: 'OffDeal' }
    ]
  };
  if (scenario === 'bigdel') {      // 지울 줄 29 > 한도 20 → Apply 는 멈춤 · IPT_ALLOW_BIG_DELETE=1 이면 한 번 통과
    for (let i = 1; i <= 25; i++) db.product_tag.push(tag(100 + i, U(5), 'Bulk ' + i));
  }
  return { product, db, U, C, T_OLD, T_NEW, MOD_OLD, MOD_NEW };
}
module.exports = { build, U, C };
