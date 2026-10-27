// ImsLoadOpening.gs 시험 — node run-opening.js [main|guard] · ilo-zero-1(회계 0 처리 목록 거르기 · 가드) — Build(ilo_build_ · iloBuild)만 · Cin7 · Drive · Supabase 호출 0
// ⚠️ 창구(so_opening_load)는 안 부른다 — Dry · Apply 는 실물 REST 로만(reload-procedure §P-2 12b)
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const scenario = process.argv[2] || 'main';
const fake = makeFakeGas({ mode: 'emu', db: {}, props: { SUPABASE_IMS_URL: 'https://fazgmyvzzhqybtvtktyg.supabase.co', SUPABASE_IMS_SERVICE_KEY: 'k', CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x' } });
Object.assign(global, fake.globals);
// fake-gas 에 없는 것 — md5(ilo_md5_) · 실제 값은 쓰지 않는다(길이만 맞으면 된다)
Utilities.computeDigest = (alg, text) => { const h = require('crypto').createHash('md5').update(String(text), 'utf8').digest(); return Array.from(h).map(b => (b > 127 ? b - 256 : b)); };
Utilities.DigestAlgorithm = { MD5: 'md5' }; Utilities.Charset = { UTF_8: 'utf8' };
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '..', 'ImsLoadOpening.gs'), 'utf8'), { filename: 'ImsLoadOpening.gs' });

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
const r2 = v => Math.round(v * 100) / 100;
function section(name) { console.log('\n── ' + name + ' ──'); }

// ── 재료 — 목록 19 장을 ilo_zeroDocs_ 자체에서 만든다(보고서 원문 = Cin7 수집이 맞는 경우) + 그대로 남아야 할 것들 ──
let seq = 0;
function sale(so, customer, cur, invs, listPaidOverride) {         // invs: [{num, total, paid, status?}] → {list, detail}
  const id = 'SALE-' + (++seq), live = invs.filter(v => !/VOIDED|DRAFT/.test(v.status || 'AUTHORISED'));
  const totalSum = r2(live.reduce((a, v) => a + v.total, 0)), paidSum = r2(live.reduce((a, v) => a + v.paid, 0));
  const list = { SaleID: id, OrderNumber: so, Customer: customer, CustomerID: 'CUST-' + customer.replace(/\W/g, '').slice(0, 12), CustomerCurrency: cur, InvoiceNumber: invs[0].num, Status: 'COMPLETED', CombinedInvoiceStatus: 'INVOICED', CombinedPaymentStatus: 'PAID',
    SaleInvoicesTotalAmount: totalSum, CombinedPaymentTotal: listPaidOverride === undefined ? paidSum : listPaidOverride };
  const detail = { ID: id, CustomerID: list.CustomerID, CustomerCurrency: cur, Terms: '30 days', CreditNotes: [],
    Invoices: invs.map((v, i) => ({ TaskID: 'TASK-' + id + '-' + i, InvoiceNumber: v.num, Status: v.status || 'AUTHORISED', InvoiceDate: '2026-03-01T00:00:00', InvoiceDueDate: '2026-03-31T00:00:00', Total: v.total, Paid: v.paid, Tax: r2(v.total * 0.13 / 1.13), TotalBeforeTax: r2(v.total / 1.13) })) };
  return { list, detail };
}
function build(scn) {
  const open = [], overpay = [], credited = [], details = [];
  const push = (kind, x) => { (kind === 'open' ? open : kind === 'overpay' ? overpay : credited)[kind === 'credited' ? 'push' : 'push'](x.list); if (kind !== 'credited') details.push(x); };
  if (scn === 'main') {
    ilo_zeroDocs_().forEach(z => {
      if (z.so === 'SO-10447') push('open', sale(z.so, z.to, 'CAD', [{ num: z.doc, total: z.total, paid: z.total }], 0));   // 목록 Paid 0 · 상세 Paid = Total
      else if (z.due > 0) push('open', sale(z.so, z.to, 'CAD', [{ num: z.doc, total: z.total, paid: z.paid }]));
      else push('overpay', sale(z.so, z.to, 'CAD', [{ num: z.doc, total: z.total, paid: z.paid }]));
    });
  }
  // 그대로 남아야 할 것
  push('open', sale('SO-90001', 'Beauty Collection Brampton Inc.', 'CAD', [{ num: '90001', total: 100, paid: 0 }]));                       // 같은 손님의 다른 인보이스
  push('open', sale('SO-90002', 'Two Invoice Shop', 'CAD', [{ num: '90002', total: 50, paid: 0 }, { num: '90003', total: 70, paid: 20 }, { num: '90004', total: 9, paid: 0, status: 'VOIDED' }]));
  push('open', sale('SO-90005', 'US Shop', 'USD', [{ num: '90005', total: 300, paid: 100 }]));
  push('overpay', sale('SO-90006', 'Overpay Shop', 'CAD', [{ num: '90006', total: 10, paid: 15 }]));
  const credits = [
    { CreditID: 'C1', CustomerID: 'CUST-RoyalsBeauty', CustomerName: 'Royals Beauty Supply', Currency: 'CAD', RemainingAmount: 217.80, Description: 'Credit note <a href="x">CR-00283</a>', Date: '2026-09-01T00:00:00' },
    { CreditID: 'C2', CustomerID: 'CUST-RoyalsBeauty', CustomerName: 'Royals Beauty Supply', Currency: 'CAD', RemainingAmount: 12.01, Description: 'CR-00282', Date: '2026-09-02T00:00:00' },
    { CreditID: 'C3', CustomerID: 'CUST-X', CustomerName: 'Used Up', Currency: 'CAD', RemainingAmount: 0, Description: 'gone', Date: '2026-09-02T00:00:00' }
  ];
  if (scn === 'guard') {
    push('open', sale('SO-80001', 'Guard SO Differs', 'CAD', [{ num: '80001', total: 100, paid: 10 }]));                                   // 목록은 SO-80009 라 한다
    push('open', sale('SO-80002', 'Guard Due Differs', 'CAD', [{ num: '80002', total: 100, paid: 10 }]));                                  // 목록 Due 50
    push('open', sale('SO-80003', 'Guard Total Differs', 'CAD', [{ num: '80003', total: 100, paid: 10 }]));                                // 목록 Total 99
    push('credited', sale('SO-80004', 'Guard Credited', 'CAD', [{ num: '80004', total: 100, paid: 110 }]));                                // CREDITED → 후보 아님
    push('overpay', sale('SO-80005', 'Guard Multi Overpay', 'CAD', [{ num: '80005', total: 100, paid: 130 }, { num: '80006', total: 20, paid: 0 }]));   // overpay 인데 live 둘
    push('open', sale('SO-80007', 'Guard Fine', 'CAD', [{ num: '80007', total: 100, paid: 10 }]));                                         // 맞는 줄
    global.ilo_zeroDocs_ = () => [
      { so: 'SO-80000', doc: '80000', to: 'Guard Missing', total: 1, paid: 0, due: 1, color: 'orange' },
      { so: 'SO-80009', doc: '80001', to: 'Guard SO Differs', total: 100, paid: 10, due: 90, color: 'orange' },
      { so: 'SO-80002', doc: '80002', to: 'Guard Due Differs', total: 100, paid: 50, due: 50, color: 'orange' },
      { so: 'SO-80003', doc: '80003', to: 'Guard Total Differs', total: 99, paid: 10, due: 89, color: 'orange' },
      { so: 'SO-80004', doc: '80004', to: 'Guard Credited', total: 100, paid: 110, due: -10, color: 'blue' },
      { so: 'SO-80005', doc: '80005', to: 'Guard Multi Overpay', total: 100, paid: 130, due: -30, color: 'blue' },
      { so: 'SO-80007', doc: '80007', to: 'Guard Fine', total: 100, paid: 10, due: 90, color: 'orange' }
    ];
  }
  const stats = { sales: open.length + overpay.length + credited.length, voided: 0, open: open.length, open_customers: 0, open_by_cur: {}, open_blank_number: 0, open_status_pairs: [], overpay: overpay.length, overpay_customers: 0, overpay_by_cur: {}, overpay_credited: credited.length, overpay_credited_by_cur: {}, overpay_status: [] };
  return { cand: { open, overpay, credited, stats }, details, credits };
}

const F = build(scenario), cfg = ilo_cfg_();
if (scenario === 'main') {
  section('ilo_build_ — 19 장 거르기');
  const res = ilo_build_(F.cand, F.details, F.credits, '2026-11-01', cfg), z = res.summary.zeroed, inv = res.p.invoices, cr = res.p.credits;
  console.log(res.report.split('\n').slice(0, 30).join('\n'));
  ok(z.problems.length === 0, '가드 문제 0');
  ok(z.list_count === 19 && z.rows.length === 19, '목록 19');
  ok(z.excluded.invoices.count === 6 && z.excluded.invoices.by_currency.CAD.remaining === 1059.35, '빠진 인보이스 6 장 · CAD 남은 Σ 1059.35 : ' + JSON.stringify(z.excluded.invoices.by_currency));
  ok(z.excluded.overpay.count === 12 && z.excluded.overpay.by_currency.CAD.amount === 2374.78, '빠진 overpay 12 줄 · CAD Σ 2374.78 : ' + JSON.stringify(z.excluded.overpay.by_currency));
  ok(z.no_line.length === 1 && z.no_line[0] === 'SO-10447 44585', '줄 없음 = SO-10447 44585(상세 Due 0 · 목록으로 맞춤) : ' + z.no_line.join(','));
  ok(z.rows.find(r => r.so === 'SO-10447').matched.indexOf('목록') === 0, 'SO-10447 은 「목록」으로 맞춘다 : ' + z.rows.find(r => r.so === 'SO-10447').matched);
  ok(res.summary.mismatch.length === 0, '어긋난 sale 0(SO-10447 면제)');
  ok(z.waived.length === 1 && z.waived[0].order === 'SO-10447', '면제된 대조 1 = SO-10447');
  ok(!res.summary.blocked, 'Apply 안 막힘');
  const zeroDocs = ilo_zeroDocs_().map(x => x.doc);
  ok(inv.every(v => zeroDocs.indexOf(v.invoice_number) < 0), '인보이스 줄에 목록 번호 없음');
  ok(inv.length === 4 && inv.map(v => v.invoice_number).sort().join(',') === '90001,90002,90003,90005', '남은 인보이스 4(90001 · 90002 · 90003 · 90005) : ' + inv.map(v => v.invoice_number).join(','));
  ok(res.summary.invoices.by_currency.CAD.count === 3 && res.summary.invoices.by_currency.CAD.remaining === 200 && res.summary.invoices.by_currency.USD.remaining === 200, '통화별 Σ 남은: CAD 3 장 200 · USD 200');
  ok(cr.filter(c => c.source === 'overpay').length === 1 && cr.find(c => c.source === 'overpay').reference.indexOf('SO-90006') === 0, 'overpay 줄은 SO-90006 하나만');
  ok(cr.filter(c => c.source === 'credit').length === 2 && r2(cr.filter(c => c.source === 'credit').reduce((a, c) => a + c.amount, 0)) === 229.81, 'Royals 손님 크레딧 둘(229.81) 그대로');
  ok(res.summary.credits.by_currency.CAD.amount === 234.81 && res.summary.credits.overpay_rows === 1, '받아 둔 돈 CAD 234.81 · overpay_rows 1');
  ok(res.report.indexOf('0z. ⭐ 회계에서 0 처리 · 제외 19') > 0 && res.report.indexOf('0z.') < res.report.indexOf('0. 원천'), '보고서 0z 표가 0. 원천 앞');
  ok(res.report.indexOf('회계 0 처리 19 장을 뺀 뒤 숫자') > 0, 'Caleb 대조표에 제외 뒤 숫자 안내');
  ok(res.report.indexOf('SO-12562 2,278.13 은 회계 0 처리 목록') > 0, 'Royals 문구 갱신');

  section('iloBuild — Drive 가짜 · build json · report');
  fake.props.ILO_STATE = JSON.stringify({ folderId: 'F1', salesDone: true, creditsDone: true, candDone: true, detailDone: true, buildFile: 'build-old.json', buildMd5: 'old' });
  const drive = [{ name: 'candidates.json', text: JSON.stringify(F.cand) }, { name: 'detail-0001-0030.json', text: JSON.stringify(F.details) }, { name: 'credits-p0001.json', text: JSON.stringify(F.credits) }];
  const fk2 = makeFakeGas({ mode: 'emu', db: {}, driveFiles: drive, props: fake.props });
  global.DriveApp = fk2.globals.DriveApp; global.PropertiesService = fk2.globals.PropertiesService; global.Logger = fk2.globals.Logger;
  iloBuild();
  const st = JSON.parse(fk2.props.ILO_STATE), bj = fk2.reports.find(r => /^build-.*\.json$/.test(r.name)), rb = fk2.reports.find(r => /^report-build-/.test(r.name));
  ok(!!bj && !!rb && st.buildFile === bj.name && st.dryMd5 === null, 'build json · report-build 저장 · 상태 buildFile 갱신 · dryMd5 비움 : ' + (bj && bj.name));
  ok(st.buildMismatch === 0 && st.buildBlocked === false, '상태 buildMismatch 0 · buildBlocked false');
  const pj = JSON.parse(bj.text);
  ok(pj.p.invoices.length === 4 && pj.p.credits.length === 3 && pj.summary.zeroed.list_count === 19, 'build json 의 p: 인보이스 4 · 받아 둔 돈 3 · summary.zeroed 있음');
  ok(/회계 0 처리 제외 6 장 \+ overpay 12 줄 · 어긋난 sale 0/.test(fk2.logs.join('\n')), '로그 끝줄에 제외 수 · 어긋난 sale 0');
} else {
  section('ilo_build_ — 가드(문제 6 · 맞는 줄 1)');
  const res = ilo_build_(F.cand, F.details, F.credits, '2026-11-01', cfg), z = res.summary.zeroed;
  console.log(res.report.split('\n').slice(0, 16).join('\n'));
  const kinds = z.problems.map(r => r.problem.split(' ')[0]);
  ok(z.problems.length === 6, '문제 6 : ' + kinds.join(','));
  ok(kinds.join(',') === 'not_in_collection,so_differs,due_differs,total_differs,not_in_collection,multi_invoice', '종류 순서대로: ' + kinds.join(','));
  ok(/CREDITED/.test(z.problems[4].problem), 'credited 는 메시지로 구분');
  ok(z.excluded.invoices.count === 1 && z.rows.find(r => r.so === 'SO-80007').where === '인보이스', '맞는 줄 SO-80007 은 인보이스에서 빠진다');
  ok(res.summary.blocked === true, 'blocked');

  section('iloBuild — 멈춤 · build json 없음 · 옛 Build 지움');
  const drive = [{ name: 'candidates.json', text: JSON.stringify(F.cand) }, { name: 'detail-0001-0030.json', text: JSON.stringify(F.details) }, { name: 'credits-p0001.json', text: JSON.stringify(F.credits) }];
  fake.props.ILO_STATE = JSON.stringify({ folderId: 'F1', salesDone: true, creditsDone: true, candDone: true, detailDone: true, buildFile: 'build-old.json', buildMd5: 'old', dryMd5: 'old' });
  const fk2 = makeFakeGas({ mode: 'emu', db: {}, driveFiles: drive, props: fake.props });
  global.DriveApp = fk2.globals.DriveApp; global.PropertiesService = fk2.globals.PropertiesService; global.Logger = fk2.globals.Logger;
  let err = null; try { iloBuild(); } catch (e) { err = e; }
  ok(err && /⛔ 멈춤 — 회계 0 처리 목록\(ilo_zeroDocs_\) 6 줄/.test(err.message) && /SO-80000 80000 Guard Missing — not_in_collection/.test(err.message), '멈춤 메시지에 수와 이름 : ' + (err && err.message.slice(0, 120)));
  const st = JSON.parse(fk2.props.ILO_STATE);
  ok(st.buildFile === null && st.buildMd5 === null && st.dryMd5 === null, '옛 buildFile · md5 · dryMd5 지움(Dry 가 못 돈다)');
  ok(!fk2.reports.some(r => /^build-.*\.json$/.test(r.name)) && fk2.reports.some(r => /^report-build-blocked-/.test(r.name)), 'build json 없음 · report-build-blocked 있음');
  let err2 = null; try { iloDry(); } catch (e) { err2 = e; }
  ok(err2 && /Build 파일이 없다/.test(err2.message), '그 뒤 iloDry 는 「Build 파일이 없다」 로 멈춘다 : ' + (err2 && err2.message));
}
console.log('\n' + (fails.length ? '❌ 실패 ' + fails.length + ' : ' + fails.join(' | ') : '⭐ 단언 전부 통과'));
process.exit(fails.length ? 1 : 0);
