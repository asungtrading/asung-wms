/**
 * ProbeProductSupplier.gs — IMS ④ 제품↔공급처 프로브 (2026-09-14)
 *
 * ⚠️ 함수를 더할 때는 이 파일에 붙인다. 파일을 새로 만들지 않는다.
 * ⚠️ 전역 prefix 는 psp_ / PSP_ 로 통일 — 다른 파일과 겹치면 프로젝트 전체가 로드 실패한다.
 * ⚠️ Config.gs 의 getProp() 를 쓴다. 키는 CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY.
 *
 * 실행 순서
 *   psp_step1_suppliers()    공급처 전량 688 → psp_supplier 탭                     1콜
 *   psp_step2_shape()        Suppliers[] 실물 — Limit·칸 이름·원문 → psp_shape     3콜
 *   psp_step3_sweep()        제품 전량 × 공급처 줄 → psp_line · psp_product        19콜 · 이어받기 있음
 *   psp_step4_report()       위 둘을 읽어 집계 → psp_report                        0콜
 *   psp_step5_crosscheck()   세트·낱개 교차 후보 → psp_cross                       0콜
 *   psp_step6_dpbom()        DP 디스플레이 7건의 BOM 원문 → psp_dpbom              7콜
 *   psp_step7_bomsweep()     BOM 훑기 페이지별 실측 + 콤보 전수 → psp_bom·psp_bompage
 *                                                                                 38콜 · 이어받기 있음
 *   보조  psp_resetSweep() · psp_resetBomSweep()
 *
 * 실측 결과(2026-09-14)
 *   공급처 688 = 활성 226 + 비활성 462
 *   제품 18,829 · 공급처 줄 12,729 (활성 공급처 11,941 · 비활성 787 · 미상 0)
 *   비활성을 가리키는 공급처는 31곳뿐 · 제품에 붙은 활성 공급처는 144곳/226
 *   ⭐ 「기본 공급처」 표시는 없다 — 2줄 이상일 때 고르는 규칙은 우리가 정한다
 *   ⭐ 문서에 없던 칸 둘 — Suppliers[].IncludeInPricing · Options[].LocationName
 *   ⚠️ Options[] 에 Default 칸이 오지 않는다 — PUT 은 우리가 만들어 붙여야 한다
 *   ⚠️ 창고별 옵션(Lead·Safety·ReorderQuantity)은 전량 0 — 쓰지 않는 칸이다
 */

var PSP_BASE = 'https://inventory.dearsystems.com/ExternalApi/v2/';
var PSP_SHEET_PROP = 'PSP_SHEET_ID';

/* ───────────────────────── 공통 ───────────────────────── */

function psp_get_(endpoint, params) {
  var qs = Object.keys(params)
    .filter(function (k) { return params[k] !== null && params[k] !== undefined; })
    .map(function (k) { return k + '=' + encodeURIComponent(params[k]); })
    .join('&');
  var url = PSP_BASE + endpoint + (qs ? '?' + qs : '');
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };

  for (var attempt = 0; attempt < 3; attempt++) {
    var res = UrlFetchApp.fetch(url, { headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    var body = res.getContentText();

    if (code === 429) {
      // ⚠️ 429 응답에만 Retry-After 가 온다. 표기값을 믿고 그만큼 쉰다(없으면 60초).
      var ra = res.getHeaders()['Retry-After'] || res.getHeaders()['retry-after'] || '60';
      var sec = parseInt(String(ra).replace(/[^0-9]/g, ''), 10) || 60;
      Logger.log('429 — ' + sec + '초 대기 후 같은 페이지 재시도: ' + endpoint);
      Utilities.sleep((sec + 5) * 1000);
      continue;
    }
    if (code !== 200) {
      throw new Error('HTTP ' + code + ' — ' + endpoint + ' — ' + body.slice(0, 300));
    }
    // ⚠️ Cin7 은 없는 경로에도 200 + HTML 을 준다. 본문이 JSON 인지 본다.
    if (body.charAt(0) !== '{' && body.charAt(0) !== '[') {
      throw new Error('200 인데 JSON 이 아니다(경로 의심) — ' + endpoint + ' — ' + body.slice(0, 200));
    }
    return JSON.parse(body);
  }
  throw new Error('429 재시도 소진 — ' + endpoint);
}

function psp_sheet_() {
  var id = PropertiesService.getScriptProperties().getProperty(PSP_SHEET_PROP);
  if (id) {
    try { return SpreadsheetApp.openById(id); } catch (e) { /* 지워졌으면 새로 만든다 */ }
  }
  var ss = SpreadsheetApp.create('IMS ④ 제품↔공급처 프로브');
  PropertiesService.getScriptProperties().setProperty(PSP_SHEET_PROP, ss.getId());
  Logger.log('⭐ 새 시트를 만들었다: ' + ss.getUrl());
  return ss;
}

function psp_tab_(ss, name, header) {
  var sh = ss.getSheetByName(name);
  if (sh) { sh.clear(); } else { sh = ss.insertSheet(name); }
  if (header && header.length) {
    sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}

/* ──────────────────── ① 공급처 전량 ──────────────────── */

function psp_step1_suppliers() {
  var t0 = Date.now();
  var all = [];
  var page = 1;

  while (true) {
    var d = psp_get_('supplier', { Page: page, Limit: 1000, IncludeDeprecated: true });
    var rows = d.SupplierList || [];           // ⚠️ 배열 키는 SupplierList
    all = all.concat(rows);
    Logger.log('supplier p' + page + ' — ' + rows.length + '행 (Total ' + d.Total + ')');
    if (rows.length === 0 || all.length >= d.Total) break;
    page++;
    Utilities.sleep(1200);
  }

  var ss = psp_sheet_();
  var sh = psp_tab_(ss, 'psp_supplier',
    ['SupplierID', 'Name', 'Status', 'Currency', 'PaymentTerm', 'AccountPayable', 'TaxRule']);
  var out = all.map(function (s) {
    return [s.ID, s.Name, s.Status, s.Currency, s.PaymentTerm, s.AccountPayable, s.TaxRule];
  });
  if (out.length) sh.getRange(2, 1, out.length, out[0].length).setValues(out);

  var byStatus = {};
  all.forEach(function (s) { byStatus[s.Status] = (byStatus[s.Status] || 0) + 1; });

  Logger.log('───── step1 결과 ─────');
  Logger.log('공급처 전량 ' + all.length + ' · Status 분포 ' + JSON.stringify(byStatus));
  Logger.log('소요 ' + Math.round((Date.now() - t0) / 1000) + '초 · 시트 ' + ss.getUrl());
}

/* ─────────────── ② 응답 실물 — Limit·칸 이름 ─────────────── */

function psp_step2_shape() {
  var t0 = Date.now();
  var log = [];

  // (1) Limit 실효 상한 — IncludeBOM 은 500 이 상한이었다. 여기도 같은지 본다.
  var p1 = psp_get_('product', { Page: 1, Limit: 1000, IncludeDeprecated: true, IncludeSuppliers: true });
  var n1 = (p1.Products || []).length;
  log.push('Limit=1000 요청 → 실제 ' + n1 + '행 (Total ' + p1.Total + ')');
  log.push(n1 === 1000 ? '⇒ 1000 먹는다' : '⇒ ⚠️ 실효 상한이 ' + n1 + ' 이다');

  // (2) 칸 이름 — ⚠️ 1페이지는 _숫자_ 시스템 항목이 몰려 있다. 가운데에서 흩어 뽑는다.
  Utilities.sleep(1200);
  var mid = Math.max(2, Math.floor((p1.Total / n1) / 2));
  var pm = psp_get_('product', { Page: mid, Limit: n1, IncludeDeprecated: true, IncludeSuppliers: true });
  Utilities.sleep(1200);
  var pq = psp_get_('product', { Page: Math.max(2, mid + Math.floor(mid / 2)), Limit: n1, IncludeDeprecated: true, IncludeSuppliers: true });

  var prods = (pm.Products || []).concat(pq.Products || []);
  log.push('표본 제품 ' + prods.length + '행 (page ' + mid + ' · ' + Math.max(2, mid + Math.floor(mid / 2)) + ')');

  var supKeys = {}, optKeys = {}, dist = {}, withLines = 0, lines = 0;
  var sampleMulti = null, sampleOne = null;

  prods.forEach(function (p) {
    if (p.Type !== 'Stock') return;
    var arr = p.Suppliers || [];
    var n = arr.length;
    var k = n >= 3 ? '3+' : String(n);
    dist[k] = (dist[k] || 0) + 1;
    lines += n;
    if (n > 0) withLines++;
    arr.forEach(function (s) {
      Object.keys(s).forEach(function (kk) { supKeys[kk] = (supKeys[kk] || 0) + 1; });
      (s.ProductSupplierOptions || []).forEach(function (o) {
        Object.keys(o).forEach(function (kk) { optKeys[kk] = (optKeys[kk] || 0) + 1; });
      });
    });
    if (n >= 2 && !sampleMulti) sampleMulti = p;
    if (n === 1 && !sampleOne) sampleOne = p;
  });

  log.push('Type=Stock 표본의 줄 수 분포 ' + JSON.stringify(dist) + ' · 줄 총수 ' + lines);
  log.push('Suppliers[] 칸: ' + JSON.stringify(supKeys));
  log.push('ProductSupplierOptions[] 칸: ' + JSON.stringify(optKeys));

  // (3) 원문 — 「기본 공급처」 표시가 있는지는 문서가 아니라 이것으로 본다
  if (sampleMulti) {
    log.push('── 2줄 이상 표본: ' + sampleMulti.SKU + ' / ' + sampleMulti.Name);
    log.push(JSON.stringify(sampleMulti.Suppliers, null, 2));
  } else {
    log.push('── ⚠️ 표본에 2줄 이상인 제품이 없었다');
  }
  if (sampleOne) {
    log.push('── 1줄 표본: ' + sampleOne.SKU);
    log.push(JSON.stringify(sampleOne.Suppliers, null, 2));
  }

  var ss = psp_sheet_();
  var sh = psp_tab_(ss, 'psp_shape', ['line']);
  var out = log.map(function (l) { return [l]; });
  sh.getRange(2, 1, out.length, 1).setValues(out);
  sh.setColumnWidth(1, 900);

  log.forEach(function (l) { Logger.log(l); });
  Logger.log('소요 ' + Math.round((Date.now() - t0) / 1000) + '초 · 시트 ' + ss.getUrl());
}

var PSP_STATE_PROP = 'PSP_SWEEP_STATE';
var PSP_TIME_BUDGET_MS = 4.5 * 60 * 1000;

var PSP_LINE_HEAD = [
  'SKU', 'ProductStatus', 'ProductType', 'UOM',
  'SupplierName', 'SupplierID', 'SupStatus', 'SupCurrency',
  'ProductSupplierID', 'Cost', 'FixedCost', 'PurchaseCost', 'Currency',
  'SupplierInventoryCode', 'SupplierProductName', 'SupplierProductURL',
  'LastSupplied', 'DropShip', 'IncludeInPricing',
  'OptCount', 'OptNullLoc', 'OptLocNames',
  'MaxLead', 'MaxSafety', 'MaxMinToReorder', 'MaxReorderQty'
];

var PSP_PROD_HEAD = [
  'SKU', 'Name', 'ProductStatus', 'ProductType', 'UOM',
  'Lines', 'ActiveSupLines', 'InactiveSupLines', 'UnknownSupLines'
];

/* ───────────────── ③ 본 훑기 ───────────────── */

function psp_step3_sweep() {
  var t0 = Date.now();
  var props = PropertiesService.getScriptProperties();
  var st = JSON.parse(props.getProperty(PSP_STATE_PROP) || 'null');

  var ss = psp_sheet_();
  var supMap = psp_supplierMap_(ss);   // GUID -> {name, status, currency}

  var shL, shP;
  if (!st) {
    st = { page: 1, total: null, prods: 0, lines: 0, startedAt: new Date().toISOString() };
    shL = psp_tab_(ss, 'psp_line', PSP_LINE_HEAD);
    shP = psp_tab_(ss, 'psp_product', PSP_PROD_HEAD);
    Logger.log('새로 시작한다 (page 1 부터)');
  } else {
    shL = ss.getSheetByName('psp_line');
    shP = ss.getSheetByName('psp_product');
    if (!shL || !shP) throw new Error('시트 탭이 없다 — 상태를 지우고 다시 시작하라: psp_resetSweep()');
    Logger.log('이어받는다 (page ' + st.page + ' 부터 · 지금까지 제품 ' + st.prods + ' · 줄 ' + st.lines + ')');
  }

  while (true) {
    var d = psp_get_('product', {
      Page: st.page, Limit: 1000, IncludeDeprecated: true, IncludeSuppliers: true
    });
    var prods = d.Products || [];
    st.total = d.Total;
    if (prods.length === 0) { st.done = true; break; }

    var lineRows = [], prodRows = [];

    prods.forEach(function (p) {
      var arr = p.Suppliers || [];
      var cls = { active: 0, inactive: 0, unknown: 0 };

      arr.forEach(function (s) {
        var sup = supMap[s.SupplierID] || null;
        var status = sup ? (sup.status === 'Active' ? 'Active' : 'Deprecated') : '미상';
        if (status === 'Active') cls.active++;
        else if (status === 'Deprecated') cls.inactive++;
        else cls.unknown++;

        var opts = s.ProductSupplierOptions || [];
        var nullLoc = 0, locNames = [], mx = { Lead: 0, Safety: 0, MinimumToReorder: 0, ReorderQuantity: 0 };
        opts.forEach(function (o) {
          if (o.LocationID === null || o.LocationID === undefined) nullLoc++;
          else locNames.push(o.LocationName || o.LocationID);
          ['Lead', 'Safety', 'MinimumToReorder', 'ReorderQuantity'].forEach(function (k) {
            var v = Number(o[k] || 0);
            if (v > mx[k]) mx[k] = v;
          });
        });

        lineRows.push([
          p.SKU, p.Status, p.Type, p.UOM,
          s.SupplierName, s.SupplierID, status, sup ? sup.currency : '',
          s.ProductSupplierID, s.Cost, s.FixedCost, s.PurchaseCost, s.Currency,
          s.SupplierInventoryCode, s.SupplierProductName, s.SupplierProductURL,
          s.LastSupplied, s.DropShip, s.IncludeInPricing,
          opts.length, nullLoc, locNames.join(' | '),
          mx.Lead, mx.Safety, mx.MinimumToReorder, mx.ReorderQuantity
        ]);
      });

      prodRows.push([
        p.SKU, p.Name, p.Status, p.Type, p.UOM,
        arr.length, cls.active, cls.inactive, cls.unknown
      ]);
    });

    if (lineRows.length) {
      shL.getRange(shL.getLastRow() + 1, 1, lineRows.length, PSP_LINE_HEAD.length).setValues(lineRows);
    }
    if (prodRows.length) {
      shP.getRange(shP.getLastRow() + 1, 1, prodRows.length, PSP_PROD_HEAD.length).setValues(prodRows);
    }

    st.prods += prodRows.length;
    st.lines += lineRows.length;
    Logger.log('p' + st.page + ' — 제품 ' + prodRows.length + ' · 줄 ' + lineRows.length +
               ' (누적 ' + st.prods + ' / ' + st.total + ')');

    st.page++;
    if (st.prods >= st.total) { st.done = true; break; }

    props.setProperty(PSP_STATE_PROP, JSON.stringify(st));

    if (Date.now() - t0 > PSP_TIME_BUDGET_MS) {
      Logger.log('⏸ 시간 예산을 써서 멈춘다 — psp_step3_sweep() 을 다시 누르면 p' + st.page + ' 부터 이어받는다');
      return;
    }
    Utilities.sleep(1200);   // 60콜/60초
  }

  props.deleteProperty(PSP_STATE_PROP);
  Logger.log('───── 훑기 완료 ─────');
  Logger.log('제품 ' + st.prods + ' / Total ' + st.total + ' · 줄 ' + st.lines +
             ' · 소요 ' + Math.round((Date.now() - t0) / 1000) + '초');
  Logger.log('이어서 psp_step4_report() 를 돌려라 (Cin7 을 부르지 않는다)');
}

function psp_resetSweep() {
  PropertiesService.getScriptProperties().deleteProperty(PSP_STATE_PROP);
  Logger.log('훑기 상태를 지웠다. 다음 실행은 p1 부터 · 탭도 새로 쓴다');
}

function psp_supplierMap_(ss) {
  var sh = ss.getSheetByName('psp_supplier');
  if (!sh) throw new Error('psp_supplier 탭이 없다 — psp_step1_suppliers() 를 먼저 돌려라');
  var v = sh.getDataRange().getValues();
  var map = {};
  for (var i = 1; i < v.length; i++) {
    if (!v[i][0]) continue;
    map[v[i][0]] = { name: v[i][1], status: v[i][2], currency: v[i][3] };
  }
  Logger.log('공급처 맵 ' + Object.keys(map).length + '건');
  return map;
}

/* ───────────────── ④ 집계 ───────────────── */

function psp_step4_report() {
  var ss = psp_sheet_();
  var L = ss.getSheetByName('psp_line').getDataRange().getValues();
  var P = ss.getSheetByName('psp_product').getDataRange().getValues();
  var out = [];
  function say(s) { out.push(s); Logger.log(s); }

  var ci = {};
  PSP_LINE_HEAD.forEach(function (h, i) { ci[h] = i; });
  var pi = {};
  PSP_PROD_HEAD.forEach(function (h, i) { pi[h] = i; });

  /* 제품 쪽 — Type=Stock 만 */
  var dist = {}, distActive = {}, nStock = 0, nStockActive = 0;
  var zeroActive = [], zeroActiveAll = 0, onlyInactive = [], onlyInactiveAll = 0;
  for (var i = 1; i < P.length; i++) {
    var r = P[i];
    if (r[pi.ProductType] !== 'Stock') continue;
    nStock++;
    var isActive = r[pi.ProductStatus] === 'Active';
    if (isActive) nStockActive++;
    var n = Number(r[pi.Lines] || 0);
    var k = n >= 3 ? '3+' : String(n);
    dist[k] = (dist[k] || 0) + 1;
    if (isActive) distActive[k] = (distActive[k] || 0) + 1;

    var act = Number(r[pi.ActiveSupLines] || 0);
    var inact = Number(r[pi.InactiveSupLines] || 0);
    if (isActive && act === 0) {
      zeroActiveAll++;
      if (zeroActive.length < 300) zeroActive.push(r[pi.SKU]);
      if (inact > 0) {
        onlyInactiveAll++;
        if (onlyInactive.length < 300) onlyInactive.push(r[pi.SKU]);
      }
    }
  }

  say('══ 제품 (Type=Stock ' + nStock + ' · 그중 활성 ' + nStockActive + ') ══');
  say('공급처 줄 수 분포 (전체)  ' + JSON.stringify(dist));
  say('공급처 줄 수 분포 (활성)  ' + JSON.stringify(distActive));
  say('⭐ 활성 제품인데 활성 공급처 줄이 0  ' + zeroActiveAll);
  say('   그중 비활성 공급처 줄은 있는 것    ' + onlyInactiveAll + '  ← 거르면 살 곳이 사라지는 제품');

  /* 줄 쪽 */
  var byStatus = {}, supSetInactive = {}, supSetActive = {}, supSetUnknown = {};
  var nameMismatch = {}, curMismatch = 0, curDist = {};
  var fixPos = 0, costPos = 0, bothZero = 0, invCode = 0, prodName = 0, prodUrl = 0;
  var dropShip = 0, notInPricing = 0, lastSuppliedNull = 0;
  var optDist = {}, optNoNullLoc = 0, locNameSet = {};
  var nz = { MaxLead: 0, MaxSafety: 0, MaxMinToReorder: 0, MaxReorderQty: 0 };
  var inactiveLines = 0;

  for (var j = 1; j < L.length; j++) {
    var l = L[j];
    if (l[ci.ProductType] !== 'Stock') continue;
    var st = l[ci.SupStatus];
    byStatus[st] = (byStatus[st] || 0) + 1;
    if (st === 'Deprecated') { inactiveLines++; supSetInactive[l[ci.SupplierID]] = l[ci.SupplierName]; }
    else if (st === 'Active') supSetActive[l[ci.SupplierID]] = l[ci.SupplierName];
    else supSetUnknown[l[ci.SupplierID]] = l[ci.SupplierName];

    var supCur = l[ci.SupCurrency], lineCur = l[ci.Currency];
    curDist[lineCur] = (curDist[lineCur] || 0) + 1;
    if (supCur && lineCur && supCur !== lineCur) curMismatch++;

    var f = Number(l[ci.FixedCost] || 0), c = Number(l[ci.Cost] || 0);
    if (f > 0) fixPos++;
    if (c > 0) costPos++;
    if (f <= 0 && c <= 0) bothZero++;
    if (l[ci.SupplierInventoryCode]) invCode++;
    if (l[ci.SupplierProductName]) prodName++;
    if (l[ci.SupplierProductURL]) prodUrl++;
    if (l[ci.DropShip] === true || l[ci.DropShip] === 'TRUE') dropShip++;
    if (l[ci.IncludeInPricing] === false || l[ci.IncludeInPricing] === 'FALSE') notInPricing++;
    if (!l[ci.LastSupplied]) lastSuppliedNull++;

    var oc = Number(l[ci.OptCount] || 0);
    optDist[oc >= 5 ? '5+' : String(oc)] = (optDist[oc >= 5 ? '5+' : String(oc)] || 0) + 1;
    if (oc > 0 && Number(l[ci.OptNullLoc] || 0) !== 1) optNoNullLoc++;
    String(l[ci.OptLocNames] || '').split(' | ').forEach(function (n) { if (n) locNameSet[n] = 1; });
    ['MaxLead', 'MaxSafety', 'MaxMinToReorder', 'MaxReorderQty'].forEach(function (k) {
      if (Number(l[ci[k]] || 0) > 0) nz[k]++;
    });
  }

  say('');
  say('══ 줄 (Type=Stock 제품의 공급처 줄 ' + (L.length - 1) + ') ══');
  say('공급처 상태별  ' + JSON.stringify(byStatus));
  say('⭐⭐ 비활성 공급처를 가리키는 줄 ' + inactiveLines +
      ' · 그 줄들이 가리키는 공급처 ' + Object.keys(supSetInactive).length + '곳  ← supplier 표 범위를 정하는 숫자');
  say('   제품에 실제로 붙은 활성 공급처 ' + Object.keys(supSetActive).length + '곳 / 226');
  say('   어느 쪽도 아닌 GUID ' + Object.keys(supSetUnknown).length + '곳');
  say('');
  say('단가  FixedCost>0 ' + fixPos + ' · Cost>0 ' + costPos + ' · ⚠️ 둘 다 0 ' + bothZero);
  say('통화  ' + JSON.stringify(curDist) + ' · 공급처 기본통화와 어긋나는 줄 ' + curMismatch);
  say('채움  공급처SKU ' + invCode + ' · 공급처제품명 ' + prodName + ' · URL ' + prodUrl +
      ' · LastSupplied 빈 줄 ' + lastSuppliedNull);
  say('기타  DropShip ' + dropShip + ' · IncludeInPricing=false ' + notInPricing);
  say('');
  say('옵션 원소 수 분포 ' + JSON.stringify(optDist));
  say('⚠️ 옵션이 있는데 LocationID=null 행이 1개가 아닌 줄 ' + optNoNullLoc + ' (PUT 의 Default 자리)');
  say('옵션에 나온 창고 ' + JSON.stringify(Object.keys(locNameSet)));
  say('0 이 아닌 값  ' + JSON.stringify(nz) + '  ← 전부 0 이면 Cin7 에서 안 쓰는 칸이다');

  /* 비활성 공급처 목록 — 범위 판단용 */
  say('');
  say('══ 제품에 붙어 있는 비활성 공급처 ══');
  Object.keys(supSetInactive).forEach(function (g) { say('  ' + supSetInactive[g] + '  ' + g); });

  say('');
  say('══ 활성인데 살 곳이 없는 제품 (표본 최대 300) ══');
  say(zeroActive.slice(0, 300).join(', '));

  var sh = psp_tab_(ss, 'psp_report', ['line']);
  var rows = out.map(function (s) { return [s]; });
  sh.getRange(2, 1, rows.length, 1).setValues(rows);
  sh.setColumnWidth(1, 900);
  Logger.log('— 위 내용을 psp_report 탭에도 적었다');
}

function psp_step5_crosscheck() {
  var ss = psp_sheet_();
  var P = ss.getSheetByName('psp_product').getDataRange().getValues();
  var pi = {};
  PSP_PROD_HEAD.forEach(function (h, i) { pi[h] = i; });

  var SUFFIX = /-(\d+|EA-ALT-UPC)$/i;   // 체일 뿐이다. 정본 아님

  var A = [], B = [];
  for (var i = 1; i < P.length; i++) {
    var r = P[i];
    if (r[pi.ProductType] !== 'Stock') continue;
    if (r[pi.ProductStatus] !== 'Active') continue;
    var sku = String(r[pi.SKU] || '');
    var lines = Number(r[pi.Lines] || 0);
    var hasSuffix = SUFFIX.test(sku);

    if (lines > 0 && hasSuffix) A.push(sku);
    if (lines === 0 && !hasSuffix) B.push(sku);
  }

  var out = [];
  function say(s) { out.push(s); Logger.log(s); }

  say('A. 활성 · 공급처 줄 있음 · 접미사 있음 = ' + A.length + '건');
  say('B. 활성 · 공급처 줄 없음 · 접미사 없음 = ' + B.length + '건');
  say('');
  say('── A 전체 (SQL IN 절용) ──');
  say(psp_sqlList_(A));
  say('');
  say('── B 전체 (SQL IN 절용) ──');
  say(psp_sqlList_(B));

  var sh = psp_tab_(ss, 'psp_cross', ['line']);
  var rows = out.map(function (s) { return [s]; });
  sh.getRange(2, 1, rows.length, 1).setValues(rows);
  sh.setColumnWidth(1, 900);
  Logger.log('— psp_cross 탭에도 적었다');
}

function psp_sqlList_(arr) {
  if (!arr.length) return '(없음)';
  if (arr.length > 1200) {
    return '⚠️ ' + arr.length + '건 — IN 절로 넣기엔 많다. psp_cross 탭에서 열로 받아라\n' +
           arr.slice(0, 50).join(', ') + ' …';
  }
  return "'" + arr.join("','") + "'";
}

var PSP_DP_SKUS = [
  'CVT18157', 'ELO82320', 'UNF18155', 'UNF18158', 'UNF18250', 'UNF18251', 'UNF18265'
];

function psp_step6_dpbom() {
  var out = [];
  function say(s) { out.push(s); Logger.log(s); }

  PSP_DP_SKUS.forEach(function (sku, idx) {
    if (idx > 0) Utilities.sleep(1200);

    // ⚠️ Sku 는 contains 검색이다 — 받은 뒤 정확히 일치하는 것만 고른다
    var d = psp_get_('product', { Sku: sku, Limit: 100, IncludeDeprecated: true, IncludeBOM: true });
    var hits = (d.Products || []).filter(function (p) { return p.SKU === sku; });

    if (!hits.length) {
      say('── ' + sku + ' : ⚠️ 응답에 정확히 일치하는 SKU 가 없다 (Total ' + d.Total + ')');
      return;
    }
    var p = hits[0];
    var bom = p.BillOfMaterialsProducts || [];
    say('── ' + sku + ' : Type=' + p.Type + ' · Status=' + p.Status + ' · UOM=' + p.UOM +
        ' · BOMType=' + p.BOMType + ' · 구성품 ' + bom.length + '개');
    say('   AutoAssembly=' + p.AutoAssembly + ' · AutoDisassembly=' + p.AutoDisassembly +
        ' · CostingMethod=' + p.CostingMethod);
    bom.forEach(function (b) {
      say('     · ' + b.ProductCode + '  x' + b.Quantity +
          '  (' + (b.Name || '') + ')  ComponentProductID=' + b.ComponentProductID);
    });
    if (!bom.length) {
      // BOM 이 비었으면 다른 칸에 구성이 숨어 있는지 본다 — 칸 이름을 통째로 찍는다
      say('   ⚠️ BOM 이 비었다. 배열·객체 칸 목록: ' +
          Object.keys(p).filter(function (k) {
            var v = p[k];
            return v && typeof v === 'object';
          }).map(function (k) {
            return k + '(' + (Array.isArray(p[k]) ? p[k].length : 'obj') + ')';
          }).join(' · '));
    }
  });

  var ss = psp_sheet_();
  var sh = psp_tab_(ss, 'psp_dpbom', ['line']);
  var rows = out.map(function (s) { return [s]; });
  sh.getRange(2, 1, rows.length, 1).setValues(rows);
  sh.setColumnWidth(1, 900);
  Logger.log('— psp_dpbom 탭에도 적었다');
}

var PSP_BOM_STATE = 'PSP_BOM_SWEEP_STATE';
var PSP_BOM_HEAD = ['SKU', 'Name', 'Status', 'Type', 'UOM', 'BOMType', 'CompCount',
                    'ComponentCode', 'Quantity', 'ComponentName', 'ComponentProductID', 'Page'];

function psp_step7_bomsweep() {
  var t0 = Date.now();
  var props = PropertiesService.getScriptProperties();
  var st = JSON.parse(props.getProperty(PSP_BOM_STATE) || 'null');

  var ss = psp_sheet_();
  var shB, shP;

  if (!st) {
    st = { page: 1, seen: 0, total: null, combos: 0, pages: [] };
    shB = psp_tab_(ss, 'psp_bom', PSP_BOM_HEAD);
    shP = psp_tab_(ss, 'psp_bompage', ['Page', 'Returned', 'CumSeen', 'Total']);
    Logger.log('새로 시작한다');
  } else {
    shB = ss.getSheetByName('psp_bom');
    shP = ss.getSheetByName('psp_bompage');
    Logger.log('이어받는다 — p' + st.page + ' · 누적 ' + st.seen + ' · 콤보 ' + st.combos);
  }

  while (true) {
    var r = psp_get_('product', {
      Page: st.page, Limit: 500, IncludeDeprecated: true, IncludeBOM: true
    });
    var items = r.Products || [];
    st.total = r.Total;
    if (!items.length) { st.done = true; break; }

    st.seen += items.length;
    shP.getRange(shP.getLastRow() + 1, 1, 1, 4).setValues([[st.page, items.length, st.seen, st.total]]);
    if (items.length < 500) {
      Logger.log('⚠️⚠️ p' + st.page + ' 가 ' + items.length + '행만 왔다 — ipr_loadBom_ 은 여기서 멈췄을 것이다');
    }

    var rows = [];
    items.forEach(function (p) {
      var bom = p.BillOfMaterialsProducts || [];
      if (bom.length < 2) return;
      st.combos++;
      bom.forEach(function (c) {
        rows.push([p.SKU, p.Name, p.Status, p.Type, p.UOM, p.BOMType, bom.length,
                   c.ProductCode, c.Quantity, c.Name, c.ComponentProductID, st.page]);
      });
    });
    if (rows.length) {
      shB.getRange(shB.getLastRow() + 1, 1, rows.length, PSP_BOM_HEAD.length).setValues(rows);
    }

    Logger.log('p' + st.page + ' — 받은 ' + items.length + ' · 누적 ' + st.seen + '/' + st.total +
               ' · 콤보 누적 ' + st.combos);

    st.page++;
    if (st.seen >= st.total) { st.done = true; break; }   // ⭐ Total 로 끝낸다
    props.setProperty(PSP_BOM_STATE, JSON.stringify(st));

    if (Date.now() - t0 > 4.5 * 60 * 1000) {
      Logger.log('⏸ 시간 예산 — psp_step7_bomsweep() 을 다시 누르면 p' + st.page + ' 부터 이어받는다');
      return;
    }
    Utilities.sleep(1200);
  }

  props.deleteProperty(PSP_BOM_STATE);
  Logger.log('───── 완료 ─────');
  Logger.log('본 행 ' + st.seen + ' / Total ' + st.total + ' · ⭐ 구성품 2개 이상 ' + st.combos +
             ' (적재된 것은 15)');
  Logger.log('페이지별 행 수는 psp_bompage · 콤보 구성품은 psp_bom 탭에 있다');
}

function psp_resetBomSweep() {
  PropertiesService.getScriptProperties().deleteProperty(PSP_BOM_STATE);
  Logger.log('BOM 훑기 상태를 지웠다');
}

// ─────────────────────────────────────────────────────────────
// 8) ⚠️ 목록 조회와 개별 조회의 BOM 이 다른가
//    p38 까지 전부 500 씩 왔고 콤보는 15 — 조기 종료가 아니었다(가설 기각 2026-09-14).
//    그런데 psp_step6_dpbom() 은 같은 SKU 에서 구성품 6~8개를 받았다.
//    차이는 호출 방식뿐 — 목록(Page+Limit) 대 개별(Sku=).
//    ⇒ 전량을 훑으며 제품마다 「목록 조회가 준 구성품 수」를 통째로 남기고,
//      일곱 건은 개별 조회와 나란히 찍는다. 다르면 목록 조회의 BOM 을 믿을 수 없다.
//    ⭐ 이 값이 틀리면 pack_factor · parent_product_id 도 같은 뿌리에서 나온 값이라 함께 의심 대상이다.
// ─────────────────────────────────────────────────────────────
var PSP_CMP_STATE = 'PSP_BOMCMP_STATE';

function psp_step8_bomcompare() {
  var t0 = Date.now();
  var props = PropertiesService.getScriptProperties();
  var st = JSON.parse(props.getProperty(PSP_CMP_STATE) || 'null');
  var ss = psp_sheet_();
  var sh;

  if (!st) {
    st = { page: 1, seen: 0, total: null };
    sh = psp_tab_(ss, 'psp_bomlen', ['SKU', 'Status', 'Type', 'UOM', 'ListBomCount', 'Page']);
    Logger.log('새로 시작한다 — 목록 조회가 주는 구성품 수를 전량 기록한다');
  } else {
    sh = ss.getSheetByName('psp_bomlen');
    Logger.log('이어받는다 — p' + st.page + ' · 누적 ' + st.seen);
  }

  while (true) {
    var r = psp_get_('product', { Page: st.page, Limit: 500, IncludeDeprecated: true, IncludeBOM: true });
    var items = r.Products || [];
    st.total = r.Total;
    if (!items.length) break;
    st.seen += items.length;

    var rows = items.map(function (p) {
      return [p.SKU, p.Status, p.Type, p.UOM, (p.BillOfMaterialsProducts || []).length, st.page];
    });
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, 6).setValues(rows);
    Logger.log('p' + st.page + ' — ' + items.length + ' (누적 ' + st.seen + '/' + st.total + ')');

    st.page++;
    if (st.seen >= st.total) break;
    props.setProperty(PSP_CMP_STATE, JSON.stringify(st));
    if (Date.now() - t0 > 4 * 60 * 1000) {
      Logger.log('⏸ 시간 예산 — 다시 누르면 p' + st.page + ' 부터 이어받는다');
      return;
    }
    Utilities.sleep(1200);
  }
  props.deleteProperty(PSP_CMP_STATE);
  Logger.log('훑기 완료 ' + st.seen + '/' + st.total);

  psp_step8b_sidebyside();
}

/** 시트에 남은 「목록이 준 수」와 개별 조회를 나란히 본다 (7콜) */
function psp_step8b_sidebyside() {
  var ss = psp_sheet_();
  var v = ss.getSheetByName('psp_bomlen').getDataRange().getValues();
  var listCount = {};
  for (var i = 1; i < v.length; i++) listCount[String(v[i][0])] = v[i][4];

  var out = [];
  function say(s) { out.push(s); Logger.log(s); }
  say('SKU          목록조회  개별조회   판정');

  var diff = 0;
  PSP_DP_SKUS.forEach(function (sku, idx) {
    if (idx > 0) Utilities.sleep(1200);
    var d = psp_get_('product', { Sku: sku, Limit: 100, IncludeDeprecated: true, IncludeBOM: true });
    var hit = (d.Products || []).filter(function (p) { return p.SKU === sku; })[0];
    var one = hit ? (hit.BillOfMaterialsProducts || []).length : '없음';
    var lst = (sku in listCount) ? listCount[sku] : '목록에 없음';
    var same = String(lst) === String(one);
    if (!same) diff++;
    say(psp_pad_(sku, 13) + psp_pad_(String(lst), 10) + psp_pad_(String(one), 10) +
        (same ? '같다' : '⚠️ 다르다'));
  });

  say('');
  say(diff ? '⚠️⚠️ 어긋난 것 ' + diff + '건 — 목록 조회의 BOM 을 믿을 수 없다'
           : '어긋난 것 없음 — 원인은 다른 데 있다');

  // 목록 조회에서 BOM 이 비어 온 제품이 얼마나 되는지도 함께 남긴다
  var zero = 0, one1 = 0, multi = 0;
  for (var j = 1; j < v.length; j++) {
    var n = Number(v[j][4] || 0);
    if (n === 0) zero++; else if (n === 1) one1++; else multi++;
  }
  say('목록 조회 기준 — BOM 없음 ' + zero + ' · 1개 ' + one1 + ' · 2개 이상 ' + multi);

  var sh = psp_tab_(ss, 'psp_bomcmp', ['line']);
  sh.getRange(2, 1, out.length, 1).setValues(out.map(function (s) { return [s]; }));
  sh.setColumnWidth(1, 700);
}

function psp_pad_(s, n) { s = String(s); while (s.length < n) s += ' '; return s; }

function psp_resetBomCompare() {
  PropertiesService.getScriptProperties().deleteProperty(PSP_CMP_STATE);
  Logger.log('BOM 대조 상태를 지웠다');
}

// ─────────────────────────────────────────────────────────────
// 9) ⚠️ 합계가 한 줄 빈다 — 12,729 인데 상태별·통화별 합이 12,728
//    [Claude Code 검토 2026-09-14] SupplierID 와 Currency 가 둘 다 빈 줄이 하나 있는 것으로 보인다.
//    그 줄의 정체를 시트에서 찾는다 (Cin7 재호출 없음).
//    함께 재는 것:
//      · (product_id, supplier_id) 쌍 중복  ← 자연키 유니크를 걸 수 있는지의 근거
//      · ProductSupplierID 중복             ← 충돌 키로 쓸 수 있는지의 근거
//      · 통화 종류 전수                      ← KRW 가 있는지
// ─────────────────────────────────────────────────────────────
function psp_step9_gaps() {
  var ss = psp_sheet_();
  var L = ss.getSheetByName('psp_line').getDataRange().getValues();
  var ci = {};
  PSP_LINE_HEAD.forEach(function (h, i) { ci[h] = i; });

  var out = [];
  function say(s) { out.push(s); Logger.log(s); }

  var pairSeen = {}, pairDup = [], psidSeen = {}, psidDup = [];
  var noSup = [], noCur = [], curSet = {}, stSet = {};
  var n = 0;

  for (var i = 1; i < L.length; i++) {
    var r = L[i];
    if (r[ci.ProductType] !== 'Stock') continue;
    n++;

    var sid = String(r[ci.SupplierID] || '');
    var cur = String(r[ci.Currency] || '');
    var st  = String(r[ci.SupStatus] || '');
    stSet[st || '(빈값)'] = (stSet[st || '(빈값)'] || 0) + 1;
    curSet[cur || '(빈값)'] = (curSet[cur || '(빈값)'] || 0) + 1;

    if (!sid) noSup.push([r[ci.SKU], r[ci.SupplierName], r[ci.ProductSupplierID]].join(' | '));
    if (!cur) noCur.push([r[ci.SKU], r[ci.SupplierName], sid].join(' | '));

    var key = r[ci.SKU] + '|' + sid;
    if (pairSeen[key]) pairDup.push(key); else pairSeen[key] = 1;

    var ps = String(r[ci.ProductSupplierID] || '');
    if (!ps) psidDup.push('(빈값) ' + r[ci.SKU]);
    else if (psidSeen[ps]) psidDup.push(ps + ' ' + r[ci.SKU]); else psidSeen[ps] = 1;
  }

  say('Type=Stock 줄 ' + n);
  say('공급처 상태별 ' + JSON.stringify(stSet));
  say('통화 전수 ' + JSON.stringify(curSet));
  say('');
  say('⭐ SupplierID 빈 줄 ' + noSup.length);
  noSup.forEach(function (s) { say('   ' + s); });
  say('⭐ Currency 빈 줄 ' + noCur.length);
  noCur.forEach(function (s) { say('   ' + s); });
  say('');
  say('⭐⭐ (SKU, SupplierID) 쌍 중복 ' + pairDup.length + '  ← 0 이면 자연키 유니크를 걸 수 있다');
  pairDup.slice(0, 20).forEach(function (s) { say('   ' + s); });
  say('⭐⭐ ProductSupplierID 중복·빈값 ' + psidDup.length + '  ← 0 이면 충돌 키로 쓸 수 있다');
  psidDup.slice(0, 20).forEach(function (s) { say('   ' + s); });

  var sh = psp_tab_(ss, 'psp_gaps', ['line']);
  sh.getRange(2, 1, out.length, 1).setValues(out.map(function (s) { return [s]; }));
  sh.setColumnWidth(1, 800);
}

// ─────────────────────────────────────────────────────────────
// 10) ⭐ 콤보의 방향 — 묶는 것인가 가르는 것인가
//    [Caleb 2026-09-14] DP 일곱은 낱개로 사서 우리가 묶는다.
//                       립오일 셋(UNF18259~61)은 디스플레이로 사서 우리가 갈라 판다.
//    ⇒ 같은 「구성품 2개 이상」인데 재고가 흐르는 방향이 반대다.
//      Cin7 이 이것을 구별하고 있나? AutoAssembly · AutoDisassembly 로 갈리는지 본다.
//      갈리면 긁어오면 되고, 안 갈리면 API 에 없는 것이라 우리 칸으로 가져야 한다(⑤ 에서).
//    ⚠️ 콤보 15 전수를 본다 — 일곱만 보면 또 부류를 놓친다. 15콜.
// ─────────────────────────────────────────────────────────────
var PSP_COMBO_SKUS = [
  'CVT18157', 'ELO82320', 'UNF18155', 'UNF18158', 'UNF18250', 'UNF18251', 'UNF18265',
  'UNF18259', 'UNF18260', 'UNF18261', 'AS-DSPLY',
  'JAL99890CB', 'JAL99891CB', 'JAL99892CB', 'JAL99893CB'
];

function psp_step10_bomdirection() {
  var out = [];
  function say(s) { out.push(s); Logger.log(s); }

  say(psp_pad_('SKU', 13) + psp_pad_('UOM', 5) + psp_pad_('BOMType', 11) +
      psp_pad_('AutoAsm', 9) + psp_pad_('AutoDisasm', 12) + psp_pad_('구성품', 7) + '공급사 매입');
  var keysAll = {};

  PSP_COMBO_SKUS.forEach(function (sku, idx) {
    if (idx > 0) Utilities.sleep(1200);
    var d = psp_get_('product', { Sku: sku, Limit: 100, IncludeDeprecated: true, IncludeBOM: true });
    var p = (d.Products || []).filter(function (x) { return x.SKU === sku; })[0];
    if (!p) { say(psp_pad_(sku, 13) + '⚠️ 못 찾음'); return; }

    Object.keys(p).forEach(function (k) {
      if (/assembl|disassembl|direction|kit|bundle|pack/i.test(k)) keysAll[k] = p[k];
    });

    say(psp_pad_(sku, 13) +
        psp_pad_(String(p.UOM), 5) +
        psp_pad_(String(p.BOMType), 11) +
        psp_pad_(String(p.AutoAssembly), 9) +
        psp_pad_(String(p.AutoDisassembly), 12) +
        psp_pad_(String((p.BillOfMaterialsProducts || []).length), 7) +
        (sku.indexOf('UNF1825') === 0 || sku.indexOf('JAL') === 0 ? '(공급처 줄 있음)' : ''));
  });

  say('');
  say('⭐ 조립·분해 관련 칸 전부: ' + JSON.stringify(keysAll));
  say('⚠️ 위 표에서 두 부류가 갈리면 Cin7 이 구별하는 것이고, 값이 전부 같으면 API 에 방향이 없다.');

  var ss = psp_sheet_();
  var sh = psp_tab_(ss, 'psp_bomdir', ['line']);
  sh.getRange(2, 1, out.length, 1).setValues(out.map(function (s) { return [s]; }));
  sh.setColumnWidth(1, 800);
}
