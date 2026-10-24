// 공급처 재료 — Cin7 응답(supplier) + 우리 표 상태(db) + 제품↔공급처 시트 · ldfix-1c 시나리오 main · conflict
'use strict';
const U = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const C = n => 'c0000000-0000-4000-8000-' + String(n).padStart(12, '0');
const STAFF = U(999);
const T_OLD = '2026-10-06T13:00:00.000+00:00', T_NEW = '2026-10-22T10:00:00.000+00:00';
const REF = { cur: U(901), term: U(902), ap: U(903) };
const SUP = (n, name, extra) => Object.assign({ ID: C(n), Name: name, Currency: 'CAD', PaymentTerm: 'Net 30', AccountPayable: '_109_', TaxRule: 'Zero-rated (Purchase)', Discount: 0, Comments: null, TaxNumber: null, Status: 'Active', Addresses: [], Contacts: [] }, extra || {});
function dbS(n, name, extra) {
  return Object.assign({ id: U(n), cin7_id: C(n), name, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, payment_term_id: REF.term, payment_term_name: 'Net 30', account_payable_id: REF.ap, account_payable_code: '_109_',
    currency_id: REF.cur, tax_rule: 'Zero-rated (Purchase)', is_purchasable: true, is_discontinued: false, discontinued_on: null, cin7_comments: null, updated_by: null, created_by: null, is_active_source: null }, extra || {});
}
const addr = (n, sid, extra) => Object.assign({ id: U(100 + n), cin7_id: C(100 + n), is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, supplier_id: sid, line1: 'Line ' + n, line2: null, city: 'Toronto', state_province: 'ON', postal_code: 'M1M 1M1', country: 'Canada', type: 'Business', updated_by: null }, extra || {});
const ct = (n, sid, extra) => Object.assign({ id: U(200 + n), cin7_id: C(200 + n), is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, supplier_id: sid, name: 'Contact ' + n, phone: '416-000-000' + n, mobile_phone: null, fax: null, email: null, website: null, is_default: true, cin7_comment: null, updated_by: null }, extra || {});
const prod = (n, sku) => ({ id: U(500 + n), cin7_id: C(500 + n), name: 'Product ' + sku, is_active: true, source: 'cin7', sku, sellable: true, parent_product_id: null, pack_factor: null, family_id: null, uom_name: 'EA', cin7_type: 'Stock', is_discontinued: false, updated_by: null, created_at: T_OLD, updated_at: T_OLD });
const ps = (n, pid, sid, extra) => Object.assign({ id: U(600 + n), cin7_id: C(600 + n), is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, product_id: pid, supplier_id: sid, supplier_sku: 'SS' + n, cost: 1.5, fixed_cost: null, currency_id: REF.cur, last_supplied: '2026-09-01', is_default: false, updated_by: null, price_formula_id: null }, extra || {});

function build(scenario) {
  const supplier = [
    SUP(1, 'Supplier S1', { Addresses: [{ ID: C(101), Type: 'Business', Line1: 'Line 1', City: 'Toronto', State: 'ON', Postcode: 'M1M 1M1', Country: 'Canada' }],
                            Contacts: [{ ID: C(201), Name: 'Contact 1', Phone: '416-000-0001', Default: true }, { ID: C(209), Name: 'No Longer Purchase', Default: false }] }),   // 그대로 · 연락처 하나 + 거래 중단 표시(안 넣음)
    SUP(2, 'Supplier S2', { Status: 'Deprecated', Contacts: [{ ID: C(202), Name: 'Contact 2', Phone: '416-000-0002', Default: true }] }),   // 우리 표: 직원이 이름 · 켜짐을 고침(Energizer 류) → 이름은 Cin7 이 덮고(672) is_active 는 IMS 값 유지(680) · 연락처 손댐(672) · Deprecated 라 주소·연락처 안 보냄(활성만)
    SUP(3, 'Supplier S3 New'),                                                       // 새 활성 → 넣는다
    SUP(4, 'Supplier S4 Old', { Status: 'Deprecated' }),                             // 새 비활성 → 안 넣는다(Extra 몫)
    SUP(5, '​TEST Supplier-Canada', { Addresses: [{ ID: C(105), Type: 'Business', Line1: 'IMS st', City: 'T', State: 'ON', Postcode: 'P', Country: 'Canada' }],
                                            Contacts: [{ ID: C(205), Name: 'Cin7 Contact 5', Default: true }] }),   // IMS 공급처와 보이는 글자 같음(앞에 U+200B · 판정 681) → cin7_id 만(674) · 주소 · 연락처 안 보냄
    SUP(7, 'Supplier S7', { Status: 'Deprecated' })                                   // 우리 표의 비활성 cin7 행(31 류) → 갱신(is_active false 그대로)
  ];
  const db = {
    ref_currency: [{ id: REF.cur, code: 'CAD', name: 'Canadian Dollar' }], ref_payment_term: [{ id: REF.term, name: 'Net 30' }], ref_account: [{ id: REF.ap, code: '_109_', name: 'AP', account_class: 'LIABILITY' }],
    supplier: [
      dbS(1, 'Supplier S1'),
      dbS(2, 'Supplier S2 (IMS edit)', { is_active: true, is_active_source: 'ims', updated_by: STAFF, updated_at: T_NEW }),   // 판정 683 — IMS 가 켠 표식(몇 번 적재해도 남는다)
      dbS(205, 'TEST Supplier-Canada', { cin7_id: null, source: 'manual', is_purchasable: true, updated_by: STAFF, updated_at: T_NEW }),
      dbS(6, 'Supplier S6 Gone'),                                                     // Cin7 전량에 없음 · 활성 → 내린다
      dbS(7, 'Supplier S7', { is_active: false })
    ],
    supplier_address: [ addr(1, U(1)), addr(6, U(6)), addr(51, U(205), { cin7_id: null, source: 'manual', line1: 'IMS own' }) ],   // addr 6 = Gone 의 주소 → 내린다
    supplier_contact: [ ct(1, U(1)), ct(2, U(2), { phone: '416-IMS-EDIT', updated_by: STAFF, updated_at: T_NEW }), ct(51, U(205), { cin7_id: null, source: 'manual', name: 'IMS Contact', is_default: true }) ],
    product: [ prod(1, 'P1'), prod(2, 'P2'), prod(3, 'P3'), prod(4, 'P4') ],
    product_supplier: [
      ps(1, U(501), U(1), { cost: 9.99, updated_by: STAFF, updated_at: T_NEW }),      // 손댄 cin7 줄 → 672 로그 · Cin7 이 덮는다(cost 1.5)
      ps(3, U(502), U(1), { source: 'manual', is_active: false, cost: 7.77, updated_by: STAFF, updated_at: T_NEW }),   // IMS 가 끈 Cin7 줄(Roux 꼴 · manual + cin7_id) → 보내지 않음
      ps(4, U(501), U(2), { cin7_id: null, source: 'manual', cost: 5.55, supplier_sku: 'IMS-SKU' }),  // 사람이 먼저 적은 줄 → 승격: cin7_id 만
      ps(6, U(503), U(6), { is_default: true }),                                       // 재계산 ①: P3 의 기본이 사라진 공급처 S6 위에 → 본 행 Apply 가 S6 를 내린 뒤 꺼진다
      ps(7, U(504), U(1), { is_default: false, last_supplied: '2026-09-10' })          // 재계산 ②: P4 는 활성 공급처 S1 줄 하나뿐인데 기본 없음 → 켜진다
    ]
  };
  // 제품↔공급처 시트(ips_line) — ImsLoadSupplierExtra 가 적어 둔 것과 같은 꼴 · 전부 문자열
  const HEAD = ['ProductCin7Id', 'SupplierCin7Id', 'ProductSupplierID', 'SupplierSku', 'Cost', 'FixedCost', 'Currency', 'LastSupplied', 'SKU', 'SupplierName'];
  const sheet = [HEAD,
    [C(501), C(1), C(601), 'SS1', '1.5', '', 'CAD', '2026-09-01', 'P1', 'Supplier S1'],        // 기존 cin7 줄(손댐) → upsert · 672
    [C(502), C(1), C(603), 'SS3', '2.5', '', 'CAD', '2026-09-01', 'P2', 'Supplier S1'],        // IMS 가 끈 줄 → 보내지 않음
    [C(501), C(2), C(604), 'CIN7-SKU', '3.5', '', 'CAD', '2026-09-15', 'P1', 'Supplier S2'],   // manual 줄과 (product, supplier) 같음 → 승격 cin7_id 만
    [C(502), C(3), C(605), 'SS5', '4.5', '', 'CAD', '2026-09-20', 'P2', 'Supplier S3 New']     // 새 줄(새 공급처 S3 · 본 행 적재 뒤라 supMap 에 있다)
  ];
  if (scenario === 'conflict') {        // Cin7 이 S1 의 이름을 우리 표의 다른 행(S6 Gone)과 같게 바꿈 → 23505 사전 검사 멈춤
    supplier[0] = Object.assign({}, supplier[0], { Name: 'Supplier S6 Gone' });
  }
  return { supplier, db, sheet, U, C, STAFF, REF, T_OLD, T_NEW };
}
module.exports = { build, U, C, STAFF };
