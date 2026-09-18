-- ─────────────────────────────────────────────────────────────
-- IMS 리시빙 1번 차수 — 표 셋 + Last bin 함수 (Asung-IMS · 2026-09-18)
--   po_receipt        입고 묶음(신설)  어느 PO · 어느 창고 · 받은 날 · 번호(RCV-…) · 상태(draft → confirmed · cancelled)
--   po_receipt_work   작업 줄(신설)    라인별 센 수량 · 빈은 나중(nullable) · 놓았는가 · 수량 축·풋어웨이 축 「누가·언제」
--   po_receipt_line   확정된 사실(기존) receipt_id 칸 하나만 더한다 — 나머지 무접촉
--   po_receipt_next_number()  RCV- 채번(시퀀스 · po_next_number 선례 그대로)
--   ims_last_bin(product_ids[], warehouse_id) → jsonb   ⭐ 「그 제품이 그 창고에서 마지막으로 놓인 빈」 — 속을 갈아 끼울 함수 하나
--
-- ⚠️ 이 차수는 표와 함수 하나까지다. 만들기·확정 RPC · 자동 분할(§11-c) · 차이 큐 · PO 밖(off-PO) 승인 · 화면은 다음 차수(그래서 이 표들에 넣는 길은 아직 PostgREST 뿐이다).
-- 앞 차수: 20260918133858(updated_by + ims_touch · 표 29) — 새 표는 그 규약 위에 선다(트리거 <표>_touch · set_updated_at 아님).
-- 정본: docs/design/po-module.md §5(거래 표 규약 · 권한 규약 셋) · §11-b(확정의 뜻) · §11-c(분할) · §11-i(입고 — ⚠️ 「줄 표 하나」를 「표 셋 · 두 단계」로 고쳐야 한다 · 말만) · §11-j(사건) · §13-a·d
-- 조사: 회신 ims-receiving-survey(2026-09-18) — WMS receiver.html 2,151행 전수 · 칸 81 · 1번 철칙(관행을 잃지 않는다)
-- 지시서: ~/asung/prompts/ims-receiving-1.md · 검토 이견 1~12 · ⬜1~9(회신)
--
-- ⭐⭐ 왜 표가 셋인가 — 관행이 두 단계다 (Caleb 2026-09-18 · WMS receiver.html 검수 → 풋어웨이 · Cin7 Stock received / Put away)
--   ① 검수    물량이 맞게 왔는지 센다 — **빈은 아직 모른다**
--   ② 풋어웨이 그 물건을 빈에 갖다 놓는다 — 사람도 시점도 다르다 · 여러 사람이 나눠 넣는다
--   po_receipt_line 은 bin_id NOT NULL(§11-i 「빈이 정해진 뒤 입고가 확정된다」)이라 ①단계의 줄을 담을 수 없다 ⇒ 빈 없이 살 수 있는 **작업 줄** 표가 필요하다.
--   확정하면 작업 줄에서 po_receipt_line 이 만들어진다(다음 차수 RPC) — 작업 줄은 「받는 중」, po_receipt_line 은 「받았다」(원장 사건의 근거 · §11-j).
--
-- ⭐⭐ ⬜1 빈 배정은 (가) — 작업 줄에 bin_id 하나(nullable) · 한 줄 = 한 빈 · 나누려면 작업 줄을 쪼갠다
--   (가)를 고른 이유 ① 확정이 1:1 이다 — 작업 줄 하나 → po_receipt_line 하나(bin·qty 그대로 복사) · 표 셋으로 끝난다
--                  ② WMS 관행(putaway_bin 한 칸 · Change bin · Place all · 줄마다 Placed)이 그대로 건너온다(1번 철칙) · 나누기(§11-i 실측 600 → A010101 400 + A010102 200)는 「줄을 쪼갠다」로 **더해진다**(WMS 가 못 하던 것)
--                  ③ 풋어웨이 중에도 「어느 빈에 몇 개」가 적힌다 — (다)는 여러 사람·여러 날에 걸친 풋어웨이의 기록이 사라지고 WMS 관행(putaway_bin 을 놓을 때 적는다)을 잃는다
--   (나) 배정 줄 표를 버린 이유 — 표가 넷이 되고 「센 수량 = 배정 합」 검산이 하나 더 생긴다. (가)에서도 센 수량은 「그 라인 작업 줄의 합」으로 읽으면 같은 값이다(쪼개도 합은 안 바뀐다 — 쪼개는 RPC 가 지킨다).
--   ⚠️ 대가: 라인당 줄이 하나가 아니다 — 「이 라인을 몇 개 세었나」는 sum(qty_ea) 이다. 화면·RPC 가 합으로 읽는다(po_line.received_qty 를 안 두고 합으로 내는 §11-i 와 같은 결).
--
-- ⭐ ⬜2 자연키 — 작업 줄은 (receipt_id, po_line_id, bin_id) 가 뜻의 열쇠다. ⚠️ bin_id 가 null 인 줄(검수 단계)은 unique 가 못 잡는다(null 은 서로 다르다) —
--   부분 유니크 인덱스는 금지(규칙 29)이므로 **DB 는 (receipt_id, po_line_id, bin_id) 유니크만 걸고**, 「빈 없는 줄은 라인당 하나」는 만들기·쪼개기 RPC 가 지킨다(다음 차수 · 「PO 당 draft 하나」와 같은 자리).
--   po_line_id 는 **이 차수에서 NOT NULL** — PO 밖(off-PO) 줄은 다음 차수(승인 칸 · product_id · po_receipt_line.po_line_id nullable · 차이 큐가 한 묶음이라 반쪽만 세우면 채울 길이 없는 칸이 남는다). 그때 `drop not null` + product_id 한 줄이다. 관행은 잃지 않는다 — 미룬다(⬜2 · 회신).
--
-- ⭐ ⬜3 po_receipt → po_receipt_line 은 **no action** — 확정된 사실이고 원장 사건의 근거다. confirmed_at 게이트가 삭제를 막지만, 게이트는 RPC 의 것이고 FK 는 표의 것이다 — 둘째 겹. 초안 묶음에는 po_receipt_line 이 애초에 없어(확정 때 생긴다) cascade 가 도울 일도 없다.
--    po_receipt → po_receipt_work 는 cascade(문서 → 소유 줄 · §5).
-- ⭐ ⬜4 번호 RCV- + 다섯 자리 · 시퀀스 po_receipt_number_seq(1 부터 · RCV-00001) · po_receipt_next_number() — po_next_number 선례를 그대로(authenticated 에 USAGE · 롤백된 번호는 빈다 · 허용).
-- ⭐ ⬜5 created_by 를 둔다(po·po_invoice·po_charge 선례) — 기본값 없음 · **만들기 RPC 가 auth.uid() → ims_staff.id 로 채운다**(다음 차수 · po_create 선례). 지금 PostgREST 로 넣으면 null 이다(화면이 주게 하지 않는다 — anon key 공개).
-- ⭐ ⬜6 ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid) → jsonb 하나 — 한 제품이면 배열 하나짜리. 두 함수를 두면 규칙이 두 곳이 된다. 「가장 최근」 = received_on desc, created_at desc(물건이 들어온 날이 축 · 같은 날은 늦게 만든 줄). security invoker(읽는 표 셋이 전부 select 열림) · stable · jsonb 단일 값이라 1,000행 캡 밖.
-- ⭐ ⬜7 po_receipt_line.receipt_id 는 **nullable** 로 붙인다 — 09-16 검증 데이터(PO-02001a 입고 줄 · §13-b)가 이 표에 있다(정본 「검증 데이터는 지우지 않는다」). 실측 행 수는 Caleb SQL(회신). NOT NULL 은 그 행들을 어떻게 할지(백필 묶음 · 삭제) 정한 뒤 다음 차수에서.
-- ⭐ ⬜9 더한 것(1번 철칙 · 조사 §3 칸 대조표 ①②): po_receipt.warehouse_id(빈은 창고의 것 · Last bin 의 축) · 작업 줄의 축 칸 넷(counted_by/at · putaway_by/at — WMS last_qty_*·last_putaway_* · 축 분리 근거 receipt 67) · count_method(scanned|manual — WMS verification_method).
--    안 더한 것: 기대치 스냅샷(WMS expected_base) — IMS 는 po_line.qty_ea − 확정된 입고 합으로 **계산**한다(§2 「PO 확정 수량 하나로 판정」) · 인보이스 합은 표시만(화면이 po_invoice 에서).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 채번 — RCV-00001 부터 (po_number_seq · po_next_number 선례 그대로) ═══
create sequence if not exists public.po_receipt_number_seq start with 1 increment by 1;

create function public.po_receipt_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'RCV-' || lpad(nextval('public.po_receipt_number_seq')::text, 5, '0');
$$;
comment on function public.po_receipt_next_number() is '입고 묶음 번호 채번 — RCV- + 다섯 자리(시퀀스 po_receipt_number_seq · 1 부터). 동시 생성에서 겹치지 않고 PostgREST insert 만으로 붙는다 · 롤백된 번호는 빈다(허용 · §11-c 와 같은 판단). 선례 po_next_number(20260916144201). 2026-09-18';

revoke all on sequence public.po_receipt_number_seq from public, anon;
grant usage, select on sequence public.po_receipt_number_seq to authenticated;      -- 기본값은 insert 하는 역할로 실행된다
revoke all on function public.po_receipt_next_number() from public, anon;
grant execute on function public.po_receipt_next_number() to authenticated;

-- ═══ ② po_receipt — 입고 묶음 ═══
-- 컷오버: 거래 ⇒ 지운다.
create table public.po_receipt (
  id              uuid primary key default gen_random_uuid(),
  receipt_number  text not null unique default public.po_receipt_next_number(),        -- RCV-00001 …
  po_id           uuid not null references public.po (id) on delete no action,          -- ⭐ 어느 발주(갈라진 뒤의 문서 · PO-12345a) · ⚠️ 「PO 당 draft 하나」는 unique 가 아니라 만들기 RPC 가 본다(부분 유니크 금지 · 규칙 29)
  warehouse_id    uuid not null references public.ref_warehouse (id) on delete no action, -- ⭐ 받는 창고 — 작업 줄의 빈은 이 창고의 것 · Last bin 의 축 · 만들 때 po.ship_to_warehouse_id 를 복사(null 이면 사람이 고른다)
  received_on     date not null default current_date,                                    -- ⭐ 한 배가 온 날 = 원장 occurred_on 의 근거(§11-i) · 확정 때 po_receipt_line.received_on 으로 복사
  status          text not null default 'draft',                                          -- draft → confirmed · cancelled 옆으로 · 삭제 게이트의 축은 status 가 아니라 confirmed_at(20260917100000)
  created_by      uuid references public.ims_staff (id) on delete no action,              -- 만든 사람 · 만들기 RPC 가 auth.uid() 로 채운다(다음 차수 · 기본값 없음 · 화면이 주지 않는다)
  confirmed_by    uuid references public.ims_staff (id) on delete no action,
  confirmed_at    timestamptz,
  cancelled_by    uuid references public.ims_staff (id) on delete no action,
  cancelled_at    timestamptz,
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id) on delete no action,              -- ims_touch 가 채운다(20260918133858 규약)

  constraint po_receipt_status_ck check (status in ('draft', 'confirmed', 'cancelled'))
);

comment on table  public.po_receipt is '⑤ 입고 묶음(리시빙 1번 차수 · 2026-09-18) — 한 발주(po_id)에 물건이 한 번 도착한 것. 아래 작업 줄(po_receipt_work)이 검수·풋어웨이 진행을 담고, 확정하면 po_receipt_line(확정된 사실)이 만들어진다(다음 차수 RPC). ⭐ 관행이 두 단계(검수 → 풋어웨이)라 표가 셋이다. 상태 draft → confirmed(= 입고 확정 · 원장 사건이 나가는 순간 §11-j) · cancelled. ⚠️ 「PO 당 열린 묶음 하나」는 만들기 RPC 가 지킨다(부분 유니크 금지). 정본 po-module §11-i(⬜ 표 셋으로 갱신) · §11-c · §11-j';
comment on column public.po_receipt.receipt_number is 'RCV-00001 부터(시퀀스 · 롤백된 번호는 빈다 · 허용) · 우리 번호일 뿐(§11-c 와 같은 판단)';
comment on column public.po_receipt.po_id          is '어느 발주 — 갈라진 뒤의 문서(PO-12345a). 확정 때 남은 수량으로 다음 문서가 자동으로 갈라진다(§11-c · 다음 차수)';
comment on column public.po_receipt.warehouse_id   is '⭐ 받는 창고 → ref_warehouse. 작업 줄의 bin_id 는 이 창고의 ref_bin 이어야 한다(RPC 가 본다) · ims_last_bin 의 둘째 인자. 만들 때 po.ship_to_warehouse_id 를 복사하고 null 이면 사람이 고른다';
comment on column public.po_receipt.received_on    is '⭐ 물건이 들어온 날 = 원장 occurred_on 의 근거(§11-i). 확정 때 po_receipt_line.received_on 으로 복사된다 — 원장은 묶음까지 조인하지 않아도 되게(4-d)';
comment on column public.po_receipt.status         is 'draft(받는 중 · 작업 줄을 고친다) → confirmed(입고 확정 · po_receipt_line 생성 · 사건 · 분할) · cancelled. 삭제는 confirmed_at 이 null 일 때만(po_doc_delete 축 · 다음 차수에 ''receipt'' 가지)';

create index po_receipt_po_id_idx        on public.po_receipt (po_id);
create index po_receipt_warehouse_id_idx on public.po_receipt (warehouse_id);
create index po_receipt_created_by_idx   on public.po_receipt (created_by);
create index po_receipt_confirmed_by_idx on public.po_receipt (confirmed_by);
create index po_receipt_cancelled_by_idx on public.po_receipt (cancelled_by);
create index po_receipt_updated_by_idx   on public.po_receipt (updated_by);
create index po_receipt_status_idx       on public.po_receipt (status);                    -- 열린 묶음 목록(status = 'draft')

create trigger po_receipt_touch before update on public.po_receipt for each row execute function public.ims_touch();

-- ═══ ③ po_receipt_work — 작업 줄 (⭐ 이 차수의 새 개념 · 검수 수량 · 빈은 나중 · 한 줄 = 한 빈) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table public.po_receipt_work (
  id              uuid primary key default gen_random_uuid(),
  receipt_id      uuid not null references public.po_receipt (id) on delete cascade,     -- ⭐ 문서 → 소유 줄 · CASCADE(§5) — 초안을 지우면 작업 줄도 간다
  po_line_id      uuid not null references public.po_line (id) on delete no action,      -- ⚠️ 이 차수는 NOT NULL — PO 밖(off-PO) 줄은 다음 차수(승인·product_id·차이 큐와 한 묶음)에서 drop not null
  qty_ea          numeric not null,                                                       -- ⭐ 검수에서 센 수량(낱개) · 줄을 쪼개면 라인의 센 수량 = 같은 po_line_id 줄들의 합
  bin_id          uuid references public.ref_bin (id) on delete no action,               -- ⭐ 풋어웨이에서 정해진 빈 · null = 아직 검수 단계 · (가) 한 줄 = 한 빈 · 나누려면 줄을 쪼갠다(RPC)
  putaway_done    boolean not null default false,                                         -- ⭐ 놓았는가 · 줄마다(여러 사람이 나눠 넣는다 · WMS putaway_done)
  count_method    text,                                                                   -- 'scanned' | 'manual' | null — WMS verification_method
  counted_by      uuid references public.ims_staff (id) on delete no action,              -- ⭐ 수량 축 「누가·언제 세었나」 — WMS last_qty_by/at (축 분리 근거 receipt 67 · Place all 이 덮지 못하게 풋어웨이 축과 갈라 둔다)
  counted_at      timestamptz,
  putaway_by      uuid references public.ims_staff (id) on delete no action,              -- ⭐ 풋어웨이 축 「누가·언제 놓았나/빈을 정했나」 — WMS last_putaway_by/at
  putaway_at      timestamptz,
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id) on delete no action,              -- ims_touch — 마지막으로 만진 사람(축 무관 · 덮어쓰기 알림의 재료 · 축 칸을 갈음하지 않는다)

  constraint po_receipt_work_qty_ea_ck        check (qty_ea > 0),
  constraint po_receipt_work_count_method_ck  check (count_method is null or count_method in ('scanned', 'manual')),
  constraint po_receipt_work_putaway_bin_ck   check (not putaway_done or bin_id is not null),          -- 놓았다면 빈이 있어야 한다(같은 행 안 · CHECK 가능)
  constraint po_receipt_work_receipt_line_bin_key unique (receipt_id, po_line_id, bin_id)              -- ⭐ 같은 묶음·같은 라인·같은 빈은 한 줄 · ⚠️ bin null 줄은 여기 안 걸린다(null 은 서로 다르다) — 「빈 없는 줄은 라인당 하나」는 RPC 가 지킨다 · 부분 유니크 금지(규칙 29)
);

comment on table  public.po_receipt_work is '⑤ 입고 작업 줄(리시빙 1번 차수 · 2026-09-18) — 받는 중의 상태. 검수: 라인별 센 수량(qty_ea · bin 없음) → 풋어웨이: bin_id 를 정하고 putaway_done 을 켠다. ⭐ (가) 한 줄 = 한 빈 — 한 라인을 두 빈에 나누면 줄을 쪼갠다(§11-i 실측 600 → 400 + 200 · WMS 는 못 하던 것) · 라인의 센 수량 = 같은 po_line_id 줄들의 합. 확정하면 줄마다 po_receipt_line 하나가 된다(1:1 · 다음 차수 RPC). 기대치는 칸이 아니라 계산(po_line.qty_ea − 확정된 입고 합 · §2 「PO 확정 수량 하나로 판정」). 축 칸 넷(counted_*·putaway_*)은 WMS 축 분리의 승계 — updated_by 로 갈음하지 않는다(Place all 이 덮는다). 정본 po-module §11-i(⬜ 갱신)';
comment on column public.po_receipt_work.po_line_id   is '어느 발주 라인. ⚠️ 이 차수는 NOT NULL — PO 에 없는 물건(off-PO · §11-i 「매니저 승인 전까지 막는다」)은 다음 차수에서 nullable + product_id + 승인 칸으로 연다';
comment on column public.po_receipt_work.qty_ea       is '⭐ 검수에서 센 낱개 수량 · > 0(센 것이 없으면 줄이 없다 — 「아직 안 센 라인」은 po_line 에서 그린다). 초과 판정·차이 큐는 확정 RPC(다음 차수)가 po_line.qty_ea 와 비교한다';
comment on column public.po_receipt_work.bin_id       is '⭐ 풋어웨이에서 정해진 빈 → ref_bin(그 묶음의 창고 것이어야 한다 · RPC 가 본다) · null = 검수 단계 · WMS putaway_bin 한 칸의 승계(text → uuid) · Last bin 제안은 ims_last_bin 으로';
comment on column public.po_receipt_work.putaway_done is '⭐ 놓았는가 — 줄마다(WMS Placed · Place all) · 켜려면 bin_id 가 있어야 한다(CHECK)';
comment on column public.po_receipt_work.count_method is '어떻게 세었나 — scanned(바코드) | manual(손으로 · 스테퍼) · WMS verification_method 의 승계';
comment on column public.po_receipt_work.counted_by   is '⭐ 수량 축 — 마지막으로 수량을 만진 사람(WMS last_qty_by). 풋어웨이 축과 따로 두는 이유: Place all 한 번이 전 줄을 덮으면 「누가 세었나」가 사라진다(WMS receipt 67 · 축 분리)';
comment on column public.po_receipt_work.putaway_by   is '⭐ 풋어웨이 축 — 마지막으로 빈을 정했거나 놓은 사람(WMS last_putaway_by)';

create index po_receipt_work_receipt_id_idx on public.po_receipt_work (receipt_id);
create index po_receipt_work_po_line_id_idx on public.po_receipt_work (po_line_id);
create index po_receipt_work_bin_id_idx     on public.po_receipt_work (bin_id);
create index po_receipt_work_counted_by_idx on public.po_receipt_work (counted_by);
create index po_receipt_work_putaway_by_idx on public.po_receipt_work (putaway_by);
create index po_receipt_work_updated_by_idx on public.po_receipt_work (updated_by);

create trigger po_receipt_work_touch before update on public.po_receipt_work for each row execute function public.ims_touch();

-- ═══ ④ po_receipt_line — receipt_id 하나만 더한다 (나머지 무접촉) ═══
-- ⚠️ nullable(⬜7) — 09-16 검증 데이터(PO-02001a 입고 줄 · §13-b)가 이 표에 있어 NOT NULL 을 지금 붙일 수 없다. 백필 묶음을 만들지·지울지 정한 뒤 다음 차수에서 set not null.
-- ⚠️ received_on·received_by 는 묶음과 겹쳐 보여도 남긴다 — §11-i 가 received_on 을 원장 occurred_on 으로 못 박았다(원장이 묶음까지 조인하지 않는다).
--    어긋남 방지(4-d ⬜ · 트리거 없이): 이 표에 쓰는 길은 **확정 RPC 하나**로 좁히고(PostgREST 직접 insert 는 화면이 안 쓴다 · 정책은 열려 있으나 관례), RPC 가 묶음의 received_on·warehouse 를 복사한다. 검사는 아침 점검 SQL(묶음과 다른 received_on 이 있는가)로 — 회신 §6 ⑦.
alter table public.po_receipt_line
  add column if not exists receipt_id uuid references public.po_receipt (id) on delete no action;   -- ⭐ no action(⬜3) — 확정된 사실 · 원장 사건의 근거 · 묶음을 지워도 사실은 안 사라진다

create index if not exists po_receipt_line_receipt_id_idx on public.po_receipt_line (receipt_id);

comment on column public.po_receipt_line.receipt_id is '⭐ 어느 입고 묶음(po_receipt)에서 확정됐나(2026-09-18 · 리시빙 1번). nullable — 09-16 검증 데이터가 묶음 없이 있다(⬜ 백필 뒤 not null). 확정 RPC(다음 차수)가 작업 줄 → 이 표로 옮기며 채운다 · on delete no action(사실은 묶음 삭제로 사라지지 않는다)';

-- ═══ ⑤ 정책 — 표 둘 · 넷씩 · select 열림 · 쓰기는 ims_can_write('receiving') (po_receipt_line 선례 20260917235000 그대로) ═══
alter table public.po_receipt      enable row level security;
alter table public.po_receipt_work enable row level security;

create policy po_receipt_select on public.po_receipt for select to authenticated using (true);
create policy po_receipt_insert on public.po_receipt for insert to authenticated with check ((select public.ims_can_write('receiving')));
create policy po_receipt_update on public.po_receipt for update to authenticated using ((select public.ims_can_write('receiving'))) with check ((select public.ims_can_write('receiving')));
create policy po_receipt_delete on public.po_receipt for delete to authenticated using ((select public.ims_can_write('receiving')));

create policy po_receipt_work_select on public.po_receipt_work for select to authenticated using (true);
create policy po_receipt_work_insert on public.po_receipt_work for insert to authenticated with check ((select public.ims_can_write('receiving')));
create policy po_receipt_work_update on public.po_receipt_work for update to authenticated using ((select public.ims_can_write('receiving'))) with check ((select public.ims_can_write('receiving')));
create policy po_receipt_work_delete on public.po_receipt_work for delete to authenticated using ((select public.ims_can_write('receiving')));

revoke all on public.po_receipt      from anon;
revoke all on public.po_receipt_work from anon;
grant select, insert, update, delete on public.po_receipt      to authenticated;
grant select, insert, update, delete on public.po_receipt_work to authenticated;

-- ═══ ⑥ ims_last_bin(p_product_ids, p_warehouse_id) — ⭐ 속을 갈아 끼울 함수 하나 ═══
-- 지금 속: po_receipt_line 에서 그 제품(po_line.product_id · 낱개)·그 창고(ref_bin.warehouse_id)의 가장 최근 것 — received_on desc, created_at desc(물건이 들어온 날이 축 · 같은 날은 늦게 만든 줄).
-- 나중 속: 원장이 오면 출고·조정·이동까지 아는 「지금 재고가 있는 자리 → 없으면 마지막으로 있던 자리」로 갈아 끼운다 — 부르는 쪽(화면·RPC)은 안 고친다.
-- ⚠️ 화면이 po_receipt_line 을 직접 조회해 라스트 빈을 만들지 마라 · wms_sku_bins(Cin7 스냅샷)는 읽지 않는다(원칙 1) · 초기에는 거의 비어 있다(시드하지 않는다 — 컷오버 때 채워진다).
-- 반환: { "<product_id>": { "bin_id", "bin", "zone", "received_on" }, … } — 없는 제품은 키가 없다(→ 화면은 null) · 빈 입력이면 {} · jsonb 단일 값이라 1,000행 캡 밖(wms_warehouse_bins 선례).
-- 한 제품만 물으려면 array[<id>] 로 부른다 — 함수를 둘 두면 규칙이 두 곳이 된다(⬜6).
create function public.ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(x.product_id::text,
           jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin_name, 'zone', x.zone, 'received_on', x.received_on)), '{}'::jsonb)
  from (
    select distinct on (pl.product_id)
           pl.product_id, rl.bin_id, b.name as bin_name, b.zone, rl.received_on
    from public.po_receipt_line rl
    join public.po_line pl on pl.id = rl.po_line_id
    join public.ref_bin  b  on b.id  = rl.bin_id
    where pl.product_id = any(coalesce(p_product_ids, '{}'::uuid[]))
      and b.warehouse_id = p_warehouse_id
    order by pl.product_id, rl.received_on desc, rl.created_at desc
  ) x;
$$;
comment on function public.ims_last_bin(uuid[], uuid) is '⭐ 「그 제품이 그 창고에서 마지막으로 놓인 빈」 — 리시빙 풋어웨이의 Last bin 제안(2026-09-18). 지금 속 = po_receipt_line(product 는 po_line 을 타고 · warehouse 는 ref_bin 을 탄다) · received_on desc, created_at desc. 나중 속 = 원장(출고·조정·이동까지) — 부르는 쪽은 안 고친다. 제품 배열 → jsonb 맵(없는 제품은 키 없음 · 빈 입력 {}) · 단일 값이라 캡 밖 · security invoker(읽는 표 셋이 select 열림). ⚠️ wms_sku_bins 를 읽지 않는다(원칙 1) · 시드하지 않는다. 정본 po-module §11-i(⬜ 갱신)';

revoke all on function public.ims_last_bin(uuid[], uuid) from public, anon;
grant execute on function public.ims_last_bin(uuid[], uuid) to authenticated;
