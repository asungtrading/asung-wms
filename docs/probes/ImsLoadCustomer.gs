/**
 * ImsLoadCustomer.gs — IMS SO 모듈 손님 표 셋 적재 (customer · customer_address · customer_contact)
 * 2026-09-22 밤 작성 · 정본 docs/design/so-module.md §9(9-g 실측 · 9-h 판정 ⑥~⑨ · 9-i 판정 ⑩~⑫)
 *
 * ⚠️⚠️ 대상: [테스트 · Asung-IMS] — SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY (ImsRefLoad.gs 머리 주석 참조)
 * ⚠️ ims_fetch_ · ims_blank_ 는 ImsRefLoad.gs 것을 쓴다(같은 프로젝트) — 다시 만들지 않는다
 * ⚠️ 최상위 const·var 금지 · 식별자 ASCII 만 · 트리거를 걸지 마라(손으로 실행)
 * ⚠️ 이 파일의 이름은 전부 ilc 로 시작한다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY · SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 * 쓰는 Script Properties: ILC_FOLDER_ID · ILC_NEXT_PAGE · ILC_DONE · ILC_TOTAL · (허락용) ILC_ALLOW_BIG_DOWN
 *
 * 안전장치 둘(2026-09-22 가짜 데이터 시험에서 수집이 짧게 끝나자 받지 못한 151명을 내렸다)
 *   1  받은 행 수 ≠ API Total → 멈춘다(다시 모은다)
 *   2  한 번에 내리는 줄이 max(20, 1%)를 넘으면 멈춘다 — 맞으면 ILC_ALLOW_BIG_DOWN=1 을 넣고 다시
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서 — 한 단계씩 · 끝날 때마다 로그를 본다
 *   0  imsLoadCustomerCollect   Cin7 전량을 Drive 에 모은다(이어 달리기 · 「Next run」 이면 다시)
 *   1  imsLoadCustomerDry       ⭐ 쓰지 않고 센다 — 멈춤 조건·FK 빈 곳·기본 규칙 결과·보낼 행 수
 *   2  imsLoadCustomerApply1    손님 upsert(parent_id 는 보내지 않는다) → Cin7 에 없는 손님은 is_active=false
 *   3  imsLoadCustomerApply2    부모 13명 잇기 · Cin7 에서 부모가 없어진 손님은 비우기(판정 ⑫ 2단계)
 *   4  imsLoadCustomerApply3    주소 — 먼저 내리기(is_active=false + 기본 해제) → upsert(판정 ⑩ 순서)
 *   5  imsLoadCustomerApply4    연락처 — 같은 순서
 *   6  imsLoadCustomerVerify    다시 읽어 센다 — HTTP 200 만 믿지 않는다
 *   ⟲  imsLoadCustomerReset     다시 모을 때만(Drive 폴더는 지우지 않는다)
 *
 * 멈춤 조건(추정해 넣지 않는다 — 로그에 무엇이 나왔는지 적고 throw)
 *   · Status 가 Active · Deprecated 밖
 *   · MarketingConsent 가 0·1·2·3 밖(판정 ⑥ · 네 값 모두 Caleb 화면 대조 · ⚠️ 순서·추론으로 옮기지 마라)
 *   · Address Type 이 Billing · Business · Shipping · 빈 값 밖(CHECK 가 어차피 막는다 — 먼저 알려 준다)
 *   · 한 손님의 연락처에 Default 가 둘 이상(실측 0 · 규칙이 정해지지 않았다)
 *   · 같은 cin7_id 가 두 번(주소·연락처·손님 어느 표든)
 *
 * 적재가 절대 보내지 않는 칸(판정 ⑫) — id · updated_at · updated_by · created_at · note ·
 *   customer.parent_id(1단계) · default_ship_to_customer_id · default_bill_to_customer_id ·
 *   customer_address.label · default_customer_id(생성 칸 — 보내면 PostgREST 가 거부한다)
 *   ⚠️ 「보내지 않는다」 ≠ 「null 로 보낸다」 — upsert 는 보낸 칸을 덮는다
 *
 * 기본 주소 규칙(판정 ③·⑦) — 손님·type 마다
 *   체크 1개 그대로 · 체크 없고 그 type 주소 하나 → 그것을 기본 · 체크 없고 여럿 → 비움 · 체크 둘 이상 → 비움
 *   비운 손님은 「기본을 사람이 정할 손님」으로 이름을 낸다
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   0  수집 — Cin7 전량을 Drive 에 (CustomerProbe 의 cupCollect 와 같은 모양)
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerCollect() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('ILC_DONE') === '1') {
    Logger.log('이미 다 모았다 — 다음은 imsLoadCustomerDry. 새로 모으려면 imsLoadCustomerReset 먼저.');
    return;
  }
  var folderId = props.getProperty('ILC_FOLDER_ID');
  var folder;
  if (folderId) {
    folder = DriveApp.getFolderById(folderId);
  } else {
    folder = DriveApp.createFolder('ImsLoadCustomer ' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
    props.setProperty('ILC_FOLDER_ID', folder.getId());
  }
  var startPage = Number(props.getProperty('ILC_NEXT_PAGE') || '1');
  var page = startPage, started = Date.now(), rows = [], done = false, total = null;
  while (Date.now() - started < 270000) {
    var data = ilc_cin7_('customer?Page=' + page + '&Limit=100&IncludeDeprecated=true');
    var items = data.CustomerList || [];
    if (total === null) total = data.Total;
    rows = rows.concat(items);
    if (items.length < 100) { done = true; break; }   // ⚠️ Total 이 아니라 받은 행 수로 끝을 판단한다
    page++;
    Utilities.sleep(1500);
  }
  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = 'pages-' + ilc_pad_(startPage) + '-' + ilc_pad_(lastPage) + '.json';
    folder.createFile(name, JSON.stringify(rows), MimeType.PLAIN_TEXT);
    Logger.log('저장: ' + name + ' · ' + rows.length + '명');
  }
  if (total !== null) props.setProperty('ILC_TOTAL', String(total));
  if (done) {
    props.setProperty('ILC_DONE', '1');
    props.deleteProperty('ILC_NEXT_PAGE');
    Logger.log('⭐ 수집 끝 — 마지막 페이지 ' + page + ' · API Total ' + total + ' · 다음은 imsLoadCustomerDry');
  } else {
    props.setProperty('ILC_NEXT_PAGE', String(page));
    Logger.log('Next run — 다음 페이지 ' + page + ' 부터 · imsLoadCustomerCollect 를 한 번 더');
  }
  Logger.log('폴더: ' + folder.getUrl());
}

function imsLoadCustomerReset() {
  var props = PropertiesService.getScriptProperties();
  ['ILC_FOLDER_ID', 'ILC_NEXT_PAGE', 'ILC_DONE', 'ILC_TOTAL'].forEach(function (k) { props.deleteProperty(k); });
  Logger.log('ILC_* 속성을 비웠다 — Drive 폴더는 그대로(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   1  dryRun — 쓰지 않는다
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerDry() {
  var b = ilc_build_();
  var out = b.report;
  out.push('');
  out.push('⭐ dryRun 끝 — 아무것도 쓰지 않았다. 숫자가 맞으면 imsLoadCustomerApply1');
  ilc_writeReport_('dry', out);
}


/* ═══════════════════════════════════════════════════════════
   2  손님 upsert · Cin7 에 없는 손님 내리기
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerApply1() {
  var t0 = Date.now();
  var b = ilc_build_();
  var out = ['=== Apply1 손님 ' + new Date().toISOString() + ' ==='];
  var n = ilc_upsert_('customer', b.customers, 500, null, t0);
  out.push('upsert 돌아온 행 ' + n + ' / 보낸 ' + b.customers.length);

  // Cin7 에 없는 손님(source='cin7') → is_active=false · 지우지 않는다(마스터 · po-module §3-f 한 규칙)
  var db = ilc_readAll_('/rest/v1/customer?select=id,cin7_id,is_active&source=eq.cin7');
  var inCin7 = {};
  b.customers.forEach(function (r) { inCin7[r.cin7_id] = true; });
  var gone = db.filter(function (r) { return r.cin7_id && !inCin7[r.cin7_id] && r.is_active; });
  var down = ilc_patchIn_('customer', 'cin7_id', gone.map(function (r) { return r.cin7_id; }), { is_active: false }, b.customers.length);
  out.push('Cin7 에 없어 내린 손님 ' + down + (gone.length ? ' : ' + gone.slice(0, 20).map(function (r) { return r.cin7_id; }).join(', ') : ''));
  out.push('다음은 imsLoadCustomerApply2(부모)');
  ilc_writeReport_('apply1', out);
}


/* ═══════════════════════════════════════════════════════════
   3  부모 잇기 · 비우기 (판정 ⑫ 2단계)
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerApply2() {
  var b = ilc_build_();
  var map = ilc_customerMap_(b.customers.length);
  var out = ['=== Apply2 부모 ' + new Date().toISOString() + ' ==='];
  var linked = 0, missing = [], childIds = {};
  b.parents.forEach(function (p) {
    var childId = map[p.child_cin7_id], parentId = map[p.parent_cin7_id];
    if (!childId || !parentId) { missing.push(p.child_name + ' → ' + p.parent_cin7_id); return; }
    childIds[p.child_cin7_id] = true;
    var res = ims_fetch_('/rest/v1/customer?id=eq.' + childId, {
      method: 'patch', headers: { 'Prefer': 'return=representation' },
      payload: JSON.stringify({ parent_id: parentId })
    });
    if (res.getResponseCode() >= 300) throw new Error('부모 잇기 실패 ' + p.child_name + ' → HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
    if (JSON.parse(res.getContentText()).length !== 1) throw new Error('부모 잇기 — 돌아온 행이 1 이 아니다: ' + p.child_name);
    linked++;
  });
  out.push('부모 이은 손님 ' + linked + ' / Cin7 부모 있는 손님 ' + b.parents.length);
  if (missing.length) throw new Error('⚠️ 부모·자식 중 우리 표에 없는 쪽이 있다 — Apply1 을 먼저: ' + missing.join(' | '));

  // Cin7 에서 부모가 없어진 손님 → parent_id 비우기
  var withParent = ilc_readAll_('/rest/v1/customer?select=id,cin7_id&source=eq.cin7&parent_id=not.is.null');
  var clear = withParent.filter(function (r) { return !childIds[r.cin7_id]; });
  var cleared = ilc_patchIn_('customer', 'cin7_id', clear.map(function (r) { return r.cin7_id; }), { parent_id: null });
  out.push('부모를 비운 손님 ' + cleared);
  out.push('다음은 imsLoadCustomerApply3(주소)');
  ilc_writeReport_('apply2', out);
}


/* ═══════════════════════════════════════════════════════════
   4 · 5  주소 · 연락처 — 내리기 → upsert (판정 ⑩ 순서 · ⑪ 한 손님은 한 요청)
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerApply3() { ilc_applyChild_('customer_address', 'addresses', { is_active: false, is_default_for_type: false }); }
function imsLoadCustomerApply4() { ilc_applyChild_('customer_contact', 'contacts', { is_active: false, is_default: false }); }

function ilc_applyChild_(table, key, downBody) {
  var t0 = Date.now();
  var b = ilc_build_();
  var map = ilc_customerMap_(b.customers.length);
  var out = ['=== ' + table + ' ' + new Date().toISOString() + ' ==='];

  // customer_id — Cin7 손님 ID → 우리 customer.id
  var rows = [], noCust = 0;
  b[key].forEach(function (r) {
    var cid = map[r._customer_cin7_id];
    if (!cid) { noCust++; return; }
    var o = {};
    Object.keys(r).forEach(function (k) { if (k.charAt(0) !== '_') o[k] = r[k]; });
    o.customer_id = cid;
    rows.push(o);
  });
  if (noCust) throw new Error('⚠️ 손님을 못 찾은 ' + key + ' ' + noCust + '줄 — Apply1 을 먼저');

  // ① 먼저 내리기 — source='cin7' · 이번에 안 온 cin7_id · 아직 활성이거나 기본인 것만
  var db = ilc_readAll_('/rest/v1/' + table + '?select=cin7_id,is_active&source=eq.cin7');
  var inCin7 = {};
  rows.forEach(function (r) { inCin7[r.cin7_id] = true; });
  var gone = db.filter(function (r) { return r.cin7_id && !inCin7[r.cin7_id] && r.is_active; });
  var down = ilc_patchIn_(table, 'cin7_id', gone.map(function (r) { return r.cin7_id; }), downBody, rows.length);
  out.push('① 내린 줄(Cin7 에 없음) ' + down);

  // ② upsert — ⚠️ 한 손님의 줄은 한 요청 안에(판정 ⑪ · deferrable 은 문장 하나 안에서만 교대를 구한다)
  var n = ilc_upsert_(table, rows, 500, 'customer_id', t0);
  out.push('② upsert 돌아온 행 ' + n + ' / 보낸 ' + rows.length);
  out.push(table === 'customer_address' ? '다음은 imsLoadCustomerApply4(연락처)' : '다음은 imsLoadCustomerVerify');
  ilc_writeReport_(table, out);
}


/* ═══════════════════════════════════════════════════════════
   6  검증 — 다시 읽어 센다
   ═══════════════════════════════════════════════════════════ */

function imsLoadCustomerVerify() {
  var b = ilc_build_();
  var out = ['=== 검증 ' + new Date().toISOString() + ' ==='];
  // 재적재 뒤에는 Cin7 에서 사라진 손님이 내려 둔 채 남는다 — 전체 수는 「Cin7 수 + 내려 둔 수」와 대조한다
  var inCin7 = {};
  b.customers.forEach(function (r) { inCin7[r.cin7_id] = true; });
  var goneKept = ilc_readAll_('/rest/v1/customer?select=cin7_id&source=eq.cin7').filter(function (r) { return r.cin7_id && !inCin7[r.cin7_id]; }).length;
  out.push('   (Cin7 에 없어 내려 둔 손님 ' + goneKept + ')');
  var pairs = [
    ['customer 전체(source=cin7) = Cin7 + 내려 둔 손님', '/rest/v1/customer?select=id&source=eq.cin7', b.customers.length + goneKept],
    ['customer 활성', '/rest/v1/customer?select=id&source=eq.cin7&is_active=eq.true', b.counts.customerActive],
    ['customer 부모 있음', '/rest/v1/customer?select=id&parent_id=not.is.null', b.parents.length],
    ['customer_address 활성(cin7)', '/rest/v1/customer_address?select=id&source=eq.cin7&is_active=eq.true', b.addresses.length],
    ['customer_address 기본', '/rest/v1/customer_address?select=id&is_active=eq.true&is_default_for_type=eq.true', b.counts.addressDefault],
    ['customer_contact 활성(cin7)', '/rest/v1/customer_contact?select=id&source=eq.cin7&is_active=eq.true', b.contacts.length],
    ['customer_contact 기본', '/rest/v1/customer_contact?select=id&is_active=eq.true&is_default=eq.true', b.counts.contactDefault],
    ['contact 동의 true', '/rest/v1/customer_contact?select=id&is_active=eq.true&marketing_consent=eq.true', b.counts.consentTrue],
    ['contact 동의 false', '/rest/v1/customer_contact?select=id&is_active=eq.true&marketing_consent=eq.false', b.counts.consentFalse],
    ['contact 동의 null', '/rest/v1/customer_contact?select=id&is_active=eq.true&marketing_consent=is.null', b.counts.consentNull],
    ['customer currency FK 빈 곳', '/rest/v1/customer?select=id&source=eq.cin7&currency_id=is.null&currency_code=not.is.null', b.counts.missCurrency],
    ['customer location FK 빈 곳', '/rest/v1/customer?select=id&source=eq.cin7&default_location_id=is.null&default_location_name=not.is.null', b.counts.missLocation]
  ];
  var bad = 0;
  pairs.forEach(function (p) {
    var got = ilc_count_(p[1]);
    var ok = got === p[2];
    if (!ok) bad++;
    out.push((ok ? '   ✅ ' : '   ⚠️ ') + p[0] + ' : DB ' + got + ' · Cin7 기준 ' + p[2]);
  });
  out.push(bad ? '⚠️ 어긋남 ' + bad + '곳 — 붙여 달라' : '⭐ 전부 일치');
  ilc_writeReport_('verify', out);
}


/* ═══════════════════════════════════════════════════════════
   행 만들기 — 모든 단계가 같은 결과를 쓴다
   ═══════════════════════════════════════════════════════════ */

function ilc_build_() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('ILC_DONE') !== '1') throw new Error('수집이 끝나지 않았다 — imsLoadCustomerCollect 먼저');
  var folder = DriveApp.getFolderById(props.getProperty('ILC_FOLDER_ID'));

  var raw = [], files = folder.getFiles(), names = [];
  while (files.hasNext()) {
    var f = files.next();
    if (!/^pages-.*\.json$/.test(f.getName())) continue;
    names.push(f.getName());
    raw = raw.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  var rep = [];
  rep.push('=== 손님 적재 행 만들기 ' + new Date().toISOString() + ' ===');
  rep.push('파일 ' + names.sort().join(', ') + ' · 받은 행 ' + raw.length + ' · API Total ' + props.getProperty('ILC_TOTAL'));

  // ⚠️⚠️ 안전장치 1 — 받은 행 수 ≠ API Total 이면 멈춘다.
  //   수집이 짧게 끝났는데 그대로 가면, 받지 못한 손님·주소·연락처를 「Cin7 에서 사라졌다」고 보고 전부 내린다
  //   (2026-09-22 가짜 데이터 시험에서 실제로 151명을 내렸다). 수집 도중 손님이 늘거나 줄면 어긋날 수 있다 — 그때는 다시 모은다.
  var apiTotal = Number(props.getProperty('ILC_TOTAL'));
  if (!(raw.length === apiTotal)) {
    ilc_writeReport_('stop', rep.concat(['⛔ 받은 행 ' + raw.length + ' ≠ API Total ' + apiTotal +
      ' — imsLoadCustomerReset 후 imsLoadCustomerCollect 로 다시 모아라']));
    throw new Error('받은 행 ' + raw.length + ' ≠ API Total ' + apiTotal + ' — 다시 모아라');
  }

  // 참조 표 — 작은 표라 한 번씩 읽는다(그래도 캡 검사는 한다)
  var cur = ilc_mapBy_('/rest/v1/ref_currency?select=id,code', 'code');
  var term = ilc_mapBy_('/rest/v1/ref_payment_term?select=id,name', 'name');
  var acct = ilc_mapBy_('/rest/v1/ref_account?select=id,code', 'code');
  var wh = ilc_mapBy_('/rest/v1/ref_warehouse?select=id,name', 'name');

  var stop = [];
  var seen = { c: {}, a: {}, k: {} };
  var customers = [], addresses = [], contacts = [], parents = [];
  var miss = { currency: {}, term: {}, ar: {}, sale: {}, location: {} };
  var cnt = { customerActive: 0, addressDefault: 0, contactDefault: 0, consentTrue: 0, consentFalse: 0, consentNull: 0,
              missCurrency: 0, missLocation: 0, filled: 0 };
  var humanPick = [];

  raw.forEach(function (c) {
    if (seen.c[c.ID]) { stop.push('손님 ID 두 번: ' + c.ID + ' ' + c.Name); return; }
    seen.c[c.ID] = true;

    // ── 손님 ──
    var st = String(c.Status);
    if (st !== 'Active' && st !== 'Deprecated') stop.push('Status 가 둘 밖: ' + st + ' — ' + c.Name);
    var curCode = ims_blank_(c.Currency), termName = ims_blank_(c.PaymentTerm);
    var arCode = ims_blank_(c.AccountReceivable), saleCode = ims_blank_(c.RevenueAccount), loc = ims_blank_(c.Location);
    var row = {
      cin7_id: c.ID,
      name: ims_blank_(c.Name),
      display_name: ims_blank_(c.DisplayName),
      is_active: st === 'Active',
      source: 'cin7',
      currency_id: curCode ? (cur[curCode] || null) : null,
      currency_code: curCode,
      payment_term_id: termName ? (term[termName] || null) : null,
      payment_term_name: termName,
      discount_pct: (c.Discount === null || c.Discount === undefined) ? null : Number(c.Discount),
      tax_rule: ims_blank_(c.TaxRule),
      price_tier: ims_blank_(c.PriceTier),
      default_location_id: loc ? (wh[loc] || null) : null,
      default_location_name: loc,
      ar_account_id: arCode ? (acct[arCode] || null) : null,
      ar_account_code: arCode,
      sale_account_id: saleCode ? (acct[saleCode] || null) : null,
      sale_account_code: saleCode,
      is_bill_parent: c.IsBillParent === true,
      is_legal_entity: c.IsLegalEntity === true,
      default_carrier: ims_blank_(c.Carrier),
      tax_number: ims_blank_(c.TaxNumber),
      tags: ims_blank_(c.Tags),
      cin7_comments: ims_blank_(c.Comments)
    };
    if (!row.name) stop.push('이름 빈 손님(name NOT NULL): ' + c.ID);
    if (row.is_active) cnt.customerActive++;
    if (curCode && !row.currency_id) { miss.currency[curCode] = (miss.currency[curCode] || 0) + 1; cnt.missCurrency++; }
    if (termName && !row.payment_term_id) miss.term[termName] = (miss.term[termName] || 0) + 1;
    if (arCode && !row.ar_account_id) miss.ar[arCode] = (miss.ar[arCode] || 0) + 1;
    if (saleCode && !row.sale_account_id) miss.sale[saleCode] = (miss.sale[saleCode] || 0) + 1;
    if (loc && !row.default_location_id) { miss.location[loc] = (miss.location[loc] || 0) + 1; cnt.missLocation++; }
    customers.push(row);

    if (ims_blank_(c.CustomerParentID)) {
      parents.push({ child_cin7_id: c.ID, child_name: c.Name, parent_cin7_id: c.CustomerParentID });
    }

    // ── 주소 — 기본 규칙(판정 ③·⑦) ──
    var addrs = c.Addresses || [];
    var byType = {};
    addrs.forEach(function (a) {
      var t = ims_blank_(a.Type);
      if (t !== null && t !== 'Billing' && t !== 'Business' && t !== 'Shipping') stop.push('Address Type 셋 밖: ' + t + ' — ' + c.Name);
      (byType[String(t)] = byType[String(t)] || []).push(a);
    });
    var defOf = {};
    Object.keys(byType).forEach(function (t) {
      var g = byType[t];
      var chk = g.filter(function (a) { return a.DefaultForType === true; });
      if (t === 'null') { g.forEach(function (a) { defOf[a.ID] = false; }); return; }   // type 없는 줄은 기본이 될 수 없다
      if (chk.length === 1) { g.forEach(function (a) { defOf[a.ID] = a.DefaultForType === true; }); }
      else if (chk.length === 0 && g.length === 1) { defOf[g[0].ID] = true; cnt.filled++; }
      else {
        g.forEach(function (a) { defOf[a.ID] = false; });
        humanPick.push(c.Name + ' · ' + t + ' ' + g.length + '줄 · 체크 ' + chk.length);
      }
    });
    addrs.forEach(function (a) {
      if (seen.a[a.ID]) { stop.push('주소 ID 두 번: ' + a.ID); return; }
      seen.a[a.ID] = true;
      if (defOf[a.ID]) cnt.addressDefault++;
      addresses.push({
        _customer_cin7_id: c.ID,
        cin7_id: a.ID,
        is_active: true,
        source: 'cin7',
        type: ims_blank_(a.Type),
        is_default_for_type: defOf[a.ID] === true,
        line1: ims_blank_(a.Line1),
        line2: ims_blank_(a.Line2),
        city: ims_blank_(a.City),
        state_province: ims_blank_(a.State),
        postal_code: ims_blank_(a.Postcode),
        country: ims_blank_(a.Country)
      });
    });

    // ── 연락처 ──
    var ks = c.Contacts || [];
    var dcount = ks.filter(function (k) { return k.Default === true; }).length;
    if (dcount > 1) stop.push('연락처 Default 둘 이상(규칙 없음): ' + c.Name + ' (' + dcount + ')');
    ks.forEach(function (k) {
      if (seen.k[k.ID]) { stop.push('연락처 ID 두 번: ' + k.ID); return; }
      seen.k[k.ID] = true;
      var mc = k.MarketingConsent, consent;
      if (mc === 2) { consent = true; cnt.consentTrue++; }
      else if (mc === 3) { consent = false; cnt.consentFalse++; }
      else if (mc === 0 || mc === 1) { consent = null; cnt.consentNull++; }
      else { stop.push('MarketingConsent 모르는 값: ' + JSON.stringify(mc) + ' — ' + c.Name + ' / ' + k.Name); consent = null; }
      if (k.Default === true) cnt.contactDefault++;
      contacts.push({
        _customer_cin7_id: c.ID,
        cin7_id: k.ID,
        is_active: true,
        source: 'cin7',
        name: ims_blank_(k.Name),
        job_title: ims_blank_(k.JobTitle),
        phone: ims_blank_(k.Phone),
        mobile_phone: ims_blank_(k.MobilePhone),
        fax: ims_blank_(k.Fax),
        email: ims_blank_(k.Email),
        website: ims_blank_(k.Website),
        is_default: k.Default === true,
        include_in_email: k.IncludeInEmail === true,
        marketing_consent: consent,
        cin7_comment: ims_blank_(k.Comment)
      });
    });
  });

  // 부모 ID 가 이번 전량에 없으면 잇지 못한다 — 멈춘다(실측 0)
  parents.forEach(function (p) { if (!seen.c[p.parent_cin7_id]) stop.push('부모가 전량에 없다: ' + p.child_name + ' → ' + p.parent_cin7_id); });

  rep.push('');
  rep.push('보낼 행 — 손님 ' + customers.length + '(활성 ' + cnt.customerActive + ') · 주소 ' + addresses.length + ' · 연락처 ' + contacts.length + ' · 부모 잇기 ' + parents.length);
  rep.push('기본 주소 — 기본 ' + cnt.addressDefault + '줄 · 규칙으로 메운 것 ' + cnt.filled + ' · 사람이 정할 손님·type ' + humanPick.length);
  humanPick.slice(0, 30).forEach(function (s) { rep.push('   ' + s); });
  rep.push('연락처 — 기본 ' + cnt.contactDefault + ' · 동의 true ' + cnt.consentTrue + ' · false ' + cnt.consentFalse + ' · null ' + cnt.consentNull);
  rep.push('FK 못 붙은 값(원문 칸에는 남는다):');
  [['currency', miss.currency], ['payment_term', miss.term], ['ar_account', miss.ar], ['sale_account', miss.sale], ['location', miss.location]]
    .forEach(function (p) {
      var ks2 = Object.keys(p[1]);
      rep.push('   ' + p[0] + ' ' + (ks2.length ? ks2.map(function (k) { return k + ' ' + p[1][k]; }).join(' · ') : '0'));
    });

  if (stop.length) {
    rep.push('');
    rep.push('⛔ 멈춤 ' + stop.length + '건 — 아무것도 쓰지 않는다');
    stop.slice(0, 50).forEach(function (s) { rep.push('   ' + s); });
    ilc_writeReport_('stop', rep);
    throw new Error('멈춤 조건 ' + stop.length + '건 — 보고서를 보라');
  }
  return { customers: customers, addresses: addresses, contacts: contacts, parents: parents, counts: cnt, report: rep };
}


/* ═══════════════════════════════════════════════════════════
   공통
   ═══════════════════════════════════════════════════════════ */

function ilc_cin7_(pathAndQuery) {
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  while (true) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery,
      { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) { Logger.log('   429 — 65초 대기 후 재시도'); Utilities.sleep(65000); continue; }
    if (code !== 200) throw new Error('Cin7 ' + code + ' · ' + pathAndQuery + ' : ' + res.getContentText().slice(0, 300));
    return JSON.parse(res.getContentText());
  }
}

/**
 * upsert — ⭐ groupKey 가 있으면 같은 값의 줄을 한 요청에서 가르지 않는다(판정 ⑪)
 * 성공 판정은 돌아온 행 수(HTTP 200 만 믿지 않는다)
 * ⚠️ PostgREST 벌크는 모든 객체의 키가 같아야 한다 — 행 만들기가 늘 같은 키를 싣는다
 */
function ilc_upsert_(table, rows, size, groupKey, t0) {
  var chunks = [], cur = [], lastKey = null;
  rows.forEach(function (r) {
    var k = groupKey ? r[groupKey] : null;
    if (cur.length >= size && (!groupKey || k !== lastKey)) { chunks.push(cur); cur = []; }
    cur.push(r); lastKey = k;
  });
  if (cur.length) chunks.push(cur);
  var total = 0;
  for (var i = 0; i < chunks.length; i++) {
    if (t0 && Date.now() - t0 > 300000) {
      throw new Error('⏸ 시간 한도 — ' + total + '행까지 썼다. 같은 함수를 다시 실행하면 된다(upsert 라 다시 써도 같다)');
    }
    var res = ims_fetch_('/rest/v1/' + table + '?on_conflict=cin7_id', {
      method: 'post',
      headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
      payload: JSON.stringify(chunks[i])
    });
    if (res.getResponseCode() >= 300) {
      Logger.log('⚠️ ' + table + ' 묶음 ' + (i + 1) + '/' + chunks.length + ' 실패 HTTP ' + res.getResponseCode());
      Logger.log(res.getContentText().slice(0, 800));
      throw new Error('적재 중단 — 여기까지 쓰인 행 ' + total);
    }
    var back = JSON.parse(res.getContentText()).length;
    if (back !== chunks[i].length) throw new Error('⚠️ 돌아온 행 ' + back + ' ≠ 보낸 ' + chunks[i].length + ' (' + table + ' 묶음 ' + (i + 1) + ')');
    total += back;
    Logger.log('  ' + table + ' ' + (i + 1) + '/' + chunks.length + ' — 누적 ' + total);
  }
  return total;
}

/**
 * cin7_id 목록으로 PATCH — 100개씩(URL 길이) · 돌아온 행 수를 센다
 * ⚠️⚠️ 안전장치 2 — 내리기(is_active=false)가 max(20, 보낸 행의 1%)를 넘으면 멈춘다.
 *   원인을 모르는 대량 비활성은 수집 사고일 가능성이 높다. 정말 맞으면 Script Property ILC_ALLOW_BIG_DOWN=1 을 넣고
 *   다시 실행한다(한 번 통과하면 지운다).
 */
function ilc_patchIn_(table, col, ids, body, baseCount) {
  if (body.is_active === false && ids.length) {
    var limit = Math.max(20, Math.floor((baseCount || 0) * 0.01));
    var props = PropertiesService.getScriptProperties();
    if (ids.length > limit) {
      if (props.getProperty('ILC_ALLOW_BIG_DOWN') !== '1') {
        throw new Error('⛔ ' + table + ' 에서 ' + ids.length + '줄을 내리려 한다(한도 ' + limit + ') — 수집 사고인지 먼저 보라. ' +
          '맞으면 Script Property ILC_ALLOW_BIG_DOWN=1 을 넣고 다시 실행');
      }
      props.deleteProperty('ILC_ALLOW_BIG_DOWN');
      Logger.log('⚠️ ILC_ALLOW_BIG_DOWN 로 한도를 넘겨 내린다 — ' + ids.length + '줄 · 속성은 지웠다');
    }
  }
  var done = 0;
  for (var i = 0; i < ids.length; i += 100) {
    var part = ids.slice(i, i + 100);
    var res = ims_fetch_('/rest/v1/' + table + '?' + col + '=in.(' + part.join(',') + ')', {
      method: 'patch', headers: { 'Prefer': 'return=representation' }, payload: JSON.stringify(body)
    });
    if (res.getResponseCode() >= 300) throw new Error(table + ' PATCH 실패 HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
    done += JSON.parse(res.getContentText()).length;
  }
  return done;
}

/** 전부 읽기 — ⚠️ PostgREST 1,000행 캡 · Range 로 나눠 읽고 Content-Range 총계와 대조(ImsLoadProduct ipr_map_ 과 같은 안전장치) */
function ilc_readAll_(path) {
  var out = [], from = 0, step = 1000, total = null;
  while (true) {
    var res = ims_fetch_(path, { method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' } });
    if (res.getResponseCode() >= 300) throw new Error('조회 실패 ' + path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    if (total === null) {
      var hs = res.getHeaders(), cr = '';
      Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
      var m = cr.match(/\/(\d+)$/);
      total = m ? Number(m[1]) : null;
    }
    var rows = JSON.parse(res.getContentText());
    out = out.concat(rows);
    from += rows.length;
    if (!rows.length) break;
    if (total !== null && from >= total) break;
    if (total === null && rows.length < step) break;
  }
  if (total !== null && out.length < total) throw new Error('⚠️ 읽기가 잘렸다: ' + out.length + ' / ' + total + ' — 멈춘다');
  if (total === null && out.length > 0 && out.length % step === 0) throw new Error('⚠️ 총계를 못 읽었는데 정확히 ' + out.length + '행 — 캡일 수 있다. 멈춘다');
  return out;
}

function ilc_mapBy_(path, keyField) {
  var m = {};
  ilc_readAll_(path).forEach(function (r) { m[String(r[keyField])] = r.id; });
  return m;
}

/** 우리 customer 의 cin7_id → id · 수가 Cin7 과 같은지 확인 */
function ilc_customerMap_(expected) {
  var m = {};
  ilc_readAll_('/rest/v1/customer?select=id,cin7_id&source=eq.cin7').forEach(function (r) { if (r.cin7_id) m[r.cin7_id] = r.id; });
  var got = Object.keys(m).length;
  if (got < expected) throw new Error('⚠️ 우리 표의 손님 ' + got + ' < Cin7 ' + expected + ' — Apply1 을 먼저');
  return m;
}

/** 행 수만 — count=exact 의 Content-Range 총계 */
function ilc_count_(path) {
  var res = ims_fetch_(path, { method: 'get', headers: { 'Range-Unit': 'items', 'Range': '0-0', 'Prefer': 'count=exact' } });
  if (res.getResponseCode() >= 300) throw new Error('count 실패 ' + path + ' → ' + res.getResponseCode());
  var hs = res.getHeaders(), cr = '';
  Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
  var m = cr.match(/\/(\d+)$/);
  if (!m) throw new Error('Content-Range 를 못 읽었다: "' + cr + '"');
  return Number(m[1]);
}

function ilc_writeReport_(tag, lines) {
  var text = lines.join('\n');
  var folderId = PropertiesService.getScriptProperties().getProperty('ILC_FOLDER_ID');
  if (folderId) {
    DriveApp.getFolderById(folderId).createFile('report-' + tag + '-' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmmss') + '.txt', text, MimeType.PLAIN_TEXT);
  }
  for (var i = 0; i < text.length; i += 8000) Logger.log(text.slice(i, i + 8000));
}

function ilc_pad_(n) { return ('000' + n).slice(-4); }
