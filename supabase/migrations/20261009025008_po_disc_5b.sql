-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ⑤-b — 환율 차액(판정 394): 읽기 창구 po_fx_cost_status(PO 줄마다 남은 차액) · 반영 창구 po_fx_cost_apply(멱등 · 미리 보기 · 사건 kind price_adjust · source_type fx_fix · 판정 399 거부면 전체 안 저장) (Asung-IMS · po-disc-5b · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 392 · 394 · 399(2026-10-08 · Caleb) · po-module §11-h · §11-i 「입고 원가의 재료」(핀)
--   판정 394  입고 뒤 PO 환율을 고쳐도 원가는 저절로 안 바뀐다(핀 po_receipt_cost · po-disc-2) — 경고 + 「차액 반영」 단추(사람이 누른다) · 이견 11 po.exchange_rate 수정은 막지 않는다(po.html HEAD_ALWAYS 그대로)
--   식 한 곳   po_fx_cost_lines(po): PO 줄마다 — 대상 레이어 = 그 줄의 구매 레이어(origin purchase · cost_source po_line) 중 핀 출처 po 인 것(핀 출처 invoice 는 인보이스 환율이 원가 환율이라 제외 · 핀 없는 레이어는 제외 + 경고) · 목표 = Σ(레이어 qty × 핀 unit_price_net × 지금 PO 환율) · 이미 = Σ(레이어 qty × 핀 unit_cost_cad) + Σ(그 줄의 fx_fix 사건 · 그 되돌림만 · 이견 10) · 남은 차액 = round(목표 − 이미, 2) · 기준통화 PO 는 언제나 0 · PO 환율 없으면 0 + 경고
--   ⬜5 레이어 qty 는 원래 수량(소비로 줄지 않는다) — 사건은 레이어에 얹히고 settle 이 팔린 몫 cost_late · 옮겨 간 몫 carried 로 나눈다(검증 G4)
--   ⬜4 po_detail 은 재발행하지 않는다 — 화면 ⑥ 이 po_fx_cost_status 를 PO 상세에서 따로 부른다
--   멱등   같은 환율로 두 번 누르면 두 번째 차액 0 · 환율을 되돌리고 누르면 반대 부호(합 0) · 사건은 되돌리지 않고 더한다(원가 사건은 append · 바로잡기는 다음 반영)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 없음(새 함수 셋)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 차액의 재료는 IMS 핀 · IMS PO 환율
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

-- ═══ ① 식 한 곳 — PO 줄마다 환율 차액의 재료(목표 · 이미 · fx_fix 합 · 남은 차액 · 제외 수) · invoker · 읽기 전용 ═══
create function public.po_fx_cost_lines(p_po_id uuid)
  returns table (po_line_id uuid, line_no int, sku text, layers int, layer_qty numeric, pin_source text, pin_fx numeric, unit_price_net numeric,
                 target_cad numeric, layer_cad numeric, fx_fix_cad numeric, already_cad numeric, remaining_cad numeric,
                 excluded_invoice_layers int, unpinned_layers int)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with p as (
    select x.id, x.exchange_rate, (c.code is not distinct from b.code) as is_base
      from public.po x join public.ref_currency c on c.id = x.currency_id
      left join (select k.value as code from public.inv_config k where k.key = 'base_currency') b on true
     where x.id = p_po_id
  ), ly as (
    select pl.id as po_line_id, pl.line_no, pr.sku, y.id as layer_id, y.qty, y.unit_cost,
           k.exchange_rate_source as pin_source, k.exchange_rate as pin_fx, k.unit_price_net, k.unit_cost_cad
      from public.po_line pl join public.product pr on pr.id = pl.product_id
      join public.inv_layer y on y.line_ref = pl.id::text and y.origin_type = 'purchase' and y.cost_source = 'po_line'
      left join public.po_receipt r on r.receipt_number = y.doc_number
      left join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id = pl.id
     where pl.po_id = p_po_id
  ), fx as (
    select j.po_line_id, coalesce(sum(j.amount_cad), 0) as fx_fix_cad
      from public.inv_cost_adjust j
     where j.source_type = 'fx_fix' or (j.source_type = 'reversal' and exists (select 1 from public.inv_cost_adjust o where o.id = j.reverses_id and o.source_type = 'fx_fix'))   -- 이견 10: fx_fix 와 그 되돌림만
     group by j.po_line_id
  ), g as (
    select ly.po_line_id, ly.line_no, ly.sku,
           count(*)::int as layers,
           coalesce(sum(ly.qty) filter (where ly.pin_source = 'po'), 0) as layer_qty,
           min(ly.pin_source) filter (where ly.pin_source = 'po') as pin_source,
           max(ly.pin_fx) filter (where ly.pin_source = 'po') as pin_fx,
           max(ly.unit_price_net) filter (where ly.pin_source = 'po') as unit_price_net,
           coalesce(sum(ly.qty * ly.unit_price_net * (select coalesce(p.exchange_rate, 0) from p)) filter (where ly.pin_source = 'po'), 0) as target_cad,
           coalesce(sum(ly.qty * ly.unit_cost_cad) filter (where ly.pin_source = 'po'), 0) as layer_cad,
           count(*) filter (where ly.pin_source = 'invoice')::int as excluded_invoice_layers,
           count(*) filter (where ly.unit_cost_cad is null)::int as unpinned_layers
      from ly group by ly.po_line_id, ly.line_no, ly.sku
  )
  select g.po_line_id, g.line_no, g.sku, g.layers, g.layer_qty, g.pin_source, g.pin_fx, g.unit_price_net,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null then 0 else g.target_cad end as target_cad,
         g.layer_cad, coalesce(fx.fx_fix_cad, 0) as fx_fix_cad,
         g.layer_cad + coalesce(fx.fx_fix_cad, 0) as already_cad,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null or g.layer_qty = 0 then 0
              else round(g.target_cad - g.layer_cad - coalesce(fx.fx_fix_cad, 0), 2) end as remaining_cad,   -- 기준통화 · 환율 없음 · po 핀 없음 → 0
         g.excluded_invoice_layers, g.unpinned_layers
    from g left join fx on fx.po_line_id = g.po_line_id
   order by g.line_no
$$;
revoke all on function public.po_fx_cost_lines(uuid) from public, anon;
grant execute on function public.po_fx_cost_lines(uuid) to authenticated;
comment on function public.po_fx_cost_lines(uuid) is 'po-disc-5b ⭐ 환율 차액 식 한 곳(판정 394 · 2026-10-09) — PO 줄마다 핀 출처 po 인 구매 레이어만(invoice 출처는 제외 · 핀 없음은 제외 + 수) · 목표 = Σ qty × 핀 unit_price_net × 지금 PO 환율 · 이미 = Σ qty × 핀 unit_cost_cad + Σ fx_fix 사건(되돌림 포함 · 이견 10) · 남은 = round(목표 − 이미, 2) · 기준통화 · 환율 없음 → 0 · po_fx_cost_status · po_fx_cost_apply 가 같이 읽는다';

-- ═══ ② 읽기 창구 — 화면 ⑥ 의 경고 재료(PO 상세가 따로 부른다 · ⬜4) ═══
create function public.po_fx_cost_status(p_po_id uuid) returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare v_po record; v_base text; v_lines jsonb; v_total numeric; v_aff int; v_exc int; v_unp int; v_warn text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'read');
  select x.id, x.po_number, x.exchange_rate, c.code as currency, x.status into v_po from public.po x join public.ref_currency c on c.id = x.currency_id where x.id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was read', p_po_id; end if;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  if v_po.currency is distinct from v_base and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then v_warn := array_append(v_warn, 'po_exchange_rate_missing'); end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb), coalesce(sum(l.remaining_cad), 0), count(*) filter (where l.remaining_cad <> 0), coalesce(sum(l.excluded_invoice_layers), 0), coalesce(sum(l.unpinned_layers), 0)
    into v_lines, v_total, v_aff, v_exc, v_unp
    from public.po_fx_cost_lines(p_po_id) l;
  if v_unp > 0 then v_warn := array_append(v_warn, 'unpinned_layers:' || v_unp); end if;
  return jsonb_build_object('po_id', v_po.id, 'po_number', v_po.po_number, 'po_status', v_po.status, 'currency', v_po.currency, 'base_currency', v_base, 'is_base', v_po.currency is not distinct from v_base,
                            'fx_now', v_po.exchange_rate, 'lines', v_lines, 'total_remaining_cad', v_total, 'affected_lines', v_aff,
                            'excluded_invoice_layers', v_exc, 'unpinned_layers', v_unp, 'affected', v_aff > 0, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.po_fx_cost_status(uuid) from public, anon;
grant execute on function public.po_fx_cost_status(uuid) to authenticated;
comment on function public.po_fx_cost_status(uuid) is 'po-disc-5b ⭐ 환율 차액 상태(판정 394) — 줄마다 po_fx_cost_lines · total_remaining_cad · affected_lines(남은 차액 ≠ 0 인 줄) · excluded_invoice_layers(핀 출처 invoice — PO 환율과 무관) · unpinned_layers(핀 없음 — 옛 입고 · 제외) · 기준통화 PO 는 늘 0 · 경고 po_exchange_rate_missing · 문 purchasing(읽기) · 화면 ⑥ PO 상세가 따로 부른다(po_detail 무재발행 ⬜4) · 「차액 반영」 단추 = po_fx_cost_apply';

-- ═══ ③ 반영 창구 — 남은 차액 ≠ 0 인 줄마다 사건(kind price_adjust · target po_line · amount_cad = 남은 차액 · source_type fx_fix · source_number FX <PO> <날> <환율>) · 곧바로 얹는다(399 거부는 예외 = 전체 안 저장) · 미리 보기 · 멱등 ═══
create function public.po_fx_cost_apply(p_po_id uuid, p_commit boolean default false) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version constant text := 'po_fx_cost_apply@2026-10-09.1';
  v_st     jsonb;
  v_po     record;
  v_staff  uuid;
  v_src    text;
  v_l      record;
  v_id     uuid;
  v_j      jsonb;
  v_events jsonb := '[]'::jsonb;
  v_sum    numeric := 0;
  v_n      int := 0;
begin
  perform public.ims_require_write('purchasing', 'saved');
  v_st := public.po_fx_cost_status(p_po_id);
  select x.po_number, x.exchange_rate into v_po from public.po x where x.id = p_po_id;
  if (v_st ->> 'is_base')::boolean then
    return v_st || jsonb_build_object('committed', false, 'events', '[]'::jsonb, 'event_count', 0, 'applied_cad', 0, 'skipped', 'base_currency', 'builder', c_version);   -- 기준통화 PO 는 늘 0
  end if;
  if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
    raise exception 'PO % has no exchange rate — enter it in the order header first — nothing was saved', v_po.po_number;
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  v_src := 'FX ' || v_po.po_number || ' ' || public.ims_today()::text || ' ' || trim_scale(v_po.exchange_rate)::text;
  for v_l in select * from public.po_fx_cost_lines(p_po_id) where remaining_cad <> 0 order by line_no loop
    v_n := v_n + 1;  v_sum := v_sum + v_l.remaining_cad;
    v_id := null;  v_j := null;
    if p_commit then
      insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, note, created_by, updated_by)
      values ('price_adjust', 'po_line', v_l.po_line_id, v_l.remaining_cad, null, null, v_po.exchange_rate, 'fx_fix', p_po_id, v_src,
              format('fx difference on PO %s line %s (%s · pin %s → now %s · target %s − already %s)', v_po.po_number, v_l.line_no, v_l.sku, trim_scale(v_l.pin_fx), trim_scale(v_po.exchange_rate), v_l.target_cad, v_l.already_cad), v_staff, v_staff)
      returning id into v_id;
      v_j := public.inv_layer_post_cost_adjust(v_id);                                     -- 판정 391 · 399 거부는 예외로 올라간다 = 전체 안 저장 · 레이어는 있다(핀이 있으면) — no_layers 면 pending
    end if;
    v_events := v_events || jsonb_build_object('id', v_id, 'po_line_id', v_l.po_line_id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'amount_cad', v_l.remaining_cad,
                                               'pin_fx', v_l.pin_fx, 'fx_now', v_po.exchange_rate, 'target_cad', v_l.target_cad, 'already_cad', v_l.already_cad,
                                               'status', case when p_commit then coalesce(v_j ->> 'status', 'pending') else 'preview' end,
                                               'layers', coalesce((v_j ->> 'layers')::int, 0), 'posted_cad', coalesce((v_j ->> 'posted_cad')::numeric, 0));
  end loop;
  return v_st || jsonb_build_object('committed', p_commit, 'source_number', v_src, 'events', v_events, 'event_count', v_n, 'applied_cad', v_sum, 'builder', c_version);
end;
$$;
revoke all on function public.po_fx_cost_apply(uuid, boolean) from public, anon;
grant execute on function public.po_fx_cost_apply(uuid, boolean) to authenticated;
comment on function public.po_fx_cost_apply(uuid, boolean) is 'po-disc-5b ⭐ 「차액 반영」 단추(판정 394 · 사람이 누른다) — po_fx_cost_lines 의 남은 차액 ≠ 0 인 줄마다 사건(kind price_adjust · target po_line · amount_cad = 남은 차액(양수 · 음수) · amount_doc null · source_type fx_fix · source_id PO · source_number FX <PO> <날> <환율>) · 곧바로 inv_layer_post_cost_adjust(399 거부는 예외 = 전체 안 저장) · 멱등: 같은 환율로 또 누르면 남은 0 → 사건 0 · 환율을 되돌리고 누르면 반대 부호(합 0) · 기준통화 PO 는 skipped base_currency · 환율 없으면 거부 · 미리 보기 p_commit false · 문 purchasing · definer';

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  foreach v_t in array array['public.po_fx_cost_lines(uuid)', 'public.po_fx_cost_status(uuid)', 'public.po_fx_cost_apply(uuid, boolean)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_fx_cost_apply' and p.prosecdef) <> 1 then v_bad := v_bad || ' apply(definer)'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_detail', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'inv_layer_post_receipt', 'po_receipt_confirm_by') and p.prosrc like '%po-disc-5b%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix') <> 0 then v_bad := v_bad || ' events-made-by-migration'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM401', message = format('STOP - po-disc-5b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
