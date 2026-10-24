// 편집기 ProbeIMS.js 의 ims_fetch_(56 ~ 73 행) · ims_blank_(115 ~ 119 행) 원문 복사 — 2026-10-24 · 바꾸지 않는다(원본이 바뀌면 다시 복사)
function ims_fetch_(path, opts) {
  var url = getProp('SUPABASE_IMS_URL').replace(/\/+$/, '') + path;
  var key = getProp('SUPABASE_IMS_SERVICE_KEY');
  var headers = {
    'apikey': key,
    'Authorization': 'Bearer ' + key,
    'Content-Type': 'application/json'
  };
  if (opts && opts.headers) {
    Object.keys(opts.headers).forEach(function (k) { headers[k] = opts.headers[k]; });
  }
  return UrlFetchApp.fetch(url, {
    method: (opts && opts.method) || 'get',
    headers: headers,
    payload: opts && opts.payload,
    muteHttpExceptions: true
  });
}
function ims_blank_(v) {
  if (v === null || v === undefined) return null;
  var s = String(v).trim();
  return s === '' ? null : s;
}
