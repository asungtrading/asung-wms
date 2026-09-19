-- ─────────────────────────────────────────────────────────────
-- 원장 이식 2차 — 입고가 원장에 닿는다 (Asung-IMS · 2026-09-19)
--   ① inv_post_receipt(uuid)      ⭐⭐ 원장의 창구 — 확정된 입고 하나를 읽어 po_in 사건을 기표한다(초과는 기준까지만 · raw 에 전부)
--   ② po_receipt_confirm(uuid)    다시 냄(시그니처 무변 · create or replace) — ⓓ 뒤에 ⓔ 창구 호출 한 줄 + 반환 'ledger' · 그 밖은 20260918203805 원문 그대로
--   ③ po_receipt_list             다시 냄 — 맨 뒤에 open_diffs 한 칸(열린 차이 수) · 기존 24칸 이름·순서 무변
--
-- 앞 차수: 20260919151601(원장 이식 1차 · 'ims' 자리 · ims_inv_balance · ims_last_bin) · 20260918203805(확정 · 이 파일이 그 함수를 다시 낸다).
-- 정본: ledger-design §1부 「발주 입고」·「⭐ 미달·초과 입고의 실무 흐름」 · §2부 「테이블 다섯 개」·「순서를 어떻게 보장하나」 · po-module §11-i(초과는 기준까지만) · §11-j(사건) · ims-principles 원칙 2
-- 지시서: ~/asung/prompts/ims-ledger-graft-2.md · ⬜1~9 는 회신에
--
-- ⭐⭐ 이견 1 — 기준(basis)은 po_line.qty_ea 에서 읽지 않는다. ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 를 읽는다 — **over·short 둘 다**(차이 행이 있는 라인은 전부).
--   [검증 ⑤ 실측 2026-09-19] 처음엔 over 만 읽고 short 는 센 것을 기준으로 적어, 12 시켜 10 받은 라인의 raw.basis 가 10 으로 남았다(분할이 qty_ea 를 10 으로 줄인 뒤라 되캘 길도 없다). 숫자(posted)는 맞았고 기록만 틀렸다.
--   ⇒ 기록용 basis(차이 행 있으면 expected_qty · 없으면 센 것)와 깎기용 상한 cap(over 면 expected_qty · 아니면 센 것 = 깎을 것 없음)을 **갈랐다**. posted 식은 cap 을 쓰고 그대로다.
--   §2 의 함정(ⓒ 가 qty_ea 를 줄인다)이 시점 문제가 아니라 **읽는 곳** 문제로 바뀐다 — 언제 부르든 같은 값. 차이 행이 없는 라인은 센 것 = 기준(자를 것이 없다).
-- ⭐⭐ 이견 2 — 한 라인이 여러 빈으로 갈렸는데 기준을 넘으면 **수량 큰 빈부터 채우고(동률은 빈 이름) 기준이 바닥나는 줄에서 자른다.** 회신 ⬜2 에 근거.
-- ⭐ 이견 3 — 창구는 security **invoker** 다. inv_ledger 정책은 auth_all(with check true) · authenticated 에 insert 가 열려 있고(20260816000000 · update/delete 만 회수) 읽는 표는 전부 select 열림 — definer 가 필요한 표가 없다.
--   confirm(definer) 안에서 불리면 그 문맥으로 돈다. 첫머리에서 ims_require_write('receiving') 을 묻는다(직접 호출도 같은 관문).
-- ⭐ 이견 4 — 창구는 **확정된 입고만** 받는다(status=confirmed · confirmed_at not null). 그래서 confirm 은 ⓓ(묶음 confirmed) **뒤**에 부른다 — 초안이 직접 호출로 장부에 닿는 길이 막히고, raw 의 po_number 가 갈라진 뒤 번호(§11-j)가 된다.
-- ⭐ 이견 5 → [Caleb 실측 확정 2026-09-19] line_ref = **po_line_id**(라인 id). Cin7 발주 행도 라인 id(CardID · TDX70301 이 세 PO 에서 line_ref 셋 다 다름 · 정본 §1부 line_ref 표)다 — 지시서의 「ProductID 888행」은 틀린 것이었다.
--   같은 PO 에 같은 제품이 두 라인이어도 라인마다 line_ref 가 다르니 유니크 7키가 겹치지 않는다 ⇒ 키 충돌 거부 분기는 없다. raw·반환의 po_line_id 와 같은 값이다.
-- ⚠️ amount 는 null — 수량 원장이다. 단가·통화·환율은 raw 에 남긴다(원가 차수가 읽는다 · 회신 ⬜9).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① inv_post_receipt(p_receipt_id) — ⭐⭐ 원장의 창구 ═══
-- 이름: inv_ 접두어 = 원장 소유(inv_ledger · inv_balance · inv_compare_run 과 같은 결) · post = 기표(장부에 적는다 · ingest 는 Cin7 수집기의 말이다) · receipt = 받는 사건의 종류.
--   SO·조정·트랜스퍼가 서면 inv_post_<사건> 이 하나씩 선다 — 장부를 어떻게 적을지는 원장이 정하고 부르는 쪽은 id 하나만 넘긴다.
-- 하는 일:
--   1. 관문 — ims_require_write('receiving') · 입고가 있고 **confirmed** 인가 (아니면 거부 · 초안은 장부에 닿지 않는다)
--   2. 멱등 — 이 입고 번호(doc_type='purchase' · doc_number=RCV · source='ims')의 행이 이미 있으면 **아무것도 쓰지 않고** already_posted=true 로 돌아간다(⬜5).
--   3. 기준 — 라인마다 둘: basis(기록 · raw.line.basis) = 차이 행(over·short)이 있으면 expected_qty(⭐ ⓑ 가 얼린 값 · 이견 1) · 없으면(딱 맞게 받음) 센 것 = 기준.
--      cap(깎기 상한) = over 면 expected_qty · 아니면 센 것(short·딱 맞음은 깎을 것이 없다). ⚠️ posted 는 cap 으로만 계산한다.
--   4. 배분(⬜2) — 그 라인의 입고 줄을 qty_ea desc, bin 이름, id 순으로 세워 기준을 채운다. 줄의 posted = least(qty, greatest(기준 − 앞 줄들의 합, 0)). 0 이 되는 줄은 행을 만들지 않는다(raw 의 bins[] 에는 남는다).
--   5. 기표 — 줄마다 inv_ledger 한 행: occurred_on=po_receipt.received_on · seq_hint 1 · sku=product.sku · warehouse=ref_warehouse.name · bin=ref_bin.name · qty_delta=posted · event_type po_in · doc_type purchase ·
--      doc_number=receipt_number(⚠️ PO 번호가 아니다 — 유니크 키에 doc_task_id 가 없어 같은 PO 의 같은 제품·같은 빈 재입고가 겹친다) · doc_task_id=po_receipt.id · line_ref=po_line_id(라인 id · raw.po_line_id 와 같은 값) · amount null · source 'ims' · raw(아래).
--   6. 경고 — received_on 이 기초선(inv_config.baseline_snapshot_key 스냅샷의 토론토 날짜)보다 이르면 'received_on_before_baseline' · 오늘보다 늦으면 'received_on_in_future'. 막지 않는다(⬜7).
-- raw(⬜4) — 한 행에서 라인 전체를 캐낼 수 있게: kind · poster(버전) · receipt_id/number · receipt_line_id · po_id · po_number(갈라진 뒤) · po_line_id · line_no · product_id · sku · warehouse_id/warehouse · bin_id/bin ·
--   received_on · received_by · confirmed_by/at · line{counted, basis, posted, excess, diff_kind} · this_bin{counted, posted, trimmed} · bins[{bin, counted, posted, trimmed}](라인 전체의 배분 · 0 으로 깎인 줄도 여기 있다) ·
--   trim_rule · unit_price · currency_id · exchange_rate · note.
-- 반환: { receipt_id, receipt_number, po_number, already_posted, existing_rows, rows_posted, qty_counted, qty_posted, qty_excess, lines[{po_line_id, line_no, sku, counted, basis, posted, excess, diff_kind, bins[]}], warnings[] }
-- ⚠️ 원장은 append-only — 이 함수는 insert 만 한다. 잘못 넣었으면 상쇄(source manual)로 고친다. 유니크 충돌(정상 흐름에서는 나지 않는다 — 멱등 분기가 앞에 있다)은 읽을 수 있는 문장으로 바꿔 던진다.
create function public.inv_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker                                              -- 이견 3 — definer 가 필요한 표가 없다
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_post_receipt@2026-09-19.1';   -- raw.poster 에 박는다 — 배분 규칙이 바뀌면 올릴 것
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_wh        text;
  v_existing  int;
  v_baseline  date;
  v_alloc     jsonb;
  v_lines     jsonb;
  v_rows      int := 0;
  v_counted   numeric := 0;
  v_posted    numeric := 0;
  v_excess    numeric := 0;
  v_warn      text[] := '{}';
  b           record;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was posted to the ledger', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;

  -- 2. 멱등 — 이미 기표된 입고는 다시 쓰지 않는다(터지지 않고 말한다 · ⬜5)
  select count(*) into v_existing
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0,
                              'qty_counted', null, 'qty_posted', null, 'qty_excess', null, 'lines', '[]'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 6. 날짜 경고 — 기초선보다 이르면 · 미래면 (막지 않는다 · ⬜7)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s
  where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and v_r.received_on < v_baseline then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if v_r.received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- 3·4. 기준과 배분 — 한 번의 SQL 로 계산해 jsonb 배열에 담는다(그 뒤 루프는 넣고 더하기만 한다)
  with ln as (
    select l.po_line_id, sum(l.qty_ea) as counted, d.kind as diff_kind,
           case when d.kind is not null then d.expected_qty else sum(l.qty_ea) end as basis,     -- ⭐ 이견 1 — 기록용 기준: 차이 행(over·short)이 있으면 ⓑ 가 얼린 값 · 없으면 센 것
           case when d.kind = 'over'    then d.expected_qty else sum(l.qty_ea) end as cap        -- 깎기 상한: over 만 자른다 · posted 는 이것만 본다(검증 ⑤ 정정 — basis 와 갈랐다)
    from public.po_receipt_line l
    left join public.po_receipt_diff d on d.receipt_id = l.receipt_id and d.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
    group by l.po_line_id, d.kind, d.expected_qty
  ),
  alloc as (
    select l.id as receipt_line_id, l.po_line_id, l.bin_id, rb.name as bin, l.qty_ea, l.received_by, l.note,
           pl.line_no, pl.product_id, pl.unit_price, pr.sku,
           ln.counted, ln.basis, ln.cap, ln.diff_kind,
           least(l.qty_ea, greatest(ln.cap - coalesce(sum(l.qty_ea) over (partition by l.po_line_id order by l.qty_ea desc, rb.name, l.id
                                                                                  rows between unbounded preceding and 1 preceding), 0), 0)) as posted   -- ⭐ ⬜2 — 큰 빈부터 채우고 바닥나는 줄에서 자른다
    from public.po_receipt_line l
    join public.ref_bin  rb on rb.id = l.bin_id
    join public.po_line  pl on pl.id = l.po_line_id
    join public.product  pr on pr.id = pl.product_id
    join ln on ln.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.qty_ea desc, a.bin, a.receipt_line_id), '[]'::jsonb) into v_alloc from alloc a;

  -- 5. 기표 — posted > 0 인 줄만 행이 된다
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(
      receipt_line_id uuid, po_line_id uuid, bin_id uuid, bin text, qty_ea numeric, received_by uuid, note text,
      line_no int, product_id uuid, unit_price numeric, sku text, counted numeric, basis numeric, diff_kind text, posted numeric)
    order by line_no, qty_ea desc, bin
  loop
    if b.posted <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, b.sku, v_wh, b.bin, b.posted, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, b.po_line_id::text, null, 'ims',          -- line_ref = po_line_id(라인 id · Caleb 실측 확정)
      jsonb_build_object(
        'kind', 'po_in', 'poster', c_version,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_line_id', b.receipt_line_id,
        'po_id', v_po.id, 'po_number', v_po.po_number,                                   -- 갈라진 뒤의 번호(ⓓ 뒤에 불린다 · §11-j)
        'po_line_id', b.po_line_id, 'line_no', b.line_no, 'product_id', b.product_id, 'sku', b.sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'received_by', b.received_by, 'confirmed_by', v_r.confirmed_by, 'confirmed_at', v_r.confirmed_at,
        'line', jsonb_build_object('counted', b.counted, 'basis', b.basis, 'posted', least(b.counted, b.basis), 'excess', greatest(b.counted - b.basis, 0), 'diff_kind', b.diff_kind),
        'this_bin', jsonb_build_object('counted', b.qty_ea, 'posted', b.posted, 'trimmed', b.qty_ea - b.posted),
        'bins', (select jsonb_agg(jsonb_build_object('bin', t2.bin, 'counted', t2.qty_ea, 'posted', t2.posted, 'trimmed', t2.qty_ea - t2.posted) order by t2.qty_ea desc, t2.bin)
                 from jsonb_to_recordset(v_alloc) as t2(po_line_id uuid, bin text, qty_ea numeric, posted numeric) where t2.po_line_id = b.po_line_id),
        'trim_rule', 'fill bins by qty desc, then bin name; cut where the cap runs out; cap = po_receipt_diff.expected_qty when over, else counted (nothing to cut); basis (recorded) = expected_qty whenever a diff row exists, else counted',
        'unit_price', b.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
        'note', b.note));
    v_rows := v_rows + 1;
    v_posted := v_posted + b.posted;
  end loop;

  -- 라인 요약(0 으로 깎인 줄도 bins[] 에 남는다)
  select coalesce(jsonb_agg(jsonb_build_object(
           'po_line_id', t.po_line_id, 'line_no', t.line_no, 'sku', t.sku, 'counted', t.counted, 'basis', t.basis,
           'posted', t.posted, 'excess', greatest(t.counted - t.basis, 0), 'diff_kind', t.diff_kind, 'bins', t.bins) order by t.line_no), '[]'::jsonb),
         coalesce(sum(t.counted), 0), coalesce(sum(greatest(t.counted - t.basis, 0)), 0)
    into v_lines, v_counted, v_excess
  from (
    select a.po_line_id, min(a.line_no) as line_no, min(a.sku) as sku, min(a.counted) as counted, min(a.basis) as basis, min(a.diff_kind) as diff_kind,
           sum(a.posted) as posted,
           jsonb_agg(jsonb_build_object('bin', a.bin, 'counted', a.qty_ea, 'posted', a.posted, 'trimmed', a.qty_ea - a.posted) order by a.qty_ea desc, a.bin) as bins
    from jsonb_to_recordset(v_alloc) as a(po_line_id uuid, line_no int, sku text, bin text, qty_ea numeric, counted numeric, basis numeric, diff_kind text, posted numeric)
    group by a.po_line_id
  ) t;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_counted', v_counted, 'qty_posted', v_posted, 'qty_excess', v_excess,
    'lines', v_lines, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Receipt % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_r.receipt_number, sqlerrm;
end;
$$;
comment on function public.inv_post_receipt(uuid) is '⭐⭐ 원장의 창구 — 확정된 입고(po_receipt · confirmed)를 읽어 inv_ledger 에 po_in 사건을 기표한다(원장 이식 2차 · 2026-09-19 · §11-j 「원장이 창구를 내고 PO 가 부른다」). 한 입고 줄 = 한 행(bin 별) · doc_type purchase · doc_number = 입고 번호 RCV-(PO 번호가 아니다 — 유니크에 doc_task_id 가 없다) · doc_task_id = po_receipt.id · line_ref = po_line_id(라인 id · Cin7 발주의 CardID 와 같은 결 · 같은 제품 두 라인도 키가 안 겹친다) · occurred_on = 묶음의 received_on · seq_hint 1 · source ims · amount null(단가·통화·환율은 raw). ⭐ 초과는 기준까지만(§11-i): 기준 = po_receipt_diff.expected_qty(over·short 둘 다 — ⓑ 가 얼린 값 · po_line.qty_ea 를 읽지 않는다 · 분할 뒤라도 안전 · 차이 행 없는 라인은 센 것) · 깎는 상한은 over 만(short 는 깎을 것이 없다 · 검증 ⑤ 정정) · 여러 빈이면 qty desc, bin 이름 순으로 채우고 바닥나는 줄에서 자른다(0 이 된 줄은 행 없음 · raw.bins 에 남는다). raw 에 센 것·넣은 것·차이·라인 전체 배분·갈라진 뒤 PO 번호. 멱등: 이미 기표된 입고는 already_posted=true · 0행(쓰지 않는다). 거부(읽을 수 있는 문장): 권한 · 확정 아님. 경고만: received_on 이 기초선보다 이름 · 미래. security invoker(inv_ledger insert 는 authenticated 에 열려 있다) · po_receipt_confirm 이 ⓓ 뒤에 같은 트랜잭션으로 부른다. ⚠️ append-only — 잘못 넣은 것은 상쇄로만';
revoke all on function public.inv_post_receipt(uuid) from public, anon;
grant execute on function public.inv_post_receipt(uuid) to authenticated;

-- ═══ ② po_receipt_confirm — 다시 냄 (시그니처 무변 · 20260918203805 원문 + ⓔ 창구 호출 · 반환 'ledger' · 그 밖은 글자 그대로) ═══
-- ⚠️ 아래 본문은 20260918203805 107~312행을 **복사**한 것이다(옮겨 적지 않았다). 바뀐 곳 넷: create or replace · declare v_ledger · ⓓ 뒤 ⓔ 블록 · 반환 'ledger'.
create or replace function public.po_receipt_confirm(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
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
  x           record;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ② · definer 안에서도 auth.uid() 는 JWT 의 것
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
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
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
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
  if v_r.received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_n then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_n, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 (분할 전 수량이 기준) — over · short · 안 센 라인은 short(received 0) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, case when x.counted > x.expected then 'over' else 'short' end, greatest(x.expected, 0), x.counted);
      if x.counted > x.expected then v_over := v_over + 1; else v_short := v_short + 1; end if;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', case when x.counted > x.expected then 'over' else 'short' end,
                                             'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 분할 또는 닫기 ═══
  if v_rem_total > 0 then
    -- ⬜4 번호 — 같은 base 의 접미사 최댓값 다음 두 글자(없으면 a·b)
    select max(substring(p.po_number from length(v_base) + 1)) into v_max
    from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
    if v_max is null then
      v_a_num := v_base || 'a'; v_b_num := v_base || 'b';
    else
      if length(v_max) <> 1 or v_max >= 'y' then
        raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
      end if;
      v_a_num := v_base || chr(ascii(v_max) + 1); v_b_num := v_base || chr(ascii(v_max) + 2);
    end if;

    -- b 문서 — 머리를 통째로 복사(칸이 늘어도 따라온다) · 번호 b · split_from_id = a · 상태 confirmed(같은 확정의 나머지 · confirmed_at/by 도 물려받는다) · 닫힘·취소 흔적 없음
    v_b_id := gen_random_uuid();
    insert into public.po
    select * from jsonb_populate_record(null::public.po,
      to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id,
                                           'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                           'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
    -- 할인 줄 복사(PO-02001b 선례 · Caleb 손 작업과 같다)
    insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
    select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;

    -- 라인 — 일부 받은 라인은 a 줄이고 b 신설 · 하나도 안 온 라인은 행을 b 로 옮긴다(인보이스 줄이 가리켜도 FK 가 따라간다)
    for x in
      select pl.*, 
             pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0)
               - coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as remaining
      from public.po_line pl where pl.po_id = v_po.id order by pl.line_no
    loop
      if x.remaining <= 0 then continue; end if;                                     -- 다 받았거나 초과 — a 에 그대로
      if x.qty_ea - x.remaining > 0 then
        -- 일부 받았다 — a 는 받은 만큼으로(입력 단위 셋은 비운다 · 이견 5)
        update public.po_line set qty_ea = x.qty_ea - x.remaining, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null
         where id = x.id and qty_ea = x.qty_ea;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        insert into public.po_line
        select * from jsonb_populate_record(null::public.po_line,
          to_jsonb(x) - 'remaining' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', x.remaining,
                                                          'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                          'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
        v_reduced := v_reduced + 1;
        if x.entered_unit_product_id is not null then v_cleared := array_append(v_cleared, x.line_no::text); end if;
      else
        -- 하나도 안 왔다 — 행을 통째로 b 로
        update public.po_line set po_id = v_b_id where id = x.id and po_id = v_po.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        v_moved := v_moved + 1;
      end if;
    end loop;

    -- a — 번호에 접미사 · 닫힘(입고 종료 · §11-b)
    update public.po set po_number = v_a_num, status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    if cardinality(v_cleared) > 0 then v_warn := array_append(v_warn, 'entered_units_cleared'); end if;
    v_warn := array_append(v_warn, 'po_split');
  else
    -- 다 받았다(또는 초과만) — 갈라지지 않고 닫힌다
    v_a_num := v_po.po_number;
    update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_closed');
  end if;
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); end if;
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

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', case when v_rem_total > 0 then jsonb_build_object('remainder_po_id', v_b_id, 'remainder_number', v_b_num, 'lines_reduced', v_reduced, 'lines_moved', v_moved, 'remainder_qty', v_rem_total) else null end,
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_receipt_confirm(uuid) is '⑤⭐⭐ 입고 확정(리시빙 2-b · 2026-09-18 → 원장 이식 2차 2026-09-19 다시 냄) — 「이 배로 온 것이 정해졌다」. 막는 것: 권한(receiving) · 이미 확정/취소 · PO 가 confirmed 아님(잠금 뒤 다시 본다) · 작업 줄 없음 · ⭐ 빈 없는 줄(라인·수량 + 빠져나갈 길을 문장에) · 빈이 다른 창고·비활성. 하는 일 ⓐ 작업 줄 → po_receipt_line 1:1(received_on 묶음 것 · received_by 놓은 사람→센 사람→확정한 사람 · 초과분 그대로) ⓑ 차이 큐 over/short(기준 = 분할 전 qty_ea − 이전 확정 합 · 안 센 라인도 short) ⓒ 라인 하나라도 남으면 자동 분할(§11-c · a 접미사+closed · b 신설 confirmed · split_from_id · 할인 복사 · 일부 라인은 줄이고 신설 · 0 라인은 행 이동) 아니면 닫기(closed·closed_at) ⓓ 묶음 confirmed ⭐ ⓔ 원장 창구 inv_post_receipt(같은 트랜잭션 · 원장이 실패하면 확정도 실패 · inv_ledger 직접 쓰기 없음 · 기준은 ⓑ 가 얼린 po_receipt_diff.expected_qty · 초과는 기준까지만). 반환에 ledger{rows_posted · qty_posted · qty_excess · lines[]} · warnings 에 ledger_trimmed_to_basis · received_on_before_baseline. ⭐ security definer(po·po_line 은 purchasing RLS · 2-b 이견 1) · 잠금 po:<base> + 라인 키. 정본 §11-i·c·j';
-- grant·revoke 는 20260918203805 의 것이 유지된다(create or replace).

-- ═══ ③ po_receipt_list — 다시 냄 (163552 589~624행 복사 · 맨 뒤에 open_diffs 한 칸 · 기존 24칸 이름·순서·타입 무변) ═══
-- ⚠️ create or replace view 는 기존 칸의 이름·순서·타입을 못 바꾼다(PG 규칙 · po_list_wide 선례) ⇒ 새 칸은 맨 뒤. 화면은 select("*") 로 읽는다(receiving.html 206행 · 짐작 아님 · 읽기만 했다) — 칸이 늘어도 깨지지 않는다.
create or replace view public.po_receipt_list
  with (security_invoker = true) as
with w as (
  select k.receipt_id,
         count(distinct k.po_line_id)::int                                          as counted_lines,
         coalesce(sum(k.qty_ea), 0)                                                 as counted_qty,
         coalesce(sum(k.qty_ea) filter (where k.bin_id is not null), 0)             as allocated_qty,
         coalesce(sum(k.qty_ea) filter (where k.putaway_done), 0)                   as placed_qty,
         count(*) filter (where k.bin_id is null)::int                               as unassigned_rows
  from public.po_receipt_work k
  group by k.receipt_id
),
pl as (
  select po_id, count(*)::int as po_lines, coalesce(sum(qty_ea), 0) as ordered_qty from public.po_line group by po_id
),
d as (                                                                               -- 열린 차이(원장 이식 2차 · 2026-09-19) — 쿼리로 센다(부분 인덱스 없음 · 규칙 29)
  select receipt_id, count(*) filter (where resolved_at is null)::int as open_diffs
  from public.po_receipt_diff group by receipt_id
)
select
  r.id, r.receipt_number, r.status, r.received_on,
  r.po_id, p.po_number, p.status as po_status,
  p.supplier_id, s.name as supplier_name,
  r.warehouse_id, wh.name as warehouse_name,
  coalesce(pl.po_lines, 0)          as po_lines,
  coalesce(pl.ordered_qty, 0)       as ordered_qty,
  coalesce(w.counted_lines, 0)      as counted_lines,
  coalesce(w.counted_qty, 0)        as counted_qty,
  coalesce(w.allocated_qty, 0)      as allocated_qty,
  coalesce(w.placed_qty, 0)         as placed_qty,
  coalesce(w.unassigned_rows, 0)    as unassigned_rows,
  r.created_by, cb.name as created_by_name,
  r.confirmed_at, r.cancelled_at, r.note, r.created_at, r.updated_at,
  coalesce(d.open_diffs, 0)         as open_diffs                                   -- ⭐ 새 칸은 맨 뒤(create or replace view 규칙 · 기존 24칸 이름·순서 무변)
from public.po_receipt r
join public.po p on p.id = r.po_id
join public.supplier s on s.id = p.supplier_id
join public.ref_warehouse wh on wh.id = r.warehouse_id
left join public.ims_staff cb on cb.id = r.created_by
left join w  on w.receipt_id = r.id
left join pl on pl.po_id = r.po_id
left join d  on d.receipt_id = r.id;


comment on view public.po_receipt_list is '⑤ 입고 목록 — PostgREST 로 표처럼(§10-j 3-a · po_list·po_invoice_list 와 같은 결). 번호 · PO · 공급처 · 창고 · 받은 날 · 상태 · PO 라인 수 · 센 수량 합 · 배정 합 · 놓은 합 · 미배정 줄 수 · 만든 사람 · ⭐ open_diffs(열린 차이 수 = po_receipt_diff.resolved_at is null · 원장 이식 2차 2026-09-19 · 맨 뒤 칸 · 쿼리로 센다 — 부분 인덱스 없음). 계산은 뷰가(화면이 다시 짜지 않는다). security_invoker. 2026-09-18';
-- grant·revoke 는 163552 의 것이 유지된다(create or replace).

-- ─────────────────────────────────────────────────────────────
-- 검증(회신 §5 · psql heredoc · Caleb 이 실행 · 새 입고를 만들고 rollback) 요지 — ① 딱 맞게 → po_in · source ims · RCV 번호 ② ims_inv_balance 증가 ③ ims_last_bin 이 그 빈
-- ④ 초과 → 기준까지만 · raw ⑤ 덜 받아 분할 → 분할 전 기준 ⑥ 두 빈 초과 → ⬜2 대로 ⑦ 목록 open_diffs ⑧ 권한 없는 확정 거부 ⑨ 롤백 뒤 source='ims' 0행
-- ─────────────────────────────────────────────────────────────
