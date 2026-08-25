-- 라인 소멸 감지 — inv_missing_lines (2026-08-25)
--
-- 배경 [실사고 2026-08-25 · TR-04175]: 원장은 append-only 라 Cin7 에서 라인이 삭제되면 아무
-- 신호도 오지 않는다. TR-04175 가 8/21 에 195줄로 수집된 뒤 8/24 에 138줄이 Cin7 에서
-- 삭제됐으나 원장은 195행을 그대로 보유 → 토론토가 138 SKU 에서 이중 차감 → ⑥ 대조
-- unknown 138. 원인 규명에 수 시간이 걸렸다 — 이 테이블이 그 시간을 줄인다.
--
-- 무엇을 하나: inv-collect 가 상세를 실제로 조회한 문서에 대해
--   B(원장에 있는 그 문서의 행 · source='cin7' 만) − A(이번 회차 상세가 만든 행) = 사라진 라인
-- 을 여기 기록한다. ⚠️ **기록과 경보만 한다**:
--  · 원장 행을 삭제·수정하지 않는다 (append-only 불변)
--  · 자동 정정 없음 — 어느 문서가 유령인지는 사람이 Cin7 화면을 보고 판정한다
--    (TR-04175 실사고에서도 그랬다). resolved_at/resolution_note 로 사람이 닫는다.
--
-- ⚠️ last_modified_on 이 유니크 키에 들어가는 이유:
--  · 같은 편집이 2~5분 주기 회차마다 재검출돼도 값이 같아 do-nothing → 중복 폭주 차단
--  · 문서가 다시 편집되면 값이 달라져 새 행 → 2차 삭제도 포착
--  [실측 2026-08-25 stockTransferList] TR-04175 LastModifiedOn 2026-08-24T14:15:51.06Z(삭제
--  시각) · TR-04174 2026-08-21T18:50:55.247Z(편집 없음) — 이 필드가 편집 시각을 담는다.
-- ⚠️ 부분 유니크 인덱스 금지(PostgREST on_conflict 규칙) — 그래서 bin 은 not null default ''
--  이고 키 컬럼 전부 not null 이다(inv_ledger 유니크 키와 같은 처리).
--
-- ⚠️⚠️ 키 생성 규칙(bin·line_ref·warehouse) 변경 시 기존 원장 행 전체가 "사라진 라인"으로
--  검출된다 — 그런 배포 전에 검출 일시 정지 또는 원장 마이그레이션 동반(EF detectMissingLines
--  절 헤더 참조 · [예정] 트랜스퍼 bin 파싱).
--
-- 조회: select * from inv_missing_lines where resolved_at is null order by detected_at desc;

create table inv_missing_lines (
  id                    bigserial primary key,
  -- 원장 유니크 키 7종 — 어느 행이 사라졌는지 특정 (inv_ledger_event_uq 와 같은 구성)
  doc_type              text        not null,
  doc_number            text        not null,
  line_ref              text        not null,
  event_type            text        not null,
  warehouse             text        not null,
  bin                   text        not null default '',
  sku                   text        not null,
  -- 문서 편집 시각 (Cin7 LastModifiedOn / Updated / LastUpdatedDate 원문) — 재검출 dedup 축
  last_modified_on      timestamptz not null,
  -- 원장에 남아 있는 값 (사람이 Cin7 화면과 대조할 재료)
  existing_qty          numeric     not null,
  existing_occurred_on  date        not null,
  existing_ledger_id    bigint      not null,
  doc_status            text,
  collector             text        not null,          -- COLLECTOR_VERSION — 어느 규칙이 감지했나
  detected_at           timestamptz not null default now(),
  -- 사람이 판단한 뒤 닫는 용도 (예: "TR-04175 라인 삭제 확인 — 상쇄 행 276건 입력")
  resolved_at           timestamptz,
  resolution_note       text
);

-- 재검출 dedup — EF 가 on_conflict=<이 키>&ignore-duplicates 로 쓴다
create unique index inv_missing_lines_uq on inv_missing_lines
  (doc_type, doc_number, line_ref, event_type, warehouse, bin, sku, last_modified_on);
-- 주 용도 조회 둘 — inv_conflicts 관례
create index inv_missing_lines_doc_idx      on inv_missing_lines (doc_type, doc_number);
create index inv_missing_lines_detected_idx on inv_missing_lines (detected_at desc);

-- RLS — inv_conflicts 와 동일(auth_all + anon 전부 회수). 쓰기 주체는 EF(service_role — RLS
-- 우회, 서버사이드 정상 경로 · 규칙 8). 이력 보존을 위해 authenticated 의 DELETE/TRUNCATE 회수 —
-- resolve 는 UPDATE(resolved_at/resolution_note)라 남겨 둔다.
alter table inv_missing_lines enable row level security;
create policy auth_all on inv_missing_lines for all to authenticated using (true) with check (true);
revoke all on inv_missing_lines from anon;
revoke delete, truncate on inv_missing_lines from authenticated;
