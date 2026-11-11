-- fsale-1 검증 — supabase/migrations/20261111023718_fsale_1_final_sale_service_line.sql (떨이 물건을 서비스 줄 FINAL-SALE 로 · 판정 1161 · 1162 · 지시서 ~/asung/prompts/fsale-1.md §2 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111023718_fsale_1_final_sale_service_line.sql -f supabase/tests/fsale_1_check.sql
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 마른 실행은 F6 · Z 만 OK(칸 · FINAL-SALE 줄이 없다) · 확인은 F9(옛 = 새)만 건너뛴다
--   ⚠️ 실제 행 무변: 가짜 오더 다섯(SO-9999991101 ~ 05 · 실제 pos 오더 머리의 복사 · 만든 시각 2001-01-01) · 창구는 가짜 id 로만 · 끝은 rollback
--   ⚠️ 번호 시퀀스 무접촉(교훈 142): 시험 트랜잭션 안에서 so_invoice_next_number · so_credit_next_number 를 가짜 번호를 돌려주는 몸으로 덮는다(rollback 으로 사라진다 · 다른 세션은 옛 몸을 본다) — F5 · F8 을 발행까지 본다
--   ⚠️ 잠금: 시험 적용이 ref_service 에 ACCESS EXCLUSIVE(칸 둘 추가)를 rollback 까지 잡는다 — 그 사이 서비스 목록 읽기가 기다린다 · lock_timeout 3 s · 토론토 17:00 뒤에만
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 머리(읽기) — 복사 원본 · 직원 신원 · 견줄 실물 ──
select
  (select s.id::text from public.so s join public.customer c on c.id = s.customer_id join public.ref_warehouse w on w.id = s.location_id
    where s.channel = 'pos' and s.status = 'fulfilled' and c.is_active and w.is_active and s.tax_rule_id is not null and s.bill_to_customer_id is not null and s.coupon_id is null
      and exists (select 1 from public.so_line l join public.product p on p.id = l.product_id where l.so_id = s.id and p.is_active and l.combo_line_id is null and l.bgrade_bin_id is null and l.unit_price > 0
                    and l.free_reason is null and not exists (select 1 from public.so_line k where k.combo_line_id = l.id))
    order by s.created_at desc limit 1) as src,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff,
  (select st.id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff_id,
  (select s.id::text from public.ref_service s where s.is_active and s.name like 'DROPSHIP - Base%' limit 1) as svc_other,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.auth_user_id is not null and (st.perms ? 'claude' or st.perms ? 'claude:read') order by (st.role = 'admin') desc, st.created_at limit 1) as mcp_uid,
  (select c.so_id::text from public.so_charge c join public.so s on s.id = c.so_id where s.status = 'fulfilled' and s.channel = 'warehouse' order by c.created_at desc limit 1) as real_so,
  (select l.invoice_id::text from public.so_invoice_line l join public.so_invoice i on i.id = l.invoice_id where l.kind = 'charge' and i.status = 'issued' and i.kind = 'sale' order by i.issued_on desc limit 1) as real_inv,
  (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'ref_service' and c.column_name = 'final_sale')::int as applied_head,
  (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq) as seq_head \gset
select 'head: applied ' || :applied_head || ' · seq(so/inv/cr) ' || :'seq_head' || ' · src ' || left(:'src', 8) || ' · staff ' || left(:'staff', 8) || ' · other service ' || left(:'svc_other', 8) || ' · real so ' || left(:'real_so', 8) || ' · real inv ' || left(:'real_inv', 8);

-- ── 도우미(begin 앞 · 잠금 구간 밖) ──
create temp table t_ids (k text primary key, id uuid not null);
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create temp table t_old (k text primary key, v text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 700)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
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
-- 행 복사(생성 칸 제외 · 칸이 늘어도 따라온다)
create function pg_temp.cp(p_tbl regclass, p_row jsonb) returns void language plpgsql as $$
declare v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols from pg_attribute a where a.attrelid = p_tbl and a.attnum > 0 and not a.attisdropped and a.attgenerated = '';
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_tbl, v_cols, v_cols, p_tbl) using p_row;
end $$;
-- 열쇠를 깊이와 상관없이 뗀다(시각 · 새 열쇠)
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
create function pg_temp.mcp(p_from text, p_to text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('d.mcp_uid'), 'role', 'ims_connector', 'aud', 'authenticated', 'client_id', (select c.claude_client_id from public.mcp_config c where c.singleton))::text, true);
  select public.mcp_sales(p_from, p_to, 'month', null, null, null, null, 50, 0)::text into v_out;
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_out, '(null)');
exception when others then
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 옛 · 새가 같아야 하는 부름(F9) — 다른 서비스 줄 넣기(시각 · id 뗌) · 실제 오더의 so_detail.charges · 실제 인보이스의 so_credit_prepare · 지난 달 mcp_sales
create function pg_temp.q(p_k text) returns text language plpgsql as $$
declare v text;
begin
  if p_k = 'svc_add' then
    v := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 5, p_service_id => %L)::text', pg_temp.id('SV'), current_setting('d.svc_other')));
    delete from public.so_charge c where c.so_id = pg_temp.id('SV');
    return coalesce(pg_temp.wo(pg_temp.j(v), array['id', 'created_at', 'updated_at', 'price_set_at'])::text, v);
  elsif p_k = 'svc_price' then                                  -- 손 단가(목록과 다름) → price_set_by 가 남는 옛 길
    v := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 2, p_unit_price => 9.99, p_service_id => %L, p_discount_pct => 10)::text', pg_temp.id('SV'), current_setting('d.svc_other')));
    delete from public.so_charge c where c.so_id = pg_temp.id('SV');
    return coalesce(pg_temp.wo(pg_temp.j(v), array['id', 'created_at', 'updated_at', 'price_set_at'])::text, v);
  elsif p_k = 'detail' then
    return coalesce(pg_temp.wo(pg_temp.j(pg_temp.asu(format('select public.so_detail(%L)::text', current_setting('d.real_so')))), array['final_sale', 'price_each_time'])::text, 'ERR');
  elsif p_k = 'prepare' then
    return pg_temp.asu(format('select public.so_credit_prepare(%L)::text', current_setting('d.real_inv')));
  elsif p_k = 'mcp' then
    v := pg_temp.mcp('2026-10-01', '2026-10-31');
    return coalesce(pg_temp.wo(pg_temp.j(v), array['final_sale', 'source_note', 'other_note'])::text, v);
  elsif p_k = 'nolines' then                                    -- 운임 줄만 있는 counter 오더 확정 = 옛 거부 그대로
    return pg_temp.asu(format('select public.so_pos_confirm(%L)::text', pg_temp.id('FR')));
  end if;
  return null;
end $$;

begin;
set local lock_timeout = '3s';
select set_config('d.src', :'src', true), set_config('d.staff', :'staff', true), set_config('d.staff_id', :'staff_id', true), set_config('d.svc_other', :'svc_other', true), set_config('d.mcp_uid', :'mcp_uid', true),
       set_config('d.real_so', :'real_so', true), set_config('d.real_inv', :'real_inv', true), clock_timestamp() as t_begin \gset

-- ── 가짜 오더 다섯 + 운임만 있는 counter 하나(실제 pos 오더 머리의 복사 · draft · 만든 시각 2001-01-01) · 번호 함수 가짜 ──
do $$
declare
  c_mark constant timestamptz := '2001-01-01 00:00:00+00';
  v_src jsonb;  v_line jsonb;  v_id uuid;  k text;  i int := 0;  v_ch text;
  c_null constant jsonb := jsonb_build_object('split_from_id', null, 'split_reason', null, 'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
                                              'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null, 'unconfirmed_at', null, 'unconfirmed_by', null, 'coupon_id', null,
                                              'confirmed_at', null, 'confirmed_by', null, 'first_confirmed_at', null, 'status', 'draft', 'order_discount_pct', null, 'reprice_suggested_at', null);
begin
  execute 'set local session_replication_role = replica';
  select to_jsonb(s) into v_src from public.so s where s.id = current_setting('d.src')::uuid;
  select to_jsonb(l) into v_line from public.so_line l join public.product p on p.id = l.product_id
   where l.so_id = current_setting('d.src')::uuid and p.is_active and l.combo_line_id is null and l.bgrade_bin_id is null and l.unit_price > 0 and l.free_reason is null
     and not exists (select 1 from public.so_line x where x.combo_line_id = l.id) order by l.line_no limit 1;
  -- CT counter(떨이만) · WH warehouse(떨이만 — 직접) · PS pos(떨이만) · SV service · MX counter(상품 줄 + 떨이) · FR counter(운임만)
  foreach k in array array['CT', 'WH', 'PS', 'SV', 'MX', 'FR'] loop
    i := i + 1;  v_id := gen_random_uuid();
    insert into t_ids values (k, v_id);
    v_ch := case k when 'WH' then 'warehouse' when 'PS' then 'pos' when 'SV' then 'service' else 'counter' end;
    perform pg_temp.cp('public.so', v_src || c_null || jsonb_build_object('id', v_id, 'so_number', 'SO-99999911' || lpad(i::text, 2, '0'), 'channel', v_ch,
      'intake', case when v_ch = 'pos' then 'pos' else 'manual' end, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  v_id := gen_random_uuid();
  insert into t_ids values ('MX.1', v_id);
  perform pg_temp.cp('public.so_line', v_line || jsonb_build_object('id', v_id, 'so_id', pg_temp.id('MX'), 'line_no', 1, 'qty_ordered', 1, 'qty_shipped', 0, 'qty_removed', 0, 'removed_reason', null, 'removed_note', null,
    'removed_at', null, 'removed_by', null, 'split_from_line_id', null, 'comments', null, 'backorder_notified_at', null, 'created_at', c_mark, 'updated_at', c_mark));
  insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_code) select pg_temp.id('FR'), 1, 'Freight', 10, s.tax_rule, '_99_' from public.so s where s.id = pg_temp.id('FR');
  execute 'set local session_replication_role = origin';
  -- 번호 함수 가짜(이 트랜잭션에서만 · 시퀀스 무접촉)
  execute $f$create or replace function public.so_invoice_next_number() returns text language sql as $b$ select '99999911' || lpad(((select count(*) from public.so_invoice i where i.invoice_number like '99999911%') + 1)::text, 2, '0') $b$ $f$;
  execute $f$create or replace function public.so_credit_next_number() returns text language sql as $b$ select 'CR-9999911' || ((select count(*) from public.so_credit c where c.credit_number like 'CR-9999911%') + 1)::text $b$ $f$;
end $$;

\if :{?mig}
-- ── 시험에서만: 적용 전 옛 출력(F9) ──
insert into t_old select x.k, pg_temp.q(x.k) from unnest(array['svc_add', 'svc_price', 'detail', 'prepare', 'mcp', 'nolines']) x(k);
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 검증(한 문장) ──
create function pg_temp.run() returns void language plpgsql as $$
declare
  v_has  boolean := exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'ref_service' and c.column_name = 'final_sale');
  v_fs   uuid;  v_fs_name text;
  ct uuid := pg_temp.id('CT');  wh uuid := pg_temp.id('WH');  ps uuid := pg_temp.id('PS');  sv uuid := pg_temp.id('SV');  mx uuid := pg_temp.id('MX');
  r text;  r2 text;  r3 text;  r4 text;  d jsonb;  v_ch public.so_charge%rowtype;  v_inv uuid;  v_il uuid;  v_cr uuid;  v_cnt int;  v_k text;  v_ok boolean;  v_det text;
  v_led0 bigint;  v_res0 bigint;  v_realm text;
begin
  if v_has then execute 'select s.id, s.name from public.ref_service s where s.final_sale' into v_fs, v_fs_name; end if;
  select count(*) into v_led0 from public.inv_ledger;
  select count(*) into v_res0 from public.so_reserve;

  if v_fs is null then
    foreach v_k in array array['F1', 'F2', 'F3', 'F4', 'F5', 'F7', 'F8', 'F10', 'S1'] loop
      perform pg_temp.res(v_k || ' (적용 전 — ref_service.final_sale 칸 · FINAL-SALE 줄이 없다)', false, 'not applied');
    end loop;
  else
    -- S1 기준 데이터 한 줄
    perform pg_temp.res('S1 기준 데이터: FINAL-SALE 서비스 한 줄 — 이름 · 단가 0 · price_each_time · final_sale · 켜짐 · 계정 _98_ Sales Account · 다른 서비스 표시 0',
      (select count(*) = 1 from public.ref_service s join public.ref_account a on a.id = s.account_id
        where to_jsonb(s)->>'final_sale' = 'true' and to_jsonb(s)->>'price_each_time' = 'true' and s.is_active and s.unit_price = 0 and a.code = '_98_' and a.name = 'Sales Account' and s.name = 'FINAL SALE ITEM - No Return or Exchange')
      and (select count(*) from public.ref_service s where to_jsonb(s)->>'final_sale' = 'true' or to_jsonb(s)->>'price_each_time' = 'true') = 1,
      (select string_agg(s.name || ' ' || (to_jsonb(s)->>'final_sale') || '/' || (to_jsonb(s)->>'price_each_time'), ' · ') from public.ref_service s where to_jsonb(s)->>'final_sale' = 'true' or to_jsonb(s)->>'price_each_time' = 'true'));

    -- F1 counter draft · 단가 4.00 · 수량 3 · 설명
    r := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_description => %L, p_qty => 3, p_unit_price => 4.00, p_service_id => %L)::text', ct, 'Old lip gloss box', v_fs));
    select * into v_ch from public.so_charge c where c.so_id = ct;
    perform pg_temp.res('F1 counter draft 에 FINAL-SALE · 4.00 × 3 · 설명: 들어감 · 금액 12.00 · 이름 = 서비스 이름 · 계정 _98_ · price_set_by 남음',
      r not like 'ERR%' and v_ch.amount = 12 and v_ch.qty = 3 and v_ch.unit_price = 4 and v_ch.service_id = v_fs and v_ch.name = v_fs_name and v_ch.description = 'Old lip gloss box' and v_ch.account_code = '_98_'
      and v_ch.price_set_by = current_setting('d.staff_id')::uuid and v_ch.price_set_at is not null, left(r, 300));

    -- F2 단가 없음 · 0 · 줄 할인 · 고치며 0 · 서비스 떼기 → 각각 거부
    r  := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 1, p_service_id => %L)::text', ct, v_fs));
    r2 := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 1, p_unit_price => 0, p_service_id => %L)::text', ct, v_fs));
    r3 := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 1, p_unit_price => 5, p_service_id => %L, p_discount_pct => 100)::text', ct, v_fs));
    r4 := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => %L, p_amount => null, p_charge_id => %L, p_qty => 3, p_unit_price => 0)::text', ct, 'x', v_ch.id));
    perform pg_temp.res('F2 단가 없음 · 0 원 · 줄 할인 · 서비스 떼며 0 원: 넷 다 거부(할 일 글) · 줄은 F1 그대로 하나',
      r like 'ERR%type the price for this sale%' and r2 like 'ERR%type the price for this sale%' and r3 like 'ERR%takes no discount%' and r4 like 'ERR%cannot be turned into another kind of line%'
      and (select count(*) from public.so_charge c where c.so_id = ct and c.amount = 12) = 1 and (select count(*) from public.so_charge c where c.so_id = ct) = 1,
      left(r, 150) || ' ‖ ' || left(r2, 80) || ' ‖ ' || left(r3, 120) || ' ‖ ' || left(r4, 150));
    -- F2b 고치기(수량 · 단가)는 된다 — 그대로 12.00 으로 되돌린다
    r := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_charge_id => %L, p_description => %L, p_qty => 2, p_unit_price => 6.00, p_service_id => %L)::text', ct, v_ch.id, 'Old lip gloss box', v_fs));
    perform pg_temp.res('F2b 고치기(2 × 6.00): 된다 · 금액 12.00 · price_set_by 그대로 남음', r not like 'ERR%' and (select c.amount = 12 and c.qty = 2 and c.unit_price = 6 and c.price_set_by is not null from public.so_charge c where c.id = v_ch.id), left(r, 200));

    -- F3 warehouse draft → 거부
    r := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 1, p_unit_price => 4, p_service_id => %L)::text', wh, v_fs));
    perform pg_temp.res('F3 warehouse draft 에 FINAL-SALE: 거부(counter · POS · service 로 보내는 글) · 줄 0', r like 'ERR%is a warehouse order%put it on a counter, POS or service order%' and (select count(*) from public.so_charge c where c.so_id = wh) = 0, left(r, 300));

    -- F4 POS · service 오더 → 들어감
    r  := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 2, p_unit_price => 2.50, p_service_id => %L)::text', ps, v_fs));
    r2 := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 1, p_unit_price => 7, p_service_id => %L)::text', sv, v_fs));
    perform pg_temp.res('F4 POS · service draft 에 FINAL-SALE: 둘 다 들어감(5.00 · 7.00)',
      r not like 'ERR%' and r2 not like 'ERR%' and (select c.amount from public.so_charge c where c.so_id = ps) = 5 and (select c.amount from public.so_charge c where c.so_id = sv) = 7, left(r, 150) || ' ‖ ' || left(r2, 150));
    delete from public.so_charge c where c.so_id = sv;

    -- F5 떨이 줄만 있는 counter: 확정 → Finish(미리 보기 → 실행 · 가짜 번호) · POS 도 확정 → 미리 보기 → 다시 열기
    r  := pg_temp.asu(format('select public.so_pos_confirm(%L)::text', ct));
    r2 := pg_temp.asu(format('select public.so_counter_ship(%L, null, false)::text', ct));
    r3 := pg_temp.asu(format('select public.so_counter_ship(%L, null, true)::text', ct));
    d := pg_temp.j(r3);  v_inv := nullif(d->>'invoice_id', '')::uuid;
    perform pg_temp.res('F5 떨이 줄만 counter: 확정됨 · Finish 미리 보기(picks [] · 합계 > 12) · 실행 fulfilled + 인보이스 한 장(가짜 번호) · 할당 · 백오더 · 원장 · WMS 0 · ship.no_goods',
      pg_temp.j(r)->>'status' = 'confirmed' and (pg_temp.j(r)->>'lines_allocated')::int = 0
      and pg_temp.j(r2)->>'committed' = 'false' and pg_temp.j(r2)->'picks' = '[]'::jsonb and (pg_temp.j(r2)->'estimate'->>'total')::numeric >= 12
      and d->>'status' = 'fulfilled' and d->'ship'->>'no_goods' = 'true' and d->>'invoice_number' like '99999911%'
      and (select s.status = 'fulfilled' and s.shipped_at is not null and s.at_wms_at is null from public.so s where s.id = ct)
      and (select count(*) from public.so_reserve) = v_res0 and (select count(*) from public.inv_ledger) = v_led0
      and (select count(*) from public.so s where s.split_from_id = ct) = 0,
      left(r, 160) || ' ‖ ' || left(r2, 160) || ' ‖ ' || left(r3, 260));
    r  := pg_temp.asu(format('select public.so_pos_confirm(%L)::text', ps));
    r2 := pg_temp.asu(format('select public.so_pos_finish(%L, false)::text', ps));
    r4 := pg_temp.asu(format('select public.so_pos_reopen(%L)::text', ps));
    perform pg_temp.res('F5b 떨이 줄만 POS: 확정됨 · Finish 미리 보기 됨 · 다시 열기(so_pos_reopen) → draft',
      pg_temp.j(r)->>'status' = 'confirmed' and pg_temp.j(r2)->>'committed' = 'false' and r4 not like 'ERR%' and (select s.status from public.so s where s.id = ps) = 'draft',
      left(r, 120) || ' ‖ ' || left(r2, 160) || ' ‖ ' || left(r4, 160));

    -- F7 상품 줄 + 떨이 줄 counter: 확정(상품 줄 할당 1) · Finish 미리 보기(계획 줄 1 · 비용 12)
    r  := pg_temp.asu(format('select public.so_charge_set(p_so_id => %L, p_name => null, p_amount => null, p_qty => 3, p_unit_price => 4, p_service_id => %L)::text', mx, v_fs));
    r2 := pg_temp.asu(format('select public.so_pos_confirm(%L)::text', mx));
    r3 := pg_temp.asu(format('select public.so_counter_ship(%L, null, false)::text', mx));
    perform pg_temp.res('F7 상품 줄 + 떨이 줄 counter: 상품 줄은 전처럼 할당 1 · 계획 줄 1(so_pick_plan 길) · 떨이는 비용 줄 12.00(charges_amount)',
      r not like 'ERR%' and (pg_temp.j(r2)->>'lines_allocated')::int = 1 and jsonb_array_length(coalesce(pg_temp.j(r3)->'plan', '[]'::jsonb)) = 1 and (pg_temp.j(r3)->'tax'->>'charges_amount')::numeric = 12
      and (select count(*) from public.so_reserve x where x.so_line_id = pg_temp.id('MX.1') and x.kind = 'allocated' and x.released_at is null) = 1,
      left(r2, 200) || ' ‖ ' || left(r3, 300));

    -- F8 크레딧(떨이 줄): 준비 창 final_sale · 미리 보기 경고 · 발행 · restock 0
    if v_inv is null then
      perform pg_temp.res('F8 (F5 의 인보이스가 없다)', false, 'no invoice');
      perform pg_temp.res('F10 (F5 의 인보이스가 없다)', false, 'no invoice');
    else
      select l.id into v_il from public.so_invoice_line l where l.invoice_id = v_inv and l.kind = 'charge';
      r  := pg_temp.asu(format('select public.so_credit_prepare(%L)::text', v_inv));
      r2 := pg_temp.asu(format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', v_inv, 'reason', 'customer_return', 'lines', jsonb_build_array(jsonb_build_object('kind', 'freight', 'so_invoice_line_id', v_il, 'amount', 12)))));
      r3 := pg_temp.asu(format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', v_inv, 'reason', 'customer_return', 'lines', jsonb_build_array(jsonb_build_object('kind', 'freight', 'so_invoice_line_id', v_il, 'amount', 12)))));
      perform pg_temp.res('F8 떨이 줄 크레딧: 준비 창 줄 final_sale true · 미리 보기 경고 final_sale:<이름>(쓰기 0) · 확인하면 발행(가짜 번호) · 같은 경고가 기록에 · 원장 0(restock 없음)',
        (select bool_and((x->>'final_sale')::boolean) from jsonb_array_elements(pg_temp.j(r)->'lines') x where x->>'kind' = 'charge')
        and pg_temp.j(r2)->'warnings' ? ('final_sale:' || v_fs_name) and pg_temp.j(r2)->>'committed' = 'false'
        and pg_temp.j(r3)->>'committed' = 'true' and pg_temp.j(r3)->>'credit_number' like 'CR-9999911%' and pg_temp.j(r3)->'warnings' ? ('final_sale:' || v_fs_name)
        and (select count(*) from public.inv_ledger) = v_led0,
        'prepare ' || coalesce((select string_agg(x->>'final_sale', ',') from jsonb_array_elements(pg_temp.j(r)->'lines') x), left(r, 120)) || ' ‖ preview ' || coalesce((pg_temp.j(r2)->'warnings')::text, left(r2, 200))
        || ' ‖ issue ' || coalesce((pg_temp.j(r3)->>'credit_number') || ' ' || (pg_temp.j(r3)->'warnings')::text || ' ledger ' || coalesce((pg_temp.j(r3)->'ledger')::text, 'null'), left(r3, 300)));

      -- F10 인보이스 줄 · 문서 데이터 · QBO 몸(가짜 짝 8794)
      r := pg_temp.asu(format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', v_inv)));
      select public.qbo_realm_of() into v_realm;
      begin
        insert into public.qbo_link select (jsonb_populate_record(null::public.qbo_link, to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'ims_id', v_fs::text, 'qbo_id', '8794'))).*
          from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'service' limit 1;
        r2 := public.qbo_invoice_body(v_inv)::text;
      exception when others then r2 := 'ERR ' || sqlstate || ': ' || sqlerrm;
      end;
      perform pg_temp.res('F10 인보이스 줄 charge(이름 — 설명 · 수량 2 · 단가 6 · 12.00 · _98_) · 문서 데이터 charges 에 그 줄 · QBO 몸 줄 ItemRef 8794 · Qty 2 · UnitPrice 6',
        (select l.description = v_fs_name || ' — Old lip gloss box' and l.qty = 2 and l.unit_price = 6 and l.amount = 12 and l.account_code = '_98_' from public.so_invoice_line l where l.id = v_il)
        and r like '%FINAL SALE ITEM - No Return or Exchange%' and r like '%Old lip gloss box%'
        and exists (select 1 from jsonb_array_elements(coalesce(pg_temp.j(r2)->'body'->'Line', pg_temp.j(r2)->'Line', '[]'::jsonb)) x
                     where x->'SalesItemLineDetail'->'ItemRef'->>'value' = '8794' and (x->'SalesItemLineDetail'->>'Qty')::numeric = 2 and (x->'SalesItemLineDetail'->>'UnitPrice')::numeric = 6 and (x->>'Amount')::numeric = 12),
        (select l.description || ' q' || l.qty || ' u' || l.unit_price || ' ' || l.account_code from public.so_invoice_line l where l.id = v_il) || ' ‖ doc ' || left(r, 80) || ' ‖ qbo ' || left(r2, 400));
    end if;
  end if;

  -- F6 떨이 줄만 있는 warehouse 오더(줄은 표에 직접) 확정 = 지금처럼 거부 · 운임 줄만 있는 counter 도 거부
  insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_code, qty, unit_price, service_id)
  select wh, 1, 'FINAL SALE ITEM - No Return or Exchange', 8, s.tax_rule, '_98_', 2, 4, v_fs from public.so s where s.id = wh and v_fs is not null;
  r  := pg_temp.asu(format('select public.so_confirm(%L, null, false, true)::text', wh));
  r2 := pg_temp.q('nolines');
  perform pg_temp.res('F6 떨이 줄만 있는 warehouse 오더 확정: 거부 「has no lines」 · 운임 줄만 있는 counter 확정도 거부 그대로',
    r like 'ERR%has no lines%' and r2 like 'ERR%has no lines%' and (select s.status from public.so s where s.id = wh) = 'draft', left(r, 200) || ' ‖ ' || left(r2, 200));

  -- F9 옛 = 새(시험에서만)
  if (select count(*) from t_old) = 0 then
    perform pg_temp.res('F9 옛 = 새 (건너뜀 — 시험 적용 때만 견준다)', true, 'skipped');
  else
    v_ok := true;  v_det := '';
    foreach v_k in array array['svc_add', 'svc_price', 'detail', 'prepare', 'mcp', 'nolines'] loop
      r := pg_temp.q(v_k);
      if r is distinct from (select t.v from t_old t where t.k = v_k) or r like 'ERR%' and v_k <> 'nolines' then v_ok := false; v_det := v_det || ' ' || v_k || ': ' || left(r, 160) || ' ≠ ' || left((select t.v from t_old t where t.k = v_k), 160); end if;
    end loop;
    perform pg_temp.res('F9 옛 = 새: 다른 서비스(Dropship) 줄 넣기(목록 단가 · 손 단가 + 할인) · 실제 오더 so_detail(새 열쇠 둘 뗌) · 실제 인보이스 so_credit_prepare · 10 월 mcp_sales(other.final_sale 뗌) · 운임만 counter 확정 거부',
      v_ok, coalesce(nullif(v_det, ''), (select string_agg(t.k || ' ' || length(t.v), ' · ') from t_old t)));
    r := pg_temp.mcp('2026-10-01', '2026-10-31');
    r2 := pg_temp.mcp(public.ims_today()::text, public.ims_today()::text);
    perform pg_temp.res('F9b mcp_sales: 10 월 other.final_sale = 0 · 오늘(F5 의 가짜 인보이스 12.00 − 크레딧은 other_credits) other.final_sale = 12',
      (pg_temp.j(r)->'other'->>'final_sale')::numeric = 0 and (pg_temp.j(r2)->'other'->>'final_sale')::numeric = 12, coalesce(left(pg_temp.j(r)->>'other', 200), left(r, 200)) || ' ‖ ' || coalesce(left(pg_temp.j(r2)->>'other', 300), left(r2, 300)));
    r := pg_temp.asu(format('select public.so_detail(%L)::text', mx));
    perform pg_temp.res('F9c so_detail.charges[] 새 열쇠: 떨이 줄 final_sale true · price_each_time true · service_id',
      (select (x->>'final_sale')::boolean and (x->>'price_each_time')::boolean and x->>'service_id' = v_fs::text from jsonb_array_elements(pg_temp.j(r)->'charges') x limit 1), left((pg_temp.j(r)->'charges')::text, 400));
  end if;

  -- R1 REST 두 겹 ① — 재발행 일곱의 깊이 0 WHERE 없는 update · delete 0
  perform pg_temp.res('R1 safeupdate 정적: 재발행 일곱(so_charge_set · so_confirm_precheck · so_pos_complete · so_credit_issue · so_credit_prepare · mcp_sales · so_detail)에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select coalesce(sum(pg_temp.nowhere(p.prosrc)), -1) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_charge_set', 'so_confirm_precheck', 'so_pos_complete', 'so_credit_issue', 'so_credit_prepare', 'mcp_sales', 'so_detail')) = 0,
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('so_charge_set', 'so_confirm_precheck', 'so_pos_complete', 'so_credit_issue', 'so_credit_prepare', 'mcp_sales', 'so_detail')));

  -- Z 실물 무접촉
  perform pg_temp.res('Z 실물 무접촉: 이 트랜잭션이 손댄 so · so_charge · so_invoice · so_credit 는 전부 가짜(만든 시각 2001-01-01 표지 또는 지금 · 가짜 번호) · 원장 행 수 그대로 · claims 비었음',
    (select count(*) from public.so s where s.updated_at = now() and s.created_at not in ('2001-01-01 00:00:00+00', now())) = 0
    and (select count(*) from public.so_charge c join public.so s on s.id = c.so_id where c.updated_at = now() and s.so_number not like 'SO-99999911%') = 0
    and (select count(*) from public.so_invoice i where i.updated_at = now() and i.invoice_number not like '99999911%') = 0
    and (select count(*) from public.so_credit c where c.updated_at = now() and c.credit_number not like 'CR-9999911%') = 0
    and (select count(*) from public.inv_ledger) = v_led0
    and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('ledger %s → %s · user %s', v_led0, (select count(*) from public.inv_ledger), current_user));
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · seq(so/inv/cr) ' || :'seq_head' || ' → '
       || (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 17 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 4(F6 · F9 건너뜀 · R1 · Z) · FAIL 9(F1 ~ F5 · F7 · F8 · F10 · S1 — 칸 없음) · 확인(적용 뒤 · -v mig 없음) OK 15 · FAIL 0(F9 건너뜀 · F9b · F9c 는 시험에서만) · 시험 begin ~ 끝 ≈ 13 s(mcp_sales 네 번이 대부분)
