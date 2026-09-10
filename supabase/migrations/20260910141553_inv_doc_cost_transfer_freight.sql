-- 원가 레이어 — 트랜스퍼 운송비: 문서 단위 표 inv_doc_cost + inv_layer_apply 안에서 도착 레이어에 원가 비례 배분 (2026-09-10)
--
-- 20260910132601 의 inv_layer_apply(main) 를 create or replace 로 덮어쓴다 — landed 블록 뒤에 운송비 배분 블록 하나를 더한 것 외에 본문 무변.
-- 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다. 보조 함수는 바꾸지 않는다.
-- ⭐ 이 마이그레이션은 **표 + 배분까지**다. 수집기(EF)는 다음 단계 — 지금은 scripts/testdb/transfer_freight_sample.sql 의 시험 데이터로만 검증한다.
--
-- ═══ 배경 — Cin7 은 트랜스퍼 운송비를 문서 단위로만 준다. 배분은 우리가 해야 한다 ═══
--  [실측 GAS 프로브 2026-09-10 · TR-04175 · TR-03975]
--    목록:  CostDistributionType = "Cost"                       ⭐ 원가 비례 배분(Cin7 설정)
--    상세 최상위 키(10): Lines · ManualJournals · ManualJournalsDistributedCosts · Status · TaskID · From · To · Reference ·
--                        DepartureDate · CompletionDate
--    ⭐ ManualJournalsDistributedCosts = ARRAY(0)  ← 둘 다 빈 배열       ⭐ Lines[0] 원가류 필드 = (없음) ← TransferQuantity 만
--  ⇒ 화면의 「Distribute journals using the product: Cost」 는 Cin7 내부 설정이고 결과를 API 로 주지 않는다. 우리가 원가 비례로 배분한다.
--
--  ~~ManualJournals 원소 키 여섯: Debit · Credit · Reference · Date · Amount · IsSystem     [실측 원문]~~
--  ~~  TR-03975  ARRAY(2)~~
--  ~~    [0] {"Debit":"_1150040007_","Credit":"_59_","Reference":"TR-03975","Date":"2026-08-26T00:00:00","Amount":4878.11,"IsSystem":true}~~
--  ~~    [1] {"Debit":"_59_","Credit":"_136_","Reference":"B6900109","Date":"2026-08-27T00:00:00","Amount":398.75,"IsSystem":false}~~
--  ~~  TR-04175  ARRAY(1)~~
--  ~~    [0] {"Debit":"_59_","Credit":"_136_","Reference":"B6913286","Date":"2026-09-04T00:00:00","Amount":249.33,"IsSystem":false}~~
--  ~~⚠️⚠️ IsSystem 으로 걸러야 한다 — 배열 길이로 판단하면 틀린다(TR-04175 는 시스템 저널이 없어 1행이고 그것이 운송비 · TR-03975 는 [1]).~~
--  ~~  · IsSystem=true  = 운송중 계정 이동(_1150040007_ In Transit ↔ _59_ 재고). 재고 원가와 무관 — 금액이 재고 자체(4,878.11)다.~~
--  ~~  · IsSystem=false = 운송비. Debit='_59_'(재고) / Credit='_136_'(Freight-COS).~~
--  ⚠️⚠️ [정정 2026-09-10 · GAS 프로브 실측 14:40 · TR-03975·TR-04175·TR-03976] **위 취소선 표는 창작이었다 — IsSystem 은 존재하지 않는 필드다.**
--    응답 전체 문자열 검색 0건(237,148 · 94,981 · 192,365자). 「[0] Debit=_1150040007_ · 4878.11 · IsSystem=true」는 **발주 구조를 트랜스퍼에 옮겨 적은 것**:
--    IsSystem true/false 짝 = 발주 ManualJournals[0].Lines 의 모양 · _1150040007_ 은 트랜스퍼 **헤더 InTransitAccount** 를 저널로 오독 · 4878.11 은 응답에 없다.
--    ⭐ 트랜스퍼 실물: 최상위 키 18개(… CostDistributionType · InTransitAccount · … · ManualJournals · SkipOrder · Order) · ManualJournals 는 ARRAY(1) 이고
--      **저널이 바로 원소**(Lines 겹 없음) · 원소 키 11개 = TaskID · ID · Reference · Amount · Date · Debit · Credit · ManualJournalsDistributedCosts ·
--      vDimensionDefaultValueStockTransferJournals · ValidationText · ValidationState. 세 문서 모두 Debit _59_ · Credit _136_:
--        TR-03975 {"Reference":"B6900109","Amount":398.75,"Date":"2026-08-27T00:00:00"} · TR-03976 {"B6900109",229.2,"2026-08-27"} · TR-04175 {"B6913286",249.33,"2026-09-04"}
--    ⭐ 운송중 계정 이동은 ManualJournals 로 오지 않는다 — Cin7 내부 처리 · 헤더 InTransitAccount 에 코드만. Debit/Credit 객체는 중첩 전체에서 root.ManualJournals[0] 하나뿐.
--    ⭐ 발주(/advanced-purchase · PO-01111 실측 15:06)는 다르다: ManualJournals[0] 키 4개(TaskID · InvoicingAndReceivingNumber · Status · Lines) · **Lines 겹 안에** 저널 ·
--      Lines[0] {"Stock in Transit",91877.51,Debit _59_,Credit _1150040012_,IsSystem:true} · Lines[1] {"16898",90,Debit _59_,Credit _135_,IsSystem:false} — 발주에는 IsSystem 이 실재한다.
--    계정 코드: 발주 In Transit _1150040012_ · 비용 _135_(landed) / 트랜스퍼 In Transit _1150040007_ · 비용 _136_(운송비). ⬜ _135_·_136_ 계정명 미확인.
--    ⇒ 트랜스퍼 필터 = **Debit _59_ AND Credit _136_**(둘 다 화이트리스트) · 「배열 길이로 판단」 문장의 근거(2행 vs 1행)도 소멸 — 세 문서 모두 1행이나 전량 순회는 유지.
--  ⭐ 저널은 나중에 붙는다 — TR-03975 Departure 08-14 · Completion 08-26 · 저널 08-27 / TR-04175 Departure 08-21 · Completion 09-02 · 저널 09-04.
--    ⚠️ TR-04175 는 09-09 실측엔 저널이 없었고 09-10 에 붙었다(LastModifiedOn = 2026-09-10T15:32:06.049Z) ⇒ ⭐ LastModifiedOn 이 수집 커서 축이다(다음 단계).
--    📌 저널 날짜는 도착일 +1~2일로 일관되지만 문서가 갱신되는 시점은 훨씬 늦다.
--
-- ═══ A. 왜 문서 단위 표(inv_doc_cost)를 따로 두나 ═══
--  · inv_cost 는 sku·line_ref·qty·unit_cost 가 전부 not null 이라 문서 단위 금액을 담을 수 없다 — 가짜 SKU 를 넣지 않는다.
--  · 표는 문서 금액을 담기만 한다. ⭐ 배분하지 않는다.
--  · ~~IsSystem=true 는 담지 않는다(운송중 계정 이동 · 재고 원가와 무관).~~ [정정 2026-09-10] 그런 행은 오지 않는다 — 계정 화이트리스트(Debit _59_ · Credit _136_)에
--    걸린 행만 담지 않는다. ⭐ 필요하면 raw 에 그 문서의 ManualJournals 배열 전체를 남긴다(「왜 이 금액만 골랐나」를 되짚을 수 있게).
--  · ⚠️ amount 는 유니크 키에서 뺐다 — 금액이 정정될 수 있으므로 upsert 로 덮어쓴다(inv_cost 와 같은 이유).
--  · ⚠️ ref_number 가 키에 있다 — 인보이스가 여러 장 붙으면 각각 남아야 한다. 📌 occurred_on 도 키에 있어 같은 인보이스가 다른 날짜로
--    정정돼도 공존한다(⚠️ inv_cost 와 같은 약점 · ⬜ 실측 표본 없음).
--  · ⚠️ ⬜ 같은 인보이스가 같은 날 두 줄로 오는 경우는 미확인 — 그러면 유니크에 걸려 하나만 남는다(두 문서 모두 1행이라 표본 없음).
--  · ⚠️ amount >= 0 CHECK 를 걸지 않는다 — 정정(과다 계상 되돌림)이 음수로 올 수 있다. ⭐ 배분 단계의 가드(B-4)가 방어한다.
--  · doc_type·kind CHECK 를 좁게 걸었다('transfer' · 'transfer_freight') — 앞으로 다른 축이 오면 그때 넓힌다(좁게 시작하면 예상 못 한 값이 조용히 들어오지 않는다).
--  · ⚠️ ref_number 는 nullable 인데 유니크 키에 들어 있다 — null 이면 유니크가 안 걸린다(규칙 29 의 약점과 같은 모양). 실측 두 건 모두 Reference 가 있었다.
--    수집기가 붙을 때 null 을 '' 로 넣을지 결정한다(⬜).
--
-- ═══ B. 배분 — inv_layer_apply 안에서 · PO landed(20260910132601)와 같은 자리·같은 구조 ═══
--  ⭐ 왜 EF 가 배분하지 않나 — ① 수집기가 inv_layer 에 의존하면 의존 방향이 역전된다(원칙: 모듈은 레고처럼 · 접점은 사건 하나)
--    ② 배분 결과가 굳으면 레이어 규칙이 바뀌어도 안 바뀐다 ⇒ 불변 조건(§3)이 깨진다. ⭐ apply 에서 하면 매번 다시 계산된다.
--  ⚠️ 불변 조건에 원천이 하나 늘었다: inv_ledger + inv_cost + inv_doc_cost + inv_snapshot.
--  B-1 대상 레이어 = 그 트랜스퍼가 도착 창고에 만든 레이어: inv_layer where origin_type='transfer' and doc_number=<TR> and warehouse <> 'IN_TRANSIT'.
--      ⚠️ IN_TRANSIT 레이어는 대상이 아니다 — 운송비는 도착지 재고에 녹는다(Debit='_59_' 가 재고 계정 · 실무 목적은 에드먼튼 매출 gross 마진 · Caleb 확인 2026-09-09).
--  B-2 배분 규칙(원가 비례 · CostDistributionType='Cost'): 레이어 원가 = unit_cost × qty · 배분액 = 문서 금액 × (레이어 원가 / 문서 레이어 원가 합).
--      ⚠️ unit_cost × qty 를 쓴다(remaining 이 아니다) — 배분은 입고 시점의 원가 구성을 따르고 그 뒤 얼마가 팔렸는지와 무관하다.
--      ⚠️ 끝수: 소수 6자리 반올림 뒤 마지막 레이어(id 순)에 잔액을 몰아 합 = 문서 금액(remainder on last · inv-cost alloc.rule 과 같은 관례).
--  B-3 삽입: inv_layer_cost_add (layer_id, 'transfer_freight', amount, occurred_on=저널 날짜, doc_number=TR, line_ref=그 레이어의 line_ref, ref_number=인보이스 번호).
--      · inv_layer_cost_add.line_ref 는 not null — transfer 레이어의 line_ref 는 원장 행의 line_ref(not null)를 복사하므로 항상 있다
--        ([실측 테스트 DB 2026-09-10] transfer 레이어 3,341 중 line_ref null 0).
--      · ⚠️ cost_add 유니크 키 (layer_id, kind, doc_number, line_ref, occurred_on) 에 ref_number 가 없다 ⇒ 같은 문서·같은 날 인보이스가 둘이면
--        그대로 넣으면 유니크 위반. ⭐ 날짜별로 합산해 1행으로 넣고 ref_number 는 쉼표 연결한다 — 인보이스별 식별은 inv_doc_cost 가 갖는다.
--        카운터 freight_multi_ref 로 그 (문서, 날짜) 수를 센다(실측 0 · 0 이 아니면 신호).
--      · p_until 반영: inv_doc_cost.occurred_on <= p_until.
--  B-4 가드: · 저널 행 금액이 음수면 예외(문서번호·인보이스·금액) — 정정일 수 있지만 표본이 없어 규칙을 정할 수 없다 ⇒ 차단하고 그때 판단.
--            · 레이어 원가 합 <= 0 이면 배분 불가 ⇒ 예외 없이 freight_no_basis 로 세고 건너뛴다(0 으로 나누지 않는다).
--              원가 미상 레이어(cost_source='unknown' · unit_cost 0)만 있는 문서가 그렇다 — [실측] 기초 이전 출발분 245레이어 · TR-03975 가 그 경우(도착 144레이어 전부 unknown).
--              ⭐ 그 문서 금액은 freight_no_basis_amount 로 합산한다(문서 수만 세면 금액을 모른다 · [실측 2026-09-10] TR-03975 $398.75).
--
--  ⚠️⚠️ 배분 기준이 없는 문서는 운송비를 버린다 — 그 금액을 세어 둔다.
--    [실측 2026-09-10] TR-03975 $398.75 가 freight_no_basis 로 떨어졌다. ⚠️ 그 문서는 기초 이전 출발(8/14 출발 · leg 1·2 가 since 로 원장에 없음)이라
--    IN_TRANSIT 레이어가 없고, 도착 레이어가 cost_source='unknown' · unit_cost 0 으로 만들어졌다 ⇒ 원가 비례로 나눌 기준이 0 이다.
--    ⇒ ⭐ 수량 비례로 배분하지 않는다(Caleb 판정 2026-09-10). 이유 둘:
--      · ⚠️ Cin7 은 CostDistributionType='Cost'(원가 비례)다 — 우리가 수량 비례로 하면 배분 방식이 달라지고 Cin7 평가액 대조에서
--        「방식이 달라 차이가 난다」가 또 생긴다. ⭐ 방식이 같아야 차이의 원인을 규명할 수 있다.
--      · ⭐ 재기준선이 지운다 — 기준선을 다시 잡으면 그 레이어에 원가가 붙어 저절로 배분된다.
--    ⚠️ 대가: 그만큼 우리 재고 평가액이 Cin7 보다 낮다. Cin7 은 그 운송비를 재고에 녹였다(Debit='_59_').
--    ⇒ ⭐ freight_no_basis_amount 가 그 차이의 크기를 알려주는 창구다 — Cin7 대조(§13 ③)에서 이 값만큼은 설명된 차이다.
--    ⬜ 미확인 — 실물 비중: 표본이 둘뿐이라 전체 트랜스퍼 중 몇 %가 no_basis 인지 모른다. 수집기(EF)가 붙으면 그 비율이 나온다.
--            · 대응 레이어가 아예 없으면 freight_orphan(0 이 아니면 신호).
--  B-5 반환에 추가: freight_rows · freight_amount(삽입 행 수·합계) · freight_docs(배분한 문서 수) · freight_no_basis · freight_no_basis_amount(그 문서 금액 합) ·
--      freight_orphan · freight_multi_ref.
--
-- ═══ 아직 안 된 것 ═══
--  · 수집기(EF) — stockTransfer 상세의 ManualJournals(~~IsSystem=false~~ → [정정 2026-09-10] Debit _59_ AND Credit _136_)를 inv_doc_cost 로 upsert. LastModifiedOn 커서. 지금은 scripts/testdb/ 시험 데이터만.
--  · 20260910132601 헤더의 「트랜스퍼 운송비 … 대상이 0건」 문장은 이 마이그레이션으로 낡았다(그 파일은 적용됐으므로 고치지 않는다).

-- ── A. inv_doc_cost ──
create table if not exists inv_doc_cost (
  id             bigint generated always as identity primary key,
  doc_type       text not null,      -- 'transfer' (앞으로 다른 축이 올 수 있다)
  doc_number     text not null,
  kind           text not null,      -- 'transfer_freight'
  amount         numeric not null,   -- ⚠️ CHECK 없음 — 정정이 음수로 올 수 있다. 배분 가드가 방어
  occurred_on    date not null,      -- ⚠️ 저널 Date (인보이스 날짜)
  ref_number     text,               -- ⭐ Service Invoice 번호 (B6913286)
  debit_account  text,               -- '_59_'
  credit_account text,               -- '_136_'
  collector      text not null,
  refreshed_at   timestamptz not null default now(),
  raw            jsonb,              -- 그 문서의 ManualJournals 배열 전체(~~IsSystem=true 포함~~ → 화이트리스트에 걸린 행 포함 · 2026-09-10 정정) — 「왜 이 금액만 골랐나」 추적용
  constraint inv_doc_cost_doc_type_ck check (doc_type in ('transfer')),
  constraint inv_doc_cost_kind_ck     check (kind in ('transfer_freight')),
  constraint inv_doc_cost_uq
    unique (doc_type, doc_number, kind, ref_number, occurred_on)
);
create index if not exists inv_doc_cost_doc_idx on inv_doc_cost (doc_type, doc_number);

alter table inv_doc_cost enable row level security;
create policy auth_all on inv_doc_cost for all to authenticated using (true) with check (true);
revoke all on inv_doc_cost from anon;
revoke delete, truncate on inv_doc_cost from authenticated;

-- ── B. inv_layer_apply(main) — 20260910132601 + 운송비 배분 블록 ──
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, id · source 필터 없음)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — 레이어가 전부 만들어진 뒤 집합 연산 한 번 ═══
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;

  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed';

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      order by doc_number
  loop
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t;
      get diagnostics v_rows = row_count;
      v_fr_rows := v_fr_rows + v_rows;
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;
  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
