-- PO 모듈 ② 공급처 — 할인 표 신설: supplier_discount (2026-09-12) · ⭐ 오늘 새로 선 표(§7-b 「표 셋 → 넷」의 넷째) · ⚠️ 행 적재 없음 — 내용은 Cin7 에 없다(실무 지식 · 사람이 채운다)
--
-- 목표: 마이그레이션 1개 · 표 1개 · 행 0건. 뼈대만.
-- 선행: 20260912202952(supplier 본체 · 226행) · 20260912210733(supplier_address 87 · supplier_contact 237) — supplier(id) 를 FK 로 참조한다.
-- 정본: docs/design/po-module.md §7-b 의 D · §5(공통 규약). 이 파일과 정본이 어긋나면 정본이 이긴다.
--
-- ═══ 왜 표인가 — Cin7 의 Discount 칸(하나)을 대체하는 것이 아니다 (§7-b-D) ═══
--   Cin7 은 공급처에 할인 칸을 하나만 준다. 그 하나로는 실태를 못 담아서 실무가 그 칸을 비워 두고 인보이스를 보고 총액을 계산해
--   additional cost 에 마이너스로 넣어 왔다. 칸이 실태를 못 담으니 우회로가 생긴 것이다 ⇒ 우리는 칸 하나가 아니라 줄이 여럿 달리는 표로 받는다.
--   📌 ims-principles.md §4-d(커스텀 속성을 물려받지 않는다 — 뜻이 있는 칸으로 승격한다)가 실제로 작동하는 첫 사례.
--   ⚠️ 본체 supplier 에서 Cin7 Discount 칸을 안 담은 것과 이 표는 다른 이야기다 — 「칸 하나」를 안 담은 것이지 할인을 안 담는 것이 아니다.
--
-- ═══ 실물 근거 — 체인 할인은 차례로 곱해진다. 더하는 것이 아니다 [Ampro INV 0094204-IN · 2026-07-10] ═══
--   Net Invoice 20,729.70 → Trade 17% = 3,524.05(남은 17,205.65) → Damage 1% = 172.06(남은 17,033.59) → Full Line 3% = 511.01 → Invoice Total 16,522.58 ✅ 인보이스와 정확히 일치
--   ⚠️ 단순 합(21%)으로 계산하면 16,376.46 — 146 달러 어긋난다 ⇒ seq(곱하는 차례)가 결과를 바꾼다.
--
-- ═══ 설계 판단 (Caleb 확정 2026-09-12 · §7-b-D) ═══
--   · ⭐ name 은 자유 문자열 — 목록(마스터)으로 만들지 않는다. 공급사마다 이름이 다르다(Trade / Damage / Full Line / Volume DC …). 실태를 모르는 채 목록부터 만들면 목록이 실태를 왜곡한다
--     (ref_account.name 에 유니크를 안 건 것과 같은 판단). 어떤 이름이 몇 번 나오는지 보고 나서 승격한다.
--   · ⭐ (supplier_id, seq) UNIQUE — 일반 제약(부분 유니크 인덱스 아님 · PostgREST on_conflict). 순서가 겹치면 어느 것을 먼저 곱할지 알 수 없다.
--     📌 중간에 끼워 넣을 때는 10·20·30 처럼 띄어 매기면 그 사이에 15 를 넣을 수 있다(줄이 많아야 서넛).
--   · ⭐ 매입가 할인만 담는다. 조기결제 할인은 ref_payment_term(discount_days·discount_percent · §4-②)이 정본 —
--     매입가 할인은 물건을 받는 순간 확정되고 인보이스에 이미 찍혀 와 재고 원가로 내려간다 · 조기결제 할인은 돈을 낼 때 확정되고 기한을 놓치면 안 생겨 원가로 내려가지 않는다.
--     같은 값이 두 곳에 살면 어긋났을 때 어느 쪽이 맞는지 알 수 없다.
--   · ⚠️ 층 칸(bool/enum)을 두지 않는다 — 종류가 하나뿐이면 아무것도 구별하지 못한다(ref_payment_term.Method 를 안 만든 판단).
--     매입가도 결제도 아닌 셋째가 나오면 그때 nullable 로 붙이고 null 을 「아직 안 정함」으로 쓴다(§4-d).
--   · ⭐ 마스터는 제안이지 잠금이 아니다 — 매번 같은 할인만 여기 담는다. 스페셜 할인은 문서에서 줄을 추가하고(마스터에 없는 이름도 받는다), 마스터에서 온 줄도 문서에서 고칠 수 있다(이번 달만 15%).
--     고친 사실이 문서에 남으면 「마스터가 낡았나 이번만 달랐나」를 사람이 판단할 수 있다. 실제 금액의 정본은 인보이스이고 이 표의 비율은 제안·검증용이다 — 마스터가 낡아도 장부는 맞는다.
--   · ⚠️ 채워야 할 공급사가 몇 곳인지 세어 보지 않았다(Caleb: 정확히 세기 어렵다 · 지금 만드는 게 맞다). 줄이 0개인 공급사가 대부분이어도 표가 비어 있을 뿐이다.
--   · ⭐ source 기본값 'manual' — 다른 표와 다르다. 다른 표는 Cin7 에서 긁어오므로 'cin7' 이 기본이지만 이 표는 Cin7 에 없는 값을 사람이 채운다.
--     check 목록 자체는 다른 표와 같게 ('cin7','manual'). cin7_id 는 공통 규약대로 두되 항상 null 이다(Cin7 에 대응 개념이 없다).
--   · percent 는 numeric — 금액에 작용하는 숫자라 부동소수점을 쓰지 않는다. CHECK 0~100 · seq CHECK 1 이상.
--
-- ═══ 권한 — 주소·연락처와 같다 ═══
--   DELETE 를 연다 — 할인 줄은 없어질 수 있고 어느 문서도 이 행을 가리키지 않는다(문서의 할인 줄은 문서에 산다 · §7-b 「⑤ 로 넘기는 판단」 1). ⚠️ TRUNCATE 는 막는다.
--
-- ═══ 공통 규약 확인 (§5 · 20260912210733 과 동일한 모양) ═══
--   공통 칸(id·cin7_id·is_active·source·note·created_at·updated_at) · FK on delete no action(cascade 금지) · 인덱스 supplier_discount_supplier_idx
--   · 트리거 supplier_discount_set_updated_at(공용 함수 재사용 · ⚠️ 다시 만들지 않는다) · RLS auth_all + revoke anon · revoke truncate from authenticated(delete 는 revoke 하지 않는다).

-- ── supplier_discount ──
create table if not exists supplier_discount (
  id          uuid primary key default gen_random_uuid(),
  cin7_id     uuid unique,
  is_active   boolean not null default true,
  source      text not null default 'manual',
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  supplier_id uuid not null references supplier(id) on delete no action,
  name        text not null,
  percent     numeric not null,
  seq         integer not null,
  constraint supplier_discount_source_ck  check (source in ('cin7','manual')),
  constraint supplier_discount_percent_ck check (percent >= 0 and percent <= 100),
  constraint supplier_discount_seq_ck     check (seq >= 1),
  constraint supplier_discount_supplier_id_seq_key unique (supplier_id, seq)
);
create index supplier_discount_supplier_idx on supplier_discount (supplier_id);

comment on table supplier_discount is 'PO 모듈 ② 공급처 매입가 할인 — 공급처당 여러 줄 · 차례(seq)로 곱하는 체인(⚠️ 더하는 것이 아니다 · Ampro 실물: 17%→1%→3% 가 인보이스와 일치 · 단순 합 21% 는 146 달러 어긋난다). Cin7 의 Discount 칸(하나)을 대체하는 것이 아니라 그 칸으로는 담지 못하던 것을 담는다(실무는 그 칸을 비우고 additional cost 마이너스로 우회해 왔다) · ⚠️ 매입가 할인만 — 조기결제 할인은 ref_payment_term(discount_days·discount_percent)이 정본, 같은 값이 두 곳에 살면 어긋났을 때 어느 쪽이 맞는지 알 수 없다 · ⚠️ 층 칸(bool/enum) 없음 — 종류가 하나뿐이면 아무것도 구별하지 못한다(ref_payment_term.Method 를 안 만든 판단), 셋째가 나오면 nullable 로 붙이고 null=「아직 안 정함」 · ⭐ 마스터는 제안이지 잠금이 아니다 — 매번 같은 할인만 여기, 스페셜은 문서에서 줄 추가, 마스터에서 온 줄도 문서에서 고칠 수 있다, 실제 금액의 정본은 인보이스고 이 비율은 제안·검증용 · ⚠️ 채워야 할 공급사 수는 세지 않았다 — 줄 0개인 공급사가 대부분이어도 표가 비어 있을 뿐 · ⚠️ 행 적재 없음(2026-09-12 신설 시점) — Cin7 에 없는 실무 지식이라 사람이 채운다 · source 기본 manual(⭐ 다른 표와 다르다) · cin7_id 항상 null · DELETE 열림 · TRUNCATE 막음 · 정본 docs/design/po-module.md §7-b-D';
comment on column supplier_discount.supplier_id is 'FK → supplier(id) · NOT NULL · on delete no action(cascade 금지) · 인덱스 supplier_discount_supplier_idx';
comment on column supplier_discount.name        is '⭐ 자유 문자열 · 목록(마스터)으로 만들지 않는다. 공급사마다 이름이 다르다(Trade / Damage / Full Line / Volume DC …). 실태를 모르는 채 목록부터 만들면 목록이 실태를 왜곡한다(ref_account.name 에 유니크를 안 건 것과 같은 판단) — 어떤 이름이 몇 번 나오는지 보고 나서 승격한다';
comment on column supplier_discount.percent     is '기본 비율(0~100 · CHECK). ⚠️ 금액에 작용하는 숫자라 numeric — 부동소수점을 쓰지 않는다. 문서에서 고칠 수 있는 제안값이고 실제 금액의 정본은 인보이스';
comment on column supplier_discount.seq         is '⚠️⚠️ 곱해지는 차례(1 이상 · CHECK) · unique (supplier_id, seq) — 체인 할인은 차례로 곱해지므로 순서가 겹치면 어느 것을 먼저 곱할지 알 수 없다. [실물 Ampro INV 0094204-IN 2026-07-10] Net 20,729.70 → Trade 17% 3,524.05(남은 17,205.65) → Damage 1% 172.06(남은 17,033.59) → Full Line 3% 511.01 → Total 16,522.58 ✅ · 단순 합 21% 면 16,376.46 (146 달러 어긋남). 📌 10·20·30 처럼 띄어 매기면 사이에 끼울 수 있다';
comment on column supplier_discount.source      is '기본 manual(⭐ 다른 마스터 표와 다르다 — 이 표의 값은 Cin7 에 없어 사람이 채운다). check 목록은 다른 표와 같게 (cin7, manual)';
comment on column supplier_discount.cin7_id     is '공통 규약대로 두지만 ⚠️ 항상 null — Cin7 에 대응 개념이 없다(Cin7 Discount 칸 하나는 이 표와 다른 것)';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() 재사용(다시 만들지 않는다) ──
create trigger supplier_discount_set_updated_at before update on supplier_discount for each row execute function set_updated_at();

-- ── RLS · 권한 — 주소·연락처와 같다: auth_all + revoke anon · ⭐ DELETE 는 연다 · ⚠️ TRUNCATE 만 막는다 ──
alter table supplier_discount enable row level security;
create policy auth_all on supplier_discount for all to authenticated using (true) with check (true);
revoke all on supplier_discount from anon;
revoke truncate on supplier_discount from authenticated;
