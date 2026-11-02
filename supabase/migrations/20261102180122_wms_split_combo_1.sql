-- wms-split-combo-1 (2026-11-02 · 판정 970 · 972 · 973) — 한 콤보 줄의 구성품은 늘 한 조각(배치 · 픽 과제)에
-- [메인 IMS · Asung-IMS] 적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일>
-- 까닭(wms-split-combo-0 조사): 픽 · 팩 화면의 박스 스캔(comboScan · 판정 887)은 연 과제 하나의 구성품만 보고 「콤보 하나」 로 채운다 —
--   구성품이 두 조각에 갈리면 조각마다 박스 한 번 = 콤보 하나로 차서 실물 박스가 두 번 나간다(거부 없이) · 팩 「n of m complete」 도 반쪽을 완성으로 보인다.
--   오더 단위 셈(wms_finalize · wms_so_handoff · so_finalize 의 whole · put_back)은 갈려도 맞다 — 고칠 곳은 조각을 만드는 문 하나.
-- 바꾼 것: wms_batch_create 하나 — 원본 20260928234815_transfer_1b2.sql:186 ~ 254 바이트 복사(DB md5 84efda39…) + 줄 검사 끝에 콤보 검사 한 덩이(「wms-split-combo-1」 주석)
--   · 같은 combo_line_id 의 구성품 줄이 p_batches 의 둘 이상에 들면 거부 — 판매 · 트랜스퍼 둘 다(공용 목록 wms_order_doc_line 이 combo_line_id · combo_sku 를 든다)
--   · 거부 글(영어 · 화면 toast 그대로): 「CB-LAC80085 on SO-20839 must stay in one split — its items are in splits 1 and 2 — nothing was saved」 · 콤보가 여럿 갈리면 「; 」 로 잇는다 · 조각 번호 = 배치 순서(라벨 <번호>-<n> 의 n)
--   · 판정 973: 한도는 화면의 일이다 — 창구는 조각 크기를 보지 않는다(콤보 하나가 한도보다 커도 한 조각이면 통과)
--   서명 · security definer · search_path · 권한 · 소유자 그대로(create or replace) · comment 는 끝에 한 마디 더
-- 무접촉: wms_wave_create(오더 하나 = 과제 하나 — 갈 수 없다) · wms_pick_task_build · so_pick_plan · 픽 · 팩 화면(판정 974 — 안전망 없음)

-- ═══ wms_batch_create 재발행 — 원본 20260928234815_transfer_1b2.sql:186 ~ 254 + 콤보 검사(줄 끝 「wms-split-combo-1」) ═══
create or replace function public.wms_batch_create(p_so_id uuid, p_batches jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_doc    public.wms_order_doc%rowtype;
  v_wh     text;
  v_plan   jsonb;
  v_ids    uuid[] := '{}';
  v_batch  uuid[];
  v_bad    text;
  v_n      int;
  i        int;
  b        jsonb;
  v_tasks  jsonb := '[]'::jsonb;
  v_t      jsonb;
  v_warn   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄 — 카탈로그 wms_manage = manager 이상(min_role)
  v_staff := public.so_current_staff();
  perform 1 from public.so s where s.id = p_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  perform 1 from public.inv_transfer x where x.id = p_so_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째 — 창고 제한 첫 실물
    raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
  end if;
  if v_doc.status <> 'at_wms' then
    raise exception 'Order % is % — only orders released to the WMS can be batched — nothing was saved', v_doc.doc_number, v_doc.status;
  end if;
  if exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = p_so_id) then
    raise exception 'Order % already has pick tasks — nothing was saved', v_doc.doc_number;
  end if;
  if p_batches is null or jsonb_typeof(p_batches) <> 'array' or jsonb_array_length(p_batches) = 0 then
    raise exception 'Order % — no batches given — nothing was saved', v_doc.doc_number;
  end if;
  -- 줄 검사: 모르는 줄 · 두 번 든 줄 · 빠진 보낼 줄 · 다 뺀 줄
  for b in select * from jsonb_array_elements(p_batches) loop
    if jsonb_typeof(b->'line_ids') <> 'array' or jsonb_array_length(b->'line_ids') = 0 then
      raise exception 'Order % — a batch has no lines — nothing was saved', v_doc.doc_number;
    end if;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_ids := v_ids || v_batch;
  end loop;
  select string_agg(u.id::text, ', ') into v_bad from unnest(v_ids) u(id) where not exists (select 1 from public.wms_order_doc_line l where l.line_id = u.id and l.doc_id = p_so_id);
  if v_bad is not null then raise exception 'Order % — lines not on this order (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ') into v_bad from (select u.id from unnest(v_ids) u(id) group by u.id having count(*) > 1) d join public.wms_order_doc_line l on l.line_id = d.id;
  if v_bad is not null then raise exception 'Order % — lines in more than one batch (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target > 0 and not (l.line_id = any (v_ids));
  if v_bad is not null then raise exception 'Order % — lines left out of the batches (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target <= 0 and l.line_id = any (v_ids);
  if v_bad is not null then raise exception 'Order % — lines with nothing to ship (%) cannot be batched — nothing was saved', v_doc.doc_number, v_bad; end if;
  -- ⭐ wms-split-combo-1(판정 972): 한 콤보 줄의 구성품은 한 조각에 — 같은 combo_line_id 의 구성품 줄이 둘 이상의 배치에 들면 거부(판매 · 트랜스퍼)
  select string_agg(format('%s on %s must stay in one split — its items are in splits %s', s.combo_sku, v_doc.doc_number,                       -- wms-split-combo-1
                           case when cardinality(s.ns) = 2 then s.ns[1] || ' and ' || s.ns[2]                                                    -- wms-split-combo-1
                                else array_to_string(s.ns[1:cardinality(s.ns) - 1], ', ') || ' and ' || s.ns[cardinality(s.ns)] end), '; ' order by s.first_no)   -- wms-split-combo-1
    into v_bad                                                                                                                                -- wms-split-combo-1
    from (select l.combo_line_id, min(l.combo_sku) as combo_sku, min(l.line_no) as first_no, array_agg(distinct b.n order by b.n) as ns        -- wms-split-combo-1
            from jsonb_array_elements(p_batches) with ordinality b(e, n)                                                                     -- wms-split-combo-1: n = 배치 순서 = 라벨의 -n
            cross join lateral jsonb_array_elements_text(b.e->'line_ids') u(id)                                                              -- wms-split-combo-1
            join public.wms_order_doc_line l on l.line_id = u.id::uuid and l.doc_id = p_so_id                                                -- wms-split-combo-1
           where l.combo_line_id is not null                                                                                                 -- wms-split-combo-1
           group by l.combo_line_id                                                                                                          -- wms-split-combo-1
          having count(distinct b.n) > 1) s;                                                                                                 -- wms-split-combo-1
  if v_bad is not null then raise exception '% — nothing was saved', v_bad; end if;                                                          -- wms-split-combo-1
  -- 계획 칸 · 과제
  v_plan := public.so_pick_plan(p_so_id);
  i := 0;
  for b in select * from jsonb_array_elements(p_batches) loop
    i := i + 1;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_t := public.wms_pick_task_build(p_so_id, v_doc.doc_number || '-' || i, v_batch, null, null, v_staff, v_plan);
    v_tasks := v_tasks || v_t;
    v_warn := v_warn || (v_t->'warnings');
  end loop;
  perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'picking', v_staff);     -- tr-1b2: 판매면 so_wms_status · 트랜스퍼면 tf_wms_status
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'status', 'picking', 'tasks', v_tasks,
                            'short_ea_total', v_plan->'short_ea_total', 'warnings', (v_plan->'warnings') || v_warn);
end;
$$;

comment on function public.wms_batch_create(uuid, jsonb) is '⑤-2a1 WMS 창구 배치 만들기(운영 manager.html Split 의 자리) — 첫 줄 ims_require_write(wms_manage) · 둘째 ims_can_warehouse(오더의 창고) · at_wms 오더 · 픽 과제 없음 · p_batches [{line_ids}] 는 보낼 줄마다 정확히 한 배치 · 라벨 <so_number>-<n> · so_pick_plan 의 계획 칸을 wms_pick_line_bins 에 · 마지막에 so_wms_status(picking · picking_at/by) · 빈 선반도 막지 않는다(warnings) · ⭐ wms-split-combo-1(판정 972): 한 콤보 줄(combo_line_id)의 구성품이 둘 이상의 배치에 들면 거부(「<콤보 SKU> on <번호> must stay in one split — its items are in splits 1 and 2 — nothing was saved」 · 판매 · 트랜스퍼) · 크기 한도는 보지 않는다(판정 973)';
