/**
 * ImsLoadProductSupplier.gs — IMS ④ 제품↔공급처 적재
 *
 * ⚠️ 최상위 const 금지 · 식별자 ASCII 만 · prefix 는 ips_ / IPS_ (ipr_ · ims_ · psp_ 와 겹치지 않는다)
 * ⚠️ ImsLoadProduct.gs 의 ipr_cin7_ · ipr_map_ · ipr_upsert_ 를 그대로 쓴다. ImsLoad.gs 의 ims_fetch_ 도.
 * ⚠️ 대상: [테스트 · Asung-IMS]
 *
 * 정본: docs/design/po-module.md §3-g
 *
 * 실행 순서
 *   1) imsLoadSupplierExtra()        확인만 — 새로 넣을 공급처가 몇 곳인지 본다
 *   2) imsLoadSupplierExtraApply()   쓴다 (⏸ 나오면 다시 호출 · 커서는 Script Property)
 *                                    ⭐ 훑으면서 줄 원자료를 시트 ips_line 에 적어 둔다
 *   3) imsLoadProductSupplier()      확인만 — 시트를 읽어 넣을 줄 수를 본다
 *   4) imsLoadProductSupplierApply() 쓴다 (⏸ 나오면 다시 호출)
 *   보조) imsLoadProductSupplierReset()   커서를 지운다
 *
 * ⚠️ 2)가 3)보다 먼저다 — 공급처가 다 있어야 줄의 FK 가 붙는다 (§3-g 판단 ①)
 * ⭐ is_default 계산과 §3-f 정리는 SQL 로 한다 — 제품마다 줄을 다 모은 뒤라야 고를 수 있다
 *
 * ⭐ 시트는 「한 회차 안의 중간 저장」이다. 재적재할 때마다 Cin7 을 새로 훑는다.
 *    (③ imsLinkProductSets 가 링크 목록을 시트에 둔 것과 같은 방식 — 이어받기가 Cin7 을 다시 안 훑게)
 */

var IPS_CURSOR   = 'IPS_SWEEP_PAGE';
var IPS_LIMIT    = 1000;          // ⭐ IncludeSuppliers 는 1000 이 먹는다 (2026-09-14 실측 · BOM 만 500)
var IPS_THROTTLE = 1200;
var IPS_MAX_RUN  = 4.5 * 60 * 1000;
var IPS_SHEET_PROP = 'IPS_SHEET_ID';
var IPS_HEAD = ['ProductCin7Id', 'SupplierCin7Id', 'ProductSupplierID', 'SupplierSku',
                'Cost', 'FixedCost', 'Currency', 'LastSupplied', 'SKU', 'SupplierName'];

// ─────────────────────────────────────────────────────────────
// 시트 — 중간 저장
// ─────────────────────────────────────────────────────────────
function ips_sheet_() {
  var id = PropertiesService.getScriptProperties().getProperty(IPS_SHEET_PROP);
  if (id) { try { return SpreadsheetApp.openById(id); } catch (e) {} }
  var ss = SpreadsheetApp.create('IMS ④ 제품↔공급처 적재');
  PropertiesService.getScriptProperties().setProperty(IPS_SHEET_PROP, ss.getId());
  Logger.log('⭐ 새 시트: ' + ss.getUrl());
  return ss;
}

function ips_lineTab_(reset) {
  var ss = ips_sheet_();
  var sh = ss.getSheetByName('ips_line');
  if (!sh) {
    sh = ss.insertSheet('ips_line');
  } else if (reset) {
    sh.clear();
  } else {
    return sh;
  }
  sh.getRange(1, 1, 1, IPS_HEAD.length).setValues([IPS_HEAD]).setFontWeight('bold');
  sh.setFrozenRows(1);
  // ⚠️⚠️ [실사고 2026-09-14] 시트가 '2025-10-03T00:00:00' 을 날짜로 해석해 Date 로 바꿨다.
  //    다시 읽으니 'Fri Oct 03' — 연도가 사라졌다. is_default 의 근거인 last_supplied 가 통째로 틀어진다.
  //    ⇒ 전 칸을 텍스트 서식(@)으로 못 박고, 값도 문자열로 적는다. 읽을 때도 Date 를 한 번 더 막는다.
  sh.getRange(1, 1, sh.getMaxRows(), IPS_HEAD.length).setNumberFormat('@');
  return sh;
}

/** 시트에서 읽은 값을 날짜 문자열로 — Date 로 바뀌어 있어도 되살린다 */
function ips_date_(v) {
  if (v === '' || v === null || v === undefined) return null;
  if (Object.prototype.toString.call(v) === '[object Date]') {
    return Utilities.formatDate(v, 'UTC', 'yyyy-MM-dd');
  }
  var s = String(v).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;   // ⚠️ 모양이 아니면 넣지 않고 센다
}

/** 시트에서 읽은 값을 수로 — 텍스트로 적혀 있어도 정밀도가 살아 있다 */
function ips_num_(v) {
  if (v === '' || v === null || v === undefined) return null;
  var n = Number(v);
  return isNaN(n) ? null : n;
}

// ─────────────────────────────────────────────────────────────
// 1·2) 공급처 보충 + 줄 원자료 수집
//    ① GET /supplier?IncludeDeprecated=true 688
//    ② 제품 전량을 IncludeSuppliers 로 훑는다 — 줄은 시트에 적고, 등장한 SupplierID 를 모은다
//    ③ supplier 표에 없는 공급처를 넣는다 (is_active=false · is_purchasable 은 보내지 않는다)
// ─────────────────────────────────────────────────────────────
function imsLoadSupplierExtra()      { ips_loadSupplierExtra_(true); }
function imsLoadSupplierExtraApply() { ips_loadSupplierExtra_(false); }

function ips_loadSupplierExtra_(dryRun) {
  var t0 = new Date().getTime();
  var props = PropertiesService.getScriptProperties();
  var page = Number(props.getProperty(IPS_CURSOR) || '1');

  // 우리 표 — ⚠️ product 18,714 는 1,000행 캡을 넘는다. ipr_map_ 이 Range 로 나눠 읽고 총계와 대조한다
  var haveSup = ipr_map_('/rest/v1/supplier?select=id,cin7_id', 'cin7_id');
  var terms   = ipr_map_('/rest/v1/ref_payment_term?select=id,name', 'name');
  var accts   = ipr_map_('/rest/v1/ref_account?select=id,code',     'code');
  var currs   = ipr_map_('/rest/v1/ref_currency?select=id,code',    'code');

  // ① Cin7 공급처 전량 — 새로 넣을 곳의 칸을 여기서 채운다 (Suppliers[] 에는 ID·Name 만 온다)
  var supAll = {};
  var sp = 1;
  while (true) {
    var sr = ipr_cin7_('supplier', { Page: sp, Limit: 1000, IncludeDeprecated: true });
    var sl = sr.SupplierList || [];
    if (!sl.length) break;
    sl.forEach(function (s) { supAll[String(s.ID)] = s; });
    if (Object.keys(supAll).length >= sr.Total) break;
    sp += 1;
    Utilities.sleep(IPS_THROTTLE);
  }
  Logger.log('Cin7 공급처 ' + Object.keys(supAll).length + ' · 우리 표 ' + Object.keys(haveSup).length);

  // ② 제품 전량 훑기 — 줄은 시트로
  var sh = ips_lineTab_(page === 1);
  var used = {}, seen = 0, lineCount = 0, stopped = '끝까지 돌았다';

  while (true) {
    if (new Date().getTime() - t0 > IPS_MAX_RUN) {
      stopped = '⏸ 시간 한도 — imsLoadSupplierExtraApply() 를 다시 호출하면 이어간다';
      break;
    }
    var r = ipr_cin7_('product', {
      Page: page, Limit: IPS_LIMIT, IncludeDeprecated: true, IncludeSuppliers: true
    });
    var items = r.Products || [];
    if (!items.length) break;
    seen += items.length;

    var rows = [];
    items.forEach(function (p) {
      if (String(p.Type) !== 'Stock') return;          // §3-g 실측의 모집단과 맞춘다
      (p.Suppliers || []).forEach(function (s) {
        used[String(s.SupplierID)] = 1;
        // ⚠️ 전부 문자열로 적는다 — 시트의 자동 해석을 막는다(위 ips_lineTab_ 주석)
        rows.push([String(p.ID), String(s.SupplierID), String(s.ProductSupplierID),
                   s.SupplierInventoryCode == null ? '' : String(s.SupplierInventoryCode),
                   s.Cost == null ? '' : String(s.Cost),
                   s.FixedCost == null ? '' : String(s.FixedCost),
                   s.Currency == null ? '' : String(s.Currency),
                   s.LastSupplied == null ? '' : String(s.LastSupplied).slice(0, 10),
                   String(p.SKU), String(s.SupplierName)]);
      });
    });
    if (rows.length) {
      sh.getRange(sh.getLastRow() + 1, 1, rows.length, IPS_HEAD.length).setValues(rows);
      lineCount += rows.length;
    }
    Logger.log('p' + page + ' — 받은 ' + items.length + ' · 줄 ' + rows.length);

    if (dryRun) { Logger.log('(dryRun — 첫 페이지만 보고 멈춘다)'); break; }

    page += 1;
    props.setProperty(IPS_CURSOR, String(page));
    if (seen >= r.Total) break;                        // ⭐ Total 로 끝낸다 (items.length 로 끝내지 않는다)
    Utilities.sleep(IPS_THROTTLE);
  }

  if (stopped.charAt(0) === '⏸') { Logger.log(stopped); return; }
  if (dryRun) {
    Logger.log('첫 페이지 기준 — 시트에 적은 줄 ' + lineCount);
  } else {
    Logger.log('훑기 끝 · 본 제품 ' + seen + ' · 시트에 적은 줄 ' + lineCount);
  }

  // ③ 표에 없는 공급처 — NOT NULL 셋을 채운다
  var toAdd = [], blankTerm = [], blankAcct = [], notInCin7 = [];
  Object.keys(used).forEach(function (g) {
    if (haveSup[g]) return;
    var s = supAll[g];
    if (!s) { notInCin7.push(g); return; }             // ⚠️ 제품이 가리키는데 공급처 목록에 없다
    var term = String(s.PaymentTerm || '');
    var code = String(s.AccountPayable || '');
    if (!term) blankTerm.push(s.Name);
    if (!code) blankAcct.push(s.Name);
    toAdd.push({
      cin7_id: g,
      name: s.Name,
      is_active: String(s.Status) === 'Active',
      source: 'cin7',
      payment_term_id: terms[term] || null,
      payment_term_name: term,                         // ⚠️ NOT NULL — 빈값이면 '' 로 들어간다. 아래 카운터
      account_payable_id: accts[code] || null,
      account_payable_code: code,                      // ⚠️ NOT NULL
      currency_id: currs[String(s.Currency || '')] || null,
      tax_rule: s.TaxRule || null,
      cin7_comments: s.Comments || null
      // ⚠️ is_purchasable 은 보내지 않는다 — 우리 칸이고 「아직 안 정했다」가 null 이다 (§7-a)
      // ⚠️ is_discontinued 도 보내지 않는다 — default false
    });
  });

  Logger.log('');
  Logger.log('제품이 가리키는 공급처 ' + Object.keys(used).length + ' 종');
  Logger.log('⭐ 표에 없어 새로 넣을 곳 ' + toAdd.length + ' (예상 31)');
  Logger.log('   그중 비활성 ' + toAdd.filter(function (x) { return !x.is_active; }).length);
  Logger.log('⚠️ PaymentTerm 빈값 ' + blankTerm.length + (blankTerm.length ? ' → ' + blankTerm.join(' · ') : ''));
  Logger.log('⚠️ AccountPayable 빈값 ' + blankAcct.length + (blankAcct.length ? ' → ' + blankAcct.join(' · ') : ''));
  Logger.log('⚠️ Cin7 공급처 목록에 없는 GUID ' + notInCin7.length + (notInCin7.length ? ' → ' + notInCin7.join(' · ') : ''));
  Logger.log('못 이은 결제조건 ' + toAdd.filter(function (x) { return !x.payment_term_id; }).length +
             ' · 못 이은 계정 ' + toAdd.filter(function (x) { return !x.account_payable_id; }).length +
             ' · 못 이은 통화 ' + toAdd.filter(function (x) { return !x.currency_id; }).length);
  if (toAdd.length) Logger.log('표본 1: ' + JSON.stringify(toAdd[0]));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }
  if (blankTerm.length || blankAcct.length) {
    Logger.log('⚠️⚠️ NOT NULL 칸이 빈 곳이 있다 — 빈 문자열로 들어간다. 그대로 진행한다(카운터로 남는다)');
  }
  if (toAdd.length) {
    Logger.log('⭐ 쓰인 행: ' + ipr_upsert_('supplier', 'cin7_id', toAdd));
  }
  props.deleteProperty(IPS_CURSOR);
  Logger.log('다음: imsLoadProductSupplier()');
}

function imsLoadProductSupplierReset() {
  PropertiesService.getScriptProperties().deleteProperty(IPS_CURSOR);
  Logger.log('커서를 지웠다. 다음 실행은 p1 부터 · 시트도 새로 쓴다');
}

// ─────────────────────────────────────────────────────────────
// 3·4) product_supplier — 시트를 읽어 넣는다
//    ⭐ 충돌 키는 cin7_id (ProductSupplierID)
//    ⭐ 승격 — 같은 (product_id, supplier_id) 가 cin7_id null 인 manual 행으로 있으면
//       새 행을 만들지 않고 그 행에 PATCH 한다 (source 는 manual 유지)
//       ⚠️ 첫 적재에는 발동하지 않는다(표가 비어 있다). 두 번째부터 동작한다
// ─────────────────────────────────────────────────────────────
function imsLoadProductSupplier()      { ips_loadLines_(true); }
function imsLoadProductSupplierApply() { ips_loadLines_(false); }

function ips_loadLines_(dryRun) {
  var prodMap = ipr_map_('/rest/v1/product?select=id,cin7_id',  'cin7_id');   // ⚠️ 18,714 — 캡 넘는다
  var supMap  = ipr_map_('/rest/v1/supplier?select=id,cin7_id', 'cin7_id');
  var currs   = ipr_map_('/rest/v1/ref_currency?select=id,code', 'code');

  // 승격 대상 — 사람이 먼저 적은 줄 (cin7_id 가 비어 있는 것)
  var manual = {};
  var mres = ims_fetch_('/rest/v1/product_supplier?cin7_id=is.null&select=id,product_id,supplier_id,source', { method: 'get' });
  if (mres.getResponseCode() < 300) {
    JSON.parse(mres.getContentText()).forEach(function (m) {
      manual[m.product_id + '|' + m.supplier_id] = m.id;
    });
  }
  Logger.log('사람이 먼저 적은 줄 ' + Object.keys(manual).length);

  var sh = ips_lineTab_(false);
  var v = sh.getDataRange().getValues();
  Logger.log('시트 줄 ' + (v.length - 1));

  var rows = [], promote = [], missProd = [], missSup = [], missCur = 0, both0 = 0, badDate = 0;
  for (var i = 1; i < v.length; i++) {
    var r = v[i];
    if (!r[0]) continue;
    var pid = prodMap[String(r[0])];
    var sid = supMap[String(r[1])];
    // ⚠️ 못 이은 줄은 넣지 않고 센다 (FK 가 끊긴다 · §3-g)
    if (!pid) { if (missProd.length < 30) missProd.push(r[8]); continue; }
    if (!sid) { if (missSup.length < 30) missSup.push(r[9]); continue; }

    var cur = currs[String(r[6] || '')] || null;
    if (!cur) missCur++;
    var cost = ips_num_(r[4]);
    var fixed = ips_num_(r[5]);
    if (!cost && !fixed) both0++;
    var lastSup = ips_date_(r[7]);
    // ⚠️ 시트에 값이 있는데 날짜 모양이 아니면 세어 둔다 — 조용히 null 로 들어가면 is_default 가 틀어진다
    if (r[7] !== '' && r[7] !== null && lastSup === null) {
      badDate++;
      if (badDate <= 5) Logger.log('⚠️ 날짜 모양이 아니다: ' + r[8] + ' → "' + r[7] + '"');
    }

    var body = {
      cin7_id: String(r[2]),
      product_id: pid,
      supplier_id: sid,
      supplier_sku: r[3] === '' ? null : String(r[3]),
      cost: cost,
      fixed_cost: fixed,
      currency_id: cur,
      last_supplied: lastSup,
      is_active: true,
      source: 'cin7'
      // ⚠️ is_default 는 보내지 않는다 — 줄을 다 모은 뒤 SQL 로 정한다
    };

    var key = pid + '|' + sid;
    if (manual[key]) {
      // ⭐ 승격 — 새 행을 만들지 않는다. source 는 건드리지 않는다
      promote.push({ id: manual[key], body: {
        cin7_id: body.cin7_id, supplier_sku: body.supplier_sku, cost: body.cost,
        fixed_cost: body.fixed_cost, currency_id: body.currency_id, last_supplied: body.last_supplied
      }});
    } else {
      rows.push(body);
    }
  }

  Logger.log('');
  Logger.log('넣을 줄 ' + rows.length + ' · 승격(PATCH) ' + promote.length);
  Logger.log('⚠️ 제품을 못 이은 줄 ' + missProd.length + (missProd.length ? ' → ' + missProd.slice(0, 10).join(' · ') : ''));
  Logger.log('⚠️ 공급처를 못 이은 줄 ' + missSup.length + (missSup.length ? ' → ' + missSup.slice(0, 10).join(' · ') : ''));
  Logger.log('통화를 못 이은 줄 ' + missCur + ' · 단가가 둘 다 없는 줄 ' + both0 + ' (예상 1,232)');
  Logger.log('⚠️⚠️ 날짜가 깨진 줄 ' + badDate + ' — 0 이 아니면 쓰지 마라(is_default 가 틀어진다)');
  if (badDate) { Logger.log('⛔ 멈춘다 — 시트를 다시 채워라: imsLoadProductSupplierReset() 뒤 imsLoadSupplierExtraApply()'); return; }
  if (rows.length) Logger.log('표본 1: ' + JSON.stringify(rows[0]));

  if (dryRun) { Logger.log('(dryRun — 쓰지 않았다)'); return; }

  if (rows.length) Logger.log('⭐ 쓰인 줄: ' + ipr_upsert_('product_supplier', 'cin7_id', rows));

  // 승격은 행마다 PATCH — ⚠️ upsert 는 부분 갱신이 아니다 (WMS 규칙 45)
  var ok = 0;
  promote.forEach(function (p) {
    var res = ims_fetch_('/rest/v1/product_supplier?id=eq.' + p.id, {
      method: 'patch',
      headers: { 'Prefer': 'return=representation' },
      payload: JSON.stringify(p.body)
    });
    if (res.getResponseCode() < 300 && JSON.parse(res.getContentText()).length === 1) ok++;
    else Logger.log('⚠️ 승격 실패 ' + p.id + ' HTTP ' + res.getResponseCode());
  });
  if (promote.length) Logger.log('⭐ 승격된 줄: ' + ok + ' / ' + promote.length);
}
