-- PO 「오늘」 ① — 날짜 기본값 넷을 토론토 날짜(ims_today)로 (2026-09-24 UTC · 파일 시각 UTC · 토론토 2026-09-23 저녁)
-- 지시서 ~/asung/prompts/po-today-1.md · 판정 Caleb 2026-09-23(§1 ① 기본값 넷만 · ② 창구 22곳은 세기만 · ③ 창구 재발행·원장·화면은 안 한다)
-- 근거: so-module §13-h — 회사의 「오늘」은 토론토 날짜 · DB 시각은 UTC 라 current_date 는 토론토 저녁 8시(EDT · 겨울 EST 7시) 이후 이미 내일이다
-- 바탕: 20260923232500_so_deal_rpc.sql ⓪(ims_today() · so.order_date 기본값 선례) · 20260916144201(po · po_receipt_line) · 20260918161537(po_receipt) · 20260916153313(po_payment)
-- 대상: [테스트 · Asung-IMS] 먼저 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 운영은 Caleb 판정 뒤
--
-- ⭐ 하는 것 — alter column … set default public.ims_today() 넷 + comment on column 넷 · 함수는 만들지도 고치지도 않는다(ims_today 는 20260923232500 에 이미 있다)
--    po.order_date · po_receipt.received_on · po_receipt_line.received_on · po_payment.paid_on
-- ⚠️ 기본값 교체는 기존 행을 바꾸지 않는다(카탈로그만) · 행 수 전후 같다
-- ⚠️ 지금 화면(asung-ims)은 이 넷을 전부 창구(po_create · po_receipt_create · po_receipt_confirm · po_payment_create)로 넣고 창구가 coalesce(p_날짜, current_date) 로 값을 직접 채운다 ⇒
--    이 기본값 넷은 지금 경로에서는 닿지 않는다(직접 insert 가 생길 때·창구가 날짜를 안 넣게 바뀔 때 안전판) · 실제로 닿는 창구 폴백·화면 toISOString 은 ②(조사 표 · Caleb 판정)
-- ⚠️ 적용된 파일(po.sql 등)의 「default current_date」 글자는 그대로다 — 카탈로그가 정본 · 다음 dump 에 ims_today() 로 나온다

alter table public.po              alter column order_date  set default public.ims_today();
alter table public.po_receipt      alter column received_on set default public.ims_today();
alter table public.po_receipt_line alter column received_on set default public.ims_today();
alter table public.po_payment      alter column paid_on     set default public.ims_today();

comment on column public.po.order_date is
  '발주 날짜 · NOT NULL · 기본값 ims_today()(토론토 오늘 · 2026-09-24 current_date 에서 바꿈 — current_date 는 UTC 라 토론토 저녁 8시(겨울 7시) 뒤 내일이다 · so-module §13-h) · ⚠️ po_create 는 coalesce(p_order_date, …)로 값을 직접 넣어 이 기본값이 닿지 않는다(창구 폴백은 별도 판정)';
comment on column public.po_receipt.received_on is
  '⭐ 물건이 들어온 날 = 원장 occurred_on 의 근거(§11-i). 확정 때 po_receipt_line.received_on 으로 복사된다 — 원장은 묶음까지 조인하지 않아도 되게(4-d) · 기본값 ims_today()(토론토 오늘 · 2026-09-24 current_date 에서 바꿈 · so-module §13-h) · ⚠️ po_receipt_create 가 coalesce(p_received_on, …)로 직접 넣어 기본값은 닿지 않는다';
comment on column public.po_receipt_line.received_on is
  '⭐ 물건이 들어온 날 — 원장 occurred_on 이 된다. 우리가 처리한 시각(created_at)이 아니다. date — 원장이 date 다 · 기본값 ims_today()(토론토 오늘 · 2026-09-24 current_date 에서 바꿈 · so-module §13-h) · ⚠️ po_receipt_confirm 이 묶음(po_receipt.received_on)을 복사해 넣어 기본값은 닿지 않는다';
comment on column public.po_payment.paid_on is
  '결제한 날 · NOT NULL · 기본값 ims_today()(토론토 오늘 · 2026-09-24 current_date 에서 바꿈 — current_date 는 UTC 라 토론토 저녁 8시(겨울 7시) 뒤 내일이다 · so-module §13-h) · ⚠️ po_payment_create 는 coalesce(p_paid_on, …)로 직접 넣어 기본값은 닿지 않는다';

-- 검증: ~/asung/prompts/po-today-1-verify.sql — pg_get_expr 넷 = public.ims_today() · 행 수 전후 같음 · 시간을 바꿔 시험할 수 없다(식을 읽어 확인 · §13-h)
