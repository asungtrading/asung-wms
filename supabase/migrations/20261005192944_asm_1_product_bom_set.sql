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

-- ─────────────────────────────────────────────────────────────
-- 콤보 정의 만들기 · 고치기 창구 — product_bom_set (Asung-IMS · asm-1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §44 — 판정 244(2026-10-05 Caleb 「코보, 세트는 미리 묶어 팔지 않아. 주문이 오면 그때 구성품을 꺼내 묶어 보내」 · 번들 · 콤보는 팔 때 구성품을 바로 뺀다 · IMS 에 조립 문서 없음)
--                      · asm 묶음 1 ~ 8(이 파일은 묶음 1 의 DB 쪽 · 오더 길 = asm-2 · 화면 = asm-3) · 판정 142(콤보 만들기 · 고치기는 조립 · 번들 차수) · 판정 131 · 132(병행 기간 양쪽에서 만든다 · IMS 값이 이긴다)
--   실물(asm-0 · 2026-10-05 테스트 DB): product_bom 콤보 15 · 줄 65 · 전부 source cin7 · is_active true · 닫힌 표(prod-2 20261001123000: 정책 select 만 · authenticated insert/update/delete 회수) · 본문에 product_bom 을 쓰는 함수 0
--   든 것: 창구 하나 product_bom_set(부모 SKU · 구성품 전체 목록 · 화면이 본 옛 목록 · p_commit · p_ack) — definer · 문 ims_require_write('master') · product_update 와 같은 두 번 부르기(미리 보기 → 저장 · blocks · warnings · unacked)
--     · p_lines 는 그 콤보의 구성품 **전체**(줄 op 가 아니다) · 빈 목록 = 콤보 해제(줄을 끈다 · 지우지 않는다) · 옛 줄과 견줘 더하기 · 수량 바꾸기 · 끄기 · 되살리기 · 손댄 줄은 source manual
--   막기(code): parent_unknown · parent_inactive · parent_is_set · parent_is_component · lines_invalid · component_unknown · component_inactive · component_is_parent · component_is_combo · component_duplicate_in_call · quantity_invalid · component_single · old_missing · changed_elsewhere · no_change
--   알리기(ack): component_is_set(세트를 구성품으로 — 오더 길이 낱개로 접는다) · open_orders(열린 오더에 이 콤보) · parent_stock(부모 장부 ≠ 0 · 판정 244) · cin7_combo(Cin7 에서 온 콤보를 고친다 — Cin7 에서도 바꾸세요 · 판정 131)
--   ⚠️ 표 · 정책 · 권한 무접촉(닫힌 채) · 뷰 없음(products.html 은 product_bom 을 직접 읽는다 · select 정책 그대로) · 부분 유니크 인덱스 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
--   ⬜ 판단(보고에 이유): 부모가 세트면 막는다 · 구성품이 세트면 그대로 두고 알린다 · 구성품 하나뿐이면 막는다(정본 「2 개 이상」) · Cin7 줄을 고치면 그 줄 source 를 manual 로(product_update 의 supplier_off 선례) · p_old 는 「sku|수량」 정렬 글자열로 견준다
-- ─────────────────────────────────────────────────────────────

create function public.product_bom_set(p_parent_sku text, p_lines jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_par      public.product%rowtype;
  v_comp     public.product%rowtype;
  v_key      text;
  v_e        jsonb;
  v_sku      text;
  v_qtxt     text;
  v_qty      numeric;
  v_seen     uuid[] := '{}';
  v_new      jsonb := '[]'::jsonb;            -- 검사를 지난 줄 [{component_id, sku, qty}]
  v_n        int := 0;
  v_cur_txt  text;                             -- 지금 켜진 줄 「sku|수량,…」(sku 순)
  v_old_txt  text;                             -- p_old 를 같은 모양으로
  v_new_txt  text;
  v_cur_n    int := 0;
  v_cin7_n   int := 0;
  v_cnt      bigint;
  v_stock    numeric;
  v_r        record;
  v_added    int := 0;  v_changed int := 0;  v_removed int := 0;  v_kept int := 0;
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_update 와 같다)
  v_staff := public.so_current_staff();
  v_key := 'combo:' || coalesce(trim(p_parent_sku), '');

  -- ① 부모
  if nullif(trim(p_parent_sku), '') is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', p_parent_sku, 'code', 'parent_unknown', 'message', 'Combo SKU is missing — nothing was saved');
  else
    select * into v_par from public.product p where p.sku = trim(p_parent_sku);
    if not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', trim(p_parent_sku), 'code', 'parent_unknown', 'message', format('SKU %s does not exist — nothing was saved', trim(p_parent_sku)));
    else
      if not v_par.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_inactive', 'sku', v_par.sku, 'code', 'parent_inactive', 'message', format('SKU %s is inactive — turn it on before making it a combo — nothing was saved', v_par.sku));
      end if;
      if v_par.parent_product_id is not null then                                                                   -- ⬜ 세트는 콤보가 못 된다 — 세트는 한 상품의 묶음 단위(pack_factor)라 구성품을 두 번 세게 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_set', 'sku', v_par.sku, 'code', 'parent_is_set', 'message', format('SKU %s is a set (pack of %s) — a set cannot also be a combo — nothing was saved', v_par.sku, coalesce(v_par.pack_factor::text, '?')));
      end if;
      select count(*) into v_cnt from public.product_bom b where b.component_product_id = v_par.id and b.is_active;
      if v_cnt > 0 then                                                                                             -- 묶음 1: 콤보 안에 콤보는 안 된다 — 다른 콤보의 구성품인 상품은 콤보가 못 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_component', 'sku', v_par.sku, 'code', 'parent_is_component', 'message', format('SKU %s is a component of %s other combo(s) — a combo cannot contain a combo — nothing was saved', v_par.sku, v_cnt));
      end if;
    end if;
  end if;

  -- ② 구성품 목록(전체) — 모양 · 하나씩
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid', 'sku', coalesce(v_par.sku, trim(p_parent_sku)), 'code', 'lines_invalid', 'message', 'Components must be a list of {sku, qty} — nothing was saved');
  else
    for v_e in select x from jsonb_array_elements(p_lines) x loop
      v_n := v_n + 1;
      if jsonb_typeof(v_e) <> 'object' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid:' || v_n, 'sku', coalesce(v_par.sku, ''), 'code', 'lines_invalid', 'message', format('Component %s is not {sku, qty} — nothing was saved', v_n));
        continue;
      end if;
      v_sku := nullif(trim(v_e->>'sku'), '');
      v_qtxt := trim(coalesce(v_e->>'qty', ''));
      if v_sku is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_n, 'sku', '', 'code', 'component_unknown', 'message', format('Component %s has no SKU — nothing was saved', v_n));
        continue;
      end if;
      select * into v_comp from public.product p where p.sku = v_sku;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_sku, 'sku', v_sku, 'code', 'component_unknown', 'message', format('Component %s does not exist — nothing was saved', v_sku));
        continue;
      end if;
      if not v_comp.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_inactive:' || v_sku, 'sku', v_sku, 'code', 'component_inactive', 'message', format('Component %s is inactive — nothing was saved', v_sku));
      end if;
      if v_par.id is not null and v_comp.id = v_par.id then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_parent:' || v_sku, 'sku', v_sku, 'code', 'component_is_parent', 'message', format('Combo %s cannot contain itself — nothing was saved', v_sku));
      end if;
      if exists (select 1 from public.product_bom b where b.parent_product_id = v_comp.id and b.is_active) then           -- 묶음 1: 콤보 안의 콤보
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_combo:' || v_sku, 'sku', v_sku, 'code', 'component_is_combo', 'message', format('Component %s is itself a combo — a combo cannot contain a combo — nothing was saved', v_sku));
      end if;
      if v_comp.id = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_duplicate_in_call:' || v_sku, 'sku', v_sku, 'code', 'component_duplicate_in_call', 'message', format('Component %s is listed twice — give it once with the total qty — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := array_append(v_seen, v_comp.id);
      if v_qtxt !~ '^[0-9]+(\.[0-9]+)?$' then                                                                    -- 글자 검사 먼저 — SQL 의 or 는 짧게 끊지 않아 'abc'::numeric 이 먼저 터진다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      if v_qtxt::numeric <= 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      v_qty := round(v_qtxt::numeric, 6);
      if v_comp.parent_product_id is not null then                                                                  -- ⬜ 세트를 구성품으로 — 막지 않는다 · 알린다(오더 길이 coalesce(parent, id) × pack_factor 로 낱개로 접는다)
        v_warns := v_warns || jsonb_build_object('key', v_key || ':component_is_set:' || v_sku, 'sku', v_sku, 'code', 'component_is_set', 'message', format('Component %s is a set (pack of %s) — the order will take %s × %s singles of its base product', v_sku, coalesce(v_comp.pack_factor::text, '?'), v_qty, coalesce(v_comp.pack_factor::text, '?')));
        v_keys := array_append(v_keys, v_key || ':component_is_set:' || v_sku);
      end if;
      v_new := v_new || jsonb_build_object('component_id', v_comp.id, 'sku', v_comp.sku, 'qty', v_qty);
    end loop;
    if jsonb_array_length(v_new) = 1 and jsonb_array_length(v_blocks) = 0 then                                   -- ⬜ 정본 「구성품 2 개 이상」(po-module 504 · 511) — IMS 만들기에도 건다
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_single', 'sku', coalesce(v_par.sku, ''), 'code', 'component_single', 'message', format('A combo needs at least two components (%s has one) — one component with a qty is a set, not a combo — nothing was saved', coalesce(v_par.sku, trim(p_parent_sku))));
    end if;
  end if;

  if v_par.id is null then
    return jsonb_build_object('committed', false, 'parent_sku', trim(p_parent_sku), 'parent_id', null, 'changes', '[]'::jsonb, 'components', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb);
  end if;

  -- ③ 지금 줄 · 옛 목록 대조(화면이 본 것과 같은가) · 바뀐 것이 있는가
  select count(*), count(*) filter (where b.source = 'cin7'),
         coalesce(string_agg(c.sku || '|' || round(b.quantity, 6)::text, ',' order by c.sku), '')
    into v_cur_n, v_cin7_n, v_cur_txt
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = v_par.id and b.is_active;
  select coalesce(string_agg(x->>'sku' || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by x->>'sku'), '') into v_new_txt from jsonb_array_elements(v_new) x;
  if p_old is null then
    if v_cur_n > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the component list the screen saw is missing — reload and try again — nothing was saved', v_par.sku));
    end if;
  elsif jsonb_typeof(p_old) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the old component list must be a list of {sku, qty} — nothing was saved', v_par.sku));
  else
    begin
      select coalesce(string_agg(trim(x->>'sku') || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by trim(x->>'sku')), '') into v_old_txt from jsonb_array_elements(p_old) x;
    exception when others then
      v_old_txt := '<unreadable>';
    end;
    if v_old_txt <> v_cur_txt then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'sku', v_par.sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the components of %s (now %s) — check again — nothing was saved', v_par.sku, case when v_cur_txt = '' then '(none)' else replace(v_cur_txt, '|', ' × ') end));
    end if;
  end if;
  if jsonb_array_length(v_blocks) = 0 and v_new_txt = v_cur_txt then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_change', 'sku', v_par.sku, 'code', 'no_change', 'message', format('Combo %s already has exactly these components — nothing to change — nothing was saved', v_par.sku));
  end if;

  -- ④ 알리기(ack) — 열린 오더 · 부모 장부 · Cin7 콤보
  select count(distinct l.so_id) into v_cnt from public.so_line l join public.so s on s.id = l.so_id where l.product_id = v_par.id and s.status not in ('fulfilled', 'cancelled');
  if v_cnt > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':open_orders', 'sku', v_par.sku, 'code', 'open_orders', 'message', format('%s open order(s) carry combo %s — they keep the components they were made with', v_cnt, v_par.sku));
    v_keys := array_append(v_keys, v_key || ':open_orders');
  end if;
  select coalesce(sum(b.qty), 0) into v_stock from public.ims_inv_balance b where b.product_id = v_par.id;
  if v_stock <> 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':parent_stock', 'sku', v_par.sku, 'code', 'parent_stock', 'message', format('Combo %s has %s in the books — combos are not kept in stock (they are made when an order ships) — adjust it out', v_par.sku, round(v_stock)));
    v_keys := array_append(v_keys, v_key || ':parent_stock');
  end if;
  if v_cin7_n > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':cin7_combo', 'sku', v_par.sku, 'code', 'cin7_combo', 'message', format('Combo %s came from Cin7 — change it in Cin7 too while both systems run, or the next import will show a difference', v_par.sku));
    v_keys := array_append(v_keys, v_key || ':cin7_combo');
  end if;

  -- ⑤ 변경 목록(미리 보기에도 준다)
  for v_r in
    select coalesce(n.sku, c.sku) as sku, n.qty as new_qty, case when b.is_active then b.quantity end as old_qty, n.component_id as new_id, b.component_product_id as old_id
      from (select (x->>'component_id')::uuid as component_id, x->>'sku' as sku, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x) n
      full join (select b.* from public.product_bom b where b.parent_product_id = v_par.id and b.is_active) b on b.component_product_id = n.component_id
      left join public.product c on c.id = b.component_product_id
     order by 1
  loop
    if v_r.old_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'added', 'qty', v_r.new_qty, 'old_qty', null); v_added := v_added + 1;
    elsif v_r.new_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'removed', 'qty', null, 'old_qty', v_r.old_qty); v_removed := v_removed + 1;
    elsif v_r.new_qty <> v_r.old_qty then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'changed', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_changed := v_changed + 1;
    else v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'unchanged', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_kept := v_kept + 1;
    end if;
  end loop;

  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                              'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                              'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑥ 저장 — 옛 줄과 새 목록을 견줘 더하기 · 수량 바꾸기 · 되살리기 · 끄기(지우지 않는다) · 손댄 줄은 source manual(판정 132 · prod-5 「IMS 가 고친 칸」 줄기)
  for v_r in select (x->>'component_id')::uuid as component_id, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x loop
    update public.product_bom b
       set quantity = v_r.qty, is_active = true, source = 'manual', updated_by = v_staff
     where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id
       and (not b.is_active or b.quantity <> v_r.qty);                                                                   -- 그대로인 줄은 건드리지 않는다(cin7 표시도 그대로)
    if not found and not exists (select 1 from public.product_bom b where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id) then
      insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active, updated_by)
      values (v_par.id, v_r.component_id, v_r.qty, 'manual', true, v_staff);
    end if;
  end loop;
  update public.product_bom b
     set is_active = false, source = 'manual', updated_by = v_staff
   where b.parent_product_id = v_par.id and b.is_active
     and not (b.component_product_id = any(coalesce((select array_agg((x->>'component_id')::uuid) from jsonb_array_elements(v_new) x), '{}'::uuid[])));

  return jsonb_build_object('committed', true, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                            'added', v_added, 'changed', v_changed, 'removed', v_removed, 'unchanged', v_kept,
                            'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                            'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) is
  'asm-1(판정 244 · asm 묶음 1): define or change a combo — the whole component list [{sku, qty}] for one parent SKU · p_old = the list the screen saw (changed_elsewhere when it differs) · preview with p_commit=false, save with true · blocks: parent_unknown · parent_inactive · parent_is_set · parent_is_component · lines_invalid · component_unknown · component_inactive · component_is_parent · component_is_combo · component_duplicate_in_call · quantity_invalid · component_single · old_missing · changed_elsewhere · no_change · warnings (ack keys): component_is_set · open_orders · parent_stock · cin7_combo · empty list = release (rows turned off, never deleted) · touched rows become source manual · master only';

-- ═══ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.product_bom_set(text, jsonb, jsonb, boolean, text[])') is null then v_bad := v_bad || ' window'; end if;
  if not has_function_privilege('authenticated', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' grants'; end if;
  if has_table_privilege('authenticated', 'public.product_bom', 'insert') or has_table_privilege('authenticated', 'public.product_bom', 'update') or has_table_privilege('authenticated', 'public.product_bom', 'delete') then v_bad := v_bad || ' product_bom-opened'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_bom') <> 1 then v_bad := v_bad || ' policies'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.product_bom'::regclass and tgname = 'product_bom_touch') then v_bad := v_bad || ' touch-trigger'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM244', message = format('STOP - asm-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
