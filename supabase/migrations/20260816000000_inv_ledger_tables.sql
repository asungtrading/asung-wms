-- 재고 원장 1단계 — 테이블 4개만 (2026-08-16 · 그릇만: 수집 코드·대조 로직은 2단계)
--
-- 설계 근거: docs/design/ledger-design.md (프로브 1~22차 실측)
--          + docs/design/2026-08-06-inventory-ledger-principles.md (착수 전 원칙)
-- 원칙 요약: **수량만·창고 단위**로 시작한다. 원가(amount·value)와 자리(bin)는 값을 받아
--   저장하되 계산에는 안 쓴다 — **둘 다 나중에 소급이 불가능해서 지금부터 담는 것**이다.
--   shadow: 쌓기만 하고 어디에도 쓰지 않는다.
-- ⚠️ 하지 않은 것(의도 — 2026-08-16 사용자 지시):
--   · 잔고 테이블 없음 — 스냅샷 + 원장으로 계산한다. 느려지면 그때 중간 저장을 도입한다
--     (없어도 되는 복잡도를 미리 넣으면 틀렸을 때 찾기 어려워진다)
--   · 뷰·트리거·RPC 없음 — 조회 형태는 대조 로직을 만들 때 정한다
-- ⚠️ Supabase 티어: 테이블 생성은 무관하나, 재고 레코드 적재 전 업그레이드 확인 필요(로드맵).

-- ─────────────────────────────────────────────────────────
-- 1) inv_ledger — 원장 본체. 한 행 = 재고 변동 하나.
--    append-only: UPDATE/DELETE 하지 않는다 — 코드가 아니라 권한으로 강제(파일 하단).
--    틀린 행은 고치는 게 아니라 **반대 방향 항목을 추가**한다(원칙 문서 1번).
-- ─────────────────────────────────────────────────────────
create table inv_ledger (
  id           bigint generated always as identity primary key,
  occurred_on  date not null,        -- 사건이 일어난 날. 우리가 처리한 시각이 아니다(그건 created_at)
  -- 같은 날 정렬용 힌트: 1=유입(+) 먼저 · 2=유출(−) 나중 — 일중 시각이 없어도
  -- 유입을 먼저 적용해 음수 중간잔고를 피한다
  seq_hint     smallint not null,
  sku          text not null,        -- base SKU. UOM(변형) SKU 는 원장 대상이 아니다
  -- ⚠️ Cin7 표기 그대로 저장('Asung Trading Inc.' / 'Asung - Edmonton') — 외부 원문 컬럼이라
  --   CHECK 를 걸지 않는다(창고 추가·표기 변경에 수집이 죽으면 안 된다).
  --   예외 'IN_TRANSIT' 은 우리 합성값 — 언더스코어 = "Cin7 원문 아님" 표기(NOT_IN_CIN7 선례와 동일 관례)
  warehouse    text not null,
  -- ⚠️ NULL 금지 — 아래 유니크 키에 들어간다. "bin 없음" 은 '' 로 표현한다:
  --   부분 유니크 인덱스(WHERE bin IS NOT NULL 류)는 PostgREST on_conflict 를 조용히 깬다
  --   (규칙 29 실사고 — 리시빙 discrepancy 가 구현 이후 한 건도 기록되지 않았다)
  bin          text not null default '',
  -- 부호 있는 수량. 유출이 음수. ⚠️ 값 CHECK 없음(2026-08-16 사용자 결정) — 소수 수량이 실재한다
  --   ([실측] UNF18155 판매 5건 5.25개 · FG-00094 UNF18158 x0.25). Cin7 원본을 받는 컬럼에
  --   우리 가정을 CHECK 로 박으면 수집이 죽는다. 0 델타 스킵 여부는 수집 코드의 판단이고 DB 는 받아들인다.
  qty_delta    numeric not null,
  event_type   text not null,
  doc_type     text not null,
  doc_number   text not null,        -- 예: SO-14286 · PO-01083 · TR-03976 · ST-01026 · FG-00110
  doc_task_id  text,                 -- Cin7 내부 식별자(있으면)
  -- 문서 안 라인 식별. 없으면 인덱스 문자열. ⚠️ 안정 식별자(Cin7 라인 ID)가 있으면 그것을 우선할 것 —
  --   인덱스 폴백은 재수집 사이에 라인이 추가/삭제/재정렬되면 다른 라인을 가리킨다
  --   (유니크 키의 급소 — sku 를 키에 넣은 이유는 유니크 인덱스 주석 참조)
  line_ref     text not null,
  amount       numeric,              -- 재고 가치 변동. 계산엔 안 쓰지만 저장한다(원가는 소급 불가)
  source       text not null,        -- cin7 / wms
  -- ⚠️ 원본 응답 저장 — 나중에 추적 불가를 막는 유일한 수단. 저장 단위는 **행 단위 원본**
  --   (그 행을 만든 라인 + 최소 문서 헤더)로 할 것: 행마다 문서 전체를 넣으면 344라인 트랜스퍼
  --   (×4행)에서 문서 원본이 ~1,376벌 중복된다. 정확한 형태는 2단계(수집) 결정 사항.
  raw          jsonb,
  created_at   timestamptz not null default now(),
  -- CHECK 3종 — 새 값 추가는 CHECK 변경 마이그레이션이 코드보다 먼저(규칙 41 절차).
  -- ⚠️ check-class-values.sh 훅은 wms_discrepancies.reason / wms_reports.kind 만 대조한다 —
  --   inv_* CHECK 는 훅 밖이므로 값을 늘릴 때 이 절차를 사람이 기억해야 한다.
  constraint inv_ledger_event_type_check check (event_type in (
    'sale_out',         -- 판매 출고 (−)
    'credit_in',        -- 반품 입고 (+)
    'po_in',            -- 발주 입고 (+)
    'transfer_out',     -- 창고이동 출발 (−)
    'transfer_in',      -- 창고이동 도착 (+)
    'adjust_existing',  -- 조정 · 기존 재고 (목표수량 − 당시수량)
    'adjust_new',       -- 조정 · 신규 재고 (+)
    'assemble_in',      -- 조립 완제품 (+)
    'assemble_out'      -- 조립 구성품 (−)
  )),
  constraint inv_ledger_doc_type_check check (doc_type in
    ('sale', 'purchase', 'transfer', 'adjustment', 'assembly', 'creditnote')),
  constraint inv_ledger_source_check check (source in ('cin7', 'wms')),
  constraint inv_ledger_seq_hint_check check (seq_hint in (1, 2))
);

-- 중복 방지 유니크 — 수집 배치가 실패해서 재실행해도 두 번 쌓이지 않는다(upsert on_conflict 대상).
-- ⚠️ 창고이동은 한 문서가 4행(출발−·IN_TRANSIT+·IN_TRANSIT−·도착+)이라 event_type+warehouse 가
--    키에 필요하고, 같은 창고 안 자리 이동은 bin 까지 있어야 구분된다.
-- ⚠️ sku 포함 (2026-08-16 검토 채택): line_ref 인덱스 폴백이 재수집 사이에 다른 라인(다른 SKU)을
--    가리키게 되면, sku 없는 키에서는 ignore-duplicates upsert 가 그 행을 **조용히** 버린다 —
--    이 레포가 가장 경계하는 실패 모드(조용한 누락). sku 가 키에 있으면 행이 들어와 일일 대조의
--    diff 가 시끄럽게 잡는다(가시적 이중 계상 > 조용한 누락).
-- ⚠️ 전체 유니크(WHERE 절 없음) — 부분 유니크는 on_conflict 를 깬다(규칙 29). bin NOT NULL '' 이 그 조건.
create unique index inv_ledger_event_uq on inv_ledger
  (doc_type, doc_number, line_ref, event_type, warehouse, bin, sku);

create index inv_ledger_sku_wh_on_idx on inv_ledger (sku, warehouse, occurred_on);  -- 잔고 계산용
create index inv_ledger_occurred_idx  on inv_ledger (occurred_on);                  -- 일자별 조회
create index inv_ledger_doc_idx       on inv_ledger (doc_type, doc_number);         -- 문서 역추적

alter table inv_ledger enable row level security;
create policy auth_all on inv_ledger for all to authenticated using (true) with check (true);

-- append-only 강제 — 원칙 문서 1번("선택이 아니라 필수"): 코드가 아니라 권한으로.
-- wms_rollback_archive 선례(authenticated 는 INSERT+SELECT 만).
-- ⚠️ default privileges 가 새 테이블에 ALL 을 부여하므로 **명시 회수가 필수**
--    ([실측 2026-08-06] wms_order_pack_progress 뷰에 anon 이 INSERT/UPDATE/DELETE/TRUNCATE 까지
--     부여돼 있었다 — "스키마 기본 권한이 헐겁다"). service_role(수집 EF/GAS)은 자동 전권 유지 —
--    서버사이드 정상 경로(규칙 8). 원장 정정은 UPDATE 가 아니라 반대 방향 행 INSERT 다.
revoke all on inv_ledger from anon;
revoke update, delete, truncate on inv_ledger from authenticated;

-- ─────────────────────────────────────────────────────────
-- 2) inv_snapshot — 기초 재고 (시작 시점 스냅샷 · 약 13,847행 예상)
-- ─────────────────────────────────────────────────────────
create table inv_snapshot (
  id           bigint generated always as identity primary key,
  snapshot_key text not null,        -- 스냅샷 회차 식별 (예: '2026-08-16-initial')
  taken_at     timestamptz not null, -- 찍은 시각
  sku          text not null,
  warehouse    text not null,
  -- ⚠️ 자리 없는 재고(Cin7 Bin=null 인데 OnHand≠0)도 담아야 한다 — [실측] 11건.
  --    자리 있는 것만 담으면 그 11건이 통째로 누락된다. 적재 규칙: 자리가 지정된 것은 자리별로,
  --    자리 없이 떠 있는 재고는 bin='' 한 행으로.
  bin          text not null default '',
  qty          numeric not null,     -- Cin7 OnHand
  value        numeric,              -- Cin7 StockOnHand(= 평가액). ⚠️ 이름과 달리 수량이 아니다
  created_at   timestamptz not null default now()
);
create unique index inv_snapshot_uq on inv_snapshot (snapshot_key, sku, warehouse, bin);
alter table inv_snapshot enable row level security;
create policy auth_all on inv_snapshot for all to authenticated using (true) with check (true);
revoke all on inv_snapshot from anon;

-- ─────────────────────────────────────────────────────────
-- 3) inv_compare — 일일 대조 결과 (창고 단위 — bin 은 잔고 계산에 쓰지 않는다)
-- ─────────────────────────────────────────────────────────
create table inv_compare (
  id          bigint generated always as identity primary key,
  checked_on  date not null,
  sku         text not null,
  warehouse   text not null,
  ledger_qty  numeric not null,      -- 우리(원장) 계산
  cin7_qty    numeric not null,      -- Cin7 실측
  -- generated column (2026-08-16 검토 채택) — "diff ≠ 실제 차" 라는 오류 부류를 원천 소멸.
  -- 선언적 컬럼이라 "트리거·RPC 금지"(1단계 그릇만)와 충돌하지 않는다.
  diff        numeric generated always as (ledger_qty - cin7_qty) stored not null,
  verdict     text not null,
  note        text,
  created_at  timestamptz not null default now(),
  constraint inv_compare_verdict_check check (verdict in (
    'match',          -- 차이 없음
    'explained',      -- 설명되는 차이 (운송 중 등)
    'missing_event',  -- 우리가 사건을 놓침
    'calc_error',     -- 우리 계산 오류
    'unknown'         -- 원인 미상 — 사람이 봐야 함
  ))
);
create unique index inv_compare_uq on inv_compare (checked_on, sku, warehouse);
alter table inv_compare enable row level security;
create policy auth_all on inv_compare for all to authenticated using (true) with check (true);
revoke all on inv_compare from anon;

-- ─────────────────────────────────────────────────────────
-- 4) inv_sync_state — 수집 진행 상태.
--    source_key 어휘는 doc_type 과 동일하지만 CHECK 는 걸지 않는다 — 상태 테이블은 새 소스
--    (예: 스냅샷 회차·보정 배치)가 생길 수 있어 유연하게 둔다.
-- ─────────────────────────────────────────────────────────
create table inv_sync_state (
  source_key  text primary key,      -- sale / purchase / transfer / adjustment / assembly / creditnote
  -- 증분 조회 기준값 — "있는 것만" 채운다. ⚠️ [실측] 판매·발주·크레딧노트는 UpdatedSince 증분이
  --   되지만, **조정·이동·조립은 날짜 축이 없어 매번 전량 조회 후 우리 쪽에서 걸러야 한다.**
  last_cursor text,
  last_run_at timestamptz,
  last_ok_at  timestamptz,
  note        text
);
alter table inv_sync_state enable row level security;
create policy auth_all on inv_sync_state for all to authenticated using (true) with check (true);
revoke all on inv_sync_state from anon;
