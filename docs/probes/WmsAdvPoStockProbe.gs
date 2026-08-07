/**
 * WmsAdvPoStockProbe.gs — Advanced PO stock received 쓰기 프로브 P1·P2 (2026-08-07)
 *
 * 목적 (PO-01094 Apply 400 조사 — 사용자 승인된 프로브):
 *   P1: POST /advanced-purchase/stock 의 Lines[].LocationID 가 실제로 저장되는가
 *       (apib 예시는 전부 null + "Use Put Away" 단서 — 1단/2단 설계를 가르는 최대 변수)
 *   P2: 같은 태스크에 다른 bin 라인 append 가 되는가 (Simple 의 "문서당 bin 1개" 제약 여부)
 *   P2b: (P2 가 400 일 때만) 한 페이로드 안의 서로 다른 bin 2줄도 400 인지 — 제약의 단위 판별
 *
 * 사용법: System_Automation 프로젝트에 이 파일을 넣고 APB_RECEIPT_ID 만 채운 뒤
 *         apbRunProbe() 실행 → 로그 전체를 복사해 보고.
 * 필요 Script Properties (전부 기존 키 재사용, 신규 없음):
 *   CIN7_ACCOUNT_ID · CIN7_APPLICATION_KEY(⚠️ CIN7_API_KEY 아님) · SUPABASE_URL · SUPABASE_SERVICE_KEY
 *
 * 안전:
 *   · 쓰는 것은 DRAFT 태스크뿐(재고 영향 없음). 끝에 DELETE ?TaskID= 로 자체 정리(Undo).
 *   · Received 는 보내지 않는다 (apib: Read-only — 사용자 조건).
 *   · 프로브 라인은 교차 조합(SKU_A + B의 bin / SKU_B + A의 bin) — 정리(DELETE)가 실패해도
 *     본 Apply 의 실제 라인(SKU_A+A의 bin …)과 duplicate 충돌이 나지 않는다.
 *     ⚠️ 단 정리 실패 상태로 본 Apply 를 돌리면 authorize 때 프로브 수량(1개×2줄)이 엉뚱한
 *     bin 으로 들어간다 — 정리 실패 시 반드시 보고 후 Apply 보류 (보고서 「정리 실패 대비」절).
 *   · Cin7 콜 간 400ms sleep. 어떤 단계가 실패해도 정리(cleanup)는 항상 시도한다.
 */

const APB_RECEIPT_ID = 0;   // ← 여기에 receipt id 입력 (wms_receipts.id)

const APB_BASE = 'https://inventory.dearsystems.com/ExternalApi/v2';

function apbRunProbe() {
  if (!APB_RECEIPT_ID) throw new Error('APB_RECEIPT_ID 를 채우세요 (wms_receipts.id)');
  const createdTasks = [];   // 정리 대상 TaskID 수집 — 실패해도 finally 에서 전부 DELETE 시도
  const L = [];
  const log = (s) => { L.push(s); Logger.log(s); };

  try {
    // ── 0) receipt + 라인 로드 (Supabase service key — GAS 표준 경로) ──────────
    const rcpt = apbSb_('wms_receipts?id=eq.' + APB_RECEIPT_ID +
      '&select=id,po_number,cin7_purchase_id,cin7_type,warehouse,source_type')[0];
    if (!rcpt) throw new Error('receipt not found: ' + APB_RECEIPT_ID);
    log('receipt: ' + rcpt.po_number + ' · type=' + rcpt.cin7_type + ' · wh=' + rcpt.warehouse);
    if (!/advanced/i.test(rcpt.cin7_type || ''))
      throw new Error('이 receipt 은 Advanced 가 아니다 (cin7_type=' + rcpt.cin7_type + ') — 프로브 중단');

    const lines = apbSb_('wms_receipt_lines?receipt_id=eq.' + APB_RECEIPT_ID +
      '&select=order_sku,received_base,putaway_bin&received_base=gt.0&putaway_bin=not.is.null&order=id');
    if (!lines.length) throw new Error('bin 이 배정된 라인이 없다 — 프로브 불가');
    const lineA = lines[0];
    const lineB = lines.find((l) =>
      l.order_sku !== lineA.order_sku &&
      String(l.putaway_bin).toUpperCase() !== String(lineA.putaway_bin).toUpperCase()) || null;
    log('lineA: ' + lineA.order_sku + ' @ ' + lineA.putaway_bin +
      (lineB ? ' · lineB: ' + lineB.order_sku + ' @ ' + lineB.putaway_bin : ' · lineB 없음(단일 bin receipt)'));

    // ── 1) bin GUID — EF 와 동일: /ref/location 최상위 창고 행(ParentID 없음)의 Bins[] 만 ──
    //    ⚠️ 응답이 Limit 500 으로 잘리지만 Bins[] 는 창고 행 하나에 전부 들어있다.
    //    child-location 행의 Name 은 bin 이름이 아니다(바코드류) — 폴백 금지 (stock-write.md 5절).
    const whName = rcpt.warehouse === 'edmonton' ? 'Asung - Edmonton' : 'Asung Trading Inc.';
    const loc = apbCin7_('GET', '/ref/location?Page=1&Limit=500', null);
    if (loc.code !== 200) throw new Error('/ref/location HTTP ' + loc.code + ': ' + loc.text.slice(0, 200));
    const whRow = (loc.json.LocationList || loc.json.Locations || []).find((r) =>
      !r.ParentID && String(r.Name || '').trim() === whName);
    if (!whRow) throw new Error('warehouse row not found: ' + whName);
    const binGuid = (name) => {
      const key = String(name || '').trim().toUpperCase();
      const b = (whRow.Bins || []).find((x) => !x.IsDeprecated && String(x.Name || '').trim().toUpperCase() === key);
      return b ? b.ID : null;
    };
    const guidA = binGuid(lineA.putaway_bin);
    if (!guidA) throw new Error('bin GUID not found: ' + lineA.putaway_bin);
    // 교차용 두 번째 bin: lineB 의 bin, 없으면 창고 Bins[] 에서 lineA 와 다른 아무 bin
    let binBName = lineB ? lineB.putaway_bin : null, guidB = lineB ? binGuid(lineB.putaway_bin) : null;
    if (!guidB) {
      const alt = (whRow.Bins || []).find((x) => !x.IsDeprecated && x.ID !== guidA);
      binBName = alt ? alt.Name : null; guidB = alt ? alt.ID : null;
    }
    if (!guidB) throw new Error('두 번째 bin 을 찾지 못했다');
    const skuB = lineB ? lineB.order_sku : lineA.order_sku;   // lineB 없으면 P2 는 같은 SKU + 다른 bin (중복 판정과 무관)
    log('binA ' + lineA.putaway_bin + ' = ' + guidA + ' · binB ' + binBName + ' = ' + guidB);

    const pid = rcpt.cin7_purchase_id;
    const today = new Date().toISOString().slice(0, 10) + 'T00:00:00Z';

    // ── 2) 사전 상태 — 기존 태스크 목록 기록 (새 태스크 식별용) ──────────────
    Utilities.sleep(400);
    const pre = apbCin7_('GET', '/advanced-purchase/stock?PurchaseID=' + encodeURIComponent(pid), null);
    log('PRE GET ' + pre.code + ': ' + pre.text.slice(0, 500));
    const preIds = ((pre.json && pre.json.StockReceiving) || []).map((t) => t.TaskID);

    // ── P1) 새 태스크 생성 + LocationID 저장 여부 — 교차 조합 (SKU_A + binB) ──
    //    ⚠️ Received 는 보내지 않는다 (read-only — 사용자 조건). TaskID 생략 = 새 태스크.
    Utilities.sleep(400);
    const p1Body = { PurchaseID: pid, Status: 'DRAFT',
      Lines: [{ Date: today, SKU: lineA.order_sku, Quantity: 1, LocationID: guidB }] };
    const p1 = apbCin7_('POST', '/advanced-purchase/stock', p1Body);
    log('P1 POST ' + p1.code + ': ' + p1.text.slice(0, 700));
    if (p1.code !== 200) { log('P1 실패 — 이후 단계 중단 (본문 확인)'); return apbReport_(L); }

    Utilities.sleep(400);
    const g1 = apbCin7_('GET', '/advanced-purchase/stock?PurchaseID=' + encodeURIComponent(pid), null);
    const tasks1 = (g1.json && g1.json.StockReceiving) || [];
    const newTask = tasks1.find((t) => preIds.indexOf(t.TaskID) < 0);
    if (newTask) createdTasks.push(newTask.TaskID);
    log('P1 되읽기 ' + g1.code + ' · 새 TaskID=' + (newTask ? newTask.TaskID : '식별 실패!') +
      ' · Lines=' + JSON.stringify(newTask ? newTask.Lines : null).slice(0, 600));
    const storedLoc = newTask && newTask.Lines && newTask.Lines[0] ? newTask.Lines[0].LocationID : undefined;
    log('★ P1 판정: LocationID 저장값 = ' + JSON.stringify(storedLoc) +
      (storedLoc === guidB ? '  → GUID 그대로 저장 (1단 설계 가능)'
        : '  → 보낸 GUID(' + guidB + ')와 다름 — put-away 2단 가능성, 구현 전 재보고'));

    // ── P2) 같은 태스크에 다른 bin append (SKU_B + binA) ─────────────────────
    if (newTask) {
      Utilities.sleep(400);
      const p2Body = { PurchaseID: pid, TaskID: newTask.TaskID, Status: 'DRAFT',
        Lines: [{ Date: today, SKU: skuB, Quantity: 1, LocationID: guidA }] };
      const p2 = apbCin7_('POST', '/advanced-purchase/stock', p2Body);
      log('P2 POST(append 다른 bin) ' + p2.code + ': ' + p2.text.slice(0, 700));
      log('★ P2 판정: ' + (p2.code === 200 ? '한 태스크에 여러 bin 허용 — Simple 의 bin 1개 제약 없음'
        : '400/오류 — 아래 P2b 로 제약 단위 판별'));

      // ── P2b) P2 실패 시에만: 새 태스크 하나에 서로 다른 bin 2줄 페이로드 ──
      if (p2.code !== 200) {
        Utilities.sleep(400);
        const p2bBody = { PurchaseID: pid, Status: 'DRAFT',
          Lines: [
            { Date: today, SKU: lineA.order_sku, Quantity: 1, LocationID: guidA },
            { Date: today, SKU: skuB, Quantity: 1, LocationID: guidB },
          ] };
        const p2b = apbCin7_('POST', '/advanced-purchase/stock', p2bBody);
        log('P2b POST(새 태스크·2 bin 페이로드) ' + p2b.code + ': ' + p2b.text.slice(0, 700));
        if (p2b.code === 200) {
          Utilities.sleep(400);
          const g2 = apbCin7_('GET', '/advanced-purchase/stock?PurchaseID=' + encodeURIComponent(pid), null);
          ((g2.json && g2.json.StockReceiving) || []).forEach((t) => {
            if (preIds.indexOf(t.TaskID) < 0 && createdTasks.indexOf(t.TaskID) < 0) createdTasks.push(t.TaskID);
          });
        }
      }
    }

    // ── 3) 최종 상태 스냅샷 ──────────────────────────────────────────────────
    Utilities.sleep(400);
    const fin = apbCin7_('GET', '/advanced-purchase/stock?PurchaseID=' + encodeURIComponent(pid), null);
    log('FINAL GET ' + fin.code + ': ' + fin.text.slice(0, 1000));
  } catch (e) {
    log('ERROR: ' + (e && e.message ? e.message : e));
  } finally {
    // ── 4) 정리 — 만든 태스크 전부 DELETE(Undo). 실패해도 나머지는 계속 시도 ──
    for (let i = 0; i < createdTasks.length; i++) {
      Utilities.sleep(400);
      const del = apbCin7_('DELETE', '/advanced-purchase/stock?TaskID=' + encodeURIComponent(createdTasks[i]), null);
      log('CLEANUP DELETE ' + createdTasks[i] + ' → ' + del.code + ': ' + del.text.slice(0, 300));
    }
    if (createdTasks.length) {
      Utilities.sleep(400);
      try {
        const rcpt2 = apbSb_('wms_receipts?id=eq.' + APB_RECEIPT_ID + '&select=cin7_purchase_id')[0];
        const chk = apbCin7_('GET', '/advanced-purchase/stock?PurchaseID=' + encodeURIComponent(rcpt2.cin7_purchase_id), null);
        const left = ((chk.json && chk.json.StockReceiving) || []).filter((t) => createdTasks.indexOf(t.TaskID) >= 0);
        log('★ 정리 확인: 프로브 태스크 잔존 ' + left.length + '개' +
          (left.length ? ' — ⚠️ 남아 있다: 보고서 「정리 실패 대비」절대로 처리, 본 Apply 보류' : ' (깨끗함)'));
      } catch (e2) { log('정리 확인 GET 실패: ' + e2); }
    }
    log('── 로그 끝 — 전체를 복사해 보고 ──');
  }
}

/* Supabase REST (service key — GAS Script Property, 프론트 금지 키의 서버사이드 정상 경로) */
function apbSb_(path) {
  const url = getProp('SUPABASE_URL') + '/rest/v1/' + path;
  const key = getProp('SUPABASE_SERVICE_KEY');
  const res = UrlFetchApp.fetch(url, {
    headers: { apikey: key, Authorization: 'Bearer ' + key }, muteHttpExceptions: true });
  if (res.getResponseCode() !== 200)
    throw new Error('Supabase ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 200));
  return JSON.parse(res.getContentText());
}

/* Cin7 호출 — throw 하지 않고 {code, text, json} 반환 (프로브는 4xx 본문 자체가 데이터다) */
function apbCin7_(method, pathq, body) {
  const res = UrlFetchApp.fetch(APB_BASE + pathq, {
    method: method.toLowerCase(),
    headers: {
      'api-auth-accountid': getProp('CIN7_ACCOUNT_ID'),
      'api-auth-applicationkey': getProp('CIN7_APPLICATION_KEY'),   // ⚠️ CIN7_API_KEY 아님
      'Content-Type': 'application/json',
    },
    payload: body ? JSON.stringify(body) : undefined,
    muteHttpExceptions: true,
  });
  const code = res.getResponseCode(), text = res.getContentText();
  let json = null; try { json = JSON.parse(text); } catch (e) {}
  return { code: code, text: text, json: json };
}

function apbReport_(L) { Logger.log('── 로그 끝 (조기 종료) ──'); }
