// ImsLoadProductTag.gs 시험 — node run-tag.js [emu|local] [main|bigdel] · ldfix-1d(판정 676 · 보고 파일 · 딜 표시 · 짐작)
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const fx = require('./fixtures/tag');
const mode = process.argv[2] || 'emu', scenario = process.argv[3] || 'main';
const F = fx.build(scenario), U = fx.U, C = fx.C;
const fake = makeFakeGas({
  mode, db: F.db, cin7: { product: F.product, productFamily: [], supplier: [] },
  props: { SUPABASE_IMS_URL: mode === 'local' ? (process.env.SUPABASE_IMS_URL || 'http://127.0.0.1:54321') : 'http://emu', SUPABASE_IMS_SERVICE_KEY: mode === 'local' ? process.env.SUPABASE_IMS_SERVICE_KEY : 'k',
           CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x' }          // ⚠️ IPT_LAST_APPLY_AT · IPT_FOLDER_ID 를 일부러 안 둔다 — 기본값 · 폴더 만들기 경로
});
Object.assign(global, fake.globals);
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
['ImsLoadProduct.gs', 'ImsLoadProductTag.gs'].forEach(f => vm.runInThisContext(fs.readFileSync(path.join(__dirname, '..', f), 'utf8'), { filename: f }));

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
const mark = () => fake.requests.length, since = n => fake.requests.slice(n);
const logMark = () => fake.logs.length, logsSince = n => fake.logs.slice(n).join('\n');
const report = prefix => { const r = fake.reports.filter(x => x.name.startsWith(prefix)); return r.length ? r[r.length - 1] : null; };
const rd = p => JSON.parse(ims_fetch_(p, { method: 'get' }).getContentText());
const tagRows = () => rd('/rest/v1/product_tag?select=id,product_id,tag,source&order=id');
const has = (rows, pid, t, src) => rows.some(r => r.product_id === pid && r.tag === t && (!src || r.source === src));
function section(name) { console.log('\n── ' + name + ' ──'); }
function finish() {
  console.log('\n── 요청 ' + fake.requests.length + ' 건 ──');
  fake.requests.forEach(r => console.log('  ' + r.method.toUpperCase().padEnd(6) + ' ' + r.path.replace(/^https?:\/\/[^/]+/, '') + (r.body ? ' [' + (Array.isArray(r.body) ? r.body.length : 'obj') + ']' : '')));
  console.log('\n' + (fails.length ? '❌ 실패 ' + fails.length + ' : ' + fails.join(' | ') : '⭐ 단언 전부 통과'));
  process.exit(fails.length ? 1 : 0);
}
const DEF = '2026-10-10T18:52:00Z';

section('Dry (속성 없음 → 기본값)');
let lm = logMark(), m = mark(); imsLoadProductTag(); let L = logsSince(lm), a = since(m);
console.log(L);
ok(a.every(r => r.method === 'get'), 'Dry 는 쓰기 0 (전부 get)');
ok(fake.folders.length === 1 && fake.props.IPT_FOLDER_ID === 'folder-1', '보고 폴더를 만들고 IPT_FOLDER_ID 에 적는다: ' + fake.props.IPT_FOLDER_ID);
ok(L.split('\n')[1] === '지난 태그 적재 시각 ' + DEF + ' ⚠️ 기본값 사용(속성 IPT_LAST_APPLY_AT 없음 · tag-1 Apply 2026-10-10 14:52 토론토)', '로그 2 번째 줄: 기본값 사용');
const dry = report('report-tag-dry-');
ok(dry && dry.mime === 'text/plain' && dry.text.split('\n')[1].indexOf('⚠️ 기본값 사용') > 0, '보고 파일 report-tag-dry 머리에도 기본값 사용');
ok(/태그 조건 딜 — 대상 줄 3 \(켜진 2\) · 태그 종류 3/.test(L), '딜 대상 3 · 켜진 2(Clearance · DISC_YesSale) · OffDeal 은 꺼짐');
const nIns = scenario === 'bigdel' ? 5 : 5, nDel = scenario === 'bigdel' ? 29 : 4;
ok(new RegExp('\\(5\\) 넣기 ' + nIns + ' · 지우기 ' + nDel + ' · manual 이라 건너뜀 1 · 건드리는 제품 ' + (scenario === 'bigdel' ? 7 : 7)).test(L), '(5) 넣기 ' + nIns + ' · 지우기 ' + nDel + ' · manual 건너뜀 1');
ok(/\(4\) IMS 에 없는 Cin7 제품\(버림 · 판정 418\) 1 · 그중 Tags 있는 1 · 버려질 줄 2/.test(L) && /cin7_id 로 못 찾고 SKU 로만 찾힘\(쓰지 않음\) 1 제품 · 줄 1 → S10/.test(L), '418: 없는 제품 1(S9) · SKU 만 1(S10)');
ok(/\(6\) 새로 넣을 cin7 태그 .* 5 줄 · 태그 4 종류 · ⚠️ 켜진 딜의 태그 2 줄\(1 종류: Clearance 2\) · 꺼진 딜의 태그 1 줄 · 짐작 Cin7 변화 가능 2 · 뗀 것 짐작 1 · 새 제품 1 · 철자 바뀜 1/.test(L), '(6) 넣을 것: 5 줄 · 4 종류 · 켜진 딜 2(Clearance) · 꺼진 1 · 짐작 넷(열쇠 사전순)');
ok(/"Clearance" · 제품 2 · 딜 ⚠️ Sale: Blowout Sale\(include\) · 짐작 (뗀 것 짐작 1 \/ 새 제품 1|새 제품 1 \/ 뗀 것 짐작 1) · SKU S1 S3/.test(L), '태그별 묶음: Clearance 제품 2 · 딜 ⚠️ · S1(뗀 것 짐작) · S3(새 제품)');
ok(/"OffDeal" · 제품 1 · 딜\(꺼짐\) Old Promo\(include · 꺼짐\) · 짐작 Cin7 변화 가능 1 · SKU S2/.test(L), '태그별 묶음: OffDeal 꺼진 딜 표시');
ok(new RegExp('\\(6\\) 지울 cin7 태그 .* ' + nDel + ' 줄 · 태그 ' + (scenario === 'bigdel' ? 29 : 4) + ' 종류 · ⚠️ 켜진 딜의 태그 1 줄\\(1 종류: DISC_YesSale 1\\) · 꺼진 딜의 태그 0 줄 · 짐작 ').test(L) && /짐작 Cin7 변화 가능 1 · Cin7 에 제품 없음 1 · 어긋남\(Cin7 수정일이 적재 앞인데 태그가 없다\) (1|26) · 철자 바뀜 1/.test(L), '(6) 지울 것: ' + nDel + ' 줄 · 켜진 딜 1(DISC_YesSale) · 짐작 넷');
ok(dry.text.indexOf('(7) IMS 에 없는 Cin7 제품 전부(판정 418 · Tags 있는 것 1) — SKU [태그]\n    S9 [Clearance, Zed]') > 0, '보고 파일 (7): 418 목록 전부(S9 [Clearance, Zed])');
const csvI = report('tag-insert-'), csvD = report('tag-delete-');
console.log('\n[tag-insert CSV]\n' + csvI.text + '\n[tag-delete CSV]\n' + csvD.text);
ok(csvI && csvI.mime === 'text/csv' && csvI.text.split('\n')[0] === 'sku,tag,deal,guess,cin7_modified_on,product_id', 'insert CSV 머리');
const iLines = csvI.text.trim().split('\n').slice(1);
ok(iLines.length === 5 && iLines.indexOf('S1,Clearance,딜 ⚠️ Sale: Blowout Sale(include),뗀 것 짐작,' + F.MOD_OLD + ',' + U(1)) >= 0, 'insert CSV: S1 Clearance 뗀 것 짐작 · 딜 ⚠️');
ok(iLines.indexOf('S3,Clearance,딜 ⚠️ Sale: Blowout Sale(include),새 제품,' + F.MOD_OLD + ',' + U(3)) >= 0, 'insert CSV: S3 새 제품');
ok(iLines.indexOf('S2,NewTag,,Cin7 변화 가능,' + F.MOD_NEW + ',' + U(2)) >= 0 && iLines.indexOf('S2,OffDeal,딜(꺼짐) Old Promo(include · 꺼짐),Cin7 변화 가능,' + F.MOD_NEW + ',' + U(2)) >= 0, 'insert CSV: S2 NewTag(딜 없음) · OffDeal(꺼진 딜)');
ok(iLines.indexOf('S7,Q4 2026,,철자 바뀜 ← q4 2026,' + F.MOD_OLD + ',' + U(7)) >= 0, 'insert CSV: S7 철자 바뀜 ← q4 2026');
const dLines = csvD.text.trim().split('\n');
ok(dLines[0] === 'sku,tag,deal,guess,cin7_modified_on,product_id,tag_id' && dLines.length === 1 + nDel, 'delete CSV 머리 + ' + nDel + ' 줄');
ok(dLines.indexOf('S6,DISC_YesSale,딜 ⚠️ Sale: Blowout Sale(include),Cin7 변화 가능,' + F.MOD_NEW + ',' + U(6) + ',' + U(506)) >= 0, 'delete CSV: S6 DISC_YesSale 켜진 딜 · 변화 가능');
ok(dLines.indexOf('S8,OldOnly,,Cin7 에 제품 없음,,' + U(8) + ',' + U(508)) >= 0, 'delete CSV: S8 Cin7 에 제품 없음(수정일 빈칸)');
ok(dLines.indexOf('S7,q4 2026,,철자 바뀜 → Q4 2026,' + F.MOD_OLD + ',' + U(7) + ',' + U(507)) >= 0, 'delete CSV: S7 철자 바뀜 → Q4 2026');
ok(dLines.indexOf('S5,Gone Tag,,어긋남(Cin7 수정일이 적재 앞인데 태그가 없다),' + F.MOD_OLD + ',' + U(5) + ',' + U(505)) >= 0, 'delete CSV: S5 Gone Tag 어긋남');
ok(!csvI.text.split('\n').some(l => /AOS|Hair Care/.test(l)) && !csvD.text.split('\n').some(l => /AOS|Hair Care/.test(l)), 'manual 태그(AOS · Hair Care)는 어느 CSV 에도 없다');
ok(/manual \{"Hair Care":1\} → "Hair Care" \(manual\)/.test(L), '417: hair care 는 manual 철자 Hair Care 가 이긴다');

if (scenario === 'bigdel') {
  section('Apply — 큰 지우기 안전장치(29 > 20) → 멈춤');
  lm = logMark(); m = mark(); imsLoadProductTagApply(); L = logsSince(lm); a = since(m);
  ok(/⛔ 지우기 29 > 한도 20 — Apply 는 멈춘다 · 맞으면 IPT_ALLOW_BIG_DELETE=1 을 넣고 한 번만/.test(L) && /쓰기 0 · 멈춤/.test(L), '멈춤 문구');
  ok(a.every(r => r.method === 'get'), '쓰기 요청 0');
  ok(report('report-tag-stop-') !== null, 'stop 보고 파일');
  ok(!('IPT_LAST_APPLY_AT' in fake.props), '멈추면 IPT_LAST_APPLY_AT 를 안 적는다');
  section('Apply — IPT_ALLOW_BIG_DELETE=1 로 한 번 통과');
  fake.props.IPT_ALLOW_BIG_DELETE = '1';
  lm = logMark(); m = mark(); imsLoadProductTagApply(); L = logsSince(lm); a = since(m);
  ok(/⚠️ 허락 속성으로 통과 — 지우기 29 > 한도 20/.test(L) && /⭐ 지운 줄 29 \/ 29/.test(L) && /쓰기 넣기 5 · 지우기 29/.test(L), '통과 · 지운 29 · 넣은 5');
  ok(!('IPT_ALLOW_BIG_DELETE' in fake.props), '허락 속성은 스스로 지운다');
  ok('IPT_LAST_APPLY_AT' in fake.props, 'IPT_LAST_APPLY_AT 적음: ' + fake.props.IPT_LAST_APPLY_AT);
  const rows = tagRows();
  ok(!rows.some(r => /^Bulk /.test(r.tag)) && has(rows, U(1), 'AOS', 'manual'), 'Bulk 25 전부 지워짐 · manual 그대로');
  finish();
}

section('Apply');
lm = logMark(); m = mark(); imsLoadProductTagApply(); L = logsSince(lm); a = since(m);
console.log(L.split('\n').filter(l => /^(═══|⭐|  넣기|쓰기|지난|CSV|보고 파일|\(5\))/.test(l)).join('\n'));
const dels = a.filter(r => r.method === 'delete');
ok(dels.length === 1 && dels[0].path === '/rest/v1/product_tag?source=eq.cin7&id=in.(' + [U(505), U(506), U(507), U(508)].join(',') + ')' && dels[0].headers.Prefer === 'return=representation', 'DELETE 한 덩이 · source=eq.cin7 · id 4(505 · 506 · 507 · 508)');
const ups = a.filter(r => r.method === 'post' && r.path === '/rest/v1/product_tag?on_conflict=product_id,tag');
const upRows = ups.reduce((x, r) => x.concat(r.body), []);
ok(ups.length === 1 && upRows.length === 5 && upRows.every(r => Object.keys(r).sort().join() === 'product_id,source,tag' && r.source === 'cin7'), 'upsert 한 요청 · 5 행 · 보내는 칸은 product_id · tag · source 뿐(보고용 칸 없음)');
ok(a.indexOf(dels[0]) < a.indexOf(ups[0]), '지우기가 넣기보다 앞');
ok(/⭐ 지운 줄 4 \/ 4/.test(L) && /쓰기 넣기 5 · 지우기 4/.test(L), '로그: 지운 4 · 넣은 5');
ok('IPT_LAST_APPLY_AT' in fake.props && fake.props.IPT_LAST_APPLY_AT > '2026-10-24', 'Apply 끝에 IPT_LAST_APPLY_AT 적음: ' + fake.props.IPT_LAST_APPLY_AT);
const ap = report('report-tag-apply-');
ok(ap && /\(6\) 새로 넣을 cin7 태그/.test(ap.text) && /쓰기 넣기 5 · 지우기 4/.test(ap.text), 'apply 보고 파일 = 계획 + 결과');
ok(fake.reports.filter(x => x.name.startsWith('tag-insert-')).length === 2, 'CSV 는 Dry · Apply 각각(둘)');
let rows = tagRows();
ok(has(rows, U(1), 'Clearance', 'cin7') && has(rows, U(2), 'NewTag', 'cin7') && has(rows, U(2), 'OffDeal', 'cin7') && has(rows, U(3), 'Clearance', 'cin7') && has(rows, U(7), 'Q4 2026', 'cin7'), 'DB: 넣은 5 줄 있음(source cin7)');
ok(!has(rows, U(5), 'Gone Tag') && !has(rows, U(6), 'DISC_YesSale') && !has(rows, U(7), 'q4 2026') && !has(rows, U(8), 'OldOnly'), 'DB: 지운 4 줄 없음');
ok(has(rows, U(1), 'AOS', 'manual') && has(rows, U(4), 'Hair Care', 'manual') && !has(rows, U(4), 'hair care') && has(rows, U(1), 'Brand X', 'cin7') && has(rows, U(5), 'Household', 'cin7'), 'DB: manual 2 줄 그대로 · P4 에 cin7 줄 안 생김 · 그대로인 cin7 2 줄');
ok(rows.length === 9, 'DB: product_tag 9 줄 = 8 − 4 + 5 (실제 ' + rows.length + ')');

section('Dry 2 회차(멱등 · 속성 있음)');
lm = logMark(); m = mark(); imsLoadProductTag(); L = logsSince(lm); a = since(m);
ok(/지난 태그 적재 시각 .* \(속성 IPT_LAST_APPLY_AT\)/.test(L) && !/기본값 사용/.test(L), '2 회차 머리: 속성 사용(기본값 아님)');
ok(/\(5\) 넣기 0 · 지우기 0 · manual 이라 건너뜀 1/.test(L), '2 회차 diff 0 · 0 · manual 1');
ok(a.every(r => r.method === 'get') && fake.folders.length === 1, '2 회차 쓰기 0 · 폴더는 다시 안 만든다');
finish();
