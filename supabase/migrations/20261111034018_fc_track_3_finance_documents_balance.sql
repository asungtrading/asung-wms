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
-- fc-track-3 — Freightcom 청구 문서 · 쉽먼트별 「견적 대비 청구 · 추가 요금」 · 계정별 남은 한도 (2026-11-10 밤 토론토 · 지시서 ~/asung/prompts/fc-track-3.md · 판정 1163 ~ 1166 · Claude Code 이견 1 ~ 9 · ⬜1 ~ ⬜8 모두 Caleb 승인 11-10)
--   왜: Freightcom 이 예약 뒤에 요금을 더 붙이기도 하고(1163 · 예 other-charge-1) · Net Terms 한도가 있어 중간중간 결제해야 한다(1164) — IMS 는 읽어서 보여 주기만 한다(1165 · 결제 · reload API 를 부르지 않는다)
--   ① 표 셋 — 돈이 담기므로 처음부터 닫음(1166 · RLS 켬 · 정책 0 · authenticated 권한 0 · 쓰기는 정의자 창구만 · 화면 읽기 창구는 fc-track-4):
--      fc_document(머리 · 열쇠 = Freightcom document id · raw 없음 ⬜1 · payments 는 [{type, amount_cents}] 만) · fc_document_line(줄 · PK (document_id, line_id) 이견 2) · fc_balance(계정 잔액 이력 · 90 일)
--   ② 저장 창구 셋(이견 6 · service_role 만 · doc_is_service):
--      fc_finance_docs_save(account, docs, limit) — 머리 upsert(first_seen_at 지킴 · fetched_at 만 새로) → 「줄을 읽을 문서」 를 돌려준다(고르는 규칙은 fc_finance_lines_due 한 곳)
--      fc_finance_lines_save(account, doc) — 문서 하나의 줄을 갈아 끼움 · payments 추림 · lines_fetched_at · lines_amount_cents(= 그때의 머리 금액 · 이견 7)
--      fc_finance_balance_save(account, method_type, balance) — available_balances 원소가 정확히 1 개이고 수일 때만 저장(이견 5) · 아니면 저장 0 + 경고
--   ③ fc_finance_lines_due(account, limit) — 줄을 읽을 문서(한 곳): 줄을 읽은 적 없음 ∨ 머리 금액이 줄 읽을 때와 다름 · net-terms-invoice 전부 · shipment-order-details 는 number 가 IMS 예약(상태 무관 · 이견 1)의 transaction_number 인 것 중
--      같은 number · 같은 금액의 더 늦은 판이 없는 것만(이견 7 — 같은 금액 재발행의 옛 판은 읽지 않는다)
--   ④ 잇는 열쇠(⬜2) = 줄의 shipment_fc_id = fc_booking.freightcom_shipment_id · 머리 number 는 줄을 읽을 문서를 고르는 데만
--   ⑤ fc_booking_rate(b)(속) — 견적 정본 = 예약 응답의 rate · 없으면(IMS 취소가 response 를 덮은 건 · deferred 475) 고른 견적 줄 fc_quote_rate.raw(이견 4)
--   ⑥ fc_charge_check(booking_id)(속 · service_role) — 판 = 그 쉽먼트 줄이 든 shipment-order-details 중 날짜가 가장 늦은 것 · 같은 날이면 금액 큰 것(이견 3 · 「최근 판 = 전체 재진술」 은 **짐작** — 실물 한 건 17439 → 25675)
--      state 는 세전 합계끼리(오차 100 ¢ · 이견 4): none | unread(머리나 인보이스 줄은 있는데 판의 줄을 아직 못 읽음) | billed | extra | less | cancelled_billed(취소한 예약에 청구 · 이견 1) | unknown(견적 없음 · 통화 다름)
--      extra_lines 는 설명용(UPS 견적에는 surcharge 줄이 없다 — 청구가 fuel 을 쪼개 오면 줄은 달라도 합계가 같으면 billed · UPS 청구 실물은 아직 없다 **짐작**) · invoiced_cents = 묶음 인보이스의 그 쉽먼트 줄 합(어긋나면 warnings invoiced_differs)
--   ⑦ fc_finance_account_summary(account)(속 · service_role · fc-track-4 화면 창구의 재료) — 남은 한도(API 값이 정본) · 한도(inv_config fc_credit_limit_<계정> · 달러 · 설정값) · 사용(= 설정 한도 − 남은 한도 · used_basis 표지 · 이견 5) ·
--      결제할 인보이스(net-terms-invoice · owing > 0 — 실물은 전부 owing 0 이라 이 꼴은 **짐작**) · 청구 전 예약 합계(booked · Freightcom 취소 아님 · 문서 머리도 줄도 없는 예약의 견적 총액)
--   ⑧ fc_finance_gate(account) — 사람 길 finance_poll 의 문(⬜6 · 사용자 JWT): freight_booking ∨ purchasing + 그 계정을 쓰는 창고(ims_can_warehouse)
--   ⑨ 스위치 inv_config fc_finance_poll_enabled(off · Caleb 이 켠다) · fc_finance_doc_batch(25) · 한도 fc_credit_limit_TOR 5000 · fc_credit_limit_EDM 2000(Caleb 11-10 · 달러 · 설정에서 고친다)
--   무접촉: fc_booking · 기존 fc_ 함수 39 개(착지 확인이 수를 본다) · fc_money_cents(못 읽는 값에 던지므로 여기서는 던지지 않는 fc_doc_cents 를 따로 둔다) · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261111034018_fc_track_3_finance_documents_balance.sql && supabase migration repair --status applied 20261111034018 --db-url "$(cat ~/.asung-testdb-url)" --yes
--   시험(Claude Code · rollback · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111034018_fc_track_3_finance_documents_balance.sql -f supabase/tests/fc_track_3_check.sql

-- ═══ 1) 스위치 · 회차 크기 · 한도 ═══
insert into public.inv_config (key, value, note) values
  ('fc_finance_poll_enabled', 'off', 'fc-track-3: Freightcom 청구 문서 · 잔액을 자동으로 읽는 cron ims-fc-finance-poll(EF freightcom finance_sweep · GET 만 · 결제 없음)의 스위치 on | off — 켜는 것은 Caleb · off 면 cron SQL 의 where 가 호출 0 · EF 도 다시 본다'),
  ('fc_finance_doc_batch', '25', 'fc-track-3: 청구 문서 읽기 한 회차에 줄을 읽을 문서 수 상한(1 ~ 100 · 문서 하나 GET 하나 · 계정 둘 합쳐서 · 회차 90 s 상한) — cron 몸이 읽어 EF 에 limit 으로 넘긴다'),
  ('fc_credit_limit_TOR', '5000', 'fc-track-3 판정 1164: Freightcom 계정 TOR 의 Net Terms 한도(달러 · Caleb 이 Freightcom 화면을 보고 고친다) — 「사용 = 이 한도 − 남은 한도」 의 기준일 뿐이고 남은 한도는 Freightcom 이 주는 값이 정본'),
  ('fc_credit_limit_EDM', '2000', 'fc-track-3 판정 1164: Freightcom 계정 EDM 의 Net Terms 한도(달러 · Caleb 이 Freightcom 화면을 보고 고친다) — 「사용 = 이 한도 − 남은 한도」 의 기준일 뿐이고 남은 한도는 Freightcom 이 주는 값이 정본')
on conflict (key) do nothing;

-- ═══ 2) 표 셋 — 처음부터 닫음(1166) ═══
create table public.fc_document (
  id                 text        primary key,
  account            text        not null,
  type               text        not null,
  number             text,
  doc_date           date,
  due_date           date,
  amount_cents       bigint      not null,
  owing_cents        bigint,
  currency           text,
  payments           jsonb,
  first_seen_at      timestamptz not null default now(),
  fetched_at         timestamptz not null default clock_timestamp(),
  lines_fetched_at   timestamptz,
  lines_amount_cents bigint
);
create index fc_document_number_idx on public.fc_document (account, type, number);
create index fc_document_date_idx   on public.fc_document (account, doc_date desc);
alter table public.fc_document enable row level security;
revoke all on table public.fc_document from public, anon, authenticated, service_role;
grant select on table public.fc_document to service_role;
comment on table public.fc_document is 'fc-track-3: Freightcom GET /finance/documents 의 문서 머리 한 행(열쇠 = Freightcom document id · fc_finance_docs_save 만 쓴다) — type 원문 lower(shipment-order-details | net-terms-invoice · CHECK 없음) · number(shipment-order-details 는 쉽먼트의 transaction_number · 같은 number 가 날짜를 달리해 여러 번 온다) · 센트 정수 · first_seen_at 은 지킨다 · payments = [{type, amount_cents}] 만(카드 칸 · 주소 없음) · lines_amount_cents = 줄을 읽을 때의 머리 금액(다르면 다시 읽는다) · RLS 켬 · 정책 없음(읽기 창구는 fc-track-4)';

create table public.fc_document_line (
  document_id    text   not null references public.fc_document (id),
  line_id        text   not null,
  type           text   not null,
  sub_type       text,
  shipment_fc_id text,
  payment_id     text,
  amount_cents   bigint not null,
  currency       text,
  message        text,
  primary key (document_id, line_id)
);
create index fc_document_line_shipment_idx on public.fc_document_line (shipment_fc_id);
alter table public.fc_document_line enable row level security;
revoke all on table public.fc_document_line from public, anon, authenticated, service_role;
grant select on table public.fc_document_line to service_role;
comment on table public.fc_document_line is 'fc-track-3: Freightcom GET /finance/document/{id} 의 line_items 한 줄(fc_finance_lines_save 만 쓴다 · 문서를 다시 읽으면 그 문서의 줄을 갈아 끼운다) — PK (document_id, line_id)(같은 line id 가 여러 문서에 나올 수 있다 **짐작** · 이견 2) · type base | surcharge | tax · sub_type 원문 lower(base 는 null) · shipment_fc_id = Freightcom shipment id(예약과 잇는 열쇠 = fc_booking.freightcom_shipment_id) · message = btrim 값 · RLS 켬 · 정책 없음';

create table public.fc_balance (
  id              bigint generated always as identity primary key,
  account         text        not null,
  method_type     text,
  available_cents bigint      not null,
  currency        text,
  checked_at      timestamptz not null default clock_timestamp()
);
create index fc_balance_account_idx on public.fc_balance (account, checked_at desc);
alter table public.fc_balance enable row level security;
revoke all on table public.fc_balance from public, anon, authenticated, service_role;
grant select on table public.fc_balance to service_role;
comment on table public.fc_balance is 'fc-track-3: Freightcom GET /finance/payment-method/{id}/available-balances 를 읽은 한 번(fc_finance_balance_save 만 쓴다 · 계정마다 가장 늦은 행이 지금 값 · 90 일 지난 행은 저장할 때 지운다) — available_cents = 남은 한도(Net Terms · CAD · USD 공용이라 currency 는 빈 채로 온다) · RLS 켬 · 정책 없음';

-- ═══ 3) 속 함수 — 파서 둘 · 견적 ═══
create function public.fc_doc_cents(p jsonb) returns bigint
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case when p is not null and jsonb_typeof(p) = 'object' and btrim(coalesce(p->>'value', '')) ~ '^-?\d{1,15}$' then btrim(p->>'value')::bigint end;
$$;
revoke all on function public.fc_doc_cents(jsonb) from public, anon, authenticated, service_role;
comment on function public.fc_doc_cents(jsonb) is 'fc-track-3(속): Freightcom 금액 {value:"16918", currency} → 센트 정수 · 정수 글자가 아니면 null(던지지 않는다 — fc_money_cents 는 던진다)';

create function public.fc_doc_date(p jsonb) returns date
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
begin
  if p is null or jsonb_typeof(p) is distinct from 'object' or coalesce(p->>'year', '') !~ '^\d{4}$' or coalesce(p->>'month', '') !~ '^\d{1,2}$' or coalesce(p->>'day', '') !~ '^\d{1,2}$' then return null; end if;
  begin
    return make_date((p->>'year')::int, (p->>'month')::int, (p->>'day')::int);
  exception when others then
    return null;
  end;
end;
$$;
revoke all on function public.fc_doc_date(jsonb) from public, anon, authenticated, service_role;
comment on function public.fc_doc_date(jsonb) is 'fc-track-3(속): Freightcom 날짜 {year, month, day} → date · 꼴이 아니거나 없는 날이면 null';

create function public.fc_booking_rate(b public.fc_booking) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  with r as (
    select x.rate, x.src
      from (select b.response#>'{shipment,rate}' as rate, 'booking'::text as src, 1 as o
            union all
            select q.raw, 'quote', 2 from public.fc_quote_rate q where q.id = b.rate_id) x
     where x.rate is not null and jsonb_typeof(x.rate) = 'object' and public.fc_doc_cents(x.rate->'base') is not null
     order by x.o
     limit 1
  )
  select jsonb_build_object(
           'source', r.src,
           'currency', nullif(upper(btrim(coalesce(r.rate#>>'{base,currency}', ''))), ''),
           'base', public.fc_doc_cents(r.rate->'base'),
           'surcharges', coalesce((select jsonb_agg(jsonb_build_object('type', coalesce(nullif(lower(btrim(s->>'type')), ''), 'surcharge'), 'cents', coalesce(public.fc_doc_cents(s->'amount'), 0)))
                                     from jsonb_array_elements(case when jsonb_typeof(r.rate->'surcharges') = 'array' then r.rate->'surcharges' else '[]'::jsonb end) s where jsonb_typeof(s) = 'object'), '[]'::jsonb),
           'taxes', coalesce((select jsonb_agg(jsonb_build_object('type', coalesce(nullif(lower(btrim(s->>'type')), ''), 'tax'), 'cents', coalesce(public.fc_doc_cents(s->'amount'), 0)))
                                from jsonb_array_elements(case when jsonb_typeof(r.rate->'taxes') = 'array' then r.rate->'taxes' else '[]'::jsonb end) s where jsonb_typeof(s) = 'object'), '[]'::jsonb),
           'total', public.fc_doc_cents(r.rate->'total'))
    from r;
$$;
revoke all on function public.fc_booking_rate(public.fc_booking) from public, anon, authenticated, service_role;
comment on function public.fc_booking_rate(public.fc_booking) is 'fc-track-3 ⑤(속 · 한 곳): 예약 금액(견적) — 예약 응답 response.shipment.rate 가 정본 · 없으면(IMS 취소가 response 를 덮은 건 · deferred 475) 고른 견적 줄 fc_quote_rate.raw → {source booking | quote, currency, base, surcharges[{type, cents}], taxes[{type, cents}], total} · 둘 다 없으면 null';

-- ═══ 4) 줄을 읽을 문서 — 한 곳 ═══
create function public.fc_finance_lines_due(p_account text, p_limit int default 25)
  returns table (document_id text, type text, number text, doc_date date, need_total bigint)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with c as (
    select d.id, d.type, d.number, d.doc_date
      from public.fc_document d
     where d.account = upper(btrim(p_account))
       and (d.lines_fetched_at is null or d.lines_amount_cents is distinct from d.amount_cents)
       and (d.type = 'net-terms-invoice'
         or (d.type = 'shipment-order-details'
             and exists (select 1 from public.fc_booking b where b.account = d.account and b.transaction_number = d.number)
             and not exists (select 1 from public.fc_document n
                              where n.account = d.account and n.type = d.type and n.number = d.number and n.amount_cents = d.amount_cents
                                and (coalesce(n.doc_date, '0001-01-01'::date), n.id) > (coalesce(d.doc_date, '0001-01-01'::date), d.id))))
  )
  select c.id, c.type, c.number, c.doc_date, count(*) over ()
    from c
   order by c.doc_date desc nulls last, c.id
   limit (case when p_limit between 1 and 100 then p_limit else 25 end);
$$;
revoke all on function public.fc_finance_lines_due(text, int) from public, anon, authenticated;
grant execute on function public.fc_finance_lines_due(text, int) to service_role;
comment on function public.fc_finance_lines_due(text, int) is 'fc-track-3 ③: 줄을 읽을 Freightcom 문서(한 곳 · service_role 만 · 읽기) — 줄을 읽은 적 없음 ∨ 머리 금액이 줄 읽을 때(lines_amount_cents)와 다름 · net-terms-invoice 전부 · shipment-order-details 는 number 가 IMS 예약(상태 무관)의 transaction_number 이고 같은 number · 같은 금액의 더 늦은 판이 없는 것만 · 정렬 doc_date 늦은 것부터 · p_limit 1 ~ 100(밖이면 25) · need_total = 상한을 걸기 전 수';

-- ═══ 5) 저장 창구 셋 ═══
create function public.fc_finance_docs_save(p_account text, p_docs jsonb, p_limit int default 25) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_acc   text := upper(btrim(coalesce(p_account, '')));
  v_arr   jsonb;
  v_recv  int;
  v_ok    int;
  v_saved int;
  v_added int;
  v_need  jsonb;
  v_total bigint;
begin
  if not public.doc_is_service() then raise exception 'fc_finance_docs_save is for the freight service only — nothing was saved'; end if;
  if v_acc !~ '^[A-Z0-9]{2,10}$' then raise exception 'p_account must be 2–10 upper-case letters or digits — nothing was saved'; end if;
  v_arr := case when jsonb_typeof(p_docs) = 'array' then p_docs when jsonb_typeof(p_docs) = 'object' and jsonb_typeof(p_docs->'documents') = 'array' then p_docs->'documents' end;
  if v_arr is null then raise exception 'p_docs must be a JSON list or {documents:[…]} — nothing was saved'; end if;
  v_recv := jsonb_array_length(v_arr);
  with e as (
    select distinct on (q.id) q.*
      from (select nullif(btrim(d->>'id'), '') as id,
                   coalesce(left(nullif(lower(btrim(d->>'type')), ''), 60), 'unknown') as type,
                   left(nullif(btrim(d->>'number'), ''), 60) as number,
                   public.fc_doc_date(d->'date') as doc_date, public.fc_doc_date(d->'due_date') as due_date,
                   public.fc_doc_cents(d->'amount') as amount_cents, public.fc_doc_cents(d->'owing') as owing_cents,
                   nullif(upper(btrim(coalesce(d#>>'{amount,currency}', ''))), '') as currency, x.ord
              from jsonb_array_elements(v_arr) with ordinality x(d, ord)
             where jsonb_typeof(d) = 'object') q
     where q.id is not null and q.amount_cents is not null
     order by q.id, q.ord desc
  ), up as (
    insert into public.fc_document as t (id, account, type, number, doc_date, due_date, amount_cents, owing_cents, currency)
    select e.id, v_acc, e.type, e.number, e.doc_date, e.due_date, e.amount_cents, e.owing_cents, e.currency from e
    on conflict (id) do update
       set type = excluded.type, number = excluded.number, doc_date = excluded.doc_date, due_date = excluded.due_date,
           amount_cents = excluded.amount_cents, owing_cents = excluded.owing_cents, currency = excluded.currency, fetched_at = clock_timestamp()
     where t.account = excluded.account                                                  -- 다른 계정의 같은 id 는 덮지 않는다(센다)
    returning (t.xmax = 0) as is_new
  )
  select (select count(*) from e), count(*), count(*) filter (where up.is_new) into v_ok, v_saved, v_added from up;
  select coalesce(jsonb_agg(d.document_id order by d.doc_date desc nulls last, d.document_id), '[]'::jsonb), coalesce(max(d.need_total), 0) into v_need, v_total from public.fc_finance_lines_due(v_acc, p_limit) d;
  return jsonb_build_object('account', v_acc, 'received', v_recv, 'saved', v_saved, 'added', v_added, 'skipped', v_recv - v_ok, 'other_account', v_ok - v_saved, 'need_lines', v_need, 'need_total', v_total);
end;
$$;
revoke all on function public.fc_finance_docs_save(text, jsonb, int) from public, anon, authenticated;
grant execute on function public.fc_finance_docs_save(text, jsonb, int) to service_role;
comment on function public.fc_finance_docs_save(text, jsonb, int) is 'fc-track-3 ② · 판정 1163 · 1164: GET /finance/documents 의 머리 저장(EF service_role 만) — id 로 upsert(금액 · owing · 날짜는 덮고 first_seen_at 은 지킨다 · fetched_at 만 새로) · id 나 금액을 못 읽는 원소 · 겹친 id 는 skipped · 다른 계정에 이미 있는 id 는 other_account(덮지 않는다) · 반환 need_lines = 줄을 읽을 문서 id(fc_finance_lines_due · p_limit) · need_total · 반환에 금액 없음';

create function public.fc_finance_lines_save(p_account text, p_doc jsonb) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_acc   text := upper(btrim(coalesce(p_account, '')));
  v_d     jsonb;
  v_id    text;
  v_doc   public.fc_document%rowtype;
  v_recv  int;
  v_saved int;
  v_pay   jsonb;
  v_amt   bigint;
  v_sum   bigint;
  v_ships int;
  v_link  int;
  v_warn  text[] := '{}';
begin
  if not public.doc_is_service() then raise exception 'fc_finance_lines_save is for the freight service only — nothing was saved'; end if;
  v_d := case when jsonb_typeof(p_doc) = 'object' and jsonb_typeof(p_doc->'document') = 'object' then p_doc->'document' else p_doc end;
  if v_d is null or jsonb_typeof(v_d) <> 'object' then raise exception 'p_doc must be a JSON object — nothing was saved'; end if;
  v_id := nullif(btrim(v_d->>'id'), '');
  if v_id is null then raise exception 'The document answer has no id — nothing was saved'; end if;
  select * into v_doc from public.fc_document d where d.id = v_id for update;
  if not found then raise exception 'Document % is not in the list yet — save the document list first — nothing was saved', v_id; end if;
  if v_doc.account <> v_acc then raise exception 'Document % belongs to account % — not % — nothing was saved', v_id, v_doc.account, v_acc; end if;
  if jsonb_typeof(v_d->'line_items') is distinct from 'array' then raise exception 'The document answer has no line_items list — nothing was saved'; end if;
  v_recv := jsonb_array_length(v_d->'line_items');
  delete from public.fc_document_line l where l.document_id = v_id;
  insert into public.fc_document_line (document_id, line_id, type, sub_type, shipment_fc_id, payment_id, amount_cents, currency, message)
  select v_id, nullif(btrim(l->>'id'), ''), coalesce(left(nullif(lower(btrim(l->>'type')), ''), 60), 'unknown'), left(nullif(lower(btrim(l->>'sub_type')), ''), 80),
         nullif(btrim(l->>'shipment_id'), ''), nullif(btrim(l->>'payment_id'), ''), public.fc_doc_cents(l->'amount'),
         nullif(upper(btrim(coalesce(l#>>'{amount,currency}', ''))), ''), left(nullif(btrim(l->>'message'), ''), 500)
    from jsonb_array_elements(v_d->'line_items') l
   where jsonb_typeof(l) = 'object' and nullif(btrim(l->>'id'), '') is not null and public.fc_doc_cents(l->'amount') is not null
  on conflict (document_id, line_id) do nothing;
  get diagnostics v_saved = row_count;
  if v_saved < v_recv then v_warn := array_append(v_warn, format('lines_skipped — %s of %s lines had no id, no readable amount or a repeated id and were not saved', v_recv - v_saved, v_recv)); end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', left(coalesce(nullif(lower(btrim(p->>'type')), ''), 'unknown'), 60), 'amount_cents', public.fc_doc_cents(p->'amount')) order by x.ord), '[]'::jsonb) into v_pay
    from jsonb_array_elements(case when jsonb_typeof(v_d->'payments') = 'array' then v_d->'payments' else '[]'::jsonb end) with ordinality x(p, ord)
   where jsonb_typeof(p) = 'object';
  v_amt := public.fc_doc_cents(v_d->'amount');
  if v_amt is not null and v_amt <> v_doc.amount_cents then v_warn := array_append(v_warn, 'amount_differs — the document and the list give different amounts · the list value was kept'); end if;
  select coalesce(sum(l.amount_cents), 0), count(distinct l.shipment_fc_id) into v_sum, v_ships from public.fc_document_line l where l.document_id = v_id;
  if v_sum <> coalesce(v_amt, v_doc.amount_cents) then v_warn := array_append(v_warn, 'lines_sum_differs — the lines do not add up to the document amount'); end if;
  select count(distinct b.id) into v_link from public.fc_document_line l join public.fc_booking b on b.freightcom_shipment_id = l.shipment_fc_id and b.account = v_acc where l.document_id = v_id;
  update public.fc_document set payments = v_pay, lines_fetched_at = clock_timestamp(), lines_amount_cents = v_doc.amount_cents where id = v_id;   -- 읽은 표지 = 그때의 머리 금액(목록이 금액을 바꾸면 다시 읽는다 · 이견 7)
  return jsonb_build_object('document_id', v_id, 'type', v_doc.type, 'number', v_doc.number, 'lines_received', v_recv, 'lines_saved', v_saved, 'lines_skipped', v_recv - v_saved,
                            'shipments', v_ships, 'linked_bookings', v_link, 'sum_matches', v_sum = coalesce(v_amt, v_doc.amount_cents), 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.fc_finance_lines_save(text, jsonb) from public, anon, authenticated;
grant execute on function public.fc_finance_lines_save(text, jsonb) to service_role;
comment on function public.fc_finance_lines_save(text, jsonb) is 'fc-track-3 ②: GET /finance/document/{id} 의 줄 저장(EF service_role 만 · 문서가 목록에 먼저 있어야 한다 · 계정이 다르면 거부) — 그 문서의 줄을 갈아 끼움(id · 금액 없는 줄은 skipped) · payments 는 [{type, amount_cents}] 만 · lines_fetched_at · lines_amount_cents(= 그때의 머리 금액) · 머리 금액 · owing 은 목록 값을 지킨다(다르면 warnings) · 반환에 금액 없음';

create function public.fc_finance_balance_save(p_account text, p_method_type text, p_balance jsonb) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_acc  text := upper(btrim(coalesce(p_account, '')));
  v_arr  jsonb;
  v_c    bigint;
  v_at   timestamptz;
begin
  if not public.doc_is_service() then raise exception 'fc_finance_balance_save is for the freight service only — nothing was saved'; end if;
  if v_acc !~ '^[A-Z0-9]{2,10}$' then raise exception 'p_account must be 2–10 upper-case letters or digits — nothing was saved'; end if;
  v_arr := case when jsonb_typeof(p_balance) = 'array' then p_balance when jsonb_typeof(p_balance) = 'object' and jsonb_typeof(p_balance->'available_balances') = 'array' then p_balance->'available_balances' end;
  if v_arr is null then return jsonb_build_object('account', v_acc, 'saved', false, 'warning', 'balance_shape — the answer has no available_balances list · nothing was saved'); end if;
  if jsonb_array_length(v_arr) <> 1 then return jsonb_build_object('account', v_acc, 'saved', false, 'warning', format('balance_count — the answer has %s balances (expected exactly 1) · nothing was saved', jsonb_array_length(v_arr))); end if;
  v_c := public.fc_doc_cents(v_arr->0);
  if v_c is null then return jsonb_build_object('account', v_acc, 'saved', false, 'warning', 'balance_value — the balance is not a whole number of cents · nothing was saved'); end if;
  insert into public.fc_balance (account, method_type, available_cents, currency)
  values (v_acc, left(nullif(lower(btrim(p_method_type)), ''), 40), v_c, nullif(upper(btrim(coalesce(v_arr#>>'{0,currency}', ''))), ''))
  returning checked_at into v_at;
  delete from public.fc_balance f where f.account = v_acc and f.checked_at < now() - interval '90 days';
  return jsonb_build_object('account', v_acc, 'saved', true, 'checked_at', v_at);
end;
$$;
revoke all on function public.fc_finance_balance_save(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fc_finance_balance_save(text, text, jsonb) to service_role;
comment on function public.fc_finance_balance_save(text, text, jsonb) is 'fc-track-3 ② · 판정 1164: 남은 한도 저장(EF service_role 만) — {available_balances:[{value, currency}]} 의 원소가 정확히 1 개이고 정수 센트일 때만 한 행 더함 · 아니면 저장 0 + warning(이견 5) · 그 계정의 90 일 지난 행은 지운다 · 반환에 금액 없음';

-- ═══ 6) 판정 — 견적 대비 청구(1163) ═══
create function public.fc_charge_check(p_booking_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  c_tol   constant bigint := 100;
  v_b     public.fc_booking%rowtype;
  v_fc    text;
  v_tn    text;
  v_rate  jsonb;
  v_doc   public.fc_document%rowtype;
  v_head  public.fc_document%rowtype;
  v_heads int := 0;
  v_last  date;
  v_bp    bigint;
  v_bt    bigint;
  v_btot  bigint;
  v_lp    bigint;
  v_lt    bigint;
  v_extra bigint;
  v_lines jsonb := '[]'::jsonb;
  v_inv   bigint;
  v_invn  int := 0;
  v_curx  boolean := false;
  v_state text;
  v_warn  text[] := '{}';
begin
  select * into v_b from public.fc_booking b where b.id = p_booking_id;
  if not found then raise exception 'Booking % not found', p_booking_id; end if;
  v_fc := nullif(btrim(v_b.freightcom_shipment_id), '');
  v_tn := nullif(btrim(v_b.transaction_number), '');
  v_rate := public.fc_booking_rate(v_b);
  if v_rate is not null then
    v_bp := (v_rate->>'base')::bigint + coalesce((select sum((s->>'cents')::bigint) from jsonb_array_elements(v_rate->'surcharges') s), 0);
    v_bt := coalesce((select sum((s->>'cents')::bigint) from jsonb_array_elements(v_rate->'taxes') s), 0);
    v_btot := coalesce((v_rate->>'total')::bigint, v_bp + v_bt);
  end if;
  -- 머리(number 로 — 판 수 · 마지막 날 · 「아직 줄을 못 읽은 더 늦은 판」 을 알아보는 데만)
  if v_tn is not null then
    select count(*), max(d.doc_date) into v_heads, v_last from public.fc_document d where d.account = v_b.account and d.type = 'shipment-order-details' and d.number = v_tn;
    select d.* into v_head from public.fc_document d where d.account = v_b.account and d.type = 'shipment-order-details' and d.number = v_tn order by d.doc_date desc nulls last, d.amount_cents desc, d.id desc limit 1;
  end if;
  -- 판 — 그 쉽먼트의 줄이 든 shipment-order-details 중 날짜가 가장 늦은 것 · 같은 날이면 금액 큰 것(잇는 열쇠 = 줄의 shipment id)
  if v_fc is not null then
    select d.* into v_doc from public.fc_document d
     where d.account = v_b.account and d.type = 'shipment-order-details' and exists (select 1 from public.fc_document_line l where l.document_id = d.id and l.shipment_fc_id = v_fc)
     order by d.doc_date desc nulls last, d.amount_cents desc, d.id desc limit 1;
    select sum(l.amount_cents), count(distinct l.document_id) into v_inv, v_invn
      from public.fc_document_line l join public.fc_document d on d.id = l.document_id
     where d.account = v_b.account and d.type = 'net-terms-invoice' and l.shipment_fc_id = v_fc;
  end if;
  if v_doc.id is not null then
    select coalesce(sum(l.amount_cents) filter (where l.type <> 'tax'), 0), coalesce(sum(l.amount_cents) filter (where l.type = 'tax'), 0),
           coalesce(bool_or(l.currency is not null and v_rate->>'currency' is not null and l.currency <> v_rate->>'currency'), false)
      into v_lp, v_lt, v_curx
      from public.fc_document_line l where l.document_id = v_doc.id and l.shipment_fc_id = v_fc;
    v_extra := v_lp - v_bp;
    select coalesce(jsonb_agg(jsonb_build_object('sub_type', x.k, 'booked', x.bk, 'billed', x.bl, 'delta', x.bl - x.bk) order by x.k), '[]'::jsonb) into v_lines
      from (select coalesce(a.k, r.k) as k, coalesce(r.c, 0) as bk, coalesce(a.c, 0) as bl
              from (select coalesce(l.sub_type, l.type) as k, sum(l.amount_cents) as c from public.fc_document_line l
                     where l.document_id = v_doc.id and l.shipment_fc_id = v_fc and l.type <> 'tax' group by 1) a
              full join (select z.k, sum(z.c) as c
                           from (select 'base'::text as k, (v_rate->>'base')::bigint as c where v_rate is not null
                                 union all
                                 select s->>'type', (s->>'cents')::bigint from jsonb_array_elements(coalesce(v_rate->'surcharges', '[]'::jsonb)) s) z
                          group by 1) r on r.k = a.k) x
     where x.bl <> x.bk;
    v_last := greatest(v_last, v_doc.doc_date);
    if v_doc.number is distinct from v_tn then v_warn := array_append(v_warn, 'number_differs — the document number is not this booking''s transaction number'); end if;
    if v_head.id is not null and v_head.id <> v_doc.id and v_head.amount_cents <> v_doc.amount_cents and coalesce(v_head.doc_date, '0001-01-01'::date) >= coalesce(v_doc.doc_date, '0001-01-01'::date) then
      v_warn := array_append(v_warn, 'newer_version_unread — a later version of this document has a different amount and its lines are not read yet');
    end if;
    if v_invn > 0 and abs(v_inv - (v_lp + v_lt)) > c_tol then v_warn := array_append(v_warn, 'invoiced_differs — the net-terms invoice lines for this shipment do not add up to the latest order details'); end if;
  end if;
  if v_rate is null then v_warn := array_append(v_warn, 'no_booked_rate — neither the booking answer nor the selected quote has a rate'); end if;
  if v_curx then v_warn := array_append(v_warn, 'currency_differs — the billed lines are not in the booked currency · not compared'); end if;
  v_state := case
    when v_doc.id is null then case when v_heads > 0 or v_invn > 0 then 'unread' else 'none' end
    when v_b.status = 'cancelled' then 'cancelled_billed'
    when v_rate is null or v_curx then 'unknown'
    when abs(v_extra) <= c_tol then 'billed'
    when v_extra > 0 then 'extra'
    else 'less'
  end;
  return jsonb_build_object('booking_id', v_b.id, 'status', v_b.status, 'account', v_b.account, 'transaction_number', v_tn, 'state', v_state,
                            'rate_source', v_rate->>'source', 'currency', v_rate->>'currency',
                            'booked_pretax', v_bp, 'tax_booked', v_bt, 'booked_total', v_btot,
                            'billed_pretax', v_lp, 'tax_billed', v_lt, 'billed_total', v_lp + v_lt,
                            'extra_cents', v_extra, 'extra_lines', v_lines, 'tolerance_cents', c_tol,
                            'doc_count', greatest(v_heads, case when v_doc.id is not null then 1 else 0 end), 'last_doc_date', v_last, 'document_id', v_doc.id,
                            'invoiced_cents', v_inv, 'invoice_count', v_invn, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.fc_charge_check(uuid) from public, anon, authenticated;
grant execute on function public.fc_charge_check(uuid) to service_role;
comment on function public.fc_charge_check(uuid) is 'fc-track-3 ⑥ · 판정 1163(속 · service_role · 화면 창구는 fc-track-4): 예약 금액(fc_booking_rate) 대비 Freightcom 청구 — 판 = 그 쉽먼트 줄(shipment_fc_id)이 든 shipment-order-details 중 날짜가 가장 늦은 것 · 같은 날이면 금액 큰 것 · state none | unread | billed | extra | less | cancelled_billed | unknown(세전 합계끼리 · 오차 100 ¢) · extra_lines[{sub_type, booked, billed, delta}] 는 설명용(base 는 sub_type base) · 세금은 tax_booked · tax_billed 따로 · invoiced_cents = 묶음 인보이스의 그 쉽먼트 줄 합 · warnings(number_differs · newer_version_unread · invoiced_differs · no_booked_rate · currency_differs) · 취소한 예약도 본다';

-- ═══ 7) 계정 요약(1164) ═══
create function public.fc_finance_account_summary(p_account text) returns jsonb
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with a as (
    select upper(btrim(coalesce(p_account, ''))) as acc
  ), bal as (
    select f.available_cents, f.checked_at, f.method_type from public.fc_balance f, a where f.account = a.acc order by f.checked_at desc, f.id desc limit 1
  ), lim as (
    select case when btrim(c.value) ~ '^\d{1,9}(\.\d{1,2})?$' then round(btrim(c.value)::numeric * 100)::bigint end as cents from public.inv_config c, a where c.key = 'fc_credit_limit_' || a.acc
  ), owe as (
    select d.id, d.number, d.doc_date, d.due_date, d.amount_cents, d.owing_cents from public.fc_document d, a where d.account = a.acc and d.type = 'net-terms-invoice' and d.owing_cents > 0
  ), ub as (
    select b.id, (public.fc_booking_rate(b)->>'total')::bigint as total_cents
      from public.fc_booking b, a
     where b.account = a.acc and b.status = 'booked' and nullif(btrim(b.freightcom_shipment_id), '') is not null and public.fc_state_kind(b.state) <> 'cancelled'
       and not exists (select 1 from public.fc_document d where d.account = b.account and d.type = 'shipment-order-details' and d.number = b.transaction_number)
       and not exists (select 1 from public.fc_document_line l join public.fc_document d on d.id = l.document_id where d.account = b.account and l.shipment_fc_id = b.freightcom_shipment_id)
  )
  select jsonb_build_object(
           'account', a.acc,
           'available_cents', (select bal.available_cents from bal), 'balance_checked_at', (select bal.checked_at from bal), 'method_type', (select bal.method_type from bal),
           'limit_cents', (select lim.cents from lim), 'limit_basis', 'setting',
           'used_cents', (select lim.cents from lim) - (select bal.available_cents from bal), 'used_basis', 'setting_limit_minus_available',
           'invoices_owing', coalesce((select jsonb_agg(to_jsonb(o) order by o.due_date, o.doc_date, o.id) from owe o), '[]'::jsonb),
           'owing_cents', coalesce((select sum(o.owing_cents) from owe o), 0), 'owing_count', (select count(*) from owe),
           'unbilled_count', (select count(*) from ub), 'unbilled_cents', coalesce((select sum(ub.total_cents) from ub), 0), 'unbilled_no_rate', (select count(*) from ub where ub.total_cents is null),
           'docs_checked_at', (select max(d.fetched_at) from public.fc_document d where d.account = a.acc))
    from a;
$$;
revoke all on function public.fc_finance_account_summary(text) from public, anon, authenticated;
grant execute on function public.fc_finance_account_summary(text) to service_role;
comment on function public.fc_finance_account_summary(text) is 'fc-track-3 ⑦ · 판정 1164(속 · service_role · 화면 창구는 fc-track-4): 계정 요약 — available_cents(남은 한도 · Freightcom 값이 정본 · 가장 늦은 fc_balance) · limit_cents(inv_config fc_credit_limit_<계정> 달러 → 센트 · 설정값) · used_cents = 한도 − 남은 한도(설정 한도 기준) · invoices_owing(net-terms-invoice · owing > 0) · owing_cents · unbilled_count · unbilled_cents(booked · Freightcom 취소 아님 · 청구 문서가 아직 없는 예약의 견적 총액) · unbilled_no_rate · docs_checked_at';

-- ═══ 8) 사람 길의 문 ═══
create function public.fc_finance_gate(p_account text) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_acc text := upper(btrim(coalesce(p_account, '')));
begin
  if not (public.ims_can_write('freight_booking') or public.ims_can_write('purchasing')) then
    raise exception 'You cannot refresh Freightcom billing — ask an admin for the ''freight_booking'' or ''purchasing'' permission — nothing was read';
  end if;
  if v_acc !~ '^[A-Z0-9]{2,10}$' then raise exception 'account must be 2–10 upper-case letters or digits — nothing was read'; end if;
  if not exists (select 1 from public.ref_warehouse w where w.freightcom_account = v_acc) then raise exception 'No warehouse uses the Freightcom account % — nothing was read', v_acc; end if;
  if not exists (select 1 from public.ref_warehouse w where w.freightcom_account = v_acc and public.ims_can_warehouse(w.id)) then raise exception 'This Freightcom account belongs to another warehouse — nothing was read'; end if;
  return jsonb_build_object('account', v_acc);
end;
$$;
revoke all on function public.fc_finance_gate(text) from public, anon;
grant execute on function public.fc_finance_gate(text) to authenticated;
comment on function public.fc_finance_gate(text) is 'fc-track-3 ⑧ ⬜6: 사람 길 finance_poll 의 문(사용자 JWT · 읽기) — freight_booking ∨ purchasing 쓰기 + 그 계정을 쓰는 창고(ims_can_warehouse) · EF 가 GET 앞에 부른다 · 화면의 돈 문은 fc-track-4';

-- ═══ 9) 착지 확인 ═══
do $$
declare v_t text;
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_doc_cents', 'fc_doc_date', 'fc_booking_rate', 'fc_finance_lines_due', 'fc_finance_docs_save', 'fc_finance_lines_save', 'fc_finance_balance_save', 'fc_charge_check', 'fc_finance_account_summary', 'fc_finance_gate')) <> 10 then
    raise exception 'fc-track-3 landing check failed: expected 10 new functions (one definition each)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') <> 49 then raise exception 'fc-track-3 landing check failed: expected 49 fc_ functions (39 before + 10)'; end if;
  foreach v_t in array array['fc_document', 'fc_document_line', 'fc_balance'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || v_t)::regclass) or exists (select 1 from pg_policy p where p.polrelid = ('public.' || v_t)::regclass)
       or has_table_privilege('authenticated', 'public.' || v_t, 'select') or has_table_privilege('anon', 'public.' || v_t, 'select') or has_table_privilege('service_role', 'public.' || v_t, 'insert') then
      raise exception 'fc-track-3 landing check failed: % must be closed (RLS on · no policy · no authenticated / anon select · no direct service_role write)', v_t;
    end if;
  end loop;
  if (select count(*) from public.inv_config c where c.key in ('fc_finance_poll_enabled', 'fc_finance_doc_batch', 'fc_credit_limit_TOR', 'fc_credit_limit_EDM')) <> 4 then raise exception 'fc-track-3 landing check failed: inv_config keys missing'; end if;
  if (select c.value from public.inv_config c where c.key = 'fc_finance_poll_enabled') <> 'off' then raise exception 'fc-track-3 landing check failed: the switch must start off'; end if;
end $$;
