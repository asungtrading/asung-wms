-- ─────────────────────────────────────────────────────────────
-- 손님 만들기 창구 · 돈 조건 기본값 · 같은 이름 알림 · 새 손님 확인(Action Centre) (Asung-IMS · master-cs-2a · 2026-10-05)
--   정본(뒤에 적는다): so-module §41 — 판정 236 ~ 240 · master-cs 묶음 1 ~ 9 · master-cs-1 보고 §5 돈 칸 · 조사 master-cs-0 §D4
--   판정 237  만들기 · 일반 칸은 일하는 열쇠(손님 = sales 쓰기 · master 도) · 돈 조건 칸은 master 만
--   판정 238  같은 이름(띄어쓰기 하나로 접고 대소문자 무시)의 손님이 있으면 알리고 확인(ack) — 막지 않는다(다른 가게가 같은 이름일 수 있다 · 접은 이름 겹침 2 쌍이 이미 있다)
--   판정 239  sales 가 만들 때 돈 칸은 정해 둔 기본값(inv_config · Settings 한 곳)으로 — 티어 Wholesale · 할인 0 · 결제조건 C.B.S · 통화 CAD · 기본 계정 · master 는 처음부터 정한다
--   판정 240  sales 가 만든 새 손님은 Action Centre 「New customers to review」 — master 가 Reviewed 를 누르면 빠진다(reviewed_by · reviewed_at) · 돈 칸을 바꾸면 확인으로 친다(cs-2b 의 일 · 여기선 자리만) · 대상 = IMS 에서 sales 가 만든 손님만
--   든 것: ① customer.reviewed_by · reviewed_at ② inv_config 기본값 키 일곱(잠금 밖 문자열 · ims_config_locked_keys 밖 · surcharge-2b so_surcharge_account_code 선례 · 있으면 두기)
--         ③ customer_create(p_customer, p_commit, p_ack) — definer · 문 = sales 또는 master 쓰기 · prod-3 모양(두 번 부르기 · 막기 · 알리기 · ack · 한 트랜잭션) · 주소 · 연락처를 한 호출에(묶음 4 · 「기본 하나」 deferrable 안에서)
--         ④ customer_review(p_customer_id, p_commit) — master 만 · reviewed 채움 ⑤ 뷰 customer_review_list(security_invoker · source manual · reviewed_at null · 활성 · 만든 사람 · 오더 수)
--   돈 칸(master 만 · master-cs-1 보고 §5 + 청구 구조 셋): price_tier · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · is_bill_parent · invoice_split_by_store
--   막기(code)  name_missing · money_field_not_allowed · default_missing · tier_invalid · payment_term_invalid · currency_invalid · ar_account_invalid · sale_account_invalid · discount_invalid · warehouse_unknown
--               parent_unknown · parent_has_parent · bill_to_unknown · ship_to_unknown · address_type_invalid · address_empty · address_default_many · contact_empty · contact_default_many · consent_invalid
--   알리기(code) name_exists(활성 · 같은 접은 이름 · 판정 238) · name_matches_inactive(꺼진 손님만 같다 — 다시 켤 자리일 수 있다) · shipping_address_missing(so_copy_customer 가 오더마다 ship_to_empty 를 낸다) · billing_address_missing(오더마다 bill_to_empty) · tier_currency_mismatch
--   경고 열쇠 = <code>(손님 하나 = 한 호출이라 접두가 필요 없다)
--   반환 { committed, customer_id, name, review_required, defaults_used:[field…], address_ids:[…], contact_ids:[…], blocks:[{key, code, message}], warnings:[{key, code, message, matches?}], unacked:[key…] }
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 기존 함수 재발행 0 · 손님 표 셋은 cs-1 로 닫혀 있어 이 창구(definer)가 유일한 만들기 길
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

-- ═══ 1) customer 확인 칸 둘 (판정 240) · 옛 행 무접촉(Cin7 손님은 대상이 아니다 — null 이어도 목록에 안 오른다) ═══
alter table public.customer add column if not exists reviewed_by uuid references public.ims_staff (id) on delete no action;
alter table public.customer add column if not exists reviewed_at timestamptz;
create index if not exists customer_reviewed_by_idx on public.customer (reviewed_by);
comment on column public.customer.reviewed_by is 'master-cs-2a(판정 240) — IMS 에서 sales 가 만든 손님을 master 가 확인한 사람(ims_staff.id) · master 가 직접 만들면 만들 때 채워진다 · Cin7 손님 · 옛 행은 null(대상 아님) · 돈 칸을 고치면 확인으로 친다(cs-2b)';
comment on column public.customer.reviewed_at is 'master-cs-2a(판정 240) — 확인 시각 · null 이고 source manual 이고 활성이면 Action Centre 「New customers to review」(뷰 customer_review_list)에 오른다';

-- ═══ 2) 돈 조건 기본값 — inv_config 키 일곱 (판정 239 · 잠금 밖 문자열 · 있으면 두기 · seed = 활성 손님 최빈값 · 결제조건만 판정 239 의 C.B.S) ═══
insert into public.inv_config (key, value, note) values
  ('customer_default_price_tier',        'Wholesale',                    'master-cs-2a(판정 239) — sales 가 만든 새 손님의 가격 티어(ref_price_tier.name · purpose sale · 활성) · 활성 손님 7,413/9,461 이 Wholesale · master 가 바꾼다'),
  ('customer_default_discount_pct',      '0',                            'master-cs-2a(판정 239) — 새 손님의 할인 %(0 ~ 100) · 활성 손님 9,389/9,461 이 0'),
  ('customer_default_payment_term',      'C.B.S (Cash Before Shipment)', 'master-cs-2a(판정 239) — 새 손님의 결제조건(ref_payment_term.name · 활성) · 판정 239 「선결제」 — 최빈값은 Net30(6,305) 이지만 새 손님은 선결제부터 · ⚠️ 이름 글자 그대로(비활성 C.B.S. 와 다르다)'),
  ('customer_default_currency_code',     'CAD',                          'master-cs-2a(판정 239) — 새 손님의 통화(ref_currency.code) · 활성 손님 9,458/9,461 이 CAD'),
  ('customer_default_ar_account_code',   '_61_',                         'master-cs-2a(판정 239) — 새 손님의 매출채권 계정(ref_account.code) · 활성 손님 9,454/9,461 이 _61_ Accounts Receivable (A/R)'),
  ('customer_default_sale_account_code', '_98_',                         'master-cs-2a(판정 239) — 새 손님의 매출 계정(ref_account.code) · 활성 손님 9,459/9,461 이 _98_ Sales Account'),
  ('customer_default_location_name',     'Asung Trading Inc.',           'master-cs-2a — 새 손님의 기본 창고(ref_warehouse.name · 활성) · 돈 칸이 아니다(sales 도 바꿀 수 있다) · 비우면 그 손님의 오더는 확정 전에 창고를 골라야 한다 · 활성 손님 9,320/9,461 이 Asung Trading Inc.')
on conflict (key) do nothing;

-- ═══ 3) 만들기 창구 ═══
--   p_customer = { name*, display_name, note, tax_rule, default_location_id, default_carrier, tax_number, tags, is_legal_entity, parent_id, default_ship_to_customer_id,
--                  [master 만] price_tier(이름) · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · is_bill_parent · invoice_split_by_store,
--                  addresses:[{type(Billing|Business|Shipping)*, line1, line2, city, state_province, postal_code, country, label, is_default_for_type}],
--                  contacts:[{name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent(0·1·2·3 숫자 또는 null — asung-so 스킬 ⚠️), is_default}] }
--   돈 칸이 요청에 있고 부른 사람이 master 가 아니면 막는다(조용히 버리지 않는다) · 없으면 기본값(기본값 키가 비었거나 가리키는 행이 없거나 꺼졌으면 막는다 — master 가 그 칸을 직접 줬으면 지나간다)
--   「기본 하나」: 주소는 type 마다 · 연락처는 손님당 — 표시가 없으면 첫 줄이 기본 · 둘 이상 표시하면 막기 · 한 트랜잭션이라 deferrable 안에서 순서와 무관
create or replace function public.customer_create(p_customer jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_master    boolean;
  v_blocks    jsonb := '[]'::jsonb;
  v_warns     jsonb := '[]'::jsonb;
  v_defaults  text[] := '{}';
  v_name      text;
  v_folded    text;
  v_matches   jsonb;
  v_n_active  int;
  v_n_off     int;
  v_money     text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'is_bill_parent', 'invoice_split_by_store'];
  v_given     text[];
  v_k         text;
  v_tier      public.ref_price_tier%rowtype;
  v_term      public.ref_payment_term%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_ar        public.ref_account%rowtype;
  v_sale      public.ref_account%rowtype;
  v_wh        public.ref_warehouse%rowtype;
  v_parent    public.customer%rowtype;
  v_other     public.customer%rowtype;
  v_disc      numeric;
  v_cfg       text;
  v_a         jsonb;
  v_c         jsonb;
  v_i         int;
  v_type      text;
  v_def_types text[] := '{}';
  v_has_ship  boolean := false;
  v_has_bill  boolean := false;
  v_n_cdef    int := 0;
  v_consent   boolean;
  v_consent_t text;
  v_cid       uuid;
  v_aid       uuid;
  v_addr_ids  jsonb := '[]'::jsonb;
  v_cont_ids  jsonb := '[]'::jsonb;
  v_keys      text[];
  v_unacked   text[];
  v_first_def_by_type jsonb := '{}'::jsonb;
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 와 같은 모양(sales 를 이름한다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_customer is null or jsonb_typeof(p_customer) <> 'object' then
    raise exception 'p_customer must be a JSON object — nothing was saved';
  end if;
  if p_customer ? 'addresses' and jsonb_typeof(p_customer->'addresses') <> 'array' then raise exception 'addresses must be a JSON array — nothing was saved'; end if;
  if p_customer ? 'contacts'  and jsonb_typeof(p_customer->'contacts')  <> 'array' then raise exception 'contacts must be a JSON array — nothing was saved'; end if;

  -- ② 이름 · 같은 이름(판정 238)
  v_name := nullif(btrim(p_customer->>'name'), '');
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', 'name_missing', 'code', 'name_missing', 'message', 'The customer has no name — nothing was saved');
  else
    v_folded := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
           coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active, 'city', (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1))
                              order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
      into v_n_active, v_n_off, v_matches
      from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
    if v_n_active > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_exists', 'code', 'name_exists', 'matches', v_matches,
        'message', format('%s active customer(s) already have this name (%s) — is this really a new customer? Confirm to create it anyway', v_n_active, (select string_agg(coalesce(m->>'name', '') || coalesce(' · ' || (m->>'city'), ''), '; ') from jsonb_array_elements(v_matches) m where (m->>'is_active')::boolean)));
    elsif v_n_off > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_matches_inactive', 'code', 'name_matches_inactive', 'matches', v_matches,
        'message', format('%s inactive customer(s) have this name — reactivating one may be better than a new row. Confirm to create a new customer', v_n_off));
    end if;
  end if;

  -- ③ 돈 칸(판정 237 · 239) — 요청에 든 돈 칸 목록
  select coalesce(array_agg(k order by k), '{}') into v_given from unnest(v_money) as k where p_customer ? k and p_customer->k <> 'null'::jsonb;
  if cardinality(v_given) > 0 and not v_master then
    v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed', 'code', 'money_field_not_allowed',
      'message', format('Only a master user can set %s on a new customer — leave them out and the defaults apply (a master user reviews them later) — nothing was saved', array_to_string(v_given, ', ')));
  end if;

  -- 티어
  if 'price_tier' = any(v_given) and v_master then
    select * into v_tier from public.ref_price_tier t where t.name = btrim(p_customer->>'price_tier') and t.is_active and t.purpose = 'sale';
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'tier_invalid', 'code', 'tier_invalid', 'message', format('Price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', p_customer->>'price_tier')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_price_tier';
    select * into v_tier from public.ref_price_tier t where t.name = v_cfg and t.is_active and t.purpose = 'sale';
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:price_tier', 'code', 'default_missing', 'message', format('The default price tier is not set up (inv_config customer_default_price_tier = %s) — ask a master user to fix the default or to create this customer — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'price_tier'); end if;
  end if;
  -- 할인
  if 'discount_pct' = any(v_given) and v_master then
    v_disc := case when (p_customer->>'discount_pct') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (p_customer->>'discount_pct')::numeric end;
    if v_disc is null or v_disc > 100 then v_blocks := v_blocks || jsonb_build_object('key', 'discount_invalid', 'code', 'discount_invalid', 'message', format('discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', p_customer->>'discount_pct')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_discount_pct';
    v_disc := case when v_cfg ~ '^[0-9]+(\.[0-9]+)?$' and v_cfg::numeric <= 100 then v_cfg::numeric end;
    if v_disc is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:discount_pct', 'code', 'default_missing', 'message', format('The default discount is not set up (inv_config customer_default_discount_pct = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'discount_pct'); end if;
  end if;
  -- 결제조건
  if 'payment_term_id' = any(v_given) and v_master then
    select * into v_term from public.ref_payment_term t where t.id = (p_customer->>'payment_term_id')::uuid and t.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'payment_term_invalid', 'code', 'payment_term_invalid', 'message', 'The payment term does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_payment_term';
    select * into v_term from public.ref_payment_term t where t.name = v_cfg and t.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:payment_term', 'code', 'default_missing', 'message', format('The default payment term is not set up (inv_config customer_default_payment_term = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'payment_term'); end if;
  end if;
  -- 통화
  if 'currency_id' = any(v_given) and v_master then
    select * into v_cur from public.ref_currency c where c.id = (p_customer->>'currency_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'currency_invalid', 'code', 'currency_invalid', 'message', 'The currency does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_currency_code';
    select * into v_cur from public.ref_currency c where c.code = v_cfg and c.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:currency', 'code', 'default_missing', 'message', format('The default currency is not set up (inv_config customer_default_currency_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'currency'); end if;
  end if;
  -- 계정 둘
  if 'ar_account_id' = any(v_given) and v_master then
    select * into v_ar from public.ref_account a where a.id = (p_customer->>'ar_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ar_account_invalid', 'code', 'ar_account_invalid', 'message', 'The receivable account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_ar_account_code';
    select * into v_ar from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:ar_account', 'code', 'default_missing', 'message', format('The default receivable account is not set up (inv_config customer_default_ar_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'ar_account'); end if;
  end if;
  if 'sale_account_id' = any(v_given) and v_master then
    select * into v_sale from public.ref_account a where a.id = (p_customer->>'sale_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'sale_account_invalid', 'code', 'sale_account_invalid', 'message', 'The sales account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_sale_account_code';
    select * into v_sale from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:sale_account', 'code', 'default_missing', 'message', format('The default sales account is not set up (inv_config customer_default_sale_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'sale_account'); end if;
  end if;
  if v_tier.id is not null and v_cur.id is not null and v_tier.currency_id <> v_cur.id then
    v_warns := v_warns || jsonb_build_object('key', 'tier_currency_mismatch', 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the customer currency %s — order prices will not match the currency', v_tier.name, v_cur.code));
  end if;
  -- 청구 구조(master 만 · 값 검사)
  if 'default_bill_to_customer_id' = any(v_given) and v_master then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_bill_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'bill_to_unknown', 'code', 'bill_to_unknown', 'message', 'The bill-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ④ 일반 칸(누구나) — 창고 · 부모 · 배송 손님
  if nullif(p_customer->>'default_location_id', '') is not null then
    select * into v_wh from public.ref_warehouse w where w.id = (p_customer->>'default_location_id')::uuid and w.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'warehouse_unknown', 'code', 'warehouse_unknown', 'message', 'The default warehouse does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_location_name';
    select * into v_wh from public.ref_warehouse w where w.name = v_cfg and w.is_active;       -- 비었거나 없으면 창고 없이 만든다(돈 칸이 아니다 · 오더가 창고를 고른다)
    if v_wh.id is not null then v_defaults := array_append(v_defaults, 'default_location'); end if;
  end if;
  if nullif(p_customer->>'parent_id', '') is not null then
    select * into v_parent from public.customer c where c.id = (p_customer->>'parent_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'parent_unknown', 'code', 'parent_unknown', 'message', 'The parent customer does not exist or is inactive — nothing was saved');
    elsif v_parent.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', 'parent_has_parent', 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_parent.name)); end if;
  end if;
  if nullif(p_customer->>'default_ship_to_customer_id', '') is not null then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_ship_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ship_to_unknown', 'code', 'ship_to_unknown', 'message', 'The ship-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ⑤ 주소 — type 어휘 · 빈 줄 · type 별 기본 하나(표시 없으면 그 type 의 첫 줄)
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := nullif(btrim(v_a->>'type'), '');
    if v_type is null or v_type not in ('Billing', 'Business', 'Shipping') then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_type_invalid:' || v_i, 'code', 'address_type_invalid', 'message', format('Address %s: type must be Billing, Business or Shipping (got %s) — nothing was saved', v_i, coalesce(v_type, '(blank)')));
      continue;
    end if;
    if nullif(btrim(coalesce(v_a->>'line1', '') || coalesce(v_a->>'city', '') || coalesce(v_a->>'postal_code', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_empty:' || v_i, 'code', 'address_empty', 'message', format('Address %s (%s) has no street, city or postal code — nothing was saved', v_i, v_type));
    end if;
    if v_type = 'Shipping' then v_has_ship := true; end if;
    if v_type = 'Billing' then v_has_bill := true; end if;
    if coalesce((v_a->>'is_default_for_type')::boolean, false) then
      if v_type = any(v_def_types) then
        v_blocks := v_blocks || jsonb_build_object('key', 'address_default_many:' || v_type, 'code', 'address_default_many', 'message', format('More than one %s address is marked default — only one per type — nothing was saved', v_type));
      else v_def_types := v_def_types || v_type; end if;
    end if;
    if not (v_first_def_by_type ? v_type) then v_first_def_by_type := v_first_def_by_type || jsonb_build_object(v_type, v_i); end if;
  end loop;
  if not v_has_ship then
    v_warns := v_warns || jsonb_build_object('key', 'shipping_address_missing', 'code', 'shipping_address_missing', 'message', 'No shipping address — every order for this customer will ask for one (ship_to_empty). Confirm to create the customer without it');
  end if;
  if not v_has_bill then
    v_warns := v_warns || jsonb_build_object('key', 'billing_address_missing', 'code', 'billing_address_missing', 'message', 'No billing address — every order for this customer will warn bill_to_empty until one is added. Confirm to create the customer without it');
  end if;

  -- ⑥ 연락처 — 빈 줄 · 동의 숫자 · 기본 하나(표시 없으면 첫 줄)
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_c->>'name', '') || coalesce(v_c->>'phone', '') || coalesce(v_c->>'mobile_phone', '') || coalesce(v_c->>'email', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'contact_empty:' || v_i, 'code', 'contact_empty', 'message', format('Contact %s has no name, phone or email — nothing was saved', v_i));
    end if;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    if v_consent_t is not null and v_consent_t not in ('0', '1', '2', '3') then
      v_blocks := v_blocks || jsonb_build_object('key', 'consent_invalid:' || v_i, 'code', 'consent_invalid', 'message', format('Contact %s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_i, v_consent_t));
    end if;
    if coalesce((v_c->>'is_default')::boolean, false) then v_n_cdef := v_n_cdef + 1; end if;
  end loop;
  if v_n_cdef > 1 then
    v_blocks := v_blocks || jsonb_build_object('key', 'contact_default_many', 'code', 'contact_default_many', 'message', 'More than one contact is marked default — only one per customer — nothing was saved');
  end if;

  -- ⑦ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 모양)
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'customer_id', null, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                              'address_ids', '[]'::jsonb, 'contact_ids', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑧ 저장 — 손님 → 주소 → 연락처 · 한 트랜잭션 · source manual · cin7_id null · created_by · master 면 reviewed 즉시(판정 240)
  insert into public.customer (name, display_name, note, source, is_active, created_by, updated_by,
                               currency_id, currency_code, payment_term_id, payment_term_name, discount_pct, price_tier, tax_rule,
                               default_location_id, default_location_name, ar_account_id, ar_account_code, sale_account_id, sale_account_code,
                               parent_id, is_bill_parent, is_legal_entity, default_ship_to_customer_id, default_bill_to_customer_id, default_carrier, tax_number, tags, invoice_split_by_store,
                               reviewed_by, reviewed_at)
  values (v_name, nullif(btrim(p_customer->>'display_name'), ''), nullif(btrim(p_customer->>'note'), ''), 'manual', true, v_staff, v_staff,
          v_cur.id, v_cur.code, v_term.id, v_term.name, v_disc, v_tier.name, nullif(btrim(p_customer->>'tax_rule'), ''),
          v_wh.id, v_wh.name, v_ar.id, v_ar.code, v_sale.id, v_sale.code,
          nullif(p_customer->>'parent_id', '')::uuid,
          case when v_master then coalesce((p_customer->>'is_bill_parent')::boolean, false) else false end,
          coalesce((p_customer->>'is_legal_entity')::boolean, false),
          nullif(p_customer->>'default_ship_to_customer_id', '')::uuid,
          case when v_master then nullif(p_customer->>'default_bill_to_customer_id', '')::uuid end,
          nullif(btrim(p_customer->>'default_carrier'), ''), nullif(btrim(p_customer->>'tax_number'), ''), nullif(btrim(p_customer->>'tags'), ''),
          case when v_master then coalesce((p_customer->>'invoice_split_by_store')::boolean, false) else false end,
          case when v_master then v_staff end, case when v_master then now() end)
  returning id into v_cid;
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := btrim(v_a->>'type');
    insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country)
    values (v_cid, 'manual', v_staff, v_type,
            case when v_type = any(v_def_types) then coalesce((v_a->>'is_default_for_type')::boolean, false) else (v_first_def_by_type->>v_type)::int = v_i end,
            nullif(btrim(v_a->>'label'), ''), nullif(btrim(v_a->>'line1'), ''), nullif(btrim(v_a->>'line2'), ''), nullif(btrim(v_a->>'city'), ''),
            nullif(btrim(v_a->>'state_province'), ''), nullif(btrim(v_a->>'postal_code'), ''), nullif(btrim(v_a->>'country'), ''))
    returning id into v_aid;
    v_addr_ids := v_addr_ids || to_jsonb(v_aid);
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    v_consent := case v_consent_t when '2' then true when '3' then false else null end;      -- asung-so ⚠️ 2 Opt in · 3 Opt out · 0 · 1 · 없음 = Unknown
    insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
    values (v_cid, 'manual', v_staff, nullif(btrim(v_c->>'name'), ''), nullif(btrim(v_c->>'phone'), ''), nullif(btrim(v_c->>'mobile_phone'), ''), nullif(btrim(v_c->>'fax'), ''),
            nullif(btrim(v_c->>'email'), ''), nullif(btrim(v_c->>'website'), ''), nullif(btrim(v_c->>'job_title'), ''), coalesce((v_c->>'include_in_email')::boolean, false), v_consent,
            case when v_n_cdef = 1 then coalesce((v_c->>'is_default')::boolean, false) else v_i = 1 end)
    returning id into v_aid;
    v_cont_ids := v_cont_ids || to_jsonb(v_aid);
  end loop;

  return jsonb_build_object('committed', true, 'customer_id', v_cid, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                            'address_ids', v_addr_ids, 'contact_ids', v_cont_ids, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.customer_create(jsonb, boolean, text[]) from public, anon;
grant execute on function public.customer_create(jsonb, boolean, text[]) to authenticated;
comment on function public.customer_create(jsonb, boolean, text[]) is
  'master-cs-2a · 판정 237 ~ 240 — 손님 만들기 한 벌(손님 + 주소들 + 연락처들 · 한 트랜잭션) · 문 = sales 또는 master 쓰기 · 두 번 부르기(p_commit false 검사 · true 저장 · 확인 안 받은 경고 열쇠가 있으면 unacked) · 돈 칸(price_tier · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · is_bill_parent · invoice_split_by_store)은 master 만 — sales 가 보내면 막기 money_field_not_allowed · 안 보내면 inv_config customer_default_* 기본값(비었거나 없거나 꺼졌으면 default_missing) · 같은 접은 이름의 활성 손님 → 알리기 name_exists(ack 로 만든다 · 판정 238) · 기본 하나(주소 type 별 · 연락처)는 표시 없으면 첫 줄 · master 가 만들면 reviewed_by/at 즉시 · sales 면 null(Action Centre). 2026-10-05';

-- ═══ 4) 확인 창구 (판정 240) — master 만 · 작은 창구 하나(Action Centre 단추가 cs-2b 를 기다리지 않게) · 「돈 칸을 바꾸면 확인으로 친다」 는 cs-2b customer_update 가 같은 두 칸을 채운다(자리만) ═══
create or replace function public.customer_review(p_customer_id uuid, p_commit boolean default false)
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_c public.customer%rowtype; v_warns jsonb := '[]'::jsonb; v_blocks jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 첫 줄 — Reviewed 는 master 열쇠만(판정 240)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_c from public.customer c where c.id = p_customer_id for update;
  if not found then raise exception 'Customer not found — nothing was saved'; end if;
  if v_c.source <> 'manual' then
    v_blocks := v_blocks || jsonb_build_object('key', 'not_ims_created', 'code', 'not_ims_created', 'message', format('%s came from Cin7 — only customers created in IMS are reviewed — nothing was saved', v_c.name));
  end if;
  if v_c.reviewed_at is not null then
    v_warns := v_warns || jsonb_build_object('key', 'already_reviewed', 'code', 'already_reviewed', 'message', format('%s was already reviewed by %s on %s — nothing to do', v_c.name,
                 coalesce((select s.name from public.ims_staff s where s.id = v_c.reviewed_by), 'system'), to_char(v_c.reviewed_at at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI')));
  end if;
  if jsonb_array_length(v_blocks) > 0 or jsonb_array_length(v_warns) > 0 or not p_commit then
    return jsonb_build_object('committed', false, 'customer_id', v_c.id, 'name', v_c.name, 'reviewed_by', v_c.reviewed_by, 'reviewed_at', v_c.reviewed_at,
                              'money', jsonb_build_object('price_tier', v_c.price_tier, 'discount_pct', v_c.discount_pct, 'payment_term_name', v_c.payment_term_name, 'currency_code', v_c.currency_code, 'ar_account_code', v_c.ar_account_code, 'sale_account_code', v_c.sale_account_code),
                              'blocks', v_blocks, 'warnings', v_warns);
  end if;
  update public.customer set reviewed_by = v_staff, reviewed_at = now(), updated_by = v_staff where id = v_c.id;
  return jsonb_build_object('committed', true, 'customer_id', v_c.id, 'name', v_c.name, 'reviewed_by', v_staff, 'reviewed_at', now(), 'blocks', '[]'::jsonb, 'warnings', '[]'::jsonb);
end;
$$;
revoke all on function public.customer_review(uuid, boolean) from public, anon;
grant execute on function public.customer_review(uuid, boolean) to authenticated;
comment on function public.customer_review(uuid, boolean) is
  'master-cs-2a · 판정 240 — Action Centre 「New customers to review」 의 Reviewed: master 만 · source manual 손님만(Cin7 손님은 막기 not_ims_created) · 이미 확인됐으면 알리기 already_reviewed(쓰지 않는다) · p_commit false 는 돈 칸 요약만 돌려준다 · 돈 칸을 고칠 때의 확인은 cs-2b customer_update 가 같은 두 칸을 채운다. 2026-10-05';

-- ═══ 5) 확인 목록 뷰 (판정 240) — security_invoker · 읽기 권한은 손님 select 와 같다(authenticated) ═══
create or replace view public.customer_review_list
  with (security_invoker = true) as
select c.id as customer_id, c.name, c.display_name, c.created_at, c.created_by, cb.name as created_by_name,
       c.price_tier, c.discount_pct, c.payment_term_name, c.currency_code, c.ar_account_code, c.sale_account_code, c.default_location_name,
       (select count(*) from public.so s where s.customer_id = c.id) as so_count,
       (select count(*) from public.so s where s.customer_id = c.id and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')) as open_so_count,
       (select min(s.created_at) from public.so s where s.customer_id = c.id) as first_order_at,
       (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1) as city
  from public.customer c
  left join public.ims_staff cb on cb.id = c.created_by
 where c.source = 'manual' and c.reviewed_at is null and c.is_active;
revoke all on public.customer_review_list from anon;
grant select on public.customer_review_list to authenticated;
comment on view public.customer_review_list is 'master-cs-2a · 판정 240 — Action Centre 「New customers to review」: IMS 에서 만들었고(source manual) 아직 확인 안 됐고(reviewed_at null) 활성인 손님 · 만든 사람 · 시각 · 돈 칸 · 오더 수(전체 · 열린) · 첫 오더 시각 · 도시 · security_invoker(손님 select 는 authenticated 전부) · 빠지는 길 = customer_review 또는 cs-2b 의 돈 칸 고치기';
