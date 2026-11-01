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
-- qbo-sync-1a — QuickBooks 짝 표 qbo_link · 받기 거울 qbo_entity · 받기 진행 qbo_pull_state + 창구 9(pull 셋 · 자동 짝 · 사람 짝 둘 · 읽기 셋) (2026-11-01 · 판정 934 · 지시서 ~/asung/prompts/qbo-sync-1.md · 이견 1 ~ 15 답 반영)
--   무엇: IMS 행(계정 · 세금 규칙 · 결제조건 · 결제 수단 · 손님 · 공급처 · 제품 · charge · 서비스) ↔ QBO Id 의 짝을 qbo_link 한 줄로 든다 — 한 번 정하면 QBO Id 로 붙든다(IMS 이름이 바뀌어도 그 Id · 이견 2)
--         QBO 목록은 qbo_entity 에 받아 둔다(934 · 칸 = id · name · sku · parent_id · fully_qualified_name · active · sync_token · fetched_at · gone_at — 연락처 · 주소 · 금액 0 · 933 과 같은 선)
--         받기 = EF qbo 의 pull(1b)이 한 쪽씩 qbo_entity_upsert · 완주하면 qbo_pull_finish 가 이번 run 에서 안 온 줄에 gone_at(이견 11) · 받기 전엔 자동 짝 거부(이견 15)
--   자동 짝(qbo_match_auto · 활성 IMS 행 · 짝 없는 것만 · 이견 6): account = code _N_ → Account.Id N · tax_rule = 「 (Sale)」「 (Purchase)」 꼬리 뗀 이름 = TaxCode 이름(활성 쪽 · GST 7/8) · payment_term = 공백 뺀 이름
--         payment_method = 고정 표(cheque → Cheque · debit_card → Debit · e_transfer → E-Transfer · wire → Wire · cash → Cash · shopify → Shopify · direct_deposit → EFT (ACH) · credit_card · opening 은 짝 없음 · 이견 4)
--         customer · supplier = lower(btrim(name)) = DisplayName · product = Sku 같은 활성 Item 하나 → 둘 이상이면 lower(btrim(left(name,100))) 같은 것 하나 → 아니면 사람 (이견 7)
--         결과 = linked · absent(QBO 후보 0 · 다음 차수가 만든다 · 화면의 「사람이 할 일」 아님) · ambiguous(후보는 있는데 못 고름 · 사람) · skipped(credit_card) (이견 2)
--   유일: (realm, ims_kind, ims_id) 하나 · QBO 쪽은 부분 유일 색인 (realm, qbo_type, qbo_id) where ims_kind <> 'tax_rule'(세금은 Sale · Purchase 둘 → TaxCode 하나 · 이견 1) · ref_tax_rule.qbo_id 는 쓰지 않는다(주석만)
--   charge(ims_id freight · discount · surcharge · freight_discount) · service(ref_service.id) 는 사람이 qbo_link_set — 이 마이그레이션은 QBO Id 를 박지 않는다(이견 5)
--   문: 창구 9 전부 authenticated + ims_is_admin()(qbo_sync_gate · 870 과 같은 선 · 읽기도 admin — QBO 이름 목록) · 표는 정책 0 · grant 0(창구만 · qbo_connection 꼴) · 속 함수 4 는 grant 0
--   REST safeupdate: update · delete 전부 WHERE 있음(qbo_pull_finish · qbo_pull_begin 의 on conflict 는 INSERT · qbo_link_clear) — 시험 qbo_sync_1a_check.sql 의 nowhere 스캐너 + 둘째 겹 = 1b 배포 뒤 실제 호출
--   FK: qbo_link.by_staff · updated_by · qbo_pull_state.started_by → ims_staff 뿐 · 거래 표 FK 0 · qbo_link.ims_id 는 다형(text · FK 없음) — 컷오버 지우는 순서 영향 없음
--   ⚠️ 자동 grant 없음(10-30 부터 default acl 은 authenticated=Dxtm) — 표 · 함수 grant 를 여기서 명시한다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(G0)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261101210000_qbo_sync_1a_link_entity.sql && supabase migration repair --status applied 20261101210000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261101210000_qbo_sync_1a_link_entity.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_1a_check.sql

-- ═══ A) 표 셋 — 정책 0 · grant 0(창구만) ═══
create table public.qbo_entity (
  realm_id             text not null,
  qbo_type             text not null constraint qbo_entity_type_ck check (qbo_type in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item')),
  qbo_id               text not null,
  name                 text not null,                                                      -- Name · 손님 · 공급처는 DisplayName
  sku                  text,                                                               -- Item 만
  parent_id            text,                                                               -- ParentRef.value(하위 손님 · 하위 계정 · 하위 품목)
  fully_qualified_name text,
  active               boolean not null default true,
  sync_token           text,
  fetched_at           timestamptz not null default now(),
  gone_at              timestamptz,                                                        -- 완주한 pull 에서 안 왔다 = QBO 에서 사라짐(지우지 않는다 · 짝이 가리킬 수 있다)
  primary key (realm_id, qbo_type, qbo_id)
);
create index qbo_entity_name_idx on public.qbo_entity (realm_id, qbo_type, lower(btrim(name)));
create index qbo_entity_sku_idx  on public.qbo_entity (realm_id, qbo_type, lower(btrim(sku))) where sku is not null;
comment on table public.qbo_entity is 'qbo-sync-1a 판정 934: QuickBooks 목록 거울(Account · TaxCode · Term · PaymentMethod · Customer · Vendor · Item) — id · 이름 · sku · 부모 · 활성 · SyncToken 만(연락처 · 주소 · 금액 0 · 933) · EF qbo pull 이 한 쪽씩 qbo_entity_upsert · 완주하면 qbo_pull_finish 가 안 온 줄에 gone_at · 읽기는 창구(admin)만 · 컷오버 K';

create table public.qbo_pull_state (
  realm_id    text not null,
  qbo_type    text not null constraint qbo_pull_state_type_ck check (qbo_type in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item')),
  started_at  timestamptz not null default now(),
  started_by  uuid references public.ims_staff (id),
  next_start  int not null default 1,                                                      -- 다음 쪽의 STARTPOSITION(EF 가 넘겨 준 값 · 이어 받기용)
  received    int not null default 0,
  pages       int not null default 0,
  finished_at timestamptz,
  gone        int,                                                                         -- 마지막 완주에서 gone_at 을 찍은 수
  updated_at  timestamptz not null default now(),
  primary key (realm_id, qbo_type)
);
comment on table public.qbo_pull_state is 'qbo-sync-1a: QBO 목록 받기 진행(종류마다 한 줄) — qbo_pull_begin(새 run · 끝난 run 뒤거나 restart · 아니면 이어 받기) → qbo_entity_upsert 쪽마다 → qbo_pull_finish(gone_at · finished_at) · finished_at 없으면 그 종류 자동 짝 거부';

create table public.qbo_link (
  id                uuid primary key default gen_random_uuid(),
  realm_id          text not null,
  ims_kind          text not null constraint qbo_link_kind_ck check (ims_kind in ('account', 'tax_rule', 'payment_term', 'payment_method', 'customer', 'supplier', 'product', 'charge', 'service')),
  ims_id            text not null,                                                         -- uuid::text(표 있는 종류) · 값 문자열(payment_method · charge)
  qbo_type          text not null constraint qbo_link_type_ck check (qbo_type in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item')),
  qbo_id            text not null,
  matched_by        text not null constraint qbo_link_by_ck check (matched_by in ('auto_code', 'auto_name', 'auto_map', 'auto_sku', 'auto_sku_name', 'manual')),
  qbo_name_at_match text,                                                                  -- 짝 지을 때의 QBO 이름(화면용 · 지금 이름은 qbo_entity)
  by_staff          uuid references public.ims_staff (id),
  matched_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id),
  constraint qbo_link_pair_ck check (qbo_type = case ims_kind when 'account' then 'Account' when 'tax_rule' then 'TaxCode' when 'payment_term' then 'Term' when 'payment_method' then 'PaymentMethod'
                                                              when 'customer' then 'Customer' when 'supplier' then 'Vendor' else 'Item' end),
  constraint qbo_link_ims_key unique (realm_id, ims_kind, ims_id)
);
create unique index qbo_link_qbo_one_idx on public.qbo_link (realm_id, qbo_type, qbo_id) where ims_kind <> 'tax_rule';   -- QBO 쪽 1:1 · 세금만 N:1(Sale · Purchase → TaxCode 하나)
create index qbo_link_qbo_idx on public.qbo_link (realm_id, qbo_type, qbo_id);
create trigger qbo_link_touch before update on public.qbo_link for each row execute function public.ims_touch();
comment on table public.qbo_link is 'qbo-sync-1a 판정 934: IMS 행 ↔ QBO Id 짝(한 번 정하면 QBO Id 로 붙든다 · IMS 이름이 바뀌어도 그 Id) — ims_kind 9 · ims_id 다형(FK 없음) · (realm, kind, ims_id) 하나 · QBO 쪽은 tax_rule 빼고 1:1(부분 유일 색인) · 자동 qbo_match_auto · 사람 qbo_link_set · 풀기 qbo_link_clear · ref_tax_rule.qbo_id 는 쓰지 않는다 · 컷오버 K';
comment on column public.ref_tax_rule.qbo_id is 'qbo-sync-1a: 쓰지 않는다 — 짝은 qbo_link(ims_kind tax_rule · Sale · Purchase 둘이 TaxCode 하나를 가리키므로 이 UNIQUE 칸에는 못 넣는다 · 이견 1) · 지우기는 별건 · 지금 null';

alter table public.qbo_entity enable row level security;
alter table public.qbo_pull_state enable row level security;
alter table public.qbo_link enable row level security;
revoke all on table public.qbo_entity, public.qbo_pull_state, public.qbo_link from public, anon, authenticated, service_role;

-- ═══ B) 속 함수 넷 — grant 0 · 창구 안에서만 ═══
create function public.qbo_sync_gate() returns uuid
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not public.ims_is_admin() then raise exception 'Only an admin can manage QuickBooks links — nothing was changed'; end if;
  return (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active limit 1);
end;
$$;
create function public.qbo_realm_of() returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v text := (select c.realm_id from public.qbo_connection c where c.singleton);
begin
  if v is null then raise exception 'QuickBooks is not connected — connect it in Settings → QuickBooks first'; end if;
  return v;
end;
$$;
create function public.qbo_type_of(p_kind text) returns text
  language sql immutable
as $$
  select case p_kind when 'account' then 'Account' when 'tax_rule' then 'TaxCode' when 'payment_term' then 'Term' when 'payment_method' then 'PaymentMethod'
                     when 'customer' then 'Customer' when 'supplier' then 'Vendor' when 'product' then 'Item' when 'charge' then 'Item' when 'service' then 'Item' end
$$;
-- IMS 쪽 행 — 종류마다 같은 꼴(ims_id · 이름 · 코드 · 활성) · payment_method 의 ims_code = QBO PaymentMethod 이름(고정 표 · credit_card 는 null = skipped · opening 은 없음 = 보내지 않는다 786)
create function public.qbo_ims_rows(p_kind text) returns table (ims_id text, ims_name text, ims_code text, ims_active boolean)
  language sql stable security definer set search_path = public, pg_temp
as $$
  select a.id::text, a.name, a.code, a.is_active from public.ref_account a where p_kind = 'account'
  union all select t.id::text, t.name, t.direction, t.is_active from public.ref_tax_rule t where p_kind = 'tax_rule'
  union all select pt.id::text, pt.name, null, pt.is_active from public.ref_payment_term pt where p_kind = 'payment_term'
  union all select m.v, m.v, m.q, true from (values ('cheque', 'Cheque'), ('debit_card', 'Debit'), ('e_transfer', 'E-Transfer'), ('wire', 'Wire'), ('cash', 'Cash'), ('shopify', 'Shopify'), ('direct_deposit', 'EFT (ACH)'), ('credit_card', null)) m(v, q) where p_kind = 'payment_method'
  union all select c.id::text, c.name, null, c.is_active from public.customer c where p_kind = 'customer'
  union all select s.id::text, s.name, null, s.is_active from public.supplier s where p_kind = 'supplier'
  union all select p.id::text, p.name, p.sku, p.is_active from public.product p where p_kind = 'product'
  union all select v, v, null, true from unnest(array['freight', 'discount', 'surcharge', 'freight_discount']) v where p_kind = 'charge'
  union all select r.id::text, r.name, null, r.is_active from public.ref_service r where p_kind = 'service'
$$;

-- ═══ C) 받기 창구 셋 — EF qbo pull(1b)이 사용자 JWT 로 부른다(admin) · realm 은 연결된 회사와 같아야 한다 ═══
create function public.qbo_pull_begin(p_realm text, p_type text, p_restart boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_s public.qbo_pull_state%rowtype; v_resumed boolean := false;
begin
  if p_realm is distinct from public.qbo_realm_of() then raise exception 'QuickBooks company % is not the connected company — nothing was changed', p_realm; end if;
  if p_type is null or p_type not in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item') then raise exception 'type must be one of Account, TaxCode, Term, PaymentMethod, Customer, Vendor, Item (got %)', p_type; end if;
  insert into public.qbo_pull_state (realm_id, qbo_type, started_by) values (p_realm, p_type, v_staff)
  on conflict (realm_id, qbo_type) do update set started_at = now(), started_by = excluded.started_by, next_start = 1, received = 0, pages = 0, finished_at = null, gone = null, updated_at = now()
    where public.qbo_pull_state.finished_at is not null or p_restart
  returning * into v_s;
  if v_s.realm_id is null then                                                                             -- 끝나지 않은 run 이 있고 restart 아님 → 이어 받기
    select * into v_s from public.qbo_pull_state s where s.realm_id = p_realm and s.qbo_type = p_type; v_resumed := true;
  end if;
  return jsonb_build_object('realm_id', v_s.realm_id, 'qbo_type', v_s.qbo_type, 'started_at', v_s.started_at, 'next_start', v_s.next_start, 'received', v_s.received, 'pages', v_s.pages, 'resumed', v_resumed);
end;
$$;
comment on function public.qbo_pull_begin(text, text, boolean) is 'qbo-sync-1a: 받기 run 시작(admin) — 끝난 run 뒤거나 p_restart 면 새 run(started_at · next_start 1) · 끝나지 않은 run 이 있으면 그대로 돌려준다(resumed true · next_start 부터 이어서) · 돌려주는 것 = 상태 한 줄';

create function public.qbo_entity_upsert(p_realm text, p_type text, p_rows jsonb, p_next_start int default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_s public.qbo_pull_state%rowtype; v_n int;
begin
  if p_realm is distinct from public.qbo_realm_of() then raise exception 'QuickBooks company % is not the connected company — nothing was changed', p_realm; end if;
  select * into v_s from public.qbo_pull_state s where s.realm_id = p_realm and s.qbo_type = p_type;
  if v_s.realm_id is null or v_s.finished_at is not null then raise exception 'No pull in progress for % — call qbo_pull_begin first', p_type; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'rows must be a JSON array of QuickBooks % rows', p_type; end if;
  if exists (select 1 from jsonb_array_elements(p_rows) r where nullif(btrim(r->>'Id'), '') is null or nullif(btrim(coalesce(r->>'Name', r->>'DisplayName')), '') is null) then
    raise exception 'Every % row needs Id and Name (or DisplayName) — nothing was saved', p_type;
  end if;
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, parent_id, fully_qualified_name, active, sync_token, fetched_at, gone_at)
  select p_realm, p_type, btrim(r->>'Id'), btrim(coalesce(r->>'Name', r->>'DisplayName')), nullif(btrim(r->>'Sku'), ''), nullif(btrim(r->'ParentRef'->>'value'), ''), r->>'FullyQualifiedName',
         coalesce((r->>'Active')::boolean, true), r->>'SyncToken', now(), null
  from jsonb_array_elements(p_rows) r
  on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = excluded.sku, parent_id = excluded.parent_id, fully_qualified_name = excluded.fully_qualified_name,
    active = excluded.active, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null;
  get diagnostics v_n = row_count;
  update public.qbo_pull_state s set received = s.received + v_n, pages = s.pages + 1, next_start = coalesce(p_next_start, s.next_start), updated_at = now()
    where s.realm_id = p_realm and s.qbo_type = p_type returning * into v_s;
  return jsonb_build_object('qbo_type', p_type, 'received_now', v_n, 'received', v_s.received, 'pages', v_s.pages, 'next_start', v_s.next_start);
end;
$$;
comment on function public.qbo_entity_upsert(text, text, jsonb, int) is 'qbo-sync-1a: 받은 한 쪽을 qbo_entity 에 넣는다(admin · 진행 중인 run 필수) — QBO 원래 꼴(Id · Name|DisplayName · Sku · ParentRef.value · FullyQualifiedName · Active · SyncToken) 그대로 · 있으면 덮고 fetched_at = now() · gone_at 풀기 · 그 밖 칸은 버린다(933) · 돌려주는 것 = received_now · received · pages · next_start';

create function public.qbo_pull_finish(p_realm text, p_type text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_s public.qbo_pull_state%rowtype; v_gone int;
begin
  if p_realm is distinct from public.qbo_realm_of() then raise exception 'QuickBooks company % is not the connected company — nothing was changed', p_realm; end if;
  select * into v_s from public.qbo_pull_state s where s.realm_id = p_realm and s.qbo_type = p_type;
  if v_s.realm_id is null or v_s.finished_at is not null then raise exception 'No pull in progress for % — call qbo_pull_begin first', p_type; end if;
  update public.qbo_entity e set gone_at = now() where e.realm_id = p_realm and e.qbo_type = p_type and e.gone_at is null and e.fetched_at < v_s.started_at;   -- 이번 run 에 안 온 줄 · WHERE 있음
  get diagnostics v_gone = row_count;
  update public.qbo_pull_state s set finished_at = now(), gone = v_gone, updated_at = now() where s.realm_id = p_realm and s.qbo_type = p_type returning * into v_s;
  return jsonb_build_object('qbo_type', p_type, 'received', v_s.received, 'pages', v_s.pages, 'gone', v_gone, 'finished_at', v_s.finished_at);
end;
$$;
comment on function public.qbo_pull_finish(text, text) is 'qbo-sync-1a: run 완주(admin) — 이번 run 의 started_at 보다 먼저 받아 둔 줄(= 이번에 안 온 줄)에 gone_at · finished_at 기록 · 그 뒤 그 종류 자동 짝이 열린다';

-- ═══ D) 자동 짝 — 활성 IMS 행 · 짝 없는 것만 · 그 종류 pull 완주 전이면 거부 · 결과 linked · absent · ambiguous · skipped ═══
create function public.qbo_match_auto(p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp set client_min_messages = warning   -- drop table if exists 의 NOTICE 를 끈다
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_by text; v_st public.qbo_pull_state%rowtype; v_linked int; v_res jsonb;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  if p_kind in ('charge', 'service') then raise exception 'No automatic rule for % — link it by hand with qbo_link_set', p_kind; end if;
  select * into v_st from public.qbo_pull_state s where s.realm_id = v_realm and s.qbo_type = v_type;
  if v_st.finished_at is null then raise exception 'The QuickBooks % list has not been pulled completely — run the pull first', v_type; end if;
  v_by := case p_kind when 'account' then 'auto_code' when 'payment_method' then 'auto_map' when 'product' then 'auto_sku' else 'auto_name' end;
  drop table if exists t_ims, t_ent, t_cand, t_pick;
  create temp table t_ims on commit drop as
    select r.ims_id, r.ims_name, lower(btrim(left(r.ims_name, 100))) as nm,
      case p_kind when 'account' then (regexp_match(r.ims_code, '^_([0-9]+)_$'))[1]
                  when 'tax_rule' then lower(btrim(regexp_replace(r.ims_name, '\s*\((Sale|Purchase)\)\s*$', '')))
                  when 'payment_term' then regexp_replace(lower(r.ims_name), '\s', '', 'g')
                  when 'payment_method' then lower(r.ims_code)
                  when 'product' then lower(btrim(r.ims_code))
                  else lower(btrim(r.ims_name)) end as k
    from public.qbo_ims_rows(p_kind) r
    where r.ims_active and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id);
  create temp table t_ent on commit drop as
    select e.qbo_id, e.name, e.active, lower(btrim(e.name)) as nm,
      case p_kind when 'account' then e.qbo_id when 'payment_term' then regexp_replace(lower(e.name), '\s', '', 'g') when 'product' then lower(btrim(e.sku)) else lower(btrim(e.name)) end as k
    from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.gone_at is null;
  create temp table t_cand on commit drop as
    select i.ims_id, e.qbo_id, e.name as qbo_name, e.active, (p_kind = 'product' and e.nm = i.nm) as name_hit from t_ims i join t_ent e on e.k = i.k where i.k is not null;
  create temp table t_pick on commit drop as
    select x.*, case when x.n_act = 1 then x.id_act when x.n_act > 1 and x.n_name = 1 then x.id_name end as qbo_id,
                case when x.n_act = 1 then x.nm_act when x.n_act > 1 and x.n_name = 1 then x.nm_name end as qbo_name,
                case when x.n_act = 1 then v_by when x.n_act > 1 and x.n_name = 1 then v_by || '_name' end as by,
                case when x.n_act = 1 or (x.n_act > 1 and x.n_name = 1) then 'linked' when x.k is null then 'skipped' when x.n_all > 0 then 'ambiguous' else 'absent' end as state
    from (select i.ims_id, i.ims_name, i.k, count(c.qbo_id) as n_all, count(c.qbo_id) filter (where c.active) as n_act, count(c.qbo_id) filter (where c.active and c.name_hit) as n_name,
                 (array_agg(c.qbo_id) filter (where c.active))[1] as id_act, (array_agg(c.qbo_name) filter (where c.active))[1] as nm_act,
                 (array_agg(c.qbo_id) filter (where c.active and c.name_hit))[1] as id_name, (array_agg(c.qbo_name) filter (where c.active and c.name_hit))[1] as nm_name,
                 string_agg(c.qbo_id || ' ' || c.qbo_name || case when c.active then '' else ' (inactive)' end, ' | ' order by c.active desc, c.qbo_id) as candidates
          from t_ims i left join t_cand c on c.ims_id = i.ims_id group by i.ims_id, i.ims_name, i.k) x;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  select v_realm, p_kind, p.ims_id, v_type, p.qbo_id, p.by, p.qbo_name, v_staff from t_pick p where p.state = 'linked'
  on conflict (realm_id, qbo_type, qbo_id) where ims_kind <> 'tax_rule' do nothing;                      -- QBO 쪽이 이미 다른 IMS 행의 것이면 못 넣는다 → ambiguous
  get diagnostics v_linked = row_count;
  update t_pick p set state = 'ambiguous', candidates = coalesce(p.candidates, '') || ' (QuickBooks id already linked)'
    where p.state = 'linked' and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = p.ims_id);
  select jsonb_build_object('kind', p_kind, 'qbo_type', v_type, 'realm_id', v_realm, 'considered', count(*), 'linked', v_linked,
           'absent', count(*) filter (where p.state = 'absent'), 'ambiguous', count(*) filter (where p.state = 'ambiguous'), 'skipped', count(*) filter (where p.state = 'skipped'),
           'examples', jsonb_build_object(
             'ambiguous', (select coalesce(jsonb_agg(jsonb_build_object('ims_id', a.ims_id, 'ims_name', a.ims_name, 'candidates', a.candidates) order by a.ims_name), '[]'::jsonb) from (select * from t_pick where state = 'ambiguous' order by ims_name limit 20) a),
             'absent',    (select coalesce(jsonb_agg(b.ims_name order by b.ims_name), '[]'::jsonb) from (select ims_name from t_pick where state = 'absent' order by ims_name limit 20) b),
             'skipped',   (select coalesce(jsonb_agg(s.ims_name order by s.ims_name), '[]'::jsonb) from t_pick s where s.state = 'skipped')))
  into v_res from t_pick p;
  return v_res;
end;
$$;
comment on function public.qbo_match_auto(text) is 'qbo-sync-1a: 자동 짝(admin · 활성 IMS 행 · 짝 없는 것만 · 그 종류 pull 완주 필수) — account code _N_ → Id N(auto_code) · tax_rule 꼬리 뗀 이름(auto_name · 활성 쪽) · payment_term 공백 뺀 이름 · payment_method 고정 표(auto_map · credit_card skipped) · customer · supplier lower(btrim(name)) · product Sku(auto_sku) → 활성 둘이면 이름(auto_sku_name) · charge · service 는 거부 · 돌려주는 것 = considered · linked · absent · ambiguous · skipped · examples 20';

-- ═══ E) 사람 짝 둘 ═══
create function public.qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_ims record; v_ent public.qbo_entity%rowtype; v_other record; v_l public.qbo_link%rowtype;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  select * into v_ims from public.qbo_ims_rows(p_kind) r where r.ims_id = p_ims_id;
  if v_ims.ims_id is null then raise exception 'No IMS % with id % — nothing was saved', p_kind, p_ims_id; end if;
  select * into v_ent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.qbo_id = p_qbo_id;
  if v_ent.qbo_id is null then raise exception 'QuickBooks % % is not in the pulled list — pull the list first, or check the id', v_type, p_qbo_id; end if;
  if v_ent.gone_at is not null then raise exception 'QuickBooks % % (%) is no longer in QuickBooks (gone since %) — nothing was saved', v_type, p_qbo_id, v_ent.name, v_ent.gone_at::date; end if;
  if p_kind <> 'tax_rule' then
    select l.ims_kind, l.ims_id into v_other from public.qbo_link l where l.realm_id = v_realm and l.qbo_type = v_type and l.qbo_id = p_qbo_id and l.ims_kind <> 'tax_rule' and not (l.ims_kind = p_kind and l.ims_id = p_ims_id);
    if found then raise exception 'QuickBooks % % (%) is already linked to IMS % % — clear that link first', v_type, p_qbo_id, v_ent.name, v_other.ims_kind, coalesce((select r.ims_name from public.qbo_ims_rows(v_other.ims_kind) r where r.ims_id = v_other.ims_id), v_other.ims_id); end if;
  end if;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  values (v_realm, p_kind, p_ims_id, v_type, p_qbo_id, 'manual', v_ent.name, v_staff)
  on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, matched_by = 'manual', qbo_name_at_match = excluded.qbo_name_at_match, by_staff = excluded.by_staff, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff
  returning * into v_l;
  return to_jsonb(v_l) || jsonb_build_object('ims_name', v_ims.ims_name, 'ims_code', v_ims.ims_code, 'qbo_name', v_ent.name, 'qbo_active', v_ent.active);
end;
$$;
comment on function public.qbo_link_set(text, text, text) is 'qbo-sync-1a: 사람 짝(admin) — IMS 행(qbo_ims_rows) · QBO 행(qbo_entity · gone 아님) 둘 다 있어야 · tax_rule 빼고 QBO Id 는 한 IMS 행만(이미 다른 것의 짝이면 거부 · 먼저 clear) · 있으면 덮는다(matched_by manual) · 돌려주는 것 = 짝 한 줄 + ims_name · qbo_name';

create function public.qbo_link_clear(p_kind text, p_ims_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_n int;
begin
  if public.qbo_type_of(p_kind) is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  delete from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = p_ims_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('kind', p_kind, 'ims_id', p_ims_id, 'deleted', v_n);
end;
$$;
comment on function public.qbo_link_clear(text, text) is 'qbo-sync-1a: 짝 풀기(admin) — (realm, kind, ims_id) 한 줄 delete(WHERE 있음) · 없으면 deleted 0';

-- ═══ F) 읽기 셋 — 화면(Settings → QuickBooks 짝 탭 · 대화 Claude) · admin 만 ═══
create function public.qbo_link_summary() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of();
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
comment on function public.qbo_link_summary() is 'qbo-sync-1a: 종류 9 의 요약(admin) — ims_active · linked · unlinked · qbo_rows · qbo_active · pull 상태(finished_at · in_progress · next_start · received)';

create function public.qbo_link_page(p_kind text, p_filter text default 'unlinked', p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(p_q), '');
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
comment on function public.qbo_link_page(text, text, text, int, int) is 'qbo-sync-1a: 짝 화면 한 쪽(admin) — filter linked(짝 있음) · unlinked(활성 · 짝 없음) · all(활성 ∪ 짝 있음) · q 는 이름 · 코드 ilike 또는 ims_id · limit ≤ 200 · 행 = IMS 행 + 짝 + 지금 QBO 이름 · candidates ≤ 5(product 는 같은 Sku · 그 밖은 같은 이름 또는 앞글자 · 0 이면 absent)';

create function public.qbo_entity_find(p_type text, p_q text default null, p_limit int default 20) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 50); v_q text := nullif(btrim(p_q), '');
begin
  if p_type is null or p_type not in ('Account', 'TaxCode', 'Term', 'PaymentMethod', 'Customer', 'Vendor', 'Item') then raise exception 'type must be one of Account, TaxCode, Term, PaymentMethod, Customer, Vendor, Item (got %)', p_type; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('qbo_id', c.qbo_id, 'name', c.name, 'sku', c.sku, 'active', c.active, 'parent_id', c.parent_id, 'fully_qualified_name', c.fully_qualified_name,
                     'linked_to', (select jsonb_build_object('kind', l.ims_kind, 'ims_id', l.ims_id) from public.qbo_link l where l.realm_id = v_realm and l.qbo_type = p_type and l.qbo_id = c.qbo_id and l.ims_kind <> 'tax_rule' limit 1)) order by c.active desc, c.name)
                   from (select e.* from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = p_type and e.gone_at is null
                           and (v_q is null or e.name ilike '%' || v_q || '%' or e.sku ilike '%' || v_q || '%' or e.qbo_id = v_q) order by e.active desc, e.name limit v_lim) c), '[]'::jsonb);
end;
$$;
comment on function public.qbo_entity_find(text, text, int) is 'qbo-sync-1a: QBO 행 고르기(admin) — 종류 하나 · q 는 이름 · sku ilike 또는 Id · gone 제외 · limit ≤ 50 · linked_to = 이미 짝인 IMS 행(tax_rule 빼고)';

-- ═══ G) grant — 창구 9 는 authenticated(문은 안에서 ims_is_admin) · 속 함수 4 는 grant 0 ═══
revoke all on function public.qbo_sync_gate(), public.qbo_realm_of(), public.qbo_type_of(text), public.qbo_ims_rows(text),
  public.qbo_pull_begin(text, text, boolean), public.qbo_entity_upsert(text, text, jsonb, int), public.qbo_pull_finish(text, text), public.qbo_match_auto(text),
  public.qbo_link_set(text, text, text), public.qbo_link_clear(text, text), public.qbo_link_summary(), public.qbo_link_page(text, text, text, int, int), public.qbo_entity_find(text, text, int)
  from public, anon, authenticated, service_role;
grant execute on function public.qbo_pull_begin(text, text, boolean), public.qbo_entity_upsert(text, text, jsonb, int), public.qbo_pull_finish(text, text), public.qbo_match_auto(text),
  public.qbo_link_set(text, text, text), public.qbo_link_clear(text, text), public.qbo_link_summary(), public.qbo_link_page(text, text, text, int, int), public.qbo_entity_find(text, text, int)
  to authenticated;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(c.relname || '=' || c.relacl::text || '/rls=' || c.relrowsecurity::text, ' ' order by c.relname) into v from pg_class c where c.oid in ('public.qbo_entity'::regclass, 'public.qbo_pull_state'::regclass, 'public.qbo_link'::regclass);
  if v <> 'qbo_entity={postgres=arwdDxtm/postgres}/rls=true qbo_link={postgres=arwdDxtm/postgres}/rls=true qbo_pull_state={postgres=arwdDxtm/postgres}/rls=true' then raise exception 'qbo-sync-1a landing: table acl %', v; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('qbo_entity', 'qbo_pull_state', 'qbo_link')) <> 0 then raise exception 'qbo-sync-1a landing: policies must be 0'; end if;
  select string_agg(distinct confrelid::regclass::text, ' ') into v from pg_constraint where conrelid in ('public.qbo_entity'::regclass, 'public.qbo_pull_state'::regclass, 'public.qbo_link'::regclass) and contype = 'f';
  if v <> 'ims_staff' then raise exception 'qbo-sync-1a landing: FK targets %', v; end if;
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('qbo_sync_gate', 'qbo_realm_of', 'qbo_type_of', 'qbo_ims_rows', 'qbo_pull_begin', 'qbo_entity_upsert', 'qbo_pull_finish', 'qbo_match_auto', 'qbo_link_set', 'qbo_link_clear', 'qbo_link_summary', 'qbo_link_page', 'qbo_entity_find');
  if v <> 'qbo_entity_find={postgres=X/postgres,authenticated=X/postgres} qbo_entity_upsert={postgres=X/postgres,authenticated=X/postgres} qbo_ims_rows={postgres=X/postgres} qbo_link_clear={postgres=X/postgres,authenticated=X/postgres} qbo_link_page={postgres=X/postgres,authenticated=X/postgres} qbo_link_set={postgres=X/postgres,authenticated=X/postgres} qbo_link_summary={postgres=X/postgres,authenticated=X/postgres} qbo_match_auto={postgres=X/postgres,authenticated=X/postgres} qbo_pull_begin={postgres=X/postgres,authenticated=X/postgres} qbo_pull_finish={postgres=X/postgres,authenticated=X/postgres} qbo_realm_of={postgres=X/postgres} qbo_sync_gate={postgres=X/postgres} qbo_type_of={postgres=X/postgres}'
    then raise exception 'qbo-sync-1a landing: function acl %', v; end if;
  raise notice 'qbo-sync-1a landing OK — 표 3 acl+rls · 정책 0 · FK → ims_staff 만 · 창구 9 authenticated · 속 함수 4 grant 0';
end $$;
