// ImsLoadProduct.gs 시험 — node run-product.js [emu|local] [main|conflict] · ldfix-1b
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const fx = require('./fixtures/product');
const mode = process.argv[2] || 'emu', scenario = process.argv[3] || 'main';
const F = fx.build(scenario), U = fx.U, C = fx.C;
const fake = makeFakeGas({
  mode, db: F.db, cin7: { product: F.product, productFamily: F.productFamily },
  props: { SUPABASE_IMS_URL: mode === 'local' ? (process.env.SUPABASE_IMS_URL || 'http://127.0.0.1:54321') : 'http://emu', SUPABASE_IMS_SERVICE_KEY: mode === 'local' ? process.env.SUPABASE_IMS_SERVICE_KEY : 'k',
           CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x', IPR_LAST_APPLY_AT: '2026-10-20T00:00:00.000Z' }
});
Object.assign(global, fake.globals);
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '..', 'ImsLoadProduct.gs'), 'utf8'), { filename: 'ImsLoadProduct.gs' });

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
const mark = () => fake.requests.length, since = n => fake.requests.slice(n);
const logMark = () => fake.logs.length, logsSince = n => fake.logs.slice(n).join('\n');
const dbRow = (t, pred) => (fake.db[t] || []).find(pred);
const posts = (reqs, re) => reqs.filter(r => r.method === 'post' && re.test(r.path));
function section(name) { console.log('\n── ' + name + ' ──'); }
function finish() {
  console.log('\n── 요청 ' + fake.requests.length + ' 건 (method path [body 행 수]) ──');
  fake.requests.forEach(r => console.log('  ' + r.method.toUpperCase().padEnd(5) + ' ' + r.path.replace(/^https?:\/\/[^/]+/, '') + (r.body ? ' [' + (Array.isArray(r.body) ? r.body.length : 'obj') + ']' : '')));
  console.log('\n' + (fails.length ? '❌ 실패 ' + fails.length + ' : ' + fails.join(' | ') : '⭐ 단언 전부 통과'));
  process.exit(fails.length ? 1 : 0);
}

if (scenario === 'conflict') {
  section('Dry — 같은 SKU 다른 cin7 행 → 멈춤');
  let err = null; const m0 = mark();
  try { imsLoadProduct(); } catch (e) { err = e; }
  ok(err && /같은 SKU 가 다른 cin7 행/.test(err.message), '멈춘다: ' + (err ? err.message.slice(0, 120) : '(안 멈춤)'));
  ok(since(m0).every(r => r.method === 'get'), 'Dry 는 쓰기 0');
  console.log(fake.logs.filter(l => /SKU 겹침/.test(l)).join('\n'));
  finish();
}

section('Family Dry · Apply');
let lm = logMark(); imsLoadProductFamily(); let L = logsSince(lm);
ok(/\[674 짝 · cin7_id 만\] F2FAM ← c0000000-0000-4000-8000-000000000102/.test(L), 'family Dry: F2FAM 짝(cin7_id 만)');
ok(/\[672 손댄 행 · Cin7 이 덮는다\] F3FAM .* — 덮임: name: IMS="Family F3 \(IMS edit\)" Cin7="Family F3FAM"/.test(L), 'family Dry: F3FAM 이름 덮임 목록');
let m = mark(); lm = logMark(); imsLoadProductFamilyApply(); let a = since(m); L = logsSince(lm);
const fPair = a.filter(r => r.method === 'patch');
ok(fPair.length === 1 && /product_family\?id=eq\.00000000-0000-4000-8000-000000000202&cin7_id=is\.null$/.test(fPair[0].path) && fPair[0].body.cin7_id === C(102), 'family: manual F2FAM 에 cin7_id 만 PATCH');
const fUp = posts(a, /product_family\?on_conflict=cin7_id/), fNew = posts(a, /product_family\?on_conflict=sku/);
ok(fUp.length === 1 && fUp[0].body.length === 2 && fNew.length === 0 && !fUp[0].body.some(r => r.sku === 'F2FAM'), 'family upsert: on_conflict=cin7_id 2 행(F1 · F3) · F2FAM 없음 · 새 행 0');
if (mode === 'emu') {
  ok(dbRow('product_family', r => r.id === U(103)).name === 'Family F3FAM', 'emu: F3FAM 이름 Cin7 값(672)');
  ok(dbRow('product_family', r => r.id === U(202)).cin7_id === C(102) && dbRow('product_family', r => r.id === U(202)).source === 'manual', 'emu: F2FAM cin7_id 만 · source manual');
}

section('Product Dry (전량)');
m = mark(); lm = logMark(); imsLoadProduct(); a = since(m); L = logsSince(lm);
console.log(L.split('\n').filter(l => /\[6|페이지|이번 실행|우리 표|덮이지 않음/.test(l)).join('\n'));
ok(a.every(r => r.method === 'get'), 'Dry 는 쓰기 0');
ok(/페이지 1 — 받은 13 · 넣을 11 \(cin7_id 로 8 · 새로 2 · 짝 1 · 이미 짝지어진 안 보냄 0\)/.test(L), 'Dry: 받은 13 · 넣을 11 · cin7_id 8 · 새로 2 · 짝 1 · 이미 짝지어진 0');
ok(/\[679 SKU 다름 · IMS 값 유지\] IMS P7-NEW ≠ Cin7 P7/.test(L), 'Dry: 679 SKU 다름(P7-NEW ≠ P7)');
ok(/\[670\/675 sellable IMS 값 유지 · ims\] P2 : IMS false \(Cin7 true\)/.test(L) && /· ims\] P1-6 : IMS false/.test(L) && /· set\] P1-12 : IMS false/.test(L) && !/P1-24 :/.test(L), 'Dry: sellable 유지 P2(ims) · P1-6(ims 세트) · P1-12(세트) · P1-24 는 같아 목록 없음');
ok(/\[674 짝 · cin7_id 만\] P6 ← c0000000-0000-4000-8000-000000000006 · 값이 다른 칸 .*name: IMS="P6 made in IMS" Cin7="Product P6"/.test(L), 'Dry: 674 짝 P6 + 다른 칸');
ok(/\[672 손댄 행 · Cin7 이 덮는다\] P8 .* — 덮임: .*family_id: IMS="00000000-0000-4000-8000-000000000202" Cin7="00000000-0000-4000-8000-000000000101"/.test(L) && /name: IMS="Product P8 \(IMS edit\)" Cin7="Product P8"/.test(L), 'Dry: 672 P8 이름 · family 이동 덮임(새 ⑧)');
ok(/\[672 손댄 행 · Cin7 이 덮는다\] P2 .* — 덮여도 값 그대로/.test(L), 'Dry: 672 P2 덮여도 값 그대로(sellable 은 유지)');
ok(/\[672\] 손댄 cin7 행 중 이번 Cin7 에 없는 것\(덮이지 않음\) 0/.test(L), 'Dry: 덮이지 않음 0');
ok(fake.props.IPR_DRY_PAGE === undefined, 'Dry 커서 지워짐');

section('Product Apply');
m = mark(); lm = logMark(); imsLoadProductApply(); a = since(m); L = logsSince(lm);
console.log(L.split('\n').filter(l => /재대조|IPR_LAST|이번 실행|쓴 행/.test(l)).join('\n'));
const pPair = a.filter(r => r.method === 'patch');
ok(pPair.length === 1 && /product\?id=eq\.00000000-0000-4000-8000-000000000206&cin7_id=is\.null$/.test(pPair[0].path) && pPair[0].body.cin7_id === C(6), 'P6 에 cin7_id 만 PATCH');
const up = posts(a, /\/product\?on_conflict=cin7_id/), fresh = posts(a, /\/product\?on_conflict=sku/);
const upRows = up.reduce((x, r) => x.concat(r.body), []), freshRows = fresh.reduce((x, r) => x.concat(r.body), []);
ok(up.length === 1 && upRows.length === 8 && fresh.length === 1 && freshRows.length === 2, 'upsert: cin7_id 로 8 · sku 로 2 (실제 ' + upRows.length + ' · ' + freshRows.length + ')');
ok(upRows.find(r => r.cin7_id === C(7)).sku === 'P7-NEW', '679: P7 행의 sku 가 IMS 값 P7-NEW');
ok(upRows.find(r => r.cin7_id === C(2)).sellable === false && upRows.find(r => r.cin7_id === C(3)).sellable === false && upRows.find(r => r.cin7_id === C(4)).sellable === false && upRows.find(r => r.cin7_id === C(14)).sellable === true, '670/675: P2 · P1-6 · P1-12 false 유지 · P1-24 true 유지');
ok(!upRows.some(r => r.sku === 'P6') && !freshRows.some(r => r.sku === 'P6'), '짝지은 P6 은 upsert 에 없음');
ok(freshRows.find(r => r.sku === 'P1-36').sellable === true && freshRows.every(r => !('parent_product_id' in r) && !('pack_factor' in r) && !('note' in r) && !('description_html' in r)), '새 세트 P1-36 은 Cin7 값 true · parent · pack · note · description_html 은 안 보낸다');
ok(upRows.every(r => !('parent_product_id' in r) && !('pack_factor' in r) && !('id' in r)), '기존 행도 parent · pack · id 를 안 보낸다');
ok(a.some(r => r.method === 'get' && /product\?select=cin7_id,sku,sellable&cin7_id=in\./.test(r.path)), '재대조 읽기(cin7_id in)');
ok(/\[670\/675 재대조\] IMS 값을 실은 행 3 · 그대로 3 · 사이에 바뀜 0/.test(L), '재대조: 3 · 그대로 3');
ok(fake.props.IPR_LAST_APPLY_AT > '2026-10-20T00:00:00.000Z' && fake.props.IPR_PRODUCT_PAGE === undefined, 'IPR_LAST_APPLY_AT 갱신 · Apply 커서 지워짐');
if (mode === 'emu') {
  ok(dbRow('product', r => r.id === U(7)).sku === 'P7-NEW', 'emu: P7 sku 그대로(679)');
  ok(dbRow('product', r => r.id === U(8)).name === 'Product P8' && dbRow('product', r => r.id === U(8)).family_id === U(101), 'emu: P8 이름 · family Cin7 값(672 · 새 ⑧)');
  ok(dbRow('product', r => r.id === U(206)).cin7_id === C(6) && dbRow('product', r => r.id === U(206)).name === 'P6 made in IMS' && dbRow('product', r => r.id === U(206)).source === 'manual', 'emu: P6 cin7_id 만 · 다른 칸 IMS 값');
  ok(dbRow('product', r => r.sku === 'P1-36').sellable === true && dbRow('product', r => r.sku === 'P11'), 'emu: 새 행 P1-36(true) · P11');
  ok(fake.db.product.length === 12, 'emu: 제품 행 10 + 새 2 = 12 (실제 ' + fake.db.product.length + ')');
}

section('2단계 잇기(새 세트) · Extra · Barcode · BOM');
const newSet = JSON.parse(ims_fetch_('/rest/v1/product?select=id&sku=eq.P1-36', { method: 'get' }).getContentText())[0].id;   // 2단계 잇기 흉내 — 시트 없이 ipr_patch_ 직접(판정 675 · 트리거가 false 로)
m = mark(); ipr_patch_([{ id: newSet, parent_product_id: U(1), pack_factor: 36 }]); a = since(m);
ok(a.some(r => r.method === 'patch' && r.path === '/rest/v1/product?id=eq.' + newSet + '&parent_product_id=is.null'), '잇기 PATCH(parent is null 조건)');
const afterLink = JSON.parse(ims_fetch_('/rest/v1/product?select=sellable,parent_product_id&id=eq.' + newSet, { method: 'get' }).getContentText())[0];
ok(afterLink.sellable === false && afterLink.parent_product_id === U(1), '새 세트 잇기 뒤 sellable false(판정 675 · ' + (mode === 'emu' ? '트리거 흉내' : '트리거 실물') + ')');
m = mark(); imsLoadProductExtraApply(); a = since(m);
const ex = posts(a, /\/product\?on_conflict=cin7_id/);
ok(ex.length === 1 && ex[0].body.length === 1 && ex[0].body[0].sku === 'AS91437-BLK' && ex[0].body[0].cin7_id === C(12), 'Extra: AS91437-BLK 를 cin7_id 로 upsert');
m = mark(); lm = logMark(); imsLoadProductBarcodeApply(); a = since(m); L = logsSince(lm);
const bcUp = posts(a, /product_barcode\?on_conflict=product_id,barcode/); const bcRows = bcUp.reduce((x, r) => x.concat(r.body), []);
ok(bcUp.length === 1 && bcRows.length === 2 && bcRows.some(r => r.product_id === U(1) && r.barcode === 'B1') && bcRows.some(r => r.product_id === U(8) && r.barcode === 'B8') && !bcRows.some(r => r.barcode === 'B2'), '바코드 upsert 2(B1 · B8) · manual B2 없음');
ok(/manual 이라 건너뜀 1 · 손댄 cin7 줄을 덮음 1/.test(L) && /\[672\] 00000000-0000-4000-8000-000000000008\|B8 : is_active IMS=true → true · is_primary IMS=false → true/.test(L), '바코드 로그: manual 건너뜀 1 · 672 B8 대표 덮임');
if (mode === 'emu') ok(dbRow('product_barcode', r => r.barcode === 'B2').is_active === false && dbRow('product_barcode', r => r.barcode === 'B8').is_primary === true, 'emu: B2 manual 그대로(꺼짐) · B8 대표 true');
m = mark(); lm = logMark(); imsLoadProductBomApply(); a = since(m); L = logsSince(lm);
const bomUp = posts(a, /product_bom\?on_conflict=parent_product_id,component_product_id/); const bomRows = bomUp.reduce((x, r) => x.concat(r.body), []);
ok(bomUp.length === 1 && bomRows.length === 1 && bomRows[0].parent_product_id === U(10) && bomRows[0].component_product_id === U(1) && bomRows[0].quantity === 2, 'BOM upsert 1 줄(P10→P1 qty 2) · manual (P10,P2) 없음');
ok(/manual 이라 건너뜀 1/.test(L) && /\[672\] P10 → P1 : quantity IMS=3 Cin7=2 · is_active IMS=true → true/.test(L), 'BOM 로그: manual 건너뜀 1 · 672 (P10,P1) 수량 덮임');
if (mode === 'emu') ok(dbRow('product_bom', r => r.component_product_id === U(2)).is_active === false && dbRow('product_bom', r => r.component_product_id === U(1)).quantity === 2, 'emu: (P10,P2) manual 꺼짐 그대로 · (P10,P1) qty 2');
finish();
