/**
 * CustomerProbe.gs — Cin7 손님 실측 (IMS SO 모듈 · 손님 표 셋 적재 전)
 * 2026-09-22 저녁 작성 · 정본 docs/design/so-module.md §9-e (적재 차수로 넘기는 것 열둘)
 *
 * ⚠️ 읽기 전용 — Cin7 만 읽는다. Supabase 에 쓰지 않는다.
 *    쓰는 곳은 Google Drive 의 새 폴더 하나(원본 JSON · 보고서)와 Script Properties 의 CUP_* 키 넷뿐이다.
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다(ImsRefLoad.gs 와 같은 프로젝트).
 * ⚠️ 최상위 const 금지 (기존 프로젝트 상수와 충돌하면 프로젝트 전체가 죽는다)
 * ⚠️ 식별자는 ASCII 만 (2026-09-11 실사고: 한자 변수명 → ReferenceError)
 * ⚠️ 트리거를 걸지 마라 (20/20 한도) — 손으로 실행하는 용도다
 * ⚠️ 이 파일의 이름은 전부 cup 로 시작한다 — 프로젝트 안 다른 파일과 겹치지 않게
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY (getProp 은 Config.gs 에 이미 있다)
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서
 *   1  cupPeek      첫 페이지 3명만 — 키 목록과 모양을 먼저 본다(호출 1번)
 *   2  cupCollect   전량 수집 — ⭐ 한 번에 다 안 끝나면 「Next run」이 뜬다. 끝날 때까지 다시 실행한다
 *                   (손님 9,452명 ≈ 95페이지 · 한 번에 약 4분 반까지만 돌고 멈춘다 · 6분 제한 대비)
 *   3  cupAnalyze   모은 것을 세어 보고서를 쓴다(Cin7 ref 호출 몇 번 더 · 결과는 Drive 폴더의 report-*.txt)
 *   ⟲  cupReset     처음부터 다시 모을 때만(폴더는 지우지 않는다 — 속성만 비운다)
 *
 *   뒤에 붙인 확인 함수 넷(2026-09-22 저녁 · 판정 근거)
 *      cupConsent     MarketingConsent 숫자 ↔ 화면 값 대조용 명단(수집 파일만)
 *      cupConsentOne  한 손님의 MarketingConsent — 지금 Cin7 값과 수집 값 나란히(호출 1번)
 *      cupAddrOne     한 손님의 주소 — 지금 Cin7 값(호출 1번 · 쓰기 뒤 재읽기용)
 *      cupNoShip      Shipping 없는 손님의 주소 구성(수집 파일만)
 *
 * 수집은 IncludeDeprecated=true — 비활성 포함 전량(적재도 비활성을 담는다 · 9-a ①)
 * ─────────────────────────────────────────────────────────────
 * 2026-09-22 실측 결과 (수집 16:52~16:56 EDT · 95페이지 · 한 번에 끝)
 *   Total 9,468 = 받은 행 9,468 = 고유 ID 9,468 · 중복 0   (09-21 프로브 때 9,452 — 16명 늘었다)
 *   Status        Active 9,460 · Deprecated 8 — 둘뿐 → is_active 하나로 충분
 *   ID            Address 19,001 · Contact 9,912 전부 있고 전부 고유 → 두 표 모두 cin7_id 가 적재 열쇠
 *   TaxNumber     필드명 확정 · 값 12
 *   Tags          쉼표로 이은 문자열 · null 8,009 · "" 603 · 값 856
 *   Address Type  Billing 9,806 · Shipping 9,191 · Business 4 · 셋 밖 0 · 빈 값 0
 *   손님당 주소    0개 18 · 1개 712 · 2개 8,286 · 3개 168 · 4+ 284
 *   DefaultForType 믿을 만하다 — Shipping 을 가진 손님 체크 1개 8,687 · 없고 하나 44 · 없고 여럿 7 · ⚠️ 둘 이상 1
 *                 Billing 체크 1개 9,432 · 없고 하나 5 · Business 체크 1 · 없고 하나 3
 *                 ⚠️ 둘 이상 1 = DALIANA MOMBRUN — 같은 배송지 중복 입력(실수) · Caleb 이 Cin7 에서 지움
 *                    20:50 EDT · cupAddrOne 재읽기로 Shipping 1 · Billing 1 확인
 *   Shipping 없음  711명 = Billing×1 699 · Billing×2 10 · Business×1 2 · 기본 Billing 있음 708 · 전원 Active
 *   Contact       Default 둘 이상 0 · 기본 없음 2 · IncludeInEmail true 869 · Fax 6 · Comment 18
 *                 ⚠️ JobTitle 이 온다 — 값 288(공급처 API 에는 없던 키) → job_title 칸을 더한다
 *   ⚠️⚠️ MarketingConsent 는 boolean 이 아니라 숫자다 — 순서가 선택 목록(Unknown·Opt in·Opt out)과 다르고 Unknown 이 둘
 *        0 = Unknown 13(Korean Aura)  ·  1 = Unknown 9,898(CHOPPAVARAPU SAIDA RAO)
 *        2 = Opt in 1(Asung Employee - Jason Lee)  ·  3 = Opt out 0 → Caleb 이 JOJOJO - Joel Chang 을 Opt out 으로 저장해 확인
 *        ⇒ 2 → true · 3 → false · 0·1 → null · 그 밖 → 적재를 멈춘다   (네 값 모두 Caleb 화면 대조)
 *        ⚠️ 「셋 중 남은 하나」 추론은 틀렸다(0 을 Opt out 으로 짐작했으나 화면은 Unknown) — 화면 대조 없이 옮기지 마라
 *   Currency      CAD 9,465 · USD 3 · 그 밖 0
 *   PaymentTerm 9종 · AccountReceivable 2종 · RevenueAccount 2종 — Cin7 ref 와 전부 이어진다
 *   Location      Asung Trading Inc. 9,327 · Asung - Edmonton 136 · 빈 값 5 — ref_warehouse.name 과 정확히 일치(SQL 확인)
 *   TaxRule 7종 · PriceTier 4종(Wholesale 7,421 · AONE 2,044 · Regular CAD 2 · USWholesale USD 1) · Discount ≠ 0 72명
 *   부모          부모 있는 손님 13 · 없는 부모 0 · 깊이 2+ 0 · 자기 참조 0 · ChildCustomers 있는 부모 5 · IsBillParent true 12
 *   빈 값         "" 와 null 이 섞여 온다(Line2 "" 13,764 · Phone null 6,216 …) → 적재 때 null 로 · 글자 안쪽 공백은 그대로
 *   이름 중복      원문 0 · 정규화 뒤 2 → name 유니크 안 건 판단이 맞다
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   1  첫 페이지 모양
   ═══════════════════════════════════════════════════════════ */

function cupPeek() {
  var r = cup_get_('customer?Page=1&Limit=3&IncludeDeprecated=true');
  var data = r.data;
  var out = [];
  out.push('=== 손님 peek ' + new Date().toISOString() + ' ===');
  out.push('최상위 키: ' + Object.keys(data).join(', '));
  out.push('Total: ' + data.Total);
  var list = data.CustomerList || [];
  out.push('CustomerList 행: ' + list.length);
  if (list.length) {
    var c = list[0];
    out.push('');
    out.push('손님 키: ' + Object.keys(c).join(', '));
    var a = (c.Addresses || [])[0];
    var k = (c.Contacts || [])[0];
    out.push('Address 키: ' + (a ? Object.keys(a).join(', ') : '(첫 손님에 주소 없음)'));
    out.push('Contact 키: ' + (k ? Object.keys(k).join(', ') : '(첫 손님에 연락처 없음)'));
  }
  out.push('');
  out.push(JSON.stringify(list[0] || {}, null, 1).slice(0, 3000));
  Logger.log(out.join('\n'));
}


/* ═══════════════════════════════════════════════════════════
   2  전량 수집 — 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function cupCollect() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('CUP_DONE') === '1') {
    Logger.log('이미 다 모았다 — cupAnalyze 를 실행하라. 다시 모으려면 cupReset 먼저.');
    return;
  }

  var folderId = props.getProperty('CUP_FOLDER_ID');
  var folder;
  if (folderId) {
    folder = DriveApp.getFolderById(folderId);
  } else {
    folder = DriveApp.createFolder('CustomerProbe ' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
    props.setProperty('CUP_FOLDER_ID', folder.getId());
  }

  var startPage = Number(props.getProperty('CUP_NEXT_PAGE') || '1');
  var page = startPage;
  var started = Date.now();
  var rows = [];
  var done = false;
  var total = null;

  while (Date.now() - started < 270000) {           // 4분 30초 — 새 페이지를 시작하지 않는 선
    var r = cup_get_('customer?Page=' + page + '&Limit=100&IncludeDeprecated=true');
    var items = r.data.CustomerList || [];
    if (total === null) total = r.data.Total;
    rows = rows.concat(items);
    if (items.length < 100) { done = true; break; }  // ⚠️ Total 이 아니라 받은 행 수로 끝을 판단한다(ImsRefLoad 주석)
    page++;
    Utilities.sleep(1500);
  }

  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = 'pages-' + cup_pad_(startPage) + '-' + cup_pad_(lastPage) + '.json';
    folder.createFile(name, JSON.stringify(rows), MimeType.PLAIN_TEXT);
    Logger.log('저장: ' + name + ' · ' + rows.length + '명');
  }
  if (total !== null) props.setProperty('CUP_TOTAL', String(total));

  if (done) {
    props.setProperty('CUP_DONE', '1');
    props.deleteProperty('CUP_NEXT_PAGE');
    Logger.log('⭐ 수집 끝 — 마지막 페이지 ' + page + ' · API Total ' + total + ' · 이제 cupAnalyze');
  } else {
    props.setProperty('CUP_NEXT_PAGE', String(page));
    Logger.log('Next run — 다음 페이지 ' + page + ' 부터 · cupCollect 를 한 번 더 실행하라');
  }
  Logger.log('폴더: ' + folder.getUrl());
}

function cupReset() {
  var props = PropertiesService.getScriptProperties();
  ['CUP_FOLDER_ID', 'CUP_NEXT_PAGE', 'CUP_DONE', 'CUP_TOTAL'].forEach(function (k) {
    props.deleteProperty(k);
  });
  Logger.log('CUP_* 속성을 비웠다 — Drive 폴더는 그대로 있다(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   3  세기 — so-module §9-e 순서대로
   ═══════════════════════════════════════════════════════════ */

function cupAnalyze() {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('CUP_FOLDER_ID');
  if (!folderId) throw new Error('CUP_FOLDER_ID 없음 — cupCollect 먼저');
  if (props.getProperty('CUP_DONE') !== '1') Logger.log('⚠️ 수집이 끝나지 않았다 — 모은 만큼만 센다');
  var folder = DriveApp.getFolderById(folderId);

  // ── 모으기 · ID 로 중복 제거 ──
  var raw = [];
  var files = folder.getFiles();
  var fileNames = [];
  while (files.hasNext()) {
    var f = files.next();
    if (!/^pages-.*\.json$/.test(f.getName())) continue;
    fileNames.push(f.getName());
    raw = raw.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  var byId = {}, dupIds = 0, cs = [];
  raw.forEach(function (c) {
    if (byId[c.ID]) { dupIds++; return; }
    byId[c.ID] = c; cs.push(c);
  });

  var out = [];
  var P = function (s) { out.push(s); };
  P('=== 손님 프로브 보고서 ' + new Date().toISOString() + ' ===');
  P('파일 ' + fileNames.sort().join(', '));
  P('받은 행 ' + raw.length + ' · 고유 ID ' + cs.length + ' · 중복 ID ' + dupIds +
    ' · API Total ' + props.getProperty('CUP_TOTAL'));
  P('  (중복·누락은 수집 도중 손님이 추가·변경되어 페이지가 밀린 것일 수 있다 — Total 과 고유 ID 를 함께 본다)');

  // ── (0) 키 목록 — 무엇이 오는지 ──
  var addrs = [], conts = [];
  cs.forEach(function (c) {
    (c.Addresses || []).forEach(function (a) { addrs.push({ c: c, a: a }); });
    (c.Contacts || []).forEach(function (k) { conts.push({ c: c, k: k }); });
  });
  P('');
  P('(0) 키 목록 · 채움 수 (값이 null·빈 문자열이 아닌 행) · 값의 형');
  P('  -- 손님 ' + cs.length);
  cup_keyFill_(cs).forEach(function (s) { P('     ' + s); });
  P('  -- Address ' + addrs.length);
  cup_keyFill_(addrs.map(function (x) { return x.a; })).forEach(function (s) { P('     ' + s); });
  P('  -- Contact ' + conts.length);
  cup_keyFill_(conts.map(function (x) { return x.k; })).forEach(function (s) { P('     ' + s); });

  // ── (1) Status distinct · 9-a ① ──
  P('');
  P('(1) Status 분포 — 둘뿐인가(9-a ①)');
  cup_countBy_(cs, function (c) { return cup_show_(c.Status); }).forEach(function (r) { P('     ' + r.k + ' : ' + r.n); });

  // ── (2) Addresses[]·Contacts[] ID 유무 · 9-a ② ──
  P('');
  P('(2) 주소·연락처 ID — 있으면 cin7_id 가 적재 열쇠(9-a ②)');
  [['Address', addrs.map(function (x) { return x.a; })], ['Contact', conts.map(function (x) { return x.k; })]]
    .forEach(function (pair) {
      var withId = pair[1].filter(function (o) { return !cup_blank_(o.ID); });
      var uniq = {};
      withId.forEach(function (o) { uniq[o.ID] = (uniq[o.ID] || 0) + 1; });
      var dup = Object.keys(uniq).filter(function (k) { return uniq[k] > 1; }).length;
      P('     ' + pair[0] + ' 전체 ' + pair[1].length + ' · ID 있음 ' + withId.length +
        ' · 고유 ' + Object.keys(uniq).length + ' · 둘 이상 나온 ID ' + dup);
    });

  // ── (3) type 분포 · 검토 이견 2 ──
  P('');
  P('(3) Address Type — CHECK 는 Billing·Business·Shipping + null');
  cup_countBy_(addrs, function (x) { return cup_show_(x.a.Type); }).forEach(function (r) {
    var ok = r.k === '(blank)' || r.k === 'Billing' || r.k === 'Business' || r.k === 'Shipping';
    P('     ' + r.k + ' : ' + r.n + (ok ? '' : '   ⚠️ CHECK 밖 — 적재가 거부된다'));
  });
  var nAddr = {}, noShip = 0, bizNoShip = 0, noBill = 0, zeroAddr = 0;
  cs.forEach(function (c) {
    var t = {};
    (c.Addresses || []).forEach(function (a) { t[String(a.Type)] = true; });
    var n = (c.Addresses || []).length;
    var key = n >= 4 ? '4+' : String(n);
    nAddr[key] = (nAddr[key] || 0) + 1;
    if (n === 0) zeroAddr++;
    if (n > 0 && !t.Shipping) noShip++;
    if (t.Business && !t.Shipping) bizNoShip++;
    if (n > 0 && !t.Billing) noBill++;
  });
  P('     손님당 주소 수: ' + Object.keys(nAddr).sort().map(function (k) { return k + '개 ' + nAddr[k]; }).join(' · '));
  P('     주소 0개 손님 ' + zeroAddr);
  P('     주소는 있는데 Shipping 없음 ' + noShip + ' · ⭐ 그중 Business 는 있고 Shipping 없음 ' + bizNoShip);
  P('     주소는 있는데 Billing 없음 ' + noBill);

  // ── (4) DefaultForType 분포 · 9-a ③ ──
  P('');
  P('(4) DefaultForType — 체크를 믿을 수 있나(9-a ③)');
  cup_countBy_(addrs, function (x) { return cup_show_(x.a.DefaultForType); }).forEach(function (r) { P('     값 ' + r.k + ' : ' + r.n); });
  ['Shipping', 'Billing', 'Business'].forEach(function (ty) {
    var one = 0, many = 0, noneSingle = 0, noneMulti = 0, manyList = [];
    cs.forEach(function (c) {
      var g = (c.Addresses || []).filter(function (a) { return a.Type === ty; });
      if (!g.length) return;
      var chk = g.filter(function (a) { return a.DefaultForType === true; }).length;
      if (chk === 1) one++;
      else if (chk > 1) { many++; if (manyList.length < 20) manyList.push(c.Name + ' (' + chk + ')'); }
      else if (g.length === 1) noneSingle++;
      else noneMulti++;
    });
    P('     -- ' + ty + ' 을 가진 손님: 체크 1개 ' + one + ' · 체크 없고 그 주소 하나 ' + noneSingle +
      ' · 체크 없고 여럿 ' + noneMulti + ' · ⚠️ 체크 둘 이상 ' + many);
    if (many) P('        ⚠️ 유니크(default_customer_id, type)에 걸린다: ' + manyList.join(' | '));
  });

  // ── (5) Contacts — Default · IncludeInEmail · MarketingConsent · 9-a ④ ──
  P('');
  P('(5) 연락처 — 기본 · 메일 포함 · 마케팅 동의(9-a ④)');
  var nCont = {}, manyDef = 0, manyDefList = [], zeroDef = 0;
  cs.forEach(function (c) {
    var k = c.Contacts || [];
    var key = k.length >= 5 ? '5+' : String(k.length);
    nCont[key] = (nCont[key] || 0) + 1;
    var d = k.filter(function (x) { return x.Default === true; }).length;
    if (d > 1) { manyDef++; if (manyDefList.length < 20) manyDefList.push(c.Name + ' (' + d + ')'); }
    if (k.length && d === 0) zeroDef++;
  });
  P('     손님당 연락처 수: ' + Object.keys(nCont).sort().map(function (k) { return k + '개 ' + nCont[k]; }).join(' · '));
  P('     연락처는 있는데 기본 없음 ' + zeroDef + ' · ⚠️ 기본 둘 이상 ' + manyDef);
  if (manyDef) P('        ⚠️ 유니크(default_customer_id)에 걸린다: ' + manyDefList.join(' | '));
  ['Default', 'IncludeInEmail', 'MarketingConsent'].forEach(function (f) {
    P('     ' + f + ': ' + cup_countBy_(conts, function (x) { return cup_show_(x.k[f]); })
      .map(function (r) { return r.k + ' ' + r.n; }).join(' · '));
  });

  // ── (6) Contacts 키 — JobTitle · Fax · Comment · 9-c ⬜5 ──
  P('');
  P('(6) 연락처 칸 — JobTitle 이 오나 · Fax·Comment 채움(9-c ⬜5)');
  ['JobTitle', 'Fax', 'Comment'].forEach(function (f) {
    var has = conts.filter(function (x) { return Object.prototype.hasOwnProperty.call(x.k, f); }).length;
    var fill = conts.filter(function (x) { return !cup_blank_(x.k[f]); }).length;
    P('     ' + f + ' : 키 있음 ' + has + ' · 값 있음 ' + fill + ' / ' + conts.length);
  });
  var cmt = conts.filter(function (x) { return !cup_blank_(x.k.Comment); }).slice(0, 15);
  if (cmt.length) {
    P('     Comment 예(최대 15):');
    cmt.forEach(function (x) { P('        ' + x.c.Name + ' | ' + String(x.k.Comment).slice(0, 120)); });
  }

  // ── (7) currency · payment_term · account · location · 검토 이견 3 · 9-a ① ──
  P('');
  P('(7) 마스터를 가리키는 칸 — FK 가 못 붙을 수');
  P('     Currency: ' + cup_countBy_(cs, function (c) { return cup_show_(c.Currency); })
    .map(function (r) { return r.k + ' ' + r.n; }).join(' · ') + '   (ref_currency = CAD · USD · 기대: 그 밖 0)');

  var terms = cup_cin7All_('ref/paymentterm', 'PaymentTermList');
  var termNames = {};
  terms.forEach(function (t) { termNames[String(t.Name)] = true; });
  cup_unmatched_(P, cs, 'PaymentTerm', termNames, 'ref/paymentterm Name ' + terms.length + '종');

  var accts = cup_cin7All_('ref/account', 'AccountsList');       // ⚠️ 복수형 s
  var acctCodes = {};
  accts.forEach(function (a) { acctCodes[String(a.Code)] = true; });
  cup_unmatched_(P, cs, 'AccountReceivable', acctCodes, 'ref/account Code ' + accts.length + '개');
  cup_unmatched_(P, cs, 'RevenueAccount', acctCodes, 'ref/account Code ' + accts.length + '개');

  P('     Location 분포 (ref_warehouse 이름과 눈으로 대조 — ref/location 은 27페이지라 부르지 않는다):');
  cup_countBy_(cs, function (c) { return cup_show_(c.Location); }).forEach(function (r) { P('        ' + r.k + ' : ' + r.n); });
  P('     TaxRule 분포:');
  cup_countBy_(cs, function (c) { return cup_show_(c.TaxRule); }).forEach(function (r) { P('        ' + r.k + ' : ' + r.n); });
  P('     PriceTier 분포:');
  cup_countBy_(cs, function (c) { return cup_show_(c.PriceTier); }).forEach(function (r) { P('        ' + r.k + ' : ' + r.n); });
  var disc = cs.filter(function (c) { return Number(c.Discount || 0) !== 0; });
  P('     Discount 0 이 아닌 손님 ' + disc.length + (disc.length ? ' · 값: ' +
    cup_countBy_(disc, function (c) { return String(c.Discount); }).map(function (r) { return r.k + ' ' + r.n; }).join(' · ') : ''));

  // ── (8) tax_number 필드명 · tags 형식 · 5-a ⬜ · 검토 이견 5 ──
  P('');
  P('(8) Tax 이름이 든 키 · Tags 형식');
  var taxKeys = {};
  cs.forEach(function (c) { Object.keys(c).forEach(function (k) { if (/tax/i.test(k)) taxKeys[k] = true; }); });
  Object.keys(taxKeys).sort().forEach(function (k) {
    var fill = cs.filter(function (c) { return !cup_blank_(c[k]); }).length;
    P('     ' + k + ' : 값 있음 ' + fill);
  });
  P('     Tags 형: ' + cup_countBy_(cs, function (c) {
    var v = c.Tags;
    return v === null || v === undefined ? 'null' : Array.isArray(v) ? 'array' : typeof v;
  }).map(function (r) { return r.k + ' ' + r.n; }).join(' · '));
  var tagEx = {};
  cs.forEach(function (c) { if (!cup_blank_(c.Tags) && Object.keys(tagEx).length < 15) tagEx[JSON.stringify(c.Tags)] = true; });
  P('     Tags 예: ' + Object.keys(tagEx).join(' | '));

  // ── (9) 부모 먼저 · 9-a ① ──
  P('');
  P('(9) 부모·자식 — 적재 순서');
  var withParent = cs.filter(function (c) { return !cup_blank_(c.CustomerParentID); });
  var orphan = withParent.filter(function (c) { return !byId[c.CustomerParentID]; });
  var deep = withParent.filter(function (c) {
    var p = byId[c.CustomerParentID];
    return p && !cup_blank_(p.CustomerParentID);
  });
  var selfRef = withParent.filter(function (c) { return c.CustomerParentID === c.ID; });
  P('     부모 있음 ' + withParent.length + ' · ⚠️ 부모 ID 가 전량에 없음 ' + orphan.length +
    ' · 부모에도 부모가 있음(깊이 2 이상) ' + deep.length + ' · 자기 자신이 부모 ' + selfRef.length);
  orphan.slice(0, 10).forEach(function (c) { P('        없는 부모: ' + c.Name + ' → ' + c.CustomerParentName + ' / ' + c.CustomerParentID); });
  deep.slice(0, 10).forEach(function (c) { P('        깊이 2+: ' + c.Name + ' → ' + c.CustomerParentName); });
  P('     IsBillParent: ' + cup_countBy_(cs, function (c) { return cup_show_(c.IsBillParent); }).map(function (r) { return r.k + ' ' + r.n; }).join(' · '));
  P('     IsLegalEntity: ' + cup_countBy_(cs, function (c) { return cup_show_(c.IsLegalEntity); }).map(function (r) { return r.k + ' ' + r.n; }).join(' · '));
  var withKids = cs.filter(function (c) { return (c.ChildCustomers || []).length > 0; }).length;
  P('     ChildCustomers 있는 손님 ' + withKids + ' (부모 쪽에서 센 수 — 위 「부모 있음」과 맞춰 본다)');

  // ── (10) 빈 문자열 vs null · 검토 이견 2 ──
  P('');
  P('(10) 빈 문자열("")과 null — 적재 때 null 로 통일할 대상');
  [['Address', addrs.map(function (x) { return x.a; }), ['Line1', 'Line2', 'City', 'State', 'Postcode', 'Country', 'Type']],
   ['Contact', conts.map(function (x) { return x.k; }), ['Name', 'Phone', 'MobilePhone', 'Email', 'Website', 'Fax', 'Comment']],
   ['손님', cs, ['DisplayName', 'TaxRule', 'PriceTier', 'Location', 'Carrier', 'Comments', 'Tags']]]
    .forEach(function (tri) {
      P('     -- ' + tri[0]);
      tri[2].forEach(function (f) {
        var e = 0, n = 0, ws = 0, absent = 0;
        tri[1].forEach(function (o) {
          if (!Object.prototype.hasOwnProperty.call(o, f)) { absent++; return; }   // 키 자체가 없음 — null 과 가른다
          var v = o[f];
          if (v === null) n++;
          else if (v === '') e++;
          else if (typeof v === 'string' && v.trim() === '') ws++;
        });
        P('        ' + f + ' : "" ' + e + ' · null ' + n + ' · 공백만 ' + ws + ' · 키 없음 ' + absent);
      });
    });

  // ── (11) 이름 중복 — name 유니크를 안 건 근거(5-a) ──
  P('');
  P('(11) 이름 중복 — 5-a 는 name 에 유니크를 걸지 않았다');
  var dupRaw = cup_dupGroups_(cs, function (c) { return String(c.Name); });
  var dupNorm = cup_dupGroups_(cs, function (c) { return String(c.Name).toLowerCase().trim().replace(/\s+/g, ' '); });
  P('     원문 같은 이름 묶음 ' + dupRaw.length + ' · 정규화 뒤 묶음 ' + dupNorm.length);
  dupNorm.slice(0, 15).forEach(function (g) {
    P('        "' + g.k + '" x' + g.rows.length + ' → ' + g.rows.map(function (c) { return c.Status + '/' + c.ID; }).join(' | '));
  });

  // ── 쓰기 ──
  var text = out.join('\n');
  var rname = 'report-' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm') + '.txt';
  folder.createFile(rname, text, MimeType.PLAIN_TEXT);
  for (var i = 0; i < text.length; i += 8000) Logger.log(text.slice(i, i + 8000));
  Logger.log('보고서: ' + rname + ' · 폴더 ' + folder.getUrl());
}


/* ═══════════════════════════════════════════════════════════
   4  확인 함수 — 2026-09-22 저녁 판정 근거
   ═══════════════════════════════════════════════════════════ */

/** 수집 파일 전부 읽기 */
function cup_loadCollected_() {
  var files = DriveApp.getFolderById(PropertiesService.getScriptProperties().getProperty('CUP_FOLDER_ID')).getFiles();
  var cs = [];
  while (files.hasNext()) {
    var f = files.next();
    if (/^pages-.*\.json$/.test(f.getName())) cs = cs.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  return cs;
}

/** 마케팅 동의 숫자 ↔ 화면 값 대조 — 수집 파일만 읽는다(Cin7 호출 없음) */
function cupConsent() {
  var cs = cup_loadCollected_();
  var out = [];
  out.push('-- 화면에서 Unknown 인 손님');
  cs.filter(function (c) { return /choppavarapu/i.test(String(c.Name)); }).forEach(function (c) {
    (c.Contacts || []).forEach(function (k) {
      out.push('   ' + c.Name + ' | ' + k.Name + ' | MarketingConsent = ' + k.MarketingConsent);
    });
  });
  [0, 2].forEach(function (v) {
    out.push('-- MarketingConsent = ' + v);
    cs.forEach(function (c) {
      (c.Contacts || []).forEach(function (k) {
        if (k.MarketingConsent === v) out.push('   ' + c.Name + ' | ' + k.Name + ' | ' + (k.Email || ''));
      });
    });
  });
  Logger.log(out.join('\n'));
}

/** 한 손님의 MarketingConsent — 지금 Cin7 값과 수집 파일 값을 나란히 (Cin7 호출 1번) */
function cupConsentOne() {
  var name = 'JOJOJO';
  var now = cup_get_('customer?Page=1&Limit=10&IncludeDeprecated=true&Name=' + encodeURIComponent(name)).data.CustomerList || [];
  var out = ['-- 지금 Cin7 (Name 이 ' + name + ' 로 시작)'];
  now.forEach(function (c) {
    (c.Contacts || []).forEach(function (k) {
      out.push('   ' + c.Name + ' | ' + k.Name + ' | MarketingConsent = ' + k.MarketingConsent + ' | 손님 LastModifiedOn ' + c.LastModifiedOn);
    });
  });
  out.push('-- 수집 파일');
  cup_loadCollected_().forEach(function (c) {
    if (String(c.Name).toUpperCase().indexOf(name) !== 0) return;
    (c.Contacts || []).forEach(function (k) {
      out.push('   ' + c.Name + ' | ' + k.Name + ' | MarketingConsent = ' + k.MarketingConsent);
    });
  });
  Logger.log(out.join('\n'));
}

/** 한 손님의 주소 — 지금 Cin7 값 (Cin7 호출 1번 · Cin7 에서 고친 뒤 재읽기용) */
function cupAddrOne() {
  var name = 'DALIANA MOMBRUN';
  var now = cup_get_('customer?Page=1&Limit=10&IncludeDeprecated=true&Name=' + encodeURIComponent(name)).data.CustomerList || [];
  var out = [];
  now.forEach(function (c) {
    out.push(c.Name + ' | LastModifiedOn ' + c.LastModifiedOn);
    (c.Addresses || []).forEach(function (a) {
      out.push('   ' + a.Type + ' | 기본 ' + a.DefaultForType + ' | ' + a.Line1 + ' / ' + a.Line2 + ' | ' + a.City + ' ' + a.Postcode + ' | ' + a.ID);
    });
  });
  Logger.log(out.join('\n'));
}

/** Shipping 없는 손님 — 주소 구성별로 센다(수집 파일만 · Cin7 호출 없음) */
function cupNoShip() {
  var cs = cup_loadCollected_();
  var target = cs.filter(function (c) {
    var a = c.Addresses || [];
    return a.length > 0 && !a.some(function (x) { return x.Type === 'Shipping'; });
  });
  var out = ['Shipping 없는 손님 ' + target.length + '명 (주소 0개 손님은 뺐다)'];

  var comp = {};
  target.forEach(function (c) {
    var m = {};
    c.Addresses.forEach(function (x) { m[x.Type] = (m[x.Type] || 0) + 1; });
    var k = Object.keys(m).sort().map(function (t) { return t + '×' + m[t]; }).join(' + ');
    comp[k] = (comp[k] || 0) + 1;
  });
  out.push('(1) 주소 구성');
  Object.keys(comp).sort(function (a, b) { return comp[b] - comp[a]; })
    .forEach(function (k) { out.push('   ' + k + ' : ' + comp[k]); });

  var billDef = target.filter(function (c) {
    return c.Addresses.some(function (x) { return x.Type === 'Billing' && x.DefaultForType === true; });
  }).length;
  var billOnlyNoDef = target.filter(function (c) {
    var b = c.Addresses.filter(function (x) { return x.Type === 'Billing'; });
    return b.length > 0 && !b.some(function (x) { return x.DefaultForType === true; });
  }).length;
  out.push('(2) 기본 Billing 있음 ' + billDef + ' · Billing 은 있는데 기본 체크 없음 ' + billOnlyNoDef);

  var st = {};
  target.forEach(function (c) { st[c.Status] = (st[c.Status] || 0) + 1; });
  out.push('(3) Status: ' + Object.keys(st).map(function (k) { return k + ' ' + st[k]; }).join(' · '));

  var yr = {};
  target.forEach(function (c) { var y = String(c.LastModifiedOn).slice(0, 4); yr[y] = (yr[y] || 0) + 1; });
  out.push('(4) LastModifiedOn 연도: ' + Object.keys(yr).sort().map(function (k) { return k + ' ' + yr[k]; }).join(' · '));

  out.push('(5) 예(최대 10)');
  target.slice(0, 10).forEach(function (c) {
    out.push('   ' + c.Name + ' | ' + c.Addresses.map(function (x) {
      return x.Type + (x.DefaultForType ? '*' : '') + ' ' + x.City;
    }).join(' · '));
  });
  Logger.log(out.join('\n'));
}


/* ═══════════════════════════════════════════════════════════
   공통
   ═══════════════════════════════════════════════════════════ */

/** Cin7 GET 한 번 · 429 는 65초 쉬고 같은 요청을 다시 */
function cup_get_(pathAndQuery) {
  var url = 'https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery;
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  while (true) {
    var res = UrlFetchApp.fetch(url, { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) {
      Logger.log('   429 — 65초 대기 후 재시도 · ' + pathAndQuery);
      Utilities.sleep(65000);
      continue;
    }
    if (code !== 200) throw new Error('Cin7 ' + code + ' · ' + pathAndQuery + ' : ' + res.getContentText().slice(0, 300));
    return { data: JSON.parse(res.getContentText()) };
  }
}

/** ref 전량 — ⚠️ Total 을 믿지 않는다(paymentterm 은 Limit 과 같은 값을 준다) · 받은 행 수로 끝 */
function cup_cin7All_(path, listKey) {
  var out = [], page = 1;
  while (true) {
    var items = cup_get_(path + '?Page=' + page + '&Limit=100').data[listKey] || [];
    out = out.concat(items);
    if (items.length < 100) break;
    page++;
    Utilities.sleep(2500);
  }
  return out;
}

function cup_unmatched_(P, cs, field, known, label) {
  var dist = cup_countBy_(cs, function (c) { return cup_show_(c[field]); });
  var miss = dist.filter(function (r) { return r.k !== '(blank)' && !known[r.k]; });
  var blank = dist.filter(function (r) { return r.k === '(blank)'; });
  var missN = miss.reduce(function (s, r) { return s + r.n; }, 0);
  P('     ' + field + ' — ' + dist.length + '종 · ⚠️ ' + label + ' 에 없는 값 ' + miss.length + '종 ' + missN + '명' +
    ' · 빈 값 ' + (blank.length ? blank[0].n : 0) + '명');
  miss.forEach(function (r) { P('        없음: ' + r.k + ' : ' + r.n); });
}

function cup_keyFill_(objs) {
  var m = {};
  objs.forEach(function (o) {
    Object.keys(o).forEach(function (k) {
      var e = m[k] || (m[k] = { has: 0, fill: 0, types: {} });
      e.has++;
      var v = o[k];
      if (!cup_blank_(v)) e.fill++;
      var t = v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v;
      e.types[t] = true;
    });
  });
  return Object.keys(m).sort().map(function (k) {
    return k + ' : 키 ' + m[k].has + ' · 값 ' + m[k].fill + ' · 형 ' + Object.keys(m[k].types).sort().join('/');
  });
}

/** 빈 값 — null · undefined · 공백뿐인 문자열 · 빈 배열 */
function cup_blank_(v) {
  if (v === null || v === undefined) return true;
  if (Array.isArray(v)) return v.length === 0;
  return String(v).trim() === '';
}

function cup_show_(v) { return cup_blank_(v) ? '(blank)' : String(v); }

function cup_countBy_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).sort().map(function (k) { return { k: k, n: m[k] }; });
}

function cup_dupGroups_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); (m[k] = m[k] || []).push(r); });
  return Object.keys(m).filter(function (k) { return m[k].length > 1; })
    .sort().map(function (k) { return { k: k, rows: m[k] }; });
}

function cup_pad_(n) { return ('000' + n).slice(-4); }
