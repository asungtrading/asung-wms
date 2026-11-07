-- supabase/tests/mail_inc_1c_check.sql — mail-inc-1c 검증: to_more 채우기 — doc_mail_enqueue 11 인자(한 벌) · doc_mail_send(키 off 옛 꼴 · on 새 길 · p_to 목록) · doc_mail_auto_invoice(복제 인보이스 + 트리거 즉시) · 무변(옛 함수 · QBO · 백오더 · CHECK) (2026-11-07 · 판정 1000 · 1018 ~ 1029 · 529)
-- [테스트 · Asung-IMS = IMS 메인 · ⚠️ 메일 켜짐] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 md5 · acl · CHECK · 칸 수 · 옛 줄) → begin → (-v mig 면 \i) → 검사 → rollback → Z(시험이 만든 줄 0)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107044600_mail_inc_1c_fill_recipients.sql -f supabase/tests/mail_inc_1c_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = EXPECT_OK(갈래마다 · 아래)
--   결과 줄 꼴 | OK | / | MISMATCH | · 쓰기 = begin 안에서만(inv_config doc_mail_multi upsert · customer_contact 시험 행 · customer.final_invoice_mail · so_invoice 복제 99999991 ~ 4 · mail_outbox 시험 줄 — 모두 rollback)
--   ⚠️ mail_claim · mail_mark · doc_mail_pdf_claim 은 부르지 않는다(실제 큐) · doc_mail_send commit true 는 rollback 안에서만 · 시험 주소 도메인 @mailinc1c.test · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다(10 초 안)
--   직원 흉내 = request.jwt.claims(시스템 manager · ac_count_1_check 와 같은 길) · 자동 트리거 = set constraints so_invoice_doc_mail_auto immediate(지연 트리거를 문장 끝에 돌린다 · rollback 이라 commit 이 없다)
--   손님 · 사람 이름 · 이메일을 적지 않는다(공개 레포 · 99-e 77) — 재료는 조건으로 고른다
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
\if :{?mig}
\set EXPECT_OK 36
\else
\set EXPECT_OK 33
\endif

-- ── 기준(begin 앞 · 읽기만) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosrc, pg_get_function_identity_arguments(p.oid) as args
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice',
                     'doc_mail_recipient', 'doc_mail_recipients', 'doc_mail_customer', 'doc_mail_fill', 'doc_mail_list', 'doc_mail_cancel', 'doc_mail_attach', 'doc_mail_pdf_claim', 'doc_mail_pdf_failed',
                     'mail_claim', 'mail_mark', 'ims_mail_address_ok', 'ims_mail_to_more_ok', 'qbo_invoice_body', 'qbo_credit_body', 'qbo_customer_body', 'mail_backorder_pick', 'mail_backorder_send');
select (select count(*) from t_pre) as fn_n0 \gset
create temp table t_ck_pre as select conname, pg_get_constraintdef(oid) as def from pg_constraint where conrelid = 'public.mail_outbox'::regclass and contype = 'c';
select (select count(*) from t_ck_pre) as ck_n0 \gset
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox') as cols0 \gset
select (select count(*) from public.mail_outbox) as out_n0, (select count(*) from public.doc_mail_skip) as skip_n0, (select count(*) from public.so_invoice) as inv_n0,
       (select count(*) from public.inv_config where key = 'doc_mail_multi') as key_n0 \gset
-- 옛 줄(재발행 diff 용 · 같은 줄이 여러 번 나올 수 있어 번호를 붙인다)
create temp table t_old as select p.proname, l.line, row_number() over (partition by p.proname, l.line order by l.n) as k, l.n from t_pre p, unnest(string_to_array(p.prosrc, E'\n')) with ordinality l(line, n) where p.proname in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice');
-- 재료(조건으로 고른다 · 이름 없음)
select (select auth_user_id::text from public.ims_staff where id = '00000000-0000-4000-a000-000000000001') as u_mgr \gset
-- B = 셀프 청구 손님 · 열린 SO(confirmed · packed · picking · at_wms) 하나 · sale issued 셀프 인보이스 하나 · 기본 연락처에 바른 이메일(498 이 있다)
select s.id::text as so_b, s.customer_id::text as b from public.so s
 where s.status in ('confirmed', 'packed', 'picking', 'at_wms') and coalesce(s.bill_to_customer_id, s.customer_id) = s.customer_id
   and exists (select 1 from public.so_invoice i where i.bill_to_customer_id = s.customer_id and i.kind = 'sale' and i.status = 'issued' and i.store_customer_id is null
                 and not exists (select 1 from public.so_invoice_order o where o.invoice_id = i.id and o.customer_id <> i.bill_to_customer_id))
   and exists (select 1 from public.customer_contact cc where cc.customer_id = s.customer_id and cc.is_active and cc.is_default and public.ims_mail_address_ok(lower(btrim(cc.email))))
 order by s.created_at desc limit 1 \gset
select i.id::text as inv_b from public.so_invoice i where i.bill_to_customer_id = :'b' and i.kind = 'sale' and i.status = 'issued' and i.store_customer_id is null
   and not exists (select 1 from public.so_invoice_order o where o.invoice_id = i.id and o.customer_id <> i.bill_to_customer_id) order by i.created_at desc limit 1 \gset
-- P(청구처) ≠ S(매장) 인 열린 SO 하나
select s.id::text as so_st, s.bill_to_customer_id::text as p, s.customer_id::text as s from public.so s
 where s.status in ('confirmed', 'packed', 'picking', 'at_wms') and s.bill_to_customer_id is not null and s.bill_to_customer_id <> s.customer_id
   and s.customer_id <> :'b'::uuid and s.bill_to_customer_id <> :'b'::uuid
 order by s.created_at desc limit 1 \gset
\echo '── 기준: 함수' :fn_n0 '· mail_outbox 칸' :cols0 '· CHECK' :ck_n0 '· outbox' :out_n0 '· skip' :skip_n0 '· invoice' :inv_n0 '· 키' :key_n0 '· 재료 B so' :so_b 'inv' :inv_b '· 매장 SO' :so_st

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
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
-- 미리 보기(commit false) · 보내기(commit true) 한 줄 — 시험 줄은 반드시 rollback
create function pg_temp.pv(p_kind text, p_ref jsonb, p_to text default null) returns jsonb language sql as $$
  select public.doc_mail_send(p_kind, p_ref, p_to, null, null, false, null);
$$;
create function pg_temp.send(p_kind text, p_ref jsonb, p_to text default null) returns jsonb language sql as $$
  select public.doc_mail_send(p_kind, p_ref, p_to, null, null, true, null);
$$;
-- 시험 연락처 — created_at 을 초 단위로 띄워 순서를 못 박는다(같은 트랜잭션은 now() 가 같다)
create function pg_temp.contact(p_cust uuid, p_tag text, p_email text, p_sec int, p_on boolean default true) returns void language sql as $$
  insert into public.customer_contact (customer_id, source, name, email, include_in_email, is_default, created_at) values (p_cust, 'manual', 'mail-inc-1c ' || p_tag, p_email, p_on, false, now() + make_interval(secs => p_sec));
$$;
-- 인보이스 복제(주문 없음 · 번호 9999999n · store 지정) — 트리거 즉시 모드면 문장 끝에 doc_mail_auto_invoice 가 돈다
create function pg_temp.clone_inv(p_src uuid, p_number text, p_store uuid) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.so_invoice select r.* from public.so_invoice i, jsonb_populate_record(null::public.so_invoice, to_jsonb(i) || jsonb_build_object('id', v_id, 'invoice_number', p_number, 'store_customer_id', p_store, 'created_at', now(), 'updated_at', now())) r where i.id = p_src;
  return v_id;
end $$;
-- 주문 줄 복제(reissue 시험) — 생성 칸 active_so_id 는 빼고 · cancelled_at = now()(active_so_id 유니크를 피한다 · 트리거의 reissue 검사는 so_id 만 본다)
create function pg_temp.clone_orders(p_src_inv uuid, p_new_inv uuid) returns int language plpgsql as $$
declare v_cols text; v_vals text; v_n int;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position),
         string_agg(case column_name when 'id' then 'gen_random_uuid()' when 'invoice_id' then quote_literal(p_new_inv) || '::uuid' when 'cancelled_at' then 'now()' else 'o.' || quote_ident(column_name) end, ', ' order by ordinal_position)
    into v_cols, v_vals
  from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_order' and is_generated = 'NEVER';
  execute format('insert into public.so_invoice_order (%s) select %s from public.so_invoice_order o where o.invoice_id = %L', v_cols, v_vals, p_src_inv);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
create function pg_temp.outbox_of(p_inv uuid) returns public.mail_outbox language sql as $$
  select m.* from public.mail_outbox m where m.kind = 'doc_final_invoice' and m.payload->'ref'->>'invoice_id' = p_inv::text order by m.created_at desc limit 1;
$$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select pg_temp.as_user(:'u_mgr');
select clock_timestamp() as t_mig \gset

-- ═══ A. 무변 — 옛 함수 md5 · acl · CHECK · 칸 수 ═══
select pg_temp.chk('A1 재발행 셋 뺀 함수 md5 무변', (select string_agg(p.proname, ',' order by p.proname) from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname and md5(q.prosrc) = p.md5 where p.proname not in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice')),
                   (select string_agg(proname, ',' order by proname) from t_pre where proname not in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice')));
select pg_temp.chk('A2 함수 acl 무변(재발행 셋 포함 전부)', (select count(*)::text from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname and q.proacl::text is not distinct from p.acl), :'fn_n0');
select pg_temp.chk('A3 mail_outbox CHECK 정의 무변 · 칸 수 무변', (select count(*)::text from t_ck_pre o join pg_constraint c on c.conrelid = 'public.mail_outbox'::regclass and c.conname = o.conname and pg_get_constraintdef(c.oid) = o.def) || '|' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox'), :'ck_n0' || '|' || :'cols0');
select pg_temp.chk('A4 doc_mail_send · doc_mail_auto_invoice 시그니처 무변 · 트리거 so_invoice_doc_mail_auto 지연 그대로', (select args from pg_proc p, lateral pg_get_function_identity_arguments(p.oid) args where p.pronamespace = 'public'::regnamespace and p.proname = 'doc_mail_send') || '|' || (select count(*) from pg_trigger where tgrelid = 'public.so_invoice'::regclass and tgname = 'so_invoice_doc_mail_auto' and tgdeferrable and tginitdeferred and tgfoid = 'public.doc_mail_auto_invoice()'::regprocedure),
                   (select args from t_pre where proname = 'doc_mail_send') || '|1');

-- ═══ B. 한 벌씩 · 꼴 · nowhere(REST 겹 ①) ═══
select pg_temp.chk('B1 doc_mail_enqueue 한 벌 · 11 인자', (select count(*)::text || '|' || string_agg(pg_get_function_identity_arguments(oid), ';') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue'),
                   '1|p_kind text, p_ref jsonb, p_to text, p_subject text, p_body text, p_customer_id uuid, p_staff uuid, p_doc_file_id uuid, p_auto boolean, p_to_more text[], p_recipients jsonb');
select pg_temp.chk('B2 doc_mail_send 한 벌 · doc_mail_auto_invoice 한 벌', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') || '|' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice'), '1|1');
select pg_temp.chk('B3 enqueue acl = postgres · service_role 만 · invoker volatile', (select proacl::text || '|' || provolatile::text || '|' || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue'), '{postgres=X/postgres,service_role=X/postgres}|v|false');
select pg_temp.chk('B4 send — anon 못 부름 · authenticated 부름 · definer volatile', (select (not has_function_privilege('anon', p.oid, 'execute'))::text || has_function_privilege('authenticated', p.oid, 'execute')::text || '|' || p.provolatile::text || '|' || p.prosecdef::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'doc_mail_send'), 'truetrue|v|true');
select pg_temp.chk('B5 nowhere 자기 시험(ar_2b 와 같은 7)', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('B6 nowhere — 재발행 셋 = 0', (select string_agg(proname || ':' || pg_temp.nowhere(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice')), 'doc_mail_auto_invoice:0,doc_mail_enqueue:0,doc_mail_send:0');
select pg_temp.chk('B7 comment 셋에 mail-inc-1c', ((obj_description('public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)'::regprocedure) ~ 'mail-inc-1c')::text || (obj_description('public.doc_mail_auto_invoice()'::regprocedure) ~ 'mail-inc-1c')::text || (obj_description('public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean, text[], jsonb)'::regprocedure) ~ 'mail-inc-1c')::text), 'truetruetrue');

-- ═══ D. 재발행 diff(시험 갈래만) — 뺀 줄은 의도한 것만 ═══
create temp table t_new as select p.proname, l.line, row_number() over (partition by p.proname, l.line order by l.n) as k, l.n from pg_proc p, unnest(string_to_array(p.prosrc, E'\n')) with ordinality l(line, n) where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice');
\if :{?mig}
select pg_temp.chk('D1 셋 다 md5 바뀜', (select count(*)::text from t_pre p join pg_proc q on q.pronamespace = 'public'::regnamespace and q.proname = p.proname and md5(q.prosrc) <> p.md5 where p.proname in ('doc_mail_send', 'doc_mail_enqueue', 'doc_mail_auto_invoice')), '3');
select pg_temp.chk('D2 뺀 줄 수(함수별) — send 6 · enqueue 4 · auto 6', (select string_agg(proname || ':' || n, ',' order by proname) from (select proname, count(*) n from (select proname, line, k from t_old except select proname, line, k from t_new) d group by proname) z), 'doc_mail_auto_invoice:6,doc_mail_enqueue:4,doc_mail_send:6');
select pg_temp.chk('D3 뺀 줄은 전부 받는 이 · enqueue 호출 · insert · 반환 · declare 줄(그 밖 0)', (select count(*)::text from (select proname, line, k from t_old except select proname, line, k from t_new) d
    where d.line !~ '(doc_mail_recipient\(|v_to|doc_mail_enqueue\(|insert into public\.mail_outbox|values \(''doc_'' \|\||''doc_kind'', p_kind|return jsonb_build_object\(''outbox_id''|''redirect_to'', v_redirect|v_rcpt->>''to'' is null|''no_email''|^\s+return null;$|^\s+end if;$)'), '0');
\echo '── 뺀 줄(원문):'
select d.proname, d.line from (select o.proname, o.line, min(o.n) n from t_old o where not exists (select 1 from t_new w where w.proname = o.proname and w.line = o.line and w.k = o.k) group by o.proname, o.line) d order by d.proname, d.n;
\endif

select clock_timestamp() as t_abd \gset
-- ═══ C. 기능 — 키 off(옛 꼴) → on(새 길) · B(셀프) · P ≠ S(매장) · 자동 트리거 ═══
-- 바탕: 세 손님의 켜짐을 전부 끈다(rollback) · 키는 upsert 로 off(없음과 같은 뜻 · 확인 갈래에서 켜져 있어도 같은 자리)
update public.customer_contact set include_in_email = false where customer_id in (:'b'::uuid, :'p'::uuid, :'s'::uuid);
insert into public.inv_config (key, value) values ('doc_mail_multi', 'off') on conflict (key) do update set value = excluded.value;
select (public.doc_mail_recipient(:'b'::uuid)->>'to') as b498 \gset
select pg_temp.chk('C0 바탕 — B 의 498 주소 있음 · 켜진 연락처 0 · 키 off', (:'b498' is not null)::text || '|' || (select count(*) from public.customer_contact cc where cc.customer_id = :'b'::uuid and cc.is_active and cc.include_in_email) || '|' || (select value from public.inv_config where key = 'doc_mail_multi'), 'true|0|off');
-- 키 off = 옛 길 그대로
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as pv_off \gset
select pg_temp.chk('C1 off — 미리 보기 열쇠 = 옛 14 개 그대로(recipients · to_more 없음) · to = 498', (select string_agg(k, ',' order by k) from jsonb_object_keys(:'pv_off'::jsonb) k) || '|' || (:'pv_off'::jsonb->>'to'),
                   'body,committed,customer_id,doc_file_id,from,from_name,kind,redirect_to,reply_to,subject,to,to_default,to_how,would_status|' || :'b498');
select pg_temp.chk('C2 off — 쉼표 목록은 옛 거부(Not one email address: 글 전체)', (pg_temp.try(format('select pg_temp.pv(%L, %L::jsonb, %L)::text', 'final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 'a@mailinc1c.test, b@mailinc1c.test')) like 'ERR P0001: Not one email address: a@mailinc1c.test, b@mailinc1c.test — nothing was saved%')::text, 'true');
select pg_temp.send('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as s_off \gset
select pg_temp.chk('C3 off — 보내기 줄: to_address 498 · to_more {} · payload 에 recipients 없음 · waiting_pdf · 반환 to_more []', (select m.to_address || '|' || m.to_more::text || '|' || (m.payload ? 'recipients')::text || '|' || m.status from public.mail_outbox m where m.id = (:'s_off'::jsonb->>'outbox_id')::uuid) || '|' || (:'s_off'::jsonb->>'to_more'), :'b498' || '|{}|false|waiting_pdf|[]');
select clock_timestamp() as t_c3 \gset
-- 키 on
update public.inv_config set value = 'on' where key = 'doc_mail_multi';
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as pv0 \gset
select pg_temp.chk('C4 on · 켜짐 0 — to = 498 · to_first 같음 · to_more [] · recipients.how · source fallback_498 · 열쇠 +3', (:'pv0'::jsonb->>'to') || '|' || (:'pv0'::jsonb->>'to_first') || '|' || (:'pv0'::jsonb->>'to_more') || '|' || (:'pv0'::jsonb->'recipients'->>'how') || '|' || (:'pv0'::jsonb->'recipients'->>'source') || '|' || (select count(*) from jsonb_object_keys(:'pv0'::jsonb)),
                   :'b498' || '|' || :'b498' || '|[]|fallback_498|fallback_498|17');
select pg_temp.chk('C4b recipients 열쇠 = how · how_498 · list · skipped · source · stores', (select string_agg(k, ',' order by k) from jsonb_object_keys(:'pv0'::jsonb->'recipients') k), 'how,how_498,list,skipped,source,stores');
select pg_temp.contact(:'b'::uuid, 't1', 't1@mailinc1c.test', 1);
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as pv1 \gset
select pg_temp.chk('C5 켜짐 1 — to = 그것 · to_more [] · how flags', (:'pv1'::jsonb->>'to') || '|' || (:'pv1'::jsonb->>'to_more') || '|' || (:'pv1'::jsonb->'recipients'->>'how'), 't1@mailinc1c.test|[]|flags');
select pg_temp.contact(:'b'::uuid, 't2', 'T2@MailInc1c.test', 2);
select pg_temp.contact(:'b'::uuid, 't3', ' t3@mailinc1c.test ', 3);
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as pv3 \gset
select pg_temp.chk('C6 켜짐 3 — to = "a, b, c"(lower · btrim · created_at 순) · to_first · to_more 2 · list 3 · skipped 0', (:'pv3'::jsonb->>'to') || '|' || (:'pv3'::jsonb->>'to_first') || '|' || (:'pv3'::jsonb->>'to_more') || '|' || jsonb_array_length(:'pv3'::jsonb->'recipients'->'list') || '|' || jsonb_array_length(:'pv3'::jsonb->'recipients'->'skipped'),
                   't1@mailinc1c.test, t2@mailinc1c.test, t3@mailinc1c.test|t1@mailinc1c.test|["t2@mailinc1c.test", "t3@mailinc1c.test"]|3|0');
select pg_temp.send('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as s3 \gset
select pg_temp.chk('C7 보내기(p_to 없음) — to_address 첫 · to_more {둘} · payload.recipients.source flags · skipped [] · auto false · 반환 to_more', (select m.to_address || '|' || m.to_more::text || '|' || (m.payload->'recipients'->>'source') || '|' || (m.payload->'recipients'->>'skipped') || '|' || (m.payload->>'auto') || '|' || m.status from public.mail_outbox m where m.id = (:'s3'::jsonb->>'outbox_id')::uuid) || '|' || (:'s3'::jsonb->>'to_more'),
                   't1@mailinc1c.test|{t2@mailinc1c.test,t3@mailinc1c.test}|flags|[]|false|waiting_pdf|["t2@mailinc1c.test", "t3@mailinc1c.test"]');
-- 직원이 칸에 쓴 그대로(이견 3) — 순서 · 겹침 · 새 주소
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 'T3@mailinc1c.test; t1@mailinc1c.test ,new@mailinc1c.test, t1@mailinc1c.test') as pvt \gset
select pg_temp.chk('C8 typed 목록 — 쓴 순서 · lower · 겹침은 처음 것만 · 새 주소 허용 · source typed', (:'pvt'::jsonb->>'to') || '|' || (:'pvt'::jsonb->>'to_more') || '|' || (:'pvt'::jsonb->'recipients'->>'source'), 't3@mailinc1c.test, t1@mailinc1c.test, new@mailinc1c.test|["t1@mailinc1c.test", "new@mailinc1c.test"]|typed');
select pg_temp.send('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 'T3@mailinc1c.test; t1@mailinc1c.test ,new@mailinc1c.test, t1@mailinc1c.test') as st \gset
select pg_temp.chk('C8b typed 보내기 줄 — to_address t3 · to_more {t1, new} · source typed', (select m.to_address || '|' || m.to_more::text || '|' || (m.payload->'recipients'->>'source') from public.mail_outbox m where m.id = (:'st'::jsonb->>'outbox_id')::uuid), 't3@mailinc1c.test|{t1@mailinc1c.test,new@mailinc1c.test}|typed');
select pg_temp.chk('C9 typed 한 주소 — 그 한 통만(to_more []) · typed / 계산 목록과 같은 글 → source flags', (select (r->>'to') || '|' || (r->>'to_more') || '|' || (r->'recipients'->>'source') from pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 'only@mailinc1c.test') r)
    || '|' || (select r->'recipients'->>'source' from pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 't1@mailinc1c.test, t2@mailinc1c.test, t3@mailinc1c.test') r), 'only@mailinc1c.test|[]|typed|flags');
select pg_temp.chk('C10 typed 거부 — 11 개 · 꼴 아님 · 구분자만(세 문장)', (pg_temp.try(format('select pg_temp.pv(%L, %L::jsonb, %L)::text', 'final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), (select string_agg('u' || g || '@mailinc1c.test', ',') from generate_series(1, 11) g))) like 'ERR P0001: At most 10 recipients in one email (you typed 11) — nothing was saved%')::text
    || (pg_temp.try(format('select pg_temp.pv(%L, %L::jsonb, %L)::text', 'final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), 'bad address')) like 'ERR P0001: Not one email address: bad address — nothing was saved%')::text
    || (pg_temp.try(format('select pg_temp.pv(%L, %L::jsonb, %L)::text', 'final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid), ' , ; ')) like 'ERR P0001: This customer has no email address — add a contact with an email, or type one — nothing was saved%')::text, 'truetruetrue');
-- 켜짐 11 + 겹침 + 꼴 아님 → cap · duplicate · bad_shape(1027) · to_more 9
select pg_temp.contact(:'b'::uuid, 't' || g, 't' || g || '@mailinc1c.test', g) from generate_series(4, 11) g;
select pg_temp.contact(:'b'::uuid, 'dup', '  T1@MAILINC1C.TEST ', 12);
select pg_temp.contact(:'b'::uuid, 'bad', 'INVOICE ONLY: x@mailinc1c.test', 13);
select pg_temp.pv('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as pv11 \gset
select pg_temp.chk('C11 켜짐 11 + dup + bad — list 10 · to_more 9 · skipped cap 1(t11) · duplicate 1 · bad_shape 1', jsonb_array_length(:'pv11'::jsonb->'recipients'->'list')::text || '|' || jsonb_array_length(:'pv11'::jsonb->'to_more') || '|' || (select string_agg((x->>'reason') || ':' || (x->>'email'), ',' order by x->>'reason') from jsonb_array_elements(:'pv11'::jsonb->'recipients'->'skipped') x),
                   '10|9|bad_shape:INVOICE ONLY: x@mailinc1c.test,cap:t11@mailinc1c.test,duplicate:T1@MAILINC1C.TEST');
select pg_temp.send('final_invoice', jsonb_build_object('invoice_id', :'inv_b'::uuid)) as s11 \gset
select pg_temp.chk('C11b 보내기 줄 — to_more 9 · payload.recipients.skipped 3 · CHECK 통과', (select cardinality(m.to_more)::text || '|' || jsonb_array_length(m.payload->'recipients'->'skipped') from public.mail_outbox m where m.id = (:'s11'::jsonb->>'outbox_id')::uuid), '9|3');
-- 청구처 P ∪ 매장 S(1018 · 1024) — sales_order 미리 보기(열린 SO)
select pg_temp.contact(:'p'::uuid, 'p1', 'p1@mailinc1c.test', 1);
select pg_temp.contact(:'s'::uuid, 's1', 's1@mailinc1c.test', 1);
select pg_temp.contact(:'s'::uuid, 's-dup-of-p1', 'P1@mailinc1c.test', 2);
select pg_temp.pv('sales_order', jsonb_build_object('so_id', :'so_st'::uuid)) as pvs \gset
select pg_temp.chk('C12 P ≠ S — to = "p1, s1" · to_more [s1] · stores [S] · skipped duplicate 1(role store) · customer_id P', (:'pvs'::jsonb->>'to') || '|' || (:'pvs'::jsonb->>'to_more') || '|' || (:'pvs'::jsonb->'recipients'->>'stores') || '|' || (select string_agg((x->>'reason') || ':' || (x->>'role'), ',') from jsonb_array_elements(:'pvs'::jsonb->'recipients'->'skipped') x) || '|' || (:'pvs'::jsonb->>'customer_id'),
                   'p1@mailinc1c.test, s1@mailinc1c.test|["s1@mailinc1c.test"]|' || jsonb_build_array(:'s'::uuid)::text || '|duplicate:store|' || :'p');
select clock_timestamp() as t_c12 \gset
-- 자동 최종 인보이스(529) — 지연 트리거를 즉시로 · B 켜짐 2(t1 · t2) · 매장 S 켜짐 1(s1 · P 쪽 dup 제외) · final_invoice_mail 켜기
update public.customer_contact set include_in_email = false where customer_id = :'b'::uuid and lower(btrim(email)) not in ('t1@mailinc1c.test', 't2@mailinc1c.test');
update public.customer_contact set include_in_email = false where customer_id = :'s'::uuid and lower(btrim(email)) <> 's1@mailinc1c.test';
update public.customer set final_invoice_mail = true where id = :'b'::uuid;
set constraints public.so_invoice_doc_mail_auto immediate;
select (select count(*) from public.mail_outbox) as out_a0, (select count(*) from public.doc_mail_skip) as skip_a0 \gset
select pg_temp.clone_inv(:'inv_b'::uuid, '99999991', :'s'::uuid) as cl1 \gset
select pg_temp.chk('C13 자동 · 키 on — 줄 1 · to_address t1 · to_more {t2, s1} · auto true · source flags · stores [S] · waiting_pdf · 첨부 []', (select ((select count(*) from public.mail_outbox) - :out_a0)::text || '|' || m.to_address || '|' || m.to_more::text || '|' || (m.payload->>'auto') || '|' || (m.payload->'recipients'->>'source') || '|' || (m.payload->'recipients'->>'stores') || '|' || m.status || '|' || m.attachments::text from pg_temp.outbox_of(:'cl1'::uuid) m),
                   '1|t1@mailinc1c.test|{t2@mailinc1c.test,s1@mailinc1c.test}|true|flags|' || jsonb_build_array(:'s'::uuid)::text || '|waiting_pdf|[]');
update public.inv_config set value = 'off' where key = 'doc_mail_multi';
select pg_temp.clone_inv(:'inv_b'::uuid, '99999992', :'s'::uuid) as cl2 \gset
select pg_temp.chk('C14 자동 · 키 off — 옛 길: to_address 498 · to_more {} · payload 에 recipients 없음', (select m.to_address || '|' || m.to_more::text || '|' || (m.payload ? 'recipients')::text from pg_temp.outbox_of(:'cl2'::uuid) m), :'b498' || '|{}|false');
update public.inv_config set value = 'on' where key = 'doc_mail_multi';
create temp table t_act as select id from public.customer_contact where customer_id in (:'b'::uuid, :'s'::uuid) and is_active;
update public.customer_contact set is_active = false where customer_id in (:'b'::uuid, :'s'::uuid);
select pg_temp.clone_inv(:'inv_b'::uuid, '99999993', :'s'::uuid) as cl3 \gset
select pg_temp.chk('C15 자동 · 받는 이 0 — 줄 없음 · doc_mail_skip no_email 1', (select count(*)::text from public.mail_outbox m where m.payload->'ref'->>'invoice_id' = :'cl3') || '|' || (select string_agg(reason, ',') from public.doc_mail_skip k where k.ref->>'invoice_id' = :'cl3'), '0|no_email');
update public.customer_contact set is_active = true where id in (select id from t_act);
-- reissue 그대로 — 지연으로 돌려 두고 주문 줄을 복제한 뒤 즉시로(쌓인 사건이 그때 돈다)
set constraints public.so_invoice_doc_mail_auto deferred;
select pg_temp.clone_inv(:'inv_b'::uuid, '99999994', null) as cl4 \gset
select pg_temp.clone_orders(:'inv_b'::uuid, :'cl4'::uuid) as cl4_orders \gset
set constraints public.so_invoice_doc_mail_auto immediate;
select pg_temp.chk('C16 자동 · 같은 오더의 앞 인보이스(복제 주문 ' || :cl4_orders || ' 줄) — reissue 건너뜀 그대로 · 줄 없음', (select count(*)::text from public.mail_outbox m where m.payload->'ref'->>'invoice_id' = :'cl4') || '|' || (select string_agg(reason, ',') from public.doc_mail_skip k where k.ref->>'invoice_id' = :'cl4'), '0|reissue');
select pg_temp.chk('C17 시험이 만든 outbox 줄 수 = 6(off 1 · on 2 · typed 1 · 자동 2) · skip +2 · 전부 시험 주소 또는 498', ((select count(*) from public.mail_outbox) - :out_n0)::text || '|' || ((select count(*) from public.doc_mail_skip) - :skip_n0) || '|' || (select count(*) from public.mail_outbox m where m.created_at >= :'t_begin0'::timestamptz and not (m.to_address like '%mailinc1c.test' or m.to_address = :'b498')), '6|2|0');
select pg_temp.chk('C18 1026 — doc_mail_recipient(B) 는 시험 내내 같은 498 · doc_mail_recipients 무변(A1)', (public.doc_mail_recipient(:'b'::uuid)->>'to'), :'b498');

-- ── 결과 ──
select clock_timestamp() as t_end0 \gset
\echo '── 결과(| OK | / | MISMATCH |) ──'
select n, case when ok then '| OK |' else '| MISMATCH |' end as res, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n from t_res \gset
rollback;
-- ── Z. rollback 뒤 — 시험이 만든 것이 0 인가(실제 큐 · 손님 · 인보이스 · 키) ──
select (select count(*) from public.mail_outbox where to_address like '%mailinc1c.test' or to_more::text like '%mailinc1c.test%' or subject like 'FINAL INVOICE 9999999%') as z_out,
       (select count(*) from public.so_invoice where invoice_number like '9999999%') as z_inv,
       (select count(*) from public.customer_contact where name like 'mail-inc-1c %') as z_cc,
       (select count(*) from public.inv_config where key = 'doc_mail_multi') as z_key,
       (select count(*) from public.mail_outbox) as z_out_all, (select count(*) from public.doc_mail_skip) as z_skip_all \gset
\echo '── Z 시험 흔적 — outbox' :z_out '(기대 0) · 복제 인보이스' :z_inv '(0) · 시험 연락처' :z_cc '(0) · 키 줄' :z_key '(= 시작' :key_n0 ') · outbox 전체' :z_out_all '(시작' :out_n0 ') · skip 전체' :z_skip_all '(시작' :skip_n0 ')'
\echo '── Z1 OK' :ok_n '· MISMATCH' :bad_n '· 기대 OK' :EXPECT_OK '· begin ~ rollback' :t_begin0 '→' :t_end0
\echo '── 구간: \\i 끝' :t_mig '· A ~ D 끝' :t_abd '· C3(off) 끝' :t_c3 '· C12 끝' :t_c12
