-- supabase/tests/qbo_sync_4_3b_check.sql — qbo-sync-4-3b 검증 (2026-11-09 · 판정 1119 ~ 1122 · §0 이견 14 · 15 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → E1 실제 RCV 두 줄(읽기만) · E2 11-05 TOR 셈 · E3 가짜 CADJ(price_adjust send · settlement_discount hold · 대 GINR) · E4 가짜 입고 날짜 · F1 계좌 여섯 · F2 기존 결제 4 통과 · F3 가짜 결제 거부 · 통과 · W1 WHERE · G 구조 → rollback
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261109104000_qbo_sync_4_3b_receipt_release_bank_currency.sql -f supabase/tests/qbo_sync_4_3b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(S0b 한 검사만 갈래마다 다르게 본다)
--   ⚠️ 가짜 재료만(레이어 · 원장 · 원가 조정 · 결제 ZZ43B) — inv_config qbo_cost_since 를 트랜잭션 안에서 2026-01-05 로 옮긴다(3-2b 꼴 · 실제 사건은 전부 2026-08-21 뒤) · 실제 RCV · 계좌 · 결제는 읽기만 · 공개 레포 — 상호 없음
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 16
select (select value from public.inv_config where key = 'db_role') as db_role;
select (select realm_id from public.qbo_connection where singleton) as realm \gset

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
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

-- ── 기준(begin 앞) ──
select (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') as pre_md5_exp,
       (select string_agg(a.code || ':' || coalesce(a.currency_code, '-'), ' ' order by a.code) from public.ref_account a where a.code in ('_106_', '_138_', '_141_', '_144_', '_145_', '_204_')) as pre_usd6,
       (select count(*) from public.ref_account where currency_code is not null) as pre_cur_n, (select count(*) from public.po_payment) as pre_pay, (select count(*) from public.inv_layer) as pre_layer, (select count(*) from public.inv_ledger) as pre_ledger,
       (select count(*) from public.inv_layer_cost_add) as pre_adds, (select count(*) from public.inv_cost_adjust) as pre_ica, (select value from public.inv_config where key = 'qbo_cost_since') as pre_since,
       (select count(*) from public.qbo_cost_sheet) as pre_sheets, (select coalesce(min(id), 0) from public.inv_layer_consume) as pre_epoch,
       (select string_agg(e.doc_key || ':' || e.status || ':' || e.cents::text, ' ' order by e.doc_key) from public.qbo_cost_expected('2026-11-09') e where e.key_kind = 'RCV') as pre_rcv,
       clock_timestamp() as t_begin \gset
\echo '── 기준: USD 여섯' :pre_usd6 '· 결제' :pre_pay '· 적용 전 RCV' :pre_rcv

begin;
set local statement_timeout = '600s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── E1 · E2 실제 RCV 두 줄(읽기만) ──
select pg_temp.chk('E1 실제 RCV 두 줄(qbo_cost_expected 11-09): status send · reason null · 차 _59_ / 대 GINR(acct_a GINR · acct_b _59_ · 음수 센트) · 날짜 = 입고일 11-05 · 11-06',
  (select string_agg(e.doc_key || ':' || e.status || ':' || coalesce(e.reason, '-') || ':' || e.acct_a || ':' || e.acct_b || ':' || e.cents::text || ':' || e.first_on::text, ' ' order by e.doc_key) from public.qbo_cost_expected('2026-11-09') e where e.key_kind = 'RCV'),
  'RCV-00117:send:-:_1150040012_:_59_:-95000:2026-11-05 RCV-00121:send:-:_1150040012_:_59_:-1203953:2026-11-06');
select pg_temp.chk('E2 11-05 TOR 셈(qbo_cost_sheet_calc): RCV-00117 send · diff −95000 · 그 장에 hold 0 · 11-06 TOR 에 RCV-00121 send · 두 장 state 그대로(pending · 재생성 hold 없음 · epoch 그대로)',
  (select c.status || ':' || c.diff_cents::text from public.qbo_cost_sheet_calc('2026-11-05', 'TOR') c where c.doc_key = 'RCV-00117') || ' ' || (select count(*) from public.qbo_cost_sheet_calc('2026-11-05', 'TOR') c where c.status = 'hold')::text
  || ' ' || (select c.status || ':' || c.diff_cents::text from public.qbo_cost_sheet_calc('2026-11-06', 'TOR') c where c.doc_key = 'RCV-00121')
  || ' ' || (select string_agg(s.state, ',' order by s.sheet_date) from public.qbo_cost_sheet s where s.wh = 'TOR' and s.sheet_date in ('2026-11-05', '2026-11-06')) || ' ' || ((select coalesce(min(id), 0) from public.inv_layer_consume) = :pre_epoch)::text,
  'send:-95000 0 send:-1203953 pending,pending true');

-- ── E3 · E4 가짜 CADJ 둘 + 가짜 입고(DO 하나 · since 를 2026-01-05 로 · 레이어 1 · 원장 1 · 조정 2 · 얹기 2) ──
do $$
declare v_l bigint := (select max(id) from public.inv_layer); v_g bigint := (select max(id) from public.inv_ledger); v_a bigint := (select max(id) from public.inv_layer_cost_add);
        v_j1 uuid := gen_random_uuid(); v_j2 uuid := gen_random_uuid(); v_cad uuid := (select id from public.ref_currency where code = 'CAD');
begin
  update public.inv_config set value = '2026-01-05' where key = 'qbo_cost_since';
  insert into public.inv_layer (id, sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) overriding system value values
    (v_l + 1, 'ZZ-SKU-43B', 'Asung Trading Inc.', 'purchase', 'RCV-ZZ43B', 'zz43b:1', null, date '2026-01-06', true, 10, 9.5, 'po_line');
  insert into public.inv_ledger (id, occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, amount, source) overriding system value values
    (v_g + 1, date '2026-01-06', 1, 'ZZ-SKU-43B', 'Asung Trading Inc.', '', 10, 'po_in', 'purchase', 'RCV-ZZ43B', 'zz43b:1', null, 'ims');
  insert into public.inv_cost_adjust (id, kind, target_type, amount_cad, source_type, source_number, status, posted_on, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse) values
    (v_j1, 'price_adjust',        'layer', -3.5, 'credit',  'ZZ43B-CR-1', 'posted', date '2026-01-07', 'RCV-ZZ43B', 'zz43b:1', 'ZZ-SKU-43B', 'Asung Trading Inc.'),
    (v_j2, 'settlement_discount', 'layer', -2.0, 'payment', 'ZZ43B-SD-1', 'posted', date '2026-01-08', 'RCV-ZZ43B', 'zz43b:1', 'ZZ-SKU-43B', 'Asung Trading Inc.');
  insert into public.inv_layer_cost_add (id, layer_id, kind, amount, occurred_on, doc_number, line_ref) overriding system value values
    (v_a + 1, v_l + 1, 'price_adjust',        -3.5, date '2026-01-07', 'RCV-ZZ43B', 'adj:' || v_j1::text),
    (v_a + 2, v_l + 1, 'settlement_discount', -2.0, date '2026-01-08', 'RCV-ZZ43B', 'adj:' || v_j2::text);
end $$;
select pg_temp.chk('E3 가짜 CADJ 둘: price_adjust(−3.50) → send · 대 GINR(acct_a GINR · acct_b _59_ · +350 = 차 GINR / 대 #59 · 1121) · reason null / settlement_discount(−2.00) → hold · 대 GINR · +200(같은 부호 · 차 GINR / 대 #59) · reason 「supplier payment round (4-5」',
  (select string_agg(e.doc_key || ':' || e.status || ':' || e.acct_a || ':' || coalesce(e.acct_b, 'null') || ':' || e.cents::text || ':' || coalesce(left(e.reason, 22), '-'), ' ' order by e.doc_key) from public.qbo_cost_expected('2026-01-31') e where e.key_kind = 'CADJ' and e.doc_key like 'ZZ43B-%'),
  'ZZ43B-CR-1:send:_1150040012_:_59_:350:- ZZ43B-SD-1:hold:_1150040012_:_59_:200:early-payment discount');
select pg_temp.chk('E4 가짜 입고(1-06 · 10 × 9.5): RCV send · 날짜 = received_on 1-06 · −9500 · 1-06 TOR 셈에 RCV 와 CADJ send 가 들고 hold 는 SD 하나', (select e.status || ':' || e.first_on::text || ':' || e.cents::text from public.qbo_cost_expected('2026-01-31') e where e.key_kind = 'RCV' and e.doc_key = 'RCV-ZZ43B')
  || ' ' || (select string_agg(c.key_kind || ':' || c.doc_key || ':' || c.status, ' ' order by c.key_kind, c.doc_key) from public.qbo_cost_sheet_calc('2026-01-08', 'TOR') c where c.doc_key like '%ZZ43B%'), 'send:2026-01-06:-9500 CADJ:ZZ43B-CR-1:send CADJ:ZZ43B-SD-1:hold RCV:RCV-ZZ43B:send');
select pg_temp.chk('E5 hold 는 가짜 settlement_discount 하나뿐(실제 11-09 셈에 hold 0 · block 0) — 재발행이 RCV · CADJ 두 가지만 바꿨다',
  (select string_agg(e.key_kind || ':' || e.doc_key, ',') filter (where e.status = 'hold') || ' ' || count(*) filter (where e.status = 'block')::text from public.qbo_cost_expected('2026-11-09') e), 'CADJ:ZZ43B-SD-1 0');

-- ── F1 · F2 계좌 여섯 · 기존 결제 ──
\if :{?mig}
select pg_temp.chk('F1(시험 갈래) USD 계좌 여섯 currency_code USD(_106_ · _138_ · _141_ · _144_ · _145_ · _204_ · 운영 QBO R5 로 여섯 모두 USD 확인) · 통화 칸 있는 계정 수 = 기준 + 6',
  (select string_agg(a.code || ':' || coalesce(a.currency_code, '-'), ' ' order by a.code) from public.ref_account a where a.code in ('_106_', '_138_', '_141_', '_144_', '_145_', '_204_')) || ' ' || ((select count(*) from public.ref_account where currency_code is not null) - :pre_cur_n)::text,
  '_106_:USD _138_:USD _141_:USD _144_:USD _145_:USD _204_:USD 6');
\else
select pg_temp.chk('F1(확인 갈래 · 이미 적용) USD 계좌 여섯 currency_code USD · 통화 칸 있는 계정 수 = 기준 + 0(기준이 여섯을 이미 담는다)',
  (select string_agg(a.code || ':' || coalesce(a.currency_code, '-'), ' ' order by a.code) from public.ref_account a where a.code in ('_106_', '_138_', '_141_', '_144_', '_145_', '_204_')) || ' ' || ((select count(*) from public.ref_account where currency_code is not null) - :pre_cur_n)::text,
  '_106_:USD _138_:USD _141_:USD _144_:USD _145_:USD _204_:USD 0');
\endif
select pg_temp.chk('F2 기존 공급처 결제: 계좌 통화 ≠ 결제 통화 0 · 결제 수 그대로 · USD 결제는 _138_(USD) · CAD 결제는 _104_(CAD)',
  (select count(*) from public.po_payment p join public.ref_currency r on r.id = p.currency_id where p.account_id is not null and public.ims_account_currency(p.account_id) <> r.code)::text || ' ' || ((select count(*) from public.po_payment) = :pre_pay)::text
  || ' ' || (select string_agg(distinct r.code || '→' || a.code || ':' || public.ims_account_currency(a.id), ' ' order by r.code || '→' || a.code || ':' || public.ims_account_currency(a.id)) from public.po_payment p join public.ref_currency r on r.id = p.currency_id join public.ref_account a on a.id = p.account_id), '0 true CAD→_104_:CAD USD→_138_:USD');

-- ── F3 가짜 결제(문지기 po.payment_door · 제약을 immediate 로 당겨 DO 안에서 잡는다) ──
do $$
declare v_usd uuid := (select id from public.ref_currency where code = 'USD'); v_cad uuid := (select id from public.ref_currency where code = 'CAD');
        v_104 uuid := (select id from public.ref_account where code = '_104_'); v_138 uuid := (select id from public.ref_account where code = '_138_'); v_e text; v_ok int := 0;
begin
  perform set_config('po.payment_door', '1', true);
  set constraints po_payment_account_currency_ck immediate;
  begin
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference) values (public.ims_today(), 12.34, v_usd, v_104, 'ZZ43B-BAD');
    v_e := 'no error';
  exception when others then v_e := sqlerrm;
  end;
  perform pg_temp.chk('F3a USD 결제를 CAD 계좌(_104_)로 → 거부 · 글 「Payment ZZ43B-BAD: bank account _104_ is in CAD but the payment currency is USD … pick a USD bank account」', (v_e ~ 'Payment ZZ43B-BAD: bank account _104_ is in CAD but the payment currency is USD')::text || ' ' || (v_e ~ 'pick a USD bank account')::text, 'true true');
  begin
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference) values (public.ims_today(), 12.34, v_usd, v_138, 'ZZ43B-OK1'); v_ok := v_ok + 1;
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference) values (public.ims_today(), 12.34, v_cad, v_104, 'ZZ43B-OK2'); v_ok := v_ok + 1;
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference) values (public.ims_today(), 12.34, v_usd, null,  'ZZ43B-OK3'); v_ok := v_ok + 1;
    v_e := 'no error';
  exception when others then v_e := sqlerrm;
  end;
  perform pg_temp.chk('F3b USD → _138_(USD) · CAD → _104_(CAD) · 계정 없음 → 셋 다 통과', v_ok::text || ' ' || v_e, '3 no error');
  begin
    update public.po_payment set account_id = v_104 where reference = 'ZZ43B-OK1';
    v_e := 'no error';
  exception when others then v_e := sqlerrm;
  end;
  perform pg_temp.chk('F3c 통과한 USD 결제의 계좌를 CAD 계좌로 바꾸면 → 거부(UPDATE OF account_id)', (v_e ~ 'bank account _104_ is in CAD but the payment currency is USD')::text, 'true');
  begin
    update public.po_payment set currency_id = v_cad where reference = 'ZZ43B-OK1';
    v_e := 'no error';
  exception when others then v_e := sqlerrm;
  end;
  perform pg_temp.chk('F3d USD 결제(_138_)의 통화만 CAD 로 바꾸면 → 거부(UPDATE OF currency_id) · 글에 계좌 통화 USD · 결제 통화 CAD', (v_e ~ 'bank account _138_ is in USD but the payment currency is CAD')::text, 'true');
  perform set_config('po.payment_door', '', true);
end $$;
select pg_temp.chk('F4 트리거: po_payment_account_currency_ck · AFTER INSERT OR UPDATE OF currency_id, account_id · DEFERRABLE INITIALLY DEFERRED · 몸 grant 0',
  (select (pg_get_triggerdef(oid) ~ 'AFTER INSERT OR UPDATE OF currency_id, account_id ON public.po_payment DEFERRABLE INITIALLY DEFERRED')::text from pg_trigger where tgname = 'po_payment_account_currency_ck')
  || ' ' || (select coalesce(proacl::text, '(default)') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_account_currency_check'), 'true {postgres=X/postgres}');

-- ── W1 · G ──
select pg_temp.chk('W1 WHERE 정적: qbo_cost_expected · po_payment_account_currency_check — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_cost_expected', 'po_payment_account_currency_check')), 'po_payment_account_currency_check 0 · qbo_cost_expected 0');
select pg_temp.chk('G1 qbo_cost_expected: 정의 하나 · ACL 그대로(service_role) · 주석에 4-3b · 몸에 1096 보류 글 없음 · CADJ null 계정 없음', (select count(*)::text || ' ' || coalesce(proacl::text, '(default)') || ' ' || (obj_description(oid, 'pg_proc') ~ '4-3b')::text || ' ' || (prosrc ~ 'opens with the supplier bill round')::text || ' ' || (prosrc ~ $r$'CADJ', coalesce\(x.ca_num, x.alr\), x.lacct, null$r$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected' group by oid, proacl, prosrc), '1 {postgres=X/postgres,service_role=X/postgres} true false false');
\if :{?mig}
select pg_temp.chk('S0b(시험 갈래) qbo_cost_expected md5 가 begin 앞과 다르다', ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') <> :'pre_md5_exp')::text, 'true');
\else
select pg_temp.chk('S0b(확인 갈래) qbo_cost_expected md5 = begin 앞(이미 적용)', ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') = :'pre_md5_exp')::text, 'true');
\endif
select pg_temp.chk('G2 새 표 0 · FK 0(po_payment 에 새 FK 없음) · 장 수 그대로 · 가짜 행 수(레이어 +1 · 원장 +1 · 얹기 +2 · 조정 +2 · 결제 +3)',
  (select count(*) from pg_constraint c where c.contype = 'f' and c.conrelid = 'public.po_payment'::regclass)::text || ' ' || ((select count(*) from public.qbo_cost_sheet) = :pre_sheets)::text
  || ' ' || ((select count(*) from public.inv_layer) - :pre_layer)::text || ' ' || ((select count(*) from public.inv_ledger) - :pre_ledger)::text || ' ' || ((select count(*) from public.inv_layer_cost_add) - :pre_adds)::text || ' ' || ((select count(*) from public.inv_cost_adjust) - :pre_ica)::text || ' ' || ((select count(*) from public.po_payment) - :pre_pay)::text,
  (select count(*) from pg_constraint c where c.contype = 'f' and c.conrelid = 'public.po_payment'::regclass)::text || ' true 1 1 2 2 3');

-- ── Z(rollback 앞) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select string_agg(a.code || ':' || coalesce(a.currency_code, '-'), ' ' order by a.code) from public.ref_account a where a.code in ('_106_', '_138_', '_141_', '_144_', '_145_', '_204_')) = :'pre_usd6'
   and (select count(*) from public.po_payment) = :pre_pay and (select count(*) from public.inv_layer) = :pre_layer and (select count(*) from public.inv_ledger) = :pre_ledger and (select count(*) from public.inv_layer_cost_add) = :pre_adds
   and (select count(*) from public.inv_cost_adjust) = :pre_ica and (select value from public.inv_config where key = 'qbo_cost_since') = :'pre_since'
   and not (:{?mig} and exists (select 1 from pg_trigger where tgname = 'po_payment_account_currency_ck')) as rolled_back_clean;
