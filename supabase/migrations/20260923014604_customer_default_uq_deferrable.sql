-- SO 모듈 마이그레이션 ③ — 「기본 하나」 유니크 둘을 DEFERRABLE INITIALLY IMMEDIATE 로 · 손님 적재 규칙 판정 ⑩~⑫ 를 주석에 (2026-09-22 토론토 밤 · 파일 시각 UTC 20260923014604)
--
-- 목표: 제약 2 다시 만들기(이름 그대로) · comment on 5(칸 3 · 표 2) · ⭐ 행 0 · 표·칸 추가 없음. 적재 GAS(ImsLoadCustomer.gs)는 다음 차수 — 이 판정들을 따른다.
-- 선행: 20260922201223_customer.sql(표 셋 · 제약 정의 145·185행 · 주석 154·195·112행) · 20260923012022_customer_contact_job_title.sql(표 주석 30·33행) — 둘 다 테스트 DB 적용됨 · ⚠️ 고치지 않는다.
-- 정본: docs/design/so-module.md §9-i(판정 ⑩~⑫ · 근거 · 버린 안) · §9-e(재적재 방식 · 부모 먼저 ✅) · §9-f(③ 파일 줄) · 5-b 653행 · 5-c 670행 「→ §9-i(deferrable)」 포인터.
--       이 파일과 정본이 어긋나면 정본이 이긴다. 지시서 ~/asung/prompts/so-mig-3-default-deferrable.md · 검토 이견 1~7 은 Caleb 판정(2026-09-22 밤) 전부 채택.
--
-- ═══ 판정 ⑪ — 왜 deferrable 인가 ═══
--   두 번째 적재부터, 손님이 Cin7 에서 기본을 A→B 로 옮기면 한 upsert 문장 안에서 A(true→false)·B(false→true)가 함께 바뀐다.
--   즉시 검사 유니크는 줄마다 검사하므로 B 줄이 A 줄보다 먼저 처리되면 23505 — 줄 순서에 따라 성공·실패가 갈린다.
--   deferrable initially immediate = 문장 끝에 한 번 검사. 끝났을 때 기본이 둘이면 여전히 거부 — 규칙은 그대로, 검사 때만 바뀐다.
--   ⚠️ initially deferred 가 아니다 — 트랜잭션 끝까지 미루면 화면의 실수가 커밋 직전까지 숨는다. 문장 끝이면 충분하다.
--   ⚠️ 한 문장 안의 교대만 구한다 — 옛 기본이 Cin7 에서 지워져 upsert 문장에 없으면 그 줄을 먼저 내려야 한다(판정 ⑩ 순서 · 2′ · 검토 이견 1).
--   arbiter: on conflict (cin7_id) 의 기준은 plain 유니크 cin7_id 그대로 — deferrable 유니크는 arbiter 가 못 된다(Postgres 규칙 · §4 시험 1 이 실측).
--
-- ⚠️ begin/commit 없음 — 적용은 psql -v ON_ERROR_STOP=1 -1 -f(한 트랜잭션) + supabase migration repair --status applied 20260923014604 (po-module §13-f).
-- 행 0 이라 제약을 다시 만드는 비용은 없다. 이름은 그대로(검증 쿼리·주석·정본이 이 이름을 가리킨다).

-- ═══ ① 제약 둘 — drop 뒤 같은 이름으로 deferrable initially immediate ═══
alter table public.customer_address
  drop constraint customer_address_default_uq,
  add  constraint customer_address_default_uq unique (default_customer_id, type) deferrable initially immediate;

alter table public.customer_contact
  drop constraint customer_contact_default_uq,
  add  constraint customer_contact_default_uq unique (default_customer_id) deferrable initially immediate;

-- ═══ ② 주석 — 앞 문장 전문(마지막으로 쓴 파일에서 옮김) + 뒤에 판정 · 뺀 문장 없음 ═══

-- customer_address.default_customer_id (앞 문장: 20260922201223 154행) — 판정 ⑪
comment on column public.customer_address.default_customer_id is '생성 칸 — is_default_for_type 이면 customer_id · 아니면 null · 전체 유니크 (default_customer_id, type) 가 「손님·type 당 기본 하나」를 막는다(기본이 아닌 줄은 null 이라 안 부딪힌다 · WHERE 없는 전체 유니크라 규칙 29 에 걸리지 않는다 · PostgREST on_conflict 도 받는다 · 5-b · 5-f 와 같은 장치) · ⚠️ type 이 null 인 기본 줄은 (customer, null) 이라 서로 안 부딪힌다 — 기본 줄에는 type 을 채우는 것이 적재·화면의 일 · ⭐ 검사 시점(판정 ⑪ · 마이그레이션 ③ 2026-09-22): 유니크 customer_address_default_uq 는 deferrable initially immediate — 줄마다가 아니라 문장 끝에 한 번 검사한다 · 손님이 Cin7 에서 기본을 A→B 로 옮기면 한 upsert 안에서 A(true→false)·B(false→true)가 함께 바뀌는데 즉시 검사면 B 가 먼저 처리될 때 23505 — 줄 순서에 따라 성공·실패가 갈렸다 · 규칙은 그대로(문장 끝에 기본이 둘이면 여전히 거부) · ⚠️ initially deferred 가 아니다(트랜잭션 끝까지 미루면 화면 실수가 커밋 직전까지 숨는다 · 문장 끝이면 충분) · 적재 짝: 한 손님의 주소는 같은 요청(= PostgREST 요청 하나 = 한 문장)에 모아 보낸다 · 버린 안: false 줄을 먼저 보내는 줄 순서 맞추기(요청 안 순서에 기대야 해서 조용히 깨진다) · ⚠️ deferrable 은 한 문장 안의 교대만 구한다 — 옛 기본이 Cin7 에서 지워져 upsert 문장에 없으면 먼저 내려야 한다(판정 ⑩ 순서 · 2′) · on_conflict 의 기준(arbiter) cin7_id 유니크는 plain 그대로(deferrable 유니크는 arbiter 가 못 된다)';

-- customer_contact.default_customer_id (앞 문장: 20260922201223 195행) — 판정 ⑪
comment on column public.customer_contact.default_customer_id is '생성 칸 — is_default 이면 customer_id · 아니면 null · 전체 유니크 customer_contact_default_uq 가 「손님당 기본 연락처 하나」를 막는다(5-c · 규칙 29 회피 장치) · ⭐ 검사 시점(판정 ⑪ · 마이그레이션 ③ 2026-09-22): 유니크 customer_contact_default_uq 는 deferrable initially immediate — 줄마다가 아니라 문장 끝에 한 번 검사한다 · 손님이 Cin7 에서 기본을 A→B 로 옮기면 한 upsert 안에서 A(true→false)·B(false→true)가 함께 바뀌는데 즉시 검사면 B 가 먼저 처리될 때 23505 — 줄 순서에 따라 성공·실패가 갈렸다 · 규칙은 그대로(문장 끝에 기본이 둘이면 여전히 거부) · ⚠️ initially deferred 가 아니다(트랜잭션 끝까지 미루면 화면 실수가 커밋 직전까지 숨는다 · 문장 끝이면 충분) · 적재 짝: 한 손님의 연락처는 같은 요청(= PostgREST 요청 하나 = 한 문장)에 모아 보낸다 · 버린 안: false 줄을 먼저 보내는 줄 순서 맞추기(요청 안 순서에 기대야 해서 조용히 깨진다) · ⚠️ deferrable 은 한 문장 안의 교대만 구한다 — 옛 기본이 Cin7 에서 지워져 upsert 문장에 없으면 먼저 내려야 한다(판정 ⑩ 순서 · 2′) · on_conflict 의 기준(arbiter) cin7_id 유니크는 plain 그대로(deferrable 유니크는 arbiter 가 못 된다)';

-- customer_address (표 · 앞 문장: 20260923012022 33행) — 판정 ⑩ 재적재 방식
comment on table  public.customer_address is 'SO 모듈 손님 주소록(Cin7 customer.Addresses[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ Cin7 하위 ID 유무는 적재 첫 회에 · 없으면 손님 단위로 지우고 다시 넣는다 · 그래서 DELETE 가 열려 있다 → ✅ Cin7 Address.ID 있음 · 19,001 전부 고유(2026-09-22 프로브) · 적재 열쇠 cin7_id 확정 · DELETE 는 여전히 열어 둔다 — Cin7 에서 지운 주소가 실제로 생겼다(DALIANA MOMBRUN 중복 배송지 · 9-g) · ⬜ 지울지 is_active=false 로 둘지는 적재 차수 §9-e) · 관계 표 규약 7칸(name 없음) · TRUNCATE 막음 · 오더의 bill_to_*·ship_to_* 는 여기서 칸칸이 복사된다(5-d · 주소록을 FK 로 가리키지 않는다) · 손님당 주소 0개 18 · 1개 712 · 2개 8,286 · 3개 168 · 4+ 284 · 정본 docs/design/so-module.md §5-b · §9 · 2026-09-22 신설 · ✅ 재적재 방식 확정(판정 ⑩ · 마이그레이션 ③ 2026-09-22): 지우지 않는다 — PO 「한 규칙」(po-module §3-f) 그대로 · 순서 ① Cin7 전량 수집 ② source=cin7 이고 이번 회차에 안 들어온 행을 is_active=false 로 내린다 + ⭐ 2′ 기본 표시도 함께 푼다(is_default_for_type=false — 비활성 행이 기본을 쥐면 새 기본이 customer_address_default_uq 에 막힌다) ③ upsert(on_conflict=cin7_id · is_active:true 실어 보낸다 · 내린 행이 다시 나타나면 저절로 되살아난다) ④ 내린 수·되살린 수를 적재 보고에 · ⚠️ 내리기가 upsert 앞이다 — 옛 기본이 Cin7 에서 지워진 줄은 upsert 문장에 없어 deferrable(판정 ⑪)로도 못 구한다(DALIANA MOMBRUN 모양 · 9-i) · source=manual 은 어디에도 안 걸린다 · DELETE 는 규약대로 열어 두되 적재는 쓰지 않는다 · 적재가 절대 보내지 않는 칸: id · note · updated_by · created_at · updated_at · label · customer_id 는 Cin7 손님 ID → 우리 customer.id 로 바꿔 보낸다(판정 ⑫ 1단계 뒤 조회)';

-- customer_contact (표 · 앞 문장: 20260923012022 30행) — 판정 ⑩ 재적재 방식
comment on table  public.customer_contact is 'SO 모듈 손님 연락처(Cin7 customer.Contacts[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ 하위 ID 유무는 적재 첫 회에 → ✅ Cin7 Contact.ID 있음 · 9,912 전부 고유(2026-09-22 프로브) · 적재 열쇠 cin7_id 확정) · 관계 표 규약 7칸 · DELETE 열림 · TRUNCATE 막음 · ⚠️ is_default · include_in_email · marketing_consent 는 받아 두기만 — 어느 칸이 메일 수신처를 정하는지는 메일 절에서 실물로(판정 ④ · 5-c ⬜) · 적재 첫 페이지에서 Contacts 키 목록을 그대로 센다(JobTitle 이 오면 그때 더한다 → ✅ 왔다 · 값 288 · job_title 을 더했다 · 마이그레이션 ② 2026-09-22 · 판정 ⑨) · 손님당 연락처 0개 12 · 1개 9,191 · 2개 176 · 3개 57 · 4개 13 · 5+ 19 · Default 둘 이상 0 · 기본 없음 2 · ⬜ 재적재 방식(이번 회차에 안 온 cin7_id 를 지울지 is_active=false 로 둘지)은 적재 차수(§9-e) · 정본 docs/design/so-module.md §5-c · §9 · 2026-09-22 신설 · ✅ 재적재 방식 확정(판정 ⑩ · 마이그레이션 ③ 2026-09-22): 지우지 않는다 — PO 「한 규칙」(po-module §3-f) 그대로 · 순서 ① Cin7 전량 수집 ② source=cin7 이고 이번 회차에 안 들어온 행을 is_active=false 로 내린다 + ⭐ 2′ 기본 표시도 함께 푼다(is_default=false — 비활성 행이 기본을 쥐면 새 기본이 customer_contact_default_uq 에 막힌다) ③ upsert(on_conflict=cin7_id · is_active:true 실어 보낸다 · 내린 행이 다시 나타나면 저절로 되살아난다) ④ 내린 수·되살린 수를 적재 보고에 · ⚠️ 내리기가 upsert 앞이다 — 옛 기본이 Cin7 에서 지워진 줄은 upsert 문장에 없어 deferrable(판정 ⑪)로도 못 구한다(DALIANA MOMBRUN 모양 · 9-i) · source=manual 은 어디에도 안 걸린다 · DELETE 는 규약대로 열어 두되 적재는 쓰지 않는다 · 적재가 절대 보내지 않는 칸: id · note · updated_by · created_at · updated_at · customer_id 는 Cin7 손님 ID → 우리 customer.id 로 바꿔 보낸다(판정 ⑫ 1단계 뒤 조회)';

-- customer.parent_id (앞 문장: 20260922201223 112행) — 판정 ⑫ 두 단계
comment on column public.customer.parent_id                   is 'Cin7 CustomerParentID → customer(id) · 자기 참조 · nullable · on delete no action · 인덱스 customer_parent_idx · ⭐ 연결 축만 — 상속 없음(§2-m 정정 · 자식 설정은 각자) · ⚠️ 적재는 부모를 먼저 넣어야 이어진다(적재 차수의 일) · ✅ 적재는 두 단계(판정 ⑫ · 마이그레이션 ③ 2026-09-22): 1단계 손님 전량 upsert — ⚠️⚠️ parent_id 칸을 아예 보내지 않는다(「보내지 않는다」 ≠ 「null 로 보낸다」 · PostgREST upsert 는 보낸 칸을 덮으므로 null 을 실으면 재적재마다 2단계가 채운 부모를 지운다) · 2단계 부모가 있는 손님(13명 · 9-g)에게만 CustomerParentID(GUID) → customer.id 를 조회해 parent_id 를 채운다(부모는 1단계로 이미 있다) · 재적재: Cin7 에서 부모가 없어진 손님(source=cin7 · parent_id not null · 이번 회차 부모 목록에 없음)은 parent_id 를 null 로 비운다 · 근거: 자기 참조 FK 는 줄마다 즉시 검사 — 자식이 부모보다 먼저 들어가면 거부 · 순서를 따지는 것보다 두 단계가 단순하다(깊이 2+ 0) · 같은 이유로 적재가 절대 보내지 않는 칸: id · default_ship_to_customer_id · default_bill_to_customer_id · note · updated_by · created_at · updated_at(칼럼 주석의 「재적재가 덮지 않는다」는 이것으로 지켜진다 · source 는 cin7 을 실어도 된다)';
