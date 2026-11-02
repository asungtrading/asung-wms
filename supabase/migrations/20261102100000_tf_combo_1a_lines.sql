-- ─────────────────────────────────────────────────────────────
-- tf-combo-1a — 트랜스퍼 콤보 줄 ① 문서 쪽 (Asung-IMS · 2026-11-02 · 판정 952 ~ 957 · tf-combo-1 §0 이견 답: 1 (가) · 2 (가) · 5 (가) · 6 거부 · 12 두 파일)
--   정본(뒤에 문서 차수가 적는다): so-module §27(트랜스퍼) · §44(콤보 asm) · 판정 952(콤보 줄 + 구성품 줄 · SO 꼴) · 953(반쪽 콤보 없음 — ① 확정은 구성품 가용 · ② 픽은 1b) · 954(받기는 구성품 줄만 · 1b) · 955(콤보 줄 원가 — · 1b) · 956(같은 SKU 낱개 + 구성품 공존) · 957(정산은 구성품 줄 · 1b)
--   든 것:
--     1) inv_transfer_line 칸 둘 — combo_line_id(구성품 줄 → 콤보 줄 · on delete cascade) · combo_qty(콤보 하나에 드는 이 구성품 수 · 정의가 바뀌어도 열린 문서는 저장된 값 그대로)
--        CHECK 셋 combo_self · combo_pair · combo_qty(SO 의 넷째 combo_values 는 값 칸이 없어 짝이 없다) · 부모 검사는 DEFERRABLE INITIALLY DEFERRED 제약 트리거(같은 트랜스퍼 · 콤보 안 콤보 금지 · 부모 존재 · SO so_line_combo_parent_check 와 같은 꼴)
--        유니크 inv_transfer_line_product_uq (transfer_id, product_id) → unique nulls not distinct (transfer_id, product_id, combo_line_id)(판정 956 · 규칙 29 부분 유니크 없음 · PG 17) — 같은 콤보 줄 둘은 (t, pid, null) 로 지금처럼 막힌다
--     2) 도우미 둘(속 · authenticated 못 부른다) — tf_combo_children_insert(콤보 줄 밑에 구성품 줄 · qty = 콤보 qty × bom.quantity · pack_factor 는 구성품 것 · 꺼진 구성품 거부) · tf_combo_children_sync(콤보 수량 → 구성품 수량)
--        콤보 판정 = so_combo_is(켜진 product_bom) · 「콤보 줄」 = 구성품 줄이 달린 줄(SO · 뷰 · so_ship 과 같은 기준 — 구성품 없는 콤보 상품 줄(TRF-00003 #316)은 보통 줄 그대로 · 기존 행 무접촉)
--     3) 창구 — inv_transfer_line_set(콤보 SKU 면 구성품 생성 · 수량 따라가기 · 구성품 줄 직접 고치기 거부 · 상품 바꾸기는 콤보가 끼면 거부 「remove the line and add it again」 · 「already has a line」 은 보통 줄만)
--        inv_transfer_line_remove(구성품 줄 거부 · 콤보 줄은 구성품 먼저) · inv_transfer_lines_paste(콤보 ok 줄 · 꺼진 구성품은 inactive · exists 는 보통 줄만 · 재고 알림은 구성품 기준 · short_by 는 콤보 단위 · available_units · components[])
--     4) 가용 · 예약 — inv_transfer_shortage need · inv_available_base talloc · stk_reserved trf 에 「콤보 줄 제외」 한 줄씩(판정 566 짝 — 셋이 같은 조건) · 다른 갈래(bal · alloc) 무변
--     5) 뷰 wms_order_doc_line 트랜스퍼 갈래 — 콤보 줄 숨김 + combo_line_id · combo_qty · combo_sku(SO 갈래 꼴) ⇒ 픽 계획 · 배치 · 픽 · 팩 · 팔렛 · handoff · Finalize 가 구성품 줄만 본다
--     6) wms_pick_lines cbc — 콤보 줄을 so_line ∪ inv_transfer_line 에서 찾는다(판정 887 박스 바코드가 트랜스퍼 픽 · 팩에서도) · inv_transfer_list line_count · qty_ea 에서 콤보 줄 제외
--   재발행(마지막 정의 · DB prosrc md5 대조 뒤 바이트 복사 · 바뀐 줄만 · 줄 끝 「tf-combo-1a」): inv_transfer_line_set · inv_transfer_line_remove · inv_transfer_shortage · inv_transfer_list(20260928201753 transfer_1a) · inv_transfer_lines_paste(20261002174937 tf_paste_1)
--        inv_available_base · stk_reserved(20261023131028 bgr_1a) · 뷰 wms_order_doc_line(20261005201634 asm_2b1) · wms_pick_lines(20261030160000 combo_bc_1)
--   ⚠️ 거래 표 FK 의 컷오버 규칙(지우는 순서): combo_line_id 는 자기 참조 cascade 라 `delete from inv_transfer_line` 한 문장이면 구성품 줄이 함께 지워진다 — 순서는 지금과 같다:
--        RESTRICT 로 이 표를 가리키는 일곱(wms_pick_task_lines · wms_pack_task_lines · wms_pallet_items · po_receipt_work · po_receipt_line · po_receipt_diff · inv_transfer_settle) → inv_transfer_line → inv_transfer. 콤보 줄에는 그 일곱의 행이 생기지 않는다.
--   손대지 않는 것: 원장 포스터 · 레이어 · 운임 · carried · 취소 · Unconfirm · Shopify 큐 함수(⚠️ shop_stock_queue_trigger 는 inv_transfer_line 문장 트리거라 콤보 줄의 콤보 pid 도 큐에 든다 — 함수 수정 0 · 해롭지 않다) · 출발 · 받기 · 정산(1b)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 화면 무접촉(transfers.html · wms-receiver.html 은 대화 Claude)
-- ─────────────────────────────────────────────────────────────
do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══ 1) inv_transfer_line 칸 둘 · CHECK 셋 · 유니크 교체 · 부모 검사(deferred 제약 트리거) ═══
alter table public.inv_transfer_line
  add column combo_line_id uuid references public.inv_transfer_line (id) on delete cascade,
  add column combo_qty     numeric;
create index inv_transfer_line_combo_line_id_idx on public.inv_transfer_line (combo_line_id) where combo_line_id is not null;
alter table public.inv_transfer_line
  add constraint inv_transfer_line_combo_self_ck check (combo_line_id is distinct from id),
  add constraint inv_transfer_line_combo_pair_ck check ((combo_line_id is null) = (combo_qty is null)),
  add constraint inv_transfer_line_combo_qty_ck  check (combo_qty is null or combo_qty > 0);
alter table public.inv_transfer_line drop constraint inv_transfer_line_product_uq;
alter table public.inv_transfer_line add constraint inv_transfer_line_product_uq unique nulls not distinct (transfer_id, product_id, combo_line_id);   -- 판정 956: 같은 SKU 가 보통 줄 + 구성품 줄로 공존 · 같은 콤보 줄 둘 · 같은 보통 줄 둘은 막힌다
comment on column public.inv_transfer_line.combo_line_id is 'tf-combo-1a(판정 952): set on a component line — the combo line it hangs under (same transfer · that line is a combo line itself) · null on ordinary and combo lines · cascade with the combo line';
comment on column public.inv_transfer_line.combo_qty     is 'tf-combo-1a: component line only — units of this component per one combo at the time the line was made · qty = combo qty × combo_qty · the combo definition may change later, open transfers keep this';

create function public.inv_transfer_line_combo_parent_check() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_p public.inv_transfer_line%rowtype; v_c public.inv_transfer_line%rowtype;
begin
  -- deferred 라 문장 끝 · 트랜잭션 끝에 돈다 — 그 사이 지워진 줄(콤보 줄을 지우면 cascade)의 묵은 사건이 올 수 있다 ⇒ 지금 행을 다시 읽어 판정한다(없으면 볼 것이 없다) · so_line_combo_parent_check 와 같은 꼴
  select * into v_c from public.inv_transfer_line where id = new.id;
  if not found or v_c.combo_line_id is null then return null; end if;
  select * into v_p from public.inv_transfer_line where id = v_c.combo_line_id;
  if not found then
    raise exception 'Line % (%) hangs under a combo line that does not exist — nothing was saved', v_c.line_no, v_c.sku;
  end if;
  if v_p.transfer_id <> v_c.transfer_id then
    raise exception 'Line % (%) hangs under combo line % of another transfer — nothing was saved', v_c.line_no, v_c.sku, v_p.line_no;
  end if;
  if v_p.combo_line_id is not null then
    raise exception 'Line % (%) hangs under line %, which is itself a component — a combo cannot contain a combo — nothing was saved', v_c.line_no, v_c.sku, v_p.line_no;
  end if;
  return null;
end;
$$;
create constraint trigger inv_transfer_line_combo_parent_ck after insert or update of combo_line_id, transfer_id on public.inv_transfer_line
  deferrable initially deferred for each row execute function public.inv_transfer_line_combo_parent_check();
comment on function public.inv_transfer_line_combo_parent_check() is 'tf-combo-1a: deferred row check — a component line''s combo_line_id points at a combo line of the same transfer (checked at statement end · SO so_line_combo_parent_check 의 트랜스퍼 판)';

-- ═══ 2) 도우미 둘 — 속 함수(authenticated 못 부른다 · definer 창구가 부른다) ═══
create function public.tf_combo_children_insert(p_parent public.inv_transfer_line, p_staff uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int := 0; v_next int; v_bad text;
begin
  select string_agg(c.sku, ', ' order by c.sku) into v_bad
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active and not c.is_active;
  if v_bad is not null then
    raise exception 'Combo % has inactive component(s) (%) — fix the combo first — nothing was saved', p_parent.sku, v_bad;
  end if;
  select coalesce(max(line_no), 0) into v_next from public.inv_transfer_line where transfer_id = p_parent.transfer_id;
  insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, updated_by, combo_line_id, combo_qty)
  select p_parent.transfer_id, (v_next + row_number() over (order by c.sku))::int, c.id, c.sku, p_parent.qty * b.quantity, coalesce(nullif(c.pack_factor, 0), 1), p_staff, p_parent.id, b.quantity
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = p_parent.product_id and b.is_active;
  get diagnostics v_n = row_count;
  if v_n < 1 then                                                                          -- 판정 885: 구성품 하나 콤보(수량 2 이상)가 있다 · 켜진 구성품 0 만 거부(so_combo_children_insert 와 같다)
    raise exception 'Combo % has no active components — fix the combo first — nothing was saved', p_parent.sku;
  end if;
  return v_n;
end;
$$;
revoke all on function public.tf_combo_children_insert(public.inv_transfer_line, uuid) from public, anon, authenticated;
comment on function public.tf_combo_children_insert(public.inv_transfer_line, uuid) is 'tf-combo-1a(판정 952): 콤보 줄 밑에 구성품 줄 — qty = 콤보 qty × bom.quantity · pack_factor 는 구성품 것(coalesce(nullif, 0) → 1) · combo_qty = bom.quantity · line_no 는 끝에 · 꺼진 구성품이 있으면 거부 · so_combo_children_insert 의 트랜스퍼 판';

create function public.tf_combo_children_sync(p_line_id uuid, p_staff uuid) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int := 0;
begin
  update public.inv_transfer_line c set qty = p.qty * c.combo_qty, updated_by = p_staff
    from public.inv_transfer_line p where p.id = p_line_id and c.combo_line_id = p.id and c.qty is distinct from p.qty * c.combo_qty;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.tf_combo_children_sync(uuid, uuid) from public, anon, authenticated;
comment on function public.tf_combo_children_sync(uuid, uuid) is 'tf-combo-1a: 콤보 줄 수량 → 구성품 줄 수량(qty = 콤보 qty × combo_qty) · 바뀐 행 수 · so_combo_children_sync 의 트랜스퍼 판';

-- ═══ 3) inv_transfer_line_set 재발행 — 원본 20260928201753_transfer_1a.sql:150 ~ 185 (DB md5 d61437d4…) 의 검사 · 메시지 그대로 + 콤보 가지(줄 끝 tf-combo-1a) ═══
create or replace function public.inv_transfer_line_set(p_transfer_id uuid, p_line jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_p public.product%rowtype; v_l public.inv_transfer_line%rowtype; v_old public.inv_transfer_line%rowtype; v_qty numeric; v_id uuid; v_no int; v_pf numeric; v_staff uuid; v_kids int := 0;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_staff := public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);     -- ⭐ 첫 줄 문(문서의 창고 둘) · tf-combo-1a: 사람을 받아 구성품 줄 updated_by 에
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be edited (unconfirm it first) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;
  if nullif(p_line->>'product_id', '') is not null then select * into v_p from public.product p where p.id = (p_line->>'product_id')::uuid;
  else select * into v_p from public.product p where p.sku = trim(p_line->>'sku'); end if;
  if not found then raise exception 'Product not found (%) — nothing was saved', coalesce(p_line->>'sku', p_line->>'product_id'); end if;
  if not v_p.is_active then raise exception 'Product % is inactive — nothing was saved', v_p.sku; end if;
  if nullif(p_line->>'qty', '') is null or (p_line->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then raise exception 'qty must be a positive number — nothing was saved'; end if;
  v_qty := (p_line->>'qty')::numeric;
  if v_qty <= 0 then raise exception 'qty must be more than 0 — nothing was saved'; end if;
  v_pf := coalesce(nullif(v_p.pack_factor, 0), 1);
  v_id := nullif(p_line->>'line_id', '')::uuid;
  if v_id is not null then
    select * into v_old from public.inv_transfer_line l where l.id = v_id and l.transfer_id = p_transfer_id;
    if not found then raise exception 'Line not found on this transfer — nothing was saved'; end if;
    if v_old.combo_line_id is not null then                                                                                                    -- tf-combo-1a(판정 952 · SO 묶음 3): 구성품 줄은 따로 못 고친다 — 콤보 줄을 고치면 따라간다
      raise exception 'Line % (%) is a component of combo % (line %) — change the combo line instead — nothing was saved', v_old.line_no, v_old.sku,
        (select c.sku from public.inv_transfer_line c where c.id = v_old.combo_line_id), (select c.line_no from public.inv_transfer_line c where c.id = v_old.combo_line_id);
    end if;
    if v_old.product_id <> v_p.id and (exists (select 1 from public.inv_transfer_line k where k.combo_line_id = v_old.id) or public.so_combo_is(v_p.id)) then   -- tf-combo-1a(이견 6): 콤보가 끼는 상품 바꾸기는 거부
      raise exception 'Line % (%) — a combo line cannot be changed to another product, and a line cannot be changed into a combo — remove the line and add it again — nothing was saved', v_old.line_no, v_old.sku;
    end if;
  end if;
  if exists (select 1 from public.inv_transfer_line l where l.transfer_id = p_transfer_id and l.product_id = v_p.id and l.combo_line_id is null and l.id is distinct from v_id) then   -- tf-combo-1a(판정 956): 보통 줄끼리만 · 구성품 줄의 같은 SKU 는 막지 않는다(유니크도 같다)
    raise exception 'Transfer % already has a line for % — change that line instead — nothing was saved', v_x.transfer_number, v_p.sku;
  end if;
  if v_id is not null then
    update public.inv_transfer_line l set product_id = v_p.id, sku = v_p.sku, qty = v_qty, pack_factor = v_pf where l.id = v_id returning * into v_l;
    perform public.tf_combo_children_sync(v_l.id, v_staff);                                                                                     -- tf-combo-1a: 콤보 줄이면 구성품 수량이 따라간다(아니면 0 행)
  else
    select coalesce(max(l.line_no), 0) + 1 into v_no from public.inv_transfer_line l where l.transfer_id = p_transfer_id;
    insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (p_transfer_id, v_no, v_p.id, v_p.sku, v_qty, v_pf) returning * into v_l;
    if public.so_combo_is(v_p.id) then perform public.tf_combo_children_insert(v_l, v_staff); end if;                                          -- tf-combo-1a(판정 952): 콤보 상품이면 구성품 줄이 딸려 온다
  end if;
  select count(*) into v_kids from public.inv_transfer_line k where k.combo_line_id = v_l.id;
  return jsonb_build_object('transfer_id', p_transfer_id, 'line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'product_name', v_p.name,
                            'qty', v_l.qty, 'pack_factor', v_l.pack_factor, 'qty_ea', v_l.qty * v_l.pack_factor,
                            'is_combo', v_kids > 0, 'components', v_kids);                                                                       -- tf-combo-1a: 화면이 구성품 줄을 다시 읽게(inv_transfer_detail)
end;
$$;
comment on function public.inv_transfer_line_set(uuid, jsonb) is 'tr-1a 줄 넣기 · 고치기(초안만 · 첫 줄 inv_transfer_require) · tf-combo-1a(판정 952 · 956 · 이견 6): 콤보 상품(so_combo_is)이면 구성품 줄이 딸려 온다(tf_combo_children_insert) · 콤보 줄 수량 수정은 구성품이 따라간다(tf_combo_children_sync) · 구성품 줄 직접 수정 거부 · 콤보가 끼는 상품 바꾸기 거부(지우고 다시) · 「already has a line」 은 보통 줄만 · 반환 is_combo · components';

-- ═══ 4) inv_transfer_line_remove 재발행 — 원본 transfer_1a:187 ~ 202 (DB md5 68074cee…) + 구성품 줄 거부 · 콤보 줄은 구성품 먼저 ═══
create or replace function public.inv_transfer_line_remove(p_transfer_id uuid, p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_l public.inv_transfer_line%rowtype; v_n int; v_kids int := 0;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  perform public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be edited (unconfirm it first) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  select * into v_l from public.inv_transfer_line l where l.id = p_line_id and l.transfer_id = p_transfer_id;
  if not found then raise exception 'Line not found on this transfer — nothing was saved'; end if;
  if v_l.combo_line_id is not null then                                                                                                        -- tf-combo-1a(판정 952 · SO 묶음 3): 구성품 줄은 따로 못 지운다
    raise exception 'Line % (%) is a component of combo % (line %) — remove the combo line instead — nothing was saved', v_l.line_no, v_l.sku,
      (select c.sku from public.inv_transfer_line c where c.id = v_l.combo_line_id), (select c.line_no from public.inv_transfer_line c where c.id = v_l.combo_line_id);
  end if;
  delete from public.inv_transfer_line where combo_line_id = p_line_id;                                                                       -- tf-combo-1a: 구성품 줄 먼저(FK 도 cascade 지만 수를 센다)
  get diagnostics v_kids = row_count;
  delete from public.inv_transfer_line where id = p_line_id and transfer_id = p_transfer_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line not found on this transfer — nothing was saved'; end if;
  return jsonb_build_object('transfer_id', p_transfer_id, 'removed', p_line_id, 'removed_components', v_kids);
end;
$$;
comment on function public.inv_transfer_line_remove(uuid, uuid) is 'tr-1a 줄 지우기(초안만) · tf-combo-1a(판정 952): 구성품 줄은 거부(콤보 줄을 지워라) · 콤보 줄을 지우면 구성품 줄 먼저 · 반환 removed_components';

-- ═══ 5) inv_transfer_lines_paste 재발행 — 원본 20261002174937_tf_paste_1.sql:46 ~ 200 바이트 복사(DB md5 4f218306…) + 콤보 가지(줄 끝 tf-combo-1a) · 권한 · comment 그대로(create or replace · comment 는 아래 다시) ═══
create or replace function public.inv_transfer_lines_paste(p_transfer_id uuid, p_lines jsonb, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_limit     constant int := 500;
  v_x         public.inv_transfer%rowtype;
  v_n         int;
  v_next      int;
  r           record;
  v_sku       text;
  v_qty       numeric;
  v_pid       uuid;  v_psku text;  v_pname text;  v_pactive boolean;  v_pf numeric;  v_spid uuid;
  v_verdict   text;
  v_msgs      text[];
  v_line_no   int;
  v_line_id   uuid;
  v_inserted  boolean;
  v_dup_of    int;
  v_exists_no int;
  v_seen_ids  uuid[] := '{}';
  v_seen_n    int[]  := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_set       jsonb;
  v_need      jsonb := '{}'::jsonb;                     -- stock pid → 이 초안의 기존 줄 EA(붙이기 전 · 묶음 5)
  v_add       jsonb := '{}'::jsonb;                     -- stock pid → 붙인 ok 줄 EA
  v_pids      uuid[] := '{}';
  v_avail     numeric;  v_short numeric;
  v_combo     boolean;  v_comp jsonb;  cr record;  v_cq numeric;  v_cmax numeric;  v_cmin numeric;  v_tmp jsonb;   -- tf-combo-1a(이견 5): 콤보 ok 줄의 구성품 몫
  e           jsonb;  v_out jsonb := '[]'::jsonb;
  n_ok int := 0;  n_nf int := 0;  n_in int := 0;  n_dup int := 0;  n_ex int := 0;  n_bad int := 0;  n_short int := 0;  n_ins int := 0;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  perform public.inv_transfer_require(v_x.from_warehouse_id, v_x.to_warehouse_id);       -- ⭐ 첫 줄 문(문서의 창고 둘 · 미리 보기도 · 묶음 6)
  if v_x.status <> 'draft' then raise exception 'Transfer % is % — only a draft can be edited (unconfirm it first) — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then raise exception 'p_lines must be a JSON array of {sku, qty} — nothing was saved'; end if;

  v_n := jsonb_array_length(p_lines);
  if v_n > c_limit then                                                                   -- 묶음 1 — 예외가 아니라 판정 · 넣지도 않는다
    return jsonb_build_object(
      'transfer_id', p_transfer_id, 'transfer_number', v_x.transfer_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'not_found', 0, 'inactive', 0, 'duplicate', 0, 'exists', 0, 'bad_qty', 0, 'short', 0, 'inserted', 0,
                                    'too_many', true, 'limit', c_limit, 'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(l.line_no), 0) into v_next from public.inv_transfer_line l where l.transfer_id = p_transfer_id;
  -- 묶음 5 — 이 초안의 기존 줄 EA(stock pid = 세트의 부모 · inv_transfer_shortage 와 같은 접기) · 붙이기 전에 센다(넣은 뒤 두 번 세지 않게)
  select coalesce(jsonb_object_agg(s.stock_pid::text, s.ea), '{}'::jsonb) into v_need
  from (select coalesce(p.parent_product_id, p.id) as stock_pid, sum(l.qty * l.pack_factor) as ea
          from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = p_transfer_id
           and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id) group by 1) s;   -- tf-combo-1a: 콤보 줄은 재고 몫이 아니다(구성품 줄이 있다)

  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(p_lines) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_pf := null; v_spid := null;
    v_verdict := null; v_msgs := '{}'; v_line_no := null; v_line_id := null; v_inserted := false; v_dup_of := null; v_exists_no := null;
    v_combo := false; v_comp := null;   -- tf-combo-1a

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만(묶음 2 · po_lines_paste 와 같은 정규식)
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만 · 0 · 음수는 bad_qty
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is not null then
      select p.id, p.sku, p.name, p.is_active, coalesce(nullif(p.pack_factor, 0), 1), coalesce(p.parent_product_id, p.id)
        into v_pid, v_psku, v_pname, v_pactive, v_pf, v_spid
      from public.product p where p.sku = v_sku;                                          -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active, coalesce(nullif(p.pack_factor, 0), 1), coalesce(p.parent_product_id, p.id)
          into v_pid, v_psku, v_pname, v_pactive, v_pf, v_spid
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;                 -- 폴백 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    v_combo := v_pid is not null and public.so_combo_is(v_pid);                             -- tf-combo-1a(판정 952): 콤보 상품(켜진 product_bom · Release 한 콤보는 낱개)
    -- 판정 여섯(묶음 3 · 이 순서)
    if v_qty is null or v_qty <= 0 then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    elsif v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    elsif v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    elsif not v_pactive then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added (inv_transfer_line_set refuses it too)');
    elsif v_combo and exists (select 1 from public.product_bom b join public.product cp on cp.id = b.component_product_id where b.parent_product_id = v_pid and b.is_active and not cp.is_active) then   -- tf-combo-1a: 꺼진 구성품이 있는 콤보(tf_combo_children_insert 가 거부한다 — 전체가 되돌아가지 않게 미리)
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'combo_component_inactive — fix the combo first (inv_transfer_line_set refuses it too)');
    else
      v_dup_of := (select v_seen_n[i] from generate_subscripts(v_seen_ids, 1) i where v_seen_ids[i] = v_pid limit 1);
      if v_dup_of is not null then
        v_verdict := 'duplicate'; v_msgs := array_append(v_msgs, format('duplicate_of_paste_line_%s — fix the source and paste again', v_dup_of));
      else
        v_seen_ids := array_append(v_seen_ids, v_pid); v_seen_n := array_append(v_seen_n, r.n);
        select l.line_no into v_exists_no from public.inv_transfer_line l where l.transfer_id = p_transfer_id and l.product_id = v_pid and l.combo_line_id is null order by l.line_no limit 1;   -- tf-combo-1a(판정 956): 보통 줄만(구성품 줄의 같은 SKU 는 막지 않는다)
        if v_exists_no is not null then
          v_verdict := 'exists'; v_msgs := array_append(v_msgs, format('already_on_line_%s — to change the quantity edit that line (inv_transfer_line_set), not paste', v_exists_no));
        else
          v_verdict := 'ok';
        end if;
      end if;
    end if;

    -- ok 만 번호를 받고(미리 보기는 예상 번호 · 넣기는 inv_transfer_line_set 이 준 번호) · 넣기는 규칙 한 곳으로(묶음 4)
    if v_verdict = 'ok' then
      v_next := v_next + 1; v_line_no := v_next;
      if p_commit then
        v_set := public.inv_transfer_line_set(p_transfer_id, jsonb_build_object('product_id', v_pid, 'qty', v_qty::text));
        v_line_no := (v_set->>'line_no')::int;  v_line_id := (v_set->>'line_id')::uuid;
        v_inserted := true; n_ins := n_ins + 1;
      end if;
      if v_combo then                                                                     -- tf-combo-1a(판정 952 · 953 ① · 이견 5): 콤보 줄의 재고 몫은 구성품으로(stock pid = 구성품의 낱개 · 콤보 하나 = quantity × 구성품 pack_factor EA)
        v_comp := '[]'::jsonb;
        for cr in select cp.sku, coalesce(cp.parent_product_id, cp.id) as spid, b.quantity as qpc, coalesce(nullif(cp.pack_factor, 0), 1) as pf
                    from public.product_bom b join public.product cp on cp.id = b.component_product_id where b.parent_product_id = v_pid and b.is_active order by cp.sku loop
          v_add := v_add || jsonb_build_object(cr.spid::text, coalesce((v_add->>(cr.spid::text))::numeric, 0) + v_qty * cr.qpc * cr.pf);
          if not (cr.spid = any(v_pids)) then v_pids := array_append(v_pids, cr.spid); end if;
          v_comp := v_comp || jsonb_build_object('sku', cr.sku, 'stock_product_id', cr.spid, 'qty_per_combo', cr.qpc, 'pack_factor', cr.pf, 'need_ea', v_qty * cr.qpc * cr.pf);
        end loop;
      else
        v_add := v_add || jsonb_build_object(v_spid::text, coalesce((v_add->>(v_spid::text))::numeric, 0) + v_qty * v_pf);
        if not (v_spid = any(v_pids)) then v_pids := array_append(v_pids, v_spid); end if;
      end if;
    end if;

    case v_verdict
      when 'ok' then n_ok := n_ok + 1;
      when 'not_found' then n_nf := n_nf + 1;
      when 'inactive' then n_in := n_in + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      when 'exists' then n_ex := n_ex + 1;
      when 'bad_qty' then n_bad := n_bad + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive, 'stock_product_id', v_spid,
      'pack_factor', case when v_verdict = 'ok' then v_pf end, 'qty_ea', case when v_verdict = 'ok' then v_qty * v_pf end,
      'available_ea', null, 'short_by', null, 'available_units', null, 'is_combo', v_combo, 'components', v_comp,   -- tf-combo-1a: 콤보 ok 줄은 components[{sku, stock_product_id, qty_per_combo, pack_factor, need_ea}] · 아래 묶음 5 가 available_ea · short_ea 를 더한다
      'line_no', v_line_no, 'line_id', v_line_id, 'inserted', v_inserted,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 묶음 5 — 재고 알림(ok 줄만 · stock pid 별 「기존 + 붙인」 EA 와 가용을 견준다 · 막지 않는다)
  for e in select x from jsonb_array_elements(v_rows) x loop
    if e->>'verdict' = 'ok' and (e->>'is_combo')::boolean then                                      -- tf-combo-1a(이견 5 (가)): 콤보 ok 줄 — 구성품마다 가용을 보고 short_by 는 콤보 단위(가장 모자란 구성품 기준 ⌈…⌉ · 콤보 수 상한) · available_units = min ⌊가용 ÷ 콤보 하나 EA⌋ · available_ea 는 null
      v_cq := (e->>'qty_ea')::numeric / (e->>'pack_factor')::numeric;
      v_cmax := 0; v_cmin := null; v_tmp := '[]'::jsonb;
      for cr in select (k->>'stock_product_id')::uuid as spid, (k->>'qty_per_combo')::numeric as qpc, (k->>'pack_factor')::numeric as pf, k from jsonb_array_elements(e->'components') k loop
        select m.available_ea into v_avail from public.so_available_many(array[cr.spid], v_x.from_warehouse_id) m;
        v_avail := coalesce(v_avail, 0);
        v_short := greatest(coalesce((v_need->>(cr.spid::text))::numeric, 0) + coalesce((v_add->>(cr.spid::text))::numeric, 0) - v_avail, 0);
        v_cmax := greatest(v_cmax, ceil(v_short / (cr.qpc * cr.pf)));
        v_cmin := least(v_cmin, floor(greatest(v_avail, 0) / (cr.qpc * cr.pf)));
        v_tmp := v_tmp || (cr.k || jsonb_build_object('available_ea', v_avail, 'short_ea', v_short));
      end loop;
      v_short := least(v_cq, v_cmax);
      e := e || jsonb_build_object('available_ea', null, 'available_units', coalesce(v_cmin, 0), 'short_by', v_short, 'components', v_tmp);
      if v_short > 0 then
        n_short := n_short + 1;
        e := jsonb_set(e, '{message}', to_jsonb(trim(both ' · ' from coalesce(e->>'message', '') || format(' · short_by_%s_combos — components short at the from warehouse (%s), confirm will refuse unless the quantity is reduced', v_short,
                 (select string_agg((k->>'sku') || ' ' || (k->>'short_ea') || ' ea', ', ') from jsonb_array_elements(v_tmp) k where (k->>'short_ea')::numeric > 0)))));
      end if;
    elsif e->>'verdict' = 'ok' then
      select m.available_ea into v_avail from public.so_available_many(array[(e->>'stock_product_id')::uuid], v_x.from_warehouse_id) m;
      v_avail := coalesce(v_avail, 0);
      v_short := greatest(coalesce((v_need->>(e->>'stock_product_id'))::numeric, 0) + coalesce((v_add->>(e->>'stock_product_id'))::numeric, 0) - v_avail, 0);
      e := e || jsonb_build_object('available_ea', v_avail, 'short_by', v_short);
      if v_short > 0 then
        n_short := n_short + 1;
        e := jsonb_set(e, '{message}', to_jsonb(trim(both ' · ' from coalesce(e->>'message', '') || format(' · short_by_%s_ea — available %s at the from warehouse, confirm will refuse unless the quantity is reduced', v_short, v_avail))));
      end if;
    end if;
    v_out := v_out || e;
  end loop;

  return jsonb_build_object(
    'transfer_id', p_transfer_id, 'transfer_number', v_x.transfer_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'not_found', n_nf, 'inactive', n_in, 'duplicate', n_dup, 'exists', n_ex, 'bad_qty', n_bad, 'short', n_short,
                                  'inserted', n_ins, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_out);
end;
$$;
comment on function public.inv_transfer_lines_paste(uuid, jsonb, boolean) is
  '⭐ 트랜스퍼 붙여 넣기(tf-paste-1 · 판정 233 = 판정 171 의 실행 · 묶음 1 ~ 6) — definer · 첫 줄 inv_transfer_require(from, to)(미리 보기도) · 초안만 · p_lines [{sku, qty}] 최대 500(넘으면 summary.too_many · 예외 아님) · 판정 여섯 bad_qty → not_found(case_fixed) → inactive → duplicate(앞줄) → exists(그 줄 · inv_transfer_line_set 으로 고쳐라) → ok · p_commit true 는 ok 만 inv_transfer_line_set 으로 줄마다 넣는다(규칙 한 곳 · 사이에 누가 같은 상품을 넣었으면 그 raise 가 전부 되돌린다) · 세트는 세트 단위 · 계수는 상품에서 · 재고는 알리기만 — stock pid(세트의 부모) 별 「이 초안의 기존 줄 + 붙인 ok 줄」 EA 가 so_available_many(출발 창고) 가용을 넘으면 그 줄들에 available_ea · short_by · summary.short(확정은 inv_transfer_shortage 로 따로 거부) · 반환 모양은 po_lines_paste 를 따른다 · ⭐ tf-combo-1a(판정 952 · 956 · 이견 5): 콤보 SKU 는 ok(is_combo · components[{sku, stock_product_id, qty_per_combo, pack_factor, need_ea, available_ea, short_ea}] · 넣으면 inv_transfer_line_set 이 구성품 줄을 만든다) · 꺼진 구성품이 있으면 inactive · exists 는 보통 줄만 · 콤보 줄의 재고 알림은 구성품 기준 — available_ea null · available_units = min ⌊가용 ÷ 콤보 하나 EA⌋ · short_by 는 콤보 단위';

-- ═══ 6) inv_transfer_shortage 재발행 — 원본 transfer_1a:220 ~ 235 바이트 복사(DB md5 8c920078…) + 콤보 줄 제외 한 줄 ═══
create or replace function public.inv_transfer_shortage(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with x as (select t.from_warehouse_id from public.inv_transfer t where t.id = p_transfer_id),
  need as (
    select coalesce(p.parent_product_id, p.id) as stock_pid, min(sp.sku) as stock_sku, sum(l.qty * l.pack_factor) as need_ea
      from public.inv_transfer_line l join public.product p on p.id = l.product_id
      left join public.product sp on sp.id = coalesce(p.parent_product_id, p.id)
     where l.transfer_id = p_transfer_id
       and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)   -- tf-combo-1a(판정 953 ①): 콤보 줄은 빼고 구성품 줄로 센다(콤보 pid 는 재고 키가 아니라 가용 0 — 빼지 않으면 확정이 늘 거부된다)
     group by 1
  ),
  av as (select m.* from public.so_available_many((select array_agg(stock_pid) from need), (select from_warehouse_id from x)) m)
  select coalesce(jsonb_agg(jsonb_build_object('stock_product_id', n.stock_pid, 'sku', n.stock_sku, 'need_ea', n.need_ea, 'available_ea', coalesce(av.available_ea, 0)) order by n.stock_sku)
                  filter (where n.need_ea > coalesce(av.available_ea, 0)), '[]'::jsonb)
    from need n left join av on av.stock_pid = n.stock_pid;
$$;
comment on function public.inv_transfer_shortage(uuid) is 'tr-1a 가용 검사 조각(확정 묶음 3 · 상세 shortage) — 줄을 낱개 제품으로 접어(세트는 parent) 출발 창고 가용(so_available_many)과 견준다 · tf-combo-1a(판정 953 ①): 콤보 줄(구성품이 달린 줄)은 빼고 구성품 줄로 센다';

-- ═══ 7) inv_available_base 재발행 — 원본 20261023131028_bgr_1a_bgrade_bins.sql:133 ~ 185 바이트 복사(DB md5 d3f21fae…) + talloc 한 줄 · comment 끝에 한 마디 ═══
create or replace function public.inv_available_base(p_location_id uuid, p_stock_pids uuid[] default null)
  returns table (stock_pid uuid, qty_ea numeric, sales_alloc_ea numeric, transfer_alloc_ea numeric, bgrade_ea numeric)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with wh as (                                                                            -- 창고 이름 — 뷰는 warehouse(이름) · sku 로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다(warehouse_id · product_id 로 거르면 뷰 전체 18k 행을 센다)
    select w.name from public.ref_warehouse w where w.id = p_location_id
  ),
  skus as (                                                                              -- 부른 키의 sku 들 — p_stock_pids 가 null 이면 null(= 전부)
    select case when p_stock_pids is null then null else (select array_agg(p.sku) from public.product p where p.id = any(p_stock_pids)) end as arr
  ),
  bal as (                                                                               -- 장부 — 창고의 모든 bin 합(ims_inv_balance · product 에 없는 sku 는 재고 키가 아니다)
    select b.product_id as stock_pid, sum(b.qty) filter (where not b.bin_is_bgrade) as qty, sum(b.qty) filter (where b.bin_is_bgrade) as bg   -- bgr-1a 판정 641: 팔 수 있는 장부 = B급 칸을 뺀 합 · B급 칸 합은 bg 로 따로
    from public.ims_inv_balance b
    where b.warehouse = (select name from wh) and b.product_id is not null
      and ((select k.arr from skus k) is null or b.sku = any((select k.arr from skus k)::text[]))   -- 스칼라 서브쿼리(InitPlan 상수)라 뷰 안 인덱스 조건으로 내려간다 · 괄호만 쓰면 서브쿼리 꼴(text = text[])로 읽힌다
    group by b.product_id
  ),
  alloc as (                                                                             -- 판매 예약 — 열린 allocated 예약 × 줄의 pack_factor · 오더 창고 · 재고 키 = 낱개(세트는 parent)
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(r.qty_allocated * l.pack_factor) as ea
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    where r.released_at is null and r.kind = 'allocated'
      and s.location_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
      and l.bgrade_bin_id is null                                                       -- bgr-1a(bgr-0 이견 2): B급 줄의 할당은 정상 가용을 깎지 않는다(stk_reserved 와 같은 조건)
    group by 1
  ),
  talloc as (                                                                            -- 트랜스퍼 예약(tr-1a 묶음 2) — 확정된 문서(창고로 보내기 · 픽 중 포함 · 출발 전)의 줄 자체 · 출발 창고 · 낱개 EA
    select coalesce(p.parent_product_id, p.id) as stock_pid, sum(l.qty * l.pack_factor) as ea
    from public.inv_transfer_line l
    join public.inv_transfer t on t.id = l.transfer_id
    join public.product p on p.id = l.product_id
    where t.status in ('confirmed', 'at_wms', 'picking')
      and t.from_warehouse_id = p_location_id
      and (p_stock_pids is null or coalesce(p.parent_product_id, p.id) = any(p_stock_pids))
      and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)   -- tf-combo-1a(판정 952 · 566 짝): 콤보 줄은 예약이 아니다 — 구성품 줄이 센다(stk_reserved trf · inv_transfer_shortage 와 같은 조건)
    group by 1
  ),
  keys as (
    select stock_pid from bal union select stock_pid from alloc union select stock_pid from talloc
  )
  select k.stock_pid,
         coalesce(bal.qty, 0),
         coalesce(alloc.ea, 0),
         coalesce(talloc.ea, 0),
         coalesce(bal.bg, 0)                                                              -- bgr-1a: bgrade_ea(그 창고 B급 칸 잔고 합 · 수량만)
  from keys k
  left join bal    on bal.stock_pid    = k.stock_pid
  left join alloc  on alloc.stock_pid  = k.stock_pid
  left join talloc on talloc.stock_pid = k.stock_pid;
$$;
comment on function public.inv_available_base(uuid, uuid[]) is '⭐⭐ 가용 재고 식 한 곳(stk-1 · 판정 264 · 265 · 2026-10-06 · 종전 so_available_many 본문) — 창고 하나의 재고 키(낱개 · 세트는 parent · p_stock_pids null = 전부 · 배열 = 그 키만 — 장부는 sku = any 로 뷰 안 인덱스에 밀어넣어 1 키 ~56 ms · 전부 ~170 ms · 배열 7,663 은 쓰지 마라(null 로)) → (stock_pid · qty_ea 창고 잔고 = ims_inv_balance 모든 bin 합 · sales_alloc_ea Σ 열린 allocated 예약 × pack_factor(오더 창고) · transfer_alloc_ea Σ 확정 · at_wms · picking 트랜스퍼 줄 qty × pack_factor(출발 창고)) · available = qty_ea − sales_alloc_ea − transfer_alloc_ea 는 부르는 쪽이 뺀다(so_available_many · stk_availability) · 조인 한 문장(= any 는 sku 밀어넣기에만 · product_id = any 는 뷰 전체를 센다) · ⭐ definer(판정 264): inv_transfer 의 select 정책은 transfer · WMS 열쇠인데 가용은 모든 직원에게 같아야 한다 — invoker 였던 so_available_many 는 sales 만 가진 직원에게 트랜스퍼 예약을 0 으로 보였다 · 원가 열 없음(판정 262) · authenticated execute(invoker 껍데기들이 부른다) · 음수 그대로 · preorder · hold · backorder 는 빼지 않는다 · ⭐ [2026-10-20 stk-av-1 판정 566] alloc · talloc 의 조건은 stk_reserved(목록)와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도(시험: 모든 키 × 창고에서 목록 합 = 타일) · ⭐ [2026-10-23 bgr-1a 판정 641] qty_ea = 팔 수 있는 장부(B급 칸 is_bgrade 제외) · bgrade_ea = 그 창고 B급 칸 잔고 합(새 다섯째 칸) · alloc 은 B급 줄(so_line.bgrade_bin_id)의 할당을 뺀다(stk_reserved 와 같은 조건) · ⭐ [2026-11-02 tf-combo-1a 판정 952] talloc 은 콤보 줄(구성품 줄이 달린 inv_transfer_line)을 빼고 구성품 줄로 센다(stk_reserved trf 와 같은 조건)';

-- ═══ 7′) stk_reserved 재발행 — 원본 bgr_1a:621 ~ 684 바이트 복사(DB md5 664db961…) + trf 한 줄(판정 566 짝) ═══
CREATE OR REPLACE FUNCTION public.stk_reserved(p_product_id uuid, p_warehouse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff     uuid;
  v_pid       uuid;
  v_sku       text;
  v_wh        text;
  v_sales     boolean;
  v_so        jsonb;
  v_trf       jsonb;
  v_so_total  numeric;
  v_trf_total numeric;
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(stk_* 와 같은 문)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
  select coalesce(p.parent_product_id, p.id) into v_pid from public.product p where p.id = p_product_id;   -- 재고 키 = 낱개(세트 id 를 받으면 그 낱개 · inv_available_base 와 같은 키)
  if v_pid is null then raise exception 'Product not found — nothing was read'; end if;
  select p.sku into v_sku from public.product p where p.id = v_pid;
  v_sales := public.ims_can_view('sales');   -- 손님 이름은 sales(:read 포함) 열쇠가 있는 사람에게만 · 창고 직원에게는 SO 번호 · 상태 · 수량만
  -- ⭐ 판매 예약 — inv_available_base 의 alloc 과 서로 같은 조건(판정 566) — 한쪽을 고치면 다른 쪽도:
  --   released_at null · kind allocated(hold · backorder · preorder 는 안 셈) · 오더 창고 s.location_id · 재고 키 coalesce(parent_product_id, id) · qty_allocated × 줄 pack_factor · 콤보는 구성품 줄이 그대로 걸린다
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_id', s.id, 'so_number', s.so_number, 'status', s.status,
           'customer_name', case when v_sales then c.name end,
           'line_sku', l.sku, 'qty', r.qty_allocated, 'pack_factor', l.pack_factor, 'qty_ea', r.qty_allocated * l.pack_factor,
           'allocated_at', r.allocated_at) order by r.allocated_at, s.so_number, l.line_no), '[]'::jsonb),
         coalesce(sum(r.qty_allocated * l.pack_factor), 0)
    into v_so, v_so_total
  from public.so_reserve r
  join public.so_line l on l.id = r.so_line_id
  join public.so s on s.id = l.so_id
  join public.product p on p.id = l.product_id
  left join public.customer c on c.id = s.customer_id
  where r.released_at is null and r.kind = 'allocated'
    and s.location_id = p_warehouse_id
    and l.bgrade_bin_id is null                                                        -- bgr-1a: inv_available_base alloc 과 같은 조건(B급 줄의 할당은 타일 · 목록 둘 다 빠진다)
    and coalesce(p.parent_product_id, p.id) = v_pid;
  -- ⭐ 트랜스퍼 예약 — inv_available_base 의 talloc 과 서로 같은 조건(판정 566): status confirmed · at_wms · picking(출발 전) · 출발 창고 · qty × 줄 pack_factor
  select coalesce(jsonb_agg(jsonb_build_object(
           'transfer_id', t.id, 'transfer_number', t.transfer_number, 'status', t.status,
           'from_warehouse', wf.name, 'to_warehouse', wt.name,
           'line_sku', l.sku, 'qty', l.qty, 'pack_factor', l.pack_factor, 'qty_ea', l.qty * l.pack_factor,
           'confirmed_at', t.confirmed_at) order by t.transfer_number, l.line_no), '[]'::jsonb),
         coalesce(sum(l.qty * l.pack_factor), 0)
    into v_trf, v_trf_total
  from public.inv_transfer_line l
  join public.inv_transfer t on t.id = l.transfer_id
  join public.product p on p.id = l.product_id
  left join public.ref_warehouse wf on wf.id = t.from_warehouse_id
  left join public.ref_warehouse wt on wt.id = t.to_warehouse_id
  where t.status in ('confirmed', 'at_wms', 'picking')
    and t.from_warehouse_id = p_warehouse_id
    and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)   -- tf-combo-1a(판정 952 · 566 짝): 콤보 줄은 빼고 구성품 줄로(inv_available_base talloc 과 같은 조건)
    and coalesce(p.parent_product_id, p.id) = v_pid;
  return jsonb_build_object('product_id', v_pid, 'sku', v_sku, 'warehouse_id', p_warehouse_id, 'warehouse', v_wh, 'customer_name_visible', v_sales,
                            'so', v_so, 'so_total', v_so_total, 'trf', v_trf, 'trf_total', v_trf_total);
end;
$function$;

-- ═══ 8) 뷰 wms_order_doc_line 재발행 — 원본 20261005201634_asm_2b1_combo_warehouse_path.sql:45 ~ 82 바이트 복사 + 트랜스퍼 갈래(판정 952 · 954) ═══
create or replace view public.wms_order_doc_line with (security_invoker = true) as
  select 'so'::text as doc_kind,
         l.so_id as doc_id,
         l.id as line_id,
         l.line_no,
         l.product_id,
         l.sku,
         l.product_name,
         l.pack_factor,
         (l.qty_ordered - l.qty_removed) as qty_target,
         ((l.qty_ordered - l.qty_removed) * l.pack_factor) as qty_target_ea,
         coalesce(p.parent_product_id, p.id) as stock_product_id,
         l.combo_line_id,
         l.combo_qty,
         (select c.sku from public.so_line c where c.id = l.combo_line_id) as combo_sku
    from public.so_line l
    join public.product p on p.id = l.product_id
   where not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1(판정 244): 콤보 줄은 창고 문서 줄이 아니다 — 구성품 줄이 재고 · 픽 · 출고를 든다
  union all
  select 'transfer'::text as doc_kind,
         l.transfer_id as doc_id,
         l.id as line_id,
         l.line_no,
         l.product_id,
         l.sku,
         p.name as product_name,
         l.pack_factor,
         l.qty as qty_target,
         (l.qty * l.pack_factor) as qty_target_ea,
         coalesce(p.parent_product_id, p.id) as stock_product_id,
         l.combo_line_id,
         l.combo_qty,
         (select c.sku from public.inv_transfer_line c where c.id = l.combo_line_id) as combo_sku
    from public.inv_transfer_line l
    join public.product p on p.id = l.product_id
   where not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id);                                              -- tf-combo-1a(판정 952 · 954): 트랜스퍼도 콤보 줄은 창고 문서 줄이 아니다 — 구성품 줄이 재고 · 픽 · 팩 · 팔렛 · 출발 · 받기를 든다
comment on view public.wms_order_doc_line is '공용 줄 목록 — so_line(qty_ordered − qty_removed) union all inv_transfer_line(qty) · pack_factor · qty_target_ea · stock_product_id(세트는 parent) · doc_id 로 읽는다 · asm-2b1(판정 244): 콤보 줄(구성품이 달린 줄)은 빠진다 — 구성품 줄이 combo_line_id · combo_qty · combo_sku 를 들고 온다(「for combo ○○」) · tf-combo-1a(판정 952): 트랜스퍼 갈래도 같다 — 콤보 줄 숨김 · 구성품 줄에 combo_line_id · combo_qty · combo_sku';



-- ═══ 9) wms_pick_lines 재발행 — 원본 20261030160000_combo_bc_1_pick_lines_combo_barcodes.sql:60 ~ 209 바이트 복사(DB md5 10322939…) + cbc 한 줄 · comment 끝에 한 마디 ═══
CREATE OR REPLACE FUNCTION public.wms_pick_lines(p_task_ids bigint[] DEFAULT NULL::bigint[], p_pack_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_task_ids bigint[];
  v_pack_id  bigint := p_pack_task_id;
  v_out      jsonb;
begin
  if (p_task_ids is null or cardinality(p_task_ids) = 0) = (p_pack_task_id is null) then
    raise exception 'Pass exactly one of p_task_ids / p_pack_task_id';
  end if;
  if p_pack_task_id is not null then
    select array[k.pick_task_id] into v_task_ids from public.wms_pack_tasks k where k.id = p_pack_task_id;
    if v_task_ids is null or v_task_ids[1] is null then return '[]'::jsonb; end if;     -- 팩 과제 없음 · 픽 과제 없는 팩 과제 = 빈 배열(깨끗한 빈손)
  else
    v_task_ids := p_task_ids;
  end if;

  with t as (
    select t.id, t.batch_label, coalesce(t.order_id, t.transfer_id) as order_id, t.wave_id, t.tote_no,
           d.doc_number as so_number, d.warehouse_id as location_id, w.name as wh_name, d.party_name as customer_name
    from public.wms_pick_tasks t
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
    left join public.ref_warehouse w on w.id = d.warehouse_id
    where t.id = any(v_task_ids)
  ), pl as (
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.transfer_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
           t.order_id, t.so_number, t.customer_name, t.location_id, t.wh_name, t.batch_label, t.wave_id, t.tote_no,
           x.sku, x.product_name, x.pack_factor,
           x.combo_line_id, x.combo_qty, x.combo_sku,                                                                       -- asm-2b1(판정 244 · 묶음 6): 구성품 줄이 어느 콤보 것인지
           coalesce(p.parent_product_id, p.id) as stock_pid, (p.parent_product_id is not null) as is_set
    from public.wms_pick_task_lines l
    join t on t.id = l.pick_task_id
    join public.wms_order_doc_line x on x.line_id = coalesce(l.order_line_id, l.transfer_line_id)
    join public.product p on p.id = x.product_id
  ), pids as (
    select distinct pl.stock_pid from pl
  ), whs as (
    select distinct t.location_id from t where t.location_id is not null
  ), bal as (                                                             -- 창고 전체 잔고 · 한 문장 · 한 번(속도 함정)
    select v.warehouse_id, v.product_id, sum(v.qty) as qty
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
      and not v.bin_is_bgrade                                             -- bgr-1a 판정 635 · 641: 팔 수 있는 잔고만
    group by v.warehouse_id, v.product_id
  ), bc as (                                                              -- 낱개(factor 1) + 그 낱개를 parent 로 둔 세트들(factor = pack_factor)
    select coalesce(p.parent_product_id, p.id) as stock_pid,
           jsonb_agg(jsonb_build_object('barcode', b.barcode,
                                        'factor', case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end,
                                        'sku', p.sku)
                     order by case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end, b.is_primary desc, b.barcode) as arr
    from public.product_barcode b
    join public.product p on p.id = b.product_id
    where b.is_active
      and (p.id = any(array(select pids.stock_pid from pids)) or p.parent_product_id = any(array(select pids.stock_pid from pids)))
    group by coalesce(p.parent_product_id, p.id)
  ), bins as (                                                            -- 계획 칸(planned) · 실제 칸(actual) · 존은 여기 한 곳에서
    select x.pick_task_line_id, x.planned,
           jsonb_agg(jsonb_build_object('bin', x.bin, 'bin_id', x.bin_id, 'qty_base', x.qty_base,
                                        'zone', coalesce(rb.zone,
                                                         case when coalesce(x.bin, '') = '' then ''
                                                              when pl2.wh_name ilike '%edmonton%' and upper(left(x.bin, 1)) = 'E' then upper(substr(x.bin, 2, 1))
                                                              else upper(left(x.bin, 1)) end),
                                        'picked_by', x.picked_by, 'picked_at', x.picked_at)
                     order by x.id) as arr
    from public.wms_pick_line_bins x
    join pl pl2 on pl2.line_id = x.pick_task_line_id
    left join public.ref_bin rb on rb.id = x.bin_id
    group by x.pick_task_line_id, x.planned
  ), sbal as (                                                            -- pick-bin-2(판정 122) 칸 잔고 한 번 · bal 과 같은 술어 · bin 있는 행만(속도 함정)
    select v.warehouse_id, v.product_id, v.bin_id, v.qty, v.bin_is_active
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
      and v.bin_id is not null
      and not v.bin_is_bgrade                                             -- bgr-1a 판정 635: 픽 안내가 B급 칸으로 가지 않는다
  ), sb as (                                                              -- 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저(계획 행 순) · 장부 내림 · 이름 · qty 는 낱개(EA)
    select z.line_id,
           jsonb_agg(jsonb_build_object('bin_id', z.bin_id, 'bin', z.bin, 'zone', z.zone, 'qty', z.qty, 'is_active', z.is_active, 'planned', z.planned)
                     order by z.planned desc, z.plan_ord nulls last, z.qty desc, z.bin) as arr
    from (
      select pl3.line_id, rb.id as bin_id, rb.name as bin,
             coalesce(rb.zone, case when coalesce(rb.name, '') = '' then ''
                                    when pl3.wh_name ilike '%edmonton%' and upper(left(rb.name, 1)) = 'E' then upper(substr(rb.name, 2, 1))
                                    else upper(left(rb.name, 1)) end) as zone,
             coalesce(s.qty, 0) as qty, rb.is_active, (pb.min_id is not null) as planned, pb.min_id as plan_ord
      from pl pl3
      join lateral (select s0.bin_id from sbal s0 where s0.product_id = pl3.stock_pid and s0.warehouse_id = pl3.location_id and s0.qty > 0 and s0.bin_is_active
                    union
                    select x.bin_id from public.wms_pick_line_bins x where x.pick_task_line_id = pl3.line_id and x.planned) c on true
      join public.ref_bin rb on rb.id = c.bin_id
      left join sbal s on s.bin_id = c.bin_id and s.product_id = pl3.stock_pid and s.warehouse_id = pl3.location_id
      left join (select x.pick_task_line_id, x.bin_id, min(x.id) as min_id from public.wms_pick_line_bins x where x.planned group by 1, 2) pb
             on pb.pick_task_line_id = pl3.line_id and pb.bin_id = c.bin_id
    ) z
    group by z.line_id
  ), cbc as (                                                             -- combo-bc-1(판정 887): 구성품 줄이 가리키는 콤보 줄의 제품 바코드 — 켜진 것 · primary 먼저 · 콤보 줄마다 한 번
    select cl.id as combo_line_id,
           jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) as arr
    from (select distinct pl.combo_line_id from pl where pl.combo_line_id is not null) c
    join (select sl.id, sl.product_id from public.so_line sl union all select tl.id, tl.product_id from public.inv_transfer_line tl) cl on cl.id = c.combo_line_id   -- tf-combo-1a(판정 954): 트랜스퍼 콤보 줄도(판매 · 트랜스퍼 줄 id 는 서로 다른 uuid)
    join public.product_barcode b on b.product_id = cl.product_id and b.is_active
    group by cl.id
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.transfer_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', coalesce(pl.order_line_id, pl.transfer_line_id), 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'combo_line_id', pl.combo_line_id, 'combo_qty', pl.combo_qty, 'combo_sku', pl.combo_sku,                                              -- asm-2b1: 화면이 「for combo ○○」 를 그린다 · 보통 줄은 null
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
             'stock_bins', coalesce(sb.arr, '[]'::jsonb),
             'barcodes', coalesce(bc.arr, '[]'::jsonb),
             'available_ea', coalesce(bal.qty, 0))
           || jsonb_build_object('combo_barcodes', coalesce(cbc.arr, '[]'::jsonb))                                                -- combo-bc-1(판정 887): 박스 바코드 — 구성품 줄이 아니면 []
           || case when v_pack_id is null then '{}'::jsonb
                   else jsonb_build_object('pack_line_id', pk.pack_line_id, 'expected_base', pk.expected_base, 'verified_base', pk.verified_base,
                                           'pack_status', pk.pack_status, 'pack_verification_method', pk.pack_verification_method,
                                           'verified_by', pk.verified_by, 'verified_at', pk.verified_at) end
           order by pl.tote_no nulls first, pl.pick_task_id, pl.line_id), '[]'::jsonb)
    into v_out
  from pl
  join public.product sp on sp.id = pl.stock_pid
  left join bal  on bal.warehouse_id = pl.location_id and bal.product_id = pl.stock_pid
  left join bc   on bc.stock_pid = pl.stock_pid
  left join bins bp on bp.pick_task_line_id = pl.line_id and bp.planned
  left join bins ba on ba.pick_task_line_id = pl.line_id and not ba.planned
  left join sb   on sb.line_id = pl.line_id
  left join cbc  on cbc.combo_line_id = pl.combo_line_id                                                                          -- combo-bc-1(판정 887)
  left join pk   on coalesce(pk.order_line_id, pk.transfer_line_id) = coalesce(pl.order_line_id, pl.transfer_line_id)
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$function$;
comment on function public.wms_pick_lines(bigint[], bigint) is
  '⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부) 또는 팩 줄(팩 과제 하나) + 제품 · 바코드(낱개 + 세트 factor) · 계획 칸 · 실제 칸 · 존(ref_bin.zone 우선 · 없으면 칸 이름 규칙) · 창고 가용(ims_inv_balance 합 · 한 문장) · ⊕ stock_bins(pick-bin-2 판정 122: 이 낱개 제품의 그 창고 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저 · 장부 내림 · 이름 · qty 는 낱개 EA · [{bin_id, bin, zone, qty, is_active, planned}]). 읽기 · stable · invoker · 창고 검사 없음(쓰기 창구가 지킨다). 사진 칸 없음(판정 33). ⊕ combo_barcodes(combo-bc-1 판정 887: 구성품 줄이면 그 콤보 줄 제품의 켜진 바코드 ["…"] · primary 먼저 · 아니면 [] — 박스 한 번 = 콤보 줄의 구성품 줄마다 combo_qty × pack_factor · verification_method scanned_combo). · tf-combo-1a(판정 954): combo_barcodes 는 트랜스퍼 콤보 줄(inv_transfer_line)에도';

-- ═══ 10) inv_transfer_list 재발행 — 원본 transfer_1a:292 ~ 316 바이트 복사(DB md5 6a7767be…) + 콤보 줄 제외 둘 ═══
create or replace function public.inv_transfer_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else
  coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (
    select x.id, x.transfer_number, x.status, x.from_warehouse_id, fw.name as from_warehouse, x.to_warehouse_id, tw.name as to_warehouse, x.note,
           x.created_at, x.confirmed_at, x.at_wms_at, x.departed_at, x.received_at, x.cancelled_at,
           cb.name as created_by_name, fb.name as confirmed_by_name,
           (select count(*) from public.inv_transfer_line l where l.transfer_id = x.id and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)) as line_count,                   -- tf-combo-1a(이견 2): 콤보 줄은 세지 않는다(구성품 줄이 든다)
           (select coalesce(sum(l.qty * l.pack_factor), 0) from public.inv_transfer_line l where l.transfer_id = x.id and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)) as qty_ea
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id
      join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by
      left join public.ims_staff fb on fb.id = x.confirmed_by
     where (nullif(p_filters->>'status', '') is null or x.status = p_filters->>'status')
       and (nullif(p_filters->>'from_warehouse_id', '') is null or x.from_warehouse_id = (p_filters->>'from_warehouse_id')::uuid)
       and (nullif(p_filters->>'to_warehouse_id', '') is null or x.to_warehouse_id = (p_filters->>'to_warehouse_id')::uuid)
       and (nullif(p_filters->>'q', '') is null or x.transfer_number ilike '%' || (p_filters->>'q') || '%' or x.note ilike '%' || (p_filters->>'q') || '%'
            or exists (select 1 from public.inv_transfer_line l where l.transfer_id = x.id and l.sku ilike '%' || (p_filters->>'q') || '%'))
       and (nullif(p_filters->>'from', '') is null or x.created_at >= (p_filters->>'from')::date)
       and (nullif(p_filters->>'to', '') is null or x.created_at < (p_filters->>'to')::date + 1)
     order by x.created_at desc limit coalesce(nullif(p_filters->>'limit', '')::int, 300)) t), '[]'::jsonb) end;
$$;
comment on function public.inv_transfer_list(jsonb) is 'tr-1a 트랜스퍼 목록(transfer 열쇠 · 필터 status · 창고 · q · 기간 · limit 300) · tf-combo-1a: line_count · qty_ea 는 콤보 줄(구성품이 달린 줄)을 빼고 센다';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_t text;
begin
  select string_agg(c.conname || '=' || pg_get_constraintdef(c.oid), ' ' order by c.conname) into v_t from pg_constraint c where c.conrelid = 'public.inv_transfer_line'::regclass and c.conname like 'inv_transfer_line_combo%' or (c.conrelid = 'public.inv_transfer_line'::regclass and c.conname = 'inv_transfer_line_product_uq');
  if v_t <> 'inv_transfer_line_combo_line_id_fkey=FOREIGN KEY (combo_line_id) REFERENCES inv_transfer_line(id) ON DELETE CASCADE inv_transfer_line_combo_pair_ck=CHECK (((combo_line_id IS NULL) = (combo_qty IS NULL))) inv_transfer_line_combo_parent_ck=TRIGGER DEFERRABLE INITIALLY DEFERRED inv_transfer_line_combo_qty_ck=CHECK (((combo_qty IS NULL) OR (combo_qty > (0)::numeric))) inv_transfer_line_combo_self_ck=CHECK ((combo_line_id IS DISTINCT FROM id)) inv_transfer_line_product_uq=UNIQUE NULLS NOT DISTINCT (transfer_id, product_id, combo_line_id)'
    then v_bad := v_bad || format(' constraints(%s)', v_t); end if;
  select count(*) into v_n from pg_trigger t where t.tgrelid = 'public.inv_transfer_line'::regclass and t.tgname = 'inv_transfer_line_combo_parent_ck' and t.tgdeferrable and t.tginitdeferred;
  if v_n <> 1 then v_bad := v_bad || ' parent_trigger'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('tf_combo_children_insert', 'tf_combo_children_sync')
     and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 2 then v_bad := v_bad || format(' helper_acl_%s_of_2', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_available_base', 'stk_reserved') and p.prosecdef;
  if v_n <> 5 then v_bad := v_bad || format(' definer_%s_of_5', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_transfer_shortage', 'inv_transfer_list', 'wms_pick_lines') and not p.prosecdef;
  if v_n <> 3 then v_bad := v_bad || format(' invoker_%s_of_3', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_transfer_shortage', 'inv_transfer_list', 'inv_available_base', 'stk_reserved', 'wms_pick_lines')
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 8 then v_bad := v_bad || format(' reissued_acl_%s_of_8', v_n); end if;
  if pg_get_viewdef('public.wms_order_doc_line'::regclass) !~ 'k\.combo_line_id = l\.id' or (length(pg_get_viewdef('public.wms_order_doc_line'::regclass)) - length(replace(pg_get_viewdef('public.wms_order_doc_line'::regclass), 'combo_line_id = l.id', ''))) / length('combo_line_id = l.id') <> 2
    then v_bad := v_bad || ' view'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_available_base', 'stk_reserved', 'inv_transfer_shortage') and p.prosrc like '%not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id)%';
  if v_n <> 3 then v_bad := v_bad || format(' exclusion_%s_of_3', v_n); end if;
  -- SO 쪽 무접촉(so_line 콤보 장치 · 창구)
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) into v_t from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_combo_children_insert', 'so_combo_children_sync', 'so_line_combo_parent_check', 'so_lines_available', 'so_pick_plan', 'so_ship', 'so_finalize', 'wms_so_handoff', 'tf_depart');
  if v_t <> 'so_combo_children_insert=3a807f52183ec43423d19375ed42b8b6 so_combo_children_sync=109b79beb016f1bedba5ab5441f53527 so_finalize=70d4711f91b1ff0b3bb7067864383124 so_line_combo_parent_check=f4c9bbc6bcef18694ee3f78d23cd89a6 so_lines_available=5fae508a5cf2c51dd15ad11f1056a537 so_pick_plan=bdde73f22c0e0af219e88c0b9f53e331 so_ship=30b384f331b241cddbfb7d2fa6300a40 tf_depart=8f5e778399d58113491737ba948de9c5 wms_so_handoff=3b76808723ea879a7ac64c5f60c50217'
    then v_bad := v_bad || format(' untouched_changed(%s)', v_t); end if;
  if v_bad <> '' then raise exception 'tf-combo-1a landing check failed:%', v_bad; end if;
end $$;
