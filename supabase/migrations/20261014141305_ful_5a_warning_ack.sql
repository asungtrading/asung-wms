-- ful-5a (2026-10-14 · 판정 467 · ful-4b5 20261014133038 위에) — 웹 오더 경고를 「확인함」으로 닫는다
--   실물(2026-10-14 · 테스트 DB · #1012): 경고 5 = tax_mismatch(시험 스토어 세금 0) · refund_due(처리됨 · 4b5) · refunded_in_shopify 12:37(판정 463 전의 거짓) · updated_after_so(시험 태그) · refunded_in_shopify 13:58(나간 물건 반품 · 직원이 IMS 크레딧 노트를 만든 뒤 닫을 것)
--     shop_order.warnings 는 쌓이기만 하고 직원이 닫을 길이 없다(dismiss · acknowledged 창구 0) · shop_order_list.warning_count 는 전체를 센다
--   판정 467 [Caleb · 2026-10-14 · 안 1]: 경고마다 「확인함」 — 지우지 않고 누가 · 언제 확인했는지 원소에 남기고(acked_at · acked_by · acked_by_name · acked_note) 화면에서 회색으로 내린다 · 목록의 경고 수는 열린 것만(확인함 · 처리됨 제외)
--     기각: 안 2(처리됨만 빼고 세기 — 사람이 해결한 경고가 영원히 숫자에 남는다) · 안 3(최근 며칠만 — 처리 안 된 옛 경고가 사라져 보인다)
--   ① 창구 shop_order_warning_ack(shop_order, ord, code, at, ack, note) — definer · 첫 줄 ims_require_write(sales) · 직원 so_current_staff · 행 잠금 for update · 원소는 자리(1 부터) + code + at 셋이 다 맞아야(화면이 옛 목록으로 누르면 거부) ·
--      확인함은 멱등(이미 확인함이면 그대로) · 다시 열기는 네 열쇠를 뺀다 · 처리됨(settled_at)은 둘 다 거부 · 열린 refund_due 의 확인함은 note 필수(손님 돈이 걸린 경고 — 환불하면 스스로 닫히므로 손으로 닫는 까닭을 남긴다) · 다른 원소 · 다른 열쇠 · 순서는 그대로(jsonb_agg … order by ord)
--   ② 뷰 shop_order_list 재발행 — ord-1a2 20261011003000:755 ~ 770 바이트 복사 + 끝에 open_warning_count 하나(settled_at 도 acked_at 도 없는 원소 수) · 기존 칸 · 순서 · 식 무접촉 · security_invoker · grant · comment 그대로(create or replace 가 ACL · comment 를 지킨다 · 의존 뷰 없음 — pg_depend 실측)
--   ⚠️ 무접촉: shop_order_warn · shop_order_ingest(4b5 의 settle 은 w || … 라 acked 열쇠를 지우지 않는다 — 검증 A10) · 화면(asung-ims 는 대화 Claude) · EF · cron · 운영
--   검증: ~/asung/prompts/ful-5a-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · 가짜 오더 · 가짜 직원 둘 · 시퀀스 무접촉)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014141305_ful_5a_warning_ack.sql && supabase migration repair --status applied 20261014141305 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① 창구 shop_order_warning_ack ═══
create function public.shop_order_warning_ack(p_shop_order_id uuid, p_ord int, p_code text, p_at text, p_ack boolean default true, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_name  text;
  v_o     public.shop_order%rowtype;
  v_w     jsonb;
  v_new   jsonb;
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_open  int;
begin
  perform public.ims_require_write('sales', 'saved');                                                                                   -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();
  select s.name into v_name from public.ims_staff s where s.id = v_staff;
  if p_ord is null or p_ord < 1 then raise exception 'Warning position % is not valid — nothing was saved', coalesce(p_ord::text, '(none)'); end if;
  if nullif(btrim(coalesce(p_code, '')), '') is null then raise exception 'Warning code is required — nothing was saved'; end if;
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;                                                   -- 행 잠금 — 같은 오더의 덧붙이기(shop_order_warn) · 받기(ingest 도 for update)와 줄을 선다
  if v_o.id is null then raise exception 'Shop order not found — nothing was saved'; end if;
  select t.w into v_w from jsonb_array_elements(v_o.warnings) with ordinality as t(w, ord) where t.ord = p_ord;
  if v_w is null or v_w->>'code' is distinct from p_code or v_w->>'at' is distinct from nullif(p_at, '') then                            -- 자리 + code + at 셋이 다 맞아야(at 없는 원소 = p_at null · '')
    raise exception 'This warning changed elsewhere — reload the order — nothing was saved';
  end if;
  if v_w->>'settled_at' is not null then raise exception 'This warning was already settled automatically — nothing was saved'; end if;  -- 처리됨(4b5 refund_due)은 확인함 · 다시 열기 모두 거부
  if p_ack then
    if v_w->>'acked_at' is not null then
      v_new := v_w;                                                                                                                      -- 멱등 — 덧씌우지 않는다
    else
      if v_w->>'code' = 'refund_due' and v_note is null then
        raise exception 'Acknowledging an open refund_due needs a note (why the refund is not being made in Shopify) — nothing was saved';
      end if;
      v_new := v_w || jsonb_build_object('acked_at', now(), 'acked_by', v_staff, 'acked_by_name', v_name) || (case when v_note is null then '{}'::jsonb else jsonb_build_object('acked_note', v_note) end);
    end if;
  else
    v_new := (case when v_w->>'acked_at' is null then v_w else v_w - array['acked_at', 'acked_by', 'acked_by_name', 'acked_note'] end);   -- 다시 열기 — 확인함이 아니면 그대로
  end if;
  if v_new <> v_w then
    update public.shop_order o set warnings = (select jsonb_agg(case when t.ord = p_ord then v_new else t.w end order by t.ord) from jsonb_array_elements(o.warnings) with ordinality as t(w, ord))
     where o.id = v_o.id;                                                                                                                -- 다른 원소 · 순서 · 열쇠 그대로
  end if;
  select count(*)::int into v_open from public.shop_order o, jsonb_array_elements(o.warnings) x where o.id = v_o.id and x->>'settled_at' is null and x->>'acked_at' is null;
  return jsonb_build_object('shop_order_id', v_o.id, 'name', v_o.name, 'ord', p_ord, 'code', p_code, 'acked', v_new->>'acked_at' is not null,
                            'acked_at', v_new->'acked_at', 'acked_by_name', v_new->'acked_by_name', 'open_warning_count', v_open);
end;
$$;
revoke all on function public.shop_order_warning_ack(uuid, int, text, text, boolean, text) from public, anon;
grant execute on function public.shop_order_warning_ack(uuid, int, text, text, boolean, text) to authenticated;
comment on function public.shop_order_warning_ack(uuid, int, text, text, boolean, text) is 'ful-5a 판정 467: 직원이 웹 오더 경고 하나를 「확인함」으로 닫거나(p_ack true · 원소에 acked_at · acked_by · acked_by_name · acked_note 를 덧붙인다 · 멱등) 다시 연다(false · 네 열쇠를 뺀다) — definer · 첫 줄 ims_require_write(sales) · 행 잠금 · 원소는 자리(1 부터) + code + at 셋이 다 맞아야(아니면 「changed elsewhere — reload」) · 처리됨(settled_at)은 거부 · 열린 refund_due 는 note 필수 · 다른 원소 · 순서 · 열쇠 그대로 · 반환 {shop_order_id, name, ord, code, acked, acked_at, acked_by_name, open_warning_count}';

-- ═══ ② 뷰 shop_order_list 재발행 — ord-1a2 20261011003000:755 ~ 770 바이트 복사 · 끝에 open_warning_count 하나(바꾼 줄 1 = so_baseline_at 뒤 쉼표 · 더한 줄 1) ═══
create or replace view public.shop_order_list
  with (security_invoker = true) as
  select o.id, o.store_id, s.code as store_code, o.shopify_order_gid, o.name, o.status, o.shopify_created_at, o.shopify_updated_at, o.shopify_cancelled_at, o.is_test,
         o.financial_status, o.source_name, o.email, o.shopify_customer_gid, o.ship_province_code, o.ship_country_code, o.currency_code,
         o.subtotal, o.total_discounts, o.total_shipping, o.total_tax, o.total, o.freight_amount, o.freight_title,
         o.customer_id, c.name as customer_name, o.location_id, w.name as location_name, o.so_id, so.so_number, so.status as so_status,
         o.reasons, jsonb_array_length(o.reasons) as reason_count, o.warnings, jsonb_array_length(o.warnings) as warning_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id) as line_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id and l.match is distinct from 'ok') as unmatched_count,
         o.received_at, o.processed_at, o.error, o.updated_at,
         o.so_baseline_at,
         (select count(*) from jsonb_array_elements(o.warnings) x where x->>'settled_at' is null and x->>'acked_at' is null) as open_warning_count   -- ful-5a 판정 467: 열린 경고 수(확인함 · 처리됨 제외) — 끝에만
    from public.shop_order o
    join public.shop_store s on s.id = o.store_id
    left join public.customer c on c.id = o.customer_id
    left join public.ref_warehouse w on w.id = o.location_id
    left join public.so so on so.id = o.so_id;
comment on column public.shop_order_list.open_warning_count is 'ful-5a 판정 467: 열린 경고 수 — 원소 중 settled_at(처리됨 · 4b5)도 acked_at(확인함 · shop_order_warning_ack)도 없는 것 · 목록 · SO 상세 · 받은 편지함이 이 수를 쓴다(warning_count 는 전체 수 그대로)';

-- ═══ 자기 검사 ═══
do $$ begin
  if to_regprocedure('public.shop_order_warning_ack(uuid, int, text, text, boolean, text)') is null then raise exception 'ful-5a: function missing'; end if;
  if has_function_privilege('anon', 'public.shop_order_warning_ack(uuid, int, text, text, boolean, text)', 'execute') then raise exception 'ful-5a: anon can execute'; end if;
  if not has_function_privilege('authenticated', 'public.shop_order_warning_ack(uuid, int, text, text, boolean, text)', 'execute') then raise exception 'ful-5a: authenticated cannot execute'; end if;
  if (select column_name from information_schema.columns where table_schema = 'public' and table_name = 'shop_order_list' order by ordinal_position desc limit 1) <> 'open_warning_count' then raise exception 'ful-5a: open_warning_count is not the last column'; end if;
  if (select array_to_string(c.reloptions, ',') from pg_class c where c.oid = 'public.shop_order_list'::regclass) !~ 'security_invoker=true' then raise exception 'ful-5a: view lost security_invoker'; end if;
end $$;
