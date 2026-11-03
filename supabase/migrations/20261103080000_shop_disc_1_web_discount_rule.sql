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
-- shop-disc-1 — asung.ca 웹 줄 할인 반올림을 들여올 때 IMS 셈으로 (판정 996 · 997 · 999 · 1001 ~ 1008 · 2026-11-03 · 지시서 ~/asung/prompts/shop-disc-1.md · 바탕 조사 shop-disc-0-report.md · §0 이견 1 ~ 12 답 Caleb)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261103080000 · ⚠️ db push 쓰지 않는다
-- 문제: Wholesale All In One 앱이 줄마다 단위당 고정 금액 할인(ManualDiscountApplication · EACH)을 보내 단가를 단위마다 반올림 → 손님 7 % 가 인보이스에 6.71 · 6.88 · 7.12 % 로 찍힌다
-- 무엇:
--   ⓪ 재발행 원본 가드 — DB prosrc md5 가 마지막 정의 파일과 다르면 멈춘다(shop_order_process fac48d11 = 20261103020000:487 · so_line_set_shopify f5bd0d5f · so_line_quote 84366f59 · 2026-11-03 대조) · 새 함수 둘이 이미 있으면 멈춘다
--   ① shop_line_rule_fit(list, unit, pct) → boolean — immutable · 1001 단가 꼴: Shopify 단가 = round(Shopify 정가 × (1 − p/100), 2) · 정가 · 단가 · p 가 null 이거나 정가 ≤ 0 · p 가 0 ~ 100 밖이면 false
--   ② so_line_set_shopify_rule(line, pct) → so_line — service_role 만 · 정가 그대로 · discount_pct = p · unit_price = 정가 × (1 − p/100) · 출처 shopify 그대로(1003) · so for update + 유효 인보이스 거부(1008) · cancelled · 구성품 · B급 · 무상 · 출처 ≠ shopify · 손 가격 · 정가 없음 · 단가 0 거부(이견 3 ~ 5) · 수량 · 예약 · WMS 무접촉 · 2 인자(이견 2 · 신원은 호출자)
--   ③ shop_order_process 재발행 — 원본 DB 바이트(171 줄) + 더한 줄만(지운 줄 0): 선언 1 · 루프 ② 의 asung 갈래(범위 = shop_line_rule_fit · 범위 안 ∧ 정가 같음 ∧ (% ≠ p ∨ 단가 ≠ 정가 × (1 − p/100)) → 후보 · 범위 밖 → 금액 경고 shopify_unit · ims_unit · line_diff · 옛 0.1 % 줄은 else 안에 그대로 = aone 무변) · ⑥-b(세금 대조 뒤 · Confirm 앞 · ② 로 고침 · 정보 원소 web_discount_rounded: at · settled_at · lines · total_diff · detail[line_no · sku · pct · shopify_unit · ims_unit · line_diff])
--   ④ 착지 가드 — 몸 셋 md5 · 오버로드 수 · 권한(② · ③ 은 authenticated · anon 불가 · ① 은 authenticated 가능) · so_line_set_shopify · so_line_quote 무변
-- 무접촉: so_line_set_shopify · so_line_quote · so_line_requote · so_line_update · so_reprice(433 그대로) · CHECK(discount_source · 1003) · 칸 없음 · 화면 · EF · aonebeauty.com 길(996) · shop_order_line
-- 검증: supabase/tests/shop_disc_1_check.sql(시험 -v mig · 적용 뒤 -v mig 없이) · 다음: shop-disc-2(ops 스크립트 997 · ② 를 shop_system_enter 안에서 부른다) · docs 차수
-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_proc text; v_set text; v_quote text;
begin
  select md5(prosrc) into v_proc from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure;
  select md5(prosrc) into v_set from pg_proc where oid = 'public.so_line_set_shopify(uuid, numeric, numeric)'::regprocedure;
  select md5(prosrc) into v_quote from pg_proc where oid = 'public.so_line_quote(public.so, uuid, numeric)'::regprocedure;
  if v_proc <> 'fac48d1123643c5a2a51aaa167ec924e' or v_set <> 'f5bd0d5f9cbe2e1d15e9441068e9cb51' or v_quote <> '84366f59d10e4f140bda924e40beec4f' then
    raise exception using errcode = 'IM511', message = format('STOP - shop_order_process md5 %s / so_line_set_shopify md5 %s / so_line_quote md5 %s are not the bodies (fac48d11 / f5bd0d5f / 84366f59) this file builds on - nothing was changed', left(v_proc, 8), left(v_set, 8), left(v_quote, 8));
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_line_rule_fit', 'so_line_set_shopify_rule')) > 0 then
    raise exception using errcode = 'IM511', message = 'STOP - shop-disc-1 is already applied (shop_line_rule_fit or so_line_set_shopify_rule exists) - nothing was changed';
  end if;
end $$;

-- ═══ ① 범위 식 한 곳 — 단가 꼴(판정 1001 · 보고서 이견 8 · 30 일 1,041 줄 · 50 % 반 센트 30 줄 포함 · 반례 0) ═══
create function public.shop_line_rule_fit(p_list numeric, p_unit numeric, p_pct numeric) returns boolean
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select p_list is not null and p_unit is not null and p_pct is not null and p_list > 0 and p_pct >= 0 and p_pct <= 100
         and round(p_list * (1 - p_pct / 100), 2) = round(p_unit, 2);
$$;
revoke all on function public.shop_line_rule_fit(numeric, numeric, numeric) from public, anon;
grant execute on function public.shop_line_rule_fit(numeric, numeric, numeric) to authenticated, service_role;
comment on function public.shop_line_rule_fit(numeric, numeric, numeric) is 'shop-disc-1 판정 1001: 웹(Shopify) 줄이 「IMS 규칙 p 의 반올림 범위 안」인가 — Shopify 단가 = round(Shopify 정가 × (1 − p/100), 2)(단가 꼴 · 앱이 할인 뒤 단가를 단위마다 반올림한다) · 정가 · 단가 · p 중 하나라도 null 이거나 정가 ≤ 0 · p 가 0 ~ 100 밖이면 false · immutable · shop_order_process(asung 줄) · shop-disc-2 ops 스크립트가 같은 식을 쓴다';

-- ═══ ② 속 창구 — 웹 줄 하나를 IMS 할인 식으로(service_role 만) ═══
create function public.so_line_set_shopify_rule(p_line_id uuid, p_pct numeric) returns public.so_line
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
-- shop-disc-1 판정 997 · 999 · 1003 · 1008 · 이견 2 ~ 5: 웹(Shopify) 줄 하나를 IMS 할인 식으로 — 정가 그대로 · discount_pct = p · unit_price = 정가 × (1 − p/100) · 출처 shopify 그대로 · deal null · price_override false
--   오더를 for update 로 잡고 같은 트랜잭션에서 유효 인보이스(so_invoice_order.active_so_id)를 본다 · 상태는 인보이스 전이면 무엇이든(confirmed · picking · packed · shipped) · cancelled 거부
--   거부: 콤보 구성품 · B급 줄 · 무상 줄 · 손 가격(price_override) · 출처 ≠ shopify · 정가 없음 · p 가 단가를 0 으로 만듦(무상 줄이 된다 · so_line_free_pair_ck)
--   무접촉: 수량 · qty_shipped · 예약(so_reserve) · WMS 과제 · price_set_by · shop_order_line(Shopify 사실) · updated_by 는 so_line_touch 가 auth.uid() 로 적는다 → 호출자가 신원을 세운다(process = shop_system_enter · shop-disc-2 도 같은 길)
--   service_role 만(revoke) · 부르는 곳: shop_order_process ⑥-b · shop-disc-2 ops 스크립트(997)
declare
  v_line public.so_line%rowtype;
  v_so   public.so%rowtype;
  v_unit numeric;
begin
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'so_line_set_shopify_rule: discount_pct % must be between 0 and 100 — nothing was saved', p_pct;
  end if;
  select s.* into v_so from public.so s join public.so_line l on l.so_id = s.id where l.id = p_line_id for update of s;        -- 1008: 오더부터 잡는다 — 인보이스 발행(so_invoice_issue)과 겹치지 않게
  if v_so.id is null then
    raise exception 'so_line_set_shopify_rule: line % not found — nothing was saved', p_line_id;
  end if;
  select * into v_line from public.so_line where id = p_line_id;
  if v_so.status = 'cancelled' then
    raise exception 'Order % is cancelled — its lines are not re-priced — nothing was saved', v_so.so_number;
  end if;
  if exists (select 1 from public.so_invoice_order io where io.active_so_id = v_so.id) then
    raise exception 'Order % is invoiced — web lines are not re-priced after the invoice — nothing was saved', v_so.so_number;
  end if;
  if v_line.combo_line_id is not null then
    raise exception 'Line % (%) is a combo component — it has no price of its own — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  if v_line.bgrade_bin_id is not null then
    raise exception 'Line % (%) is a B-grade line — its price comes from the B-grade bin — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  if v_line.free_reason is not null then
    raise exception 'Line % (%) is a free line (%) — it is not re-priced — nothing was saved', v_line.line_no, v_line.sku, v_line.free_reason;
  end if;
  if v_line.price_override then
    raise exception 'Line % (%) has a hand price — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  if v_line.discount_source is distinct from 'shopify' then
    raise exception 'Line % (%) is not a Shopify-priced line (discount source %) — nothing was saved', v_line.line_no, v_line.sku, coalesce(v_line.discount_source, 'none');
  end if;
  if v_line.list_price is null or v_line.list_price <= 0 then
    raise exception 'Line % (%) has no list price — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  v_unit := v_line.list_price * (1 - p_pct / 100);
  if v_unit = 0 then
    raise exception 'Line % (%): a % %% discount would make it a free line — nothing was saved', v_line.line_no, v_line.sku, p_pct;
  end if;
  update public.so_line
     set discount_pct = p_pct, unit_price = v_unit, discount_source = 'shopify', deal_line_id = null, price_override = false
   where id = v_line.id
  returning * into v_line;
  return v_line;
end;
$$;
revoke all on function public.so_line_set_shopify_rule(uuid, numeric) from public, anon, authenticated;
comment on function public.so_line_set_shopify_rule(uuid, numeric) is 'shop-disc-1 판정 997 · 999 · 1003 · 1008: 웹(Shopify) 줄 하나를 IMS 할인 식으로 — 정가 그대로 · discount_pct = p · unit_price = 정가 × (1 − p/100)(IMS 줄과 같은 식 · 줄 금액 = round(수량 × 단가, 2)) · 출처 shopify 그대로(433 · 다시 매기기가 건너뛴다) · deal null · price_override false · 오더를 for update 로 잡고 유효 인보이스가 있으면 거부 · cancelled 거부 · 인보이스 전이면 상태 무관(confirmed · picking · packed · shipped) · 콤보 구성품 · B급 · 무상 · 출처 ≠ shopify · 손 가격 · 정가 없음 · 단가 0(p 100) 거부 · 수량 · 예약 · WMS · price_set_by · shop_order_line 무접촉 · updated_by 는 so_line_touch 가 auth.uid() 로 적는다(호출자가 신원을 세운다: shop_order_process = shop_system_enter) · service_role 만 · 부르는 곳: shop_order_process ⑥-b(들여올 때) · shop-disc-2 ops 스크립트(열린 오더 한 번 바로잡기)';

-- ═══ ③ shop_order_process 재발행 — 원본 DB 바이트(md5 fac48d11 · 171 줄) + 더한 줄만(26 · 지운 줄 0) · 서명 · 권한 · comment 그대로 + 토막 ═══
create or replace function public.shop_order_process(p_shop_order_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o       public.shop_order%rowtype;
  v_gws     text[];                                                                                                                  -- 2e-1a 판정 986: 받은 거래의 게이트웨이(소문자 · distinct)
  v_s       public.shop_store%rowtype;
  c         public.customer%rowtype;
  v_prev    jsonb;
  v_so      jsonb;
  v_so_id   uuid;
  v_so_row  public.so%rowtype;
  v_ship    jsonb;
  v_warn    jsonb := '[]'::jsonb;
  v_res     jsonb;
  l         record;
  q         record;
  v_line    public.so_line%rowtype;
  v_pct     numeric;
  v_ims_pct numeric;
  v_fl      jsonb;
  v_orig    numeric;
  v_disc    numeric;
  v_ims_tax numeric;
  v_paid    numeric;
  v_conf    jsonb := null;
  v_blocked text := null;
  v_po      text;
  v_note    text;
  v_n_lines int := 0;
  v_pickup  boolean := false;  v_dlv record;  v_car public.ref_carrier%rowtype;  v_rule text;  v_src text;  v_tax jsonb;  v_a record;   -- ful-1b 판정 454: 픽업 오더(v_a — 원문 select 의 별칭 a 를 가리지 않게)
  v_fit boolean;  v_ims_unit numeric;  v_ldiff numeric;  v_fix jsonb := '[]'::jsonb;  v_rnd jsonb := '[]'::jsonb;  v_f record;  v_n_fix int := 0;  v_sum_diff numeric := 0;   -- shop-disc-1 판정 996 · 1001 · 1004 · 1007: asung.ca 줄 고침 후보(v_fix) · 고친 줄(v_rnd)
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_process: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.status <> 'received' then
    return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'not received (' || v_o.status || ')');
  end if;
  if v_o.shopify_cancelled_at is not null then                                                                               -- 판정 434: SO 가 생기기 전에 취소됐다
    return public.shop_order_cancelled(v_o.id);
  end if;
  if v_o.customer_id is null or v_o.location_id is null or jsonb_array_length(v_o.reasons) > 0 then
    update public.shop_order set status = 'needs_review' where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'needs_review', 'skipped', true, 'message', 'prepare left reasons or no customer / warehouse');
  end if;
  select * into v_s from public.shop_store s where s.id = v_o.store_id;
  select * into c from public.customer x where x.id = v_o.customer_id;
  v_ship := v_o.raw->'shippingAddress';
  v_po   := coalesce(nullif(trim(v_o.raw->>'poNumber'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('purchase_order(po)', 'purchase_order', 'po') limit 1));
  v_note := coalesce(nullif(trim(v_o.raw->>'note'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('order note', 'order_note', 'note') limit 1));
  select * into v_dlv from public.shop_order_delivery(v_o.raw);
  v_pickup := coalesce(v_o.delivery_method, v_dlv.method) = 'PICK_UP';                                                                   -- ful-1b 판정 454(칸은 ingest 가 · 없으면 raw 로)

  begin                                                                                                                      -- 실패하면 여기까지 되감긴다(SO 없음 · claims 도 되감김) → status error
    v_prev := public.shop_system_enter();
    -- ① 머리(so_create 그대로 · intake shopify · 손님 값 복사 · 오더 할인은 손님 딜로 찾힌다 → 아래서 0 으로)
    v_so := public.so_create(c.id, 'warehouse', 'shopify', v_o.location_id, null);
    v_so_id := (v_so->>'id')::uuid;
    v_warn := v_warn || public.shop_order_overdue_warning(c.id);                                                                          -- ovd-1 판정 769 · 770 · 771: 청구처에 연체 인보이스가 있으면 경고 원소 customer_overdue(그때 값 · 금액 · 「at the time the order came in」 · 없으면 빈 배열) — 막지 않는다 · 뒤의 created 갱신이 warnings || v_warn 으로 싣는다
    -- ② 줄 — 단가 = Shopify 할인 뒤(판정 367 · 431 ③) · 같은 SKU 가 둘이어도 새 줄(p_force_new) · 0 원 줄은 promotion
    for l in select x.* from public.shop_order_line x where x.shop_order_id = v_o.id and x.match = 'ok' order by x.line_no loop
      v_res := public.so_line_add(v_so_id, l.product_id, l.quantity, coalesce(l.unit_price, 0), null, case when coalesce(l.unit_price, 0) = 0 then 'promotion' end, null, true);
      if v_res->>'action' <> 'added' then raise exception 'shop_order_process: line % (%) was not added (%) — nothing was saved', l.line_no, l.sku, v_res->>'action'; end if;
      v_pct := case when coalesce(l.list_price, 0) > 0 then round((l.list_price - coalesce(l.unit_price, 0)) / l.list_price * 100, 2) else 0 end;
      v_line := public.so_line_set_shopify((v_res->'line'->>'id')::uuid, l.list_price, greatest(0, least(100, v_pct)));
      update public.shop_order_line set so_line_id = v_line.id where id = l.id;
      v_n_lines := v_n_lines + 1;
      -- 할인 어긋남(판정 431 ③) — IMS 규칙(so_line_quote: 손님 기본 · 딜 · 세트)으로 셈한 % 와 대조 · 0.1 % 안은 같은 것(돈 반올림) · IMS 값으로 바꾸지 않는다
      select * into v_so_row from public.so where id = v_so_id;
      select * into q from public.so_line_quote(v_so_row, l.product_id, l.quantity);
      v_ims_pct := coalesce(q.discount_pct, 0);
      if v_s.kind = 'asung' then                                                                                                     -- shop-disc-1 판정 996 · 1001 · 1006 · 1007: asung.ca 줄 — 범위 = 단가 꼴(shop_line_rule_fit: Shopify 단가 = round(Shopify 정가 × (1 − p/100), 2)) · 범위 안 ∧ 정가 같음 ∧ (지금 % ≠ p ∨ 단가 ≠ 정가 × (1 − p/100)) 이면 ⑥ 뒤에 ② 로 고칠 후보 · 범위 밖은 1 센트라도 금액 경고(Shopify 값 유지) · 정가 다른 줄은 list_price_mismatch 가 따로(아래 그대로)
        v_ims_unit := case when coalesce(l.list_price, 0) > 0 then l.list_price * (1 - v_ims_pct / 100) end;                                                        -- 1001 의 기준값 = Shopify 정가 × (1 − p/100)
        v_fit := public.shop_line_rule_fit(l.list_price, l.unit_price, v_ims_pct);
        if v_fit and q.list_price is not null and l.list_price is not null and abs(q.list_price - l.list_price) <= 0.005
           and (v_line.discount_pct is distinct from v_ims_pct or v_line.unit_price is distinct from round(v_ims_unit, 7)) then                                   -- 이견 1: % 가 같아도 단가가 다른 줄(정가 199.99 · 7 % → 185.99 ≠ 185.9907)도 고친다 · numeric(18,7)
          v_fix := v_fix || jsonb_build_object('line_id', v_line.id, 'line_no', l.line_no, 'sku', l.sku, 'qty', l.quantity, 'pct', v_ims_pct, 'shopify_unit', l.unit_price);
        elsif not v_fit then
          v_ldiff := round(l.quantity * coalesce(v_ims_unit, 0), 2) - round(l.quantity * coalesce(l.unit_price, 0), 2);                                             -- line_diff = IMS 금액 − Shopify 금액(양수 = IMS 식이면 손님이 더 낸다)
          v_warn := v_warn || jsonb_build_object('code', 'discount_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_pct', v_pct, 'ims_pct', v_ims_pct, 'ims_source', q.discount_source,
                                                 'shopify_unit', l.unit_price, 'ims_unit', v_ims_unit, 'line_diff', v_ldiff,
                                                 'message', format('Line %s %s: Shopify unit price %s but the IMS rule (%s%% %s) gives %s — line differs by %s — the Shopify price was kept', l.line_no, l.sku, l.unit_price, v_ims_pct, coalesce(q.discount_source, 'none'), round(coalesce(v_ims_unit, 0), 4), v_ldiff));
        end if;
      else                                                                                                                             -- shop-disc-1: aone 은 아래 옛 줄 그대로(판정 431 ③ · 0.1 % 문턱)
      if abs(v_pct - v_ims_pct) > 0.1 then
        v_warn := v_warn || jsonb_build_object('code', 'discount_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_pct', v_pct, 'ims_pct', v_ims_pct, 'ims_source', q.discount_source,
                                               'message', format('Line %s %s: Shopify discount %s%% but IMS rules give %s%% (%s) — the Shopify price was kept', l.line_no, l.sku, v_pct, v_ims_pct, coalesce(q.discount_source, 'none')));
      end if;
      end if;                                                                                                                          -- shop-disc-1
      if q.list_price is not null and l.list_price is not null and abs(q.list_price - l.list_price) > 0.005 then
        v_warn := v_warn || jsonb_build_object('code', 'list_price_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_list', l.list_price, 'ims_list', q.list_price,
                                               'message', format('Line %s %s: Shopify list price %s but IMS tier price %s — the Shopify price was kept', l.line_no, l.sku, l.list_price, q.list_price));
      end if;
    end loop;
    if v_n_lines = 0 then raise exception 'shop_order_process: no matched lines — nothing was saved'; end if;
    -- ③ 머리 — ref · 메모(PO · Order Note) · 배송지 = Shopify 배송지(so_header_update 가 세금 규칙을 배송지로 다시 고른다 · 368) · ful-1b: 픽업 오더는 따로(454)
    if v_pickup then
      -- ful-1b 판정 454: 픽업 오더 — 배송지 주소는 비운다(contact · phone 만 · 누가 찾아가는지) · 세금 주 = 손님 주소 차례(오더 배송지 → 청구지 → Shopify 손님 기본 주소 → IMS 손님 주소(Billing 먼저) → 픽업 창고의 주) 중 규칙이 있는 첫 것
      --   → so_header_update 의 tax_rule 열쇠(so_tax_set_manual · manual = true — Caleb 이 SO-25086 에서 손으로 한 모양) · 운송사 = 표의 Pickup 미리 채움(판정 379 · 452 의 PICK_UP 검사를 지난다) · 깨끗하면 ⑧ 이 자동 확정
      for v_a in
        select 1 as ord, 'order shipping address' as src, v_ship->>'countryCodeV2' as country, v_ship->>'provinceCode' as state
        union all select 2, 'order billing address', v_o.raw->'billingAddress'->>'countryCodeV2', v_o.raw->'billingAddress'->>'provinceCode'
        union all select 3, 'Shopify customer default address', v_o.raw->'customer'->'defaultAddress'->>'countryCodeV2', v_o.raw->'customer'->'defaultAddress'->>'provinceCode'
        union all select 10 + (row_number() over (order by (ca.type = 'Billing') desc, ca.is_default_for_type desc, ca.created_at))::int, 'IMS customer ' || coalesce(ca.type, '') || ' address', ca.country, ca.state_province
                    from public.customer_address ca where ca.customer_id = c.id and ca.is_active
        union all select 99, 'pickup warehouse ' || w.name, w.country, w.state_province from public.ref_warehouse w where w.id = v_o.location_id
        order by 1
      loop
        if nullif(trim(coalesce(v_a.state, '')), '') is null then continue; end if;
        v_tax := public.so_tax_rule_for(v_a.country, v_a.state, null, 'sale');
        if v_tax->>'rule' is not null then v_rule := v_tax->>'rule'; v_src := v_a.src; exit; end if;
      end loop;
      perform public.so_header_update(v_so_id, jsonb_build_object(
        'ref', v_o.name,
        'comments', nullif(concat_ws(' · ', 'PICKUP' || coalesce(' ' || v_dlv.location_name, ''), case when v_po is not null then 'PO ' || v_po end, v_note, 'Shopify ' || v_s.code || ' ' || v_o.name), ''),
        'ship_to_company', null::text, 'ship_to_contact', coalesce(nullif(trim(v_ship->>'name'), ''), nullif(trim(v_o.raw->'customer'->>'displayName'), '')), 'ship_to_phone', coalesce(nullif(trim(v_o.raw->>'phone'), ''), nullif(trim(v_ship->>'phone'), '')),
        'ship_to_line1', null::text, 'ship_to_line2', null::text, 'ship_to_city', null::text, 'ship_to_state_province', null::text, 'ship_to_postal_code', null::text, 'ship_to_country', null::text)
        || case when v_rule is not null then jsonb_build_object('tax_rule', v_rule) else '{}'::jsonb end);
      if v_rule is null then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_tax_unknown', 'message', 'Pickup order: no tax rule found from the customer address or the pickup warehouse — pick a tax rule on the order');
      elsif v_src like 'pickup warehouse%' then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_tax_from_location', 'rule', v_rule, 'source', v_src, 'message', format('Pickup order: no customer address with a tax rule — tax rule %s taken from the %s', v_rule, v_src));
      end if;
      select * into v_car from public.ref_carrier rc where rc.kind = 'pickup' and rc.is_active order by rc.name limit 1;
      if v_car.id is null then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_carrier_missing', 'message', 'Pickup order: no active Pickup carrier on the carrier list — pick the carrier before Ship & invoice');
      else
        update public.so set carrier_id = v_car.id, carrier = v_car.name where id = v_so_id;                                           -- so_header_update 엔 carrier_id 열쇠가 없다(ful-1a 는 so_finalize 만 고쳤다) · definer 안 · draft · 같은 칸을 쓰는 창구는 so_copy_customer(손님 기본) · so_finalize(①에서 푼 값)
      end if;
    else
      perform public.so_header_update(v_so_id, jsonb_build_object(                                                                -- null 도 보낸다 — SO 배송지 = Shopify 배송지 그대로(손님 기본 주소가 남지 않게)
        'ref', v_o.name,
        'comments', nullif(concat_ws(' · ', case when v_po is not null then 'PO ' || v_po end, v_note, 'Shopify ' || v_s.code || ' ' || v_o.name), ''),
        'ship_to_company', nullif(trim(v_ship->>'company'), ''), 'ship_to_contact', nullif(trim(v_ship->>'name'), ''), 'ship_to_phone', coalesce(nullif(trim(v_ship->>'phone'), ''), nullif(trim(v_o.raw->>'phone'), '')),
        'ship_to_line1', nullif(trim(v_ship->>'address1'), ''), 'ship_to_line2', nullif(trim(v_ship->>'address2'), ''), 'ship_to_city', nullif(trim(v_ship->>'city'), ''),
        'ship_to_state_province', coalesce(nullif(trim(v_ship->>'provinceCode'), ''), nullif(trim(v_ship->>'province'), '')), 'ship_to_postal_code', nullif(trim(v_ship->>'zip'), ''),
        'ship_to_country', coalesce(nullif(trim(v_ship->>'countryCodeV2'), ''), nullif(trim(v_ship->>'country'), ''))));
    end if;
    -- ④ 오더 전체 할인 — 손님이 본 금액 그대로(431 ③): 손님 딜로 찾힌 오더 할인은 0(manual) 으로 · 경고
    select * into v_so_row from public.so where id = v_so_id;
    if coalesce(v_so_row.order_discount_pct, 0) > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'order_discount_dropped', 'ims_pct', v_so_row.order_discount_pct, 'source', v_so_row.order_discount_source,
                                             'message', format('IMS would give an order discount of %s%% (%s) — not applied, the Shopify amounts were kept', v_so_row.order_discount_pct, v_so_row.order_discount_source));
      perform public.so_header_update(v_so_id, '{"order_discount_pct": 0}'::jsonb);
    end if;
    -- ⑤ 운임 — aone(판정 369: 손님이 낸 배송비 · 무료 배송 = 운임 + 100 %) · asung(판정 473 · frt-1a: Shopify 운임을 SO 운임 줄에 견적으로 · 정보 원소 freight_estimate_from_shopify · Ship & invoice 가 고친다) — 속 함수 shop_order_freight 한 곳(운임 0 · 픽업 · NetTerm 은 줄 없음)
    v_warn := v_warn || public.shop_order_freight(v_so_id, v_s.kind, v_o.name, v_o.raw->'shippingLines'->'nodes'->0);
    -- ⑥ 세금(판정 368) — IMS 가 셈한 세금 ↔ Shopify totalTax
    select t.tax into v_ims_tax from public.so_totals_many(array[v_so_id]) t;
    if v_o.total_tax is not null and abs(coalesce(v_ims_tax, 0) - v_o.total_tax) > 0.005 then
      v_warn := v_warn || jsonb_build_object('code', 'tax_mismatch', 'ims', round(coalesce(v_ims_tax, 0), 2), 'shopify', v_o.total_tax,
                                             'message', format('IMS tax %s but Shopify charged %s — check the tax rule and the ship-to province', round(coalesce(v_ims_tax, 0), 2), v_o.total_tax));
    end if;
    -- ⑥-b shop-disc-1 판정 996 · 999 · 1002 · 1003 · 1004: asung.ca 범위 안 줄을 IMS 셈으로 — 세금 대조(⑥ · Shopify 값으로) 뒤 · Confirm(⑧) 앞 · ② so_line_set_shopify_rule(% = p · 단가 = 정가 × (1 − p/100) · 출처 shopify 그대로) · 고친 줄이 있으면 정보 원소 web_discount_rounded 하나(settled_at · 열린 경고 아님) · ④ 가 오더 할인을 manual 0 으로 굳혔으므로 repick 트리거는 건너뛴다(이견 6)
    if v_s.kind = 'asung' and jsonb_array_length(v_fix) > 0 then
      for v_f in select x.* from jsonb_to_recordset(v_fix) as x(line_id uuid, line_no int, sku text, qty numeric, pct numeric, shopify_unit numeric) loop
        v_line := public.so_line_set_shopify_rule(v_f.line_id, v_f.pct);
        v_ldiff := round(v_f.qty * v_line.unit_price, 2) - round(v_f.qty * coalesce(v_f.shopify_unit, 0), 2);                                                   -- line_diff = IMS 금액 − Shopify 금액
        v_n_fix := v_n_fix + 1;  v_sum_diff := v_sum_diff + v_ldiff;
        v_rnd := v_rnd || jsonb_build_object('line_no', v_f.line_no, 'sku', v_f.sku, 'pct', v_f.pct, 'shopify_unit', v_f.shopify_unit, 'ims_unit', v_line.unit_price, 'line_diff', v_ldiff);
      end loop;
      v_warn := v_warn || jsonb_build_object('code', 'web_discount_rounded', 'at', now(), 'settled_at', now(), 'lines', v_n_fix, 'total_diff', v_sum_diff, 'detail', v_rnd,
                                             'message', format('%s web line(s) re-priced with the IMS discount rule (Shopify rounded per unit) — order total %s%s', v_n_fix, case when v_sum_diff >= 0 then '+' else '' end, v_sum_diff));
    end if;
    -- ⑦ 결제(판정 370) — aone 카드 · Shopify 가 받음 → 오더에 묶인 선결제 · asung NetTerm(pending) 은 없음
    if v_s.kind = 'aone' and upper(coalesce(v_o.financial_status, '')) = 'PAID' and coalesce(v_o.total, 0) > 0 then
      v_paid := round(v_o.total, 2);
      select array_agg(distinct lower(trim(t->>'gateway'))) into v_gws                                                                    -- 2e-1a 판정 986: 받은 거래(CAPTURE · SALE · SUCCESS)의 게이트웨이가 paypal 뿐이면 method paypal(계좌 기본값 _124_ PayPal) · 섞이거나 없으면 shopify 그대로
        from jsonb_array_elements(coalesce(case when jsonb_typeof(v_o.raw->'transactions') = 'array' then v_o.raw->'transactions' end, '[]'::jsonb)) t
       where upper(coalesce(t->>'kind', '')) in ('CAPTURE', 'SALE') and upper(coalesce(t->>'status', '')) = 'SUCCESS';
      v_res := public.so_payment_add(jsonb_build_object('customer_id', c.id, 'amount', v_paid, 'method', case when v_gws = array['paypal'] then 'paypal' else 'shopify' end, 'reference', v_o.name, 'warehouse_id', v_o.location_id,
                                                        'note', 'Shopify ' || v_s.code || ' ' || v_o.name || ' (paid online)', 'target_so_ids', jsonb_build_array(v_so_id)));
      insert into public.shop_order_transaction (transaction_gid, shop_order_id, so_payment_id, kind, gateway, amount, currency_code, processed_at, source)             -- pay-3a 판정 470: ⑦ 이 적은 결제의 거래 표지 — 받기가 raw 의 SALE · CAPTURE 를 「새 거래」로 다시 적지 않게(raw 비교와 별개로 남긴다)
      select t->>'id', v_o.id, (v_res->>'payment_id')::uuid, upper(t->>'kind'), t->>'gateway', (t->'amountSet'->'shopMoney'->>'amount')::numeric, upper(t->'amountSet'->'shopMoney'->>'currencyCode'), nullif(t->>'processedAt', '')::timestamptz, 'process'
        from jsonb_array_elements(coalesce(case when jsonb_typeof(v_o.raw->'transactions') = 'array' then v_o.raw->'transactions' end, '[]'::jsonb)) t
       where upper(coalesce(t->>'kind', '')) in ('CAPTURE', 'SALE') and upper(coalesce(t->>'status', '')) = 'SUCCESS' and coalesce(t->>'id', '') ~ '^gid://shopify/OrderTransaction/[0-9]+$' and nullif(t->'amountSet'->'shopMoney'->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
      on conflict (transaction_gid) do nothing;
    end if;
    -- ⑧ 확정(판정 371) — 막히면 draft 로 두고 까닭을 경고에
    begin
      v_conf := public.so_confirm(v_so_id);
    exception when others then
      v_blocked := sqlerrm;
    end;
    if v_blocked is not null then
      v_warn := v_warn || jsonb_build_object('code', 'confirm_blocked', 'message', v_blocked);
    end if;
    perform public.shop_system_leave(v_prev);
  exception when others then
    update public.shop_order set status = 'error', error = left(sqlerrm, 1000), processed_at = now() where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'error', 'error', left(sqlerrm, 1000));
  end;

  update public.shop_order set status = 'created', so_id = v_so_id, processed_at = now(), so_baseline_at = now(), error = null, warnings = warnings || v_warn where id = v_o.id;
  select * into v_so_row from public.so where id = v_so_id;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', 'created', 'so_id', v_so_id, 'so_number', v_so_row.so_number, 'so_status', v_so_row.status, 'lines', v_n_lines,
                            'confirmed', v_blocked is null, 'confirm', v_conf, 'payment', v_paid, 'warnings', v_warn, 'pickup', v_pickup, 'tax_rule', v_rule, 'tax_source', v_src);   -- ful-1b
end;
$$;
do $$
begin
  execute format('comment on function public.shop_order_process(uuid) is %L', coalesce(obj_description('public.shop_order_process(uuid)'::regprocedure, 'pg_proc'), '') || ' · ⭐ shop-disc-1 판정 996 · 999 · 1001 · 1002 · 1004 · 1006 · 1007: asung.ca(스토어 kind asung) 줄은 범위(shop_line_rule_fit · 단가 꼴) 안 ∧ Shopify 정가 = IMS 정가 ∧ (% ≠ p ∨ 단가 ≠ 정가 × (1 − p/100)) 이면 ⑥ 세금 대조 뒤 · ⑧ Confirm 앞에 so_line_set_shopify_rule 로 % = p · 단가 = 정가 × (1 − p/100)(출처 shopify 그대로) · 고친 줄이 있으면 정보 원소 web_discount_rounded(at · settled_at · lines · total_diff · detail) · 범위 밖은 1 센트라도 discount_mismatch(shopify_pct · ims_pct · ims_source + shopify_unit · ims_unit · line_diff = IMS 금액 − Shopify 금액) · 정가 다른 줄은 손대지 않음(list_price_mismatch) · aone 길은 옛 0.1 % 문턱 그대로(else 안 · 무변)');
end $$;

-- ═══ ④ 착지 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_line_rule_fit', 'so_line_set_shopify_rule', 'shop_order_process', 'so_line_set_shopify', 'so_line_quote'))
     <> 'shop_line_rule_fit=79e97664d125c2469feafc3794a0957d shop_order_process=b9cef38b5a641873f2103c7d58b18cac so_line_quote=84366f59d10e4f140bda924e40beec4f so_line_set_shopify=f5bd0d5f9cbe2e1d15e9441068e9cb51 so_line_set_shopify_rule=4cd4df37bcb144536e86abb14306c3fa' then v_bad := v_bad || ' bodies'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_line_rule_fit', 'so_line_set_shopify_rule', 'shop_order_process', 'so_line_set_shopify', 'so_line_quote')) <> 5 then v_bad := v_bad || ' overloads'; end if;
  if has_function_privilege('authenticated', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute') or has_function_privilege('anon', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.shop_order_process(uuid)', 'execute') or has_function_privilege('anon', 'public.shop_order_process(uuid)', 'execute')
     or has_function_privilege('anon', 'public.shop_line_rule_fit(numeric, numeric, numeric)', 'execute') then v_bad := v_bad || ' privileges'; end if;
  if not has_function_privilege('service_role', 'public.so_line_set_shopify_rule(uuid, numeric)', 'execute') or not has_function_privilege('authenticated', 'public.shop_line_rule_fit(numeric, numeric, numeric)', 'execute') then v_bad := v_bad || ' grants'; end if;
  if not public.shop_line_rule_fit(10.99, 5.50, 50) or not public.shop_line_rule_fit(1.49, 1.39, 7) or public.shop_line_rule_fit(6.49, 6.03, 7) or public.shop_line_rule_fit(null, 1, 7) or public.shop_line_rule_fit(1.49, 1.39, null) then v_bad := v_bad || ' fit'; end if;
  if (select prosrc from pg_proc where oid = 'public.shop_order_process(uuid)'::regprocedure) not like '%so_line_set_shopify_rule(v_f.line_id, v_f.pct)%' then v_bad := v_bad || ' process_calls_rule'; end if;
  if v_bad <> '' then raise exception 'shop-disc-1 landing check failed:%', v_bad; end if;
end $$;
-- 끝 — 적용 뒤: supabase/tests/shop_disc_1_check.sql(-v mig 없이) · 새 웹 오더 하루 관찰(web_discount_rounded · discount_mismatch · tax_mismatch) → shop-disc-2
