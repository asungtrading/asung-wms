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

-- nb-3 — Action Centre 「Sold without stock」 의 Count & check: 센 개수로 조정 확정 + 확인 기록을 한 트랜잭션에
--   (판정 1176 · Caleb 2026-11-10 「mark checked 할때 바로 정리되는게 가장 깔끔해 보여.」 · so-module §112-g · §20 판정 7 · 0-11 · 지시서 ~/asung/prompts/nb-3.md)
--   무엇:
--     ① so_stock_short_check — 칸 adjust_number(만든 ADJ 번호 · 없으면 null) · source 값에 'count'(manual 은 그대로 Mark checked)
--     ② so_stock_short_count_state(안 도우미 · 직원이 못 부른다) — 그 SKU × 창고의 칸별 장부 · picked · 확인 안 된 「재고 없이 나갔다」 줄(오더별) · 레이어 − 장부 · seen(본 값의 지문)
--     ③ so_stock_short_count_view(읽기 · R1) — 문 = Action Centre 와 같은 sales 보기 · ② 를 그대로 + can_count
--     ④ so_stock_short_count(쓰기 · R2 · p_commit false = 미리 보기) — 문 = inv_adjust_require(stock_adjust + 그 창고 · worker 는 열쇠가 있어도 못 한다 = 매니저 이상 · 판정 1176)
--          조정은 지금 창구를 그대로 부른다: inv_adjust_create → inv_adjust_line_set(mode set · reason count · 단가 비움) → inv_adjust_eval → inv_adjust_confirm — 검사 · 원가 규칙 · nb-1 메우기 무복사
--          미리 보기는 같은 길을 안쪽 블록에서 돌리고 되돌린다(머리만 번호 없는 임시 행 — ADJ 번호 시퀀스를 쓰지 않는다)
--          바꿀 줄이 0 이면 조정 없이 확인만 · 본 값(p_seen)이 지금과 다르면 거부 · 장부가 음수인 칸은 반드시 세어야 한다 · 확인 안 된 줄이 없으면 거부
--     ⑤ so_stock_short_list 재발행 — 줄마다 adjust_number · check_source 두 칸 더함(지운 칸 0) · 몸 = DB prosrc 원본(874b243e = 20261021131845 rls-3b) + 고친 자리(-- nb-3 표지)만
--   무접촉: so_stock_short_confirm(Mark checked 그대로) · inv_adjust_* 전부 · nb-1 · nb-2 의 함수(so_pick_plan · so_counter_ship · ref_bin_unassigned_guard) · 이미 있는 확인 기록 · 원장 행 0 · 화면 0

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.so_stock_short_list(jsonb)'::regprocedure) is distinct from '874b243e4714d8a28a8477a73fd1684e' then
    raise exception 'nb-3 ⓪ so_stock_short_list differs from what this migration was built on — rebuild from the current body first — nothing was changed';
  end if;
  if to_regprocedure('public.inv_layer_recent_cost(text,text)') is null then
    raise exception 'nb-3 ⓪ nb-1 (inv_layer_recent_cost) is not applied — apply nb-1 first — nothing was changed';
  end if;
end $$;

-- ═══ ① 확인 기록 — 만든 조정 번호 · source count ═══
alter table public.so_stock_short_check add column if not exists adjust_number text;
alter table public.so_stock_short_check drop constraint if exists so_stock_short_check_source_ck;
alter table public.so_stock_short_check add constraint so_stock_short_check_source_ck check (source in ('manual', 'count'));
alter table public.so_stock_short_check drop constraint if exists so_stock_short_check_adjust_ck;
alter table public.so_stock_short_check add constraint so_stock_short_check_adjust_ck check (adjust_number is null or source = 'count');
alter table public.so_stock_short_check drop constraint if exists so_stock_short_check_adjust_number_fkey;
alter table public.so_stock_short_check add constraint so_stock_short_check_adjust_number_fkey foreign key (adjust_number) references public.inv_adjust (adjust_number);
create index if not exists so_stock_short_check_adjust_number_idx on public.so_stock_short_check (adjust_number);
comment on column public.so_stock_short_check.adjust_number is 'nb-3(판정 1176) — Count & check 가 만든 조정 문서 번호(ADJ-…) · 세어 보니 장부가 맞아 조정이 없었으면 null · Mark checked(source manual)는 늘 null';
comment on column public.so_stock_short_check.source is 'manual = Mark checked(so_stock_short_confirm · 장부가 맞다는 확인만) · count = Count & check(so_stock_short_count · 세고 고침 · nb-3)';

-- ═══ ② 안 도우미 — 그 SKU × 창고의 지금 모양(칸 · 확인 안 된 줄 · 지문) ═══
create or replace function public.so_stock_short_count_state(p_product_id uuid, p_warehouse_id uuid) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare v_sku text; v_wh text; v_bins jsonb; v_shorts jsonb; v_layer numeric; v_ledger numeric;
begin
  select p.sku into v_sku from public.product p where p.id = p_product_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
  if v_sku is null or v_wh is null then raise exception 'Product or warehouse not found — nothing was read'; end if;
  -- 칸: 장부 행이 있는 칸 전부(0 이어도) · 조정 eval 과 같은 셈(장부 = ims_inv_balance · picked = inv_adjust_picked) · 옛 「칸 없음」 행('')은 보여 주기만
  select coalesce(jsonb_agg(jsonb_build_object(
           'bin', b.bin, 'bin_id', b.bin_id,
           'kind', case when b.bin = '' then 'no_bin' when b.bin = 'UNASSIGNED' then 'unassigned' else 'bin' end,
           'ledger', b.qty, 'picked', b.picked, 'shelf', b.qty - b.picked,
           'countable', b.countable, 'must_count', b.countable and b.qty < 0,
           'why_not', case when b.bin = '' then 'Old row without a bin — fixed separately' when not b.countable then 'This bin is switched off' end)
           order by (b.bin = ''), (b.bin = 'UNASSIGNED'), b.bin), '[]'::jsonb),
         coalesce(sum(b.qty), 0)
    into v_bins, v_ledger
    from (select x.bin, x.bin_id, x.qty, public.inv_adjust_picked(p_warehouse_id, x.bin_id, p_product_id) as picked, (x.bin <> '' and x.bin_id is not null and coalesce(x.bin_is_active, false)) as countable
            from public.ims_inv_balance_of(array[p_product_id], p_warehouse_id) x) b;
  -- 확인 안 된 「재고 없이 나갔다」 줄 — 오더(doc_number)별로 모은다 · 확인 기록의 열쇠가 (doc_number, sku, warehouse) 이므로 한 오더의 같은 SKU 두 줄은 한 줄(layers 2)
  select coalesce(jsonb_agg(jsonb_build_object('doc_number', q.doc_number, 'qty', q.qty, 'layers', q.layers, 'received_on', q.received_on, 'so_id', s.id, 'channel', s.channel)
           order by q.received_on, q.doc_number), '[]'::jsonb)
    into v_shorts
    from (select y.doc_number, sum(y.qty) as qty, count(*) as layers, min(y.received_on) as received_on
            from public.inv_layer y
           where y.origin_type = 'sale_shortfall' and y.sku = v_sku and y.warehouse = v_wh
             and not exists (select 1 from public.so_stock_short_check k where k.doc_number = y.doc_number and k.sku = y.sku and k.warehouse = y.warehouse)
           group by y.doc_number) q
    left join public.so s on s.so_number = q.doc_number;
  select coalesce(sum(v.remaining_qty), 0) into v_layer from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = v_sku and y.warehouse = v_wh;
  return jsonb_build_object('product_id', p_product_id, 'sku', v_sku, 'warehouse_id', p_warehouse_id, 'warehouse', v_wh,
    'bins', v_bins, 'shorts', v_shorts,
    'short_qty', (select coalesce(sum((x->>'qty')::numeric), 0) from jsonb_array_elements(v_shorts) x),
    'ledger_qty', v_ledger, 'layer_qty', v_layer, 'fill_room', greatest(v_layer - v_ledger, 0),               -- nb-1(판정 1170)의 「메울 수 있는 몫」 = 레이어 남은 수량 − 장부 수량(창고 단위)
    'seen', md5((select coalesce(string_agg(format('%s|%s|%s', x->>'bin', (x->>'ledger')::numeric, (x->>'picked')::numeric), ';' order by x->>'bin'), '') from jsonb_array_elements(v_bins) x)
                || '#' || (select coalesce(string_agg(format('%s|%s', x->>'doc_number', (x->>'qty')::numeric), ';' order by x->>'doc_number'), '') from jsonb_array_elements(v_shorts) x)));
end $$;
comment on function public.so_stock_short_count_state(uuid, uuid) is 'nb-3 안 도우미 — 그 SKU × 창고의 칸별 장부 · picked · 확인 안 된 「재고 없이 나갔다」 줄 · seen 지문 · 문 없음(직원이 못 부른다 — so_stock_short_count_view · so_stock_short_count 가 문을 지난 뒤 부른다)';
revoke all on function public.so_stock_short_count_state(uuid, uuid) from public, anon, authenticated;

-- ═══ ③ 읽기(R1) — 줄 하나를 열면 ═══
create or replace function public.so_stock_short_count_view(p_sku text, p_warehouse text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare v_pid uuid; v_name text; v_whid uuid;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- 첫 줄 문 = so_stock_short_list 와 같은 열쇠
  select p.id, p.name into v_pid, v_name from public.product p where p.sku = btrim(p_sku);
  if v_pid is null then raise exception 'Product % not found — nothing was read', coalesce(p_sku, '?'); end if;
  select w.id into v_whid from public.ref_warehouse w where w.name = btrim(p_warehouse);
  if v_whid is null then raise exception 'Warehouse % not found — nothing was read', coalesce(p_warehouse, '?'); end if;
  return public.so_stock_short_count_state(v_pid, v_whid)
      || jsonb_build_object('name', v_name, 'can_count', public.ims_can_adjust() and public.ims_can_warehouse(v_whid));   -- 판정 1176: 재고를 바꾸는 쪽 = stock_adjust + 그 창고 + 매니저 이상(ims_can_adjust 가 worker 를 막는다)
end $$;
comment on function public.so_stock_short_count_view(text, text) is 'nb-3 R1 — Action Centre 「Sold without stock」 줄 하나: 칸별 장부 · picked(조정 eval 과 같은 셈) · 확인 안 된 줄 전부 · seen · can_count · 문 = sales 보기 · 원가 값 없음(미리 보기 값은 so_stock_short_count p_commit false)';
revoke all on function public.so_stock_short_count_view(text, text) from public, anon;
grant execute on function public.so_stock_short_count_view(text, text) to authenticated;

-- ═══ ④ 쓰기(R2) — Count & check ═══
create or replace function public.so_stock_short_count(p_sku text, p_warehouse text, p_counts jsonb, p_seen text default null, p_note text default null, p_commit boolean default false) returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_staff uuid; v_pid uuid; v_sku text; v_wh public.ref_warehouse%rowtype; v_st jsonb; v_c jsonb; v_b public.ref_bin%rowtype; v_note text := nullif(btrim(p_note), '');
  v_in jsonb := '[]'::jsonb; v_qty numeric; v_ledger numeric; v_picked numeric; v_changes int := 0; v_miss text; v_docs text;
  v_adj_id uuid; v_adj_no text; v_lines jsonb := '[]'::jsonb; v_sum jsonb := jsonb_build_object('rejects', '[]'::jsonb, 'warnings', '[]'::jsonb); v_conf jsonb; v_checked jsonb := '[]'::jsonb; v_n int := 0;
begin
  v_staff := public.inv_adjust_require(null);                                                 -- ⭐ 첫 줄 문 — stock_adjust(admin · 열쇠를 켠 supervisor · manager · worker 는 못 한다 = 매니저 이상 · 판정 1176)
  select * into v_wh from public.ref_warehouse w where w.name = btrim(p_warehouse) and w.is_active;
  if not found then raise exception 'Warehouse % not found or inactive — nothing was saved', coalesce(p_warehouse, '?'); end if;
  perform public.inv_adjust_require(v_wh.id);                                                 -- ⭐ 둘째 줄 문 — 그 창고
  select p.id, p.sku into v_pid, v_sku from public.product p where p.sku = btrim(p_sku);
  if v_pid is null then raise exception 'Product % not found — nothing was saved', coalesce(p_sku, '?'); end if;
  if p_counts is null or jsonb_typeof(p_counts) <> 'array' or jsonb_array_length(p_counts) = 0 then
    raise exception 'Enter the counted quantity for at least one bin — nothing was saved';
  end if;
  -- 센 개수 — 칸은 이 창고의 활성 칸(같은 검사를 inv_adjust_line_set 이 다시 한다) · 장부 · picked 는 조정과 같은 도우미
  for v_c in select * from jsonb_array_elements(p_counts) loop
    if jsonb_typeof(v_c) <> 'object' then raise exception 'Each count must be an object with bin and qty — nothing was saved'; end if;
    if nullif(v_c->>'bin_id', '') is not null then select * into v_b from public.ref_bin b where b.id = (v_c->>'bin_id')::uuid;
    else select * into v_b from public.ref_bin b where b.warehouse_id = v_wh.id and b.name = btrim(v_c->>'bin'); end if;
    if not found or v_b.warehouse_id <> v_wh.id or not v_b.is_active or v_b.name = '' then
      raise exception 'Bin % is not an active bin at % — nothing was saved', coalesce(nullif(v_c->>'bin', ''), v_c->>'bin_id', '(no bin)'), v_wh.name;
    end if;
    if coalesce(v_c->>'qty', '') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then raise exception 'The counted quantity for bin % must be a number 0 or more — nothing was saved', v_b.name; end if;
    if exists (select 1 from jsonb_array_elements(v_in) x where x->>'bin_id' = v_b.id::text) then raise exception 'Bin % is counted twice — nothing was saved', v_b.name; end if;
    v_qty := (v_c->>'qty')::numeric;
    v_ledger := public.inv_adjust_ledger(v_wh.name, v_b.name, v_sku);
    v_picked := public.inv_adjust_picked(v_wh.id, v_b.id, v_pid);
    if v_qty <> v_ledger - v_picked then v_changes := v_changes + 1; end if;
    v_in := v_in || jsonb_build_object('bin_id', v_b.id, 'bin', v_b.name, 'qty', v_qty, 'ledger', v_ledger, 'picked', v_picked, 'delta', v_qty - (v_ledger - v_picked));
  end loop;
  v_st := public.so_stock_short_count_state(v_pid, v_wh.id);
  if jsonb_array_length(v_st->'shorts') = 0 then
    raise exception 'There is no unchecked sold-without-stock line for % at % — nothing to check — nothing was saved', v_sku, v_wh.name;
  end if;
  select string_agg(x->>'bin', ', ' order by x->>'bin') into v_miss from jsonb_array_elements(v_st->'bins') x
   where (x->>'must_count')::boolean and not exists (select 1 from jsonb_array_elements(v_in) i where i->>'bin_id' = x->>'bin_id');
  if v_miss is not null then raise exception 'Count bin % too — its ledger is below zero — nothing was saved', v_miss; end if;
  if p_commit and (p_seen is null or p_seen is distinct from v_st->>'seen') then
    raise exception 'Stock or the sold-without-stock lines for % at % changed since you looked — reload and count again — nothing was saved', v_sku, v_wh.name;
  end if;
  select string_agg(x->>'doc_number', ', ' order by x->>'doc_number') into v_docs from jsonb_array_elements(v_st->'shorts') x;

  if v_changes > 0 then
    begin                                                                                     -- 안쪽 블록 — 미리 보기는 끝에서 통째로 되돌린다(NB3PV)
      if p_commit then
        v_conf := public.inv_adjust_create(v_wh.id, left('Count & check — ' || v_sku || ' — ' || v_docs || coalesce(' — ' || v_note, ''), 500), null);
        v_adj_id := (v_conf->>'id')::uuid;  v_adj_no := v_conf->>'adjust_number';
      else                                                                                    -- 미리 보기의 머리 — 번호 시퀀스를 쓰지 않는 임시 행(되돌아간다) · 줄 · 셈은 아래 같은 창구
        insert into public.inv_adjust (adjust_number, warehouse_id, warehouse, note, created_by, updated_by)
        values ('PREVIEW-' || gen_random_uuid()::text, v_wh.id, v_wh.name, 'Count & check preview', v_staff, v_staff) returning id into v_adj_id;
      end if;
      for v_c in select * from jsonb_array_elements(v_in) loop
        perform public.inv_adjust_line_set(v_adj_id, jsonb_build_object('product_id', v_pid, 'bin_id', v_c->>'bin_id', 'mode', 'set', 'qty', v_c->>'qty', 'reason', 'count'));
      end loop;
      if p_commit and public.so_stock_short_count_state(v_pid, v_wh.id)->>'seen' is distinct from p_seen then   -- 줄이 본 값을 굳힌 뒤 한 번 더 — 그 뒤의 바뀜은 inv_adjust_confirm 의 eval 이 잡는다
        raise exception 'Stock or the sold-without-stock lines for % at % changed since you looked — reload and count again — nothing was saved', v_sku, v_wh.name;
      end if;
      select coalesce(jsonb_agg(to_jsonb(e) - 'line_id' order by e.line_no), '[]'::jsonb) into v_lines from public.inv_adjust_eval(v_adj_id) e;
      v_sum := public.inv_adjust_summary(v_lines);
      if not p_commit then raise exception using errcode = 'NB3PV', message = 'preview — rolled back'; end if;
      v_conf := public.inv_adjust_confirm(v_adj_id);
    exception when sqlstate 'NB3PV' then
      v_adj_id := null;
    end;
  else                                                                                        -- 세어 보니 장부와 같다 — 조정 없음 · 줄은 센 값 그대로
    select coalesce(jsonb_agg(jsonb_build_object('bin_id', x->'bin_id', 'bin', x->'bin', 'mode', 'set', 'qty_input', x->'qty', 'ledger', x->'ledger', 'picked', x->'picked',
                                                 'basis', (x->>'ledger')::numeric - (x->>'picked')::numeric, 'delta', 0, 'result', x->'ledger', 'cost_branch', 'none', 'fill_qty', 0, 'layer_qty', 0, 'rejects', '[]'::jsonb)
                              order by o), '[]'::jsonb) into v_lines from jsonb_array_elements(v_in) with ordinality t(x, o);
  end if;

  if p_commit then
    for v_c in select * from jsonb_array_elements(v_st->'shorts') loop
      insert into public.so_stock_short_check (doc_number, sku, warehouse, checked_by, note, source, adjust_number, updated_by)
      values (v_c->>'doc_number', v_sku, v_wh.name, v_staff, coalesce(v_note, case when v_adj_no is null then 'counted — matches' else 'counted — ' || v_adj_no end), 'count', v_adj_no, v_staff);
      v_n := v_n + 1;  v_checked := v_checked || jsonb_build_array(v_c->>'doc_number');
    end loop;
  end if;
  return jsonb_build_object('committed', p_commit, 'sku', v_sku, 'warehouse', v_wh.name, 'warehouse_id', v_wh.id,
    'action', case when v_changes > 0 then 'adjust_and_check' else 'check_only' end,
    'adjust_number', v_adj_no, 'adjust_id', case when p_commit then v_adj_id end,
    'lines', v_lines, 'rejects', v_sum->'rejects', 'warnings', v_sum->'warnings',
    'can_commit', jsonb_array_length(v_sum->'rejects') = 0,
    'shorts', v_st->'shorts', 'checked', v_checked, 'checked_count', v_n,
    'no_bin_qty', (select coalesce(sum((x->>'ledger')::numeric), 0) from jsonb_array_elements(v_st->'bins') x where x->>'kind' = 'no_bin'),
    'seen', v_st->>'seen');
end $$;
comment on function public.so_stock_short_count(text, text, jsonb, text, text, boolean) is 'nb-3 R2(판정 1176) — Count & check: 칸마다 센 개수(mode set · reason count)로 조정 문서를 만들고 확정 + 그 SKU × 창고의 확인 안 된 「재고 없이 나갔다」 줄 전부를 확인함으로 — 한 트랜잭션 · 바꿀 줄이 0 이면 확인만 · p_commit false = 미리 보기(아무것도 안 남는다) · 문 = stock_adjust + 그 창고 + 매니저 이상(inv_adjust_require) · 조정은 inv_adjust_create · _line_set · _eval · _confirm 을 그대로 부른다';
revoke all on function public.so_stock_short_count(text, text, jsonb, text, text, boolean) from public, anon;
grant execute on function public.so_stock_short_count(text, text, jsonb, text, text, boolean) to authenticated;

-- ═══ ⑤ so_stock_short_list 재발행 — 줄에 adjust_number · check_source(칸 더하기만) ═══
CREATE OR REPLACE FUNCTION public.so_stock_short_list(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f          jsonb := coalesce(p_filters, '{}'::jsonb);
  v_wh       text;
  v_unc_only boolean := coalesce((f->>'unchecked_only')::boolean, false);
  v_to       date := coalesce(nullif(f->>'to', '')::date, public.ims_today());
  v_from     date := coalesce(nullif(f->>'from', '')::date, public.ims_today() - 30);
  v_limit    int  := least(greatest(coalesce((f->>'limit')::int, 200), 1), 500);
  v_offset   int  := greatest(coalesce((f->>'offset')::int, 0), 0);
  v_open     jsonb;  v_open_n int;
  v_done     jsonb;  v_done_n int;
  v_unknown  int;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Action Centre 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  if nullif(f->>'warehouse_id', '') is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'warehouse_id')::uuid;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  elsif nullif(f->>'warehouse', '') is not null then
    v_wh := f->>'warehouse';
  end if;
  if v_from > v_to then raise exception 'from % is after to %', v_from, v_to; end if;

  with rows as (
    select y.id as layer_id, y.doc_number, y.sku, y.warehouse, y.qty, y.received_on, y.cost_source, case when (select public.ims_can_view_cost()) then y.unit_cost end as unit_cost, (y.cost_source = 'unknown') as unknown,   -- rls-3b(판정 580): 원가 값만 열쇠로 · 목록 · 개수 · cost_source 는 그대로
           s.id as so_id, s.channel, s.status as so_status, s.customer_id, c.name as customer_name,
           k.id as check_id, k.checked_at, k.checked_by, ks.name as checked_by_name, k.note, k.adjust_number, k.source as check_source   -- nb-3(R3): 만든 조정 번호(없으면 null) · manual = Mark checked · count = Count & check
    from public.inv_layer y
    left join public.so s on s.so_number = y.doc_number
    left join public.customer c on c.id = s.customer_id
    left join public.so_stock_short_check k on k.doc_number = y.doc_number and k.sku = y.sku and k.warehouse = y.warehouse
    left join public.ims_staff ks on ks.id = k.checked_by
    where y.origin_type = 'sale_shortfall' and (v_wh is null or y.warehouse = v_wh)
  )
  select coalesce((select jsonb_agg(to_jsonb(r) order by r.received_on desc, r.doc_number, r.sku) from rows r where r.check_id is null), '[]'::jsonb),
         (select count(*) from rows r where r.check_id is null),
         (select count(*) from rows r where r.check_id is null and r.unknown),
         case when v_unc_only then '[]'::jsonb else
           coalesce((select jsonb_agg(to_jsonb(r) order by r.checked_at desc, r.doc_number, r.sku)
                     from (select * from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to
                           order by r.checked_at desc, r.doc_number, r.sku limit v_limit offset v_offset) r), '[]'::jsonb) end,
         case when v_unc_only then 0 else (select count(*) from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to) end
    into v_open, v_open_n, v_unknown, v_done, v_done_n;

  return jsonb_build_object(
    'warehouse', v_wh, 'from', v_from, 'to', v_to, 'limit', v_limit, 'offset', v_offset,
    'unchecked_count', v_open_n, 'unchecked_unknown_cost', v_unknown, 'checked_in_range', v_done_n,
    'unchecked', v_open, 'checked', v_done);
end;

$function$
;
