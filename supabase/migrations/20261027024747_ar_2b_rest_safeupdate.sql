-- ar-2b (2026-10-27 UTC · 판정 789): so_opening_load 가 REST(PostgREST · authenticator 역할 · safeupdate)에서 21000 「UPDATE requires a WHERE clause」 로 막혔다 — WHERE 없는 update 넷에 WHERE 를 더해 재발행
-- 실사고 2026-10-26 밤: ImsLoadOpening.gs iloDry → rpc so_opening_load HTTP 400 {"code":"21000","message":"UPDATE requires a WHERE clause"} · 한 트랜잭션이라 아무것도 쓰이지 않았다
-- 원인: ar-2(20261027014202) 의 so_opening_load 에서 임시 표 전체에 판정 칸(reason · action)을 채우는 update 넷이 WHERE 없이 쓰였다 — psql 직결 시험은 safeupdate 를 못 실어(load · PGOPTIONS 막힘) 잡지 못했다(so-module §72-e 1 재발)
-- 전수(ar-2 함수 7 · hcr-1 함수 7 의 마지막 정의 · 임시 표 · CTE 포함 · 깊이 0 WHERE 로 셈): 걸린 것은 so_opening_load 의 update 넷뿐 · delete 0 · 다른 함수 0
-- 고침: 마지막 정의(= 운영 · 테스트 DB prosrc md5 aaede92b5c07d3a68ce7461bb44126d6) 바이트 위에 WHERE 만 더한다 — 뜻 무변(넷 모두 「막 채운 임시 표의 모든 행」 · 그 시점에 reason · action 은 전부 null 이므로 `is null` 이 곧 모든 행) · ACL · comment 그대로
--   ① ar2_inv.reason   … end where i.reason is null;
--   ② ar2_inv.action   … else 'update' end where i.action is null;
--   ③ ar2_cr.reason    … end where r.reason is null;
--   ④ ar2_crg.action   … end where g.action is null;
-- 시험: psql 은 safeupdate 를 못 싣는다 → 정적 셈(supabase/tests/ar_2b_check.sql · 깊이 0 WHERE 스캐너 · 고치기 전 4 → 뒤 0) + service_role 로 같은 입력 dry · apply 결과 무변 · 실제 REST 통과는 테스트 프로젝트 REST 를 curl 로(회신)
-- 적용(Caleb · 테스트 DB): PGOPTIONS="-c lock_timeout=5s" psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261027024747_ar_2b_rest_safeupdate.sql && supabase migration repair --status applied 20261027024747 --db-url "$(cat ~/.asung-testdb-url)"
-- ⚠️ 운영(asung-WMS)에는 전환일까지 db push 금지(CLAUDE.md §2) · 이 파일은 so_opening_load 하나만 다시 만든다(표 · 제약 · 다른 함수 · doc_* 무접촉)

create or replace function public.so_opening_load(p jsonb, p_dry boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- ar-2 판정 775 · 783 ~ 786: 컷오버 날 이월 적재 — Apps Script(ar-3)가 service_role 로 부른다(한 번에 invoices ≤ 500 · credits ≤ 500 · 실측 ar-2 회신) · 자리 = reload-procedure §P 12b(거래 지우기 5 뒤 · 마스터 8 뒤 · cron 13 앞)
-- 입력 p = {as_of?: date(기본 ims_today · 이월 결제의 paid_on · 발행일이 이 날 뒤면 거부), complete?: bool(true 면 「입력에 없는 기존 이월 줄」 도 보고 — 지우지는 않는다),
--           invoices?: [{legacy_sale_id!, legacy_invoice_id!, invoice_number!(숫자 5 자리 이상), cin7_customer_id!(customer.cin7_id), issued_on!, due_on?, payment_term_name?, currency!(code), total_before_tax!, tax!, total!, prior_settled?(기본 0)}],
--           credits?:  [{cin7_customer_id!, currency!(code), amount!(> 0), source!(credit | overpay), reference?}]}
-- 판단(Dry 와 Apply 가 같은 길): ① 풀기 — 손님 cin7_id · 통화 code · 결제조건 name(못 찾으면 이름만 · 기한은 입력값) · 계정 _1150040009_(없으면 전체 멈춤) · 브랜치 = 손님 default_location_id
--   ② 인보이스 — 옛 열쇠 legacy_invoice_id 로 기존 opening 줄을 찾는다 · 같으면 same · 다르면 update · 없으면 insert · IMS 붙임(활성 결제 · 크레딧 alloc)이 있으면 바뀐 줄은 거부(784)
--      금액 = lines_amount(= Total − Tax) · tax · total · amount_due = total · prior_settled(이전에 받은 돈) · 남은 금액 = total − prior_settled(so_invoice_remaining) · 번호는 옛 번호를 명시로(시퀀스 무변) · issued_by null · 오더 없음
--   ③ 받아 둔 돈 — 유효 줄을 (청구처 = coalesce(default_bill_to_customer_id, id), 통화) 로 합쳐 so_payment 한 줄(kind payment · method opening · paid_on as_of · 계정 _1150040009_ · 브랜치 = 매장의 위치 칸(없으면 청구처의) · note 에 출처 글 + 매장 이름) · 기존 줄은 금액 같으면 same · 다르면 update · IMS 붙임(alloc) · 그 손님 · 통화의 IMS 환불이 있으면 거부
--   ④ p_dry 면 판단 결과만 돌려주고 아무것도 쓰지 않는다(임시 표만) · 반환 jsonb: invoices{in, inserted, updated, same, rejected, rejects[], by_currency[], customer_unresolved, term_unresolved, before_tax_adjusted, existing_not_in_input} · credits{rows_in, groups, inserted, updated, same, rejected, rejects[], by_currency[], customer_unresolved, branch_unresolved, large[], existing_not_in_input} · account · ms
-- ⚠️ REST(authenticator · safeupdate): WHERE 없는 delete · update 없음 · 임시 표는 truncate
declare
  v_t0      timestamptz := clock_timestamp();
  v_as_of   date;
  v_complete boolean;
  v_acct    public.ref_account%rowtype;
  v_today   date := public.ims_today();
  x         jsonb;
  v_seq     int := 0;
  v_n       int;
  v_ids     text[];
  v_inv     record;
  v_cr      record;
  v_out     jsonb;
  v_inv_out jsonb;
  v_cr_out  jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object {as_of?, complete?, invoices?: [...], credits?: [...]} — nothing was saved'; end if;
  if p ? 'invoices' and jsonb_typeof(p->'invoices') <> 'array' then raise exception 'invoices must be a JSON array — nothing was saved'; end if;
  if p ? 'credits' and jsonb_typeof(p->'credits') <> 'array' then raise exception 'credits must be a JSON array — nothing was saved'; end if;
  if coalesce(jsonb_array_length(p->'invoices'), 0) > 500 then raise exception 'Too many invoices in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p->'invoices'); end if;
  if coalesce(jsonb_array_length(p->'credits'), 0) > 500 then raise exception 'Too many credits in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p->'credits'); end if;
  v_as_of := coalesce(nullif(p->>'as_of', '')::date, v_today);
  if v_as_of > v_today then raise exception 'as_of % is in the future — nothing was saved', v_as_of; end if;
  v_complete := coalesce((p->>'complete')::boolean, false);
  select * into v_acct from public.ref_account a where a.code = '_1150040009_';
  if v_acct.id is null or not v_acct.is_active then raise exception 'Account _1150040009_ (Customer Credits — 판정 786) is missing or inactive in ref_account — nothing was saved'; end if;

  -- 임시 표(세션 전용 · 트랜잭션 끝에 사라진다 · 쪽마다 truncate)
  if to_regclass('pg_temp.ar2_inv') is null then
    create temp table ar2_inv (seq int, legacy_sale_id text, legacy_invoice_id text, invoice_number text, cin7_customer_id uuid, store_id uuid, store_name text, bill_to_id uuid, bill_to_name text,
                               issued_on date, due_on date, term_name text, term_id uuid, currency_code text, currency_id uuid, before_tax numeric, tax numeric, total numeric, prior_settled numeric,
                               lines_amount numeric, btx_adj numeric, existing_id uuid, action text, reason text) on commit drop;
    create temp table ar2_cr  (seq int, cin7_customer_id uuid, store_id uuid, store_name text, store_warehouse_id uuid, customer_id uuid, customer_name text, currency_code text, currency_id uuid, amount numeric, source text, reference text, reason text) on commit drop;
    create temp table ar2_crg (customer_id uuid, customer_name text, currency_id uuid, currency_code text, amount numeric, n int, note text, warehouse_id uuid, warehouse_name text, existing_id uuid, action text, reason text) on commit drop;
  end if;
  truncate ar2_inv;  truncate ar2_cr;  truncate ar2_crg;

  -- ── ① 인보이스 줄 풀기 ──
  for x in select t from jsonb_array_elements(coalesce(p->'invoices', '[]'::jsonb)) t loop
    v_seq := v_seq + 1;
    insert into ar2_inv (seq, legacy_sale_id, legacy_invoice_id, invoice_number, cin7_customer_id, issued_on, due_on, term_name, currency_code, before_tax, tax, total, prior_settled)
    values (v_seq, nullif(btrim(x->>'legacy_sale_id'), ''), nullif(btrim(x->>'legacy_invoice_id'), ''), nullif(btrim(x->>'invoice_number'), ''),
            nullif(btrim(x->>'cin7_customer_id'), '')::uuid, nullif(x->>'issued_on', '')::date, nullif(x->>'due_on', '')::date, nullif(btrim(x->>'payment_term_name'), ''),
            upper(nullif(btrim(x->>'currency'), '')), nullif(x->>'total_before_tax', '')::numeric, nullif(x->>'tax', '')::numeric, nullif(x->>'total', '')::numeric, coalesce(nullif(x->>'prior_settled', '')::numeric, 0));
  end loop;
  update ar2_inv i set store_id = c.id, store_name = c.name, bill_to_id = coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.cin7_id = i.cin7_customer_id;
  update ar2_inv i set bill_to_name = b.name from public.customer b where b.id = i.bill_to_id;
  update ar2_inv i set currency_id = rc.id from public.ref_currency rc where rc.code = i.currency_code and rc.is_active;
  update ar2_inv i set term_id = (select pt.id from public.ref_payment_term pt where lower(btrim(pt.name)) = lower(i.term_name) order by pt.is_active desc, pt.name, pt.id limit 1) where i.term_name is not null;   -- 이름 자연키 · 같은 이름이 여럿이면 활성 먼저
  update ar2_inv i set term_name = pt.name from public.ref_payment_term pt where pt.id = i.term_id;
  update ar2_inv i set due_on = i.issued_on + pt.net_days from public.ref_payment_term pt where pt.id = i.term_id and i.due_on is null and i.issued_on is not null and pt.net_days is not null;
  update ar2_inv i set lines_amount = round(i.total - i.tax, 2), btx_adj = round(i.total - i.tax, 2) - round(i.before_tax, 2) where i.total is not null and i.tax is not null and i.before_tax is not null;
  update ar2_inv i set existing_id = e.id from public.so_invoice e where e.kind = 'opening' and e.legacy_invoice_id = i.legacy_invoice_id;
  -- 거부 이유(첫 이유 하나만)
  update ar2_inv i set reason = case
    when i.legacy_sale_id is null or i.legacy_invoice_id is null then 'legacy_key_missing'
    when i.invoice_number is null or i.invoice_number !~ '^[0-9]{5,}$' then 'number_invalid'
    when i.cin7_customer_id is null then 'customer_id_missing'
    when i.store_id is null then 'customer_unresolved'
    when i.currency_id is null then 'currency_unresolved'
    when i.issued_on is null then 'issued_on_missing'
    when i.issued_on > v_as_of then 'issued_on_future'
    when i.before_tax is null or i.tax is null or i.total is null then 'amount_missing'
    when i.total <> round(i.total, 2) or i.tax <> round(i.tax, 2) or i.prior_settled <> round(i.prior_settled, 2) then 'amount_decimals'
    when i.total <= 0 then 'total_invalid'
    when i.prior_settled < 0 then 'prior_settled_negative'
    when i.prior_settled >= i.total then 'nothing_remaining'
    when abs(round(i.before_tax, 2) + round(i.tax, 2) - round(i.total, 2)) > 0.05 then 'total_mismatch'
    when exists (select 1 from ar2_inv d where d.legacy_invoice_id = i.legacy_invoice_id and d.seq < i.seq) then 'duplicate_in_input'
    when exists (select 1 from ar2_inv d where d.invoice_number = i.invoice_number and d.seq < i.seq) then 'number_duplicate_in_input'
    when exists (select 1 from public.so_invoice e where e.invoice_number = i.invoice_number and e.id is distinct from i.existing_id) then 'number_taken'
    end where i.reason is null;
  -- 같음 · 바뀜 · 넣음 · IMS 붙임이 있는 바뀜은 거부
  update ar2_inv i set action = case
    when i.reason is not null then 'reject'
    when i.existing_id is null then 'insert'
    when exists (select 1 from public.so_invoice e where e.id = i.existing_id
                   and e.invoice_number = i.invoice_number and e.store_customer_id = i.store_id and e.bill_to_customer_id = i.bill_to_id
                   and e.issued_on = i.issued_on and e.due_on is not distinct from i.due_on and e.payment_term_id is not distinct from i.term_id and e.payment_term_name is not distinct from i.term_name
                   and e.currency_id = i.currency_id and e.lines_amount = i.lines_amount and e.tax_amount = i.tax and e.total = i.total and e.prior_settled = i.prior_settled
                   and e.legacy_sale_id = i.legacy_sale_id and e.status = 'issued') then 'same'
    else 'update' end where i.action is null;
  update ar2_inv i set action = 'reject', reason = 'has_ims_allocations' where i.action = 'update'
    and (exists (select 1 from public.so_payment_alloc a join public.so_payment pm on pm.id = a.payment_id where a.invoice_id = i.existing_id and a.voided_at is null and pm.status = 'active')
      or exists (select 1 from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id where ca.invoice_id = i.existing_id and ca.voided_at is null and c.status = 'issued'));
  update ar2_inv i set action = 'reject', reason = 'cancelled_in_ims' where i.action = 'update' and exists (select 1 from public.so_invoice e where e.id = i.existing_id and e.status <> 'issued');

  -- ── ② 받아 둔 돈 줄 풀기 → (손님, 통화) 묶기 ──
  v_seq := 0;
  for x in select t from jsonb_array_elements(coalesce(p->'credits', '[]'::jsonb)) t loop
    v_seq := v_seq + 1;
    insert into ar2_cr (seq, cin7_customer_id, currency_code, amount, source, reference)
    values (v_seq, nullif(btrim(x->>'cin7_customer_id'), '')::uuid, upper(nullif(btrim(x->>'currency'), '')), nullif(x->>'amount', '')::numeric, lower(nullif(btrim(x->>'source'), '')), nullif(btrim(x->>'reference'), ''));
  end loop;
  update ar2_cr r set store_id = c.id, store_name = c.name, store_warehouse_id = c.default_location_id, customer_id = coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.cin7_id = r.cin7_customer_id;   -- 돈은 청구처 앞으로(결제의 손님 = 청구처 · 발행 때 자동 소진 · 잔액이 보는 손님) · 매장 이름은 note 에
  update ar2_cr r set customer_name = b.name from public.customer b where b.id = r.customer_id;
  update ar2_cr r set currency_id = rc.id from public.ref_currency rc where rc.code = r.currency_code and rc.is_active;
  update ar2_cr r set reason = case
    when r.cin7_customer_id is null then 'customer_id_missing'
    when r.customer_id is null then 'customer_unresolved'
    when r.currency_id is null then 'currency_unresolved'
    when r.amount is null or r.amount <= 0 then 'amount_invalid'
    when r.amount <> round(r.amount, 2) then 'amount_decimals'
    when r.source is null or r.source not in ('credit', 'overpay') then 'source_invalid'
    end where r.reason is null;
  insert into ar2_crg (customer_id, customer_name, currency_id, currency_code, amount, n, note)
  select r.customer_id, r.customer_name, r.currency_id, r.currency_code, sum(r.amount), count(*)::int,
         left(string_agg(r.source || ' ' || r.amount::text || coalesce(' — ' || r.reference, '') || case when r.store_id <> r.customer_id then ' (' || r.store_name || ')' else '' end, ' | ' order by r.seq), 2000)
    from ar2_cr r where r.reason is null group by r.customer_id, r.customer_name, r.currency_id, r.currency_code;
  update ar2_crg g set warehouse_id = w.id, warehouse_name = w.name from public.ref_warehouse w where w.is_active and w.id = (select r.store_warehouse_id from ar2_cr r where r.customer_id = g.customer_id and r.currency_id = g.currency_id and r.reason is null and r.store_warehouse_id is not null order by r.seq limit 1);   -- 브랜치 = 매장(이전 시스템의 손님)의 위치 칸 · 첫 줄
  update ar2_crg g set warehouse_id = w.id, warehouse_name = w.name from public.customer c join public.ref_warehouse w on w.id = c.default_location_id and w.is_active where c.id = g.customer_id and g.warehouse_id is null;   -- 없으면 청구처의 위치 칸 · 그것도 없으면 거부
  update ar2_crg g set existing_id = pm.id from public.so_payment pm where pm.customer_id = g.customer_id and pm.currency_id = g.currency_id and pm.method = 'opening';
  update ar2_crg g set action = case
    when g.warehouse_id is null then 'reject'
    when g.existing_id is null then 'insert'
    when exists (select 1 from public.so_payment pm where pm.id = g.existing_id and pm.status = 'active' and pm.amount = g.amount and pm.note is not distinct from g.note and pm.paid_on = v_as_of) then 'same'
    else 'update' end,
    reason = case when g.warehouse_id is null then 'branch_unresolved' end where g.action is null;
  update ar2_crg g set action = 'reject', reason = 'has_ims_allocations' where g.action = 'update'
    and (exists (select 1 from public.so_payment_alloc a where a.payment_id = g.existing_id and a.voided_at is null)
      or exists (select 1 from public.so_payment pm where pm.customer_id = g.customer_id and pm.currency_id = g.currency_id and pm.kind = 'refund' and pm.status = 'active'));
  update ar2_crg g set action = 'reject', reason = 'voided_in_ims' where g.action = 'update' and exists (select 1 from public.so_payment pm where pm.id = g.existing_id and pm.status <> 'active');

  -- ── ③ 쓰기(Dry 가 아닐 때만 · 판단은 위에서 끝났다) ──
  if not p_dry then
    for v_inv in select * from ar2_inv i where i.action = 'insert' order by i.seq loop
      insert into public.so_invoice (invoice_number, status, kind, bill_to_customer_id, bill_to_name, store_customer_id, legacy_sale_id, legacy_invoice_id,
                                     issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code,
                                     lines_amount, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total,
                                     deposit_applied, credit_applied, balance_forward, amount_due, prior_settled)
      values (v_inv.invoice_number, 'issued', 'opening', v_inv.bill_to_id, v_inv.bill_to_name, v_inv.store_id, v_inv.legacy_sale_id, v_inv.legacy_invoice_id,
              v_inv.issued_on, null, v_inv.term_id, v_inv.term_name, v_inv.due_on, v_inv.currency_id, v_inv.currency_code,
              v_inv.lines_amount, 0, 0, 0, 0, v_inv.lines_amount, v_inv.tax, v_inv.total,
              0, 0, null, v_inv.total, v_inv.prior_settled);
    end loop;
    for v_inv in select * from ar2_inv i where i.action = 'update' order by i.seq loop
      update public.so_invoice set invoice_number = v_inv.invoice_number, bill_to_customer_id = v_inv.bill_to_id, bill_to_name = v_inv.bill_to_name, store_customer_id = v_inv.store_id, legacy_sale_id = v_inv.legacy_sale_id,
                                   issued_on = v_inv.issued_on, payment_term_id = v_inv.term_id, payment_term_name = v_inv.term_name, due_on = v_inv.due_on, currency_id = v_inv.currency_id, currency_code = v_inv.currency_code,
                                   lines_amount = v_inv.lines_amount, taxable_amount = v_inv.lines_amount, tax_amount = v_inv.tax, total = v_inv.total, amount_due = v_inv.total, prior_settled = v_inv.prior_settled
      where id = v_inv.existing_id and kind = 'opening';
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception 'Opening invoice % (legacy %) was not updated — nothing was saved', v_inv.invoice_number, v_inv.legacy_invoice_id; end if;
    end loop;
    for v_cr in select * from ar2_crg g where g.action = 'insert' loop
      insert into public.so_payment (kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, note, created_by, updated_by)
      values ('payment', v_cr.amount, v_as_of, 'opening', 'Opening balance ' || v_as_of::text, v_cr.customer_id, v_cr.currency_id, v_cr.currency_code, v_acct.id, v_acct.code, v_cr.warehouse_id, v_cr.warehouse_name, v_cr.note, null, null);
    end loop;
    for v_cr in select * from ar2_crg g where g.action = 'update' loop
      update public.so_payment set amount = v_cr.amount, paid_on = v_as_of, reference = 'Opening balance ' || v_as_of::text, note = v_cr.note, account_id = v_acct.id, account_code = v_acct.code, warehouse_id = v_cr.warehouse_id, warehouse_name = v_cr.warehouse_name
      where id = v_cr.existing_id and method = 'opening' and status = 'active';
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception 'Opening balance for customer % (%) was not updated — nothing was saved', v_cr.customer_name, v_cr.currency_code; end if;
    end loop;
  end if;

  -- ── ④ 반환 ──
  select array_agg(i.legacy_invoice_id) into v_ids from ar2_inv i where i.legacy_invoice_id is not null;
  v_inv_out := jsonb_build_object(
    'in',        (select count(*) from ar2_inv),
    'inserted',  (select count(*) from ar2_inv i where i.action = 'insert'),
    'updated',   (select count(*) from ar2_inv i where i.action = 'update'),
    'same',      (select count(*) from ar2_inv i where i.action = 'same'),
    'rejected',  (select count(*) from ar2_inv i where i.action = 'reject'),
    'rejects',   (select coalesce(jsonb_agg(jsonb_build_object('seq', i.seq, 'legacy_invoice_id', i.legacy_invoice_id, 'invoice_number', i.invoice_number, 'cin7_customer_id', i.cin7_customer_id, 'customer_name', i.store_name, 'reason', i.reason) order by i.seq), '[]'::jsonb) from ar2_inv i where i.action = 'reject'),
    'by_currency', (select coalesce(jsonb_agg(jsonb_build_object('currency_code', g.currency_code, 'count', g.n, 'total', g.tot, 'prior_settled', g.ps, 'remaining', g.tot - g.ps) order by g.currency_code), '[]'::jsonb)
                    from (select i.currency_code, count(*)::int n, sum(i.total) tot, sum(i.prior_settled) ps from ar2_inv i where i.action in ('insert', 'update', 'same') group by i.currency_code) g),
    'customer_unresolved', (select count(*) from ar2_inv i where i.reason = 'customer_unresolved'),
    'term_unresolved',     (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.term_id is null),
    'due_unknown',         (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.due_on is null),
    'before_tax_adjusted', jsonb_build_object('count', (select count(*) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.btx_adj <> 0), 'sum_abs', (select coalesce(sum(abs(i.btx_adj)), 0) from ar2_inv i where i.action in ('insert', 'update', 'same') and i.btx_adj <> 0)),
    'existing_not_in_input', case when v_complete then (select jsonb_build_object('count', count(*), 'invoice_numbers', coalesce(jsonb_agg(e.invoice_number order by e.invoice_number) filter (where e.invoice_number is not null), '[]'::jsonb))
                                                         from (select e.invoice_number from public.so_invoice e where e.kind = 'opening' and not (e.legacy_invoice_id = any(coalesce(v_ids, '{}'::text[]))) order by e.invoice_number limit 50) e)
                             else null end);
  v_cr_out := jsonb_build_object(
    'rows_in',   (select count(*) from ar2_cr),
    'groups',    (select count(*) from ar2_crg),
    'inserted',  (select count(*) from ar2_crg g where g.action = 'insert'),
    'updated',   (select count(*) from ar2_crg g where g.action = 'update'),
    'same',      (select count(*) from ar2_crg g where g.action = 'same'),
    'rejected',  (select count(*) from ar2_cr r where r.reason is not null) + (select count(*) from ar2_crg g where g.action = 'reject'),
    'rejects',   (select coalesce(jsonb_agg(j order by (j->>'seq')::int nulls last), '[]'::jsonb) from (
                    select jsonb_build_object('seq', r.seq, 'cin7_customer_id', r.cin7_customer_id, 'customer_name', r.customer_name, 'currency_code', r.currency_code, 'amount', r.amount, 'reason', r.reason) j from ar2_cr r where r.reason is not null
                    union all
                    select jsonb_build_object('seq', null, 'customer_id', g.customer_id, 'customer_name', g.customer_name, 'currency_code', g.currency_code, 'amount', g.amount, 'reason', g.reason) from ar2_crg g where g.action = 'reject') u),
    'by_currency', (select coalesce(jsonb_agg(jsonb_build_object('currency_code', g.currency_code, 'count', g.n, 'amount', g.amt) order by g.currency_code), '[]'::jsonb)
                    from (select g.currency_code, count(*)::int n, sum(g.amount) amt from ar2_crg g where g.action in ('insert', 'update', 'same') group by g.currency_code) g),
    'customer_unresolved', (select count(*) from ar2_cr r where r.reason = 'customer_unresolved'),
    'branch_unresolved',   (select count(*) from ar2_crg g where g.reason = 'branch_unresolved'),
    'large', (select coalesce(jsonb_agg(jsonb_build_object('customer_name', g.customer_name, 'currency_code', g.currency_code, 'amount', g.amount, 'note', g.note) order by g.amount desc), '[]'::jsonb) from ar2_crg g where g.action in ('insert', 'update', 'same') and g.amount >= 1000),
    'existing_not_in_input', case when v_complete then (select jsonb_build_object('count', count(*), 'customers', coalesce(jsonb_agg(jsonb_build_object('customer_name', c.name, 'currency_code', pm.currency_code, 'amount', pm.amount) order by c.name), '[]'::jsonb))
                                                         from public.so_payment pm join public.customer c on c.id = pm.customer_id
                                                         where pm.method = 'opening' and not exists (select 1 from ar2_crg g where g.customer_id = pm.customer_id and g.currency_id = pm.currency_id))
                             else null end);
  v_out := jsonb_build_object('dry', p_dry, 'as_of', v_as_of, 'complete', v_complete,
                              'account', jsonb_build_object('id', v_acct.id, 'code', v_acct.code, 'name', v_acct.name),
                              'invoices', v_inv_out, 'credits', v_cr_out,
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  return v_out;
end $fn$;
revoke all on function public.so_opening_load(jsonb, boolean) from public, anon, authenticated;
grant execute on function public.so_opening_load(jsonb, boolean) to service_role;
comment on function public.so_opening_load(jsonb, boolean) is 'ar-2 판정 775 · 783 ~ 786: 컷오버 날 이월 적재(service_role · Apps Script ar-3) — invoices[] → so_invoice kind opening(옛 번호 · 발행일 · 기한 · 금액 · prior_settled · 옛 열쇠) · credits[] → so_payment method opening(손님 · 통화별 한 줄 · 계정 _1150040009_ · 손님 브랜치) · 멱등(legacy_invoice_id · (customer, currency) 로 덮어쓰기 · IMS 붙임이 있으면 그 줄 거부) · p_dry true(기본) 는 같은 판단 · 쓰기 0 · 반환 jsonb 넣음 · 바뀜 · 같음 · 거부(이유) · 통화별 합 · 못 찾음(손님 · 결제조건 · 브랜치) · complete true 면 입력에 없는 기존 이월 줄도 보고(지우지 않는다)';

-- ═══ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load';
  if v_src is null then v_bad := v_bad || ' so_opening_load(missing)'; end if;
  if v_src not like '%end where i.reason is null;%' then v_bad := v_bad || ' where①(ar2_inv.reason)'; end if;
  if v_src not like '%else ''update'' end where i.action is null;%' then v_bad := v_bad || ' where②(ar2_inv.action)'; end if;
  if v_src not like '%end where r.reason is null;%' then v_bad := v_bad || ' where③(ar2_cr.reason)'; end if;
  if v_src not like '%''branch_unresolved'' end where g.action is null;%' then v_bad := v_bad || ' where④(ar2_crg.action)'; end if;
  if v_src like '%then ''number_taken''
    end;%' or v_src like '%else ''update'' end;%' or v_src like '%then ''source_invalid''
    end;%' or v_src like '%''branch_unresolved'' end;%' then v_bad := v_bad || ' old-statement-still-there'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') <> 1 then v_bad := v_bad || ' so_opening_load(count<>1)'; end if;
  if not (select prosecdef from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') then v_bad := v_bad || ' so_opening_load(not definer)'; end if;
  if has_function_privilege('authenticated', 'public.so_opening_load(jsonb, boolean)', 'execute') or has_function_privilege('anon', 'public.so_opening_load(jsonb, boolean)', 'execute') or not has_function_privilege('service_role', 'public.so_opening_load(jsonb, boolean)', 'execute') then v_bad := v_bad || ' so_opening_load(grants)'; end if;
  if coalesce(obj_description('public.so_opening_load(jsonb, boolean)'::regprocedure, 'pg_proc'), '') not like 'ar-2 판정 775 · 783 ~ 786%' then v_bad := v_bad || ' so_opening_load(comment)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM789', message = format('STOP - ar-2b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
