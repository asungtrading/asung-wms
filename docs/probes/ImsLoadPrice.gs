/**
 * ImsLoadPrice.gs — IMS 가격표 적재 (product_price · Cin7 PriceTier1~8)
 * 2026-09-23 작성 · 정본 docs/design/so-module.md §11(11-c 판정 · 11-f 적재로 넘긴 것) · 마이그레이션 20260923154749
 *
 * ⚠️⚠️ 대상: [테스트 · Asung-IMS] — SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY (ImsRefLoad.gs 머리 주석 참조)
 * ⚠️ ims_fetch_ 는 ImsRefLoad.gs 것을 쓴다(같은 프로젝트) — 다시 만들지 않는다 · getProp 은 Config.gs
 * ⚠️ 최상위 const·var 금지 · 식별자 ASCII 만 · 트리거를 걸지 마라(손으로 실행)
 * ⚠️ 이 파일의 이름은 전부 ilp 로 시작한다
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY · SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 * 쓰는 Script Properties: ILP_FOLDER_ID · ILP_NEXT_PAGE · ILP_DONE · ILP_TOTAL · (허락용) ILP_ALLOW_BIG_DOWN
 *
 * ─────────────────────────────────────────────────────────────
 * 실행 순서 — 한 단계씩 · 끝날 때마다 로그를 본다
 *   0  imsLoadPriceCollect   Cin7 제품 전량(IncludeBOM · 500개씩 · 이어 달리기)과 티어 목록을 Drive 에 모은다
 *   1  imsLoadPriceDry       ⭐ 쓰지 않고 센다 — 멈춤 조건 · 새로/바뀜/같음/되살림/내림 · 무접촉(formula·manual) 수
 *   2  imsLoadPriceApply     바뀐 것만 upsert → Cin7 에서 사라진 cin7 줄은 is_active=false(지우지 않는다)
 *                            ⏸ 시간 한도에 걸리면 다시 실행 — 비교해서 남은 것만 보낸다
 *   3  imsLoadPriceVerify    다시 읽어 Cin7 기준과 대조한다 — HTTP 200 만 믿지 않는다
 *   ⟲  imsLoadPriceReset     다시 모을 때만(Drive 폴더는 지우지 않는다)
 *
 * 무엇을 가져오나 (판정 · 정본 11-c · 11-f · Caleb 2026-09-23)
 *   낱개 · 콤보   자기 가격 — Deprecated 도(값이 있으면)            (콤보 = 서로 다른 물건 묶음 · 계산할 수 없다)
 *   세트          Sellable=Yes 만 — 그 값은 「고정가」 줄이 된다       (지금 BEL43475-12 하나 · 셋 16.99)
 *                 Sellable=No 세트는 안 가져온다 — 값이 있어도 뜻이 없다(실측: 4,890 이 낱개 한 개 값과 같다)
 *   ⭐ 세트인가는 IMS product.parent_product_id 로 가른다(DB CHECK 와 같은 기준 · po-module 「pack_factor 와 관계로」)
 *      Cin7 BOM 과 어긋나면 세고 이름을 낸다 — 멈추지 않는다
 *   티어          code 1~8 만 · 9·10 은 IMS 에 없다
 *   값            Cin7 의 0 = 가격 없음 → 줄을 만들지 않는다 · 음수는 건너뛰고 센다 · 숫자가 아니면 멈춘다
 *
 * 재적재 규칙 (po-module §3-f 「한 규칙」 · 판정 2026-09-23)
 *   source='cin7' 줄만 다룬다 — formula · manual 줄은 보지도 덮지도 않는다(같은 열쇠면 건너뛰고 센다)
 *   upsert 열쇠 (product_id, tier_id) · 보내는 칸은 product_id · tier_id · price · source · is_active 다섯뿐
 *   ⚠️ price_set_at · price_set_by 는 보내지 않는다 — 트리거가 「값이 바뀔 때만」 찍는다(같은 값을 다시 써도 안 움직인다)
 *   ⚠️ id · note · updated_* · created_at · cin7_id 도 보내지 않는다(「보내지 않는다」 ≠ 「null 로 보낸다」)
 *   Cin7 에서 사라진 cin7 줄 → is_active=false · 다시 나타나면 upsert 가 is_active:true 로 되살린다
 *
 * 멈춤 조건(추정해 넣지 않는다 — 로그에 적고 throw)
 *   · 받은 행 수 ≠ API Total · 같은 제품 ID 두 번
 *   · Cin7 티어 code 1~8 의 이름이 IMS ref_price_tier.name 과 다르다 · IMS 에 없는 code 에 양수 가격이 있다(새 티어 — Caleb 판정)
 *   · 가격 칸이 숫자가 아니다
 *   · 한 번에 내리는 줄 > max(20, 활성 cin7 줄의 1%) — 맞으면 ILP_ALLOW_BIG_DOWN=1 을 넣고 한 번만 통과
 * ─────────────────────────────────────────────────────────────
 * 2026-09-23 첫 적재 실측 ([테스트 · Asung-IMS] · Caleb 실행 · Drive `ImsLoadPrice 2026-09-23 12:08`)
 *   수집   12:08~12:09 EDT · 38페이지 · 18,963 = API Total · 티어 10(9·10 은 값 없음 — 건너뜀)
 *   Dry    IMS 제품 18,714 · Cin7 에만 있는 제품 249(가격 있는 것 115 · 표본 -EA-ALT-UPC · AMZ00101…) — 제품 재적재 뒤 이 스크립트를 다시 돌리면 채워진다
 *          세트 판정 어긋남 0 · 안 가져온 세트(Sellable No) 6,346 · 음수 0(프로브의 −0.4 는 가져오지 않는 제품에 있다 · 짐작)
 *          바라는 줄 76,872 = 낱개 76,772 · 콤보 97 · 세트 고정가 3(BEL43475-12 T1·T2·T6 = 16.99)
 *          티어별 T1 11,867 · T2 11,807 · T3 11,883 · T4 11,860 · T5 11,341 · T6 8,516 · T7 9,429 · T8 169
 *   Apply  12:14:31~12:15:29 EDT · 한 번에 끝 · 보낸 76,872 = 돌아온 76,872 · 내림 0
 *   Verify 전부 일치(보낼 것 0 · 내릴 것 0 · 활성 cin7 76,872 · 티어 여덟 · 세트 3)
 *   SQL    price_set_by 채움 0(시스템) · 세트 줄 3 · 비활성 제품의 줄 17,925 · 소수 셋째 자리 이상 53(프로브 합 4+5+1+1+2+5+35 와 같다) ·
 *          파는 세트인데 줄 없음 0 · 표본 ABC59130 · BEL43475 · BEL43475-12 · ANU73469 · ANN00023 이 프로브 값과 같다
 * ─────────────────────────────────────────────────────────────
 */


/* ═══════════════════════════════════════════════════════════
   0  수집
   ═══════════════════════════════════════════════════════════ */

function imsLoadPriceCollect() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('ILP_DONE') === '1') {
    Logger.log('이미 다 모았다 — 다음은 imsLoadPriceDry. 새로 모으려면 imsLoadPriceReset 먼저.');
    return;
  }
  var folderId = props.getProperty('ILP_FOLDER_ID');
  var folder;
  if (folderId) {
    folder = DriveApp.getFolderById(folderId);
  } else {
    folder = DriveApp.createFolder('ImsLoadPrice ' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyy-MM-dd HH:mm'));
    props.setProperty('ILP_FOLDER_ID', folder.getId());
    var tiers = ilp_cin7_('ref/priceTier?Page=1&Limit=100').PriceTiers || [];
    folder.createFile('tiers.json', JSON.stringify(tiers), MimeType.PLAIN_TEXT);
    Logger.log('티어 목록 저장 · ' + tiers.length + '행');
  }
  var lim = ilp_limit_();
  var startPage = Number(props.getProperty('ILP_NEXT_PAGE') || '1');
  var page = startPage, started = Date.now(), rows = [], done = false, total = null;
  while (Date.now() - started < 270000) {
    var data = ilp_cin7_('product?Page=' + page + '&Limit=' + lim + '&IncludeDeprecated=true&IncludeBOM=true');
    var items = data.Products || [];
    if (total === null) total = data.Total;
    items.forEach(function (x) { rows.push(ilp_trim_(x)); });
    if (items.length < lim) { done = true; break; }   // ⚠️ Total 이 아니라 받은 행 수로 끝을 판단한다
    page++;
    Utilities.sleep(1500);
  }
  var lastPage = done ? page : page - 1;
  if (rows.length) {
    var name = 'pages-' + ilp_pad_(startPage) + '-' + ilp_pad_(lastPage) + '.json';
    folder.createFile(name, JSON.stringify(rows), MimeType.PLAIN_TEXT);
    Logger.log('저장: ' + name + ' · ' + rows.length + '개');
  }
  if (total !== null) props.setProperty('ILP_TOTAL', String(total));
  if (done) {
    props.setProperty('ILP_DONE', '1');
    props.deleteProperty('ILP_NEXT_PAGE');
    Logger.log('⭐ 수집 끝 — 마지막 페이지 ' + page + ' · API Total ' + total + ' · 다음은 imsLoadPriceDry');
  } else {
    props.setProperty('ILP_NEXT_PAGE', String(page));
    Logger.log('Next run — 다음 페이지 ' + page + ' 부터 · imsLoadPriceCollect 를 한 번 더');
  }
  Logger.log('폴더: ' + folder.getUrl());
}

function imsLoadPriceReset() {
  var props = PropertiesService.getScriptProperties();
  ['ILP_FOLDER_ID', 'ILP_NEXT_PAGE', 'ILP_DONE', 'ILP_TOTAL'].forEach(function (k) { props.deleteProperty(k); });
  Logger.log('ILP_* 속성을 비웠다 — Drive 폴더는 그대로(손으로 지운다)');
}


/* ═══════════════════════════════════════════════════════════
   1  dryRun — 쓰지 않는다
   ═══════════════════════════════════════════════════════════ */

function imsLoadPriceDry() {
  var b = ilp_build_();
  b.report.push('');
  b.report.push('⭐ dryRun 끝 — 아무것도 쓰지 않았다. 숫자가 맞으면 imsLoadPriceApply');
  ilp_writeReport_('dry', b.report);
}


/* ═══════════════════════════════════════════════════════════
   2  Apply — 바뀐 것만 upsert → 사라진 cin7 줄 내리기
   ═══════════════════════════════════════════════════════════ */

function imsLoadPriceApply() {
  var t0 = Date.now();
  var b = ilp_build_();
  var out = ['=== Apply 가격 ' + new Date().toISOString() + ' ==='];
  out.push('보낼 줄 ' + b.send.length + ' (새로 ' + b.n.fresh + ' · 바뀜 ' + b.n.changed + ' · 되살림 ' + b.n.revive + ') · 내릴 줄 ' + b.down.length);

  // ⚠️ 내리기 한도를 upsert 전에 먼저 본다 — 수집 사고면 아무것도 쓰기 전에 멈춘다
  ilp_guardDown_(b.down.length, b.n.dbCin7Active);

  var n = ilp_upsert_(b.send, 500, t0);
  out.push('upsert 돌아온 줄 ' + n + ' / 보낸 ' + b.send.length);

  var downed = ilp_patchIds_(b.down.map(function (r) { return r.id; }), { is_active: false });
  out.push('내린 줄(is_active=false) ' + downed + ' / ' + b.down.length);
  if (b.down.length) out.push('   표본 ' + b.down.slice(0, 15).map(function (r) { return r.label; }).join(', '));
  out.push('');
  out.push('⭐ Apply 끝 — 다음은 imsLoadPriceVerify');
  ilp_writeReport_('apply', out);
}


/* ═══════════════════════════════════════════════════════════
   3  Verify — 다시 읽어 대조
   ═══════════════════════════════════════════════════════════ */

function imsLoadPriceVerify() {
  var b = ilp_build_();
  var out = ['=== 검증 가격 ' + new Date().toISOString() + ' ==='];
  var bad = 0;
  var chk = function (label, got, want) {
    var ok = got === want;
    if (!ok) bad++;
    out.push((ok ? '   ✅ ' : '   ⚠️ ') + label + ' : DB ' + got + ' · Cin7 기준 ' + want);
  };
  // build 가 DB 를 다시 읽어 비교했으므로 「보낼 것」과 「내릴 것」이 0 이어야 한다
  chk('보낼 줄(새로 · 바뀜 · 되살림) 남은 것', b.send.length, 0);
  chk('내릴 줄 남은 것', b.down.length, 0);
  // ⚠️ formula·manual 줄이 차지한 열쇠는 기준에서 뺀다 — 그 자리에는 cin7 줄이 설 수 없다(가짜 데이터 시험에서 1 어긋나 잡았다)
  var wantCin7 = b.want.filter(function (w) { return !w.shadowed; });
  chk('활성 cin7 줄 = Cin7 기준 줄(사람·식 줄 자리 제외 ' + (b.want.length - wantCin7.length) + ')', b.n.dbCin7Active, wantCin7.length);
  var db = b.dbRows;
  b.tiers.forEach(function (t) {
    var got = db.filter(function (r) { return r.source === 'cin7' && r.is_active && r.tier_id === t.id; }).length;
    var want = wantCin7.filter(function (w) { return w.tier_id === t.id; }).length;
    chk('티어 ' + t.code + ' ' + t.name, got, want);
  });
  var setIds = {};
  wantCin7.forEach(function (w) { if (w.kind === 'set') setIds[w.product_id] = true; });
  var setRows = db.filter(function (r) { return r.source === 'cin7' && r.is_active && setIds[r.product_id]; });
  chk('세트 고정가 줄(Sellable=Yes 세트)', setRows.length, wantCin7.filter(function (w) { return w.kind === 'set'; }).length);
  out.push('     세트 줄: ' + setRows.map(function (r) { return b.skuOf[r.product_id] + '·T' + b.codeOf[r.tier_id] + '=' + Number(r.price); }).join(', '));
  out.push('   (참고) formula·manual 줄 ' + b.n.dbOther + ' · 내려 둔 cin7 줄 ' + b.n.dbCin7Inactive);
  out.push(bad ? '⚠️ 어긋남 ' + bad + '곳 — 붙여 달라' : '⭐ 전부 일치');
  ilp_writeReport_('verify', out);
}


/* ═══════════════════════════════════════════════════════════
   행 만들기 — 모든 단계가 같은 결과를 쓴다
   ═══════════════════════════════════════════════════════════ */

function ilp_build_() {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('ILP_FOLDER_ID');
  if (!folderId) throw new Error('ILP_FOLDER_ID 없음 — imsLoadPriceCollect 먼저');
  if (props.getProperty('ILP_DONE') !== '1') throw new Error('수집이 끝나지 않았다 — imsLoadPriceCollect 를 「수집 끝」까지');
  var folder = DriveApp.getFolderById(folderId);

  // ── 수집 파일 ──
  var raw = [], cinTiers = null;
  var files = folder.getFiles();
  while (files.hasNext()) {
    var f = files.next();
    if (f.getName() === 'tiers.json') cinTiers = JSON.parse(f.getBlob().getDataAsString());
    else if (/^pages-.*\.json$/.test(f.getName())) raw = raw.concat(JSON.parse(f.getBlob().getDataAsString()));
  }
  if (!cinTiers) throw new Error('tiers.json 없음 — imsLoadPriceReset → imsLoadPriceCollect');
  var total = Number(props.getProperty('ILP_TOTAL'));
  if (raw.length !== total) throw new Error('⛔ 받은 행 ' + raw.length + ' ≠ API Total ' + total + ' — 수집이 짧다. Reset 뒤 다시 모아라');
  var seen = {};
  raw.forEach(function (x) {
    var id = String(x.ID).toLowerCase();
    if (seen[id]) throw new Error('⛔ 같은 제품 ID 두 번: ' + x.SKU + ' (' + id + ')');
    seen[id] = true;
  });

  var R = [];
  var P = function (s) { R.push(s); };
  P('=== 가격 적재 계산 ' + new Date().toISOString() + ' ===');
  P('Cin7 제품 ' + raw.length + ' = API Total ' + total + ' ✓');

  // ── 티어 — code 로 맞춘다 ──
  var tiers = ilp_readAll_('/rest/v1/ref_price_tier?select=id,code,name,is_active&order=code');
  var tierByCode = {}, codeOf = {};
  tiers.forEach(function (t) { tierByCode[t.code] = t; codeOf[t.id] = t.code; });
  cinTiers.forEach(function (c) {
    var t = tierByCode[Number(c.Code)];
    if (t) {
      if (t.name !== c.Name) throw new Error('⛔ 티어 code ' + c.Code + ' 이름이 다르다 — Cin7 「' + c.Name + '」 · IMS 「' + t.name + '」 · Caleb 판정 뒤 마이그레이션으로');
      return;
    }
    var pos = raw.filter(function (x) { var v = x['PriceTier' + c.Code]; return typeof v === 'number' && v > 0; }).length;
    if (pos > 0) throw new Error('⛔ IMS 에 없는 티어 code ' + c.Code + ' 「' + c.Name + '」 에 양수 가격 ' + pos + '개 — 새 티어다. 쓰임·통화를 Caleb 이 정한 뒤 마이그레이션으로');
    P('티어 code ' + c.Code + ' 「' + c.Name + '」 — IMS 에 없고 값도 없다(건너뛴다)');
  });
  P('IMS 티어 ' + tiers.length + ' — ' + tiers.map(function (t) { return t.code + ' ' + t.name; }).join(' · '));

  // ── IMS 제품 — cin7_id → id · 세트인가 ──
  var prods = ilp_readAll_('/rest/v1/product?select=id,cin7_id,sku,parent_product_id');
  var byCin7 = {}, skuOf = {};
  prods.forEach(function (p) { if (p.cin7_id) byCin7[String(p.cin7_id).toLowerCase()] = p; skuOf[p.id] = p.sku; });
  P('IMS 제품 ' + prods.length);

  // ── Cin7 → 바라는 줄 ──
  var want = [], n = { notInIms: 0, notInImsPos: 0, setSkip: 0, neg: 0, zero: 0, kindDiff: 0,
    base: 0, combo: 0, set: 0, fresh: 0, changed: 0, same: 0, revive: 0, other: 0 };
  var notInImsSample = [], negSample = [], kindDiffSample = [];
  raw.forEach(function (x) {
    var p = byCin7[String(x.ID).toLowerCase()];
    var hasPos = tiers.some(function (t) { var v = x['PriceTier' + t.code]; return typeof v === 'number' && v > 0; });
    if (!p) {
      n.notInIms++;
      if (hasPos) { n.notInImsPos++; if (notInImsSample.length < 15) notInImsSample.push(x.SKU); }
      return;
    }
    var imsSet = !!p.parent_product_id;
    var cinKind = !x.BomN ? 'base' : x.BomN === 1 ? 'set' : 'combo';
    if (imsSet !== (cinKind === 'set')) { n.kindDiff++; if (kindDiffSample.length < 15) kindDiffSample.push(x.SKU + '(IMS ' + (imsSet ? '세트' : '낱개·콤보') + ' · Cin7 ' + cinKind + ')'); }
    var kind = imsSet ? 'set' : (cinKind === 'combo' ? 'combo' : 'base');
    if (kind === 'set' && x.Sellable !== true) { n.setSkip++; return; }
    tiers.forEach(function (t) {
      var v = x['PriceTier' + t.code];
      if (v === null || v === undefined) { n.zero++; return; }
      if (typeof v !== 'number') throw new Error('⛔ 가격이 숫자가 아니다: ' + x.SKU + ' T' + t.code + ' = ' + JSON.stringify(v));
      if (v === 0) { n.zero++; return; }
      if (v < 0) { n.neg++; if (negSample.length < 10) negSample.push(x.SKU + ' T' + t.code + '=' + v); return; }
      want.push({ product_id: p.id, tier_id: t.id, price: ilp_round7_(v), kind: kind });
      n[kind]++;
    });
  });

  // ── DB 가격 줄과 비교 ──
  var dbRows = ilp_readAll_('/rest/v1/product_price?select=id,product_id,tier_id,price,source,is_active');
  var dbByKey = {};
  dbRows.forEach(function (r) { dbByKey[r.product_id + '|' + r.tier_id] = r; });
  var wantKey = {}, send = [];
  want.forEach(function (w) {
    var k = w.product_id + '|' + w.tier_id;
    wantKey[k] = true;
    var d = dbByKey[k];
    var body = { product_id: w.product_id, tier_id: w.tier_id, price: w.price, source: 'cin7', is_active: true };
    if (!d) { n.fresh++; send.push(body); return; }
    if (d.source !== 'cin7') { n.other++; w.shadowed = true; return; }   // formula · manual — 무접촉 · 이 열쇠는 cin7 줄이 설 수 없다
    var same = Math.abs(Number(d.price) - w.price) < 1e-9;
    if (!d.is_active) { n.revive++; send.push(body); return; }
    if (!same) { n.changed++; send.push(body); return; }
    n.same++;
  });
  var down = [];
  dbRows.forEach(function (r) {
    if (r.source === 'cin7' && r.is_active && !wantKey[r.product_id + '|' + r.tier_id]) {
      down.push({ id: r.id, label: skuOf[r.product_id] + '·T' + codeOf[r.tier_id] + '=' + Number(r.price) });
    }
  });
  n.dbCin7Active = dbRows.filter(function (r) { return r.source === 'cin7' && r.is_active; }).length;
  n.dbCin7Inactive = dbRows.filter(function (r) { return r.source === 'cin7' && !r.is_active; }).length;
  n.dbOther = dbRows.filter(function (r) { return r.source !== 'cin7'; }).length;

  // ── 보고 ──
  P('');
  P('Cin7 제품 중 IMS 에 없는 것 ' + n.notInIms + ' · 그중 가격이 있는 것 ' + n.notInImsPos +
    (notInImsSample.length ? ' · 표본 ' + notInImsSample.join(', ') : '') + '  (제품 적재 뒤 새로 생긴 제품 — 먼저 제품 적재가 필요하다)');
  P('세트 판정 어긋남(IMS parent_product_id vs Cin7 BOM) ' + n.kindDiff + (kindDiffSample.length ? ' · 표본 ' + kindDiffSample.join(', ') : '') + '  (IMS 기준으로 따른다)');
  P('안 가져온 세트(Sellable No) ' + n.setSkip + '개');
  P('0·없음 칸 ' + n.zero + ' · ⚠️ 음수 건너뜀 ' + n.neg + (negSample.length ? ' · ' + negSample.join(', ') : ''));
  P('');
  P('바라는 줄 ' + want.length + ' = 낱개 ' + n.base + ' · 콤보 ' + n.combo + ' · 세트(고정가) ' + n.set);
  tiers.forEach(function (t) {
    P('   T' + t.code + ' ' + t.name + ' — ' + want.filter(function (w) { return w.tier_id === t.id; }).length);
  });
  var sets = want.filter(function (w) { return w.kind === 'set'; });
  if (sets.length) P('   세트 고정가 줄: ' + sets.map(function (w) { return skuOf[w.product_id] + '·T' + codeOf[w.tier_id] + '=' + w.price; }).join(', '));
  P('');
  P('DB 지금 — 활성 cin7 ' + n.dbCin7Active + ' · 내려 둔 cin7 ' + n.dbCin7Inactive + ' · formula·manual ' + n.dbOther);
  P('할 일 — 새로 ' + n.fresh + ' · 바뀜 ' + n.changed + ' · 되살림 ' + n.revive + ' · 같음(안 보냄) ' + n.same +
    ' · 무접촉(formula·manual 같은 열쇠) ' + n.other + ' · 내림 ' + down.length);
  if (down.length) P('   내릴 표본 ' + down.slice(0, 15).map(function (r) { return r.label; }).join(', '));
  var lim = Math.max(20, Math.floor(n.dbCin7Active * 0.01));
  if (down.length > lim) P('   ⛔ 내리는 줄이 한도 ' + lim + ' 을 넘는다 — Apply 는 멈춘다(맞으면 ILP_ALLOW_BIG_DOWN=1)');

  return { report: R, want: want, send: send, down: down, n: n, tiers: tiers, dbRows: dbRows, skuOf: skuOf, codeOf: codeOf };
}


/* ═══════════════════════════════════════════════════════════
   도우미
   ═══════════════════════════════════════════════════════════ */

function ilp_limit_() { return 500; }   // BOM 을 켜면 1000 이 안 온다(2026-09-13 실측)

/** 저장할 칸만 — 식별 · 상태 · Sellable · BOM 구성품 수 · 가격 열 칸 */
function ilp_trim_(x) {
  var o = { ID: x.ID, SKU: x.SKU, Status: x.Status, Type: x.Type, Sellable: x.Sellable,
    BomN: (x.BillOfMaterialsProducts || []).length };
  for (var i = 1; i <= 10; i++) o['PriceTier' + i] = x['PriceTier' + i];
  return o;
}

/** numeric(18,7) 에 맞춘다 — 부동소수 꼬리 방지 */
function ilp_round7_(v) { return Math.round(v * 1e7) / 1e7; }

function ilp_cin7_(pathAndQuery) {
  var headers = {
    'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
    'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),
    'Content-Type': 'application/json'
  };
  while (true) {
    var res = UrlFetchApp.fetch('https://inventory.dearsystems.com/ExternalApi/v2/' + pathAndQuery,
      { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) { Logger.log('   429 — 65초 대기 후 재시도'); Utilities.sleep(65000); continue; }
    if (code !== 200) throw new Error('Cin7 ' + code + ' · ' + pathAndQuery + ' : ' + res.getContentText().slice(0, 300));
    return JSON.parse(res.getContentText());
  }
}

/** 보낸 칸만 덮는 upsert — 열쇠 (product_id, tier_id) · 돌아온 줄 수로 성공을 판단한다 */
function ilp_upsert_(rows, size, t0) {
  var total = 0;
  for (var i = 0; i < rows.length; i += size) {
    if (t0 && Date.now() - t0 > 300000) {
      throw new Error('⏸ 시간 한도 — ' + total + '줄까지 썼다. imsLoadPriceApply 를 다시 실행하면 남은 것만 보낸다');
    }
    var part = rows.slice(i, i + size);
    var res = ims_fetch_('/rest/v1/product_price?on_conflict=product_id,tier_id', {
      method: 'post',
      headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' },
      payload: JSON.stringify(part)
    });
    if (res.getResponseCode() >= 300) {
      Logger.log('⚠️ 묶음 ' + (i / size + 1) + ' 실패 HTTP ' + res.getResponseCode());
      Logger.log(res.getContentText().slice(0, 800));
      throw new Error('적재 중단 — 여기까지 쓰인 줄 ' + total);
    }
    var back = JSON.parse(res.getContentText()).length;
    if (back !== part.length) throw new Error('⚠️ 돌아온 줄 ' + back + ' ≠ 보낸 ' + part.length);
    total += back;
    Logger.log('  product_price ' + total + ' / ' + rows.length);
  }
  return total;
}

function ilp_guardDown_(count, baseCount) {
  var limit = Math.max(20, Math.floor((baseCount || 0) * 0.01));
  if (count <= limit) return;
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('ILP_ALLOW_BIG_DOWN') !== '1') {
    throw new Error('⛔ 가격 ' + count + '줄을 내리려 한다(한도 ' + limit + ') — 수집 사고인지 먼저 보라. ' +
      '맞으면 Script Property ILP_ALLOW_BIG_DOWN=1 을 넣고 다시 실행');
  }
  props.deleteProperty('ILP_ALLOW_BIG_DOWN');
  Logger.log('⚠️ ILP_ALLOW_BIG_DOWN 로 한도를 넘겨 내린다 — ' + count + '줄 · 속성은 지웠다');
}

function ilp_patchIds_(ids, body) {
  var done = 0;
  for (var i = 0; i < ids.length; i += 100) {
    var part = ids.slice(i, i + 100);
    var res = ims_fetch_('/rest/v1/product_price?id=in.(' + part.join(',') + ')', {
      method: 'patch', headers: { 'Prefer': 'return=representation' }, payload: JSON.stringify(body)
    });
    if (res.getResponseCode() >= 300) throw new Error('product_price PATCH 실패 HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
    done += JSON.parse(res.getContentText()).length;
  }
  return done;
}

/** 전량 읽기 — ⚠️ PostgREST 1,000행 캡 · Range 로 끝까지 · 총계와 대조 */
function ilp_readAll_(path) {
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
  if (total !== null && out.length < total) throw new Error('⚠️ 읽기가 잘렸다: ' + out.length + ' / ' + total + ' — 멈춘다');
  if (total === null && out.length > 0 && out.length % step === 0) throw new Error('⚠️ 총계를 못 읽었는데 정확히 ' + out.length + '행 — 캡일 수 있다. 멈춘다');
  return out;
}

function ilp_writeReport_(tag, lines) {
  var text = lines.join('\n');
  var folderId = PropertiesService.getScriptProperties().getProperty('ILP_FOLDER_ID');
  if (folderId) {
    DriveApp.getFolderById(folderId).createFile('report-' + tag + '-' +
      Utilities.formatDate(new Date(), 'America/Toronto', 'yyyyMMdd-HHmmss') + '.txt', text, MimeType.PLAIN_TEXT);
  }
  for (var i = 0; i < text.length; i += 8000) Logger.log(text.slice(i, i + 8000));
}

function ilp_pad_(n) { return ('000' + n).slice(-4); }
