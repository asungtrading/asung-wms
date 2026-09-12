/**
 * SupplierProbe.gs — Cin7 공급처 실측 (IMS PO 모듈 ② 공급처)
 * 2026-09-11 아침 세션에서 작성
 *
 * ⚠️ 읽기 전용 — Cin7 만 읽는다. Supabase 에 쓰지 않는다.
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다.
 * ⚠️ 최상위 const 금지 (기존 프로젝트 상수와 충돌하면 프로젝트 전체가 죽는다)
 * ⚠️ 식별자는 ASCII 만 (2026-09-11 실사고: 한자 변수명 → ReferenceError)
 * ⚠️ 트리거를 걸지 마라 (20/20 한도) — 손으로 실행하는 용도다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 함수 둘
 *   spProbeSupplierDeprecated  비활성 포함 전량 실측 (전량 688 = 활성 226 + 비활성 462)
 *   spkProbeSupplierKind       발주처인가 경비처인가 (활성 226 을 시트로 뽑는다)
 *
 * 2026-09-11 실측 결과 요약
 *   Total   IncludeDeprecated=false 226 · =true 688
 *   Status  Active 226 · Deprecated 462
 *   ⭐ 이름 중복 688행 전수 0 (원문·정규화 모두) → name 자연키 가능
 *   비활성 462곳의 AdditionalAttribute1 = Service Supplier 457 (경비 지출처)
 *   ⚠️ KRW 1곳 (IPOS Systems · 비활성)
 *   Addresses 최대 2 · Contacts 최대 4 → 표 셋이 되는 이유
 *   ⚠️ AdditionalAttribute1 은 구분 기준이 아니다 — 활성 72곳 빈값 · 154곳 중 8곳이 판정과 어긋남
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   ① 비활성 포함 전량 실측
   ═══════════════════════════════════════════════════════════ */

function spProbeSupplierDeprecated() {
  var act = sp_fetchSuppliers_(false);   // IncludeDeprecated 미사용
  var all = sp_fetchSuppliers_(true);    // 비활성 포함

  var out = [];
  out.push('=== 공급처 프로브 ' + new Date().toISOString() + ' ===');
  out.push('IncludeDeprecated=false  받은 행 ' + act.rows.length + ' / Total ' + act.total);
  out.push('IncludeDeprecated=true   받은 행 ' + all.rows.length + ' / Total ' + all.total);

  // (1) ID 기준 차집합 — 비활성으로만 나오는 행
  var actIds = {};
  act.rows.forEach(function (s) { actIds[s.ID] = true; });
  var only = all.rows.filter(function (s) { return !actIds[s.ID]; });
  out.push('');
  out.push('(1) 비활성에서만 나온 행: ' + only.length + '건');

  // (2) Status 값의 종류
  out.push('');
  out.push('(2) Status 값 분포 (전체)');
  sp_countBy_(all.rows, function (s) { return String(s.Status); }).forEach(function (r) {
    out.push('   ' + r.k + ' : ' + r.n);
  });

  // (3) 이름 중복 — 자연키 판단의 핵심
  out.push('');
  out.push('(3) 이름 중복 (전체 ' + all.rows.length + '행 기준)');
  out.push('   -- 원문 그대로');
  var dupRaw = sp_dupGroups_(all.rows, function (s) { return String(s.Name); });
  out.push('      묶음 ' + dupRaw.length + '개');
  dupRaw.forEach(function (g) {
    out.push('      * "' + g.k + '" x' + g.rows.length + ' -> ' +
      g.rows.map(function (s) { return s.Status + '/' + s.Currency + '/' + s.ID; }).join(' | '));
  });
  out.push('   -- 정규화(소문자 · 앞뒤 공백 제거 · 연속 공백 1칸)');
  var dupNorm = sp_dupGroups_(all.rows, function (s) {
    return String(s.Name).toLowerCase().trim().replace(/\s+/g, ' ');
  });
  out.push('      묶음 ' + dupNorm.length + '개');
  dupNorm.forEach(function (g) {
    out.push('      * "' + g.k + '" x' + g.rows.length + ' -> ' +
      g.rows.map(function (s) { return '[' + s.Name + '] ' + s.Status + '/' + s.ID; }).join(' | '));
  });

  // (4) 비활성 전용 행이 쓰는 참조 문자열 — 활성에 없던 값이 있는가
  out.push('');
  out.push('(4) 비활성 전용 행의 참조 값 (활성 집합에 없던 것만)');
  ['PaymentTerm', 'AccountPayable', 'Currency', 'TaxRule'].forEach(function (f) {
    var known = {};
    act.rows.forEach(function (s) { known[String(s[f])] = true; });
    var novel = sp_countBy_(only, function (s) { return String(s[f]); })
      .filter(function (r) { return !known[r.k]; });
    out.push('   ' + f + ' — 새 값 ' + novel.length + '종' +
      (novel.length ? ' : ' + novel.map(function (r) { return r.k + '(' + r.n + ')'; }).join(' · ') : ''));
  });

  // (5) 비활성 전용 행의 빈 값 — NOT NULL 을 걸 수 있는지
  out.push('');
  out.push('(5) 비활성 전용 행의 빈 값 (null · 빈 문자열)');
  ['Name', 'Currency', 'PaymentTerm', 'AccountPayable', 'TaxRule'].forEach(function (f) {
    var blank = only.filter(function (s) {
      return s[f] === null || s[f] === undefined || String(s[f]).trim() === '';
    }).length;
    out.push('   ' + f + ' : ' + blank + ' / ' + only.length);
  });

  // (6) 주소·연락처 최대 개수 — 표 셋이 되는 근거
  out.push('');
  var maxA = 0, maxC = 0;
  all.rows.forEach(function (s) {
    maxA = Math.max(maxA, (s.Addresses || []).length);
    maxC = Math.max(maxC, (s.Contacts || []).length);
  });
  out.push('(6) Addresses 최대 ' + maxA + ' · Contacts 최대 ' + maxC + ' (비활성 포함 전체)');

  // (7) 비활성 전용 행 목록
  out.push('');
  out.push('(7) 비활성 전용 행 (최대 30건)');
  only.slice(0, 30).forEach(function (s) {
    out.push('   ' + s.Status + ' | ' + s.Name + ' | ' + s.Currency + ' | ' +
      s.PaymentTerm + ' | ' + s.AccountPayable);
  });

  var text = out.join('\n');
  Logger.log(text);
  return text;
}


/* ═══════════════════════════════════════════════════════════
   ② 발주처인가 경비처인가 — 활성 226 을 시트로
   ═══════════════════════════════════════════════════════════ */

function spkProbeSupplierKind() {
  var act = sp_fetchSuppliers_(false);
  var all = sp_fetchSuppliers_(true);

  var actIds = {};
  act.rows.forEach(function (s) { actIds[s.ID] = true; });
  var dep = all.rows.filter(function (s) { return !actIds[s.ID]; });

  var out = [];
  out.push('=== 공급처 성격 프로브 ' + new Date().toISOString() + ' ===');
  out.push('활성 ' + act.rows.length + ' · 비활성 ' + dep.length);

  // (1) AdditionalAttribute1 — 활성 / 비활성 각각
  out.push('');
  out.push('(1) AdditionalAttribute1 분포');
  [['활성', act.rows], ['비활성', dep]].forEach(function (pair) {
    out.push('   -- ' + pair[0] + ' ' + pair[1].length + '곳');
    sp_countBy_(pair[1], function (s) {
      var v = s.AdditionalAttribute1;
      return (v === null || v === undefined || String(v).trim() === '') ? '(빈값)' : String(v);
    }).forEach(function (r) { out.push('      ' + r.k + ' : ' + r.n); });
  });

  // (2) AccountPayable x AdditionalAttribute1 교차 — 회계상 구분선인지
  out.push('');
  out.push('(2) AccountPayable 분포');
  [['활성', act.rows], ['비활성', dep]].forEach(function (pair) {
    out.push('   -- ' + pair[0]);
    sp_countBy_(pair[1], function (s) {
      var v = s.AdditionalAttribute1;
      var t = (v === null || v === undefined || String(v).trim() === '') ? '(빈값)' : String(v);
      return String(s.AccountPayable) + ' x ' + t;
    }).forEach(function (r) { out.push('      ' + r.k + ' : ' + r.n); });
  });

  // (3) 활성 226곳의 PaymentTerm 분포
  out.push('');
  out.push('(3) 활성 226곳의 PaymentTerm 분포');
  sp_countBy_(act.rows, function (s) { return String(s.PaymentTerm); })
    .sort(function (a, b) { return b.n - a.n; })
    .forEach(function (r) { out.push('      ' + r.k + ' : ' + r.n); });

  // (4) KRW 공급처가 누구인지
  out.push('');
  out.push('(4) KRW 공급처');
  all.rows.filter(function (s) { return String(s.Currency) === 'KRW'; })
    .forEach(function (s) {
      out.push('      ' + s.Status + ' | ' + s.Name + ' | ' + s.PaymentTerm +
        ' | ' + s.AccountPayable + ' | ' + s.AdditionalAttribute1);
    });

  Logger.log(out.join('\n'));

  // (5) 활성 226곳 전체를 시트로 — 눈으로 판정하고 O/X 를 적을 수 있게
  spk_writeSheet_(act.rows);
  return out.join('\n');
}

/** 활성 공급처를 새 스프레드시트에 쓴다 (기존 시트를 건드리지 않는다) */
function spk_writeSheet_(rows) {
  var ss = SpreadsheetApp.create('공급처 판정 ' +
    Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
  var sh = ss.getActiveSheet();
  sh.setName('활성 공급처');

  var header = ['판정(O=발주처 / X=경비처 / ?=모름)', 'Name', 'Currency', 'PaymentTerm',
                'AccountPayable', 'TaxRule', 'Discount', 'AdditionalAttribute1',
                '주소수', '연락처수', 'Comments', 'TaxNumber', 'LastModifiedOn', 'ID'];
  var data = rows.map(function (s) {
    return ['', s.Name, s.Currency, s.PaymentTerm, s.AccountPayable, s.TaxRule,
            s.Discount, s.AdditionalAttribute1 || '',
            (s.Addresses || []).length, (s.Contacts || []).length,
            s.Comments || '', s.TaxNumber || '', s.LastModifiedOn || '', s.ID];
  });
  data.sort(function (a, b) { return String(a[1]).localeCompare(String(b[1])); });

  sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold');
  sh.getRange(2, 1, data.length, header.length).setValues(data);
  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 240);
  sh.setColumnWidth(2, 320);
  sh.getRange(2, 1, data.length, 1).setBackground('#fff8e1');

  Logger.log('시트: ' + ss.getUrl());
}


/* ═══════════════════════════════════════════════════════════
   공통
   ═══════════════════════════════════════════════════════════ */

/**
 * 공급처 전량
 * ⚠️ 배열 키는 SupplierList
 * ⚠️ sleep 1200ms — 공급처는 7페이지라 이 정도로 충분하다.
 *    (ref/location 처럼 27페이지짜리는 2500ms 가 필요하다 — ImsRefLoad.gs 참조)
 */
function sp_fetchSuppliers_(includeDeprecated) {
  var base = 'https://inventory.dearsystems.com/ExternalApi/v2/';
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  var rows = [], page = 1, total = null;
  while (true) {
    var url = base + 'supplier?Page=' + page + '&Limit=100' +
      (includeDeprecated ? '&IncludeDeprecated=true' : '');
    var res = UrlFetchApp.fetch(url, { method: 'GET', headers: headers, muteHttpExceptions: true });

    if (res.getResponseCode() === 429) {
      Logger.log('   429 — 65초 대기 후 재시도 (page ' + page + ')');
      Utilities.sleep(65000);
      continue;
    }
    if (res.getResponseCode() !== 200) {
      throw new Error('Cin7 ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }

    var data = JSON.parse(res.getContentText());
    var items = data.SupplierList || [];
    if (total === null) total = data.Total;
    rows = rows.concat(items);
    if (items.length < 100 || rows.length >= total) break;
    page++;
    Utilities.sleep(1200);
  }
  return { rows: rows, total: total };
}

function sp_countBy_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).sort().map(function (k) { return { k: k, n: m[k] }; });
}

function sp_dupGroups_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); (m[k] = m[k] || []).push(r); });
  return Object.keys(m).filter(function (k) { return m[k].length > 1; })
    .sort().map(function (k) { return { k: k, rows: m[k] }; });
}
