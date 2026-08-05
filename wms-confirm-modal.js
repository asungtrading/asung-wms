/* wms-confirm-modal.js — 되돌리기 어려운 동작의 확인 모달 (공용)
 *
 * 쓰는 곳 (2026-08-05 현재):
 *   picker.html — Complete as incomplete (finish(true), 미선언 short 있을 때)
 *   packer.html — Complete pack (doneBtn, 미선언 short 있을 때)
 *   (예정: receiver Complete PO · 리시빙 초과/Off-PO 확인 · fulfillment Finalize)
 *
 * 왜 native confirm 이 아닌가 (2026-08-05, SO-14129):
 *   footer 의 완료 버튼 오탭 → native confirm OK 오탭 — 물리 탭 2회만으로 60줄 오더가
 *   검수 0건으로 완료됐다(상시 재현 검증됨). 이 모달은 부족 수량을 직접 타이핑해야
 *   확정 버튼이 활성화되는 마찰을 둔다. 하드 차단은 하지 않는다(사용자 결정).
 * ⚠️ 화면별로 복사해 두지 말 것 — 갈라지면 한쪽만 가드가 생긴다
 *   (receiver 의 포커스 처리가 picker/packer 와 반대로 된 것이 그 사례다).
 * ⚠️ 문구는 전부 호출 화면이 넘긴다(keepLabel·endLabel·warnText·라벨) — 모달에
 *   화면 종속 문구를 하드코딩하면 다른 화면에서 틀린 문구가 나온다.
 * ⚠️ 규칙 41: stock_short 선언 라인은 호출자가 부족 계산에서 제외한다.
 *   선언 라인만 남은 완료는 이 모달을 띄우지 않는다(정직한 기록을 벌주지 않는다).
 *
 * 키 정책: autofocus 없음 · Enter 는 어떤 경우에도 확정 불가(캡처 단계 전면 차단 —
 *   스캐너 말미 CR 포함, 열린 동안 #scan 의 keydown 에도 닿지 않는다) ·
 *   Escape = 취소(화면에 표시하지 않는 단축키 — 태블릿에는 키가 없으니 안내문 금지).
 * 호출자 책임: 모달 표시 중 scanBusy 로 스캔 차단 · 닫힌 뒤 스캔 입력 잔여물 비우기 +
 *   focusScan(). 모듈은 포커스를 일절 건드리지 않는다.
 */
(function () {
  "use strict";

  var STYLE_ID = "wcmStyle";
  /* 색 토큰은 화면들(:root)과 같은 값 — 모듈 단독 로드도 가능하게 하드코딩.
     빨강(#dc2626)은 테두리·경고문 전용, 부족 수량은 노랑(#d9820a) — 색이 두 뜻으로 섞이지 않게. */
  var CSS =
    ".wcm{position:fixed;inset:0;z-index:80;background:rgba(16,22,30,.62);display:grid;place-items:center;padding:20px}" +
    ".wcm .box{max-width:430px;width:100%;background:#fff;border:2px solid #dc2626;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,.3);padding:22px;color:#12161c}" +
    ".wcm .warn2{color:#dc2626;font-weight:800;font-size:14.5px;margin:0 0 14px;line-height:1.4}" +
    ".wcm .nums{display:flex;gap:26px;align-items:flex-end;margin:0 0 12px}" +
    ".wcm .num .v{font-family:ui-monospace,Menlo,monospace;font-weight:800;font-size:28px;line-height:1.05;color:#12161c}" +
    ".wcm .num .v.short{color:#d9820a}" +
    ".wcm .num .v.t1{font-size:20px}" +
    ".wcm .num .l{font-family:ui-monospace,Menlo,monospace;font-size:11px;font-weight:700;color:#6b7686;text-transform:uppercase;letter-spacing:.04em;margin-top:3px}" +
    ".wcm .lines{max-height:140px;overflow:auto;border:1px solid #e5e9ef;border-radius:10px;background:#f7f8fa;padding:8px 11px;margin:0 0 14px;font-family:ui-monospace,Menlo,monospace;font-size:12px;line-height:1.7}" +
    ".wcm .hint{font-size:12px;color:#6b7686;margin:0 0 6px}" +
    ".wcm .fr{display:flex;gap:8px;margin:0 0 16px}" +
    ".wcm .fr input{width:110px;border:1px solid #e5e9ef;border-radius:9px;padding:9px 11px;font:inherit;font-size:15px;font-family:ui-monospace,Menlo,monospace}" +
    ".wcm .fr input:focus{outline:none;border-color:#d9820a;box-shadow:0 0 0 3px rgba(217,130,10,.15)}" +
    ".wcm .end{border:1px solid #e5e9ef;background:#fff;color:#dc2626;border-radius:9px;padding:8px 12px;font:inherit;font-size:12.5px;font-weight:700;cursor:pointer;white-space:nowrap}" +
    ".wcm .end:disabled{opacity:.45;cursor:default}" +
    ".wcm .keep{width:100%;border:0;border-radius:11px;background:#12161c;color:#fff;padding:15px;font:inherit;font-size:15px;font-weight:800;cursor:pointer}";

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    var st = document.createElement("style");
    st.id = STYLE_ID;
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  /* opts (문구는 전부 호출 화면 책임 — UI 영어, 규칙 11):
   *   keepLabel   필수 — 안전(취소) 버튼 라벨. 모달 맨 아래 큰 버튼
   *               (footer 완료 버튼을 오탭한 손가락의 두 번째 탭이 떨어지는 자리 = 안전 방향).
   *   endLabel    필수 — 확정 버튼 전체 라벨. 숫자 포함 권장 (예: "End · 177 short").
   *   doneLabel   완료 수량 라벨 ("picked" / "verified") — 큰 중립 숫자 밑에 표시.
   *   doneQty     완료 base 수량.
   *   shortQty    부족 base 수량 (⚠️ stock_short 선언 라인 제외 후) = 타이핑해야 하는 값.
   *   orderedQty  주문 base 수량 — 티어 분모. 부족/주문 ≥ 50% → 티어 2(경고문 + 큰 부족 숫자).
   *               검수 0건은 100% 라 자동으로 티어 2. 티어는 표시만 다르다 — 마찰 로직 무분기.
   *   warnText    티어 2 상단 경고 1줄 (생략 시 doneLabel 로 조립한 기본 문구).
   *   hintText    마찰 입력 안내 (생략 시 기본 문구).
   *   lines       [{sku, short}] 부족 라인 목록 (표시용, 생략 가능).
   * 반환: Promise<boolean> — true = 확정(End), false = 취소(계속 작업 / Escape).
   */
  function ask(opts) {
    return new Promise(function (res) {
      ensureStyle();
      var shortQty = Number(opts.shortQty) || 0;
      var orderedQty = Number(opts.orderedQty) || 0;
      var tier2 = !orderedQty || shortQty / orderedQty >= 0.5;
      var warnText = opts.warnText || ("⚠ More than half of the ordered quantity was not " + (opts.doneLabel || "confirmed") + ".");
      var hintText = opts.hintText || "Type the short quantity to enable End";

      var ov = document.createElement("div");
      ov.className = "wcm";
      ov.innerHTML =
        '<div class="box">' +
          (tier2 ? '<p class="warn2">' + esc(warnText) + "</p>" : "") +
          '<div class="nums">' +
            '<div class="num"><div class="v">' + esc(opts.doneQty) + '</div><div class="l">' + esc(opts.doneLabel) + "</div></div>" +
            '<div class="num"><div class="v short' + (tier2 ? "" : " t1") + '">' + esc(shortQty) + '</div><div class="l">short</div></div>' +
          "</div>" +
          (opts.lines && opts.lines.length
            ? '<div class="lines">' + opts.lines.map(function (l) { return "· " + esc(l.sku) + " — short " + esc(l.short); }).join("<br>") + "</div>"
            : "") +
          '<div class="hint">' + esc(hintText) + "</div>" +
          '<div class="fr"><input inputmode="numeric" autocomplete="off" placeholder="0"><button class="end" disabled>' + esc(opts.endLabel) + "</button></div>" +
          '<button class="keep">' + esc(opts.keepLabel) + "</button>" +
        "</div>";
      document.body.appendChild(ov);

      var inp = ov.querySelector("input"), end = ov.querySelector(".end"), keep = ov.querySelector(".keep");
      var closed = false;
      function close(v) {
        if (closed) return;
        closed = true;
        document.removeEventListener("keydown", onKey, true);
        ov.remove();
        res(v);
      }
      /* 캡처 단계 전면 차단: Enter 는 어떤 경우에도 확정 불가(스캐너 말미 CR 포함 —
         열린 동안 화면의 스캔 입력 keydown 에도 닿지 않는다). Escape 는 취소 —
         화면에 표시하지 않는 단축키(안내문 금지). */
      function onKey(e) {
        if (e.key === "Enter") { e.preventDefault(); e.stopPropagation(); }
        else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(false); }
      }
      document.addEventListener("keydown", onKey, true);

      inp.addEventListener("input", function () {
        var v = inp.value.trim();
        end.disabled = !(/^\d+$/.test(v) && Number(v) === shortQty);   // 정확히 일치할 때만
      });
      end.onclick = function () { if (!end.disabled) close(true); };
      keep.onclick = function () { close(false); };
      /* autofocus 금지 — 포커스는 건드리지 않는다. 닫힌 뒤 재포커스는 호출 화면의 focusScan 책임. */
    });
  }

  window.wmsConfirmModal = { ask: ask };
})();
