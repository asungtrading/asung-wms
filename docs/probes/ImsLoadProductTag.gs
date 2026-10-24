/**
 * ImsLoadProductTag.gs — IMS 제품 태그 적재 (product_tag · Cin7 제품 Tags → IMS)
 *
 * ⚠️ 최상위 const 금지 · 식별자 ASCII 만 · prefix 는 ipt_ / IPT_ (ipr_ · ips_ · ilp_ · ims_ · cdp_ 와 겹치지 않는다)
 * ⚠️ ImsLoadProduct.gs 의 ipr_cin7_ · ipr_upsert_ 를 그대로 쓴다. ImsRefLoad.gs 의 ims_fetch_ 도.
 * ⚠️ ImsLoadProduct.gs 는 고치지 않는다(미룬 164 는 따로 한 차수)
 * ⚠️ 대상: [테스트 · Asung-IMS]
 *
 * 정본: docs/design/so-module.md 13 절 D4 · §56 · §57-c · 판정 410 · 417 · 418 · 676 · tag-0 프로브(2026-10-10)
 *
 * 하는 일 — Cin7 제품 Tags 를 IMS product_tag 의 source='cin7' 줄에 맞춘다(관계 표 규약)
 *   · 원하는 상태 = (IMS 제품, 정본 철자) 집합 — Cin7 전 제품의 Tags 를 쪼개고 정리한 것(판정 417)
 *   · 지금 상태   = product_tag 의 source='cin7' 줄만
 *   · 넣기 = 원하는 것 − 지금 cin7 줄 − 같은 (제품, 태그)의 manual 줄   (manual 이 있으면 그대로 · 새 cin7 줄을 만들지 않는다)
 *   · 지우기 = 지금 cin7 줄 − 원하는 것                                (Cin7 에서 사라진 태그 · 철자가 바뀐 옛 줄)
 *   · manual 줄은 절대 건드리지 않는다(지우기 · 고치기 0)
 *   · 지우기 → 넣기 순(같은 (product_id, tag) unique 와 부딪히지 않게)
 *
 * 판정 417 — 태그 정리 · 철자 정하기
 *   쉼표로 쪼갬 → 앞뒤 공백 제거 → 안의 연속 공백을 한 칸으로 → 빈 조각 버림 → 한 제품 안 중복 버림(정리 뒤 기준)
 *   소문자로 접은 열쇠마다 철자별 「제품 수」(Cin7 전체 · IMS 에 없는 제품 포함)를 세어
 *   ① IMS 에 이미 있는 manual 철자가 있으면 그것(사람이 고른 것) ② 가장 많은 철자 ③ 같으면 앞글자 대문자
 *   ④ 그래도 같으면 대문자 수가 많은 것 ⑤ 그래도 같으면 사전순 앞 — 묶음별 결과를 전부 로그에 · Cin7 원본은 바꾸지 않는다
 *
 * 판정 418 — IMS 에 없는 Cin7 제품(678)의 태그는 버리고 목록만 · 다시 돌릴 수 있다(diff 라 남은 것만 한다)
 *
 * ⭐ [2026-10-24 · ldfix-1d · 판정 676] 「IMS 에서 뗀 Cin7 태그를 재적재가 되살림」(미룬 130)은 DB 무변 — 적재 규칙도 무변.
 *   대신 확인 실행(Dry)이 **바뀔 것 전부**를 사람이 보는 꼴로 낸다 — 컷오버 날 사람이 목록을 보고 Apply 한다.
 *   · 보고 자리: Drive 폴더(속성 IPT_FOLDER_ID · 없으면 만들고 적는다)에 파일 셋 — Logger 는 요약 + 태그별 상위 IPT_LOG_TOP 만(63,501 줄 규모라 넘친다)
 *       report-tag-<dry|apply|stop>-<시각>.txt   요약 · 태그별 묶음(넣을 것 · 지울 것) · IMS 에 없는 Cin7 제품 전부(418)
 *       tag-insert-<시각>.csv                     새로 넣을 cin7 태그 한 줄씩 — sku · tag · deal · guess · cin7_modified_on · product_id
 *       tag-delete-<시각>.csv                     지울 cin7 태그 한 줄씩  — 같은 칸 + tag_id
 *   · 딜 표시(deal): 그 태그를 조건으로 쓰는 딜(so_deal_target.target='tag' · 정확 일치 — DB 함수 so_deal_products_all · 트리거 product_tag_deal_hit_changed 와 같은 비교)
 *       켜짐 = 딜 is_active · 줄 is_active · 오더 전체 할인 아님(트리거와 같은 조건) · 아니면 (꺼짐) 으로 표시 — 넣을 것 · 지울 것 둘 다
 *       ⚠️ 되살아나면 할인이 걸린다(Clearance 예) — 지워지면 할인이 사라진다. 사람이 보는 핵심.
 *   · 짐작(guess) — 가를 수 없다는 판정 676 의 전제는 그대로 · 표시만(Cin7 제품 LastModifiedOn 과 지난 태그 적재 시각을 견준다)
 *       넣을 것: 철자 바뀜(같은 제품 · 같은 소문자 열쇠의 지울 줄이 있다) · 새 제품(IMS product.created_at 이 적재 뒤) · 뗀 것 짐작(Cin7 수정일 ≤ 적재 시각) · Cin7 변화 가능(수정일 > 적재 시각) · 수정일 없음
 *       지울 것: Cin7 에 제품 없음 · 철자 바뀜 · Cin7 변화 가능(수정일 > 적재 시각) · 어긋남(수정일 ≤ 적재 시각인데 Cin7 에 태그가 없다) · 수정일 없음
 *       한계: 제품의 다른 칸이 바뀌어도 수정일이 움직인다 → 「Cin7 변화 가능」 쪽으로 기운다(틀려도 안전한 방향)
 *   · 지난 태그 적재 시각 = 속성 IPT_LAST_APPLY_AT · ⚠️ 없으면 IPT_LAST_APPLY_DEFAULT(tag-1 Apply 2026-10-10 14:52 토론토)를 쓰고 「기본값 사용」 을 보고 · 로그 머리에 찍는다
 *       (System_Automation 의 Script Properties 가 50 개를 넘어 화면에서 못 넣는다 — 사람이 속성을 넣는 단계는 없다 · Apply 가 끝까지 가면 코드가 적는다)
 *   · Apply 도 같은 보고 파일(계획 + 결과)을 남긴다 — 컷오버 날 「무엇을 넣었나」 의 기록
 *
 * 실행 순서
 *   1) imsLoadProductTag()        확인만 · 쓰기 0 — Drive 보고 파일 셋 + 로그 요약을 대화 Claude 에게
 *   2) imsLoadProductTagApply()   쓴다 (⏸ 「Next run」 이 나오면 같은 함수를 다시 — 커서 없이 diff 로 남은 것만 한다)
 *   보조) 큰 지우기 안전장치에 걸리면 Script Property IPT_ALLOW_BIG_DELETE=1 을 넣고 한 번만 통과(끝나면 스스로 지운다)
 *
 * 쓰는 Script Properties: IPT_FOLDER_ID(보고 폴더 · 코드가 만든다) · IPT_LAST_APPLY_AT(Apply 끝 · 코드가 적는다) · (허락용) IPT_ALLOW_BIG_DELETE
 *
 * ⚠️ 손으로 돌린다 — 트리거 등록 없음 · SystemMonitor 미연동(회신 참조)
 * ⚠️ 쓰기는 service key(ims_fetch_)라 RLS 를 지나간다 — product_tag 의 insert/update/delete 는 authenticated 에게 없다(prod-2)
 * ⚠️ product_tag 트리거: *_shop_queue(켜진 listing 만 큐) · *_deal_hit_changed(태그 대상 딜이 있을 때만) · touch(update 만 · 안 쓴다)
 */

var IPT_LIMIT        = 1000;                 // ⭐ IncludeBOM 없이 1000 이 먹는다 (tag-0 프로브 실측 · 20 페이지)
var IPT_THROTTLE     = 2500;
var IPT_MAX_RUN      = 5.5 * 60 * 1000;      // 쓰기 덩이 사이에만 본다 — 넘으면 멈추고 「Next run」
var IPT_INSERT_CHUNK = 1000;                 // ipr_upsert_ 가 안에서 500 씩 나눈다
var IPT_DELETE_CHUNK = 40;                   // ⚠️ UrlFetchApp 의 URL 한도 2 KB — id=in.(…) 에 uuid 40 개 ≈ 1.5 KB
var IPT_ALLOW_PROP   = 'IPT_ALLOW_BIG_DELETE';
var IPT_FOLDER_PROP  = 'IPT_FOLDER_ID';
var IPT_LAST_APPLY_PROP    = 'IPT_LAST_APPLY_AT';
var IPT_LAST_APPLY_DEFAULT = '2026-10-10T18:52:00Z';   // tag-1 Apply(2026-10-10 14:52 토론토 · so-module §57-c) — 속성이 없을 때(Caleb 2026-10-24)
var IPT_LOG_TOP      = 30;                   // Logger 에 찍는 태그별 묶음 수(보고 파일에는 전부)
var IPT_SKU_PER_TAG  = 50;                   // 태그별 묶음 한 줄에 싣는 SKU 수(나머지는 수만 · 전부는 CSV 에)

function imsLoadProductTag()      { ipt_run_(true); }
function imsLoadProductTagApply() { ipt_run_(false); }

// ─────────────────────────────────────────────────────────────
// 우리 표 — 전부 읽는다 (Range 로 나눠 · 총계와 대조 · 1,000행 캡 안전장치는 ipr_map_ 과 같다)
// ─────────────────────────────────────────────────────────────
function ipt_readAll_(path) {
  var out = [], from = 0, step = 1000, total = null;
  while (true) {
    var res = ims_fetch_(path, { method: 'get',
      headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' } });
    if (res.getResponseCode() >= 300) throw new Error('조회 실패 ' + path + ' → ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
    if (total === null) {
      var hs = res.getHeaders(), cr = '';
      Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
      var m = cr.match(/\/(\d+)$/);
      total = m ? Number(m[1]) : null;
    }
    var rows = JSON.parse(res.getContentText());
    out = out.concat(rows);
    from += rows.length;
    if (!rows.length) break;
    if (total !== null && from >= total) break;
    if (total === null && rows.length < step) break;
  }
  if (total !== null && out.length < total) throw new Error('⚠️ 읽기가 잘렸다: ' + path + ' ' + out.length + ' / ' + total + ' — 멈춘다');
  if (total === null && out.length > 0 && out.length % step === 0) throw new Error('⚠️ 총계를 못 읽었는데 정확히 ' + out.length + '행 — 캡일 수 있다. 멈춘다');
  Logger.log('  ' + path + ' → ' + out.length + (total === null ? ' / 총계 미확인' : ' / 원격 총계 ' + total));
  return out;
}

// ─────────────────────────────────────────────────────────────
// Tags 쪼개기 · 정리 — tag-0 프로브(cdp_tags_)와 같은 자르기 + 판정 417 의 안 공백 · 중복 정리
//   돌려주는 것: 정리한 태그 목록(한 제품 안 중복 없음) · st 에 갈래별 수를 더한다
// ─────────────────────────────────────────────────────────────
function ipt_split_(tagsStr, st, samples) {
  if (tagsStr === null || tagsStr === undefined || String(tagsStr).trim() === '') return [];
  var seen = {}, list = [];
  String(tagsStr).split(',').forEach(function (r) {
    st.pieces++;
    var trimmed = r.trim();
    if (trimmed === '') { st.empty++; return; }
    if (r !== trimmed && r !== ' ' + trimmed) st.oddTrim++;            // 「, 」 한 칸 앞 공백(보통 모양) 말고 다른 앞뒤 공백
    var t = trimmed.replace(/\s+/g, ' ');                              // 안의 연속 공백(탭 포함) → 한 칸
    if (t !== trimmed) { st.inner++; if (samples.inner.length < 10) samples.inner.push(JSON.stringify(trimmed) + ' → ' + JSON.stringify(t)); }
    if (seen[t]) { st.dup++; return; }
    seen[t] = true; list.push(t);
  });
  return list;
}

/** 묶음(소문자 열쇠 하나)의 정본 철자 — 판정 417 · 돌려주는 것 { tag, reason } */
function ipt_canon_(counts, manualCounts) {
  var spellings = Object.keys(counts);
  if (spellings.length === 1 && !manualCounts) return { tag: spellings[0], reason: '' };
  // ① manual 철자 우선(사람이 고른 것) — manual 철자가 둘이면 manual 제품 수가 많은 쪽(⚠️ 로그)
  if (manualCounts) {
    var ms = Object.keys(manualCounts).sort(function (a, b) { return manualCounts[b] - manualCounts[a] || (a < b ? -1 : 1); });
    return { tag: ms[0], reason: 'manual' + (ms.length > 1 ? ' ⚠️ manual 철자 ' + ms.length : '') };
  }
  function upperN(s) { return (s.match(/[A-Z]/g) || []).length; }
  function firstUp(s) { return /^[A-Z]/.test(s) ? 1 : 0; }
  spellings.sort(function (a, b) {
    return counts[b] - counts[a]                 // ② 제품 수 많은 것
        || firstUp(b) - firstUp(a)               // ③ 앞글자 대문자
        || upperN(b) - upperN(a)                 // ④ 대문자 수
        || (a < b ? -1 : 1);                     // ⑤ 사전순
  });
  var w = spellings[0], r2 = spellings[1];
  var reason = counts[w] > counts[r2] ? '많음' : firstUp(w) > firstUp(r2) ? '대문자' : upperN(w) > upperN(r2) ? '대문자 수' : '사전순';
  return { tag: w, reason: reason };
}

function ipt_top_(obj, n) {
  return Object.keys(obj).sort(function (a, b) { return obj[b] - obj[a] || (a < b ? -1 : 1); }).slice(0, n);
}

// ─────────────────────────────────────────────────────────────
// [ldfix-1d] 보고 파일 — Drive 폴더(속성 IPT_FOLDER_ID · 없으면 만든다) · CSV
// ─────────────────────────────────────────────────────────────
function ipt_folder_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty(IPT_FOLDER_PROP);
  if (id) return DriveApp.getFolderById(id);
  var folder = DriveApp.createFolder('ImsLoadProductTag ' + Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
  props.setProperty(IPT_FOLDER_PROP, folder.getId());
  Logger.log('보고 폴더를 만들었다 — ' + IPT_FOLDER_PROP + ' = ' + folder.getId());
  return folder;
}

function ipt_file_(folder, name, text, mime) {
  folder.createFile(name, text, mime);
  return name + ' (' + text.length + ' 자)';
}

function ipt_csvCell_(v) {
  var s = (v === null || v === undefined) ? '' : String(v);
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function ipt_csv_(header, rows) {
  var lines = [header.join(',')];
  rows.forEach(function (r) { lines.push(header.map(function (h) { return ipt_csvCell_(r[h]); }).join(',')); });
  return lines.join('\n') + '\n';
}

/** ISO 문자열 → epoch ms · 못 읽으면 null */
function ipt_ts_(s) {
  if (s === null || s === undefined || s === '') return null;
  var t = Date.parse(String(s));
  return isNaN(t) ? null : t;
}

// ─────────────────────────────────────────────────────────────
// [ldfix-1d] 태그 조건 딜 — so_deal_target(target='tag') ← so_deal_line ← so_deal · 정확 일치(DB 와 같다)
//   돌려주는 것 { byTag: { 태그: [ { deal, kind, on } ] }, targets, on }
// ─────────────────────────────────────────────────────────────
function ipt_deals_() {
  var deals = {}, lines = {};
  ipt_readAll_('/rest/v1/so_deal?select=id,name,is_active,is_order_level&order=id').forEach(function (d) { deals[d.id] = d; });
  ipt_readAll_('/rest/v1/so_deal_line?select=id,deal_id,is_active&order=id').forEach(function (l) { lines[l.id] = l; });
  var targets = ipt_readAll_('/rest/v1/so_deal_target?select=line_id,kind,tag&target=eq.tag&order=id');
  var byTag = {}, on = 0;
  targets.forEach(function (t) {
    var l = lines[t.line_id] || {}, d = deals[l.deal_id] || {};
    var isOn = !!(d.is_active && l.is_active && !d.is_order_level);   // 트리거 product_tag_deal_hit_changed 와 같은 조건
    if (isOn) on++;
    byTag[t.tag] = byTag[t.tag] || [];
    byTag[t.tag].push({ deal: d.name || '(딜 없음 ' + l.deal_id + ')', kind: t.kind, on: isOn });
  });
  return { byTag: byTag, targets: targets.length, on: on };
}

/** 태그 하나의 딜 표시 문자열 — 없으면 '' */
function ipt_dealMark_(dealByTag, tag) {
  var hits = dealByTag[tag];
  if (!hits || !hits.length) return '';
  var anyOn = hits.some(function (h) { return h.on; });
  return (anyOn ? '딜 ⚠️ ' : '딜(꺼짐) ') + hits.map(function (h) { return h.deal + '(' + h.kind + (h.on ? '' : ' · 꺼짐') + ')'; }).join(' · ');
}

// ─────────────────────────────────────────────────────────────
// 본체
// ─────────────────────────────────────────────────────────────
function ipt_run_(dryRun) {
  var t0 = new Date().getTime();
  var rep = [];                                            // 보고 파일 전문(Logger 에 안 찍는 줄도 들어간다)
  function P(s) { Logger.log(s); rep.push(s); }            // 로그 + 보고
  function R(s) { rep.push(s); }                           // 보고에만
  function elapsed() { return Math.round((new Date().getTime() - t0) / 1000) + ' 초'; }
  var stamp = Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmmss');
  var folder = null;
  function finish(kind) {
    if (!folder) folder = ipt_folder_();
    var name = ipt_file_(folder, 'report-tag-' + kind + '-' + stamp + '.txt', rep.join('\n'), MimeType.PLAIN_TEXT);
    Logger.log('보고 파일: ' + name + ' · 폴더 ' + folder.getId());
  }
  P(dryRun ? '═══ imsLoadProductTag — 확인만(쓰기 0)' : '═══ imsLoadProductTagApply — 쓴다');

  // 지난 태그 적재 시각 — 짐작(676)의 기준 · 속성이 없으면 기본값(tag-1 Apply)
  var props = PropertiesService.getScriptProperties();
  var lastApplyRaw = props.getProperty(IPT_LAST_APPLY_PROP);
  var lastApply = lastApplyRaw || IPT_LAST_APPLY_DEFAULT;
  var lastApplyMs = ipt_ts_(lastApply);
  P('지난 태그 적재 시각 ' + lastApply + (lastApplyRaw ? ' (속성 ' + IPT_LAST_APPLY_PROP + ')' : ' ⚠️ 기본값 사용(속성 ' + IPT_LAST_APPLY_PROP + ' 없음 · tag-1 Apply 2026-10-10 14:52 토론토)'));
  if (lastApplyMs === null) P('⚠️ 지난 적재 시각을 날짜로 못 읽었다 — 짐작은 전부 「수정일 없음」 으로 찍힌다');

  // ── A) 우리 표 ──
  // 제품 — cin7_id → id · sku → id · id → family_id · created_at(676 짐작 「새 제품」) 를 한 번에(캡 안전장치는 ipr_map_ 과 같다)
  var prods = ipt_readAll_('/rest/v1/product?select=id,cin7_id,sku,family_id,created_at&order=id');
  var byCin7 = {}, bySku = {}, famOf = {}, skuOf = {}, cin7Of = {}, createdOf = {};
  prods.forEach(function (p) {
    if (p.cin7_id) byCin7[String(p.cin7_id)] = p.id;
    bySku[String(p.sku)] = p.id;
    famOf[p.id] = p.family_id || null;
    skuOf[p.id] = String(p.sku);
    cin7Of[p.id] = p.cin7_id ? String(p.cin7_id) : null;
    createdOf[p.id] = ipt_ts_(p.created_at);
  });
  P('IMS product ' + prods.length + ' · cin7_id 있는 ' + Object.keys(byCin7).length);

  // product_tag 전부 — cin7 줄은 (제품|태그) → id · manual 줄은 (제품|태그) 집합 + 소문자 열쇠별 철자 수
  var tagRows = ipt_readAll_('/rest/v1/product_tag?select=id,product_id,tag,source&order=id');
  var curCin7 = {}, manualKeys = {}, manualSpell = {}, nCin7 = 0, nManual = 0;
  tagRows.forEach(function (r) {
    var k = r.product_id + '|' + r.tag;
    if (r.source === 'cin7') { curCin7[k] = r.id; nCin7++; }
    else {
      manualKeys[k] = true; nManual++;
      var lk = r.tag.toLowerCase();
      manualSpell[lk] = manualSpell[lk] || {};
      manualSpell[lk][r.tag] = (manualSpell[lk][r.tag] || 0) + 1;
    }
  });
  P('IMS product_tag ' + tagRows.length + ' = cin7 ' + nCin7 + ' · manual ' + nManual);

  // 켜진 listing — 큐 영향 짐작용
  var listed = ipt_readAll_('/rest/v1/shop_listing?select=family_id,product_id&is_on=eq.true');
  var listedFam = {}, listedProd = {};
  listed.forEach(function (l) { if (l.family_id) listedFam[l.family_id] = true; if (l.product_id) listedProd[l.product_id] = true; });

  // 태그 조건 딜(676 · 딜 표시)
  var deals = ipt_deals_();
  P('태그 조건 딜 — 대상 줄 ' + deals.targets + ' (켜진 ' + deals.on + ') · 태그 종류 ' + Object.keys(deals.byTag).length + ' — 비교는 정확 일치(DB 와 같다)');

  // ── B) Cin7 제품 전량 — IncludeBOM 없이 · Limit 1000 · 페이지 끝까지 ──
  var cin7 = [], page = 1, apiTotal = null, cin7ById = {};
  while (true) {
    var res = ipr_cin7_('product', { Page: page, Limit: IPT_LIMIT, IncludeDeprecated: true });
    if (apiTotal === null) apiTotal = Number(res.Total);
    var items = res.Products || [];
    items.forEach(function (x) {
      var row = { ID: String(x.ID), SKU: String(x.SKU || '').trim(), Tags: x.Tags, Mod: x.LastModifiedOn || null, modMs: ipt_ts_(x.LastModifiedOn) };
      cin7.push(row); cin7ById[row.ID] = row;
    });
    if (items.length < IPT_LIMIT) break;
    page += 1;
    Utilities.sleep(IPT_THROTTLE);
  }
  P('(0) Cin7 제품 ' + cin7.length + ' · API Total ' + apiTotal + ' · 페이지 ' + page + ' · ' + elapsed());
  // ⚠️ 대량 비활성 안전장치(스킬 규칙 6) — 받은 행 수 ≠ API Total 이면 수집이 짧게 끝난 것 · 지우기가 통째로 틀어진다
  if (cin7.length !== apiTotal) { P('⛔ 받은 행 수 ' + cin7.length + ' ≠ API Total ' + apiTotal + ' — 멈춘다(수집이 짧게 끝났다 · 다시 실행)'); finish('stop'); return; }

  // ── C) 쪼개기 · 정리 ──
  var st = { pieces: 0, empty: 0, oddTrim: 0, inner: 0, dup: 0 }, samples = { inner: [] };
  var withTags = 0, rawRows = 0, cleanRows = 0, spell = {};          // spell[소문자 열쇠][철자] = 제품 수(Cin7 전체)
  cin7.forEach(function (x) {
    var raw = (x.Tags === null || x.Tags === undefined) ? [] : String(x.Tags).split(',').map(function (s) { return s.trim(); }).filter(function (s) { return s !== ''; });
    rawRows += raw.length;
    x.tags = ipt_split_(x.Tags, st, samples);
    if (x.tags.length) withTags++;
    cleanRows += x.tags.length;
    x.tags.forEach(function (t) { var lk = t.toLowerCase(); spell[lk] = spell[lk] || {}; spell[lk][t] = (spell[lk][t] || 0) + 1; });
  });
  P('(1) Tags 있는 제품 ' + withTags + ' · (제품, 태그) 줄 정리 전 ' + rawRows + ' → 정리 뒤 ' + cleanRows + ' · 소문자 열쇠 ' + Object.keys(spell).length);
  P('    조각 ' + st.pieces + ' · 빈 조각 ' + st.empty + ' · 앞뒤 공백(한 칸 앞 말고) ' + st.oddTrim + ' · 안 연속 공백 ' + st.inner + ' · 한 제품 안 중복(정리 뒤) ' + st.dup);
  if (samples.inner.length) P('    안 공백 예: ' + samples.inner.join(' · '));

  // ── D) 철자 정하기(판정 417) ──
  var canon = {}, merged = [], manualWins = 0;
  Object.keys(spell).forEach(function (lk) {
    var c = ipt_canon_(spell[lk], manualSpell[lk] || null);
    canon[lk] = c.tag;
    if (Object.keys(spell[lk]).length > 1 || (manualSpell[lk] && !spell[lk][c.tag])) {
      if (c.reason === 'manual' || c.reason.indexOf('manual') === 0) manualWins++;
      merged.push('    ' + JSON.stringify(spell[lk]) + (manualSpell[lk] ? ' manual ' + JSON.stringify(manualSpell[lk]) : '') + ' → ' + JSON.stringify(c.tag) + ' (' + c.reason + ')');
    }
  });
  P('(2) 철자 합치기 ' + merged.length + ' 묶음 (manual 철자가 이긴 것 ' + manualWins + ') — 규칙: manual > 제품 수 > 앞글자 대문자 > 대문자 수 > 사전순');
  merged.sort().forEach(function (s) { P(s); });
  var kindsAfter = {};
  Object.keys(spell).forEach(function (lk) { kindsAfter[canon[lk]] = true; });
  P('    정본 철자 종류 ' + Object.keys(kindsAfter).length);

  // ── E) 원하는 상태 — IMS 제품(cin7_id 로)만 ──
  var want = {}, wantN = 0, wantProducts = {}, topWant = {};
  var missing = { products: 0, withTags: 0, rows: 0, skus: [], top: {} };   // skus 는 전부(보고 파일) · Logger 는 처음 50
  var skuOnly = { products: 0, rows: 0, skus: [] };
  cin7.forEach(function (x) {
    var pid = byCin7[x.ID];
    if (!pid) {
      if (bySku[x.SKU]) {                                   // cin7_id 로는 못 찾고 SKU 로만 찾힌다 — 쓰지 않고 센다
        skuOnly.products++; skuOnly.rows += x.tags.length; if (skuOnly.skus.length < 20) skuOnly.skus.push(x.SKU);
      } else {
        missing.products++;
        if (x.tags.length) { missing.withTags++; missing.rows += x.tags.length; missing.skus.push(x.SKU + ' [' + x.tags.join(', ') + ']'); x.tags.forEach(function (t) { missing.top[t] = (missing.top[t] || 0) + 1; }); }
      }
      return;
    }
    var seen = {};
    x.tags.forEach(function (t) {
      var c = canon[t.toLowerCase()];
      if (seen[c]) return;                                  // 정리 뒤 같은 정본 철자가 둘 → 하나만
      seen[c] = true;
      want[pid + '|' + c] = true; wantN++; wantProducts[pid] = true;
      topWant[c] = (topWant[c] || 0) + 1;
    });
  });
  P('(3) 원하는 (제품, 정본 철자) ' + wantN + ' 줄 · 제품 ' + Object.keys(wantProducts).length + ' · 종류 ' + Object.keys(topWant).length);
  P('    상위 30: ' + ipt_top_(topWant, 30).map(function (t) { return t + ' ' + topWant[t]; }).join(' · '));
  P('(4) IMS 에 없는 Cin7 제품(버림 · 판정 418) ' + missing.products + ' · 그중 Tags 있는 ' + missing.withTags + ' · 버려질 줄 ' + missing.rows + ' — 컷오버 날 제품 적재를 먼저 돌리면 0 에 가까워야 한다(순서 검사)');
  P('    버려질 태그 상위 15: ' + ipt_top_(missing.top, 15).map(function (t) { return t + ' ' + missing.top[t]; }).join(' · '));
  Logger.log('    SKU 처음 50 / ' + missing.withTags + ': ' + missing.skus.slice(0, 50).map(function (s) { return s.replace(/ \[.*$/, ''); }).join(' ') + ' (전부는 보고 파일에)');
  P('    cin7_id 로 못 찾고 SKU 로만 찾힘(쓰지 않음) ' + skuOnly.products + ' 제품 · 줄 ' + skuOnly.rows + (skuOnly.skus.length ? ' → ' + skuOnly.skus.join(' ') : ''));

  // ── F) diff ──
  var ins = [], insInfo = [], delInfo = [], skipManual = 0, touched = {};
  Object.keys(want).forEach(function (k) {
    if (curCin7[k]) return;
    if (manualKeys[k]) { skipManual++; return; }           // manual 이 있으면 그대로 · 새 cin7 줄을 만들지 않는다
    var i = k.indexOf('|'), pid = k.slice(0, i), tag = k.slice(i + 1);
    ins.push({ product_id: pid, tag: tag, source: 'cin7' });            // ⚠️ 보내는 행은 이 셋뿐(보고용 칸을 섞지 않는다)
    insInfo.push({ product_id: pid, tag: tag });
    touched[pid] = true;
  });
  Object.keys(curCin7).forEach(function (k) {
    if (want[k]) return;
    var i = k.indexOf('|');
    delInfo.push({ tag_id: curCin7[k], product_id: k.slice(0, i), tag: k.slice(i + 1) });
    touched[k.slice(0, i)] = true;
  });
  var del = delInfo.map(function (d) { return d.tag_id; });
  var qTargets = {};
  Object.keys(touched).forEach(function (pid) {
    if (listedProd[pid]) qTargets['p:' + pid] = true;
    var f = famOf[pid]; if (f && listedFam[f]) qTargets['f:' + f] = true;
  });
  P('(5) 넣기 ' + ins.length + ' · 지우기 ' + del.length + ' · manual 이라 건너뜀 ' + skipManual + ' · 건드리는 제품 ' + Object.keys(touched).length);
  P('    큐 영향 짐작: 켜진 shop_listing 대상 ' + Object.keys(qTargets).length + ' (켜진 listing ' + listed.length + ' · 세트의 구성품이 바뀌면 그 세트도 — 여기 셈에 없음)');
  if (ins.length) P('    넣기 표본: ' + JSON.stringify(ins[0]));
  P('    지금 cin7 줄 ' + nCin7 + ' → 끝나면 ' + (nCin7 - del.length + ins.length) + ' (원하는 ' + wantN + ' − manual 겹침 ' + skipManual + ')');

  // ── F2) [ldfix-1d · 판정 676] 바뀔 것 전부 — 딜 표시 · 짐작 · 태그별 묶음 · CSV ──
  var delByLk = {}, insByLk = {};                           // 제품|소문자 열쇠 → 철자(철자 바뀜 짝 찾기)
  delInfo.forEach(function (d) { delByLk[d.product_id + '|' + d.tag.toLowerCase()] = d.tag; });
  insInfo.forEach(function (d) { insByLk[d.product_id + '|' + d.tag.toLowerCase()] = d.tag; });
  function guessIns(d) {
    var old = delByLk[d.product_id + '|' + d.tag.toLowerCase()];
    if (old !== undefined) return '철자 바뀜 ← ' + old;
    var cr = createdOf[d.product_id];
    if (lastApplyMs !== null && cr !== null && cr > lastApplyMs) return '새 제품';
    var x = cin7Of[d.product_id] ? cin7ById[cin7Of[d.product_id]] : null;
    if (!x || x.modMs === null || lastApplyMs === null) return '수정일 없음';
    return x.modMs <= lastApplyMs ? '뗀 것 짐작' : 'Cin7 변화 가능';
  }
  function guessDel(d) {
    var x = cin7Of[d.product_id] ? cin7ById[cin7Of[d.product_id]] : null;
    if (!x) return 'Cin7 에 제품 없음';
    var nw = insByLk[d.product_id + '|' + d.tag.toLowerCase()];
    if (nw !== undefined) return '철자 바뀜 → ' + nw;
    if (x.modMs === null || lastApplyMs === null) return '수정일 없음';
    return x.modMs > lastApplyMs ? 'Cin7 변화 가능' : '어긋남(Cin7 수정일이 적재 앞인데 태그가 없다)';
  }
  function modOf(pid) { var x = cin7Of[pid] ? cin7ById[cin7Of[pid]] : null; return x ? x.Mod : null; }
  function guessKey(g) { return g.replace(/ [←→].*$/, ''); }
  function enrich(list, guessFn) {
    list.forEach(function (d) {
      d.sku = skuOf[d.product_id] || '';
      d.deal = ipt_dealMark_(deals.byTag, d.tag);
      d.guess = guessFn(d);
      d.cin7_modified_on = modOf(d.product_id);
    });
  }
  enrich(insInfo, guessIns); enrich(delInfo, guessDel);
  // 태그별 묶음 — 제품 수 많은 순 · 딜 표시 · 짐작 요약 · SKU 처음 IPT_SKU_PER_TAG
  function groups(list) {
    var g = {};
    list.forEach(function (d) {
      var e = g[d.tag] = g[d.tag] || { tag: d.tag, n: 0, skus: [], guess: {}, deal: d.deal };
      e.n++; if (e.skus.length < IPT_SKU_PER_TAG) e.skus.push(d.sku);
      var gk = guessKey(d.guess); e.guess[gk] = (e.guess[gk] || 0) + 1;
    });
    return Object.keys(g).map(function (t) { return g[t]; }).sort(function (a, b) { return b.n - a.n || (a.tag < b.tag ? -1 : 1); });
  }
  function groupLine(e) {
    return '    ' + JSON.stringify(e.tag) + ' · 제품 ' + e.n + (e.deal ? ' · ' + e.deal : '') + ' · 짐작 ' + Object.keys(e.guess).map(function (k) { return k + ' ' + e.guess[k]; }).join(' / ') +
      ' · SKU ' + e.skus.join(' ') + (e.n > e.skus.length ? ' … (나머지 ' + (e.n - e.skus.length) + ')' : '');
  }
  function guessTotals(list) {
    var c = {}; list.forEach(function (d) { var k = guessKey(d.guess); c[k] = (c[k] || 0) + 1; });
    return Object.keys(c).sort().map(function (k) { return k + ' ' + c[k]; }).join(' · ') || '(없음)';
  }
  function dealTotals(list) {
    var on = {}, off = {}, nOn = 0, nOff = 0;
    list.forEach(function (d) { if (!d.deal) return; if (d.deal.indexOf('딜 ⚠️') === 0) { nOn++; on[d.tag] = (on[d.tag] || 0) + 1; } else { nOff++; off[d.tag] = (off[d.tag] || 0) + 1; } });
    return { nOn: nOn, nOff: nOff, on: on, off: off };
  }
  function section(title, list) {
    var gs = groups(list), dt = dealTotals(list);
    P('(6) ' + title + ' ' + list.length + ' 줄 · 태그 ' + gs.length + ' 종류 · ⚠️ 켜진 딜의 태그 ' + dt.nOn + ' 줄(' + Object.keys(dt.on).length + ' 종류: ' + Object.keys(dt.on).sort().map(function (t) { return t + ' ' + dt.on[t]; }).join(' · ') + ')' +
      ' · 꺼진 딜의 태그 ' + dt.nOff + ' 줄 · 짐작 ' + guessTotals(list));
    gs.forEach(function (e, i) { (i < IPT_LOG_TOP ? P : R)(groupLine(e)); });
    if (gs.length > IPT_LOG_TOP) Logger.log('    … 태그 ' + (gs.length - IPT_LOG_TOP) + ' 종류 더 — 보고 파일에 전부 · 한 줄씩은 CSV 에');
  }
  section('새로 넣을 cin7 태그 (판정 676 — 사람이 본다 · 「뗀 것 짐작」 은 IMS 에서 뗀 것일 수 있다)', insInfo);
  section('지울 cin7 태그 (Cin7 에서 사라짐 — 켜진 딜의 태그면 그 제품의 할인이 사라진다)', delInfo);
  R('(7) IMS 에 없는 Cin7 제품 전부(판정 418 · Tags 있는 것 ' + missing.withTags + ') — SKU [태그]');
  missing.skus.forEach(function (s) { R('    ' + s); });
  folder = ipt_folder_();
  var csvCols = ['sku', 'tag', 'deal', 'guess', 'cin7_modified_on', 'product_id'];
  P('CSV: ' + ipt_file_(folder, 'tag-insert-' + stamp + '.csv', ipt_csv_(csvCols, insInfo), MimeType.CSV) +
    ' · ' + ipt_file_(folder, 'tag-delete-' + stamp + '.csv', ipt_csv_(csvCols.concat(['tag_id']), delInfo), MimeType.CSV) + ' · 폴더 ' + folder.getId());

  // ⚠️ 큰 지우기 안전장치(스킬 규칙 6 의 「대량 비활성」 결) — 지금 cin7 줄의 1% 또는 20 을 넘으면 멈춘다
  var limit = Math.max(20, Math.ceil(nCin7 * 0.01));
  var bigOk = props.getProperty(IPT_ALLOW_PROP) === '1';
  if (del.length > limit) P((dryRun ? '⚠️' : (bigOk ? '⚠️ 허락 속성으로 통과 —' : '⛔')) + ' 지우기 ' + del.length + ' > 한도 ' + limit + (bigOk ? '' : ' — Apply 는 멈춘다 · 맞으면 ' + IPT_ALLOW_PROP + '=1 을 넣고 한 번만'));

  if (dryRun) { P('쓰기 0 · ' + elapsed()); finish('dry'); return; }
  if (del.length > limit && !bigOk) { P('쓰기 0 · 멈춤 · ' + elapsed()); finish('stop'); return; }

  // ── G) 쓰기 — 지우기 → 넣기 · 덩이마다 시간 확인 ──
  var deleted = 0, inserted = 0, stopped = false;
  for (var d = 0; d < del.length; d += IPT_DELETE_CHUNK) {
    if (new Date().getTime() - t0 > IPT_MAX_RUN) { stopped = true; break; }
    var ids = del.slice(d, d + IPT_DELETE_CHUNK);
    var dres = ims_fetch_('/rest/v1/product_tag?source=eq.cin7&id=in.(' + ids.join(',') + ')',
      { method: 'delete', headers: { 'Prefer': 'return=representation' } });
    if (dres.getResponseCode() >= 300) { P('⛔ 지우기 덩이 ' + (d / IPT_DELETE_CHUNK + 1) + ' 실패 HTTP ' + dres.getResponseCode() + ' ' + dres.getContentText().slice(0, 800)); P('지운 줄 ' + deleted + ' · 넣은 줄 0 · 멈춤'); finish('apply'); return; }
    var n = JSON.parse(dres.getContentText()).length;
    if (n !== ids.length) P('⚠️ 지우기 덩이 ' + (d / IPT_DELETE_CHUNK + 1) + ' — 보낸 ' + ids.length + ' · 지워진 ' + n);
    deleted += n;
    if ((d / IPT_DELETE_CHUNK) % 25 === 24) P('  지우기 ' + deleted + ' / ' + del.length);
  }
  if (!stopped) P('⭐ 지운 줄 ' + deleted + ' / ' + del.length);
  for (var i2 = 0; i2 < ins.length && !stopped; i2 += IPT_INSERT_CHUNK) {
    if (new Date().getTime() - t0 > IPT_MAX_RUN) { stopped = true; break; }
    var chunk = ins.slice(i2, i2 + IPT_INSERT_CHUNK);
    try {
      inserted += ipr_upsert_('product_tag', 'product_id,tag', chunk);   // 실패하면 안에서 HTTP · 응답 원문을 찍고 throw
    } catch (e) {
      P('⛔ 넣기 덩이 ' + (i2 / IPT_INSERT_CHUNK + 1) + ' 에서 멈춤 — ' + e.message); P('지운 줄 ' + deleted + ' · 넣은 줄 ' + inserted + ' · 다시 돌리면 남은 것만 한다'); finish('apply'); return;
    }
    P('  넣기 ' + inserted + ' / ' + ins.length);
  }
  if (bigOk) props.deleteProperty(IPT_ALLOW_PROP);
  if (stopped) { P('⏸ 시간 한도 — 지운 줄 ' + deleted + ' · 넣은 줄 ' + inserted + ' · Next run: imsLoadProductTagApply() 를 다시(남은 것만 한다) · ' + elapsed()); finish('apply'); return; }
  props.setProperty(IPT_LAST_APPLY_PROP, new Date().toISOString());
  P('쓰기 넣기 ' + inserted + ' · 지우기 ' + deleted + ' · ' + elapsed() + ' · ' + IPT_LAST_APPLY_PROP + ' = ' + props.getProperty(IPT_LAST_APPLY_PROP));
  P('다음: ~/asung/prompts/tag-1-check.sql 로 대조 → send_tags 는 아직 켜지 않는다(tag-0 ⬜5)');
  finish('apply');
}
