-- supabase/tests/mail_inc_1a_check.sql — mail-inc-1a 검증: to_more 칸 · CHECK · doc_mail_recipients · mail_claim 재발행(한 줄) · 무변(옛 함수 · QBO 셋 · 백오더 둘) (2026-11-03 · 판정 1000 · 1018 ~ 1029)
-- [테스트 · Asung-IMS = 운영] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 12 md5 · acl · 옛 CHECK 정의 · 498 반환 스냅샷(sale issued 인보이스 전부) · mail_claim 줄) → begin → (-v mig 면 \i) → 검사 → rollback → Z1
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103174500_mail_inc_1a_recipients.sql -f supabase/tests/mail_inc_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = 시험 49 · 확인 45(B2 · D1 ~ D3 는 적용 전 대비 +1 검사라 시험 갈래에서만 돈다)
--   결과 줄 꼴 | OK | / | MISMATCH | · 쓰기 = begin 안에서만(customer_contact 시험 행 · mail_outbox status cancelled 시험 행 · 모두 rollback) · 메일 창구(mail_claim · doc_mail_pdf_claim · doc_mail_send) 부르지 않음 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다(10 초 안)
--   셈은 전부 파일 안에서 다시 센다(보고서 숫자를 손으로 적지 않는다) — 기대값 = 「지금의 켜짐」 실물
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif

-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosrc
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('mail_claim', 'doc_mail_recipient', 'doc_mail_customer', 'doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice', 'doc_mail_list',
                     'qbo_invoice_body', 'qbo_credit_body', 'qbo_customer_body', 'mail_backorder_pick', 'mail_backorder_send', 'ims_mail_address_ok');
select (select count(*) from t_pre) as fn_n0 \gset
create temp table t_ck_pre as select conname, pg_get_constraintdef(oid) as def from pg_constraint where conrelid = 'public.mail_outbox'::regclass and contype = 'c';
select (select count(*) from t_ck_pre) as ck_n0 \gset
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox') as cols0 \gset
-- 498 반환 스냅샷 — 새 함수 만들기 전(sale · issued 인보이스 전부)
create temp table t_r498 as select i.id, i.bill_to_customer_id as b, public.doc_mail_recipient(i.bill_to_customer_id) as r from public.so_invoice i where i.kind = 'sale' and i.status = 'issued';
select (select count(*) from t_r498) as inv_n0 \gset
-- mail_claim 줄(재발행 diff 용 · 같은 줄이 여러 번 나올 수 있어 번호를 붙인다)
create temp table t_claim_old as select l.line, row_number() over (partition by l.line order by l.n) as k, l.n from t_pre p, unnest(string_to_array(p.prosrc, E'\n')) with ordinality l(line, n) where p.proname = 'mail_claim';
select (select count(*) from t_claim_old) as claim_lines0 \gset
\echo '── 기준: 함수' :fn_n0 '· mail_outbox 칸' :cols0 '· CHECK' :ck_n0 '· sale issued 인보이스' :inv_n0 '· mail_claim 줄' :claim_lines0

-- safeupdate 의 규칙을 정적으로 센다(ar_2b_check.sql 의 pg_temp.nowhere 그대로)
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
-- 켜진 바른 주소(1000 · 1020 · 1027 의 셈 재료) — 손님 · lower(btrim) 주소
create function pg_temp.fl(p_cust uuid) returns table (e text, nm text, is_default boolean, created_at timestamptz, id uuid) language sql stable as $$
  select lower(btrim(cc.email)), cc.name, cc.is_default, cc.created_at, cc.id from public.customer_contact cc
  where cc.customer_id = p_cust and cc.is_active and cc.include_in_email and public.ims_mail_address_ok(lower(btrim(cc.email)))
$$;
-- 청구처 ∪ 매장들 합집합 수(처음 나온 것만)
create function pg_temp.union_n(p_bill uuid, p_stores uuid[]) returns int language sql stable as $$
  select count(distinct f.e)::int from (select v_c from unnest(array[p_bill] || coalesce(p_stores, '{}')) v_c) c, pg_temp.fl(c.v_c) f
$$;
-- mail_outbox 에 넣어 보기(CHECK · status cancelled · rollback 됨) → 'ok' | sqlstate
create function pg_temp.try_ins(p_to text, p_more text[]) returns text language plpgsql as $$
begin
  insert into public.mail_outbox (kind, category, status, from_address, to_address, to_more, subject, dedupe_key)
  values ('doc_final_invoice', 'transactional', 'cancelled', 'info@asung.ca', p_to, p_more, 'mail-inc-1a check', 'mail-inc-1a-check:' || gen_random_uuid()::text);
  return 'ok';
exception when others then return sqlstate;
end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;

-- ═══ A. 무변 — 시험 행을 넣기 전에(옛 함수 11 md5 · acl · 498 반환 스냅샷) ═══
select pg_temp.chk('A1 옛 함수 12 md5 무변(mail_claim 뺀 전부)', (select string_agg(p.proname, ',' order by p.proname) from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname and md5(q.prosrc) = p.md5 where p.proname <> 'mail_claim'),
                   (select string_agg(proname, ',' order by proname) from t_pre where proname <> 'mail_claim'));
select pg_temp.chk('A2 옛 함수 13 acl 무변', (select count(*)::text from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname and q.proacl::text is not distinct from p.acl), :'fn_n0');
select pg_temp.chk('A3 doc_mail_recipient 반환 — sale issued 인보이스 전부 옛 값과 같다', (select count(*)::text from t_r498 t where t.r is not distinct from public.doc_mail_recipient(t.b)), :'inv_n0');
select pg_temp.chk('A4 옛 CHECK 정의 무변(to_ck · original_to_ck 포함 전부)', (select count(*)::text from t_ck_pre o join pg_constraint c on c.conrelid = 'public.mail_outbox'::regclass and c.conname = o.conname and pg_get_constraintdef(c.oid) = o.def), :'ck_n0');

-- ═══ B. 칸 · CHECK(1028 · 이견 3) ═══
select pg_temp.chk('B1 to_more 칸 — text[] not null default {} 끝에', (select column_name || '|' || data_type || '|' || is_nullable || '|' || column_default || '|' || (ordinal_position = (select max(ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox'))::text
                                                                 from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox' and column_name = 'to_more'), 'to_more|ARRAY|NO|''{}''::text[]|true');
\if :{?mig}
select pg_temp.chk('B2 칸 수 +1 · CHECK +1', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox') || '|' || (select count(*) from pg_constraint where conrelid = 'public.mail_outbox'::regclass and contype = 'c'), (:cols0 + 1)::text || '|' || (:ck_n0 + 1)::text);
\endif
select pg_temp.chk('B3 기존 행은 모두 {}', (select count(*)::text from public.mail_outbox where to_more <> '{}'), '0');
select pg_temp.chk('B4 받음 — {} · 9 개 · 대소문자 다른 둘', pg_temp.try_ins('a@x.ca', '{}') || ' ' || pg_temp.try_ins('a@x.ca', array['b1@x.ca','b2@x.ca','b3@x.ca','b4@x.ca','b5@x.ca','b6@x.ca','b7@x.ca','b8@x.ca','b9@x.ca']) || ' ' || pg_temp.try_ins('a@x.ca', array['b@x.ca', 'c@y.ca']), 'ok ok ok');
select pg_temp.chk('B5 거부 — 쉼표 · 꼴 아님 · 빈 · null 원소', pg_temp.try_ins('a@x.ca', array['b@x.ca, c@x.ca']) || ' ' || pg_temp.try_ins('a@x.ca', array['not an address']) || ' ' || pg_temp.try_ins('a@x.ca', array['']) || ' ' || pg_temp.try_ins('a@x.ca', array['b@x.ca', null]), '23514 23514 23514 23514');
select pg_temp.chk('B6 거부 — to_address 와 겹침(대소문자 · 공백) · 원소끼리 겹침 · 10 개', pg_temp.try_ins('a@x.ca', array[' A@x.ca ']) || ' ' || pg_temp.try_ins('a@x.ca', array['b@x.ca', 'B@x.ca']) || ' ' || pg_temp.try_ins('a@x.ca', array['b1@x.ca','b2@x.ca','b3@x.ca','b4@x.ca','b5@x.ca','b6@x.ca','b7@x.ca','b8@x.ca','b9@x.ca','b10@x.ca']), '23514 23514 23514');
select pg_temp.chk('B7 옛 CHECK 그대로 — to_address 쉼표 거부', pg_temp.try_ins('a@x.ca, b@x.ca', '{}'), '23514');
select pg_temp.chk('B8 helper acl = ims_mail_address_ok · immutable', (select (p.proacl::text is not distinct from (select q.proacl::text from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'ims_mail_address_ok'))::text || '|' || p.provolatile::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_mail_to_more_ok'), 'true|i');

-- ═══ C. doc_mail_recipients — 실물(1000 · 1018 · 1020 · 1021 · 1024 · 1027 · 이견 1 · 2 · 5 · 6 · 8 · 9) ═══
-- 재료 — 이름으로 찾는다(id 를 적지 않는다)
select s.id as so_keele, s.customer_id as c_keele from public.so s join public.customer c on c.id = s.customer_id where c.name = 'Beauty Collection Keele Inc.' order by s.created_at desc limit 1 \gset
select s.id as so_blw, s.customer_id as c_blw, s.bill_to_customer_id as c_clore from public.so s join public.customer c on c.id = s.customer_id join public.customer b on b.id = s.bill_to_customer_id where c.name = 'Clore Inc. (BLW)' and b.name = 'Clore Inc.' and s.status <> 'cancelled' order by s.created_at desc limit 1 \gset
select s.id as so_clore2, s.customer_id as c_clore2, c.name as n_clore2 from public.so s join public.customer c on c.id = s.customer_id where s.bill_to_customer_id = :'c_clore' and s.customer_id <> :'c_blw' and s.status <> 'cancelled' order by s.created_at desc limit 1 \gset
select s.id as so_afro, coalesce(s.bill_to_customer_id, s.customer_id) as c_afro from public.so s join public.customer c on c.id = coalesce(s.bill_to_customer_id, s.customer_id) where c.name = 'Afro Queens Beauty Supply' and s.status <> 'cancelled' order by s.created_at desc limit 1 \gset
-- 켜짐 0 · 498 있음 손님의 오더(fallback) — 이름을 적지 않고 고른다
select s.id as so_fb, coalesce(s.bill_to_customer_id, s.customer_id) as c_fb, c.name as n_fb from public.so s join public.customer c on c.id = coalesce(s.bill_to_customer_id, s.customer_id)
 where c.is_active and s.status <> 'cancelled' and not exists (select 1 from pg_temp.fl(c.id)) and (public.doc_mail_recipient(c.id)->>'to') is not null order by s.created_at desc limit 1 \gset
\echo '── 재료: Keele so' :so_keele '· Clore BLW so' :so_blw '· Clore 둘째 매장' :n_clore2 '· Afro Queens so' :so_afro '· fallback 손님' :n_fb

-- C1 Keele(sales_order · 셀프 청구 · 1000 만으로) = 켜진 바른 주소 수 · 순서 = 기본 먼저 · created_at · id · stores 0 · 모두 bill_to
select public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_keele')) as r_keele \gset
select pg_temp.chk('C1a Keele 수 = 다시 센 켜진 주소 수(보고서 3)', (select jsonb_array_length(:'r_keele'::jsonb->'list')::text), (select count(*)::text from pg_temp.fl(:'c_keele')));
select pg_temp.chk('C1b Keele 순서 = 기본 먼저 · created_at · id', (select string_agg(x->>'email', ',') from jsonb_array_elements(:'r_keele'::jsonb->'list') x), (select string_agg(e, ',' order by is_default desc, created_at, id) from pg_temp.fl(:'c_keele')));
select pg_temp.chk('C1c Keele how flags · skipped 0 · stores [] · role 모두 bill_to · how_498 null', (:'r_keele'::jsonb->>'how') || '|' || jsonb_array_length(:'r_keele'::jsonb->'skipped') || '|' || (:'r_keele'::jsonb->>'stores') || '|' || (select count(*) filter (where x->>'role' <> 'bill_to') from jsonb_array_elements(:'r_keele'::jsonb->'list') x) || '|' || coalesce(:'r_keele'::jsonb->>'how_498', 'null'), 'flags|0|[]|0|null');
select pg_temp.chk('C1d Keele customer_id = doc_mail_customer', (:'r_keele'::jsonb->>'customer_id'), public.doc_mail_customer('sales_order', jsonb_build_object('so_id', :'so_keele'))::text);

-- C2 Clore BLW(sales_order · 청구처 Clore Inc. ∪ 매장 BLW) = 합집합(보고서 5) · 공유 주소는 store 쪽이 skipped duplicate(이견 2 a)
select public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_blw')) as r_blw \gset
select pg_temp.chk('C2a Clore BLW 수 = 다시 센 합집합(보고서 5)', (select jsonb_array_length(:'r_blw'::jsonb->'list')::text), pg_temp.union_n(:'c_clore', array[:'c_blw'::uuid])::text);
select pg_temp.chk('C2b Clore BLW 순서 = 청구처(기본 · created_at · id) → 매장 · 처음 것만', (select string_agg(x->>'email', ',') from jsonb_array_elements(:'r_blw'::jsonb->'list') x),
  (select string_agg(e, ',' order by n) from (select e, min(n) n from (select f.e, row_number() over (order by c.ord, f.is_default desc, f.created_at, f.id) n from (values (:'c_clore'::uuid, 0), (:'c_blw'::uuid, 1)) c(id, ord), pg_temp.fl(c.id) f) z group by e) y));
select pg_temp.chk('C2c Clore BLW skipped duplicate 수 = 매장이 청구처와 함께 켠 주소 수 · 모두 role store', (select count(*) filter (where x->>'reason' = 'duplicate' and x->>'role' = 'store')::text || '|' || count(*) filter (where x->>'reason' <> 'duplicate' or x->>'role' <> 'store') from jsonb_array_elements(:'r_blw'::jsonb->'skipped') x),
  (select count(*)::text from pg_temp.fl(:'c_blw') s where s.e in (select e from pg_temp.fl(:'c_clore'))) || '|0');
select pg_temp.chk('C2d Clore BLW how flags · stores = [BLW] · list 의 customer_id ∈ {Clore, BLW}', (:'r_blw'::jsonb->>'how') || '|' || (:'r_blw'::jsonb->>'stores') || '|' || (select count(*) filter (where (x->>'customer_id')::uuid not in (:'c_clore'::uuid, :'c_blw'::uuid)) from jsonb_array_elements(:'r_blw'::jsonb->'list') x), 'flags|' || jsonb_build_array(:'c_blw'::uuid)::text || '|0');

-- C3 인보이스 — 매장 ≠ 청구처인 sale issued 인보이스 전부(보고서 2 장 · 파일이 다시 찾는다) · 수 = 합집합 · stores 1 · how flags
create temp table t_inv2 as
  select i.id, i.bill_to_customer_id b, array(select distinct o.customer_id from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null and o.customer_id is not null) st,
         public.doc_mail_recipients('final_invoice', jsonb_build_object('invoice_id', i.id)) r
  from public.so_invoice i where i.kind = 'sale' and i.status = 'issued'
   and exists (select 1 from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null and o.customer_id <> i.bill_to_customer_id);
select (select count(*) from t_inv2) as inv2_n \gset
\echo '── 매장 ≠ 청구처 인보이스' :inv2_n '장'
select pg_temp.chk('C3a 매장 ≠ 청구처 인보이스 — 수 = 합집합 (전부)', (select count(*)::text from t_inv2 t where jsonb_array_length(t.r->'list') = pg_temp.union_n(t.b, t.st)), :'inv2_n');
select pg_temp.chk('C3b 매장 ≠ 청구처 인보이스 — how flags · stores = 오더 매장(청구처 뺀) (전부)', (select count(*)::text from t_inv2 t where t.r->>'how' = 'flags' and (t.r->'stores') = (select to_jsonb(array(select s from unnest(t.st) s where s <> t.b)))), :'inv2_n');
select pg_temp.chk('C3c 매장 = 청구처 인보이스 전부 — stores [] · 수 = 청구처 켜진 주소 수(0 이면 498)', (select count(*)::text from public.so_invoice i, lateral public.doc_mail_recipients('final_invoice', jsonb_build_object('invoice_id', i.id)) r
    where i.kind = 'sale' and i.status = 'issued' and not exists (select 1 from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null and o.customer_id <> i.bill_to_customer_id)
      and r->>'stores' = '[]' and jsonb_array_length(r->'list') = case when pg_temp.union_n(i.bill_to_customer_id, '{}') > 0 then pg_temp.union_n(i.bill_to_customer_id, '{}') when (public.doc_mail_recipient(i.bill_to_customer_id)->>'to') is not null then 1 else 0 end),
  (select count(*)::text from public.so_invoice i where i.kind = 'sale' and i.status = 'issued' and not exists (select 1 from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null and o.customer_id <> i.bill_to_customer_id)));
select pg_temp.chk('C3d sale issued 인보이스 — how 가 none 인 장(보고서 「498 도 없음 0」)', (select count(*)::text from public.so_invoice i where i.kind = 'sale' and i.status = 'issued' and public.doc_mail_recipients('final_invoice', jsonb_build_object('invoice_id', i.id))->>'how' = 'none'),
  (select count(*)::text from public.so_invoice i where i.kind = 'sale' and i.status = 'issued' and pg_temp.union_n(i.bill_to_customer_id, array(select distinct o.customer_id from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null)) = 0 and (public.doc_mail_recipient(i.bill_to_customer_id)->>'to') is null));

-- C4 Afro Queens — 빈 이메일 켜짐(실측) → skipped blank 에 이름으로(이견 2 b)
select public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_afro')) as r_afro \gset
select pg_temp.chk('C4a Afro Queens 수 = 켜진 바른 주소 수', (select jsonb_array_length(:'r_afro'::jsonb->'list')::text), (select count(*)::text from pg_temp.fl(:'c_afro')));
select pg_temp.chk('C4b Afro Queens skipped blank = 켜진 빈 이메일 연락처(이름)', (select string_agg(x->>'name', ',' order by x->>'name') from jsonb_array_elements(:'r_afro'::jsonb->'skipped') x where x->>'reason' = 'blank'),
  (select string_agg(cc.name, ',' order by cc.name) from public.customer_contact cc where cc.customer_id = :'c_afro' and cc.is_active and cc.include_in_email and nullif(btrim(cc.email), '') is null));

-- C5 fallback_498 — 켜짐 0 · 498 있음(1021 가 · 이견 8) · 그 손님을 시험 안에서 꺼 none(이견 6)
select public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_fb')) as r_fb \gset
select pg_temp.chk('C5a fallback — how fallback_498 · list 1 = 498 주소 · role bill_to · how_498 = 옛 how', (:'r_fb'::jsonb->>'how') || '|' || jsonb_array_length(:'r_fb'::jsonb->'list') || '|' || (:'r_fb'::jsonb->'list'->0->>'email') || '|' || (:'r_fb'::jsonb->'list'->0->>'role') || '|' || (:'r_fb'::jsonb->>'how_498'),
  'fallback_498|1|' || (public.doc_mail_recipient(:'c_fb')->>'to') || '|bill_to|' || (public.doc_mail_recipient(:'c_fb')->>'how'));
select pg_temp.chk('C5b fallback — name = 그 주소의 첫 활성 연락처', (:'r_fb'::jsonb->'list'->0->>'name'), (select cc.name from public.customer_contact cc where cc.customer_id = :'c_fb' and cc.is_active and lower(btrim(cc.email)) = (public.doc_mail_recipient(:'c_fb')->>'to') order by cc.is_default desc, cc.created_at, cc.id limit 1));
update public.customer_contact set is_active = false where customer_id = :'c_fb';                                    -- 시험 안에서 끄기(rollback)
select pg_temp.chk('C5c none — 연락처를 모두 끄면 how none · list [] · how_498 null', (select (r->>'how') || '|' || (r->>'list') || '|' || coalesce(r->>'how_498', 'null') from public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_fb')) r), 'none|[]|null');
select pg_temp.chk('C5d 없는 문서 — how none · customer_id null', (select (r->>'how') || '|' || coalesce(r->>'customer_id', 'null') from public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', gen_random_uuid())) r), 'none|null');

-- C6 ship_ready 매장 둘(1024 · 실제 Clore 오더 둘 · insert 0) = 세 손님 합집합 · stores 2 · 순서 = orders 순
select public.doc_mail_recipients('ship_ready', jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_blw'), jsonb_build_object('so_id', :'so_clore2')))) as r_sr \gset
select pg_temp.chk('C6a ship_ready 매장 둘 — 수 = 세 손님 합집합', (select jsonb_array_length(:'r_sr'::jsonb->'list')::text), pg_temp.union_n(:'c_clore', array[:'c_blw'::uuid, :'c_clore2'::uuid])::text);
select pg_temp.chk('C6b ship_ready 매장 둘 — stores [BLW, 둘째] · how flags · customer_id Clore', (:'r_sr'::jsonb->>'stores') || '|' || (:'r_sr'::jsonb->>'how') || '|' || (:'r_sr'::jsonb->>'customer_id'), jsonb_build_array(:'c_blw'::uuid, :'c_clore2'::uuid)::text || '|flags|' || :'c_clore');
select pg_temp.chk('C6c ship_ready 같은 오더 둘 — stores 는 하나(겹친 매장 제거)', (select r->>'stores' from public.doc_mail_recipients('ship_ready', jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_blw'), jsonb_build_object('so_id', :'so_blw')))) r), jsonb_build_array(:'c_blw'::uuid)::text);

-- C7 시험 행(customer_contact 에만 · Keele) — 상한 10 → cap · 한 손님 안 겹침 → duplicate · 꼴 아님(Nu Yu 의 실측 문자열) → bad_shape(이견 2 b · 4)
select (select count(*) from pg_temp.fl(:'c_keele')) as keele_n \gset
insert into public.customer_contact (customer_id, source, name, email, include_in_email, is_default)
  select :'c_keele', 'manual', 'mail-inc-1a test ' || g, 't' || g || '@example.test', true, false from generate_series(1, 8) g;
insert into public.customer_contact (customer_id, source, name, email, include_in_email, is_default) values
  (:'c_keele', 'manual', 'mail-inc-1a dup',  ' ' || upper((select e from pg_temp.fl(:'c_keele') order by is_default desc, created_at, id limit 1)) || ' ', true, false),
  (:'c_keele', 'manual', 'mail-inc-1a bad',  'INVOICE ONLY: nuyu@rogers.com', true, false);
select public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_keele')) as r_cap \gset
select pg_temp.chk('C7a 상한 — 켜진 바른 주소 ' || (:keele_n + 8) || ' → list 10 · skipped cap ' || (:keele_n + 8 - 10), jsonb_array_length(:'r_cap'::jsonb->'list')::text || '|' || (select count(*) filter (where x->>'reason' = 'cap') from jsonb_array_elements(:'r_cap'::jsonb->'skipped') x), '10|' || (:keele_n + 8 - 10)::text);
select pg_temp.chk('C7b 겹침 — 대소문자 · 공백만 다른 주소 → skipped duplicate 1(이름)', (select string_agg(x->>'name', ',') from jsonb_array_elements(:'r_cap'::jsonb->'skipped') x where x->>'reason' = 'duplicate'), 'mail-inc-1a dup');
select pg_temp.chk('C7c 꼴 아님 — skipped bad_shape 1(이름 · 원문 btrim)', (select string_agg((x->>'name') || '|' || (x->>'email'), ',') from jsonb_array_elements(:'r_cap'::jsonb->'skipped') x where x->>'reason' = 'bad_shape'), 'mail-inc-1a bad|INVOICE ONLY: nuyu@rogers.com');
select pg_temp.chk('C7d list 는 모두 바른 꼴 · 겹침 없음 · 앞 ' || :keele_n || ' 은 원래 순서', (select (count(*) filter (where not public.ims_mail_address_ok(x->>'email')))::text || '|' || (count(*) - count(distinct x->>'email')) from jsonb_array_elements(:'r_cap'::jsonb->'list') x) || '|' || (select string_agg(z.x->>'email', ',' order by z.n) from (select t.x, t.n from jsonb_array_elements(:'r_cap'::jsonb->'list') with ordinality t(x, n) where t.n <= :keele_n) z), '0|0|' || (select string_agg(x->>'email', ',') from jsonb_array_elements(:'r_keele'::jsonb->'list') x));
update public.customer_contact set include_in_email = false where customer_id = :'c_clore';                          -- 시험 안에서 청구처 켜짐 0 으로(rollback)
select pg_temp.chk('C7e 1021 — 청구처 켜짐 0 · 매장 켜짐 있음 → how flags · 매장 주소만(이견 9)', (select (r->>'how') || '|' || jsonb_array_length(r->'list') || '|' || (select count(*) filter (where x->>'role' <> 'store') from jsonb_array_elements(r->'list') x)
    from public.doc_mail_recipients('sales_order', jsonb_build_object('so_id', :'so_blw')) r), 'flags|' || (select count(*) from pg_temp.fl(:'c_blw')) || '|0');

-- ═══ D. mail_claim 재발행 — 한 줄 · 그 밖 바이트 무변 · acl · nowhere ═══
create temp table t_claim_new as select l.line, row_number() over (partition by l.line order by l.n) as k, l.n from pg_proc p, unnest(string_to_array(p.prosrc, E'\n')) with ordinality l(line, n) where p.pronamespace = 'public'::regnamespace and p.proname = 'mail_claim';
\if :{?mig}
select pg_temp.chk('D1 mail_claim md5 바뀜', (select (md5(q.prosrc) <> p.md5)::text from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname where p.proname = 'mail_claim'), 'true');
select pg_temp.chk('D2 mail_claim 줄 diff — 더한 줄 1 · 뺀 줄 0 · 줄 수 +1', (select count(*)::text from (select line, k from t_claim_new except select line, k from t_claim_old) a) || '|' || (select count(*) from (select line, k from t_claim_old except select line, k from t_claim_new) d) || '|' || (select count(*) from t_claim_new), '1|0|' || (:claim_lines0 + 1)::text);
select pg_temp.chk('D3 더한 줄 = to_more 한 줄', (select btrim(line) from (select line, k from t_claim_new except select line, k from t_claim_old) a), '''to_more'', u.to_more,');
\endif
select pg_temp.chk('D4 pg_get_functiondef(mail_claim) 에 to_more 한 번', (select count(*)::text from regexp_matches(pg_get_functiondef('public.mail_claim(integer)'::regprocedure), '''to_more'', u\.to_more', 'g')), '1');
select pg_temp.chk('D5 mail_claim acl 무변(postgres · service_role)', (select q.proacl::text from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'mail_claim'), (select acl from t_pre where proname = 'mail_claim'));
select pg_temp.chk('D6 nowhere 자기 시험(ar_2b 와 같은 7)', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('D7 nowhere — mail_claim · doc_mail_recipients · ims_mail_to_more_ok = 0', (select string_agg(proname || ':' || pg_temp.nowhere(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('mail_claim', 'doc_mail_recipients', 'ims_mail_to_more_ok')), 'doc_mail_recipients:0,ims_mail_to_more_ok:0,mail_claim:0');

-- ═══ E. 새 함수 권한 · 꼴 ═══
select pg_temp.chk('E1 doc_mail_recipients — anon · authenticated · public 못 부름 · service_role · postgres 부름 · stable · invoker', (select (not has_function_privilege('anon', p.oid, 'execute'))::text || (not has_function_privilege('authenticated', p.oid, 'execute'))::text || has_function_privilege('service_role', p.oid, 'execute')::text || has_function_privilege('postgres', p.oid, 'execute')::text || '|' || p.provolatile::text || '|' || p.prosecdef::text || '|' || (p.proacl::text is not distinct from (select acl from t_pre where proname = 'doc_mail_recipient'))::text
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'doc_mail_recipients'), 'truetruetruetrue|s|false|true');
select pg_temp.chk('E2 반환 열쇠 = customer_id · how · how_498 · list · skipped · stores', (select string_agg(k, ',' order by k) from jsonb_object_keys(:'r_blw'::jsonb) k), 'customer_id,how,how_498,list,skipped,stores');
select pg_temp.chk('E3 list 원소 열쇠 = customer_id · email · name · role · skipped 원소 = + reason', (select string_agg(k, ',' order by k) from jsonb_object_keys(:'r_blw'::jsonb->'list'->0) k) || '|' || (select string_agg(k, ',' order by k) from jsonb_object_keys(:'r_cap'::jsonb->'skipped'->0) k), 'customer_id,email,name,role|customer_id,email,name,reason,role');
select pg_temp.chk('E4 comment 셋(칸 · 함수 둘) · mail_claim comment 에 to_more', ((col_description('public.mail_outbox'::regclass, (select attnum from pg_attribute where attrelid = 'public.mail_outbox'::regclass and attname = 'to_more')) ~ '1028')::text || (obj_description('public.doc_mail_recipients(text, jsonb)'::regprocedure, 'pg_proc') ~ '1026')::text || (obj_description('public.ims_mail_to_more_ok(text, text[])'::regprocedure, 'pg_proc') ~ '1027')::text || (obj_description('public.mail_claim(integer)'::regprocedure, 'pg_proc') ~ 'to_more')::text), 'truetruetruetrue');

-- ═══ F. NOTICE — Caleb 이 본다(검사 아님) ═══
do $$
declare r record; v_n int := 0;
begin
  raise notice '── 1020(가) 셀프 청구 손님 중 켜진 연락처가 있는데 기본이 꺼져 빠지는 곳(보고서 3) — Customers 에서 확인:';
  for r in
    select c.name, (select lower(btrim(cc.email)) from public.customer_contact cc where cc.customer_id = c.id and cc.is_active and cc.is_default limit 1) dropped_default,
           (select string_agg(f.e, ', ' order by f.is_default desc, f.created_at, f.id) from pg_temp.fl(c.id) f) goes_to
    from public.customer c where c.is_active and c.default_bill_to_customer_id is null and exists (select 1 from pg_temp.fl(c.id))
     and exists (select 1 from public.customer_contact cc where cc.customer_id = c.id and cc.is_active and cc.is_default and public.ims_mail_address_ok(lower(btrim(cc.email))) and lower(btrim(cc.email)) not in (select e from pg_temp.fl(c.id)))
    order by c.name
  loop
    v_n := v_n + 1;
    raise notice '   % — 기본(꺼짐 · 빠짐) % → 받는 이 %', r.name, r.dropped_default, r.goes_to;
  end loop;
  raise notice '   = % 손님', v_n;
  raise notice '── 켜졌는데 빈 이메일 · 꼴 아님(실측 · 시험 행 제외):';
  for r in
    select c.name cname, cc.name, coalesce(cc.email, '<null>') email from public.customer_contact cc join public.customer c on c.id = cc.customer_id
    where c.is_active and cc.is_active and cc.include_in_email and cc.name not like 'mail-inc-1a %' and (nullif(btrim(cc.email), '') is null or not public.ims_mail_address_ok(lower(btrim(cc.email)))) order by 1, 2
  loop
    raise notice '   % — % [%]', r.cname, r.name, r.email;
  end loop;
end $$;
\echo '── Clore BLW 실물(list · skipped):'
select jsonb_pretty(:'r_blw'::jsonb);

-- ── 결과 ──
select clock_timestamp() as t_end0 \gset
\echo '── 결과(| OK | / | MISMATCH |) ──'
select n, case when ok then '| OK |' else '| MISMATCH |' end as res, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n from t_res \gset
rollback;
\echo '── Z1 OK' :ok_n '· MISMATCH' :bad_n '· begin ~ rollback' :t_begin0 '→' :t_end0
