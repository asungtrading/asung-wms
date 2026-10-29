-- pos-reopen-1 (2026-10-28 · 판정 863 줄기 · 지시서 ~/asung/prompts/pos-reopen-1.md · 이견 1 ~ 9) — Reopen 한 POS 판매에서 줄 ✕ · 줄 전부 지우기가 so_reserve FK 로 막히던 것
--   실물(Caleb 화면 · 2026-10-28 21:28 · 테스트 DB · pos v1.16a): SO-25237(POS · confirmed) → Payments Cash 50 Cancel(so_pos_payment_cancel OK) → Reopen to change items(so_pos_reopen OK · draft)
--     → ORS11009 × 1 줄 ✕(so_line_remove) → 「update or delete on table "so_line" violates foreign key constraint "so_reserve_so_line_id_fkey" on table "so_reserve"」(23503)
--   원인(코드 + rollback 재현 · 결제와 무관): so_pos_reopen 은 5-f 대로 예약을 지우지 않고 released_at 을 찍어 남긴다(so_unconfirm 과 같은 꼴 · 맞다)
--     · so_line_remove · so_lines_clear 는 「열린 예약(released_at is null)」만 거부하고 줄을 지운다 → 풀린 이력 행이 so_reserve_so_line_id_fkey(on delete no action)에 걸려 23503
--     · 문지기 글이 「열린 것만 막는다」인데 FK 는 「풀린 것도 막는다」 — 둘이 어긋난 자리 · warehouse 길(so_unconfirm → 줄 ✕)도 같은 벽(테스트 DB 에 warehouse draft 3 · 예약 이력 7 행)
--     · 같은 판매에서 수량 고치기(so_line_update) · 다시 Confirm(so_pos_confirm → so_allocate_all 이 열린 예약 없는 줄에 새 행) 은 된다 · Delete draft(so_delete) 는 FK 앞에서 읽을 수 있는 글로 거부(이력 있음 → so_cancel)
--     · 남은 풀린 행은 가용을 깎지 않는다 — inv_available_base · so_lines_available · so_allocate_all 이 전부 released_at is null 만 센다(테스트 DB POS draft 12 · 130 행 · 열린 것 0)
--   안(나) [Claude Code 판단]: 줄을 지우는 창구 둘(so_line_remove · so_lines_clear)이 그 줄의 **풀린** 예약 행을 먼저 지우고 줄을 지운다 — 열린 예약 거부는 그대로(마지막 방어 = FK no action 그대로)
--     · 까닭: 줄이 없어지면 그 줄의 예약 이력은 붙을 데가 없다(5-f 「왜 오래 걸렸나」는 남는 줄에서 답한다) · POS 와 warehouse 길을 한 자리에서 고친다 · 이미 남은 행(POS draft 12 · 130 행)은 그대로 두고 줄을 지울 때 함께 간다(일괄 정리 없음)
--     · 기각(가) so_pos_reopen 이 예약을 지운다: 5-f(지우지 않고 released_at)를 뒤집고 warehouse 길은 그대로 막힌다 · 기각(다) FK cascade: 살아 있는 예약까지 소리 없이 지운다(so_delete 가 이력 있음을 거부하는 뜻이 사라진다)
--   ① so_line_remove 재발행(원본 20261005195104:674 ~ 711 바이트 + 더한 줄 4) — 열린 예약 거부 뒤 · 그 줄 + 구성품 줄의 풀린 행 delete · row_count → 반환 reserve_history_removed
--   ② so_lines_clear 재발행(원본 20261020123910:1180 ~ 1231 바이트 + 더한 줄 4 · create → create or replace) — commit 갈래에서 오더 전 줄의 풀린 행 delete → 반환 reserve_history_removed
--   ③ so_reserve.so_line_id 칸 주석에 이 판정을 덧붙인다(「예약이 붙은 줄은 지우지 않는다」 → 「열린 예약이 붙은 줄은 지우지 않는다 · 풀린 이력은 줄과 함께 간다」)
--   ⚠️ 무접촉: so_pos_reopen · so_delete · so_pos_confirm · so_allocate_all · so_unconfirm · so_line_update · so_cancel(끝 do 블록이 prosrc md5 를 단언) · FK so_reserve_so_line_id_fkey 그대로(no action) · 표 · 칸 · 정책 · 트리거 변화 없음 · 가용 식 무변
--   ⚠️ shop_stock_queue 트리거(so_reserve_shop_stock_d)가 풀린 행 delete 에도 돈다 — 그 제품에 켜진 listing 이 있으면 큐 한 줄(다시 셈 · 값은 같다 · 해가 없다)
--   컷오버 날 지우기(cutover-delete): 새 표 · 시퀀스 · 칸 없음 → 지우는 순서 변화 없음(함수만)
--   원본 md5(DB prosrc · 2026-10-28 테스트 DB · 마지막 정의 파일 본문과 일치 확인): so_line_remove 17cc8717cffcbb04c9f69e69d95ec573 · so_lines_clear a7be7e796330210bb738d378937c95af
--     무접촉: so_pos_reopen a4cbbc54bab27e288795bb997f62aef5 · so_delete a98f03969aba10e19fa0972897a87505 · so_pos_confirm 2a20a8abad4d4a5dcb509d64a15b77b4 · so_allocate_all c3298ba7a9b1c06da0fc917b0c1b6533 · so_unconfirm b9b48b92b7445a84abcdb5aa1b254b28 · so_line_update d0e0f54f79b5c55334e5ea0f5f4b83b2 · so_cancel 818b2dd98a8c6159af4701d1de11e1fb
--   검증: supabase/tests/pos_reopen_1.sql(시험 적용 begin → rollback · 가짜 손님 · 제품 둘 · 직원 셋 · POS 판매 넷 · 재현(23503) → 고침 뒤 ✕ OK → 수량 → 다시 Confirm → 미리 보기 · so_lines_clear · so_delete · warehouse so_unconfirm 길 · 가용 전후 · 무접촉 · 시퀀스 되돌림)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029014000_pos_reopen_1.sql && supabase migration repair --status applied 20261029014000 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ 0) 기대는 마지막 정의인가 — 다르면 멈춘다(재발행 둘의 원본 · 무접촉 일곱) ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') is distinct from '17cc8717cffcbb04c9f69e69d95ec573' then v_bad := v_bad || ' so_line_remove'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') is distinct from 'a7be7e796330210bb738d378937c95af' then v_bad := v_bad || ' so_lines_clear'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') is distinct from 'a4cbbc54bab27e288795bb997f62aef5' then v_bad := v_bad || ' so_pos_reopen'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') is distinct from 'a98f03969aba10e19fa0972897a87505' then v_bad := v_bad || ' so_delete'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_allocate_all') is distinct from 'c3298ba7a9b1c06da0fc917b0c1b6533' then v_bad := v_bad || ' so_allocate_all'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_reserve_so_line_id_fkey' and conrelid = 'public.so_reserve'::regclass) is distinct from 'FOREIGN KEY (so_line_id) REFERENCES so_line(id)' then v_bad := v_bad || ' so_reserve_so_line_id_fkey'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM863', message = format('STOP - pos-reopen-1 expects the last definitions as of 2026-10-28; these differ:%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ ① so_line_remove 재발행 — 원본 20261005195104_asm_2a_combo_lines.sql:674 ~ 711 바이트 + 더한 줄(pos-reopen-1 표시) ═══
create or replace function public.so_line_remove(p_line_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_n      int;
  v_left   int;
  v_kids   int := 0;                                            -- asm-2a(묶음 3): 콤보 줄을 지우면 구성품 줄도 · 구성품 줄은 따로 못 지운다
  v_hist   int := 0;                                            -- pos-reopen-1: 이 줄(+ 구성품 줄)의 풀린 예약 이력 행 — 줄과 함께 지운다(열린 예약은 아래에서 거부)
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was deleted';
  end if;
  v_so := public.so_require_draft(v_line.so_id, 'deleted');
  if v_line.combo_line_id is not null then
    raise exception 'Line % is a component of combo % (line %) — remove the combo line instead — nothing was deleted', v_line.line_no,
      (select c.sku from public.so_line c where c.id = v_line.combo_line_id), (select c.line_no from public.so_line c where c.id = v_line.combo_line_id);
  end if;
  if exists (select 1 from public.so_reserve r where r.released_at is null and (r.so_line_id = p_line_id or r.so_line_id in (select c.id from public.so_line c where c.combo_line_id = p_line_id))) then
    raise exception 'Line % of % has an open allocation — release it first — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;
  delete from public.so_reserve res where res.released_at is not null and (res.so_line_id = p_line_id or res.so_line_id in (select c.id from public.so_line c where c.combo_line_id = p_line_id));   -- pos-reopen-1: 풀린 이력은 줄과 함께(Reopen · Unconfirm 뒤 ✕ 가 so_reserve_so_line_id_fkey 23503 으로 막히던 자리 · FK 는 그대로)
  get diagnostics v_hist = row_count;

  delete from public.so_line where combo_line_id = p_line_id;                                                                 -- asm-2a: 구성품 줄 먼저(FK 도 cascade 지만 수를 센다)
  get diagnostics v_kids = row_count;
  delete from public.so_line where id = p_line_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not deleted — it may have been removed by someone else just now — nothing was deleted', v_line.line_no, v_so.so_number;
  end if;
  select count(*) into v_left from public.so_line where so_id = v_so.id;
  return jsonb_build_object('so_number', v_so.so_number, 'removed_line_no', v_line.line_no, 'lines_left', v_left, 'removed_components', v_kids, 'reserve_history_removed', v_hist);   -- pos-reopen-1: 열쇠 하나 더
end;
$$;

-- ═══ ② so_lines_clear 재발행 — 원본 20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql:1180 ~ 1231 바이트(create → create or replace) + 더한 줄(pos-reopen-1 표시) ═══
create or replace function public.so_lines_clear(p_so_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  v_lines   int;  v_combo int;  v_comp int;  v_charges int;  v_coupon boolean;
  v_n       int := 0;  v_k int := 0;
  v_hist    int := 0;                                                                                              -- pos-reopen-1: 오더 전 줄의 풀린 예약 이력 행 — 줄과 함께 지운다(열린 예약은 아래에서 거부)
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;                                                -- 오더 행 잠금(so_require_draft 는 stable · 잠그지 않는다)
  if not found then
    raise exception 'Order not found — nothing was deleted';
  end if;
  if v_so.status <> 'draft' then                                                                                   -- 판정 541
    raise exception 'Order % is not a draft (status %) — unconfirm it first (a supervisor can), then clear the lines — nothing was deleted', v_so.so_number, v_so.status;
  end if;
  if v_so.intake = 'shopify' then
    raise exception 'Order % came from Shopify — its lines cannot be cleared all at once (remove lines one by one, or cancel the order) — nothing was deleted', v_so.so_number;
  end if;
  if exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id and r.released_at is null) then
    raise exception 'Order % has an open allocation — release it first — nothing was deleted', v_so.so_number;
  end if;

  select count(*) filter (where combo_line_id is null), count(*) filter (where combo_line_id is null and exists (select 1 from public.so_line c where c.combo_line_id = l.id)), count(*) filter (where combo_line_id is not null)
    into v_lines, v_combo, v_comp
  from public.so_line l where l.so_id = p_so_id;
  select count(*) into v_charges from public.so_charge c where c.so_id = p_so_id;
  v_coupon := v_so.coupon_id is not null;

  if not p_commit then
    return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
                              'lines', v_lines, 'combo_lines', v_combo, 'component_lines', v_comp, 'charges_left', v_charges, 'coupon_left', v_coupon);
  end if;

  delete from public.so_reserve res where res.released_at is not null and res.so_line_id in (select l.id from public.so_line l where l.so_id = p_so_id);   -- pos-reopen-1: 풀린 이력은 줄과 함께(so_line_remove 와 같은 자리 · FK 는 그대로)
  get diagnostics v_hist = row_count;
  delete from public.so_line where so_id = p_so_id and combo_line_id is not null;                                   -- 구성품 줄 먼저(so_line_remove 와 같은 순서 · FK 도 cascade 지만 수를 센다)
  get diagnostics v_k = row_count;
  delete from public.so_line where so_id = p_so_id;
  get diagnostics v_n = row_count;
  if v_n <> v_lines or v_k <> v_comp then
    raise exception 'Order % lines changed while clearing (expected % + % · deleted % + %) — nothing was deleted', v_so.so_number, v_lines, v_comp, v_n, v_k;
  end if;
  v_so := public.so_order_discount_apply(p_so_id, v_staff);                                                        -- 판정 308: order_discount_* 는 그 한 곳만 쓴다(줄이 0 → 문턱 밖 · 쿠폰 id 는 남는다)

  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'committed', true,
                            'lines', v_n, 'combo_lines', v_combo, 'component_lines', v_k, 'charges_left', v_charges, 'coupon_left', v_so.coupon_id is not null,
                            'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'source', v_so.order_discount_source, 'deal_id', v_so.order_discount_deal_id),
                            'reserve_history_removed', v_hist);   -- pos-reopen-1: 열쇠 하나 더
end;
$$;

-- ═══ ③ so_reserve.so_line_id 칸 주석 — 판정을 덧붙인다(원문 20260923133042 그대로 + pos-reopen-1 줄) ═══
comment on column public.so_reserve.so_line_id is 'FK → so_line(id) · NOT NULL · ⭐ on delete no action — 이력이다 · 예약이 붙은 줄은 확정된 적이 있으므로 지우지 않고 cancelled 로(검토 이견 1 · po_receipt_line→po_line 과 같은 결) · 인덱스 so_reserve_so_line_idx · [2026-10-28 pos-reopen-1] 「지우지 않는다」는 열린 예약(released_at is null)에만 — 풀린 이력 행은 줄을 지우는 창구(so_line_remove · so_lines_clear)가 줄과 함께 지운다(줄이 없으면 이력이 붙을 데가 없다 · Reopen · Unconfirm 뒤 줄 고치기가 FK 23503 으로 막히던 것 · FK 는 그대로 마지막 방어) · so_delete 는 이력이 있으면 여전히 거부(so_cancel 로)';

-- ═══ 끝) 착지 — 재발행 둘은 바뀌었고 · 무접촉 일곱은 그대로 · FK · acl 그대로 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') = '17cc8717cffcbb04c9f69e69d95ec573' then v_bad := v_bad || ' so_line_remove(unchanged)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') = 'a7be7e796330210bb738d378937c95af' then v_bad := v_bad || ' so_lines_clear(unchanged)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_remove', 'so_lines_clear')) <> 2 then v_bad := v_bad || ' (count of the two functions is not 2)'; end if;
  if not (select bool_and(prosecdef and provolatile = 'v') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_line_remove', 'so_lines_clear')) then v_bad := v_bad || ' (definer/volatile)'; end if;
  if not has_function_privilege('authenticated', 'public.so_line_remove(uuid)', 'execute') or has_function_privilege('anon', 'public.so_line_remove(uuid)', 'execute') then v_bad := v_bad || ' so_line_remove(acl)'; end if;
  if not has_function_privilege('authenticated', 'public.so_lines_clear(uuid, boolean)', 'execute') or has_function_privilege('anon', 'public.so_lines_clear(uuid, boolean)', 'execute') then v_bad := v_bad || ' so_lines_clear(acl)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') is distinct from 'a4cbbc54bab27e288795bb997f62aef5' then v_bad := v_bad || ' so_pos_reopen'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') is distinct from 'a98f03969aba10e19fa0972897a87505' then v_bad := v_bad || ' so_delete'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') is distinct from '2a20a8abad4d4a5dcb509d64a15b77b4' then v_bad := v_bad || ' so_pos_confirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_allocate_all') is distinct from 'c3298ba7a9b1c06da0fc917b0c1b6533' then v_bad := v_bad || ' so_allocate_all'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') is distinct from 'b9b48b92b7445a84abcdb5aa1b254b28' then v_bad := v_bad || ' so_unconfirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_update') is distinct from 'd0e0f54f79b5c55334e5ea0f5f4b83b2' then v_bad := v_bad || ' so_line_update'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') is distinct from '818b2dd98a8c6159af4701d1de11e1fb' then v_bad := v_bad || ' so_cancel'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'so_reserve_so_line_id_fkey' and conrelid = 'public.so_reserve'::regclass) is distinct from 'FOREIGN KEY (so_line_id) REFERENCES so_line(id)' then v_bad := v_bad || ' so_reserve_so_line_id_fkey'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_reserve'::regclass and not tgisinternal) <> 5 then v_bad := v_bad || ' (so_reserve triggers <> 5)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM863', message = format('STOP - pos-reopen-1 landing check failed:%s', v_bad); end if;
end $$;
