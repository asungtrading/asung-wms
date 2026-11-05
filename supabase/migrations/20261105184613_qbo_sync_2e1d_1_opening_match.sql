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
-- qbo-sync-2e-1d-1 — 이월 인보이스 QBO 짝(DB) · 되살리기 고침(「모두 섰을 때만」) · 수단 짝 되살리기 (판정 982 · 1016 · 1039 · deferred 452 · 341 · 2026-11-05 · 지시서 ~/asung/prompts/qbo-sync-2e-1d-1.md · §0 이견 답: 1 A(matched 행 삭제) · 2 · 6 · 8 · 9 그대로 · 3 · 4 · 5 · 7 · 10 ~ 13 이대로)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용 + supabase migration repair --status applied <이 파일 번호> · ⚠️ db push 쓰지 않는다 · 2e-2-1(20261103200000) 뒤
-- 무엇:
--   ⓪ 재발행 원본 가드 — qbo_payment_requeue(2e-2-1 `20261103200000`) · qbo_link_set(1a `20261101210000`)의 DB prosrc md5 가 마지막 정의 파일과 다르면 멈춘다 · 결제 · 크레딧 붙임 몸 넷 · qbo_key_gate 무변 확인 · 두 번 적용 방지
--   ① 표: qbo_txn + match_how(auto | manual · source = 'matched' 일 때만 · CHECK) · match_snapshot(짝 당시 QBO 행 — Id · DocNumber · TotalAmt · Balance · CustomerRef · SyncToken · TxnDate) / 새 표 qbo_opening_review(이월 인보이스마다 마지막 검사 — reason · warning · 본 QBO 행 · 풀림 흔적 · 거래 표 FK 없음 · 창구만)
--   ② 속(grant 0): qbo_opening_slim(QBO 행 추림) · qbo_opening_check(다섯 조건 — DocNumber 완전 일치 ∧ 한 장뿐 ∧ CustomerRef ∈ {매장 짝 · 청구처 짝 · 그 둘의 qbo_entity.parent_id} ∧ TotalAmt = total ∧ Balance = total − prior_settled − IMS 가 이미 보낸 붙임 합)
--      qbo_opening_record(qbo_txn matched 행 + review + requeue — 한 트랜잭션) · qbo_opening_remaining(결제가 걸린 이월 · since 전 짝 없는 장 수) · qbo_payment_requeue_one(남은 장 0 일 때만 sync + failed → queued · 아니면 failed 그대로 · 글 「N carried-over invoice(s) …」) · qbo_payment_method_requeue(수단 짝 뒤 · 판정 1039)
--   ③ 창구(열쇠 QUICKBOOKS · qbo_key_gate · admin 도 열쇠 · 945): qbo_opening_candidates(물은 번호 + QBO 행 → 자동 짝 · 못 지으면 review 에 까닭 · 멱등) · qbo_opening_match(사람 짝 · 경고는 p_ack) · qbo_opening_unmatch(이견 1 A: matched 행 삭제 · 보낸 것 있으면 거부 · queued · blocked 일감은 failed 로) · qbo_opening_list(목록 · 'qbo:read' 면 보인다)
--   ④ 재발행: qbo_payment_requeue(2e-2-1 바이트 + 결제 가지를 requeue_one 으로) · qbo_link_set(1a 바이트 + payment_method 짝이 서면 qbo_payment_method_requeue · 돌려주는 jsonb 에 requeued)
--   ⑤ grant · 착지
-- 안 하는 것: EF(1d-2 — KEY_ACTIONS 에 opening_candidates · opening_read) · 화면(1d-3) · 결제 · 크레딧 붙임 몸(글 그대로 「Settings → QuickBooks → Opening invoices」) · qbo_txn UNIQUE 둘 무변 · 백필 없음(QBO 행은 EF 가 가져온다)
-- 거래 표 FK: 새 FK 없음(qbo_opening_review.invoice_id 는 uuid 만 · qbo_txn ims_id 다형 · ims_staff FK 둘은 qbo_txn.updated_by 와 같은 꼴) — 컷오버 지우는 순서 무변 · 검증: supabase/tests/qbo_sync_2e1d_1_check.sql(-v mig 시험 · 적용 뒤 -v mig 없이)

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_requeue')   is distinct from '9a691814b021d4927d5d9b17179ab78d' then v_bad := v_bad || ' qbo_payment_requeue'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_link_set')          is distinct from '0fce741132f19fb9e76fb45ac56ff7e3' then v_bad := v_bad || ' qbo_link_set'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_key_gate')          is distinct from '2e9b5d48245284eb6d2123080d376708' then v_bad := v_bad || ' qbo_key_gate'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')      is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')      is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_apply_body') is distinct from '08b17e793b3ec596b8b077de0ae719bc' then v_bad := v_bad || ' qbo_credit_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync') is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_requeue', 'qbo_link_set', 'qbo_key_gate', 'qbo_payment_sync')) <> 4 then v_bad := v_bad || ' overloads'; end if;
  if to_regprocedure('public.so_invoice_store(uuid)') is null or to_regprocedure('public.so_invoice_remaining(uuid)') is null or to_regprocedure('public.qbo_send_since_ok(date)') is null then v_bad := v_bad || ' so_invoice_store/so_invoice_remaining/qbo_send_since_ok'; end if;
  if exists (select 1 from pg_attribute where attrelid = 'public.qbo_txn'::regclass and attname = 'match_how' and not attisdropped) or to_regclass('public.qbo_opening_review') is not null then v_bad := v_bad || ' already-applied(qbo_txn.match_how / qbo_opening_review)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══ ① 표 ═══
alter table public.qbo_txn add column match_how text, add column match_snapshot jsonb,
  add constraint qbo_txn_match_ck check ((source = 'matched') = (match_how is not null) and (match_how is null or match_how in ('auto', 'manual'))
                                         and (source = 'sent' or (match_snapshot is not null and job_id is null and fingerprint is null)));
comment on column public.qbo_txn.match_how is 'qbo-sync-2e-1d-1: source = matched 행만 — auto(qbo_opening_candidates 다섯 조건) | manual(qbo_opening_match · 경고는 p_ack) · sent 행은 null(CHECK)';
comment on column public.qbo_txn.match_snapshot is 'qbo-sync-2e-1d-1: 짝 당시 QBO Invoice 행 추림(Id · DocNumber · TotalAmt · Balance · CustomerRef · SyncToken · TxnDate) · matched 행만 · PII 칸 없음';

create table public.qbo_opening_review (
  realm_id   text not null,
  invoice_id uuid not null,
  checked_at timestamptz,
  reason     text constraint qbo_opening_review_reason_ck check (reason is null or reason in ('not_found', 'many', 'unlinked', 'customer', 'total', 'balance', 'docnumber', 'taken', 'unmatched')),
  warning    text,
  qbo_rows   jsonb not null default '[]'::jsonb,
  unmatched_at timestamptz, unmatched_by uuid references public.ims_staff(id), unmatched_snapshot jsonb, unmatched_note text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), updated_by uuid references public.ims_staff(id),
  primary key (realm_id, invoice_id)
);
comment on table public.qbo_opening_review is 'qbo-sync-2e-1d-1(deferred 452 · 이견 2): 이월 인보이스(so_invoice kind opening)마다 QBO 짝 검사의 마지막 결과 — reason null = 짝이 서 있다(qbo_txn source matched) · not_found | many | unlinked | customer | total | balance | docnumber | taken = 사람 목록(warning 에 글) · unmatched = 풀린 뒤 다시 검사 전 · qbo_rows = 검사 때 본 QBO 행 추림 · 풀림 흔적(unmatched_at · by · snapshot · note — 이견 1 A: matched 행은 지운다) · 거래 표 FK 없음 · 창구만(grant 0 · RLS 정책 0)';
alter table public.qbo_opening_review enable row level security;
revoke all on table public.qbo_opening_review from public, anon, authenticated, service_role;
create trigger qbo_opening_review_touch before update on public.qbo_opening_review for each row execute function public.ims_touch();

-- ═══ ② 속 함수(grant 0) ═══
create function public.qbo_opening_slim(p_row jsonb) returns jsonb
  language sql immutable
as $$
  select jsonb_build_object('Id', btrim(p_row->>'Id'), 'DocNumber', btrim(p_row->>'DocNumber'), 'TotalAmt', p_row->'TotalAmt', 'Balance', p_row->'Balance',
                            'CustomerRef', btrim(p_row->'CustomerRef'->>'value'), 'SyncToken', p_row->>'SyncToken', 'TxnDate', p_row->>'TxnDate');
$$;
comment on function public.qbo_opening_slim(jsonb) is 'qbo-sync-2e-1d-1(속): QBO Invoice 행에서 짝에 쓰는 일곱 칸만 — match_snapshot · review.qbo_rows 에 담는 꼴(PII 칸 없음)';

create function public.qbo_opening_num(p text) returns numeric
  language plpgsql immutable
as $$
begin
  return nullif(btrim(p), '')::numeric;
exception when others then return null;
end;
$$;
comment on function public.qbo_opening_num(text) is 'qbo-sync-2e-1d-1(속): 글자 → numeric · 못 읽으면 null(검사가 「어긋남」 으로 본다)';

create function public.qbo_opening_check(p_invoice_id uuid, p_rows jsonb, p_qbo_id text default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_i public.so_invoice%rowtype; v_store uuid; v_rows jsonb := '[]'::jsonb; v_row jsonb; v_n int;
        v_reasons text[] := '{}'; v_msgs text[] := '{}'; v_allowed text[]; v_l_store text; v_l_bill text; v_sent numeric := 0; v_expect numeric; v_bal numeric; v_tot numeric; v_cust text;
begin
  if v_realm is null then raise exception 'QuickBooks is not connected — connect it in Settings → QuickBooks first'; end if;
  select * into v_i from public.so_invoice i where i.id = p_invoice_id;
  if v_i.id is null then raise exception 'No IMS invoice % — nothing was matched', p_invoice_id; end if;
  if v_i.kind <> 'opening' then raise exception 'Invoice % was issued in IMS — it goes to QuickBooks by itself and is not matched here', v_i.invoice_number; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — only issued carried-over invoices can be matched', v_i.invoice_number, v_i.status; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'rows must be a JSON array of QuickBooks Invoice rows'; end if;
  if p_qbo_id is null then                                                                             -- 자동: DocNumber = invoice_number 완전 일치 · 한 장뿐
    select coalesce(jsonb_agg(public.qbo_opening_slim(x)), '[]'::jsonb) into v_rows from jsonb_array_elements(p_rows) x where btrim(coalesce(x->>'DocNumber', '')) = v_i.invoice_number;
    v_n := jsonb_array_length(v_rows);
    if v_n = 0 then v_reasons := array_append(v_reasons, 'not_found'); v_msgs := v_msgs || format('no QuickBooks invoice is numbered %s', v_i.invoice_number);
    elsif v_n > 1 then v_reasons := array_append(v_reasons, 'many'); v_msgs := v_msgs || format('QuickBooks has %s invoices numbered %s — pick one by hand', v_n, v_i.invoice_number);
    else v_row := v_rows->0; end if;
  else                                                                                                 -- 사람: Id 로 읽은 행 · DocNumber 가 다르면 경고(docnumber)
    select public.qbo_opening_slim(x) into v_row from jsonb_array_elements(p_rows) x where btrim(coalesce(x->>'Id', '')) = btrim(p_qbo_id) limit 1;
    if v_row is null then raise exception 'QuickBooks Invoice #% is not among the rows given — read it again', btrim(p_qbo_id); end if;
    v_rows := jsonb_build_array(v_row);
    if coalesce(v_row->>'DocNumber', '') <> v_i.invoice_number then v_reasons := array_append(v_reasons, 'docnumber'); v_msgs := v_msgs || format('QuickBooks invoice #%s is numbered "%s", not %s', v_row->>'Id', coalesce(v_row->>'DocNumber', ''), v_i.invoice_number); end if;
  end if;
  if v_row is not null then
    v_store := public.so_invoice_store(v_i.id);
    select l.qbo_id into v_l_store from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_store::text;
    select l.qbo_id into v_l_bill  from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_i.bill_to_customer_id::text;
    if v_l_store is null or v_l_bill is null then
      v_reasons := array_append(v_reasons, 'unlinked'); v_msgs := v_msgs || format('the store or bill-to customer of invoice %s has no QuickBooks customer match yet — match the customer under Settings → QuickBooks matching first', v_i.invoice_number);
    else                                                                                               -- 이견 4: 부모는 qbo_entity.parent_id(거울)로 — 묵으면 customer 까닭으로 사람 목록
      v_allowed := array[v_l_store, v_l_bill] || coalesce(array(select e.parent_id from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id in (v_l_store, v_l_bill) and e.parent_id is not null), '{}'::text[]);
      v_cust := v_row->>'CustomerRef';
      if v_cust is null or not (v_cust = any (v_allowed)) then v_reasons := array_append(v_reasons, 'customer'); v_msgs := v_msgs || format('QuickBooks invoice #%s belongs to customer %s — not this invoice''s store, bill-to customer, or their parent', v_row->>'Id', coalesce(v_cust, '?')); end if;
    end if;
    v_tot := public.qbo_opening_num(v_row->>'TotalAmt');
    if v_tot is null or v_tot <> v_i.total then v_reasons := array_append(v_reasons, 'total'); v_msgs := v_msgs || format('QuickBooks total %s differs from IMS total %s', coalesce(v_tot::text, '?'), v_i.total); end if;
    select coalesce(sum(a.amount), 0) into v_sent from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
      where a.invoice_id = v_i.id and a.voided_at is null and p.status = 'active'
        and exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'payment' and t.ims_id = p.id::text and t.voided_at is null);
    v_sent := v_sent + coalesce((select sum(ca.amount) from public.so_credit_alloc ca where ca.invoice_id = v_i.id and ca.voided_at is null
                                   and exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit_alloc' and t.ims_id = ca.id::text and t.voided_at is null)), 0);
    v_expect := v_i.total - coalesce(v_i.prior_settled, 0) - v_sent;
    v_bal := public.qbo_opening_num(v_row->>'Balance');
    if v_bal is null or v_bal <> v_expect then v_reasons := array_append(v_reasons, 'balance'); v_msgs := v_msgs || format('QuickBooks balance %s differs from what IMS expects (%s) — QuickBooks may already have a payment on this invoice; sending the IMS payment would record it twice', coalesce(v_bal::text, '?'), v_expect); end if;
  end if;
  return jsonb_build_object('invoice_id', v_i.id, 'invoice_number', v_i.invoice_number, 'ok', cardinality(v_reasons) = 0, 'reasons', to_jsonb(v_reasons), 'reason', v_reasons[1],
                            'warning', case when cardinality(v_msgs) > 0 then array_to_string(v_msgs, ' · ') end, 'row', v_row, 'rows', v_rows, 'expect_balance', v_expect, 'sent_sum', v_sent, 'allowed_customers', to_jsonb(coalesce(v_allowed, '{}'::text[])));
end;
$$;
comment on function public.qbo_opening_check(uuid, jsonb, text) is 'qbo-sync-2e-1d-1(속 · 읽기만): 이월 인보이스 하나 ↔ QBO Invoice 행 묶음 — 자동(p_qbo_id null): DocNumber 완전 일치 ∧ 한 장뿐 / 사람(p_qbo_id): 그 Id 의 행 · DocNumber 다르면 docnumber — 그 뒤 CustomerRef ∈ {매장 짝 · 청구처 짝 · 그 둘의 qbo_entity.parent_id}(unlinked · customer) ∧ TotalAmt = total ∧ Balance = total − prior_settled − IMS 가 이미 보낸 붙임 합(balance · 두 번 적힘 경고) · ok · reasons · warning · row(추림)';

create function public.qbo_opening_remaining(p_payment_id uuid) returns int
  language sql stable security definer set search_path = public, pg_temp
as $$
  select count(*)::int from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id
   where a.payment_id = p_payment_id and a.voided_at is null and (i.kind = 'opening' or not public.qbo_send_since_ok(i.issued_on))
     and not exists (select 1 from public.qbo_txn t join public.qbo_connection c on c.singleton and t.realm_id = c.realm_id where t.ims_kind = 'invoice' and t.ims_id = i.id::text and t.voided_at is null);
$$;
comment on function public.qbo_opening_remaining(uuid) is 'qbo-sync-2e-1d-1(속 · 이견 6): 이 결제의 활성 붙임 중 (이월 ∨ since 전) ∧ 활성 qbo_txn invoice 없음 인 장수 — since 뒤 sale 인보이스는 몸이 blocked 로 기다리므로 세지 않는다 · 0 이어야 결제 일감을 되살린다';

create function public.qbo_payment_requeue_one(p_payment_id uuid, p_by uuid, p_note text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_left int; v_j public.qbo_job%rowtype; v_s jsonb; v_act text := 'none';
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  v_left := public.qbo_opening_remaining(p_payment_id);
  select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id = p_payment_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_left > 0 then                                                                                   -- 모두 서지 않았다 — failed 그대로 · 글만 남은 장 수(처음 걸린 한 장이 아니라)
    if v_j.id is not null and v_j.state = 'failed' then
      update public.qbo_job j set last_error = left(format('%s carried-over invoice(s) on this payment still have no QuickBooks match — match them under Settings → QuickBooks → Opening invoices and the payment then goes by itself', v_left), 2000), updated_by = p_by
       where j.id = v_j.id;
      v_act := 'waiting';
    else v_act := case when v_j.id is null then 'waiting_no_job' else 'waiting_' || v_j.state end; end if;
    return jsonb_build_object('action', v_act, 'remaining', v_left, 'job_id', v_j.id);
  end if;
  if v_j.id is not null and v_j.state = 'failed' and public.qbo_payment_fingerprint(p_payment_id) is not null then   -- failed 일감은 sync 보다 먼저 queued 로 — 몸에서 실패한 일감은 지문이 null(claim 은 몸이 성공할 때만 적는다 · 실물 failed 11 장 모두 null)이라 sync 가 「the payment changed after it failed」 로 먼저 집어 간다(시험 5 회차 실측)
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, p_note), 2000), updated_by = p_by where j.id = v_j.id;
    return jsonb_build_object('action', 'queued', 'remaining', 0, 'job_id', v_j.id, 'sync', null);
  end if;
  v_s := public.qbo_payment_sync(p_payment_id, p_by);                                                  -- 일감이 없으면 만든다(지문 있을 때 queued) · 지문 null 이면 skipped · queued · blocked 는 그대로
  select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id = p_payment_id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  return jsonb_build_object('action', coalesce(v_s->>'action', 'none'), 'remaining', 0, 'job_id', v_j.id, 'sync', v_s->>'action');
end;
$$;
comment on function public.qbo_payment_requeue_one(uuid, uuid, text) is 'qbo-sync-2e-1d-1(속 · 이견 6): 결제 하나 되살리기 — 남은 이월 장(qbo_opening_remaining) > 0 이면 failed 그대로 · last_error 를 「N carried-over invoice(s) …」 로 / 0 이면 failed → queued(note · sync 보다 먼저 — 몸에서 실패한 일감은 지문 null) · 일감 없으면 qbo_payment_sync 가 만든다 · qbo_payment_requeue · qbo_payment_method_requeue 가 부른다';

create function public.qbo_payment_method_requeue(p_method text, p_by uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_r record; v_n int := 0;
begin
  for v_r in select j.ims_id::uuid as payment_id from public.qbo_job j join public.so_payment p on p.id::text = j.ims_id join public.qbo_connection c on c.singleton and c.realm_id = j.realm_id
              where j.kind = 'payment' and j.ims_kind = 'payment' and j.state = 'failed' and p.status = 'active' and p.kind = 'payment' and p.method = p_method order by j.created_at, j.id loop
    if (public.qbo_payment_requeue_one(v_r.payment_id, p_by, format('sent again: payment method "%s" is now matched in QuickBooks', p_method)))->>'action' = 'queued' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_payment_method_requeue(text, uuid) is 'qbo-sync-2e-1d-1(속 · 판정 1039 · 이견 7): 수단 p_method 인 활성 결제의 failed 결제 일감을 qbo_payment_requeue_one 으로(남은 이월 장 > 0 이면 건너뛴다 — 짝 때 되살아난다) · qbo_link_set(payment_method) 이 부른다 · 돌려주는 것 = queued 가 된 수';

create function public.qbo_opening_record(p_invoice_id uuid, p_how text, p_check jsonb, p_staff uuid, p_ack_warning text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_row jsonb := p_check->'row'; v_num text := p_check->>'invoice_number'; v_holder text; v_rq int := 0; v_t public.qbo_txn%rowtype;
begin
  if v_row is null or nullif(btrim(coalesce(v_row->>'Id', '')), '') is null then raise exception 'No QuickBooks row to record for invoice %', v_num; end if;
  select i.invoice_number into v_holder from public.qbo_txn t join public.so_invoice i on i.id::text = t.ims_id where t.realm_id = v_realm and t.qbo_type = 'Invoice' and t.qbo_id = v_row->>'Id';   -- 10: UNIQUE 에 맡기지 않고 사람 글로
  if v_holder is not null then
    insert into public.qbo_opening_review as rv (realm_id, invoice_id, checked_at, reason, warning, qbo_rows, updated_by)
    values (v_realm, p_invoice_id, now(), 'taken', format('QuickBooks invoice #%s is already matched to IMS invoice %s — unmatch that one first', v_row->>'Id', v_holder), coalesce(p_check->'rows', '[]'::jsonb), p_staff)
    on conflict (realm_id, invoice_id) do update set checked_at = now(), reason = excluded.reason, warning = excluded.warning, qbo_rows = excluded.qbo_rows, updated_by = excluded.updated_by;
    return jsonb_build_object('result', 'taken', 'invoice_id', p_invoice_id, 'invoice_number', v_num, 'qbo_id', v_row->>'Id', 'holder', v_holder);
  end if;
  insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source, match_how, match_snapshot, updated_by)
  values (v_realm, 'invoice', p_invoice_id::text, 'Invoice', v_row->>'Id', v_row->>'DocNumber', v_row->>'SyncToken', public.qbo_opening_num(v_row->>'TotalAmt'), null, null, null, now(), null, null, 'matched', p_how, v_row, p_staff)
  returning * into v_t;
  insert into public.qbo_opening_review as rv (realm_id, invoice_id, checked_at, reason, warning, qbo_rows, updated_by)
  values (v_realm, p_invoice_id, now(), null, p_ack_warning, coalesce(p_check->'rows', '[]'::jsonb), p_staff)
  on conflict (realm_id, invoice_id) do update set checked_at = now(), reason = null, warning = excluded.warning, qbo_rows = excluded.qbo_rows, updated_by = excluded.updated_by;
  v_rq := public.qbo_payment_requeue(p_invoice_id);                                                    -- 같은 트랜잭션 · 결제는 남은 이월 장 0 일 때만 queued(requeue_one) · 크레딧 붙임은 2e-2-1 그대로
  return jsonb_build_object('result', 'matched', 'invoice_id', p_invoice_id, 'invoice_number', v_num, 'qbo_id', v_t.qbo_id, 'txn_id', v_t.id, 'match_how', p_how, 'requeue_touched', v_rq);
end;
$$;
comment on function public.qbo_opening_record(uuid, text, jsonb, uuid, text) is 'qbo-sync-2e-1d-1(속): 짝 적기 — 다른 IMS 인보이스가 그 QBO Id 를 쥐고 있으면 taken(review 에 글 · 사람 글) · 아니면 qbo_txn(source matched · match_how · match_snapshot · job_id null) + review(reason null · 사람 짝이면 받아들인 경고) + qbo_payment_requeue — 한 트랜잭션';

-- ═══ ③ 창구 — 열쇠 QUICKBOOKS(qbo_key_gate · 945) ═══
create function public.qbo_opening_candidates(p_doc_numbers text[], p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_r record; v_c jsonb; v_o jsonb; v_out jsonb := '[]'::jsonb; v_t public.qbo_txn%rowtype; v_rv public.qbo_opening_review%rowtype;
        v_matched int := 0; v_taken int := 0; v_already int := 0; v_changed int := 0; v_same int := 0; v_unknown int := 0; v_nums text[] := coalesce(p_doc_numbers, '{}'::text[]);
begin
  if p_rows is not null and jsonb_typeof(p_rows) <> 'array' then raise exception 'rows must be a JSON array of QuickBooks Invoice rows'; end if;
  if cardinality(v_nums) = 0 then return jsonb_build_object('checked', 0, 'matched', 0, 'taken', 0, 'already', 0, 'review_changed', 0, 'review_same', 0, 'unknown_numbers', 0, 'rows', '[]'::jsonb); end if;
  select count(*) into v_unknown from unnest(v_nums) n where not exists (select 1 from public.so_invoice i where i.invoice_number = n and i.kind = 'opening' and i.status = 'issued');
  for v_r in select i.id, i.invoice_number from public.so_invoice i where i.kind = 'opening' and i.status = 'issued' and i.invoice_number = any (v_nums) order by i.invoice_number loop
    select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_r.id::text and t.voided_at is null;
    if v_t.id is not null then
      v_already := v_already + 1; v_out := v_out || jsonb_build_object('invoice_number', v_r.invoice_number, 'result', 'already', 'qbo_id', v_t.qbo_id, 'match_how', v_t.match_how); continue;
    end if;
    v_c := public.qbo_opening_check(v_r.id, coalesce(p_rows, '[]'::jsonb), null);
    if (v_c->>'ok')::boolean then
      v_o := public.qbo_opening_record(v_r.id, 'auto', v_c, v_staff, null);
      if v_o->>'result' = 'matched' then v_matched := v_matched + 1; else v_taken := v_taken + 1; end if;
      v_out := v_out || (v_o || jsonb_build_object('invoice_number', v_r.invoice_number));
    else                                                                                               -- 사람 목록 — 같은 결과면 쓰지 않는다(멱등 · 변화 0)
      select * into v_rv from public.qbo_opening_review rv where rv.realm_id = v_realm and rv.invoice_id = v_r.id;
      if v_rv.invoice_id is not null and v_rv.reason is not distinct from (v_c->>'reason') and v_rv.warning is not distinct from (v_c->>'warning') and v_rv.qbo_rows = coalesce(v_c->'rows', '[]'::jsonb) then
        v_same := v_same + 1;
      else
        insert into public.qbo_opening_review as rv (realm_id, invoice_id, checked_at, reason, warning, qbo_rows, updated_by)
        values (v_realm, v_r.id, now(), v_c->>'reason', v_c->>'warning', coalesce(v_c->'rows', '[]'::jsonb), v_staff)
        on conflict (realm_id, invoice_id) do update set checked_at = now(), reason = excluded.reason, warning = excluded.warning, qbo_rows = excluded.qbo_rows, updated_by = excluded.updated_by;
        v_changed := v_changed + 1;
      end if;
      v_out := v_out || jsonb_build_object('invoice_number', v_r.invoice_number, 'invoice_id', v_r.id, 'result', 'review', 'reason', v_c->>'reason', 'warning', v_c->>'warning', 'candidates', jsonb_array_length(coalesce(v_c->'rows', '[]'::jsonb)));
    end if;
  end loop;
  return jsonb_build_object('checked', v_matched + v_taken + v_already + v_changed + v_same, 'matched', v_matched, 'taken', v_taken, 'already', v_already, 'review_changed', v_changed, 'review_same', v_same, 'unknown_numbers', v_unknown, 'rows', v_out);
end;
$$;
comment on function public.qbo_opening_candidates(text[], jsonb) is 'qbo-sync-2e-1d-1 창구(열쇠 qbo 쓰기 · 이견 3): EF 가 DocNumber in (…) 로 물은 번호 묶음(p_doc_numbers)과 그 QBO Invoice 행 전부(p_rows · Id · SyncToken · DocNumber · TxnDate · TotalAmt · Balance · CustomerRef)를 받아 이월 인보이스마다 자동 짝(qbo_opening_check 다섯 조건 → qbo_opening_record) · 못 지으면 qbo_opening_review 에 까닭 + 경고(같으면 안 쓴다 — 멱등) · 이미 선 것은 already · 빈 묶음 = 변화 0 · 쓰기는 자동 짝 + 되살리기뿐';

create function public.qbo_opening_match(p_invoice_id uuid, p_qbo_id text, p_row jsonb, p_ack boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_holder record; v_c jsonb; v_num text;
begin
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null then raise exception 'Pick the QuickBooks invoice to match — nothing was saved'; end if;
  if p_row is null or jsonb_typeof(p_row) <> 'object' then raise exception 'row must be the QuickBooks Invoice row read by id — nothing was saved'; end if;
  if btrim(coalesce(p_row->>'Id', '')) <> btrim(p_qbo_id) then raise exception 'The row given is QuickBooks Invoice #% — not #% — read it again', coalesce(p_row->>'Id', '?'), btrim(p_qbo_id); end if;
  select i.invoice_number into v_num from public.so_invoice i where i.id = p_invoice_id;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = p_invoice_id::text and t.voided_at is null;
  if v_t.id is not null then raise exception 'Invoice % is already matched to QuickBooks Invoice #% — unmatch it first — nothing was saved', coalesce(v_num, p_invoice_id::text), v_t.qbo_id; end if;
  select t.source, t.ims_id, i.invoice_number into v_holder from public.qbo_txn t left join public.so_invoice i on i.id::text = t.ims_id where t.realm_id = v_realm and t.qbo_type = 'Invoice' and t.qbo_id = btrim(p_qbo_id);
  if found then
    raise exception 'QuickBooks Invoice #% is already % IMS invoice % — % — nothing was saved', btrim(p_qbo_id), case when v_holder.source = 'sent' then 'the one IMS sent for' else 'matched to' end, coalesce(v_holder.invoice_number, v_holder.ims_id),
      case when v_holder.source = 'sent' then 'it cannot be matched again' else 'unmatch that one first' end;
  end if;
  v_c := public.qbo_opening_check(p_invoice_id, jsonb_build_array(p_row), btrim(p_qbo_id));
  if not (v_c->>'ok')::boolean and not coalesce(p_ack, false) then
    raise exception 'QuickBooks Invoice #% does not look like IMS invoice %: % — confirm to match it anyway — nothing was saved', btrim(p_qbo_id), v_num, v_c->>'warning';
  end if;
  return public.qbo_opening_record(p_invoice_id, 'manual', v_c, v_staff, case when not (v_c->>'ok')::boolean then v_c->>'warning' end) || jsonb_build_object('acked', not (v_c->>'ok')::boolean, 'warning', case when not (v_c->>'ok')::boolean then v_c->>'warning' end);
end;
$$;
comment on function public.qbo_opening_match(uuid, text, jsonb, boolean) is 'qbo-sync-2e-1d-1 창구(열쇠 qbo 쓰기 · 이견 10): 사람 짝 — QBO Id + EF 가 Id 로 읽은 행(p_row) · 이미 선 인보이스 · 다른 IMS 인보이스가 쥔 QBO Id 는 사람 글로 거부 · 검사 넷(docnumber · customer · total · balance)이 어긋나면 p_ack 없이 거부 · ack 면 경고를 review.warning 에 남기고 matched manual + requeue';

create function public.qbo_opening_unmatch(p_invoice_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_t public.qbo_txn%rowtype; v_num text; v_sent text; v_n int := 0;
begin
  select i.invoice_number into v_num from public.so_invoice i where i.id = p_invoice_id;
  if v_num is null then raise exception 'No IMS invoice % — nothing was changed', p_invoice_id; end if;
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = p_invoice_id::text and t.voided_at is null;
  if v_t.id is null then raise exception 'Invoice % has no QuickBooks match — nothing to undo', v_num; end if;
  if v_t.source <> 'matched' then raise exception 'Invoice % was sent to QuickBooks by IMS (#%) — that link is not undone here — nothing was changed', v_num, v_t.qbo_id; end if;
  select string_agg(t.qbo_id, ', ') into v_sent from public.qbo_txn t                                   -- 이견 8: 보낸 것이 서 있으면 거부
    where t.realm_id = v_realm and t.voided_at is null
      and ((t.ims_kind = 'payment' and t.ims_id in (select a.payment_id::text from public.so_payment_alloc a where a.invoice_id = p_invoice_id))
        or (t.ims_kind = 'credit_alloc' and t.ims_id in (select ca.id::text from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id)));
  if v_sent is not null then raise exception 'A payment or credit application on invoice % is already in QuickBooks (Payment #%) — undo it in IMS and let the void reach QuickBooks first — nothing was changed', v_num, v_sent; end if;
  if exists (select 1 from public.qbo_job j where j.realm_id = v_realm and j.state in ('sending', 'unknown')
              and ((j.kind in ('payment', 'payment_void') and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a where a.invoice_id = p_invoice_id))
                or (j.kind in ('credit_apply', 'credit_apply_void') and j.ims_id in (select ca.id::text from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id)))) then
    raise exception 'A payment or credit application on invoice % is being sent to QuickBooks right now — wait until it settles, then try again — nothing was changed', v_num;
  end if;
  update public.qbo_job j set state = 'failed', claimed_at = null, blocked_by = null, updated_by = v_staff,                                          -- 이견 8: 안 나간 일감은 failed 로 되돌린다
         last_error = left(format('Invoice %s was unmatched from QuickBooks — match it again under Settings → QuickBooks → Opening invoices and this job then goes by itself', v_num), 2000)
   where j.realm_id = v_realm and j.state in ('queued', 'blocked')
     and ((j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null))
       or (j.kind = 'credit_apply' and j.ims_kind = 'credit_alloc' and j.ims_id in (select ca.id::text from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id and ca.voided_at is null)));
  get diagnostics v_n = row_count;
  delete from public.qbo_txn t where t.id = v_t.id and t.source = 'matched';                                                                        -- 이견 1 A: matched 행은 지운다(UNIQUE 둘이 voided 행을 막는다)
  insert into public.qbo_opening_review as rv (realm_id, invoice_id, checked_at, reason, warning, qbo_rows, unmatched_at, unmatched_by, unmatched_snapshot, unmatched_note, updated_by)
  values (v_realm, p_invoice_id, null, 'unmatched', null, '[]'::jsonb, now(), v_staff, jsonb_build_object('qbo_id', v_t.qbo_id, 'match_how', v_t.match_how, 'matched_at', v_t.sent_at, 'matched_by', v_t.updated_by, 'snapshot', v_t.match_snapshot), nullif(btrim(coalesce(p_note, '')), ''), v_staff)
  on conflict (realm_id, invoice_id) do update set reason = 'unmatched', warning = null, unmatched_at = now(), unmatched_by = excluded.unmatched_by, unmatched_snapshot = excluded.unmatched_snapshot, unmatched_note = excluded.unmatched_note, updated_by = excluded.updated_by;
  return jsonb_build_object('invoice_id', p_invoice_id, 'invoice_number', v_num, 'qbo_id', v_t.qbo_id, 'match_how', v_t.match_how, 'jobs_failed', v_n);
end;
$$;
comment on function public.qbo_opening_unmatch(uuid, text) is 'qbo-sync-2e-1d-1 창구(열쇠 qbo 쓰기 · 이견 1 A · 8): 짝 풀기 — sent 행은 거부 · 이 인보이스에 붙은 결제 · 크레딧 붙임이 QBO 에 서 있거나(활성 qbo_txn) 보내는 중(sending · unknown)이면 거부 · queued · blocked 일감은 failed(last_error 「was unmatched」) · matched 행 삭제 · review 에 unmatched + 흔적(snapshot · note)';

create function public.qbo_opening_list() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_rows jsonb; v_sum jsonb;
begin
  with inv as (
    select i.id, i.invoice_number, i.issued_on, i.currency_code, i.total, coalesce(i.prior_settled, 0) as prior_settled, i.bill_to_customer_id, i.bill_to_name, i.legacy_invoice_id,
           public.so_invoice_store(i.id) as store_id, public.so_invoice_remaining(i.id) as remaining
      from public.so_invoice i where i.kind = 'opening' and i.status = 'issued'),
  pay as (
    select a.invoice_id, jsonb_agg(jsonb_build_object('payment_id', p.id, 'amount', a.amount, 'payment_amount', p.amount, 'method', p.method, 'paid_on', p.paid_on, 'reference', p.reference,
                                                      'job_state', coalesce(j.state, 'none'), 'job_error', j.last_error, 'job_id', j.id, 'remaining', public.qbo_opening_remaining(p.id),
                                                      'in_qbo', exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'payment' and t.ims_id = p.id::text and t.voided_at is null))
                                   order by p.paid_on, p.created_at) as items,
           count(*) as n, coalesce(sum(a.amount), 0) as amount
      from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
      left join lateral (select j.* from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id = p.id::text order by j.created_at desc, j.id desc limit 1) j on true
     where a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method <> 'opening' and a.invoice_id in (select id from inv) group by a.invoice_id),
  cr as (
    select ca.invoice_id, jsonb_agg(jsonb_build_object('alloc_id', ca.id, 'credit_id', c.id, 'credit_number', c.credit_number, 'amount', ca.amount, 'job_state', coalesce(j.state, 'none'), 'job_error', j.last_error, 'job_id', j.id,
                                                       'in_qbo', exists (select 1 from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit_alloc' and t.ims_id = ca.id::text and t.voided_at is null))
                                    order by ca.created_at) as items,
           count(*) as n, coalesce(sum(ca.amount), 0) as amount
      from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id
      left join lateral (select j.* from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit_apply' and j.ims_kind = 'credit_alloc' and j.ims_id = ca.id::text order by j.created_at desc, j.id desc limit 1) j on true
     where ca.voided_at is null and c.status = 'issued' and ca.invoice_id in (select id from inv) group by ca.invoice_id),
  one as (
    select inv.*, sc.name as store_name,
           t.id as txn_id, t.qbo_id, t.match_how, t.sent_at as matched_at, t.updated_by as matched_by, st.name as matched_by_name, t.match_snapshot,
           rv.checked_at, rv.reason, rv.warning, rv.qbo_rows, rv.unmatched_at, rv.unmatched_note,
           coalesce(pay.items, '[]'::jsonb) as payments, coalesce(pay.n, 0) as pay_n, coalesce(pay.amount, 0) as pay_amount,
           coalesce(cr.items, '[]'::jsonb) as credits, coalesce(cr.n, 0) as cr_n, coalesce(cr.amount, 0) as cr_amount
      from inv
      left join public.customer sc on sc.id = inv.store_id
      left join public.qbo_txn t on t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = inv.id::text and t.voided_at is null
      left join public.ims_staff st on st.id = t.updated_by
      left join public.qbo_opening_review rv on rv.realm_id = v_realm and rv.invoice_id = inv.id
      left join pay on pay.invoice_id = inv.id
      left join cr on cr.invoice_id = inv.id)
  select coalesce(jsonb_agg(jsonb_build_object('invoice_id', o.id, 'invoice_number', o.invoice_number, 'issued_on', o.issued_on, 'currency_code', o.currency_code, 'total', o.total, 'prior_settled', o.prior_settled, 'remaining', o.remaining,
                                               'bill_to_customer_id', o.bill_to_customer_id, 'bill_to_name', o.bill_to_name, 'store_customer_id', o.store_id, 'store_name', o.store_name, 'legacy_invoice_id', o.legacy_invoice_id,
                                               'match', case when o.txn_id is null then 'none' else o.match_how end, 'qbo_id', o.qbo_id, 'matched_at', o.matched_at, 'matched_by', o.matched_by, 'matched_by_name', o.matched_by_name, 'snapshot', o.match_snapshot,
                                               'checked_at', o.checked_at, 'reason', o.reason, 'warning', o.warning, 'candidates', o.qbo_rows, 'unmatched_at', o.unmatched_at, 'unmatched_note', o.unmatched_note,
                                               'pay_count', o.pay_n, 'pay_amount', o.pay_amount, 'credit_count', o.cr_n, 'credit_amount', o.cr_amount, 'payments', o.payments, 'credits', o.credits,
                                               'jobs', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select x->>'job_state' as k, count(*) as n from jsonb_array_elements(o.payments || o.credits) x group by 1) s))
                            order by o.invoice_number), '[]'::jsonb),
         jsonb_build_object('invoices', count(*), 'matched_auto', count(*) filter (where o.match_how = 'auto'), 'matched_manual', count(*) filter (where o.match_how = 'manual'), 'unmatched', count(*) filter (where o.txn_id is null),
                            'review', count(*) filter (where o.txn_id is null and o.reason is not null), 'never_checked', count(*) filter (where o.txn_id is null and o.checked_at is null),
                            'with_attachments', count(*) filter (where o.pay_n + o.cr_n > 0), 'with_attachments_unmatched', count(*) filter (where o.txn_id is null and o.pay_n + o.cr_n > 0))
    into v_rows, v_sum from one o;
  return jsonb_build_object('realm_id', v_realm, 'summary', v_sum, 'rows', v_rows);
end;
$$;
comment on function public.qbo_opening_list() is 'qbo-sync-2e-1d-1 창구(열쇠 qbo:read 보기 · 이견 9 · jsonb 한 행): 이월 인보이스(issued) 전부 — 번호 · 청구처 · 매장 · total · prior_settled · remaining · 컷 뒤 붙임(결제 · 크레딧 수 · 합 · 줄마다 일감 상태 · 글 · 남은 이월 장) · jobs(상태별 수 · none = 일감 없음) · 짝(none | auto | manual · QBO Id · 언제 · 누가 · snapshot) · 검토(checked_at · reason · warning · candidates · 풀림) · summary — 화면 1d-3 이 읽는다';

-- ═══ ④ 재발행 ═══
-- qbo_payment_requeue — 원본 2e-2-1 `20261103200000` 267 ~ 289 행 바이트(md5 9a691814…) + 결제 가지 두 줄(sync · failed → queued) → qbo_payment_requeue_one 한 줄(이견 6) · 크레딧 붙임 가지 · 서명 · 반환 그대로
create or replace function public.qbo_payment_requeue(p_invoice_id uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_n int := 0; v_num text;
begin
  select i.invoice_number into v_num from public.so_invoice i where i.id = p_invoice_id;
  for r in select distinct a.payment_id, p.created_by from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
            where a.invoice_id = p_invoice_id and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method <> 'opening' loop
    perform public.qbo_payment_requeue_one(r.payment_id, r.created_by, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks');   -- 2e-1d-1 이견 6: 남은 이월 장 0 일 때만 sync + failed → queued · 아니면 failed 그대로(글 「N carried-over …」)
    v_n := v_n + 1;
  end loop;
  for r in select a.id, a.created_by from public.so_credit_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null order by a.created_at, a.id loop   -- 2e-2-1 판정 1016: 이 인보이스에 붙은 활성 크레딧 붙임도(일감 없으면 만든다 · failed 는 되살린다)
    perform public.qbo_credit_alloc_sync(r.id, r.created_by);
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: invoice ' || coalesce(v_num, '?') || ' is now matched in QuickBooks'), 2000)
     where j.kind = 'credit_apply' and j.ims_kind = 'credit_alloc' and j.ims_id = r.id::text and j.state = 'failed';
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_payment_requeue(uuid) is 'qbo-sync-2e-1b A-3 · [2e-2-1 판정 1016: 활성 크레딧 붙임도 — qbo_credit_alloc_sync(일감 없으면 만든다) + failed credit_apply 를 queued 로] · [2e-1d-1 이견 6: 결제는 qbo_payment_requeue_one — 그 결제가 붙은 이월 · since 전 인보이스가 모두 짝이 섰을 때만 sync + failed → queued · 아니면 failed 그대로 · 글 「N carried-over invoice(s) …」](속 · grant 0 · qbo_opening_record 가 부른다): 돌려주는 것 = 결제 수 + 크레딧 붙임 수';

-- qbo_link_set — 원본 1a `20261101210000` 265 ~ 286 행 바이트(md5 0fce7411…) + declare v_rq · payment_method 가지 한 줄 · 반환에 requeued(판정 1039 · 이견 7) · 서명 그대로(create or replace · ACL 그대로)
create or replace function public.qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_ims record; v_ent public.qbo_entity%rowtype; v_other record; v_l public.qbo_link%rowtype; v_rq int := 0;
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
  if p_kind = 'payment_method' then v_rq := public.qbo_payment_method_requeue(p_ims_id, v_staff); end if;   -- 2e-1d-1 판정 1039: 수단 짝이 서면 그 수단의 failed 결제 일감을 queued 로(남은 이월 장 > 0 은 건너뛴다)
  return to_jsonb(v_l) || jsonb_build_object('ims_name', v_ims.ims_name, 'ims_code', v_ims.ims_code, 'qbo_name', v_ent.name, 'qbo_active', v_ent.active, 'requeued', v_rq);
end;
$$;
comment on function public.qbo_link_set(text, text, text) is 'qbo-sync-1a 창구(열쇠 qbo 쓰기 · 2a) · [2e-1d-1 판정 1039: payment_method 짝이 서면 qbo_payment_method_requeue — 그 수단의 failed 결제 일감을 queued 로 · 반환 requeued]: 사람 짝 — qbo_entity 에 있는 Id 만 · 사라진 것 거부 · 같은 QBO Id 의 다른 IMS 짝 거부(tax_rule 만 N:1) · 같은 IMS 행은 덮어쓴다(manual)';

-- ═══ ⑤ grant · 착지 ═══
revoke all on function public.qbo_opening_slim(jsonb), public.qbo_opening_num(text), public.qbo_opening_check(uuid, jsonb, text), public.qbo_opening_remaining(uuid), public.qbo_payment_requeue_one(uuid, uuid, text),
  public.qbo_payment_method_requeue(text, uuid), public.qbo_opening_record(uuid, text, jsonb, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.qbo_opening_candidates(text[], jsonb), public.qbo_opening_match(uuid, text, jsonb, boolean), public.qbo_opening_unmatch(uuid, text), public.qbo_opening_list()
  from public, anon, service_role;
grant execute on function public.qbo_opening_candidates(text[], jsonb), public.qbo_opening_match(uuid, text, jsonb, boolean), public.qbo_opening_unmatch(uuid, text), public.qbo_opening_list() to authenticated;
do $$
begin
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-1d-1: source matched 행 = 이월 인보이스 ↔ QBO Invoice 짝(match_how auto | manual · match_snapshot · job_id null · 풀기는 행 삭제 — 이견 1 A · UNIQUE 둘이 voided 행을 막는다)');
end $$;
do $$
declare v text; v_bad text := '';
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_opening_slim', 'qbo_opening_num', 'qbo_opening_check', 'qbo_opening_remaining', 'qbo_payment_requeue_one', 'qbo_payment_method_requeue', 'qbo_opening_record',
                                                                                     'qbo_opening_candidates', 'qbo_opening_match', 'qbo_opening_unmatch', 'qbo_opening_list', 'qbo_payment_requeue', 'qbo_link_set');
  if v <> 'qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text)={postgres=X/postgres,authenticated=X/postgres} qbo_opening_candidates(p_doc_numbers text[], p_rows jsonb)={postgres=X/postgres,authenticated=X/postgres} qbo_opening_check(p_invoice_id uuid, p_rows jsonb, p_qbo_id text)={postgres=X/postgres} qbo_opening_list()={postgres=X/postgres,authenticated=X/postgres} qbo_opening_match(p_invoice_id uuid, p_qbo_id text, p_row jsonb, p_ack boolean)={postgres=X/postgres,authenticated=X/postgres} qbo_opening_num(p text)={postgres=X/postgres} qbo_opening_record(p_invoice_id uuid, p_how text, p_check jsonb, p_staff uuid, p_ack_warning text)={postgres=X/postgres} qbo_opening_remaining(p_payment_id uuid)={postgres=X/postgres} qbo_opening_slim(p_row jsonb)={postgres=X/postgres} qbo_opening_unmatch(p_invoice_id uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres} qbo_payment_method_requeue(p_method text, p_by uuid)={postgres=X/postgres} qbo_payment_requeue(p_invoice_id uuid)={postgres=X/postgres} qbo_payment_requeue_one(p_payment_id uuid, p_by uuid, p_note text)={postgres=X/postgres}' then
    raise exception '⑤ ACL unexpected: %', v;
  end if;
  if (select relacl::text || ':' || relrowsecurity::text from pg_class where oid = 'public.qbo_opening_review'::regclass) <> '{postgres=arwdDxtm/postgres}:true' then raise exception '⑤ qbo_opening_review ACL / RLS unexpected'; end if;
  if (select count(*) from pg_constraint where conname = 'qbo_txn_match_ck') <> 1 then raise exception '⑤ qbo_txn_match_ck missing'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')      is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')      is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_apply_body') is distinct from '08b17e793b3ec596b8b077de0ae719bc' then v_bad := v_bad || ' qbo_credit_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync') is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')         is distinct from '9c7890b8833396d63568e056965d8a3c' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')          is distinct from 'fc2d42c04bd2c0b9689dae6111cd3a55' then v_bad := v_bad || ' qbo_job_done'; end if;
  if v_bad <> '' then raise exception '⑤ functions changed by this migration (must not):%', v_bad; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_requeue') = '9a691814b021d4927d5d9b17179ab78d' then raise exception '⑤ qbo_payment_requeue was not re-issued'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_link_set') = '0fce741132f19fb9e76fb45ac56ff7e3' then raise exception '⑤ qbo_link_set was not re-issued'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_requeue', 'qbo_link_set')) <> 2 then raise exception '⑤ overloads'; end if;
  raise notice '⑤ qbo-sync-2e-1d-1 landed: qbo_txn.match_how · match_snapshot · qbo_opening_review · creatures 4 · inner 7 · re-issued 2 — carried-over invoices: % issued · % with post-cutover attachments and no match yet',
    (select count(*) from public.so_invoice i where i.kind = 'opening' and i.status = 'issued'),
    (select count(*) from public.so_invoice i where i.kind = 'opening' and i.status = 'issued'
       and not exists (select 1 from public.qbo_txn t where t.ims_kind = 'invoice' and t.ims_id = i.id::text and t.voided_at is null)
       and (exists (select 1 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = i.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment' and p.method <> 'opening')
         or exists (select 1 from public.so_credit_alloc ca where ca.invoice_id = i.id and ca.voided_at is null)));
end $$;
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e1d_1_check.sql(-v mig 없이) → REST 한 번(열쇠 qbo 인 JWT 로 qbo_opening_candidates([] · []) → 변화 0) → 1d-2(EF KEY_ACTIONS opening_candidates · opening_read) → 1d-3(화면)
