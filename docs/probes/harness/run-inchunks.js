// `in.(…)` 글자 수 묶음 시험 — node run-inchunks.js · url-1(2026-10-27 · deferred 349 · so-module §80-c)
// 대상: ilp_idChunks_ · ils_idChunks_ · ipr_idChunks_ · ipt_idChunks_(순수 함수) + 그것을 쓰는 ilp_patchIds_ · ils_patchIn_ · ipr_recheckKept_ · 태그 Apply 의 DELETE 덩이(가짜 ims_fetch_ 로 URL 을 받아 센다)
// Cin7 · Drive · Supabase 호출 0 · ImsLoadCustomer 의 ilc_patchIn_(c91bc24 · 실물 통과)은 대상이 아니다
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeFakeGas } = require('./fake-gas');
const fake = makeFakeGas({ mode: 'emu', db: {}, props: { SUPABASE_IMS_URL: 'https://fazgmyvzzhqybtvtktyg.supabase.co', SUPABASE_IMS_SERVICE_KEY: 'k', CIN7_ACCOUNT_ID: 'x', CIN7_APPLICATION_KEY: 'x' } });
Object.assign(global, fake.globals);
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'ims-common.js'), 'utf8'), { filename: 'ims-common.js' });
const GS = ['ImsLoadPrice.gs', 'ImsLoadSupplier.gs', 'ImsLoadProduct.gs', 'ImsLoadProductTag.gs'];
GS.forEach(f => { const p = path.join(__dirname, '..', f); const st = fs.statSync(p); const md5 = require('crypto').createHash('md5').update(fs.readFileSync(p)).digest('hex'); console.log('  올림 ' + f + ' · ' + st.size + ' B · md5 ' + md5 + ' · mtime ' + st.mtime.toISOString()); vm.runInThisContext(fs.readFileSync(p, 'utf8'), { filename: f }); });

const fails = [];
const ok = (cond, msg) => { console.log((cond ? '  ✅ ' : '  ❌ ') + msg); if (!cond) fails.push(msg); };
function section(name) { console.log('\n── ' + name + ' ──'); }
const MAX = 1500;

// ── 재료 — 길이 36(uuid 꼴) · 72 · 150 자 키 × 0 · 1 · 41 · 100 · 1,000 개 (전부 서로 다르다) ──
function key(len, i) { const s = ('k' + i + '-').padEnd(len, 'abcdef0123456789'); return s.slice(0, len); }
function keys(len, n) { const out = []; for (let i = 0; i < n; i++) out.push(key(len, i)); return out; }
const LENS = [36, 72, 150], NS = [0, 1, 41, 100, 1000];

// ── 1) 순수 묶음 함수 넷 — 같은 규칙 ──
section('1) idChunks_ 넷 — 모든 묶음 id 부분 ≤ 1,500 · 손실 · 중복 0 · 빈 목록 [] · 순서 유지');
const CHUNKERS = { ilp_idChunks_, ils_idChunks_, ipr_idChunks_, ipt_idChunks_ };
const table = [];
Object.keys(CHUNKERS).forEach(name => {
  const fn = CHUNKERS[name];
  LENS.forEach(len => NS.forEach(n => {
    const ids = keys(len, n), chunks = fn(ids);
    const joined = chunks.map(c => c.join(','));
    const maxLen = joined.reduce((a, j) => Math.max(a, j.length), 0);
    const flat = [].concat(...chunks);
    const lost = ids.filter(x => flat.indexOf(x) < 0).length;
    const dup = flat.length - new Set(flat).size;
    const ordered = flat.join('\u0001') === ids.join('\u0001');
    const perChunk = Math.floor((MAX + 1) / (len + 1));                 // 한 묶음에 들어가는 최대 개수(id 부분 = k×len + (k−1) ≤ 1,500)
    const expectChunks = n === 0 ? 0 : Math.ceil(n / perChunk);
    const pass = maxLen <= MAX && lost === 0 && dup === 0 && flat.length === ids.length && ordered && chunks.length === expectChunks && chunks.every(c => c.length);
    table.push({ fn: name, len, n, chunks: chunks.length, perChunk, maxLen, pass });
    ok(pass, name + ' 길이 ' + len + ' × ' + n + ' → 묶음 ' + chunks.length + '(기대 ' + expectChunks + ' · 묶음당 ' + perChunk + ') · 가장 긴 id 부분 ' + maxLen + ' · 손실 ' + lost + ' · 중복 ' + dup);
  }));
  // (d) 키 하나가 1,500 보다 길면 그 하나만 실린 묶음 · 멈추지 않는다 · 앞뒤 키는 따로
  const big = 'B'.repeat(1501), ids = [key(36, 1), big, key(36, 2)];
  let out = null, err = null; try { out = fn(ids); } catch (e) { err = e; }
  ok(!err && out && out.length === 3 && out[1].length === 1 && out[1][0] === big && out[0][0] === ids[0] && out[2][0] === ids[2], name + ' 1,501 자 키 하나 → [k1] · [big] · [k2] 세 묶음 · 멈추지 않음' + (err ? ' (throw: ' + err.message + ')' : ''));
  const big2 = 'C'.repeat(1500);                                        // 꼭 1,500 이면 혼자 실린다(쉼표 셈 때문에 다른 키와 못 묶인다)
  const out2 = fn([big2, key(36, 3)]);
  ok(out2.length === 2 && out2[0][0] === big2 && out2[0].join(',').length === 1500, name + ' 1,500 자 키는 혼자 한 묶음(id 부분 1,500)');
  ok(fn([]).length === 0, name + ' 빈 목록 → []');
  ok(fn(keys(36, 40)).length === 1 && fn(keys(36, 41)).length === 2, name + ' uuid 36 자 — 40 개는 한 묶음(1,479) · 41 개는 둘(1,516 > 1,500)');
});

// ── 2) 부르는 길 — 가짜 ims_fetch_ 로 URL 을 받아 센다 (표 · 창구 호출 0 · 응답은 보낸 id 수만큼 행) ──
section('2) 쓰는 함수 넷 — 요청 수 · URL 의 id 부분 · 돌아온 셈');
let calls = [];
function inPart(url) { const m = url.match(/in\.\(([^)]*)\)/); return m ? m[1] : null; }
global.ims_fetch_ = function (p, opts) {
  const part = inPart(p); const ids = part === null ? [] : (part === '' ? [] : part.split(','));
  calls.push({ path: p, method: (opts && opts.method) || 'get', ids, headers: (opts && opts.headers) || {} });
  const rows = ids.map(id => ({ id, cin7_id: id, sku: 'SKU-' + id.slice(0, 8), sellable: true }));
  return { getResponseCode: () => 200, getContentText: () => JSON.stringify(rows), getHeaders: () => ({ 'Content-Range': (rows.length ? '0-' + (rows.length - 1) : '*') + '/' + rows.length }) };
};
function checkCalls(label, ids, expectMethod, pathRe) {
  const joined = calls.map(c => c.ids.join(','));
  const maxLen = joined.reduce((a, j) => Math.max(a, j.length), 0);
  const flat = [].concat(...calls.map(c => c.ids));
  const lost = ids.filter(x => flat.indexOf(x) < 0).length, dup = flat.length - new Set(flat).size;
  const methods = calls.every(c => c.method === expectMethod), paths = calls.every(c => pathRe.test(c.path));
  const expectCalls = ids.length === 0 ? 0 : ids.length <= 40 ? 1 : Math.ceil(ids.length / Math.floor((MAX + 1) / 37));
  const pass = maxLen <= MAX && lost === 0 && dup === 0 && flat.length === ids.length && methods && paths && (ids.length === 0 ? calls.length === 0 : calls.length === expectCalls);
  ok(pass, label + ' — 요청 ' + calls.length + '(기대 ' + expectCalls + ') · 가장 긴 id 부분 ' + maxLen + ' · 손실 ' + lost + ' · 중복 ' + dup + ' · method ' + expectMethod + ' ' + methods + ' · 경로 ' + paths);
  return calls.length;
}
[0, 1, 41, 100, 1000].forEach(n => {
  const ids = keys(36, n);
  calls = []; const done = ilp_patchIds_(ids, { is_active: false });
  checkCalls('ilp_patchIds_ × ' + n, ids, 'patch', /^\/rest\/v1\/product_price\?id=in\.\(/); ok(done === n, '  돌아온 행 셈 ' + done + ' = ' + n);
  calls = []; const d2 = ils_patchIn_('supplier_address', ids, { is_active: false }, 1000000);   // baseCount 100 만 → 한도 10,000 · 문 검사는 그대로 지나간다
  checkCalls('ils_patchIn_ × ' + n, ids, 'patch', /^\/rest\/v1\/supplier_address\?cin7_id=in\.\(/); ok(d2 === n, '  돌아온 행 셈 ' + d2 + ' = ' + n);
  calls = []; const logsBefore = fake.logs.length; ipr_recheckKept_(ids.map(id => ({ cin7_id: id, sku: 'SKU-' + id.slice(0, 8), sellable: true })));
  checkCalls('ipr_recheckKept_ × ' + n, ids, 'get', /^\/rest\/v1\/product\?select=cin7_id,sku,sellable&cin7_id=in\.\(/);
  const last = fake.logs.slice(logsBefore).join('\n'); ok(n === 0 ? /실은 행 0/.test(last) : new RegExp('실은 행 ' + n + ' · 그대로 ' + n + ' · 사이에 바뀜 0').test(last), '  재대조 로그: ' + last.trim().slice(0, 90));
});
// ipr_recheckKept_ 가 묶음을 이어 붙여 「사이에 바뀜」 을 전 묶음에서 잡는지 — 100 개 중 1 번째 · 99 번째(다른 묶음)를 바꿔 돌려준다
{ const ids = keys(36, 100); const changedSet = new Set([ids[0], ids[99]]);
  global.ims_fetch_ = (p, o) => { const part = inPart(p); const ii = part ? part.split(',') : []; calls.push({ path: p, method: (o && o.method) || 'get', ids: ii, headers: {} }); const rows = ii.map(id => ({ cin7_id: id, sku: 'SKU-' + id.slice(0, 8), sellable: !changedSet.has(id) })); return { getResponseCode: () => 200, getContentText: () => JSON.stringify(rows), getHeaders: () => ({ 'Content-Range': '0-' + (rows.length - 1) + '/' + rows.length }) }; };
  calls = []; const lb = fake.logs.length; ipr_recheckKept_(ids.map(id => ({ cin7_id: id, sku: 'SKU-' + id.slice(0, 8), sellable: true })));
  const l = fake.logs.slice(lb).join('\n'); ok(calls.length === 3 && /사이에 바뀜 2 → SKU-k0-abcde : 보낸 true → 지금 false · SKU-k99-abcd : 보낸 true → 지금 false/.test(l), '  ipr_recheckKept_ 세 묶음 걸친 변경 2 를 다 잡는다: ' + l.trim().slice(0, 140)); }

// ── 3) 태그 Apply 의 DELETE 덩이 — ipt_run_(false) 를 돌려 가짜 ims_fetch_ 가 받은 DELETE URL 을 센다 ──
section('3) ImsLoadProductTag Apply — DELETE 덩이가 글자 수로 나뉜다(100 · 1,000 지우기)');
[100, 1000].forEach(nDel => {
  const uu = i => ('00000000-0000-4000-8000-' + String(i).padStart(12, '0'));
  const delIds = []; for (let i = 0; i < nDel; i++) delIds.push(uu(i));
  const ptRows = delIds.map((id, i) => ({ id, product_id: 'P-' + i, tag: 'gone' + i, source: 'cin7' }));
  // 가짜 길 — product_tag 읽기(ipt_readAll_ → Range) · product 읽기(ipr_productMap_) · Cin7 제품 0 장 · DELETE · 속성 · Drive 는 fake-gas
  let dels = [];
  global.ims_fetch_ = (p, o) => {
    const method = (o && o.method) || 'get';
    if (method === 'delete') { const part = inPart(p); const ii = part ? part.split(',') : []; dels.push({ path: p, ids: ii }); return { getResponseCode: () => 200, getContentText: () => JSON.stringify(ii.map(id => ({ id }))), getHeaders: () => ({}) }; }
    const rows = /\/product_tag\?/.test(p) ? ptRows : [];
    const rg = (o && o.headers && o.headers.Range) ? o.headers.Range.split('-').map(Number) : [0, rows.length - 1];
    const out = rows.slice(rg[0], rg[1] + 1);
    return { getResponseCode: () => 200, getContentText: () => JSON.stringify(out), getHeaders: () => ({ 'Content-Range': (out.length ? rg[0] + '-' + (rg[0] + out.length - 1) : '*') + '/' + rows.length }) };
  };
  global.ims_cin7All_ = () => [];
  global.UrlFetchApp.fetch = (url, o) => { if (/dearsystems/.test(url)) return { getResponseCode: () => 200, getContentText: () => JSON.stringify({ Products: [], Total: 0 }), getHeaders: () => ({}) }; throw new Error('뜻밖의 fetch ' + url); };
  PropertiesService.getScriptProperties().setProperty(IPT_ALLOW_PROP, '1');      // 큰 지우기 안전장치는 이 시험의 대상이 아니다 — 한 번 통과
  let err = null; try { ipt_run_(false); } catch (e) { err = e; }
  const joined = dels.map(c => c.ids.join(',')), maxLen = joined.reduce((a, j) => Math.max(a, j.length), 0);
  const flat = [].concat(...dels.map(c => c.ids)), lost = delIds.filter(x => flat.indexOf(x) < 0).length, dup = flat.length - new Set(flat).size;
  const expectCalls = Math.ceil(nDel / 40);
  ok(!err && dels.length === expectCalls && maxLen <= MAX && lost === 0 && dup === 0 && dels.every(c => /^\/rest\/v1\/product_tag\?source=eq\.cin7&id=in\.\(/.test(c.path)),
    '지우기 ' + nDel + ' → DELETE ' + dels.length + ' 번(기대 ' + expectCalls + ' · uuid 40 개씩) · 가장 긴 id 부분 ' + maxLen + ' · 손실 ' + lost + ' · 중복 ' + dup + (err ? ' · throw: ' + err.message : ''));
  const lg = fake.logs.join('\n'); ok(new RegExp('⭐ 지운 줄 ' + nDel + ' / ' + nDel).test(lg), '  로그 「⭐ 지운 줄 ' + nDel + ' / ' + nDel + '」');
});

// ── 표 ──
section('표 — 함수 · 길이 · 개수 → 묶음 수 · 묶음당 · 가장 긴 id 부분');
console.log('  fn            len  n     chunks  perChunk  maxIdPart  pass');
table.forEach(r => console.log('  ' + r.fn.padEnd(14) + String(r.len).padEnd(5) + String(r.n).padEnd(6) + String(r.chunks).padEnd(8) + String(r.perChunk).padEnd(10) + String(r.maxLen).padEnd(11) + (r.pass ? '✅' : '❌')));

console.log(fails.length ? '\n❌ 실패 ' + fails.length + '\n' + fails.map(f => ' - ' + f).join('\n') : '\n⭐ 단언 전부 통과');
process.exit(fails.length ? 1 : 0);
