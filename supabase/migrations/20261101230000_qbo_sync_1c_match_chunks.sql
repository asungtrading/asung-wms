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
-- qbo-sync-1c — qbo_match_auto 를 묶음(cursor)으로 · 임시 표 analyze · qbo_ims_rows rows 20000 (2026-11-01 · 판정 934 · 지시서 ~/asung/prompts/qbo-sync-1.md 1c 이견 1 ~ 5 답 「다섯 다 동의」)
--   왜: 1b 실호출에서 qbo_match_auto('customer') 첫 호출이 57014(REST statement_timeout 8 s) · 바로 다시 부르니 통과 — 재현은 안 됐다(psql · authenticated 역할 0.94 ~ 1.14 s · 단계별 넣기 563 ms 가 절반 · pg_stat_statements REST 최대 6,169 ms · 같은 시각 qbo_entity · qbo_link autovacuum)
--       ⇒ 환경이 느려지는 날에도 한 호출이 8 s 안에 끝나도록 묶음으로 자른다(권장 A · 기각 B = 통계 · 색인만 — 1 s 를 0.8 s 로 만들 뿐)
--   무엇: qbo_match_auto(p_kind, p_after text default null, p_limit int default 5000 · 1 ~ 20000) — 활성 · 짝 없는 IMS 행을 ims_id 순으로 p_after 뒤부터 p_limit 개만 · 결과에 limit · next_after(이 묶음의 마지막 ims_id) · remaining(그 뒤 남은 활성 · 짝 없음 수) · done(remaining = 0)
--         부르는 쪽은 done 까지 next_after 를 p_after 로 돌린다(pull 과 같은 꼴) · p_limit 20000 이면 지금 크기(product 14,717)는 한 번에 끝난다(1a 시험의 D 줄은 그렇게 부른다)
--         임시 표 넷은 만든 뒤 analyze(통계 없는 임시 표의 plan 흔들림 제거 · 실측 merge join 추정 330,604 vs 실제 9,764) · qbo_ims_rows 는 rows 20000(추정 500 → anti-join 이 nested loop 9,791 회였다)
--   안 하는 것: 함수 안 SET statement_timeout(지금 문장의 시계는 안 바뀐다) · qbo_link_qbo_idx 제거(tax_rule 조회가 쓴다) · 표 · 다른 창구 · 정책 · grant 무접촉(qbo_match_auto 의 grant 만 새 서명으로 다시)
--   서명이 바뀐다 → drop function qbo_match_auto(text) + create · 옛 서명이 남지 않는지 착지 검사 · 1a 시험(qbo_sync_1a_check.sql)의 pg_temp.m 은 (kind, null, 20000) 으로 고쳤다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(G0)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261101230000_qbo_sync_1c_match_chunks.sql && supabase migration repair --status applied 20261101230000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): export MIG=supabase/migrations/20261101230000_qbo_sync_1c_match_chunks.sql; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig="$MIG" -f supabase/tests/qbo_sync_1c_check.sql

-- ═══ A) qbo_ims_rows — 몸 그대로 · rows 20000 만 ═══
create or replace function public.qbo_ims_rows(p_kind text) returns table (ims_id text, ims_name text, ims_code text, ims_active boolean)
  language sql stable security definer set search_path = public, pg_temp rows 20000
as $$
  select a.id::text, a.name, a.code, a.is_active from public.ref_account a where p_kind = 'account'
  union all select t.id::text, t.name, t.direction, t.is_active from public.ref_tax_rule t where p_kind = 'tax_rule'
  union all select pt.id::text, pt.name, null, pt.is_active from public.ref_payment_term pt where p_kind = 'payment_term'
  union all select m.v, m.v, m.q, true from (values ('cheque', 'Cheque'), ('debit_card', 'Debit'), ('e_transfer', 'E-Transfer'), ('wire', 'Wire'), ('cash', 'Cash'), ('shopify', 'Shopify'), ('direct_deposit', 'EFT (ACH)'), ('credit_card', null)) m(v, q) where p_kind = 'payment_method'
  union all select c.id::text, c.name, null, c.is_active from public.customer c where p_kind = 'customer'
  union all select s.id::text, s.name, null, s.is_active from public.supplier s where p_kind = 'supplier'
  union all select p.id::text, p.name, p.sku, p.is_active from public.product p where p_kind = 'product'
  union all select v, v, null, true from unnest(array['freight', 'discount', 'surcharge', 'freight_discount']) v where p_kind = 'charge'
  union all select r.id::text, r.name, null, r.is_active from public.ref_service r where p_kind = 'service'
$$;

-- ═══ B) qbo_match_auto — 묶음 · analyze · 결과에 limit · next_after · remaining · done ═══
drop function public.qbo_match_auto(text);
create function public.qbo_match_auto(p_kind text, p_after text default null, p_limit int default 5000) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp set client_min_messages = warning   -- drop table if exists 의 NOTICE 를 끈다
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_by text; v_st public.qbo_pull_state%rowtype;
        v_lim int := least(greatest(coalesce(p_limit, 5000), 1), 20000); v_linked int; v_next text; v_remaining int; v_res jsonb;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  if p_kind in ('charge', 'service') then raise exception 'No automatic rule for % — link it by hand with qbo_link_set', p_kind; end if;
  select * into v_st from public.qbo_pull_state s where s.realm_id = v_realm and s.qbo_type = v_type;
  if v_st.finished_at is null then raise exception 'The QuickBooks % list has not been pulled completely — run the pull first', v_type; end if;
  v_by := case p_kind when 'account' then 'auto_code' when 'payment_method' then 'auto_map' when 'product' then 'auto_sku' else 'auto_name' end;
  drop table if exists t_ims, t_ent, t_cand, t_pick;
  create temp table t_ims on commit drop as                                                            -- 이 묶음 = 활성 · 짝 없음 · ims_id > p_after · ims_id 순 · v_lim 개
    select r.ims_id, r.ims_name, lower(btrim(left(r.ims_name, 100))) as nm,
      case p_kind when 'account' then (regexp_match(r.ims_code, '^_([0-9]+)_$'))[1]
                  when 'tax_rule' then lower(btrim(regexp_replace(r.ims_name, '\s*\((Sale|Purchase)\)\s*$', '')))
                  when 'payment_term' then regexp_replace(lower(r.ims_name), '\s', '', 'g')
                  when 'payment_method' then lower(r.ims_code)
                  when 'product' then lower(btrim(r.ims_code))
                  else lower(btrim(r.ims_name)) end as k
    from public.qbo_ims_rows(p_kind) r
    where r.ims_active and (p_after is null or r.ims_id > p_after)
      and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id)
    order by r.ims_id limit v_lim;
  analyze t_ims;
  create temp table t_ent on commit drop as
    select e.qbo_id, e.name, e.active, lower(btrim(e.name)) as nm,
      case p_kind when 'account' then e.qbo_id when 'payment_term' then regexp_replace(lower(e.name), '\s', '', 'g') when 'product' then lower(btrim(e.sku)) else lower(btrim(e.name)) end as k
    from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.gone_at is null;
  analyze t_ent;
  create temp table t_cand on commit drop as
    select i.ims_id, e.qbo_id, e.name as qbo_name, e.active, (p_kind = 'product' and e.nm = i.nm) as name_hit from t_ims i join t_ent e on e.k = i.k where i.k is not null;
  analyze t_cand;
  create temp table t_pick on commit drop as
    select x.*, case when x.n_act = 1 then x.id_act when x.n_act > 1 and x.n_name = 1 then x.id_name end as qbo_id,
                case when x.n_act = 1 then x.nm_act when x.n_act > 1 and x.n_name = 1 then x.nm_name end as qbo_name,
                case when x.n_act = 1 then v_by when x.n_act > 1 and x.n_name = 1 then v_by || '_name' end as by,
                case when x.n_act = 1 or (x.n_act > 1 and x.n_name = 1) then 'linked' when x.k is null then 'skipped' when x.n_all > 0 then 'ambiguous' else 'absent' end as state
    from (select i.ims_id, i.ims_name, i.k, count(c.qbo_id) as n_all, count(c.qbo_id) filter (where c.active) as n_act, count(c.qbo_id) filter (where c.active and c.name_hit) as n_name,
                 (array_agg(c.qbo_id) filter (where c.active))[1] as id_act, (array_agg(c.qbo_name) filter (where c.active))[1] as nm_act,
                 (array_agg(c.qbo_id) filter (where c.active and c.name_hit))[1] as id_name, (array_agg(c.qbo_name) filter (where c.active and c.name_hit))[1] as nm_name,
                 string_agg(c.qbo_id || ' ' || c.qbo_name || case when c.active then '' else ' (inactive)' end, ' | ' order by c.active desc, c.qbo_id) as candidates
          from t_ims i left join t_cand c on c.ims_id = i.ims_id group by i.ims_id, i.ims_name, i.k) x;
  analyze t_pick;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  select v_realm, p_kind, p.ims_id, v_type, p.qbo_id, p.by, p.qbo_name, v_staff from t_pick p where p.state = 'linked'
  on conflict (realm_id, qbo_type, qbo_id) where ims_kind <> 'tax_rule' do nothing;                      -- QBO 쪽이 이미 다른 IMS 행의 것이면 못 넣는다 → ambiguous
  get diagnostics v_linked = row_count;
  update t_pick p set state = 'ambiguous', candidates = coalesce(p.candidates, '') || ' (QuickBooks id already linked)'
    where p.state = 'linked' and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = p.ims_id);
  select coalesce(max(p.ims_id), p_after) into v_next from t_pick p;                                     -- 묶음이 비면 p_after 그대로
  select count(*) into v_remaining from public.qbo_ims_rows(p_kind) r                                   -- 이 묶음 뒤에 남은 활성 · 짝 없음(absent · ambiguous 는 남지 않는다 — 다음 묶음은 next_after 뒤만)
    where r.ims_active and (v_next is null or r.ims_id > v_next)
      and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id);
  select jsonb_build_object('kind', p_kind, 'qbo_type', v_type, 'realm_id', v_realm, 'considered', count(*), 'linked', v_linked,
           'absent', count(*) filter (where p.state = 'absent'), 'ambiguous', count(*) filter (where p.state = 'ambiguous'), 'skipped', count(*) filter (where p.state = 'skipped'),
           'limit', v_lim, 'after', p_after, 'next_after', v_next, 'remaining', v_remaining, 'done', v_remaining = 0,
           'examples', jsonb_build_object(
             'ambiguous', (select coalesce(jsonb_agg(jsonb_build_object('ims_id', a.ims_id, 'ims_name', a.ims_name, 'candidates', a.candidates) order by a.ims_name), '[]'::jsonb) from (select * from t_pick where state = 'ambiguous' order by ims_name limit 20) a),
             'absent',    (select coalesce(jsonb_agg(b.ims_name order by b.ims_name), '[]'::jsonb) from (select ims_name from t_pick where state = 'absent' order by ims_name limit 20) b),
             'skipped',   (select coalesce(jsonb_agg(s.ims_name order by s.ims_name), '[]'::jsonb) from t_pick s where s.state = 'skipped')))
  into v_res from t_pick p;
  return v_res;
end;
$$;
comment on function public.qbo_match_auto(text, text, int) is 'qbo-sync-1c: 자동 짝(admin · 활성 IMS 행 · 짝 없는 것만 · 그 종류 pull 완주 필수) — 묶음: ims_id 순 · p_after 뒤부터 p_limit(기본 5000 · 최대 20000)개 · 결과 next_after · remaining · done(부르는 쪽이 done 까지 돈다) · 규칙은 1a 그대로(account code _N_ → Id N · tax_rule 꼬리 뗀 이름 · payment_term 공백 뺀 이름 · payment_method 고정 표 · customer · supplier lower(btrim(name)) · product Sku → 활성 둘이면 이름) · 결과 considered · linked · absent · ambiguous · skipped · examples 20 · charge · service 는 거부';

revoke all on function public.qbo_ims_rows(text), public.qbo_match_auto(text, text, int) from public, anon, authenticated, service_role;
grant execute on function public.qbo_match_auto(text, text, int) to authenticated;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-') || ' rows=' || p.prorows::int, ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_match_auto', 'qbo_ims_rows');
  if v <> 'qbo_ims_rows(p_kind text)={postgres=X/postgres} rows=20000 qbo_match_auto(p_kind text, p_after text, p_limit integer)={postgres=X/postgres,authenticated=X/postgres} rows=0' then raise exception 'qbo-sync-1c landing: %', v; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_match_auto') <> 1 then raise exception 'qbo-sync-1c landing: old signature still there'; end if;
  raise notice 'qbo-sync-1c landing OK — qbo_match_auto(text, text, int) 하나 · authenticated · qbo_ims_rows rows 20000';
end $$;
