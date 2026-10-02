-- tf-paste-1 — 트랜스퍼 붙여 넣기 창구 inv_transfer_lines_paste (2026-10-02 UTC · 판정 233(= 판정 171 의 실행) · tf-paste 묶음 1 ~ 8 · so-module §27 · §38 거리)
--   판정 233  트랜스퍼 붙여 넣기는 DB 창구를 새로 만든다 — SO · PO 와 같은 모양 · 미리 보기 → 한 트랜잭션으로 전부 또는 하나도 · 화면(tf-paste-2)은 이 창구를 부른다 · 기각 (가) 화면이 줄마다 inv_transfer_line_set(반쯤 들어간다)
--   묶음 1    모양은 po_lines_paste(마지막 정의 20260918000000:198) — [{sku, qty}] · 미리 보기와 넣기가 같은 모양 · 500 줄 · 넘으면 판정 too_many(예외 아님)
--   묶음 2    열쇠는 우리 SKU — 앞뒤 공백(비분리 포함)만 자른다 · 못 찾으면 대소문자 무시로 한 번 더(case_fixed) · 바코드 안 받는다
--   묶음 3    판정 여섯 — bad_qty → not_found → inactive → duplicate(앞줄 번호 · 합치지 않는다) → exists(그 줄 번호 · 「change that line instead」) → ok · 넣을 때는 ok 만 · 한 트랜잭션
--   묶음 4    수량은 그 상품의 단위(세트면 세트 단위) · 계수는 상품에서 굳힌다 — 넣기는 inv_transfer_line_set 을 줄마다 부른다(규칙 한 곳 · 같은 칸 · 같은 문장 · 사이에 누가 같은 상품을 넣었으면 그 raise 가 전체를 되돌린다 = 원자성)
--             대가: ok 줄마다 문서 행 잠금 · inv_transfer_require · 상품 조회가 되풀이된다(500 줄이면 500 번 · 전부 싼 것)
--   묶음 5    출발 창고 가용보다 많이 붙이면 알리기만 — ok 인 채 available_ea · short_by · summary.short · 막지 않는다 · 확정(inv_transfer_confirm)이 inv_transfer_shortage 로 따로 거부한다(transfer_1a:250 ~ 253 확인)
--             가용 = so_available_many(stock pid = 세트의 부모, 출발 창고) — inv_transfer_shortage 와 같은 식(잔고 − 판매 할당 − 확정·at_wms·picking 트랜스퍼 줄 · 이 초안의 줄은 안 뺀다) ⇒ short_by 는 stock pid 별 「이 초안의 기존 줄 + 붙인 ok 줄」 EA 합 − 가용 · 그 stock pid 의 ok 줄 전부에 같은 값
--   묶음 6    초안에서만 · 첫 줄 문 inv_transfer_require(from, to)(미리 보기도 — 「미리 보기는 되는데 저장이 안 되지」를 피한다 · PO 와 같다)
--   무접촉    기존 트랜스퍼 함수 열둘 · 화면(transfers.html 「Paste lines」 = tf-paste-2)
--   반환      { transfer_id, transfer_number, committed, summary{ total, ok, not_found, inactive, duplicate, exists, bad_qty, short, inserted, too_many, limit, message },
--              lines[{ n, input_sku, input_qty, verdict, product_id, sku, product_name, product_active, pack_factor, qty_ea, available_ea, short_by, line_no, line_id, inserted, message }] }
--   막기 문장(예외): Transfer not found · (inv_transfer_require 의 둘) · Transfer % is % — only a draft can be edited (unconfirm it first) · p_lines must be a JSON array of {sku, qty}
--   판정 code(verdict): ok · not_found · inactive · duplicate · exists · bad_qty · summary.too_many
--   검증: ~/asung/prompts/tf-paste-1-verify.sql (시험 적용 장치 · 테스트 DB · rollback · inv_transfer_number_seq setval) · ⚠️ 운영 무접촉(컷오버 전 운영 적용 금지 · ims-principles)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다
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

-- ═══ inv_transfer_lines_paste — 붙여 넣기(미리 보기 / 넣기 · 같은 모양) ═══════════════════════════════════════════════════════
create function public.inv_transfer_lines_paste(p_transfer_id uuid, p_lines jsonb, p_commit boolean default false) returns jsonb
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
          from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = p_transfer_id group by 1) s;

  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(p_lines) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_pf := null; v_spid := null;
    v_verdict := null; v_msgs := '{}'; v_line_no := null; v_line_id := null; v_inserted := false; v_dup_of := null; v_exists_no := null;

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

    -- 판정 여섯(묶음 3 · 이 순서)
    if v_qty is null or v_qty <= 0 then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    elsif v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    elsif v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    elsif not v_pactive then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added (inv_transfer_line_set refuses it too)');
    else
      v_dup_of := (select v_seen_n[i] from generate_subscripts(v_seen_ids, 1) i where v_seen_ids[i] = v_pid limit 1);
      if v_dup_of is not null then
        v_verdict := 'duplicate'; v_msgs := array_append(v_msgs, format('duplicate_of_paste_line_%s — fix the source and paste again', v_dup_of));
      else
        v_seen_ids := array_append(v_seen_ids, v_pid); v_seen_n := array_append(v_seen_n, r.n);
        select l.line_no into v_exists_no from public.inv_transfer_line l where l.transfer_id = p_transfer_id and l.product_id = v_pid order by l.line_no limit 1;
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
      v_add := v_add || jsonb_build_object(v_spid::text, coalesce((v_add->>(v_spid::text))::numeric, 0) + v_qty * v_pf);
      if not (v_spid = any(v_pids)) then v_pids := array_append(v_pids, v_spid); end if;
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
      'available_ea', null, 'short_by', null,
      'line_no', v_line_no, 'line_id', v_line_id, 'inserted', v_inserted,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 묶음 5 — 재고 알림(ok 줄만 · stock pid 별 「기존 + 붙인」 EA 와 가용을 견준다 · 막지 않는다)
  for e in select x from jsonb_array_elements(v_rows) x loop
    if e->>'verdict' = 'ok' then
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
revoke all on function public.inv_transfer_lines_paste(uuid, jsonb, boolean) from public, anon;
grant execute on function public.inv_transfer_lines_paste(uuid, jsonb, boolean) to authenticated;
comment on function public.inv_transfer_lines_paste(uuid, jsonb, boolean) is
  '⭐ 트랜스퍼 붙여 넣기(tf-paste-1 · 판정 233 = 판정 171 의 실행 · 묶음 1 ~ 6) — definer · 첫 줄 inv_transfer_require(from, to)(미리 보기도) · 초안만 · p_lines [{sku, qty}] 최대 500(넘으면 summary.too_many · 예외 아님) · 판정 여섯 bad_qty → not_found(case_fixed) → inactive → duplicate(앞줄) → exists(그 줄 · inv_transfer_line_set 으로 고쳐라) → ok · p_commit true 는 ok 만 inv_transfer_line_set 으로 줄마다 넣는다(규칙 한 곳 · 사이에 누가 같은 상품을 넣었으면 그 raise 가 전부 되돌린다) · 세트는 세트 단위 · 계수는 상품에서 · 재고는 알리기만 — stock pid(세트의 부모) 별 「이 초안의 기존 줄 + 붙인 ok 줄」 EA 가 so_available_many(출발 창고) 가용을 넘으면 그 줄들에 available_ea · short_by · summary.short(확정은 inv_transfer_shortage 로 따로 거부) · 반환 모양은 po_lines_paste 를 따른다';
