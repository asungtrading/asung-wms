-- 픽리스트에 배송 주소·결제 조건 표기 (2026-08-30 — 조사 보고·계획 승인분)
-- 목적: 오더 분할 후 인쇄하는 픽리스트에서 인보이스 처리 전에 주소·terms 를 눈으로 확인.
-- 필드 실측: GAS 프로브 2026-08-28 · SO-15505 — /sale 상세 최상위 ShippingAddress(객체)·Terms(문자열).
-- nullable · 기본값 없음 · 백필 금지(과거 오더는 null → 인쇄에서 줄 생략, reference 전례와 동일).
-- ⚠️ 배포 순서(규칙 23): 이 마이그레이션 push → 원격 컬럼 확인 → hello EF 배포 → 프론트.

alter table wms_orders
  add column ship_address jsonb,
  add column terms text;

comment on column wms_orders.ship_address is
  'Cin7 sale 상세 ShippingAddress 객체 원문(⚠️ 유입 시점 값 — 이후 Cin7 수정은 반영 안 됨(A안 2026-08-30), hold 재조회 patch 에 얹는 최신화는 다음 단계). 인쇄는 DisplayAddressLine1/2 두 줄을 그대로 사용, 원문 보존은 라벨 인쇄 대비';

comment on column wms_orders.terms is
  'Cin7 sale 상세 Terms 문자열(예 "C.B.S (Cash Before Shipment)"). ⚠️ 유입 시점 값 — ship_address 와 동일 한계. 픽리스트 인쇄용';
