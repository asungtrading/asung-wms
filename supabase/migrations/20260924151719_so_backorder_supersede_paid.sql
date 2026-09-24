-- SO 쓰기 ③b′ — so_backorder_supersede 재발행: 이어받기는 값을 매긴 줄만 센다 (판정 13 · Caleb 2026-09-24 「무상줄은 세지 말아야지」)
-- 사정: 20260924145105 의 so_backorder_supersede 는 새 오더의 그 제품 줄 수량을 전부 셌다 — 무상 줄(free_reason sample · promotion · replacement · other)도 들어갔다.
--   예) vv A 60 백오더 · 파손 교환품 A 1 을 무상(replacement)으로 넣은 오더를 확정 → 60 이 「1 이어받음 · 59 더 원하지 않음」으로 닫힌다 — 수요가 1 로 줄었다고 잘못 기록되고 알림도 안 간다.
-- 판정: free_reason is not null 인 줄은 수량에서 뺀다 · 그 제품에 무상 줄만 있으면 그 제품은 이어받지 않는다(k 행이 안 생긴다) · 대표 줄(taken_by_line_id)도 값을 매긴 줄에서.
--   근거: 샘플·프로모션·교환품은 손님이 수요를 다시 말한 것이 아니라 우리가 준 것.
-- 방법: 마지막 정의 20260924145105:112~170(③c 는 이 함수를 다시 내지 않았다 · grep 확인)을 바이트 그대로 뽑아 join 조건 한 줄에 `and l.free_reason is null` · create → create or replace · comment 한 문장 — 원본 diff 는 회신(바뀐 줄 3 · 빠진 줄 0).
-- 같은 모양 훑기: 「새 오더의 그 제품 수량」을 세는 자리(sum(qty_ordered) · 같은 손님·같은 제품)는 마지막 정의 전수에서 이 함수 한 곳(grep) — 다른 자리 없음.
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3b-verify.sql v3 13) 절(나머지 절은 그대로 다시 돈다)

create or replace function public.so_backorder_supersede(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_base  text;
  k       record;
  t       record;
  v_rem   numeric;
  v_take  numeric;
  v_n     int := 0;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' or v_so.confirmed_at is null then
    raise exception 'Order % is % — backorders are taken over at confirmation only — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');

  for k in
    select l.product_id, sum(l.qty_ordered) as qty,
           (array_agg(l.id order by (s.id <> p_so_id), s.so_number, l.line_no))[1] as line_id
    from public.so_line l join public.so s on s.id = l.so_id and l.free_reason is null     -- ③b′ 판정 13: 값을 매긴 줄만 센다(무상 줄은 우리가 준 것 · 수요가 아니다) · 무상 줄만 있는 제품은 이어받지 않는다 · 대표 줄도 유상 줄에서
    where s.id = p_so_id
       or (s.split_from_id = p_so_id and s.confirmed_at = v_so.confirmed_at and s.created_at = v_so.confirmed_at)
    group by l.product_id
  loop
    v_rem := k.qty;
    for t in
      select res.id as reserve_id, res.qty_allocated, l.id as line_id, l.line_no, l.sku, s.so_number, s.order_date, s.location_name
      from public.so_reserve res
      join public.so_line l on l.id = res.so_line_id
      join public.so s on s.id = l.so_id
      where res.kind = 'backorder' and res.released_at is null
        and s.status = 'confirmed'
        and s.customer_id = v_so.customer_id
        and l.product_id = k.product_id
        and regexp_replace(s.so_number, '[a-z]+$', '') <> v_base
      order by s.order_date, s.created_at, s.so_number, l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || t.line_id::text));
      v_take := least(t.qty_allocated, v_rem);
      perform public.so_backorder_record(t.line_id, 'superseded', t.qty_allocated, v_take, t.qty_allocated - v_take, p_so_id, k.line_id, p_staff, null);
      update public.so_reserve set released_at = now(), released_by = p_staff, released_reason = 'closed', updated_by = p_staff
      where id = t.reserve_id and released_at is null;
      v_rem := v_rem - v_take;
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('so_number', t.so_number, 'line_no', t.line_no, 'sku', t.sku, 'order_date', t.order_date, 'location', t.location_name,
                                           'qty_open', t.qty_allocated, 'qty_taken', v_take, 'qty_unwanted', t.qty_allocated - v_take, 'taken_by_line_id', k.line_id);
    end loop;
  end loop;
  return jsonb_build_object('lines_closed', v_n, 'lines', v_out);
end;
$$;
comment on function public.so_backorder_supersede(uuid, uuid) is
  '⭐ 확정 때 이어받기(③b · 판정 3·4·5·8·9 · so_confirm 끝에서 commit 만) — 같은 손님·같은 제품의 열린 백오더 줄(가족 밖 · confirmed · 브랜치 무관 · 프리오더 제외)을 가장 오래된 줄부터 새 수량으로 채우고(qty_taken) 나머지는 더 원하지 않음(qty_unwanted) · ⭐ 새 수량은 값을 매긴 줄만(free_reason null · 판정 13 · 무상 줄만 있는 제품은 이어받지 않는다) · 예약 closed · 장부 superseded(taken_by = 확정한 오더 · 그 제품의 첫 줄) · 오더는 닫지 않는다(판정 11 · 만료가 닫는다)';
revoke all on function public.so_backorder_supersede(uuid, uuid) from public, anon, authenticated;
