/**
 * PriceTierProbe.gs — Cin7 가격 티어 실측 (IMS SO 모듈 · 가격표 차수 전)
 * 2026-09-23 작성 · 정본 so-module.md §1-j · po-module 「⬜ 미측정」 프로브 5번(PriceTier1~10 비0 건수 — 한 번도 안 돌았다)
 *
 * ⚠️ 읽기 전용 — Cin7 만 읽는다. Supabase 에 쓰지 않는다.
 *    쓰는 곳은 Google Drive 의 새 폴더 하나(수집 JSON · 보고서)와 Script Properties 의 PTP_* 키 넷뿐이다.
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다(ImsRefLoad.gs 와 같은 프로젝트).
 * ⚠️ 최상위 const 금지 (기존 프로젝트 상수와 충돌하면 프로젝트 전체가 죽는다)
 * ⚠️ 식별자는 ASCII 만 (2026-09-11 실사고: 한자 변수명 → ReferenceError)
 * ⚠️ 트리거를 걸지 마라 (20/20 한도) — 손으로 실행하는 용도다
 * ⚠️ 이 파일의 이름은 전부 ptp 로 시작한다 — 프로젝트 안 다른 파일과 겹치지 않게
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY (getProp 은 Config.gs 에 이미 있다)
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서
 *   1  ptpPeek      티어 목록(ref/priceTier) 원문 + 제품 첫 3개의 가격 칸 — 모양을 먼저 본다(호출 2번)
 *   2  ptpCollect   제품 전량 수집 — ⭐ 한 번에 다 안 끝나면 「Next run」이 뜬다. 끝날 때까지 다시 실행한다
 *                   (제품 18,963 · IncludeBOM=true · 500개씩 ≈ 38페이지 · 한 번에 약 4분 반까지만 돌고 멈춘다
 *                    · 2026-09-13 같은 조건 2분 42초 — 한 번에 끝날 것으로 본다)
 *                   ⚠️ 가격 칸 · 식별 칸 · BOM 요약만 저장한다(83칸 전부가 아니다)
 *   3  ptpAnalyze   모은 것을 세어 보고서를 쓴다(ref/priceTier 호출 1번 더 · 결과는 Drive 폴더의 report-*.txt)
 *   4  ptpSetUnit   세트 가격을 Sellable Yes/No 로 갈라 낱개와 대조 · 지금의 할인율 분포(수집 파일만 · Cin7 호출 없음)
 *                   Caleb 2026-09-23: 안 파는 세트(Sellable No)는 가격을 안 가져와도 된다 · 파는 세트(Yes)는 가져온다
 *                   ⚠️ 옛 판(Sellable 없이) 모은 파일이면 멈춘다 — ptpReset → ptpCollect 부터
 *   ⟲  ptpReset     처음부터 다시 모을 때만(폴더는 지우지 않는다 — 속성만 비운다)
 *
 * 무엇을 세나 (보고서 번호)
 *   (0) 받은 행 · 고유 ID · API Total · Status · Type · ⭐ 갈래 셋(낱개 · 세트 · 콤보 — BOM 으로 가른다)
 *       Caleb 2026-09-23: 판매는 base(낱개) 단위라 세트는 가격을 안 넣은 것이 훨씬 많을 것 — 섞어 세면 낱개의 빈 가격이 묻힌다
 *       ⚠️ 가르는 기준은 BOM 이다(구성품 0 낱개 · 1 세트 · 2+ 콤보) — UOM 이름·SKU 접미사로 읽지 마라(asung-po)
 *   (1) 티어 목록 — ref/priceTier 원문 · PriceTiers 객체의 키 이름 · 둘이 같은가
 *   (2) 칸 번호 ↔ 이름 짝 — ref/priceTier 의 Code 로 짝을 정하고(Code N → PriceTierN) 제품 값으로 검산한다
 *       ⚠️ 값만으로 찾지 않는다 — 0 끼리 · 같은 값 티어끼리 속는다(가짜 데이터 시험에서 둘 다 실제로 속았다)
 *   (3) 칸마다 채움 — 0 · null · 양수 · 음수 · 최솟값 · 최댓값 · 소수 자릿수 최대 · 셋째 자리 이상 개수 (전체 · Active Stock 갈래별)
 *   (4) 손님이 쓰는 티어 넷(Wholesale · AONE · Regular CAD · USWholesale USD · 정본 9-g) —
 *       Active Stock 갈래별 0 인 수 · 낱개는 표본 SKU
 *   (5) 티어끼리의 관계 — Wholesale 대비 같다 · 낮다 · 높다 (Active Stock 낱개 · 둘 다 양수)
 *   (6) SKU 중복 · 빈 SKU
 *   (7) 가격이 든 세트 — 세트 가격 = 낱개 가격 × BOM Quantity 인가(티어별 · Active Stock)
 * ─────────────────────────────────────────────────────────────
 * 2026-09-23 실측 (Caleb 실행 · 토론토 오전 · 정본 so-module §11-b 가 정본)
 *   제품 18,963 = API Total · 낱개 12,462 · 세트 6,486 · 콤보 15 / Active Stock 낱개 8,609 · 세트 5,832 · 콤보 15
 *   ref/priceTier → {PriceTiers:[{Code,Name}]} 열 · Code N ↔ PriceTierN ↔ PriceTiers[Name] 열 티어 전부 100% 일치 · Tier 9·10 전부 0
 *   세트 Sellable Yes 1(BEL43475-12 · 16.99 = 낱개 1.39×12 보다 1.9% 비쌈) · No 5,831 — 값이 있어도 4,890 이 낱개 한 개 값과 같다(뜻 없음)
 *   ⚠️ 가짜 데이터 시험에서 잡은 것 셋 — 값만으로 짝을 찾으면 0 끼리 속고 · 같은 값 티어끼리 동점에서 속는다(→ Code 로 짝) · 짝 없는 티어에서 (5) 가 멈췄다
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   1  모양 먼저
   ═══════════════════════════════════════════════════════════ */

function ptpPeek() {
  var out = [];
  out.push('=== 가격 티어 peek ' + new Date().toISOString() + ' ===');

  var t = ptp_get_('ref/priceTier?Page=1&Limit=100').data;
  out.push('');
  out.push('-- ref/priceTier 최상위 키: ' + Object.keys(t).join(', '));
  out.push(JSON.stringify(t, null, 1).slice(0, 3000));

  var p = ptp_get_('product?Page=1&Limit=3&IncludeDeprecated=true').data;
  out.push('');
  out.push('-- product 최상위 키: ' + Object.keys(p).join(', ') + ' · Total ' + p.Total);
  var list = p.Products || [];
  out.push('Products 행: ' + list.length);
  if (list.length) {
    out.push('제품 키에 Price 가 든 것: ' + Object.keys(list[0]).filter(function (k) { return /price/i.test(k); }).join(', '));
  }
  list.forEach(function (x) {
    out.push('');
    out.push(x.SKU + ' · ' + x.Status + ' · ' + x.Type);
    out.push('  ' + ptp_slots_().map(function (n) { return 'T' + n + '=' + x['PriceTier' + n]; }).join(' '));
    out.push('  PriceTiers = ' + JSON.stringify(x.PriceTiers));
  });
  Logger.log(out.join('\n'));
}


/* ═══════════════════════════════════════════════════════════
   2  전량 수집 — 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function ptpCollect() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('PTP_DONE') === '1') {
    Logger.log('이미 다 모았다 — ptpAnalyze 를 실행하라. 다시 모으려면 ptpReset 먼저.');
    return;
  }

  var folderId = props.getProperty('PTP_FOLDER_ID');
  var folder;
  if (folderId) {
    folder = DriveApp.getFolderById(folderId);
  } else {
    folder = DriveApp.createFolder('PriceTierProbe ' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
    props.setProperty('PTP_FOLDER_ID', folder.getId());
  }

  var startPage = Number(props.getProperty('PTP_NEXT_PAGE') || '1');
  var page = startPage;
  var started = Date.now();
  var rows = [];
  var done = false;
  var total = null;

  while (Date.now() - started < 270000) {           // 4분 30초 — 새 페이지를 시작하지 않는 선
    var r = ptp_get_('product?Page=' + page + '&Limit=' + ptp_limit_() + '&IncludeDeprecated=true&IncludeBOM=true');
    var items = r.data.Products || [];
    if (total === null) total = r.data.Total;
    items.forEach(function (x) { rows.push(ptp_trim_(x)); });
    if (items.length < ptp_limit_()) { done = true; break; }  // ⚠️ Total 이 아니라 받은 행 수로 끝을 판단한다
    page++;
    Utilities.sleep(1500);
  }

  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = 'pages-' + ptp_pad_(startPage) + '-' + ptp_pad_(lastPage) + '.json';
    folder.createFile(name, JSON.stringify(rows), MimeType.PLAIN_TEXT);
    Logger.log('저장: ' + name + ' · ' + rows.length + '개');
  }
  if (total !== null) props.setProperty('PTP_TOTAL', String(total));

  if (done) {
    props.setProperty('PTP_DONE', '1');
    props.deleteProperty('PTP_NEXT_PAGE');
    Logger.log('⭐ 수집 끝 — 마지막 페이지 ' + page + ' · API Total ' + total + ' · 이제 ptpAnalyze');
  } else {
    props.setProperty('PTP_NEXT_PAGE', String(page));
    Logger.log('Next run — 다음 페이지 ' + page + ' 부터 · ptpCollect 를 한 번 더 실행하라');
  }
  Logger.log('폴더: ' + folder.getUrl());
}

function ptpReset() {
  var props = PropertiesService.getScriptProperties();
  ['PTP_FOLDER_ID', 'PTP_NEXT_PAGE', 'PTP_DONE', 'PTP_TOTAL'].forEach(function (k) {
    props.deleteProperty(k);
  });
  Logger.log('PTP_* 속성을 비웠다 — Drive 폴더는 그대로 있다(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   3  세기
   ═══════════════════════════════════════════════════════════ */

function ptpAnalyze() {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('PTP_FOLDER_ID');
  if (!folderId) throw new Error('PTP_FOLDER_ID 없음 — ptpCollect 먼저');
  if (props.getProperty('PTP_DONE') !== '1') Logger.log('⚠️ 수집이 끝나지 않았다 — 모은 만큼만 센다');
  var folder = DriveApp.getFolderById(folderId);

  // ── 모으기 · ID 로 중복 제거 ──
  var raw = [], fileNames = [];
  var files = folder.getFiles();
  while (files.hasNext()) {
    var f = files.next();
    if (!/^pages-.*\.json$/.test(f.getName())) continue;
    fileNames.push(f.getName());
    raw = raw.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  var byId = {}, dupIds = 0, ps = [];
  raw.forEach(function (x) {
    if (byId[x.ID]) { dupIds++; return; }
    byId[x.ID] = x; ps.push(x);
  });
  var act = ps.filter(function (x) { return x.Status === 'Active' && x.Type === 'Stock'; });
  var kinds = { base: '낱개', set: '세트', combo: '콤보' };
  var actBy = { base: [], set: [], combo: [] };
  act.forEach(function (x) { actBy[ptp_kind_(x)].push(x); });

  var out = [];
  var P = function (s) { out.push(s); };
  P('=== 가격 티어 프로브 보고서 ' + new Date().toISOString() + ' ===');
  P('파일 ' + fileNames.sort().join(', '));

  // (0)
  P('');
  P('(0) 받은 행 ' + raw.length + ' · 고유 ID ' + ps.length + ' · 중복 ID ' + dupIds +
    ' · API Total ' + props.getProperty('PTP_TOTAL'));
  P('  (중복·누락은 수집 도중 제품이 추가·변경되어 페이지가 밀린 것일 수 있다 — Total 과 고유 ID 를 함께 본다)');
  P('  Status: ' + ptp_countBy_(ps, function (x) { return ptp_show_(x.Status); }).map(ptp_kn_).join(' · '));
  P('  Type:   ' + ptp_countBy_(ps, function (x) { return ptp_show_(x.Type); }).map(ptp_kn_).join(' · '));
  P('  ⭐ 아래 「Active Stock」 = Status Active 이고 Type Stock 인 제품 ' + act.length + '개');
  P('  ⭐ 갈래(BOM 구성품 수) 전체: ' + ptp_countBy_(ps, function (x) { return kinds[ptp_kind_(x)]; }).map(ptp_kn_).join(' · ') +
    '  /  Active Stock: 낱개 ' + actBy.base.length + ' · 세트 ' + actBy.set.length + ' · 콤보 ' + actBy.combo.length);

  // (1) 티어 목록
  P('');
  P('(1) 티어 목록');
  var refRaw = ptp_get_('ref/priceTier?Page=1&Limit=100').data;
  var refList = ptp_firstArray_(refRaw);
  P('  ref/priceTier 최상위 키: ' + Object.keys(refRaw).join(', ') + ' · 배열 ' + (refList ? refList.length + '행' : '없음'));
  if (refList) refList.forEach(function (t) { P('     ' + JSON.stringify(t)); });

  var keyCount = {};
  ps.forEach(function (x) {
    var o = x.PriceTiers;
    if (o && typeof o === 'object' && !Array.isArray(o)) {
      Object.keys(o).forEach(function (k) { keyCount[k] = (keyCount[k] || 0) + 1; });
    }
  });
  var tierNames = Object.keys(keyCount);
  var noObj = ps.filter(function (x) { return !x.PriceTiers || typeof x.PriceTiers !== 'object' || Array.isArray(x.PriceTiers); }).length;
  P('  PriceTiers 객체의 키 ' + tierNames.length + '종 (객체 없는 제품 ' + noObj + ')');
  tierNames.forEach(function (k) { P('     「' + k + '」 : 제품 ' + keyCount[k]); });

  // (2) 칸 번호 ↔ 이름 — ⭐ 짝은 ref/priceTier 의 Code(Code N → PriceTierN) · 값은 검산에만 쓴다
  //     (가짜 데이터 시험: 값만으로 찾으면 ① 0 끼리 같다로 속고 ② 두 티어 값이 같으면 동점에서 엉뚱한 칸을 고른다)
  P('');
  P('(2) 칸 번호 ↔ 이름 짝 — Code N → PriceTierN 을 제품 값으로 검산');
  P('    「같음」= 둘 다 양수이고 같다 · 「어긋남」= 이름 값과 칸 값이 다르다(0 포함) · 「다른 칸이 더 맞다」가 뜨면 Code 짝이 틀렸을 수 있다');
  var codeOf = {};
  (refList || []).forEach(function (t) { if (t && t.Name !== undefined) codeOf[t.Name] = Number(t.Code); });
  var mapName = {};
  tierNames.forEach(function (k) {
    var posK = 0, eqBy = {};
    ptp_slots_().forEach(function (n) { eqBy[n] = 0; });
    ps.forEach(function (x) {
      var a = x.PriceTiers && x.PriceTiers[k];
      if (!(typeof a === 'number' && a > 0)) return;
      posK++;
      ptp_slots_().forEach(function (n) { var v = x['PriceTier' + n]; if (typeof v === 'number' && Math.abs(a - v) < 1e-9) eqBy[n]++; });
    });
    var n = codeOf[k];
    if (!(n >= 1 && n <= 10)) {
      P('  「' + k + '」 — ⚠️ ref/priceTier 에 Code 가 없다 · 짝을 정하지 않는다');
      return;
    }
    mapName[k] = { n: n };
    var bad = ps.filter(function (x) {
      var a = x.PriceTiers && x.PriceTiers[k], v = x['PriceTier' + n];
      return !(typeof a === 'number' && typeof v === 'number' && Math.abs(a - v) < 1e-9);
    });
    var better = ptp_slots_().filter(function (m) { return m !== n && eqBy[m] > eqBy[n]; });
    P('  「' + k + '」 Code ' + n + ' → PriceTier' + n + ' · 양수 ' + posK + ' 중 같음 ' + eqBy[n] +
      (bad.length === 0 ? ' · 전 제품 일치 ✓' : ' · ⚠️ 어긋난 제품 ' + bad.length + ' · 표본 ' +
        bad.slice(0, 5).map(function (x) { return x.SKU + '(' + x.PriceTiers[k] + '≠' + x['PriceTier' + n] + ')'; }).join(', ')) +
      (better.length ? ' · ⚠️ 다른 칸이 더 맞다: ' + better.map(function (m) { return 'T' + m + ' ' + eqBy[m]; }).join(' · ') : ''));
  });
  var taken = {};
  Object.keys(mapName).forEach(function (k) { var n = mapName[k].n; (taken[n] = taken[n] || []).push(k); });
  Object.keys(taken).forEach(function (n) { if (taken[n].length > 1) P('  ⚠️ PriceTier' + n + ' 에 이름 둘 이상: ' + taken[n].join(' · ')); });

  // (3) 칸마다 채움
  P('');
  P('(3) 칸마다 채움 — 전체 ' + ps.length + ' / Active Stock 낱개 ' + actBy.base.length + ' · 세트 ' + actBy.set.length + ' · 콤보 ' + actBy.combo.length);
  var slotName = {};
  Object.keys(mapName).forEach(function (k) { slotName[mapName[k].n] = k; });
  ptp_slots_().forEach(function (n) {
    var s1 = ptp_stat_(ps, 'PriceTier' + n);
    P('  T' + n + ' ' + (slotName[n] ? '「' + slotName[n] + '」' : '(이름 없음)'));
    P('     전체            ' + ptp_statLine_(s1));
    ['base', 'set', 'combo'].forEach(function (g) {
      P('     Active ' + kinds[g] + '     ' + ptp_statLine_(ptp_stat_(actBy[g], 'PriceTier' + n)));
    });
  });

  // (4) 손님이 쓰는 티어 넷
  P('');
  P('(4) 손님이 쓰는 티어 넷 — Active Stock 갈래별 0(또는 null) 인 제품 수 / 갈래 전체');
  ['Wholesale', 'AONE', 'Regular CAD', 'USWholesale USD'].forEach(function (k) {
    var m = mapName[k];
    if (!m) { P('  「' + k + '」 — ⚠️ PriceTiers 키에 없다'); return; }
    var z = {};
    ['base', 'set', 'combo'].forEach(function (g) {
      z[g] = actBy[g].filter(function (x) { var v = x['PriceTier' + m.n]; return !(typeof v === 'number' && v > 0); });
    });
    P('  「' + k + '」(T' + m.n + ') — 0 · null  낱개 ' + z.base.length + '/' + actBy.base.length +
      ' · 세트 ' + z.set.length + '/' + actBy.set.length + ' · 콤보 ' + z.combo.length + '/' + actBy.combo.length);
    if (z.base.length) P('       낱개 표본 ' + z.base.slice(0, 15).map(function (x) { return x.SKU; }).join(', '));
  });

  // (5) Wholesale 대비
  P('');
  P('(5) 티어끼리 — Wholesale 대비 (Active Stock 낱개 · 둘 다 양수인 제품만)');
  var w = mapName['Wholesale'];
  if (!w) {
    P('  ⚠️ Wholesale 짝을 못 찾았다 — 건너뛴다');
  } else {
    tierNames.filter(function (k) { return k !== 'Wholesale'; }).forEach(function (k) {
      var m = mapName[k], eq = 0, lo = 0, hi = 0;
      if (!m) { P('  「' + k + '」 — 짝이 없어 건너뛴다((2) 참고)'); return; }
      actBy.base.forEach(function (x) {
        var a = x['PriceTier' + m.n], b = x['PriceTier' + w.n];
        if (!(typeof a === 'number' && a > 0 && typeof b === 'number' && b > 0)) return;
        if (Math.abs(a - b) < 1e-9) eq++; else if (a < b) lo++; else hi++;
      });
      P('  「' + k + '」 — 같다 ' + eq + ' · 낮다 ' + lo + ' · 높다 ' + hi);
    });
  }

  // (6) SKU
  P('');
  var blankSku = ps.filter(function (x) { return ptp_blank_(x.SKU); }).length;
  var dup = ptp_dupGroups_(ps.filter(function (x) { return !ptp_blank_(x.SKU); }), function (x) { return String(x.SKU).trim().toUpperCase(); });
  P('(6) 빈 SKU ' + blankSku + ' · SKU 중복(대소문자·앞뒤 공백 무시) ' + dup.length + '종' +
    (dup.length ? ' · 표본 ' + dup.slice(0, 10).map(function (g) { return g.k + '×' + g.rows.length; }).join(', ') : ''));

  // (7) 가격이 든 세트 — 낱개 × 계수와 같은가
  P('');
  P('(7) 가격이 든 세트 — 세트 가격 = 낱개 가격 × BOM Quantity 인가 (Active Stock 세트 · 세트·낱개 둘 다 양수인 것만)');
  P('    ⚠️ 낱개는 BomParent(구성품 GUID)로 찾는다 · 0.005 안쪽이면 같다로 센다(반올림)');
  Object.keys(mapName).forEach(function (k) {
    var m = mapName[k], has = 0, eq = 0, lo = 0, hi = 0, noBase = 0, sample = [];
    actBy.set.forEach(function (x) {
      var sp = x['PriceTier' + m.n];
      if (!(typeof sp === 'number' && sp > 0)) return;
      has++;
      var b = byId[x.BomParent], bp = b && b['PriceTier' + m.n], q = Number(x.BomQty);
      if (!(typeof bp === 'number' && bp > 0) || !(q > 0)) { noBase++; return; }
      var d = sp - bp * q;
      if (Math.abs(d) < 0.005) eq++; else if (d < 0) lo++; else hi++;
      if (Math.abs(d) >= 0.005 && sample.length < 5) sample.push(x.SKU + '(' + sp + ' vs ' + bp + '×' + q + ')');
    });
    P('  「' + k + '」 — 가격 든 세트 ' + has + ' · 같다 ' + eq + ' · 낮다 ' + lo + ' · 높다 ' + hi + ' · 낱개 가격 없음 ' + noBase +
      (sample.length ? ' · 표본 ' + sample.join(', ') : ''));
  });
  var badQty = actBy.set.filter(function (x) { return !(Number(x.BomQty) > 0); }).length;
  var noParent = actBy.set.filter(function (x) { return !byId[x.BomParent]; }).length;
  P('  세트 중 BOM Quantity 가 양수가 아닌 것 ' + badQty + ' · 구성품 GUID 가 수집에 없는 것 ' + noParent);

  var text = out.join('\n');
  var rep = folder.createFile('report-' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm') + '.txt',
    text, MimeType.PLAIN_TEXT);
  Logger.log(text);
  Logger.log('보고서: ' + rep.getUrl());
}


/* ═══════════════════════════════════════════════════════════
   4  세트 가격 = 낱개 한 개 가격인가 (2026-09-23 · 보고서 (7) 을 보고 더함 · Cin7 호출 없음)
   ═══════════════════════════════════════════════════════════
   (7) 에서 세트 가격이 「낱개 × 계수」보다 거의 전부 낮았고, 표본은 세트 가격 = 낱개 한 개 가격이었다
   (ABC59130-12 Wholesale 16.39 = 낱개 16.39). 그 모양이 전체에서도 그런지 센다.
   ⚠️ 수집 파일만 읽는다 — ptpCollect 가 끝난 뒤 실행한다 */

function ptpSetUnit() {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('PTP_FOLDER_ID');
  if (!folderId) throw new Error('PTP_FOLDER_ID 없음 — ptpCollect 먼저');
  var folder = DriveApp.getFolderById(folderId);
  var ps = [], byId = {};
  var files = folder.getFiles();
  while (files.hasNext()) {
    var f = files.next();
    if (!/^pages-.*\.json$/.test(f.getName())) continue;
    JSON.parse(f.getBlob().getDataAsString()).forEach(function (x) { if (!byId[x.ID]) { byId[x.ID] = x; ps.push(x); } });
  }
  var noSell = ps.filter(function (x) { return x.Sellable === undefined; }).length;
  if (noSell === ps.length) throw new Error('수집 파일에 Sellable 이 없다 — 옛 판으로 모은 것이다. ptpReset → ptpCollect 를 새 판으로 다시');
  var sets = ps.filter(function (x) { return x.Status === 'Active' && x.Type === 'Stock' && ptp_kind_(x) === 'set'; });
  var bases = ps.filter(function (x) { return x.Status === 'Active' && x.Type === 'Stock' && ptp_kind_(x) === 'base'; });
  var names = ['Wholesale', 'Franchise', 'AONE', 'Regular CAD', 'ComparedPrice CAD', 'wholesalespecia CAD', 'USWholesale USD', 'REFERENCECOST USD'];
  var out = [];
  var P = function (t) { out.push(t); };
  P('=== 세트 가격 vs 낱개 가격 — Sellable 로 갈라 ' + new Date().toISOString() + ' ===');
  P('  Active Stock 세트 ' + sets.length + ' · Sellable true ' + sets.filter(function (x) { return x.Sellable === true; }).length +
    ' · false ' + sets.filter(function (x) { return x.Sellable === false; }).length +
    ' · 그 밖 ' + sets.filter(function (x) { return x.Sellable !== true && x.Sellable !== false; }).length);
  P('  Active Stock 낱개 ' + bases.length + ' · Sellable true ' + bases.filter(function (x) { return x.Sellable === true; }).length +
    ' · false ' + bases.filter(function (x) { return x.Sellable === false; }).length);
  var bf = bases.filter(function (x) { return x.Sellable === false; });
  if (bf.length) P('     ⚠️ 안 파는 낱개 표본 ' + bf.slice(0, 15).map(function (x) { return x.SKU; }).join(', '));
  P('  세트·낱개 둘 다 양수인 것만 · 0.005 안쪽이면 같다');
  P('  「낱개 한 개와 같다」 = 세트 가격 = 낱개 가격 · 「낱개×계수」 = 세트 가격 = 낱개 가격 × BOM Quantity');
  P('  ⭐ 할인율 = 1 − 세트 가격 ÷ (낱개 가격 × 계수) — 세트 가격이 「세트 한 개 값」이라고 볼 때 지금 몇 % 싸게 파는가');

  [true, false].forEach(function (sell) {
    var grp = sets.filter(function (x) { return x.Sellable === sell; });
    P('');
    P('━━ Sellable ' + (sell ? 'Yes(실제로 세트로 판다)' : 'No(안 판다)') + ' 세트 ' + grp.length + ' ━━');
    names.forEach(function (k, i) {
      var n = i + 1, has = 0, zero = 0, same1 = 0, sameQ = 0, other = 0, disc = {}, sample = [];
      grp.forEach(function (x) {
        var sp = x['PriceTier' + n], b = byId[x.BomParent], bp = b && b['PriceTier' + n], q = Number(x.BomQty);
        if (!(typeof sp === 'number' && sp > 0)) { zero++; return; }
        if (!(typeof bp === 'number' && bp > 0 && q > 0)) return;
        has++;
        if (Math.abs(sp - bp) < 0.005 && q !== 1) { same1++; return; }
        if (Math.abs(sp - bp * q) < 0.005) { sameQ++; return; }
        other++;
        var d = 1 - sp / (bp * q);
        var key = d < 0 ? '비쌈(<0%)' : d < 0.02 ? '0~2%' : d < 0.05 ? '2~5%' : d < 0.10 ? '5~10%' : d < 0.20 ? '10~20%' : d < 0.50 ? '20~50%' : '50%+';
        disc[key] = (disc[key] || 0) + 1;
        if (sample.length < 6) sample.push(x.SKU + '(' + sp + ' / ' + bp + '×' + q + ' · ' + Math.round(d * 1000) / 10 + '%)');
      });
      if (!has && !zero) return;
      P('  「' + k + '」 T' + n + ' — 세트 가격 0 ' + zero + ' · 둘 다 양수 ' + has + ' · 낱개 한 개와 같다 ' + same1 +
        ' · 낱개×계수 ' + sameQ + ' · 그 밖 ' + other);
      var order = ['비쌈(<0%)', '0~2%', '2~5%', '5~10%', '10~20%', '20~50%', '50%+'];
      var dl = order.filter(function (o) { return disc[o]; }).map(function (o) { return o + ' ' + disc[o]; });
      if (dl.length) P('       할인율 분포(그 밖) ' + dl.join(' · '));
      if (sample.length) P('       표본 ' + sample.join(', '));
    });
  });
  var text = out.join('\n');
  folder.createFile('setunit-' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm') + '.txt', text, MimeType.PLAIN_TEXT);
  Logger.log(text);
}


/* ═══════════════════════════════════════════════════════════
   도우미
   ═══════════════════════════════════════════════════════════ */

function ptp_get_(pathAndQuery) {
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

function ptp_slots_() { return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]; }

/** BOM 을 켜면 1000 이 안 온다(2026-09-13 실측 · ImsLoadProduct IPR_LIMIT) */
function ptp_limit_() { return 500; }

/** 갈래 — BOM 구성품 수로 가른다(0 낱개 · 1 세트 · 2+ 콤보) · ⚠️ 이름·접미사로 읽지 않는다 */
function ptp_kind_(x) { return !x.BomN ? 'base' : x.BomN === 1 ? 'set' : 'combo'; }

/** 저장할 칸만 — 식별 · 상태 · 가격 */
function ptp_trim_(x) {
  var o = { ID: x.ID, SKU: x.SKU, Name: x.Name, Status: x.Status, Type: x.Type, UOM: x.UOM, Sellable: x.Sellable, PriceTiers: x.PriceTiers };
  ptp_slots_().forEach(function (n) { o['PriceTier' + n] = x['PriceTier' + n]; });
  var bom = x.BillOfMaterialsProducts || [];
  o.BomN = bom.length;
  if (bom.length) { o.BomParent = bom[0].ComponentProductID; o.BomQty = bom[0].Quantity; o.BomSku = bom[0].ProductCode; }
  return o;
}

/** 응답 안의 첫 배열 — ref/priceTier 의 목록 키 이름을 모르므로(peek 로 확인 전) */
function ptp_firstArray_(data) {
  var keys = Object.keys(data || {});
  for (var i = 0; i < keys.length; i++) if (Array.isArray(data[keys[i]])) return data[keys[i]];
  return null;
}

function ptp_stat_(rows, field) {
  var s = { n: rows.length, nul: 0, notNum: 0, zero: 0, pos: 0, neg: 0, min: null, max: null, dec: 0, dec3: 0 };
  rows.forEach(function (x) {
    var v = x[field];
    if (v === null || v === undefined) { s.nul++; return; }
    if (typeof v !== 'number') { s.notNum++; return; }
    if (v === 0) s.zero++; else if (v > 0) s.pos++; else s.neg++;
    if (v !== 0) {
      if (s.min === null || v < s.min) s.min = v;
      if (s.max === null || v > s.max) s.max = v;
    }
    var d = ptp_decimals_(v);
    if (d > s.dec) s.dec = d;
    if (d > 2) s.dec3++;
  });
  return s;
}

function ptp_statLine_(s) {
  return '양수 ' + s.pos + ' · 0 ' + s.zero + ' · null ' + s.nul +
    (s.neg ? ' · ⚠️ 음수 ' + s.neg : '') + (s.notNum ? ' · ⚠️ 숫자 아님 ' + s.notNum : '') +
    (s.min !== null ? ' · 범위 ' + s.min + '~' + s.max : '') + ' · 소수 최대 ' + s.dec + '자리' + (s.dec3 ? ' · 셋째 자리 이상 ' + s.dec3 + '개' : '');
}

function ptp_decimals_(v) {
  var t = String(v);
  if (t.indexOf('e') >= 0 || t.indexOf('E') >= 0) return 99;   // 지수 표기 — 보고서에서 눈에 띄게
  var i = t.indexOf('.');
  return i < 0 ? 0 : t.length - i - 1;
}

/** 빈 값 — null · undefined · 공백뿐인 문자열 · 빈 배열 */
function ptp_blank_(v) {
  if (v === null || v === undefined) return true;
  if (Array.isArray(v)) return v.length === 0;
  return String(v).trim() === '';
}

function ptp_show_(v) { return ptp_blank_(v) ? '(blank)' : String(v); }

function ptp_kn_(r) { return r.k + ' ' + r.n; }

function ptp_countBy_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).sort().map(function (k) { return { k: k, n: m[k] }; });
}

function ptp_dupGroups_(rows, keyFn) {
  var m = {};
  rows.forEach(function (r) { var k = keyFn(r); (m[k] = m[k] || []).push(r); });
  return Object.keys(m).filter(function (k) { return m[k].length > 1; })
    .sort().map(function (k) { return { k: k, rows: m[k] }; });
}

function ptp_pad_(n) { return ('000' + n).slice(-4); }
