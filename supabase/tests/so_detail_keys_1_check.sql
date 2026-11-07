-- supabase/tests/so_detail_keys_1_check.sql — so-detail-keys-1 검증: so_detail 줄 객체에 네 키(no_price · free · shipped_total · removed) 가 돌아왔다 (2026-11-07 · 지시서 ~/asung/prompts/so-detail-keys-1.md)
-- [운영 메인 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 2s · statement_timeout 10s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변 단언
--   Claude Code(시험): MIG=supabase/migrations/20261107143714_so_detail_keys_1.sql; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/so_detail_keys_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · Z2(시험만 · rollback 뒤 옛 md5) · 기대 OK 수 EXPECT_OK(시험 10 · 적용 뒤 9)
--   읽기만(실제 행을 바꾸지 않는다 — rollback 되더라도 · asung-workflow §4 · Caleb 2026-11-07) · 가짜 행 없음 · 신원은 사장님(ims_staff name 'Seungchill Chang' · set local role authenticated)
--   가격 없는 줄(unit_price null · no_price true)의 단언은 없다 — 지금 DB 에 그런 줄이 한 상태에도 없어 「해당 없음」(지시서 C.4) · 잠시 null 로 바꾸는 안은 받지 않았다
--   ⚠️ 키 검사는 따옴표 열쇠(e ? 'shipped_total')로 — 값이 null · false 여도 「있음」 이 맞다
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 10
\else
\set EXPECT_OK 9
\endif
\pset pager off
select (select count(*) from public.so) as y_so, (select count(*) from public.so_line) as y_sl,
       (select left(md5(prosrc), 8) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail') as y_md5,
       (select auth_user_id::text from public.ims_staff where name = 'Seungchill Chang') as u_boss,
       (select id::text from public.so where so_number = 'SO-20918') as so_20918 \gset
\echo '── 기준: so' :y_so '· so_line' :y_sl '· so_detail md5' :y_md5 '· 사장님 있음:' :u_boss '· SO-20918' :so_20918
-- ── begin 앞(잠금 없음): 임시 표 · 임시 함수 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_ids (k text primary key, v text);   -- psql 변수는 $$ 안(do)에서 안 풀린다 → 임시 표로 넘긴다(ac_count_1_check 와 같은 길)
insert into t_ids values ('u_boss', :'u_boss'), ('so_20918', :'so_20918');
create function pg_temp.v(p_k text) returns text language sql security definer as $$ select v from t_ids where k = p_k $$;   -- definer: set local role authenticated 뒤에도 postgres 의 임시 표를 읽는다
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.as_boss() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', (select v from t_ids where k = 'u_boss'), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.head() returns text language sql security definer as $$
  select pg_get_function_identity_arguments(oid) || '|' || prosecdef::text || '|' || provolatile::text || '|' || coalesce(proconfig::text, '-') || '|' || coalesce(proacl::text, '-') || '|' || md5(coalesce(obj_description(oid, 'pg_proc'), '')) || '|' || prorettype::regtype::text || '|' || length(prosrc) || '|' || left(md5(prosrc), 8)
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail';
$$;
select pg_temp.head() as head_before \gset
\echo '── 적용 전 머리|secdef|volatile|config|acl|comment md5|ret|len|md5:' :head_before

begin;
set local lock_timeout = '2s';
set local statement_timeout = '10s';
select clock_timestamp() as t_begin0000 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
select pg_temp.chk('G0 landing — so_detail 하나 · 새 md5 e56a3ce9 · 11029 자 · 머리 · invoker · stable · search_path · acl · comment 그대로',
  pg_temp.head(), 'p_so_id uuid|false|s|{"search_path=public, pg_temp"}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|47e068a1d6d690c8bd7347c01401992b|jsonb|11029|e56a3ce9');
\endif

do $$
declare d jsonb; l0 jsonb; v_src text;
begin
  -- A: SO-20918(Fulfilled · Shopify · 20 줄) — 사장님
  perform pg_temp.as_boss();
  d := public.so_detail(pg_temp.v('so_20918')::uuid);
  perform pg_temp.chk('A1 SO-20918 lines 20 줄 모두 네 키(no_price · free · shipped_total · removed) 있음 — n_lines/with_keys',
    jsonb_array_length(d->'lines')::text || '/' || (select count(*) from jsonb_array_elements(d->'lines') e where e ? 'no_price' and e ? 'free' and e ? 'shipped_total' and e ? 'removed')::text, '20/20');
  l0 := d->'lines'->0;
  perform pg_temp.chk('A2 lines[0] AS91581 — shipped_total 6.60 · no_price false · free false · removed false · total 6.60 그대로 · surcharge_unit 있음',
    (l0->>'sku') || ' ' || (l0->>'shipped_total') || ' ' || (l0->>'no_price') || ' ' || (l0->>'free') || ' ' || (l0->>'removed') || ' ' || (l0->>'total') || ' ' || (l0 ? 'surcharge_unit')::text,
    'AS91581 6.60 false false false 6.60 true');
  perform pg_temp.chk('A3 lines[0] 네 키의 jsonb 꼴 — number · boolean · boolean · boolean', jsonb_typeof(l0->'shipped_total') || ' ' || jsonb_typeof(l0->'no_price') || ' ' || jsonb_typeof(l0->'free') || ' ' || jsonb_typeof(l0->'removed'), 'number boolean boolean boolean');
  perform pg_temp.chk('A4 totals.basis shipped · lines_total 1202.23 · lines_without_price 0 · free_lines 0 · lines_removed 0(SO-20918 실측 11-07)',
    (d->'totals'->>'basis') || ' ' || (d->'totals'->>'lines_total') || ' ' || (d->'totals'->>'lines_without_price') || ' ' || (d->'totals'->>'free_lines') || ' ' || (d->'totals'->>'lines_removed'), 'shipped 1202.23 0 0 0');
  -- B: 최근 Fulfilled 15 — 구성품 줄을 뺀 Σ shipped_total = totals.lines_total(둘 다 줄마다 round(qty_shipped × unit_price, 2) · so_tax_preview :53) · 구성품 줄의 shipped_total 은 전부 0(CHECK so_line_combo_values_ck 가 unit_price = 0)
  perform pg_temp.chk('B1 최근 Fulfilled 15 — 모두 네 키 · Σ shipped_total(구성품 제외) = totals.lines_total · basis shipped — n/with_keys_all/sum_eq/basis_shipped',
    (select count(*)::text || '/' || count(*) filter (where n_lines = with_keys)::text || '/' || count(*) filter (where sum_st = lines_total)::text || '/' || count(*) filter (where basis = 'shipped')::text
       from (select jsonb_array_length(j->'lines') n_lines,
                    (select count(*) from jsonb_array_elements(j->'lines') e where e ? 'no_price' and e ? 'free' and e ? 'shipped_total' and e ? 'removed') with_keys,
                    (select coalesce(sum((e->>'shipped_total')::numeric), 0) from jsonb_array_elements(j->'lines') e where e->'combo_line_id' = 'null'::jsonb) sum_st,
                    (j->'totals'->>'lines_total')::numeric lines_total, j->'totals'->>'basis' basis
               from (select public.so_detail(s.id) j from (select id from public.so where status = 'fulfilled' order by closed_at desc limit 15) s) x) y),
    '15/15/15/15');
  perform pg_temp.chk('B2 같은 15 — 구성품 줄 수 / 그중 shipped_total ≠ 0 인 줄(0 이어야 · 넣어도 Σ 가 같다) — SO-20002 의 4 줄 포함',
    (select count(*) filter (where e->'combo_line_id' <> 'null'::jsonb)::text || '/' || count(*) filter (where e->'combo_line_id' <> 'null'::jsonb and (e->>'shipped_total')::numeric <> 0)::text
       from (select public.so_detail(s.id) j from (select id from public.so where status = 'fulfilled' order by closed_at desc limit 15) s) x, jsonb_array_elements(x.j->'lines') e),
    '4/0');
  perform pg_temp.chk('B3 같은 15 — 줄마다 shipped_total = round(qty_shipped × unit_price, 2) (to_jsonb(l) 의 qty_shipped · unit_price 로 되셈) — 어긋난 줄 수',
    (select count(*)::text from (select public.so_detail(s.id) j from (select id from public.so where status = 'fulfilled' order by closed_at desc limit 15) s) x, jsonb_array_elements(x.j->'lines') e
       where (e->>'shipped_total')::numeric is distinct from round((e->>'qty_shipped')::numeric * (e->>'unit_price')::numeric, 2)), '0');
  -- L: 정적 — 네 키가 prosrc 의 주석 줄이 아닌 줄에(「--」 뒤에 오는 'no_price' 등 0 · 제 줄 있음)
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail';
  perform pg_temp.chk('L1 prosrc — 「--」 뒤 같은 줄에 ''no_price''|''free''|''shipped_total''|''removed'' 0 줄 · 네 키 줄이 62 칸 들여쓰기로 제 줄에 1 줄',
    (select count(*) filter (where line ~ '--.*''(no_price|free|shipped_total|removed)'',')::text || '/' || count(*) filter (where line = repeat(' ', 62) || '''no_price'', l.unit_price is null, ''free'', l.free_reason is not null, ''shipped_total'', round(l.qty_shipped * l.unit_price, 2), ''removed'', l.qty_removed > 0,')::text
       from unnest(string_to_array(v_src, E'\n')) line), '0/1');
  perform pg_temp.chk('L2 prosrc — ln-1 주석 줄은 ''total'', public.so_line_total(l), 로 시작해 「에)」 로 끝난다(꼬리 공백 없음) · 1 줄',
    (select count(*)::text from unnest(string_to_array(v_src, E'\n')) line where line ~ '''total'', public\.so_line_total\(l\),   -- ln-1 판정 546\(price_set_by · price_set_at 은 to_jsonb\(l\) 에\)$'), '1');
end $$;
reset role;   -- do 안의 set local role authenticated 를 되돌린다 — 결과 표(t_res)는 postgres 의 임시 표

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select pg_temp.as_boss() as as_boss \gset
select so_number, (select count(*) from jsonb_array_elements(d.j->'lines')) n_lines,
       (select count(*) from jsonb_array_elements(d.j->'lines') e where e ? 'shipped_total' and e ? 'no_price' and e ? 'free' and e ? 'removed') with_keys,
       (select sum((e->>'shipped_total')::numeric) from jsonb_array_elements(d.j->'lines') e where e->'combo_line_id' = 'null'::jsonb) sum_shipped_total,
       (d.j->'totals'->>'lines_total')::numeric lines_total
from (select * from public.so where status = 'fulfilled' order by closed_at desc limit 15) s
cross join lateral (select public.so_detail(s.id) j) d order by s.closed_at desc;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.so_line) = :y_sl
        then 'Z1 OK rows unchanged after rollback (so · so_line)' else 'Z1 MISMATCH rows changed' end as z1;
\if :{?mig}
select case when (select left(md5(prosrc), 8) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail') = :'y_md5' and :'y_md5' = '9f4e87f6'
        then 'Z2 OK so_detail back to 9f4e87f6 after rollback' else 'Z2 MISMATCH so_detail md5 ' || (select left(md5(prosrc), 8) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail') end as z2;
\else
select case when (select left(md5(prosrc), 8) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail') = 'e56a3ce9'
        then 'Z2 OK so_detail is e56a3ce9 (applied)' else 'Z2 MISMATCH so_detail md5 ' || (select left(md5(prosrc), 8) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail') end as z2;
\endif
