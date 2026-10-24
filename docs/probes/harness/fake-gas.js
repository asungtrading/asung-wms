// 가짜 GAS 전역 + PostgREST 에뮬레이터(emu) / curl 로컬 모드(local) — ldfix-1a
'use strict';
const { execFileSync } = require('child_process');
const crypto = require('crypto');

function makeFakeGas(opts) {
  const mode = opts.mode;                      // 'emu' | 'local'
  const props = Object.assign({}, opts.props || {});
  const driveFiles = (opts.driveFiles || []).map(f => ({ name: f.name, text: f.text }));
  const reports = [];
  const logs = [];
  const requests = [];                          // {method, path, body, headers}
  const db = opts.db ? JSON.parse(JSON.stringify(opts.db)) : {};   // emu 의 표 상태(깊은 복사)
  const nowIso = () => new Date().toISOString();

  // ── PostgREST 에뮬레이터 ──
  function parseUrl(url) {
    const m = url.match(/\/rest\/v1\/([^?]+)\??(.*)$/);
    const table = m[1], qs = m[2] || '';
    const filters = [], extra = {};
    qs.split('&').filter(Boolean).forEach(kv => {
      const i = kv.indexOf('='); const k = decodeURIComponent(kv.slice(0, i)), v = decodeURIComponent(kv.slice(i + 1));
      if (k === 'select' || k === 'on_conflict' || k === 'order') { extra[k] = v; return; }
      filters.push([k, v]);
    });
    return { table, filters, extra };
  }
  function match(row, filters) {
    return filters.every(([k, v]) => {
      const x = row[k] === undefined ? null : row[k];
      if (v === 'is.null') return x === null;
      if (v === 'not.is.null') return x !== null;
      if (v.startsWith('eq.')) return String(x) === v.slice(3);
      if (v.startsWith('gt.')) return x !== null && String(x) > v.slice(3);
      if (v.startsWith('in.(')) return v.slice(4, -1).split(',').indexOf(String(x)) >= 0;
      throw new Error('emu: filter 미지원 ' + k + '=' + v);
    });
  }
  function touch(table, row) {                  // ims_touch — service_role 이라 updated_by null
    row.updated_at = nowIso(); row.updated_by = null;
  }
  function customerGuard(row, oldParent) {      // customer_parent_guard 규칙 4 · 판정 678(ldfix-1a2 · 256 바뀜): 부모 없음 + 'cin7' 만 null · 'ims' 는 남긴다
    if ((row.parent_id === null || row.parent_id === undefined) && row.parent_source === 'cin7') row.parent_source = null;
    if (oldParent && row.parent_id !== oldParent && row.default_bill_to_customer_id === oldParent) row.default_bill_to_customer_id = null;
  }
  function defaults(table, row) {
    const r = Object.assign({ id: crypto.randomUUID(), created_at: nowIso(), updated_at: nowIso(), updated_by: null, source: 'cin7', is_active: true, note: null }, row);
    if (table === 'customer') Object.assign(r, { parent_id: r.parent_id ?? null, parent_source: r.parent_source ?? null, default_bill_to_customer_id: r.default_bill_to_customer_id ?? null, cin7_id: r.cin7_id ?? null });
    if (table === 'product') {                    // product_sellable_default(INSERT · 명시 null → 종류 기본) · 칸 기본 true · sellable_source 기본 null
      Object.assign(r, { parent_product_id: r.parent_product_id ?? null, pack_factor: r.pack_factor ?? null, sellable_source: r.sellable_source ?? null, family_id: r.family_id ?? null, cin7_id: r.cin7_id ?? null });
      if (r.sellable === null || r.sellable === undefined) r.sellable = (r.parent_product_id === null);
    }
    return r;
  }
  function productGuard(row, oldParent, oldSellable, body) {   // product_sellable_default(UPDATE OF parent_product_id): 낱개 → 세트인데 같은 문장이 sellable 을 안 바꿨으면 false
    if (oldParent === null && row.parent_product_id !== null && !('sellable' in body)) row.sellable = false;
    if (row.sellable === null) row.sellable = (row.parent_product_id === null);
  }
  function respond(code, bodyObj, headers) {
    const text = typeof bodyObj === 'string' ? bodyObj : JSON.stringify(bodyObj);
    const hs = Object.assign({}, headers || {});
    return { getResponseCode: () => code, getContentText: () => text, getHeaders: () => hs };
  }
  function emuFetch(url, o) {
    const { table, filters, extra } = parseUrl(url);
    const method = (o.method || 'get').toLowerCase();
    const prefer = String((o.headers || {}).Prefer || '');
    const rows = db[table] || (db[table] = []);
    if (method === 'get') {
      const hit = rows.filter(r => match(r, filters));
      let out = hit, hdr = {};
      const range = (o.headers || {}).Range;
      if (range) { const [a, b] = range.split('-').map(Number); out = hit.slice(a, b + 1); if (prefer.includes('count=exact')) hdr['Content-Range'] = (out.length ? a + '-' + (a + out.length - 1) : '*') + '/' + hit.length; }
      else if (prefer.includes('count=exact')) hdr['Content-Range'] = (hit.length ? '0-' + (hit.length - 1) : '*') + '/' + hit.length;
      return respond(200, out, hdr);
    }
    if (method === 'patch') {
      const body = JSON.parse(o.payload);
      const hit = rows.filter(r => match(r, filters));
      hit.forEach(r => { const oldParent = r.parent_id, oldPP = r.parent_product_id, oldS = r.sellable; Object.assign(r, body); if (table === 'customer' && 'parent_id' in body) customerGuard(r, oldParent); if (table === 'product' && 'parent_product_id' in body) productGuard(r, oldPP, oldS, body); touch(table, r); });
      return respond(200, prefer.includes('return=representation') ? hit : []);
    }
    if (method === 'post' && table.startsWith('rpc/')) {
      if (table === 'rpc/product_supplier_default_recalc') return respond(200, recalcDefaults(JSON.parse(o.payload || '{}').p_product_ids || null));
      throw new Error('emu: rpc 미지원 ' + table);
    }
    if (method === 'delete') {                  // ldfix-1d · 태그 적재의 DELETE ?source=eq.cin7&id=in.(…) · return=representation 이면 지운 행을 돌려준다
      const hit = rows.filter(r => match(r, filters));
      db[table] = rows.filter(r => hit.indexOf(r) < 0);
      return respond(200, prefer.includes('return=representation') ? hit : []);
    }
    if (method === 'post') {
      const body = JSON.parse(o.payload); const arr = Array.isArray(body) ? body : [body];
      const keys = (extra.on_conflict || '').split(',').filter(Boolean);
      const out = [];
      arr.forEach(b => {
        const found = keys.length ? rows.find(r => keys.every(k => String(r[k]) === String(b[k]))) : null;
        if (found) { const oldParent = found.parent_id, oldPP = found.parent_product_id, oldS = found.sellable; Object.assign(found, b); if (table === 'customer' && 'parent_id' in b) customerGuard(found, oldParent); if (table === 'product' && 'parent_product_id' in b) productGuard(found, oldPP, oldS, b); touch(table, found); out.push(found); }
        else { const r = defaults(table, b); rows.push(r); out.push(r); }
      });
      return respond(201, prefer.includes('return=representation') ? out : []);
    }
    throw new Error('emu: method 미지원 ' + method);
  }
  // ── 가짜 Cin7 — opts.cin7 = { product: [...], productFamily: [...] } · Page · Limit · Sku 만 받는다 · Products / ProductFamilies 로 돌려준다 ──
  const cin7 = opts.cin7 || {};
  function cin7Fetch(url) {
    const m = url.match(/ExternalApi\/v2\/([A-Za-z]+)\??(.*)$/); const path = m[1]; const q = {};
    (m[2] || '').split('&').filter(Boolean).forEach(kv => { const i = kv.indexOf('='); q[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1)); });
    let all = cin7[path]; if (!all) throw new Error('가짜 Cin7 에 없는 길: ' + path);
    if (q.Sku) all = all.filter(x => String(x.SKU) === q.Sku);
    const page = Number(q.Page || 1), limit = Number(q.Limit || 100);
    const items = all.slice((page - 1) * limit, page * limit);
    const body = { Total: all.length }; body[path === 'productFamily' ? 'ProductFamilies' : (path === 'supplier' ? 'SupplierList' : 'Products')] = items;
    return respond(200, body);
  }
  // ── product_supplier_default_recalc 흉내 — po-module §3-g ① 끄기 → ② 켜기(동점 · 날짜 없음은 비워 둠 · manual 줄 있는 제품은 건드리지 않음) ──
  function recalcDefaults(pids) {
    const ps = db.product_supplier || [], sup = {}; (db.supplier || []).forEach(s => { sup[s.id] = s; });
    const inScope = r => !pids || pids.indexOf(r.product_id) >= 0;
    let off = 0, on = 0;
    ps.forEach(r => { if (inScope(r) && r.is_default && (!r.is_active || !(sup[r.supplier_id] && sup[r.supplier_id].is_active))) { r.is_default = false; touch('product_supplier', r); off++; } });
    const byP = {}; ps.forEach(r => { (byP[r.product_id] = byP[r.product_id] || []).push(r); });
    Object.keys(byP).forEach(pid => {
      const rows = byP[pid]; if (!inScope(rows[0])) return;
      if (rows.some(r => r.source === 'manual') || rows.some(r => r.is_default)) return;
      const cand = rows.filter(r => r.is_active && sup[r.supplier_id] && sup[r.supplier_id].is_active);
      if (!cand.length) return;
      const n = cand.length; cand.sort((a, b) => (b.last_supplied || '') < (a.last_supplied || '') ? -1 : ((b.last_supplied || '') > (a.last_supplied || '') ? 1 : 0));
      const top = cand[0], tie = cand.filter(r => r.last_supplied === top.last_supplied).length;
      if (n === 1 || (top.last_supplied && tie === 1)) { top.is_default = true; touch('product_supplier', top); on++; }
    });
    const multi = Object.keys(byP).filter(pid => inScope(byP[pid][0]) && byP[pid].filter(r => r.is_default).length > 1).length;
    return { turned_off: off, turned_on: on, multi_default_products: multi, scope: pids ? pids.length + ' products' : 'all' };
  }
  // ── curl 로컬 모드 ──
  function curlFetch(url, o) {
    const args = ['-sS', '-i', '-X', (o.method || 'get').toUpperCase(), url, '-H', 'Expect:'];
    Object.keys(o.headers || {}).forEach(k => args.push('-H', k + ': ' + o.headers[k]));
    if (o.payload !== undefined && o.payload !== null) args.push('--data-binary', '@-');
    const raw = execFileSync('curl', args, { input: o.payload || '', maxBuffer: 64 * 1024 * 1024 }).toString('utf8');
    const sep = raw.indexOf('\r\n\r\n'); const head = raw.slice(0, sep), body = raw.slice(sep + 4);
    const lines = head.split('\r\n'); const code = Number(lines[0].split(' ')[1]); const hs = {};
    lines.slice(1).forEach(l => { const i = l.indexOf(':'); if (i > 0) hs[l.slice(0, i)] = l.slice(i + 1).trim(); });
    return respond(code, body, hs);
  }

  const folders = [];
  function folderObj(id) {
    return {
      getId: () => id, getUrl: () => 'drive://' + id,
      getFiles: () => { let i = 0; return { hasNext: () => i < driveFiles.length, next: () => { const f = driveFiles[i++]; return { getName: () => f.name, getBlob: () => ({ getDataAsString: () => f.text }) }; } }; },
      createFile: (name, text, mime) => { reports.push({ name, text, mime: mime || null, folder: id }); return {}; }
    };
  }
  const g = {
    getProp: k => { if (!(k in props)) throw new Error('getProp 없음 ' + k); return props[k]; },
    Logger: { log: s => logs.push(String(s)) },
    MimeType: { PLAIN_TEXT: 'text/plain', CSV: 'text/csv' },
    Utilities: { formatDate: (d, tz, fmt) => d.toISOString().replace(/[-:T]/g, '').slice(0, 14), sleep: () => {} },
    PropertiesService: { getScriptProperties: () => ({ getProperty: k => (k in props ? props[k] : null), setProperty: (k, v) => { props[k] = String(v); }, deleteProperty: k => { delete props[k]; } }) },
    SpreadsheetApp: {                             // 제품↔공급처 적재의 중간 저장 시트(ips_line) · 읽기만 흉내
      openById: id => ({ getId: () => id, getUrl: () => 'sheet://' + id, getSheetByName: name => (opts.sheets && opts.sheets[name]) ? { getName: () => name, getDataRange: () => ({ getValues: () => opts.sheets[name] }), getLastRow: () => opts.sheets[name].length } : null,
                         insertSheet: () => { throw new Error('하네스는 시트를 만들지 않는다'); }, getSheets: () => { throw new Error('하네스는 시트 목록을 주지 않는다'); } }),
      create: () => { throw new Error('하네스는 시트를 만들지 않는다'); }
    },
    DriveApp: {
      getFolderById: id => folderObj(id),
      createFolder: name => { folders.push(name); return folderObj('folder-' + folders.length); }   // ldfix-1d · 태그 적재가 보고 폴더를 만든다(이름만 기록)
    },
    UrlFetchApp: {
      fetch: (url, o) => {
        const rec = { method: (o.method || 'get').toLowerCase(), path: url.replace(/^https?:\/\/[^/]+/, ''), body: o.payload ? JSON.parse(o.payload) : null, headers: o.headers || {} };
        requests.push(rec);
        if (url.indexOf('dearsystems') >= 0) return cin7Fetch(url);
        return mode === 'local' ? curlFetch(url, o) : emuFetch(url, o);
      }
    }
  };
  return { globals: g, props, reports, logs, requests, db, folders };
}
module.exports = { makeFakeGas };
