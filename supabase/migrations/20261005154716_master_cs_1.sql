-- ─────────────────────────────────────────────────────────────
-- 손님 · 공급처 마스터의 문 — 손님 표 셋 직접 쓰기 닫기 · created_by · 공급처 연락처 「기본 하나」 (Asung-IMS · master-cs-1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §41 — 판정 236(손님 · 공급처 먼저) · 237(만들기 · 일반 칸은 일하는 열쇠 · 돈 조건 칸은 master) · 238(같은 이름 — 손님은 알리고 확인 · 공급처는 막는다) · master-cs 묶음 1 ~ 9 · 조사 master-cs-0
--   든 것: ① customer · customer_address · customer_contact 의 authenticated 직접 쓰기를 닫는다(prod-2 20261001123000 C 절과 같은 길 — 쓰기 정책 drop + revoke · select 정책 · grant 그대로)
--           ⚠️ customer 의 UPDATE 만 다르다 — so_invoice_issue(마지막 정의 20261002144956:76 · security invoker · 145 행 `perform 1 from public.customer c where … for update`)가 직원 신원으로 손님 행을 잠근다.
--             FOR UPDATE 는 UPDATE 권한과 UPDATE 정책의 USING 을 함께 요구한다 — 권한을 걷거나 정책을 지우면 그 잠금이 42501 로 죽거나(권한) 0 행으로 조용히 빠진다(정책 없음 = 거부 → 잠그지 못한 채 지나간다).
--             ⇒ UPDATE 권한은 두고 정책을 「잠금만」으로 바꾼다: using (true) · with check (false) — 행을 잠글 수는 있고, 바꾸면 RLS 가 문장으로 거부한다(42501 · 조용한 0 행이 아니다). INSERT 는 권한까지 걷는다 · DELETE 는 이미 걷혀 있다(20260922201223:228).
--             (대안 = so_invoice_issue 를 definer 로 재발행 — 이 차수의 「재발행 0」 과 어긋나 두지 않았다 · cs-2b 나 뒤 차수의 판정 거리)
--         ② customer · supplier 에 created_by(uuid → ims_staff · nullable · 옛 행 · 적재 행은 null · 만들기 창구가 채운다 · 묶음 6 · 35-e 60 과 같은 줄기) · 주소 · 연락처 표에는 두지 않는다(줄은 창구가 insert 때 updated_by 를 함께 적는다)
--         ③ supplier_contact 에 customer_contact 와 같은 「기본 하나」 장치 — 생성 칸 default_supplier_id + 전체 유니크 supplier_contact_default_uq deferrable initially immediate(20260923014604 판정 ⑪ 그대로 · 부분 유니크 아님 · 지금 둘 이상인 공급처 0 · 비활성 포함 0)
--   닫은 뒤에도 사는 길: 적재 ImsLoadCustomer.gs = service_role(ImsRefLoad.gs ims_fetch_ · rolbypassrls · 표 권한 그대로) · definer 창구(so_create → so_copy_customer · 잔액 · 크레딧 · 결제 열 창구의 for update 잠금) · 트리거 ims_touch(definer) · 소유자 psql
--   닫히는 길: authenticated PostgREST 의 insert · update · delete(화면은 쓰는 곳 0 · master-cs-0 §C) · 공급처 표 넷은 이번에 닫지 않는다(suppliers.html 173 의 is_purchasable 직접 update — cs-3 에서 화면 한 줄과 함께)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 0 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다(prod-2 D 절 모양)
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

-- ═══ 1) 손님 표 셋 닫기 — 정책 이름은 원문 그대로(customer 20260922201223:212~223 · 주소 · 연락처 20260923182231:45~57) · 없는 것도 if exists ═══
-- customer: INSERT 닫기 · UPDATE 는 「잠금만」 · DELETE 는 이미 걷힘(다시 걷어도 같다)
drop policy if exists customer_insert on public.customer;
drop policy if exists customer_update on public.customer;
drop policy if exists customer_delete on public.customer;
create policy customer_update_lock_only on public.customer for update to authenticated using (true) with check (false);
revoke insert, delete on public.customer from authenticated;
comment on policy customer_update_lock_only on public.customer is
  'master-cs-1 — authenticated 는 손님 행을 바꿀 수 없다(with check false → 42501 문장) · 잠글 수는 있다(using true — so_invoice_issue 가 invoker 로 for update 한다 · UPDATE 권한도 그래서 남겼다) · 쓰기는 창구(cs-2a · 2b · definer)로만';

-- customer_address · customer_contact: 셋 다 drop + revoke insert · update · delete (관계 표 · 잠그는 함수 없음 · select 는 그대로)
drop policy if exists customer_address_insert on public.customer_address;
drop policy if exists customer_address_update on public.customer_address;
drop policy if exists customer_address_delete on public.customer_address;
revoke insert, update, delete on public.customer_address from authenticated;

drop policy if exists customer_contact_insert on public.customer_contact;
drop policy if exists customer_contact_update on public.customer_contact;
drop policy if exists customer_contact_delete on public.customer_contact;
revoke insert, update, delete on public.customer_contact from authenticated;

-- ═══ 2) created_by — 두 마스터 · nullable · FK · 인덱스(규약 <표>_<칸>_idx) · 옛 행 무접촉 ═══
alter table public.customer add column if not exists created_by uuid references public.ims_staff (id) on delete no action;
create index if not exists customer_created_by_idx on public.customer (created_by);
comment on column public.customer.created_by is 'master-cs-1(묶음 6) — IMS 에서 만든 사람(ims_staff.id) · 만들기 창구(cs-2a)가 채운다 · 적재 행 · 옛 행은 null(= Cin7 에서 왔다) · updated_by 는 고칠 때만(ims_touch)';
alter table public.supplier add column if not exists created_by uuid references public.ims_staff (id) on delete no action;
create index if not exists supplier_created_by_idx on public.supplier (created_by);
comment on column public.supplier.created_by is 'master-cs-1(묶음 6) — IMS 에서 만든 사람(ims_staff.id) · 만들기 창구(cs-3)가 채운다 · 적재 행 · 옛 행은 null(= Cin7 에서 왔다)';

-- ═══ 3) supplier_contact 「기본 하나」 — customer_contact 와 같은 모양(생성 칸 + 전체 유니크 · deferrable initially immediate · 20260923014604) ═══
alter table public.supplier_contact
  add column default_supplier_id uuid generated always as (case when is_default then supplier_id end) stored;
alter table public.supplier_contact
  add constraint supplier_contact_default_uq unique (default_supplier_id) deferrable initially immediate;
comment on column public.supplier_contact.default_supplier_id is
  '생성 칸 — is_default 이면 supplier_id · 아니면 null · 전체 유니크 supplier_contact_default_uq 가 「공급처당 기본 연락처 하나」(master-cs-1 묶음 4 · customer_contact.default_customer_id 와 같은 장치 · 부분 유니크 아님 — PostgREST on_conflict 선례) · deferrable initially immediate: 한 문장 안에서 기본을 옮길 때(옛 false · 새 true 가 같은 문장) 줄 순서와 상관없이 문장 끝에 한 번 검사 · 문장을 나누려면 set constraints … deferred · ⚠️ 적재가 보내지 않는 칸(생성 칸 — 보내면 거부)';

-- ═══ 4) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_bad text := '';
  v_n   int;
begin
  -- customer: 정책 2(select · update_lock_only) · insert · delete 권한 없음 · update · select 있음
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'customer';
  if v_n <> 2 or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customer' and policyname = 'customer_select' and cmd = 'SELECT')
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customer' and policyname = 'customer_update_lock_only' and cmd = 'UPDATE' and qual = 'true' and with_check = 'false') then
    v_bad := v_bad || format(' customer(policies %s)', v_n);
  end if;
  if has_table_privilege('authenticated', 'public.customer', 'insert') or has_table_privilege('authenticated', 'public.customer', 'delete')
     or has_any_column_privilege('authenticated', 'public.customer', 'insert')
     or not has_table_privilege('authenticated', 'public.customer', 'update') or not has_table_privilege('authenticated', 'public.customer', 'select') then
    v_bad := v_bad || ' customer(privileges)';
  end if;
  -- customer_address · customer_contact: 정책 1(select) · insert · update · delete 권한 없음 · select 있음
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'customer_address') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customer_address' and cmd = 'SELECT')
     or has_table_privilege('authenticated', 'public.customer_address', 'insert') or has_table_privilege('authenticated', 'public.customer_address', 'update')
     or has_table_privilege('authenticated', 'public.customer_address', 'delete') or has_any_column_privilege('authenticated', 'public.customer_address', 'update')
     or not has_table_privilege('authenticated', 'public.customer_address', 'select') then
    v_bad := v_bad || ' customer_address';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'customer_contact') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customer_contact' and cmd = 'SELECT')
     or has_table_privilege('authenticated', 'public.customer_contact', 'insert') or has_table_privilege('authenticated', 'public.customer_contact', 'update')
     or has_table_privilege('authenticated', 'public.customer_contact', 'delete') or has_any_column_privilege('authenticated', 'public.customer_contact', 'update')
     or not has_table_privilege('authenticated', 'public.customer_contact', 'select') then
    v_bad := v_bad || ' customer_contact';
  end if;
  -- 적재 계정은 그대로(service_role · 세 표 insert · update)
  if not (has_table_privilege('service_role', 'public.customer', 'insert') and has_table_privilege('service_role', 'public.customer', 'update')
          and has_table_privilege('service_role', 'public.customer_address', 'insert') and has_table_privilege('service_role', 'public.customer_contact', 'insert')) then
    v_bad := v_bad || ' service_role(privileges)';
  end if;
  -- created_by 둘 · supplier_contact 장치
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name in ('customer', 'supplier') and column_name = 'created_by' and is_nullable = 'YES') <> 2 then
    v_bad := v_bad || ' created_by';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'supplier_contact_default_uq' and conrelid = 'public.supplier_contact'::regclass and condeferrable and not condeferred)
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'supplier_contact' and column_name = 'default_supplier_id' and is_generated = 'ALWAYS') then
    v_bad := v_bad || ' supplier_contact(default device)';
  end if;
  -- 공급처 표 넷은 이번에 건드리지 않았다
  if not (has_table_privilege('authenticated', 'public.supplier', 'update') and has_table_privilege('authenticated', 'public.supplier_contact', 'insert')) then
    v_bad := v_bad || ' supplier(privileges changed)';
  end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM236',
      message = format('STOP - the customer door is not closed as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
