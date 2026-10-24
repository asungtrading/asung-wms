/**
 * ImsLoadSupplier.gs — IMS ② 공급처 적재: 본 행(supplier) · 주소(supplier_address) · 연락처(supplier_contact)
 * 2026-10-24 · ldfix-1c · 판정 673(본 행 적재를 새로) · 674 · 680 · 681 · 672 · 671 · 정본 po-module §7-a · §3-f · so-module §72
 *
 * ⚠️⚠️ 대상: [테스트 · Asung-IMS] — SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY (ImsRefLoad.gs 머리 주석 참조)
 * ⚠️ ims_fetch_ · ims_blank_ 는 ImsRefLoad.gs(편집기 ProbeIMS.js) 것을 쓴다 · getProp 은 Config.gs — 다시 만들지 않는다
 * ⚠️ 최상위 const · var 금지 · 식별자 ASCII 만 · 트리거 없음(손으로 실행) · 이 파일의 이름은 전부 ils 로 시작한다(실행 함수 imsLoad* 빼고)
 * ⚠️ 편집기 ProbeSupplier.js 의 imsLoadSupplierSub · imsLoadPurchasable 덩이(513 ~ 707 행)는 이 파일로 옮겼다 — 그쪽을 지운다(같은 이름이 둘이면 뒤가 이긴다)
 *
 * 필요한 Script Properties: CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY · SUPABASE_IMS_URL · SUPABASE_IMS_SERVICE_KEY
 * 쓰는 Script Properties: ILS_LAST_APPLY_AT(672 보조 · Apply 끝) · (허락용) ILS_ALLOW_BIG_DOWN=1(대량 내리기를 한 번만 통과)
 *
 * 실행 순서 — Drive 수집 없음(Cin7 688 행 · 7 쪽 · 매번 다시 읽는다 · 받은 행 ≠ API Total 이면 멈춤)
 *   1  imsLoadSupplier           ⭐ 쓰지 않고 센다 — 새 행 · 갱신 · 짝(674) · 손댄 행(672) · is_active IMS 값 유지(680) · 이름 겹침(23505 사전 검사) · 내릴 행
 *   2  imsLoadSupplierApply      짝짓기 PATCH → upsert(cin7_id) → Cin7 에 없는 cin7 행 is_active=false
 *   3  imsLoadSupplierSub        쓰지 않고 센다 — 주소 · 연락처
 *   4  imsLoadSupplierSubApply   내리기(Cin7 에 없는 cin7 줄 is_active=false · 기본 풀기) → upsert(cin7_id · 한 공급처의 줄은 한 요청에)
 *   5  imsLoadSupplierVerify     다시 읽어 센다
 *   그 뒤  imsLoadSupplierExtraApply → imsLoadProductSupplierApply (ImsLoadProductSupplier.gs · 제품이 가리키는 새 비활성 공급처 · 제품↔공급처 줄)
 *   ⛔ imsLoadPurchasable(Apply) 는 실행 순서에 없다 — 2026-09-11 시트 값을 다시 쓴다 · 컷오버 날 돌리지 않는다(새 ③)
 *
 * 규칙
 *   범위    새 행은 Cin7 활성만 넣는다(§7-a) · 우리 표에 이미 있는 cin7 행은 Cin7 상태와 무관하게 갱신(비활성 31 포함 · §3-g) · 새 비활성은 넣지 않는다(제품이 가리키면 imsLoadSupplierExtra 몫)
 *           Cin7 전량(IncludeDeprecated)에 없는 cin7 행 → is_active=false(지우지 않는다 · 대량 내리기 안전장치 max(20, 1 %))
 *   열쇠    cin7_id · 새 행 · 갱신 모두 on_conflict=cin7_id
 *   674 · 681  cin7_id 없는 IMS 공급처(source manual)와 「보이는 글자가 정확히 같은」 이름(U+200B · U+200C · U+200D · U+FEFF · U+00A0 를 빼고 trim) → IMS 행에 cin7_id 만 PATCH · 묶음에서 뺀다 · 값이 다른 칸 로그
 *           저장은 원문 그대로 · 같은 비교로 이름 겹침(supplier_name_key 23505)을 미리 걸러 멈춤
 *   672     source=cin7 이면서 updated_by 가 있는 행(지난 적재 뒤 직원이 창구로 고친 행 · 적재가 쓰면 ims_touch 가 비운다)의 「IMS 값 ↔ Cin7 값」 을 로그에 — Cin7 값이 덮는다(이름 · 결제조건 · 계정 · 통화 · 세금 규칙 · 메모)
 *   680 · 683  ⭐ is_active_source='ims' 인 행(IMS 창구가 켜거나 껐다 · ldfix-1c2 마이그레이션 · 몇 번 적재해도 남는다)의 is_active 는 IMS 값을 같은 키로 싣는다(Cin7 Deprecated 를 IMS 가 켠 Energizer Canada 류 · 로그 「is_active 는 IMS 값 유지」)
 *           (ldfix-1c 의 updated_by 기준은 적재가 비워 한 번만 통했다 → 판정 683 으로 칸을 두었다) · 672 목록의 기준은 그대로 updated_by
 *   682     Apply 끝에 rpc product_supplier_default_recalc(전체)를 부른다 — 공급처 켜짐이 바뀌었으면 기본 공급처가 따라간다(§3-g ① 끄기 → ② 켜기 · 멱등) · 「기본 둘 이상 > 0」 이면 ⚠️
 *   보내지 않는 칸  is_purchasable · is_discontinued · discontinued_on · note · id · created_* · updated_*(IMS 칸 · §7-a) — 「보내지 않는다」 ≠ 「null 로 보낸다」
 *   주소 · 연락처  짝지은 공급처(source manual · cin7_id 있음)의 Cin7 줄은 적재하지 않는다(연락처 기본 하나 supplier_contact_default_uq 가 IMS 기본과 23505 로 부딪친다)
 *           'no longer purchase' 이름의 연락처는 행을 만들지 않는다(§7-b) · 손댄 cin7 줄은 672 로그 · 사라진 cin7 줄은 내린다
 */

function imsLoadSupplier()         { ils_load_(true); }
function imsLoadSupplierApply()    { ils_load_(false); }
function imsLoadSupplierSub()      { ils_loadSub_(true); }
function imsLoadSupplierSubApply() { ils_loadSub_(false); }

/* ═══════════════════════════════════════════════════════════
   1 · 2  본 행 — 판정 673
   ═══════════════════════════════════════════════════════════ */

function ils_load_(dryRun) {
  var props = PropertiesService.getScriptProperties();
  var b = ils_build_();
  var rep = b.report;
  if (dryRun) { rep.push('(dryRun — 쓰지 않았다) · 숫자가 맞으면 imsLoadSupplierApply'); ils_log_(rep); return; }
  if (b.stop.length) { ils_log_(rep); throw new Error('⛔ 멈춤 ' + b.stop.length + '건 — 로그를 보라'); }

  var paired = ils_pairPatch_('supplier', b.pairs);
  rep.push('짝지은 IMS 공급처(cin7_id 만 · 674) ' + paired + ' / ' + b.pairs.length);
  var n = ils_upsert_('supplier', b.rows, 200);
  rep.push('upsert 돌아온 행 ' + n + ' / 보낸 ' + b.rows.length + ' (갱신 ' + b.counts.update + ' · 새 행 ' + b.counts.fresh + ')');
  var down = ils_patchIn_('supplier', b.gone.map(function (r) { return r.cin7_id; }), { is_active: false }, b.rows.length);
  rep.push('Cin7 에 없어 내린 공급처 ' + down + (b.gone.length ? ' : ' + b.gone.slice(0, 20).map(function (r) { return r.name; }).join(' · ') : ''));
  rep.push(ils_recalc_());                                                       // 판정 682 — 켜짐이 바뀐 공급처의 제품 기본 공급처
  props.setProperty('ILS_LAST_APPLY_AT', new Date().toISOString());
  rep.push('ILS_LAST_APPLY_AT = ' + props.getProperty('ILS_LAST_APPLY_AT') + ' · 다음은 imsLoadSupplierSub');
  ils_log_(rep);
}

/** Cin7 전량 + 우리 표 → 보낼 행 · 짝 · 손댄 행 · 내릴 행 · 멈춤 조건 — Dry · Apply · Verify 가 같은 판정을 쓴다 */
function ils_build_() {
  var cin7 = ils_cin7_();
  var rep = ['=== 공급처 적재 ' + new Date().toISOString() + ' === Cin7 전량 ' + cin7.rows.length + ' (API Total ' + cin7.total + ')'];
  var stop = [];
  if (cin7.rows.length !== cin7.total) stop.push('받은 행 ' + cin7.rows.length + ' ≠ API Total ' + cin7.total + ' — 다시 돌려라');

  var term = ils_mapBy_('/rest/v1/ref_payment_term?select=id,name', 'name');
  var acct = ils_mapBy_('/rest/v1/ref_account?select=id,code', 'code');
  var cur  = ils_mapBy_('/rest/v1/ref_currency?select=id,code', 'code');

  var db = ils_readAll_('/rest/v1/supplier?select=*');
  var byCin7 = {}, byVis = {}, nManual = 0, nPaired = 0;
  db.forEach(function (r) {
    if (r.cin7_id) byCin7[String(r.cin7_id)] = r;
    var k = ils_vis_(r.name);
    if (byVis[k]) stop.push('우리 표에 보이는 글자가 같은 이름이 둘: ' + JSON.stringify(r.name) + ' / ' + JSON.stringify(byVis[k].name));
    byVis[k] = r;
    if (r.source === 'manual') { if (r.cin7_id) nPaired++; else nManual++; }
  });

  var rows = [], pairs = [], touched = [], kept = [], seenCin7 = {}, counts = { update: 0, fresh: 0, skipInactiveNew: 0, cin7Active: 0, pairedSkip: 0 };
  var miss = { term: {}, acct: {}, cur: {} };
  cin7.rows.forEach(function (s) {
    seenCin7[String(s.ID)] = true;
    var st = String(s.Status);
    if (st !== 'Active' && st !== 'Deprecated') stop.push('Status 가 둘 밖: ' + st + ' — ' + s.Name);
    if (st === 'Active') counts.cin7Active++;
    var tName = ims_blank_(s.PaymentTerm) || '', aCode = ims_blank_(s.AccountPayable) || '', cCode = ims_blank_(s.Currency);
    if (tName && !term[tName]) miss.term[tName] = (miss.term[tName] || 0) + 1;
    if (aCode && !acct[aCode]) miss.acct[aCode] = (miss.acct[aCode] || 0) + 1;
    if (cCode && !cur[cCode]) miss.cur[cCode] = (miss.cur[cCode] || 0) + 1;
    var row = {
      cin7_id: String(s.ID),
      name: String(s.Name),                              // 원문 그대로(판정 681 — 비교만 보이는 글자로)
      is_active: st === 'Active',
      source: 'cin7',
      payment_term_id: tName ? (term[tName] || null) : null,
      payment_term_name: tName,                          // NOT NULL — 빈값이면 ''
      account_payable_id: aCode ? (acct[aCode] || null) : null,
      account_payable_code: aCode,                       // NOT NULL
      currency_id: cCode ? (cur[cCode] || null) : null,
      tax_rule: ims_blank_(s.TaxRule),
      cin7_comments: ims_blank_(s.Comments)
    };
    var ex = byCin7[row.cin7_id];
    if (ex && ex.source !== 'cin7') { counts.pairedSkip++; return; }   // 이미 짝지은 IMS 공급처 — IMS 값이 이긴다(판정 132) · 매 회차 건드리지 않는다
    if (ex) {
      // 이름 겹침 사전 검사 — Cin7 이 바꾼 이름이 우리 표의 다른 행과 같으면 supplier_name_key 23505
      var other = byVis[ils_vis_(row.name)];
      if (other && other.id !== ex.id) stop.push('이름 겹침(23505): Cin7 ' + JSON.stringify(row.name) + '(cin7_id ' + row.cin7_id + ') 이 우리 표의 다른 행 ' + JSON.stringify(other.name) + '(' + other.source + ') 과 같다');
      if (ex.is_active_source === 'ims') {               // 판정 683(680 의 기준을 칸으로) — IMS 가 켜거나 끈 공급처의 is_active 는 IMS 값
        if (row.is_active !== ex.is_active) kept.push(ex.name + ' : IMS ' + ex.is_active + ' (Cin7 ' + row.is_active + ')');
        row.is_active = ex.is_active;
      }
      if (ex.updated_by) {                               // 판정 672 — 손댄 행 목록(is_active 가 유지됐으면 차이에 안 보인다)
        var d = ils_diff_(ex, row, ['cin7_id', 'source', 'is_active_source']);
        touched.push(ex.name + ' (updated_at ' + ex.updated_at + ')' + (d.length ? ' — 덮임: ' + d.join(' / ') : ' — 덮여도 값 그대로'));
      }
      counts.update++;
      rows.push(row);
      return;
    }
    var m = byVis[ils_vis_(row.name)];
    if (m) {
      if (m.source === 'manual' && !m.cin7_id) { pairs.push({ ims_id: m.id, cin7_id: row.cin7_id, name: m.name, diffs: ils_diff_(m, row, ['cin7_id', 'source', 'is_active']) }); return; }
      stop.push('이름 겹침(23505): Cin7 ' + JSON.stringify(row.name) + '(cin7_id ' + row.cin7_id + ') 이 우리 표의 ' + m.source + ' 행 ' + JSON.stringify(m.name) + '(cin7_id ' + (m.cin7_id || '-') + ') 과 같다 — 사람이 가른다');
      return;
    }
    if (!row.is_active) { counts.skipInactiveNew++; return; }   // 새 비활성은 넣지 않는다(§7-a · 제품이 가리키면 Extra 몫)
    counts.fresh++;
    rows.push(row);
  });
  var gone = db.filter(function (r) { return r.source === 'cin7' && r.cin7_id && !seenCin7[String(r.cin7_id)] && r.is_active; });
  var unseenTouched = db.filter(function (r) { return r.source === 'cin7' && r.updated_by && !seenCin7[String(r.cin7_id)]; });

  rep.push('우리 표 ' + db.length + ' (cin7 ' + (db.length - nManual - nPaired) + ' · IMS 에서 만든 ' + nManual + ' · 이미 짝지은 ' + nPaired + ') · 지난 적재 시각 ' + (PropertiesService.getScriptProperties().getProperty('ILS_LAST_APPLY_AT') || '(속성 없음)'));
  rep.push('보낼 행 ' + rows.length + ' = 갱신 ' + counts.update + ' + 새 행 ' + counts.fresh + ' · 새 비활성(안 넣음) ' + counts.skipInactiveNew + ' · Cin7 활성 ' + counts.cin7Active);
  rep.push('⭐ 짝지은 IMS 공급처(674 · 681 · cin7_id 만) 이번 ' + pairs.length + ' · 이미 짝지어진(안 보냄) ' + counts.pairedSkip + ' · 손댄 행(672 · Cin7 이 덮는다) ' + touched.length + ' · is_active IMS 값 유지(680) ' + kept.length + ' · Cin7 에 없어 내릴 행 ' + gone.length);
  pairs.forEach(function (p) { rep.push('   [674 짝] ' + JSON.stringify(p.name) + ' ← cin7_id ' + p.cin7_id + (p.diffs.length ? ' · 값이 다른 칸 ' + p.diffs.join(' / ') : ' · 다른 칸 없음')); });
  kept.forEach(function (k) { rep.push('   [680 is_active 는 IMS 값 유지] ' + k); });
  touched.forEach(function (t) { rep.push('   [672 손댄 행] ' + t); });
  unseenTouched.forEach(function (r) { rep.push('   [672 손댄 행] ' + r.name + ' — 덮이지 않음(Cin7 전량에 없음)'); });
  gone.forEach(function (r) { rep.push('   [내림] ' + r.name); });
  rep.push('FK 못 붙은 값(원문 칸에는 남는다): payment_term ' + ils_fmt_(miss.term) + ' · account ' + ils_fmt_(miss.acct) + ' · currency ' + ils_fmt_(miss.cur));
  if (stop.length) { rep.push('⛔ 멈춤 ' + stop.length + '건 — 아무것도 쓰지 않는다'); stop.forEach(function (s) { rep.push('   ' + s); }); }
  return { rows: rows, pairs: pairs, gone: gone, counts: counts, stop: stop, report: rep, cin7: cin7, byCin7: byCin7 };
}

/* ═══════════════════════════════════════════════════════════
   3 · 4  주소 · 연락처 — 편집기 ProbeSupplier.js 의 SupplierSub 를 옮김 + 672 · 674 · 내리기(판정 ⑩ 꼴)
   ═══════════════════════════════════════════════════════════ */

function ils_loadSub_(dryRun) {
  var cin7 = ils_cin7_();
  var rep = ['=== 공급처 주소 · 연락처 ' + new Date().toISOString() + ' === Cin7 전량 ' + cin7.rows.length + ' (API Total ' + cin7.total + ')'];
  if (cin7.rows.length !== cin7.total) { ils_log_(rep.concat(['⛔ 받은 행 ≠ API Total — 다시 돌려라'])); throw new Error('받은 행 ' + cin7.rows.length + ' ≠ API Total ' + cin7.total); }

  // 우리 본체 — cin7_id → {id, source} · 짝지은 IMS 공급처(manual · cin7_id 있음)의 줄은 적재하지 않는다
  var sup = {}, skipSup = {};
  ils_readAll_('/rest/v1/supplier?select=id,cin7_id,source&cin7_id=not.is.null').forEach(function (r) { sup[String(r.cin7_id)] = r.id; if (r.source !== 'cin7') skipSup[String(r.cin7_id)] = true; });

  var addrs = [], contacts = [], orphan = [], skippedNlp = 0, skippedPaired = { a: 0, c: 0 };
  cin7.rows.forEach(function (s) {
    if (String(s.Status) !== 'Active') return;           // 활성 공급처의 줄만(§7-b · 옛 SupplierSub 와 같다)
    var supId = sup[String(s.ID)];
    if (!supId) { orphan.push(s.Name); return; }
    if (skipSup[String(s.ID)]) { skippedPaired.a += (s.Addresses || []).length; skippedPaired.c += (s.Contacts || []).length; return; }
    (s.Addresses || []).forEach(function (a) {
      addrs.push({ cin7_id: String(a.ID), supplier_id: supId, is_active: true, source: 'cin7', type: ims_blank_(a.Type),
                   line1: ims_blank_(a.Line1), line2: ims_blank_(a.Line2), city: ims_blank_(a.City), state_province: ims_blank_(a.State), postal_code: ims_blank_(a.Postcode), country: ims_blank_(a.Country) });
    });
    (s.Contacts || []).forEach(function (c) {
      if (String(c.Name || '').trim().toLowerCase() === 'no longer purchase') { skippedNlp++; return; }   // 거래 중단 표시는 연락처가 아니다(§7-b)
      contacts.push({ cin7_id: String(c.ID), supplier_id: supId, is_active: true, source: 'cin7', name: ims_blank_(c.Name), phone: ims_blank_(c.Phone), mobile_phone: ims_blank_(c.MobilePhone),
                      fax: ims_blank_(c.Fax), email: ims_blank_(c.Email), website: ims_blank_(c.Website), is_default: c.Default === true, cin7_comment: ims_blank_(c.Comment) });
    });
  });
  rep.push('보낼 줄 — 주소 ' + addrs.length + ' · 연락처 ' + contacts.length + ' · 거래 중단 표시라 건너뜀 ' + skippedNlp + ' · 짝지은 IMS 공급처의 Cin7 줄 건너뜀(674) 주소 ' + skippedPaired.a + ' · 연락처 ' + skippedPaired.c);
  rep.push('cin7_id 중복 — 주소 ' + ils_dup_(addrs) + ' · 연락처 ' + ils_dup_(contacts));
  if (orphan.length) { rep.push('⛔ 본체에서 못 찾은 공급처 ' + orphan.length + ' → ' + orphan.slice(0, 10).join(' · ') + ' — imsLoadSupplierApply 를 먼저'); }

  // 672 — 손댄 cin7 줄
  var touchedLines = [];
  [['supplier_address', addrs, ['cin7_id', 'source', 'supplier_id']], ['supplier_contact', contacts, ['cin7_id', 'source', 'supplier_id']]].forEach(function (t) {
    var byCin7 = {};
    t[1].forEach(function (r) { byCin7[r.cin7_id] = r; });
    ils_readAll_('/rest/v1/' + t[0] + '?select=*&source=eq.cin7&updated_by=not.is.null').forEach(function (r) {
      var c = byCin7[String(r.cin7_id)], label = t[0] + ' ' + (r.name || r.line1 || r.cin7_id) + ' (updated_at ' + r.updated_at + ')';
      if (!c) { touchedLines.push(label + ' — 덮이지 않음(이번 Cin7 에 없음)'); return; }
      var d = ils_diff_(r, c, t[2]);
      touchedLines.push(label + (d.length ? ' — 덮임: ' + d.join(' / ') : ' — 덮여도 값 그대로'));
    });
  });
  rep.push('손댄 cin7 줄(672 · Cin7 이 덮는다) ' + touchedLines.length);
  touchedLines.forEach(function (l) { rep.push('   [672] ' + l); });

  // 내릴 줄 — source=cin7 · 이번에 안 온 cin7_id · 아직 활성이거나 기본인 것
  var gone = {};
  [['supplier_address', addrs, { is_active: false }], ['supplier_contact', contacts, { is_active: false, is_default: false }]].forEach(function (t) {
    var inCin7 = {};
    t[1].forEach(function (r) { inCin7[r.cin7_id] = true; });
    gone[t[0]] = ils_readAll_('/rest/v1/' + t[0] + '?select=cin7_id,is_active&source=eq.cin7').filter(function (r) { return r.cin7_id && !inCin7[String(r.cin7_id)] && r.is_active; }).map(function (r) { return r.cin7_id; });
    rep.push('Cin7 에 없어 내릴 ' + t[0] + ' ' + gone[t[0]].length);
  });

  if (dryRun) { rep.push('(dryRun — 쓰지 않았다) · 숫자가 맞으면 imsLoadSupplierSubApply'); ils_log_(rep); return; }
  if (orphan.length) { ils_log_(rep); throw new Error('본체에서 못 찾은 공급처 ' + orphan.length + ' — imsLoadSupplierApply 를 먼저'); }

  // ① 먼저 내리기(판정 ⑩ 순서) → ② upsert(한 공급처의 줄은 한 요청에 · 연락처 기본 하나는 deferrable)
  var dA = ils_patchIn_('supplier_address', gone.supplier_address, { is_active: false }, addrs.length);
  var dC = ils_patchIn_('supplier_contact', gone.supplier_contact, { is_active: false, is_default: false }, contacts.length);
  rep.push('① 내린 줄 — 주소 ' + dA + ' · 연락처 ' + dC);
  var nA = ils_upsert_('supplier_address', addrs, 200, 'supplier_id');
  var nC = ils_upsert_('supplier_contact', contacts, 200, 'supplier_id');
  rep.push('② upsert 돌아온 줄 — 주소 ' + nA + ' / ' + addrs.length + ' · 연락처 ' + nC + ' / ' + contacts.length);
  PropertiesService.getScriptProperties().setProperty('ILS_LAST_APPLY_AT', new Date().toISOString());
  rep.push('다음은 imsLoadSupplierVerify');
  ils_log_(rep);
}

/* ═══════════════════════════════════════════════════════════
   5  검증 — 다시 읽어 센다
   ═══════════════════════════════════════════════════════════ */

function imsLoadSupplierVerify() {
  var b = ils_build_();
  var rep = ['=== 검증 ' + new Date().toISOString() + ' ==='];
  var sentCin7 = {};
  b.rows.forEach(function (r) { sentCin7[r.cin7_id] = r; });
  var dbCin7 = ils_readAll_('/rest/v1/supplier?select=cin7_id,is_active&source=eq.cin7');
  var goneKept = dbCin7.filter(function (r) { return r.cin7_id && !sentCin7[String(r.cin7_id)]; }).length;
  // is_active 는 대조하지 않는다 — 680 의 표식(updated_by)을 적재가 비워 다시 만든 계획과 DB 가 갈릴 수 있다 · 대신 「Cin7 상태와 다른 cin7 행」 을 이름으로 찍는다
  var cin7Status = {};
  b.cin7.rows.forEach(function (s) { cin7Status[String(s.ID)] = String(s.Status) === 'Active'; });
  var differs = ils_readAll_('/rest/v1/supplier?select=name,cin7_id,is_active&source=eq.cin7').filter(function (r) { return r.cin7_id && cin7Status[String(r.cin7_id)] !== undefined && cin7Status[String(r.cin7_id)] !== r.is_active; });
  var pairs = [
    ['supplier(source=cin7) 전체 = 이번에 보낼 행 + 내려 둔 행', '/rest/v1/supplier?select=id&source=eq.cin7', b.rows.length + goneKept],
    ['supplier IMS 에서 만든 행 중 cin7_id 없음 = Cin7 와 짝이 안 된 것', '/rest/v1/supplier?select=id&source=eq.manual&cin7_id=is.null', b.pairs.length ? -1 : null]
  ];
  var bad = 0;
  pairs.forEach(function (p) {
    var got = ils_count_(p[1]);
    if (p[2] === null) { rep.push('   (' + p[0] + ' : DB ' + got + ' — 대조하지 않는다)'); return; }
    if (p[2] === -1) { rep.push('   ⚠️ ' + p[0] + ' : DB ' + got + ' — 짝이 ' + b.pairs.length + ' 남아 있다(Apply 를 먼저)'); bad++; return; }
    var ok = got === p[2];
    if (!ok) bad++;
    rep.push((ok ? '   ✅ ' : '   ⚠️ ') + p[0] + ' : DB ' + got + ' · 기준 ' + p[2]);
  });
  rep.push('   (is_active 가 Cin7 상태와 다른 cin7 행 ' + differs.length + (differs.length ? ' → ' + differs.map(function (r) { return r.name + '(IMS ' + r.is_active + ')'; }).join(' · ') : '') + ' — 683 is_active_source=ims 로 지키는 것 · 대조하지 않는다)');
  rep.push('   (내려 둔 cin7 행 ' + goneKept + ' · 손댄 행 ' + ils_count_('/rest/v1/supplier?select=id&source=eq.cin7&updated_by=not.is.null') + ' — 적재 뒤 0 이어야 한다)');
  rep.push('   (주소 활성(cin7) ' + ils_count_('/rest/v1/supplier_address?select=id&source=eq.cin7&is_active=eq.true') + ' · 연락처 활성(cin7) ' + ils_count_('/rest/v1/supplier_contact?select=id&source=eq.cin7&is_active=eq.true') + ' · 연락처 기본(cin7) ' + ils_count_('/rest/v1/supplier_contact?select=id&source=eq.cin7&is_active=eq.true&is_default=eq.true') + ' — imsLoadSupplierSub 의 보낼 줄과 견준다)');
  rep.push(bad ? '⚠️ 어긋남 ' + bad + '곳' : '⭐ 본 행 전부 일치');
  ils_log_(rep);
}

/* ═══════════════════════════════════════════════════════════
   ⛔ 구매 가능 PATCH — 편집기 ProbeSupplier.js 에서 옮김 · 컷오버 날 돌리지 않는다(새 ③)
   ⚠️⚠️ 2026-09-11 시트(1AqoQPQejFcZfkkwRWDFKMw4GVkM2HcGT5vNRSfI-HJU)의 판정 217 곳을 다시 쓴다 — IMS 가 그 뒤 Settings 에서 바꾼 is_purchasable(예: Energizer Canada Yes · 2026-10-23)을 되돌린다
   ⚠️ is_purchasable 의 정본은 이제 IMS 다(판정 237 · 238 · supplier_update) · 이 함수는 첫 적재(2026-09-11)의 기록으로만 남긴다
   ═══════════════════════════════════════════════════════════ */
function imsLoadPurchasable()      { ils_loadPurchasable_(true); }
function imsLoadPurchasableApply() { ils_loadPurchasable_(false); }

function ils_loadPurchasable_(dryRun) {
  Logger.log('⛔ 컷오버 날 돌리지 않는다 — 2026-09-11 시트 값을 다시 쓴다(IMS 가 그 뒤 바꾼 is_purchasable 을 되돌린다) · dryRun 만 허용');
  var sheetId = '1AqoQPQejFcZfkkwRWDFKMw4GVkM2HcGT5vNRSfI-HJU';
  var sh = SpreadsheetApp.openById(sheetId).getSheets()[0];
  var values = sh.getDataRange().getValues();
  Logger.log('시트: ' + sh.getParent().getName() + ' / ' + sh.getName());
  Logger.log('데이터 행: ' + (values.length - 1));

  var idxJudge = 0;                      // A열
  var idxName  = 1;                      // B열
  var idxId    = values[0].length - 1;   // 마지막 열 = ID
  if (String(values[0][idxId]).trim() !== 'ID') {
    Logger.log('⚠️ 마지막 열이 ID 가 아니다 → "' + values[0][idxId] + '" — 멈춘다');
    return;
  }

  var trueRows = [], falseRows = [], skipRows = [], odd = [];
  for (var i = 1; i < values.length; i++) {
    var raw  = String(values[i][idxJudge] || '').trim().toUpperCase();
    var name = String(values[i][idxName] || '');
    var id   = String(values[i][idxId] || '').trim();
    if (!id) { odd.push('행 ' + (i + 1) + ' ID 없음 (' + name + ')'); continue; }

    if (raw === 'O')                    trueRows.push({ id: id, name: name });
    else if (raw === 'X')               falseRows.push({ id: id, name: name });
    else if (raw === '' || raw === '?') skipRows.push({ id: id, name: name });
    else odd.push('행 ' + (i + 1) + ' 판정="' + values[i][idxJudge] + '" (' + name + ')');
  }

  Logger.log('');
  Logger.log('⭐ O(true) ' + trueRows.length +
             ' · X(false) ' + falseRows.length +
             ' · ?/빈값(건드리지 않음) ' + skipRows.length);
  Logger.log('   어제 기록 기대치 — 161 / 56 / 9');
  Logger.log('예상 밖 표기: ' + odd.length);
  odd.slice(0, 20).forEach(function (x) { Logger.log('   ' + x); });

  if (odd.length) { Logger.log('⚠️ 예상 밖 표기가 있어 쓰지 않는다'); return; }
  if (dryRun) { Logger.log(''); Logger.log('(dryRun — 쓰지 않았다)'); return; }
  throw new Error('⛔ imsLoadPurchasableApply 는 컷오버 날 돌리지 않는다(새 ③ · 2026-10-24) — is_purchasable 은 IMS Settings 에서 고친다');
}

/* ═══════════════════════════════════════════════════════════
   공통 — Cin7 · IMS 읽기 · 쓰기 · 비교
   ═══════════════════════════════════════════════════════════ */

/** Cin7 공급처 전량(IncludeDeprecated=true · 100 씩) — Total 과 받은 행 수를 함께 돌려준다(둘이 다르면 부르는 쪽이 멈춘다) */
function ils_cin7_() {
  var base = 'https://inventory.dearsystems.com/ExternalApi/v2/';
  var headers = { 'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'), 'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'), 'Content-Type': 'application/json' };
  var rows = [], page = 1, total = null;
  while (true) {
    var res = UrlFetchApp.fetch(base + 'supplier?Page=' + page + '&Limit=100&IncludeDeprecated=true', { method: 'get', headers: headers, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 429) { Logger.log('   429 — 65초 대기 후 재시도'); Utilities.sleep(65000); continue; }
    if (code !== 200) throw new Error('Cin7 supplier ' + code + ': ' + res.getContentText().slice(0, 300));
    var data = JSON.parse(res.getContentText());
    var items = data.SupplierList || [];                 // ⚠️ 공급처 배열 키는 SupplierList
    if (total === null) total = Number(data.Total);
    rows = rows.concat(items);
    if (items.length < 100 || rows.length >= total) break;
    page++;
    Utilities.sleep(1200);
  }
  return { rows: rows, total: total };
}

/** 판정 681 — 보이는 글자 기준 이름(U+200B · U+200C · U+200D · U+FEFF · U+00A0 를 빼고 trim) · 비교에만 쓴다(저장은 원문) */
function ils_vis_(name) {
  return String(name === null || name === undefined ? '' : name).replace(/[​‌‍﻿ ]/g, '').trim();
}

/** 두 행의 값이 다른 칸 — b(보내는 행)의 키 기준 · skip 키는 뺀다 */
function ils_diff_(a, b, skip) {
  var out = [];
  Object.keys(b).forEach(function (k) {
    if (skip.indexOf(k) >= 0) return;
    var x = (a[k] === undefined) ? null : a[k], y = (b[k] === undefined) ? null : b[k];
    if (JSON.stringify(x) !== JSON.stringify(y)) out.push(k + ': IMS=' + JSON.stringify(x) + ' Cin7=' + JSON.stringify(y));
  });
  return out;
}

/** 674 — IMS 에서 만든 행에 cin7_id 만 PATCH · 아직 비어 있을 때만 */
function ils_pairPatch_(table, pairs) {
  var done = 0;
  pairs.forEach(function (p) {
    var res = ims_fetch_('/rest/v1/' + table + '?id=eq.' + p.ims_id + '&cin7_id=is.null', { method: 'patch', headers: { 'Prefer': 'return=representation' }, payload: JSON.stringify({ cin7_id: p.cin7_id }) });
    if (res.getResponseCode() >= 300) throw new Error('짝짓기 PATCH 실패 ' + p.name + ' → HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
    if (JSON.parse(res.getContentText()).length !== 1) throw new Error('짝짓기 — 돌아온 행이 1 이 아니다(그 사이 누가 cin7_id 를 붙였나): ' + p.name);
    done++;
  });
  return done;
}

/** upsert(on_conflict=cin7_id · merge-duplicates) — groupKey 가 있으면 같은 값의 줄을 한 요청에서 가르지 않는다 · 성공 판정은 돌아온 행 수 */
function ils_upsert_(table, rows, size, groupKey) {
  var chunks = [], cur = [], lastKey = null;
  rows.forEach(function (r) {
    var k = groupKey ? r[groupKey] : null;
    if (cur.length >= size && (!groupKey || k !== lastKey)) { chunks.push(cur); cur = []; }
    cur.push(r); lastKey = k;
  });
  if (cur.length) chunks.push(cur);
  var total = 0;
  for (var i = 0; i < chunks.length; i++) {
    var res = ims_fetch_('/rest/v1/' + table + '?on_conflict=cin7_id', { method: 'post', headers: { 'Prefer': 'resolution=merge-duplicates,return=representation' }, payload: JSON.stringify(chunks[i]) });
    if (res.getResponseCode() >= 300) throw new Error(table + ' 묶음 ' + (i + 1) + '/' + chunks.length + ' 실패 HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 800) + ' · 여기까지 쓰인 행 ' + total);
    var back = JSON.parse(res.getContentText()).length;
    if (back !== chunks[i].length) throw new Error('돌아온 행 ' + back + ' ≠ 보낸 ' + chunks[i].length + ' (' + table + ' 묶음 ' + (i + 1) + ')');
    total += back;
  }
  return total;
}

/** cin7_id 목록으로 PATCH — 40 개씩 · 내리기(is_active=false)는 max(20, 보낸 행의 1 %)를 넘으면 멈춤(ILS_ALLOW_BIG_DOWN=1 로 한 번만 통과) */
function ils_patchIn_(table, ids, body, baseCount) {
  if (!ids.length) return 0;
  if (body.is_active === false) {
    var limit = Math.max(20, Math.floor((baseCount || 0) * 0.01)), props = PropertiesService.getScriptProperties();
    if (ids.length > limit) {
      if (props.getProperty('ILS_ALLOW_BIG_DOWN') !== '1') throw new Error('⛔ ' + table + ' 에서 ' + ids.length + '줄을 내리려 한다(한도 ' + limit + ') — Cin7 읽기가 짧게 끝났는지 먼저 보라 · 맞으면 ILS_ALLOW_BIG_DOWN=1 을 넣고 다시');
      props.deleteProperty('ILS_ALLOW_BIG_DOWN');
      Logger.log('⚠️ ILS_ALLOW_BIG_DOWN 로 한도를 넘겨 내린다 — ' + ids.length + '줄 · 속성은 지웠다');
    }
  }
  var done = 0;
  for (var i = 0; i < ids.length; i += 40) {
    var part = ids.slice(i, i + 40);
    var res = ims_fetch_('/rest/v1/' + table + '?cin7_id=in.(' + part.join(',') + ')', { method: 'patch', headers: { 'Prefer': 'return=representation' }, payload: JSON.stringify(body) });
    if (res.getResponseCode() >= 300) throw new Error(table + ' PATCH 실패 HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
    done += JSON.parse(res.getContentText()).length;
  }
  return done;
}

/** 전부 읽기 — PostgREST 1,000행 캡 · Range 로 나눠 읽고 Content-Range 총계와 대조 */
function ils_readAll_(path) {
  var out = [], from = 0, step = 1000, total = null;
  while (true) {
    var res = ims_fetch_(path, { method: 'get', headers: { 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1), 'Prefer': 'count=exact' } });
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
function ils_mapBy_(path, keyField) { var m = {}; ils_readAll_(path).forEach(function (r) { m[String(r[keyField])] = r.id; }); return m; }
function ils_count_(path) {
  var res = ims_fetch_(path, { method: 'get', headers: { 'Range-Unit': 'items', 'Range': '0-0', 'Prefer': 'count=exact' } });
  if (res.getResponseCode() >= 300) throw new Error('count 실패 ' + path + ' → ' + res.getResponseCode());
  var hs = res.getHeaders(), cr = '';
  Object.keys(hs).forEach(function (k) { if (String(k).toLowerCase() === 'content-range') cr = String(hs[k]); });
  var m = cr.match(/\/(\d+)$/);
  if (!m) throw new Error('Content-Range 를 못 읽었다: "' + cr + '"');
  return Number(m[1]);
}
/** 판정 682 · 미룬 317 — 기본 공급처 재계산 rpc(전체 · service_role) · 반환 {turned_off, turned_on, multi_default_products, scope} */
function ils_recalc_() {
  var res = ims_fetch_('/rest/v1/rpc/product_supplier_default_recalc', { method: 'post', payload: '{}' });
  if (res.getResponseCode() >= 300) throw new Error('기본 공급처 재계산 rpc 실패 HTTP ' + res.getResponseCode() + ' ' + res.getContentText().slice(0, 300));
  var r = JSON.parse(res.getContentText());
  return '[682 기본 공급처 재계산] 끔 ' + r.turned_off + ' · 켬 ' + r.turned_on + ' · 기본 둘 이상 ' + r.multi_default_products + (Number(r.multi_default_products) > 0 ? ' ⚠️ 0 이어야 한다 — 사람이 가른다' : '') + ' (' + r.scope + ')';
}
function ils_dup_(rows) { var seen = {}, n = 0; rows.forEach(function (r) { if (seen[r.cin7_id]) n++; else seen[r.cin7_id] = true; }); return n; }
function ils_fmt_(m) { var ks = Object.keys(m); return ks.length ? ks.map(function (k) { return k + ' ' + m[k]; }).join(' · ') : '0'; }
function ils_log_(lines) { var text = lines.join('\n'); for (var i = 0; i < text.length; i += 8000) Logger.log(text.slice(i, i + 8000)); }
