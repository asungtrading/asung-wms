/**
 * ImsRefLoad.gs — IMS 테스트 DB(Asung-IMS) ref_ 마스터 표 적재
 * 2026-09-11 저녁 세션에서 작성 · 실행 결과 3,481행 적재 완료
 *
 * ⚠️⚠️ 이 코드는 **테스트 DB(Asung-IMS · fazgmyvzzhqybtvtktyg)** 를 가리킨다.
 *      운영(asung-WMS)에 쓰려면 Script Properties 키를 바꿔야 한다.
 *      SUPABASE_IMS_* 는 WMS 용 키와 **다른 이름**이어야 한다 — 덮어쓰면 WMS 자동화가
 *      테스트 DB 를 보게 된다.
 *
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다.
 * ⚠️ 최상위 const 금지 (기존 프로젝트 상수와 충돌하면 프로젝트 전체가 죽는다)
 * ⚠️ 식별자는 ASCII 만 (2026-09-11 실사고: 한자 변수명 → ReferenceError)
 * ⚠️ 트리거를 걸지 마라 (20/20 한도) — 손으로 실행하는 용도다
 *
 * 필요한 Script Properties:
 *   CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY
 *   SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 *
 * 실행 순서 (각 표마다 dryRun → Apply):
 *   imsPing
 *   imsLoadSimpleRefs      → imsLoadSimpleRefsApply    (brand 415 · category 19 · unit 44)
 *   imsLoadAccount         → imsLoadAccountApply       (289)
 *   imsLoadPaymentTerm     → imsLoadPaymentTermApply   (34 · 계산 칸은 비운다)
 *   imsLoadWarehouse       → imsLoadWarehouseApply     (3)
 *   imsLoadBin             → imsLoadBinApply           (2,675 · 200행씩)
 *
 * ⚠️ 매 적재 후 SQL 로 다시 읽어 확인할 것. HTTP 201 만 보고 끝내지 마라.
 */


/* ═══════════════════════════════════════════════════════════
   공통
   ═══════════════════════════════════════════════════════════ */

/** 연결 확인 — ref_brand 에 접근되는지 */
function imsPing() {
  var res = ims_fetch_('/rest/v1/ref_brand?select=id', {
    method: 'get',
    headers: { 'Prefer': 'count=exact', 'Range': '0-0' }
  });
  Logger.log('HTTP ' + res.getResponseCode());
  Logger.log(res.getContentText().slice(0, 300));
}

/** IMS 테스트 DB(PostgREST) 호출 공통 */
function ims_fetch_(path, opts) {
  var url = getProp('SUPABASE_IMS_URL').replace(/\/+$/, '') + path;
  var key = getProp('SUPABASE_IMS_SERVICE_KEY');
  var headers = {
    'apikey': key,
    'Authorization': 'Bearer ' + key,
    'Content-Type': 'application/json'
  };
  if (opts && opts.headers) {
    Object.keys(opts.headers).forEach(function (k) { headers[k] = opts.headers[k]; });
  }
  return UrlFetchApp.fetch(url, {
    method: (opts && opts.method) || 'get',
    headers: headers,
    payload: opts && opts.payload,
    muteHttpExceptions: true
  });
}

/**
 * Cin7 ref 엔드포인트 전량
 * ⚠️ listKey 는 엔드포인트마다 다르다 — 추측하지 말고 imsPeekRaw_ 로 먼저 볼 것
 *    brand=BrandList · category=CategoryList · unit=UnitList
 *    account=AccountsList(복수형!) · paymentterm=PaymentTermList · location=LocationList
 * ⚠️ Total 을 믿지 마라 — paymentterm 은 Limit 과 같은 값을 준다. 받은 행 수로 판단한다.
 * ⚠️ sleep 2500ms — ref/location 은 27페이지라 1200ms 로는 60콜/60초를 넘는다
 */
function ims_cin7All_(path, listKey) {
  var base = 'https://inventory.dearsystems.com/ExternalApi/v2/';
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  var out = [], page = 1;
  while (true) {
    var res = UrlFetchApp.fetch(base + path + '?Page=' + page + '&Limit=100',
      { method: 'get', headers: headers, muteHttpExceptions: true });

    if (res.getResponseCode() === 429) {
      Logger.log('   429 — 65초 대기 후 재시도 (page ' + page + ')');
      Utilities.sleep(65000);
      continue;                      // 같은 페이지를 다시
    }
    if (res.getResponseCode() !== 200) {
      throw new Error(path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }

    var data = JSON.parse(res.getContentText());
    var items = data[listKey] || [];
    out = out.concat(items);
    if (items.length < 100) break;
    page++;
    Utilities.sleep(2500);
  }
  return out;
}

/** 빈 문자열을 null 로 통일 (Cin7 은 "" 와 null 을 섞어 준다) */
function ims_blank_(v) {
  if (v === null || v === undefined) return null;
  var s = String(v).trim();
  return s === '' ? null : s;
}

/** 새 엔드포인트의 응답 모양을 먼저 본다 — listKey 를 추측하지 않기 위해 */
function ims_peekRaw_(path) {
  var base = 'https://inventory.dearsystems.com/ExternalApi/v2/';
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  var res = UrlFetchApp.fetch(base + path + '?Page=1&Limit=3',
    { method: 'get', headers: headers, muteHttpExceptions: true });
  Logger.log('HTTP ' + res.getResponseCode());
  var txt = res.getContentText();
  try {
    var data = JSON.parse(txt);
    if (Array.isArray(data)) Logger.log('⭐ 최상위가 배열 · ' + data.length + '행');
    else Logger.log('최상위 키: ' + Object.keys(data).join(', '));
  } catch (e) { Logger.log('JSON 파싱 실패'); }
  Logger.log(txt.slice(0, 2000));
}

function imsPeekAccount()     { ims_peekRaw_('ref/account'); }
function imsPeekPaymentTerm() { ims_peekRaw_('ref/paymentterm'); }
function imsPeekLocation()    { ims_peekRaw_('ref/location'); }


/* ═══════════════════════════════════════════════════════════
   ref_brand · ref_category · ref_unit — Cin7 필드가 ID·Name 둘뿐
   ═══════════════════════════════════════════════════════════ */

function imsLoadSimpleRefs()      { ims_loadSimple_(true); }
function imsLoadSimpleRefsApply() { ims_loadSimple_(false); }

function ims_loadSimple_(dryRun) {
  var specs = [
    { cin7: 'ref/brand',    table: 'ref_brand',    listKey: 'BrandList' },
    { cin7: 'ref/category', table: 'ref_category', listKey: 'CategoryList' },
    { cin7: 'ref/unit',     table: 'ref_unit',     listKey: 'UnitList' }
  ];

  specs.forEach(function (s) {
    Logger.log('===== ' + s.table + ' =====');

    var items = ims_cin7All_(s.cin7, s.listKey);
    Logger.log('Cin7 에서 받은 행: ' + items.length);
    if (!items.length) { Logger.log('⚠️ 0행 — listKey 를 확인하라'); return; }
    Logger.log('첫 행 키: ' + Object.keys(items[0]).join(', '));

    var rows = items.map(function (x) {
      return { cin7_id: x.ID, name: String(x.Name), source: 'cin7' };
    });

    var seen = {}, dup = [];
    rows.forEach(function (r) { if (seen[r.name]) dup.push(r.name); else seen[r.name] = true; });
    Logger.log('이름 중복: ' + dup.length + (dup.length ? ' → ' + dup.join(' · ') : ''));

    if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
    if (dup.length) { Logger.log('⚠️ 중복이 있어 쓰지 않는다'); return; }

    var res = ims_fetch_('/rest/v1/' + s.table + '?on_conflict=name', {
      method: 'post',
      headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
      payload: JSON.stringify(rows)
    });
    Logger.log('HTTP ' + res.getResponseCode());
    if (res.getResponseCode() >= 300) { Logger.log(res.getContentText().slice(0, 500)); return; }
    Logger.log('⭐ 쓰인 행: ' + JSON.parse(res.getContentText()).length);
  });
}


/* ═══════════════════════════════════════════════════════════
   ref_account — 자연키 code · ARCHIVED 도 담는다
   ⚠️ name 유니크 없음 — 실측 중복 9개 (걸었으면 289행 전체가 막혔다)
   ⚠️ uuid 형태의 ID 가 없다 → cin7_id 는 null
   ⚠️ DisplayName · 은행 계좌 · SystemAccount* 는 담지 않는다
   ═══════════════════════════════════════════════════════════ */

function imsLoadAccount()      { ims_loadAccount_(true); }
function imsLoadAccountApply() { ims_loadAccount_(false); }

function ims_loadAccount_(dryRun) {
  var items = ims_cin7All_('ref/account', 'AccountsList');   // ⚠️ 복수형 s
  Logger.log('Cin7 에서 받은 행: ' + items.length);
  if (!items.length) { Logger.log('⚠️ 0행 — listKey 확인'); return; }

  Logger.log('첫 행 전체 키: ' + Object.keys(items[0]).join(', '));

  ['Status', 'Type', 'Class', 'ForPayments'].forEach(function (f) {
    var m = {};
    items.forEach(function (x) { var k = String(x[f]); m[k] = (m[k] || 0) + 1; });
    Logger.log(f + ' : ' + Object.keys(m).sort().map(function (k) {
      return k + '(' + m[k] + ')';
    }).join(' · '));
  });

  var seen = {}, dup = [], noCode = 0;
  items.forEach(function (x) {
    var c = x.Code;
    if (c === null || c === undefined || String(c).trim() === '') { noCode++; return; }
    if (seen[c]) dup.push(c); else seen[c] = true;
  });
  Logger.log('⭐ code 중복: ' + dup.length + (dup.length ? ' → ' + dup.join(' · ') : ''));
  Logger.log('⭐ code 빈값: ' + noCode);

  var sn = {}, dn = [];
  items.forEach(function (x) { var n = String(x.Name); if (sn[n]) dn.push(n); else sn[n] = true; });
  Logger.log('name 중복: ' + dn.length + (dn.length ? ' → ' + dn.join(' · ') : ''));

  var rows = items.filter(function (x) {
    return x.Code !== null && x.Code !== undefined && String(x.Code).trim() !== '';
  }).map(function (x) {
    return {
      cin7_id: null,                       // ref/account 에는 uuid 가 없다
      code: String(x.Code),
      name: String(x.Name),
      account_class: String(x.Class),
      account_type: x.Type === null || x.Type === undefined ? null : String(x.Type),
      for_payments: x.ForPayments === true || String(x.ForPayments) === 'true',
      is_active: String(x.Status) === 'ACTIVE',
      note: x.Description ? String(x.Description) : null,
      source: 'cin7'
    };
  });
  Logger.log('표에 넣을 행: ' + rows.length);
  Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (dup.length) { Logger.log('⚠️ code 중복이 있어 쓰지 않는다'); return; }

  var res = ims_fetch_('/rest/v1/ref_account?on_conflict=code', {
    method: 'post',
    headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
    payload: JSON.stringify(rows)
  });
  Logger.log('HTTP ' + res.getResponseCode());
  if (res.getResponseCode() >= 300) { Logger.log(res.getContentText().slice(0, 800)); return; }
  Logger.log('⭐ 쓰인 행: ' + JSON.parse(res.getContentText()).length);
}


/* ═══════════════════════════════════════════════════════════
   ref_payment_term — 1단계: 이름만 넣는다
   ⚠️⚠️ Duration 은 담지 않는다 — 같은 칸에 기일·할인 기한·0 세 가지가 섞여 있다
        실물: "1% Warehouse Allowance + 2%10 Net30" 의 Duration 이 10
   ⚠️ net_days · discount_days · discount_percent · is_split 은 2단계에서 사람이 채운다
   ⚠️ Method(전부 'number of days') · IsDefault(inv_config 영역) 는 담지 않는다
   ═══════════════════════════════════════════════════════════ */

function imsLoadPaymentTerm()      { ims_loadPaymentTerm_(true); }
function imsLoadPaymentTermApply() { ims_loadPaymentTerm_(false); }

function ims_loadPaymentTerm_(dryRun) {
  var items = ims_cin7All_('ref/paymentterm', 'PaymentTermList');
  Logger.log('Cin7 에서 받은 행: ' + items.length);
  if (!items.length) { Logger.log('⚠️ 0행'); return; }

  Logger.log('첫 행 키: ' + Object.keys(items[0]).join(', '));

  ['Method', 'IsActive', 'IsDefault'].forEach(function (f) {
    var m = {};
    items.forEach(function (x) { var k = String(x[f]); m[k] = (m[k] || 0) + 1; });
    Logger.log(f + ' : ' + Object.keys(m).sort().map(function (k) {
      return k + '(' + m[k] + ')';
    }).join(' · '));
  });

  var seen = {}, dup = [];
  items.forEach(function (x) {
    var n = String(x.Name);
    if (seen[n]) dup.push(n); else seen[n] = true;
  });
  Logger.log('⭐ name 중복: ' + dup.length + (dup.length ? ' → ' + dup.join(' · ') : ''));

  // ⚠️ Duration 은 표에 안 들어간다 — 사람이 손으로 채울 때 참고용으로만 찍는다
  Logger.log('');
  Logger.log('이름 / Duration / 활성  (⚠️ Duration 은 표에 안 들어간다)');
  items.slice().sort(function (a, b) {
    return String(a.Name).localeCompare(String(b.Name));
  }).forEach(function (x) {
    Logger.log('  ' + String(x.Name) + '  |  ' + x.Duration + '  |  ' + (x.IsActive ? '활성' : '비활성'));
  });

  var rows = items.map(function (x) {
    return {
      cin7_id: x.ID,
      name: String(x.Name),
      is_active: x.IsActive === true,
      source: 'cin7'
      // net_days · discount_days · discount_percent · is_split 은 넣지 않는다 (2단계)
    };
  });
  Logger.log('');
  Logger.log('표에 넣을 행: ' + rows.length);

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (dup.length) { Logger.log('⚠️ name 중복이 있어 쓰지 않는다'); return; }

  var res = ims_fetch_('/rest/v1/ref_payment_term?on_conflict=name', {
    method: 'post',
    headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
    payload: JSON.stringify(rows)
  });
  Logger.log('HTTP ' + res.getResponseCode());
  if (res.getResponseCode() >= 300) { Logger.log(res.getContentText().slice(0, 800)); return; }
  Logger.log('⭐ 쓰인 행: ' + JSON.parse(res.getContentText()).length);
}


/* ═══════════════════════════════════════════════════════════
   ref_warehouse — ParentID 없는 행만(창고 3)
   ⚠️ IN_TRANSIT 은 Cin7 에 없다 (원장의 합성 창고)
   ⚠️ Production Facility 는 담되 is_active=false
   ⚠️ 표에 is_staging 칸이 없다 (bin 에만 있다)
   ⚠️ FixedAssetsLocation · IsCoMan · IsShopFloor · PickZones · Bins 는 담지 않는다
   ═══════════════════════════════════════════════════════════ */

function imsLoadWarehouse()      { ims_loadWarehouse_(true); }
function imsLoadWarehouseApply() { ims_loadWarehouse_(false); }

function ims_loadWarehouse_(dryRun) {
  var all = ims_cin7All_('ref/location', 'LocationList');
  Logger.log('전체 행: ' + all.length);

  var wh = all.filter(function (x) { return !x.ParentID; });
  var bins = all.filter(function (x) { return !!x.ParentID; });
  Logger.log('창고(ParentID 없음): ' + wh.length + ' · bin: ' + bins.length);

  Logger.log('');
  wh.forEach(function (x) {
    Logger.log('  ' + x.Name + '  | default=' + x.IsDefault + ' | deprecated=' + x.IsDeprecated +
      ' | 주소=' + JSON.stringify([
        x.AddressLine1, x.AddressCitySuburb, x.AddressStateProvince,
        x.AddressZipPostCode, x.AddressCountry
      ]));
    Logger.log('     ID: ' + x.ID);
  });

  var rows = wh.map(function (x) {
    return {
      cin7_id: x.ID,
      name: String(x.Name),
      is_default: x.IsDefault === true,
      address_line1: ims_blank_(x.AddressLine1),
      address_line2: ims_blank_(x.AddressLine2),
      city: ims_blank_(x.AddressCitySuburb),
      state_province: ims_blank_(x.AddressStateProvince),
      postal_code: ims_blank_(x.AddressZipPostCode),
      country: ims_blank_(x.AddressCountry),
      is_active: x.IsDeprecated !== true && String(x.Name) !== 'Production Facility',
      source: 'cin7'
    };
  });
  Logger.log('');
  Logger.log('표에 넣을 행: ' + rows.length);
  Logger.log(JSON.stringify(rows, null, 1));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }

  var res = ims_fetch_('/rest/v1/ref_warehouse?on_conflict=name', {
    method: 'post',
    headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
    payload: JSON.stringify(rows)
  });
  Logger.log('HTTP ' + res.getResponseCode());
  if (res.getResponseCode() >= 300) { Logger.log(res.getContentText().slice(0, 800)); return; }
  Logger.log('⭐ 쓰인 행: ' + JSON.parse(res.getContentText()).length);
}


/* ═══════════════════════════════════════════════════════════
   ref_bin — ParentID 있는 행(2,675)
   ⚠️ warehouse_id 는 우리 ref_warehouse.id — Cin7 ParentID 를 우리 id 로 바꾼다
      ⭐ 창고 uuid 를 코드에 박지 마라. 표에서 읽는다 (DB 를 다시 만들면 uuid 가 바뀐다)
   ⚠️ zone 은 채우지 않는다 (채우는 방법 미정 — wms_sku_bins 를 읽으면 원칙 2 위반)
   ⚠️ 200행씩 나눠 보낸다 · upsert 라 다시 돌려도 중복되지 않는다
   ⚠️ 2,675행 — PostgREST 1,000행 캡을 넘는 첫 실물. 읽을 때 주의.
   ═══════════════════════════════════════════════════════════ */

function imsLoadBin()      { ims_loadBin_(true); }
function imsLoadBinApply() { ims_loadBin_(false); }

function ims_loadBin_(dryRun) {
  // 1) 창고 대응표 — 우리 표에서 읽는다 (하드코딩 금지)
  var res0 = ims_fetch_('/rest/v1/ref_warehouse?select=id,cin7_id,name', { method: 'get' });
  if (res0.getResponseCode() !== 200) {
    Logger.log('창고 조회 실패 ' + res0.getResponseCode() + ': ' + res0.getContentText().slice(0, 300));
    return;
  }
  var whRows = JSON.parse(res0.getContentText());
  var map = {};
  whRows.forEach(function (w) { map[w.cin7_id] = w.id; });
  Logger.log('창고 대응표: ' + whRows.length + '개');

  // 2) Cin7 전량에서 bin 만
  var all = ims_cin7All_('ref/location', 'LocationList');
  var bins = all.filter(function (x) { return !!x.ParentID; });
  Logger.log('bin: ' + bins.length);

  // 3) 부모가 우리 표에 있는지 — 없으면 FK 가 깨진다
  var orphan = bins.filter(function (x) { return !map[x.ParentID]; });
  Logger.log('⭐ 부모 창고를 못 찾은 bin: ' + orphan.length);
  if (orphan.length) {
    var byParent = {};
    orphan.forEach(function (x) { byParent[x.ParentID] = (byParent[x.ParentID] || 0) + 1; });
    Object.keys(byParent).forEach(function (k) { Logger.log('   ' + k + ' : ' + byParent[k] + '개'); });
  }

  var cnt = {};
  bins.forEach(function (x) {
    var id = map[x.ParentID];
    var nm = (whRows.filter(function (w) { return w.id === id; })[0] || {}).name || '(모름)';
    cnt[nm] = (cnt[nm] || 0) + 1;
  });
  Logger.log('창고별 bin: ' + Object.keys(cnt).sort().map(function (k) {
    return k + ' ' + cnt[k];
  }).join(' · '));

  // 복합 자연키 (warehouse_id, name) 중복
  var seen = {}, dup = [];
  bins.forEach(function (x) {
    var k = x.ParentID + '|' + String(x.Name);
    if (seen[k]) dup.push(k); else seen[k] = true;
  });
  Logger.log('⭐ (창고,이름) 중복: ' + dup.length);

  // ⚠️ 창고를 넘나드는 같은 이름 — 0 은 오늘의 사실이지 규칙이 아니다
  var byName = {};
  bins.forEach(function (x) { (byName[String(x.Name)] = byName[String(x.Name)] || []).push(x.ParentID); });
  var crossWh = Object.keys(byName).filter(function (n) { return byName[n].length > 1; });
  Logger.log('참고: 창고를 넘나드는 같은 이름: ' + crossWh.length +
    (crossWh.length ? ' → ' + crossWh.slice(0, 5).join(' · ') : ''));

  var rows = bins.filter(function (x) { return !!map[x.ParentID]; }).map(function (x) {
    return {
      cin7_id: x.ID,
      warehouse_id: map[x.ParentID],
      name: String(x.Name),
      is_staging: x.IsStaging === true,
      is_active: x.IsDeprecated !== true,
      source: 'cin7'
      // zone 은 넣지 않는다
    };
  });
  Logger.log('표에 넣을 행: ' + rows.length);
  Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (dup.length) { Logger.log('⚠️ 복합키 중복이 있어 쓰지 않는다'); return; }

  // 4) 200행씩
  var total = 0;
  for (var i = 0; i < rows.length; i += 200) {
    var chunk = rows.slice(i, i + 200);
    var res = ims_fetch_('/rest/v1/ref_bin?on_conflict=warehouse_id,name', {
      method: 'post',
      headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
      payload: JSON.stringify(chunk)
    });
    if (res.getResponseCode() >= 300) {
      Logger.log('⚠️ ' + i + '번째 묶음 실패 HTTP ' + res.getResponseCode());
      Logger.log(res.getContentText().slice(0, 800));
      Logger.log('여기까지 쓰인 행: ' + total);
      return;
    }
    total += JSON.parse(res.getContentText()).length;
    Logger.log('  ' + (i + chunk.length) + ' / ' + rows.length + ' — 누적 ' + total);
  }
  Logger.log('⭐ 쓰인 행: ' + total);
}
