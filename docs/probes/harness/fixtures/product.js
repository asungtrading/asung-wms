// 제품 재료 — Cin7 응답(product · productFamily) + 우리 표 상태(db) · ldfix-1b 시나리오 main · conflict
'use strict';
const U = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');     // 우리 id
const C = n => 'c0000000-0000-4000-8000-' + String(n).padStart(12, '0');     // Cin7 GUID
const STAFF = U(999);
const T_OLD = '2026-10-06T13:00:00.000+00:00', T_NEW = '2026-10-22T10:00:00.000+00:00';
const PF = (n, sku, extra) => Object.assign({ ID: C(n), SKU: sku, Name: 'Family ' + sku, Brand: null, Category: null, UOM: null, Option1Name: 'Color', Option2Name: null, Option3Name: null, CostingMethod: 'FIFO', Description: null, LastModifiedOn: null, Products: [] }, extra || {});
const P = (n, sku, extra) => Object.assign({ ID: C(n), SKU: sku, Name: 'Product ' + sku, Status: 'Active', Type: 'Stock', UOM: 'EA', Brand: null, Category: null, Sellable: true,
  InventoryAccount: null, COGSAccount: null, RevenueAccount: null, ExpenseAccount: null, PurchaseTaxRule: null, SaleTaxRule: null, CostingMethod: 'FIFO', HSCode: null, CountryOfOrigin: null, CountryOfOriginCode: null,
  Weight: null, WeightUnits: null, Description: null, InternalNote: null, CreatedDate: null, LastModifiedOn: null, AdditionalAttribute3: null, AdditionalAttribute4: null, Barcode: null, BillOfMaterialsProducts: [] }, extra || {});
// 우리 표의 cin7 제품 행 — 적재가 보내는 값과 같게(672 「덮여도 값 그대로」) · 보내지 않는 칸은 null/기본
function dbP(n, sku, extra) {
  return Object.assign({ id: U(n), cin7_id: C(n), name: 'Product ' + sku, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, sku, family_id: null, option1_value: null, option2_value: null, option3_value: null,
    parent_product_id: null, pack_factor: null, brand_id: null, brand_name: null, category_id: null, category_name: null, unit_id: null, uom_name: 'EA',
    inventory_account_id: null, inventory_account_code: null, cogs_account_id: null, cogs_account_code: null, revenue_account_id: null, revenue_account_code: null, expense_account_id: null, expense_account_code: null,
    purchase_tax_rule: null, sale_tax_rule: null, cin7_type: 'Stock', sellable: true, costing_method: 'FIFO', hs_code: null, country_of_origin: null, country_of_origin_code: null, weight: null, weight_unit: null,
    cin7_description: null, cin7_internal_note: null, cin7_created_on: null, cin7_modified_on: null, is_discontinued: false, cin7_project_name: null, registered_on: null, updated_by: null, set_discount_pct: null, surcharge_group_id: null, sellable_source: null,
    description_edited_at: null, description_edited_by: null, description_html: null }, extra || {});
}
function dbF(n, sku, extra) {
  return Object.assign({ id: U(n), cin7_id: C(n), name: 'Family ' + sku, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, sku, brand_id: null, brand_name: null, category_id: null, category_name: null, unit_id: null, uom_name: null,
    option1_name: 'Color', option2_name: null, option3_name: null, costing_method: 'FIFO', cin7_description: null, cin7_modified_on: null, updated_by: null, description_edited_at: null, description_edited_by: null, description_html: null, web_image_id: null }, extra || {});
}
const bc = (n, pid, barcode, extra) => Object.assign({ id: U(300 + n), cin7_id: null, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, product_id: pid, barcode, is_primary: true, valid_from: null, updated_by: null }, extra || {});
const bom = (n, parent, comp, qty, extra) => Object.assign({ id: U(400 + n), cin7_id: null, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, parent_product_id: parent, component_product_id: comp, quantity: qty, wastage_percent: null, wastage_quantity: null, cost_percentage: null, updated_by: null }, extra || {});

function build(scenario) {
  const productFamily = [
    PF(101, 'F1FAM', { Products: [{ SKU: 'P1', Option1: 'Red' }, { SKU: 'P8', Option1: 'Blue' }] }),   // P8 은 우리 표에서 manual family F2 로 옮겨 둠(새 ⑧) → Cin7 F1 로 되돌아간다(672 로그)
    PF(102, 'F2FAM'),                                                                                       // 우리 표의 manual family 와 SKU 같음 → cin7_id 만(674)
    PF(103, 'F3FAM', { Name: 'Family F3FAM' })                                                                // 우리 표에서 이름을 고침(updated_by) → 672 · Cin7 이 덮는다
  ];
  const product = [
    P(1, 'P1', { Barcode: 'B1' }),                                                          // 그대로
    P(2, 'P2', { Sellable: true, Barcode: 'B2' }),                                          // 우리 표: sellable false · sellable_source ims → IMS 값 유지(670) · 바코드 B2 는 IMS 가 끔(manual) → 안 보냄
    P(3, 'P1-6', { UOM: '6', Sellable: true, BillOfMaterialsProducts: [{ ComponentProductID: C(1), ProductCode: 'P1', Quantity: 6 }] }),   // ims sellable 세트 → false 유지
    P(4, 'P1-12', { UOM: '12', Sellable: true, BillOfMaterialsProducts: [{ ComponentProductID: C(1), ProductCode: 'P1', Quantity: 12 }] }), // cin7 세트 기존(sellable_source cin7 · false) → 세트라 IMS 값 false 유지(675)
    P(14, 'P1-24', { UOM: '24', Sellable: true, BillOfMaterialsProducts: [{ ComponentProductID: C(1), ProductCode: 'P1', Quantity: 24 }] }), // cin7 세트 기존인데 우리 표 sellable true(BEL43475-12 류) → true 그대로
    P(5, 'P1-36', { UOM: '36', Sellable: true, BillOfMaterialsProducts: [{ ComponentProductID: C(1), ProductCode: 'P1', Quantity: 36 }] }), // 새 세트 → 1단계 Cin7 값 true → 2단계 잇기에서 트리거 false
    P(6, 'P6'),                                                                             // 우리 표에 manual 로 같은 SKU → cin7_id 만(674 · cs-4)
    P(7, 'P7'),                                                                             // 우리 표: cin7_id 같고 sku 'P7-NEW' → IMS SKU 유지(679) · on_conflict=cin7_id
    P(8, 'P8', { Barcode: 'B8' }),                                                          // 우리 표: 직원이 이름 고침 + family 옮김 → 672 목록 · Cin7 이 덮는다 · 바코드 B8 대표 끔(cin7 · updated_by) → 덮임 로그
    P(10, 'P10', { BillOfMaterialsProducts: [{ ComponentProductID: C(1), ProductCode: 'P1', Quantity: 2 }, { ComponentProductID: C(2), ProductCode: 'P2', Quantity: 1 }] }),   // 콤보 · (P10,P2) 는 IMS 가 끔(manual) → 안 보냄 · (P10,P1) 손댐 qty 3 → 672
    P(11, 'P11'),                                                                           // 새 제품(낱개) → on_conflict=sku
    P(12, 'AS91437-BLK', { Type: 'Non Inventory' }),                                        // Extra 한 건 · 우리 표에 있음 → cin7_id 로
    P(13, 'P13-SVC', { Type: 'Service' })                                                   // Stock 아님 → 건너뜀
  ];
  const db = {
    product_family: [
      dbF(101, 'F1FAM'),
      dbF(202, 'F2FAM', { cin7_id: null, source: 'manual' }),
      dbF(103, 'F3FAM', { name: 'Family F3 (IMS edit)', updated_by: STAFF, updated_at: T_NEW })
    ],
    product: [
      dbP(1, 'P1', { family_id: U(101), option1_value: 'Red' }),
      dbP(2, 'P2', { sellable: false, sellable_source: 'ims', updated_by: STAFF, updated_at: T_NEW }),
      dbP(3, 'P1-6', { parent_product_id: U(1), pack_factor: 6, uom_name: '6', sellable: false, sellable_source: 'ims' }),
      dbP(4, 'P1-12', { parent_product_id: U(1), pack_factor: 12, uom_name: '12', sellable: false, sellable_source: 'cin7' }),
      dbP(14, 'P1-24', { parent_product_id: U(1), pack_factor: 24, uom_name: '24', sellable: true, sellable_source: 'cin7' }),
      dbP(206, 'P6', { cin7_id: null, source: 'manual', name: 'P6 made in IMS', sellable: false, sellable_source: 'ims' }),
      dbP(7, 'P7-NEW', { }),
      dbP(8, 'P8', { name: 'Product P8 (IMS edit)', family_id: U(202), option1_value: 'Blue', updated_by: STAFF, updated_at: T_NEW }),
      dbP(10, 'P10', { }),
      dbP(12, 'AS91437-BLK', { cin7_type: 'Non Inventory' })
    ],
    product_barcode: [
      bc(1, U(1), 'B1'), bc(2, U(2), 'B2', { is_active: false, is_primary: false, source: 'manual', updated_by: STAFF, updated_at: T_NEW }), bc(8, U(8), 'B8', { is_primary: false, updated_by: STAFF, updated_at: T_NEW })
    ],
    product_bom: [
      bom(1, U(10), U(1), 3, { updated_by: STAFF, updated_at: T_NEW }), bom(2, U(10), U(2), 1, { is_active: false, source: 'manual', updated_by: STAFF, updated_at: T_NEW })
    ],
    ref_brand: [], ref_category: [], ref_unit: [], ref_account: []
  };
  if (scenario === 'conflict') {        // 같은 SKU 가 다른 cin7 행 → 멈춤
    product.push(P(21, 'P9'));
    db.product.push(dbP(22, 'P9'));
  }
  return { product, productFamily, db, U, C, STAFF, T_OLD, T_NEW };
}
module.exports = { build, U, C, STAFF };
