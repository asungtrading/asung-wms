/**
 * ImsLoadOpening.gs — 컷오버 미수 · 받아 둔 돈 이월 적재 (판정 775 · 783 ~ 786 · ar-3)
 * 2026-10-27 작성 · 창구 = ar-2(20261027014202_ar_2_opening_carry_forward.sql · so_opening_load(p jsonb, p_dry) · service_role 만)
 * 원천 읽기의 꼴은 ar-1 OpeningProbe.gs(daf8af5) 의 실측을 그대로 가져왔다 — saleList 전량 · ref/customer/credits 전량 · /sale?ID= 상세의 Invoices[] · CreditNotes[]
 *
 * ⚠️⚠️ 대상: Asung-IMS(지금의 테스트 DB = 컷오버 뒤 메인 · 판정 617) — SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY (ImsLoadHist · ImsRefLoad 와 같다) · 로그 첫 줄이 프로젝트 ref 를 찍는다
 * ⚠️ getProp · ims_fetch_ 는 같은 프로젝트의 Config.gs · ImsRefLoad.gs 것을 쓴다(다시 만들지 않는다) · Cin7 호출은 이 파일의 ilo_get_
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다 · 최상위 const 금지 · 식별자 ASCII 만 · 트리거 없음(손으로 돌린다)
 * ⚠️ 이 파일의 이름은 전부 ilo 로 시작한다 — 같은 이름 함수가 둘이면 에러 없이 뒤의 것이 이긴다
 * ⚠️ Script Properties 는 **ILO_STATE 하나**(JSON) — 이 프로젝트는 속성이 50 개를 넘어 설정 화면이 읽기 전용이다(asung-apps-script 규칙 6)
 *    그래서 허락 표지(어긋남 통과 · 거부 통과)도 속성이 아니라 ILO_STATE 안의 표지이고, 코드(iloAllowMismatch · iloAllowRejects)로만 켠다 · 한 번 쓰면 꺼진다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY · SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서(각 단계가 「Next run」 이면 같은 함수를 한 번 더 · 4 분 30 초에서 멈춘다)
 *   1  iloCollect   saleList 전량(Limit 1000 · 받은 행 = Total 확인 · 쪽 되풀이 가드) + ref/customer/credits 전량 → Drive(쪽마다 파일)
 *   2  iloDetail    후보만 /sale?ID= 상세 — 열린 것(VOIDED 아님 ∧ SaleInvoicesTotalAmount − CombinedPaymentTotal > 0.005)
 *                   + 크레딧으로 안 바뀐 오버페이(VOIDED 아님 ∧ CombinedPaymentTotal − SaleInvoicesTotalAmount > 0.005 ∧ CombinedPaymentStatus 에 CREDITED 없음)
 *                   → candidates.json · detail-*.json(25 건마다 저장 · 이어 달리기)
 *   3  iloBuild     창구 입력 p 를 만든다(쓰기 0) → build-*.json(p + 요약) · report-build-*.txt
 *                   ⭐ sale 마다 대조: Σ(상세 인보이스 Total − Paid · VOIDED · DRAFT 제외 · 부호 그대로) = 목록 SaleInvoicesTotalAmount − CombinedPaymentTotal (0.01 안)
 *                      어긋나는 sale 은 목록으로 보고하고 Apply 를 막는다(크레딧 노트가 인보이스 Paid 에 어떻게 들어가는지는 SO-00269 한 건만 봤다 — 짐작)
 *   4  iloDry       so_opening_load(p, true) → report-dry-*.txt(거부 · 손님 못 찾음 · large[] 를 맨 위에 · 끝에 Caleb 대조표)
 *   5  iloApply     같은 p(md5 가 Dry 때와 같아야) → 직전 Dry 한 번 더(거부 > 0 이면 멈춤) → so_opening_load(p, false) · complete:true → report-apply-*.txt
 *   6  iloVerify    읽기만 — so_invoice(kind opening) · so_payment(method opening) · so_customer_balance 표본 → Build 요약과 같은가 → report-verify-*.txt
 *   ⟲  iloReset     ILO_STATE 만 지운다(Drive 폴더는 그대로)
 *   ⚑  iloAllowMismatch · iloAllowRejects   허락 표지를 한 번 켠다(각각 Apply 의 두 멈춤을 한 번만 통과)
 *
 * 입력 p(창구 ar-2): {as_of, complete:true, invoices:[{legacy_sale_id, legacy_invoice_id, invoice_number, cin7_customer_id, issued_on, due_on, payment_term_name, currency, total_before_tax, tax, total, prior_settled}],
 *                     credits:[{cin7_customer_id, currency, amount, source: credit|overpay, reference}]}
 *   이월 인보이스 = 후보 sale 의 Invoices[] 중 Status 가 VOIDED · DRAFT 가 아니고 Total − Paid > 0.005 인 것마다 하나 · legacy_sale_id = SaleID · legacy_invoice_id = TaskID · cin7_customer_id = 상세 CustomerID · currency = CustomerCurrency · payment_term_name = Terms · prior_settled = Paid
 *   받아 둔 돈 = ① ref/customer/credits 의 RemainingAmount > 0 행마다 {credit · RemainingAmount · Description 의 글자(HTML 링크 벗김) + 날짜}
 *              ② 오버페이 sale 마다 {overpay · CombinedPaymentTotal − SaleInvoicesTotalAmount · 'SO-… · invoice … · balance credited'}
 *   as_of = ilo_cfg_().asOf 가 있으면 그 날 · 없으면 Build 를 돌린 날(토론토) — 창구는 이 날을 받아 둔 돈의 paid_on 으로 쓰고 발행일이 이 날 뒤면 거부한다
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   상수 — 함수로(최상위 const 금지)
   ═══════════════════════════════════════════════════════════ */

function ilo_cfg_() {
  return {
    asOf: null,             // 창구 p.as_of — null 이면 Build 날(토론토) · 마감일로 못 박으려면 '2026-10-31'
    saleLimit: 1000,        // ar-1 실측: saleList Limit 1000 동작(18,431 행)
    creditLimit: 100,       // apib 기본 100 · 1000 은 실측 없음 · 79 행이라 한 쪽
    detailBatch: 25,        // 상세 몇 건마다 Drive 저장 + 상태 저장(회차가 6 분에 죽어도 그만큼만 다시)
    budgetMs: 270000,       // 4 분 30 초 — 이 뒤로 새 호출을 시작하지 않는다
    deferAfterMs: 200000,   // 이 뒤에 429 를 맞으면 쉬지 않고 Next run(쉬다가 6 분을 넘기지 않게)
    sleepMs: 1200,          // Cin7 호출 간격(60 콜 / 60 초)
    tol: 0.01,              // sale 대조 허용 차
    maxPerCall: 500         // 창구 상한(invoices · credits 각각) — 넘으면 멈춘다(쪽 나누기는 안 만들었다 · complete:true 가 쪽과 안 맞는다)
  };
}


/* ═══════════════════════════════════════════════════════════
   1  전량 수집 — saleList → ref/customer/credits · 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function iloCollect() {
  ilo_banner_('iloCollect');
  var st = ilo_state_(), folder = ilo_folder_(st), started = Date.now(), cfg = ilo_cfg_();
  if (st.salesDone && st.creditsDone) { Logger.log('이미 다 모았다 — iloDetail 을 실행하라. 다시 모으려면 iloReset 먼저(폴더도 새로 — 옛 쪽 파일 위에 쌓이지 않게).'); return; }

  if (!st.salesDone) {
    var r = ilo_collectPages_(folder, st, started, {
      tag: 'sales', key: 'SaleList', idKey: 'SaleID', firstLimit: cfg.saleLimit,
      path: function (p, lim) { return 'saleList?Page=' + p + '&Limit=' + lim; }
    });
    if (!r.done) { ilo_save_state_(st); Logger.log('Next run — saleList 다음 쪽 ' + st.salesNext + ' 부터 · iloCollect 를 한 번 더 실행하라 · 폴더: ' + folder.getUrl()); return; }
    st.salesDone = true;
    Logger.log('⭐ saleList 끝 — 받은 행 ' + st.salesGot + ' · API Total ' + st.salesTotal + (st.salesGot === st.salesTotal ? ' · 같다' : ' ⚠️ 다르다 — iloDetail 이 고유 SaleID 로 다시 세고 모자라면 멈춘다'));
    ilo_save_state_(st);
  }
  if (!st.creditsDone) {
    var c = ilo_collectPages_(folder, st, started, {
      tag: 'credits', key: 'CustomerCredits', idKey: 'CreditID', firstLimit: cfg.creditLimit,
      path: function (p, lim) { return 'ref/customer/credits?Page=' + p + '&Limit=' + lim; }
    });
    if (!c.done) { ilo_save_state_(st); Logger.log('Next run — ref/customer/credits 다음 쪽 ' + st.creditsNext + ' 부터 · iloCollect 를 한 번 더 실행하라 · 폴더: ' + folder.getUrl()); return; }
    st.creditsDone = true;
    Logger.log('⭐ ref/customer/credits 끝 — 받은 행 ' + st.creditsGot + ' · API Total ' + (st.creditsTotal === null || st.creditsTotal === undefined ? '(응답에 없음 · 끝 = 받은 행 < Limit)' : st.creditsTotal));
    ilo_save_state_(st);
  }
  Logger.log('⭐ 수집 끝 — 다음은 iloDetail · 폴더: ' + folder.getUrl());
}

// 쪽 순회 한 갈래 — 쪽마다 파일(tag-pNNNN.json) · 4 분 30 초에서 새 쪽을 시작하지 않는다 · 끝 판단은 Total 이 아니라 받은 행 수 < Limit
// 첫 쪽에서 Limit 이 안 먹으면(받은 행 < Limit 인데 Total 이 더 크다) 받은 행 수를 Limit 으로 처음부터 · 같은 첫 행이 되풀이되면 멈춘다(Page 가 안 먹는 엔드포인트)
function ilo_collectPages_(folder, st, started, o) {
  var cfg = ilo_cfg_(), pageProp = o.tag + 'Next', limitProp = o.tag + 'Limit', totalProp = o.tag + 'Total', gotProp = o.tag + 'Got', firstProp = o.tag + 'FirstId';
  var page = st[pageProp] || 1, limit = st[limitProp] || o.firstLimit, done = false;
  while (Date.now() - started < cfg.budgetMs) {
    var x = ilo_need_(o.path(page, limit));
    var items = x.data[o.key] || [];
    if (st[totalProp] === undefined || st[totalProp] === null) st[totalProp] = (x.data.Total === undefined ? null : x.data.Total);
    if (page === 1 && !st[limitProp]) {
      if (items.length > 0 && items.length < limit && (x.data.Total || 0) > items.length) {
        Logger.log('   ' + o.tag + ': Limit=' + limit + ' 이 안 먹는다(받은 ' + items.length + ' · Total ' + x.data.Total + ') — Limit ' + items.length + ' 로 다시');
        limit = items.length; st[limitProp] = limit; continue;
      }
      st[limitProp] = limit;
    }
    var firstId = items.length ? String(items[0][o.idKey] || JSON.stringify(items[0]).slice(0, 200)) : null;
    if (firstId !== null && firstId === st[firstProp]) throw new Error(o.tag + ' 쪽 ' + page + ' 의 첫 행이 앞 쪽과 같다 — Page 가 안 먹는다 · 원본을 보고 멈춤');
    st[firstProp] = firstId;
    if (items.length) ilo_save_(folder, o.tag + '-p' + ilo_pad_(page) + '.json', JSON.stringify(items));
    st[gotProp] = (st[gotProp] || 0) + items.length;
    Logger.log('   ' + o.tag + ' 쪽 ' + page + ' · ' + items.length + ' 행 · 누계 ' + st[gotProp] + (st[totalProp] === null ? '' : ' / Total ' + st[totalProp]));
    if (items.length < limit) { done = true; page++; break; }
    page++;
    st[pageProp] = page;             // 쪽 하나가 끝날 때마다(회차가 죽어도 이 쪽까지는 저장됐다)
    ilo_save_state_(st);
  }
  st[pageProp] = done ? null : page;
  return { done: done };
}


/* ═══════════════════════════════════════════════════════════
   2  후보 가르기 + 상세 — 이어 달리기
   ═══════════════════════════════════════════════════════════ */

function iloDetail() {
  ilo_banner_('iloDetail');
  var st = ilo_state_(), cfg = ilo_cfg_();
  if (!st.salesDone || !st.creditsDone) { Logger.log('수집이 안 끝났다 — iloCollect 를 끝까지(Next run 이 안 뜰 때까지) 먼저.'); return; }
  var folder = ilo_folder_(st), started = Date.now();

  if (!st.candDone) {
    var dd = ilo_dedupe_(ilo_readAll_(folder, 'sales-'), 'SaleID');
    if (st.salesTotal !== null && st.salesTotal !== undefined && dd.rows.length < st.salesTotal) {
      throw new Error('⛔ 멈춤 — saleList 고유 SaleID ' + dd.rows.length + ' < API Total ' + st.salesTotal + ' (수집이 짧게 끝났다 · 규칙 6) — iloReset 뒤 새 폴더로 iloCollect 부터');
    }
    var cand = ilo_candidates_(dd.rows);
    ilo_save_(folder, 'candidates.json', JSON.stringify(cand));
    st.candDone = true; st.candOpen = cand.open.length; st.candOverpay = cand.overpay.length; st.detailNext = 0; st.detailFiles = [];
    ilo_save_state_(st);
    Logger.log('후보: 열린 sale ' + cand.open.length + ' (손님 ' + ilo_uniq_(cand.open, 'CustomerID') + ' · 목록 기준 남은 합 ' + ilo_sumByCur_(cand.open, function (s) { return ilo_n_(s.SaleInvoicesTotalAmount) - ilo_n_(s.CombinedPaymentTotal); }) + ')' +
      ' · 오버페이 sale ' + cand.overpay.length + ' (' + ilo_sumByCur_(cand.overpay, function (s) { return ilo_n_(s.CombinedPaymentTotal) - ilo_n_(s.SaleInvoicesTotalAmount); }) + ')' +
      ' · 고유 SaleID ' + dd.rows.length + ' · 받은 행 ' + dd.raw + ' · Total ' + st.salesTotal);
  }

  var candJ = ilo_readJson_(folder, 'candidates.json');
  if (!candJ) throw new Error('candidates.json 이 없다 — iloReset 뒤 다시');
  var jobs = candJ.open.concat(candJ.overpay), i = st.detailNext || 0, batch = [], batchFrom = i, deferred = false;
  var flush = function (upto) {              // upto = 저장이 끝난 뒤의 다음 일 번호(0 기준) — 이 번호까지는 Drive 에 있다
    if (!batch.length) return;
    var name = 'detail-' + ilo_pad_(batchFrom + 1) + '-' + ilo_pad_(upto) + '.json';
    ilo_save_(folder, name, JSON.stringify(batch));
    st.detailFiles = (st.detailFiles || []).concat([name]); st.detailNext = upto; ilo_save_state_(st);
    Logger.log('   저장 ' + name + ' · ' + batch.length + ' 건 · 누계 ' + upto + ' / ' + jobs.length);
    batch = []; batchFrom = upto;
  };
  for (; i < jobs.length; i++) {
    if (Date.now() - started > cfg.budgetMs) break;
    var s = jobs[i], x = ilo_get_('sale?ID=' + s.SaleID + '&HideInventoryMovements=true', started);
    if (x.deferred) { deferred = true; break; }
    if (x.code !== 200 || !x.isJson) {
      x = ilo_get_('sale?ID=' + s.SaleID + '&HideInventoryMovements=true', started);   // 한 번 더
      if (x.deferred) { deferred = true; break; }
      if (x.code !== 200 || !x.isJson) { flush(i); throw new Error('⛔ 상세 실패 ' + ilo_show_(s.OrderNumber) + ' (' + s.SaleID + ') HTTP ' + x.code + (x.isJson ? '' : ' JSON 아님') + ' : ' + String(x.text).slice(0, 200) + ' — 이 건부터 다시(iloDetail 한 번 더)'); }
    }
    batch.push({ list: s, detail: x.data });
    if (batch.length >= cfg.detailBatch) flush(i + 1);
  }
  flush(i);
  if (i < jobs.length) { st.detailNext = i; ilo_save_state_(st); Logger.log('Next run — 상세 ' + (i + 1) + '/' + jobs.length + ' 부터' + (deferred ? '(429 를 늦게 맞아 쉬지 않고 넘긴다)' : '') + ' · iloDetail 을 한 번 더 실행하라 · 폴더: ' + folder.getUrl()); return; }
  st.detailNext = jobs.length; st.detailDone = true; ilo_save_state_(st);
  Logger.log('⭐ 상세 끝 — ' + jobs.length + ' 건 · 파일 ' + (st.detailFiles || []).length + ' · 다음은 iloBuild · 폴더: ' + folder.getUrl());
}

// 후보 가르기(순수) — 열린 것 · 크레딧으로 안 바뀐 오버페이 · 목록 기준 통계(Build 보고서의 「목록 기준」 칸)
function ilo_candidates_(S) {
  var n = ilo_n_, live = S.filter(function (s) { return !ilo_voided_(s); });
  var open = live.filter(function (s) { return n(s.SaleInvoicesTotalAmount) - n(s.CombinedPaymentTotal) > 0.005; });
  var over = live.filter(function (s) { return n(s.CombinedPaymentTotal) - n(s.SaleInvoicesTotalAmount) > 0.005; });
  var overCredited = over.filter(function (s) { return /CREDITED/i.test(ilo_str_(s.CombinedPaymentStatus)); });
  var overpay = over.filter(function (s) { return !/CREDITED/i.test(ilo_str_(s.CombinedPaymentStatus)); });
  var sortKey = function (a, b) { return ilo_str_(a.OrderNumber) < ilo_str_(b.OrderNumber) ? -1 : 1; };
  open.sort(sortKey); overpay.sort(sortKey);
  return {
    open: open, overpay: overpay,
    stats: {
      sales: S.length, voided: S.length - live.length,
      open: open.length, open_customers: ilo_uniq_(open, 'CustomerID'), open_by_cur: ilo_sumByCurObj_(open, function (s) { return n(s.SaleInvoicesTotalAmount) - n(s.CombinedPaymentTotal); }),
      open_blank_number: open.filter(function (s) { return !ilo_str_(s.InvoiceNumber); }).length,
      open_status_pairs: ilo_countBy_(open, function (s) { return ilo_show_(s.CombinedInvoiceStatus) + ' × ' + ilo_show_(s.CombinedPaymentStatus); }),
      overpay: overpay.length, overpay_customers: ilo_uniq_(overpay, 'CustomerID'), overpay_by_cur: ilo_sumByCurObj_(overpay, function (s) { return n(s.CombinedPaymentTotal) - n(s.SaleInvoicesTotalAmount); }),
      overpay_credited: overCredited.length, overpay_credited_by_cur: ilo_sumByCurObj_(overCredited, function (s) { return n(s.CombinedPaymentTotal) - n(s.SaleInvoicesTotalAmount); }),
      overpay_status: ilo_countBy_(overpay, function (s) { return ilo_show_(s.CombinedPaymentStatus); })
    }
  };
}


/* ═══════════════════════════════════════════════════════════
   3  창구 입력 p 만들기 — Cin7 호출 0 · 쓰기 0
   ═══════════════════════════════════════════════════════════ */

function iloBuild() {
  ilo_banner_('iloBuild');
  var st = ilo_state_(), cfg = ilo_cfg_();
  if (!st.detailDone) { Logger.log('상세가 안 끝났다 — iloDetail 을 끝까지 먼저.'); return; }
  var folder = ilo_folder_(st);
  var cand = ilo_readJson_(folder, 'candidates.json');
  var details = ilo_readAll_(folder, 'detail-').rows;
  var credits = ilo_readAll_(folder, 'credits-').rows;
  var res = ilo_build_(cand, details, credits, cfg.asOf || ilo_today_(), cfg);
  var text = JSON.stringify({ p: res.p, summary: res.summary });
  var stamp = ilo_stamp_(), name = 'build-' + stamp + '.json';
  ilo_save_(folder, name, text);
  folder.createFile('report-build-' + stamp + '.txt', res.report, MimeType.PLAIN_TEXT);
  st.buildFile = name; st.buildMd5 = ilo_md5_(text); st.buildMismatch = res.summary.mismatch.length; st.buildBlocked = res.summary.blocked;
  st.dryMd5 = null; st.dryAt = null; st.dryRejected = null;      // 새 Build 면 Dry 부터 다시
  ilo_save_state_(st);
  Logger.log(res.report);
  Logger.log('⭐ ' + name + ' · md5 ' + st.buildMd5 + ' · 인보이스 ' + res.p.invoices.length + ' · 받아 둔 돈 줄 ' + res.p.credits.length + ' · 어긋난 sale ' + st.buildMismatch + (st.buildBlocked ? ' ⛔ Apply 막힘(Dry 는 된다)' : '') + ' · 다음은 iloDry · 폴더: ' + folder.getUrl());
}

// 셈 본체(순수 — 시험 장치가 직접 부른다) → { p, summary, report }
function ilo_build_(cand, details, credits, asOf, cfg) {
  var n = ilo_n_, r2 = ilo_r2_, tol = cfg.tol, out = [], P = function (s) { out.push(s); };
  var byId = {}; details.forEach(function (d) { if (d && d.list && d.list.SaleID) byId[d.list.SaleID] = d; });
  var invoices = [], creditsOut = [], mismatch = [], notes = [], roundedInv = 0, roundedCr = 0, custDiff = 0, blankNumber = 0, missingDetail = [], termBlank = 0, dueBlank = 0, negInv = 0;

  // ── 이월 인보이스(열린 sale) + sale 대조 ──
  cand.open.forEach(function (s) {
    var d = byId[s.SaleID];
    if (!d) { missingDetail.push(s); return; }
    var det = d.detail, invs = ilo_arr_(det.Invoices !== undefined ? det.Invoices : det.Invoice);
    var custId = ilo_str_(det.CustomerID) || ilo_str_(s.CustomerID), cur = ilo_str_(det.CustomerCurrency) || ilo_str_(s.CustomerCurrency);
    if (ilo_str_(det.CustomerID) && ilo_str_(s.CustomerID) && ilo_str_(det.CustomerID) !== ilo_str_(s.CustomerID)) custDiff++;
    var live = invs.filter(function (v) { var u = ilo_str_(v.Status).toUpperCase(); return u !== 'VOIDED' && u !== 'DRAFT'; });
    var sumSigned = 0, lines = [], negs = 0;
    live.forEach(function (v) {
      var total = n(v.Total), paid = n(v.Paid), rem = total - paid;
      sumSigned += rem;
      if (rem < -0.005) { negInv++; negs++; }      // 한 sale 안에서 넘게 받은 인보이스가 열린 인보이스를 상계한다 — 실을 수 없다(목록 합은 맞아도 어긋남으로)
      if (rem > 0.005) {
        var tb = n(v.TotalBeforeTax), tx = n(v.Tax);
        if (Math.abs(total - r2(total)) > 0.0001 || Math.abs(paid - r2(paid)) > 0.0001 || Math.abs(tx - r2(tx)) > 0.0001) roundedInv++;
        if (!ilo_str_(v.InvoiceNumber)) blankNumber++;
        if (!ilo_str_(det.Terms)) termBlank++;
        if (!ilo_d_(v.InvoiceDueDate)) dueBlank++;
        lines.push({
          legacy_sale_id: ilo_str_(s.SaleID), legacy_invoice_id: ilo_str_(v.TaskID), invoice_number: ilo_str_(v.InvoiceNumber),
          cin7_customer_id: custId, issued_on: ilo_d_(v.InvoiceDate) || null, due_on: ilo_d_(v.InvoiceDueDate) || null,
          payment_term_name: ilo_str_(det.Terms) || null, currency: cur,
          total_before_tax: r2(tb), tax: r2(tx), total: r2(total), prior_settled: r2(paid),
          _order: ilo_str_(s.OrderNumber), _customer: ilo_str_(s.Customer)   // 보고용 — 창구는 모르는 키를 무시한다(x->>'…' 로만 읽는다)
        });
      }
    });
    var listDiff = n(s.SaleInvoicesTotalAmount) - n(s.CombinedPaymentTotal);
    if (Math.abs(sumSigned - listDiff) > tol || !lines.length || negs > 0) {
      var cns = ilo_arr_(det.CreditNotes !== undefined ? det.CreditNotes : det.CreditNote).filter(function (c) { return ilo_str_(c.Status).toUpperCase() !== 'VOIDED'; });
      var cnTotal = cns.reduce(function (a, c) { return a + n(c.Total); }, 0), cnRefund = cns.reduce(function (a, c) { return a + ilo_sum_(ilo_arr_(c.Refunds), 'Amount'); }, 0);
      var cnNet = cnTotal - cnRefund;
      mismatch.push({ order: ilo_str_(s.OrderNumber), customer: ilo_str_(s.Customer), sale_id: s.SaleID, list_remaining: r2(listDiff), detail_remaining: r2(sumSigned), diff: r2(sumSigned - listDiff),
        invoices: live.map(function (v) { return ilo_show_(v.InvoiceNumber) + ' ' + ilo_show_(v.Status) + ' Total ' + ilo_m_(v.Total) + ' Paid ' + ilo_m_(v.Paid); }).join(' | ') + (invs.length > live.length ? ' (+ VOIDED/DRAFT ' + (invs.length - live.length) + ')' : ''),
        credit_notes: cns.map(function (c) { return ilo_show_(c.CreditNoteNumber) + ' ' + ilo_show_(c.Status) + ' Total ' + ilo_m_(c.Total) + ' Refunds ' + ilo_m_(ilo_sum_(ilo_arr_(c.Refunds), 'Amount')); }).join(' | '),
        cn_explains: cns.length > 0 && Math.abs((sumSigned - cnNet) - listDiff) <= tol, lines_loaded: lines.length, negative_invoices: negs });
    }
    invoices = invoices.concat(lines);
  });

  // ── 받아 둔 돈 ② 오버페이(크레딧으로 안 바뀐 것) ──
  cand.overpay.forEach(function (s) {
    var d = byId[s.SaleID];
    if (!d) { missingDetail.push(s); return; }
    var det = d.detail, invs = ilo_arr_(det.Invoices !== undefined ? det.Invoices : det.Invoice);
    var live = invs.filter(function (v) { var u = ilo_str_(v.Status).toUpperCase(); return u !== 'VOIDED' && u !== 'DRAFT'; });
    var sumSigned = live.reduce(function (a, v) { return a + n(v.Total) - n(v.Paid); }, 0);
    var listDiff = n(s.SaleInvoicesTotalAmount) - n(s.CombinedPaymentTotal), amt = r2(-listDiff);
    if (Math.abs(sumSigned - listDiff) > tol && live.length) {       // 인보이스 전 선결제(인보이스 0 장)는 상세로 대조할 것이 없다 — 목록 값을 그대로
      mismatch.push({ order: ilo_str_(s.OrderNumber), customer: ilo_str_(s.Customer), sale_id: s.SaleID, list_remaining: r2(listDiff), detail_remaining: r2(sumSigned), diff: r2(sumSigned - listDiff),
        invoices: live.map(function (v) { return ilo_show_(v.InvoiceNumber) + ' ' + ilo_show_(v.Status) + ' Total ' + ilo_m_(v.Total) + ' Paid ' + ilo_m_(v.Paid); }).join(' | '), credit_notes: '', cn_explains: false, lines_loaded: 0, overpay: true });
    }
    if (Math.abs(amt - (-listDiff)) > 0.0001) roundedCr++;
    creditsOut.push({ cin7_customer_id: ilo_str_(det.CustomerID) || ilo_str_(s.CustomerID), currency: ilo_str_(det.CustomerCurrency) || ilo_str_(s.CustomerCurrency), amount: amt, source: 'overpay',
      reference: ilo_str_(s.OrderNumber) + ' · invoice ' + (live.map(function (v) { return ilo_str_(v.InvoiceNumber); }).filter(Boolean).join('/') || '-') + ' · balance credited', _customer: ilo_str_(s.Customer) });
  });

  // ── 받아 둔 돈 ① 손님 크레딧(RemainingAmount > 0) ──
  var credRows = credits.filter(function (c) { return n(c.RemainingAmount) > 0.005; });
  credRows.forEach(function (c) {
    var amt = r2(n(c.RemainingAmount));
    if (Math.abs(amt - n(c.RemainingAmount)) > 0.0001) roundedCr++;
    creditsOut.push({ cin7_customer_id: ilo_str_(c.CustomerID), currency: ilo_str_(c.Currency), amount: amt, source: 'credit',
      reference: (ilo_text_(c.Description) || 'customer credit') + (ilo_d_(c.Date) ? ' (' + ilo_d_(c.Date) + ')' : ''), _customer: ilo_str_(c.CustomerName) });
  });

  var p = { as_of: asOf, complete: true, invoices: invoices, credits: creditsOut };
  var sumInv = ilo_groupCur_(invoices, function (v) { return { count: 1, total: v.total, prior_settled: v.prior_settled, remaining: r2(v.total - v.prior_settled) }; });
  var sumCr1 = ilo_groupCur_(creditsOut.filter(function (c) { return c.source === 'credit'; }), function (c) { return { count: 1, amount: c.amount }; });
  var sumCr2 = ilo_groupCur_(creditsOut.filter(function (c) { return c.source === 'overpay'; }), function (c) { return { count: 1, amount: c.amount }; });
  var sumCr = ilo_groupCur_(creditsOut, function (c) { return { count: 1, amount: c.amount }; });
  var tooMany = invoices.length > cfg.maxPerCall || creditsOut.length > cfg.maxPerCall;
  var summary = {
    as_of: asOf, built_at: new Date().toISOString(), stats: cand.stats,
    invoices: { count: invoices.length, customers: ilo_uniq_(invoices, 'cin7_customer_id'), sales: ilo_uniq_(invoices, 'legacy_sale_id'), by_currency: sumInv,
                blank_number: blankNumber, term_blank: termBlank, due_blank: dueBlank, rounded: roundedInv, customer_id_differs: custDiff, negative_invoices: negInv },
    credits: { count: creditsOut.length, customers: ilo_uniq_(creditsOut, 'cin7_customer_id'), by_currency: sumCr, credit_rows: credRows.length, credit_by_currency: sumCr1, overpay_rows: cand.overpay.length, overpay_by_currency: sumCr2, rounded: roundedCr },
    mismatch: mismatch, missing_detail: missingDetail.map(function (s) { return ilo_str_(s.OrderNumber); }),
    blocked: mismatch.length > 0 || missingDetail.length > 0 || tooMany, too_many: tooMany
  };

  // ── 보고서 ──
  P('=== ImsLoadOpening build ' + summary.built_at + ' · as_of ' + asOf + ' ===');
  P('');
  P('0. 원천');
  P('   saleList 고유 sale ' + cand.stats.sales + ' · VOIDED ' + cand.stats.voided + ' · 열린 sale ' + cand.stats.open + '(손님 ' + cand.stats.open_customers + ') · 오버페이 sale ' + cand.stats.overpay + '(손님 ' + cand.stats.overpay_customers + ') · 오버페이인데 CREDITED(① 로 간 것) ' + cand.stats.overpay_credited);
  P('   상세 ' + details.length + ' 건 · ref/customer/credits ' + credits.length + ' 행(RemainingAmount > 0 ' + credRows.length + ')');
  P('');
  P('1. ⭐ sale 대조 — Σ(상세 인보이스 Total − Paid · VOIDED · DRAFT 제외) = 목록 SaleInvoicesTotalAmount − CombinedPaymentTotal (' + tol + ' 안)');
  if (!mismatch.length) P('   어긋난 sale 0 — 통과');
  else {
    P('   ⛔ 어긋난 sale ' + mismatch.length + ' — Apply 를 막는다(맞으면 iloAllowMismatch 를 한 번 실행한 뒤 iloApply · 한 번만 통과)');
    mismatch.forEach(function (m) {
      P('   ' + ilo_padR_(m.order, 10) + ' ' + ilo_padR_(m.customer, 32) + ' 목록 남은 ' + ilo_padL_(ilo_m_(m.list_remaining), 11) + ' · 상세 Σ ' + ilo_padL_(ilo_m_(m.detail_remaining), 11) + ' · 차 ' + ilo_padL_(ilo_m_(m.diff), 10) + (m.overpay ? ' · 오버페이' : ' · 실린 줄 ' + m.lines_loaded) + (m.negative_invoices ? ' · ⚠️ Paid > Total 인 인보이스 ' + m.negative_invoices + '(열린 인보이스를 상계 — 실린 남은 금액이 sale 의 남은 금액보다 크다)' : ''));
      P('       인보이스: ' + (m.invoices || '(없음)'));
      if (m.credit_notes) P('       크레딧 노트: ' + m.credit_notes + (m.cn_explains ? '  ⭐ 차이 = Σ크레딧 노트 − Σ환불 (크레딧 노트가 Paid 에 안 들어간 꼴 — 짐작 · Caleb 판단)' : ''));
    });
  }
  if (missingDetail.length) P('   ⛔ 상세가 없는 후보 ' + missingDetail.length + ' : ' + summary.missing_detail.join(', ') + ' — iloDetail 을 다시');
  if (tooMany) P('   ⛔ 창구 상한 ' + cfg.maxPerCall + ' 을 넘는다(인보이스 ' + invoices.length + ' · 받아 둔 돈 ' + creditsOut.length + ') — 쪽 나누기는 없다 · 대화 Claude 와 상의');
  P('');
  P('2. 이월 인보이스 — ' + invoices.length + ' 장 · sale ' + summary.invoices.sales + ' · 손님 ' + summary.invoices.customers);
  P('   통화   장수   Σ Total         Σ 이전에 받음   Σ 남은 금액      | 목록 기준 Σ(SaleInvoicesTotalAmount − CombinedPaymentTotal)');
  Object.keys(sumInv).sort().forEach(function (k) { var g = sumInv[k]; P('   ' + ilo_padR_(k, 6) + ' ' + ilo_padL_(String(g.count), 5) + ' ' + ilo_padL_(ilo_m_(g.total), 14) + ' ' + ilo_padL_(ilo_m_(g.prior_settled), 14) + ' ' + ilo_padL_(ilo_m_(g.remaining), 14) + '    | ' + ilo_m_(cand.stats.open_by_cur[k])); });
  P('   번호 빈 인보이스 ' + blankNumber + '(창구가 number_invalid 로 거부) · Terms 빈 것 ' + termBlank + ' · 기한 빈 것 ' + dueBlank + '(결제조건 net_days 로 채워진다 · 둘 다 없으면 due_unknown) · 소수 셋째 자리 반올림 ' + roundedInv + ' · 목록 ≠ 상세 CustomerID ' + custDiff + ' · Paid > Total 인 인보이스 ' + negInv);
  P('');
  P('3. 받아 둔 돈 — 줄 ' + creditsOut.length + ' · 손님(매장) ' + summary.credits.customers + ' (창구가 청구처 · 통화로 묶는다)');
  P('   ① 손님 크레딧(RemainingAmount > 0) ' + credRows.length + ' 행: ' + ilo_curText_(sumCr1));
  P('   ② 오버페이(balance credited · PREPAID 포함) ' + cand.overpay.length + ' sale: ' + ilo_curText_(sumCr2) + '   (목록 기준 ' + ilo_curText_(cand.stats.overpay_by_cur, true) + ')');
  P('   합: ' + ilo_curText_(sumCr) + ' · 소수 셋째 자리 반올림 ' + roundedCr);
  P('   큰 줄(≥ 1000 · 창구 large[] 와 같은 기준):');
  var big = creditsOut.filter(function (c) { return c.amount >= 1000; }).sort(function (a, b) { return b.amount - a.amount; });
  if (!big.length) P('      (없음)');
  big.forEach(function (c) { P('      ' + ilo_padR_(c._customer, 32) + ' ' + c.currency + ' ' + ilo_padL_(ilo_m_(c.amount), 11) + ' · ' + c.source + ' · ' + c.reference); });
  P('');
  P(ilo_calebTable_(summary));
  return { p: p, summary: summary, report: out.join('\n') };
}

// ⭐ Caleb 대조표 — QuickBooks A/R Aging(10-31) · 손님 크레딧과 맞춰 볼 칸
function ilo_calebTable_(summary, dryRet) {
  var out = [], P = function (s) { out.push(s); };
  var inv = dryRet ? ilo_byCurArr_(dryRet.invoices.by_currency, 'remaining', 'count') : summary.invoices.by_currency;
  var cr = dryRet ? ilo_byCurArr_(dryRet.credits.by_currency, 'amount', 'count') : summary.credits.by_currency;
  P('════ Caleb 대조표 — QuickBooks A/R Aging Summary(As of 2026-10-31 · 통화별) 와 나란히 · 「QBO」 칸을 채우고 차이를 본다 ════');
  P('   (' + (dryRet ? '창구 Dry 가 받아들인 것 기준' : 'Build 기준 — Dry 뒤에는 Dry 보고서의 표를 쓴다') + ' · 컷오버 날 Cin7 입력이 10-31 마감 뒤 없다는 전제(Caleb) · 어긋나면 볼 곳은 아래)');
  P('');
  P('   항목                              통화   IMS(이월)            QBO(10-31)         차이');
  Object.keys(inv).sort().forEach(function (k) {
    P('   미수 인보이스 Σ 남은 금액          ' + ilo_padR_(k, 6) + ' ' + ilo_padL_(ilo_m_(inv[k].remaining !== undefined ? inv[k].remaining : inv[k].amount), 14) + '       ______________     ________');
    P('   미수 인보이스 장 수                ' + ilo_padR_(k, 6) + ' ' + ilo_padL_(String(inv[k].count), 14) + '       ______________     ________');
  });
  P('   미수 손님 수(Cin7 손님 = 매장)     -      ' + ilo_padL_(String(summary.invoices.customers), 14) + '       ______________     ________   (QBO 는 청구처 수일 수 있다 — 매장이 여럿인 손님은 IMS 가 더 많다)');
  Object.keys(cr).sort().forEach(function (k) {
    P('   받아 둔 돈(크레딧 + 오버페이)     ' + ilo_padR_(k, 6) + ' ' + ilo_padL_(ilo_m_(cr[k].amount), 14) + '       ______________     ________   (QBO: Unapplied payments / Customer credits)');
  });
  P('');
  P('   차이가 나면 볼 곳(짐작 — 확인 안 함):');
  P('     · Cin7 → QBO 동기화가 안 된 몫(QBO 에 없는 인보이스 · 결제 — Cin7 의 Integration 로그) · QBO 에만 손으로 넣은 결제 · 환율(USD 인보이스를 QBO 가 CAD 로 환산한 금액)');
  P('     · 크레딧 노트(Cin7 에선 인보이스에서 빠지고 QBO 에선 별도 Credit Memo) · 위 1 의 어긋난 sale · Royals Beauty Supply SO-12562 2,278.13(회계 확인 중 · 잘못이면 Cin7 결제를 지우고 Collect 부터 다시)');
  P('     · IMS 쪽: Dry 의 rejects(customer_unresolved 등) 가 빠진 만큼 IMS 합이 작다 — Dry 보고서 맨 위');
  return out.join('\n');
}


/* ═══════════════════════════════════════════════════════════
   4  Dry — 창구에 p 를 보내 판단만 받는다(쓰기 0)
   ═══════════════════════════════════════════════════════════ */

function iloDry() {
  ilo_banner_('iloDry');
  var st = ilo_state_(), b = ilo_loadBuild_(st);
  var t0 = Date.now(), ret = ilo_rpc_('so_opening_load', { p: b.p, p_dry: true }), ms = Date.now() - t0;
  if (ret.dry !== true) throw new Error('창구가 dry:true 를 돌려주지 않았다 — ' + JSON.stringify(ret).slice(0, 300));
  var stamp = ilo_stamp_();
  var text = ilo_dryReport_('dry', b, ret, ms, st);
  b.folder.createFile('report-dry-' + stamp + '.txt', text, MimeType.PLAIN_TEXT);
  st.dryMd5 = st.buildMd5; st.dryAt = new Date().toISOString(); st.dryRejected = (ret.invoices.rejected || 0) + (ret.credits.rejected || 0);
  ilo_save_state_(st);
  Logger.log(text);
  Logger.log('⭐ Dry 끝 · ' + ms + ' ms(왕복) · 창구 ' + ret.ms + ' ms · 거부 ' + st.dryRejected + ' · 보고서 report-dry-' + stamp + '.txt · 숫자를 대화 Claude 와 맞춘 뒤 iloApply · 폴더: ' + b.folder.getUrl());
}

function ilo_loadBuild_(st) {
  if (!st.buildFile) throw new Error('Build 파일이 없다 — iloBuild 먼저');
  var folder = ilo_folder_(st), raw = ilo_readText_(folder, st.buildFile);
  if (raw === null) throw new Error('Drive 에 ' + st.buildFile + ' 이 없다 — iloBuild 다시');
  var md5 = ilo_md5_(raw);
  if (md5 !== st.buildMd5) throw new Error('⛔ ' + st.buildFile + ' 의 md5 가 Build 때와 다르다(' + md5 + ' ≠ ' + st.buildMd5 + ') — 파일이 바뀌었다 · iloBuild 다시');
  var j = JSON.parse(raw);
  return { folder: folder, p: j.p, summary: j.summary, md5: md5, name: st.buildFile };
}

function ilo_dryReport_(mode, b, ret, ms, st) {
  var out = [], P = function (s) { out.push(s); }, inv = ret.invoices, cr = ret.credits;
  P('=== ImsLoadOpening ' + mode + ' ' + new Date().toISOString() + ' · ' + b.name + ' · md5 ' + b.md5 + ' · 창구 ' + ret.ms + ' ms · 왕복 ' + ms + ' ms · as_of ' + ret.as_of + ' · 계정 ' + ret.account.code + ' ' + ret.account.name + ' ===');
  P('');
  P('⭐ 맨 위 — 거부 · 못 찾음 · 큰 돈');
  P('   인보이스 거부 ' + inv.rejected + ' / ' + inv['in'] + ' · 손님 못 찾음 ' + inv.customer_unresolved + ' · 결제조건 못 찾음 ' + inv.term_unresolved + ' · 기한 모름 ' + inv.due_unknown + ' · TotalBeforeTax 어긋남 ' + inv.before_tax_adjusted.count + '(|Σ| ' + ilo_m_(inv.before_tax_adjusted.sum_abs) + ')');
  ilo_arr_(inv.rejects).forEach(function (r) { P('      #' + r.seq + ' ' + ilo_padR_(ilo_show_(r.invoice_number), 8) + ' ' + ilo_padR_(ilo_show_(r.customer_name), 32) + ' ' + r.reason + ' · legacy ' + ilo_show_(r.legacy_invoice_id) + ' · cin7 손님 ' + ilo_show_(r.cin7_customer_id)); });
  P('   받아 둔 돈 거부 ' + cr.rejected + ' / ' + cr.rows_in + ' 줄 · 손님 못 찾음 ' + cr.customer_unresolved + ' · 브랜치 못 찾음 ' + cr.branch_unresolved + ' · 묶음 ' + cr.groups);
  ilo_arr_(cr.rejects).forEach(function (r) { P('      ' + (r.seq === null || r.seq === undefined ? '(묶음)' : '#' + r.seq) + ' ' + ilo_padR_(ilo_show_(r.customer_name), 32) + ' ' + ilo_show_(r.currency_code) + ' ' + ilo_padL_(ilo_m_(r.amount), 11) + ' ' + r.reason + (r.cin7_customer_id ? ' · cin7 손님 ' + r.cin7_customer_id : '')); });
  P('   큰 돈(≥ 1000) ' + ilo_arr_(cr.large).length);
  ilo_arr_(cr.large).forEach(function (r) { P('      ' + ilo_padR_(ilo_show_(r.customer_name), 32) + ' ' + ilo_show_(r.currency_code) + ' ' + ilo_padL_(ilo_m_(r.amount), 11) + ' · ' + ilo_show_(r.note)); });
  if (b.summary.mismatch.length) P('   ⛔ Build 의 어긋난 sale ' + b.summary.mismatch.length + ' (report-build 1 절) — Apply 가 막힌다');
  P('');
  P('1. 창구 셈 — 인보이스: 넣음 ' + inv.inserted + ' · 바뀜 ' + inv.updated + ' · 같음 ' + inv.same + ' · 거부 ' + inv.rejected + '   받아 둔 돈: 묶음 ' + cr.groups + ' · 넣음 ' + cr.inserted + ' · 바뀜 ' + cr.updated + ' · 같음 ' + cr.same + ' · 거부 ' + cr.rejected);
  P('   통화   장수   Σ Total         Σ 이전에 받음   Σ 남은 금액      | Build 장수 · Σ 남은 금액(받아들인 것만 다르면 거부 몫)');
  ilo_arr_(inv.by_currency).forEach(function (g) { var bb = b.summary.invoices.by_currency[g.currency_code] || { count: 0, remaining: 0 }; P('   ' + ilo_padR_(g.currency_code, 6) + ' ' + ilo_padL_(String(g.count), 5) + ' ' + ilo_padL_(ilo_m_(g.total), 14) + ' ' + ilo_padL_(ilo_m_(g.prior_settled), 14) + ' ' + ilo_padL_(ilo_m_(g.remaining), 14) + '    | ' + bb.count + ' · ' + ilo_m_(bb.remaining) + (Math.abs(ilo_n_(g.remaining) - ilo_n_(bb.remaining)) > 0.005 ? '  ⚠️ 다르다' : '  같다')); });
  P('   받아 둔 돈 통화별(묶음 뒤): ' + ilo_arr_(cr.by_currency).map(function (g) { var bb = b.summary.credits.by_currency[g.currency_code] || { amount: 0 }; return g.currency_code + ' ' + g.count + ' 손님 ' + ilo_m_(g.amount) + ' | Build ' + ilo_m_(bb.amount) + (Math.abs(ilo_n_(g.amount) - ilo_n_(bb.amount)) > 0.005 ? ' ⚠️ 다르다' : ' 같다'); }).join(' · '));
  if (inv.existing_not_in_input) P('   입력에 없는 기존 이월 인보이스 ' + inv.existing_not_in_input.count + (inv.existing_not_in_input.count ? ' : ' + ilo_arr_(inv.existing_not_in_input.invoice_numbers).join(', ') : ''));
  if (cr.existing_not_in_input) P('   입력에 없는 기존 이월 결제 ' + cr.existing_not_in_input.count + (cr.existing_not_in_input.count ? ' : ' + ilo_arr_(cr.existing_not_in_input.customers).map(function (c) { return c.customer_name + ' ' + c.currency_code + ' ' + ilo_m_(c.amount); }).join(' · ') : ''));
  P('');
  P('2. 창구 반환 원문');
  P(JSON.stringify(ret, null, 1));
  P('');
  P(ilo_calebTable_(b.summary, ret));
  return out.join('\n');
}


/* ═══════════════════════════════════════════════════════════
   5  Apply — 같은 p · 직전 Dry 로 거부 0 확인 · complete:true
   ═══════════════════════════════════════════════════════════ */

function iloApply() {
  ilo_banner_('iloApply');
  var st = ilo_state_(), b = ilo_loadBuild_(st), why = [];
  if (!st.dryMd5) throw new Error('⛔ 이 Build 로 Dry 를 아직 안 돌렸다 — iloDry 먼저');
  if (st.dryMd5 !== b.md5) throw new Error('⛔ Dry 때의 p(md5 ' + st.dryMd5 + ')와 지금의 p(' + b.md5 + ')가 다르다 — iloDry 다시');
  if (b.summary.too_many) throw new Error('⛔ 창구 상한을 넘는다 — report-build 1 절');
  if (b.summary.missing_detail.length) throw new Error('⛔ 상세가 없는 후보가 있다 — iloDetail 다시');
  if (b.summary.mismatch.length) {
    if (st.allowMismatch) { st.allowMismatch = false; ilo_save_state_(st); Logger.log('⚠️ 어긋난 sale ' + b.summary.mismatch.length + ' 을 한 번 통과(iloAllowMismatch) — 표지를 껐다'); }
    else throw new Error('⛔ 멈춤 — Build 의 어긋난 sale ' + b.summary.mismatch.length + '(report-build 1 절) · 맞으면 iloAllowMismatch 를 한 번 실행한 뒤 iloApply(한 번만 통과)');
  }
  if (b.p.complete !== true) throw new Error('p.complete 가 true 가 아니다 — iloBuild 다시');
  if (st.applyAt) Logger.log('⚠️ 이미 Apply 한 적 있다(' + st.applyAt + ' · md5 ' + st.applyMd5 + ') — 창구가 멱등이라 같은 p 는 same · 바뀐 줄만 update 된다');

  // 직전 Dry — 그 사이 DB 가 바뀌었을 수 있다(cron · 동료)
  var pre = ilo_rpc_('so_opening_load', { p: b.p, p_dry: true });
  var rej = (pre.invoices.rejected || 0) + (pre.credits.rejected || 0);
  if (rej > 0) {
    if (st.allowRejects) { st.allowRejects = false; ilo_save_state_(st); Logger.log('⚠️ 거부 ' + rej + ' 을 한 번 통과(iloAllowRejects) — 표지를 껐다 · 거부된 줄은 들어가지 않는다'); }
    else { var t = ilo_dryReport_('apply-precheck', b, pre, 0, st); b.folder.createFile('report-apply-blocked-' + ilo_stamp_() + '.txt', t, MimeType.PLAIN_TEXT); Logger.log(t); throw new Error('⛔ 멈춤 — 직전 Dry 에 거부 ' + rej + ' (인보이스 ' + pre.invoices.rejected + ' · 받아 둔 돈 ' + pre.credits.rejected + ') · 보고서 맨 위를 보고 고치거나(Cin7 · IMS 손님) 맞으면 iloAllowRejects 를 한 번 실행한 뒤 iloApply'); }
  }
  var t0 = Date.now(), ret = ilo_rpc_('so_opening_load', { p: b.p, p_dry: false }), ms = Date.now() - t0;
  if (ret.dry !== false) throw new Error('창구가 dry:false 를 돌려주지 않았다 — ' + JSON.stringify(ret).slice(0, 300));
  var stamp = ilo_stamp_(), text = ilo_dryReport_('apply', b, ret, ms, st), extra = [];
  ['inserted', 'updated', 'same', 'rejected'].forEach(function (k) { if (ret.invoices[k] !== pre.invoices[k]) extra.push('인보이스 ' + k + ' 직전 Dry ' + pre.invoices[k] + ' → Apply ' + ret.invoices[k]); if (ret.credits[k] !== pre.credits[k]) extra.push('받아 둔 돈 ' + k + ' 직전 Dry ' + pre.credits[k] + ' → Apply ' + ret.credits[k]); });
  if (extra.length) text += '\n\n⚠️ 직전 Dry 와 Apply 의 셈이 다르다(그 사이 DB 가 바뀌었다): ' + extra.join(' · ');
  var notIn = (ret.invoices.existing_not_in_input ? ret.invoices.existing_not_in_input.count : 0) + (ret.credits.existing_not_in_input ? ret.credits.existing_not_in_input.count : 0);
  if (notIn > 0) text += '\n\n⚠️ 입력에 없는 기존 이월 줄 ' + notIn + ' — 창구는 지우지 않는다 · 옛 Build 로 넣은 것이면 Caleb 이 판단(1 절 목록)';
  b.folder.createFile('report-apply-' + stamp + '.txt', text, MimeType.PLAIN_TEXT);
  st.applyAt = new Date().toISOString(); st.applyMd5 = b.md5; ilo_save_state_(st);
  Logger.log(text);
  Logger.log('⭐ Apply 끝 · 창구 ' + ret.ms + ' ms · 인보이스 넣음 ' + ret.invoices.inserted + ' 바뀜 ' + ret.invoices.updated + ' 같음 ' + ret.invoices.same + ' 거부 ' + ret.invoices.rejected + ' · 받아 둔 돈 넣음 ' + ret.credits.inserted + ' 바뀜 ' + ret.credits.updated + ' 같음 ' + ret.credits.same + ' 거부 ' + ret.credits.rejected + ' · 다음은 iloVerify · 폴더: ' + b.folder.getUrl());
}


/* ═══════════════════════════════════════════════════════════
   6  Verify — 읽기만 · IMS 표 ↔ Build 요약
   ═══════════════════════════════════════════════════════════ */

function iloVerify() {
  ilo_banner_('iloVerify');
  var st = ilo_state_(), b = ilo_loadBuild_(st), out = [], P = function (s) { out.push(s); }, n = ilo_n_;
  var invs = ilo_restAll_('so_invoice?kind=eq.opening&select=id,invoice_number,status,bill_to_customer_id,bill_to_name,store_customer_id,currency_code,total,prior_settled,legacy_invoice_id,legacy_sale_id,issued_on,due_on&order=invoice_number');
  var pays = ilo_restAll_('so_payment?method=eq.opening&select=id,customer_id,currency_code,amount,status,paid_on,warehouse_name,note&order=created_at');
  var issued = invs.filter(function (v) { return v.status === 'issued'; }), active = pays.filter(function (p) { return p.status === 'active'; });
  var invCur = ilo_groupCur_(issued.map(function (v) { return { currency: v.currency_code, total: n(v.total), prior_settled: n(v.prior_settled) }; }), function (v) { return { count: 1, total: v.total, prior_settled: v.prior_settled, remaining: ilo_r2_(v.total - v.prior_settled) }; });
  var payCur = ilo_groupCur_(active.map(function (p) { return { currency: p.currency_code, amount: n(p.amount) }; }), function (p) { return { count: 1, amount: p.amount }; });
  var okAll = true;
  P('=== ImsLoadOpening verify ' + new Date().toISOString() + ' · ' + b.name + ' · md5 ' + b.md5 + (st.applyAt ? ' · Apply ' + st.applyAt : ' · ⚠️ Apply 기록 없음') + ' ===');
  P('');
  P('1. so_invoice kind=opening — ' + invs.length + ' 장(issued ' + issued.length + ' · 그 밖 ' + (invs.length - issued.length) + ')   vs Build ' + b.summary.invoices.count + ' 장');
  P('   통화   IMS 장수   Σ 남은 금액      | Build 장수   Σ 남은 금액');
  ilo_keys_(invCur, b.summary.invoices.by_currency).forEach(function (k) {
    var a = invCur[k] || { count: 0, remaining: 0 }, bb = b.summary.invoices.by_currency[k] || { count: 0, remaining: 0 };
    var same = a.count === bb.count && Math.abs(n(a.remaining) - n(bb.remaining)) <= 0.005; if (!same) okAll = false;
    P('   ' + ilo_padR_(k, 6) + ' ' + ilo_padL_(String(a.count), 8) + ' ' + ilo_padL_(ilo_m_(a.remaining), 16) + '   | ' + ilo_padL_(String(bb.count), 8) + ' ' + ilo_padL_(ilo_m_(bb.remaining), 14) + (same ? '   같다' : '   ⚠️ 다르다(Dry 의 거부 몫이면 그만큼 — report-dry 맨 위)'));
  });
  var legacyDup = ilo_countBy_(issued, function (v) { return v.legacy_invoice_id; }).filter(function (r) { return r.n > 1; }).length;
  P('   옛 열쇠 겹침 ' + legacyDup + ' · 번호 빈 것 ' + issued.filter(function (v) { return !v.invoice_number; }).length + ' · 기한 빈 것 ' + issued.filter(function (v) { return !v.due_on; }).length);
  P('');
  P('2. so_payment method=opening — ' + pays.length + ' 줄(active ' + active.length + ')   vs Build 받아 둔 돈 ' + b.summary.credits.count + ' 줄(창구가 청구처 · 통화로 묶는다 — 줄 수는 다르고 합이 같아야)');
  ilo_keys_(payCur, b.summary.credits.by_currency).forEach(function (k) {
    var a = payCur[k] || { count: 0, amount: 0 }, bb = b.summary.credits.by_currency[k] || { count: 0, amount: 0 };
    var same = Math.abs(n(a.amount) - n(bb.amount)) <= 0.005; if (!same) okAll = false;
    P('   ' + ilo_padR_(k, 6) + ' IMS ' + a.count + ' 손님 ' + ilo_padL_(ilo_m_(a.amount), 14) + '   | Build ' + bb.count + ' 줄 ' + ilo_padL_(ilo_m_(bb.amount), 14) + (same ? '   같다' : '   ⚠️ 다르다'));
  });
  P('');
  P('3. 손님 잔액 표본(so_customer_balance · 정본 식) — 이월 남은 금액이 큰 청구처 5');
  var byCust = {};
  issued.forEach(function (v) { var k = v.bill_to_customer_id + '|' + v.currency_code; byCust[k] = byCust[k] || { id: v.bill_to_customer_id, name: v.bill_to_name, cur: v.currency_code, n: 0, rem: 0 }; byCust[k].n++; byCust[k].rem += n(v.total) - n(v.prior_settled); });
  var top = Object.keys(byCust).map(function (k) { return byCust[k]; }).sort(function (a, b2) { return b2.rem - a.rem; }).slice(0, 5);
  top.forEach(function (c) {
    var rows = ilo_arr_(ilo_rpc_('so_customer_balance', { p_customer_id: c.id })).filter(function (r) { return r.currency_code === c.cur; }), r = rows[0] || {};
    var onAcct = active.filter(function (p) { return p.customer_id === c.id && p.currency_code === c.cur; }).reduce(function (a, p) { return a + n(p.amount); }, 0);
    var same = r.open_invoices === c.n && Math.abs(n(r.open_invoices_due) - c.rem) <= 0.005; if (!same) okAll = false;
    P('   ' + ilo_padR_(ilo_show_(c.name), 32) + ' ' + c.cur + ' · 이월 ' + c.n + ' 장 ' + ilo_padL_(ilo_m_(c.rem), 12) + ' · 잔액 식: open_invoices ' + ilo_show_(r.open_invoices) + ' · open_invoices_due ' + ilo_m_(r.open_invoices_due) + ' · received ' + ilo_m_(r.received) + ' · available ' + ilo_m_(r.available) + ' · 이 손님의 이월 결제 ' + ilo_m_(onAcct) + (same ? '   같다' : '   ⚠️ 다르다(IMS 결제 · 크레딧이 벌써 붙었나)'));
  });
  P('');
  P(okAll ? '⭐ 전부 같다' : '⚠️ 다른 곳이 있다 — 위 ⚠️ 줄 · Dry 의 거부 몫이면 그만큼이 정상');
  var text = out.join('\n');
  b.folder.createFile('report-verify-' + ilo_stamp_() + '.txt', text, MimeType.PLAIN_TEXT);
  Logger.log(text);
}


/* ═══════════════════════════════════════════════════════════
   ⟲ 상태 · 허락 표지
   ═══════════════════════════════════════════════════════════ */

function iloReset() {
  PropertiesService.getScriptProperties().deleteProperty('ILO_STATE');
  Logger.log('ILO_STATE 를 지웠다 — Drive 폴더는 그대로 있다(손으로 지운다 · 다음 iloCollect 가 새 폴더를 만든다)');
}
function iloAllowMismatch() { var st = ilo_state_(); st.allowMismatch = true; ilo_save_state_(st); Logger.log('허락 표지 allowMismatch 켬 — 다음 iloApply 가 어긋난 sale 을 한 번만 통과하고 표지를 끈다'); }
function iloAllowRejects() { var st = ilo_state_(); st.allowRejects = true; ilo_save_state_(st); Logger.log('허락 표지 allowRejects 켬 — 다음 iloApply 가 거부 > 0 을 한 번만 통과하고 표지를 끈다(거부된 줄은 들어가지 않는다)'); }


/* ═══════════════════════════════════════════════════════════
   공통 — Cin7 · IMS 창구 · Drive · 상태 · 셈 도우미
   ═══════════════════════════════════════════════════════════ */

/** Cin7 GET 한 번 — 429 는 Retry-After 만큼(없으면 60 초) 쉬고 다시(여섯 번까지) · 회차가 deferAfterMs 를 넘긴 뒤의 429 는 쉬지 않고 {deferred:true}(부른 쪽이 Next run) · 그 밖의 코드는 돌려준다 · 호출 뒤 1.2 초 */
function ilo_get_(pathAndQuery, started) {
  var cfg = ilo_cfg_();
  var headers = { 'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'), 'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'), 'Content-Type': 'application/json' };
  for (var tries = 0; tries < 6; tries++) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery, { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) {
      var hs = res.getHeaders() || {}, raw = null;
      Object.keys(hs).forEach(function (k) { if (k.toLowerCase() === 'retry-after') raw = hs[k]; });
      var ra = Number(String(raw === null ? '60' : raw).replace(/[^0-9]/g, '')) || 60;
      if (started !== undefined && Date.now() - started > cfg.deferAfterMs) { Logger.log('   429 — 회차가 늦어 쉬지 않고 넘긴다(' + pathAndQuery.slice(0, 50) + ')'); return { code: 429, deferred: true, text: '', data: null, isJson: false }; }
      Logger.log('   429 — ' + ra + '초 대기 후 재시도(' + pathAndQuery.slice(0, 50) + ')');
      Utilities.sleep(ra * 1000 + 1000);
      continue;
    }
    var text = res.getContentText(), data = null, isJson = false;
    try { data = JSON.parse(text); isJson = true; } catch (e) { data = null; }   // cin7-api 규칙 18 — 없는 경로는 200 + HTML
    Utilities.sleep(cfg.sleepMs);
    return { code: code, text: text, data: data, isJson: isJson, deferred: false };
  }
  throw new Error('Cin7 429 가 여섯 번 — ' + pathAndQuery);
}
/** 수집용 — 200 + JSON 이 아니면 멈춘다(부른 쪽이 상태를 아직 안 바꿔 부분 수집이 남지 않는다) */
function ilo_need_(pathAndQuery) {
  var x = ilo_get_(pathAndQuery);
  if (x.code !== 200 || !x.isJson) throw new Error('Cin7 ' + x.code + (x.isJson ? '' : ' (JSON 아님)') + ' · ' + pathAndQuery + ' : ' + String(x.text).slice(0, 300));
  return x;
}
/** IMS 창구 — ims_fetch_(ImsRefLoad.gs) · 200 이 아니면 본문째 멈춘다 */
function ilo_rpc_(fn, payload) {
  var res = ims_fetch_('/rest/v1/rpc/' + fn, { method: 'post', payload: JSON.stringify(payload) });
  var code = res.getResponseCode();
  if (code !== 200) throw new Error('rpc ' + fn + ' HTTP ' + code + ' : ' + String(res.getContentText()).slice(0, 800));
  return JSON.parse(res.getContentText());
}
/** IMS 표 읽기(service_role · RLS 없음) — PostgREST 1,000 행 캡을 Range 로 넘긴다 */
function ilo_restAll_(pathAndQuery) {
  var out = [], from = 0, size = 1000;
  while (true) {
    var res = ims_fetch_('/rest/v1/' + pathAndQuery, { headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + size - 1), 'Prefer': 'count=exact' } });
    var code = res.getResponseCode();
    if (code !== 200 && code !== 206) throw new Error('GET ' + pathAndQuery.slice(0, 60) + ' HTTP ' + code + ' : ' + String(res.getContentText()).slice(0, 300));
    var rows = JSON.parse(res.getContentText()); out = out.concat(rows);
    var hs = res.getHeaders() || {}, cr = null;
    Object.keys(hs).forEach(function (k) { if (k.toLowerCase() === 'content-range') cr = String(hs[k]); });
    var total = cr && /\/(\d+)$/.test(cr) ? Number(cr.match(/\/(\d+)$/)[1]) : null;
    if (rows.length < size || (total !== null && out.length >= total)) break;
    from += size;
  }
  return out;
}
function ilo_banner_(name) {
  var url = getProp('SUPABASE_IMS_URL'), ref = (url.match(/https?:\/\/([a-z0-9]+)\./) || [])[1] || url;
  Logger.log('══ ' + name + ' · IMS ' + ref + ' · ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm') + ' ══');
}
function ilo_md5_(text) {
  var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, text, Utilities.Charset.UTF_8);
  return bytes.map(function (b) { var h = (b < 0 ? b + 256 : b).toString(16); return h.length === 1 ? '0' + h : h; }).join('');
}

function ilo_state_() {
  var v = PropertiesService.getScriptProperties().getProperty('ILO_STATE');
  return v ? JSON.parse(v) : {};
}
function ilo_save_state_(st) { PropertiesService.getScriptProperties().setProperty('ILO_STATE', JSON.stringify(st)); }
function ilo_folder_(st) {
  if (st.folderId) return DriveApp.getFolderById(st.folderId);
  var f = DriveApp.createFolder('ImsLoadOpening ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
  st.folderId = f.getId(); ilo_save_state_(st);
  return f;
}
function ilo_save_(folder, name, text) { folder.createFile(name, String(text === undefined || text === null ? '' : text), MimeType.PLAIN_TEXT); }
function ilo_readAll_(folder, prefix) {
  var it = folder.getFiles(), files = [];
  while (it.hasNext()) { var f = it.next(); if (f.getName().indexOf(prefix) === 0 && /\.json$/.test(f.getName())) files.push(f); }
  files.sort(function (a, b) { return a.getName() < b.getName() ? -1 : 1; });
  var rows = [];
  files.forEach(function (f) { rows = rows.concat(JSON.parse(f.getBlob().getDataAsString())); });
  return { rows: rows, files: files.length };
}
function ilo_readText_(folder, name) {
  var it = folder.getFiles(), hit = null;
  while (it.hasNext()) { var f = it.next(); if (f.getName() === name) hit = f; }   // 같은 이름이 여럿이면 마지막
  return hit ? hit.getBlob().getDataAsString() : null;
}
function ilo_readJson_(folder, name) { var t = ilo_readText_(folder, name); if (t === null) return null; try { return JSON.parse(t); } catch (e) { return null; } }
function ilo_today_() { return Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd'); }
function ilo_stamp_() { return Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmm'); }

function ilo_voided_(s) { return ilo_str_(s.CombinedInvoiceStatus).toUpperCase() === 'VOIDED' || ilo_str_(s.Status).toUpperCase() === 'VOIDED'; }
function ilo_dedupe_(r, key) {
  var seen = {}, out = [], noKey = 0;
  r.rows.forEach(function (x) { var k = x[key]; if (!k) { noKey++; out.push(x); return; } if (seen[k]) return; seen[k] = 1; out.push(x); });
  return { rows: out, raw: r.rows.length, noKey: noKey };
}
function ilo_groupCur_(rows, fn) {           // {CAD:{count, total, …}} — fn 이 주는 숫자 칸을 통화별로 더한다
  var m = {};
  rows.forEach(function (r) { var k = ilo_show_(r.currency); var v = fn(r); m[k] = m[k] || {}; Object.keys(v).forEach(function (c) { m[k][c] = ilo_r2_((m[k][c] || 0) + ilo_n_(v[c])); }); });
  return m;
}
function ilo_byCurArr_(arr, amtKey, cntKey) { var m = {}; ilo_arr_(arr).forEach(function (g) { m[ilo_show_(g.currency_code)] = { count: ilo_n_(g[cntKey]), amount: ilo_n_(g[amtKey]), remaining: ilo_n_(g[amtKey]) }; }); return m; }
function ilo_curText_(m, isPlain) { return Object.keys(m).sort().map(function (k) { return k + ' ' + (isPlain ? ilo_m_(m[k]) : (m[k].count + ' 줄 ' + ilo_m_(m[k].amount))); }).join(' · ') || '0'; }
function ilo_keys_(a, b) { var m = {}; Object.keys(a).forEach(function (k) { m[k] = 1; }); Object.keys(b).forEach(function (k) { m[k] = 1; }); return Object.keys(m).sort(); }
function ilo_sumByCurObj_(rows, fn) { var m = {}; rows.forEach(function (s) { var k = ilo_show_(s.CustomerCurrency); m[k] = ilo_r2_((m[k] || 0) + fn(s)); }); return m; }
function ilo_sumByCur_(rows, fn) { var m = ilo_sumByCurObj_(rows, fn); return Object.keys(m).sort().map(function (k) { return k + ' ' + ilo_m_(m[k]); }).join(' · ') || '0'; }
function ilo_countBy_(rows, fn) {
  var m = {};
  rows.forEach(function (r) { var k = fn(r); m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).map(function (k) { return { k: k, n: m[k] }; }).sort(function (a, b) { return b.n - a.n || (a.k < b.k ? -1 : 1); });
}
function ilo_uniq_(rows, key) { var m = {}; rows.forEach(function (r) { m[r[key] || '(none)'] = 1; }); return Object.keys(m).length; }
function ilo_sum_(rows, key) { return rows.reduce(function (a, r) { return a + ilo_n_(r[key]); }, 0); }
function ilo_arr_(v) { return v === undefined || v === null ? [] : (Array.isArray(v) ? v : [v]); }
function ilo_n_(v) { var x = Number(v); return isFinite(x) ? x : 0; }
function ilo_r2_(v) { return Math.round((ilo_n_(v) + (ilo_n_(v) >= 0 ? 1e-9 : -1e-9)) * 100) / 100; }
function ilo_m_(v) { return (v === undefined || v === null) ? '(없음)' : ilo_n_(v).toFixed(2); }
function ilo_str_(v) { return (v === undefined || v === null) ? '' : String(v).trim(); }
function ilo_show_(v) { var s = ilo_str_(v); return s === '' ? '(blank)' : s; }
function ilo_d_(v) { var s = ilo_str_(v); return s ? s.slice(0, 10) : ''; }
function ilo_text_(html) { return ilo_str_(html).replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim(); }
function ilo_pad_(n) { return ('0000' + n).slice(-4); }
function ilo_padR_(s, w) { s = String(s); return s.length >= w ? s + ' ' : s + new Array(w - s.length + 1).join(' '); }
function ilo_padL_(s, w) { s = String(s); return s.length >= w ? s : new Array(w - s.length + 1).join(' ') + s; }
