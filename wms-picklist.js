/* wms-picklist.js — 픽리스트 인쇄의 단일 출처 (single source of truth)
 *
 * 쓰는 곳:
 *   manager.html — Create batches (printPickList) · Create wave (printWaveAll)
 *   picker.html  — 배치/웨이브 화면 🖨 Print 재인쇄
 *   packer.html  — 팩 화면 🖨 Print 재인쇄
 *
 * ⚠️ 인쇄 형식은 여기 한 곳에서만 바꾼다. 어느 화면에 복사해 두면 한쪽만 고쳐지는
 *    드리프트가 생긴다(같은 사고가 이미 있었다).
 * ⚠️ 바코드 값 = 스캔 재진입 키다. 배치면 batch_label(SO-123-2), 웨이브면 wave label(W-0801-1).
 *    다른 값을 넣으면 인쇄물로 화면에 다시 들어올 수 없다.
 * ⚠️ 로고는 절대 URL(location.origin + …) — 새 문서라 상대경로가 안 잡힌다.
 * ⚠️ window.open 은 반드시 호출자의 클릭 핸들러 안에서 먼저 부른다(await 뒤 open 은 차단된다).
 *    이 모듈은 이미 열린 win 을 받기만 한다.
 * ⚠️ Terms · Ship To(2026-08-30) 는 wms_orders.terms·ship_address(jsonb) — **유입 시점 값**이다(A안).
 *    인쇄 시점의 Cin7 최신값이 아니다 — Cin7 에서 주소·terms 를 고친 오더는 옛 값이 찍힌다(최신화는 다음 단계).
 *    과거 오더는 null → row() 가 줄을 생략한다(reference 전례).
 */
(function () {
  "use strict";

  var LOGO_FILE = "/asung-logo-dark.png";
  var JSBARCODE = "https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js";

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function whName(w) { return w === "edmonton" ? "Edmonton" : "Toronto"; }

  /* 날짜 표시. ⚠️ new Date("2026-07-28") 는 UTC 로 파싱돼 tz 에 따라 하루 밀린다 —
     Y/M/D 를 직접 넣어 로컬 날짜로 만든다. */
  function fmtDate(v) {
    if (!v) return "";
    var s = String(v).slice(0, 10);
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
    if (!m) return String(v);
    var d = new Date(+m[1], +m[2] - 1, +m[3]);
    return isNaN(d.getTime()) ? s : d.toLocaleDateString();
  }

  function row(label, val) {
    return val === "" || val == null ? "" : "<div><b>" + esc(label) + "</b>" + esc(val) + "</div>";
  }

  function docHead(docLabel, barcode) {
    return '<div class="top">' +
      '<div class="brandwrap"><img src="' + (location.origin + LOGO_FILE) + '" class="logo" alt="ASUNG">' +
      '<div class="doc">' + esc(docLabel) + "</div></div>" +
      '<div class="bc"><svg class="bcsvg" data-code="' + esc(barcode) + '"></svg></div>' +
      "</div>";
  }

  /* ---- 배치 한 장 (일반 분할 배치 · wave 멤버 배치 공용) ----
     p = {
       pageBreak, barcode, batchLabel, orderNumber, reference, orderDate,
       terms, shipAddress(wms_orders.ship_address jsonb 원문 — Display 두 줄만 찍는다, 유입 시점 값),
       warehouse, priceTier, printed, printedBy,
       wave, tote, customerName, totalLines, totalUnits,
       pickedBySlot(기본 true — 우측 칸에 "Picked By ____"),
       zones, comments, footer
     }
     ⚠️ barcode 는 batchLabel 그대로. 스캔 재진입 키다. */
  function batchPage(p) {
    p = p || {};
    var barcode = p.barcode || p.batchLabel || "";
    var printed = p.printed || new Date().toLocaleDateString();
    // Ship To — Cin7 이 인쇄용으로 합쳐둔 DisplayAddressLine1/2 그대로(우리가 조립하지 않는다 — 실측 SO-15505)
    var addr = p.shipAddress || {};
    var ship1 = String(addr.DisplayAddressLine1 || "").trim();
    var ship2 = String(addr.DisplayAddressLine2 || "").trim();
    var shipRows = (ship1 || ship2)
      ? row("Ship To", ship1 || ship2) +
        (ship1 && ship2 ? "<div><b></b>" + esc(ship2) + "</div>" : "")   // 둘째 줄은 라벨 폭만큼 들여쓴 무라벨 줄
      : "";
    var left = row("Batch", p.batchLabel) +
      row("Order", p.orderNumber) +
      row("Reference", p.reference) +
      row("Order Date", fmtDate(p.orderDate)) +          // Cin7 화면 용어 = Order Date (API OrderDate)
      row("Terms", p.terms) +
      shipRows +
      row("Warehouse", p.warehouse ? whName(p.warehouse) : "") +
      row("Price Tier", (p.priceTier || "").trim()) +
      "<div><b>Printed</b>" + esc(printed) + (p.printedBy ? " · by " + esc(p.printedBy) : "") + "</div>";
    var waveVal = p.wave ? (p.wave + (p.tote ? " · Tote " + p.tote : "")) : "";
    var right = row("Wave", waveVal) +
      "<div><b>Customer</b>" + esc(p.customerName || "—") + "</div>" +
      "<div><b>Total Lines</b>" + esc(p.totalLines == null ? "" : p.totalLines) + "</div>" +
      "<div><b>Total Units</b>" + esc(p.totalUnits == null ? "" : p.totalUnits) + "</div>" +
      (p.pickedBySlot === false ? "" : "<div><b>Picked By</b>________________</div>");
    var cmt = (p.comments || "").trim();
    return '<section class="page' + (p.pageBreak ? " pb" : "") + '">' +
      docHead("PICK LIST", barcode) +
      '<div class="info"><div>' + left + "</div><div>" + right + "</div></div>" +
      (p.zones == null ? "" : '<div class="zones"><b>Zones</b> ' + esc(p.zones) + "</div>") +
      (cmt ? '<div class="cmt"><b>Comments</b> ' + esc(cmt) + "</div>" : "") +
      (p.footer ? '<div class="pk">' + esc(p.footer) + "</div>" : "") +
      "</section>";
  }

  /* ---- 웨이브 요약 한 장 (웨이브 바코드 + 토트 배정표) ----
     w = { pageBreak, label, warehouse, printed, printedBy,
           totes:[{tote, orderNumber, customerName, orderDate, lines, units}] }
     ⚠️ barcode = wave label. 픽커가 이걸 스캔하면 웨이브가 열린다. */
  function waveSummaryPage(w) {
    w = w || {};
    var totes = w.totes || [];
    var printed = w.printed || new Date().toLocaleDateString();
    var hasDate = totes.some(function (t) { return !!t.orderDate; });
    var totalL = totes.reduce(function (s, t) { return s + Number(t.lines || 0); }, 0);
    var totalU = totes.reduce(function (s, t) { return s + Number(t.units || 0); }, 0);
    var rows = totes.map(function (t) {
      return "<tr><td class=\"tn\">TOTE " + esc(t.tote) + "</td>" +
        "<td>" + esc(t.orderNumber || "") + "</td>" +
        "<td>" + esc(t.customerName || "—") + "</td>" +
        (hasDate ? "<td>" + esc(fmtDate(t.orderDate)) + "</td>" : "") +
        '<td class="num">' + esc(t.lines == null ? "" : t.lines) + "</td>" +
        '<td class="num">' + esc(t.units == null ? "" : t.units) + "</td></tr>";
    }).join("");
    return '<section class="page' + (w.pageBreak ? " pb" : "") + '">' +
      docHead("WAVE PICK LIST", w.label || "") +
      '<div class="info"><div>' +
        row("Wave", w.label) +
        row("Warehouse", w.warehouse ? whName(w.warehouse) : "") +
        "<div><b>Printed</b>" + esc(printed) + (w.printedBy ? " · by " + esc(w.printedBy) : "") + "</div>" +
      "</div><div>" +
        "<div><b>Orders / Totes</b>" + totes.length + "</div>" +
        "<div><b>Total Lines</b>" + totalL + "</div>" +
        "<div><b>Total Units</b>" + totalU + "</div>" +
        "<div><b>Picked By</b>________________</div>" +
      "</div></div>" +
      "<table><thead><tr><th>Tote</th><th>Order</th><th>Customer</th>" +
        (hasDate ? "<th>Order Date</th>" : "") +
        '<th class="num">Lines</th><th class="num">Units</th></tr></thead>' +
      "<tbody>" + rows + "</tbody></table>" +
      '<div class="note">One route, sort into totes — the picking screen directs every scan to its tote. ' +
      "Scan the wave barcode above to open it.</div>" +
      "</section>";
  }

  var CSS = [
    "*{box-sizing:border-box} body{font-family:Arial,Helvetica,sans-serif;color:#12161c;margin:28px;font-size:13px}",
    ".top{display:flex;align-items:flex-start;justify-content:space-between;border-bottom:2px solid #12161c;padding-bottom:14px}",
    ".brandwrap{display:flex;flex-direction:column;gap:8px}",
    ".brandwrap .logo{height:40px;width:auto;display:block}",
    ".doc{font-size:26px;font-weight:800;letter-spacing:.02em}",
    ".bc{text-align:right}",
    ".info{display:flex;gap:48px;margin:20px 0 10px}",
    ".info div{line-height:1.7} .info b{display:inline-block;min-width:104px;color:#555}",
    ".pk{margin:10px 0;font-weight:800;font-size:15px}",
    ".zones{margin:10px 0 2px;font-size:14px} .zones b{color:#555;margin-right:8px}",
    ".cmt{margin:10px 0 2px;font-size:14px;padding:9px 12px;background:#fdf6ec;border:1px solid #f5dcae;border-radius:8px;color:#8a5a06} .cmt b{color:#8a5a06;margin-right:8px}",
    "table{width:100%;border-collapse:collapse;margin-top:6px}",
    "th{font-size:11px;text-transform:uppercase;letter-spacing:.03em;color:#555;text-align:left;padding:8px 10px;border-bottom:2px solid #12161c}",
    "td{padding:9px 10px;border-bottom:1px solid #ddd;font-size:14px}",
    "td.tn{font-weight:800;white-space:nowrap} td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}",
    ".note{margin-top:16px;color:#555;font-size:12px}",
    "@media print{body{margin:14mm} .pb{page-break-before:always}}",
  ].join("\n    ");

  /* 이미 열린 창(win)에 문서를 쓰고 바코드 렌더 후 인쇄 다이얼로그를 띄운다. */
  function render(win, docTitle, pagesHtml) {
    if (!win) return;
    win.document.write('<!doctype html><html><head><meta charset="utf-8"><title>' + esc(docTitle) + "</title>" +
      '<script src="' + JSBARCODE + '"><\/script>' +
      "<style>\n    " + CSS + "\n  </style></head><body>" +
      pagesHtml +
      "<script>" +
      'try{ document.querySelectorAll(".bcsvg").forEach(function(el){ JsBarcode(el, el.getAttribute("data-code"), ' +
      '{format:"CODE128",displayValue:true,fontSize:15,height:50,margin:0}); }); }catch(e){}' +
      'window.addEventListener("load",function(){ setTimeout(function(){ try{window.print();}catch(e){} }, 450); });' +
      "<\/script></body></html>");
    win.document.close();
  }

  window.wmsPickList = {
    esc: esc, whName: whName, fmtDate: fmtDate,
    batchPage: batchPage, waveSummaryPage: waveSummaryPage, render: render,
  };
})();
