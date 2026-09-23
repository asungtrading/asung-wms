/**
 * CaseDiscountProbe.gs — Cin7 케이스 할인(UOM 태그) 실측 (IMS SO 모듈 · 할인 규칙 차수 전)
 * 2026-09-23 작성 · 정본 so-module.md §12(할인 규칙 차수는 쓰기 ①과 ② 사이)
 *
 * ⚠️ 읽기 전용 — Cin7 만 읽는다. Supabase 에 쓰지 않는다.
 *    쓰는 곳은 Google Drive 의 새 폴더 하나(수집 JSON · 보고서)와 Script Properties 의 CDP_* 키 넷뿐이다.
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다(ImsRefLoad.gs 와 같은 프로젝트).
 * ⚠️ 최상위 const·var 금지 · 식별자 ASCII 만 · 트리거를 걸지 마라(손으로 실행)
 * ⚠️ 이 파일의 이름은 전부 cdp 로 시작한다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY (getProp 은 Config.gs 에 이미 있다)
 *
 * 배경(Caleb 2026-09-23)
 *   Cin7 은 낱개 제품에 태그 「GM20UOM12」 를 붙이고, 딜 「UOM Discount」 가 그 태그의 제품에 수량 기준 할인을 건다
 *   GM = General Merchandise · HS = Hair & Skin care · 「20」 = % · 「12」 = 몇 개 이상
 *   「케이스 수량에 맞는 태그를 넣고 있어」 · 「우리는 mix and match는 사용 안해」 · 판매는 낱개 SKU · 세트는 오더에 안 나온다
 *   ⇒ IMS 안: 「이 묶음은 케이스 수량 이상 사면 몇 %」 규칙 — 케이스 수량은 세트 계수(BOM Quantity)에서 찾는다
 *   이 프로브가 답할 물음 셋: ① % 는 무엇으로 묶으면 같아지나(브랜드 · 카테고리) ② 태그 수량 = 가장 작은 세트 계수인가 ③ 세트가 없는 태그 제품은 몇인가
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서
 *   1  cdpCollect   제품 전량(IncludeBOM · 500개씩 · 이어 달리기) — 「Next run」 이면 다시
 *   2  cdpAnalyze   보고서(로그 + Drive 폴더 report-*.txt)
 *   ⟲  cdpReset     다시 모을 때만
 *
 * 보고서
 *   (0) 받은 행 · Tags 가 있는 제품 · 태그 종류
 *   (1) 케이스 태그(GM|HS 숫자 UOM 숫자) — 태그별 제품 수 · 한 제품에 둘 이상 · 형식이 어긋난 비슷한 태그
 *   (2) 태그 수량 vs 그 제품의 세트 계수 — 가장 작은 세트와 같다 · 다른 세트와 같다 · 어느 세트와도 다르다 · 세트 없음 · 태그가 세트에 붙었다
 *   (3) % 는 무엇으로 묶이나 — 브랜드별 · 카테고리별 % 종류(하나면 그 묶음으로 규칙 하나)
 *   (4) GM · HS 머리 vs 카테고리
 *   (5) 태그 없는 낱개 중 세트가 있는 것 — 같은 브랜드에 태그 제품이 있는데 빠진 것(규칙으로 바꾸면 새로 할인이 걸린다)
 *   (6) 세일 태그 — DISC_YesSale · Clearance · DISC_NoSale_Stock 등 제품 수
 * ─────────────────────────────────────────────────────────────
 * 2026-09-23 실측 (Caleb 실행 · 16:36 EDT · 정본은 so-module 할인 규칙 절)
 *   제품 18,989 = API Total · Tags 있는 제품 12,372 · 태그 종류 1,245(ASS 9,127 · AOS 7,766 · EDM_NoSale 2,390 · BOTH_NoSale_Stock 1,421 …)
 *   케이스 태그 제품 1,217(Active 1,079) · GM20UOM12 806 · HS15UOM12 92 · GM20UOM6 79 · 형식 어긋난 UOM 태그 0
 *   태그 수량 vs 세트 계수 — 가장 작은 세트와 같다 1,163 · 더 큰 세트 9(단계 할인 SPR07301 등 · 태그 둘 8) · 다르다 5(AS00968GRE·PUR·RED · COC01450 · QHE01961) ·
 *                         세트 없음 48 · 세트에 붙은 태그 0
 *   % 는 브랜드로 안 묶인다(Kim & C 에 5·10·15·20) · 태그 브랜드 안 「세트 있고 태그 없는」 Active 낱개 1,323 — 브랜드 규칙이면 새로 할인이 걸린다
 *   ⇒ Caleb 판정: 태그 방식 유지 · 딜 줄 「몇 개 이상」(비움 · 숫자 · 케이스) · 빼기(태그 + 낱개 SKU) · 케이스 줄은 미리 보기 화면 뒤에
 *   딜이 쓰는 태그 DISC_YesSale 645 · Clearance 473 · DISC_NoSale_Stock 543
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   1  수집 — 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function cdpCollect() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('CDP_DONE') === '1') {
    Logger.log('이미 다 모았다 — cdpAnalyze 를 실행하라. 다시 모으려면 cdpReset 먼저.');
    return;
  }
  var folderId = props.getProperty('CDP_FOLDER_ID');
  var folder;
  if (folderId) {
    folder = DriveApp.getFolderById(folderId);
  } else {
    folder = DriveApp.createFolder('CaseDiscountProbe ' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
    props.setProperty('CDP_FOLDER_ID', folder.getId());
  }
  var lim = cdp_limit_();
  var startPage = Number(props.getProperty('CDP_NEXT_PAGE') || '1');
  var page = startPage, started = Date.now(), rows = [], done = false, total = null;
  while (Date.now() - started < 270000) {
    var data = cdp_get_('product?Page=' + page + '&Limit=' + lim + '&IncludeDeprecated=true&IncludeBOM=true');
    var items = data.Products || [];
    if (total === null) total = data.Total;
    items.forEach(function (x) { rows.push(cdp_trim_(x)); });
    if (items.length < lim) { done = true; break; }   // ⚠️ Total 이 아니라 받은 행 수로 끝을 판단한다
    page++;
    Utilities.sleep(1500);
  }
  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = 'pages-' + cdp_pad_(startPage) + '-' + cdp_pad_(lastPage) + '.json';
    folder.createFile(name, JSON.stringify(rows), MimeType.PLAIN_TEXT);
    Logger.log('저장: ' + name + ' · ' + rows.length + '개');
  }
  if (total !== null) props.setProperty('CDP_TOTAL', String(total));
  if (done) {
    props.setProperty('CDP_DONE', '1');
    props.deleteProperty('CDP_NEXT_PAGE');
    Logger.log('⭐ 수집 끝 — 마지막 페이지 ' + page + ' · API Total ' + total + ' · 이제 cdpAnalyze');
  } else {
    props.setProperty('CDP_NEXT_PAGE', String(page));
    Logger.log('Next run — 다음 페이지 ' + page + ' 부터 · cdpCollect 를 한 번 더 실행하라');
  }
  Logger.log('폴더: ' + folder.getUrl());
}

function cdpReset() {
  var props = PropertiesService.getScriptProperties();
  ['CDP_FOLDER_ID', 'CDP_NEXT_PAGE', 'CDP_DONE', 'CDP_TOTAL'].forEach(function (k) { props.deleteProperty(k); });
  Logger.log('CDP_* 속성을 비웠다 — Drive 폴더는 그대로 있다(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   2  세기
   ═══════════════════════════════════════════════════════════ */

function cdpAnalyze() {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('CDP_FOLDER_ID');
  if (!folderId) throw new Error('CDP_FOLDER_ID 없음 — cdpCollect 먼저');
  if (props.getProperty('CDP_DONE') !== '1') Logger.log('⚠️ 수집이 끝나지 않았다 — 모은 만큼만 센다');
  var folder = DriveApp.getFolderById(folderId);

  var raw = [];
  var files = folder.getFiles();
  while (files.hasNext()) {
    var f = files.next();
    if (/^pages-.*\.json$/.test(f.getName())) raw = raw.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  var byId = {}, ps = [], dup = 0;
  raw.forEach(function (x) { var id = String(x.ID).toLowerCase(); if (byId[id]) { dup++; return; } byId[id] = x; ps.push(x); });

  // 세트 → 낱개 잇기 (BOM 구성품 하나 = 세트 · 가르는 기준은 BOM · 이름·접미사 아님)
  var setsOf = {};   // 낱개 id → [{sku, qty, active}]
  ps.forEach(function (x) {
    if (x.BomN === 1 && x.BomParent) {
      var pid = String(x.BomParent).toLowerCase();
      (setsOf[pid] = setsOf[pid] || []).push({ sku: x.SKU, qty: Number(x.BomQty), active: x.Status === 'Active' });
    }
  });

  var out = [];
  var P = function (s) { out.push(s); };
  P('=== 케이스 할인 프로브 보고서 ' + new Date().toISOString() + ' ===');
  P('(0) 받은 행 ' + raw.length + ' · 고유 ID ' + ps.length + ' · 중복 ' + dup + ' · API Total ' + props.getProperty('CDP_TOTAL'));
  var withTags = ps.filter(function (x) { return cdp_tags_(x).length > 0; });
  var tagCount = {};
  withTags.forEach(function (x) { cdp_tags_(x).forEach(function (t) { tagCount[t] = (tagCount[t] || 0) + 1; }); });
  P('  Tags 가 있는 제품 ' + withTags.length + ' · 태그 종류 ' + Object.keys(tagCount).length);

  // (1) 케이스 태그
  var re = /^(GM|HS)(\d+)UOM(\d+)$/i;
  var caseTagged = [], nearMiss = {};
  ps.forEach(function (x) {
    var hits = [];
    cdp_tags_(x).forEach(function (t) {
      var m = t.match(re);
      if (m) hits.push({ tag: t, head: m[1].toUpperCase(), pct: Number(m[2]), qty: Number(m[3]) });
      else if (/uom/i.test(t)) nearMiss[t] = (nearMiss[t] || 0) + 1;
    });
    if (hits.length) caseTagged.push({ x: x, hits: hits });
  });
  P('');
  P('(1) 케이스 태그(GM|HS 숫자 UOM 숫자)가 붙은 제품 ' + caseTagged.length +
    ' · Active ' + caseTagged.filter(function (c) { return c.x.Status === 'Active'; }).length);
  var byTag = {};
  caseTagged.forEach(function (c) { c.hits.forEach(function (h) { byTag[h.tag.toUpperCase()] = (byTag[h.tag.toUpperCase()] || 0) + 1; }); });
  P('  태그별 제품 수: ' + Object.keys(byTag).sort().map(function (k) { return k + ' ' + byTag[k]; }).join(' · '));
  var multi = caseTagged.filter(function (c) { return c.hits.length > 1; });
  P('  ⚠️ 한 제품에 케이스 태그 둘 이상 ' + multi.length + (multi.length ? ' · 표본 ' + multi.slice(0, 10).map(function (c) { return c.x.SKU + '(' + c.hits.map(function (h) { return h.tag; }).join('+') + ')'; }).join(', ') : ''));
  var nm = Object.keys(nearMiss);
  P('  「UOM」 이 들어갔지만 형식이 다른 태그 ' + nm.length + (nm.length ? ' · ' + nm.slice(0, 15).map(function (k) { return k + ' ' + nearMiss[k]; }).join(' · ') : ''));

  // (2) 태그 수량 vs 세트 계수
  var r2 = { onSet: 0, eqMin: 0, eqOther: 0, noMatch: 0, noSet: 0 }, s2 = { onSet: [], eqOther: [], noMatch: [], noSet: [] };
  caseTagged.forEach(function (c) {
    var x = c.x;
    if (x.BomN === 1) { r2.onSet++; if (s2.onSet.length < 10) s2.onSet.push(x.SKU); return; }
    var sets = (setsOf[String(x.ID).toLowerCase()] || []).filter(function (s) { return s.qty > 0; });
    var qtys = sets.map(function (s) { return s.qty; }).sort(function (a, b) { return a - b; });
    c.hits.forEach(function (h) {
      if (!qtys.length) { r2.noSet++; if (s2.noSet.length < 15) s2.noSet.push(x.SKU + '(' + h.tag + ')'); return; }
      if (h.qty === qtys[0]) { r2.eqMin++; return; }
      if (qtys.indexOf(h.qty) >= 0) { r2.eqOther++; if (s2.eqOther.length < 15) s2.eqOther.push(x.SKU + '(' + h.tag + ' · 세트 ' + qtys.join('/') + ')'); return; }
      r2.noMatch++; if (s2.noMatch.length < 15) s2.noMatch.push(x.SKU + '(' + h.tag + ' · 세트 ' + qtys.join('/') + ')');
    });
  });
  P('');
  P('(2) 태그 수량 vs 그 낱개의 세트 계수(BOM Quantity)');
  P('  가장 작은 세트와 같다 ' + r2.eqMin + ' · 다른(더 큰) 세트와 같다 ' + r2.eqOther + ' · 어느 세트와도 다르다 ' + r2.noMatch + ' · 세트 없음 ' + r2.noSet + ' · 태그가 세트 제품에 붙었다 ' + r2.onSet);
  if (s2.eqOther.length) P('    다른 세트 표본 ' + s2.eqOther.join(', '));
  if (s2.noMatch.length) P('    다르다 표본 ' + s2.noMatch.join(', '));
  if (s2.noSet.length) P('    세트 없음 표본 ' + s2.noSet.join(', '));
  if (s2.onSet.length) P('    세트에 붙음 표본 ' + s2.onSet.join(', '));

  // (3) % 는 무엇으로 묶이나
  P('');
  P('(3) % 는 무엇으로 묶이나 — 묶음 안 % 종류가 하나면 그 묶음 규칙 하나로 된다');
  ['Brand', 'Category'].forEach(function (field) {
    var g = {};
    caseTagged.forEach(function (c) {
      var k = cdp_show_(c.x[field]);
      var e = g[k] || (g[k] = { n: 0, pcts: {} });
      e.n++;
      c.hits.forEach(function (h) { e.pcts[h.head + h.pct] = (e.pcts[h.head + h.pct] || 0) + 1; });
    });
    var keys = Object.keys(g).sort(function (a, b) { return g[b].n - g[a].n; });
    var single = keys.filter(function (k) { return Object.keys(g[k].pcts).length === 1; });
    P('  ' + field + ' ' + keys.length + '종 · % 가 하나뿐인 ' + field + ' ' + single.length + ' · 둘 이상 ' + (keys.length - single.length));
    keys.slice(0, 30).forEach(function (k) {
      P('     ' + k + ' — 제품 ' + g[k].n + ' · ' + Object.keys(g[k].pcts).sort().map(function (p) { return p + '%×' + g[k].pcts[p]; }).join(' '));
    });
  });

  // (4) GM · HS vs 카테고리
  P('');
  P('(4) 머리(GM · HS) vs 카테고리');
  ['GM', 'HS'].forEach(function (head) {
    var cats = {};
    caseTagged.forEach(function (c) { if (c.hits.some(function (h) { return h.head === head; })) { var k = cdp_show_(c.x.Category); cats[k] = (cats[k] || 0) + 1; } });
    P('  ' + head + ' — ' + Object.keys(cats).sort(function (a, b) { return cats[b] - cats[a]; }).map(function (k) { return k + ' ' + cats[k]; }).join(' · '));
  });

  // (5) 태그 없는 낱개 중 세트가 있는 것 — 태그 제품이 있는 브랜드 안에서
  var tagBrands = {};
  caseTagged.forEach(function (c) { tagBrands[cdp_show_(c.x.Brand)] = true; });
  var taggedIds = {};
  caseTagged.forEach(function (c) { taggedIds[String(c.x.ID).toLowerCase()] = true; });
  var missing = {}, missN = 0;
  ps.forEach(function (x) {
    if (x.Status !== 'Active' || x.Type !== 'Stock' || x.BomN) return;
    var id = String(x.ID).toLowerCase();
    if (taggedIds[id] || !setsOf[id]) return;
    var b = cdp_show_(x.Brand);
    if (!tagBrands[b]) return;
    missN++; missing[b] = (missing[b] || 0) + 1;
  });
  P('');
  P('(5) 케이스 태그가 있는 브랜드 안에서, 세트는 있는데 태그가 없는 Active 낱개 ' + missN + '  (브랜드 규칙으로 바꾸면 새로 할인이 걸릴 제품)');
  Object.keys(missing).sort(function (a, b) { return missing[b] - missing[a]; }).slice(0, 20).forEach(function (k) { P('     ' + k + ' ' + missing[k]); });

  // (6) 세일 태그
  P('');
  P('(6) 태그 상위 30(케이스 태그 제외)');
  Object.keys(tagCount).filter(function (t) { return !re.test(t); }).sort(function (a, b) { return tagCount[b] - tagCount[a]; }).slice(0, 30)
    .forEach(function (t) { P('     「' + t + '」 ' + tagCount[t]); });
  ['DISC_YesSale', 'Clearance', 'DISC_NoSale_Stock'].forEach(function (t) {
    var n = ps.filter(function (x) { return cdp_tags_(x).some(function (y) { return y.toLowerCase() === t.toLowerCase(); }); }).length;
    P('  딜이 쓰는 태그 「' + t + '」 제품 ' + n);
  });

  var text = out.join('\n');
  folder.createFile('report-' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm') + '.txt', text, MimeType.PLAIN_TEXT);
  for (var i = 0; i < text.length; i += 8000) Logger.log(text.slice(i, i + 8000));
}


/* ═══════════════════════════════════════════════════════════
   도우미
   ═══════════════════════════════════════════════════════════ */

function cdp_limit_() { return 500; }   // BOM 을 켜면 1000 이 안 온다(2026-09-13 실측)

function cdp_trim_(x) {
  var bom = x.BillOfMaterialsProducts || [];
  var o = { ID: x.ID, SKU: x.SKU, Status: x.Status, Type: x.Type, Brand: x.Brand, Category: x.Category, Tags: x.Tags, BomN: bom.length };
  if (bom.length) { o.BomParent = bom[0].ComponentProductID; o.BomQty = bom[0].Quantity; }
  return o;
}

/** Tags 는 쉼표로 이은 문자열(손님과 같다 · cin7-api customer.md) — 앞뒤 공백 제거 · 빈 것 버림 */
function cdp_tags_(x) {
  if (x.Tags === null || x.Tags === undefined) return [];
  return String(x.Tags).split(',').map(function (t) { return t.trim(); }).filter(function (t) { return t !== ''; });
}

function cdp_get_(pathAndQuery) {
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

function cdp_show_(v) { return (v === null || v === undefined || String(v).trim() === '') ? '(blank)' : String(v); }

function cdp_pad_(n) { return ('000' + n).slice(-4); }
