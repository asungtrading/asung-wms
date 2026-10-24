// ImsLoadSupplier.gs · ImsLoadProductSupplier.gs 시험 — node run-supplier.js [emu|local] [main|conflict] · ldfix-1c
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const fx = require('./fixtures/supplier');
const mode = process.argv[2] || 'emu', scenario = process.argv[3] || 'main';
const F = fx.build(scenario), U = fx.U, C = fx.C;
const fake = makeFakeGas({
  mode, db: F.db, cin7: { supplier: F.supplier, product: [], productFamily: [] }, sheets: { ips_line: F.sheet },
  props: { SUPABASE_IMS_URL: mode === 'local' ? (process.env.SUPABASE_IMS_URL || 'http://127.0.0.1:54321') : 'http://emu', SUPABASE_IMS_SERVICE_KEY: mode === 'local' ? process.env.SUPABASE_IMS_SERVICE_KEY : 'k',
           CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x', ILS_LAST_APPLY_AT: '2026-10-20T00:00:00.000Z', IPS_SHEET_ID: 'sheet' }
});
Object.assign(global, fake.globals);
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
['ImsLoadProduct.gs', 'ImsLoadProductSupplier.gs', 'ImsLoadSupplier.gs'].forEach(f => vm.runInThisContext(fs.readFileSync(path.join(__dirname, '..', f), 'utf8'), { filename: f }));

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
const mark = () => fake.requests.length, since = n => fake.requests.slice(n);
const logMark = () => fake.logs.length, logsSince = n => fake.logs.slice(n).join('\n');
const dbRow = (t, pred) => (fake.db[t] || []).find(pred);
const posts = (reqs, re) => reqs.filter(r => r.method === 'post' && re.test(r.path)), patches = (reqs, re) => reqs.filter(r => r.method === 'patch' && re.test(r.path));
const rd = (p) => JSON.parse(ims_fetch_(p, { method: 'get' }).getContentText());
function section(name) { console.log('\n── ' + name + ' ──'); }
function finish() {
  console.log('\n── 요청 ' + fake.requests.length + ' 건 ──');
  fake.requests.forEach(r => console.log('  ' + r.method.toUpperCase().padEnd(5) + ' ' + r.path.replace(/^https?:\/\/[^/]+/, '') + (r.body ? ' [' + (Array.isArray(r.body) ? r.body.length : 'obj') + ']' : '')));
  console.log('\n' + (fails.length ? '❌ 실패 ' + fails.length + ' : ' + fails.join(' | ') : '⭐ 단언 전부 통과'));
  process.exit(fails.length ? 1 : 0);
}

if (scenario === 'conflict') {
  section('Apply — 이름 겹침(23505 사전 검사) → 멈춤');
  let err = null; const m0 = mark();
  try { imsLoadSupplierApply(); } catch (e) { err = e; }
  ok(err && /멈춤/.test(err.message), '멈춘다: ' + (err ? err.message : '(안 멈춤)'));
  ok(since(m0).every(r => r.method === 'get'), '쓰기 요청 0');
  ok(/이름 겹침\(23505\): Cin7 "Supplier S6 Gone"\(cin7_id c0000000-0000-4000-8000-000000000001\) 이 우리 표의 다른 행 "Supplier S6 Gone"/.test(fake.logs.join('\n')), '로그: 이름 겹침 문구');
  finish();
}

section('본 행 Dry');
let lm = logMark(); let m = mark(); imsLoadSupplier(); let L = logsSince(lm); let a = since(m);
console.log(L);
ok(a.every(r => r.method === 'get'), 'Dry 는 쓰기 0');
ok(/보낼 행 4 = 갱신 3 \+ 새 행 1 · 새 비활성\(안 넣음\) 1 · Cin7 활성 3/.test(L), 'Dry: 보낼 4 = 갱신 3 + 새 1 · 새 비활성 1');
ok(/짝지은 IMS 공급처\(674 · 681 · cin7_id 만\) 이번 1 · 이미 짝지어진\(안 보냄\) 0 · 손댄 행\(672 · Cin7 이 덮는다\) 1 · is_active IMS 값 유지\(680\) 1 · Cin7 에 없어 내릴 행 1/.test(L), 'Dry: 짝 1 · 손댄 1 · 680 1 · 내림 1');
ok(/\[674 짝\] "TEST Supplier-Canada" ← cin7_id c0000000-0000-4000-8000-000000000005 · 값이 다른 칸 name: IMS="TEST Supplier-Canada" Cin7="​TEST Supplier-Canada"/.test(L), '681: U+200B 가 붙은 Cin7 이름과 짝(이름 차이는 목록에)');
ok(/\[680 is_active 는 IMS 값 유지\] Supplier S2 \(IMS edit\) : IMS true \(Cin7 false\)/.test(L), '680 · 683: S2 is_active IMS true 유지(is_active_source ims)');
ok(/\[672 손댄 행\] Supplier S2 \(IMS edit\) .* — 덮임: name: IMS="Supplier S2 \(IMS edit\)" Cin7="Supplier S2"/.test(L) && !/is_active: IMS/.test(L), '672: S2 이름 덮임 · is_active 는 차이에 없음');
ok(/\[내림\] Supplier S6 Gone/.test(L), '내릴 행 S6');

section('본 행 Apply');
lm = logMark(); m = mark(); imsLoadSupplierApply(); L = logsSince(lm); a = since(m);
const pr = patches(a, /supplier\?id=eq\.00000000-0000-4000-8000-000000000205&cin7_id=is\.null$/);
ok(pr.length === 1 && JSON.stringify(pr[0].body) === JSON.stringify({ cin7_id: C(5) }), '674 PATCH: TEST Supplier-Canada 에 cin7_id 만');
const up = posts(a, /\/supplier\?on_conflict=cin7_id/); const rows = up.reduce((x, r) => x.concat(r.body), []);
ok(up.length === 1 && rows.length === 4 && rows.map(r => r.cin7_id).sort().join() === [C(1), C(2), C(3), C(7)].sort().join(), 'upsert 4(S1 · S2 · S3 · S7) · S4 · S5 없음');
ok(rows.find(r => r.cin7_id === C(2)).is_active === true && rows.find(r => r.cin7_id === C(2)).name === 'Supplier S2' && rows.find(r => r.cin7_id === C(7)).is_active === false, 'S2: is_active true(680) · name Cin7 값(672) · S7 false');
ok(rows.every(r => !('is_purchasable' in r) && !('is_discontinued' in r) && !('note' in r) && !('id' in r)), 'is_purchasable · is_discontinued · note · id 를 안 보낸다');
const dn = patches(a, /supplier\?cin7_id=in\./);
ok(dn.length === 1 && dn[0].path === '/rest/v1/supplier?cin7_id=in.(' + C(6) + ')' && dn[0].body.is_active === false, '내리기 PATCH: S6 만');
ok(fake.props.ILS_LAST_APPLY_AT > '2026-10-20T00:00:00.000Z', 'ILS_LAST_APPLY_AT 갱신');
const rc1 = a.filter(r => r.method === 'post' && /rpc\/product_supplier_default_recalc/.test(r.path));
ok(rc1.length === 1 && /\[682 기본 공급처 재계산\] 끔 1 · 켬 1 · 기본 둘 이상 0 \(all\)/.test(L), '682: Apply 끝 재계산 rpc 1 회 · 끔 1(P3 · S6 내려감) · 켬 1(P4 · S1) · 둘 이상 0');
if (mode === 'emu') ok(dbRow('product_supplier', r => r.id === U(606)).is_default === false && dbRow('product_supplier', r => r.id === U(607)).is_default === true, 'emu: P3 기본 꺼짐 · P4 기본 켜짐');
if (mode === 'emu') {
  ok(dbRow('supplier', r => r.id === U(205)).cin7_id === C(5) && dbRow('supplier', r => r.id === U(205)).name === 'TEST Supplier-Canada' && dbRow('supplier', r => r.id === U(205)).is_purchasable === true, 'emu: IMS 공급처 cin7_id 만 · 이름 원문 · purchasable 그대로');
  ok(dbRow('supplier', r => r.id === U(2)).name === 'Supplier S2' && dbRow('supplier', r => r.id === U(2)).is_active === true && dbRow('supplier', r => r.id === U(2)).updated_by === null, 'emu: S2 이름 Cin7 · 켜짐 IMS · updated_by 비움');
  ok(dbRow('supplier', r => r.cin7_id === C(3)) && !dbRow('supplier', r => r.cin7_id === C(4)) && dbRow('supplier', r => r.id === U(6)).is_active === false, 'emu: S3 새로 · S4 없음 · S6 내려짐');
}

section('본 행 Apply 2 회차(멱등 · 짝지은 행은 안 보냄)');
lm = logMark(); m = mark(); imsLoadSupplierApply(); L = logsSince(lm); a = since(m);
ok(/이번 0 · 이미 짝지어진\(안 보냄\) 1/.test(L) && /is_active IMS 값 유지\(680\) 1/.test(L), '2 회차: 짝 0 · 이미 짝지어진 1 · 680 · 683 1(칸 표식이라 남는다)');
const up2 = posts(a, /\/supplier\?on_conflict=cin7_id/).reduce((x, r) => x.concat(r.body), []);
ok(up2.length === 4 && !up2.some(r => r.cin7_id === C(5)) && up2.find(r => r.cin7_id === C(2)).is_active === true, '2 회차 upsert 4 · 짝지은 S5 없음 · ⭐ S2 켜짐이 남는다(판정 683)');
ok(/\[682 기본 공급처 재계산\] 끔 0 · 켬 0 · 기본 둘 이상 0/.test(L), '2 회차 재계산 멱등(끔 0 · 켬 0)');
ok(patches(a, /supplier\?id=eq\./).length === 0 && patches(a, /supplier\?cin7_id=in\./).length === 0, '2 회차: 짝짓기 PATCH 0 · 내리기 0');

section('주소 · 연락처 Dry · Apply');
lm = logMark(); m = mark(); imsLoadSupplierSub(); L = logsSince(lm); a = since(m);
console.log(L);
ok(a.every(r => r.method === 'get'), 'Sub Dry 는 쓰기 0');
ok(/보낼 줄 — 주소 1 · 연락처 1 · 거래 중단 표시라 건너뜀 1 · 짝지은 IMS 공급처의 Cin7 줄 건너뜀\(674\) 주소 1 · 연락처 1/.test(L), 'Sub: 주소 1 · 연락처 1 · 거래 중단 1 · 짝지은 공급처 줄 1/1 건너뜀');
ok(/\[672\] supplier_contact Contact 2 .* — 덮이지 않음\(이번 Cin7 에 없음\)/.test(L), '672: 손댄 연락처(S2 · Deprecated 라 이번에 없음) 목록');
ok(/Cin7 에 없어 내릴 supplier_address 1/.test(L) && /Cin7 에 없어 내릴 supplier_contact 1/.test(L), '내릴 줄: 주소 1(S6) · 연락처 1(S2)');
lm = logMark(); m = mark(); imsLoadSupplierSubApply(); L = logsSince(lm); a = since(m);
const dA = patches(a, /supplier_address\?cin7_id=in\./), dC = patches(a, /supplier_contact\?cin7_id=in\./), uA = posts(a, /supplier_address\?on_conflict=cin7_id/), uC = posts(a, /supplier_contact\?on_conflict=cin7_id/);
ok(dA.length === 1 && dA[0].path.indexOf(C(106)) > 0 && dC.length === 1 && dC[0].path.indexOf(C(202)) > 0 && dC[0].body.is_default === false, '내리기 PATCH: 주소 C106 · 연락처 C202(기본 풀기)');
ok(a.indexOf(dA[0]) < a.indexOf(uA[0]) && uA[0].body.length === 1 && uA[0].body[0].cin7_id === C(101) && uC[0].body.length === 1 && uC[0].body[0].cin7_id === C(201) && uC[0].body[0].is_active === true, '내리기가 upsert 보다 앞 · 주소 C101 · 연락처 C201 (is_active true)');
ok(!uA[0].body.some(r => r.cin7_id === C(105)) && !uC[0].body.some(r => r.cin7_id === C(205) || r.cin7_id === C(209)), '짝지은 공급처의 줄(C105 · C205) · 거래 중단 표시(C209) 없음');
if (mode === 'emu') ok(dbRow('supplier_contact', r => r.cin7_id === C(202)).is_active === false && dbRow('supplier_contact', r => r.id === U(251)).is_default === true && dbRow('supplier_address', r => r.cin7_id === C(106)).is_active === false, 'emu: C202 내려짐 · IMS 연락처 기본 그대로 · S6 주소 내려짐');

section('Verify');
lm = logMark(); imsLoadSupplierVerify(); L = logsSince(lm); console.log(L);
ok(/✅ supplier\(source=cin7\) 전체 = 이번에 보낼 행 \+ 내려 둔 행 : DB 5 · 기준 5/.test(L), 'Verify: cin7 행 5 = 보낼 4 + 내려 둔 1');
ok(/\(is_active 가 Cin7 상태와 다른 cin7 행 1 → Supplier S2\(IMS true\)/.test(L), 'Verify: Cin7 상태와 다른 행 1 = S2(683 으로 지킨 것 · 2 회차 뒤에도)');
ok(/⭐ 본 행 전부 일치/.test(L), 'Verify 본 행 일치');

section('제품↔공급처 Apply (ImsLoadProductSupplier.gs)');
lm = logMark(); m = mark(); imsLoadProductSupplierApply(); L = logsSince(lm); a = since(m);
console.log(L.split('\n').filter(l => /ldfix-1c|672|승격|쓰인/.test(l)).join('\n'));
const psUp = posts(a, /product_supplier\?on_conflict=cin7_id/).reduce((x, r) => x.concat(r.body), []);
ok(psUp.length === 2 && psUp.some(r => r.cin7_id === C(601)) && psUp.some(r => r.cin7_id === C(605)) && !psUp.some(r => r.cin7_id === C(603)), 'product_supplier upsert 2(C601 · C605 새) · IMS 가 끈 C603 없음');
const prm = patches(a, /product_supplier\?id=eq\.00000000-0000-4000-8000-000000000604$/);
ok(prm.length === 1 && JSON.stringify(prm[0].body) === JSON.stringify({ cin7_id: C(604) }), '승격 PATCH: cin7_id 만(cost · supplier_sku 안 보냄)');
ok(/보내지 않은 줄\(IMS 가 정한 Cin7 줄\) 1 · 손댄 cin7 줄을 덮음 1/.test(L) && /\[672 손댄 줄 · Cin7 이 덮는다\] P1 ← Supplier S1 .* — 덮임: cost: IMS=9.99 Cin7=1.5/.test(L), 'product_supplier 로그: 안 보냄 1 · 672 cost 덮임');
ok(a.filter(r => r.method === 'post' && /rpc\/product_supplier_default_recalc/.test(r.path)).length === 1 && /\[682 기본 공급처 재계산\] 끔 0 · 켬 (0|1) · 기본 둘 이상 0 \(all\)/.test(L), '682: 제품↔공급처 Apply 끝 재계산 rpc 1 회 · 둘 이상 0');
if (mode === 'emu') ok(dbRow('product_supplier', r => r.id === U(603)).cost === 7.77 && dbRow('product_supplier', r => r.id === U(603)).is_active === false && dbRow('product_supplier', r => r.id === U(604)).cin7_id === C(604) && dbRow('product_supplier', r => r.id === U(604)).cost === 5.55 && dbRow('product_supplier', r => r.id === U(604)).supplier_sku === 'IMS-SKU' && dbRow('product_supplier', r => r.id === U(601)).cost === 1.5, 'emu: C603 그대로 · 승격 줄 IMS 값 그대로 + cin7_id · 손댄 줄 Cin7 값');
finish();
