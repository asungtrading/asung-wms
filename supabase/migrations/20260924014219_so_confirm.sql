-- SO 쓰기 ②a — 확정과 할당: 칸 · 문지기 짝 넷 · 가용 · 분할(속) · 할당 엔진(속) · 형제 조회 둘 · so_confirm · so_unconfirm (2026-09-24 UTC · 파일 시각 UTC · 토론토 2026-09-23 저녁)
-- 지시서 ~/asung/prompts/so-write-2-confirm.md · 판정 Caleb 2026-09-23(R1~R10 · 회신 이견 1~14 중 2 고침 · 추가 판정 「오더 나누기」는 ②b) · 정본 docs/design/so-module.md §14(신설 · 말만)
-- 바탕: 20260923133042(so · so_line · so_reserve · open_line_id 유니크) · 20260923134840(so_merge_reason_ck 새 식) · 20260923182231(so_status_guard 짝 0 · so_require_draft 는 191030:46) ·
--       20260923232500(창구 규약 · ims_today) · 20260919151601(ims_inv_balance 뷰 · IN_TRANSIT 창고 행 is_active=false) · 20260918020000(ims_role_rank · ims_can_write) · 20260919175712(po_family_* 재귀 모양) ·
--       20260924001820(po_receipt_confirm 채번 자리 :278~370 — base · advisory lock · 다음 글자)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ 무엇을 하나(⬜8 — 둘로 나눈 앞쪽 · so_hold · so_reallocate · so_cancel · so_change_location · so_backorder_proceed · 오더 나누기 · so_detail·so_delete 재발행은 ②b)
--    ① 칸  so_split_reason_ck 에 preorder · manual(R2 · 추가 판정) · so.closed_note(R4 이유 필수 · 이견 5) · so.unconfirmed_at/by(R9 기록) · so_line.split_from_line_id(이견 6 · 되돌리기의 정확한 합침)
--    ② so_status_guard 재발행 — 허락 짝 넷 draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled(⬜3 · 이견 7) · 그 밖 한 글자 그대로
--    ③ so_require_role(p_min) — 역할 순위 문(ims_role_rank · R3~R5·R9) · 속 함수 · ims_require_write('sales') 와 둘 다(⬜2 · sales 열쇠 없는 manager 는 막힌다 — 맞는 선)
--    ④ so_available(product, location) → EA — 가용 창구 하나(5-f · ims_inv_balance 모든 bin 합 − 열린 allocated × pack_factor · 세트 줄은 낱개 재고를 본다)
--    ⑤ so_split(속) — 접미어 채번(base · advisory lock · 다음 글자 · x 까지) · 머리 통째 복사 · draft insert → 같은 트랜잭션 confirmed(문지기 예외 없음 · 이견 4) · 줄 옮기기(통째 = 행 이동 · 일부 = 원래 줄 줄이고 새 줄 + split_from_line_id)
--    ⑥ so_allocate_run(속) — 엔진 하나(이견 9): 잠금 순서 → 줄마다 floor(가용_EA/pack_factor) → 무리 셋(할당·백오더·프리오더) → 가장 앞선 무리가 원래 번호를 지키고 나머지만 형제(이견 1 · 빈 문서 없음) · p_hold 면 전부 hold · 나누지 않음(이견 2 고침)
--    ⑦ so_family_members · so_family_lines — 재귀 형제 조회(5-d · po_family_* 모양 + closed_reason · merged_into_id · split_reason · open_qty · 예약 kind) · merged·cancelled 형제는 합계에서 뺀다(목록에는 낸다)
--    ⑧ so_confirm(so_id · p_preorder_line_ids · p_hold · p_commit) — manager 이상 · draft · warehouse 채널만(④ 에서 pos·counter) · R6 막는 조건 · 미리 보기 p_commit=false
--    ⑨ so_unconfirm(so_id) — supervisor 이상 · 확정 때 태어난 형제만(created_at = 원래 confirmed_at · 손대지 않았다 = 「같은 시각」 ⬜7) · 도로 합치고 · 재고 전부 풀고 · draft
--
-- ⭐ 규칙(정본 §14 로 옮긴다)
--    R1 확정할 때 모자란 몫은 늘 나눈다(묻지 않는다) · 원래 오더는 늘 전부 할당된 줄만(또는 통째로 hold · 통째로 백오더/프리오더 — 이견 1) · 백오더·프리오더 형제는 할당 없음(kind backorder·preorder 줄) · 물건이 들어와도 자동으로 잡지 않는다
--    R2 프리오더 줄은 따로 뗀다(split_reason preorder) · 처음부터 잡지 않는다 · 한 번의 확정으로 셋까지(원래 · a 백오더 · b 프리오더)
--    R3 보류는 늘 오더 전체(Caleb 「보류는 특정 제품에만 한한 경우는 없어」) — p_hold 확정은 재고를 잡지 않고 나누지도 않는다 · 풀기·다시 잡기는 ②b(so_hold · so_reallocate)
--    R5 확정 = manager 이상 · R9 되돌리기 = supervisor 이상 · R6 막는 조건 넷(가격 없는 줄 · 창고 없음/비활성 · 비활성 제품 · 비활성 손님) + 줄 없음 · pos/counter 채널 · 경고(티어·통화·reprice_suggested·deal_ended)
--    단위 — ims_inv_balance.qty 는 낱개(EA) · bin 별 행 · so_reserve.qty_allocated 는 판매 단위 ⇒ 가용은 EA · 줄에 잡는 수량 = floor(가용_EA / pack_factor) · 0 이면 통째로 백오더 · 음수 잔고는 0 으로 본다(이견 10)
--    잠금 — (창고, 낱개 제품) 순 pg_advisory_xact_lock 'so_avail:' · 줄마다 'so_reserve:' · 분할 채번 'so:'||base (교착 없음 · ⬜4)
--    번호 — 원래 번호는 남고 갈라져 나온 것만 소문자 한 글자 · b 를 또 나눠도 c · 최대 24(a~x · y 이상 거부 · PO 문장) · 글자는 다시 쓰지 않는다(cancelled·merged 도 센다)
--    되돌리기 — 형제 문서는 지우지 않는다(cancelled · closed_reason merged · merged_into_id · closed_note) · 통째로 갔던 줄은 행이 돌아오고(so_id) · 일부만 갔던 줄은 원래 줄에 수량을 도로 더한다(형제 줄 행은 이력으로 남는다 — 합계에서는 merged 형제를 뺀다)
-- ⚠️ 다시 만들지 않은 것 — so_require_draft · so_current_staff · ims_require_write · ims_role_rank · ims_today · so_line_quote · so_detail(②b 재발행) · so_delete(②b 문장 한 줄) · ims_inv_balance(뷰)
-- ⚠️ 시퀀스 무접촉(so_create 를 부르지 않는다) · seed 없음 · 검증 ~/asung/prompts/so-write-2a-verify.sql

-- ═══ ① 칸 ═══
-- 1-a so.split_reason — preorder(R2) · manual(추가 판정 · 오더 나누기 ②b) 더함 · CHECK 교체 선례 20260923134840(drop + add) · 'warehouse' 는 이번에 만드는 길이 없어 비어 있다(이견 8)
alter table public.so drop constraint if exists so_split_reason_ck;
alter table public.so add  constraint so_split_reason_ck check (split_reason is null or split_reason in ('stock_short','warehouse','preorder','manual'));
comment on constraint so_split_reason_ck on public.so is
  '갈라진 계기 넷(2026-09-24) — stock_short(재고 부족 · 확정·창고 바꾸기·백오더 진행이 낳는 백오더 형제) · preorder(프리오더 줄을 따로 뗀 형제 · R2) · manual(사람이 누른 오더 나누기 · ②b) · warehouse(한 오더를 두 창고에서 — ⚠️ 아직 만드는 길이 없다 · 비어 있다) · null = 갈라져 나온 문서가 아니다(so_split_pair_ck)';

-- 1-b so.closed_note — 닫은 이유 문장(R4 취소 이유 필수 · 되돌리기 합침은 자동 문장) · closed_reason 은 어휘 넷 그대로
alter table public.so add column if not exists closed_note text;
comment on column public.so.closed_note is
  '닫은 이유 문장(2026-09-24 · R4) — closed_reason 은 어휘(expired·superseded·voided·merged)고 이것은 사람의 말 · 취소(voided)는 필수(②b so_cancel) · 되돌리기 합침(merged)은 자동 「Unconfirmed with SO-…」 · 오더 메모(comments)와 다른 칸';

-- 1-c so.unconfirmed_at · unconfirmed_by — 확정 되돌리기 기록(R9 「누가 언제 되돌렸나」) · 다시 확정하면 confirmed_at/by 가 새로 찍히고 이 둘은 남는다(마지막 되돌리기)
alter table public.so
  add column if not exists unconfirmed_at timestamptz,
  add column if not exists unconfirmed_by uuid references public.ims_staff (id) on delete no action;
create index if not exists so_unconfirmed_by_idx on public.so (unconfirmed_by);
comment on column public.so.unconfirmed_at is '⭐ 확정 되돌리기(so_unconfirm · R9 · supervisor 이상) 시각 — 마지막 것 · 되돌리면 confirmed_at/by 는 비고 status 는 draft · 다시 확정하면 confirmed_at/by 가 새로 찍히고 이 칸은 남는다';
comment on column public.so.unconfirmed_by is '되돌린 사람 → ims_staff(id) · 인덱스 so_unconfirmed_by_idx';

-- 1-d so_line.split_from_line_id — 일부만 갈라진 줄의 계보(이견 6) · 통째로 옮긴 줄은 행이 그대로 가므로 null · 되돌리기가 이 칸으로 수량을 도로 더한다
alter table public.so_line add column if not exists split_from_line_id uuid references public.so_line (id) on delete no action;
create index if not exists so_line_split_from_line_idx on public.so_line (split_from_line_id);
comment on column public.so_line.split_from_line_id is
  '⭐ 일부만 갈라진 줄의 원래 줄 → so_line(id)(2026-09-24 · 이견 6) — 확정·창고 바꾸기·백오더 진행·오더 나누기가 한 줄의 일부를 형제로 옮길 때 원래 줄은 수량을 줄이고 형제에 새 줄이 서며 여기가 원래 줄을 가리킨다 · 통째로 옮긴 줄은 행 자체가 형제로 가므로 null · so_unconfirm 이 이 칸으로 수량을 도로 더한다(없으면 행을 되돌린다) · so_family_lines fragments 에 보인다';

-- ═══ ② so_status_guard 재발행 — 허락 짝 넷(⬜3) · 마지막 정의 20260923182231:92 · 바뀐 줄: create → create or replace · v_ok 한 줄 · 주석 한 줄 ═══
create or replace function public.so_status_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_ok boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft' then
      raise exception 'A new order must start as draft (got %) — nothing was saved', new.status;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;                                   -- status 그대로 — 머리 고치기 · 줄 수 반영 등은 지나간다
  end if;

  -- 허락 짝 목록 — ② 확정·할당(2026-09-24 · ⬜3): draft→confirmed(확정 · 형제 탄생) · confirmed→draft(되돌리기 R9) · confirmed→cancelled(취소 R4 · 되돌리기의 형제 합침) · draft→cancelled(이력 있는 draft · 이견 7)
  --   ③ 출고 · ④ POS·counter · ⑤ Release to WMS · WMS 사건(내려가는 짝 포함 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'));

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  'so BEFORE INSERT OR UPDATE — 자기 행만 보는 전이 문지기(6-g′ · 12-b 판정 6). insert 는 draft 만 · update 로 status 가 바뀌면 허락 짝 목록(v_ok)에 없으면 거부 — 2026-09-24 ②a 짝 넷: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled(③~⑤ 가 더한다). status 그대로인 update 는 통과. ⚠️ 소유자·definer 창구도 지난다 · 형제는 draft 로 태어나 같은 트랜잭션에서 confirmed 로 간다(예외 없음 · 이견 4)';

-- ═══ ③ so_require_role — 역할 순위 문(속 함수 · ims_require_write 뒤에 둘째 문) ═══
--   ims_can_write('sales') 는 admin·supervisor 를 perms 와 무관하게 통과시키고 manager 는 perms 에 sales 가 있어야 한다(20260918020000:105) ⇒ 둘 다 묻는다(⬜2)
create function public.so_require_role(p_min text, p_verb text default 'saved') returns void
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  select s.role into v_role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_role is null then
    raise exception 'You are not registered as active staff — nothing was %', p_verb;
  end if;
  if coalesce(public.ims_role_rank(v_role), 0) < coalesce(public.ims_role_rank(p_min), 99) then
    raise exception 'This needs a % or above (you are %) — nothing was %', p_min, v_role, p_verb;
  end if;
end;
$$;
comment on function public.so_require_role(text, text) is 'SO 창구 속 함수(②a · ⬜2) — 호출자의 ims_staff.role 순위가 p_min 이상인지(ims_role_rank · manager 2 · supervisor 3 · admin 4) · 아니면 거부 「This needs a manager or above — nothing was saved」 · ims_require_write(sales) 다음 둘째 문으로 쓴다(sales 열쇠 없는 manager 는 첫 문에서 막힌다 — 맞는 선) · R3~R5 manager · R9 supervisor';
revoke all on function public.so_require_role(text, text) from public, anon, authenticated;

-- ═══ ④ so_available — 가용 재고 창구 하나(5-f · 2-d) · EA ═══
--   창고 잔고 = ims_inv_balance 의 그 창고(warehouse_id) · 그 낱개 제품(product_id) 모든 bin 합(bin '' 포함 · IN_TRANSIT 은 다른 warehouse 행이라 자연 제외 · 잔고 0·음수 그대로)
--   − Σ(열린 allocated 예약 qty_allocated × 그 줄 pack_factor) — 그 창고의 오더 · 같은 낱개 제품(세트 줄은 낱개로 환산)
--   세트 제품(parent_product_id 있음)을 물으면 낱개의 잔고를 본다(세일즈 오더에 세트는 나오지 않지만 나와도 틀리지 않게) · 늘 한 값(없으면 0 − 할당)
create function public.so_available(p_product_id uuid, p_location_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with pid as (
    select coalesce(p.parent_product_id, p.id) as stock_pid from public.product p where p.id = p_product_id
  ),
  bal as (
    select coalesce(sum(b.qty), 0) as qty
    from public.ims_inv_balance b, pid
    where b.product_id = pid.stock_pid and b.warehouse_id = p_location_id
  ),
  alloc as (
    select coalesce(sum(r.qty_allocated * l.pack_factor), 0) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id, pid
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and coalesce(p.parent_product_id, p.id) = pid.stock_pid
  )
  select bal.qty - alloc.ea from bal, alloc;
$$;
comment on function public.so_available(uuid, uuid) is
  '⭐ 가용 재고 창구 하나(5-f · 2-d · ②a) — 낱개(EA) · 창고 잔고(ims_inv_balance · 그 창고의 모든 bin 합 · 세트를 물으면 낱개 잔고) − Σ 열린 allocated 예약(qty_allocated × pack_factor · 그 창고 오더) · preorder·hold·backorder 줄은 빼지 않는다(재고를 잡지 않은 기록) · 음수·0 그대로 낸다(엔진이 0 으로 본다) · 화면은 다시 짜지 않는다 · ⚠️ 창고 조인은 ims_inv_balance 가 ref_warehouse.name 텍스트로 잇는다(원장 정본 ⬜)';
revoke all on function public.so_available(uuid, uuid) from public, anon;
grant execute on function public.so_available(uuid, uuid) to authenticated;

-- ═══ ⑤ so_split — 분할(속 함수) · 접미어 채번 · 머리 복사 · 줄 옮기기 ═══
--   p_moves = [{"line_id": …, "qty": …}] · qty >= 줄 수량이면 행이 통째로 옮겨 가고(id 그대로) · 작으면 원래 줄을 줄이고 형제에 새 줄(split_from_line_id = 원래 줄)
--   p_target_status 'confirmed' = 모체가 확정 중에 낳았다(확정 흔적을 물려받는다 · draft insert → confirmed update · 문지기 짝) · 'draft' = 초안 나누기(②b)
--   운임(so_charge)은 원래에 남는다 · 오더 전체 할인·reprice_suggested_at 은 복사(⬜6) · 예약(so_reserve)은 건드리지 않는다(부르는 쪽이 건다)
create function public.so_split(p_so_id uuid, p_reason text, p_moves jsonb, p_target_status text, p_staff uuid) returns public.so
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_new    public.so%rowtype;
  v_base   text;
  v_max    text;
  v_num    text;
  v_id     uuid := gen_random_uuid();
  m        record;
  l        public.so_line%rowtype;
  v_next   int := 0;
  v_n      int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_reason not in ('stock_short','warehouse','preorder','manual') then
    raise exception 'split_reason % is not one of stock_short, warehouse, preorder, manual — nothing was saved', p_reason;
  end if;
  if p_target_status not in ('draft','confirmed') then
    raise exception 'A split order can only be born draft or confirmed — nothing was saved';
  end if;
  if coalesce(jsonb_array_length(p_moves), 0) = 0 then
    raise exception 'Nothing to split off — nothing was saved';
  end if;

  -- 번호 — base(접미어를 뗀 것)로 잠그고 그 base 의 접미어 최댓값 다음 글자 하나(5-d · PO 20260924001820:278~370 과 같은 자리 · cancelled·merged 도 센다 — 글자는 다시 쓰지 않는다)
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('so:' || v_base));
  select max(substring(s.so_number from length(v_base) + 1)) into v_max
  from public.so s where s.so_number ~ ('^' || v_base || '[a-z]$');
  if v_max is null then
    v_num := v_base || 'a';
  elsif v_max >= 'x' then
    raise exception 'Order % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_so.so_number, v_max;
  else
    v_num := v_base || chr(ascii(v_max) + 1);
  end if;

  -- 머리 통째 복사(칸이 늘어도 따라온다) — draft 로 태어난다(문지기 · 이견 4) · 닫힘·창고·출하·되돌리기 흔적은 비운다 · 확정 흔적은 target 이 confirmed 일 때 아래 update 에서 물려받는다
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft',
      'split_from_id', v_so.id, 'split_reason', p_reason,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null,
      'created_at', now(), 'created_by', p_staff, 'updated_at', now(), 'updated_by', p_staff));

  -- 줄 옮기기(모체 line_no 순 · 형제 line_no 1부터)
  for m in
    select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty
    from jsonb_array_elements(p_moves) e
    join public.so_line x on x.id = (e->>'line_id')::uuid
    order by x.line_no
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Split quantity for line % must be positive — nothing was saved', l.line_no; end if;
    v_next := v_next + 1;
    if m.qty >= l.qty_ordered then
      update public.so_line set so_id = v_id, line_no = v_next, updated_by = p_staff where id = l.id;                       -- 통째 — 행이 간다(id 그대로)
    else
      update public.so_line set qty_ordered = qty_ordered - m.qty, updated_by = p_staff where id = l.id;                    -- 일부 — 원래 줄을 줄이고
      insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped,
                                  list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff);                 -- 형제에 새 줄 · 계보
    end if;
  end loop;

  if p_target_status = 'confirmed' then
    update public.so set status = 'confirmed', confirmed_at = v_so.confirmed_at, confirmed_by = v_so.confirmed_by, updated_by = p_staff
    where id = v_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not saved — nothing was saved', v_num; end if;
  end if;

  select * into v_new from public.so where id = v_id;
  return v_new;
end;
$$;
comment on function public.so_split(uuid, text, jsonb, text, uuid) is
  'SO 창구 속 함수(②a · 5-d 번호 규칙) — 모체에서 줄(전부 또는 일부)을 떼어 형제 문서를 만든다. 번호 = base 의 접미어 최댓값 다음 소문자 한 글자(a~x · y 이상 거부 · advisory lock so:base · cancelled·merged 도 센다) · 머리 통째 복사(운임 제외 · 오더 전체 할인 복사) · draft 로 태어나 target 이 confirmed 면 같은 트랜잭션에서 confirmed(확정 흔적은 모체 것 · 문지기 짝) · 통째 줄은 행이 가고(id 그대로) 일부 줄은 원래를 줄이고 새 줄(split_from_line_id) · 예약은 건드리지 않는다(부르는 쪽) · 권한·상태 확인은 부르는 창구가 했다';
revoke all on function public.so_split(uuid, text, jsonb, text, uuid) from public, anon, authenticated;

-- ═══ ⑥ so_allocate_run — 할당 엔진(속 함수 · 이견 9) · 확정 · (②b) 재할당 · 창고 바꾸기 · 백오더 진행이 함께 쓴다 ═══
--   대상 줄 = 그 오더의 열린 예약이 없는 줄 전부(부르는 쪽이 먼저 풀어 둔다) · p_hold 면 전부 kind hold(나누지 않는다 · R3)
--   무리 셋: A 할당(전부 또는 일부) · B 백오더(0 또는 나머지) · P 프리오더(p_preorder_line_ids) · 가장 앞선 무리(A > B > P)가 원래 번호를 지키고 나머지만 형제(이견 1 · 빈 문서 없음) · 형제 순서 B(a) → P(b)
--   가용은 잠금 뒤에 읽고(EA · 음수는 0) 같은 낱개 제품이 여러 줄이면 앞 줄이 먼저 잡는다 · 잡는 수량 = floor(가용_EA / pack_factor) · 예약 allocated_by 는 system(null) · preorder·hold 는 사람(p_staff)
--   p_confirm true 면 원래를 draft→confirmed 로 올린다(so_confirm) · false 면 이미 confirmed 인 오더(②b) · p_commit false 면 계획만 돌려준다(미리 보기 · 잠금은 트랜잭션 끝까지)
create function public.so_allocate_run(p_so_id uuid, p_location_id uuid, p_preorder_line_ids uuid[], p_hold boolean, p_confirm boolean, p_commit boolean, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so      public.so%rowtype;
  l         record;
  v_key     text;
  v_rem     numeric;
  v_alloc   numeric;
  v_avail   jsonb := '{}'::jsonb;                    -- 낱개 제품 → 남은 가용(EA) · 이번 실행 안에서만
  v_plan    jsonb := '[]'::jsonb;
  a_ids     uuid[] := '{}';  a_qty numeric[] := '{}';       -- A 할당(줄 · 잡는 수량)
  b_moves   jsonb := '[]'::jsonb;  b_n int := 0;             -- B 백오더 [{line_id, qty}]
  p_moves   jsonb := '[]'::jsonb;  p_n int := 0;             -- P 프리오더
  v_keep    text;
  v_sib_b   public.so%rowtype;  v_sib_p public.so%rowtype;
  v_sibs    jsonb := '[]'::jsonb;
  v_n       int;
  i         int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_location_id is null then raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number; end if;

  -- 잠금 — (창고, 낱개 제품) 오름차순 · 줄마다(5-f) · 두 매니저가 같은 제품을 반대 순서로 잡을 수 없다(⬜4)
  for l in
    select x.id, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by 2, 1
  loop
    perform pg_advisory_xact_lock(hashtext('so_avail:' || p_location_id::text || ':' || l.stock_pid::text));
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || l.id::text));
  end loop;

  -- 줄마다 판정(모체 line_no 순 — 같은 제품이 두 줄이면 앞 줄이 먼저 잡는다)
  for l in
    select x.*, coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_line x join public.product p on p.id = x.product_id
    where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null)
    order by x.line_no
  loop
    if p_hold then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'hold', 'allocated', 0, 'backordered', 0, 'preorder', 0);
      a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, l.qty_ordered);
      continue;
    end if;
    if l.id = any(coalesce(p_preorder_line_ids, '{}'::uuid[])) then
      v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                             'kind', 'preorder', 'allocated', 0, 'backordered', 0, 'preorder', l.qty_ordered);
      p_moves := p_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered);  p_n := p_n + 1;
      continue;
    end if;
    v_key := l.stock_pid::text;
    if not (v_avail ? v_key) then
      v_avail := v_avail || jsonb_build_object(v_key, greatest(public.so_available(l.stock_pid, p_location_id), 0));
    end if;
    v_rem   := (v_avail->>v_key)::numeric;
    v_alloc := least(l.qty_ordered, floor(v_rem / l.pack_factor));
    v_avail := v_avail || jsonb_build_object(v_key, v_rem - v_alloc * l.pack_factor);
    v_plan := v_plan || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'pack_factor', l.pack_factor,
                                           'available_ea_before', v_rem,
                                           'kind', case when v_alloc = l.qty_ordered then 'allocated' when v_alloc = 0 then 'backorder' else 'partial' end,
                                           'allocated', v_alloc, 'backordered', l.qty_ordered - v_alloc, 'preorder', 0);
    if v_alloc > 0 then a_ids := array_append(a_ids, l.id);  a_qty := array_append(a_qty, v_alloc); end if;
    if v_alloc < l.qty_ordered then
      b_moves := b_moves || jsonb_build_object('line_id', l.id, 'qty', l.qty_ordered - v_alloc);  b_n := b_n + 1;
    end if;
  end loop;

  if coalesce(array_length(a_ids, 1), 0) = 0 and b_n = 0 and p_n = 0 then
    raise exception 'Order % has no lines to allocate — nothing was saved', v_so.so_number;
  end if;

  -- 어느 무리가 원래 번호를 지키나(이견 1) — hold 는 전부 원래(나누지 않는다)
  v_keep := case when p_hold then 'hold'
                 when coalesce(array_length(a_ids, 1), 0) > 0 then 'allocated'
                 when b_n > 0 then 'backorder'
                 else 'preorder' end;

  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'keeps', v_keep, 'lines', v_plan,
      'siblings', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
         select jsonb_build_object('split_reason', 'stock_short', 'lines', b_n) as x where b_n > 0 and v_keep <> 'backorder' and not p_hold
         union all
         select jsonb_build_object('split_reason', 'preorder', 'lines', p_n) where p_n > 0 and v_keep <> 'preorder' and not p_hold) z));
  end if;

  -- 확정(so_confirm) — 원래를 draft → confirmed 로 먼저 올린다(형제가 확정 흔적을 물려받는다)
  if p_confirm then
    update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = p_staff, updated_by = p_staff
    where id = p_so_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  end if;

  -- 형제 — 원래가 지키지 않는 무리만(빈 문서 없음) · B 가 앞 글자
  if b_n > 0 and v_keep <> 'backorder' then
    v_sib_b := public.so_split(p_so_id, 'stock_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib_b.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_b.id, 'so_number', v_sib_b.so_number, 'split_reason', 'stock_short', 'lines', b_n);
  end if;
  if p_n > 0 and v_keep <> 'preorder' then
    v_sib_p := public.so_split(p_so_id, 'preorder', p_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = v_sib_p.id;
    v_sibs := v_sibs || jsonb_build_object('so_id', v_sib_p.id, 'so_number', v_sib_p.so_number, 'split_reason', 'preorder', 'lines', p_n);
  end if;

  -- 원래에 남은 줄의 예약
  if v_keep = 'hold' then
    for i in 1 .. coalesce(array_length(a_ids, 1), 0) loop
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'hold', p_staff);
    end loop;
  elsif v_keep = 'allocated' then
    for i in 1 .. array_length(a_ids, 1) loop                                          -- a_qty = 잡는 수량 = so_split 뒤 그 줄의 qty_ordered
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (a_ids[i], a_qty[i], 'allocated', null);
    end loop;
  elsif v_keep = 'backorder' then
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  else
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'preorder', p_staff from public.so_line x where x.so_id = p_so_id
      and not exists (select 1 from public.so_reserve r where r.so_line_id = x.id and r.released_at is null);
  end if;

  select * into v_so from public.so where id = p_so_id;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'committed', true, 'keeps', v_keep, 'lines', v_plan, 'siblings', v_sibs);
end;
$$;
comment on function public.so_allocate_run(uuid, uuid, uuid[], boolean, boolean, boolean, uuid) is
  '⭐⭐ SO 할당 엔진(②a 속 함수 · 이견 9 · R1·R2·R3) — 열린 예약이 없는 줄을 (창고, 낱개 제품) 순으로 잠그고 가용(EA · so_available · 음수 0)에서 floor(가용/pack_factor) 만큼 잡는다 · 무리 셋 A 할당 · B 백오더 · P 프리오더(p_preorder_line_ids) · 가장 앞선 무리가 원래 번호를 지키고 나머지만 형제(so_split · B=a · P=b · 빈 문서 없음) · p_hold 면 전부 kind hold 로 원래에(나누지 않는다) · p_confirm 이면 원래를 draft→confirmed 로 먼저 올린다 · p_commit false = 계획만 · 예약 allocated·backorder 는 system(null) · preorder·hold 는 사람 · so_confirm(②a) · so_reallocate·so_change_location·so_backorder_proceed(②b)가 부른다';
revoke all on function public.so_allocate_run(uuid, uuid, uuid[], boolean, boolean, boolean, uuid) from public, anon, authenticated;

-- ═══ ⑦ 형제 조회 둘(5-d · po_family_* 20260919175712:56·92 모양) ═══
-- 7-a so_family_members — 뿌리까지 올라가 거기서 내려온 전부(닫힌 것까지 · 자기 포함) · path 순환 방어 · 깊이 50 · open_qty = 안 나간 수량(cancelled 는 0)
create function public.so_family_members(p_so_id uuid)
returns table (so_id uuid, so_number text, status text, closed_reason text, merged_into_id uuid, split_reason text, split_from_id uuid, depth int, is_self boolean, open_qty numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with recursive up as (
  select s.id, s.split_from_id, 1 as depth, array[s.id] as path
  from public.so s where s.id = p_so_id
  union all
  select q.id, q.split_from_id, up.depth + 1, up.path || q.id
  from up join public.so q on q.id = up.split_from_id
  where up.depth < 50 and not (q.id = any(up.path))
),
root as (
  select u.id from up u order by u.depth desc limit 1
),
down as (
  select s.id, s.split_from_id, 0 as depth, array[s.id] as path
  from public.so s where s.id = (select id from root)
  union all
  select c.id, c.split_from_id, down.depth + 1, down.path || c.id
  from down join public.so c on c.split_from_id = down.id
  where down.depth < 50 and not (c.id = any(down.path))
)
select s.id, s.so_number, s.status, s.closed_reason, s.merged_into_id, s.split_reason, s.split_from_id, d.depth, (s.id = p_so_id),
       case when s.status = 'cancelled' then 0
            else coalesce((select sum(l.qty_ordered - l.qty_shipped) from public.so_line l where l.so_id = s.id), 0) end
from down d join public.so s on s.id = d.id
order by s.so_number;
$$;
comment on function public.so_family_members(uuid) is '⭐ 형제 문서(5-d · ②a) — 이 오더가 속한 분할 가족 전부(뿌리에서 내려온 모든 문서 · 자기 포함 · 닫힌·취소·합쳐진 것도 · 갈라진 적 없으면 하나) · split_from_id 로 올라가 내려오는 재귀 · path 배열 순환 방어 · 깊이 50 · 칸: so_id · so_number · status · closed_reason · merged_into_id · split_reason · split_from_id · depth(뿌리 0) · is_self · open_qty(Σ qty_ordered − qty_shipped · cancelled 는 0) · invoker · stable';
revoke all on function public.so_family_members(uuid) from public, anon;
grant execute on function public.so_family_members(uuid) to authenticated;

-- 7-b so_family_lines — 제품 단위로 접는다(product_id · 5-d 이견 2) · 합계는 cancelled(merged·voided …) 문서를 뺀다(그 수요는 원래로 돌아갔거나 사라졌다) · fragments 는 전부 낸다(문서 상태 · 열린 예약 kind·수량)
create function public.so_family_lines(p_so_id uuid)
returns table (product_id uuid, sku text, product_name text, ordered_total numeric, shipped_total numeric, open_total numeric, members int, fragments jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with fm as (
  select * from public.so_family_members(p_so_id)
),
frag as (
  select l.product_id, fm.so_id, fm.so_number, fm.status as so_status, fm.split_reason, l.id as so_line_id, l.line_no, l.qty_ordered, l.qty_shipped, l.split_from_line_id,
         r.kind as reserve_kind, r.qty_allocated as reserve_qty
  from fm
  join public.so_line l on l.so_id = fm.so_id
  left join public.so_reserve r on r.so_line_id = l.id and r.released_at is null
)
select f.product_id, pr.sku, pr.name,
       coalesce(sum(f.qty_ordered) filter (where f.so_status <> 'cancelled'), 0),
       coalesce(sum(f.qty_shipped) filter (where f.so_status <> 'cancelled'), 0),
       coalesce(sum(f.qty_ordered - f.qty_shipped) filter (where f.so_status <> 'cancelled'), 0),
       (count(distinct f.so_id) filter (where f.so_status <> 'cancelled'))::int,
       jsonb_agg(jsonb_build_object('so_id', f.so_id, 'so_number', f.so_number, 'so_status', f.so_status, 'split_reason', f.split_reason,
                                    'so_line_id', f.so_line_id, 'line_no', f.line_no, 'qty_ordered', f.qty_ordered, 'qty_shipped', f.qty_shipped,
                                    'split_from_line_id', f.split_from_line_id, 'reserve_kind', f.reserve_kind, 'reserve_qty', f.reserve_qty)
                 order by f.so_number, f.line_no)
from frag f
join public.product pr on pr.id = f.product_id
group by f.product_id, pr.sku, pr.name
order by pr.sku;
$$;
comment on function public.so_family_lines(uuid) is '⭐⭐ 형제 합계 · 제품 단위(5-d · ②a) — 가족(so_family_members) 전부의 so_line 을 product_id 로 접는다(line_no 아님) · ordered_total·shipped_total·open_total·members 는 cancelled 문서(merged·voided …)를 뺀다 — 합쳐진 형제의 수요는 원래로 돌아갔다 · fragments[] 는 전부 낸다 {so_number · so_status · split_reason · line_no · qty · split_from_line_id · reserve_kind · reserve_qty(열린 예약)} · ⭐ 계산은 DB 가 한다(PO 실사고 2026-09-19) · invoker · stable';
revoke all on function public.so_family_lines(uuid) from public, anon;
grant execute on function public.so_family_lines(uuid) to authenticated;

-- ═══ ⑧ so_confirm — 확정(R1·R2·R3·R5·R6 · 6-d) ═══
create function public.so_confirm(
  p_so_id              uuid,
  p_preorder_line_ids  uuid[]  default '{}'::uuid[],   -- 사람이 고른 프리오더 줄(6-d) · 따로 뗀다(R2)
  p_hold               boolean default false,          -- 처음부터 보류로 확정(R3 · 오더 전체 · 재고를 잡지 않고 나누지 않는다)
  p_commit             boolean default true            -- false = 미리 보기(무엇이 할당·백오더·프리오더로 가나)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
  v_warn   text[] := '{}';
  v_res    jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R5)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — confirming pos and counter orders comes in a later step — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  if p_hold and coalesce(array_length(p_preorder_line_ids, 1), 0) > 0 then
    raise exception 'Choose either hold (whole order) or preorder lines, not both — nothing was saved';
  end if;

  -- R6 막는 조건 — 손님 · 창고 · 줄
  select * into c from public.customer where id = v_so.customer_id;
  if not found or not c.is_active then
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', coalesce(c.name, '?');
  end if;
  if v_so.location_id is null then
    raise exception 'Order % has no warehouse — set one before confirming — nothing was saved', v_so.so_number;
  end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then                       -- IN_TRANSIT 은 is_active=false 로 들어 있어 여기서 걸린다(이견 11)
    raise exception 'Warehouse % is inactive — pick an active warehouse — nothing was saved', coalesce(v_wh.name, '?');
  end if;
  select count(*) into v_n from public.so_line where so_id = p_so_id;
  if v_n = 0 then
    raise exception 'Order % has no lines — nothing was saved', v_so.so_number;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad from public.so_line l where l.so_id = p_so_id and l.unit_price is null;
  if v_bad is not null then
    raise exception 'Order % has lines without a price (%) — give them a price first — nothing was saved', v_so.so_number, v_bad;
  end if;
  select string_agg(l.sku, ', ' order by l.line_no) into v_bad
  from public.so_line l join public.product p on p.id = l.product_id where l.so_id = p_so_id and not p.is_active;
  if v_bad is not null then
    raise exception 'Order % has inactive products (%) — remove them first — nothing was saved', v_so.so_number, v_bad;
  end if;
  select string_agg(x::text, ', ') into v_bad
  from unnest(coalesce(p_preorder_line_ids, '{}'::uuid[])) x where not exists (select 1 from public.so_line l where l.id = x and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Preorder line % is not on order % — nothing was saved', v_bad, v_so.so_number;
  end if;

  -- 경고(막지 않는다) — 티어·통화 · 다시 매기기 권고 · 세일 끝난 뒤 넣은 줄
  v_warn := public.so_tier_warnings(v_so);
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if exists (select 1 from public.so_line l where l.so_id = p_so_id and l.deal_line_id is not null
               and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) then
    v_warn := array_append(v_warn, 'deal_ended_before_line_added');
  end if;

  v_res := public.so_allocate_run(p_so_id, v_so.location_id, p_preorder_line_ids, p_hold, true, p_commit, v_staff);
  return v_res || jsonb_build_object('warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_confirm(uuid, uuid[], boolean, boolean) is
  '⭐ SO 확정(②a · R1·R2·R3·R5·R6 · 6-d) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · draft 만 · warehouse 채널만(pos·counter 는 ④). 막는 것: 비활성 손님 · 창고 없음/비활성(IN_TRANSIT 포함) · 줄 없음 · 가격 없는 줄 · 비활성 제품 · 오더 밖 프리오더 줄 · hold 와 preorder 동시. 경고: 티어·통화 · reprice_suggested · deal_ended_before_line_added. 엔진 so_allocate_run: 잡을 수 있는 만큼 잡고 모자란 몫은 백오더 형제(a) · 프리오더 줄은 형제(b) · 원래는 가장 앞선 무리를 지킨다(빈 문서 없음) · p_hold = 오더 전체 보류로 확정(재고 안 잡음 · 안 나눔) · p_commit false = 미리 보기. 반환 {so_number · status · committed · keeps · lines[] · siblings[] · warnings}';
revoke all on function public.so_confirm(uuid, uuid[], boolean, boolean) from public, anon;
grant execute on function public.so_confirm(uuid, uuid[], boolean, boolean) to authenticated;

-- ═══ ⑨ so_unconfirm — 확정 되돌리기(R9 · supervisor 이상) ═══
--   대상 형제 = split_from_id = 원래 ∧ created_at = 원래.confirmed_at(그 확정 때 태어났다) · 손대지 않았다 = 형제·줄·예약의 updated_at 이 형제 created_at 과 같다 ∧ 예약 전부 열려 있다 ∧ 운임 0 ∧ 자식 0(⬜7 「같은 시각」)
--   원래 아래 다른 자식(확정 뒤 나눈 것 · 백오더 진행 · 오더 나누기)이 있으면 거부 — 되돌리기는 확정 하나만 무른다
--   하는 일: 예약 전부 풀기(원래 · 형제) · 형제 줄 도로 합치기(통째 = 행 이동 · 일부 = 원래 줄에 수량 더함) · 형제 cancelled/merged/merged_into_id/closed_note · 원래 draft · unconfirmed_at/by
create function public.so_unconfirm(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  s         public.so%rowtype;
  l         public.so_line%rowtype;
  v_next    int;
  v_merged  text[] := '{}';
  v_moved   int := 0;  v_added int := 0;  v_released int := 0;
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('supervisor', 'saved');       -- ⭐ 둘째 줄 — supervisor 이상(R9)
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.split_from_id is not null and v_so.confirmed_at is not null
     and exists (select 1 from public.so m where m.id = v_so.split_from_id and m.confirmed_at = v_so.confirmed_at) then
    raise exception 'Order % was itself split off at confirmation — unconfirm the original order % instead — nothing was saved',
      v_so.so_number, (select m.so_number from public.so m where m.id = v_so.split_from_id);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- 형제 검사(자기 행만 보는 것이 아니라 여기서 다른 행을 본다 — RPC 의 일 · 6-g′)
  for s in select * from public.so x where x.split_from_id = p_so_id order by x.so_number loop
    if s.created_at is distinct from v_so.confirmed_at then
      raise exception 'Order % was split again after confirmation (%) — unconfirm only undoes the split made at confirmation — nothing was saved', v_so.so_number, s.so_number;
    end if;
    if s.status <> 'confirmed' then
      raise exception 'Split order % is % — it must still be confirmed and in IMS to merge it back — nothing was saved', s.so_number, s.status;
    end if;
    if s.updated_at is distinct from s.created_at
       or exists (select 1 from public.so_line x where x.so_id = s.id and x.updated_at is distinct from s.created_at)
       or exists (select 1 from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = s.id and (r.released_at is not null or r.updated_at is distinct from s.created_at))
       or exists (select 1 from public.so_charge ch where ch.so_id = s.id)
       or exists (select 1 from public.so y where y.split_from_id = s.id) then
      raise exception 'Split order % was changed after the split — unconfirm is only possible while the split orders are untouched — nothing was saved', s.so_number;
    end if;
  end loop;

  -- 예약 전부 풀기 — 원래(allocated · hold · backorder · preorder) + 형제(backorder · preorder) · 지우지 않는다(5-f)
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x
  where x.id = r.so_line_id and r.released_at is null
    and (x.so_id = p_so_id or x.so_id in (select id from public.so where split_from_id = p_so_id));
  get diagnostics v_released = row_count;

  -- 형제 줄 도로 합치기 · 형제 닫기
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;
  for s in select * from public.so x where x.split_from_id = p_so_id order by x.so_number loop
    for l in select * from public.so_line x where x.so_id = s.id order by x.line_no loop
      if l.split_from_line_id is not null then
        update public.so_line set qty_ordered = qty_ordered + l.qty_ordered, updated_by = v_staff
        where id = l.split_from_line_id and so_id = p_so_id;
        get diagnostics v_n = row_count;
        if v_n <> 1 then raise exception 'Line % of % has lost its original line — nothing was saved', l.line_no, s.so_number; end if;
        v_added := v_added + 1;                                  -- 형제 줄 행은 이력으로 남는다(합계는 merged 문서를 뺀다)
      else
        v_next := v_next + 1;
        update public.so_line set so_id = p_so_id, line_no = v_next, updated_by = v_staff where id = l.id;
        v_moved := v_moved + 1;
      end if;
    end loop;
    update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = p_so_id, closed_at = now(),
                         closed_note = format('Unconfirmed with %s', v_so.so_number), cancelled_by = v_staff, updated_by = v_staff
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not merged back — it may have been changed by someone else just now — nothing was saved', s.so_number; end if;
    v_merged := array_append(v_merged, s.so_number);
  end loop;

  -- 원래 → draft · 되돌리기 기록 · 확정 흔적 비움(다시 확정하면 새로 찍힌다)
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, unconfirmed_at = now(), unconfirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not unconfirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  return jsonb_build_object('so_number', v_so.so_number, 'status', 'draft', 'merged', to_jsonb(v_merged),
                            'lines_moved_back', v_moved, 'lines_added_back', v_added, 'reserves_released', v_released);
end;
$$;
comment on function public.so_unconfirm(uuid) is
  '⭐ 확정 되돌리기(②a · R9 · Caleb 「백오더로 스플릿 되기 이전으로 롤백」) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(supervisor). 조건: 원래가 confirmed(IMS 안 · 창고로 갔으면 먼저 WMS 롤백) · 형제는 그 확정 때 태어난 것만(created_at = 원래 confirmed_at) · 손대지 않았다(형제·줄·예약 updated_at = 형제 created_at · 예약 전부 열림 · 운임 0 · 자식 0 — 「같은 시각」 ⬜7) · 확정 뒤 다시 나눈 자식이 있으면 거부. 하는 일: 예약 전부 풀기(원래·형제 · released_at/by) · 형제 줄 도로 합치기(통째 = 행 이동 · 일부 = split_from_line_id 줄에 수량 더함 · 형제 줄 행은 이력) · 형제 cancelled·merged·merged_into_id·closed_note · 원래 draft · confirmed_at/by 비움 · unconfirmed_at/by. 글자는 다시 쓰지 않는다(다음 확정은 다음 글자) · 줄 가격·할인은 그대로(다시 매기기는 so_reprice)';
revoke all on function public.so_unconfirm(uuid) from public, anon;
grant execute on function public.so_unconfirm(uuid) to authenticated;

-- ═══ 검증(~/asung/prompts/so-write-2a-verify.sql · psql -v ON_ERROR_STOP=1 -f · 시퀀스 rollback 밖 setval) ═══
--   구조: 칸 넷 · CHECK 식 · 함수 8(guard 재발행 · so_require_role · so_available · so_split · so_allocate_run · so_family_members · so_family_lines · so_confirm · so_unconfirm)
--   흐름: A 충분 · B 일부 · C 0 · D 프리오더 → 미리 보기 → 확정 → 셋(원래 · a 백오더 · b 프리오더) · 예약 kind · 가용이 준다 · 세트 줄 floor(있으면) · 전부 없음 → 원래 자신이 백오더 · p_hold → 전부 hold ·
--        되돌리기(supervisor) → 형제 merged · closed_note · draft · 가용 원상 · 다시 확정 → 다음 글자(c) · 거부 여덟(manager 되돌리기 · 형제 고친 뒤 · pos · IN_TRANSIT · 가격 없음 · 비활성 제품 · 비활성 손님 · 창고 없음) · 권한 셋(sales만 · manager · supervisor)
