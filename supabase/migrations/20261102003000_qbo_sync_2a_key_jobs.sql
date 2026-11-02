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
-- qbo-sync-2a — 열쇠 qbo(판정 945) · 보내기 일감 qbo_job · 거래 짝 qbo_txn · 손님 · Item 몸 함수 · 일감 창구 8 (2026-11-01 · 판정 935 ~ 946 · 지시서 ~/asung/prompts/qbo-sync-2a.md · 이견 1 ~ 17 답 반영)
--   A 열쇠 qbo(945): ims_perm_catalog 재발행(20261031233700:130 ~ 158 바이트 복사 + "qbo" 한 줄 — freight_booking 앞에) · 값 'qbo'(쓰기) · 'qbo:read'(보기) · 문 qbo_key_gate(p_write) = 활성 직원 + perms 글자 그대로(mcp_gate 꼴 · ⚠️ admin 도 켜야 한다 · ims_can_view 안 씀)
--     qbo_sync_gate 재발행(몸 = qbo_key_gate(true) · 1a 창구 9 + 1c match_auto 의 호출 자리 12 는 그대로) · 읽기 셋(qbo_link_summary · qbo_link_page · qbo_entity_find) 재발행 = 1a 바이트 그대로 + gate 만 qbo_key_gate(false)
--     qbo_status 재발행 = 1a 바이트 그대로 + caller_qbo('write' | 'read' | null) · caller_is_admin 은 그대로(연결 칸이 읽는다) · 연결류(qbo_admin_gate · state_new · realm_clear · EF query · read)는 무접촉
--   B 표 둘(ims_id text 다형 · FK 는 ims_staff · 자기 참조 blocked_by 뿐 · 거래 표 FK 0 → 컷오버 지우는 순서 영향 없음 · 이견 5): qbo_job(일감 · 열린 일감은 (realm, kind, ims_kind, ims_id) 하나 · 부분 유일) · qbo_txn(거래 짝 · 2b 가 채운다 · 표만)
--     qbo_link.matched_by CHECK 에 created · inv_config 키 넷(qbo_send_enabled off · qbo_send_since '' · qbo_send_batch 15 · qbo_cogs_account_code _58_)
--   C 몸 함수(grant 0 · claim · add 가 부른다 · 규칙이 SQL 로 시험된다): qbo_customer_body(936 · 946) · qbo_item_body(937 · 941 · 943 · 944) · qbo_account_ref · qbo_country_name
--     손님: DisplayName = left(btrim(name),100) · Customer · Vendor 거울과 이름 충돌이면 실패(자동으로 바꾸지 않는다 · Employee 는 거울에 없어 실제 쓰기의 6240 이 남는다) · CompanyName · BillAddr(기본 Billing 주소 · Country 946: CA → Canada · US → USA · 그 밖은 그대로 + 경고) · PrimaryEmailAddr(doc_mail_recipient 와 같은 선)
--           CurrencyRef · SalesTermRef(qbo_link payment_term) · DefaultTaxCodeRef(customer.tax_rule 이름 → ref_tax_rule → qbo_link · 없으면 비움 · 이견 6) · Taxable true · 전화 · 배송 주소 없음 · parent_id 있으면 ParentRef(부모 짝) · Job · BillWithParent(청구처 = 부모) — 부모 짝 없으면 parent_customer_id 를 돌려주고 add 가 부모 일감 먼저 + blocked
--     Item: Name = left(btrim(name),100) · 콜론 → '-'(이견 9) · gone 아닌 QBO Item 과 lower(btrim) 정확 비교(「(deleted)」 꼬리 떼지 않음 · 이견 8) 같으면 ` [SKU]` · name_alt 는 늘 같이(EF 가 6240 에 한 번 더 · 이견 11) · 같은 Sku 가 비활성뿐이면 실패 「QuickBooks item is inactive」(941) · 활성이 있으면 실패(사람 짝)
--           Type Service · Taxable true · IncomeAccountRef = coalesce(product.revenue_account_code, inv_config customer_default_sale_account_code) 의 qbo_link · ExpenseAccountRef = inv_config qbo_cogs_account_code 의 qbo_link(이견 10) · surcharge → 「Tariff Surcharge」 · so_surcharge_account_code(_94_) · freight · discount · freight_discount 는 거부(943)
--   D 일감 창구 8: 열쇠 = qbo_job_add(customer | item · 미리 쌓기 · 열린 일감 있으면 그것 · 부모 먼저 + blocked) · qbo_job_list · qbo_job_retry(failed · unknown → queued · request_id 새로 · unknown 은 note 필수) · qbo_job_skip(note 필수)
--                   service_role(EF send · doc_is_service 꼴) = qbo_job_claim(stale sending 10 분 → unknown 먼저 · blocked → queued(부모 sent) · queued → sending · for update skip locked · 몸은 다음 문장에서 일감마다 · 몸 실패는 그 일감만 failed) · qbo_job_done(sent + qbo_link created + qbo_entity upsert + 자식 풀기) · qbo_job_fail · qbo_job_unknown
--     ⚠️ 자동 재시도 없음(이견 12) — 쓰기는 결과를 모르면 unknown · 사람이 retry · requestid = qbo_job.request_id(uuid · retry 마다 새로 — 같은 id 는 처음 응답(실패 포함)을 되돌려 주므로 · 이견 13)
--   무접촉: qbo_admin_gate · qbo_state_new · qbo_realm_clear · 1a 창구 9 의 몸(gate 함수만 바뀜) · 화면 · EF(문 가르기는 같은 차수의 qbo.ts) · 거래 표 · 첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(G0) · 새 표 grant 명시(10-30 부터 자동 grant 없음)
--   ⚠️ 화면 배포 전에는 북키퍼 화면이 여전히 admin 글을 보인다 — settings.html qbomatch 칸(caller_qbo)은 대화 Claude(set v14)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102003000_qbo_sync_2a_key_jobs.sql && supabase migration repair --status applied 20261102003000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261102003000_qbo_sync_2a_key_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2a_check.sql

-- ═══ A) 열쇠 qbo — ims_perm_catalog 재발행(20261031233700:130 ~ 158 바이트 복사 + qbo 한 줄 — freight_booking(마지막 · 쉼표 없음) 앞에) ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "shopify":    {"room": "ims", "min_role": "manager", "label": "Shopify stores, product push, stock sync (manager and above · shop-1a)"},
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"},
      "doc_template":          {"room": "ims", "min_role": "supervisor", "label": "Document templates — publish a layout version (admin always · supervisor only when switched on · off until switched on)"},
      "cost":                  {"room": "ims", "label": "Inventory cost — stock value, layer values, unit costs (admin and supervisor always · person by person · read and write both show it · off until switched on)"},
      "claude":                {"room": "ims", "label": "Claude connector — ask Claude about orders, stock, customers, POs and backorders (person by person · admins and supervisors must be switched on too · read only · off until switched on)"},
      "qbo":                   {"room": "ims", "label": "QuickBooks — matching, list refresh, send queue (person by person · admins and supervisors must be switched on too · read = see only · write = match, refresh, resend, skip · connecting stays with admins · off until switched on)"},
      "freight_booking":       {"room": "ims", "rooms": ["wms", "ims"], "label": "Freight booking — book, cancel and re-book Freightcom shipments (admin and supervisor always · person by person · warehouse and office each switched on · quotes stay with sales / fulfillment · off until switched on)"}
    }
  }'::jsonb;
$$;
do $$ begin
  execute format('comment on function public.ims_perm_catalog() is %L',
    obj_description(to_regprocedure('public.ims_perm_catalog()'), 'pg_proc')
    || ' · ⭐ [2026-11-01 qbo-sync-2a] screens.qbo(QuickBooks 짝 · 받기 · 보내기 일감 · 판정 945 — ⚠️ admin · supervisor 도 켜야 한다 · qbo_key_gate 가 perms ? qbo | qbo:read 를 글자 그대로 본다 · 연결 · 끊기 · Untie · 원문 조회는 admin(qbo_admin_gate) 그대로)');
end $$;

create function public.qbo_key_gate(p_write boolean default true) returns uuid
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_s public.ims_staff%rowtype;
begin
  select * into v_s from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_s.id is null then raise exception 'You are not registered as active staff — nothing was changed'; end if;
  if not (coalesce(v_s.perms, '[]'::jsonb) ? 'qbo' or (not p_write and coalesce(v_s.perms, '[]'::jsonb) ? 'qbo:read')) then
    raise exception 'Your account does not have the ''qbo''% permission — ask an admin to switch it on in Staff — nothing was changed', case when p_write then ' (write)' else '' end;
  end if;
  return v_s.id;
end;
$$;
comment on function public.qbo_key_gate(boolean) is 'qbo-sync-2a 판정 945: QuickBooks 열쇠의 문 — 활성 직원 + perms 글자 그대로(''qbo'' = 쓰기 · ''qbo:read'' = 보기만 · p_write false 면 둘 다 통과) · ⚠️ admin · supervisor 예외 없음(켜야 한다 · CLAUDE 열쇠 921 과 같은 선) · EF qbo 가 KEY_ACTIONS(pull · 뒤에 send · job) 앞에 사용자 JWT 로 부른다 · 돌려주는 것 = staff_id';

create or replace function public.qbo_sync_gate() returns uuid
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  return public.qbo_key_gate(true);                                                                      -- 2a: admin 만 → 열쇠 qbo(쓰기) · 1a 창구 9 + 1c match_auto 의 호출 자리는 그대로
end;
$$;
comment on function public.qbo_sync_gate() is 'qbo-sync-2a 판정 945: 1a 짝 · 받기 창구의 문 = qbo_key_gate(true)(perms ''qbo'' · admin 도 켜야 한다) — 1a 때는 ims_is_admin 이었다 · 읽기 셋은 qbo_key_gate(false)';

-- 읽기 셋 재발행 — 1a(20261101210000:303 ~ 359) 바이트 그대로 · declare 의 gate 만 qbo_key_gate(false)
create or replace function public.qbo_link_summary() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of();
begin
  return (select jsonb_agg(jsonb_build_object('kind', k.kind, 'qbo_type', public.qbo_type_of(k.kind),
            'ims_active', (select count(*) from public.qbo_ims_rows(k.kind) r where r.ims_active),
            'linked',     (select count(*) from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = k.kind),
            'unlinked',   (select count(*) from public.qbo_ims_rows(k.kind) r where r.ims_active and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = k.kind and l.ims_id = r.ims_id)),
            'qbo_rows',   (select count(*) from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = public.qbo_type_of(k.kind) and e.gone_at is null),
            'qbo_active', (select count(*) from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = public.qbo_type_of(k.kind) and e.gone_at is null and e.active),
            'pull_finished_at', s.finished_at, 'pull_in_progress', (s.started_at is not null and s.finished_at is null), 'pull_next_start', s.next_start, 'pull_received', s.received) order by k.ord)
          from (values ('account', 1), ('tax_rule', 2), ('payment_term', 3), ('payment_method', 4), ('customer', 5), ('supplier', 6), ('product', 7), ('charge', 8), ('service', 9)) k(kind, ord)
          left join public.qbo_pull_state s on s.realm_id = v_realm and s.qbo_type = public.qbo_type_of(k.kind));
end;
$$;
create or replace function public.qbo_link_page(p_kind text, p_filter text default 'unlinked', p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(p_q), '');
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  if p_filter not in ('linked', 'unlinked', 'all') then raise exception 'filter must be linked, unlinked or all (got %)', p_filter; end if;
  return (with base as (
      select r.ims_id, r.ims_name, r.ims_code, r.ims_active, l.qbo_id, l.matched_by, l.matched_at, l.qbo_name_at_match, e.name as qbo_name, e.active as qbo_active, e.gone_at as qbo_gone_at
      from public.qbo_ims_rows(p_kind) r
      left join public.qbo_link l on l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id
      left join public.qbo_entity e on e.realm_id = v_realm and e.qbo_type = v_type and e.qbo_id = l.qbo_id
      where case p_filter when 'linked' then l.qbo_id is not null when 'unlinked' then r.ims_active and l.qbo_id is null else r.ims_active or l.qbo_id is not null end
        and (v_q is null or r.ims_name ilike '%' || v_q || '%' or r.ims_code ilike '%' || v_q || '%' or r.ims_id = v_q)),
    pg as (select * from base order by ims_name, ims_id limit v_lim offset v_off)
    select jsonb_build_object('kind', p_kind, 'qbo_type', v_type, 'filter', p_filter, 'total', (select count(*) from base), 'limit', v_lim, 'offset', v_off,
      'rows', coalesce((select jsonb_agg(to_jsonb(pg) || jsonb_build_object('candidates', coalesce((
                select jsonb_agg(jsonb_build_object('qbo_id', c.qbo_id, 'name', c.name, 'sku', c.sku, 'active', c.active) order by c.active desc, c.name)
                from (select e.* from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.gone_at is null
                        and case when p_kind = 'product' then lower(btrim(e.sku)) = lower(btrim(pg.ims_code))
                                 else lower(btrim(e.name)) = lower(btrim(pg.ims_name)) or e.name ilike pg.ims_name || '%' end
                      order by e.active desc, e.name limit 5) c), '[]'::jsonb)) order by pg.ims_name, pg.ims_id) from pg), '[]'::jsonb)));
end;
$$;
create or replace function public.qbo_entity_find(p_type text, p_q text default null, p_limit int default 20) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 50); v_q text := nullif(btrim(p_q), '');
begin
  if p_type is null or p_type not in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item') then raise exception 'type must be one of Account, TaxCode, Term, PaymentMethod, Customer, Vendor, Item (got %)', p_type; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('qbo_id', c.qbo_id, 'name', c.name, 'sku', c.sku, 'active', c.active, 'parent_id', c.parent_id, 'fully_qualified_name', c.fully_qualified_name,
                     'linked_to', (select jsonb_build_object('kind', l.ims_kind, 'ims_id', l.ims_id) from public.qbo_link l where l.realm_id = v_realm and l.qbo_type = p_type and l.qbo_id = c.qbo_id and l.ims_kind <> 'tax_rule' limit 1)) order by c.active desc, c.name)
                   from (select e.* from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = p_type and e.gone_at is null
                           and (v_q is null or e.name ilike '%' || v_q || '%' or e.sku ilike '%' || v_q || '%' or e.qbo_id = v_q) order by e.active desc, e.name limit v_lim) c), '[]'::jsonb);
end;
$$;
comment on function public.qbo_link_summary() is 'qbo-sync-1a: 종류 9 의 요약 — ims_active · linked · unlinked · qbo_rows · qbo_active · pull 상태(finished_at · in_progress · next_start · received) · [2a 945] 문 = qbo_key_gate(false)(qbo 또는 qbo:read)';
comment on function public.qbo_link_page(text, text, text, int, int) is 'qbo-sync-1a: 짝 화면 한 쪽 — filter linked(짝 있음) · unlinked(활성 · 짝 없음) · all(활성 ∪ 짝 있음) · q 는 이름 · 코드 ilike 또는 ims_id · limit ≤ 200 · 행 = IMS 행 + 짝 + 지금 QBO 이름 · candidates ≤ 5(product 는 같은 Sku · 그 밖은 같은 이름 또는 앞글자 · 0 이면 absent) · [2a 945] 문 = qbo_key_gate(false)';
comment on function public.qbo_entity_find(text, text, int) is 'qbo-sync-1a: QBO 행 고르기 — 종류 하나 · q 는 이름 · sku ilike 또는 Id · gone 제외 · limit ≤ 50 · linked_to = 이미 짝인 IMS 행(tax_rule 빼고) · [2a 945] 문 = qbo_key_gate(false)';

-- qbo_status 재발행 — 1a(20261029160000:166 ~ 190) 바이트 그대로 + caller_qbo
create or replace function public.qbo_status() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v      public.qbo_connection%rowtype;
  v_by   text;
  v_adm  boolean := public.ims_is_admin();
  v_key  text := (select case when s.perms ? 'qbo' then 'write' when s.perms ? 'qbo:read' then 'read' end from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);   -- 2a 945
  v_pins jsonb;
begin
  select coalesce(jsonb_object_agg(replace(c.key, 'qbo_realm_', ''), c.value), '{}'::jsonb) into v_pins from public.inv_config c where c.key in ('qbo_realm_sandbox', 'qbo_realm_production');
  select * into v from public.qbo_connection;
  if not found then
    return jsonb_build_object('status', 'none', 'caller_is_admin', v_adm, 'caller_qbo', v_key, 'pinned_realm', v_pins);
  end if;
  select s.name into v_by from public.ims_staff s where s.id = v.connected_by;
  return jsonb_build_object(
    'status', v.status, 'env', v.env, 'realm_id', v.realm_id, 'company_name', v.company_name,
    'connected_by', v_by, 'connected_at', v.connected_at,
    'access_expires_at', v.access_expires_at, 'refresh_expires_at', v.refresh_expires_at,
    'token_version', v.token_version, 'refreshing', (v.refreshing_until is not null and v.refreshing_until > now()),
    'last_refresh_at', v.last_refresh_at, 'last_error', v.last_error, 'last_error_at', v.last_error_at,
    'caller_is_admin', v_adm, 'caller_qbo', v_key, 'pinned_realm', v_pins);
end;
$$;
comment on function public.qbo_status() is 'qbo-1a: Settings ?t=qbo 가 읽는 연결 상태 한 줄 — 토큰 칸 없음(Vault id 도 없음) · 연결 없으면 status none · caller_is_admin(870 · 연결 단추를 보일지) · pinned_realm(env 별 고정 회사) · [2a 945] caller_qbo = write | read | null(짝 화면 · 일감 화면이 읽는다)';

-- ═══ B) 표 — qbo_job · qbo_txn(정책 0 · grant 0 · 창구만) · qbo_link CHECK created · inv_config 키 넷 ═══
create table public.qbo_job (
  id              uuid primary key default gen_random_uuid(),
  realm_id        text not null,
  kind            text not null constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void')),
  ims_kind        text not null constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit')),
  ims_id          text not null,                                                            -- uuid::text(customer · product · so_invoice · so_credit) · 'surcharge'(charge)
  state           text not null default 'queued' constraint qbo_job_state_ck check (state in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped')),
  attempts        int  not null default 0 constraint qbo_job_attempts_ck check (attempts >= 0),
  next_at         timestamptz not null default now(),
  claimed_at      timestamptz,
  request_id      uuid not null default gen_random_uuid(),                                  -- Intuit requestid(같은 realm 안 유일 · 50 자 안) · retry 마다 새로(같은 id 는 처음 응답을 되돌려 준다 · 실패 응답 포함)
  blocked_by      uuid references public.qbo_job (id),                                      -- 부모 손님 일감
  qbo_id          text,
  qbo_name        text,                                                                     -- QBO 가 받은 이름(DisplayName · Name — ` [SKU]` 가 붙었으면 그 이름)
  sync_token      text,
  sent_at         timestamptz,
  last_error      text,
  last_intuit_tid text,
  warning         text,                                                                     -- 몸을 만들 때의 경고(946 나라 이름 · 주소 없음 · 이름 자름 …) · 보내기를 막지 않는다
  note            text,                                                                     -- retry · skip 의 사람 말
  by_staff        uuid references public.ims_staff (id),
  created_at      timestamptz not null default clock_timestamp(),                           -- now() 이 아니라 clock_timestamp(): 한 트랜잭션에서 여러 일감을 쌓아도 쌓은 순서가 남는다(claim 은 created_at 순)
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id),
  constraint qbo_job_pair_ck     check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit' else ims_kind end
                                        and (kind <> 'item' or ims_kind in ('product', 'charge'))),
  constraint qbo_job_sending_ck  check (state <> 'sending' or claimed_at is not null),
  constraint qbo_job_error_ck    check (state not in ('failed', 'unknown') or last_error is not null),
  constraint qbo_job_blocked_ck  check (state <> 'blocked' or blocked_by is not null),
  constraint qbo_job_sent_ck     check ((state = 'sent') = (sent_at is not null) and (state <> 'sent' or qbo_id is not null)),
  constraint qbo_job_skipped_ck  check (state <> 'skipped' or note is not null),
  constraint qbo_job_not_self_ck check (blocked_by is null or blocked_by <> id)
);
create unique index qbo_job_open_idx on public.qbo_job (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped');   -- 열린 일감은 하나
create index qbo_job_pick_idx on public.qbo_job (state, next_at, created_at);
create index qbo_job_blocked_idx on public.qbo_job (blocked_by) where blocked_by is not null;
create trigger qbo_job_touch before update on public.qbo_job for each row execute function public.ims_touch();
comment on table public.qbo_job is 'qbo-sync-2a: QuickBooks 보내기 일감 — kind customer · item(2a) · invoice · credit · invoice_void · credit_void(2b) · ims_id 다형(FK 없음) · 열린 일감(sent · skipped 아님)은 (realm, kind, ims_kind, ims_id) 하나 · 상태 queued → sending → sent | failed | unknown · blocked(부모 손님 먼저) · skipped(사람) · ⚠️ 자동 재시도 없음 — 결과를 모르면 unknown · 사람이 retry(request_id 새로) · 컷오버 K';

create table public.qbo_txn (
  id          uuid primary key default gen_random_uuid(),
  realm_id    text not null,
  ims_kind    text not null constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit')),
  ims_id      text not null,                                                                -- so_invoice.id · so_credit.id ::text(FK 없음)
  qbo_type    text not null constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo')),
  qbo_id      text not null,
  doc_number  text,
  sync_token  text,
  total_amt   numeric,
  total_tax   numeric,
  sent_at     timestamptz not null default now(),
  voided_at   timestamptz,
  job_id      uuid references public.qbo_job (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' else 'CreditMemo' end),
  constraint qbo_txn_ims_key unique (realm_id, ims_kind, ims_id),
  constraint qbo_txn_qbo_key unique (realm_id, qbo_type, qbo_id)
);
create trigger qbo_txn_touch before update on public.qbo_txn for each row execute function public.ims_touch();
comment on table public.qbo_txn is 'qbo-sync-2a: IMS 인보이스 · 크레딧 ↔ QBO Invoice · CreditMemo 짝(2b 가 채운다 · 2a 는 표만) — ims_id 다형(FK 없음) · (realm, kind, ims_id) 하나 · (realm, type, qbo_id) 하나 · QBO 가 돌려준 합계(942 대조) · voided_at(2c) · 컷오버 K';

alter table public.qbo_job enable row level security;
alter table public.qbo_txn enable row level security;
revoke all on table public.qbo_job, public.qbo_txn from public, anon, authenticated, service_role;

alter table public.qbo_link drop constraint qbo_link_by_ck;
alter table public.qbo_link add constraint qbo_link_by_ck check (matched_by in ('auto_code', 'auto_name', 'auto_map', 'auto_sku', 'auto_sku_name', 'manual', 'created'));

insert into public.inv_config (key, value, note) values
  ('qbo_send_enabled', 'off', 'qbo-sync-2a: QuickBooks 보내기 cron 길 on | off — 수동 send(열쇠 qbo)는 이 값과 무관(이견 16) · cron 등록은 2b'),
  ('qbo_send_since', '', 'qbo-sync-2a: 이 날(YYYY-MM-DD) 이후 발행분만 일감을 쌓는다 · 비어 있으면 아무것도 안 쌓는다(2b 의 트리거가 본다)'),
  ('qbo_send_batch', '15', 'qbo-sync-2a: send 한 번에 claim 하는 일감 수(1 ~ 50)'),
  ('qbo_cogs_account_code', '_58_', 'qbo-sync-2a 이견 10: IMS 가 만드는 QuickBooks Item 의 ExpenseAccountRef(IMS 계정 코드 · qbo_link account 로 Id 를 찾는다) · QBO 실물 Item 14,737 이 #58 Cost of Goods Sold')
on conflict (key) do nothing;

-- ═══ C) 속 함수 넷 — grant 0 · 창구(add · claim) 안에서만 ═══
create function public.qbo_country_name(p text) returns text
  language sql immutable
as $$
  select case upper(btrim(coalesce(p, ''))) when '' then null when 'CA' then 'Canada' when 'US' then 'USA' else btrim(p) end
$$;
comment on function public.qbo_country_name(text) is 'qbo-sync-2a 판정 946: BillAddr.Country 는 나라 이름 — CA → Canada · US → USA · 이미 Canada 면 그대로 · 그 밖은 그대로(몸 함수가 경고 한 줄)';

create function public.qbo_account_ref(p_code text, p_what text) returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v text;
begin
  if nullif(btrim(coalesce(p_code, '')), '') is null then raise exception 'No IMS account code for % — set it in Settings — nothing was sent', p_what; end if;
  select l.qbo_id into v from public.ref_account a join public.qbo_link l on l.realm_id = public.qbo_realm_of() and l.ims_kind = 'account' and l.ims_id = a.id::text where a.code = p_code limit 1;
  if v is null then raise exception 'IMS account % (%) has no QuickBooks match — link it under Settings → QuickBooks matching — nothing was sent', p_code, p_what; end if;
  return v;
end;
$$;

-- 손님 몸(936 · 946 · 이견 6 · 7) — 돌려주는 것 = { kind customer · ims_id · display_name · body · warnings · parent_customer_id(부모 짝 없을 때만 · add 가 부모 일감 먼저) }
create function public.qbo_customer_body(p_customer_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_c public.customer%rowtype; v_a public.customer_address%rowtype; v_name text; v_dup text; v_email text; v_term text; v_tax text; v_parent text; v_country text;
        v_warn text[] := '{}'; v_cur text; v_body jsonb;
begin
  select * into v_c from public.customer c where c.id = p_customer_id;
  if v_c.id is null then raise exception 'No IMS customer % — nothing was sent', p_customer_id; end if;
  if not v_c.is_active then raise exception 'IMS customer % is inactive — not sent to QuickBooks', v_c.name; end if;
  v_name := left(btrim(v_c.name), 100);
  if v_name = '' then raise exception 'IMS customer % has an empty name — nothing was sent', p_customer_id; end if;
  if length(btrim(v_c.name)) > 100 then v_warn := array_append(v_warn, ('name cut to 100 characters: ' || v_name)); end if;
  select e.qbo_type || ' #' || e.qbo_id || ' ' || e.name into v_dup from public.qbo_entity e
    where e.realm_id = v_realm and e.qbo_type in ('Customer', 'Vendor') and e.gone_at is null and lower(btrim(e.name)) = lower(v_name) order by e.active desc, e.qbo_type, e.qbo_id limit 1;
  if v_dup is not null then raise exception 'QuickBooks already has a customer or supplier named "%" (%) — link the IMS customer to it under Settings → QuickBooks matching, or rename one of them — nothing was sent', v_name, v_dup; end if;
  select * into v_a from public.customer_address a where a.customer_id = p_customer_id and a.is_active and a.type = 'Billing' and a.is_default_for_type order by a.created_at, a.id limit 1;
  if v_a.id is null then v_warn := array_append(v_warn, 'no default billing address — BillAddr not sent'); end if;
  v_country := public.qbo_country_name(v_a.country);
  if v_country is not null and v_country not in ('Canada', 'USA') then v_warn := array_append(v_warn, ('country "' || v_country || '" sent as is (946 maps only CA and US)')); end if;
  v_email := public.doc_mail_recipient(p_customer_id)->>'to';
  if v_email is null then v_warn := array_append(v_warn, 'no email on file — PrimaryEmailAddr not sent'); end if;
  if v_c.payment_term_id is not null then
    select l.qbo_id into v_term from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_term' and l.ims_id = v_c.payment_term_id::text;
    if v_term is null then v_warn := array_append(v_warn, ('payment term "' || coalesce(v_c.payment_term_name, '?') || '" has no QuickBooks match — SalesTermRef not sent')); end if;
  end if;
  if nullif(btrim(coalesce(v_c.tax_rule, '')), '') is not null then
    select l.qbo_id into v_tax from public.ref_tax_rule t join public.qbo_link l on l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = v_c.tax_rule order by t.is_active desc limit 1;
    if v_tax is null then v_warn := array_append(v_warn, ('tax rule "' || v_c.tax_rule || '" has no QuickBooks match — DefaultTaxCodeRef not sent')); end if;
  end if;
  if v_c.parent_id is not null then
    select l.qbo_id into v_parent from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_c.parent_id::text;
  end if;
  v_cur := coalesce(nullif(btrim(coalesce(v_c.currency_code, '')), ''), (select c.value from public.inv_config c where c.key = 'customer_default_currency_code'), 'CAD');
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'DisplayName', v_name, 'CompanyName', v_name, 'Taxable', true,
    'CurrencyRef', jsonb_build_object('value', v_cur),
    'BillAddr', case when v_a.id is not null then jsonb_build_object('Line1', nullif(btrim(coalesce(v_a.line1, '')), ''), 'Line2', nullif(btrim(coalesce(v_a.line2, '')), ''), 'City', nullif(btrim(coalesce(v_a.city, '')), ''),
                                                                    'CountrySubDivisionCode', nullif(btrim(coalesce(v_a.state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_a.postal_code, '')), ''), 'Country', v_country) end,
    'PrimaryEmailAddr', case when v_email is not null then jsonb_build_object('Address', v_email) end,
    'SalesTermRef', case when v_term is not null then jsonb_build_object('value', v_term) end,
    'DefaultTaxCodeRef', case when v_tax is not null then jsonb_build_object('value', v_tax) end,
    'ParentRef', case when v_parent is not null then jsonb_build_object('value', v_parent) end,
    'Job', case when v_parent is not null then true end,
    'BillWithParent', case when v_parent is not null then (v_c.default_bill_to_customer_id = v_c.parent_id) end));
  return jsonb_build_object('kind', 'customer', 'ims_kind', 'customer', 'ims_id', p_customer_id::text, 'display_name', v_name, 'body', v_body, 'warnings', to_jsonb(v_warn),
                            'parent_customer_id', case when v_c.parent_id is not null and v_parent is null then v_c.parent_id::text end);
end;
$$;
comment on function public.qbo_customer_body(uuid) is 'qbo-sync-2a 판정 936 · 946: IMS 손님 → QBO Customer 만들기 몸 — DisplayName · CompanyName = left(btrim(name),100) · Customer · Vendor 거울과 이름이 같으면 실패(자동으로 바꾸지 않는다) · BillAddr = 기본 Billing 주소(Country CA → Canada · US → USA · 그 밖은 경고) · PrimaryEmailAddr = doc_mail_recipient 와 같은 선 · CurrencyRef · SalesTermRef · DefaultTaxCodeRef(tax_rule 이름 → qbo_link · 없으면 비움) · Taxable true · 전화 · 배송 주소 없음 · parent_id 있으면 ParentRef · Job · BillWithParent(청구처 = 부모) · 부모 짝 없으면 parent_customer_id 로 알린다';

-- Item 몸(937 · 941 · 943 · 944 · 이견 8 ~ 11) — p_ims_id = product.id::text 또는 'surcharge' · 돌려주는 것 = { kind item · ims_kind · ims_id · name · name_alt · sku · body · warnings }
create function public.qbo_item_body(p_ims_id text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.product%rowtype; v_ims_kind text; v_sku text; v_base text; v_name text; v_alt text; v_income text; v_expense text; v_dup text; v_warn text[] := '{}'; v_body jsonb;
begin
  if p_ims_id in ('freight', 'discount', 'freight_discount') then
    raise exception 'Charge % is not created as a QuickBooks item — freight and discount are linked already (Settings → QuickBooks matching) and a freight discount goes on the freight line (943) — nothing was sent', p_ims_id;
  elsif p_ims_id = 'surcharge' then
    v_ims_kind := 'charge';
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'surcharge') then raise exception 'IMS surcharge is already linked to a QuickBooks item — nothing was sent'; end if;
    v_base := 'Tariff Surcharge';
    select 'Item #' || e.qbo_id || ' ' || e.name || case when e.active then '' else ' (inactive)' end into v_dup from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Item' and e.gone_at is null and lower(btrim(e.name)) = lower(v_base) order by e.active desc, e.qbo_id limit 1;
    if v_dup is not null then raise exception 'QuickBooks already has an item named "%" (%) — link IMS surcharge to it under Settings → QuickBooks matching — nothing was sent', v_base, v_dup; end if;
    v_name := v_base;
    v_income := public.qbo_account_ref((select c.value from public.inv_config c where c.key = 'so_surcharge_account_code'), 'surcharge income (so_surcharge_account_code)');
    v_expense := null;
  else
    v_ims_kind := 'product';
    begin v_p.id := p_ims_id::uuid; exception when others then raise exception 'ims_id must be a product id or ''surcharge'' (got %) — nothing was sent', p_ims_id; end;
    select * into v_p from public.product p where p.id = p_ims_id::uuid;
    if v_p.id is null then raise exception 'No IMS product % — nothing was sent', p_ims_id; end if;
    if not v_p.is_active then raise exception 'IMS product % (%) is inactive — not sent to QuickBooks', v_p.sku, v_p.name; end if;
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'product' and l.ims_id = v_p.id::text) then raise exception 'IMS product % is already linked to a QuickBooks item — nothing was sent', v_p.sku; end if;
    v_sku := btrim(coalesce(v_p.sku, ''));
    if v_sku = '' then raise exception 'IMS product % has no SKU — nothing was sent', v_p.name; end if;
    -- 941: 같은 Sku 의 QBO Item 이 비활성뿐 → 자동으로 켜지 않는다 · 활성이 있으면 사람 짝
    select 'Item #' || e.qbo_id || ' ' || e.name into v_dup from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Item' and e.gone_at is null and e.active and lower(btrim(e.sku)) = lower(v_sku) order by e.qbo_id limit 1;
    if v_dup is not null then raise exception 'QuickBooks already has an active item with SKU % (%) — link it under Settings → QuickBooks matching — nothing was sent', v_sku, v_dup; end if;
    select 'Item #' || e.qbo_id || ' ' || e.name into v_dup from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Item' and e.gone_at is null and not e.active and lower(btrim(e.sku)) = lower(v_sku) order by e.qbo_id limit 1;
    if v_dup is not null then raise exception 'QuickBooks item is inactive — % has SKU % but is inactive in QuickBooks; make it active there, link it under Settings → QuickBooks matching, then send again — nothing was sent', v_dup, v_sku; end if;
    v_base := left(btrim(v_p.name), 100);
    if length(btrim(v_p.name)) > 100 then v_warn := array_append(v_warn, 'name cut to 100 characters'); end if;
    if position(':' in v_base) > 0 then v_base := replace(v_base, ':', '-'); v_warn := array_append(v_warn, 'colon in name replaced with -'); end if;
    v_alt := rtrim(left(v_base, greatest(100 - length(v_sku) - 3, 1))) || ' [' || v_sku || ']';
    select 'Item #' || e.qbo_id || case when e.active then '' else ' (inactive)' end into v_dup from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Item' and e.gone_at is null and lower(btrim(e.name)) = lower(v_base) order by e.active desc, e.qbo_id limit 1;
    if v_dup is not null then v_name := v_alt; v_warn := array_append(v_warn, ('name "' || v_base || '" is already used by QuickBooks ' || v_dup || ' — sent as "' || v_alt || '"')); else v_name := v_base; end if;
    v_income := public.qbo_account_ref(coalesce(nullif(btrim(coalesce(v_p.revenue_account_code, '')), ''), (select c.value from public.inv_config c where c.key = 'customer_default_sale_account_code')), 'product income (revenue_account_code · customer_default_sale_account_code)');
    v_expense := public.qbo_account_ref((select c.value from public.inv_config c where c.key = 'qbo_cogs_account_code'), 'cost of goods sold (qbo_cogs_account_code)');
  end if;
  v_body := jsonb_strip_nulls(jsonb_build_object('Name', v_name, 'Sku', v_sku, 'Type', 'Service', 'Taxable', true,
    'IncomeAccountRef', jsonb_build_object('value', v_income), 'ExpenseAccountRef', case when v_expense is not null then jsonb_build_object('value', v_expense) end));
  return jsonb_build_object('kind', 'item', 'ims_kind', v_ims_kind, 'ims_id', p_ims_id, 'name', v_name, 'name_alt', v_alt, 'sku', v_sku, 'body', v_body, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.qbo_item_body(text) is 'qbo-sync-2a 판정 937 · 941 · 943 · 944: IMS 제품(product.id) 또는 surcharge → QBO Item 만들기 몸 — Name = left(btrim(name),100) · 콜론 → - · gone 아닌 QBO Item 과 lower(btrim) 정확 비교(꼬리 「(deleted)」 떼지 않음) 같으면 ` [SKU]` · name_alt 는 늘 같이(6240 에 한 번 더) · 같은 Sku 가 비활성뿐이면 실패 「QuickBooks item is inactive」 · 활성이 있으면 실패(사람 짝) · Type Service · Taxable true · Income = coalesce(revenue_account_code, customer_default_sale_account_code) · Expense = qbo_cogs_account_code · surcharge → Tariff Surcharge · so_surcharge_account_code · Expense 없음 · freight · discount · freight_discount 거부';

-- ═══ D) 일감 창구 8 — 열쇠 넷(authenticated · qbo_key_gate) · service_role 넷(EF send · doc_is_service) ═══
create function public.qbo_job_add(p_kind text, p_ims_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_b jsonb; v_ims_kind text; v_j public.qbo_job%rowtype; v_parent jsonb; v_state text := 'queued'; v_blocked uuid;
begin
  if p_kind not in ('customer', 'item') then raise exception 'kind must be customer or item (invoice and credit jobs are queued by issuing — next step) — nothing was saved'; end if;
  if nullif(btrim(coalesce(p_ims_id, '')), '') is null then raise exception 'ims_id is required — nothing was saved'; end if;
  if p_kind = 'customer' then
    begin v_b := public.qbo_customer_body(p_ims_id::uuid); exception when invalid_text_representation then raise exception 'ims_id must be a customer id (got %) — nothing was saved', p_ims_id; end;
    if exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = p_ims_id) then raise exception 'IMS customer is already linked to a QuickBooks customer — nothing was saved'; end if;
  else
    v_b := public.qbo_item_body(p_ims_id);
  end if;
  v_ims_kind := v_b->>'ims_kind';
  select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = p_kind and j.ims_kind = v_ims_kind and j.ims_id = p_ims_id and j.state not in ('sent', 'skipped');
  if v_j.id is not null then return to_jsonb(v_j) || jsonb_build_object('existing', true, 'preview', v_b); end if;
  if v_b->>'parent_customer_id' is not null then                                                           -- 부모 손님 먼저(깊이 하나 · customer_parent_guard) · 이 일감은 blocked
    v_parent := public.qbo_job_add('customer', v_b->>'parent_customer_id');
    v_blocked := (v_parent->>'id')::uuid; v_state := 'blocked';
  end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, warning, by_staff)
  values (v_realm, p_kind, v_ims_kind, p_ims_id, v_state, v_blocked, nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), ''), v_staff)
  returning * into v_j;
  return to_jsonb(v_j) || jsonb_build_object('existing', false, 'preview', v_b, 'parent_job', v_parent);
end;
$$;
comment on function public.qbo_job_add(text, text) is 'qbo-sync-2a: 손님 · Item 만들기 일감을 미리 쌓는다(열쇠 qbo) — 몸을 미리 만들어 거부 사유를 바로 돌려준다(짝 있음 · 이름 충돌 · 비활성 Item …) · 열린 일감이 있으면 그것(existing true) · 부모 손님 짝이 없으면 부모 일감 먼저 + 이 일감 blocked · 돌려주는 것 = 일감 한 줄 + preview(몸) · 몸은 보낼 때 다시 만든다(이름 규칙은 그때)';

create function public.qbo_job_list(p_state text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0);
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  return (with base as (
      select j.*, case j.ims_kind when 'customer' then (select c.name from public.customer c where c.id::text = j.ims_id)
                                 when 'product' then (select p.sku || ' ' || p.name from public.product p where p.id::text = j.ims_id)
                                 when 'invoice' then (select i.invoice_number from public.so_invoice i where i.id::text = j.ims_id)
                                 when 'credit' then (select c.credit_number from public.so_credit c where c.id::text = j.ims_id) else j.ims_id end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name
      from public.qbo_job j where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state))
    select jsonb_build_object('state', p_state, 'total', (select count(*) from base), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg(to_jsonb(b) order by case b.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, b.created_at desc) from (select * from base order by case state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end, created_at desc limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
comment on function public.qbo_job_list(text, int, int) is 'qbo-sync-2a: 일감 목록(열쇠 qbo 또는 qbo:read) — state 하나 · open(sent · skipped 아님) · null = 전부 · counts(상태별) · 행 = 일감 + ims_name + by_name · unknown · failed 먼저 · limit ≤ 200';

create function public.qbo_job_claim(p_limit int default 15) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름으로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and p.state = 'sent';
  get diagnostics v_unblocked = row_count;
  -- ③ 잡기 — queued → sending(for update skip locked · 10 분 임대)
  with pick as (
    select j.id from public.qbo_job j where j.realm_id = v_realm and j.state = 'queued' and j.next_at <= now()
     order by j.created_at, j.id limit greatest(1, least(coalesce(p_limit, 15), 50)) for update skip locked),
  upd as (update public.qbo_job j set state = 'sending', claimed_at = now(), attempts = j.attempts + 1 from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ④ 몸은 다음 문장에서 일감마다(같은 문장 안의 읽기는 update 전 행을 본다) · 몸이 안 만들어지면 그 일감만 failed
  for v_j in select * from public.qbo_job j where j.id = any (v_ids) order by j.created_at, j.id loop
    begin
      v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id) end;
      if v_b is null then raise exception 'kind % is not sendable yet (2b)', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), '') where j.id = v_j.id;
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'body', v_b->'body', 'warnings', v_b->'warnings');
    exception when others then
      update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(sqlerrm, 2000) where j.id = v_j.id;
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('realm_id', v_realm, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'jobs', v_rows);
end;
$$;
comment on function public.qbo_job_claim(int) is 'qbo-sync-2a: EF send 가 service_role 로 부른다 — ① sending 10 분 넘음 → unknown(자동 재전송 없음) ② blocked → queued(부모 sent) ③ queued · next_at 지남 → sending(for update skip locked · 1 ~ 50) ④ 일감마다 몸(qbo_customer_body · qbo_item_body) · 몸 실패는 그 일감만 failed · 돌려주는 것 = recovered_unknown · unblocked · claimed · body_failed · jobs[{job_id · kind · ims_kind · ims_id · attempt · request_id · name · name_alt · sku · body · warnings}]';

create function public.qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_done is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can be finished (this one is %) — nothing was saved', v_j.state; end if;
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null or nullif(btrim(coalesce(p_qbo_name, '')), '') is null then raise exception 'qbo_id and qbo_name are required — nothing was saved'; end if;
  update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = btrim(p_qbo_name), sync_token = p_sync_token, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         last_error = case when p_note is not null then left(coalesce(j.last_error || ' · ', '') || p_note, 2000) else j.last_error end, attempts = j.attempts + case when p_note is not null then 1 else 0 end
   where j.id = v_j.id;
  if v_j.kind in ('customer', 'item') then
    v_type := case v_j.ims_kind when 'customer' then 'Customer' else 'Item' end;
    insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active, sync_token, fetched_at, gone_at)
    values (v_j.realm_id, v_type, btrim(p_qbo_id), btrim(p_qbo_name), nullif(btrim(coalesce(p_sku, '')), ''), true, p_sync_token, now(), null)
    on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = coalesce(excluded.sku, public.qbo_entity.sku), active = true, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null;
    begin
      insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
      values (v_j.realm_id, v_j.ims_kind, v_j.ims_id, v_type, btrim(p_qbo_id), 'created', btrim(p_qbo_name), v_j.by_staff)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_type = excluded.qbo_type, qbo_id = excluded.qbo_id, matched_by = 'created', qbo_name_at_match = excluded.qbo_name_at_match, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff;
    exception when unique_violation then                                                              -- QBO 쪽 부분 유일(이미 다른 IMS 행의 짝) — QBO 레코드는 생겼다 · 사람이 짝을 바로잡는다
      v_link_err := format('QuickBooks %s #%s was created but is already linked to another IMS row — fix the link by hand under Settings → QuickBooks matching', v_type, btrim(p_qbo_id));
      update public.qbo_job j set state = 'failed', sent_at = null, last_error = left(coalesce(j.last_error || ' · ', '') || v_link_err, 2000) where j.id = v_j.id;
    end;
    if v_link_err is null then
      update public.qbo_job j set state = 'queued', next_at = now() where j.state = 'blocked' and j.blocked_by = v_j.id;
      get diagnostics v_unblocked = row_count;
    end if;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked);
end;
$$;
comment on function public.qbo_job_done(uuid, text, text, text, text, text, text) is 'qbo-sync-2a: 보내기 성공(service_role) — sending · unknown → sent(qbo_id · qbo_name · sync_token · intuit_tid) · p_note 는 「6240 뒤 [SKU] 로 다시」 같은 흔적(last_error 에 덧붙이고 attempts +1) · customer · item 이면 qbo_entity upsert + qbo_link(created · 있으면 덮음) + 자식 일감 풀기 · QBO Id 가 이미 다른 IMS 행의 짝이면 failed + 사람 말(QBO 레코드는 생겼다)';

create function public.qbo_job_fail(p_job uuid, p_error text, p_intuit_tid text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_fail is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can fail (this one is %) — nothing was saved', v_j.state; end if;
  update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'send failed'), 2000), last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid) where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'failed', 'attempts', v_j.attempts);
end;
$$;
comment on function public.qbo_job_fail(uuid, text, text) is 'qbo-sync-2a: 보내기 거부(service_role · QBO 가 4xx 로 처리 안 됨이 분명할 때) — sending · unknown → failed · 자동 재시도 없음 · 사람이 qbo_job_retry';

create function public.qbo_job_unknown(p_job uuid, p_error text, p_intuit_tid text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_unknown is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state <> 'sending' then raise exception 'Only a job being sent can become unknown (this one is %) — nothing was saved', v_j.state; end if;
  update public.qbo_job j set state = 'unknown', claimed_at = null, last_error = left(coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'no answer from QuickBooks'), 2000), last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid) where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'unknown', 'attempts', v_j.attempts);
end;
$$;
comment on function public.qbo_job_unknown(uuid, text, text) is 'qbo-sync-2a: 결과를 모른다(service_role · 네트워크 끊김 · 5xx · 응답 없음) — sending → unknown · 다음 send 가 이름(DisplayName · Name · Sku)으로 조회해 있으면 done · 없으면 사람이 retry';

create function public.qbo_job_retry(p_job uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype;
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown') then raise exception 'Only a failed job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = coalesce(nullif(btrim(p_note), ''), j.note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts);
end;
$$;
comment on function public.qbo_job_retry(uuid, text) is 'qbo-sync-2a: 다시 보내기(열쇠 qbo) — failed · unknown → queued · request_id 새로(같은 requestid 는 처음 응답을 되돌려 준다) · unknown 은 note 필수(QBO 에서 확인한 것) · last_error 는 남긴다';

create function public.qbo_job_skip(p_job uuid, p_note text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype;
begin
  if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this job is skipped (a note is required) — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('queued', 'blocked', 'failed', 'unknown') then raise exception 'Only a queued, blocked, failed or unknown job can be skipped (this one is %) — nothing was saved', v_j.state; end if;
  update public.qbo_job j set state = 'skipped', claimed_at = null, note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'skipped', 'blocked_children', (select count(*) from public.qbo_job c where c.blocked_by = v_j.id and c.state = 'blocked'));
end;
$$;
comment on function public.qbo_job_skip(uuid, text) is 'qbo-sync-2a: 건너뛰기(열쇠 qbo · note 필수 · 「QuickBooks 에 손으로 넣었다」 등) — queued · blocked · failed · unknown → skipped · 자식 blocked 는 그대로(사람이 본다) · 짝은 qbo_link_set 으로 따로';

-- ═══ E) grant — 열쇠 창구 authenticated · service 창구 service_role · 속 함수 grant 0 ═══
revoke all on function public.qbo_key_gate(boolean), public.qbo_sync_gate(), public.qbo_country_name(text), public.qbo_account_ref(text, text), public.qbo_customer_body(uuid), public.qbo_item_body(text),
  public.qbo_job_add(text, text), public.qbo_job_list(text, int, int), public.qbo_job_retry(uuid, text), public.qbo_job_skip(uuid, text),
  public.qbo_job_claim(int), public.qbo_job_done(uuid, text, text, text, text, text, text), public.qbo_job_fail(uuid, text, text), public.qbo_job_unknown(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.qbo_key_gate(boolean), public.qbo_job_add(text, text), public.qbo_job_list(text, int, int), public.qbo_job_retry(uuid, text), public.qbo_job_skip(uuid, text) to authenticated;
grant execute on function public.qbo_job_claim(int), public.qbo_job_done(uuid, text, text, text, text, text, text), public.qbo_job_fail(uuid, text, text), public.qbo_job_unknown(uuid, text, text) to service_role;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(c.relname || '=' || c.relacl::text || '/rls=' || c.relrowsecurity::text, ' ' order by c.relname) into v from pg_class c where c.oid in ('public.qbo_job'::regclass, 'public.qbo_txn'::regclass);
  if v <> 'qbo_job={postgres=arwdDxtm/postgres}/rls=true qbo_txn={postgres=arwdDxtm/postgres}/rls=true' then raise exception 'qbo-sync-2a landing: table acl %', v; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('qbo_job', 'qbo_txn')) <> 0 then raise exception 'qbo-sync-2a landing: policies must be 0'; end if;
  select string_agg(distinct confrelid::regclass::text, ' ' order by confrelid::regclass::text) into v from pg_constraint where conrelid in ('public.qbo_job'::regclass, 'public.qbo_txn'::regclass) and contype = 'f';
  if v <> 'ims_staff qbo_job' then raise exception 'qbo-sync-2a landing: FK targets %', v; end if;
  if not (public.ims_perm_catalog()->'screens' ? 'qbo') then raise exception 'qbo-sync-2a landing: catalog qbo'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'qbo_link_by_ck') !~ '''created''' then raise exception 'qbo-sync-2a landing: qbo_link_by_ck created'; end if;
  if (select count(*) from public.inv_config where key in ('qbo_send_enabled', 'qbo_send_since', 'qbo_send_batch', 'qbo_cogs_account_code')) <> 4 then raise exception 'qbo-sync-2a landing: inv_config keys'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_status') !~ 'caller_qbo' then raise exception 'qbo-sync-2a landing: qbo_status caller_qbo'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_sync_gate') !~ 'qbo_key_gate\(true\)' then raise exception 'qbo-sync-2a landing: qbo_sync_gate body'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_link_summary', 'qbo_link_page', 'qbo_entity_find') and prosrc ~ 'qbo_key_gate\(false\)') <> 3 then raise exception 'qbo-sync-2a landing: read gates'; end if;
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_key_gate', 'qbo_country_name', 'qbo_account_ref', 'qbo_customer_body', 'qbo_item_body', 'qbo_job_add', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_skip', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_fail', 'qbo_job_unknown');
  if v <> 'qbo_account_ref={postgres=X/postgres} qbo_country_name={postgres=X/postgres} qbo_customer_body={postgres=X/postgres} qbo_item_body={postgres=X/postgres} qbo_job_add={postgres=X/postgres,authenticated=X/postgres} qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_fail={postgres=X/postgres,service_role=X/postgres} qbo_job_list={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_job_skip={postgres=X/postgres,authenticated=X/postgres} qbo_job_unknown={postgres=X/postgres,service_role=X/postgres} qbo_key_gate={postgres=X/postgres,authenticated=X/postgres}'
    then raise exception 'qbo-sync-2a landing: function acl %', v; end if;
  raise notice 'qbo-sync-2a landing OK — 표 2 acl+rls · 정책 0 · FK → ims_staff · qbo_job(자기) 만 · 카탈로그 qbo · qbo_link created · inv_config 4 · qbo_status caller_qbo · 문 재발행 5 · 창구 8 + 열쇠 문 · 속 함수 4 grant 0';
end $$;
