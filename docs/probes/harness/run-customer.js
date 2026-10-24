// ImsLoadCustomer.gs 시험 — node run-customer.js [emu|local] [main|dup|exists] · ldfix-1a
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const fx = require('./fixtures/customer');
const mode = process.argv[2] || 'emu', scenario = process.argv[3] || 'main';
const F = fx.build(scenario), U = fx.U, C = fx.C;
const LAST_APPLY = '2026-10-20T00:00:00.000Z';
const fake = makeFakeGas({
  mode, db: F.db,
  props: { SUPABASE_IMS_URL: mode === 'local' ? (process.env.SUPABASE_IMS_URL || 'http://127.0.0.1:54321') : 'http://emu', SUPABASE_IMS_SERVICE_KEY: mode === 'local' ? process.env.SUPABASE_IMS_SERVICE_KEY : 'k',
           CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x', ILC_DONE: '1', ILC_FOLDER_ID: 'folder', ILC_TOTAL: String(F.raw.length), ILC_LAST_APPLY_AT: LAST_APPLY },
  driveFiles: [{ name: 'pages-0001-0001.json', text: JSON.stringify(F.raw) }]
});
Object.assign(global, fake.globals);
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '..', 'ImsLoadCustomer.gs'), 'utf8'), { filename: 'ImsLoadCustomer.gs' });

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
const report = tag => { const r = fake.reports.filter(x => x.name.startsWith('report-' + tag + '-')); return r.length ? r[r.length - 1].text : ''; };
const reqs = (m, re) => fake.requests.filter(r => r.method === m && re.test(r.path));
const mark = () => fake.requests.length;
const since = n => fake.requests.slice(n);
const dbRow = (t, id) => (fake.db[t] || []).find(r => r.id === id);

function section(name) { console.log('\n── ' + name + ' ──'); }

if (scenario !== 'main') {
  section('Dry — 멈춤 조건 (' + scenario + ')');
  let err = null;
  try { imsLoadCustomerDry(); } catch (e) { err = e; }
  ok(err && /멈춤 조건/.test(err.message), '멈춘다: ' + (err ? err.message : '(안 멈춤)'));
  const stop = report('stop');
  ok(scenario === 'dup' ? /같은 이름이 둘 이상이라 짝짓지 못한다.*Dup Name/.test(stop) : /이미 cin7 행으로 있다.*Exists Co/.test(stop), '멈춤 보고 문구');
  ok(fake.requests.every(r => r.method === 'get'), '쓰기 요청 0 (전부 get): ' + fake.requests.map(r => r.method).join(','));
  console.log('\n[stop 보고]\n' + stop);
  finish();
}

section('Dry');
imsLoadCustomerDry();
const dry = report('dry');
console.log(dry);
ok(fake.requests.every(r => r.method === 'get'), 'Dry 는 쓰기 0');
ok(/짝지은 IMS 손님\(판정 674\) 이번 1 · 이미 짝지어진 1 → Cin7 행 건너뜀 2 · 주소 3 · 연락처 1/.test(dry), '머리: 짝짓기 1 · 이미 1 · 건너뜀 2/3/1');
ok(/2단계\(109\) 이을 것 1 · 건너뜀 IMS 가 정한 관계 7\(세움 6 · 뗌 1 · Cin7 부모와 다른 것 2\) · 짝지은 손님 1/.test(dry), '머리: 2단계 1 · IMS 관계 7(세움 6 · 뗌 1 · 다른 것 2) · 짝지은 1');
ok(/손댄 행\(672 · 적재가 덮는다\) 손님 9 · 주소 1 · 연락처 0 · 어긋남 7/.test(dry), '머리: 손댄 행 9/1/0 · 어긋남 7(Clore 6 시각 앞 + Stale ByNull 1)');
ok(/Kid Detached : IMS 부모 「\(없음\)」 ≠ Cin7 부모 「Par A」/.test(dry), '109 · 678 목록: Kid Detached(뗌) ≠ Cin7 부모 Par A');
ok(/TEST IMS Shopify ← cin7_id c0000000-0000-4000-8000-000000000007 · 값이 다른 칸 .*price_tier: IMS="Retail" Cin7="Wholesale"/.test(dry), '674 목록: 짝 + 다른 칸(price_tier)');
ok(/Clore Inc\. \(OTT\) : IMS 부모 「Other Parent」 ≠ Cin7 부모 「Clore Inc\.」/.test(dry), '109 목록: OTT 의 IMS 부모 ≠ Cin7 부모');
ok(/customer Touched Co \(IMS edit\) .* — 덮임: name: IMS="Touched Co \(IMS edit\)" Cin7="Touched Co"/.test(dry), '672: Touched Co 이름 덮임');
ok(/customer Touched Gone .* — 덮이지 않음\(이번 Cin7 에 없음\)/.test(dry), '672: Touched Gone 덮이지 않음');
ok(/customer Clore Inc\. \(BLW\) .* — 덮여도 값 그대로/.test(dry), '672: Clore BLW 덮여도 값 그대로');
ok(/customer_address Line 3 IMS .* — 덮임: line1: IMS="Line 3 IMS" Cin7="Line 3 CIN7"/.test(dry), '672: 주소 line1 덮임');
ok(/⚠️ customer — 적재 시각 뒤에 바뀌었는데 updated_by 가 없는 행 1/.test(dry), '672 보조: Stale ByNull 어긋남');
ok(/보낼 행 — 손님 15\(활성 15\) · 주소 2 · 연락처 1 · 부모 잇기 1 \/ Cin7 부모 있는 손님 9/.test(dry), '보낼 행 15 · 주소 2 · 연락처 1 · 잇기 1/9');

section('Apply1');
let m = mark(); imsLoadCustomerApply1(); const a1 = since(m);
console.log(report('apply1'));
const pair = a1.filter(r => r.method === 'patch' && r.path === '/rest/v1/customer?id=eq.' + U(51) + '&cin7_id=is.null');
ok(pair.length === 1 && JSON.stringify(pair[0].body) === JSON.stringify({ cin7_id: C(7) }), '674 PATCH: id=eq.U51&cin7_id=is.null {cin7_id: C7} 만');
const up = a1.filter(r => r.method === 'post' && r.path === '/rest/v1/customer?on_conflict=cin7_id');
const upRows = up.reduce((a, r) => a.concat(r.body), []);
ok(up.length === 1 && upRows.length === 15, 'upsert 한 요청 · 15 행 (실제 ' + up.length + ' · ' + upRows.length + ')');
ok(!upRows.some(r => r.cin7_id === C(7) || r.cin7_id === C(8)), 'upsert 에 짝지은 손님(C7 · C8) 없음');
ok(upRows.every(r => !('parent_id' in r) && !('parent_source' in r) && !('id' in r) && !('note' in r) && !('default_bill_to_customer_id' in r)), 'upsert 가 parent_id · parent_source · id · note · bill_to 를 보내지 않는다');
ok(pair.length && up.length && a1.indexOf(pair[0]) < a1.indexOf(up[0]), '674 PATCH 가 upsert 보다 앞');
const down1 = a1.filter(r => r.method === 'patch' && /customer\?cin7_id=in\./.test(r.path));
ok(down1.length === 1 && down1[0].path === '/rest/v1/customer?cin7_id=in.(' + C(10) + ',' + C(17) + ')' && JSON.stringify(down1[0].body) === '{"is_active":false}', '내리기 PATCH: C10 · C17 {is_active:false}');
ok(fake.props.ILC_LAST_APPLY_AT > LAST_APPLY, 'ILC_LAST_APPLY_AT 갱신: ' + fake.props.ILC_LAST_APPLY_AT);
if (mode === 'emu') {
  ok(dbRow('customer', U(51)).cin7_id === C(7) && dbRow('customer', U(51)).price_tier === 'Retail' && dbRow('customer', U(51)).source === 'manual', 'emu: IMS 손님에 cin7_id 만 · price_tier Retail · source manual 그대로');
  ok(dbRow('customer', U(9)).name === 'Touched Co', 'emu: Touched Co 이름이 Cin7 값으로(672)');
  ok(dbRow('customer', U(11)).parent_source === 'ims' && dbRow('customer', U(11)).parent_id === U(1), 'emu: Clore 자식 부모 · parent_source 그대로');
  ok(dbRow('customer', U(10)).is_active === false && dbRow('customer', U(17)).is_active === false, 'emu: C10 · C17 내려짐');
}

section('Apply2');
m = mark(); imsLoadCustomerApply2(); const a2 = since(m);
console.log(report('apply2'));
const link = a2.filter(r => r.method === 'patch' && /customer\?id=eq\./.test(r.path));
ok(link.length === 1 && link[0].path === '/rest/v1/customer?id=eq.' + U(4) && JSON.stringify(link[0].body) === JSON.stringify({ parent_id: U(3), parent_source: 'cin7' }), '잇기 PATCH: Kid A 하나 · {parent_id: Par A, parent_source: cin7}');
const clear = a2.filter(r => r.method === 'patch' && /customer\?cin7_id=in\./.test(r.path));
ok(clear.length === 1 && clear[0].path === '/rest/v1/customer?cin7_id=in.(' + C(5) + ')' && JSON.stringify(clear[0].body) === '{"parent_id":null}', '비우기 PATCH: Kid Gone 하나 {parent_id:null}');
ok(a2.some(r => r.method === 'get' && /source=eq\.cin7&parent_source=eq\.cin7&parent_id=not\.is\.null/.test(r.path)), '비우기 후보 읽기가 parent_source=eq.cin7 로 좁힌다');
ok(/건너뜀 — IMS 가 정한 관계 7\(세움 6 · 뗌 1 · 미룬 109 · 판정 678\) · 짝지은 IMS 손님 1\(판정 674\)/.test(report('apply2')), 'apply2 로그: 건너뜀 7(세움 6 · 뗌 1) · 1');
ok(link.length === 1 && !link.some(r => r.path === '/rest/v1/customer?id=eq.' + U(19)), '잇기 PATCH 에 Kid Detached(뗌) 없음');
ok(/청구처가 옛 부모라 함께 비워진 손님 1/.test(report('apply2')), 'apply2 로그: 청구처 함께 비움 1');
if (mode === 'emu') {
  const kg = dbRow('customer', U(5)), ki = dbRow('customer', U(6)), ott = dbRow('customer', U(16));
  ok(kg.parent_id === null && kg.parent_source === null && kg.default_bill_to_customer_id === null, 'emu: Kid Gone 부모 · parent_source · 청구처 비움(판정 256 · 규칙 4)');
  ok(ki.parent_id === U(2) && ki.parent_source === 'ims', 'emu: Kid ImsOnly 그대로');
  ok(ott.parent_id === U(2) && ott.parent_source === 'ims', 'emu: Clore (OTT) IMS 부모 그대로(IMS 가 이긴다)');
  ok(dbRow('customer', U(4)).parent_id === U(3) && dbRow('customer', U(4)).parent_source === 'cin7', 'emu: Kid A 이어짐 · cin7');
  ok(dbRow('customer', U(19)).parent_id === null && dbRow('customer', U(19)).parent_source === 'ims', 'emu: Kid Detached 그대로(null · ims · 판정 678)');
}

section('Apply3 · Apply4');
m = mark(); imsLoadCustomerApply3(); const a3 = since(m);
console.log(report('customer_address'));
const upA = a3.filter(r => r.method === 'post'); const rowsA = upA.reduce((a, r) => a.concat(r.body), []);
ok(upA.length === 1 && rowsA.length === 2 && rowsA.every(r => r.customer_id === U(4)), '주소 upsert 2 행 · Kid A 것만');
ok(!rowsA.some(r => [C(107), C(108), C(110)].indexOf(r.cin7_id) >= 0), '짝지은 손님의 Cin7 주소(C107 · C108 · C110) 없음');
const downA = a3.filter(r => r.method === 'patch');
ok(downA.length === 1 && downA[0].path === '/rest/v1/customer_address?cin7_id=in.(' + C(109) + ')' && downA[0].body.is_active === false && downA[0].body.is_default_for_type === false, '주소 내리기: Gone Active 의 주소 하나 · 기본도 풂');
ok(/건너뜀 3\(판정 674/.test(report('customer_address')), 'apply3 로그: 건너뜀 3');
m = mark(); imsLoadCustomerApply4(); const a4 = since(m);
console.log(report('customer_contact'));
const upK = a4.filter(r => r.method === 'post'); const rowsK = upK.reduce((a, r) => a.concat(r.body), []);
ok(upK.length === 1 && rowsK.length === 1 && rowsK[0].cin7_id === C(201) && rowsK[0].customer_id === U(4), '연락처 upsert 1 행 · Kid A');
ok(/건너뜀 1\(판정 674/.test(report('customer_contact')), 'apply4 로그: 건너뜀 1');
if (mode === 'emu') {
  ok(dbRow('customer_address', U(103)).line1 === 'Line 3 CIN7', 'emu: 손댄 주소가 Cin7 값으로(672)');
  ok(dbRow('customer_address', U(151)).is_default_for_type === true && dbRow('customer_address', U(152)).is_default_for_type === true, 'emu: IMS 손님의 manual 주소 그대로');
  ok(!fake.db.customer_address.some(r => r.cin7_id === C(107) || r.cin7_id === C(108)), 'emu: 짝지은 손님의 Cin7 주소 행 없음');
}

section('Verify');
m = mark(); imsLoadCustomerVerify();
const v = report('verify'); console.log(v);
ok(/⭐ 전부 일치/.test(v), 'Verify 전부 일치');
ok(/customer 부모 있음\(parent_source=cin7\) : DB 1 · Cin7 기준 1/.test(v), 'Verify 부모 cin7 1');
ok(/\(IMS 가 정한 관계 — 세운 부모 7 · 뗀 것 1 — 대조하지 않는다/.test(v), 'Verify IMS 관계 세움 7(Clore 6 + Kid ImsOnly) · 뗌 1(Kid Detached) 따로');

function finish() {
  console.log('\n── 요청 ' + fake.requests.length + ' 건 (method path [body 행 수]) ──');
  fake.requests.forEach(r => console.log('  ' + r.method.toUpperCase().padEnd(5) + ' ' + r.path + (r.body ? ' [' + (Array.isArray(r.body) ? r.body.length : 'obj') + ']' : '')));
  console.log('\n' + (fails.length ? '❌ 실패 ' + fails.length + ' : ' + fails.join(' | ') : '⭐ 단언 전부 통과'));
  process.exit(fails.length ? 1 : 0);
}
finish();
