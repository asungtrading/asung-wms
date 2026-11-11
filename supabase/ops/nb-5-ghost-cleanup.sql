-- supabase/ops/nb-5-ghost-cleanup.sql — 유령 원가 두 건 정리(EDM EZB70340 · ORS21020 · 판정 1178 · nb-5 · 2026-11-11)
-- [Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ 옛 운영 asung-WMS 에 돌리지 않는다(⓪ 가드가 막는다)
--
-- 무엇: 재고 없이 판 뒤 단가를 넣은 + 조정(nb-1 이 서기 전)이 남긴 「수량 0 인데 가치가 남은」 레이어 둘을 없앤다 — 장부 0(모든 칸) · 레이어 남은 0 · 가치 0.
--   EZB70340 EDM  장부 '' −1 · EA010404 +1(합 0) · 레이어 3975371 1 @5.264(ADJ-00101 · 판매 SO-21090)
--   ORS21020 EDM  장부 0                          · 레이어 3975634 1 @5.564(ADJ-00134 · 판매 SO-21211)   합 $10.828(장에는 5.26 + 5.56 = $10.82)
-- 꼴: SKU 마다 조정 문서 하나(머리만 · 줄 없음) + 원장 짝 두 줄(source ims · doc_type adjustment · event_type adjust_existing · 같은 날 occurred_on = ims_today() = 적용하는 날)
--   + 다리 seq 1  line_ref nb-5:in   +1  → 실제 창구 inv_layer_post_adjust(nb-1 판)가 「레이어 남은 1 − 장부 0 = 1」 을 전부 메운다(레이어 없음 · amount 0 · raw.cost.fill_qty 1)
--   − 다리 seq 2  line_ref nb-5:out  −1  → 같은 창구가 FIFO 로 유령 레이어를 소진(reason adjust_out · amount = 그 레이어 가치)
--   EZB70340: + 다리 = 칸 없음('') · − 다리 = EA010404 → 두 칸 모두 0(칸 없음 −1 도 이 짝이 메운다 · 줄 둘로 끝)   ORS21020: 두 다리 모두 ED020203(칸 무변 · 순액 0)
--   문서 번호 ADJ-NB5-EZB70340 · ADJ-NB5-ORS21020(고정 — 번호 시퀀스 inv_adjust_number_seq 를 쓰지 않는다 · 다시 돌리면 번호로 멈춘다)
-- 왜 source ims · 조정 문서인가(inv-count-1 의 MANUAL · manual 꼴이 아닌 까닭 · 코드):
--   ① 재생성 inv_layer_apply 는 manual 조정을 inv_layer_apply_adjust 로 보낸다 = (문서, SKU, 창고, event_type) 순액 → ± 짝은 0 = 아무것도 안 함 · fill hint 도 안 읽는다 ⇒ 유령이 그대로 남는다.
--      ims 조정만 inv_layer_apply_adjust_ims → inv_layer_post_adjust(raw.cost hint) = 실시간과 같은 함수 · 줄(line_ref)마다.
--   ② 하루 원가 장 qbo_cost_expected 의 범위 = source ims 문서 · adjust_out 소진의 계정은 inv_adjust(adjust_number = 문서 번호)에서 읽는다(없으면 block 「adjustment … not found」 = 장이 멈춘다).
--      ⇒ inv_adjust 머리가 있어야 한다 · account 를 비우면 기본 계정(inv_adjust_default_account_code = _1150040010_ = ADJ-00101 · ADJ-00134 가 쓴 계정) ⇒ 그 두 조정의 반대 줄.
--   ③ 문서를 SKU 마다 나눈 까닭: 장은 (창고, 종류, 문서, 계정)마다 센트로 반올림한다 — 한 문서면 10.828 → 10.83 · 이미 간 5.26 + 갈 5.56 = 10.82 와 1 센트 어긋난다.
--   줄(inv_adjust_line)이 없는 까닭: 줄은 칸 없음을 못 담고(bin_ck) 한 문서 · 제품 · 칸에 줄 하나(line_uq)라 ± 두 다리를 못 담는다 — 설명은 머리 note · 실물은 원장 raw.
-- 하루 원가 장(적용하는 날 · EDM): ADJ-NB5-EZB70340 차 _1150040010_ 5.26 / 대 #59 · ADJ-NB5-ORS21020 차 _1150040010_ 5.56 / 대 #59 — 그 밖의 열쇠 무변(판정 1094 의 판매 줄 SO-21090 · SO-21211 그대로).
-- 재생성: 옛 + 조정 행(ADJ-00101 · ADJ-00134)은 raw.cost 에 fill_qty 가 없어 fill 0 = 레이어를 다시 세운다 → 이 문서의 + 다리가 hint 1 로 메우고(레이어 없음) − 다리가 FIFO 로 그 레이어를 소진 = 같은 결과
--   (유령 레이어가 그 SKU × 창고에 남은 단 하나이고 received_on 이 적용일보다 앞이라 FIFO 첫 번째 · 시험 supabase/tests/nb_5_check.sql 이 두 SKU 를 지우고 원장 순서로 다시 세워 대조한다).
--   ⚠️ 남는 틈(deferred 582 와 같은 뿌리 · 짐작): 적용한 날 · 적용 뒤에 같은 SKU 의 트랜스퍼가 EDM 에 도착하면(자식 레이어는 부모의 옛 received_on) 재생성(유입 먼저)의 − 다리가 그 레이어를 먼저 집는다 — 수량 같음 · 가치가 단가 차이만큼 다름. ⇒ 창고가 끝난 뒤 적용한다.
-- 트리거(inv_ledger): inv_ledger_bgrade_guard — 조정은 통과(두 칸 B급 아님 · '' 는 첫 줄에서 돌아간다) · shop_stock_queue_trigger — 창고 합이 같아 drain 이 skipped_same.
-- 안 하는 것: 옛 원장 행 · 옛 조정 문서 · 다른 SKU · 번호 시퀀스 · QBO 호출(장은 다음 새벽 cron 이 짓는다).
-- 꼴: 마이그레이션 아님 · 함수 아님 · 한 번 · begin/commit 없음(-1 이 한 트랜잭션) · 검산이 하나라도 어긋나면 raise → 전부 되돌아간다.
-- 실행(레포 뿌리에서):
--   시험(rollback · Claude Code): supabase/tests/nb_5_check.sql 머리의 명령
--   적용(Caleb · commit):
--     PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/ops/nb-5-ghost-cleanup.sql > ~/nb-5.log 2>&1; echo "exit=$?"; grep -nE '^OK [0-9]+|MISMATCH|ERROR' ~/nb-5.log
--   확인(적용 뒤 · 쓰기 0): 위 명령에 -v check=1  → 기대 OK 는 파일 끝 「기대」 줄
-- 되돌리기(적용 뒤 · 한 트랜잭션으로 · 그날 장이 이미 QBO 에 갔으면 다음 장이 「adj. of」 줄로 되돌린다):
--   delete from public.inv_layer_consume where doc_type = 'adjustment' and doc_number in ('ADJ-NB5-EZB70340', 'ADJ-NB5-ORS21020') and line_ref = 'nb-5:out';
--   delete from public.inv_ledger where source = 'ims' and doc_type = 'adjustment' and doc_number in ('ADJ-NB5-EZB70340', 'ADJ-NB5-ORS21020') and raw ->> 'prompt' = 'nb-5';
--   delete from public.inv_adjust where adjust_number in ('ADJ-NB5-EZB70340', 'ADJ-NB5-ORS21020');
-- 차례: ⓪ 이 DB 확인 → ① 계획 둘 · 지금 모양 → ② 지금 모양 단언(raise) → ③ 쓰기(머리 2 · 원장 4 · 소진 2) → ④ 목표 모양 검산 → 결과

-- ⓪ 이 DB 확인 (1/2) — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄)
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

\if :{?check}
\set nb5_check 1
\echo '[CHECK] check=1 — ② 지금 모양 단언 · ③ 쓰기는 건너뛴다 · 넣은 것과 목표 모양을 센다(적용 뒤 확인 실행)'
\else
\set nb5_check 0
\endif

-- ⓪ 이 DB 확인 (2/2) — po_line(IMS 전용 표) · 함께: 타임아웃 · 결과 표 · 도우미 · ① 계획 둘 · 전 숫자(문장 하나로)
select set_config('nb5.check', :'nb5_check', true) as nb5_check \gset
do $$ begin
  if to_regclass('public.po_line') is null then
    raise exception using errcode = 'WM501', message = 'STOP - not Asung-IMS: po_line missing - this is not the IMS project. Nothing was changed.';
  end if;
  perform set_config('lock_timeout', '3s', true);
  perform set_config('statement_timeout', '60s', true);
  create temp table t_nb5_res (n int generated always as identity, name text, ok boolean, detail text) on commit drop;
  create function pg_temp.nb5_chk(p_name text, p_ok boolean, p_detail text) returns void language sql as
    'insert into t_nb5_res (name, ok, detail) values (p_name, coalesce(p_ok, false), left(coalesce(p_detail, ''(null)''), 600))';
  -- ① 계획 둘(하드코딩 · nb-0 11-10 · nb-5 조사 11-11 02:40 토론토) — ghost_* = 없앨 레이어 · led_rows / led_max = 그때 그 SKU × EDM 의 원장 행 수 · 마지막 id(그 사이 판매 · 조정이 있었으면 멈춘다)
  create temp table t_nb5_plan on commit drop as
  select * from (values
    ('EZB70340', 'ADJ-NB5-EZB70340', '',         'EA010404', 3975371::bigint, 'ADJ-00101', 5.264::numeric, 'SO-21090', 2::int,  21460573::bigint, '{"": -1, "EA010404": 1}'::jsonb),
    ('ORS21020', 'ADJ-NB5-ORS21020', 'ED020203', 'ED020203', 3975634,         'ADJ-00134', 5.564,          'SO-21211', 16,      21462210,         '{}'::jsonb)
  ) v(sku, doc, bin_in, bin_out, ghost_layer, ghost_doc, ghost_value, sale_doc, led_rows, led_max, bins_now);
  -- 지금 모양을 글 하나로(SKU × EDM): 0 이 아닌 칸 · 장부 합 · 남은 레이어(id · 수량 · 가치) · 레이어 남은 합 · 가치 합 · 원장 행 수 · 마지막 id
  create function pg_temp.nb5_state(p_sku text) returns jsonb language sql as $f$
    select jsonb_build_object(
      'bins', (select coalesce(jsonb_object_agg(b.bin, b.qty), '{}'::jsonb) from public.inv_balance b where b.sku = p_sku and b.warehouse = 'Asung - Edmonton' and b.qty <> 0),
      'ledger', (select coalesce(sum(b.qty), 0) from public.inv_balance b where b.sku = p_sku and b.warehouse = 'Asung - Edmonton'),
      'open_layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'origin', y.origin_type, 'doc', y.doc_number, 'qty', v.remaining_qty, 'value', v.remaining_value) order by y.id), '[]'::jsonb)
                        from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = 'Asung - Edmonton' and (v.remaining_qty <> 0 or v.remaining_value <> 0)),
      'layer_qty', (select coalesce(sum(v.remaining_qty), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = 'Asung - Edmonton'),
      'layer_value', (select coalesce(sum(v.remaining_value), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = 'Asung - Edmonton'),
      'led_rows', (select count(*) from public.inv_ledger e where e.sku = p_sku and e.warehouse = 'Asung - Edmonton'),
      'led_max', (select max(e.id) from public.inv_ledger e where e.sku = p_sku and e.warehouse = 'Asung - Edmonton'))
  $f$;
  create temp table t_nb5_pre on commit drop as
  select p.sku, pg_temp.nb5_state(p.sku) as st,
         (select count(*) from public.inv_ledger) as n_ledger, (select count(*) from public.inv_layer) as n_layer, (select count(*) from public.inv_layer_consume) as n_consume,
         (select count(*) from public.inv_adjust) as n_adjust, (select count(*) from public.inv_adjust_line) as n_adjust_line,
         (select count(*) from public.inv_ledger e where e.doc_number = p.doc) as n_doc_ledger, (select count(*) from public.inv_adjust a where a.adjust_number = p.doc) as n_doc_adjust
    from t_nb5_plan p;
end $$;
\echo '① 지금 모양(쓰기 전) · 오늘(토론토 · occurred_on)'
select to_char(public.ims_today(), 'YYYY-MM-DD') as today, sku, st from t_nb5_pre order by sku;

-- ═══ ② 지금 모양 단언 — 하나라도 어긋나면 아무것도 쓰지 않는다(check 모드는 건너뛴다) ═══
do $$
declare p record; v_st jsonb; v_bad text := ''; v_today date := public.ims_today(); v_def text; v_acct text; v_n int;
begin
  if current_setting('nb5.check', true) = '1' then return; end if;
  select count(*) into v_n from t_nb5_pre where n_doc_ledger > 0 or n_doc_adjust > 0;
  if v_n > 0 then
    raise exception using errcode = 'IM178', message = 'STOP - nb-5 was already applied (documents ADJ-NB5-… exist) - run with -v check=1 to verify. Nothing was changed.';
  end if;
  select nullif(btrim(c.value), '') into v_def from public.inv_config c where c.key = 'inv_adjust_default_account_code';
  for p in select * from t_nb5_plan order by sku loop
    select st into v_st from t_nb5_pre where sku = p.sku;
    if v_st -> 'bins' <> p.bins_now then v_bad := v_bad || format(' [%s bins %s, expected %s]', p.sku, v_st -> 'bins', p.bins_now); end if;
    if (v_st ->> 'ledger')::numeric <> 0 then v_bad := v_bad || format(' [%s ledger %s, expected 0]', p.sku, v_st ->> 'ledger'); end if;
    if (v_st ->> 'layer_qty')::numeric <> 1 or (v_st ->> 'layer_value')::numeric <> p.ghost_value or jsonb_array_length(v_st -> 'open_layers') <> 1
       or (v_st -> 'open_layers' -> 0 ->> 'id')::bigint <> p.ghost_layer or v_st -> 'open_layers' -> 0 ->> 'doc' <> p.ghost_doc or v_st -> 'open_layers' -> 0 ->> 'origin' <> 'adjust_new' then
      v_bad := v_bad || format(' [%s open layers %s, expected only layer %s (%s) 1 @ %s]', p.sku, v_st -> 'open_layers', p.ghost_layer, p.ghost_doc, p.ghost_value);
    end if;
    if (v_st ->> 'led_rows')::int <> p.led_rows or (v_st ->> 'led_max')::bigint <> p.led_max then
      v_bad := v_bad || format(' [%s ledger rows %s last id %s, expected %s / %s - something moved this SKU since the investigation]', p.sku, v_st ->> 'led_rows', v_st ->> 'led_max', p.led_rows, p.led_max);
    end if;
    if exists (select 1 from public.inv_layer_consume c where c.layer_id = p.ghost_layer) or exists (select 1 from public.inv_layer_cost_add a where a.layer_id = p.ghost_layer)
       or exists (select 1 from public.inv_layer y where y.parent_layer_id = p.ghost_layer) then
      v_bad := v_bad || format(' [%s layer %s already has consume / cost-add / child rows]', p.sku, p.ghost_layer);
    end if;
    if (select y.received_on from public.inv_layer y where y.id = p.ghost_layer) >= v_today then
      v_bad := v_bad || format(' [%s layer %s is dated today or later - the cleanup must be dated after it]', p.sku, p.ghost_layer);
    end if;
    select y.account_code into v_acct from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = p.ghost_doc;
    if v_def is null or v_acct is distinct from v_def then
      v_bad := v_bad || format(' [%s: %s used account %s but the default adjustment account is %s - the reversal would land in another account]', p.sku, p.ghost_doc, coalesce(v_acct, '<none>'), coalesce(v_def, '<none>'));
    end if;
    select count(*) into v_n from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id
      where w.name = 'Asung - Edmonton' and rb.name in (p.bin_in, p.bin_out) and rb.is_active and not rb.is_bgrade;
    if v_n <> (select count(distinct x) from unnest(array[nullif(p.bin_in, ''), nullif(p.bin_out, '')]) x) then
      v_bad := v_bad || format(' [%s: bin %s / %s is missing, inactive or B-grade]', p.sku, coalesce(nullif(p.bin_in, ''), '(no bin)'), p.bin_out);
    end if;
  end loop;
  if v_bad <> '' then
    raise exception using errcode = 'IM178', message = 'STOP - the stock does not look like it did when nb-5 was written:' || v_bad || '. Nothing was changed.';
  end if;
end $$;

-- ═══ ③ 쓰기 — SKU 마다: 조정 머리 1 → + 다리(창구 → 원장) → − 다리(창구 → 원장) · inv_post_adjust 와 같은 순서(레이어 먼저 · 결과를 raw.cost 에) ═══
do $$
declare
  c_poster constant text := 'nb-5-ghost-cleanup@2026-11-11.1';
  c_wh     constant text := 'Asung - Edmonton';
  p record; v_today date := public.ims_today(); v_whid uuid; v_pid uuid; v_adj uuid; v_note text; v_hdr jsonb; v_cost jsonb; v_bin_id uuid;
begin
  if current_setting('nb5.check', true) = '1' then return; end if;
  select w.id into strict v_whid from public.ref_warehouse w where w.name = c_wh;
  for p in select * from t_nb5_plan order by sku loop
    select pr.id into strict v_pid from public.product pr where pr.sku = p.sku;
    v_note := format('nb-5 ghost cost cleanup(판정 1178) - %s, Edmonton: 0 on hand (counted). %s added +1 with a unit cost after %s had already sold that unit without stock, so a cost layer of 1 @ %s stayed with no stock behind it. '
                     || 'This document removes it: +1 in %s (fills the sold-without-stock gap - no new cost) and -1 in %s (uses up that layer). Quantity net 0. It has no lines on purpose - see Stock movements for the two rows.',
                     p.sku, p.ghost_doc, p.sale_doc, p.ghost_value, coalesce(nullif(p.bin_in, ''), '(no bin)'), p.bin_out);
    insert into public.inv_adjust (adjust_number, status, warehouse_id, warehouse, note, posted_on, confirmed_at)
    values (p.doc, 'confirmed', v_whid, c_wh, v_note, v_today, now()) returning id into v_adj;
    v_hdr := jsonb_build_object('adjust_number', p.doc, 'adjusted_on', v_today, 'warehouse_id', v_whid, 'warehouse', c_wh, 'report_id', null, 'account_code', null, 'note', v_note, 'confirmed_by', null);

    -- + 다리: 메우기는 창구가 스스로 센다(hint null = 실시간) — 레이어 남은 1 − 장부 0 = 1 을 전부 메워야 한다
    v_cost := public.inv_layer_post_adjust(p.doc, 'nb-5:in', p.sku, c_wh, 1, v_today, null, null);
    if v_cost ->> 'branch' is distinct from 'filled' or (v_cost ->> 'fill_qty')::numeric is distinct from 1 or v_cost ? 'layer_id' then
      raise exception using errcode = 'IM178', message = format('STOP - %s: the + leg did not fill (inv_layer_post_adjust returned %s). Nothing was changed.', p.sku, v_cost);
    end if;
    select rb.id into v_bin_id from public.ref_bin rb where rb.warehouse_id = v_whid and rb.name = p.bin_in and p.bin_in <> '';
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_today, 1, p.sku, c_wh, p.bin_in, 1, 'adjust_existing', 'adjustment', p.doc, v_adj::text, 'nb-5:in', nullif(v_cost ->> 'amount', '')::numeric, 'ims',
            jsonb_build_object('kind', 'adjust', 'poster', c_poster, 'header', v_hdr,
              'line', jsonb_build_object('line_id', null, 'line_no', 1, 'product_id', v_pid, 'sku', p.sku, 'bin_id', v_bin_id, 'bin', p.bin_in, 'mode', 'delta', 'qty_input', 1, 'delta', 1,
                                         'reason', 'other', 'reason_note', 'nb-5 ghost cost cleanup - fill leg', 'unit_cost', null),
              'rule', format('nb-5 fill leg: +1 in %s, filled by the sold-without-stock gap of %s (layer remaining 1 - ledger 0) - no layer, no cost', coalesce(nullif(p.bin_in, ''), '(no bin)'), p.sale_doc),
              'cost', v_cost, 'prompt', 'nb-5', 'decision', 1178, 'leg', 'in',
              'ghost', jsonb_build_object('layer_id', p.ghost_layer, 'doc', p.ghost_doc, 'sale', p.sale_doc, 'value', p.ghost_value)));

    -- − 다리: FIFO 가 유령 레이어 하나를 통째로 소진해야 한다
    v_cost := public.inv_layer_post_adjust(p.doc, 'nb-5:out', p.sku, c_wh, -1, v_today, null, null);
    if (v_cost ->> 'taken')::numeric is distinct from 1 or (v_cost ->> 'short')::int is distinct from 0 or (v_cost ->> 'consume_rows')::int is distinct from 1
       or (v_cost ->> 'amount')::numeric is distinct from p.ghost_value
       or not exists (select 1 from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p.doc and c.line_ref = 'nb-5:out' and c.layer_id = p.ghost_layer) then
      raise exception using errcode = 'IM178', message = format('STOP - %s: the - leg did not use up layer %s (inv_layer_post_adjust returned %s). Nothing was changed.', p.sku, p.ghost_layer, v_cost);
    end if;
    select rb.id into v_bin_id from public.ref_bin rb where rb.warehouse_id = v_whid and rb.name = p.bin_out;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_today, 2, p.sku, c_wh, p.bin_out, -1, 'adjust_existing', 'adjustment', p.doc, v_adj::text, 'nb-5:out', nullif(v_cost ->> 'amount', '')::numeric, 'ims',
            jsonb_build_object('kind', 'adjust', 'poster', c_poster, 'header', v_hdr,
              'line', jsonb_build_object('line_id', null, 'line_no', 2, 'product_id', v_pid, 'sku', p.sku, 'bin_id', v_bin_id, 'bin', p.bin_out, 'mode', 'delta', 'qty_input', -1, 'delta', -1,
                                         'reason', 'other', 'reason_note', 'nb-5 ghost cost cleanup - layer leg', 'unit_cost', null),
              'rule', format('nb-5 layer leg: -1 in %s, uses up cost layer %s (1 @ %s) left by %s', p.bin_out, p.ghost_layer, p.ghost_value, p.ghost_doc),
              'cost', v_cost, 'prompt', 'nb-5', 'decision', 1178, 'leg', 'out',
              'ghost', jsonb_build_object('layer_id', p.ghost_layer, 'doc', p.ghost_doc, 'sale', p.sale_doc, 'value', p.ghost_value)));
  end loop;
end $$;

-- ═══ ④ 목표 모양 검산 — 문장 하나(DO) · check 모드는 「전 + n」 줄을 건너뛴다 ═══
do $$
declare p record; v_st jsonb; v_check boolean := current_setting('nb5.check', true) = '1'; v_n int; v_t text; v_day date; v_exp jsonb := '{}'::jsonb;
begin
  -- 하루 원가 장의 누적 기대(문서 날짜까지) — 한 번만 부른다(무겁다) · 문서가 없으면(적용 전 check) 비운다
  select max(a.posted_on) into v_day from public.inv_adjust a where a.adjust_number in (select doc from t_nb5_plan);
  if v_day is not null then
    select coalesce(jsonb_object_agg(q.doc_key, q.t), '{}'::jsonb) into v_exp
      from (select x.doc_key, string_agg(format('%s %s %s|%s|%s|%s', x.wh_code, x.key_kind, x.doc_key, x.acct_a, x.acct_b, x.cents) || '|' || x.status, ' · ') as t
              from public.qbo_cost_expected(v_day, null, null) x where x.doc_key in (select doc from t_nb5_plan) group by 1) q;
  end if;
  for p in select * from t_nb5_plan order by sku loop
    v_st := pg_temp.nb5_state(p.sku);
    perform pg_temp.nb5_chk(format('④ %s 목표 — 모든 칸 0(칸 없음 포함) · 장부 0 · 남은 레이어 없음 · 레이어 남은 0 · 가치 0', p.sku),
      v_st -> 'bins' = '{}'::jsonb and (v_st ->> 'ledger')::numeric = 0 and jsonb_array_length(v_st -> 'open_layers') = 0 and (v_st ->> 'layer_qty')::numeric = 0 and (v_st ->> 'layer_value')::numeric = 0,
      (v_st - 'led_rows' - 'led_max')::text);
    select count(*) into v_n from public.inv_adjust a
      where a.adjust_number = p.doc and a.status = 'confirmed' and a.warehouse = 'Asung - Edmonton' and a.account_id is null and a.note like 'nb-5 ghost cost cleanup(판정 1178)%'
        and not exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id);
    perform pg_temp.nb5_chk(format('④ %s 조정 머리 1 — confirmed · EDM · 계정 비움(기본) · note 「nb-5 ghost cost cleanup(판정 1178)…」 · 줄 0', p.doc), v_n = 1, format('n %s · posted_on %s', v_n, v_day));
    select string_agg(format('%s|%s|%s|%s|%s|%s|fill %s|taken %s|short %s', e.line_ref, e.seq_hint, coalesce(nullif(e.bin, ''), '(no bin)'), trim_scale(e.qty_delta), trim_scale(e.amount), e.raw -> 'cost' ->> 'branch',
                             coalesce(trim_scale((e.raw -> 'cost' ->> 'fill_qty')::numeric)::text, '-'), coalesce(trim_scale((e.raw -> 'cost' ->> 'taken')::numeric)::text, '-'), coalesce(e.raw -> 'cost' ->> 'short', '-')), ' · ' order by e.seq_hint, e.id)
      into v_t
      from public.inv_ledger e
      where e.doc_number = p.doc and e.doc_type = 'adjustment' and e.source = 'ims' and e.event_type = 'adjust_existing' and e.sku = p.sku and e.warehouse = 'Asung - Edmonton'
        and e.raw ->> 'prompt' = 'nb-5' and e.occurred_on = v_day and e.doc_task_id = (select a.id::text from public.inv_adjust a where a.adjust_number = p.doc);
    perform pg_temp.nb5_chk(format('④ %s 원장 2 행 — + 다리(seq 1 · 메움 1 · amount 0) · − 다리(seq 2 · FIFO 1 · short 0 · amount = 레이어 가치) · 머리와 같은 날', p.doc),
      v_t = format('nb-5:in|1|%s|1|0|filled|fill 1|taken -|short - · nb-5:out|2|%s|-1|%s|fifo|fill -|taken 1|short 0', coalesce(nullif(p.bin_in, ''), '(no bin)'), p.bin_out, trim_scale(p.ghost_value)), v_t);
    select string_agg(format('layer %s|%s|%s|%s|%s|%s', c.layer_id, c.line_ref, c.reason, trim_scale(c.qty), trim_scale(c.amount), (c.occurred_on = v_day)::text), ' · ' order by c.id) into v_t
      from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p.doc;
    perform pg_temp.nb5_chk(format('④ %s 소진 1 행 — 레이어 %s · adjust_out · 1 · %s · 새 레이어 0', p.doc, p.ghost_layer, p.ghost_value),
      v_t = format('layer %s|nb-5:out|adjust_out|1|%s|true', p.ghost_layer, trim_scale(p.ghost_value)) and not exists (select 1 from public.inv_layer y where y.doc_number = p.doc), v_t);
    -- 하루 원가 장에 갈 줄(누적 기대 · 이 문서 열쇠): 차 조정 기본 계정 / 대 #59 · send · 센트 = 레이어 가치 반올림
    v_t := v_exp ->> p.doc;
    perform pg_temp.nb5_chk(format('④ %s 하루 원가 장 기대 — EDM ADJ 차 _1150040010_ / 대 _59_ · +%s 센트 · send(ADJ-00101 · ADJ-00134 의 반대 부호)', p.doc, (round(p.ghost_value, 2) * 100)::bigint),
      v_t = format('EDM ADJ %s|_1150040010_|_59_|%s|send', p.doc, (round(p.ghost_value, 2) * 100)::bigint), v_t);
  end loop;
  if not v_check then
    select format('ledger +%s · layer +%s · consume +%s · adjust +%s · adjust_line +%s',
                  (select count(*) from public.inv_ledger) - min(n_ledger), (select count(*) from public.inv_layer) - min(n_layer), (select count(*) from public.inv_layer_consume) - min(n_consume),
                  (select count(*) from public.inv_adjust) - min(n_adjust), (select count(*) from public.inv_adjust_line) - min(n_adjust_line)) into v_t from t_nb5_pre;
    perform pg_temp.nb5_chk('④ 표 행 수 — 원장 +4 · 레이어 +0 · 소진 +2 · 조정 머리 +2 · 조정 줄 +0(적용 실행만)', v_t = 'ledger +4 · layer +0 · consume +2 · adjust +2 · adjust_line +0', v_t);
  end if;
end $$;

-- ═══ 결과 ═══  기대: 적용 OK 11 · MISMATCH 0 / 확인(-v check=1) OK 10 · MISMATCH 0
\echo '④ 목표 모양(쓴 뒤)'
select sku, pg_temp.nb5_state(sku) as st from t_nb5_plan order by sku;
\echo '═══ 결과 ═══'
select n, case when ok then 'OK ' else 'MISMATCH' end as r, name, case when ok then '' else detail end as detail from t_nb5_res order by n;
do $$
declare v_ok int; v_bad int;
begin
  select count(*) filter (where ok), count(*) filter (where not ok) into v_ok, v_bad from t_nb5_res;
  raise notice 'OK % · MISMATCH %', v_ok, v_bad;
  if v_bad > 0 then
    raise exception using errcode = 'IM178', message = format('%s check(s) failed - everything rolled back. Nothing was changed.', v_bad);
  end if;
end $$;
