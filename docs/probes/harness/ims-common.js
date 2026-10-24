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
// 편집기 ProbeIMS.js 의 ims_cin7All_(83 ~ 113 행) 원문 복사 — 2026-10-24(ldfix-1b) · 바꾸지 않는다
function ims_cin7All_(path, listKey) {
  var base = 'https://inventory.dearsystems.com/ExternalApi/v2/';
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  var out = [], page = 1;
  while (true) {
    var res = UrlFetchApp.fetch(base + path + '?Page=' + page + '&Limit=100',
      { method: 'get', headers: headers, muteHttpExceptions: true });

    if (res.getResponseCode() === 429) {
      Logger.log('   429 — 65초 대기 후 재시도 (page ' + page + ')');
      Utilities.sleep(65000);
      continue;                      // 같은 페이지를 다시
    }
    if (res.getResponseCode() !== 200) {
      throw new Error(path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    }

    var data = JSON.parse(res.getContentText());
    var items = data[listKey] || [];
    out = out.concat(items);
    if (items.length < 100) break;
    page++;
    Utilities.sleep(2500);
  }
  return out;
}
