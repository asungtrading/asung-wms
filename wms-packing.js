/* wms-packing.js — 팩킹 유닛 라벨 + 오더 소계 캡션의 단일 출처 (single source of truth)
 *
 * 쓰는 곳:
 *   fulfillment.html — 유닛 생성(addUnit·createBoxFor) · 작업화면 표시 · 유닛별/스토어별 팩킹리스트 인쇄
 *   admin.html       — Finalized 재출력 3종(Print / PDF / CSV, getPackingData 공용 경로)
 *
 * ⚠️ 라벨 문자열을 만드는 곳은 여기 한 곳이다. 화면과 인쇄물이 어긋나면 작업자가 실물에 적은
 *    표기와 서류가 대조되지 않는다 — 어느 화면에도 복사해 두지 말 것.
 *
 * 라벨 규칙 (2026-08-02 변경):
 *   생성 라벨 = 유닛 식별자만 — 팔렛 `P1`, 박스 `B3`.
 *   예전에는 오더번호를 접두사로 붙였고(`SO-13849-P1`), 멀티오더 선택이면 "외 여러 건" 표시로
 *   `+` 를 덧붙여 `SO-13849+-P1` 이 됐다. 오더번호는 헤더·오더별 소계에 이미 있어 세 번째 반복이었고,
 *   `+` 는 읽는 사람에게 아무 의미가 없다. → 생성 자체를 짧은 식별자로 바꿨다.
 *   `unitCode()` 는 **이미 DB 에 저장된 옛 라벨**을 같은 형태로 보여주기 위한 정규화다
 *   (새 라벨엔 아무 일도 하지 않는다). 표시용 땜질이 아니라 과거 데이터 호환 계층이다.
 */
(function () {
  "use strict";

  /* 유닛 객체는 두 형태로 돌아다닌다:
     DB 행(`{unit_type, label}`) / admin getPackingData 의 가공 행(`{unitType, label}`).
     둘 다 받는다 — 호출자마다 변환하게 두면 그게 드리프트의 시작이다. */
  function typeOf(u) {
    if (typeof u === "string") return u;
    return (u && (u.unit_type || u.unitType)) || "";
  }
  function isBox(u) { return typeOf(u) === "box"; }
  function rawLabel(u) {
    if (typeof u === "string") return u;
    return (u && u.label) || "";
  }

  /* "SO-13849+-P1" / "SO-13849-B2" / "SHIP+-P3" → "P1" / "B2" / "P3"
     이미 짧은 "P1" 은 그대로. 형태를 못 알아보면 원문을 돌려준다(정보를 지우지 않는다). */
  function unitCode(u) {
    var raw = String(rawLabel(u)).trim();
    if (!raw) return "";
    var m = raw.match(/([PB])\s*-?\s*(\d+)$/i);
    return m ? m[1].toUpperCase() + m[2] : raw;
  }

  function unitTypeWord(u) { return isBox(u) ? "BOX" : "PALLET"; }
  function unitIcon(u) { return isBox(u) ? "📦" : "🟩"; }

  /* 유닛 제목 — "P1 · PALLET" / "B3 · BOX". 아이콘은 붙이지 않는다(HTML 만 아이콘을 쓴다). */
  function unitTitle(u) { return unitCode(u) + " · " + unitTypeWord(u); }

  /* 중첩 표기 — "B3 on P1". 부모가 없으면 자기 코드만. */
  function unitOn(u, parent) {
    var code = unitCode(u);
    var p = parent ? unitCode(parent) : "";
    return p ? code + " on " + p : code;
  }

  /* 다음 유닛 라벨. `units` = 현재 작업 중인 유닛 배열(선택된 오더들에 관련된 전부).
     번호 = **이미 쓰인 최대 번호 + 1**. 예전의 "개수 + 1" 은 중간 유닛을 지우면 같은 번호를
     다시 내주었다(P1·P2 중 P1 삭제 → 개수 1 → 또 P2). 접두사가 없어진 만큼 라벨 하나가
     곧 유닛의 이름이므로 중복을 만들지 않는다.
     ⚠️ 한계: 서로 다른 세션에서 따로 꾸린 오더를 나중에 함께 선택하면 각자의 P1 이 한 화면에
     모일 수 있다(저장된 라벨은 고치지 않는다 — 유닛의 키는 `id`). */
  function nextUnitLabel(type, units) {
    var pfx = type === "box" ? "B" : "P";
    var max = 0;
    (units || []).forEach(function (u) {
      if (typeOf(u) !== type) return;
      var m = unitCode(u).match(/^[PB](\d+)$/);
      if (m) max = Math.max(max, parseInt(m[1], 10));
    });
    return pfx + (max + 1);
  }

  /* ---- 오더 소계 캡션 (2026-08-02) ----------------------------------------
     품목표 맨 위에 붙는 "SO-13993 (subtotal 10)" 한 줄.
     ⚠️ 유닛에 오더가 하나뿐이어도 **항상** 붙인다. 예전에는 오더가 2건 이상일 때만 넣었는데
     (혼합 유닛의 구분선 용도), 그러면 단일 오더 유닛의 표는 자기가 누구 물건인지 말하지 못하고
     읽는 사람이 페이지 헤더까지 되짚어야 한다 — 현장 피드백(P2 에 소계 행이 없어 대조 불가).
     형식은 여기 한 곳에서만 만든다: 유닛별 인쇄 · 스토어별 종합 · admin Print/PDF/CSV 가 같은 줄. */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  var CAP_MONO = "ui-monospace,'SF Mono','DM Mono',Menlo,monospace";

  /* 평문 — PDF/CSV 처럼 마크업을 못 쓰는 출력용 */
  function orderSubtotalText(orderLabel, sub) {
    return String(orderLabel == null ? "" : orderLabel) + " (subtotal " + Number(sub || 0) + ")";
  }
  /* 표 안의 캡션 행. colspan 기본 4 = SKU·Barcode·Product·Qty */
  function orderSubtotalRow(orderLabel, sub, colspan) {
    return '<tr><td colspan="' + (colspan || 4) + '" style="background:#f7f7f7;font-family:' + CAP_MONO + ';font-weight:800">'
      + esc(orderLabel) + ' <span style="font-weight:400;color:#666">(subtotal ' + Number(sub || 0) + ')</span></td></tr>';
  }

  window.wmsPacking = {
    unitCode: unitCode,
    unitTypeWord: unitTypeWord,
    unitIcon: unitIcon,
    unitTitle: unitTitle,
    unitOn: unitOn,
    nextUnitLabel: nextUnitLabel,
    orderSubtotalText: orderSubtotalText,
    orderSubtotalRow: orderSubtotalRow,
  };
})();
