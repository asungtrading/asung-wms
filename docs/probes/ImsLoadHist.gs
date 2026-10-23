/**
 * ImsLoadHist.gs — IMS 이전의 판매 · 발주 기록(읽기 전용 · hist_so · hist_po) 적재
 * 2026-10-23 · hist-3 · 판정 654 B · 656 ~ 661 · 창구 = hist-1(20261023165138_hist_1.sql · hist_so_load · hist_po_load)
 *
 * ⚠️⚠️ 대상: [테스트 · Asung-IMS] — SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY (ImsRefLoad.gs 머리 주석 참조) · 로그 첫 줄이 프로젝트 ref 를 찍는다
 * ⚠️ getProp · ims_fetch_ 는 같은 프로젝트의 Config.gs · ImsRefLoad.gs 것을 쓴다(다시 만들지 않는다) · Cin7 호출 · BigQuery 읽기는 이 파일의 ilh_ 도우미
 * ⚠️ 레포에서 실행되지 않는다 — Apps Script 에 붙여 쓰는 원본이다 · 최상위 const 금지 · 식별자 ASCII 만 · 트리거 없음(손으로 돌린다)
 * ⚠️ Advanced Google Service 「BigQuery API」 가 이 프로젝트에 켜져 있어야 한다(Services → BigQuery) — 안 켜져 있으면 ilhDry 첫 줄에서 멈춘다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY · SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 *   선택: ILH_SALE_LIMIT(saleList 한 쪽 · 기본 100 · ilhDry 가 1000 이 동작하면 1000 으로) · ILH_PAGE_ORDERS(창구 한 쪽의 오더 수 · 기본 300 · 창구 상한 500)
 *         ILH_PO_EXTRA_OK(쉼표 목록 · 모르는 PO 상태를 「넣는다」 로 허락) · ILH_ALLOW_UNRESOLVED=1(어긋남 멈춤을 한 번만 통과 · 쓰고 나면 지워진다)
 *
 * 실행 순서(각 단계가 「Next run」 이면 같은 함수를 한 번 더):
 *   1 ilhDry             쓰기 0 · Cin7 확인 다섯 · BigQuery 숫자 · 짝 표본 20 — 대화 Claude 와 숫자를 맞춘 뒤 다음으로
 *   2 ilhPairs           saleList(CreatedSince 2025-10-01) · purchaseList 전 쪽 → Drive 의 pairs-*.json(오더 번호 → GUID)
 *   3 ilhLoadPurchases   BigQuery 발주 줄 → 발주마다 묶어 hist_po_load 로(쪽마다 커서 저장)
 *   4 ilhLoadSales       BigQuery 판매 줄(확정 표 → 당월 표) → hist_so_load 로
 *   5 ilhReset           커서 · 진행 속성만 지운다(IMS 표 · Drive 파일은 그대로 · 창구가 멱등이라 처음부터 다시 돌려도 같은 결과)
 *
 * 판매 — 어느 줄을 보내나(판정 658 · 659)
 *   출처는 오더마다 하나: order_number 가 확정 표(asung_sales_confirmed · invoice_date >= 2025-11-01 · sale IS NOT NULL)에 있으면 bq_confirmed(그 오더의 확정 표 줄 전부 · Invoice + Credit note)
 *   그 밖은 bq_current: 당월 표(asung_order_details_historical)에서 R1 dedup 뒤 UPPER(TRIM(Status)) IN ('CLOSED','COMPLETED') AND Invoice_Date IS NOT NULL
 *     — 「인보이스 된 것」 의 기준 = Status(스킬 R3 · 「확정 판별의 권위 = Status · Order_Progress 로 가르지 않는다」) · ilhDry 가 후보 기준별 오더 수를 함께 찍는다
 *   두 출처 모두 인보이스 날짜 2025-11-01 ~ 오늘(토론토) 만 · 미래 날짜는 여기서도 창구에서도 거른다(두 겹)
 * 발주 — order_date >= 2025-11-01 · 상태가 VOIDED · DRAFT · ORDERING(승인 전 = 초안 · 판정 663)이 아닌 PO 전부(판정 661) · 복합 상태는 조각 하나라도 그 셋이면 뺀다 · 모르는 상태가 나오면 쓰기 함수가 멈춘다
 *
 * ═══ BigQuery 콘솔에 붙여 미리 볼 문장(ilhDry 와 같은 것) — 2026-10-23 실측 대조: 확정 10,110 오더 · 206,910 줄 · 반품 764 줄 · 453 오더 ═══
 *   -- D1 확정 표(Core · sale IS NOT NULL)
 *   SELECT COUNT(*) lines, COUNT(DISTINCT order_number) orders, COUNTIF(doc_type = 'Credit note') return_lines, COUNT(DISTINCT IF(doc_type = 'Credit note', order_number, NULL)) return_orders,
 *          COUNTIF(invoice_date > CURRENT_DATE('America/Toronto')) future_lines, MIN(invoice_date) d_min, MAX(invoice_date) d_max
 *   FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_confirmed` WHERE invoice_date >= '2025-11-01' AND sale IS NOT NULL;
 *   -- D2 당월 표(R1 dedup · 확정 표에 없는 오더) 기준별 오더 수
 *   WITH c AS (SELECT DISTINCT order_number FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_sales_confirmed` WHERE invoice_date >= '2025-11-01' AND sale IS NOT NULL),
 *   d AS (SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY Order_Number, SKU ORDER BY CASE WHEN cin7_updated IS NULL THEN 1 ELSE 0 END, COALESCE(cin7_updated, loaded_at) DESC, loaded_at DESC) rn
 *                        FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_order_details_historical` WHERE Order_Date >= '2025-11-01') WHERE rn = 1 AND Order_Number NOT IN (SELECT order_number FROM c))
 *   SELECT COUNT(DISTINCT Order_Number) all_orders, COUNT(*) all_lines,
 *          COUNT(DISTINCT IF(UPPER(TRIM(Status)) IN ('CLOSED','COMPLETED') AND Invoice_Date IS NOT NULL, Order_Number, NULL)) by_status_closed_completed,
 *          COUNT(DISTINCT IF(Invoice_Number IS NOT NULL AND Invoice_Number <> '', Order_Number, NULL)) by_invoice_number,
 *          COUNT(DISTINCT IF(UPPER(TRIM(Invoice_Status)) IN ('AUTHORISED','PAID'), Order_Number, NULL)) by_invoice_status_auth_paid,
 *          COUNT(DISTINCT IF(UPPER(TRIM(Order_Progress)) IN ('4.INVOICED','INVOICED','5.FULFILLED','FULFILLED','3.FINALIZED','FINALIZED'), Order_Number, NULL)) by_order_progress,
 *          COUNTIF(UPPER(TRIM(Status)) IN ('CLOSED','COMPLETED') AND Invoice_Date IS NOT NULL) lines_chosen,
 *          COUNTIF(UPPER(TRIM(Status)) IN ('CLOSED','COMPLETED') AND Invoice_Date > CURRENT_DATE('America/Toronto')) future_lines_chosen
 *   FROM d;
 *   -- D3 당월 표 상태 분포(R6 — 값을 눈으로)
 *   SELECT UPPER(TRIM(Status)) s, UPPER(TRIM(Invoice_Status)) i, COUNT(DISTINCT Order_Number) orders FROM `geometric-rock-487814-k4.Cin7_Sales_Data.asung_order_details_historical` WHERE Order_Date >= '2025-11-01' GROUP BY 1, 2 ORDER BY 3 DESC;
 *   -- D4 발주(상태별)
 *   SELECT UPPER(TRIM(status)) s, COUNT(DISTINCT po_number) pos, COUNT(*) lines, COUNTIF(order_date > CURRENT_DATE('America/Toronto')) future_lines
 *   FROM `geometric-rock-487814-k4.Cin7_Purchase_Data.asung_purchase_history` WHERE order_date >= '2025-11-01' GROUP BY 1 ORDER BY 2 DESC;
 */

/* ═══════════════════════════════════════════════════════════
   상수 — 함수로(최상위 const 금지)
   ═══════════════════════════════════════════════════════════ */
function ilh_cfg_() {
  return {
    bqProject: 'geometric-rock-487814-k4',
    salesDs: 'geometric-rock-487814-k4.Cin7_Sales_Data',
    purchaseDs: 'geometric-rock-487814-k4.Cin7_Purchase_Data',
    coreFrom: '2025-11-01',                       // 판정 658 — Core 시절 시작(인보이스 날짜 · 발주 날짜)
    pairsSince: '2025-10-01T00:00:00',            // saleList CreatedSince — 넓게 받고 남는 것은 버린다(hist-0 이견 3)
    runBudgetMs: 270000,                          // 4 분 30 초(규칙 6 이어 달리기)
    pageOrders: Math.min(500, Number(getProp_opt_('ILH_PAGE_ORDERS') || 300)),   // 창구 한 쪽(상한 500)
    saleLimit: Number(getProp_opt_('ILH_SALE_LIMIT') || 100),
    poSkip: ['VOIDED', 'DRAFT', 'ORDERING'],      // 판정 661 — 취소 · 초안만 뺀다 · 판정 663 — ORDERING(승인 전 · 공급처에 안 보낸 발주)도 초안으로 본다
    poKnown: ['ORDERING', 'ORDERED', 'RECEIVING', 'RECEIVED', 'INVOICED', 'CREDITED', 'COMPLETED', 'PARTIALLY INVOICED', 'CREDIT NOTE CLOSED', 'VOIDED', 'DRAFT'],   // cin7-api purchase.md 상태 목록 + 실측 복합 조각
    unresolvedMax: 0.20                           // 쪽의 20 % 를 넘으면 멈춤(ILH_ALLOW_UNRESOLVED=1 로 한 번만 통과)
  };
}
function getProp_opt_(key) {                      // 없는 속성은 null(getProp 은 없으면 throw)
  return PropertiesService.getScriptProperties().getProperty(key);
}

/* ═══════════════════════════════════════════════════════════
   1  마른 실행 — 쓰기 0
   ═══════════════════════════════════════════════════════════ */
function ilhDry() {
  var cfg = ilh_cfg_();
  ilh_banner_('ilhDry (쓰기 0)');
  // ① Cin7 확인 다섯(hist-0 Q3)
  var a = ilh_cin7_('saleList?Page=1&Limit=100&CreatedSince=' + cfg.pairsSince);
  var al = a.SaleList || [];
  Logger.log('a) saleList Limit=100 CreatedSince=' + cfg.pairsSince + ' → Total ' + a.Total + ' · 받은 행 ' + al.length);
  Logger.log('   첫 두 행 칸: ' + (al[0] ? Object.keys(al[0]).join(',') : '(없음)'));
  Logger.log('   표본: ' + al.slice(0, 2).map(function (r) { return r.OrderNumber + ' ' + r.Status + ' ' + r.InvoiceDate + ' ' + (r.CustomerID || '(no CustomerID)') + ' ' + r.Customer; }).join(' | '));
  var b = ilh_cin7_('saleList?Page=1&Limit=1000&CreatedSince=' + cfg.pairsSince);
  var bl = b.SaleList || [];
  Logger.log('b) saleList Limit=1000 → 받은 행 ' + bl.length + (bl.length > 100 ? ' ⭐ 1000 이 동작한다 — Script Property ILH_SALE_LIMIT=1000 으로' : ' ⚠️ 100 뿐 — Limit 은 100'));
  var withId = bl.filter(function (r) { return r.CustomerID; }).length;
  Logger.log('c) CustomerID 가 찬 행 ' + withId + ' / ' + bl.length);
  var d = ilh_cin7_('saleCreditNoteList?Page=1&Limit=2');
  var dk = Object.keys(d).filter(function (k) { return Array.isArray(d[k]); })[0];
  Logger.log('d) saleCreditNoteList → Total ' + d.Total + ' · 배열 키 ' + dk + ' · 첫 행 칸: ' + ((dk && d[dk][0]) ? Object.keys(d[dk][0]).join(',') : '(없음)'));
  var e = ilh_cin7_('purchaseList?Page=1&Limit=1000');
  var el = e.PurchaseList || [];
  Logger.log('e) purchaseList Limit=1000 → Total ' + e.Total + ' · 받은 행 ' + el.length + ' · 첫 ' + (el[0] ? el[0].OrderNumber + ' ' + el[0].OrderDate : '-') + ' · 마지막 ' + (el.length ? el[el.length - 1].OrderNumber + ' ' + el[el.length - 1].OrderDate + ' SupplierID ' + (el[el.length - 1].SupplierID || '(없음)') : '-'));
  // ② BigQuery 숫자
  var q = ilh_sql_();
  ilh_logRows_('D1 확정 표(Core)', ilh_bq_(q.d1));
  ilh_logRows_('D2 당월 표(확정 표에 없는 오더) 기준별', ilh_bq_(q.d2));
  ilh_logRows_('D3 당월 표 상태 분포(위 10)', ilh_bq_(q.d3).slice(0, 10));
  ilh_logRows_('D4 발주 상태별', ilh_bq_(q.d4));
  var bad = ilh_bq_(q.d5);
  Logger.log('D5 오더 번호 꼴 — SO-nnnnn 이 아닌 것: ' + (bad.length ? bad.map(function (r) { return r.src + ':' + r.order_number; }).join(',') : '0'));
  ilh_logRows_('D6 발주 중 거를 상태 · 모르는 상태', ilh_poStatusCheck_(ilh_bq_(q.d4)));
  // ③ 짝 표본 20 — 확정 표의 오더 20 개를 saleList Search 로
  var sample = ilh_bq_(q.sample20);
  var hit = 0, noId = 0, miss = 0;
  sample.forEach(function (r) {
    var s = ilh_cin7_('saleList?Page=1&Limit=5&Search=' + encodeURIComponent(r.order_number));
    var row = (s.SaleList || []).filter(function (x) { return x.OrderNumber === r.order_number; })[0];
    if (!row) miss++; else if (row.CustomerID) hit++; else noId++;
    Utilities.sleep(1200);
  });
  Logger.log('짝 표본 20: CustomerID 있음 ' + hit + ' · 행은 있는데 CustomerID 없음 ' + noId + ' · saleList 에 없음 ' + miss);
  Logger.log('⭐ ilhDry 끝 — 숫자를 대화 Claude 와 맞춘 뒤 ilhPairs');
}

/* ═══════════════════════════════════════════════════════════
   2  짝 받기 — saleList · purchaseList 전 쪽 → Drive pairs-*.json
   ═══════════════════════════════════════════════════════════ */
function ilhPairs() {
  var cfg = ilh_cfg_(), props = PropertiesService.getScriptProperties();
  ilh_banner_('ilhPairs');
  var folder = ilh_folder_();
  if (props.getProperty('ILH_PAIRS_SALE_DONE') !== '1') {
    var r = ilh_collect_(folder, 'sale', 'saleList', 'SaleList', cfg.saleLimit, '&CreatedSince=' + cfg.pairsSince, 'ILH_PAIRS_SALE', function (x) { return [x.OrderNumber, x.CustomerID || null, x.Status]; });
    if (!r.done) { Logger.log('Next run — ilhPairs 를 한 번 더(saleList 쪽 ' + r.nextPage + ' 부터)'); return; }
  }
  if (props.getProperty('ILH_PAIRS_PO_DONE') !== '1') {
    var r2 = ilh_collect_(folder, 'po', 'purchaseList', 'PurchaseList', 1000, '', 'ILH_PAIRS_PO', function (x) { return [x.OrderNumber, x.SupplierID || null, x.Status]; });
    if (!r2.done) { Logger.log('Next run — ilhPairs 를 한 번 더(purchaseList 쪽 ' + r2.nextPage + ' 부터)'); return; }
  }
  // 합쳐서 pairs-sale.json · pairs-po.json 하나씩
  var sale = ilh_mergePairs_(folder, 'pairs-sale-pages-'), po = ilh_mergePairs_(folder, 'pairs-po-pages-');
  ilh_writeFile_(folder, 'pairs-sale.json', JSON.stringify(sale));
  ilh_writeFile_(folder, 'pairs-po.json', JSON.stringify(po));
  Logger.log('⭐ 짝 끝 — 판매 ' + Object.keys(sale).length + ' 오더(GUID 없음 ' + ilh_countNull_(sale) + ') · 발주 ' + Object.keys(po).length + ' (GUID 없음 ' + ilh_countNull_(po) + ') · 폴더 ' + folder.getUrl() + ' · 다음은 ilhLoadPurchases');
}

function ilh_collect_(folder, tag, endpoint, arrKey, limit, extraQuery, propPrefix, pick) {
  var cfg = ilh_cfg_(), props = PropertiesService.getScriptProperties();
  var startPage = Number(props.getProperty(propPrefix + '_NEXT_PAGE') || '1');
  var page = startPage, started = Date.now(), rows = [], done = false, total = null;
  while (Date.now() - started < cfg.runBudgetMs) {
    var data = ilh_cin7_(endpoint + '?Page=' + page + '&Limit=' + limit + extraQuery);
    var items = data[arrKey] || [];
    if (total === null) total = data.Total;
    items.forEach(function (x) { rows.push(pick(x)); });
    if (items.length < limit) { done = true; break; }   // 끝 판단 = 받은 행 수 < Limit(Total 이 아니다 · 규칙 6)
    page++;
    Utilities.sleep(1200);
  }
  var lastPage = done ? page : page - 1;
  if (rows.length) ilh_writeFile_(folder, 'pairs-' + tag + '-pages-' + ilh_pad_(startPage) + '-' + ilh_pad_(lastPage) + '.json', JSON.stringify(rows));
  var got = Number(props.getProperty(propPrefix + '_GOT') || '0') + rows.length;
  props.setProperty(propPrefix + '_GOT', String(got));
  if (total !== null) props.setProperty(propPrefix + '_TOTAL', String(total));
  Logger.log(endpoint + ' 쪽 ' + startPage + ' ~ ' + lastPage + ' · 이번 ' + rows.length + ' · 누적 ' + got + ' · API Total ' + total);
  if (done) {
    if (got !== Number(props.getProperty(propPrefix + '_TOTAL'))) {
      throw new Error(endpoint + ': 받은 행 ' + got + ' ≠ API Total ' + props.getProperty(propPrefix + '_TOTAL') + ' — 수집이 짧게 끝났다 · ilhReset 뒤 다시(규칙 6 안전장치)');
    }
    props.setProperty(propPrefix + '_DONE', '1');
    props.deleteProperty(propPrefix + '_NEXT_PAGE');
  } else {
    props.setProperty(propPrefix + '_NEXT_PAGE', String(page));
  }
  return { done: done, nextPage: page };
}
function ilh_mergePairs_(folder, prefix) {
  var map = {}, it = folder.getFiles();
  while (it.hasNext()) {
    var f = it.next();
    if (f.getName().indexOf(prefix) !== 0) continue;
    JSON.parse(f.getBlob().getDataAsString()).forEach(function (t) { if (t[0] && !(t[0] in map && map[t[0]])) map[t[0]] = t[1]; });
  }
  return map;
}
function ilh_loadPairs_(folder, name) {
  var it = folder.getFilesByName(name);
  if (!it.hasNext()) throw new Error(name + ' 이 없다 — ilhPairs 먼저');
  return JSON.parse(it.next().getBlob().getDataAsString());
}

/* ═══════════════════════════════════════════════════════════
   3  발주 적재 — BigQuery 발주 줄 → hist_po_load (판정 661)
   ═══════════════════════════════════════════════════════════ */
function ilhLoadPurchases() {
  var cfg = ilh_cfg_(), props = PropertiesService.getScriptProperties(), q = ilh_sql_();
  ilh_banner_('ilhLoadPurchases');
  if (props.getProperty('ILH_PAIRS_PO_DONE') !== '1') throw new Error('짝이 없다 — ilhPairs 먼저');
  var folder = ilh_folder_(), pairs = ilh_loadPairs_(folder, 'pairs-po.json');
  var st = ilh_poStatusCheck_(ilh_bq_(q.d4));
  var unknown = st.filter(function (r) { return r.verdict === 'UNKNOWN'; });
  if (unknown.length) throw new Error('모르는 PO 상태 — 넣을지 뺄지 정해라: ' + unknown.map(function (r) { return r.status + '(' + r.pos + ')'; }).join(', ') + ' · 넣으려면 ILH_PO_EXTRA_OK 에 쉼표로');
  var cursor = props.getProperty('ILH_PO_CURSOR') || '', started = Date.now(), sum = null;
  while (Date.now() - started < cfg.runBudgetMs) {
    var rows = ilh_bq_(q.poPage(cursor, cfg.pageOrders));
    if (!rows.length) { props.setProperty('ILH_PO_DONE', '1'); Logger.log('⭐ 발주 적재 끝 · 누적 ' + props.getProperty('ILH_PO_SUM') + ' · 다음은 ilhLoadSales'); return; }
    var orders = ilh_groupPo_(rows, pairs, cfg);
    var ret = ilh_rpc_('hist_po_load', orders);
    ilh_guard_(ret, orders.length, rows.length, 'supplier_unresolved');
    sum = ilh_addSum_(props, 'ILH_PO_SUM', ret);
    cursor = rows[rows.length - 1].po_number;
    props.setProperty('ILH_PO_CURSOR', cursor);
    Logger.log('쪽 ' + orders.length + ' 발주 · ' + rows.length + ' 줄 → ' + JSON.stringify(ret) + ' · 커서 ' + cursor);
  }
  Logger.log('Next run — ilhLoadPurchases 를 한 번 더(커서 ' + cursor + ' · 누적 ' + JSON.stringify(sum) + ')');
}
function ilh_groupPo_(rows, pairs, cfg) {
  var byNo = {}, order = [];
  rows.forEach(function (r) {
    var o = byNo[r.po_number];
    if (!o) {
      o = byNo[r.po_number] = { po_number: r.po_number, era: 'core', cin7_supplier_id: pairs[r.po_number] || null, supplier_name: r.supplier_name, order_date: r.order_date, required_by: r.required_by,
                                received_date: r.received_date, status: r.status, po_complete: ilh_bool_(r.po_complete), currency: r.currency, po_total: ilh_num_(r.po_total), lines: [] };
      order.push(o);
    }
    o.lines.push({ sku: r.sku, product_name: r.product_name, quantity: ilh_num_(r.quantity), received_quantity: ilh_num_(r.received_quantity), unit_price: ilh_num_(r.unit_price), line_total: ilh_num_(r.line_total) });
  });
  return order;
}
function ilh_poStatusCheck_(statusRows) {
  var cfg = ilh_cfg_(), extra = (getProp_opt_('ILH_PO_EXTRA_OK') || '').split(',').map(function (s) { return s.trim().toUpperCase(); }).filter(String);
  return statusRows.map(function (r) {
    var s = String(r.s || '').toUpperCase().trim(), parts = s.split('/').map(function (p) { return p.trim(); });
    var verdict = parts.some(function (p) { return cfg.poSkip.indexOf(p) >= 0; }) ? 'SKIP'
                : parts.every(function (p) { return cfg.poKnown.indexOf(p) >= 0 || extra.indexOf(p) >= 0; }) ? 'LOAD' : 'UNKNOWN';
    return { status: s || '(빈 값)', pos: r.pos, lines: r.lines, future_lines: r.future_lines, verdict: verdict };
  });
}

/* ═══════════════════════════════════════════════════════════
   4  판매 적재 — 확정 표(bq_confirmed) → 당월 표(bq_current) → hist_so_load (판정 658 · 659)
   ═══════════════════════════════════════════════════════════ */
function ilhLoadSales() {
  var cfg = ilh_cfg_(), props = PropertiesService.getScriptProperties(), q = ilh_sql_();
  ilh_banner_('ilhLoadSales');
  if (props.getProperty('ILH_PAIRS_SALE_DONE') !== '1') throw new Error('짝이 없다 — ilhPairs 먼저');
  var folder = ilh_folder_(), pairs = ilh_loadPairs_(folder, 'pairs-sale.json');
  var started = Date.now(), sum = null;
  var phases = [{ key: 'ILH_SO_CONF', source: 'bq_confirmed', page: q.confPage }, { key: 'ILH_SO_CURR', source: 'bq_current', page: q.currPage }];
  for (var i = 0; i < phases.length; i++) {
    var ph = phases[i];
    if (props.getProperty(ph.key + '_DONE') === '1') continue;
    var cursor = props.getProperty(ph.key + '_CURSOR') || '';
    while (Date.now() - started < cfg.runBudgetMs) {
      var rows = ilh_bq_(ph.page(cursor, cfg.pageOrders));
      if (!rows.length) { props.setProperty(ph.key + '_DONE', '1'); Logger.log('⭐ ' + ph.source + ' 끝'); break; }
      var orders = ilh_groupSo_(rows, pairs, ph.source), unpaired = orders.filter(function (o) { return !o.cin7_customer_id; }).length;
      var ret = ilh_rpc_('hist_so_load', orders);
      ilh_guard_(ret, orders.length, rows.length, 'customer_unresolved');
      sum = ilh_addSum_(props, 'ILH_SO_SUM', ret);
      cursor = rows[rows.length - 1].order_number;
      props.setProperty(ph.key + '_CURSOR', cursor);
      Logger.log(ph.source + ' 쪽 ' + orders.length + ' 오더(짝 없음 ' + unpaired + ') · ' + rows.length + ' 줄 → ' + JSON.stringify(ret) + ' · 커서 ' + cursor);
    }
    if (props.getProperty(ph.key + '_DONE') !== '1') { Logger.log('Next run — ilhLoadSales 를 한 번 더(' + ph.source + ' 커서 ' + cursor + ' · 누적 ' + JSON.stringify(sum) + ')'); return; }
  }
  Logger.log('⭐ 판매 적재 끝 · 누적 ' + props.getProperty('ILH_SO_SUM') + ' · 컷오버 직전에 ilhReset → ilhPairs → ilhLoadPurchases → ilhLoadSales 를 다시(창구가 멱등)');
}
function ilh_groupSo_(rows, pairs, source) {
  var byNo = {}, order = [];
  rows.forEach(function (r) {
    var o = byNo[r.order_number];
    if (!o) {
      o = byNo[r.order_number] = { order_number: r.order_number, era: 'core', source: source, cin7_customer_id: pairs[r.order_number] || null, customer_name: r.customer, order_date: r.order_date,
                                   invoice_date: null, invoice_number: null, location: r.location, currency: r.currency || null, lines: [] };
      order.push(o);
    }
    o.lines.push({ doc_type: r.doc_type || 'invoice', doc_number: r.doc_number, doc_date: r.doc_date, sku: r.sku, product_name: r.product, brand: r.brand,
                   quantity: ilh_num_(r.quantity), sale: ilh_num_(r.sale), discount: ilh_num_(r.discount), tax: ilh_num_(r.tax), total: ilh_num_(r.total) });
  });
  return order;   // invoice_date · invoice_number 는 창구가 첫 invoice 줄에서 채운다(hist-1 이견 2)
}

/* ═══════════════════════════════════════════════════════════
   5  리셋 — 커서 · 진행 속성만
   ═══════════════════════════════════════════════════════════ */
function ilhReset() {
  var props = PropertiesService.getScriptProperties(), n = 0;
  ['ILH_PAIRS_SALE_DONE', 'ILH_PAIRS_SALE_NEXT_PAGE', 'ILH_PAIRS_SALE_GOT', 'ILH_PAIRS_SALE_TOTAL', 'ILH_PAIRS_PO_DONE', 'ILH_PAIRS_PO_NEXT_PAGE', 'ILH_PAIRS_PO_GOT', 'ILH_PAIRS_PO_TOTAL',
   'ILH_PO_CURSOR', 'ILH_PO_DONE', 'ILH_PO_SUM', 'ILH_SO_CONF_CURSOR', 'ILH_SO_CONF_DONE', 'ILH_SO_CURR_CURSOR', 'ILH_SO_CURR_DONE', 'ILH_SO_SUM', 'ILH_ALLOW_UNRESOLVED'
  ].forEach(function (k) { if (props.getProperty(k) !== null) { props.deleteProperty(k); n++; } });
  Logger.log('ilhReset — 속성 ' + n + ' 개 지움 · IMS 표 · Drive 폴더(ILH_FOLDER_ID)는 그대로 · 짝을 다시 받으려면 ilhPairs(옛 pairs-*.json 위에 새 쪽이 쌓인다 — 폴더를 비우거나 ILH_FOLDER_ID 를 지워 새 폴더로)');
}

/* ═══════════════════════════════════════════════════════════
   BigQuery 문장 — 쪽은 오더 번호 순 · 커서 = 마지막으로 보낸 번호(이어 달리기 · 멱등)
   ═══════════════════════════════════════════════════════════ */
function ilh_sql_() {
  var c = ilh_cfg_(), T = 'CURRENT_DATE(\'America/Toronto\')';
  var conf = '`' + c.salesDs + '.asung_sales_confirmed`', curr = '`' + c.salesDs + '.asung_order_details_historical`', po = '`' + c.purchaseDs + '.asung_purchase_history`';
  var confKeep = 'invoice_date >= \'' + c.coreFrom + '\' AND sale IS NOT NULL';
  var confOrders = '(SELECT DISTINCT order_number FROM ' + conf + ' WHERE ' + confKeep + ')';
  var currDedup = '(SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY Order_Number, SKU ORDER BY CASE WHEN cin7_updated IS NULL THEN 1 ELSE 0 END, COALESCE(cin7_updated, loaded_at) DESC, loaded_at DESC) rn FROM ' + curr + ' WHERE Order_Date >= \'' + c.coreFrom + '\') WHERE rn = 1 AND Order_Number NOT IN ' + confOrders + ')';
  var currKeep = 'UPPER(TRIM(Status)) IN (\'CLOSED\',\'COMPLETED\') AND Invoice_Date IS NOT NULL';
  return {
    d1: 'SELECT COUNT(*) lines, COUNT(DISTINCT order_number) orders, COUNTIF(doc_type = \'Credit note\') return_lines, COUNT(DISTINCT IF(doc_type = \'Credit note\', order_number, NULL)) return_orders, COUNTIF(invoice_date > ' + T + ') future_lines, MIN(invoice_date) d_min, MAX(invoice_date) d_max FROM ' + conf + ' WHERE ' + confKeep,
    d2: 'SELECT COUNT(DISTINCT Order_Number) all_orders, COUNT(*) all_lines, COUNT(DISTINCT IF(' + currKeep + ', Order_Number, NULL)) by_status_closed_completed, COUNT(DISTINCT IF(Invoice_Number IS NOT NULL AND Invoice_Number <> \'\', Order_Number, NULL)) by_invoice_number, COUNT(DISTINCT IF(UPPER(TRIM(Invoice_Status)) IN (\'AUTHORISED\',\'PAID\'), Order_Number, NULL)) by_invoice_status_auth_paid, COUNT(DISTINCT IF(UPPER(TRIM(Order_Progress)) IN (\'4.INVOICED\',\'INVOICED\',\'5.FULFILLED\',\'FULFILLED\',\'3.FINALIZED\',\'FINALIZED\'), Order_Number, NULL)) by_order_progress, COUNTIF(' + currKeep + ') lines_chosen, COUNTIF(UPPER(TRIM(Status)) IN (\'CLOSED\',\'COMPLETED\') AND Invoice_Date > ' + T + ') future_lines_chosen FROM ' + currDedup,
    d3: 'SELECT UPPER(TRIM(Status)) s, UPPER(TRIM(Invoice_Status)) i, COUNT(DISTINCT Order_Number) orders FROM ' + curr + ' WHERE Order_Date >= \'' + c.coreFrom + '\' GROUP BY 1, 2 ORDER BY 3 DESC',
    d4: 'SELECT UPPER(TRIM(status)) s, COUNT(DISTINCT po_number) pos, COUNT(*) lines, COUNTIF(order_date > ' + T + ') future_lines FROM ' + po + ' WHERE order_date >= \'' + c.coreFrom + '\' GROUP BY 1 ORDER BY 2 DESC',
    d5: 'SELECT \'confirmed\' src, order_number FROM ' + conf + ' WHERE ' + confKeep + ' AND NOT REGEXP_CONTAINS(order_number, r\'^SO-[0-9]{5}$\') GROUP BY 2 UNION ALL SELECT \'current\', Order_Number FROM ' + currDedup + ' WHERE NOT REGEXP_CONTAINS(Order_Number, r\'^SO-[0-9]{5}$\') GROUP BY 2 UNION ALL SELECT \'po\', po_number FROM ' + po + ' WHERE order_date >= \'' + c.coreFrom + '\' AND NOT REGEXP_CONTAINS(po_number, r\'^PO-[0-9]{5}$\') GROUP BY 2 LIMIT 50',
    sample20: 'SELECT order_number FROM ' + conf + ' WHERE ' + confKeep + ' GROUP BY 1 ORDER BY RAND() LIMIT 20',
    // 쪽: 다음 N 오더(번호 순 · 커서 뒤)의 줄 전부 — 번호가 SO-nnnnn 폭이 같아 글자 순 = 번호 순(D5 가 예외를 찍는다)
    confPage: function (cursor, n) {
      return 'WITH o AS (SELECT order_number FROM ' + conf + ' WHERE ' + confKeep + ' AND invoice_date <= ' + T + ' AND order_number > \'' + cursor + '\' GROUP BY 1 ORDER BY 1 LIMIT ' + n + ') ' +   // 오더 고르기도 미래 날짜를 뺀 줄에서(미래뿐인 오더가 쪽을 비워 「끝」 으로 읽히지 않게)
             'SELECT s.order_number, s.customer, s.order_date, s.location, CAST(NULL AS STRING) currency, LOWER(IF(s.doc_type = \'Credit note\', \'credit\', \'invoice\')) doc_type, CAST(s.document_number AS STRING) doc_number, CAST(s.invoice_date AS STRING) doc_date, ' +
             's.sku, s.product, s.brand, s.quantity, s.sale, s.discount, s.tax, s.total FROM ' + conf + ' s JOIN o USING (order_number) WHERE ' + confKeep + ' AND s.invoice_date <= ' + T + ' ORDER BY s.order_number, s.invoice_date, s.doc_type, s.sku';
    },
    currPage: function (cursor, n) {
      return 'WITH d AS (SELECT * FROM ' + currDedup + ' WHERE ' + currKeep + ' AND Invoice_Date >= \'' + c.coreFrom + '\' AND Invoice_Date <= ' + T + '), ' +
             'o AS (SELECT Order_Number FROM d WHERE Order_Number > \'' + cursor + '\' GROUP BY 1 ORDER BY 1 LIMIT ' + n + ') ' +
             'SELECT d.Order_Number order_number, d.Customer customer, CAST(d.Order_Date AS STRING) order_date, d.Location location, d.Currency currency, \'invoice\' doc_type, CAST(d.Invoice_Number AS STRING) doc_number, CAST(d.Invoice_Date AS STRING) doc_date, ' +
             'd.SKU sku, d.Product product, d.Brand brand, d.Quantity quantity, d.Sale sale, CAST(NULL AS NUMERIC) discount, d.Tax tax, d.Total total FROM d JOIN o USING (Order_Number) ORDER BY d.Order_Number, d.SKU';
    },
    poPage: function (cursor, n) {
      var skip = ilh_cfg_().poSkip.map(function (s) { return '\'' + s + '\''; }).join(',');
      return 'WITH o AS (SELECT po_number FROM ' + po + ' WHERE order_date >= \'' + c.coreFrom + '\' AND order_date <= ' + T + ' AND po_number > \'' + cursor + '\' AND NOT EXISTS (SELECT 1 FROM UNNEST(SPLIT(UPPER(TRIM(status)), \'/\')) p WHERE TRIM(p) IN (' + skip + ')) GROUP BY 1 ORDER BY 1 LIMIT ' + n + ') ' +
             'SELECT p.po_number, p.supplier_name, CAST(p.order_date AS STRING) order_date, CAST(p.required_by AS STRING) required_by, CAST(p.received_date AS STRING) received_date, p.status, CAST(p.po_complete AS STRING) po_complete, p.currency, p.po_total, ' +
             'p.sku, p.product_name, p.quantity, p.received_quantity, p.unit_price, p.line_total FROM ' + po + ' p JOIN o USING (po_number) ORDER BY p.po_number, p.sku';
    }
  };
}

/* ═══════════════════════════════════════════════════════════
   공통 — BigQuery 읽기 · Cin7 · IMS 창구 · 안전장치 · Drive
   ═══════════════════════════════════════════════════════════ */
// BigQuery.Jobs.query → 쪽(pageToken)을 다 넘겨 행 객체 배열로 · 값은 글자(DATE 는 YYYY-MM-DD · 숫자는 글자 · TIMESTAMP 는 쓰지 않는다 — R2)
function ilh_bq_(sql) {
  var project = ilh_cfg_().bqProject;
  var res = BigQuery.Jobs.query({ query: sql, useLegacySql: false, timeoutMs: 180000, maxResults: 50000 }, project);
  if (!res.jobComplete) throw new Error('BigQuery 가 180 초 안에 끝나지 않았다 — 문장을 좁혀라');
  var fields = (res.schema && res.schema.fields || []).map(function (f) { return f.name; }), out = [];
  var push = function (rows) { (rows || []).forEach(function (r) { var o = {}; r.f.forEach(function (c, i) { o[fields[i]] = c.v; }); out.push(o); }); };
  push(res.rows);
  var token = res.pageToken, jobId = res.jobReference && res.jobReference.jobId;
  while (token) {
    var more = BigQuery.Jobs.getQueryResults(project, jobId, { pageToken: token, maxResults: 50000, location: res.jobReference.location });
    push(more.rows);
    token = more.pageToken;
  }
  return out;
}
function ilh_cin7_(pathAndQuery) {
  var headers = { 'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'), 'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'), 'Content-Type': 'application/json' };
  for (var tries = 0; tries < 6; tries++) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery, { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) {                                  // Retry-After 만큼 쉰다(없으면 60 초 · cin7-api 11 번)
      var ra = Number(((res.getHeaders() || {})['Retry-After'] || '60').toString().replace(/[^0-9]/g, '')) || 60;
      Logger.log('   429 — ' + ra + '초 대기 후 재시도(' + pathAndQuery.slice(0, 40) + ')');
      Utilities.sleep(ra * 1000 + 1000);
      continue;
    }
    if (code !== 200) throw new Error('Cin7 ' + code + ' · ' + pathAndQuery + ' : ' + res.getContentText().slice(0, 300));
    return JSON.parse(res.getContentText());
  }
  throw new Error('Cin7 429 가 여섯 번 — ' + pathAndQuery);
}
function ilh_rpc_(fn, orders) {
  var res = ims_fetch_('/rest/v1/rpc/' + fn, { method: 'post', payload: JSON.stringify({ p_orders: orders }) });
  var code = res.getResponseCode();
  if (code !== 200) throw new Error(fn + ' ' + code + ' : ' + res.getContentText().slice(0, 500));
  return JSON.parse(res.getContentText());
}
// 크게 어긋나면 멈춤 — IMS 번호 겹침 > 0 · 주인 못 풀림 > 20 % · 제품 못 풀림 > 20 %(한 쪽 기준) · ILH_ALLOW_UNRESOLVED=1 이면 한 번만 통과(속성을 지운다)
function ilh_guard_(ret, nOrders, nLines, ownerKey) {
  var cfg = ilh_cfg_(), props = PropertiesService.getScriptProperties(), why = [];
  if ((ret.orders_skipped_ims_number || 0) > 0) why.push('orders_skipped_ims_number ' + ret.orders_skipped_ims_number + '(IMS 번호와 겹침 — 실측 0 이어야 한다)');
  if (nOrders && (ret[ownerKey] || 0) > nOrders * cfg.unresolvedMax) why.push(ownerKey + ' ' + ret[ownerKey] + ' / ' + nOrders + ' 오더');
  if (nLines && (ret.product_unresolved || 0) > nLines * cfg.unresolvedMax) why.push('product_unresolved ' + ret.product_unresolved + ' / ' + nLines + ' 줄');
  if (!why.length) return;
  if (props.getProperty('ILH_ALLOW_UNRESOLVED') === '1') { props.deleteProperty('ILH_ALLOW_UNRESOLVED'); Logger.log('⚠️ 어긋남을 한 번 통과(ILH_ALLOW_UNRESOLVED): ' + why.join(' · ')); return; }
  throw new Error('⛔ 멈춤 — 이 쪽은 이미 창구에 들어갔다(멱등 · 다시 보내면 같은 결과): ' + why.join(' · ') + ' · 맞으면 ILH_ALLOW_UNRESOLVED=1 을 넣고 같은 함수를 한 번 더(한 번만 통과)');
}
function ilh_addSum_(props, key, ret) {
  var sum = JSON.parse(props.getProperty(key) || '{}');
  Object.keys(ret).forEach(function (k) { sum[k] = (sum[k] || 0) + (Number(ret[k]) || 0); });
  props.setProperty(key, JSON.stringify(sum));
  return sum;
}
function ilh_banner_(name) {
  var url = getProp('SUPABASE_IMS_URL'), ref = (url.match(/https?:\/\/([a-z0-9]+)\./) || [])[1] || url;
  Logger.log('══ ' + name + ' · IMS ' + ref + ' · BigQuery ' + ilh_cfg_().bqProject + ' · ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm') + ' ══');
}
function ilh_folder_() {
  var props = PropertiesService.getScriptProperties(), id = props.getProperty('ILH_FOLDER_ID');
  if (id) return DriveApp.getFolderById(id);
  var f = DriveApp.createFolder('ImsLoadHist ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
  props.setProperty('ILH_FOLDER_ID', f.getId());
  return f;
}
function ilh_writeFile_(folder, name, text) {
  var it = folder.getFilesByName(name);
  while (it.hasNext()) it.next().setTrashed(true);
  folder.createFile(name, text, MimeType.PLAIN_TEXT);
}
function ilh_logRows_(title, rows) {
  Logger.log(title + ' (' + rows.length + ' 행)');
  rows.forEach(function (r) { Logger.log('   ' + Object.keys(r).map(function (k) { return k + '=' + r[k]; }).join(' · ')); });
}
function ilh_countNull_(map) { return Object.keys(map).filter(function (k) { return !map[k]; }).length; }
function ilh_pad_(n) { return ('0000' + n).slice(-4); }
function ilh_num_(v) { return (v === null || v === undefined || v === '') ? null : Number(v); }
function ilh_bool_(v) { return (v === null || v === undefined || v === '') ? null : String(v).toLowerCase() === 'true'; }
