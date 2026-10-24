// 손님 재료 — Cin7 응답(raw) + 우리 표 상태(db) · ldfix-1a 시나리오 main · dup · exists
'use strict';
const U = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');     // 우리 id
const C = n => 'c0000000-0000-4000-8000-' + String(n).padStart(12, '0');     // Cin7 GUID
const STAFF = U(999);
const T_OLD = '2026-10-06T13:00:00.000+00:00', T_NEW = '2026-10-22T10:00:00.000+00:00';
const REF = { cur: U(901), term: U(902), ar: U(903), sale: U(904), wh: U(905) };

function cin7Customer(n, name, extra) {
  return Object.assign({ ID: C(n), Name: name, DisplayName: null, Status: 'Active', Currency: 'CAD', PaymentTerm: 'C.B.S', AccountReceivable: '_61_', RevenueAccount: '_98_',
    Location: 'Asung Trading Inc.', Discount: 0, TaxRule: 'HST ON', PriceTier: 'Wholesale', IsBillParent: false, IsLegalEntity: false, Carrier: null, TaxNumber: null, Tags: null, Comments: null,
    CustomerParentID: null, Addresses: [], Contacts: [] }, extra || {});
}
// 우리 표의 cin7 손님 행 — 적재가 보내는 값과 같게(672 의 「덮여도 값 그대로」 를 만들려고) · ref id 는 REF 고정값(ref 표도 같은 id 로 둔다)
function dbCustomer(n, name, extra) {
  return Object.assign({ id: U(n), cin7_id: C(n), name, display_name: null, is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, updated_by: null,
    currency_id: REF.cur, currency_code: 'CAD', payment_term_id: REF.term, payment_term_name: 'C.B.S', discount_pct: 0, tax_rule: 'HST ON', price_tier: 'Wholesale', default_location_id: REF.wh, default_location_name: 'Asung Trading Inc.',
    ar_account_id: REF.ar, ar_account_code: '_61_', sale_account_id: REF.sale, sale_account_code: '_98_', parent_id: null, is_bill_parent: false, is_legal_entity: false, default_ship_to_customer_id: null, default_bill_to_customer_id: null,
    default_carrier: null, tax_number: null, tags: null, cin7_comments: null, invoice_split_by_store: false, created_by: null, reviewed_by: null, reviewed_at: null, parent_source: null, default_carrier_id: null, backorder_mail: false, final_invoice_mail: false }, extra || {});
}
function addr(n, custId, type, extra) {
  return Object.assign({ id: U(100 + n), cin7_id: C(100 + n), is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, updated_by: null, customer_id: custId, type, is_default_for_type: true, label: null,
    line1: 'Line ' + n, line2: null, city: 'Toronto', state_province: 'ON', postal_code: 'M1M 1M1', country: 'Canada' }, extra || {});
}
function contact(n, custId, extra) {
  return Object.assign({ id: U(200 + n), cin7_id: C(200 + n), is_active: true, source: 'cin7', note: null, created_at: T_OLD, updated_at: T_OLD, updated_by: null, customer_id: custId, name: 'Contact ' + n, phone: null, mobile_phone: null, fax: null,
    email: 'c' + n + '@x.ca', website: null, is_default: true, include_in_email: false, marketing_consent: true, cin7_comment: null, job_title: null }, extra || {});
}
const cloreKids = ['BLW', 'EDM', 'HMT', 'KIT', 'MSS', 'OTT'];

function build(scenario) {
  const raw = [
    cin7Customer(1, 'Clore Inc.'), cin7Customer(2, 'Other Parent'),
    ...cloreKids.map((k, i) => cin7Customer(11 + i, 'Clore Inc. (' + k + ')', { CustomerParentID: C(1) })),
    cin7Customer(3, 'Par A'),
    cin7Customer(4, 'Kid A', { CustomerParentID: C(3),
      Addresses: [{ ID: C(101), Type: 'Shipping', DefaultForType: true, Line1: 'Line 1', Line2: null, City: 'Toronto', State: 'ON', Postcode: 'M1M 1M1', Country: 'Canada' },
                  { ID: C(103), Type: 'Billing', DefaultForType: false, Line1: 'Line 3 CIN7', Line2: null, City: 'Toronto', State: 'ON', Postcode: 'M1M 1M1', Country: 'Canada' }],
      Contacts: [{ ID: C(201), Name: 'Contact 1', JobTitle: null, Phone: null, MobilePhone: null, Fax: null, Email: 'c1@x.ca', Website: null, Default: true, IncludeInEmail: false, MarketingConsent: 2, Comment: null }] }),
    cin7Customer(5, 'Kid Gone'),                       // 우리 표: 부모 Par A(cin7) → Cin7 에서 부모가 없어짐 → 비운다(청구처도)
    cin7Customer(6, 'Kid ImsOnly'),                    // 우리 표: 부모 Other Parent(ims) → 건드리지 않는다
    cin7Customer(7, 'TEST IMS Shopify', { CustomerParentID: C(3),   // IMS 에서 만든 손님과 이름 같음 → 짝짓기 · 주소 · 연락처 · 부모 잇기 건너뜀
      Addresses: [{ ID: C(107), Type: 'Billing', DefaultForType: true, Line1: 'B', City: 'T', State: 'ON', Postcode: 'P', Country: 'Canada' },
                  { ID: C(108), Type: 'Shipping', DefaultForType: true, Line1: 'S', City: 'T', State: 'ON', Postcode: 'P', Country: 'Canada' }],
      Contacts: [{ ID: C(207), Name: 'Shop Contact', Default: true, IncludeInEmail: false, MarketingConsent: 0 }] }),
    cin7Customer(8, 'Paired Before', { Addresses: [{ ID: C(110), Type: 'Shipping', DefaultForType: true, Line1: 'PB', City: 'T', State: 'ON', Postcode: 'P', Country: 'Canada' }] }),   // 지난 회차에 짝지은 손님
    cin7Customer(9, 'Touched Co'),                     // 우리 표: 직원이 이름을 고침(updated_by) → 672 목록 · 덮임
    cin7Customer(18, 'Stale ByNull')                   // 우리 표: updated_by null 인데 updated_at 이 적재 시각 뒤 → 어긋남 알림
  ];
  const db = {
    customer: [
      dbCustomer(1, 'Clore Inc.'), dbCustomer(2, 'Other Parent'),
      ...cloreKids.map((k, i) => dbCustomer(11 + i, 'Clore Inc. (' + k + ')', { parent_id: k === 'OTT' ? U(2) : U(1), parent_source: 'ims', default_bill_to_customer_id: k === 'OTT' ? U(2) : U(1), updated_by: STAFF, updated_at: T_OLD })),
      dbCustomer(3, 'Par A'), dbCustomer(4, 'Kid A'),
      dbCustomer(5, 'Kid Gone', { parent_id: U(3), parent_source: 'cin7', default_bill_to_customer_id: U(3) }),
      dbCustomer(6, 'Kid ImsOnly', { parent_id: U(2), parent_source: 'ims', default_bill_to_customer_id: U(2) }),
      dbCustomer(51, 'TEST IMS Shopify', { cin7_id: null, source: 'manual', currency_id: null, currency_code: null, payment_term_id: null, payment_term_name: null, tax_rule: null, price_tier: 'Retail', default_location_id: null, default_location_name: null, ar_account_id: null, ar_account_code: null, sale_account_id: null, sale_account_code: null, updated_by: STAFF, updated_at: T_NEW }),
      dbCustomer(52, 'Paired Before', { cin7_id: C(8), source: 'manual', updated_by: STAFF, updated_at: T_NEW }),
      dbCustomer(9, 'Touched Co', { name: 'Touched Co (IMS edit)', updated_by: STAFF, updated_at: T_NEW }),
      dbCustomer(10, 'Touched Gone', { updated_by: STAFF, updated_at: T_NEW }),          // Cin7 에 없음 · 활성 → 내린다 · 672 「덮이지 않음」
      dbCustomer(17, 'Gone Active'),                                                       // Cin7 에 없음 · 활성 → 내린다
      dbCustomer(18, 'Stale ByNull', { updated_at: '2026-10-21T00:00:00.000+00:00' })
    ],
    customer_address: [
      addr(1, U(4), 'Shipping'), addr(3, U(4), 'Billing', { line1: 'Line 3 IMS', updated_by: STAFF, updated_at: T_NEW }),
      addr(9, U(17), 'Shipping'),                                                          // Gone Active 의 주소 → 내린다
      addr(51, U(51), 'Billing', { cin7_id: null, source: 'manual' }), addr(52, U(51), 'Shipping', { cin7_id: null, source: 'manual' }),
      addr(53, U(52), 'Shipping', { cin7_id: null, source: 'manual' })
    ],
    customer_contact: [ contact(1, U(4)), contact(51, U(51), { cin7_id: null, source: 'manual' }) ],
    ref_currency: [{ id: REF.cur, code: 'CAD', name: 'Canadian Dollar' }], ref_payment_term: [{ id: REF.term, name: 'C.B.S' }],
    ref_account: [{ id: REF.ar, code: '_61_', name: 'AR' }, { id: REF.sale, code: '_98_', name: 'Sales' }], ref_warehouse: [{ id: REF.wh, name: 'Asung Trading Inc.' }]
  };
  if (scenario === 'dup') {           // 같은 이름 둘(Cin7 쪽) → 멈춤
    raw.push(cin7Customer(21, 'Dup Name'), cin7Customer(22, 'Dup Name'));
    db.customer.push(dbCustomer(53, 'Dup Name', { cin7_id: null, source: 'manual' }));
  }
  if (scenario === 'exists') {        // IMS 손님과 이름 같은 Cin7 손님이 이미 cin7 행 → 멈춤
    raw.push(cin7Customer(23, 'Exists Co'));
    db.customer.push(dbCustomer(23, 'Exists Co'), dbCustomer(54, 'Exists Co', { cin7_id: null, source: 'manual' }));
  }
  return { raw, db, U, C, STAFF, T_OLD, T_NEW, REF };
}
module.exports = { build, U, C, STAFF };
