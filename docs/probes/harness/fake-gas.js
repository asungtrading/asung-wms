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
    return r;
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
      hit.forEach(r => { const oldParent = r.parent_id; Object.assign(r, body); if (table === 'customer' && 'parent_id' in body) customerGuard(r, oldParent); touch(table, r); });
      return respond(200, prefer.includes('return=representation') ? hit : []);
    }
    if (method === 'post') {
      const body = JSON.parse(o.payload); const arr = Array.isArray(body) ? body : [body];
      const keys = (extra.on_conflict || '').split(',').filter(Boolean);
      const out = [];
      arr.forEach(b => {
        const found = keys.length ? rows.find(r => keys.every(k => String(r[k]) === String(b[k]))) : null;
        if (found) { const oldParent = found.parent_id; Object.assign(found, b); if (table === 'customer' && 'parent_id' in b) customerGuard(found, oldParent); touch(table, found); out.push(found); }
        else { const r = defaults(table, b); rows.push(r); out.push(r); }
      });
      return respond(201, prefer.includes('return=representation') ? out : []);
    }
    throw new Error('emu: method 미지원 ' + method);
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

  const g = {
    getProp: k => { if (!(k in props)) throw new Error('getProp 없음 ' + k); return props[k]; },
    Logger: { log: s => logs.push(String(s)) },
    MimeType: { PLAIN_TEXT: 'text/plain' },
    Utilities: { formatDate: (d, tz, fmt) => d.toISOString().replace(/[-:T]/g, '').slice(0, 14), sleep: () => {} },
    PropertiesService: { getScriptProperties: () => ({ getProperty: k => (k in props ? props[k] : null), setProperty: (k, v) => { props[k] = String(v); }, deleteProperty: k => { delete props[k]; } }) },
    DriveApp: {
      getFolderById: id => ({
        getId: () => id, getUrl: () => 'drive://' + id,
        getFiles: () => { let i = 0; return { hasNext: () => i < driveFiles.length, next: () => { const f = driveFiles[i++]; return { getName: () => f.name, getBlob: () => ({ getDataAsString: () => f.text }) }; } }; },
        createFile: (name, text) => { reports.push({ name, text }); return {}; }
      }),
      createFolder: () => { throw new Error('하네스는 Collect 를 돌리지 않는다'); }
    },
    UrlFetchApp: {
      fetch: (url, o) => {
        const rec = { method: (o.method || 'get').toLowerCase(), path: url.replace(/^https?:\/\/[^/]+/, ''), body: o.payload ? JSON.parse(o.payload) : null, headers: o.headers || {} };
        requests.push(rec);
        if (url.indexOf('dearsystems') >= 0) throw new Error('하네스는 Cin7 을 부르지 않는다: ' + url);
        return mode === 'local' ? curlFetch(url, o) : emuFetch(url, o);
      }
    }
  };
  return { globals: g, props, reports, logs, requests, db };
}
module.exports = { makeFakeGas };
