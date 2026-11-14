-- crtax-1 검증 — supabase/migrations/20261114111500_crtax_1_carried_over_credit_tax_rule.sql (이월 인보이스 크레딧의 세금 규칙 · 판정 1215 ~ 1220 · 지시서 ~/asung/prompts/crtax-1.md §4 · asung-workflow §4 틀 · fsale_1_check.sql 과 같은 장치)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261114111500_crtax_1_carried_over_credit_tax_rule.sql -f supabase/tests/crtax_1_check.sql
--   확인(적용 뒤 · 사람): 같은 명령에서 -v mig=… 만 뺀다 — 옛 = 새 대조 넷(F13 · I2 · I8 · I9)만 건너뛴다 · ⚠️ 북키퍼가 CR-01040 을 이미 채웠으면 F 갈래는 FAIL 이 맞다(그 크레딧이 채우기 전 모습일 때만 도는 시험)
--   ⚠️ 실제 행 무변: 끝은 rollback · fill 성공 시험은 CR-01040 실물에(답 8 — 몇 초 행 잠금 · rollback 으로 그대로) · 발행 시험은 이월 인보이스 하나에 가짜 번호 크레딧(CR-9999914n)
--   ⚠️ 번호 시퀀스 무접촉(교훈 142): 시험 트랜잭션 안에서 so_credit_next_number 를 가짜 번호를 돌려주는 몸으로 덮는다(rollback 으로 사라진다 · 다른 세션은 옛 몸을 본다) · 머리 · 끝에서 seq 대조
--   ⚠️ 잠금: 시험 적용이 so_credit 에 ACCESS EXCLUSIVE(칸 둘 + FK)를 rollback 까지 잡는다 — 그 사이 크레딧 읽기가 기다린다 · lock_timeout 3 s · 토론토 17:00 뒤에만
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 머리(읽기) — 직원 신원 둘 · 견줄 실물 ──
select
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff,
  (select st.id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff_id,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'worker' and st.auth_user_id is not null and st.perms ? 'sales' order by st.created_at limit 1) as low,
  (select c.id::text from public.so_credit c where c.credit_number = 'CR-01040') as cr,
  (select c.id::text from public.so_credit c join public.so_invoice i on i.id = c.invoice_id where i.kind = 'sale' and c.status = 'issued' order by c.credit_number desc limit 1) as cr_sale,
  (select c.id::text from public.so_credit c where c.status = 'cancelled' order by c.credit_number desc limit 1) as cr_cancelled,
  (select c.id::text from public.so_credit c where c.invoice_id is null and c.status = 'issued' and c.tax_rule_id is not null order by c.credit_number desc limit 1) as cr_ref,
  (select i.id::text from public.so_invoice i where i.invoice_number = '50754' and i.kind = 'opening' and i.status = 'issued') as inv_open,
  (select i.id::text from public.so_invoice i where i.kind = 'sale' and i.status = 'issued' order by i.issued_on desc, i.invoice_number desc limit 1) as inv_sale,
  (select a.id::text from public.ref_account a where a.code = '_1150040036_') as acct,
  (select w.id::text from public.ref_warehouse w where w.is_active order by w.name limit 1) as wh,
  (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'so_credit' and c.column_name = 'tax_rule_filled_at')::int as applied_head,
  (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq) as seq_head \gset
select 'head: applied ' || :applied_head || ' · seq(so/inv/cr) ' || :'seq_head' || ' · staff ' || left(:'staff', 8) || ' · low ' || left(:'low', 8) || ' · CR-01040 ' || left(:'cr', 8) || ' · sale credit ' || left(:'cr_sale', 8)
       || ' · cancelled ' || left(:'cr_cancelled', 8) || ' · ref ' || left(:'cr_ref', 8) || ' · open inv ' || left(:'inv_open', 8) || ' · sale inv ' || left(:'inv_sale', 8) || ' · acct ' || left(:'acct', 8) || ' · wh ' || left(:'wh', 8);

-- ── 도우미(begin 앞 · 잠금 구간 밖) ──
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create temp table t_old (k text primary key, v text);
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 700)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_uid text, p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', p_uid), true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_out, '(null)');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- postgres 로 한 문장(qbo_credit_body 는 직원에게 열려 있지 않다) — 예외는 글자로
create function pg_temp.pg(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return coalesce(v_out, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 열쇠를 깊이와 상관없이 뗀다(새 열쇠 · 시각)
create function pg_temp.wo(p jsonb, p_keys text[]) returns jsonb language sql as $$
  select case jsonb_typeof(p)
    when 'object' then (select coalesce(jsonb_object_agg(e.key, pg_temp.wo(e.value, p_keys)), '{}'::jsonb) from jsonb_each(p) e where not (e.key = any (p_keys)))
    when 'array' then (select coalesce(jsonb_agg(pg_temp.wo(e.value, p_keys) order by e.ord), '[]'::jsonb) from jsonb_array_elements(p) with ordinality e(value, ord))
    else p end $$;
-- safeupdate 정적 셈(ar_2b_check.sql 과 같은 스캐너 · 깊이 0 WHERE 없는 update · delete 수)
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
-- 발행 요청(other 줄 하나 · 스폰서십 계정) — p_extra 로 열쇠를 더한다
create function pg_temp.pay(p_invoice text, p_amount numeric, p_extra jsonb) returns text language sql as $$
  select (jsonb_build_object('invoice_id', p_invoice, 'reason', 'other', 'note', 'crtax-1 test', 'warehouse_id', current_setting('d.wh'),
                             'lines', jsonb_build_array(jsonb_build_object('kind', 'other', 'amount', p_amount, 'description', 'crtax-1 test line', 'account_id', current_setting('d.acct')))) || coalesce(p_extra, '{}'::jsonb))::text $$;
-- 옛 · 새가 같아야 하는 부름(F13 · I2 · I8 · I9) — 새 열쇠는 떼고 견준다
create function pg_temp.q(p_k text) returns text language plpgsql as $$
declare v text; c_new constant text[] := array['tax_rule_fillable', 'tax_rule_fill_blocked', 'tax_rule_options', 'tax_rule_filled_by_name', 'tax_rule_filled_at', 'tax_rule_filled_by', 'needs_tax_rule', 'tax_rule_suggested'];
begin
  if p_k = 'detail_sale' then
    v := pg_temp.asu(current_setting('d.staff'), format('select public.so_credit_detail(%L)::text', current_setting('d.cr_sale')));
  elsif p_k = 'prepare_sale' then
    v := pg_temp.asu(current_setting('d.staff'), format('select public.so_credit_prepare(%L)::text', current_setting('d.inv_sale')));
  elsif p_k = 'issue_sale_preview' then                          -- 일반 인보이스 크레딧 미리 보기(other 줄 · 첫 오더 세율) — 규칙을 보내도 옛 그대로 무시
    v := pg_temp.asu(current_setting('d.staff'), format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.pay(current_setting('d.inv_sale'), 1, jsonb_build_object('tax_rule', 'Exempt (Sale)') - 'warehouse_id')));
  elsif p_k = 'issue_ref_preview' then                           -- 참조 크레딧 미리 보기(실제 참조 크레딧의 손님 · 매장 · 규칙 그대로)
    select pg_temp.asu(current_setting('d.staff'), format('select public.so_credit_issue(%L::jsonb, false)::text',
             jsonb_build_object('ref', jsonb_build_object('invoice_number', 'CRTAX1-TEST'), 'customer_id', c.customer_id, 'store_customer_id', c.store_customer_id, 'tax_rule', c.tax_rule, 'reason', 'other', 'note', 'crtax-1 test',
                                'warehouse_id', current_setting('d.wh'),
                                'lines', jsonb_build_array(jsonb_build_object('kind', 'other', 'amount', 100, 'description', 'crtax-1 test line', 'account_id', current_setting('d.acct'))))::text))
      into v from public.so_credit c where c.id = current_setting('d.cr_ref')::uuid;
  end if;
  return coalesce(pg_temp.wo(pg_temp.j(v), c_new)::text, v);
end $$;

begin;
set local lock_timeout = '3s';
select set_config('d.staff', :'staff', true), set_config('d.staff_id', :'staff_id', true), set_config('d.low', :'low', true), set_config('d.cr', :'cr', true), set_config('d.cr_sale', :'cr_sale', true),
       set_config('d.cr_cancelled', :'cr_cancelled', true), set_config('d.cr_ref', :'cr_ref', true), set_config('d.inv_open', :'inv_open', true), set_config('d.inv_sale', :'inv_sale', true),
       set_config('d.acct', :'acct', true), set_config('d.wh', :'wh', true), clock_timestamp() as t_begin \gset
-- 번호 함수 가짜(이 트랜잭션에서만 · 시퀀스 무접촉)
create or replace function public.so_credit_next_number() returns text language sql as $b$ select 'CR-9999914' || ((select count(*) from public.so_credit c where c.credit_number like 'CR-9999914%') + 1)::text $b$;

\if :{?mig}
-- ── 시험에서만: 적용 전 옛 출력 ──
insert into t_old select x.k, pg_temp.q(x.k) from unnest(array['detail_sale', 'prepare_sale', 'issue_sale_preview', 'issue_ref_preview']) x(k);
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create function pg_temp.run() returns void language plpgsql as $$
declare
  c_staff constant text := current_setting('d.staff');  c_low constant text := current_setting('d.low');
  c_cr constant uuid := current_setting('d.cr')::uuid;  c_open constant text := current_setting('d.inv_open');
  r text;  j jsonb;  v_before jsonb;  v_after jsonb;  v_lines0 jsonb;  v_jobs0 jsonb;  v_sugg jsonb;  v_new uuid;  v_n int;
  c_chg constant text[] := array['tax_rule_id', 'tax_rule', 'rate_pct', 'tax_rule_filled_at', 'tax_rule_filled_by', 'updated_at', 'updated_by'];
begin
  -- ═══ S 정적 ═══
  perform pg_temp.res('S1 safeupdate — 새 창구 · 도우미에 WHERE 없는 update · delete 0',
    (select sum(pg_temp.nowhere(p.prosrc)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_tax_rule_fill', 'so_credit_tax_rule_fill_check', 'so_credit_tax_rule_options', 'so_credit_tax_rule_suggest', 'so_invoice_no_order', 'so_credit_issue')) = 0
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_tax_rule_fill', 'so_credit_tax_rule_fill_check', 'so_credit_tax_rule_options', 'so_credit_tax_rule_suggest', 'so_invoice_no_order')) = 5, 'scan');
  perform pg_temp.res('S2 판별 한 곳 — 이월 인보이스 모두 no_order · sale 인보이스는 0 · null 은 false',
    (select count(*) from public.so_invoice i where i.kind = 'opening' and not public.so_invoice_no_order(i.id)) = 0
    and (select count(*) from public.so_invoice i where i.kind = 'sale' and public.so_invoice_no_order(i.id)) = 0
    and public.so_invoice_no_order(null) = false and public.so_invoice_no_order(gen_random_uuid()) = false, 'sets');
  j := public.so_credit_tax_rule_options(true);
  perform pg_temp.res('S3 목록 — 채우기용 = 세율 0 + QBO 짝 셋(Exempt · Out of Scope · Zero-rated) · 전체 = 활성 sale 모두(has_qbo)',
    (select array_agg(o->>'tax_rule' order by o->>'tax_rule') from jsonb_array_elements(j) o) = array['Exempt (Sale)', 'Out of Scope (Sale)', 'Zero-rated (Sale)']
    and (select bool_and((o->>'rate_pct')::numeric = 0 and (o->>'has_qbo')::boolean and o->>'qbo_code' is not null) from jsonb_array_elements(j) o)
    and jsonb_array_length(public.so_credit_tax_rule_options(false)) = (select count(*) from public.ref_tax_rule t where t.direction = 'sale' and t.is_active)
    and (select count(*) from jsonb_array_elements(public.so_credit_tax_rule_options(false)) o where o->>'tax_rule' in ('Tax on Sales', 'HST NS (Sale)')) = 0, j::text);

  -- ═══ F 채우기(CR-01040 실물 · rollback) ═══
  select to_jsonb(c) into v_before from public.so_credit c where c.id = c_cr;
  select jsonb_agg(to_jsonb(l) - 'rate_pct' - 'updated_at' - 'updated_by' order by l.line_no) into v_lines0 from public.so_credit_line l where l.credit_id = c_cr;
  select jsonb_agg(to_jsonb(q) order by q.id) into v_jobs0 from public.qbo_job q where q.ims_id = c_cr::text or q.blocked_by in (select x.id from public.qbo_job x where x.ims_id = c_cr::text);
  j := pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_detail(%L)::text', c_cr)));
  perform pg_temp.res('F1 상세(채우기 전) — tax_rule_fillable true · 이유 null · 고를 규칙 셋',
    (j->>'tax_rule_fillable')::boolean and j->>'tax_rule_fill_blocked' is null and jsonb_array_length(j->'tax_rule_options') = 3 and j->'credit'->>'tax_rule_filled_at' is null and j->>'tax_rule_filled_by_name' is null,
    coalesce((j - 'open_invoices' - 'credit_row' - 'lines' - 'allocations_all')::text, 'ERR'));
  r := pg_temp.pg(format('select public.qbo_credit_body(%L)::text', c_cr));
  perform pg_temp.res('F2 보내기 몸(채우기 전) — 「has no tax rule to send」 로 멈춘다(지금의 고장 그대로)', r like 'ERR %has no tax rule to send%', left(r, 300));
  r := pg_temp.asu(c_low, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'Exempt (Sale)'));
  perform pg_temp.res('F3 거부 — 권한(worker · sales 열쇠 있음) 「This needs a manager or above」', r like 'ERR %needs a manager or above%nothing was saved%', left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'HST ON (Sale)'));
  perform pg_temp.res('F4 거부 — 세율 0 아닌 규칙', r like 'ERR %only a 0 percent rule can be filled in%nothing was saved%', left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'HST NS (Sale)'));
  perform pg_temp.res('F5 거부 — 비활성 · 없는 규칙 · 빈 이름',
    r like 'ERR %is not an active sale rule%nothing was saved%'
    and pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'No such rule')) like 'ERR %is not an active sale rule%'
    and pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, '  ')) like 'ERR %Pick a tax rule (p_tax_rule)%', left(r, 300));
  begin                                                          -- 짝 없는 규칙: 이 안에서만 Out of Scope 의 짝을 지우고 → 되돌린다(하위 트랜잭션)
    delete from public.qbo_link l where l.ims_kind = 'tax_rule' and l.ims_id = (select t.id::text from public.ref_tax_rule t where t.name = 'Out of Scope (Sale)' and t.direction = 'sale');
    r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'Out of Scope (Sale)'))
         || ' ¦ options ' || jsonb_array_length(public.so_credit_tax_rule_options(true))::text;
    raise exception using errcode = 'TS001', message = r;
  exception when sqlstate 'TS001' then r := sqlerrm;
  end;
  perform pg_temp.res('F6 거부 — QBO 세금 코드 짝 없는 규칙(목록에서도 빠진다 · 뒤에 짝은 그대로)',
    r like 'ERR %has no QuickBooks tax code%nothing was saved% ¦ options 2' and jsonb_array_length(public.so_credit_tax_rule_options(true)) = 3, left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', current_setting('d.cr_sale'), 'Exempt (Sale)'));
  perform pg_temp.res('F7 거부 — 오더 있는 인보이스의 크레딧(머리 규칙은 원래 빔 — 고치지 않는다)',
    r like 'ERR %takes its tax rule from the order on its invoice%nothing was saved%' and (select c.tax_rule_id is null from public.so_credit c where c.id = current_setting('d.cr_sale')::uuid), left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', current_setting('d.cr_cancelled'), 'Exempt (Sale)'));
  perform pg_temp.res('F8 거부 — 상태(cancelled) · 없는 크레딧 · 이미 규칙 있는 참조 크레딧',
    r like 'ERR %is cancelled — only an issued credit note can take a tax rule%nothing was saved%'
    and pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', gen_random_uuid(), 'Exempt (Sale)')) like 'ERR %Credit note not found%'
    and pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', current_setting('d.cr_ref'), 'Exempt (Sale)')) like 'ERR %already has tax rule%nothing was saved%', left(r, 300));
  begin                                                          -- 보낸 일감: 이 안에서만 그 크레딧의 credit 일감을 sent 로 → 되돌린다(트리거 끔)
    execute 'set local session_replication_role = replica';
    update public.qbo_job q set state = 'sent', qbo_id = '999999', sent_at = now() where q.kind = 'credit' and q.ims_id = c_cr::text;
    execute 'set local session_replication_role = origin';
    r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'Exempt (Sale)'))
         || ' ¦ ' || coalesce(pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_detail(%L)::text', c_cr)))->>'tax_rule_fill_blocked', '(null)');
    raise exception using errcode = 'TS001', message = r;
  exception when sqlstate 'TS001' then r := sqlerrm;
  end;
  execute 'set local session_replication_role = origin';
  perform pg_temp.res('F9 거부 — 이미 보낸 일감(sent) · 상세도 같은 이유를 돌려준다',
    r like 'ERR %is already in QuickBooks or being sent (job is sent)%nothing was saved% ¦ %is already in QuickBooks or being sent%', left(r, 400));
  begin                                                          -- qbo_txn 에 있음: 이 안에서만 가짜 거래 줄 → 되돌린다
    execute 'set local session_replication_role = replica';
    insert into public.qbo_txn select (jsonb_populate_record(t, jsonb_build_object('id', gen_random_uuid(), 'ims_kind', 'credit', 'ims_id', c_cr::text, 'qbo_id', '999998'))).*
      from public.qbo_txn t order by (t.ims_kind = 'credit') desc limit 1;
    get diagnostics v_n = row_count;
    execute 'set local session_replication_role = origin';
    r := v_n::text || ' ¦ ' || pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'Exempt (Sale)'));
    raise exception using errcode = 'TS001', message = r;
  exception when sqlstate 'TS001' then r := sqlerrm;
            when others then r := 'SETUP ' || sqlerrm;
  end;
  execute 'set local session_replication_role = origin';
  perform pg_temp.res('F9b 거부 — qbo_txn 에 이미 있는 크레딧', r like '1 ¦ ERR %is already in QuickBooks — the tax rule cannot be changed here%nothing was saved%', left(r, 400));
  -- 성공
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, ' Exempt (Sale) '));
  j := pg_temp.j(r);
  select to_jsonb(c) into v_after from public.so_credit c where c.id = c_cr;
  perform pg_temp.res('F10 채우기 성공 — 머리 규칙 · 세율 0 · 채운 시각 · 사람 · 줄 세율 0 · 그 밖 칸(금액 · 세금 · 합계 · warnings · 상태) 무변',
    (j->>'committed')::boolean and j->>'tax_rule' = 'Exempt (Sale)' and (j->>'rate_pct')::numeric = 0 and (j->>'lines_updated')::int = 1 and (j->>'total')::numeric = 1000 and (j->>'tax_amount')::numeric = 0
    and j->'qbo_job'->>'state' = 'failed'
    and v_after->>'tax_rule' = 'Exempt (Sale)' and v_after->>'tax_rule_id' = (select t.id::text from public.ref_tax_rule t where t.name = 'Exempt (Sale)' and t.direction = 'sale')
    and (v_after->>'rate_pct')::numeric = 0 and v_after->>'tax_rule_filled_by' = current_setting('d.staff_id') and v_after->>'tax_rule_filled_at' is not null and v_after->>'updated_by' = current_setting('d.staff_id')
    and pg_temp.wo(v_after, c_chg) = pg_temp.wo(v_before, c_chg)
    and (select jsonb_agg(to_jsonb(l) - 'rate_pct' - 'updated_at' - 'updated_by' order by l.line_no) from public.so_credit_line l where l.credit_id = c_cr) = v_lines0
    and (select bool_and(l.rate_pct = 0 and l.tax_amount = 0) from public.so_credit_line l where l.credit_id = c_cr), left(r, 500));
  perform pg_temp.res('F11 QBO 일감 무접촉 — credit(failed) · credit_apply(blocked) 줄이 글자까지 그대로',
    (select jsonb_agg(to_jsonb(q) order by q.id) from public.qbo_job q where q.ims_id = c_cr::text or q.blocked_by in (select x.id from public.qbo_job x where x.ims_id = c_cr::text)) = v_jobs0
    and jsonb_array_length(v_jobs0) = 2, v_jobs0::text);
  r := pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', c_cr, 'Zero-rated (Sale)'));
  perform pg_temp.res('F12 거부 — 이미 채움(두 번째는 못 바꾼다)', r like 'ERR %CR-01040 already has tax rule Exempt (Sale)%nothing was saved%', left(r, 300));
  r := pg_temp.pg(format('select public.qbo_credit_body(%L)::text', c_cr));
  j := pg_temp.j(r);
  perform pg_temp.res('F12b 보내기 몸(채운 뒤) — 멈추지 않는다 · 줄 TaxCodeRef = Exempt 의 QBO 코드 · TotalTax 0 · 합계 1000 · needs 0',
    j is not null and j->'body'->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value' = (select o->>'qbo_code' from jsonb_array_elements(public.so_credit_tax_rule_options(true)) o where o->>'tax_rule' = 'Exempt (Sale)')
    and (j->'body'->'TxnTaxDetail'->>'TotalTax')::numeric = 0 and (j->'totals'->>'total')::numeric = 1000 and jsonb_array_length(j->'needs') = 0 and (j->>'line_count')::int = 1
    and jsonb_array_length(j->'body'->'TxnTaxDetail'->'TaxLine') = 1, left(r, 600));
  j := pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_detail(%L)::text', c_cr)));
  perform pg_temp.res('F12c 상세(채운 뒤) — fillable false · 이유 · 목록 빔 · 채운 사람 이름 · credit 에 시각',
    not (j->>'tax_rule_fillable')::boolean and j->>'tax_rule_fill_blocked' like '%already has tax rule Exempt (Sale)' and j->'tax_rule_options' = '[]'::jsonb
    and j->>'tax_rule_filled_by_name' is not null and j->'credit'->>'tax_rule_filled_at' is not null and j->'credit'->>'tax_rule' = 'Exempt (Sale)',
    coalesce((j - 'open_invoices' - 'credit_row' - 'lines' - 'allocations_all')::text, 'ERR'));
  j := pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_detail(%L)::text', current_setting('d.cr_sale'))));
  perform pg_temp.res('F13 일반 인보이스 크레딧 상세 — fillable false · 옛 열쇠는 옛 출력 그대로(시험에서만 대조)',
    not (j->>'tax_rule_fillable')::boolean and j->>'tax_rule_fill_blocked' like '%takes its tax rule from the order%' and j->'tax_rule_options' = '[]'::jsonb
    and (not exists (select 1 from t_old) or pg_temp.q('detail_sale') = (select o.v from t_old o where o.k = 'detail_sale')), left(coalesce(j->>'tax_rule_fill_blocked', 'ERR'), 300));

  -- ═══ I 발행(판정 1217 ~ 1219 · 이월 인보이스 50754 · 가짜 번호) ═══
  j := pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_prepare(%L)::text', c_open)));
  v_sugg := j->'tax_rule_suggested';
  perform pg_temp.res('I1 준비(이월) — needs_tax_rule true · 제안 = 매장 기본 배송지 규칙 · 목록 = 활성 sale 모두',
    (j->'invoice'->>'needs_tax_rule')::boolean and v_sugg->>'tax_rule' is not null and v_sugg->>'source' = 'ship_to'
    and jsonb_array_length(j->'tax_rule_options') = (select count(*) from public.ref_tax_rule t where t.direction = 'sale' and t.is_active)
    and (select count(*) from jsonb_array_elements(j->'tax_rule_options') o where o ? 'has_qbo' and o ? 'qbo_code' and o ? 'rate_pct') = jsonb_array_length(j->'tax_rule_options'),
    coalesce(v_sugg::text, '(no suggestion)') || ' ¦ ' || left(coalesce(j->'tax_rule_options'->0, '{}')::text, 200));
  j := pg_temp.j(pg_temp.asu(c_staff, format('select public.so_credit_prepare(%L)::text', current_setting('d.inv_sale'))));
  perform pg_temp.res('I2 준비(일반) — needs_tax_rule false · 제안 null · 목록 빔 · 옛 열쇠는 옛 출력 그대로(시험에서만 대조)',
    not (j->'invoice'->>'needs_tax_rule')::boolean and j->>'tax_rule_suggested' is null and j->'tax_rule_options' = '[]'::jsonb
    and (not exists (select 1 from t_old) or pg_temp.q('prepare_sale') = (select o.v from t_old o where o.k = 'prepare_sale')), left(coalesce((j->'invoice')::text, 'ERR'), 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_issue(%L::jsonb, false)::text', pg_temp.pay(c_open, 100, null)));
  j := pg_temp.j(r);
  perform pg_temp.res('I3 미리 보기(이월 · 규칙 안 보냄) — 제안 규칙으로 셈 · origin.needs_tax_rule · tax_rule_source ship_to · 저장 0',
    j is not null and not (j->>'committed')::boolean and (j->'origin'->>'needs_tax_rule')::boolean and j->'origin'->>'tax_rule' = v_sugg->>'tax_rule' and j->'origin'->>'tax_rule_source' = 'ship_to'
    and (j->'lines'->0->>'rate_pct')::numeric = (v_sugg->>'rate_pct')::numeric and (j->'totals'->>'tax_amount')::numeric = round(100 * (v_sugg->>'rate_pct')::numeric / 100, 2)
    and (select count(*) from public.so_credit c where c.credit_number like 'CR-9999914%') = 0, left(r, 400));
  r := pg_temp.asu(c_staff, format('select public.so_credit_issue(%L::jsonb, true)::text', pg_temp.pay(c_open, 100, null)));
  perform pg_temp.res('I4 거부 — 발행(이월 · 규칙 안 보냄) 「Pick a tax rule for a credit on a carried-over invoice」(판정 1218)',
    r like 'ERR %Pick a tax rule for a credit on a carried-over invoice%nothing was saved%' and (select count(*) from public.so_credit c where c.credit_number like 'CR-9999914%') = 0, left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_issue(%L::jsonb, true)::text', pg_temp.pay(c_open, 100, jsonb_build_object('tax_rule', 'HST NS (Sale)'))));
  perform pg_temp.res('I5 거부 — 발행(이월 · 비활성 규칙)', r like 'ERR %Tax rule HST NS (Sale) is not an active sale rule%nothing was saved%', left(r, 300));
  r := pg_temp.asu(c_staff, format('select public.so_credit_issue(%L::jsonb, true)::text', pg_temp.pay(c_open, 100, jsonb_build_object('tax_rule', 'GST (Sale)'))));
  j := pg_temp.j(r);  v_new := (j->>'credit_id')::uuid;
  perform pg_temp.res('I6 발행(이월 · GST 5 %) — 머리 규칙 · 세율 · 줄 세율 · 세금 5.00 · 합계 105 · 채움 칸 null · 가짜 번호',
    (j->>'committed')::boolean and j->>'credit_number' = 'CR-99999141' and j->'origin'->>'tax_rule' = 'GST (Sale)' and j->'origin'->>'tax_rule_source' = 'given'
    and (select c.tax_rule = 'GST (Sale)' and c.rate_pct = 5 and c.tax_amount = 5 and c.total = 105 and c.tax_rule_id is not null and c.tax_rule_filled_at is null and c.tax_rule_filled_by is null from public.so_credit c where c.id = v_new)
    and (select bool_and(l.rate_pct = 5 and l.tax_amount = 5 and l.kind = 'other') from public.so_credit_line l where l.credit_id = v_new), left(r, 400));
  r := pg_temp.pg(format('select public.qbo_credit_body(%L)::text', v_new));
  j := pg_temp.j(r);
  perform pg_temp.res('I6b 그 크레딧의 보내기 몸 — 세금 규칙에서 멈추지 않는다 · TaxCodeRef = GST 의 QBO 코드 · TotalTax 5',
    j is not null and j->'body'->'Line'->0->'SalesItemLineDetail'->'TaxCodeRef'->>'value' = (select o->>'qbo_code' from jsonb_array_elements(public.so_credit_tax_rule_options(false)) o where o->>'tax_rule' = 'GST (Sale)')
    and (j->'body'->'TxnTaxDetail'->>'TotalTax')::numeric = 5, left(r, 500));
  r := pg_temp.asu(c_staff, format('select public.so_credit_issue(%L::jsonb, true)::text',
         (pg_temp.pay(c_open, 200, jsonb_build_object('tax_rule', 'Zero-rated (Sale)'))::jsonb
          || jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('kind', 'other', 'amount', 200, 'description', 'crtax-1 test line', 'account_id', current_setting('d.acct')),
                                                           jsonb_build_object('kind', 'restocking_fee', 'amount', -10, 'account_id', current_setting('d.acct')))))::text));
  j := pg_temp.j(r);  v_new := (j->>'credit_id')::uuid;
  perform pg_temp.res('I7 발행(이월 · Zero-rated · other + restocking_fee) — 두 줄 모두 세율 0 · 세금 0 · 합계 190 · 그 뒤 채우기는 거부(이미 규칙 있음)',
    (j->>'committed')::boolean and (select c.tax_rule = 'Zero-rated (Sale)' and c.rate_pct = 0 and c.tax_amount = 0 and c.total = 190 from public.so_credit c where c.id = v_new)
    and (select count(*) = 2 and bool_and(l.rate_pct = 0 and l.tax_amount = 0) from public.so_credit_line l where l.credit_id = v_new)
    and pg_temp.asu(c_staff, format('select public.so_credit_tax_rule_fill(%L, %L)::text', v_new, 'Exempt (Sale)')) like 'ERR %already has tax rule Zero-rated (Sale)%', left(r, 400));
  r := pg_temp.q('issue_sale_preview');
  perform pg_temp.res('I8 일반 인보이스 크레딧 미리 보기 — 옛 출력 그대로(시험에서만 대조) · 규칙을 보내도 무시 · origin 에 새 열쇠 없음',
    r not like 'ERR%' and not (pg_temp.j(r)->'origin' ? 'tax_rule') and (not exists (select 1 from t_old) or r = (select o.v from t_old o where o.k = 'issue_sale_preview')), left(r, 300));
  r := pg_temp.q('issue_ref_preview');
  perform pg_temp.res('I9 참조 크레딧 미리 보기 — 옛 출력 그대로(시험에서만 대조)',
    r not like 'ERR%' and (not exists (select 1 from t_old) or r = (select o.v from t_old o where o.k = 'issue_ref_preview')), left(r, 300));

  -- ═══ Z 끝 상태 ═══
  perform pg_temp.res('Z 실제 행 — 이 트랜잭션이 건드린 크레딧은 CR-01040 과 가짜 번호 둘뿐 · 다른 크레딧에 채움 칸 0 · 신원 되돌림',
    (select count(*) from public.so_credit c where c.updated_at = now() and c.credit_number <> 'CR-01040' and c.credit_number not like 'CR-9999914%') = 0
    and (select count(*) from public.so_credit c where c.credit_number like 'CR-9999914%') = 2
    and (select count(*) from public.so_credit c where c.tax_rule_filled_at is not null) = 1
    and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('fake credits %s · user %s', (select count(*) from public.so_credit c where c.credit_number like 'CR-9999914%'), current_user));
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · seq(so/inv/cr) ' || :'seq_head' || ' → '
       || (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 30 · FAIL 0 · seq 앞 = 뒤 · begin ~ 끝 ≈ 11 s(2026-11-14 실측) · 확인(적용 뒤 · CR-01040 이 아직 안 채워졌을 때) OK 30(옛 = 새 대조 넷은 건너뜀)
