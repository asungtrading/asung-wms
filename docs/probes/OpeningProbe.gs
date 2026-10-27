/**
 * OpeningProbe.gs — 컷오버 미수 · 오버페이 이월의 원천 실측 (판정 775 · ar-1)
 * 2026-10-26 밤 작성 · 조사 ar-0 회신이 넘긴 「모르는 것 ①~⑤ · 크레딧 원천 셋」 을 닫는 프로브
 *
 * ⚠️ 읽기 전용 — Cin7 만 읽는다. Supabase 에 쓰지 않는다.
 *    쓰는 곳은 코드가 만드는 Google Drive 폴더 하나(원본 JSON · 보고서)와 Script Property `OPP_STATE` 하나뿐이다.
 *    (속성을 하나로 묶은 이유: 이 프로젝트는 Script Properties 가 50 개를 넘어 설정 화면이 읽기 전용이다 —
 *     지울 때도 코드(oppReset)로만 지운다 · asung-apps-script 규칙 6)
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다(ImsRefLoad.gs · ImsLoadHist.gs 와 같은 프로젝트).
 * ⚠️ 최상위 const 금지 (기존 프로젝트 상수와 충돌하면 프로젝트 전체가 죽는다)
 * ⚠️ 식별자는 ASCII 만 (2026-09-11 실사고: 한자 변수명 → ReferenceError)
 * ⚠️ 트리거를 걸지 마라 (20/20 한도) — 손으로 실행하는 용도다
 * ⚠️ 이 파일의 이름은 전부 opp 로 시작한다 — 같은 이름 함수가 둘이면 에러 없이 뒤의 것이 이긴다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY (getProp 은 Config.gs 에 이미 있다)
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서
 *   1  oppPeek      호출 약 10 번 — 모양부터. 원본 JSON 을 Drive 에 그대로
 *                   a) saleList Limit=1000 한 쪽(⑤)  b) CombinedInvoiceStatus 필터 배선(③)
 *                   c) ref/customer/credits  d) saleCreditNoteList  e) sale/payment  f) sale 상세 — 상태 코드 · 최상위 키 · 첫 행 키
 *   2  oppCollect   saleList 전량(날짜 필터 없음 — Omni 이전 것이 섞였나 봐야 한다) → ref/customer/credits 전량
 *                   ⭐ 한 번에 다 안 끝나면 로그에 「Next run」 — 끝날 때까지 다시 실행한다(4 분 30 초에서 멈춘다)
 *   3  oppAnalyze   모은 것을 세어 report-analyze-*.txt + candidates.json(경우마다 3 sale) — Cin7 호출 0
 *   4  oppDetail    후보(많아야 18 sale)만 sale 상세 · sale/payment + 그 손님들의 ref/customer/credits(쓴 것 포함)
 *                   → 원본 JSON + report-detail-*.txt(인보이스별 표 · 끝에 「Caleb 화면 대조표」) · Next run 이면 다시
 *   ⟲  oppReset     속성 OPP_STATE 만 지운다(폴더는 그대로 — 손으로 지운다)
 *
 * apib 원문(공개 · 2026-10-26 받음)에서 확인한 것 — ⚠️ 문서 표기일 뿐 실측 아님(cin7-api 규칙 12):
 *   saleList          InvoiceAmount = 「Total Invoice amount minus total Credit note amount」 · PaidAmount = 「Total Paid amount minus Refunded amount」
 *                     SaleInvoicesTotalAmount = 「Total invoice amount」 · CombinedPaymentTotal = 「Combined total invoice paid amount」
 *                     CombinedPaymentStatus ∈ NOT REFUNDED · PREPAID · PARTIALLY PAID · UNPAID · PAID · VOIDED
 *                     파라미터 CombinedInvoiceStatus(필드명과 같다) · ⚠️ 픽 · 팩 은 파라미터 CombinedPickStatus ≠ 필드 CombinedPickingStatus
 *   ref/customer/credits  Page · Limit(기본 100) · CustomerID · ShowUsedCredits(기본 false) → CustomerCredits[ CreditID · CustomerID · CustomerName ·
 *                     Account · Amount · RemainingAmount · Currency · ConvRate · Date · Description("Credit by prepayments") ] · 예시에 Total 이 없다
 *   sale/payment      SaleID 필수(손님 단위 목록이 아니다) → 배열[ SaleID · TaskID · ID · SaleOrderNumber · InvoiceNumber · CreditNoteNumber ·
 *                     Type(PREPAYMENT · PAYMENT · REFUND) · Reference · Amount · DatePaid · Account · CurrencyRate · DateCreated · CreditID(크레딧에서 낸 결제) ]
 *   sale 상세         Invoices[ TaskID · InvoiceNumber · Status · InvoiceDate · InvoiceDueDate · Total · Paid · Payments[] … ] ·
 *                     CreditNotes[ CreditNoteNumber · CreditNoteInvoiceNumber · Status · CreditNoteDate · Total · Refunds[] … ]
 *                     (⚠️ cin7-api references/sale.md 의 발췌는 Invoice 를 객체로 적었다 — 둘 다 받는다)
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   1  모양부터
   ═══════════════════════════════════════════════════════════ */

function oppPeek() {
  var st = opp_state_(), folder = opp_folder_(st), out = [];
  var P = function (s) { out.push(s); };
  P('=== OpeningProbe peek ' + new Date().toISOString() + ' ===');

  // a) ⑤ Limit=1000
  var a = opp_get_('saleList?Page=1&Limit=1000');
  opp_save_(folder, 'peek-a-salelist-limit1000.json', a.text);
  var al = (a.data && a.data.SaleList) || [];
  P('a) saleList Page=1 Limit=1000 → HTTP ' + a.code + ' · Total ' + (a.data ? a.data.Total : '?') + ' · 받은 행 ' + al.length +
    (!a.data ? '' : (al.length >= Math.min(1000, a.data.Total || 0) ? ' ⭐ 1000 이 동작한다(또는 전부 왔다)' : ' ⚠️ ' + al.length + ' 행뿐 — 서버 상한 ' + al.length + '(oppCollect 가 이 값으로 다시 받는다)')));
  if (al.length) P('   행 키: ' + Object.keys(al[0]).join(', '));

  // b) ③ 필터 배선 — 동작을 아는 CreatedSince 를 같이 보낸다(규칙 12 ②)
  var since = '2026-10-01T00:00:00';
  var rows = [
    ['(필터 없음)', 'saleList?Page=1&Limit=1'],
    ['CreatedSince 만', 'saleList?Page=1&Limit=1&CreatedSince=' + since],
    ['+ CombinedInvoiceStatus=PAID', 'saleList?Page=1&Limit=1&CreatedSince=' + since + '&CombinedInvoiceStatus=PAID'],
    ['+ CombinedInvoiceStatus=AUTHORISED', 'saleList?Page=1&Limit=1&CreatedSince=' + since + '&CombinedInvoiceStatus=AUTHORISED'],
    ['+ CombinedInvoiceStatus=ZZZ(없는 값)', 'saleList?Page=1&Limit=1&CreatedSince=' + since + '&CombinedInvoiceStatus=ZZZ']
  ];
  P('');
  P('b) 필터 배선(③) — Total 을 나란히');
  var totals = rows.map(function (r) {
    var x = opp_get_(r[1]);
    var t = x.data ? x.data.Total : null;
    P('   ' + opp_padR_(r[0], 40) + ' HTTP ' + x.code + ' · Total ' + t);
    return t;
  });
  P('   판정: ' + opp_filterVerdict_(totals[0], totals[1], totals[2], totals[3], totals[4]));

  // c) d) e) f) 후보 엔드포인트 — 상태 코드 · 최상위 키 · 첫 행 키 · 원본 저장
  P('');
  var paid = al.filter(function (s) { return opp_n_(s.PaidAmount) > 0.005 && s.SaleID; })[0] || al.filter(function (s) { return s.SaleID; })[0];
  var probes = [
    ['c) ref/customer/credits', 'ref/customer/credits?Page=1&Limit=100', 'peek-c-customer-credits.json'],
    ['c2) ref/customer/credits 쓴 것 포함', 'ref/customer/credits?Page=1&Limit=5&ShowUsedCredits=true', 'peek-c2-customer-credits-used.json'],
    ['d) saleCreditNoteList', 'saleCreditNoteList?Page=1&Limit=5', 'peek-d-salecreditnotelist.json']
  ];
  if (paid) {
    probes.push(['e) sale/payment ' + paid.OrderNumber, 'sale/payment?SaleID=' + paid.SaleID, 'peek-e-sale-payment-' + opp_safe_(paid.OrderNumber) + '.json']);
    probes.push(['f) sale 상세 ' + paid.OrderNumber, 'sale?ID=' + paid.SaleID + '&HideInventoryMovements=true', 'peek-f-sale-' + opp_safe_(paid.OrderNumber) + '.json']);
  } else {
    P('e) f) 건너뜀 — a) 에 SaleID 있는 행이 없다');
  }
  probes.forEach(function (p) {
    var x = opp_get_(p[1]);
    opp_save_(folder, p[2], x.text);
    P(p[0] + ' → HTTP ' + x.code + (x.isJson ? '' : ' ⚠️ JSON 아님(규칙 18 — 없는 경로는 200 + HTML)') + ' · ' + opp_shape_(x.data));
  });
  if (paid) {
    var f = opp_get_last_detail_(folder, paid);   // 방금 저장한 f) 를 다시 부르지 않고 모양만 더 적는다
    if (f) P('   f) 의 인보이스 · 결제 · 크레딧 노트 키: ' + f);
  }

  P('');
  P('⭐ peek 끝 — 원본은 Drive 폴더에 · 다음은 oppCollect');
  P('폴더: ' + folder.getUrl());
  Logger.log(out.join('\n'));
  folder.createFile('report-peek-' + opp_stamp_() + '.txt', out.join('\n'), MimeType.PLAIN_TEXT);
}


/* ═══════════════════════════════════════════════════════════
   2  전량 수집 — 이어 달리기 · saleList → ref/customer/credits
   ═══════════════════════════════════════════════════════════ */

function oppCollect() {
  var st = opp_state_(), folder = opp_folder_(st), started = Date.now();
  if (st.salesDone && st.creditsDone) { Logger.log('이미 다 모았다 — oppAnalyze 를 실행하라. 다시 모으려면 oppReset 먼저.'); return; }

  if (!st.salesDone) {
    var r = opp_collectPages_(folder, st, started, {
      tag: 'sales', key: 'SaleList', path: function (p, lim) { return 'saleList?Page=' + p + '&Limit=' + lim; },
      pageProp: 'salesNext', limitProp: 'salesLimit', totalProp: 'salesTotal', gotProp: 'salesGot', firstLimit: 1000
    });
    if (!r.done) { opp_save_state_(st); Logger.log('Next run — saleList 다음 쪽 ' + st.salesNext + ' 부터 · oppCollect 를 한 번 더 실행하라'); Logger.log('폴더: ' + folder.getUrl()); return; }
    st.salesDone = true;
    Logger.log('⭐ saleList 끝 — 받은 행 ' + st.salesGot + ' · API Total ' + st.salesTotal + (st.salesGot === st.salesTotal ? ' · 같다' : ' ⚠️ 다르다 — oppAnalyze 가 고유 SaleID 로 다시 센다'));
    opp_save_state_(st);
  }

  if (!st.creditsDone) {
    var c = opp_collectPages_(folder, st, started, {
      tag: 'credits', key: 'CustomerCredits', path: function (p, lim) { return 'ref/customer/credits?Page=' + p + '&Limit=' + lim; },
      pageProp: 'creditsNext', limitProp: 'creditsLimit', totalProp: 'creditsTotal', gotProp: 'creditsGot', firstLimit: 100   // 문서 기본 100 · 1000 은 실측 없음
    });
    if (!c.done) { opp_save_state_(st); Logger.log('Next run — ref/customer/credits 다음 쪽 ' + st.creditsNext + ' 부터 · oppCollect 를 한 번 더 실행하라'); Logger.log('폴더: ' + folder.getUrl()); return; }
    st.creditsDone = true;
    Logger.log('⭐ ref/customer/credits 끝 — 받은 행 ' + st.creditsGot + ' · API Total ' + (st.creditsTotal === null || st.creditsTotal === undefined ? '(응답에 없음)' : st.creditsTotal));
    opp_save_state_(st);
  }
  Logger.log('⭐ 수집 끝 — 이제 oppAnalyze · 폴더: ' + folder.getUrl());
}

// 쪽 순회 한 갈래 — 4 분 30 초에서 새 쪽을 시작하지 않는다 · 끝 판단은 Total 이 아니라 받은 행 수 < Limit
function opp_collectPages_(folder, st, started, o) {
  var page = st[o.pageProp] || 1, startPage = page, rows = [], done = false;
  var limit = st[o.limitProp] || o.firstLimit;
  while (Date.now() - started < 270000) {
    var x = opp_need_(o.path(page, limit));
    var items = x.data[o.key] || [];
    if (st[o.totalProp] === undefined || st[o.totalProp] === null) st[o.totalProp] = (x.data.Total === undefined ? null : x.data.Total);
    if (page === 1 && !st[o.limitProp]) {                 // 첫 쪽에서 Limit 이 먹었나 본다 — 안 먹었으면 받은 행 수(서버 상한)로 처음부터
      if (items.length > 0 && items.length < limit && (x.data.Total || 0) > items.length) {
        Logger.log('   ' + o.tag + ': Limit=' + limit + ' 이 안 먹는다(받은 ' + items.length + ' · Total ' + x.data.Total + ') — Limit ' + items.length + ' 로 다시');
        limit = items.length; st[o.limitProp] = limit; continue;
      }
      st[o.limitProp] = limit;
    }
    var first = items.length ? JSON.stringify(items[0]) : null;   // 쪽이 안 넘어가는 엔드포인트면 같은 행이 되풀이된다(cup_cin7All_ 의 Total 불신과 같은 계열)
    if (first !== null && first === st[o.tag + 'First']) throw new Error(o.tag + ' 쪽 ' + page + ' 의 첫 행이 앞 쪽과 같다 — Page 가 안 먹는다 · 원본을 보고 멈춤');
    st[o.tag + 'First'] = first;
    rows = rows.concat(items);
    if (items.length < limit) { done = true; break; }
    page++;
  }
  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = o.tag + '-p' + opp_pad_(startPage) + '-p' + opp_pad_(lastPage) + '.json';
    opp_save_(folder, name, JSON.stringify(rows));
    Logger.log('저장: ' + name + ' · ' + rows.length + ' 행');
  }
  st[o.gotProp] = (st[o.gotProp] || 0) + rows.length;
  st[o.pageProp] = done ? null : page;
  return { done: done };
}

function oppReset() {
  PropertiesService.getScriptProperties().deleteProperty('OPP_STATE');
  Logger.log('OPP_STATE 를 지웠다 — Drive 폴더는 그대로 있다(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   3  세기 — Cin7 호출 0
   ═══════════════════════════════════════════════════════════ */

function oppAnalyze() {
  var st = opp_state_();
  if (!st.salesDone || !st.creditsDone) { Logger.log('수집이 안 끝났다 — oppCollect 를 끝까지(Next run 이 안 뜰 때까지) 먼저.'); return; }
  var folder = opp_folder_(st);
  var sales = opp_dedupe_(opp_readAll_(folder, 'sales-'), 'SaleID');
  var credits = opp_readAll_(folder, 'credits-').rows;
  var res = opp_analyze_(sales, credits, st, opp_today_());
  folder.createFile('report-analyze-' + opp_stamp_() + '.txt', res.text, MimeType.PLAIN_TEXT);
  opp_save_(folder, 'candidates.json', JSON.stringify(res.candidates));
  Logger.log(res.text);
  Logger.log('⭐ 보고서 · candidates.json 저장 — 다음은 oppDetail · 폴더: ' + folder.getUrl());
}

// 셈 본체(순수 함수 — 시험 장치가 직접 부른다)
function opp_analyze_(dd, credits, st, today) {
  var out = [], P = function (s) { out.push(s); };
  var S = dd.rows, n = opp_n_, CUT = '2025-11-01';
  P('=== OpeningProbe analyze ' + new Date().toISOString() + ' · 오늘(토론토) ' + today + ' ===');
  P('');
  P('0. 수집');
  P('   saleList 받은 행 ' + dd.raw + ' · 고유 SaleID ' + S.length + ' · 겹친 행 ' + (dd.raw - S.length) + ' · SaleID 없는 행 ' + dd.noKey +
    ' · API Total(첫 쪽) ' + st.salesTotal + (dd.raw === st.salesTotal ? ' · 같다' : ' ⚠️ 받은 행 ≠ Total(수집 중 늘었거나 쪽이 밀렸다 — 고유 SaleID 로 센다)'));
  P('   ref/customer/credits 받은 행 ' + credits.length + ' · API Total ' + (st.creditsTotal === null || st.creditsTotal === undefined ? '(응답에 없음)' : st.creditsTotal));

  // 1 분포
  P('');
  P('1. 분포');
  P('   CombinedInvoiceStatus × CombinedPaymentStatus × 받은 비율(인보이스 금액 대비)');
  opp_countBy_(S, function (s) { return opp_show_(s.CombinedInvoiceStatus) + ' × ' + opp_show_(s.CombinedPaymentStatus) + ' × ' + opp_ratio_(s); })
    .forEach(function (r) { P('     ' + opp_padR_(r.k, 62) + r.n); });
  P('   Type');
  opp_countBy_(S, function (s) { return opp_show_(s.Type); }).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });
  P('   CustomerCurrency');
  opp_countBy_(S, function (s) { return opp_show_(s.CustomerCurrency); }).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });
  P('   Status(위 15)');
  opp_countBy_(S, function (s) { return opp_show_(s.Status); }).slice(0, 15).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });
  P('   InvoiceDate 달(인보이스 있는 것 · ' + CUT + ' 앞은 Omni 시절)');
  opp_countBy_(S.filter(function (s) { return opp_d_(s.InvoiceDate); }), function (s) { return opp_d_(s.InvoiceDate).slice(0, 7); })
    .sort(function (a, b) { return a.k < b.k ? -1 : 1; }).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });
  var noInv = S.filter(function (s) { return !opp_d_(s.InvoiceDate); }).length;
  P('     (InvoiceDate 없음)            ' + noInv);

  // 2 칸끼리 차이
  P('');
  P('2. 칸끼리 차이(0.005 넘게)');
  opp_pairDiff_(P, S, 'InvoiceAmount', 'SaleInvoicesTotalAmount');
  opp_pairDiff_(P, S, 'PaidAmount', 'CombinedPaymentTotal');

  // 3 열린 것
  var open = S.filter(opp_isOpen_);
  P('');
  P('3. 열린 것(짐작 기준: CombinedInvoiceStatus · Status 가 VOIDED 아님 ∧ InvoiceAmount − PaidAmount > 0.005)');
  opp_openBlock_(P, '전체', open);
  opp_openBlock_(P, 'InvoiceDate ' + CUT + ' 이전(Omni 질문)', open.filter(function (s) { return opp_d_(s.InvoiceDate) && opp_d_(s.InvoiceDate) < CUT; }));
  opp_openBlock_(P, 'InvoiceDate 없음', open.filter(function (s) { return !opp_d_(s.InvoiceDate); }));
  opp_openBlock_(P, 'InvoiceDueDate 지남(< ' + today + ')', open.filter(function (s) { return opp_d_(s.InvoiceDueDate) && opp_d_(s.InvoiceDueDate) < today; }));
  opp_openBlock_(P, 'InvoiceDueDate 없음', open.filter(function (s) { return !opp_d_(s.InvoiceDueDate); }));
  P('   열린 것의 상태 짝');
  opp_countBy_(open, function (s) { return opp_show_(s.CombinedInvoiceStatus) + ' × ' + opp_show_(s.CombinedPaymentStatus); })
    .forEach(function (r) { P('     ' + opp_padR_(r.k, 50) + r.n); });

  // 4 손님 크레딧
  P('');
  P('4. ref/customer/credits(ShowUsedCredits 기본 false)');
  var rem = credits.filter(function (c) { return n(c.RemainingAmount) > 0.005; });
  P('   행 ' + credits.length + ' · RemainingAmount > 0 인 행 ' + rem.length + ' · 손님 ' + opp_uniq_(rem, 'CustomerID') +
    ' · Σ Amount ' + opp_sumByCur_(credits, 'Amount', 'Currency') + ' · Σ RemainingAmount ' + opp_sumByCur_(credits, 'RemainingAmount', 'Currency'));
  P('   Description(위 10)');
  opp_countBy_(credits, function (c) { return opp_show_(c.Description); }).slice(0, 10).forEach(function (r) { P('     ' + opp_padR_(r.k, 50) + r.n); });
  P('   Account');
  opp_countBy_(credits, function (c) { return opp_show_(c.Account); }).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });
  P('   Date 달');
  opp_countBy_(credits, function (c) { return (opp_d_(c.Date) || '(없음)').slice(0, 7); })
    .sort(function (a, b) { return a.k < b.k ? -1 : 1; }).forEach(function (r) { P('     ' + opp_padR_(r.k, 30) + r.n); });

  // 5 후보
  var cand = opp_candidates_(S, credits, CUT);
  P('');
  P('5. 후보 — 경우마다 3(최근 인보이스 · 같은 날이면 오더 번호)');
  cand.cases.forEach(function (cs) {
    P('   (' + cs.code + ') ' + cs.label + ' — 해당 ' + cs.total + ' 건');
    if (!cs.picks.length) P('       (없음)');
    cs.picks.forEach(function (s) { P('       ' + opp_saleLine_(s)); });
  });
  P('   (사) 손님 크레딧 RemainingAmount > 0 — 해당 ' + cand.creditPicksTotal + ' 행');
  if (!cand.creditPicks.length) P('       (없음)');
  cand.creditPicks.forEach(function (c) { P('       ' + opp_creditLine_(c)); });

  return { text: out.join('\n'), candidates: cand };
}

// 경우 분류 — 같은 칸으로 찾고 같은 칸으로 답을 맞추면 틀려도 모른다 ⇒ 각 경우의 첫째는 Caleb 화면 대조로 간다
function opp_candidates_(S, credits, CUT) {
  var n = opp_n_, live = S.filter(function (s) { return !opp_voided_(s); });
  var defs = [
    ['가', '부분 결제(0 < Paid < Amount)', function (s) { return n(s.InvoiceAmount) > 0.005 && n(s.PaidAmount) > 0.005 && n(s.InvoiceAmount) - n(s.PaidAmount) > 0.005; }],
    ['나', '넘게 받음(Paid > Amount · 인보이스 있음)', function (s) { return n(s.InvoiceAmount) > 0.005 && n(s.PaidAmount) - n(s.InvoiceAmount) > 0.005; }],
    ['다', '크레딧 노트 있음(CreditNoteNumber 있음 · AUTHORISED 먼저)', function (s) { return !!opp_str_(s.CreditNoteNumber); }],
    ['라', 'Advanced 이고 열린 것', function (s) { return /advanced/i.test(s.Type || '') && opp_isOpen_(s); }],
    ['마', CUT + ' 이전 발행이고 열린 것', function (s) { return opp_d_(s.InvoiceDate) && opp_d_(s.InvoiceDate) < CUT && opp_isOpen_(s); }],
    ['바', '인보이스 전 선결제(Amount 0 · Paid > 0 — 지시서 밖 · 이견 4)', function (s) { return n(s.InvoiceAmount) <= 0.005 && n(s.PaidAmount) > 0.005; }]
  ];
  var cases = defs.map(function (d) {
    var hit = live.filter(d[2]);
    if (d[0] === '다') hit.sort(function (a, b) { return (opp_show_(a.CreditNoteStatus) === 'AUTHORISED' ? 0 : 1) - (opp_show_(b.CreditNoteStatus) === 'AUTHORISED' ? 0 : 1) || opp_recent_(a, b); });
    else hit.sort(opp_recent_);
    var byStatus = d[0] === '다' ? opp_countBy_(hit, function (s) { return opp_show_(s.CreditNoteStatus); }).map(function (r) { return r.k + ' ' + r.n; }).join(' · ') : null;
    return { code: d[0], label: d[1] + (byStatus ? ' [' + byStatus + ']' : ''), total: hit.length, picks: hit.slice(0, 3) };
  });
  var rem = credits.filter(function (c) { return n(c.RemainingAmount) > 0.005; })
    .sort(function (a, b) { return (opp_d_(b.Date) || '') < (opp_d_(a.Date) || '') ? -1 : ((opp_d_(b.Date) || '') > (opp_d_(a.Date) || '') ? 1 : 0); });
  return { cases: cases, creditPicks: rem.slice(0, 3), creditPicksTotal: rem.length };
}


/* ═══════════════════════════════════════════════════════════
   4  후보 상세 + 화면 대조표 — 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function oppDetail() {
  var st = opp_state_();
  var folder = opp_folder_(st);
  var cand = opp_readJson_(folder, 'candidates.json');
  if (!cand) { Logger.log('candidates.json 이 없다 — oppAnalyze 먼저.'); return; }
  var jobs = opp_detailJobs_(cand), started = Date.now();
  var i = st.detailNext || 0;
  for (; i < jobs.length; i++) {
    if (Date.now() - started > 270000) break;
    var j = jobs[i];
    var x = opp_get_(j.path);
    opp_save_(folder, j.file, x.text);
    Logger.log('   ' + (i + 1) + '/' + jobs.length + ' ' + j.file + ' → HTTP ' + x.code + (x.isJson ? '' : ' ⚠️ JSON 아님'));
  }
  if (i < jobs.length) {
    st.detailNext = i; opp_save_state_(st);
    Logger.log('Next run — 상세 ' + (i + 1) + '/' + jobs.length + ' 부터 · oppDetail 을 한 번 더 실행하라'); return;
  }
  st.detailNext = jobs.length; opp_save_state_(st);
  var files = {};
  jobs.forEach(function (j) { files[j.file] = opp_readJson_(folder, j.file); });
  var text = opp_detailReport_(cand, jobs, files);
  folder.createFile('report-detail-' + opp_stamp_() + '.txt', text, MimeType.PLAIN_TEXT);
  Logger.log(text);
  Logger.log('⭐ 상세 끝 · 폴더: ' + folder.getUrl());
}

// 부를 것 목록 — sale 하나마다 상세 + sale/payment · 손님마다 크레딧(쓴 것 포함) · 겹치면 한 번
function opp_detailJobs_(cand) {
  var jobs = [], seenSale = {}, seenCust = {};
  var addCust = function (id, name) {
    if (!id || seenCust[id]) return; seenCust[id] = 1;
    jobs.push({ kind: 'credits', customerId: id, customer: name, path: 'ref/customer/credits?Page=1&Limit=100&CustomerID=' + id + '&ShowUsedCredits=true', file: 'detail-credits-' + opp_safe_(name || id).slice(0, 40) + '-' + id.slice(0, 8) + '.json' });
  };
  cand.cases.forEach(function (cs) {
    cs.picks.forEach(function (s) {
      if (!s.SaleID || seenSale[s.SaleID]) return; seenSale[s.SaleID] = 1;
      jobs.push({ kind: 'sale', code: cs.code, sale: s, path: 'sale?ID=' + s.SaleID + '&HideInventoryMovements=true', file: 'detail-sale-' + opp_safe_(s.OrderNumber) + '.json' });
      jobs.push({ kind: 'payment', code: cs.code, sale: s, path: 'sale/payment?SaleID=' + s.SaleID, file: 'detail-payment-' + opp_safe_(s.OrderNumber) + '.json' });
    });
  });
  cand.cases.forEach(function (cs) { cs.picks.forEach(function (s) { addCust(s.CustomerID, s.Customer); }); });
  cand.creditPicks.forEach(function (c) { addCust(c.CustomerID, c.CustomerName); });
  return jobs;
}

function opp_detailReport_(cand, jobs, files) {
  var out = [], P = function (s) { out.push(s); }, n = opp_n_;
  P('=== OpeningProbe detail ' + new Date().toISOString() + ' ===');
  jobs.filter(function (j) { return j.kind === 'sale'; }).forEach(function (j) {
    var s = j.sale, d = files[j.file], pay = files['detail-payment-' + opp_safe_(s.OrderNumber) + '.json'];
    P('');
    P('(' + j.code + ') ' + opp_saleLine_(s));
    if (!d) { P('   ⚠️ 상세 없음(JSON 아님)'); return; }
    var invs = opp_arr_(d.Invoices !== undefined ? d.Invoices : d.Invoice);
    var cns = opp_arr_(d.CreditNotes !== undefined ? d.CreditNotes : d.CreditNote);
    P('   상세 최상위: Status ' + opp_show_(d.Status) + ' · Terms ' + opp_show_(d.Terms) + ' · CombinedPaymentStatus ' + opp_show_(d.CombinedPaymentStatus) + ' · 인보이스 ' + invs.length + ' · 크레딧 노트 ' + cns.length);
    P('   인보이스   번호        상태         발행일      기한        Total        Paid        ΣPayments   결제 수');
    invs.forEach(function (v) {
      var ps = opp_arr_(v.Payments);
      P('              ' + [opp_padR_(opp_show_(v.InvoiceNumber), 11), opp_padR_(opp_show_(v.Status), 12), opp_padR_(opp_d_(v.InvoiceDate) || '-', 11), opp_padR_(opp_d_(v.InvoiceDueDate) || '-', 11),
        opp_padL_(opp_m_(v.Total), 11), opp_padL_(opp_m_(v.Paid), 11), opp_padL_(opp_m_(opp_sum_(ps, 'Amount')), 11), opp_padL_(String(ps.length), 6)].join(' '));
    });
    cns.forEach(function (c) {
      var rf = opp_arr_(c.Refunds);
      P('   크레딧 노트 ' + opp_show_(c.CreditNoteNumber) + ' · 원 인보이스 ' + opp_show_(c.CreditNoteInvoiceNumber) + ' · ' + opp_show_(c.Status) + ' · ' + (opp_d_(c.CreditNoteDate) || '-') +
        ' · Total ' + opp_m_(c.Total) + ' · ΣRefunds ' + opp_m_(opp_sum_(rf, 'Amount')) + ' (' + rf.length + ')');
    });
    var invTotal = invs.filter(function (v) { return opp_show_(v.Status) !== 'VOIDED'; }).reduce(function (a, v) { return a + n(v.Total); }, 0);
    var cnTotal = cns.filter(function (c) { return opp_show_(c.Status) !== 'VOIDED'; }).reduce(function (a, c) { return a + n(c.Total); }, 0);
    P('   대조: Σ인보이스 Total ' + opp_m_(invTotal) + ' − Σ크레딧 노트 Total ' + opp_m_(cnTotal) + ' = ' + opp_m_(invTotal - cnTotal) + '  vs  목록 InvoiceAmount ' + opp_m_(s.InvoiceAmount) +
      ' · SaleInvoicesTotalAmount ' + opp_m_(s.SaleInvoicesTotalAmount));
    if (pay) {
      var pl = opp_arr_(pay);
      var byType = opp_countBy_(pl, function (p) { return opp_show_(p.Type) + (p.CreditID ? ' (크레딧에서)' : ''); });
      P('   sale/payment ' + pl.length + ' 행: ' + byType.map(function (r) {
        var sum = pl.filter(function (p) { return opp_show_(p.Type) + (p.CreditID ? ' (크레딧에서)' : '') === r.k; }).reduce(function (a, p) { return a + n(p.Amount); }, 0);
        return r.k + ' ' + r.n + ' 건 ' + opp_m_(sum);
      }).join(' · ') + '  vs  목록 PaidAmount ' + opp_m_(s.PaidAmount) + ' · CombinedPaymentTotal ' + opp_m_(s.CombinedPaymentTotal));
    } else {
      P('   sale/payment: ⚠️ 없음(JSON 아님)');
    }
  });
  P('');
  P('손님 크레딧(ShowUsedCredits=true)');
  jobs.filter(function (j) { return j.kind === 'credits'; }).forEach(function (j) {
    var d = files[j.file], rows = d ? opp_arr_(d.CustomerCredits) : [];
    P('   ' + opp_show_(j.customer) + ' — ' + (d ? rows.length + ' 행 · Σ Amount ' + opp_m_(opp_sum_(rows, 'Amount')) + ' · Σ RemainingAmount ' + opp_m_(opp_sum_(rows, 'RemainingAmount')) : '⚠️ 없음(JSON 아님)'));
    rows.slice(0, 8).forEach(function (c) { P('       ' + (opp_d_(c.Date) || '-') + ' · ' + opp_show_(c.Description) + ' · Amount ' + opp_m_(c.Amount) + ' · Remaining ' + opp_m_(c.RemainingAmount) + ' · ' + opp_show_(c.Currency) + ' · 계정 ' + opp_show_(c.Account)); });
  });
  P('');
  P(opp_screenTable_(cand));
  return out.join('\n');
}

// ⭐ Caleb 화면 대조표 — 경우마다 첫째 한 명 · 같다/다르다만 답한다 · ⚠️ Cin7 화면의 메뉴 · 칸 이름은 짐작(실물과 다르면 가까운 칸으로)
function opp_screenTable_(cand) {
  var out = [], P = function (s) { out.push(s); };
  var look = {
    '가': '받은 금액 · 남은 금액(Balance due)이 프로브 Paid · (Amount − Paid) 와 같은가',
    '나': '넘게 받은 차액이 어디로 갔나 — 인보이스 탭의 Paid 와, 손님 화면의 크레딧(아래 (사) 와 같은 곳)에 그 차액이 있나',
    '다': '크레딧 노트 탭의 Total 과, 인보이스 탭의 Balance — 프로브 InvoiceAmount 가 「인보이스 − 크레딧」 인가(apib 설명) · 크레딧이 환불됐나 · 다음 인보이스에 쓰였나',
    '라': '인보이스가 여럿이면 인보이스마다 Total · Paid · 기한 — 프로브 InvoiceAmount 가 그 합인가(④)',
    '마': '이 인보이스가 Omni 에서 넘어온 것인가(메모 · 날짜) · 남은 금액이 실제 받을 돈인가',
    '바': '인보이스 전에 받은 선결제(Prepayment)가 프로브 PaidAmount 와 같은가 · 이 오더가 아직 열려 있나'
  };
  P('════ Caleb 화면 대조표 — 한 줄씩 Cin7 화면을 열어 「같다 / 다르다(화면 값)」 만 답한다 ════');
  P('   (Cin7 메뉴 · 탭 이름은 짐작이다 — 실물 이름이 다르면 가장 가까운 것을 보고 적어 달라)');
  cand.cases.forEach(function (cs) {
    var s = cs.picks[0];
    if (!s) { P('(' + cs.code + ') ' + cs.label + ' — 후보 없음(대조 안 함)'); return; }
    P('(' + cs.code + ') ' + cs.label);
    P('     Cin7 → Sale → ' + opp_show_(s.OrderNumber) + ' 검색 · 열기(손님 ' + opp_show_(s.Customer) + ' · 인보이스 ' + opp_show_(s.InvoiceNumber) + ') → Invoice 탭' + (cs.code === '다' ? ' · Credit Note 탭' : '') + '의 Total · Paid · Balance');
    P('     볼 것: ' + look[cs.code]);
    P('     프로브 값: InvoiceAmount ' + opp_m_(s.InvoiceAmount) + ' · PaidAmount ' + opp_m_(s.PaidAmount) + ' · 남은(Amount − Paid) ' + opp_m_(opp_n_(s.InvoiceAmount) - opp_n_(s.PaidAmount)) +
      ' · SaleInvoicesTotalAmount ' + opp_m_(s.SaleInvoicesTotalAmount) + ' · CombinedPaymentTotal ' + opp_m_(s.CombinedPaymentTotal) +
      ' · CombinedInvoiceStatus ' + opp_show_(s.CombinedInvoiceStatus) + ' · CombinedPaymentStatus ' + opp_show_(s.CombinedPaymentStatus) +
      (s.CreditNoteNumber ? ' · CreditNote ' + s.CreditNoteNumber + ' ' + opp_show_(s.CreditNoteStatus) : '') + ' · 기한 ' + (opp_d_(s.InvoiceDueDate) || '-'));
    P('     답: 같다 / 다르다 → ');
  });
  var c = cand.creditPicks[0];
  if (c) {
    P('(사) 손님 크레딧(오버페이 · 열린 크레딧 원천 후보 ref/customer/credits)');
    P('     Cin7 → Customers → ' + opp_show_(c.CustomerName) + ' 열기 → 크레딧 · 잔액이 보이는 곳(탭 이름 짐작: Credits / Balance) — 「쓸 수 있는 크레딧」 숫자');
    P('     볼 것: 화면의 남은 크레딧이 프로브 RemainingAmount 와 같은가 · 이 손님의 다른 크레딧 줄이 화면에 더 있나(위 「손님 크레딧」 목록)');
    P('     프로브 값: ' + opp_creditLine_(c));
    P('     답: 같다 / 다르다 → ');
  } else {
    P('(사) 손님 크레딧 — RemainingAmount > 0 인 행 없음(대조 안 함 · 오버페이가 다른 곳에 있다는 뜻일 수 있다 — (나) 의 답을 본다)');
  }
  return out.join('\n');
}


/* ═══════════════════════════════════════════════════════════
   판정 · 셈 도우미(순수)
   ═══════════════════════════════════════════════════════════ */

function opp_voided_(s) { return opp_show_(s.CombinedInvoiceStatus) === 'VOIDED' || opp_show_(s.Status) === 'VOIDED'; }
function opp_isOpen_(s) { return !opp_voided_(s) && opp_n_(s.InvoiceAmount) - opp_n_(s.PaidAmount) > 0.005; }
function opp_ratio_(s) {
  var a = opp_n_(s.InvoiceAmount), p = opp_n_(s.PaidAmount);
  if (a <= 0.005) return p > 0.005 ? '청구 0 · 받음 있음' : '청구 0';
  if (p <= 0.005) return '0';
  if (a - p > 0.005) return '일부';
  if (p - a > 0.005) return '넘음';
  return '다';
}
function opp_filterVerdict_(none, base, paid, auth, zzz) {
  if ([none, base, paid, auth, zzz].some(function (t) { return t === null || t === undefined; })) return '⚠️ Total 이 비어 판단 못 함 — 원본을 본다';
  if (base === none) return '⚠️ CreatedSince 도 Total 을 안 바꿨다 — 배선 확인 실패(이 판정을 쓰지 마라)';
  if (paid === base && auth === base && zzz === base) return '⚠️ 무시됨 — CombinedInvoiceStatus 는 세 값 모두 Total 이 CreatedSince 만과 같다(서버 필터 안 씀 · 전량 + 클라이언트 필터)';
  if (zzz === 0 && paid <= base && auth <= base) return '⭐ 동작한다 — 없는 값 0 · PAID ' + paid + ' · AUTHORISED ' + auth + ' ≤ ' + base + ' (나머지 ' + (base - paid - auth) + ' 은 다른 상태)';
  return '❓ 섞였다 — 원본을 본다(PAID ' + paid + ' · AUTHORISED ' + auth + ' · ZZZ ' + zzz + ' · 기준 ' + base + ')';
}
function opp_openBlock_(P, label, rows) {
  var sum = {};
  rows.forEach(function (s) { var k = opp_show_(s.CustomerCurrency); sum[k] = (sum[k] || 0) + opp_n_(s.InvoiceAmount) - opp_n_(s.PaidAmount); });
  P('   ' + opp_padR_(label, 36) + rows.length + ' 장 · 손님 ' + opp_uniq_(rows, 'CustomerID') + ' · 남은 합 ' +
    (Object.keys(sum).sort().map(function (k) { return k + ' ' + opp_m_(sum[k]); }).join(' · ') || '0'));
}
function opp_pairDiff_(P, S, a, b) {
  var missB = S.filter(function (s) { return s[b] === undefined || s[b] === null; }).length;
  var diff = S.filter(function (s) { return s[b] !== undefined && s[b] !== null && Math.abs(opp_n_(s[a]) - opp_n_(s[b])) > 0.005; });
  P('   ' + a + ' vs ' + b + ': ' + b + ' 없음 ' + missB + ' · 다른 행 ' + diff.length + ' / ' + S.length);
  diff.slice(0, 5).forEach(function (s) { P('       ' + opp_show_(s.OrderNumber) + ' · ' + a + ' ' + opp_m_(s[a]) + ' · ' + b + ' ' + opp_m_(s[b]) + ' · ' + opp_show_(s.Type) + ' · CN ' + opp_show_(s.CreditNoteNumber)); });
}
function opp_saleLine_(s) {
  return [opp_show_(s.Customer), opp_show_(s.OrderNumber), '인보이스 ' + opp_show_(s.InvoiceNumber), opp_show_(s.Type), opp_show_(s.CustomerCurrency),
    '발행 ' + (opp_d_(s.InvoiceDate) || '-'), '기한 ' + (opp_d_(s.InvoiceDueDate) || '-'),
    'InvoiceAmount ' + opp_m_(s.InvoiceAmount), 'PaidAmount ' + opp_m_(s.PaidAmount), 'SaleInvoicesTotalAmount ' + opp_m_(s.SaleInvoicesTotalAmount),
    'CombinedPaymentTotal ' + opp_m_(s.CombinedPaymentTotal), opp_show_(s.CombinedInvoiceStatus) + '/' + opp_show_(s.CombinedPaymentStatus),
    'CN ' + opp_show_(s.CreditNoteNumber) + ' ' + opp_show_(s.CreditNoteStatus), 'Status ' + opp_show_(s.Status)].join(' · ');
}
function opp_creditLine_(c) {
  return [opp_show_(c.CustomerName), (opp_d_(c.Date) || '-'), opp_show_(c.Description), 'Amount ' + opp_m_(c.Amount), 'RemainingAmount ' + opp_m_(c.RemainingAmount), opp_show_(c.Currency), '계정 ' + opp_show_(c.Account), 'CreditID ' + opp_show_(c.CreditID)].join(' · ');
}
function opp_recent_(a, b) {
  var x = opp_d_(a.InvoiceDate) || '', y = opp_d_(b.InvoiceDate) || '';
  if (x !== y) return x < y ? 1 : -1;
  return opp_show_(a.OrderNumber) < opp_show_(b.OrderNumber) ? 1 : -1;
}
function opp_countBy_(rows, fn) {
  var m = {};
  rows.forEach(function (r) { var k = fn(r); m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).map(function (k) { return { k: k, n: m[k] }; }).sort(function (a, b) { return b.n - a.n || (a.k < b.k ? -1 : 1); });
}
function opp_dedupe_(r, key) {
  var seen = {}, out = [], noKey = 0;
  r.rows.forEach(function (x) { var k = x[key]; if (!k) { noKey++; out.push(x); return; } if (seen[k]) return; seen[k] = 1; out.push(x); });
  return { rows: out, raw: r.rows.length, noKey: noKey };
}
function opp_uniq_(rows, key) { var m = {}; rows.forEach(function (r) { m[r[key] || '(none)'] = 1; }); return Object.keys(m).length; }
function opp_sum_(rows, key) { return rows.reduce(function (a, r) { return a + opp_n_(r[key]); }, 0); }
function opp_sumByCur_(rows, key, curKey) {
  var m = {}; rows.forEach(function (r) { var k = opp_show_(r[curKey]); m[k] = (m[k] || 0) + opp_n_(r[key]); });
  return Object.keys(m).sort().map(function (k) { return k + ' ' + opp_m_(m[k]); }).join(' · ') || '0';
}
function opp_arr_(v) { return v === undefined || v === null ? [] : (Array.isArray(v) ? v : [v]); }
function opp_n_(v) { var x = Number(v); return isFinite(x) ? x : 0; }
function opp_m_(v) { return (v === undefined || v === null) ? '(없음)' : opp_n_(v).toFixed(2); }
function opp_str_(v) { return (v === undefined || v === null) ? '' : String(v).trim(); }
function opp_show_(v) { var s = opp_str_(v); return s === '' ? '(blank)' : s; }
function opp_d_(v) { var s = opp_str_(v); return s ? s.slice(0, 10) : ''; }
function opp_pad_(n) { return ('0000' + n).slice(-4); }
function opp_padR_(s, w) { s = String(s); return s.length >= w ? s + ' ' : s + new Array(w - s.length + 1).join(' '); }
function opp_padL_(s, w) { s = String(s); return s.length >= w ? s : new Array(w - s.length + 1).join(' ') + s; }
function opp_safe_(s) { return String(s || 'x').replace(/[^A-Za-z0-9_-]/g, '_'); }
function opp_shape_(d) {
  if (d === null || d === undefined) return '(본문 없음)';
  if (Array.isArray(d)) return '배열 ' + d.length + ' 행' + (d.length ? ' · 첫 행 키: ' + Object.keys(d[0] || {}).join(', ') : '');
  var keys = Object.keys(d), arrKey = keys.filter(function (k) { return Array.isArray(d[k]); })[0];
  return '최상위 키: ' + keys.join(', ') + (d.Total !== undefined ? ' · Total ' + d.Total : '') +
    (arrKey ? ' · 배열 ' + arrKey + ' ' + d[arrKey].length + ' 행' + (d[arrKey].length ? ' · 첫 행 키: ' + Object.keys(d[arrKey][0] || {}).join(', ') : '') : '');
}


/* ═══════════════════════════════════════════════════════════
   공통 — Cin7 · Drive · 상태
   ═══════════════════════════════════════════════════════════ */

/** Cin7 GET 한 번 — 429 는 Retry-After 만큼(없으면 60 초) 쉬고 다시(여섯 번까지) · 그 밖의 코드는 돌려준다(throw 안 함) · 호출 뒤 1.2 초 */
function opp_get_(pathAndQuery) {
  var headers = { 'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'), 'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'), 'Content-Type': 'application/json' };
  for (var tries = 0; tries < 6; tries++) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery, { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) {
      var hs = res.getHeaders() || {}, raw = null;
      Object.keys(hs).forEach(function (k) { if (k.toLowerCase() === 'retry-after') raw = hs[k]; });
      var ra = Number(String(raw === null ? '60' : raw).replace(/[^0-9]/g, '')) || 60;
      Logger.log('   429 — ' + ra + '초 대기 후 재시도(' + pathAndQuery.slice(0, 50) + ')');
      Utilities.sleep(ra * 1000 + 1000);
      continue;
    }
    var text = res.getContentText(), data = null, isJson = false;
    try { data = JSON.parse(text); isJson = true; } catch (e) { data = null; }   // 규칙 18 — 없는 경로는 200 + HTML
    Utilities.sleep(1200);
    return { code: code, text: text, data: data, isJson: isJson };
  }
  throw new Error('Cin7 429 가 여섯 번 — ' + pathAndQuery);
}
/** 수집용 — 200 + JSON 이 아니면 멈춘다(부분 수집을 남기지 않게 속성은 부른 쪽이 아직 안 바꿨다) */
function opp_need_(pathAndQuery) {
  var x = opp_get_(pathAndQuery);
  if (x.code !== 200 || !x.isJson) throw new Error('Cin7 ' + x.code + (x.isJson ? '' : ' (JSON 아님)') + ' · ' + pathAndQuery + ' : ' + String(x.text).slice(0, 300));
  return x;
}
function opp_get_last_detail_(folder, s) {
  var d = opp_readJson_(folder, 'peek-f-sale-' + opp_safe_(s.OrderNumber) + '.json');
  if (!d) return null;
  var invs = opp_arr_(d.Invoices !== undefined ? d.Invoices : d.Invoice), cns = opp_arr_(d.CreditNotes !== undefined ? d.CreditNotes : d.CreditNote);
  var inv = invs[0] || {}, pay = opp_arr_(inv.Payments)[0] || {}, cn = cns[0] || {};
  return 'Invoices ' + invs.length + ' [' + Object.keys(inv).join(', ') + '] · Payments[0] [' + Object.keys(pay).join(', ') + '] · CreditNotes ' + cns.length + ' [' + Object.keys(cn).join(', ') + ']';
}

function opp_state_() {
  var v = PropertiesService.getScriptProperties().getProperty('OPP_STATE');
  return v ? JSON.parse(v) : {};
}
function opp_save_state_(st) { PropertiesService.getScriptProperties().setProperty('OPP_STATE', JSON.stringify(st)); }
function opp_folder_(st) {
  if (st.folderId) return DriveApp.getFolderById(st.folderId);
  var f = DriveApp.createFolder('OpeningProbe ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
  st.folderId = f.getId(); opp_save_state_(st);
  return f;
}
function opp_save_(folder, name, text) { folder.createFile(name, String(text === undefined || text === null ? '' : text), MimeType.PLAIN_TEXT); }
function opp_readAll_(folder, prefix) {
  var it = folder.getFiles(), files = [];
  while (it.hasNext()) { var f = it.next(); if (f.getName().indexOf(prefix) === 0 && /\.json$/.test(f.getName())) files.push(f); }
  files.sort(function (a, b) { return a.getName() < b.getName() ? -1 : 1; });
  var rows = [];
  files.forEach(function (f) { rows = rows.concat(JSON.parse(f.getBlob().getDataAsString())); });
  return { rows: rows, files: files.length };
}
function opp_readJson_(folder, name) {
  var it = folder.getFiles(), hit = null;
  while (it.hasNext()) { var f = it.next(); if (f.getName() === name) hit = f; }   // 같은 이름이 여럿이면 마지막(다시 돌린 것)
  if (!hit) return null;
  try { return JSON.parse(hit.getBlob().getDataAsString()); } catch (e) { return null; }
}
function opp_today_() { return Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd'); }
function opp_stamp_() { return Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm'); }
