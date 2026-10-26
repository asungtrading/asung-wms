-- srm-1 검증 — supabase/migrations/20261026124840_srm_1_ship_ready_mail_preview.sql (판정 744 · 745 · asung-doc §4 · so-module §66)
--   시험 적용 + 검증(Claude Code · rollback): cd ~/asung/asung-wms && set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026124840_srm_1_ship_ready_mail_preview.sql -f supabase/tests/srm_1_check.sql 2>&1 | tee /tmp/srm_1.out
--   마른 실행(적용 전 · -v mig 없음): 결함 재현 갈래가 돈다(옛 판 md5 d5c17ce5) · 확인 실행(Caleb · 적용 뒤 · -v mig 없음): 같은 명령에서 -v mig 만 뺀다
--   갈래는 \if :{?mig} 가 아니라 DB 의 doc_mail_send prosrc md5 로 가른다(옛 판 = 거절 재현 · 새 판 = 통과) — 마른 실행과 확인 실행은 둘 다 mig 가 없어서
--   기대 OK 수(통과한 실행에서 받아 적음): 시험(-v mig) · 마른(적용 전) · 확인(적용 뒤) — 파일 끝 「기대 OK」 주석
--   ⚠️ 재료 전부 가짜(rollback) — 직원 1(sales) · 손님 1 · 연락처 1 · 제품 1 · packed 오더 2 · doc_file 2 행(버킷 파일 없음 · 쓰는 ship_ready 판을 doc_template_active 에서 받음) · 메일 줄은 이 트랜잭션 안
--   ⚠️ 테스트 DB 는 mail_enabled on · cron 이 돈다 — 반드시 rollback 으로 끝난다 · doc_mail_pdf_claim · mail_claim 은 부르지 않는다 · 시퀀스는 당기지 않는다(so · doc_file 직접 insert)
--   ⚠️ ship_ready ref 는 Ship & invoice 창과 같은 입력 {orders:[{so_id, picks:[{line_id, bin, qty}]}]} — picks 가 없으면 so_invoice_preview 가 WMS 인계를 찾아 가짜 오더를 거절한다
\set ON_ERROR_STOP on
\pset pager off
-- ── 머리(잠금 없음) — 시퀀스 · 함수 판 · 재료 열쇠 · 실물 스냅샷 ──
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_before, :'so_seq_called' as so_called_before, :inv_seq_last as inv_seq_before, :'inv_seq_called' as inv_called_before;
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace), '(none)') as dms_md5_head \gset
select (:'dms_md5_head' = 'd5c17ce5c763bf7da620404a26cad3d2')::int as is_old \gset
select ((:{?mig}) or :is_old = 0)::int as expect_pass \gset
select :'dms_md5_head' as dms_md5_head, :is_old as is_old, :expect_pass as expect_pass;
select coalesce((select proacl::text from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace), '(none)') as acl_head \gset
select id::text as wh from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select id::text as cur from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as taxr from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active limit 1 \gset
select id::text as acc98 from public.ref_account where code = '_98_' \gset
select id::text as term30 from public.ref_payment_term where name = 'Net 30' limit 1 \gset
select a.template_id::text as tpl_sr from public.doc_template_active a where a.kind = 'ship_ready' \gset
select md5(coalesce(string_agg((to_jsonb(t) - 'attachments')::text, '|' order by t.id), '')) || ' ' || count(*) as snap_ob from public.mail_outbox t \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) as snap_df from public.doc_file t \gset
select count(*) as n_sr_head from public.mail_outbox where kind = 'doc_ship_ready' \gset

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\pset format unaligned
\pset tuples_only on
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
-- 가짜 직원(sales 쓰기) 신원으로 창구를 부른다 — postgres 세션 그대로 부르지 않는다 · 예외는 'ERR <sqlstate>: <문장>' 글자로
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000057a101","role":"authenticated"}', true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  return v_out;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;

-- ── 가짜 재료(replica · 트리거 없이) ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values ('00000000-0000-4000-8000-00000057a101', 'srm1-sa@example.invalid', 'srm1 sales', 'worker', '["sales"]', true);
insert into public.customer (name, currency_id, currency_code, default_location_id) values ('srm1 Cust', :'cur'::uuid, 'CAD', :'wh'::uuid) returning id::text as k1 \gset
insert into public.customer_contact (customer_id, name, email, is_default, is_active) values (:'k1'::uuid, 'Srm One', 'srm.one@example.invalid', true, true);
insert into public.product (name, sku, source, uom_name) values ('Srm1 P1', 'SRM1-P1', 'manual', 'EA') returning id::text as p1 \gset
create function pg_temp.mk_so(p_no text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.so (so_number, customer_id, bill_to_customer_id, channel, intake, status, currency_id, currency_code, location_id, location_name, order_date, ref, payment_term_id, payment_term_name,
                         tax_rule_id, tax_rule, tax_rule_manual, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                         ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country, sale_account_id, sale_account_code, confirmed_at)
  values (p_no, current_setting('d.k1')::uuid, current_setting('d.k1')::uuid, 'warehouse', 'manual', 'packed', current_setting('d.cur')::uuid, 'CAD', current_setting('d.wh')::uuid, 'Asung Trading Inc.', public.ims_today(), 'PO-' || p_no, current_setting('d.term')::uuid, 'Net 30',
          current_setting('d.taxr')::uuid, 'HST ON (Sale)', false, 'srm1 Cust', '1 Bill St', 'Toronto', 'ON', 'M1M 1M1', 'Canada',
          'Ship ' || p_no, '9 Ship Rd', 'Markham', 'ON', 'L3R 0A1', 'Canada', current_setting('d.acc98')::uuid, '_98_', now())
  returning id into v_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, list_price, discount_pct, discount_source, unit_price)
  values (v_id, 1, current_setting('d.p1')::uuid, 'SRM1-P1', 'Srm1 P1', 'EA', 1, 2, 0, 10, 0, 'customer', 10);
  return v_id;
end $$;
select set_config('d.k1', :'k1', true), set_config('d.cur', :'cur', true), set_config('d.wh', :'wh', true), set_config('d.term', :'term30', true), set_config('d.taxr', :'taxr', true), set_config('d.acc98', :'acc98', true), set_config('d.p1', :'p1', true);
select pg_temp.mk_so('SO-79911')::text as so1, pg_temp.mk_so('SO-79912')::text as so2 \gset
select id::text as l1 from public.so_line where so_id = :'so1'::uuid \gset
select id::text as l2 from public.so_line where so_id = :'so2'::uuid \gset
-- 창이 보내는 ref(두 오더 따로) · doc_file.ref 는 EF 꼴 {창의 ref, group, so_ids}
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so1', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l1', 'bin', 'SRM1-BIN', 'qty', 2)))))::text as ref1 \gset
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so2', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l2', 'bin', 'SRM1-BIN', 'qty', 2)))))::text as ref2 \gset
insert into public.doc_file (kind, ref, doc_number, template_id, template_version, path, bytes, sha256, pages, reason, made_by)
  values ('ship_ready', :'ref1'::jsonb || jsonb_build_object('group', :'k1' || '|', 'so_ids', jsonb_build_array(:'so1')), null, :'tpl_sr'::uuid, 1, 'ship_ready/srm1-probe-t1-20261026T000001Z.pdf', 1000, repeat('ab', 32), 1, 'send', (select id from public.ims_staff where email = 'srm1-sa@example.invalid')) returning id::text as pdf1 \gset
insert into public.doc_file (kind, ref, doc_number, template_id, template_version, path, bytes, sha256, pages, reason, made_by)
  values ('ship_ready', :'ref2'::jsonb || jsonb_build_object('group', :'k1' || '|', 'so_ids', jsonb_build_array(:'so2')), null, :'tpl_sr'::uuid, 1, 'ship_ready/srm1-probe-t1-20261026T000002Z.pdf', 1000, repeat('cd', 32), 1, 'send', (select id from public.ims_staff where email = 'srm1-sa@example.invalid')) returning id::text as pdf2 \gset
set local session_replication_role = origin;

\if :{?mig}
-- 시험에서만: 적용 전 옛 판으로 결함 재현 · S4 의 옛 반환
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, false)::text', :'ref1'::jsonb)) as s1_old \gset
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, true, %L)::text', :'ref1'::jsonb, :'pdf2')) as s5_old \gset
select pg_temp.asu(format('select public.doc_mail_send(''sales_order'', %L, null, null, null, false)::text', jsonb_build_object('so_id', :'so1'))) as s4_old \gset
select pg_temp.chk('G0 시험에서만: 적용 전 = doc-3a 판(md5 d5c17ce5) · 미리 보기가 거절(결함 재현) · 다른 오더 PDF 로 보내기가 통과(결함 재현 · rollback 됨)',
  :is_old = 1 and :'s1_old' like 'ERR P0001: A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved' and (pg_temp.j(:'s5_old')->>'status') = 'queued' and left(:'s4_old', 1) = '{',
  format('%s | %s | %s', left(:'s1_old', 120), left(:'s5_old', 120), left(:'s4_old', 80)));
delete from public.mail_outbox where kind = 'doc_ship_ready' and payload->>'requested_by' = (select id::text from public.ims_staff where email = 'srm1-sa@example.invalid');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 doc_mail_send 몸이 새 판(98f93aaa243f111befdad7eeb9a0eb1e) · 함수 하나',
  (select md5(prosrc) from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) = '98f93aaa243f111befdad7eeb9a0eb1e'
  and (select count(*) from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) = 1,
  (select left(md5(prosrc), 8) from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace limit 1));
\else
select pg_temp.chk('G0 확인 · 마른 실행: doc_mail_send 가 있다 · 판 = ' || case when :is_old = 1 then '옛(doc-3a · 거절 재현 갈래)' else '새(srm-1 · 통과 갈래)' end,
  :'dms_md5_head' <> '(none)' and (:is_old = 1 or :'dms_md5_head' = '98f93aaa243f111befdad7eeb9a0eb1e'), :'dms_md5_head');
\endif

-- ── S1 미리 보기 — ship_ready · commit false · doc_file_id null ──
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, false)::text', :'ref1'::jsonb)) as s1 \gset
\if :expect_pass
select pg_temp.chk('S1 미리 보기(새 판): 번호 없이 통과 · committed false · 받는 이 = 기본 연락처 · 제목 = doc_setting · 본문에 손님 이름 · 화면이 읽는 칸 일곱(from · from_name · reply_to · redirect_to · to · subject · body) 다 있다',
  (pg_temp.j(:'s1')->>'committed') = 'false' and (pg_temp.j(:'s1')->>'kind') = 'ship_ready'
  and (pg_temp.j(:'s1')->>'to') = 'srm.one@example.invalid' and (pg_temp.j(:'s1')->>'to_default') = 'srm.one@example.invalid'
  and (pg_temp.j(:'s1')->>'subject') = (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject')
  and (pg_temp.j(:'s1')->>'body') like '%srm1 Cust%'
  and pg_temp.j(:'s1') ?& array['from', 'from_name', 'reply_to', 'redirect_to', 'to', 'subject', 'body']
  and (pg_temp.j(:'s1')->>'customer_id') = :'k1',
  left(:'s1', 300));
\else
select pg_temp.chk('S1 결함 재현(옛 판 · 적용 전): 미리 보기가 번호 없이 거절된다 — 화면과 같은 문장',
  :'s1' = 'ERR P0001: A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved', left(:'s1', 200));
\endif

-- ── S2 보내기 · 번호 없음 — commit true · null → 같은 거절 문장 · mail_outbox 무변 ──
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, true)::text', :'ref1'::jsonb)) as s2 \gset
select count(*) as n_sr_s2 from public.mail_outbox where kind = 'doc_ship_ready' \gset
select pg_temp.chk('S2 보내기 · 번호 없음: 같은 거절 문장(판 무관) · mail_outbox 의 doc_ship_ready 줄 수 무변',
  :'s2' = 'ERR P0001: A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved' and :n_sr_s2 = :n_sr_head,
  format('%s | n_sr %s (머리 %s)', left(:'s2', 200), :n_sr_s2, :n_sr_head));

-- ── S5 보내기 · 다른 오더의 ship_ready PDF — 판정 745 ──
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, true, %L)::text', :'ref1'::jsonb, :'pdf2')) as s5 \gset
select count(*) as n_sr_s5 from public.mail_outbox where kind = 'doc_ship_ready' \gset
\if :expect_pass
select pg_temp.chk('S5 보내기 · 다른 오더의 PDF(새 판 · 판정 745): 새 문장으로 거절 · mail_outbox 무변',
  :'s5' = 'ERR P0001: That Ship Ready PDF is for a different order — make the PDF for this order and send again — nothing was saved' and :n_sr_s5 = :n_sr_head,
  format('%s | n_sr %s', left(:'s5', 200), :n_sr_s5));
\else
select pg_temp.chk('S5 결함 재현(옛 판): 다른 오더의 PDF 로도 queued 가 선다(판정 745 전)',
  (pg_temp.j(:'s5')->>'status') = 'queued' and :n_sr_s5 = :n_sr_head + 1, left(:'s5', 200));
delete from public.mail_outbox where kind = 'doc_ship_ready' and payload->>'requested_by' = (select id::text from public.ims_staff where email = 'srm1-sa@example.invalid');
\endif
-- 없는 파일 · 다른 kind 는 doc_mail_enqueue 의 문장 그대로(판 무관)
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, true, %L)::text', :'ref1'::jsonb, '00000000-0000-4000-8000-00000057a1ff')) as s5b \gset
select pg_temp.chk('S5b 보내기 · 없는 파일 번호: doc_mail_enqueue 의 문장 그대로(Stored PDF not found)',
  :'s5b' = 'ERR P0001: Stored PDF not found — nothing was saved', left(:'s5b', 200));

-- ── S3 보내기 · 이 오더의 PDF — 검사를 지나 queued ──
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, true, %L)::text', :'ref1'::jsonb, :'pdf1')) as s3 \gset
select count(*) as n_sr_s3 from public.mail_outbox where kind = 'doc_ship_ready' \gset
select pg_temp.chk('S3 보내기 · 이 오더의 PDF: queued 한 줄 — kind doc_ship_ready · 받는 이 · 제목 · attachments[0].doc_file_id = 그 PDF · payload.ref = 창의 ref · payload.doc_file_id · created_by = 직원',
  (pg_temp.j(:'s3')->>'committed') = 'true' and (pg_temp.j(:'s3')->>'status') = 'queued' and :n_sr_s3 = :n_sr_head + 1
  and (select o.kind = 'doc_ship_ready' and o.status = 'queued' and o.to_address = 'srm.one@example.invalid' and o.customer_id = :'k1'::uuid
              and o.subject = (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject')
              and o.attachments->0 @> jsonb_build_object('doc_file_id', :'pdf1', 'bytes', 1000, 'filename', 'srm1-probe-t1-20261026T000001Z.pdf')
              and o.payload->'ref' = :'ref1'::jsonb and o.payload->>'doc_file_id' = :'pdf1' and (o.payload->>'auto')::boolean = false
              and o.created_by = (select id from public.ims_staff where email = 'srm1-sa@example.invalid') and o.dedupe_key like 'doc:ship_ready:%'
       from public.mail_outbox o where o.id = (pg_temp.j(:'s3')->>'outbox_id')::uuid),
  format('%s | n_sr %s', left(:'s3', 300), :n_sr_s3));

-- ── S4 다른 kind 무변 — sales_order 미리 보기 ──
select pg_temp.asu(format('select public.doc_mail_send(''sales_order'', %L, null, null, null, false)::text', jsonb_build_object('so_id', :'so1'))) as s4 \gset
\if :{?mig}
select pg_temp.chk('S4 시험에서만: sales_order 미리 보기 옛 판 = 새 판(반환 md5)',
  md5(:'s4_old') = md5(:'s4') and (pg_temp.j(:'s4')->>'committed') = 'false', format('old %s | new %s', left(:'s4_old', 120), left(:'s4', 120)));
\else
select pg_temp.chk('S4 확인: sales_order 미리 보기 통과 · 칸 일곱 그대로',
  (pg_temp.j(:'s4')->>'committed') = 'false' and (pg_temp.j(:'s4')->>'kind') = 'sales_order' and pg_temp.j(:'s4') ?& array['from', 'from_name', 'reply_to', 'redirect_to', 'to', 'subject', 'body'],
  left(:'s4', 200));
\endif

-- ── L 함수 모양 · 실물 무접촉 ──
\if :expect_pass
select pg_temp.chk('L1 함수 모양(새 판): definer · authenticated 실행 · anon 없음 · ACL 머리와 같다 · comment 에 745 · 검사 둘 다 몸에 있다',
  (select prosecdef from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace)
  and has_function_privilege('authenticated', 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)', 'execute')
  and (select proacl::text from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) = :'acl_head'
  and obj_description('public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)'::regprocedure, 'pg_proc') ~ '745'
  and (select prosrc from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) ~ 'p_commit and p_kind = ''ship_ready'' and p_doc_file_id is null'
  and (select prosrc from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) ~ 'is for a different order',
  (select proacl::text from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace));
\endif
select pg_temp.chk('Z1 실물 무접촉: mail_outbox(가짜 밖) · doc_file(가짜 밖) md5 머리와 같다 · 무접촉 함수 몸 그대로(doc_mail_enqueue · doc_mail_attach · doc_mail_auto_invoice · mail_claim 은 이 차수가 안 건드린다)',
  (select md5(coalesce(string_agg((to_jsonb(t) - 'attachments')::text, '|' order by t.id), '')) || ' ' || count(*) from public.mail_outbox t where not (t.kind = 'doc_ship_ready' and t.created_by = (select id from public.ims_staff where email = 'srm1-sa@example.invalid'))) = :'snap_ob'
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) from public.doc_file t where t.path not like 'ship_ready/srm1-probe-%') = :'snap_df'
  and (select count(*) from pg_proc where proname in ('doc_mail_enqueue', 'doc_mail_attach', 'doc_mail_auto_invoice', 'mail_claim') and pronamespace = 'public'::regnamespace) = 4,
  'snap');
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- ── 번호 되돌리기 = greatest(실제 최대, 머리) · 전후 원문(이 시험은 시퀀스를 당기지 않는다 — 안전망) ──
select setval('public.so_number_seq', greatest(coalesce((select max(substring(s.so_number from '^SO-([0-9]+)')::bigint) from public.so s), 0), :so_seq_last), :'so_seq_called'::boolean) as so_seq_set;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(i.invoice_number::bigint) from public.so_invoice i where i.invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as inv_seq_set;
select last_value as so_seq_after, is_called as so_called_after from public.so_number_seq;
select last_value as inv_seq_after, is_called as inv_called_after from public.so_invoice_number_seq;
select 'rolled back — srm1 fake rows left: staff ' || (select count(*) from public.ims_staff where email like 'srm1-%') || ' · cust ' || (select count(*) from public.customer where name = 'srm1 Cust') || ' · so ' || (select count(*) from public.so where so_number in ('SO-79911', 'SO-79912')) || ' · doc_file ' || (select count(*) from public.doc_file where path like 'ship_ready/srm1-probe-%') || ' · outbox doc_ship_ready ' || (select count(*) from public.mail_outbox where kind = 'doc_ship_ready') as leftover;
-- 기대 OK: 시험(-v mig) 10(1 회차 실측) · 마른(적용 전 · 옛 판 · -v mig 없음) 8(실측) · 확인(적용 뒤 · -v mig 없음) 9(계산 = 마른 갈래 + L1 · 적용 전엔 못 돈다 — Caleb 확인 실행이 첫 통과)
