-- ─────────────────────────────────────────────────────────────
-- IMS 리시빙 2-b — 확정 · 자동 분할 · 차이 큐 (Asung-IMS · 2026-09-18)
--   po_receipt_diff          ⭐ 차이 큐 표(신설) — over · short · (off_po 는 어휘만 · ⬜5)
--   po_receipt_diff_list     차이 큐 목록 뷰(security_invoker · 화면 다음 차수)
--   po_receipt_confirm       ⭐⭐ 확정 RPC — 작업 줄 → po_receipt_line · 차이 큐 · ⭐ 자동 분할(§11-c) · 묶음 confirmed
--   po_receipt_detail        다시 냄(시그니처 무변 · create or replace) — receipt_lines[] · diffs[] · received_here · split 정보
--
-- ⚠️ 사건(원장)은 내보내지 않는다 — 훅도 없다. 원장 이식 차수가 po_receipt_line 을 읽어 사건을 만든다(§11-j 합의 · 아래 이견 7).
-- 앞 차수: 20260918161537(표 셋) · 163552(RPC 여덟 · 규약·잠금·거부 문장 본보기) · 173042(unassign · 합 불변을 잰다) · 174428(split placed). 전부 무접촉(detail 만 다시 냄).
-- 정본: po-module §5(거래 표 예외 · 권한 규약 셋) · §11-b(closed = 입고 종료) · §11-c(갈라진다 · a 받은 쪽 · split_from_id 바로 앞) · §11-i(초과·부족·차이 큐) · §11-j(사건은 원장 이식 때) · §13-d
-- 지시서: ~/asung/prompts/ims-receiving-2b.md · 검토 이견 1~10 · ⬜1~9(회신)
--
-- ⭐⭐ 이견 1 — po_receipt_confirm 은 **security definer** 다(이 레포의 쓰기 RPC 중 처음).
--   확정은 po · po_line · po_discount 에 쓴다(번호 바꾸기 · 닫기 · b 문서 만들기). 그 표들의 RLS 는 ims_can_write('purchasing') 이다.
--   security invoker 로 두면 receiving 권한만 가진 사람의 update 는 **0행(조용히)** · insert 는 42501 — 「권한은 있는데 확정이 안 된다」가 된다.
--   purchasing 권한을 함께 요구하면 창고 담당이 확정을 못 한다. ⇒ 함수가 receiving 권한을 첫머리에서 묻고(ims_require_write · auth.uid() 는 definer 안에서도 JWT 를 읽는다), 그 뒤 쓰기는 정의자 권한으로.
--   보호: revoke public/anon · grant authenticated · search_path 고정 · 모든 update/delete 뒤 row_count(0행은 남이 바꾼 것 — 거부).
--
-- ⭐⭐ ⬜1 순서 ⓐ 입고 줄 → ⓑ 차이 → ⓒ 분할/닫기 → ⓓ 묶음 confirmed. ⓑ 가 ⓒ 앞인 이유: 차이의 기준(po_line.qty_ea − 이전 확정 합)은 갈라지기 **전** 문서의 수량이다 — ⓒ 가 qty_ea 를 줄인다. ⓓ 가 맨 뒤: 어디서 터져도 아무것도 안 남는다(한 트랜잭션).
-- ⭐ ⬜2 received_by = 그 줄을 **놓은 사람**(putaway_by) → 없으면 센 사람 → 없으면 확정한 사람. po_receipt_line.received_by 의 주석이 「풋어웨이까지 한 사람」이다. 확정한 사람은 po_receipt.confirmed_by 에 따로 남는다.
-- ⭐ ⬜3 분할 — 라인은 셋으로 가른다: 다 받은 라인(a 에 그대로) · 일부 받은 라인(a 는 받은 만큼으로 줄이고 b 에 나머지 줄 신설 · line_no 같게) · **하나도 안 온 라인은 행을 b 로 옮긴다**(update po_id — 지우지 않는다: 인보이스 줄이 이 라인을 가리킬 수 있고 「인보이스가 먼저 온다」가 실무다 · 한 인보이스가 a·b 에 걸치는 것은 §11-g 가 허용).
--        할인(po_discount)은 b 에 **복사**(2026-09-16 Caleb 이 PO-02001b 에 손으로 한 것과 같다). 비용 배분(po_charge_alloc.po_id)·크레딧 채번(credit_po_id)은 a 에 남는다(문서에 붙는 것 · §11-b). 「닫는다」= po.status 'closed' + closed_at(칸 실물 · closed_by 칸은 없다 · ⬜9).
--        ⚠️ 입력 단위 셋(entered_*)은 줄인 a 라인과 신설 b 라인에서 **비운다** — 「사람이 넣은 수 × 계수 = qty_ea」 검산이 더는 맞지 않는다(이견 5 · warnings entered_units_cleared).
-- ⭐ ⬜4 번호 — 실물 조회. base = 접미사를 뗀 번호 · 같은 base 의 접미사 최댓값 다음 두 글자(없으면 a·b · 'b' 였으면 c·d). 잠금 'po:'||base 로 형제 채번을 줄 세운다. z 를 넘으면 거부(두 글자 접미사는 만들지 않는다).
-- ⭐ ⬜5 표 이름 po_receipt_diff · unique (receipt_id, po_line_id)(한 확정에 라인당 한 건 · b 문서는 receipt 도 line 도 다르다) · off_po 는 CHECK 어휘에 넣고 (kind='off_po') = (po_line_id is null) 로 뜻을 같은 행 안에서 못 박는다 — 어휘는 거짓말하는 칸이 아니고, 나중 ALTER 는 마이그레이션 하나 값이다.
-- ⭐ ⬜6 확정 뒤 detail: 작업 줄은 그대로(지운 적 없는 사실) + receipt_lines[](po_receipt_line) + diffs[] + 라인마다 received_here(이 묶음의 입고 줄 합 — counted 와 다르면 신호) · header 에 po_closed_at · split_to.
-- ⭐ ⬜7 여러 건 닫기 RPC 는 이 차수에 없다(화면이 없다 · 안 도는 함수를 두지 않는다). 표에 resolved_by/at · note 가 있어 다음 차수가 RPC 하나로 연다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_receipt_diff — 차이 큐 ═══
-- 컷오버: 거래 ⇒ 지운다.
create table public.po_receipt_diff (
  id            uuid primary key default gen_random_uuid(),
  receipt_id    uuid not null references public.po_receipt (id) on delete no action,   -- 확정된 묶음(확정된 묶음은 지워지지 않는다 · FK 는 둘째 겹 · po_receipt_line 과 같은 판단)
  po_id         uuid not null references public.po (id) on delete no action,           -- 확정 순간의 문서(갈라진 뒤 a) — 번호가 바뀌어도 id 로 따라간다
  po_line_id    uuid references public.po_line (id) on delete no action,               -- off_po 면 null(어휘만 · 이 차수는 늘 채워진다)
  product_id    uuid not null references public.product (id) on delete no action,
  kind          text not null,                                                          -- over · short · off_po
  expected_qty  numeric not null,                                                       -- 기준(po_line.qty_ea − 이전 확정 입고 합 · 갈라지기 전 문서의 수량)
  received_qty  numeric not null,                                                       -- 이 묶음에서 센(= 입고 줄에 적힌) 수량
  note          text,
  resolved_by   uuid references public.ims_staff (id) on delete no action,              -- 사람이 닫는다(자동 조정 없음 · §11-i) · 닫는 RPC 는 화면 차수
  resolved_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,

  constraint po_receipt_diff_kind_ck      check (kind in ('over', 'short', 'off_po')),
  constraint po_receipt_diff_off_po_ck    check ((kind = 'off_po') = (po_line_id is null)),           -- 같은 행 안 · PO 밖이면 라인이 없고, 라인이 없으면 PO 밖이다
  constraint po_receipt_diff_qty_ck       check (expected_qty >= 0 and received_qty >= 0),
  constraint po_receipt_diff_resolved_ck  check ((resolved_at is null) = (resolved_by is null)),
  constraint po_receipt_diff_receipt_line_key unique (receipt_id, po_line_id)                         -- 한 확정에 라인당 한 건(⚠️ off_po 의 null 은 안 걸린다 — 부분 유니크 금지 · 그 규칙은 그때의 RPC 가)
);
comment on table  public.po_receipt_diff is '⑤ 입고 차이 큐(리시빙 2-b · 2026-09-18 · Caleb) — 확정하는 순간 라인마다 기준(PO 확정 수량 − 이전 확정 입고)과 센 수량이 다르면 한 건. over = 기준보다 많이 왔다(재고에 안 들어간 것이 건물에 있다 · 사건은 기준까지만 §11-i) · short = 적게 왔다(분할은 나머지를 옮길 뿐 「왜 덜 왔나」는 아무도 안 본다 — 나눠 보냄·결품·분실·오산을 사람이 가른다) · off_po = PO 에 없는 물건(어휘만 · 작업 줄 po_line_id 가 NOT NULL 인 동안은 나지 않는다). ⭐ 자동으로 닫지 않는다 — resolved_by/at 을 사람이(닫는 RPC·화면은 다음 차수). b 문서에서 더 받아도 앞의 건은 그대로 남는다. 「열린 것」은 뷰(po_receipt_diff_list)로 센다 — 부분 유니크 없음. 정본 po-module §11-i';
comment on column public.po_receipt_diff.expected_qty is '기준 — 갈라지기 전 문서의 po_line.qty_ea − 이전에 확정된 입고 합(이 묶음 제외). 확정 RPC 가 분할 전에 계산한다(⬜1 순서)';
comment on column public.po_receipt_diff.received_qty is '이 묶음에서 센 수량 = 작업 줄 합 = 입고 줄 합(초과분 포함 · 자르지 않는다)';
comment on column public.po_receipt_diff.kind is 'over | short | off_po(어휘만 · CHECK off_po_ck 가 po_line_id null 과 묶는다)';

create index po_receipt_diff_receipt_id_idx  on public.po_receipt_diff (receipt_id);
create index po_receipt_diff_po_id_idx       on public.po_receipt_diff (po_id);
create index po_receipt_diff_po_line_id_idx  on public.po_receipt_diff (po_line_id);
create index po_receipt_diff_product_id_idx  on public.po_receipt_diff (product_id);
create index po_receipt_diff_resolved_by_idx on public.po_receipt_diff (resolved_by);
create index po_receipt_diff_updated_by_idx  on public.po_receipt_diff (updated_by);
create index po_receipt_diff_resolved_at_idx on public.po_receipt_diff (resolved_at);                  -- 열린 것(resolved_at is null) 조회 · 일반 인덱스(부분 아님)

create trigger po_receipt_diff_touch before update on public.po_receipt_diff for each row execute function public.ims_touch();

alter table public.po_receipt_diff enable row level security;
create policy po_receipt_diff_select on public.po_receipt_diff for select to authenticated using (true);
create policy po_receipt_diff_insert on public.po_receipt_diff for insert to authenticated with check ((select public.ims_can_write('receiving')));
create policy po_receipt_diff_update on public.po_receipt_diff for update to authenticated using ((select public.ims_can_write('receiving'))) with check ((select public.ims_can_write('receiving')));
create policy po_receipt_diff_delete on public.po_receipt_diff for delete to authenticated using ((select public.ims_can_write('receiving')));
revoke all on public.po_receipt_diff from anon;
grant select, insert, update, delete on public.po_receipt_diff to authenticated;

-- ═══ ② po_receipt_diff_list — 큐 목록 뷰 (열린 것 = resolved_at is null · 화면은 .is("resolved_at","null")) ═══
create view public.po_receipt_diff_list
  with (security_invoker = true) as
select
  d.id, d.kind, d.expected_qty, d.received_qty, d.received_qty - d.expected_qty as diff_qty,
  d.receipt_id, r.receipt_number, r.received_on, r.warehouse_id, wh.name as warehouse_name,
  d.po_id, p.po_number, p.status as po_status, p.supplier_id, s.name as supplier_name,
  d.po_line_id, pl.line_no, d.product_id, pr.sku, pr.name as product_name,
  d.note, d.resolved_at, d.resolved_by, rb.name as resolved_by_name,
  d.created_at, d.updated_at
from public.po_receipt_diff d
join public.po_receipt r on r.id = d.receipt_id
join public.ref_warehouse wh on wh.id = r.warehouse_id
join public.po p on p.id = d.po_id
join public.supplier s on s.id = p.supplier_id
left join public.po_line pl on pl.id = d.po_line_id
join public.product pr on pr.id = d.product_id
left join public.ims_staff rb on rb.id = d.resolved_by;
comment on view public.po_receipt_diff_list is '⑤ 입고 차이 큐 목록(리시빙 2-b) — 종류 · 기준 · 센 수량 · 차이 · 묶음 · 발주 · 공급처 · 라인 · 제품 · 닫은 사람. 열린 것 = resolved_at is null(쿼리로 센다 · 부분 인덱스 없음). security_invoker. 2026-09-18';
revoke all on public.po_receipt_diff_list from anon;
grant select on public.po_receipt_diff_list to authenticated;

-- ═══ ③ po_receipt_confirm — ⭐⭐ 확정 ═══
-- POST /rest/v1/rpc/po_receipt_confirm  {"p_receipt_id":"<po_receipt.id>"}
-- → { receipt_id, receipt_number, status:'confirmed', confirmed_at, confirmed_by, receipt_lines_created,
--     po:{ id, number_before, number_after, status, closed_at },
--     split:{ remainder_po_id, remainder_number, lines_reduced, lines_moved, remainder_qty } | null,
--     diffs:{ over, short, rows:[{line_no, sku, kind, expected_qty, received_qty}] }, warnings[] }
create function public.po_receipt_confirm(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  x           record;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ② · definer 안에서도 auth.uid() 는 JWT 의 것
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_n then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_n, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 (분할 전 수량이 기준) — over · short · 안 센 라인은 short(received 0) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, case when x.counted > x.expected then 'over' else 'short' end, greatest(x.expected, 0), x.counted);
      if x.counted > x.expected then v_over := v_over + 1; else v_short := v_short + 1; end if;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', case when x.counted > x.expected then 'over' else 'short' end,
                                             'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 분할 또는 닫기 ═══
  if v_rem_total > 0 then
    -- ⬜4 번호 — 같은 base 의 접미사 최댓값 다음 두 글자(없으면 a·b)
    select max(substring(p.po_number from length(v_base) + 1)) into v_max
    from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
    if v_max is null then
      v_a_num := v_base || 'a'; v_b_num := v_base || 'b';
    else
      if length(v_max) <> 1 or v_max >= 'y' then
        raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
      end if;
      v_a_num := v_base || chr(ascii(v_max) + 1); v_b_num := v_base || chr(ascii(v_max) + 2);
    end if;

    -- b 문서 — 머리를 통째로 복사(칸이 늘어도 따라온다) · 번호 b · split_from_id = a · 상태 confirmed(같은 확정의 나머지 · confirmed_at/by 도 물려받는다) · 닫힘·취소 흔적 없음
    v_b_id := gen_random_uuid();
    insert into public.po
    select * from jsonb_populate_record(null::public.po,
      to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id,
                                           'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                           'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
    -- 할인 줄 복사(PO-02001b 선례 · Caleb 손 작업과 같다)
    insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
    select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;

    -- 라인 — 일부 받은 라인은 a 줄이고 b 신설 · 하나도 안 온 라인은 행을 b 로 옮긴다(인보이스 줄이 가리켜도 FK 가 따라간다)
    for x in
      select pl.*, 
             pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0)
               - coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as remaining
      from public.po_line pl where pl.po_id = v_po.id order by pl.line_no
    loop
      if x.remaining <= 0 then continue; end if;                                     -- 다 받았거나 초과 — a 에 그대로
      if x.qty_ea - x.remaining > 0 then
        -- 일부 받았다 — a 는 받은 만큼으로(입력 단위 셋은 비운다 · 이견 5)
        update public.po_line set qty_ea = x.qty_ea - x.remaining, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null
         where id = x.id and qty_ea = x.qty_ea;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        insert into public.po_line
        select * from jsonb_populate_record(null::public.po_line,
          to_jsonb(x) - 'remaining' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', x.remaining,
                                                          'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                          'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
        v_reduced := v_reduced + 1;
        if x.entered_unit_product_id is not null then v_cleared := array_append(v_cleared, x.line_no::text); end if;
      else
        -- 하나도 안 왔다 — 행을 통째로 b 로
        update public.po_line set po_id = v_b_id where id = x.id and po_id = v_po.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        v_moved := v_moved + 1;
      end if;
    end loop;

    -- a — 번호에 접미사 · 닫힘(입고 종료 · §11-b)
    update public.po set po_number = v_a_num, status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    if cardinality(v_cleared) > 0 then v_warn := array_append(v_warn, 'entered_units_cleared'); end if;
    v_warn := array_append(v_warn, 'po_split');
  else
    -- 다 받았다(또는 초과만) — 갈라지지 않고 닫힌다
    v_a_num := v_po.po_number;
    update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_closed');
  end if;
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); end if;
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', case when v_rem_total > 0 then jsonb_build_object('remainder_po_id', v_b_id, 'remainder_number', v_b_num, 'lines_reduced', v_reduced, 'lines_moved', v_moved, 'remainder_qty', v_rem_total) else null end,
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_receipt_confirm(uuid) is '⑤⭐⭐ 입고 확정(리시빙 2-b · 2026-09-18) — 「이 배로 온 것이 정해졌다」. 막는 것: 권한(receiving) · 이미 확정/취소 · PO 가 confirmed 아님(잠금 뒤 다시 본다) · 작업 줄 없음 · ⭐ 빈 없는 줄(라인·수량 + 빠져나갈 길을 문장에) · 빈이 다른 창고·비활성. 하는 일 ⓐ 작업 줄 → po_receipt_line 1:1(received_on 묶음 것 · received_by 놓은 사람→센 사람→확정한 사람 · 초과분 그대로) ⓑ 차이 큐 over/short(기준 = 분할 전 qty_ea − 이전 확정 합 · 안 센 라인도 short) ⓒ 라인 하나라도 남으면 자동 분할(§11-c · a 접미사+closed · b 신설 confirmed · split_from_id · 할인 복사 · 일부 라인은 줄이고 신설 · 0 라인은 행 이동) 아니면 닫기(closed·closed_at) ⓓ 묶음 confirmed. ⭐ security definer(po·po_line 은 purchasing RLS · 이견 1) · 잠금 po:<base> + 라인 키. ⚠️ 사건은 안 나간다 — 원장 이식 차수가 po_receipt_line 을 읽는다(§11-j). 정본 §11-i·c';
revoke all on function public.po_receipt_confirm(uuid) from public, anon;
grant execute on function public.po_receipt_confirm(uuid) to authenticated;

-- ═══ ④ po_receipt_detail — 다시 냄 (시그니처 무변 · receipt_lines[] · diffs[] · received_here · split 정보 · 그 밖은 163552 그대로) ═══
create or replace function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone,
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  where k.receipt_id = p_receipt_id
),
rl as (
  select l.*, b.name as bin, b.zone, pl.line_no,
         (select s.name from public.ims_staff s where s.id = l.received_by) as received_by_name
  from public.po_receipt_line l
  join public.po_line pl on pl.id = l.po_line_id
  left join public.ref_bin b on b.id = l.bin_id
  where l.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(y.qty_ea) from rl y where y.po_line_id = pl.id), 0) as received_here,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status, 'po_closed_at', p.closed_at,
      'po_split_from_number', sf.po_number,
      'po_split_to', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'po_number', c.po_number, 'status', c.status) order by c.po_number) from public.po c where c.split_from_id = p.id), '[]'::jsonb),
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before, 'received_here', l.received_here,
      'remaining', l.ordered - l.received_before,
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'over', (l.counted > l.ordered - l.received_before),
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name)
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'receipt_lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', y.id, 'po_line_id', y.po_line_id, 'line_no', y.line_no, 'qty_ea', y.qty_ea, 'bin_id', y.bin_id, 'bin', y.bin, 'zone', y.zone,
      'received_on', y.received_on, 'received_by', y.received_by, 'received_by_name', y.received_by_name, 'note', y.note, 'created_at', y.created_at)
      order by y.line_no, y.bin)
    from rl y), '[]'::jsonb),
  'diffs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'kind', d.kind, 'po_line_id', d.po_line_id, 'line_no', pl.line_no, 'sku', pr.sku,
      'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
      'note', d.note, 'resolved_at', d.resolved_at, 'resolved_by_name', rb.name)
      order by pl.line_no)
    from public.po_receipt_diff d
    left join public.po_line pl on pl.id = d.po_line_id
    join public.product pr on pr.id = d.product_id
    left join public.ims_staff rb on rb.id = d.resolved_by
    where d.receipt_id = p_receipt_id), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'received_here', coalesce(sum(l.received_here), 0),
      'over_lines', count(*) filter (where l.counted > l.ordered - l.received_before),
      'short_lines', count(*) filter (where l.counted < l.ordered - l.received_before),
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.ordered - l.received_before) then 'over_receipt' end,
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end
      ], null)) as v) t
  )
) end;
$$;
comment on function public.po_receipt_detail(uuid) is '⑤ 입고 상세 — ⭐ 계산의 정본(화면은 그린다 · 다시 짜지 않는다 · 리시빙 2-a → 2-b 다시 냄 2026-09-18). header(+ po_closed_at · po_split_from_number · po_split_to[]) · lines[] = PO 라인 전부 — ordered · invoiced(표시만) · received_before · ⭐ received_here(이 묶음의 입고 줄 합 · 확정 뒤 counted 와 같아야 한다 — 다르면 warnings receipt_lines_differ_from_work) · remaining · counted · allocated · unallocated · placed · over · work[](확정 뒤에도 그대로 · 지운 적 없는 사실) · ⭐ receipt_lines[](po_receipt_line · 확정된 사실) · ⭐ diffs[](차이 큐) · totals(+ received_here · open_diffs) · warnings[](po_not_confirmed 는 draft 일 때만 · open_diffs). 이름은 전부 별칭 서브쿼리. 없는 id → null. 정본 §11-i';
-- grant·revoke 는 163552 의 것이 유지된다(create or replace)

-- ─────────────────────────────────────────────────────────────
-- 화면(receiving.html · 대화 Claude)이 부르는 모양
--   확정      sb.rpc("po_receipt_confirm", { p_receipt_id })  → data.po.number_after · data.split(null | {remainder_number, remainder_qty}) · data.diffs.rows[] · warnings[] · 거부 문장은 그대로 띄운다(빠져나갈 길이 문장에 있다)
--   확정 뒤   sb.rpc("po_receipt_detail", { p_receipt_id })   → header.status 'confirmed' · receipt_lines[] · diffs[] · header.po_split_to[] (읽기 전용 화면)
--   차이 큐   sb.from("po_receipt_diff_list").select("*",{count:"exact"}).is("resolved_at", null).order("created_at",{ascending:false}).range(a,b)   (닫는 RPC·화면은 다음 차수)
-- ─────────────────────────────────────────────────────────────
