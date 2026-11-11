-- nb-5 검증 — supabase/ops/nb-5-ghost-cleanup.sql(유령 원가 두 건 정리 · EDM EZB70340 · ORS21020 · 판정 1178 · 지시서 ~/asung/prompts/nb-5.md §4)
--   시험(Claude Code · 메인 DB · begin → 스크립트 → 검증 → rollback):
--     cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -P pager=off -v ON_ERROR_STOP=1 -v ops=supabase/ops/nb-5-ghost-cleanup.sql -f supabase/tests/nb_5_check.sql 2>&1 | tee /tmp/nb_5_check.out; echo "exit=$?"
--   마른 실행(스크립트 없이 검증만 · 유령 2 가 FAIL 로 잡혀야 한다): 위 명령에서 -v ops=… 만 뺀다
--   기대: 시험 OK 11 · FAIL 0(안의 ops 스크립트 OK 11 · MISMATCH 0) / 마른 실행 OK 2 · FAIL 3(T 둘 · W1 — 유령 2) — 통과한 실행(2026-11-11 02:50 토론토 · 1 회차)에서 받아 적었다 · begin ~ rollback 7.3 s / 2.6 s
--   ⚠️ 이 파일은 적용 뒤 확인용이 아니다(재생성 흉내가 실제 레이어를 지웠다 되돌린다 · 지시서 §4 가 허락한 시험 전용) — 적용 뒤 확인은 ops 스크립트의 -v check=1
--   ⚠️ 재료가 가짜가 아니다(지시서 §4): 실제 두 SKU 가 대상 · 그래서 끝은 반드시 rollback · 번호 시퀀스는 쓰지 않는다(전 · 후 원문을 찍는다)
--   재생성 흉내(R1 · R2): inv_layer_apply 전체가 아니라 그 갈래를 본뜬 것 — 그 SKU × EDM 의 「첫 + 조정 날」 부터의 소진 · 레이어(조정 · 판매 부족분)를 지우고
--     그날부터의 원장 행을 inv_layer_apply 의 루프 순서(occurred_on · seq_hint · id)로 같은 갈래 함수(inv_layer_apply_adjust_ims · inv_layer_apply_sale_out)에 다시 넣는다 → 지문(id · 시각 제외)이 지금과 같은가
--     서브트랜잭션 안에서 돌리고 결과를 예외 메시지에 실어 나른다 = 안의 쓰기는 전부 되돌아간다(inv-count-1 · asung-workflow §4 「동일성 시험」)
--     ORS21020 은 11-10 같은 날에 + 조정(ADJ-00134 · seq 1)과 판매(SO-21211 · seq 2)가 있다 — 재생성은 유입 먼저(실시간은 판매 먼저) · 판매의 shortfall hint 가 같은 결과를 내는지도 여기서 본다
select last_value as seq_last, is_called as seq_called from public.inv_adjust_number_seq \gset
\echo 'head: inv_adjust_number_seq' :seq_last :seq_called

\if :{?ops}
\set nb5t_ops 1
\else
\set nb5t_ops 0
\endif

begin;
select set_config('nb5t.ops', :'nb5t_ops', true) as nb5t_ops, set_config('nb5t.seq', :'seq_last', true) as nb5t_seq \gset

-- ═══ 도우미 · 전(前) 담기 — 문장 하나 ═══
do $$ begin
  perform set_config('lock_timeout', '3s', true);
  perform set_config('statement_timeout', '90s', true);
  create temp table t_res (n int generated always as identity, tag text, ok boolean, detail text) on commit drop;
  create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as
    'insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, ''(null)''), 1500))';
  -- 지문: 그 SKU × EDM 의 레이어 · 소진 전부(id · 시각 제외 · 정렬 · 숫자는 trim_scale)
  create function pg_temp.fp(p_sku text) returns text language sql as $f$
    select 'L[' || coalesce((select string_agg(format('%s|%s|%s|%s|%s|%s|%s|rem %s|val %s', y.origin_type, y.doc_number, y.line_ref, y.received_on, trim_scale(y.qty), trim_scale(y.unit_cost), y.cost_source,
                                                      trim_scale(v.remaining_qty), trim_scale(v.remaining_value)), ' ; ' order by y.received_on, y.origin_type, y.doc_number, y.line_ref, y.qty)
                               from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = 'Asung - Edmonton'), '')
        || '] C[' || coalesce((select string_agg(format('%s/%s/%s<-%s|%s|%s|%s|%s|%s|%s|%s', y.origin_type, y.doc_number, y.line_ref, c.doc_type, c.doc_number, c.line_ref, c.event_type, c.occurred_on,
                                                        trim_scale(c.qty), trim_scale(c.unit_cost), trim_scale(c.amount)) || '|' || c.reason, ' ; '
                                                 order by c.occurred_on, c.doc_number, c.line_ref, y.received_on, y.origin_type, y.doc_number, y.line_ref, c.qty)
                                 from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id where y.sku = p_sku and y.warehouse = 'Asung - Edmonton'), '') || ']'
  $f$;
  -- 재생성 흉내(머리 주석) — 쓰기 0(서브트랜잭션 되돌림)
  create function pg_temp.regen(p_sku text, p_from date) returns text language plpgsql as $f$
  declare v_r record; v_fp text; v_n int := 0;
  begin
    if exists (select 1 from public.inv_ledger e where e.sku = p_sku and e.warehouse = 'Asung - Edmonton' and e.occurred_on >= p_from
                 and (e.source <> 'ims' or e.event_type not in ('adjust_existing', 'adjust_new', 'sale_out'))) then
      return 'UNSUPPORTED: a ledger row since ' || p_from || ' is not an IMS adjustment or sale — this imitation does not cover it';
    end if;
    begin
      delete from public.inv_layer_consume c using public.inv_layer y where y.id = c.layer_id and y.sku = p_sku and y.warehouse = 'Asung - Edmonton' and c.occurred_on >= p_from;
      delete from public.inv_layer y where y.sku = p_sku and y.warehouse = 'Asung - Edmonton' and y.received_on >= p_from and y.origin_type in ('adjust_new', 'adjust_existing', 'sale_shortfall');
      perform public.inv_layer_apply_reset_done();
      for v_r in select e.id, e.event_type from public.inv_ledger e where e.sku = p_sku and e.warehouse = 'Asung - Edmonton' and e.occurred_on >= p_from order by e.occurred_on, e.seq_hint, e.id loop
        if v_r.event_type = 'sale_out' then perform public.inv_layer_apply_sale_out(v_r.id, null);
        else perform public.inv_layer_apply_adjust_ims(v_r.id, null); end if;
        v_n := v_n + 1;
      end loop;
      v_fp := 'rows ' || v_n || ' · ' || pg_temp.fp(p_sku);
      raise exception using errcode = 'NB5R0', message = v_fp;
    exception when sqlstate 'NB5R0' then
      v_fp := sqlerrm;
    end;
    return v_fp;
  end $f$;
  -- 「레이어 = 장부」 대조 — 지점 창고 둘 전부(SKU × 창고) · 레이어 남은 수량 합 ↔ 장부 수량 합
  create function pg_temp.whcheck() returns jsonb language sql as $f$
    with lay as (select y.sku, y.warehouse, sum(y.qty - coalesce(c.q, 0)) as rem
                   from public.inv_layer y left join (select k.layer_id, sum(k.qty) as q from public.inv_layer_consume k group by 1) c on c.layer_id = y.id
                  where y.warehouse in ('Asung Trading Inc.', 'Asung - Edmonton') group by 1, 2),
         led as (select b.sku, b.warehouse, sum(b.qty) as q from public.inv_balance b where b.warehouse in ('Asung Trading Inc.', 'Asung - Edmonton') group by 1, 2)
    select jsonb_build_object('keys', count(*), 'layer_over', count(*) filter (where coalesce(a.rem, 0) > coalesce(d.q, 0)), 'layer_under', count(*) filter (where coalesce(a.rem, 0) < coalesce(d.q, 0)),
             'over_list', coalesce(string_agg(coalesce(a.sku, d.sku) || '@' || coalesce(a.warehouse, d.warehouse) || ' lay ' || trim_scale(coalesce(a.rem, 0)) || ' led ' || trim_scale(coalesce(d.q, 0)), ' · '
                                              order by coalesce(a.sku, d.sku)) filter (where coalesce(a.rem, 0) > coalesce(d.q, 0)), ''))
      from lay a full join led d on d.sku = a.sku and d.warehouse = a.warehouse
  $f$;
  -- 하루 원가 장 미리 보기(오늘 · EDM) — qbo_cost_preview 는 QuickBooks 열쇠 문이 있다 → 그 호출 동안만 admin claims(ops 스크립트는 claims 없이 돈다 = 실제 적용과 같다)
  create function pg_temp.pv() returns jsonb language plpgsql as $f$
  declare v_sub text; v_j jsonb;
  begin
    select s.auth_user_id::text into v_sub from public.ims_staff s where s.is_active and s.role = 'admin' and s.auth_user_id is not null order by s.created_at limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_sub, 'role', 'authenticated')::text, true);
    v_j := public.qbo_cost_preview(public.ims_today(), 'EDM');
    perform set_config('request.jwt.claims', '', true);
    return v_j;
  end $f$;
  create temp table t_pre on commit drop as
  select clock_timestamp() as t0, pg_temp.whcheck() as wh, pg_temp.pv() as pv,
         (select last_value from public.inv_adjust_number_seq) as seq,
         (select count(*) from public.shop_stock_queue q where q.done_at is null) as queue_open,
         (select count(*) from public.shop_stock_queue q join public.product p on p.id = q.product_id where q.done_at is null and p.sku not in ('EZB70340', 'ORS21020')) as queue_other,
         (select count(*) from public.shop_store s where s.is_active and s.live) as live_stores,
         (select md5(coalesce(string_agg(to_jsonb(a)::text, ',' order by a.adjust_number), '')) from public.inv_adjust a where a.adjust_number in ('ADJ-00101', 'ADJ-00134'))
           || '/' || (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), '')) from public.inv_ledger e where e.sku in ('EZB70340', 'ORS21020') and e.warehouse = 'Asung - Edmonton' and e.raw ->> 'prompt' is distinct from 'nb-5')
           || '/' || (select md5(coalesce(string_agg(to_jsonb(y)::text, ',' order by y.id), '')) from public.inv_layer y where y.sku in ('EZB70340', 'ORS21020') and y.warehouse = 'Asung - Edmonton') as old_md5;
end $$;
\echo '전(前): 레이어 = 장부 대조 · 원가 장 미리 보기(오늘 · EDM)'
select wh as layer_vs_ledger_before, pv ->> 'date' as sheet_date, pv ->> 'baseline' as baseline, pv -> 'sheet' ->> 'state' as sheet_state, pv ->> 'error' as error,
       jsonb_array_length(pv -> 'keys') as keys, jsonb_array_length(pv -> 'holds') as holds, jsonb_array_length(pv -> 'blocks') as blocks, pv ->> 'debit_cents' as debit_cents, pv ->> 'balanced' as balanced from t_pre;

\if :{?ops}
\echo '── ops 스크립트(rollback 됨):' :ops
\i :ops
\else
\echo '── 마른 실행: ops 스크립트 없이 검증만'
\endif

-- ═══ 검증 — 문장 하나 ═══
do $$
declare
  v_ops boolean := current_setting('nb5t.ops', true) = '1';
  v_pre record; v_wh jsonb; v_pv jsonb; v_a text; v_b text; v_t text; v_n int; v_m int; p record;
begin
  select * into v_pre from t_pre;
  -- R 재생성 재현(두 모드 모두 · 마른 실행에서는 「지금의 유령이 그대로 되살아난다」 를 보인다)
  for p in select * from (values ('EZB70340', date '2026-11-09'), ('ORS21020', date '2026-11-10')) v(sku, d0) order by 1 loop
    v_a := pg_temp.fp(p.sku);
    v_b := pg_temp.regen(p.sku, p.d0);
    perform pg_temp.res(format('R %s 재생성 재현 — %s 부터의 소진 · 레이어를 지우고 원장 순서로 다시 세운 지문 = 지금 지문', p.sku, p.d0),
      substring(v_b from position(' · ' in v_b) + 3) = v_a and position('UNSUPPORTED' in v_b) = 0,
      case when substring(v_b from position(' · ' in v_b) + 3) = v_a
           then left(v_b, position(' · ' in v_b) - 1) || ' replayed · same · layers still open after replay: '
                || coalesce((select string_agg(m[1], ' ; ') from regexp_matches(v_b, '([a-z_]+\|[^|;]*\|[^|;]*\|[^|;]*\|[^|;]*\|[^|;]*\|[^|;]*\|rem [0-9.]*[1-9][0-9.]*\|val [0-9.]+)', 'g') m), 'none')
           else 'now ' || v_a || ' ≠ regen ' || v_b end);
  end loop;
  -- T 목표 모양(두 모드 모두 · 마른 실행은 FAIL 이어야 한다)
  for p in select * from (values ('EZB70340'), ('ORS21020')) v(sku) order by 1 loop
    select format('bins[%s] ledger %s · layer qty %s · value %s',
             (select coalesce(string_agg(coalesce(nullif(b.bin, ''), '(no bin)') || '=' || trim_scale(b.qty), ' ' order by b.bin), '') from public.inv_balance b where b.sku = p.sku and b.warehouse = 'Asung - Edmonton' and b.qty <> 0),
             (select trim_scale(coalesce(sum(b.qty), 0)) from public.inv_balance b where b.sku = p.sku and b.warehouse = 'Asung - Edmonton'),
             (select trim_scale(coalesce(sum(v.remaining_qty), 0)) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p.sku and y.warehouse = 'Asung - Edmonton'),
             (select trim_scale(coalesce(sum(v.remaining_value), 0)) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p.sku and y.warehouse = 'Asung - Edmonton')) into v_t;
    perform pg_temp.res(format('T %s 목표 — EDM 모든 칸 0(칸 없음 포함) · 장부 0 · 레이어 남은 0 · 가치 0', p.sku), v_t = 'bins[] ledger 0 · layer qty 0 · value 0', v_t);
  end loop;
  -- W 「레이어 = 장부」 — 지점 창고 전부
  v_wh := pg_temp.whcheck();
  perform pg_temp.res('W1 지점 창고 전부(SKU × 창고) 레이어 남은 > 장부 = 0 키', (v_wh ->> 'layer_over')::int = 0, v_wh::text);
  if v_ops then
    perform pg_temp.res('W2 전 = 2 키(이 둘뿐) → 후 0 · 「레이어 < 장부」 키 수 · 전체 키 수 무변',
      (v_pre.wh ->> 'layer_over')::int = 2 and v_pre.wh ->> 'over_list' = 'EZB70340@Asung - Edmonton lay 1 led 0 · ORS21020@Asung - Edmonton lay 1 led 0'
      and (v_wh ->> 'layer_over')::int = 0 and v_wh -> 'layer_under' = v_pre.wh -> 'layer_under' and v_wh -> 'keys' = v_pre.wh -> 'keys',
      'before ' || v_pre.wh::text || ' → after ' || v_wh::text);
    -- P 하루 원가 장(오늘 · EDM) 전 · 후
    v_pv := pg_temp.pv();
    create temp table t_post (pv jsonb) on commit drop;
    insert into t_post (pv) values (v_pv);
    select count(*) into v_n from jsonb_array_elements(v_pre.pv -> 'keys') k where not exists (select 1 from jsonb_array_elements(v_pv -> 'keys') a where a = k);
    select count(*), coalesce(string_agg(format('%s %s|%s|%s|%s|%s', a ->> 'key_kind', a ->> 'doc_key', a ->> 'acct_a', a ->> 'acct_b', a ->> 'diff_cents', a ->> 'status'), ' · ' order by a ->> 'doc_key'), '')
      into v_m, v_t from jsonb_array_elements(v_pv -> 'keys') a where not exists (select 1 from jsonb_array_elements(v_pre.pv -> 'keys') k where k = a);
    perform pg_temp.res('P1 원가 장 열쇠: 사라진 것 0 · 새로 생긴 것 2 = ADJ-NB5-EZB70340 +526 · ADJ-NB5-ORS21020 +556(차 _1150040010_ / 대 _59_ · send) · 보류 · 제외 · 막음 · 오류 무변(판정 1094 의 SO 줄 포함 나머지 전부 그대로)',
      v_n = 0 and v_m = 2 and v_t = 'ADJ ADJ-NB5-EZB70340|_1150040010_|_59_|526|send · ADJ ADJ-NB5-ORS21020|_1150040010_|_59_|556|send'
      and v_pv -> 'holds' = v_pre.pv -> 'holds' and v_pv -> 'excluded' = v_pre.pv -> 'excluded' and v_pv -> 'blocks' = v_pre.pv -> 'blocks' and v_pv ->> 'error' is null and v_pre.pv ->> 'error' is null,
      format('gone %s · new %s [%s] · blocks %s → %s · error %s', v_n, v_m, v_t, jsonb_array_length(v_pre.pv -> 'blocks'), jsonb_array_length(v_pv -> 'blocks'), coalesce(v_pv ->> 'error', '-')));
    select coalesce(string_agg(format('%s %s %s %s', a ->> 'account_code', a ->> 'posting', a ->> 'cents', coalesce(a ->> 'doc_key', '-')), ' · ' order by a ->> 'account_code', a ->> 'doc_key'), '') into v_t
      from jsonb_array_elements(v_pv -> 'je_lines') a where not exists (select 1 from jsonb_array_elements(v_pre.pv -> 'je_lines') k where k = a) and a ->> 'account_code' <> '_59_';
    select (select coalesce(sum(case when a ->> 'posting' = 'Debit' then 1 else -1 end * (a ->> 'cents')::bigint), 0) from jsonb_array_elements(v_pv -> 'je_lines') a where a ->> 'account_code' = '_59_')
         - (select coalesce(sum(case when a ->> 'posting' = 'Debit' then 1 else -1 end * (a ->> 'cents')::bigint), 0) from jsonb_array_elements(v_pre.pv -> 'je_lines') a where a ->> 'account_code' = '_59_') into v_n;
    perform pg_temp.res('P2 분개 줄: 새 줄 = 차 _1150040010_ 526 · 556(문서마다) · #59(재고 EDM) 순액 −1082 센트 · 차 = 대',
      v_t = '_1150040010_ Debit 526 ADJ-NB5-EZB70340 · _1150040010_ Debit 556 ADJ-NB5-ORS21020' and v_n = -1082 and (v_pv ->> 'balanced')::boolean,
      format('new [%s] · #59 net %s · balanced %s · debit %s → %s', v_t, v_n, v_pv ->> 'balanced', v_pre.pv ->> 'debit_cents', v_pv ->> 'debit_cents'));
    -- Q 무접촉
    select last_value into v_n from public.inv_adjust_number_seq;
    perform pg_temp.res('Q1 번호 시퀀스 inv_adjust_number_seq 무접촉(머리 = 전 = 후)', v_n = v_pre.seq and v_n = current_setting('nb5t.seq')::bigint, format('head %s · before %s · after %s', current_setting('nb5t.seq'), v_pre.seq, v_n));
    select count(*) into v_n from public.shop_stock_queue q where q.done_at is null;
    select count(*) into v_m from public.shop_stock_queue q join public.product p2 on p2.id = q.product_id where q.done_at is null and p2.sku not in ('EZB70340', 'ORS21020');
    perform pg_temp.res('Q2 Shopify 큐 — 두 제품 밖 열린 줄 무변 · 새 줄은 두 제품 × live 스토어 이하(창고 합이 같아 drain 이 skipped_same)', v_m = v_pre.queue_other and v_n - v_pre.queue_open <= 2 * v_pre.live_stores,
      format('open %s → %s · other %s → %s · live stores %s', v_pre.queue_open, v_n, v_pre.queue_other, v_m, v_pre.live_stores));
    select (select md5(coalesce(string_agg(to_jsonb(a)::text, ',' order by a.adjust_number), '')) from public.inv_adjust a where a.adjust_number in ('ADJ-00101', 'ADJ-00134'))
           || '/' || (select md5(coalesce(string_agg(to_jsonb(e)::text, ',' order by e.id), '')) from public.inv_ledger e where e.sku in ('EZB70340', 'ORS21020') and e.warehouse = 'Asung - Edmonton' and e.raw ->> 'prompt' is distinct from 'nb-5')
           || '/' || (select md5(coalesce(string_agg(to_jsonb(y)::text, ',' order by y.id), '')) from public.inv_layer y where y.sku in ('EZB70340', 'ORS21020') and y.warehouse = 'Asung - Edmonton') into v_t;
    perform pg_temp.res('Q3 옛 것 무변 — 조정 문서 ADJ-00101 · ADJ-00134 · 두 SKU 의 옛 원장 행 · 레이어 행(md5 · 소진만 늘었다)', v_t = v_pre.old_md5, v_pre.old_md5 || ' → ' || v_t);
  end if;
end $$;

\echo '═══ 결과 ═══'
select n, case when ok then 'OK  ' else 'FAIL' end as r, tag, detail from t_res order by n;
\if :{?ops}
\echo '═══ 하루 원가 장 미리 보기(오늘 · EDM) 전 · 후 차이만 ═══'
select 'keys +' as what, a as line from t_pre b, t_post c, jsonb_array_elements(c.pv -> 'keys') a where not exists (select 1 from jsonb_array_elements(b.pv -> 'keys') k where k = a)
union all select 'keys -', k from t_pre b, t_post c, jsonb_array_elements(b.pv -> 'keys') k where not exists (select 1 from jsonb_array_elements(c.pv -> 'keys') a where a = k)
union all select 'je   +', a from t_pre b, t_post c, jsonb_array_elements(c.pv -> 'je_lines') a where not exists (select 1 from jsonb_array_elements(b.pv -> 'je_lines') k where k = a)
union all select 'je   -', k from t_pre b, t_post c, jsonb_array_elements(b.pv -> 'je_lines') k where not exists (select 1 from jsonb_array_elements(c.pv -> 'je_lines') a where a = k)
union all select 'totals', jsonb_build_object('debit_before', b.pv -> 'debit_cents', 'debit_after', c.pv -> 'debit_cents', 'credit_before', b.pv -> 'credit_cents', 'credit_after', c.pv -> 'credit_cents',
                                             'lines_before', b.pv -> 'je_line_count', 'lines_after', c.pv -> 'je_line_count', 'balanced_after', c.pv -> 'balanced') from t_pre b, t_post c;
\endif
select 'OK ' || count(*) filter (where ok) || ' · FAIL ' || count(*) filter (where not ok) || ' · begin ~ here ' || round(extract(epoch from clock_timestamp() - (select t0 from t_pre))::numeric, 1) || ' s' as summary from t_res;
rollback;
select last_value as seq_last_after, is_called as seq_called_after from public.inv_adjust_number_seq;
