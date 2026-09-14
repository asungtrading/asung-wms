/**
 * ImsLoadProduct.gs — IMS ③ 제품 적재 (product_family · product)
 *
 * ⚠️ 최상위 const 금지 · 식별자 ASCII 만
 * ⚠️ ims_fetch_ · ims_blank_ · ims_cin7All_ 은 ImsLoad.gs 것을 쓴다
 * ⚠️ 대상: [테스트 · Asung-IMS]
 *
 * 정본: docs/design/po-module.md §3-d
 *  · 담는 범위 Type='Stock' · 단 UOM='EA-ALT-UPC' 이고 BOM Quantity=1 인 59건은 제외
 *    (그 59 는 product_barcode 로 흡수한다 · BOM 이 1 이 아닌 둘은 세트일 수 있어 남긴다)
 *  · AS91437-BLK 는 Type=Non Inventory 지만 실물은 자재다 → imsLoadProductExtraApply() 로 따로
 *  · parent_product_id · pack_factor 는 1단계에서 보내지 않는다 (2단계 · 낱개가 먼저 다 있어야 한다)
 *  · family_id · option1~3_value 는 GET /productFamily 의 Products[] 에서만 온다
 *
 * 실행 순서
 *   1) imsLoadProductFamily()        확인만
 *   2) imsLoadProductFamilyApply()   쓴다 (1,141)
 *   3) imsLoadProduct()              확인만 (첫 페이지만 훑는다)
 *   4) imsLoadProductApply()         쓴다 (⏸ 나오면 다시 호출 · 커서는 Script Property)
 *   5) imsLoadProductExtraApply()    ⭐ AS91437-BLK 한 건
 *   보조) imsLoadProductReset()      커서를 지운다
 */

var IPR_PROP_CURSOR = 'IPR_PRODUCT_PAGE';
var IPR_LIMIT       = 500;    // BOM 을 켜면 1000 이 안 온다 (2026-09-13 실측)
var IPR_CHUNK       = 500;    // PostgREST 로 보내는 묶음
var IPR_THROTTLE    = 2500;
var IPR_MAX_RUN     = 4.5 * 60 * 1000;

// ─────────────────────────────────────────────────────────────
// Cin7 — 한 페이지 (ims_cin7All_ 은 파라미터를 못 넣는다)
// ─────────────────────────────────────────────────────────────
function ipr_cin7_(path, params) {
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  var qs = Object.keys(params || {}).map(function (k) {
    return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
  }).join('&');
  while (true) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + path + (qs ? '?' + qs : ''),
      { method: 'get', headers: headers, muteHttpExceptions: true });
    if (res.getResponseCode() === 429) {
      Logger.log('   429 — 65초 대기 후 재시도');
      Utilities.sleep(65000);
      continue;
    }
    if (res.getResponseCode() !== 200) {
      throw new Error(path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }
    return JSON.parse(res.getContentText());
  }
}

/**
 * ⚠️⚠️ 우리 표에서 대응표를 만든다 — PostgREST 1,000행 캡을 넘기지 마라
 *    product_family 는 1,141행이다. select 한 번으로 읽으면 조용히 1,000 에서 잘리고
 *    나머지 141 군의 제품들이 family_id 없이 들어간다(에러 없음 · 과거 사고 5건).
 *    ⇒ Range 헤더로 나눠 읽고, 마지막에 Content-Range 의 총계와 대조한다.
 */
function ipr_map_(path, keyField) {
  var out = {}, from = 0, step = 1000, total = null;
  while (true) {
    var res = ims_fetch_(path, {
      method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' }
    });
    if (res.getResponseCode() >= 300) {
      throw new Error('조회 실패 ' + path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }
    // ⚠️ 헤더 이름의 대소문자가 환경마다 다르다 — 찾아서 읽는다(못 읽으면 NaN 이 되고 검사가 통째로 건너뛰어진다)
    if (total === null) {
      var hs = res.getHeaders(), cr = '';
      Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
      var m = cr.match(/\/(\d+)$/);
      total = m ? Number(m[1]) : null;
      if (total === null) Logger.log('  ⚠️ Content-Range 를 못 읽었다 (' + path + ') — 총계 대조 없이 진행한다: "' + cr + '"');
    }
    var rows = JSON.parse(res.getContentText());
    rows.forEach(function (r) { out[String(r[keyField])] = r.id; });
    from += rows.length;
    if (!rows.length) break;
    if (total !== null && from >= total) break;
    if (total === null && rows.length < step) break;   // 총계를 모르면 「덜 왔으면 끝」으로 판정
  }
  var got = Object.keys(out).length;
  Logger.log('  ' + path + ' → ' + got + (total === null ? ' / 총계 미확인' : ' / 원격 총계 ' + total));
  // ⚠️⚠️ 안전장치 — 캡에 잘렸는데 모르고 지나가면 FK 가 조용히 null 로 들어간다(과거 사고 5건)
  if (total !== null && got < total) {
    throw new Error('⚠️ 대응표가 잘렸다: ' + got + ' / ' + total + ' — 멈춘다');
  }
  if (total === null && got % step === 0 && got > 0) {
    throw new Error('⚠️ 총계를 못 읽었는데 받은 행이 정확히 ' + got + ' 이다 — 캡에 걸렸을 수 있다. 멈춘다');
  }
  return out;
}

/** 묶음으로 upsert. 성공 판정은 돌아온 행 수로 한다(HTTP 200 만 믿지 않는다) */
function ipr_upsert_(table, conflictCols, rows) {
  var total = 0;
  for (var i = 0; i < rows.length; i += IPR_CHUNK) {
    var chunk = rows.slice(i, i + IPR_CHUNK);
    var res = ims_fetch_('/rest/v1/' + table + '?on_conflict=' + conflictCols, {
      method: 'post',
      headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
      payload: JSON.stringify(chunk)
    });
    if (res.getResponseCode() >= 300) {
      Logger.log('⚠️ ' + i + '번째 묶음 실패 HTTP ' + res.getResponseCode());
      Logger.log(res.getContentText().slice(0, 800));
      Logger.log('여기까지 쓰인 행: ' + total);
      throw new Error('적재 중단');
    }
    total += JSON.parse(res.getContentText()).length;
    Logger.log('  ' + (i + chunk.length) + ' / ' + rows.length + ' — 누적 ' + total);
  }
  return total;
}

// ─────────────────────────────────────────────────────────────
// 1) product_family — 1,141
// ─────────────────────────────────────────────────────────────
function imsLoadProductFamily()      { ipr_loadFamily_(true); }
function imsLoadProductFamilyApply() { ipr_loadFamily_(false); }

function ipr_loadFamily_(dryRun) {
  // ⚠️ Limit=100 인 ims_cin7All_ 로 12페이지 — 파라미터가 필요 없으니 재사용한다
  var items = ims_cin7All_('productFamily', 'ProductFamilies');
  Logger.log('Cin7 제품군: ' + items.length + ' (정본 기대치 1,141)');
  if (!items.length) { Logger.log('⚠️ 0행 — 멈춘다'); return; }

  var brands = ipr_map_('/rest/v1/ref_brand?select=id,name',    'name');
  var cats   = ipr_map_('/rest/v1/ref_category?select=id,name', 'name');
  var units  = ipr_map_('/rest/v1/ref_unit?select=id,name',     'name');

  var missB = [], missC = [], missU = [];
  var rows = items.map(function (f) {
    var bn = ims_blank_(f.Brand), cn = ims_blank_(f.Category), un = ims_blank_(f.UOM);
    if (bn && !brands[bn]) missB.push(f.SKU + ' → "' + bn + '"');
    if (cn && !cats[cn])   missC.push(f.SKU + ' → "' + cn + '"');
    if (un && !units[un])  missU.push(f.SKU + ' → "' + un + '"');
    return {
      cin7_id: f.ID,
      sku: String(f.SKU).trim(),
      name: String(f.Name),
      is_active: true,
      source: 'cin7',
      brand_id: bn ? (brands[bn] || null) : null,
      brand_name: bn,
      category_id: cn ? (cats[cn] || null) : null,
      category_name: cn,
      unit_id: un ? (units[un] || null) : null,
      uom_name: un,
      option1_name: ims_blank_(f.Option1Name),
      option2_name: ims_blank_(f.Option2Name),
      option3_name: ims_blank_(f.Option3Name),
      costing_method: ims_blank_(f.CostingMethod),
      cin7_description: ims_blank_(f.Description),
      cin7_modified_on: f.LastModifiedOn || null
    };
  });

  Logger.log('⭐ FK 못 붙은 곳 — 브랜드 ' + missB.length + ' · 카테고리 ' + missC.length + ' · 단위 ' + missU.length);
  [['브랜드', missB], ['카테고리', missC], ['단위', missU]].forEach(function (p) {
    if (p[1].length) { Logger.log(' -- ' + p[0]); p[1].slice(0, 20).forEach(function (x) { Logger.log('    ' + x); }); }
  });

  // 자연키 중복 — 걸리면 배치 전체가 실패한다
  var seen = {}, dup = [];
  rows.forEach(function (r) { if (seen[r.sku]) dup.push(r.sku); else seen[r.sku] = true; });
  Logger.log('sku 중복: ' + dup.length + (dup.length ? ' → ' + dup.join(' · ') : ''));
  Logger.log('FAM 으로 안 끝나는 것: ' + rows.filter(function (r) { return !/FAM$/i.test(r.sku); }).length);
  Logger.log('표에 넣을 행: ' + rows.length);
  Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (dup.length) { Logger.log('⚠️ sku 중복이 있어 쓰지 않는다'); return; }

  Logger.log('⭐ 쓰인 행: ' + ipr_upsert_('product_family', 'sku', rows));
}

// ─────────────────────────────────────────────────────────────
// 2) product — 18,715 (Type=Stock · EA-ALT-UPC 이면서 BOM=1 인 59 제외)
//    ⏸ 6분 한도에 걸리면 커서를 저장하고 멈춘다. 다시 호출하면 이어간다.
// ─────────────────────────────────────────────────────────────
function imsLoadProduct()      { ipr_loadProduct_(true); }
function imsLoadProductApply() { ipr_loadProduct_(false); }

function imsLoadProductReset() {
  PropertiesService.getScriptProperties().deleteProperty(IPR_PROP_CURSOR);
  Logger.log('커서를 지웠다. imsLoadProductApply() 부터 다시.');
}

function ipr_loadProduct_(dryRun) {
  var t0 = new Date().getTime();
  var props = PropertiesService.getScriptProperties();
  var page = Number(props.getProperty(IPR_PROP_CURSOR) || '1');

  // 대응표 — ⚠️ product_family 는 1,141 이라 캡을 넘는다
  var brands = ipr_map_('/rest/v1/ref_brand?select=id,name',    'name');
  var cats   = ipr_map_('/rest/v1/ref_category?select=id,name', 'name');
  var units  = ipr_map_('/rest/v1/ref_unit?select=id,name',     'name');
  var accts  = ipr_map_('/rest/v1/ref_account?select=id,code',  'code');
  var fams   = ipr_map_('/rest/v1/product_family?select=id,sku', 'sku');

  // ⭐ family_id · option 값의 유일한 출처 — 제품 응답에는 이 고리가 없다
  var famItems = ims_cin7All_('productFamily', 'ProductFamilies');
  var famOf = {};
  famItems.forEach(function (f) {
    (f.Products || []).forEach(function (p) {
      famOf[String(p.SKU)] = {
        famSku: String(f.SKU).trim(),
        o1: ims_blank_(p.Option1), o2: ims_blank_(p.Option2), o3: ims_blank_(p.Option3)
      };
    });
  });
  Logger.log('family 대응: 제품군 ' + famItems.length + ' · 변형 ' + Object.keys(famOf).length);

  var stopped = '끝까지 돌았다';
  var seenTotal = 0, wrote = 0, skipped = { type: 0, altupc: 0 }, missFam = [], missAcct = {};

  while (true) {
    if (new Date().getTime() - t0 > IPR_MAX_RUN) {
      stopped = '⏸ 시간 한도 — imsLoadProductApply() 를 다시 호출하면 이어간다';
      break;
    }
    var res = ipr_cin7_('product', {
      Page: page, Limit: IPR_LIMIT, IncludeDeprecated: true, IncludeBOM: true
    });
    var items = res.Products || [];
    if (!items.length) break;
    seenTotal += items.length;

    var rows = [];
    items.forEach(function (p) {
      if (String(p.Type) !== 'Stock') { skipped.type++; return; }
      var uom = String(p.UOM || '');
      var bom = p.BillOfMaterialsProducts || [];
      // ⚠️ 흡수 조건은 UOM 이 EA-ALT-UPC 「그리고」 BOM Quantity=1 인 것뿐
      if (uom === 'EA-ALT-UPC' && bom.length === 1 && Number(bom[0].Quantity) === 1) {
        skipped.altupc++; return;
      }
      rows.push(ipr_row_(p, brands, cats, units, accts, fams, famOf, missFam, missAcct));
    });

    if (dryRun) {
      Logger.log('페이지 ' + page + ' — 받은 ' + items.length + ' · 넣을 ' + rows.length);
      Logger.log('표본 1: ' + JSON.stringify(rows[0]));
      Logger.log('(dryRun — 첫 페이지만 보고 멈춘다)');
      return;
    }

    if (rows.length) wrote += ipr_upsert_('product', 'sku', rows);
    page += 1;
    props.setProperty(IPR_PROP_CURSOR, String(page));

    if (items.length < IPR_LIMIT) break;
    Utilities.sleep(IPR_THROTTLE);
  }

  Logger.log('');
  Logger.log(stopped + ' · 이번에 본 행 ' + seenTotal + ' · 쓴 행 ' + wrote + ' · 다음 페이지 ' + page);
  Logger.log('건너뜀 — Stock 아님 ' + skipped.type + ' · EA-ALT-UPC(BOM=1) ' + skipped.altupc);
  Logger.log('⚠️ family 못 찾음: ' + missFam.length + (missFam.length ? ' → ' + missFam.slice(0, 10).join(' · ') : ''));
  var ma = Object.keys(missAcct);
  Logger.log('⚠️ 계정 못 이음: ' + ma.length + (ma.length ? ' → ' + ma.slice(0, 10).join(' · ') : ''));
}

function ipr_row_(p, brands, cats, units, accts, fams, famOf, missFam, missAcct) {
  var bn = ims_blank_(p.Brand), cn = ims_blank_(p.Category), un = ims_blank_(p.UOM);
  var fam = famOf[String(p.SKU)] || null;
  var famId = null;
  if (fam) {
    famId = fams[fam.famSku] || null;
    if (!famId && missFam.length < 50) missFam.push(p.SKU + ' → ' + fam.famSku);
  }
  function acct(code) {
    var c = ims_blank_(code);
    if (!c) return [null, null];
    var id = accts[c] || null;
    if (!id) missAcct[c] = true;
    return [id, c];
  }
  var ia = acct(p.InventoryAccount), ca = acct(p.COGSAccount);
  var ra = acct(p.RevenueAccount),   ea = acct(p.ExpenseAccount);
  var a3 = ims_blank_(p.AdditionalAttribute3);

  return {
    cin7_id: p.ID,
    sku: String(p.SKU).trim(),
    name: String(p.Name),
    is_active: String(p.Status) === 'Active',
    source: 'cin7',

    family_id: famId,
    option1_value: fam ? fam.o1 : null,
    option2_value: fam ? fam.o2 : null,
    option3_value: fam ? fam.o3 : null,
    // ⚠️ parent_product_id · pack_factor 는 2단계 (낱개가 먼저 다 있어야 한다)

    brand_id: bn ? (brands[bn] || null) : null,
    brand_name: bn,
    category_id: cn ? (cats[cn] || null) : null,
    category_name: cn,
    unit_id: un ? (units[un] || null) : null,
    uom_name: un,

    inventory_account_id: ia[0], inventory_account_code: ia[1],
    cogs_account_id:      ca[0], cogs_account_code:      ca[1],
    revenue_account_id:   ra[0], revenue_account_code:   ra[1],
    expense_account_id:   ea[0], expense_account_code:   ea[1],

    purchase_tax_rule: ims_blank_(p.PurchaseTaxRule),
    sale_tax_rule:     ims_blank_(p.SaleTaxRule),

    cin7_type: ims_blank_(p.Type),
    sellable: p.Sellable === true,
    costing_method: ims_blank_(p.CostingMethod),
    hs_code: ims_blank_(p.HSCode),
    country_of_origin: ims_blank_(p.CountryOfOrigin),
    country_of_origin_code: ims_blank_(p.CountryOfOriginCode),
    weight: (p.Weight === null || p.Weight === undefined || p.Weight === '') ? null : Number(p.Weight),
    weight_unit: ims_blank_(p.WeightUnits),
    cin7_description: ims_blank_(p.Description),
    cin7_internal_note: ims_blank_(p.InternalNote),
    cin7_created_on: p.CreatedDate || null,
    cin7_modified_on: p.LastModifiedOn || null,

    // ⭐ 슬롯3 을 갈라 담는다 — 한 칸에 두 축이 살던 것
    is_discontinued: a3 === 'Discontinued',
    cin7_project_name: a3,
    // 슬롯4 — ⚠️ CreatedDate 로 복원되지 않는다(7할이 다르다)
    registered_on: ims_blank_(p.AdditionalAttribute4)
  };
}

// ─────────────────────────────────────────────────────────────
// 3) ⭐ AS91437-BLK 한 건 — 규칙 밖이라 따로 넣는다
//    Type=Non Inventory 로 앉아 있지만 실물은 AS91437 을 만드는 벌크 자재다(Caleb 2026-09-13).
//    ⚠️ 본체 적재는 규칙대로만 돌리고 이 예외는 여기서만 처리한다 —
//       SKU 를 본 함수에 박으면 다음 사람이 규칙을 오해한다.
// ─────────────────────────────────────────────────────────────
function imsLoadProductExtra()      { ipr_loadExtra_(true); }
function imsLoadProductExtraApply() { ipr_loadExtra_(false); }

function ipr_loadExtra_(dryRun) {
  var sku = 'AS91437-BLK';
  var res = ipr_cin7_('product', { Sku: sku, Limit: 1, IncludeDeprecated: true, IncludeBOM: true });
  var items = (res.Products || []).filter(function (p) { return String(p.SKU) === sku; });
  if (!items.length) { Logger.log('⚠️ ' + sku + ' 을 못 찾았다 — 멈춘다'); return; }
  var p = items[0];
  Logger.log('찾았다: ' + p.SKU + ' · Type=' + p.Type + ' · Status=' + p.Status + ' · ' + p.Name);

  var brands = ipr_map_('/rest/v1/ref_brand?select=id,name',    'name');
  var cats   = ipr_map_('/rest/v1/ref_category?select=id,name', 'name');
  var units  = ipr_map_('/rest/v1/ref_unit?select=id,name',     'name');
  var accts  = ipr_map_('/rest/v1/ref_account?select=id,code',  'code');
  var fams   = ipr_map_('/rest/v1/product_family?select=id,sku', 'sku');

  var row = ipr_row_(p, brands, cats, units, accts, fams, {}, [], {});
  row.note = '⚠️ Cin7 Type=Non Inventory 이나 실물은 AS91437 을 만드는 벌크 자재 (Caleb 2026-09-13)';
  Logger.log(JSON.stringify(row));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  Logger.log('⭐ 쓰인 행: ' + ipr_upsert_('product', 'sku', [row]));
}

// ─────────────────────────────────────────────────────────────
// 4) ⭐ 2단계 — parent_product_id · pack_factor 를 잇는다
//
//    ⚠️⚠️ 정본은 BOM 이다 (2026-09-13 2차 실측으로 확정)
//      parent  = BillOfMaterialsProducts[0].ComponentProductID  (GUID)
//      factor  = BillOfMaterialsProducts[0].Quantity
//      ⚠️ SKU 접미사와 UOM 이름은 **검산으로만** 쓴다.
//         BOM 은 「이 세트 하나를 만들려면 낱개가 몇 개 드는가」이고 Cin7 이 재고를 빼는 것도 BOM 이다.
//         UOM 이름은 화면 표시일 뿐 — 둘이 어긋나면 화면은 6개라 하고 재고는 1개가 빠진다(에러 없음).
//         실물: AIA00207-6 · ORS12208-6 이 UOM=6 인데 BOM=1 이었다 (Caleb 이 Cin7 에서 수정)
//
//    ⭐ 왜 1단계와 나누는가 — parent_product_id 는 자기 표를 가리키는 FK 다.
//       낱개가 먼저 다 들어가 있어야 이어진다. 18,714 가 확정된 지금이 그 자리다.
//
//    ⚠️ 구성품이 2개 이상인 것(콤보 15)은 여기서 건드리지 않는다 — product_bom 의 몫이다.
//    ⚠️ 대체 UPC 로 흡수된 59 는 product 에 없으므로 저절로 빠진다.
//
//    ⭐ 오타 탐지기 셋 — 평상시 0 이어야 신호가 산다
//       ① 구성품 1개인데 그 GUID 가 우리 표에 없음
//       ② 세트의 uom_name(숫자) ≠ pack_factor(BOM)      ⚠️ 재고가 조용히 틀어지는 자리
//       ③ 접미사로 찾은 부모 ≠ BOM 으로 찾은 부모
// ─────────────────────────────────────────────────────────────
function imsLinkProductSets()      { ipr_linkSets_(true); }
function imsLinkProductSetsApply() { ipr_linkSets_(false); }

function ipr_linkSets_(dryRun) {
  var t0 = new Date().getTime();

  // 우리 표의 cin7_id → {id, sku, uom} · ⚠️ 18,714 행이라 캡을 크게 넘는다
  var byCin7 = {}, bySku = {}, mapped = 0, from = 0, step = 1000, total = null;
  while (true) {
    var res = ims_fetch_('/rest/v1/product?select=id,cin7_id,sku,uom_name', {
      method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' }
    });
    if (res.getResponseCode() >= 300) {
      throw new Error('product 조회 실패 ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }
    if (total === null) {
      var hs = res.getHeaders(), cr = '';
      Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
      var m = cr.match(/\/(\d+)$/);
      total = m ? Number(m[1]) : null;
    }
    var rows = JSON.parse(res.getContentText());
    rows.forEach(function (r) {
      var o = { id: r.id, sku: String(r.sku), uom: r.uom_name === null ? '' : String(r.uom_name) };
      if (r.cin7_id) byCin7[String(r.cin7_id)] = o;
      bySku[o.sku] = o;
      mapped++;
    });
    from += rows.length;
    if (!rows.length) break;
    if (total !== null && from >= total) break;
    if (total === null && rows.length < step) break;
  }
  Logger.log('product 대응표: ' + mapped + (total === null ? ' / 총계 미확인' : ' / 원격 총계 ' + total));
  if (total !== null && mapped < total) throw new Error('⚠️ 대응표가 잘렸다: ' + mapped + ' / ' + total);

  // Cin7 전량을 BOM 켜고 훑으며 구성품 1개짜리만 모은다
  var page = 1, links = [], seen = 0;
  var badGuid = [], uomMismatch = [], sufMismatch = [], multi = 0, noBom = 0, notOurs = 0;

  while (true) {
    if (new Date().getTime() - t0 > IPR_MAX_RUN) {
      Logger.log('⏸ 시간 한도 — 여기까지 모은 것만 처리한다. 다시 호출하면 처음부터 다시 훑는다(멱등)');
      break;
    }
    var r = ipr_cin7_('product', { Page: page, Limit: IPR_LIMIT, IncludeDeprecated: true, IncludeBOM: true });
    var items = r.Products || [];
    if (!items.length) break;
    seen += items.length;

    items.forEach(function (p) {
      var bom = p.BillOfMaterialsProducts || [];
      if (!bom.length) { noBom++; return; }
      if (bom.length >= 2) { multi++; return; }        // 콤보 — product_bom 의 몫

      var me = byCin7[String(p.ID)];
      if (!me) { notOurs++; return; }                  // 대체 UPC 로 흡수된 59 등

      var c = bom[0];
      var parent = byCin7[String(c.ComponentProductID)];
      if (!parent) {
        if (badGuid.length < 30) badGuid.push(me.sku + ' → ' + c.ProductCode + ' (' + c.ComponentProductID + ')');
        return;                                        // ⚠️ FK 가 끊기므로 보내지 않는다
      }

      var q = Number(c.Quantity);
      // ② 검산 — UOM 이름이 숫자인데 BOM 과 다르면 ⚠️ 재고가 틀어진다
      if (/^\d+$/.test(me.uom) && Number(me.uom) !== q) {
        if (uomMismatch.length < 30) uomMismatch.push(me.sku + ' : uom=' + me.uom + ' · BOM=' + q);
      }
      // ③ 검산 — 접미사로 찾은 부모와 같은가
      var sm = me.sku.match(/^(.+)-(\d+)$/);
      if (sm) {
        var sufParent = bySku[sm[1]];
        if (!sufParent || sufParent.id !== parent.id) {
          if (sufMismatch.length < 30) sufMismatch.push(me.sku + ' : 접미사→' + (sufParent ? sufParent.sku : '없음') +
                                                        ' · BOM→' + parent.sku);
        }
      }

      links.push({ id: me.id, parent_product_id: parent.id, pack_factor: q });
    });

    page += 1;
    if (items.length < IPR_LIMIT) break;
    Utilities.sleep(IPR_THROTTLE);
  }

  Logger.log('');
  Logger.log('훑은 행 ' + seen + ' · 구성품 1개로 이을 것 ' + links.length);
  Logger.log('  건너뜀 — BOM 없음 ' + noBom + ' · 구성품 2개 이상(콤보) ' + multi + ' · 우리 표에 없음 ' + notOurs);
  Logger.log('');
  Logger.log('⭐ 오타 탐지기 셋 (평상시 0)');
  Logger.log('  ① 구성품 GUID 가 우리 표에 없음: ' + badGuid.length + (badGuid.length ? ' → ' + badGuid.join(' · ') : ''));
  Logger.log('  ② ⚠️ uom_name(숫자) ≠ pack_factor: ' + uomMismatch.length + (uomMismatch.length ? ' → ' + uomMismatch.join(' · ') : ''));
  Logger.log('  ③ 접미사 부모 ≠ BOM 부모: ' + sufMismatch.length + (sufMismatch.length ? ' → ' + sufMismatch.join(' · ') : ''));

  var f = {};
  links.forEach(function (x) { f[String(x.pack_factor)] = (f[String(x.pack_factor)] || 0) + 1; });
  Logger.log('  pack_factor 분포: ' + Object.keys(f).sort(function (a, b) { return f[b] - f[a]; })
    .slice(0, 20).map(function (k) { return k + ' ' + f[k]; }).join(' · '));
  Logger.log('표본 2: ' + JSON.stringify(links.slice(0, 2)));

  if (dryRun) { Logger.log(''); Logger.log('(dryRun — 쓰지 않았다)'); return; }

  // ⭐ 링크 목록을 시트에 저장한다 — 이어받을 때 Cin7 을 다시 훑지 않기 위해서다
  //    [실측 2026-09-14] 훑기 2분 10초 + PATCH 2분 20초라 한 번에 984건뿐이었다.
  //    시트에 두면 이어받기가 4분 30초를 온전히 PATCH 에 쓴다.
  ipr_saveLinks_(links);
  Logger.log('');
  Logger.log('⭐ 이은 행: ' + ipr_patch_(links));
}

/**
 * ⭐ 이어받기 전용 — Cin7 을 훑지 않고 시트에 저장된 링크로 나머지를 잇는다.
 *    imsLinkProductSetsApply() 를 한 번 돌린 뒤에 쓴다. 몇 번이고 다시 불러도 안전하다.
 */
function imsLinkProductSetsResume() {
  var links = ipr_loadLinks_();
  Logger.log('시트에서 읽은 링크: ' + links.length);
  if (!links.length) { Logger.log('⚠️ 비어 있다 — imsLinkProductSetsApply() 를 먼저 돌려라'); return; }
  Logger.log('⭐ 이은 행: ' + ipr_patch_(links));
}

function ipr_linkSheet_() {
  var id = PropertiesService.getScriptProperties().getProperty('PR_PROBE_SHEET_ID');
  if (!id) throw new Error('PR_PROBE_SHEET_ID 가 없다 — prProbeSetup() 을 먼저 돌려라');
  var ss = SpreadsheetApp.openById(id);
  return ss.getSheetByName('_set_links') || ss.insertSheet('_set_links');
}

function ipr_saveLinks_(links) {
  var sh = ipr_linkSheet_();
  sh.clear();
  sh.appendRow(['id', 'parent_product_id', 'pack_factor']);
  var rows = links.map(function (x) { return [x.id, x.parent_product_id, x.pack_factor]; });
  if (rows.length) sh.getRange(2, 1, rows.length, 3).setValues(rows);
  Logger.log('시트에 저장: ' + rows.length + '줄 (_set_links)');
}

function ipr_loadLinks_() {
  var vals = ipr_linkSheet_().getDataRange().getValues();
  vals.shift();
  return vals.filter(function (r) { return r[0]; }).map(function (r) {
    return { id: String(r[0]), parent_product_id: String(r[1]), pack_factor: Number(r[2]) };
  });
}

/**
 * ⚠️⚠️ [실사고 2026-09-14] 두 칸만 고치려고 upsert(POST · merge-duplicates)를 썼다가 400 이 났다.
 *    PostgREST 의 merge-duplicates 는 **보낸 칸만 고치는 것이 아니라 행 전체를 다시 쓴다.**
 *    안 보낸 칸이 기본값·null 로 채워지고 name NOT NULL 에서 걸렸다(23502).
 *    ⭐ name 이 nullable 이었다면 18,714행의 이름이 통째로 비워졌을 것이다 — 제약이 방어선이었다.
 *    ⇒ 부분 갱신은 반드시 PATCH 다. 한 행씩이라 느리지만(6,347건 ≈ 12분) 안전하다.
 *    ⚠️ 6분 한도에 걸리므로 이어받는다. 이미 이어진 행은 건너뛴다(멱등).
 */
function ipr_patch_(links) {
  var t0 = new Date().getTime();
  var done = 0, skipped = 0, failed = [];

  // ⭐ [실측 2026-09-14] 이미 이어진 행도 PATCH 요청을 한 번씩 보내느라
  //    709건을 「건너뛰는 데만」 4분을 썼다. ⇒ 먼저 읽어서 아예 빼고 시작한다.
  var already = {}, from = 0, step = 1000;
  while (true) {
    var q = ims_fetch_('/rest/v1/product?select=id&parent_product_id=not.is.null', {
      method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1) }
    });
    if (q.getResponseCode() >= 300) break;
    var got = JSON.parse(q.getContentText());
    got.forEach(function (r) { already[String(r.id)] = true; });
    from += got.length;
    if (got.length < step) break;
  }
  var before = links.length;
  links = links.filter(function (x) { return !already[String(x.id)]; });
  Logger.log('  이미 이어진 행 ' + Object.keys(already).length + ' 을 빼고 ' + links.length + ' / ' + before + ' 를 처리한다');

  for (var i = 0; i < links.length; i++) {
    if (new Date().getTime() - t0 > IPR_MAX_RUN) {
      Logger.log('⏸ 시간 한도 — ' + done + '건 이었다. imsLinkProductSetsApply() 를 다시 호출하면 나머지를 잇는다');
      break;
    }
    var x = links[i];
    // 이미 이어진 행은 건너뛴다 — is null 조건을 붙이면 서버가 판단한다(재실행 안전)
    var res = ims_fetch_('/rest/v1/product?id=eq.' + x.id + '&parent_product_id=is.null', {
      method: 'patch',
      headers: { 'Prefer': 'return=representation' },
      payload: JSON.stringify({ parent_product_id: x.parent_product_id, pack_factor: x.pack_factor })
    });
    if (res.getResponseCode() >= 300) {
      if (failed.length < 10) failed.push(x.id + ' → HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 200));
      continue;
    }
    var back = JSON.parse(res.getContentText());
    if (back.length) done++; else skipped++;
    if ((done + skipped) % 500 === 0) Logger.log('  ' + (done + skipped) + ' / ' + links.length + ' — 이은 ' + done + ' · 이미 있음 ' + skipped);
  }

  Logger.log('  이미 이어져 있던 행: ' + skipped);
  if (failed.length) { Logger.log('⚠️ 실패 ' + failed.length); failed.forEach(function (f) { Logger.log('   ' + f); }); }
  return done;
}

// ─────────────────────────────────────────────────────────────
// 5) product_barcode — 부모 자신의 바코드 + 대체 UPC 59
//
//    ⭐ 왜 표인가 — Cin7 은 제품당 바코드 칸이 하나뿐이라 `…-EA-ALT-UPC` SKU 를 파서 우회해 왔다.
//       우리는 줄을 더한다(Caleb 2026-09-13: 앞으로도 화면에서 바꿀 수 있어야 한다).
//
//    담는 줄 둘
//      ① 제품 자신의 Barcode        is_primary=true  · cin7_id=null (제품 행의 cin7_id 는 product 에 있다)
//      ② 대체 UPC 로 흡수된 59      is_primary=false · cin7_id=그 대체 SKU 의 ProductID (추적선)
//                                   부모는 BOM 의 ComponentProductID 로 찾는다
//
//    ⚠️ 부모와 바코드가 같은 12건은 ②를 만들지 않는다 — 같은 값이라 새 정보가 없고,
//       merge-duplicates 가 ①의 is_primary=true 를 false 로 덮어쓴다.
//    ⚠️ 한 묶음 안에 같은 (product_id, barcode) 가 둘이면 PostgREST 가 400 을 낸다
//       ("cannot affect row a second time") — 보내기 전에 걸러 낸다.
//    ⚠️⚠️ 자연키는 (product_id, barcode) 다. 다른 제품이 같은 바코드를 갖는 것은 막지 않는다
//       (실측 48종 중복) — 세어서 로그에 남긴다. 스캔 화면이 갈라 물어야 하는 자리다.
// ─────────────────────────────────────────────────────────────
var IPR_PROP_BC_CURSOR = 'IPR_BARCODE_PAGE';

function imsLoadProductBarcode()      { ipr_loadBarcode_(true); }
function imsLoadProductBarcodeApply() { ipr_loadBarcode_(false); }
function imsLoadProductBarcodeReset() {
  PropertiesService.getScriptProperties().deleteProperty(IPR_PROP_BC_CURSOR);
  Logger.log('바코드 커서를 지웠다.');
}

function ipr_loadBarcode_(dryRun) {
  var t0 = new Date().getTime();
  var props = PropertiesService.getScriptProperties();
  var page = Number(props.getProperty(IPR_PROP_BC_CURSOR) || '1');

  var pmap = ipr_productMap_();          // cin7_id → {id, sku, barcode}
  var stopped = '끝까지 돌았다';
  var seen = 0, wrote = 0;
  var noBarcode = 0, dupInBatch = 0;
  var bcOwners = {};                      // 바코드 → 제품 수 (교차 중복 세기)

  while (true) {
    if (new Date().getTime() - t0 > IPR_MAX_RUN) {
      stopped = '⏸ 시간 한도 — imsLoadProductBarcodeApply() 를 다시 호출하면 이어간다';
      break;
    }
    var r = ipr_cin7_('product', { Page: page, Limit: IPR_LIMIT, IncludeDeprecated: true, IncludeBOM: true });
    var items = r.Products || [];
    if (!items.length) break;
    seen += items.length;

    var rows = [], key = {};
    items.forEach(function (p) {
      var bc = ims_blank_(p.Barcode);
      var me = pmap[String(p.ID)];

      if (me) {
        // ① 제품 자신의 바코드
        if (!bc) { noBarcode++; return; }
        bcOwners[bc] = (bcOwners[bc] || 0) + 1;
        var k1 = me.id + '|' + bc;
        if (key[k1]) { dupInBatch++; return; }
        key[k1] = true;
        rows.push({ cin7_id: null, is_active: true, source: 'cin7',
                    product_id: me.id, barcode: bc, is_primary: true, valid_from: null });
        return;
      }

      // ② 대체 UPC 59 는 여기서 처리하지 않는다 → imsLoadProductAltUpcApply()
      //    ⚠️ 부모의 바코드가 우리 표에 없다(product 에서 barcode 칸을 뺐다).
      //       같은지 비교하려면 ①이 다 들어간 뒤 product_barcode 를 읽어야 한다.
    });

    if (dryRun) {
      Logger.log('페이지 ' + page + ' — 받은 ' + items.length + ' · 넣을 ' + rows.length);
      Logger.log('  바코드 없음 ' + noBarcode + ' · 묶음 내 중복 ' + dupInBatch);
      Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));
      Logger.log('(dryRun — 첫 페이지만 보고 멈춘다)');
      return;
    }

    if (rows.length) wrote += ipr_upsert_('product_barcode', 'product_id,barcode', rows);
    page += 1;
    props.setProperty(IPR_PROP_BC_CURSOR, String(page));
    if (items.length < IPR_LIMIT) break;
    Utilities.sleep(IPR_THROTTLE);
  }

  var cross = Object.keys(bcOwners).filter(function (b) { return bcOwners[b] > 1; }).length;
  Logger.log('');
  Logger.log(stopped + ' · 본 행 ' + seen + ' · 쓴 줄 ' + wrote + ' · 다음 페이지 ' + page);
  Logger.log('  바코드 없음 ' + noBarcode + ' · 묶음 내 중복 ' + dupInBatch);
  Logger.log('  ⚠️ 이번에 본 것 중 한 바코드를 여러 제품이 쓰는 것: ' + cross + '종');
}

/** cin7_id → {id, sku, barcode} · ⚠️ 18,714행이라 캡을 크게 넘는다 */
function ipr_productMap_() {
  var out = {}, from = 0, step = 1000, total = null, n = 0;
  while (true) {
    var res = ims_fetch_('/rest/v1/product?select=id,cin7_id,sku', {
      method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' }
    });
    if (res.getResponseCode() >= 300) throw new Error('product 조회 실패 ' + res.getResponseCode());
    if (total === null) {
      var hs = res.getHeaders(), cr = '';
      Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
      var m = cr.match(/\/(\d+)$/);
      total = m ? Number(m[1]) : null;
    }
    var rows = JSON.parse(res.getContentText());
    rows.forEach(function (r) {
      if (r.cin7_id) out[String(r.cin7_id)] = { id: r.id, sku: String(r.sku), barcode: null };
      n++;
    });
    from += rows.length;
    if (!rows.length) break;
    if (total !== null && from >= total) break;
    if (total === null && rows.length < step) break;
  }
  Logger.log('product 대응표: ' + n + (total === null ? ' / 총계 미확인' : ' / 원격 총계 ' + total));
  if (total !== null && n < total) throw new Error('⚠️ 대응표가 잘렸다: ' + n + ' / ' + total);
  return out;
}

// ─────────────────────────────────────────────────────────────
// 6) product_bom — 콤보 15건 · 구성품 60여 줄
//    ⭐ 구성품이 2개 이상인 것만. 구성품 1개(세트·대체UPC)는 여기 없다.
// ─────────────────────────────────────────────────────────────
function imsLoadProductBom()      { ipr_loadBom_(true); }
function imsLoadProductBomApply() { ipr_loadBom_(false); }

function ipr_loadBom_(dryRun) {
  var pmap = ipr_productMap_();
  var page = 1, rows = [], combos = 0, missParent = [], missComp = [], seen = 0;

  while (true) {
    var r = ipr_cin7_('product', { Page: page, Limit: IPR_LIMIT, IncludeDeprecated: true, IncludeBOM: true });
    var items = r.Products || [];
    if (!items.length) break;
    seen += items.length;

    items.forEach(function (p) {
      var bom = p.BillOfMaterialsProducts || [];
      if (bom.length < 2) return;
      combos++;
      var me = pmap[String(p.ID)];
      if (!me) { missParent.push(String(p.SKU)); return; }
      bom.forEach(function (c) {
        var comp = pmap[String(c.ComponentProductID)];
        if (!comp) { missComp.push(p.SKU + ' → ' + c.ProductCode); return; }
        rows.push({
          cin7_id: null, is_active: true, source: 'cin7',
          parent_product_id: me.id, component_product_id: comp.id,
          quantity: Number(c.Quantity),
          wastage_percent: c.WastagePercent === undefined ? null : Number(c.WastagePercent),
          wastage_quantity: c.WastageQuantity === undefined ? null : Number(c.WastageQuantity),
          cost_percentage: c.CostPercentage === undefined ? null : Number(c.CostPercentage)
        });
      });
    });
    page += 1;
    if (items.length < IPR_LIMIT) break;
    Utilities.sleep(IPR_THROTTLE);
  }

  // ⚠️⚠️ [실사고 2026-09-14] 한 묶음 안에 같은 (parent, component) 가 둘이면
  //    PostgREST 가 400 을 낸다: "ON CONFLICT DO UPDATE command cannot affect row a second time".
  //    ⇒ 같은 콤보에 같은 구성품이 두 줄로 들어 있다(Cin7 화면에서 줄을 두 번 더한 것).
  //       수량을 합치지 않고 **큰 쪽을 남기고 세어 둔다** — 원인을 모르면 합치지 않는다.
  var byKey = {}, dupPairs = [];
  rows.forEach(function (x) {
    var k = x.parent_product_id + '|' + x.component_product_id;
    if (byKey[k]) {
      dupPairs.push(k + ' : ' + byKey[k].quantity + ' vs ' + x.quantity);
      if (Number(x.quantity) > Number(byKey[k].quantity)) byKey[k] = x;
    } else byKey[k] = x;
  });
  var deduped = Object.keys(byKey).map(function (k) { return byKey[k]; });
  if (dupPairs.length) {
    Logger.log('⚠️ 같은 콤보에 같은 구성품이 두 줄: ' + dupPairs.length);
    dupPairs.forEach(function (d) { Logger.log('   ' + d); });
  }
  rows = deduped;

  Logger.log('본 행 ' + seen + ' · 콤보 ' + combos + ' · 구성품 줄 ' + rows.length);
  Logger.log('⚠️ 콤보인데 우리 표에 없음: ' + missParent.length + (missParent.length ? ' → ' + missParent.join(' · ') : ''));
  Logger.log('⚠️ 구성품이 우리 표에 없음: ' + missComp.length + (missComp.length ? ' → ' + missComp.join(' · ') : ''));
  var q = {};
  rows.forEach(function (x) { q[String(x.quantity)] = (q[String(x.quantity)] || 0) + 1; });
  Logger.log('수량 분포: ' + Object.keys(q).sort(function (a, b) { return q[b] - q[a]; })
    .map(function (k) { return k + ' ' + q[k]; }).join(' · '));
  Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  Logger.log('⭐ 쓰인 줄: ' + ipr_upsert_('product_bom', 'parent_product_id,component_product_id', rows));
}

// ─────────────────────────────────────────────────────────────
// 5-b) ⭐ 대체 UPC 59 — ①이 다 들어간 뒤에 붙인다
//    ⚠️ 부모의 바코드가 product 에 없다(칸을 뺐다). product_barcode 에서 읽어 비교한다.
//       이미 같은 줄이 있으면 만들지 않는다 — 새 정보가 없고,
//       merge-duplicates 가 ①의 is_primary=true 를 false 로 덮는다(부모와 같은 12건).
//    ⚠️ 바코드가 없는 7건도 줄이 안 생긴다 — 바코드용 SKU 인데 바코드가 없다.
// ─────────────────────────────────────────────────────────────
function imsLoadProductAltUpc()      { ipr_loadAltUpc_(true); }
function imsLoadProductAltUpcApply() { ipr_loadAltUpc_(false); }

function ipr_loadAltUpc_(dryRun) {
  var pmap = ipr_productMap_();
  var page = 1, cands = [], seen = 0;

  while (true) {
    var r = ipr_cin7_('product', { Page: page, Limit: IPR_LIMIT, IncludeDeprecated: true, IncludeBOM: true });
    var items = r.Products || [];
    if (!items.length) break;
    seen += items.length;
    items.forEach(function (p) {
      if (pmap[String(p.ID)]) return;                 // 우리 표에 있으면 ①에서 처리됐다
      if (String(p.UOM || '') !== 'EA-ALT-UPC') return;
      var bom = p.BillOfMaterialsProducts || [];
      if (bom.length !== 1 || Number(bom[0].Quantity) !== 1) return;
      cands.push({ sku: String(p.SKU), id: String(p.ID), bc: ims_blank_(p.Barcode),
                   parentCin7: String(bom[0].ComponentProductID), parentCode: String(bom[0].ProductCode) });
    });
    page += 1;
    if (items.length < IPR_LIMIT) break;
    Utilities.sleep(IPR_THROTTLE);
  }
  Logger.log('본 행 ' + seen + ' · 대체 UPC 후보 ' + cands.length + ' (정본 기대치 59)');

  var rows = [], noBc = [], noParent = [], already = [];
  cands.forEach(function (c) {
    var parent = pmap[c.parentCin7];
    if (!parent) { noParent.push(c.sku); return; }
    if (!c.bc) { noBc.push(c.sku); return; }
    // 부모가 이미 그 바코드를 갖고 있나 — product_barcode 에서 읽는다
    var q = ims_fetch_('/rest/v1/product_barcode?select=id&product_id=eq.' + parent.id +
                       '&barcode=eq.' + encodeURIComponent(c.bc), { method: 'get' });
    if (q.getResponseCode() >= 300) {
      throw new Error('조회 실패 ' + q.getResponseCode() + ': ' + q.getContentText().slice(0, 200));
    }
    if (JSON.parse(q.getContentText()).length) { already.push(c.sku); return; }
    rows.push({ cin7_id: c.id, is_active: true, source: 'cin7',
                product_id: parent.id, barcode: c.bc, is_primary: false, valid_from: null,
                note: '대체 UPC — Cin7 SKU ' + c.sku + ' 에서 흡수 (2026-09-14)' });
    Utilities.sleep(200);
  });

  Logger.log('⭐ 넣을 줄: ' + rows.length);
  Logger.log('  ⚠️ 바코드 없음: ' + noBc.length + (noBc.length ? ' → ' + noBc.join(' · ') : ''));
  Logger.log('  ⚠️ 부모가 이미 갖고 있음: ' + already.length + (already.length ? ' → ' + already.join(' · ') : ''));
  Logger.log('  ⚠️ 부모 못 찾음: ' + noParent.length + (noParent.length ? ' → ' + noParent.join(' · ') : ''));
  Logger.log('표본 2: ' + JSON.stringify(rows.slice(0, 2)));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (!rows.length) { Logger.log('넣을 줄이 없다'); return; }
  Logger.log('⭐ 쓰인 줄: ' + ipr_upsert_('product_barcode', 'product_id,barcode', rows));
}
