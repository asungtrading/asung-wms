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

-- ═══ rcv-3 — 열린 short 가 있으면 입고 확정이 PO 를 열어 둔다 · short 사유가 닫기를 정한다 · PO-02055 다시 열기 (2026-10-21 · 판정 598 ~ 601 · rcv-2 조사 · 정본 po-module 판정 88 ⑥ · 550 ~ 553 뒤) ═══
--   계기: PO-02055 — 1,290 중 240 만 세고 확정 → PO closed · WMS Ready to receive 에서 사라짐 · 남은 1,050 을 받을 길 없음(닫힌 PO 는 새 입고 거부 · 다시 여는 함수 없음 · Settle 은 이름표뿐).
--   판정 598: 열린 short 가 있으면 확정해도 PO 는 confirmed 그대로 · 다음 입고는 「확정 인보이스 goods − 받은 것」을 기대(이미 그 셈 · po_receipt_confirm_by ⓑ) · 마지막 short 가 「안 온다」로 정리되거나 다 받으면 닫힌다.
--   판정 599: short 사유 — split_shipment = 나머지가 이 PO 로 온다(열어 둠) · out_of_stock · lost_damaged · miscount · other = 안 온다(그 PO 에 올 몫이 더 없으면 닫는다) · 되돌리기(po_receipt_diff_reopen)는 닫힌 PO 를 다시 연다.
--   판정 600: 창고 화면 확정은 남긴다 — 확정 전 미리 보기 재료는 도우미 po_receipt_keep_open(p_po_id, p_receipt_id) 가 낸다(초안 입고를 주면 「이대로 확정하면 열린 채 / 닫힘」 · 줄마다 상태).
--   판정 601: PO-02055 를 confirmed · closed_at null 로(열린 short 셋이 근거 · 조건을 단언 · 하나라도 다르면 멈춘다).
--   ⓪ 도우미 po_receipt_keep_open — 닫기 규칙 한 곳: 줄마다 남은 몫 = 확정 인보이스 goods − 받은 것(− 초안 입고에서 센 것) · 남은 몫 > 0 인 줄의 **마지막 short**(최근 입고의 것)가 열렸거나 split_shipment 면 「열어 둔다」 · 초안을 주면 덜 센 줄은 pending(확정하면 short) · 아직 short 가 없는 줄(unsettled)도 「열어 둔다」(안 온다고 아무도 말하지 않았다) · 그 밖(not_coming · done)만 「닫는다」.
--      ⚠️ 앞 입고의 옛 short 는 자동 정리하지 않는다(행은 이력) — 줄의 **마지막** short 만 판정에 쓴다(rcv-3 이견) · off_invoice(더 옴)는 남은 몫 ≤ 0 이라 안 본다 · 인보이스가 적어 a 로 갈린 줄은 남은 몫 0 · 트랜스퍼 입고(po_id null)는 안 만난다.
--   ① po_receipt_confirm_by — ⓒ 닫기를 도우미 판정으로(열린 채면 warnings po_kept_open · 아니면 옛 po_closed 그대로) · 반환 'po' 에 status · kept_open · remaining_ea · outlook · 그 밖의 줄 0.
--   ② po_receipt_diff_resolve — 정리 뒤 도우미가 「닫는다」고 하고 받은 입고가 있으면 PO 를 닫는다(split_shipment 는 「열어 둔다」라 안 닫힌다) · 반환 'po'.
--   ③ po_receipt_diff_reopen — short 를 되돌린 뒤 도우미가 「열어 둔다」면 닫힌 PO 를 confirmed · closed_at null 로 · 반환 'po'.
--   ④ po_receipt_create_by — 닫힌 PO 거부 문장만 지금 규칙으로(옛 「moved to the split document」 는 판정 88 전의 말).
--   보고만(이 차수 밖): 둘째 입고에는 PO 비용(운임 · 관세)이 안 얹힌다(배분 줄 단위로 한 번만 · 판정 553 과 같은 문제) · PO-02040 · PO-02002a 도 closed 인데 열린 short 가 있다(판정 601 은 PO-02055 한 행 — 그 둘은 Caleb 판정 거리).
--   ⚠️ 운영에는 닿지 않는다(가드).

create temp table rcv3_before as
select (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm', 'wms_recv_confirm', 'wms_recv_start', 'po_receipt_create', 'po_receipt_post_now_by', 'po_receipt_detail', 'inv_post_receipt', 'po_receipt_diff_settle_off_invoice', 'po_receipt_diff_settle_over', 'po_doc_cancel', 'wms_recv_complete')) as others,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_diff_resolve', 'po_receipt_diff_reopen', 'po_receipt_create_by')) as acls,
       (select string_agg(x.po_number || ':' || x.status, ',' order by x.po_number) from public.po x where x.po_number <> 'PO-02055') as other_po_status;

-- ═══ ⓪ 도우미 — 「이 PO 에 아직 올 몫이 있나」 한 곳 · 읽기만 · 화면도 부른다(미리 보기 · 판정 600) ═══
create function public.po_receipt_keep_open(p_po_id uuid, p_receipt_id uuid default null) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  with l as (
    select pl.id as po_line_id, pl.line_no, pr.sku,
           coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                      where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
           coalesce((select sum(x.qty_ea) from public.po_receipt_line x where x.po_line_id = pl.id), 0) as received,
           case when p_receipt_id is null then 0 else coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id and w.post_id is null), 0) end as draft_counted,
           (select d.resolution from public.po_receipt_diff d where d.po_line_id = pl.id and d.kind = 'short' order by d.created_at desc, d.id desc limit 1) as last_res,
           (select d.resolved_at is not null from public.po_receipt_diff d where d.po_line_id = pl.id and d.kind = 'short' order by d.created_at desc, d.id desc limit 1) as last_settled
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = p_po_id
  ), s as (
    select l.*, l.invoiced - l.received - l.draft_counted as remaining,
           case when l.invoiced - l.received - l.draft_counted <= 0 then 'done'
                when p_receipt_id is not null and l.draft_counted < l.invoiced - l.received then 'pending'
                when l.last_settled is null then 'unsettled'
                when not l.last_settled then 'open'
                when l.last_res = 'split_shipment' then 'split_shipment'
                else 'not_coming' end as state
    from l
  )
  select jsonb_build_object(
    'keep_open', coalesce(bool_or(s.state in ('open', 'split_shipment', 'pending', 'unsettled')), false),
    'after_confirm', case when coalesce(bool_or(s.state in ('open', 'split_shipment', 'pending', 'unsettled')), false) then 'stays_open' else 'closes' end,
    'remaining_ea', coalesce(sum(s.remaining) filter (where s.remaining > 0 and s.state in ('open', 'split_shipment', 'pending', 'unsettled')), 0),   -- 아직 올 몫만(not_coming 은 뺀다)
    'not_coming_ea', coalesce(sum(s.remaining) filter (where s.remaining > 0 and s.state = 'not_coming'), 0),
    'open_short_lines', count(*) filter (where s.state in ('open', 'pending', 'unsettled')),
    'split_lines', count(*) filter (where s.state = 'split_shipment'),
    'received_any', exists (select 1 from public.po_receipt r where r.po_id = p_po_id and r.status = 'confirmed'),
    'lines', coalesce(jsonb_agg(jsonb_build_object('po_line_id', s.po_line_id, 'line_no', s.line_no, 'sku', s.sku, 'invoiced', s.invoiced, 'received', s.received,
                                                   'draft_counted', s.draft_counted, 'remaining', greatest(s.remaining, 0), 'state', s.state, 'last_short', s.last_res) order by s.line_no), '[]'::jsonb))
  from s
$$;
revoke all on function public.po_receipt_keep_open(uuid, uuid) from public, anon;
grant execute on function public.po_receipt_keep_open(uuid, uuid) to authenticated, service_role;
comment on function public.po_receipt_keep_open(uuid, uuid) is 'rcv-3(판정 598 ~ 600 · 2026-10-21) — 이 PO 에 아직 올 몫이 있나(닫기 규칙 한 곳): 줄마다 남은 몫 = 확정 인보이스 goods − 받은 것(− p_receipt_id 초안에서 센 것) · 남은 몫 > 0 인 줄의 마지막 short 가 열림(open) · split_shipment · 아직 없음(unsettled) · 초안에서 덜 셈(pending) 이면 keep_open · 전부 done · not_coming 이면 닫는다 · 반환 {keep_open, after_confirm stays_open|closes, remaining_ea(아직 올 몫 — open · split_shipment · pending · unsettled 줄의 합), not_coming_ea(안 오는 것으로 정리된 몫), open_short_lines, split_lines, received_any, lines[{line_no, sku, invoiced, received, draft_counted, remaining, state, last_short}]} · 확정(po_receipt_confirm_by) · 정리(po_receipt_diff_resolve) · 되돌리기(po_receipt_diff_reopen) · 화면 미리 보기가 함께 쓴다';

-- ═══ po_receipt_confirm_by 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:430 바이트 + declare 1 줄 + ⓒ 닫기 덩이(도우미 판정 · 열린 채면 po_kept_open · 아니면 옛 닫기 그대로) + 반환 'po' 1 줄 · rcv-3 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_confirm_by(p_staff uuid, p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  v_ledger    jsonb;                                           -- ⓔ 원장 창구의 반환(원장 이식 2차 · 2026-09-19)
  v_cur       text;                                            -- ⑥ 환율 게이트(원가 이식 1차 · 2026-09-19) — 발주 통화 코드
  v_base_cur  text;                                            -- ⑥ 기준통화 코드 · ⚠️ v_base(접미사를 뗀 PO 번호 · 잠금·채번)와 다른 것 — 이름을 같이 쓰면 채번이 CADa 가 된다(2026-09-19 실사고)
  x           record;
  v_ob_n      int;                                             -- inv-basis-3: 초과분이 놓인 칸 수 · 칸 · 놓은 사람 · 문장용
  v_ob_bin    uuid;
  v_ob_by     uuid;
  v_ob_txt    text;
  v_cj        jsonb;                                           -- inv-basis-3 · 판정 94(⑯): 입고 순간 비용 얹기의 반환 · 얹은 것 · 오류
  v_cpost     jsonb := '[]'::jsonb;
  v_cerr      jsonb := '[]'::jsonb;
  v_aj        jsonb;                                           -- po-disc-3 · 판정 391: 보류 원가 조정 얹기의 반환
  v_apost     jsonb := '[]'::jsonb;
  v_aerr      jsonb := '[]'::jsonb;
  v_work_np   int;                                             -- rcv-1b: 먼저 반영 안 된 작업 줄 수(ⓐ 는 이것만 입고 줄로)
  v_pb_n      int := 0;  v_pb_q numeric := 0;  v_pb_r int := 0;   -- rcv-1b: posted_before(묶음 수 · 수량 · 줄 수)
  v_keep      jsonb;                                           -- rcv-3(판정 598 · 599): 「아직 올 몫이 있나」 — po_receipt_keep_open 의 반환
begin
  if p_staff is null then raise exception 'po_receipt_confirm_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — it is confirmed by the warehouse Complete, not here — nothing was saved', v_r.receipt_number; end if;   -- tr-3a 판정 70(트랜스퍼를 막는 한 줄만)
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  -- inv-basis-2 · 판정 88 ③ · 92 — 확정 인보이스가 없는 PO 는 받지 않는다(입고 문에서 이미 막지만, 옛 초안 · 직접 호출도 여기서 한 번 더)
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then the receipt can be confirmed — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- rcv-1b(판정 550): 먼저 반영된 작업 줄 · 묶음 — ⓐ 는 반영 안 된 줄만 입고 줄로(전량 반영이면 0 줄) · ⓑ counted 는 전부(short · off_invoice 는 합으로 한 번)
  select count(*), coalesce(sum(w.qty_ea), 0) into v_pb_r, v_pb_q from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.post_id is not null;
  select count(*) into v_pb_n from public.po_receipt_post p where p.receipt_id = p_receipt_id;
  v_work_np := v_work_n - v_pb_r;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 발주인데 환율이 없거나 0 이면 **확정 자체를 거부**한다(Caleb 2026-09-19 · 원가가 조용히 틀리는 것보다 낫다 · 정본 「0 금지」).
  --   기준통화는 inv_config.base_currency(박지 않는다) · 발주 통화는 po.currency_id → ref_currency.code.
  --   ⚠️ po.exchange_rate 는 **CAD per USD** 다(Cin7 「CAD units per USD」 · 화면 칸 「CAD per USD」) — unit_price × exchange_rate = CAD. 곱한다 · 나누지 않는다.
  --   문장이 어디서 고치는지 말한다 — 발주 머리의 「Exchange rate (CAD per USD)」 칸 · 확정 뒤에도 열려 있다(po.html HEAD_ALWAYS).
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and confirm again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id and w.post_id is null                                       -- rcv-1b: 먼저 반영된 줄은 묶음이 이미 입고 줄(post_id)로 만들었다
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_np then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_np, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 — over · short · 안 센 라인은 short(received 0) · ⭐ inv-basis-2 · 판정 88 ② · 93 ⓑ: 기준 = 확정 인보이스 goods 합(크레딧 · 초안 제외) − 앞선 입고 합(PO 수량이 아니다) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                      where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0)
             - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id and w.post_id is not null), 0) as posted   -- rcv-1b
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.posted > x.counted then                                                                 -- rcv-1b(④ 안전띠 — 가드 ⑤ 가 먼저 막아 보통 오지 않는다)
      raise exception 'Line % (%) on %: % EA are already in stock from post-now, but only % are counted — fix it with a stock adjustment (Adjustments), then confirm — nothing was saved', x.line_no, x.sku, v_r.receipt_number, x.posted, x.counted;
    end if;
    if x.counted > x.expected then
      -- ⭐ inv-basis-3 · 판정 88 ⑧ · 93 ⓓ: 더 온 것(인보이스 초과 · 인보이스에 없는 줄)은 off_invoice 한 행 — 창고가 놓은 칸을 행에 남긴다(판정 43 · 어느 칸에 얼마).
      --   초과분이 놓인 칸 = 원장 창구 inv_post_receipt 와 같은 자르기(큰 칸부터 · 칸 이름 · 상한 = 기준)로 정한다 · 두 칸에 걸치면 막는다(판정 92 · off-PO 와 같이 한 물건 한 칸 · 나눠 놓기 없음).
      select b.bins, b.bin_id, b.placed_by, b.bins_txt into v_ob_n, v_ob_bin, v_ob_by, v_ob_txt
        from public.po_receipt_over_bins(p_receipt_id, x.po_line_id, x.expected) b;   -- 판정 100: 자르기 식은 속 함수 한 곳 — 창고 Complete 가 먼저 막고 여기는 안전띠(칸 0 = 칸 없는 줄은 위 ② 가 먼저 막는다)
      if coalesce(v_ob_n, 0) <> 1 then
        raise exception 'Line % (%) on %: % EA more than the confirmed invoice (% counted · % invoiced) sit in more than one bin (%) — move the extra into one bin, or lower the count, so the office can decide it as one off-invoice item — nothing was saved',
          x.line_no, x.sku, v_r.receipt_number, x.counted - greatest(x.expected, 0), x.counted, greatest(x.expected, 0), coalesce(v_ob_txt, '?');
      end if;
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, bin_id, placed_by, placed_at, updated_by)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'off_invoice', greatest(x.expected, 0), x.counted,
              'off-invoice (receipt confirm) — more than the confirmed invoice · decision pending', v_ob_bin, coalesce(v_ob_by, v_staff), v_now, v_staff);
      v_over := v_over + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'off_invoice', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    elsif x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'short', greatest(x.expected, 0), x.counted);
      v_short := v_short + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'short', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 닫기 — inv-basis-2 · 판정 88 ⑤ ⑥: 입고 확정은 더 이상 가르지 않는다(가르는 자리는 인보이스 확정 · po_invoice_confirm) · 덜 받은 몫은 short 차이로 남고 크레딧은 오피스 단추 · PO 는 닫힌다(입고 종료 · §11-b) ═══
  v_a_num := v_po.po_number;
  v_keep := public.po_receipt_keep_open(v_po.id, null);                                       -- rcv-3(판정 598 · 599): 열린 short(이 확정이 방금 남긴 것 포함) · split_shipment 가 있으면 PO 는 열린 채 — 다음 입고가 「확정 인보이스 − 받은 것」을 기대한다
  if (v_keep->>'keep_open')::boolean then
    select count(*) into v_n from public.po where id = v_po.id and status = 'confirmed';
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_kept_open');
  else
  update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
  v_warn := array_append(v_warn, 'po_closed');
  end if;
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); v_warn := array_append(v_warn, 'off_invoice'); end if;   -- inv-basis-3: 옛 경고 이름은 모양 무변 · 새 어휘도 함께
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  -- ═══ ⓔ 원장 — 창구를 부른다 (원장 이식 2차 · 2026-09-19 · ⬜1) ═══
  -- ⭐ 같은 트랜잭션 — 원장이 실패하면 확정도 실패한다(재고에 안 잡힐 거면 확정도 하면 안 된다). inv_ledger 에 직접 쓰지 않는다(원칙 2 · §11-j).
  -- ⭐ 자리가 ⓓ 뒤인 이유 셋: ① 창구는 「확정된 입고」만 받는다(status=confirmed 를 스스로 확인 — 직접 호출로 초안이 장부에 닿는 길을 막는다)
  --   ② raw 의 po_number 는 갈라진 뒤의 번호여야 한다(§11-j) — ⓒ 가 끝나야 안다 ③ 기준은 po_line.qty_ea 가 아니라 ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 에서
  --   읽으므로(§2 의 함정 — ⓒ 가 qty_ea 를 줄인다) ⓒ 뒤라도 어긋나지 않는다. 기준을 「미리 잡아 두는」 그릇이 그 표다.
  v_ledger := public.inv_post_receipt(p_receipt_id);
  if coalesce((v_ledger->>'qty_excess')::numeric, 0) > 0 then v_warn := array_append(v_warn, 'ledger_trimmed_to_basis'); end if;
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;

  -- ═══ ⓕ inv-basis-3 · 판정 94(⑯): 입고 전에 확정해 둔 이 발주의 비용은 지금 원가에 얹는다 — 배분 줄 단위 멱등(창구가 건너뛴다) · 오류는 경고로 모아 돌려준다(확정을 막지 않는다 · tf_arrive 판정 78 모양) ═══
  for x in select distinct c.id, c.charge_number from public.po_charge c join public.po_charge_alloc a on a.po_charge_id = c.id
            where a.po_id = v_po.id and c.status = 'confirmed' and c.confirmed_at is not null
              and not exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text)
            order by c.charge_number loop
    begin
      v_cj := public.inv_layer_post_charge(x.id);
      v_cpost := v_cpost || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'layers_touched', v_cj -> 'layers_touched', 'amount_posted_cad', v_cj -> 'amount_posted_cad', 'warnings', v_cj -> 'warnings');
    exception when others then
      v_cerr := v_cerr || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_cerr) > 0 then v_warn := array_append(v_warn, 'charge_errors'); end if;

  -- ═══ ⓖ po-disc-3 · 판정 391: 레이어가 없어 보류됐던 원가 조정(이 PO 의 줄 · 이 PO 의 비용 배분 줄)을 지금 얹는다 — ⓕ 비용 뒤(둘 다 금액만 얹어 총액은 순서와 무관 · 재생성 쏟기도 비용 뒤) · 오류는 경고로(확정을 막지 않는다) ═══
  for x in select j.id, j.source_number from public.inv_cost_adjust j
            where j.status = 'pending'
              and ((j.target_type = 'po_line' and exists (select 1 from public.po_line pl where pl.id = j.po_line_id and pl.po_id = v_po.id))
                or (j.target_type = 'charge_alloc' and exists (select 1 from public.po_charge_alloc a where a.id = j.po_charge_alloc_id and a.po_id = v_po.id)))
            order by j.created_at, j.source_number, j.reverses_id nulls first, j.id loop                       -- 원래 사건 뒤에 그 되돌림(같은 트랜잭션은 created_at 이 같다)
    begin
      v_aj := public.inv_layer_post_cost_adjust(x.id);
      v_apost := v_apost || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'status', v_aj ->> 'status', 'posted_cad', v_aj -> 'posted_cad', 'layers', v_aj -> 'layers');
    exception when others then
      v_aerr := v_aerr || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_aerr) > 0 then v_warn := array_append(v_warn, 'adjust_errors'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'posted_before', jsonb_build_object('batches', v_pb_n, 'qty', v_pb_q, 'rows', v_pb_r),   -- rcv-1b: 먼저 반영된 묶음 · 수량 · 줄
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', case when (v_keep->>'keep_open')::boolean then 'confirmed' else 'closed' end, 'closed_at', case when (v_keep->>'keep_open')::boolean then null else v_now end,
                              'kept_open', (v_keep->>'keep_open')::boolean, 'remaining_ea', v_keep->'remaining_ea', 'outlook', v_keep->'lines'),   -- rcv-3: 열린 채 남았나 · 남은 EA · 줄마다 상태
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'charges', jsonb_build_object('posted', v_cpost, 'errors', v_cerr),   -- inv-basis-3 · 판정 94(⑯): 이 발주의 확정 비용을 입고 순간 얹은 결과
    'adjustments', jsonb_build_object('posted', v_apost, 'errors', v_aerr),   -- po-disc-3 · 판정 391: 보류 원가 조정을 입고 순간 얹은 결과
    'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ po_receipt_diff_resolve 재발행 — 원본 20260928025627_wms_5_6c1_off_po_decide_ledger.sql:487 바이트 + declare 1 줄 + 정리 뒤 닫기 덩이 + 반환 'po' 1 줄 · rcv-3 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_diff_resolve(p_diff_id uuid, p_resolution text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_line_no int;
  v_fam     jsonb;
  v_keep    jsonb;  v_po_closed boolean := false;                                                        -- rcv-3(판정 598 · 599)
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  if p_resolution is null or p_resolution not in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other') then
    raise exception 'Reason "%" is not one of split_shipment, out_of_stock, lost_damaged, miscount, other — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');
  if p_resolution = 'other' and v_note is null then
    raise exception 'Reason "other" needs a note saying what actually happened — nothing was saved';
  end if;

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 차이를 두 사람이 동시에 닫지 않게
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;

  -- ① short 만 — over 는 재고를 움직이는 일이라 형제 함수 po_receipt_diff_settle_over 가 닫는다(2026-09-20 · 이유 free·billed·credited · 원장·레이어에 넣는다)
  if v_d.kind <> 'short' then
    raise exception 'Line % (%) on % is an "%" difference — only short differences are settled here. An over difference puts the extra into stock: settle it with po_receipt_diff_settle_over (reason free · billed · credited); an off-PO item is decided with po_receipt_diff_settle_off_po — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  -- ② 이미 닫힘 — 누가 무엇으로 언제 · 빠져나갈 길(reopen)을 문장에
  if v_d.resolved_at is not null then
    raise exception 'Line % (%) on % was already settled as "%" by % on % — reopen it first if that was wrong — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),                    -- 별칭 s — ims_staff 자기 칸과 헷갈리지 않게
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, resolved_by = v_staff, resolved_at = v_now
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line % on % was not saved — it may have been settled by someone else just now — nothing was saved', coalesce(v_line_no::text, '?'), v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  -- rcv-3(판정 598 · 599): 「안 온다」(split_shipment 말고)로 정리한 뒤 이 PO 에 아직 올 몫이 없으면 PO 를 닫는다 · split_shipment 는 닫지 않는다 · 받은 입고가 있는 confirmed PO 만
  if v_d.po_id is not null then
    v_keep := public.po_receipt_keep_open(v_d.po_id, null);
    if not (v_keep->>'keep_open')::boolean and (v_keep->>'received_any')::boolean then
      update public.po set status = 'closed', closed_at = v_now where id = v_d.po_id and status = 'confirmed';
      get diagnostics v_n = row_count;  v_po_closed := v_n = 1;
    end if;
  end if;
  select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members)
    into v_fam
  from public.po_family_lines(v_d.po_id) f where f.product_id = v_d.product_id;

  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number,
    'kind', v_d.kind, 'sku', v_sku, 'line_no', v_line_no, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
    'resolution', p_resolution, 'resolution_note', v_note, 'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'family', v_fam,
    'open_diffs_left', v_open,
    'po', jsonb_build_object('id', v_d.po_id, 'closed_now', v_po_closed, 'kept_open', coalesce((v_keep->>'keep_open')::boolean, false), 'remaining_ea', v_keep->'remaining_ea', 'outlook', v_keep->'lines'));   -- rcv-3
end;
$function$;

-- ═══ po_receipt_diff_reopen 재발행 — 원본 20260929195458_inv_basis_2.sql:1050 바이트 + declare 1 줄 + 되돌린 뒤 다시 열기 덩이 + 반환 'po' 1 줄 · rcv-3 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_diff_reopen(p_diff_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;
  v_d     public.po_receipt_diff%rowtype;
  v_r     public.po_receipt%rowtype;
  v_n     int;
  v_open  int;
  v_note  text;
  v_keep  jsonb;  v_po_reopened boolean := false;                                                           -- rcv-3(판정 599)
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if v_d.resolved_at is null then
    raise exception 'This difference on % is not settled — there is nothing to reopen — nothing was saved', v_r.receipt_number;
  end if;
  -- ⭐ 2026-09-20 over 닫기 — over 는 닫히는 순간 초과분이 원장·레이어에 들어갔다(재고가 움직였다). 세 칸만 비우면 재고는 남고 기록만 사라진다.
  --   원장은 append-only 라 되돌리려면 반대 사건(상쇄)을 남기는 별도 길이 필요하다 — 아직 없다. 그래서 거부하고 무엇을 해야 하는지 말한다.
  if v_d.kind = 'over' then
    raise exception 'Line on % was settled as "%" and the extra % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty - v_d.expected_qty;
  end if;
  -- ⑤-6c1 off-PO — accepted(free · billed)는 받는 순간 원장 · 레이어에 들어갔다(일곱 묶음 6 · 받은 뒤 되돌리기 없음) · 옛 off_po 의 rejected 는 장부에 아무것도 없어 되돌릴 수 있다 · 판정 99: off_invoice 는 결정이 둘 다 받는 것이라 되돌릴 길이 없다
  if v_d.kind in ('off_po', 'off_invoice') and v_d.resolution like 'accepted%' then   -- inv-basis-3: off_invoice 도 받은 뒤 되돌리기 없음(판정 99 뒤 off_invoice 는 이 갈래뿐)
    raise exception 'Off-PO item on % was accepted as "%" and % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty - v_d.expected_qty;   -- inv-basis-3: 장부에 든 수량 = 초과분(off_po 는 expected 0)
  end if;
  if v_d.kind = 'off_po' and v_d.resolution = 'rejected' and v_d.removed_at is not null then   -- inv-basis-3 · 판정 92: 선반에서 뺀 뒤에는 되돌리지 않는다(CHECK removed_ck 의 날것 오류 대신 문장) · 판정 99: 옛 off_po 만(off_invoice 는 거절이 없다)
    raise exception 'Off-PO item on % was rejected and already taken off the shelf on % — it cannot be reopened; if it is back, the warehouse scans it again as a new item — nothing was saved',
      v_r.receipt_number, to_char(v_d.removed_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;

  v_note := nullif(btrim(p_note), '');
  update public.po_receipt_diff
     set resolution = null, resolved_by = null, resolved_at = null,
         resolution_note = case when v_note is null then resolution_note
                                else 'reopened: ' || v_note || coalesce(' | was: ' || resolution || coalesce(' — ' || resolution_note, ''), '') end
   where id = p_diff_id and resolved_at is not null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Difference on % was not saved — it may have been reopened by someone else just now — nothing was saved', v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  -- rcv-3(판정 599): 되돌려서 「아직 올 몫」이 다시 생겼으면 닫힌 PO 를 다시 연다(confirmed · closed_at 비움) — WMS Ready to receive 에 다시 뜬다
  if v_d.po_id is not null and v_d.kind = 'short' then
    v_keep := public.po_receipt_keep_open(v_d.po_id, null);
    if (v_keep->>'keep_open')::boolean then
      update public.po set status = 'confirmed', closed_at = null where id = v_d.po_id and status = 'closed';
      get diagnostics v_n = row_count;  v_po_reopened := v_n = 1;
    end if;
  end if;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'kind', v_d.kind,
                            'was_resolution', v_d.resolution, 'was_resolved_by', v_d.resolved_by, 'was_resolved_at', v_d.resolved_at,
                            'reopened_by', v_staff, 'open_diffs_left', v_open,
                            'po', jsonb_build_object('id', v_d.po_id, 'reopened_now', v_po_reopened, 'kept_open', coalesce((v_keep->>'keep_open')::boolean, false), 'remaining_ea', v_keep->'remaining_ea', 'outlook', v_keep->'lines'));   -- rcv-3
end;
$function$;

-- ═══ po_receipt_create_by 재발행 — 원본 20260929190928_inv_basis_1.sql:447 바이트 + 거부 문장 1 줄(닫힌 PO 의 뜻을 지금 규칙으로) · rcv-3 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_create_by(p_staff uuid, p_po_id uuid, p_received_on date DEFAULT ims_today(), p_warehouse_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  v_po     public.po%rowtype;
  v_open   text;
  v_wh     uuid;
  v_whn    text;
  v_r      public.po_receipt%rowtype;
  v_warn   text[] := '{}';
begin
  if p_staff is null then raise exception 'po_receipt_create_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  -- 만든 사람 — 서버 유도(po_create 선례 · 화면이 주지 않는다)

  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  -- ⬜3 confirmed 만 — draft(공급처에 안 갔다) · closed(입고 종료 · 남은 수량은 갈라진 문서로) · cancelled(안 온다)
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — receiving can start only on a confirmed order% — nothing was saved',
      v_po.po_number, v_po.status,
      case v_po.status when 'closed' then ' (receiving is finished on this order — everything invoiced was received, or what did not arrive was settled as not coming; if more is still coming, reopen that short difference in Purchase Receipts and the order opens again)'   -- rcv-3(판정 598 · 599): 옛 「split document」 문장은 판정 88 전의 말
                       when 'draft'  then ' (confirm it first)'
                       else '' end;
  end if;
  -- inv-basis-2 · 판정 88 ③ · 92 — 확정 인보이스가 붙은 PO 만 받는다(오피스 New receipt · 창고 wms_recv_start 둘 다 여기를 지난다)
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then receiving can start — nothing was saved', v_po.po_number;
  end if;
  -- ⭐⭐ PO 당 draft 하나 — 부분 유니크 대신 여기서(규칙 29) · 기존 번호를 문장에
  perform pg_advisory_xact_lock(hashtext('po_receipt:' || p_po_id::text));           -- 이견 12 — 둘이 동시에 열면 뒤 것이 앞 것을 본다(권한 불필요 · 트랜잭션 끝에 풀림)
  select r.receipt_number into v_open from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if v_open is not null then
    raise exception 'PO % already has an open receipt (%) — continue that one or delete it first — nothing was saved', v_po.po_number, v_open;
  end if;
  -- 창고 — PO 의 배송지 · 없으면 인자 · 그것도 없으면 거부(빈은 창고의 것 · ims_last_bin 의 축)
  v_wh := coalesce(v_po.ship_to_warehouse_id, p_warehouse_id);
  if v_wh is null then
    raise exception 'PO % has no ship-to warehouse — pass p_warehouse_id — nothing was saved', v_po.po_number;
  end if;
  if v_po.ship_to_warehouse_id is null then v_warn := array_append(v_warn, 'warehouse_from_parameter'); end if;
  select w.name into v_whn from public.ref_warehouse w where w.id = v_wh and w.is_active;
  if v_whn is null then raise exception 'Warehouse % not found or inactive — nothing was saved', v_wh; end if;
  if p_received_on is not null and p_received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  insert into public.po_receipt (po_id, warehouse_id, received_on, status, created_by)
  values (p_po_id, v_wh, coalesce(p_received_on, public.ims_today()), 'draft', v_staff)
  returning * into v_r;

  return jsonb_build_object(
    'id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status,
    'po_id', v_po.id, 'po_number', v_po.po_number,
    'warehouse_id', v_wh, 'warehouse_name', v_whn, 'received_on', v_r.received_on,
    'created_by', v_staff, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ ⑤ 데이터 — PO-02055 다시 열기(판정 601) · 조건을 단언 · 하나라도 다르면 멈춘다 ═══
do $$
declare v_po public.po%rowtype; v_n int; v_keep jsonb;
begin
  select * into v_po from public.po where po_number = 'PO-02055';
  if v_po.id is null then raise exception 'rcv-3 (판정 601): PO-02055 not found — nothing was changed'; end if;
  if v_po.status <> 'closed' or v_po.closed_at is null then raise exception 'rcv-3 (판정 601): PO-02055 is % (closed_at %) — expected closed — nothing was changed', v_po.status, v_po.closed_at; end if;
  select count(*) into v_n from public.po_receipt_diff d where d.po_id = v_po.id and d.kind = 'short' and d.resolved_at is null;
  if v_n <> 3 then raise exception 'rcv-3 (판정 601): PO-02055 has % open short differences — expected 3 — nothing was changed', v_n; end if;
  select count(*) into v_n from public.po_receipt_diff d where d.po_id = v_po.id and d.kind <> 'short';
  if v_n <> 0 then raise exception 'rcv-3 (판정 601): PO-02055 has % non-short differences — look first — nothing was changed', v_n; end if;
  select count(*) into v_n from public.po_invoice i where i.invoice_number = '71034' and i.status = 'confirmed' and i.doc_kind = 'invoice'
     and exists (select 1 from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id where il.po_invoice_id = i.id and pl.po_id = v_po.id);
  if v_n <> 1 then raise exception 'rcv-3 (판정 601): invoice 71034 confirmed on PO-02055 not found — nothing was changed'; end if;
  select count(*) into v_n from public.po_receipt r where r.po_id = v_po.id;
  if v_n <> 1 or not exists (select 1 from public.po_receipt r where r.po_id = v_po.id and r.receipt_number = 'RCV-00046' and r.status = 'confirmed') then
    raise exception 'rcv-3 (판정 601): PO-02055 should have exactly one receipt RCV-00046 confirmed (found %) — nothing was changed', v_n; end if;
  v_keep := public.po_receipt_keep_open(v_po.id, null);
  if not (v_keep->>'keep_open')::boolean or (v_keep->>'remaining_ea')::numeric <> 1050 then
    raise exception 'rcv-3 (판정 601): the rule says % for PO-02055 (remaining %) — expected keep_open · 1050 — nothing was changed', v_keep->>'after_confirm', v_keep->>'remaining_ea'; end if;
  update public.po set status = 'confirmed', closed_at = null where id = v_po.id and status = 'closed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'rcv-3 (판정 601): PO-02055 was not reopened — nothing was changed'; end if;
end $$;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_b record; v_keep jsonb;
begin
  select * into v_b from rcv3_before;
  if to_regprocedure('public.po_receipt_keep_open(uuid, uuid)') is null or not has_function_privilege('authenticated', 'public.po_receipt_keep_open(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.po_receipt_keep_open(uuid, uuid)', 'execute') then v_bad := v_bad || ' helper'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and (
       (p.proname = 'po_receipt_confirm_by'   and md5(p.prosrc) = 'd2734ecd59053597f3c91cf4c6b52b4f')
    or (p.proname = 'po_receipt_diff_resolve' and md5(p.prosrc) = 'c61d6023c9b9af89a2d98338091790f2')
    or (p.proname = 'po_receipt_diff_reopen'  and md5(p.prosrc) = '542302d7c49f4dec8a41dd15855d27b5')
    or (p.proname = 'po_receipt_create_by'    and md5(p.prosrc) = '7cb0f24fcdc72792b487cc822782bca5'));
  if v_n <> 4 then v_bad := v_bad || format(' reissued_bodies_%s_of_4', v_n); end if;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_diff_resolve', 'po_receipt_diff_reopen', 'po_receipt_create_by')) is distinct from v_b.acls then v_bad := v_bad || ' acls_changed'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_diff_resolve', 'po_receipt_diff_reopen', 'po_receipt_create_by')) <> 4 then v_bad := v_bad || ' overloads'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm', 'wms_recv_confirm', 'wms_recv_start', 'po_receipt_create', 'po_receipt_post_now_by', 'po_receipt_detail', 'inv_post_receipt', 'po_receipt_diff_settle_off_invoice', 'po_receipt_diff_settle_over', 'po_doc_cancel', 'wms_recv_complete')) is distinct from v_b.others then v_bad := v_bad || ' other_receipt_functions_changed'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_confirm_by' and p.prosrc ~ 'is a transfer arrival' and p.prosrc ~ 'po_kept_open' and p.prosrc ~ 'po_closed') <> 1 then v_bad := v_bad || ' confirm_by_text'; end if;
  select status, closed_at into v_b from public.po where po_number = 'PO-02055';
  if v_b.status <> 'confirmed' or v_b.closed_at is not null then v_bad := v_bad || ' po_02055_not_reopened'; end if;
  if (select string_agg(x.po_number || ':' || x.status, ',' order by x.po_number) from public.po x where x.po_number <> 'PO-02055') is distinct from (select r.other_po_status from rcv3_before r) then v_bad := v_bad || ' other_po_status_changed'; end if;
  if v_bad <> '' then raise exception 'rcv-3 landing check failed:%', v_bad; end if;
end $$;
drop table rcv3_before;
