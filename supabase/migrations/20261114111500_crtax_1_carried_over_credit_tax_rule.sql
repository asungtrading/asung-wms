-- supabase/migrations/20261114111500_crtax_1_carried_over_credit_tax_rule.sql — crtax-1: 이월 인보이스에 건 크레딧의 세금 규칙(판정 1215 ~ 1220 · 2026-11-13 ~ 14 · 지시서 ~/asung/prompts/crtax-1.md)
-- 왜: CR-01040(스폰서십 1,000 · other 줄)을 이월 인보이스 49498(so_invoice.kind opening · 오더 0)에서 냈다 → 인보이스 크레딧은 세금 규칙을 그 오더에서 읽는데 오더가 없어 머리 · 줄 규칙이 빈 채 발행 → qbo_credit_body 가 「line 1 has no tax rule to send」 로 멈춤
-- 판정 1215 빈 규칙은 새 창구로 채운다(손 UPDATE 금지) · 1216 북키퍼(manager)가 고른다 — 활성 sale · 세율 0 · 이 realm 의 QBO 세금 코드 짝 ⇒ 금액 · 세금 · 합계 무변 · 1217 앞으로 이월 인보이스 크레딧은 발행 때 규칙을 받는다
-- 판정 1218 발행 commit 은 이월이면 p.tax_rule 필수(제안은 미리 보기 · 준비 창구에서만 · 매장 기본 배송지) · 1219 발행 규칙 = 활성 sale(세율 · QBO 짝 무관 · 목록에 QBO 코드 유무) · 1220 기록 = so_credit 칸 둘(warnings 무접촉)
-- 판별(이견 1): 「오더 없는 인보이스」 = so_invoice 가 있고 so_invoice_order 0 — so_invoice_no_order 한 곳(발행 · 준비 · 채우기 검사가 같이 쓴다 · 지금 kind opening 310 건과 같은 집합)
-- 새 것: so_credit 칸 둘(tax_rule_filled_at · tax_rule_filled_by · 짝 check) · 함수 다섯 — so_invoice_no_order · so_credit_tax_rule_suggest · so_credit_tax_rule_options · so_credit_tax_rule_fill_check · so_credit_tax_rule_fill
-- 재발행 셋(몸 = DB prosrc 원본 2026-11-14 + 더한 줄 · 시그니처 · definer/invoker · volatility · search_path · acl 그대로 · create or replace · drop 없음): so_credit_issue · so_credit_prepare · so_credit_detail
-- 무접촉: qbo_credit_body(인보이스 줄 없는 줄은 머리 규칙을 먼저 읽는다 — 채우면 지나간다) · qbo_job(채우기는 일감을 건드리지 않는다 · 북키퍼가 Retry) · CR-01040 실물(적용 뒤 북키퍼가 화면에서) · 일반 인보이스 크레딧(머리 규칙 null 그대로) · 참조 크레딧 · 화면 · EF
-- 검증 supabase/tests/crtax_1_check.sql(begin → rollback · 번호 함수는 시험 안에서 가짜로 덮는다) · 적용은 사람: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> && supabase migration repair --status applied … · supabase db push 금지
-- ⚠️ 잠금: so_credit 에 칸 둘 + FK(ims_staff) — ACCESS EXCLUSIVE 가 트랜잭션 끝까지 · 토론토 17:00 뒤에만

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

-- ═══ 앞 검사 — 재발행 원본이 2026-11-14 에 읽은 DB prosrc 그대로인가 · 칸 · 새 함수가 아직 없는가 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_issue(jsonb, boolean)'::regprocedure) <> '0f451d71041020768b4b463b248f48a4' then v_bad := v_bad || ' so_credit_issue'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_prepare(uuid)'::regprocedure) <> 'dfa978d2dc2b1fd9634fd2b3cfae1892' then v_bad := v_bad || ' so_credit_prepare'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_detail(uuid)'::regprocedure) <> '779791222118ca1763cb2ad3989047ba' then v_bad := v_bad || ' so_credit_detail'; end if;
  if exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'so_credit' and c.column_name in ('tax_rule_filled_at', 'tax_rule_filled_by')) then v_bad := v_bad || ' so_credit_columns_exist'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_invoice_no_order', 'so_credit_tax_rule_suggest', 'so_credit_tax_rule_options', 'so_credit_tax_rule_fill_check', 'so_credit_tax_rule_fill')) then v_bad := v_bad || ' new_functions_exist'; end if;
  if v_bad <> '' then raise exception 'crtax-1 pre-check failed (functions changed since the migration was written — rebuild it from the current prosrc · or the columns / functions already exist):%', v_bad; end if;
end $$;

-- ═══ ① so_credit 칸 둘(판정 1220) — 나중에 채운 세금 규칙의 시각 · 사람(발행 때 정한 규칙이면 둘 다 null) ═══
alter table public.so_credit
  add column tax_rule_filled_at timestamptz,
  add column tax_rule_filled_by uuid references public.ims_staff(id),
  add constraint so_credit_tax_rule_filled_pair check ((tax_rule_filled_at is null) = (tax_rule_filled_by is null));
comment on column public.so_credit.tax_rule_filled_at is 'crtax-1(판정 1215 · 1220) — 발행 뒤에 세금 규칙을 채운 시각(so_credit_tax_rule_fill · 오더 없는 인보이스의 크레딧만) · 발행 때 정한 규칙이면 null';
comment on column public.so_credit.tax_rule_filled_by is 'crtax-1(판정 1215 · 1220) — 그 규칙을 채운 직원(ims_staff.id) · tax_rule_filled_at 과 짝';

-- ═══ ② 도우미 — 오더 없는 인보이스(판별의 한 곳 · 이견 1) ═══
create function public.so_invoice_no_order(p_invoice_id uuid) returns boolean
  language sql stable set search_path = public, pg_temp
as $$
  select p_invoice_id is not null
     and exists (select 1 from public.so_invoice i where i.id = p_invoice_id)
     and not exists (select 1 from public.so_invoice_order o where o.invoice_id = p_invoice_id);
$$;
comment on function public.so_invoice_no_order(uuid) is 'crtax-1(판정 1215 · 1217 · 이견 1) — 그 인보이스에 오더가 하나도 없나(이월 인보이스 kind opening 이 그렇다) · 크레딧이 세금 규칙을 가져올 오더가 없다는 판별의 한 곳(so_credit_issue · so_credit_prepare · so_credit_tax_rule_fill_check)';
revoke all on function public.so_invoice_no_order(uuid) from public, anon, authenticated, service_role;
grant execute on function public.so_invoice_no_order(uuid) to authenticated, service_role;

-- ═══ ③ 도우미 — 제안 규칙(판정 1218 · 610 과 같은 식: 그 손님의 기본 배송지 → so_tax_rule_for) · 없으면 null ═══
create function public.so_credit_tax_rule_suggest(p_customer_id uuid, p_on date) returns jsonb
  language sql stable set search_path = public, pg_temp
as $$
  select jsonb_build_object('rule_id', r.id, 'tax_rule', r.name, 'rate_pct', r.rate_pct, 'source', 'ship_to', 'country', a.country, 'state_province', a.state_province)
    from (select sa.* from public.customer_address sa where sa.customer_id = p_customer_id and sa.type = 'Shipping' and sa.is_active and sa.is_default_for_type limit 1) a
    join public.ref_tax_rule r on r.id = nullif(public.so_tax_rule_for(a.country, a.state_province, coalesce(p_on, public.ims_today()), 'sale')->>'rule_id', '')::uuid;
$$;
comment on function public.so_credit_tax_rule_suggest(uuid, date) is 'crtax-1(판정 1218) — 오더 없는 인보이스 크레딧의 세금 규칙 제안: 그 손님(매장)의 기본 배송지 → so_tax_rule_for · 없으면 null · 제안일 뿐(발행 commit 은 고른 규칙을 받아야 한다)';
revoke all on function public.so_credit_tax_rule_suggest(uuid, date) from public, anon, authenticated, service_role;
grant execute on function public.so_credit_tax_rule_suggest(uuid, date) to authenticated, service_role;

-- ═══ ④ 도우미 — 고를 규칙 목록(판정 1216 · 1219) · p_zero_only: 채우기용(세율 0 + 이 realm 의 QBO 짝) · 아니면 활성 sale 모두(QBO 코드 유무) ═══
-- definer: qbo_link · qbo_entity · qbo_connection 은 직원이 직접 못 읽는다 — 돌려주는 것은 규칙 이름 · 세율 · QBO 세금 코드 번호 · 이름뿐 · QuickBooks 가 끊겨 있으면 짝 없음으로
create function public.so_credit_tax_rule_options(p_zero_only boolean) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object('rule_id', r.id, 'tax_rule', r.name, 'rate_pct', r.rate_pct, 'has_qbo', (l.qbo_id is not null), 'qbo_code', l.qbo_id, 'qbo_code_name', e.name)
                            order by r.rate_pct, r.name), '[]'::jsonb)
    from public.ref_tax_rule r
    left join public.qbo_link l on l.realm_id = (select c.realm_id from public.qbo_connection c where c.singleton) and l.ims_kind = 'tax_rule' and l.ims_id = r.id::text
    left join public.qbo_entity e on e.realm_id = l.realm_id and e.qbo_type = 'TaxCode' and e.qbo_id = l.qbo_id
   where r.direction = 'sale' and r.is_active
     and (not coalesce(p_zero_only, false) or (r.rate_pct = 0 and l.qbo_id is not null));
$$;
comment on function public.so_credit_tax_rule_options(boolean) is 'crtax-1(판정 1216 · 1219) — 크레딧 세금 규칙 목록 [{rule_id, tax_rule, rate_pct, has_qbo, qbo_code, qbo_code_name}] · true = 채우기용(활성 sale · 세율 0 · 이 realm 의 QBO 세금 코드 짝) · false = 활성 sale 모두';
revoke all on function public.so_credit_tax_rule_options(boolean) from public, anon, authenticated, service_role;
grant execute on function public.so_credit_tax_rule_options(boolean) to authenticated, service_role;

-- ═══ ⑤ 도우미 — 채울 수 있나(null = 된다 · 아니면 이유 글) · so_credit_tax_rule_fill 과 so_credit_detail 이 같이 쓴다(이견 6) ═══
create function public.so_credit_tax_rule_fill_check(p_credit_id uuid) returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_c public.so_credit%rowtype;
  v_j public.qbo_job%rowtype;
begin
  select * into v_c from public.so_credit c where c.id = p_credit_id;
  if v_c.id is null then return 'Credit note not found'; end if;
  if v_c.status <> 'issued' then return format('Credit note %s is %s — only an issued credit note can take a tax rule', v_c.credit_number, v_c.status); end if;
  if v_c.tax_rule_id is not null then return format('Credit note %s already has tax rule %s', v_c.credit_number, v_c.tax_rule); end if;
  if not public.so_invoice_no_order(v_c.invoice_id) then                                               -- 일반 인보이스 크레딧: 머리 규칙은 원래 비어 있다(줄마다 그 오더의 규칙) — 고치지 않는다
    return format('Credit note %s takes its tax rule from the order on its invoice — there is nothing to fill in', v_c.credit_number);
  end if;
  if v_c.tax_amount <> 0 or exists (select 1 from public.so_credit_line l where l.credit_id = v_c.id and (l.tax_amount <> 0 or coalesce(l.rate_pct, 0) <> 0 or l.so_invoice_line_id is not null)) then
    return format('Credit note %s carries tax or an invoice line — a tax rule can only be filled in on a credit with no tax', v_c.credit_number);
  end if;
  -- 이견 7: 아직 QuickBooks 에 없다 — 가장 최근 credit 일감이 sending · sent · unknown 이거나 qbo_id 가 있으면 거부 · qbo_txn 에 있어도 거부(일감 없음 · failed · queued · blocked · skipped 는 지나간다)
  select * into v_j from public.qbo_job j where j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = v_c.id::text order by j.created_at desc, j.id desc limit 1;
  if v_j.id is not null and (v_j.state in ('sending', 'sent', 'unknown') or v_j.qbo_id is not null) then
    return format('Credit note %s is already in QuickBooks or being sent (job is %s) — the tax rule cannot be changed here', v_c.credit_number, v_j.state);
  end if;
  if exists (select 1 from public.qbo_txn t where t.ims_kind = 'credit' and t.ims_id = v_c.id::text) then
    return format('Credit note %s is already in QuickBooks — the tax rule cannot be changed here', v_c.credit_number);
  end if;
  return null;
end;
$$;
comment on function public.so_credit_tax_rule_fill_check(uuid) is 'crtax-1(판정 1215 · 1216 · 이견 6 · 7) — 그 크레딧의 빈 세금 규칙을 채울 수 있나: null = 된다 · 아니면 이유 글(issued · 규칙 빔 · 오더 없는 인보이스 · 세금 0 · QuickBooks 에 아직 없음) · so_credit_tax_rule_fill 과 so_credit_detail 이 같이 쓴다';
revoke all on function public.so_credit_tax_rule_fill_check(uuid) from public, anon, authenticated, service_role;

-- ═══ ⑥ 창구 — so_credit_tax_rule_fill(판정 1215 · 1216 · 1220): 빈 규칙을 세율 0 규칙으로 채운다 · 금액 · 세금 · 합계 · QBO 일감 무접촉 ═══
create function public.so_credit_tax_rule_fill(p_credit_id uuid, p_tax_rule text) returns jsonb
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_cr      public.so_credit%rowtype;
  v_rule    public.ref_tax_rule%rowtype;
  v_blocked text;
  v_name    text := nullif(trim(p_tax_rule), '');
  v_lines   int := 0;
  v_j       public.qbo_job%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(발행 취소 so_credit_cancel 과 같은 문)
  v_staff := public.so_current_staff();
  if p_credit_id is null then raise exception 'p_credit_id is required — nothing was saved'; end if;
  if v_name is null then raise exception 'Pick a tax rule (p_tax_rule) — nothing was saved'; end if;
  select * into v_cr from public.so_credit c where c.id = p_credit_id for update;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  v_blocked := public.so_credit_tax_rule_fill_check(v_cr.id);
  if v_blocked is not null then raise exception '% — nothing was saved', v_blocked; end if;
  -- 규칙(판정 1216): 이름으로 · 활성 sale · 세율 0 · 이 realm 의 QBO 세금 코드 짝(목록 도우미와 같은 집합)
  select * into v_rule from public.ref_tax_rule r where r.name = v_name and r.direction = 'sale' and r.is_active;
  if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', v_name; end if;
  if v_rule.rate_pct <> 0 then
    raise exception 'Tax rule % is % percent — only a 0 percent rule can be filled in (the amounts on an issued credit note do not change) — nothing was saved', v_rule.name, trim_scale(v_rule.rate_pct);
  end if;
  if not exists (select 1 from jsonb_array_elements(public.so_credit_tax_rule_options(true)) o where (o->>'rule_id')::uuid = v_rule.id) then
    raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching first — nothing was saved', v_rule.name;
  end if;
  update public.so_credit c
     set tax_rule_id = v_rule.id, tax_rule = v_rule.name, rate_pct = v_rule.rate_pct, tax_rule_filled_at = now(), tax_rule_filled_by = v_staff, updated_by = v_staff
   where c.id = v_cr.id;
  update public.so_credit_line l set rate_pct = v_rule.rate_pct, updated_by = v_staff where l.credit_id = v_cr.id and l.rate_pct is null;
  get diagnostics v_lines = row_count;
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  select * into v_j from public.qbo_job j where j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = v_cr.id::text order by j.created_at desc, j.id desc limit 1;   -- 읽기만(일감은 건드리지 않는다 — 북키퍼가 Retry)
  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'tax_rule_id', v_cr.tax_rule_id, 'tax_rule', v_cr.tax_rule, 'rate_pct', v_cr.rate_pct,
                            'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'lines_updated', v_lines, 'tax_rule_filled_at', v_cr.tax_rule_filled_at, 'tax_rule_filled_by', v_cr.tax_rule_filled_by,
                            'qbo_job', case when v_j.id is not null then jsonb_build_object('job_id', v_j.id, 'state', v_j.state, 'last_error', v_j.last_error) end);
end;
$$;
comment on function public.so_credit_tax_rule_fill(uuid, text) is 'crtax-1(판정 1215 · 1216 · 1220) — 오더 없는 인보이스(이월)에 건 issued 크레딧의 빈 세금 규칙을 채운다: manager · 규칙 = 이름 · 활성 sale · 세율 0 · QBO 세금 코드 짝 · 머리 tax_rule_id · tax_rule · rate_pct + 줄 rate_pct + tax_rule_filled_at · _by · 금액 · 세금 · 합계 · warnings · QBO 일감 무접촉(Retry 는 사람이)';
revoke all on function public.so_credit_tax_rule_fill(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.so_credit_tax_rule_fill(uuid, text) to authenticated;

-- ═══ 재발행 1/3 — so_credit_issue(DB prosrc 원본 md5 0f451d71 + 더한 줄 · crtax-1(판정 1217 ~ 1219): 오더 없는 인보이스(이월) 크레딧은 p.tax_rule(활성 sale)을 받는다 — commit 은 필수 · 미리 보기는 매장 기본 배송지 제안 · other · restocking_fee 줄 세율 = 그 규칙) ═══
CREATE OR REPLACE FUNCTION public.so_credit_issue(p jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other','price_adjustment'];   -- crn-2 판정 612
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_ref       boolean := false;                                                                        -- crn-1 판정 602 · 609: 참조 크레딧(인보이스 없음 · 옛 이름 cin7)
  v_ref_inv   text;  v_ref_ord text;  v_ref_date date;
  v_tax_src   text;  v_sa public.customer_address%rowtype;  v_tr jsonb;  v_seen text;                  -- crn-1 판정 610: 세금 기본 = 손님 기본 배송지의 규칙 · 경고 reference_seen
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_bgb       uuid;                                                                   -- bgr-1d: 반품하는 인보이스 줄의 B급 칸(정상 줄 · 참조 크레딧은 null)
  v_first_io  public.so_invoice_order%rowtype;
  v_open      boolean := false;                                                                        -- crtax-1(판정 1217 · 1218): 원 인보이스에 오더가 없다(이월) — 세금 규칙을 받아야 한다
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_fd        public.so_invoice_line%rowtype;  v_fd_amt numeric := 0;  v_fd_line numeric := 0;  v_fd_tax numeric;  v_fd_already numeric;  v_fd_inv numeric;   -- fr-3 판정 355: 운임 할인 되돌림(인보이스 charge_discount 줄 · 같은 비율 · 끝수는 마지막에)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
  -- crn-2(판정 603 · 611 · 613 · 614): 인보이스 줄마다 가격 층(tiers · so_credit_line_state) — 이 호출 안의 반품 · 조정이 차례로 깎는다 · v_odb = 줄 번호 → 오더 할인 거울의 기준 금액(조정된 몫은 뺀다)
  v_tiers     jsonb := '{}'::jsonb;  v_take jsonb;  v_tier jsonb;  v_odb jsonb := '{}'::jsonb;  v_od_base numeric;  v_before numeric;  v_after numeric;  v_adj_n int := 0;  v_ret_n int := 0;
  -- hcr-1(판정 774 · 778 · 779 · 781): 참조 크레딧이 이력(hist_)을 읽기만 한다 — 매장 칸(v_store) · 778 반영 단가 · 남은 수량 경고 · 781 세금 제안 · 경고를 기록(so_credit.warnings)에 남긴다
  v_store     uuid;  v_hl jsonb := '{}'::jsonb;  v_hist_found boolean := false;  v_hist_manual boolean := false;  v_hist_tax jsonb;  v_hu numeric;  v_hrem numeric;  v_hask numeric;  v_wt text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;
  if exists (select 1 from jsonb_array_elements(p->'lines') bx                                                          -- bgr-1e 판정 651: 「안 돌아옴 · b_grade」 는 새로 못 쓴다(줄 · 콤보 구성품 · 미리 보기도)
              where nullif(trim(bx->>'not_restocked_reason'), '') = 'b_grade'
                 or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(bx->'components') = 'array' then bx->'components' else '[]'::jsonb end) bc
                             where nullif(trim(bc->>'not_restocked_reason'), '') = 'b_grade')) then
    raise exception 'B-grade goods go back into a B-grade bin now — pick a B-grade bin as the restock bin, or use damaged if it is thrown out — nothing was saved';
  end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 참조 번호(옛 인보이스 종이 번호 · 판정 602 · 609 — 옛 열쇠 cin7 은 거부)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
    v_store := coalesce(public.so_invoice_store(v_inv.id), v_first_io.customer_id);                                                                         -- cr-store-1a(판정 1030 · 1031 · 이견 1 · 2): 인보이스 크레딧의 매장 = 인보이스의 매장 열쇠(이월은 store_customer_id · sale 은 오더 손님 so_invoice_order.customer_id) · 매장 둘 인보이스(열쇠 null)만 첫 오더(so_number 순)의 손님으로 + 경고
    if v_store is not null and public.so_invoice_store(v_inv.id) is null then v_warn := array_append(v_warn, 'store_ambiguous'); end if;
    v_open := public.so_invoice_no_order(v_inv.id);                                                     -- crtax-1(판정 1217 ~ 1219): 오더 없는 인보이스(이월)는 규칙을 가져올 오더가 없다 — 보낸 규칙(활성 sale)을 쓴다 · commit 은 필수 · 미리 보기만 매장 기본 배송지 제안
    if v_open then
      if nullif(trim(p->>'tax_rule'), '') is not null then
        select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
        if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
        v_tax_src := 'given';
      elsif p_commit then
        raise exception 'Pick a tax rule for a credit on a carried-over invoice — invoice % has no order to take one from — nothing was saved', v_inv.invoice_number;   -- 판정 1218
      else
        v_tr := public.so_credit_tax_rule_suggest(coalesce(v_store, v_cust), v_on);
        if v_tr is not null then
          select * into v_rule from public.ref_tax_rule r where r.id = (v_tr->>'rule_id')::uuid;
          v_tax_src := 'ship_to';
        end if;
      end if;
    end if;
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    if (select c.default_bill_to_customer_id from public.customer c where c.id = v_cust) is not null then                                           -- cr-store-1a(이견 4): customer_id 는 청구처여야 한다 — 매장을 보내면 그 크레딧은 어느 인보이스(청구처 이름)에도 못 붙는다
      raise exception 'Customer % bills to % — send customer_id = the bill-to and store_customer_id = this store — nothing was saved',
        (select c.name from public.customer c where c.id = v_cust), (select b.name from public.customer c join public.customer b on b.id = c.default_bill_to_customer_id where c.id = v_cust);
    end if;
    v_store := nullif(p->>'store_customer_id', '')::uuid;                                                                                       -- hcr-1 판정 779: 매장(종이 · 목록의 이름) · 돈(customer_id)은 매장의 청구처 coalesce(default_bill_to_customer_id, id) 여야 한다
    if v_store is not null then
      if not exists (select 1 from public.customer c where c.id = v_store) then raise exception 'Store customer not found — nothing was saved'; end if;
      if v_cust <> (select coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.id = v_store) then
        raise exception 'customer_id must be the bill-to of store % — the money goes to the bill-to, the paper and the list show the store — nothing was saved', (select c.name from public.customer c where c.id = v_store);
      end if;
    else
      if exists (select 1 from public.customer s where s.default_bill_to_customer_id = v_cust) then                                                  -- cr-store-1a(판정 1032 (가)): 매장을 둔 청구처는 매장 필수(본사 자신도 고를 수 있다 · 본사도 독립적으로 오더한다) · 매장 없는 손님만 「비면 청구처 자신」
        raise exception 'Customer % has stores — pick the store this credit belongs to (or the head office itself) — nothing was saved', (select c.name from public.customer c where c.id = v_cust);
      end if;
      v_store := v_cust;
    end if;
    v_hist_found := exists (select 1 from public.hist_so_line hl where hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) = lower(v_ref_inv));          -- hcr-1 판정 774: 옛 인보이스가 이력에 있으면 읽는다(없으면 옛 동작 그대로)
    if v_hist_found then                                                                                                                            -- 한 곳(hist_credit_lines)의 778 단가 · 남은 수량 — 창구 hist_credit_source 와 같은 식
      select coalesce(jsonb_object_agg(k.key, jsonb_build_object('unit', k.unit, 'rem', k.rem)), '{}'::jsonb) into v_hl
        from (select coalesce(h.product_id::text, upper(h.sku)) as key, min(h.unit_price_adj) as unit, sum(h.qty_remaining) as rem from public.hist_credit_lines(v_ref_inv) h where h.kind = 'product' group by 1) k;
    end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    elsif v_hist_found then                                                                               -- hcr-1 판정 781: 이력의 세율 = 매장 지금 규칙이면 그 규칙 · 다르면 같은 세율의 규칙(하나면 제안 · 여럿 · 없음이면 거부 글로 고르라) · 「다르다」 는 경고
      v_hist_tax := public.hist_credit_tax(v_ref_inv, v_store, v_on);
      if nullif(v_hist_tax->'suggested'->>'rule_id', '') is null then
        raise exception 'Pick a tax rule — invoice % was taxed at % percent and % active sale rule(s) have that rate (%) — nothing was saved', v_ref_inv, trim_scale(coalesce((v_hist_tax->>'old_rate_pct')::numeric, 0)),
          jsonb_array_length(coalesce(v_hist_tax->'candidates', '[]'::jsonb)), coalesce((select string_agg(cx->>'rule', ', ') from jsonb_array_elements(coalesce(v_hist_tax->'candidates', '[]'::jsonb)) cx), '-');
      end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_hist_tax->'suggested'->>'rule_id')::uuid;
      v_tax_src := 'history';
      if coalesce((v_hist_tax->>'differs')::boolean, false) then v_warn := array_append(v_warn, 'tax_rule_differs:' || coalesce(v_hist_tax->'current_rule'->>'rule', '-')); end if;
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = coalesce(v_store, v_cust) and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
      if v_sa.id is null then raise exception 'Pick a tax rule — the customer has no default ship-to address to suggest one from — nothing was saved'; end if;
      v_tr := public.so_tax_rule_for(v_sa.country, v_sa.state_province, v_on, 'sale');
      if nullif(v_tr->>'rule_id', '') is null then raise exception 'Pick a tax rule — no sale tax rule is linked to the customer''s default ship-to (% / %) — nothing was saved', coalesce(v_sa.country, '?'), coalesce(v_sa.state_province, '?'); end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_tr->>'rule_id')::uuid;
      v_tax_src := 'ship_to';
    end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or ref {invoice_number, order_number, invoice_date} (a credit without an IMS invoice) — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다) · [qbo-sync-2c1 · 판정 966] tax 줄은 받지 않는다(세금이 틀렸으면 전액 크레딧으로 상쇄 → 바른 새 인보이스 · CHECK · 옛 행은 그대로)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind = 'tax' then raise exception 'A tax-only credit note is not allowed — credit the invoice in full and issue a corrected invoice instead — nothing was saved'; end if;   -- qbo-sync-2c1 판정 966
    if v_kind is null or v_kind not in ('product','freight','other','restocking_fee','price_adjustment') then raise exception 'Line kind must be one of product, freight, other, restocking_fee, price_adjustment — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    if v_kind = 'price_adjustment' then v_adj_n := v_adj_n + 1; continue; end if;                       -- crn-2: 가격 조정은 둘째 바퀴(반품이 먼저 낮은 층을 가져간다 · §2-2)
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_bgb := null;                                                                                                                                                         -- bgr-1d
    v_take := null;  v_od_base := null;                                                                                                                                                -- crn-2
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_ref then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A reference credit product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A reference credit product line needs unit_price (the price on the paper invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_hist_found then                                                                                                  -- hcr-1 판정 774 · 778 · 기술 3: 이력 줄(778 반영 단가 · 남은 수량)과 견준다 — 막지 않는다 · 경고만
          v_hu := (v_hl->(v_pr.id::text)->>'unit')::numeric;  v_hrem := (v_hl->(v_pr.id::text)->>'rem')::numeric;
          if v_hu is null then
            v_hist_manual := true;  v_wt := 'not_on_invoice:' || v_pr.sku;  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if;
          else
            if abs(v_unit - v_hu) >= 0.005 then v_hist_manual := true; end if;                                                                           -- 한 푼(0.005) 이상 다르면 「손으로 넣은 단가」
            select coalesce(sum(nullif(t->>'qty_returned', '')::numeric), 0) into v_hask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(trim(t->>'sku'), '') = v_sku;
            if v_hask > v_hrem then v_wt := format('qty_over_sold:%s:%s/%s', v_pr.sku, trim_scale(v_hask), trim_scale(v_hrem));  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if; end if;
          end if;
        end if;
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_already := (public.so_credit_line_state(v_il.id)->>'qty_returned')::numeric;                   -- crn-2: 「이미 반품」 식은 so_credit_line_state 한 곳(§22-f ⬜ 복사 식 닫힘 · 값은 같다)
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        -- crn-2 판정 611: 반품은 조정된 몫(낮은 층)부터 — 이 줄의 층을 가져와(이 호출의 앞선 줄이 깎은 것 포함) 낮은 값부터 v_qty 만큼 뗀다
        if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
        v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, null);
        v_tiers := v_tiers || jsonb_build_object(v_il.id::text, v_take->'tiers');
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select sl.bgrade_bin_id into v_bgb from public.so_line sl where sl.id = v_il.so_line_id;                                  -- bgr-1d 판정 640
        if v_bgb is not null then v_warn := array_append(v_warn, 'final_sale:' || v_sku); end if;                                -- bgr-1d: 경고만(노 리턴 · 발행은 막지 않는다)
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_take is null then
        v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_od_base := v_amount;
      else                                                                                                      -- crn-2 판정 611: 낸 단가 층은 인보이스 단가(오더 할인 거울이 따로 뺀다) · 조정 층은 새 단가 그대로(거울 기준에서 뺀다)
        select coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else round((pt->>'qty')::numeric * (pt->>'unit_price')::numeric, 2) end), 0),
               coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else 0 end), 0)
          into v_amount, v_od_base from jsonb_array_elements(v_take->'parts') pt;
        if exists (select 1 from jsonb_array_elements(v_take->'parts') pt where not (pt->>'paid')::boolean) then
          v_unit := round(v_amount / v_qty, 6);
          v_desc := v_desc || ' (' || (select string_agg(trim_scale((pt->>'qty')::numeric) || ' × ' || trim_scale(case when (pt->>'paid')::boolean then coalesce(v_il.unit_price, 0) else (pt->>'unit_price')::numeric end), ' + ' order by ord) from jsonb_array_elements(v_take->'parts') with ordinality t(pt, ord)) || ')';
        end if;
      end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_ref then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null and v_bgb is not null then                                                                         -- bgr-1d 판정 649: B급 줄의 반품 = 팔려 나간 그 B급 칸
          select rb.name into v_bin_name from public.ref_bin rb where rb.id = v_bgb and rb.is_bgrade and rb.is_active and rb.warehouse_id = v_w.id;
          if v_bin_name is null then v_warn := array_append(v_warn, 'bgrade_bin_gone:' || v_sku); end if;                     -- 꺼졌거나 · 비활성 · 다른 창고 → 정상 기본(ims_last_bin)
        end if;
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_ref then null else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;   -- crn-1 판정 602: 참조 크레딧은 되짚지 않는다(예상 null · 실제 원가는 inv_layer_post_credit ② 가중평균부터)
      end if;
    elsif v_kind = 'freight' then
      if v_ref then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select 'final_sale:' || fs.name into v_wt from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.id = v_il.so_charge_id and fs.final_sale;   -- fsale-1(판정 1162-5 · 640 과 같은 열쇠 꼴): 떨이 줄 크레딧 — 경고만(막지 않는다)
        if found and not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      if not v_ref then                                                                                             -- fr-3 판정 355: 그 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 같은 비율로 되돌린다
        select * into v_fd from public.so_invoice_line d where d.invoice_id = v_inv.id and d.kind = 'charge_discount' and d.so_charge_id = v_il.so_charge_id;
        if v_fd.id is not null then
          v_fd_inv := -v_fd.amount;                                                                                    -- 인보이스 할인(양수)
          select coalesce(-sum(cl.amount), 0) into v_fd_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_fd.id and c.status = 'issued';   -- 이미 돌려준 할인(양수)
          v_fd_line := case when v_already + v_amount = v_il.amount then v_fd_inv - v_fd_already                             -- 끝수 규칙: 정가를 다 돌려주는 마지막 줄은 남은 할인 전부(합 = 인보이스 할인 · 정확히)
                            else least(round(v_amount * v_fd_inv / v_il.amount, 2), v_fd_inv - v_fd_already) end;                 -- 그 밖은 round(x × 비율, 2) · 남은 할인을 넘지 않는다
          if (v_already - v_fd_already) + (v_amount - v_fd_line) > v_il.amount - v_fd_inv or v_fd_line > v_amount then         -- 순액 한도: 돌려준 순액 합 ≤ 손님이 낸 순액 · 남은 할인이 이번 운임보다 크면(앞 크레딧이 할인 없이 정가를 가져간 옛 모양) 음수 순액이 되므로 거부(정가 한도 검사는 위에 그대로)
            raise exception 'Invoice % charge % : the customer paid % net (% less % discount) — % net already credited and % asked now — only % left — nothing was saved',
              v_inv.invoice_number, v_il.line_no, v_il.amount - v_fd_inv, v_il.amount, v_fd_inv, v_already - v_fd_already, v_amount - v_fd_line, (v_il.amount - v_fd_inv) - (v_already - v_fd_already);
          end if;
        end if;
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_ref or v_open then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    if v_kind = 'product' then v_odb := v_odb || jsonb_build_object(v_ln::text, v_od_base); v_ret_n := v_ret_n + 1; end if;                                      -- crn-2: 거울 기준(조정된 몫 제외)
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'freight' and not v_ref and v_fd.id is not null and v_fd_line > 0 then                                   -- fr-3 판정 355 · 352 · 354 · 358: 운임 줄 바로 뒤 할인 되돌림 줄 · 음수 · 세금 따로(줄마다) · 계정 = 인보이스 할인 줄 것
      v_fd_tax := public.so_tax_amount(-v_fd_line, v_io.rate_pct);
      v_ln := v_ln + 1;  v_fd_amt := v_fd_amt - v_fd_line;  v_tax_amt := v_tax_amt + coalesce(v_fd_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'freight_discount', 'so_invoice_line_id', v_fd.id, 'description', v_fd.description,
                                               'amount', -v_fd_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_fd_tax, 0), 'account_id', v_fd.account_id, 'account_code', v_fd.account_code);
    end if;
    if v_kind = 'product' and not v_ref then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- ═══ crn-2 판정 603 · 611 · 613 · 614: 가격 조정 줄(둘째 바퀴) — 인보이스 줄: 층(낸 단가 = 오더 할인 뒤 · 앞선 조정이 있으면 그 단가)에서 새 단가보다 비싼 가장 낮은 층 하나 · 수량은 그 층 안에서만(넘치면 나눠 보내라) ·
  --     참조 크레딧: 낸 단가 · 새 단가 · 수량을 손으로 · 금액 = (낸 − 새) × 수량 · 세율 = 그 줄(또는 규칙) · 계정 = 그 인보이스 줄(614 · 참조는 _98_) · 재고 0 · 거울 · surcharge · 운임 할인 · 피 기준에 안 들어간다 ═══
  for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'price_adjustment' loop
    v_il := null;  v_io := null;  v_pr := null;  v_acct := null;  v_tier := null;  v_il_id := null;  v_so_line_id := null;  v_product_id := null;  v_sku := null;  v_desc := null;
    v_qty := nullif(x->>'qty', '')::numeric;  v_after := nullif(x->>'new_unit_price', '')::numeric;  v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_qty is null or v_qty <= 0 then raise exception 'A price adjustment line needs qty > 0 — nothing was saved'; end if;
    if v_after is null or v_after <= 0 then raise exception 'A price adjustment line needs new_unit_price above 0 — to write the goods off entirely use a product line marked not returned, or an other line — nothing was saved'; end if;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;
    if v_ref then
      v_sku := nullif(trim(x->>'sku'), '');
      if v_sku is null then raise exception 'A reference credit price adjustment line needs sku — nothing was saved'; end if;
      select * into v_pr from public.product pr where pr.sku = v_sku;
      if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
      v_before := nullif(x->>'paid_unit_price', '')::numeric;
      if v_before is null or v_before < 0 then raise exception 'A reference credit price adjustment line needs paid_unit_price (the price on the paper invoice) — nothing was saved'; end if;
      if v_after >= v_before then raise exception 'New unit price % is not below the paid unit price % — nothing was saved', trim_scale(v_after), trim_scale(v_before); end if;
      v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := v_pr.name;
      if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
    else
      v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
      if v_il_id is null then raise exception 'A price adjustment line needs so_invoice_line_id (the invoice line being adjusted) — nothing was saved'; end if;
      select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
      if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
      if v_il.combo_components is not null then raise exception 'Invoice % line % (%) is a combo — a price adjustment on a combo is not supported; use an other line — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku; end if;
      if exists (select 1 from public.so_line sl where sl.id = v_il.so_line_id and sl.bgrade_bin_id is not null) then v_warn := array_append(v_warn, 'final_sale:' || v_il.sku); end if;   -- bgr-1d: 가격 조정도 같은 경고
      select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
      if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
      if not exists (select 1 from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0) then
        raise exception 'Invoice % line % (%): nothing left to adjust — all % were returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_il.qty);
      end if;
      select t into v_tier from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0 and (t->>'unit_price')::numeric > v_after order by (t->>'unit_price')::numeric limit 1;
      if v_tier is null then
        raise exception 'Invoice % line % (%): new unit price % is not below the current unit price % — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_after),
          trim_scale((select min((t->>'unit_price')::numeric) from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0));
      end if;
      v_before := (v_tier->>'unit_price')::numeric;
      if v_qty > (v_tier->>'qty')::numeric then
        raise exception 'Invoice % line % (%): only % can be adjusted at % — split the adjustment (% at %%s%, the rest at the next price level) — nothing was saved',
          v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before), trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before);
      end if;
      v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, v_after);
      v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_tiers_add(v_take->'tiers', v_qty, v_after));
      v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := v_il.description;
      select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
      if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;   -- 판정 614: 그 판매 줄의 매출 계정
    end if;
    v_amount := round((v_before - v_after) * v_qty, 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'price_adjustment', 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku,
                                             'description', format('Price adjustment %s → %s', trim_scale(v_before), trim_scale(v_after)) || coalesce(' — ' || v_desc, ''),
                                             'qty_adjusted', v_qty, 'unit_price_before', v_before, 'unit_price_after', v_after, 'unit_price', v_before - v_after,
                                             'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
  end loop;
  if v_adj_n > 0 and v_ret_n = 0 and v_reason <> 'price_adjustment' then v_warn := array_append(v_warn, 'reason_not_price_adjustment'); end if;          -- crn-2 §2-4: 경고만
  if v_reason = 'price_adjustment' and v_ret_n > 0 then v_warn := array_append(v_warn, 'reason_price_adjustment_with_returns'); end if;

  -- crn-1 판정 602 · crn-0 §2-5: 참조 크레딧 경고 — 늘 manual_unit_price(인보이스 없이 넣은 단가 · 화면이 크게) · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않는다)
  if v_ref then
    if not v_hist_found or v_hist_manual then                                                                                 -- hcr-1 기술 3: 이력이 있으면 단가가 이력(778 반영)과 다를 때 · 인보이스에 없는 제품일 때만
    v_warn := array_append(v_warn, 'manual_unit_price');
    end if;
    if not v_hist_found then v_warn := array_append(v_warn, 'reference_not_in_history'); end if;                                              -- hcr-1: 이력에 없는 번호 — 수량 · 단가를 견주지 못했다
    select string_agg(distinct c2.credit_number, ', ') into v_seen
      from public.so_credit c2 join public.so_credit_line l2 on l2.credit_id = c2.id
     where c2.customer_id = v_cust and c2.status = 'issued' and lower(trim(c2.ref_invoice_number)) = lower(v_ref_inv)
       and l2.kind = 'product' and l2.sku in (select le->>'sku' from jsonb_array_elements(v_lines) le where le->>'kind' = 'product');
    if v_seen is not null then v_warn := array_append(v_warn, 'reference_seen:' || v_seen); end if;
  end if;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_ref then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum(coalesce((v_odb->>(le->>'line_no'))::numeric, (le->>'amount')::numeric)) as amt   -- crn-2 판정 611 · 613: 조정된 몫은 거울 기준에서 뺀다(그 몫은 새 단가 그대로)
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id join public.so_line sl on sl.id = il.so_line_id   -- od-1
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0 and not public.so_line_manual(sl)   -- od-1 판정 542 · 544: 손으로 정한 줄은 오더 할인을 받지 않았으니 되돌릴 몫도 없다
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_ref or v_open then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'store_customer_id', v_store, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) || case when v_open then jsonb_build_object('needs_tax_rule', true, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src) else '{}'::jsonb end end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'freight_discount_amount', v_fd_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, ref_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, freight_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)   -- fr-3
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_ref_inv, v_ref_ord, v_ref_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fd_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)   -- fr-3
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components,
                                       qty_adjusted, unit_price_before, unit_price_after)                                                                                                -- crn-2
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb),                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
            nullif(e->>'qty_adjusted', '')::numeric, nullif(e->>'unit_price_before', '')::numeric, nullif(e->>'unit_price_after', '')::numeric)                                              -- crn-2
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  update public.so_credit c set store_customer_id = v_store, warnings = to_jsonb(v_warn) where c.id = v_cr.id;                               -- hcr-1 판정 779 · 기술 3: 매장 · 경고를 기록에(원장 경고까지 합친 뒤 · 상태는 안 건드린다)
  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'store_customer_id', v_store, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) || case when v_open then jsonb_build_object('needs_tax_rule', true, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src) else '{}'::jsonb end end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ 재발행 2/3 — so_credit_prepare(DB prosrc 원본 md5 dfa978d2 + 더한 줄 · crtax-1: invoice.needs_tax_rule · tax_rule_suggested · tax_rule_options[]) ═══
CREATE OR REPLACE FUNCTION public.so_credit_prepare(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           public.so_invoice_no_order(i.id) as no_order,                                                -- crtax-1(판정 1217): 오더 없는 인보이스(이월) — 발행이 세금 규칙을 받는다
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id), 'needs_tax_rule', inv.no_order),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returned')::numeric end,                                                            -- crn-2: 식은 so_credit_line_state 한 곳(§22-f ⬜ 닫힘)
                'qty_returnable', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returnable')::numeric end,
                -- crn-2 판정 603 · 611 · 613: 가격 조정 재료 — 낸 단가(오더 할인 뒤) · 층(tiers) · 조정할 수 있는 수량(낸 단가 층) · 열린 조정 몫 · 앞선 조정 목록(콤보 줄은 null)
                'adjust', case when l.kind = 'product' and l.combo_components is null then public.so_credit_line_state(l.id) - 'so_invoice_line_id' - 'tiers_raw' end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
                'discount_line_id', fd.fd_id, 'discount_amount', fd.fd_amount, 'net_amount', case when l.kind = 'charge' then l.amount - coalesce(fd.fd_amount, 0) end,                     -- fr-3 판정 355: 운임 줄의 할인(인보이스 charge_discount 줄 · 양수) · 순액
                'discount_credited', fd.fd_credited, 'net_credited', case when l.kind = 'charge' then fd.gross_credited - coalesce(fd.fd_credited, 0) end,                   -- 이미 돌려준 할인(양수) · 이미 돌려준 순액
                'net_remaining', case when l.kind = 'charge' then (l.amount - coalesce(fd.fd_amount, 0)) - (fd.gross_credited - coalesce(fd.fd_credited, 0)) end,              -- 남은 순액 한도(so_credit_issue 의 순액 검사와 같은 식)
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                'final_sale', sl.bgrade_bin_id is not null or (l.kind = 'charge' and exists (select 1 from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.id = l.so_charge_id and fs.final_sale)), 'restock_bgrade_bin_gone', sl.bgrade_bin_id is not null and bgb.j is null,   -- bgr-1d 판정 640 · 649: B급으로 판 줄 · 그 B급 칸이 꺼졌거나 비활성이면 정상 기본으로
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and l.combo_components is null and inv.wh_id is not null and pr.id is not null
                                            then coalesce(bgb.j, public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text) end,   -- bgr-1d 판정 649: B급 줄은 팔려 나간 그 B급 칸 먼저
                -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄 = 반품 단위(qty 는 콤보 수) · 구성품마다 돌아가는 칸 기본(ims_last_bin · 낱개 제품 · 그 창고) — 보통 줄은 null
                'combo_components', (select jsonb_agg(cj || jsonb_build_object('restock_bin_default', case when inv.wh_id is not null and cpr.id is not null then public.ims_last_bin(array[coalesce(cpr.parent_product_id, cpr.id)], inv.wh_id) -> coalesce(cpr.parent_product_id, cpr.id)::text end) order by cj->>'sku')
                                       from jsonb_array_elements(l.combo_components) cj left join public.product cpr on cpr.id = nullif(cj->>'product_id', '')::uuid))
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join lateral (select jsonb_build_object('bin_id', rb.id, 'bin', rb.name, 'zone', rb.zone, 'received_on', null, 'is_bgrade', true) as j                       -- bgr-1d: ims_last_bin 칸 꼴 + is_bgrade
                                   from public.ref_bin rb where rb.id = sl.bgrade_bin_id and rb.is_bgrade and rb.is_active and rb.warehouse_id = inv.wh_id) bgb on true
              left join lateral (select d.id as fd_id, -d.amount as fd_amount,                                                                                       -- fr-3: 운임 줄의 할인 줄(없으면 null)
                                        (select coalesce(-sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = d.id and c.status = 'issued') as fd_credited,
                                        (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') as gross_credited
                                   from public.so_invoice_line d where l.kind = 'charge' and d.invoice_id = l.invoice_id and d.kind = 'charge_discount' and d.so_charge_id = l.so_charge_id) fd on true
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'tax_rule_suggested', case when inv.no_order then public.so_credit_tax_rule_suggest(coalesce(public.so_invoice_store(inv.id), inv.bill_to_customer_id), inv.today) end,   -- crtax-1(판정 1218): 제안만(매장 기본 배송지) · 발행 commit 은 고른 규칙을 받아야 한다
    'tax_rule_options', case when inv.no_order then public.so_credit_tax_rule_options(false) else '[]'::jsonb end,                                                            -- crtax-1(판정 1219): 활성 sale 규칙 모두 · QBO 코드 유무
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other","price_adjustment"]'::jsonb,                                                      -- crn-2 판정 612
                                'not_restocked_reasons', '["damaged","not_returned","other"]'::jsonb,                                                   -- bgr-1e 판정 651: b_grade 는 새로 못 고른다
                                'not_restocked_reasons_retired', '["b_grade"]'::jsonb,                                                                    -- bgr-1e: 옛 줄 표시용(라벨만)
                                'line_kinds', '["product","freight","tax","other","restocking_fee","price_adjustment"]'::jsonb)                                                   -- crn-2 판정 603
  )
  from inv, cfg;
$function$;

-- ═══ 재발행 3/3 — so_credit_detail(DB prosrc 원본 md5 77979122 + 더한 줄 · crtax-1: tax_rule_fillable · tax_rule_fill_blocked · tax_rule_options[] · tax_rule_filled_by_name) ═══
CREATE OR REPLACE FUNCTION public.so_credit_detail(p_credit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr public.so_credit%rowtype;
  v_blocked text;                                                                                                                       -- crtax-1: 세금 규칙을 채울 수 없는 이유(null = 채울 수 있다)
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Credit Notes 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  v_blocked := public.so_credit_tax_rule_fill_check(v_cr.id);                                                                           -- crtax-1(판정 1215 · 1216): 채우기 창구 so_credit_tax_rule_fill 과 같은 검사
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'store_name', (select c.name from public.customer c where c.id = v_cr.store_customer_id),                                           -- hcr-1 판정 779: 매장 이름(credit.store_customer_id 와 credit.warnings 는 to_jsonb 로 저절로)
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'tax_rule_fillable', (v_blocked is null), 'tax_rule_fill_blocked', v_blocked,                                                     -- crtax-1(판정 1215 · 1216 · 1220): 채울 수 있나 · 안 되는 이유 · 고를 규칙(세율 0 + QBO 짝) · 채운 사람(시각 · id 는 credit 에)
    'tax_rule_options', case when v_blocked is null then public.so_credit_tax_rule_options(true) else '[]'::jsonb end,
    'tax_rule_filled_by_name', (select st.name from public.ims_staff st where st.id = v_cr.tax_rule_filled_by),
    'remaining', public.so_credit_remaining(v_cr.id),                                                                                   -- so-credit-read-1 C1: 식의 한 곳(옛 식은 C0 정의 그대로였다)
    -- so-credit-read-1 R2(2026-09-25) — 더한 키 넷(옛 키 아홉은 그대로 · 부르는 곳 0 이지만 규칙대로 더하기만)
    'credit_row', (select to_jsonb(v) from public.so_credit_list v where v.id = v_cr.id),
    'allocations_all', (select coalesce(jsonb_agg(jsonb_build_object('alloc_id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.invoice_number, 'invoice_status', i.status,
                                                                     'refund_payment_id', a.refund_payment_id, 'refund_paid_on', p.paid_on, 'refund_method', p.method, 'refund_reference', p.reference, 'refund_status', p.status,
                                                                     'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id left join public.so_payment p on p.id = a.refund_payment_id
                        where a.credit_id = v_cr.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                                                                   'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                                                                   'attached_from_this_credit', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id = l.id and a.voided_at is null), 0)) order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v_cr.customer_id and l.currency_id = v_cr.currency_id
                        and public.so_invoice_store(l.id) = public.so_credit_store(v_cr.id)),                                                       -- cr-store-1a(판정 1033 (나) 의 한 곳 · 1023′ (가)): Attach 후보 = 크레딧을 낸 매장의 열린 인보이스만(문 so_credit_alloc_add 와 같은 열쇠)
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_cr.customer_id) b where b.currency_id = v_cr.currency_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', case when (select public.ims_can_view_cost()) then y.unit_cost end /* rls-3b(판정 580): 원가 값만 열쇠로 */, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;

$function$;

-- ═══ comment — 재발행 셋은 옛 글 뒤에 덧(한 번만) ═══
do $$
declare v_r record;
begin
  for v_r in select * from (values
    ('public.so_credit_issue(jsonb, boolean)', ' · crtax-1(판정 1217 ~ 1219): 오더 없는 인보이스(이월) 크레딧은 p.tax_rule(활성 sale)을 받는다 — commit 은 필수 · 미리 보기는 매장 기본 배송지 제안 · other · restocking_fee 줄 세율 = 그 규칙'),
    ('public.so_credit_prepare(uuid)', ' · crtax-1: invoice.needs_tax_rule · tax_rule_suggested · tax_rule_options[]'),
    ('public.so_credit_detail(uuid)', ' · crtax-1: tax_rule_fillable · tax_rule_fill_blocked · tax_rule_options[] · tax_rule_filled_by_name')
  ) as t(sig, add) loop
    if position('crtax-1' in coalesce(obj_description(v_r.sig::regprocedure, 'pg_proc'), '')) = 0 then
      execute format('comment on function %s is %L', v_r.sig, coalesce(obj_description(v_r.sig::regprocedure, 'pg_proc'), '') || v_r.add);
    end if;
  end loop;
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_issue(jsonb, boolean)'::regprocedure) <> 'ecad052269dd69acbb6ca384c7c13130' then v_bad := v_bad || ' so_credit_issue_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue') <> 1 then v_bad := v_bad || ' so_credit_issue_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_prepare(uuid)'::regprocedure) <> '2286b74a8403a048dd5d151fb1392aa2' then v_bad := v_bad || ' so_credit_prepare_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_prepare') <> 1 then v_bad := v_bad || ' so_credit_prepare_count'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_detail(uuid)'::regprocedure) <> '6a79ff9d5fc578c6b167479c124db7e9' then v_bad := v_bad || ' so_credit_detail_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_detail') <> 1 then v_bad := v_bad || ' so_credit_detail_count'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_invoice_no_order', 'so_credit_tax_rule_suggest', 'so_credit_tax_rule_options', 'so_credit_tax_rule_fill_check', 'so_credit_tax_rule_fill')) <> 5 then v_bad := v_bad || ' new_function_count'; end if;
  if has_function_privilege('anon', 'public.so_credit_tax_rule_fill(uuid, text)', 'execute') or not has_function_privilege('authenticated', 'public.so_credit_tax_rule_fill(uuid, text)', 'execute') then v_bad := v_bad || ' fill_acl'; end if;
  if has_function_privilege('authenticated', 'public.so_credit_tax_rule_fill_check(uuid)', 'execute') or has_function_privilege('anon', 'public.so_credit_tax_rule_options(boolean)', 'execute') then v_bad := v_bad || ' helper_acl'; end if;
  if (select count(*) from public.so_credit c where c.tax_rule_filled_at is not null or c.tax_rule_filled_by is not null) <> 0 then v_bad := v_bad || ' filled_rows'; end if;
  if v_bad <> '' then raise exception 'crtax-1 landing check failed:%', v_bad; end if;
  raise notice 'crtax-1 landing OK — so_credit tax_rule_filled_at · tax_rule_filled_by + 5 new functions + 3 functions reissued';
end $$;
