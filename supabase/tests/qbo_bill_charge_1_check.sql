-- supabase/tests/qbo_bill_charge_1_check.sql — qbo-bill-charge-1 검증 (2026-11-11 · 판정 1189 ~ 1192 · §0 이견 1 ~ 7 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 15335 꼴 · S2 설정 바꾸기 · S3 설정 계정 고장 · S4 돈 안 내는 줄 · S5 크레딧 · S6 goods 만 = 고치기 전 · S7 창구 문 · 거부 · S9 REST WHERE · G 구조 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111220003_qbo_bill_charge_1_supplier_line_accounts.sql -f supabase/tests/qbo_bill_charge_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 · 시험 갈래에만 도는 검사 = S0 설정 기본값 · S6b 재발행 md5)
--   ⚠️ 가짜 재료만(직원 zz-qbo-bill-charge-1-* · 공급처 ZZ-BC1 · PO-79441 · 문서 ZZBC1-* · 계정 _zzbc1_* · 거울 zzbc1v) — 실제 공급처 · 인보이스 · 계정 · 짝은 읽기만
--   ⚠️ 설정 두 줄(inv_config qbo_supplier_line_*)은 이 트랜잭션 안에서 바꾼다(창구 시험 · 지시서 시나리오 2 · 3) — rollback 으로 돌아간다 · 일감 claim · mail · 송신 창구는 부르지 않는다 · 공개 레포 — 상호를 찍지 않는다
--   ⚠️ create or replace function · inv_config 행 잠금 — 토론토 17:00 뒤 · begin ~ rollback 10 초 안
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 28
\else
\set EXPECT_OK 26
\endif
select (select value from public.inv_config where key = 'db_role') as db_role;

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return coalesce(v_out, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p_txt text) returns jsonb language sql as $$ select case when left(p_txt, 1) in ('{', '[') then p_txt::jsonb end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
$$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.acc(p_body jsonb, p_n int) returns text language sql as $$
  select x->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value' from jsonb_array_elements(p_body->'body'->'Line') x where (x->>'LineNum')::int = p_n
$$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v_txt text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v_txt := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v_txt, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

-- ── 기준(begin 앞 · 잠금 없음) — 실제 goods 만 인보이스 하나의 몸(S6) · 무변 함수 md5 · 실제 행 수 ──
create temp table t_pre as
select (select i.id from public.po_invoice i join public.po_invoice_money m on m.id = i.id
         where i.status = 'confirmed' and i.doc_kind = 'invoice' and m.diff = 0
           and not exists (select 1 from public.po_invoice_line l where l.po_invoice_id = i.id and (l.line_kind <> 'goods' or not l.is_payable))
         order by i.invoice_date, i.id limit 1) as real_id,
       null::text as real_body,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace
          and proname in ('qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_charge_bill_body', 'qbo_account_ref', 'qbo_link_set', 'qbo_link_clear', 'qbo_link_summary', 'ims_config_set', 'inv_config_guard', 'inv_layer_post_receipt', 'qbo_bill_payment_body', 'qbo_discount_credit_body')) as md5_same,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') as md5_body,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.supplier) as n_sup, (select count(*) from public.po) as n_po, (select count(*) from public.po_invoice) as n_inv,
       (select count(*) from public.ref_account) as n_acc, (select count(*) from public.qbo_link) as n_link, (select count(*) from public.qbo_entity) as n_ent, (select count(*) from public.qbo_job) as n_job, (select count(*) from public.inv_config) as n_cfg;
update t_pre set real_body = pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', real_id, 'bill')) where real_id is not null;
select real_id is not null as has_real_goods_invoice, left(real_body, 1) = '{' as real_body_built, n_inv, n_job, n_cfg, clock_timestamp() as t_begin from t_pre \gset
\echo '── 기준: invoices' :n_inv '· jobs' :n_job '· settings' :n_cfg '· real goods-only body built' :real_body_built

begin;
set local statement_timeout = '120s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
select pg_temp.chk('S0(시험 갈래) 심은 설정 두 줄 = _95_ · _95_', (select string_agg(c.value, ' ' order by c.key) from public.inv_config c where c.key in ('qbo_supplier_line_charge_account_code', 'qbo_supplier_line_other_account_code')), '_95_ _95_');
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — 직원 셋(열쇠 qbo · qbo:read · 없음) · 공급처 CAD + Vendor 짝 · 계정 둘(꺼짐 · 짝 없음) · PO + 줄 · 문서 여섯 ──
do $$
declare
  v_cad uuid := (select id from public.ref_currency where code = 'CAD'); v_term uuid := (select id from public.ref_payment_term where name = 'Due on receipt');
  v_hst uuid := (select id from public.ref_tax_rule where name = 'HST ON (Purchase)'); v_prod uuid := (select id from public.product where sku = 'AAL10850');
  v_realm text := (select realm_id from public.qbo_connection where singleton); v_ap public.ref_account%rowtype;
  v_u1 uuid := gen_random_uuid(); v_u2 uuid := gen_random_uuid(); v_u3 uuid := gen_random_uuid(); v_bk uuid;
  v_s uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid();
  v_ia uuid := gen_random_uuid(); v_ib uuid := gen_random_uuid(); v_ic uuid := gen_random_uuid(); v_idd uuid := gen_random_uuid(); v_ie uuid := gen_random_uuid(); v_ik uuid := gen_random_uuid();
  v_x text; v_y text;
begin
  select * into v_ap from public.ref_account where code = '_62_';
  select min(q.code), max(q.code) into v_x, v_y from (select a.code from public.ref_account a where a.is_active and a.account_type = 'EXPENSE' and a.code <> '_95_'
     and exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'account' and l.ims_id = a.id::text) order by a.code limit 2) q;
  if v_cad is null or v_term is null or v_hst is null or v_prod is null or v_realm is null or v_ap.id is null or v_x is null or v_x = v_y then raise exception 'fixture: a reference row is missing (currency · term · tax rule · product AAL10850 · realm · _62_ · two linked expense accounts)'; end if;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_u1, 'zz-qbo-bill-charge-1-bk@test.invalid', 'ZZ bill-charge bookkeeper', 'manager', '["ims", "qbo"]', '{}') returning id into v_bk;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_u2, 'zz-qbo-bill-charge-1-ro@test.invalid', 'ZZ bill-charge reader', 'manager', '["ims", "qbo:read"]', '{}'),
                                                                                                 (v_u3, 'zz-qbo-bill-charge-1-nk@test.invalid', 'ZZ bill-charge no key', 'manager', '["ims", "purchasing", "master"]', '{}');
  insert into public.ref_account (name, code, is_active, source, account_class, account_type) values ('ZZ-BC1 switched off', '_zzbc1_off_', false, 'manual', 'EXPENSE', 'EXPENSE'), ('ZZ-BC1 not linked', '_zzbc1_nolink_', true, 'manual', 'EXPENSE', 'EXPENSE');
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values (v_s, 'ZZ-BC1 Supplier', 'manual', true, v_term, 'Due on receipt', v_ap.id, v_ap.code, v_cad);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (v_realm, 'Vendor', 'zzbc1v', 'ZZ-BC1 Vendor', true);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'supplier', v_s::text, 'Vendor', 'zzbc1v', 'manual');
  insert into public.po (id, po_number, status, supplier_id, currency_id) values (v_po, 'PO-79441', 'confirmed', v_s, v_cad);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l1, v_po, 1, v_prod, 1000, 2.5);
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, total_amount, status, doc_kind, tax_rule_id) values
    (v_ia,  v_s, 'ZZBC1-15335', public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst),
    (v_ib,  v_s, 'ZZBC1-OTHER', public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst),
    (v_ic,  v_s, 'ZZBC1-NP',    public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst),
    (v_idd, v_s, 'ZZBC1-ALLNP', public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst),
    (v_ie,  v_s, 'ZZBC1-GOODS', public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst),
    (v_ik,  v_s, 'ZZBC1-CR',    public.ims_today() - 2, null, null, null, v_cad, 0, 'draft', 'credit', v_hst);
  -- A = 15335 꼴(goods 7 + charge 1 · 줄 규칙 없음 → 머리 HST) · B = goods + charge + other · C = 낼 goods · 안 낼 goods · 안 낼 charge · 낼 charge + 할인 10% · D = 전부 안 냄 · E = goods 만 · K = 크레딧(goods 가격 차이 + charge)
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable, credit_reason) values
    (v_ia, 1, 'goods', v_l1, null, 24, 5.5, true, null), (v_ia, 2, 'goods', v_l1, null, 72, 5.5, true, null), (v_ia, 3, 'goods', v_l1, null, 48, 5.5, true, null), (v_ia, 4, 'goods', v_l1, null, 48, 5.5, true, null),
    (v_ia, 5, 'goods', v_l1, null, 48, 1.85, true, null), (v_ia, 6, 'goods', v_l1, null, 24, 1.85, true, null), (v_ia, 7, 'goods', v_l1, null, 200, 2.2, true, null),
    (v_ia, 8, 'charge', null, 'Freight - Shipping & Handling Charges', 1, 25, true, null),
    (v_ib, 1, 'goods', v_l1, null, 4, 2.5, true, null), (v_ib, 2, 'charge', null, 'ZZ freight', 1, 5, true, null), (v_ib, 3, 'other', null, 'ZZ pallet fee', 1, 3, true, null),
    (v_ic, 1, 'goods', v_l1, null, 10, 2.5, true, null), (v_ic, 2, 'goods', v_l1, null, 4, 2.5, false, null), (v_ic, 3, 'charge', null, 'ZZ freight not paid', 1, 20, false, null), (v_ic, 4, 'charge', null, 'ZZ handling', 1, 5, true, null),
    (v_idd, 1, 'goods', v_l1, null, 4, 2.5, false, null), (v_idd, 2, 'charge', null, 'ZZ freight not paid', 1, 20, false, null),
    (v_ie, 1, 'goods', v_l1, null, 4, 2.5, true, null),
    (v_ik, 1, 'goods', v_l1, null, 2, 2.5, true, 'price_difference'), (v_ik, 2, 'charge', null, 'ZZ freight credit', 1, 5, true, null);
  insert into public.po_invoice_discount (po_invoice_id, seq, name, percent) values (v_ic, 1, 'ZZ trade', 10);
  update public.po_invoice i set total_amount = m.computed_total from public.po_invoice_money m where m.id = i.id and i.id in (v_ia, v_ib, v_ic, v_idd, v_ie, v_ik);
  update public.po_invoice set status = 'confirmed', confirmed_by = v_bk, confirmed_at = now() where id in (v_ia, v_ib, v_ic, v_idd, v_ie, v_ik);
  update public.inv_config set value = '_95_', updated_by = null where key in ('qbo_supplier_line_charge_account_code', 'qbo_supplier_line_other_account_code');   -- 확인 갈래: 실제 값이 무엇이든 시험은 _95_ 에서 시작(rollback)
  perform pg_temp.put('u_bk', v_u1::text); perform pg_temp.put('u_ro', v_u2::text); perform pg_temp.put('u_nk', v_u3::text); perform pg_temp.put('x', v_x); perform pg_temp.put('y', v_y); perform pg_temp.put('hst', v_hst::text);
  perform pg_temp.put('ia', v_ia::text); perform pg_temp.put('ib', v_ib::text); perform pg_temp.put('ic', v_ic::text); perform pg_temp.put('id', v_idd::text); perform pg_temp.put('ie', v_ie::text); perform pg_temp.put('ik', v_ik::text);
  perform pg_temp.put('q95', (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.realm_id = v_realm and l.ims_kind = 'account' and a.code = '_95_'));
  perform pg_temp.put('qx',  (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.realm_id = v_realm and l.ims_kind = 'account' and a.code = v_x));
  perform pg_temp.put('qy',  (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.realm_id = v_realm and l.ims_kind = 'account' and a.code = v_y));
  perform pg_temp.put('qginr', (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.realm_id = v_realm and l.ims_kind = 'account' and a.code = '_1150040012_'));
  perform pg_temp.put('taxcode', public.qbo_purchase_tax(v_hst)->>'tax_code');
end $$;

-- ── S1 ~ S6 몸(DO 하나 · 서버 안) ──
do $$
declare
  v_b jsonb; v_t text; v_m record; v_g record; v_real record; v_x text := pg_temp.id('x'); v_y text := pg_temp.id('y');
  v_q95 text := pg_temp.id('q95'); v_qx text := pg_temp.id('qx'); v_qy text := pg_temp.id('qy'); v_qg text := pg_temp.id('qginr'); v_tc text := pg_temp.id('taxcode');
  c_real constant uuid := '697fb03d-909c-4807-b786-f6236b99c7ce';
begin
  -- S1a 실물 15335 — 남는 거부는 찍힌 합계 대조(1192) 하나뿐(실물이 그 뒤 고쳐졌으면 그 상태대로 판정)
  select m.diff, i.status, (select count(*) from public.po_invoice_line l where l.po_invoice_id = i.id and l.line_kind <> 'goods') as non_goods into v_real from public.po_invoice i join public.po_invoice_money m on m.id = i.id where i.id = c_real;
  if v_real.status is null then
    perform pg_temp.chk('S1a 실물 15335 — 없음(건너뜀 · 판정 없이 OK)', 'skipped', 'skipped');
  else
    v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', c_real, 'bill'));
    perform pg_temp.chk('S1a 실물 15335: charge 거부 문장 없음 · 남는 거부는 찍힌 합계 대조 하나(diff ≠ 0 일 때 · 1192) — 그 밖에는 몸이 선다',
      (v_t not like '%not payable goods lines%')::text || ' ' || case when v_t like 'ERR %the lines add up to % but the printed total is %nothing was sent' then 'diff-only' when left(v_t, 1) = '{' then 'built' else left(v_t, 90) end,
      'true ' || case when v_real.status <> 'confirmed' then left(v_t, 90) when v_real.diff <> 0 then 'diff-only' else 'built' end);
  end if;
  -- S1b 합계를 맞춘 가짜 사본 — 8 줄 · charge 줄 = _95_ 의 QBO id · HST 코드 · 줄 합 + 세금 = 낼 돈
  v_b := public.qbo_bill_body(pg_temp.id('ia')::uuid, 'bill');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('ia')::uuid;
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('ia')::uuid;
  perform pg_temp.chk('S1b 15335 꼴 사본: 8 줄 · goods 7 = GINR · 8 번 = charge 설정 계정(_95_) · 세금 코드 HST · Description = 줄 글 · Amount 25.00',
    (v_b->>'line_count') || ' ' || (select count(*) from jsonb_array_elements(v_b->'body'->'Line') x where (x->>'LineNum')::int <= 7 and x->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value' = v_qg)::text
      || ' ' || pg_temp.acc(v_b, 8) || ' ' || (v_b->'body'->'Line'->7->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value') || ' ' || (v_b->'body'->'Line'->7->>'Description') || ' ' || (v_b->'body'->'Line'->7->>'Amount'),
    '8 7 ' || v_q95 || ' ' || v_tc || ' Freight - Shipping & Handling Charges 25.00');
  perform pg_temp.chk('S1c 15335 꼴 사본: 줄 합 1654.20 + 세금 215.04 = 1869.24 = 낼 돈 = 뷰 computed · lookup total_cents 186924 · 지문 · TaxLine 하나(과세 1654.20) · 경고 없음',
    (select sum((x->>'Amount')::numeric) from jsonb_array_elements(v_b->'body'->'Line') x)::text || ' ' || (v_b->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || v_m.payable_net::text || ' ' || v_m.computed_total::text
      || ' ' || (v_b->'lookup'->>'total_cents') || ' ' || (v_b->>'fingerprint') || ' ' || jsonb_array_length(v_b->'body'->'TxnTaxDetail'->'TaxLine')::text || ' ' || (v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || jsonb_array_length(v_b->'warnings')::text,
    '1654.20 215.04 1869.24 1869.24 186924 186924|CAD 1 1654.20 0');
  -- S2 설정을 다른 계정으로 — charge → X · other → Y(열쇠 직원이 창구로)
  perform pg_temp.as_user(pg_temp.id('u_bk'));
  v_t := pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L, %L)::text', 'charge', v_x, '_95_'));
  perform pg_temp.chk('S2a 쓰기 창구 charge → X: changed true · code X · old_code _95_ · linked · 문제 없음 · 고친 사람 = 열쇠 직원',
    (pg_temp.j(v_t)->>'changed') || ' ' || (pg_temp.j(v_t)->>'code') || ' ' || (pg_temp.j(v_t)->>'old_code') || ' ' || (pg_temp.j(v_t)->>'linked') || ' ' || coalesce(pg_temp.j(v_t)->>'problem', '-') || ' ' || (pg_temp.j(v_t)->>'updated_by_name') || ' ' || (pg_temp.j(v_t)->>'line_kind'),
    'true ' || v_x || ' _95_ true - ZZ bill-charge bookkeeper charge');
  v_t := pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'other', v_y));
  perform pg_temp.chk('S2b 쓰기 창구 other → Y(p_old 없이): changed true · code Y', (pg_temp.j(v_t)->>'changed') || ' ' || (pg_temp.j(v_t)->>'code'), 'true ' || v_y);
  v_b := public.qbo_bill_body(pg_temp.id('ib')::uuid, 'bill');
  perform pg_temp.chk('S2c 몸 B(goods + charge + other): 계정 GINR · X · Y · Description 「ZZ freight」 · 「ZZ pallet fee」 · 금액 10.00 5.00 3.00',
    pg_temp.acc(v_b, 1) || ' ' || pg_temp.acc(v_b, 2) || ' ' || pg_temp.acc(v_b, 3) || ' ' || (v_b->'body'->'Line'->1->>'Description') || '|' || (v_b->'body'->'Line'->2->>'Description') || ' ' || (select string_agg(x->>'Amount', ' ' order by (x->>'LineNum')::int) from jsonb_array_elements(v_b->'body'->'Line') x),
    v_qg || ' ' || v_qx || ' ' || v_qy || ' ZZ freight|ZZ pallet fee 10.00 5.00 3.00');
  perform pg_temp.chk('S2d 몸 A 의 charge 줄도 새 설정 X 로(다음에 만드는 몸부터)', pg_temp.acc(public.qbo_bill_body(pg_temp.id('ia')::uuid, 'bill'), 8), v_qx);
  -- S3 설정 계정 고장(other 줄 설정을 직접 바꿔 — 창구는 이런 값을 받지 않는다) → 까닭 글로 거부 · goods 만 · charge 만 문서는 그대로 선다
  update public.inv_config set value = '' where key = 'qbo_supplier_line_other_account_code';
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ib'), 'bill'));
  perform pg_temp.chk('S3a 설정 빔 → 「No QuickBooks account is chosen for supplier invoice other lines … nothing was sent」', (v_t like 'ERR %No QuickBooks account is chosen for supplier invoice other lines%nothing was sent')::text, 'true');
  update public.inv_config set value = '_zzbc1_off_' where key = 'qbo_supplier_line_other_account_code';
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ib'), 'bill'));
  perform pg_temp.chk('S3b 꺼진 계정 → 「… is switched off in IMS … nothing was sent」', (v_t like 'ERR %Account _zzbc1_off_ ZZ-BC1 switched off (chosen for supplier invoice other lines) is switched off in IMS%nothing was sent')::text, 'true');
  update public.inv_config set value = '_zzbc1_nolink_' where key = 'qbo_supplier_line_other_account_code';
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ib'), 'bill'));
  perform pg_temp.chk('S3c QBO 짝 없는 계정 → 「… has no QuickBooks match … nothing was sent」', (v_t like 'ERR %IMS account _zzbc1_nolink_ (supplier invoice other lines) has no QuickBooks match%nothing was sent')::text, 'true');
  update public.inv_config set value = '_zzbc1_gone_' where key = 'qbo_supplier_line_other_account_code';
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ib'), 'bill'));
  perform pg_temp.chk('S3d 없는 계정 → 「… does not exist in IMS … nothing was sent」 · other 설정이 고장이어도 goods 만(E) · charge 만(A) 문서는 선다',
    (v_t like 'ERR %Account _zzbc1_gone_ (chosen for supplier invoice other lines) does not exist in IMS%nothing was sent')::text
      || ' ' || left(pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ie'), 'bill')), 1) || ' ' || left(pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('ia'), 'bill')), 1), 'true { {');
  update public.inv_config set value = v_y where key = 'qbo_supplier_line_other_account_code';
  -- S4 돈 안 내는 줄(1191) — 줄 · 할인 · 세금 · 합계 · lookup 모두 낼 돈 기준
  v_b := public.qbo_bill_body(pg_temp.id('ic')::uuid, 'bill');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('ic')::uuid;
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('ic')::uuid;
  perform pg_temp.chk('S4a 몸 C: 3 줄(낼 goods 25.00 · 낼 charge 5.00 · 할인 −낼 할인) · 안 낼 줄의 글 없음 · 계정 GINR · X · GINR · 경고 「2 line(s) marked not payable」',
    (v_b->>'line_count') || ' ' || (select string_agg(x->>'Amount', ' ' order by (x->>'LineNum')::int) from jsonb_array_elements(v_b->'body'->'Line') x) || ' ' || ((v_b->'body'->'Line')::text like '%not paid%')::text
      || ' ' || pg_temp.acc(v_b, 1) || ' ' || pg_temp.acc(v_b, 2) || ' ' || pg_temp.acc(v_b, 3) || ' ' || ((v_b->'warnings')::text like '%2 line(s) marked not payable%')::text,
    '3 25.00 5.00 ' || (-v_g.payable_discount)::text || ' false ' || v_qg || ' ' || v_qx || ' ' || v_qg || ' true');
  perform pg_temp.chk('S4b 몸 C: 줄 합 + 세금 = 낼 돈(payable_net) < 줄 전체 합(computed) · TotalTax = 낼 세금 · TaxLine 과세 = 낼 과세 · lookup total_cents · 지문 · totals.total = 낼 돈 · 낼 할인 2.50',
    ((select sum((x->>'Amount')::numeric) from jsonb_array_elements(v_b->'body'->'Line') x) + (v_b->'body'->'TxnTaxDetail'->>'TotalTax')::numeric = v_m.payable_net)::text || ' ' || (v_m.payable_net < v_m.computed_total)::text
      || ' ' || ((v_b->'body'->'TxnTaxDetail'->>'TotalTax')::numeric = v_m.payable_tax)::text || ' ' || ((v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable')::numeric = v_g.payable_taxable)::text
      || ' ' || ((v_b->'lookup'->>'total_cents')::bigint = round(v_m.payable_net * 100))::text || ' ' || ((v_b->>'fingerprint') = round(v_m.payable_net * 100)::bigint::text || '|CAD')::text || ' ' || ((v_b->'totals'->>'total')::numeric = v_m.payable_net)::text || ' ' || v_g.payable_discount::text,
    'true true true true true true true 2.50');
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', pg_temp.id('id'), 'bill'));
  perform pg_temp.chk('S4c 전부 안 내는 문서 D → 「has no payable lines … nothing was sent」', (v_t like 'ERR %Invoice ZZBC1-ALLNP has no payable lines%nothing was sent')::text, 'true');
  -- S5 크레딧 — 같은 몸 · charge 줄은 같은 설정 계정
  v_b := public.qbo_vendor_credit_body(pg_temp.id('ik')::uuid);
  perform pg_temp.chk('S5 크레딧 K: kind vendor_credit · VendorCredit · 2 줄 · goods = GINR(「price difference」) · charge = 설정 계정 X(「ZZ freight credit」) · DueDate 없음 · 줄 합 + 세금 = 낼 돈',
    (v_b->>'kind') || ' ' || (v_b->'lookup'->>'entity') || ' ' || (v_b->>'line_count') || ' ' || pg_temp.acc(v_b, 1) || ' ' || ((v_b->'body'->'Line'->0->>'Description') like '%price difference')::text || ' ' || pg_temp.acc(v_b, 2) || ' ' || (v_b->'body'->'Line'->1->>'Description')
      || ' ' || (v_b->'body' ? 'DueDate')::text || ' ' || ((select sum((x->>'Amount')::numeric) from jsonb_array_elements(v_b->'body'->'Line') x) + (v_b->'body'->'TxnTaxDetail'->>'TotalTax')::numeric = (select payable_net from public.po_invoice_money where id = pg_temp.id('ik')::uuid))::text,
    'vendor_credit VendorCredit 2 ' || v_qg || ' true ' || v_qx || ' ZZ freight credit false true');
  -- S6 goods 만 있는 문서 = 고치기 전과 같다(실물 하나를 begin 앞 · 뒤로 · 설정이 바뀌어 있어도)
  perform pg_temp.chk('S6a 실물 goods 만 인보이스의 몸(jsonb) = begin 앞(없으면 건너뜀)',
    (select case when p.real_id is null then 'skipped' else (pg_temp.j(p.real_body) is not distinct from pg_temp.j(pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', p.real_id, 'bill'))))::text || ' ' || left(p.real_body, 1) end from t_pre p),
    (select case when p.real_id is null then 'skipped' else 'true {' end from t_pre p));
  v_b := public.qbo_bill_body(pg_temp.id('ie')::uuid, 'bill');
  perform pg_temp.chk('S6c 가짜 goods 만 E: 1 줄 · GINR · Description 「AAL10850 × 4 @ 2.5 · PO PO-79441」 · 경고 없음', (v_b->>'line_count') || ' ' || pg_temp.acc(v_b, 1) || ' ' || (v_b->'body'->'Line'->0->>'Description') || ' ' || jsonb_array_length(v_b->'warnings')::text, '1 ' || v_qg || ' AAL10850 × 4 @ 2.5 · PO PO-79441 0');
end $$;
\if :{?mig}
select pg_temp.chk('S6b(시험 갈래) 재발행된 qbo_bill_body md5 ≠ begin 앞', ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') <> (select md5_body from t_pre))::text, 'true');
\endif

-- ── S7 창구 — 실제 authenticated 역할 · 열쇠 없는 직원(purchasing · master 는 있다) ──
select pg_temp.as_user(pg_temp.id('u_nk'));
set local role authenticated;
do $$
declare v_out text := '';
begin
  begin perform public.qbo_supplier_line_account_set('charge', '_95_', null); v_out := v_out || 'set:no error'; exception when others then v_out := v_out || 'set:' || sqlstate || ':' || sqlerrm; end;
  begin perform public.qbo_supplier_line_accounts(); v_out := v_out || ' ¦ read:no error'; exception when others then v_out := v_out || ' ¦ read:' || sqlstate || ':' || sqlerrm; end;
  begin perform public.qbo_supplier_line_account('charge'); v_out := v_out || ' ¦ inner:no error'; exception when others then v_out := v_out || ' ¦ inner:' || sqlstate; end;
  begin perform public.qbo_supplier_line_account_row('charge'); v_out := v_out || ' ¦ row:no error'; exception when others then v_out := v_out || ' ¦ row:' || sqlstate; end;
  begin update public.inv_config set value = '_95_' where key = 'qbo_supplier_line_charge_account_code'; v_out := v_out || ' ¦ direct:no error'; exception when others then v_out := v_out || ' ¦ direct:' || sqlstate; end;
  perform set_config('app.zzbc1_nk', v_out, true);
end $$;
reset role;

do $$
declare v_t text; v_r jsonb; v_x text := pg_temp.id('x'); v_y text := pg_temp.id('y'); v_n int;
begin
  perform pg_temp.chk('S7a 열쇠 없는 직원(실제 authenticated 역할): 쓰기 · 읽기 창구 = 열쇠 거부 문장 · 속 함수 둘 · 표 직접 update = 42501',
    regexp_replace(current_setting('app.zzbc1_nk', true), 'Your account does not have the ''qbo''( \(write\))? permission — ask an admin to switch it on in Staff — nothing was changed', 'KEY\1', 'g'),
    'set:P0001:KEY (write) ¦ read:P0001:KEY ¦ inner:42501 ¦ row:42501 ¦ direct:42501');
  -- 보기 열쇠(qbo:read) — 읽기는 되고 can_edit false · 쓰기는 거부
  perform pg_temp.as_user(pg_temp.id('u_ro'));
  v_r := pg_temp.j(pg_temp.try('select public.qbo_supplier_line_accounts()::text'));
  v_t := pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L, null)::text', 'charge', '_95_'));
  perform pg_temp.chk('S7b 보기 열쇠: 읽기 can_edit false · lines charge · other · 쓰기 = 「''qbo'' (write) permission」 거부',
    (v_r->>'can_edit') || ' ' || (select string_agg(x->>'line_kind', ',' order by o) from jsonb_array_elements(v_r->'lines') with ordinality t(x, o)) || ' ' || (v_t like 'ERR P0001: Your account does not have the ''qbo'' (write) permission%nothing was changed')::text, 'false charge,other true');
  -- 쓰기 열쇠 — 읽기 꼴 · 고를 목록
  perform pg_temp.as_user(pg_temp.id('u_bk'));
  v_r := pg_temp.j(pg_temp.try('select public.qbo_supplier_line_accounts()::text'));
  select count(*) into v_n from public.ref_account a where a.is_active and a.account_type in ('COSTOFGOODSSOLD', 'EXPENSE') and exists (select 1 from public.qbo_link l where l.realm_id = public.qbo_realm_of() and l.ims_kind = 'account' and l.ims_id = a.id::text);
  perform pg_temp.chk('S7c 쓰기 열쇠 읽기: can_edit true · 지금 값 X · Y · linked · 문제 없음 · 고를 목록 = 켜짐 ∧ 짝 ∧ COGS · EXPENSE 수 · _95_ 있음 · 가짜 꺼짐 · 짝 없음 · GINR 없음 · 줄 열쇠 11 · 계정 열쇠 3',
    (v_r->>'can_edit') || ' ' || (v_r->'lines'->0->>'code') || ' ' || (v_r->'lines'->1->>'code') || ' ' || (v_r->'lines'->0->>'linked') || ' ' || coalesce(v_r->'lines'->1->>'problem', '-') || ' ' || (jsonb_array_length(v_r->'accounts') = v_n and v_n > 0)::text
      || ' ' || (v_r->'accounts' @> '[{"code": "_95_"}]')::text || ' ' || (v_r->'accounts' @> '[{"code": "_zzbc1_off_"}]' or v_r->'accounts' @> '[{"code": "_zzbc1_nolink_"}]' or v_r->'accounts' @> '[{"code": "_1150040012_"}]')::text
      || ' ' || (select count(*) from jsonb_object_keys(v_r->'lines'->0))::text || ' ' || (select count(*) from jsonb_object_keys(v_r->'accounts'->0))::text,
    'true ' || v_x || ' ' || v_y || ' true - true true false 11 3');
  -- 쓰기 거부 일곱 + 같은 값 + 설정 무변
  perform pg_temp.chk('S7d 쓰기 거부: 종류 goods · 빈 값 · 없는 계정 · 꺼진 계정 · 짝 없는 계정 · 종류 밖(GINR = OTHERCURRENTASSET) · 화면이 본 값이 다름(changed_elsewhere)',
    (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'goods', '_95_')) like 'ERR P0001: line_kind must be charge or other (got goods)%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'charge', '  ')) like 'ERR P0001: Choose an account%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'charge', '_zzbc1_gone_')) like 'ERR P0001: Account _zzbc1_gone_ does not exist in IMS%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'charge', '_zzbc1_off_')) like 'ERR P0001: Account _zzbc1_off_ ZZ-BC1 switched off is switched off%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'charge', '_zzbc1_nolink_')) like 'ERR P0001: Account _zzbc1_nolink_ ZZ-BC1 not linked has no QuickBooks match%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L)::text', 'charge', '_1150040012_')) like 'ERR P0001: Account _1150040012_ % is a OTHERCURRENTASSET account%nothing was saved')::text
      || ' ' || (pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L, %L)::text', 'charge', '_95_', '_95_')) like 'ERR P0001: changed_elsewhere: the charge line account was changed by ZZ bill-charge bookkeeper at % to "' || v_x || '" since this page loaded%nothing was saved')::text,
    'true true true true true true true');
  v_t := pg_temp.try(format('select public.qbo_supplier_line_account_set(%L, %L, %L)::text', 'charge', v_x, v_x));
  perform pg_temp.chk('S7e 같은 값 → changed false · 거부 뒤 설정 무변(X · Y) · ims_config_set 은 새 키를 거부(「not changed from the app」 · 판정 572 그대로)',
    (pg_temp.j(v_t)->>'changed') || ' ' || (select string_agg(c.value, ' ' order by c.key) from public.inv_config c where c.key in ('qbo_supplier_line_charge_account_code', 'qbo_supplier_line_other_account_code'))
      || ' ' || (pg_temp.try(format('select public.ims_config_set(%L, %L, null)::text', 'qbo_supplier_line_charge_account_code', '_95_')) like 'ERR P0001: Setting qbo_supplier_line_charge_account_code is not changed from the app%')::text,
    'false ' || v_x || ' ' || v_y || ' true');
  perform pg_temp.as_user(null);
  -- S9 REST 두 겹 ① — 새 창구 · 속 함수 · 재발행 몸의 update · delete 깊이 0 WHERE
  perform pg_temp.chk('S9 REST WHERE: 스캐너 자기 시험 「10」 · 새 함수 넷 + qbo_bill_body 의 WHERE 없는 update · delete = 0 · 쓰기 창구에 update 하나',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text
      || ' ' || (select sum(pg_temp.nowhere(p.prosrc))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set', 'qbo_bill_body'))
      || ' ' || (select (length(p.prosrc) - length(replace(p.prosrc, 'update public.inv_config', ''))) / length('update public.inv_config') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_supplier_line_account_set')::text,
    '10 0 1');
  -- G 구조
  perform pg_temp.chk('G1 권한: 창구 둘만 authenticated · 속 함수 둘 · 몸은 grant 0 · anon 0',
    (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_body', 'qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set'))
      || ' ' || (has_function_privilege('anon', 'public.qbo_supplier_line_accounts()', 'execute') or has_function_privilege('anon', 'public.qbo_supplier_line_account_set(text, text, text)', 'execute') or has_function_privilege('service_role', 'public.qbo_supplier_line_account_set(text, text, text)', 'execute'))::text,
    'qbo_bill_body:{postgres=X/postgres} qbo_supplier_line_account:{postgres=X/postgres} qbo_supplier_line_account_row:{postgres=X/postgres} qbo_supplier_line_account_set:{postgres=X/postgres,authenticated=X/postgres} qbo_supplier_line_accounts:{postgres=X/postgres,authenticated=X/postgres} false');
  perform pg_temp.chk('G2 무변 열넷(claim · preview · done · retry · charge_bill_body · account_ref · link_set · link_clear · link_summary · ims_config_set · inv_config_guard · inv_layer_post_receipt · bill_payment_body · discount_credit_body) md5 = begin 앞 · 이름마다 정의 하나',
    ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_charge_bill_body', 'qbo_account_ref', 'qbo_link_set', 'qbo_link_clear', 'qbo_link_summary', 'ims_config_set', 'inv_config_guard', 'inv_layer_post_receipt', 'qbo_bill_payment_body', 'qbo_discount_credit_body'))
      = (select md5_same from t_pre))::text
      || ' ' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_body', 'qbo_supplier_line_account', 'qbo_supplier_line_account_row', 'qbo_supplier_line_accounts', 'qbo_supplier_line_account_set'))::text,
    'true 5');
  perform pg_temp.chk('G3 실제 행(트랜잭션 안) = 기준 + 가짜(직원 3 · 공급처 1 · PO 1 · 문서 6 · 계정 2 · 짝 1 · 거울 1) · 설정 행 = 기준 + 2(시험 갈래) | 기준(확인 갈래) · 짝 종류 charge 무변',
    ((select count(*) from public.ims_staff) - p.n_staff)::text || ' ' || ((select count(*) from public.supplier) - p.n_sup)::text || ' ' || ((select count(*) from public.po) - p.n_po)::text || ' ' || ((select count(*) from public.po_invoice) - p.n_inv)::text
      || ' ' || ((select count(*) from public.ref_account) - p.n_acc)::text || ' ' || ((select count(*) from public.qbo_link) - p.n_link)::text || ' ' || ((select count(*) from public.qbo_entity) - p.n_ent)::text
      || ' ' || (((select count(*) from public.inv_config) - p.n_cfg) in (0, 2))::text,
    '3 1 1 6 2 1 1 true') from t_pre p;
end $$;

-- ── Z(rollback 앞 — t_res 는 임시 표지만 줄은 트랜잭션 안에서 들어갔다) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select format('OK %s · FAIL %s · EXPECT %s', count(*) filter (where ok), count(*) filter (where not ok), :EXPECT_OK) as summary from t_res \gset
\echo :summary
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.ims_staff) = p.n_staff and (select count(*) from public.supplier) = p.n_sup and (select count(*) from public.po) = p.n_po and (select count(*) from public.po_invoice) = p.n_inv
   and (select count(*) from public.ref_account) = p.n_acc and (select count(*) from public.qbo_link) = p.n_link and (select count(*) from public.qbo_entity) = p.n_ent and (select count(*) from public.qbo_job) = p.n_job
   and (select count(*) from public.inv_config) = p.n_cfg and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_bill_body') = p.md5_body as rolled_back_clean from t_pre p;
