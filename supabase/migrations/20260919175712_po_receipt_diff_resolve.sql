-- ─────────────────────────────────────────────────────────────
-- IMS 리시빙 — 차이 닫기(short) · 형제 문서 합계 (Asung-IMS · 2026-09-19)
--   ① po_receipt_diff + resolution · resolution_note   닫은 이유(어휘 다섯 · CHECK) · 「닫혔다」의 세 칸(resolution · resolved_by · resolved_at)이 함께 움직이게 CHECK 로 묶는다
--   ② po_family_members(po_id)    ⭐ 형제 문서 — split_from_id 로 뿌리까지 올라가 거기서 내려오며 전부 모은다(재귀 · 순환·깊이 방어)
--   ③ po_family_lines(po_id)      ⭐⭐ 형제 합계 · 제품 단위 — ordered_total(= 원래 주문 수량) · received_total · still_owed · fragments[](문서별 조각)
--   ④ po_receipt_diff_resolve(diff, resolution, note)   ⭐ short 를 닫는다 — over 는 이유를 문장에 적어 거부(재고를 움직이는 일 · 별도 차수)
--   ⑤ po_receipt_diff_reopen(diff, note)                되돌리기 — 사람의 판단 기록이라 잘못 닫은 것을 되돌릴 길이 있어야 한다
--   ⑥ po_receipt_diff_list       다시 냄 — 맨 뒤에 resolution · resolution_note(기존 26칸 무변)
--   ⑦ po_receipt_detail          다시 냄(시그니처 무변) — header.po_family · lines[].family · diffs[] + resolution·resolution_note·resolved_by·family
--
-- ⚠️⚠️ 전부 create or replace(함수·뷰) · alter … add column if not exists — 다시 밀 때 drop 이 필요하지 않다(inv_post_receipt 의 교훈 · §13-f).
-- 앞 차수: 20260918203805(차이 큐 표 · detail · diff_list) · 20260919155005(원장 이식 2차 · confirm ⓔ · po_receipt_list open_diffs). confirm 무접촉.
-- 정본: po-module §11-c(분할 · 알파벳을 잇는다 · line_no 같게) · §11-i(차이 큐 · short 를 담는 이유) · §13-f · §5 권한 규약 ②(첫머리 ims_require_write · update 뒤 row_count)
-- 지시서: ~/asung/prompts/ims-diff-resolve.md · ⬜1~8 은 회신에
--
-- ⭐⭐ 이견 1 — 형제끼리 라인은 **product_id** 로 맞춘다(line_no 가 아니다). 분할은 line_no 를 그대로 물려주지만(§11-c), 갈라진 b 는 confirmed 라 po_lines_paste 로
--   **새 라인을 더 붙일 수 있고**(20260916181719 · 「draft·confirmed 는 붙인다」) 그 line_no 는 b 안의 max+1 이라 a 의 다른 제품 line_no 와 겹칠 수 있다.
--   product_id 는 「결국 그 제품을 다 받았나」라는 질문의 축 자체다. 한 발주에 같은 제품 두 라인은 paste 가 막고(duplicate·exists) DB 유니크는 없지만,
--   생겨도 product_id 로 접으면 두 라인이 합쳐질 뿐 답(다 받았나)은 틀리지 않는다. line_no 는 조각(fragments[])에 표시용으로 남긴다.
-- ⭐ 이견 2 — 「닫혔다」의 축은 **resolved_at 하나**다(목록·상세·화면이 이미 그것을 본다). resolution 이 따로 놀 수 없게 CHECK 로 셋을 묶었다 — 하나만 채운 행은 DB 가 거부한다.
-- ⭐ 이견 3 — 되돌리기(reopen)를 이 차수에 넣었다. 차이 큐는 원장이 아니라 사람의 판단 기록이고, 잘못 닫은 것을 못 되돌리면 새 행을 만들어야 하는데 그것이 더 나쁘다.
--   되돌리면 세 칸을 비우고 resolution_note 는 남긴다(무엇으로 닫았었는지 흔적 · 새 메모를 주면 덧붙인다).
-- ⭐ 이견 4 — other 는 메모를 요구한다(CHECK + RPC 문장). 「그 밖」이 메모 없이 쌓이면 세는 뜻이 없다.
-- ⭐ 이견 5 — po_receipt_diff_list 에도 resolution · resolution_note 를 맨 뒤에 더했다(지시서 범위 밖 · 차이 큐 화면이 읽을 자리 · 기존 칸 무변).
-- ⚠️ 재귀 — 위로 올라갈 때·내려올 때 모두 path 배열로 방문을 표시하고(자기 자신·고리 차단) 깊이 50 에서 멈춘다. 순환이 있어도 빈 결과가 아니라 닿은 곳까지를 낸다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_receipt_diff — 이유 칸 · 함께 움직이는 세 칸 ═══
-- 어휘 다섯(short 의 이유 · Caleb): split_shipment(나눠 왔다 — 나머지가 갈라진 문서로 이어졌고 결국 다 받았다) · out_of_stock(공급사 결품 — 영영 안 온다 · 발주를 닫는다)
--   · lost_damaged(운송 중 분실·파손 — 크레딧을 받는다) · miscount(우리가 잘못 셌다) · other(그 밖 · ⚠️ 메모 필수). 자유 메모가 아니라 어휘여야 「결품이 몇 번이나 났나」를 셀 수 있다.
alter table public.po_receipt_diff add column if not exists resolution      text;
alter table public.po_receipt_diff add column if not exists resolution_note text;

alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolution_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_ck
  check (resolution is null or resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other'));
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_other_note_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_other_note_ck
  check (resolution is distinct from 'other' or resolution_note is not null);                               -- other 면 메모가 있어야 한다(같은 행 안 · CHECK 가능)
-- ⭐ 「닫혔다」의 세 칸이 함께 — 종전 (resolved_at is null) = (resolved_by is null) 에 resolution 을 묶는다. 하나만 채운 행은 들어갈 수 없다(목록의 칩이 거짓말을 못 한다).
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolved_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolved_ck
  check ((resolved_at is null) = (resolved_by is null) and (resolved_at is null) = (resolution is null));

comment on column public.po_receipt_diff.resolution      is '닫은 이유 — split_shipment | out_of_stock | lost_damaged | miscount | other(메모 필수). 어휘(자유 메모 아님 · 세기 위해). null = 안 닫혔다. ⭐ resolved_at·resolved_by 와 함께 채워진다(CHECK po_receipt_diff_resolved_ck) — 닫는 길은 po_receipt_diff_resolve 하나 · 되돌리기는 po_receipt_diff_reopen. 2026-09-19';
comment on column public.po_receipt_diff.resolution_note is '닫을 때의 메모 — other 면 필수(CHECK) · 그 밖은 선택. 되돌려도 지우지 않는다(무엇으로 닫았었는지 흔적). 2026-09-19';
comment on table  public.po_receipt_diff is '⑤ 입고 차이 큐(리시빙 2-b · 2026-09-18 · Caleb) — 확정하는 순간 라인마다 기준(PO 확정 수량 − 이전 확정 입고)과 센 수량이 다르면 한 건. over = 기준보다 많이 왔다(재고에 안 들어간 것이 건물에 있다 · 사건은 기준까지만 §11-i) · short = 적게 왔다(분할은 나머지를 옮길 뿐 「왜 덜 왔나」는 아무도 안 본다 — 나눠 보냄·결품·분실·오산을 사람이 가른다) · off_po = PO 에 없는 물건(어휘만). ⭐ [2026-09-19] 닫는 길 = po_receipt_diff_resolve(short 만 · 이유 어휘 다섯 · other 는 메모) · 되돌리기 = po_receipt_diff_reopen · over 는 재고를 움직이는 일이라 별도 차수 · 「닫혔다」= resolved_at(resolution·resolved_by 와 CHECK 로 묶임). 형제 합계는 po_family_lines. 정본 po-module §11-i';

-- ═══ ② po_family_members(p_po_id) — ⭐ 형제 문서 ═══
-- split_from_id 를 거슬러 뿌리까지 올라가고(up) 거기서 내려오며(down) 전부 모은다. a → b → c·d 처럼 여러 단이 될 수 있다(§11-c 알파벳을 잇는다).
-- ⚠️ 순환 방어 둘 — path 배열에 방문한 id 를 쌓아 이미 있는 id 로는 안 간다(자기 자신을 가리키는 split_from_id · 고리) · 깊이 50 에서 멈춘다.
--   고리가 있어도 빈 결과가 아니라 닿은 곳까지를 낸다(뿌리 = 올라가서 닿은 가장 위). 분할이 없었으면 자기 자신 하나.
-- 없는 id → 0행. security invoker · stable · set-returning(detail·RPC·화면 어디서든 같은 답).
create or replace function public.po_family_members(p_po_id uuid)
returns table (po_id uuid, po_number text, status text, closed_at timestamptz, split_from_id uuid, depth int, is_self boolean)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with recursive up as (
  select p.id, p.split_from_id, 1 as depth, array[p.id] as path
  from public.po p where p.id = p_po_id
  union all
  select q.id, q.split_from_id, up.depth + 1, up.path || q.id
  from up join public.po q on q.id = up.split_from_id
  where up.depth < 50 and not (q.id = any(up.path))                                                         -- 순환 · 깊이 방어(올라갈 때)
),
root as (
  select u.id from up u order by u.depth desc limit 1                                                        -- 올라가서 닿은 가장 위 = 뿌리
),
down as (
  select p.id, p.split_from_id, 0 as depth, array[p.id] as path
  from public.po p where p.id = (select id from root)
  union all
  select c.id, c.split_from_id, down.depth + 1, down.path || c.id
  from down join public.po c on c.split_from_id = down.id
  where down.depth < 50 and not (c.id = any(down.path))                                                      -- 순환 · 깊이 방어(내려올 때)
)
select p.id, p.po_number, p.status, p.closed_at, p.split_from_id, d.depth, (p.id = p_po_id)
from down d join public.po p on p.id = d.id
order by p.po_number;
$$;
comment on function public.po_family_members(uuid) is '⭐ 형제 문서 — 이 발주가 속한 분할 가족 전부(뿌리에서 내려온 모든 문서 · 자기 자신 포함 · 분할이 없었으면 하나). split_from_id 로 뿌리까지 올라가 거기서 내려오는 재귀 · ⚠️ path 배열로 순환(자기 참조·고리)을 막고 깊이 50 에서 멈춘다 — 고리가 있어도 닿은 곳까지 낸다. 칸: po_id · po_number · status · closed_at · split_from_id · depth(뿌리 0) · is_self. security invoker · stable. 2026-09-19 · 정본 po-module §11-c';
revoke all on function public.po_family_members(uuid) from public, anon;
grant execute on function public.po_family_members(uuid) to authenticated;

-- ═══ ③ po_family_lines(p_po_id) — ⭐⭐ 형제 합계 · 제품 단위 ═══
-- 이견 1 — 라인은 product_id 로 맞춘다. ordered_total = 형제 전부의 po_line.qty_ea 합(⭐ 분할이 a 를 줄이고 b 에 나머지를 신설하므로 합이 보존된다 — 검증 ②가 실물로 잰다)
--   · received_total = 형제의 모든 po_line 에 달린 po_receipt_line.qty_ea 합(초과분 포함 · 「받은 것」의 사실) · still_owed = 차 · members = 그 제품이 걸린 문서 수
--   · fragments[] = 문서별 조각 {po_id, po_number, po_status, po_line_id, line_no, ordered, received} (화면은 한 줄을 쓰고 펼치면 이것을 본다).
create or replace function public.po_family_lines(p_po_id uuid)
returns table (product_id uuid, sku text, product_name text, line_nos int[], ordered_total numeric, received_total numeric, still_owed numeric, members int, fragments jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with fm as (
  select * from public.po_family_members(p_po_id)
),
frag as (
  select pl.product_id, fm.po_id, fm.po_number, fm.status as po_status, pl.id as po_line_id, pl.line_no, pl.qty_ea as ordered,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id), 0) as received
  from fm join public.po_line pl on pl.po_id = fm.po_id
)
select f.product_id, pr.sku, pr.name as product_name,
       array_agg(distinct f.line_no order by f.line_no),
       sum(f.ordered), sum(f.received), sum(f.ordered) - sum(f.received),
       count(distinct f.po_id)::int,
       jsonb_agg(jsonb_build_object('po_id', f.po_id, 'po_number', f.po_number, 'po_status', f.po_status, 'po_line_id', f.po_line_id,
                                    'line_no', f.line_no, 'ordered', f.ordered, 'received', f.received)
                 order by f.po_number, f.line_no)
from frag f
join public.product pr on pr.id = f.product_id
group by f.product_id, pr.sku, pr.name;
$$;
comment on function public.po_family_lines(uuid) is '⭐⭐ 형제 합계 · 제품 단위 — 그 발주의 분할 가족(po_family_members) 전부에서 product_id 로 접는다(⚠️ line_no 가 아니다 — 갈라진 b 에 새 라인이 붙으면 line_no 가 다른 제품과 겹칠 수 있다 · 이견 1). ordered_total = 형제 po_line.qty_ea 합(= 원래 주문 수량 · 분할이 합을 보존한다 §11-c) · received_total = 형제의 po_receipt_line 합(초과분 포함) · still_owed · members · fragments[]{po_id, po_number, po_status, po_line_id, line_no, ordered, received}. ⭐ 계산은 DB 가 한다 — 화면이 형제를 찾아 더하지 않는다. 분할이 없었으면 조각 하나. security invoker · stable. 2026-09-19';
revoke all on function public.po_family_lines(uuid) from public, anon;
grant execute on function public.po_family_lines(uuid) to authenticated;

-- ═══ ④ po_receipt_diff_resolve(p_diff_id, p_resolution, p_note) — ⭐ short 를 닫는다 ═══
-- POST /rest/v1/rpc/po_receipt_diff_resolve  {"p_diff_id":…,"p_resolution":"split_shipment","p_note":null}
-- → { diff_id, receipt_id, receipt_number, kind, sku, line_no, expected_qty, received_qty, resolution, resolution_note, resolved_by, resolved_by_name, resolved_at,
--     family{ordered_total, received_total, still_owed, members}, open_diffs_left }   ← 화면이 칩을 갱신한다
-- 막는 것(읽을 수 있는 문장 · 「nothing was saved」): 권한 · 직원 기록 없음 · 이유가 어휘 밖 · other 인데 메모 없음 · 없는 차이 · ⭐ kind 가 short 아님(over 는 왜 아직 안 되는지를 문장에)
--   · 이미 닫힘(누가 무엇으로 언제 — reopen 을 안내). update 는 resolved_at is null 조건으로 · row_count 0 이면 남이 사이에 닫은 것 — 거부(§5 ②).
-- security invoker — po_receipt_diff 의 update 정책이 ims_can_write('receiving') 이고 첫머리에서 같은 것을 묻는다(definer 가 필요한 표가 없다).
create or replace function public.po_receipt_diff_resolve(p_diff_id uuid, p_resolution text, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
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

  -- ① short 만 — over 는 재고를 움직이는 일(받기로 했으면 장부에 넣어야 하고 돌려보냈으면 안 넣는다) · 별도 차수
  if v_d.kind <> 'short' then
    raise exception 'Line % (%) on % is an "%" difference — only short differences can be settled here. An over difference also has to decide whether the extra goes into stock or back to the supplier — that is not built yet — nothing was saved',
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
  select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members)
    into v_fam
  from public.po_family_lines(v_d.po_id) f where f.product_id = v_d.product_id;

  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number,
    'kind', v_d.kind, 'sku', v_sku, 'line_no', v_line_no, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
    'resolution', p_resolution, 'resolution_note', v_note, 'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'family', v_fam,
    'open_diffs_left', v_open);
end;
$$;
comment on function public.po_receipt_diff_resolve(uuid, text, text) is '⑤⭐ 차이 닫기(short 만 · 2026-09-19 · Caleb) — 이유 어휘 다섯(split_shipment · out_of_stock · lost_damaged · miscount · other[메모 필수])으로 닫고 resolution·resolved_by(서버 유도)·resolved_at 을 함께 채운다. 막는 것(읽을 수 있는 문장): 권한(receiving) · 어휘 밖 · other 인데 메모 없음 · 없는 차이 · ⭐ over 는 거부하며 왜 아직 안 되는지 말한다(재고에 넣을지 돌려보낼지를 정해야 한다 — 별도 차수) · 이미 닫힘(누가·무엇으로·언제 + reopen 안내) · 남이 사이에 닫음(row_count 0). 반환에 family(형제 합계 · 제품 단위)와 open_diffs_left(이 입고에 남은 열린 차이 — 화면이 칩을 갱신). security invoker · 잠금 for update. 정본 po-module §11-i';
revoke all on function public.po_receipt_diff_resolve(uuid, text, text) from public, anon;
grant execute on function public.po_receipt_diff_resolve(uuid, text, text) to authenticated;

-- ═══ ⑤ po_receipt_diff_reopen(p_diff_id, p_note) — 되돌리기 ═══
-- 세 칸(resolution · resolved_by · resolved_at)을 함께 비운다. resolution_note 는 지우지 않는다 — 새 메모를 주면 앞에 덧붙인다(무엇으로 닫았었는지 흔적).
create or replace function public.po_receipt_diff_reopen(p_diff_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_d     public.po_receipt_diff%rowtype;
  v_r     public.po_receipt%rowtype;
  v_n     int;
  v_open  int;
  v_note  text;
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

  v_note := nullif(btrim(p_note), '');
  update public.po_receipt_diff
     set resolution = null, resolved_by = null, resolved_at = null,
         resolution_note = case when v_note is null then resolution_note
                                else 'reopened: ' || v_note || coalesce(' | was: ' || resolution || coalesce(' — ' || resolution_note, ''), '') end
   where id = p_diff_id and resolved_at is not null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Difference on % was not saved — it may have been reopened by someone else just now — nothing was saved', v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'kind', v_d.kind,
                            'was_resolution', v_d.resolution, 'was_resolved_by', v_d.resolved_by, 'was_resolved_at', v_d.resolved_at,
                            'reopened_by', v_staff, 'open_diffs_left', v_open);
end;
$$;
comment on function public.po_receipt_diff_reopen(uuid, text) is '⑤ 차이 되돌리기(2026-09-19) — 닫힌 차이의 resolution·resolved_by·resolved_at 을 함께 비운다(CHECK 가 셋을 묶는다). resolution_note 는 지우지 않고 새 메모를 주면 「reopened: … | was: <이유>」로 덧붙인다(흔적). 막는 것: 권한 · 없는 차이 · 안 닫힌 것(되돌릴 것이 없다) · 남이 사이에 되돌림. 반환에 was_* 와 open_diffs_left. security invoker. 정본 po-module §11-i';
revoke all on function public.po_receipt_diff_reopen(uuid, text) from public, anon;
grant execute on function public.po_receipt_diff_reopen(uuid, text) to authenticated;

-- ═══ ⑥ po_receipt_diff_list — 다시 냄 (203805 80~96행 복사 · 맨 뒤에 resolution · resolution_note · 기존 26칸 이름·순서 무변) ═══
create or replace view public.po_receipt_diff_list
  with (security_invoker = true) as
select
  d.id, d.kind, d.expected_qty, d.received_qty, d.received_qty - d.expected_qty as diff_qty,
  d.receipt_id, r.receipt_number, r.received_on, r.warehouse_id, wh.name as warehouse_name,
  d.po_id, p.po_number, p.status as po_status, p.supplier_id, s.name as supplier_name,
  d.po_line_id, pl.line_no, d.product_id, pr.sku, pr.name as product_name,
  d.note, d.resolved_at, d.resolved_by, rb.name as resolved_by_name,
  d.created_at, d.updated_at,
  d.resolution, d.resolution_note                                          -- 새 칸은 맨 뒤(create or replace view 규칙 · 기존 26칸 무변 · 2026-09-19)
from public.po_receipt_diff d
join public.po_receipt r on r.id = d.receipt_id
join public.ref_warehouse wh on wh.id = r.warehouse_id
join public.po p on p.id = d.po_id
join public.supplier s on s.id = p.supplier_id
left join public.po_line pl on pl.id = d.po_line_id
join public.product pr on pr.id = d.product_id
left join public.ims_staff rb on rb.id = d.resolved_by;

comment on view public.po_receipt_diff_list is '⑤ 입고 차이 큐 목록(리시빙 2-b) — 종류 · 기준 · 센 수량 · 차이 · 묶음 · 발주 · 공급처 · 라인 · 제품 · 닫은 사람 · ⭐ [2026-09-19] resolution · resolution_note(맨 뒤 칸). 열린 것 = resolved_at is null(쿼리로 센다 · 부분 인덱스 없음). security_invoker. 2026-09-18';
-- grant·revoke 는 203805 의 것이 유지된다(create or replace).

-- ═══ ⑦ po_receipt_detail — 다시 냄 (시그니처 무변 · 203805 318행~ 원문 복사 · 바뀐 곳 넷: CTE fm·fam · header.po_family · lines[].family · diffs[] 칸 넷) ═══
-- ⚠️ 형제가 없으면(분할이 없었으면) po_family.members 는 자기 자신 하나 · family.fragments 는 조각 하나 — 빈 값이 아니다.
create or replace function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone,
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  where k.receipt_id = p_receipt_id
),
rl as (
  select l.*, b.name as bin, b.zone, pl.line_no,
         (select s.name from public.ims_staff s where s.id = l.received_by) as received_by_name
  from public.po_receipt_line l
  join public.po_line pl on pl.id = l.po_line_id
  left join public.ref_bin b on b.id = l.bin_id
  where l.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(y.qty_ea) from rl y where y.po_line_id = pl.id), 0) as received_here,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
),
fm as (                                                     -- 형제 문서 — 뿌리에서 내려온 전부 · 자기 자신 포함 · 분할이 없었으면 하나(차이 닫기 차수 2026-09-19)
  select * from public.po_family_members((select po_id from r))
),
fam as (                                                    -- 형제 합계 · 제품 단위 — ⭐ 계산은 DB 가 한다(화면이 형제를 찾아 더하지 않는다)
  select * from public.po_family_lines((select po_id from r))
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status, 'po_closed_at', p.closed_at,
      'po_split_from_number', sf.po_number,
      'po_split_to', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'po_number', c.po_number, 'status', c.status) order by c.po_number) from public.po c where c.split_from_id = p.id), '[]'::jsonb),
      'po_family', jsonb_build_object(                                                                      -- ⭐ 형제 문서 합계(문서 단위 · 2026-09-19) — 「12 중 12 · 다 받음」의 근거
        'root_number', (select m.po_number from fm m order by m.depth, m.po_number limit 1),
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.po_id, 'po_number', m.po_number, 'status', m.status, 'closed_at', m.closed_at, 'is_this', m.is_self) order by m.po_number) from fm m), '[]'::jsonb),
        'ordered_total',  (select coalesce(sum(f.ordered_total), 0)  from fam f),
        'received_total', (select coalesce(sum(f.received_total), 0) from fam f),
        'still_owed',     (select coalesce(sum(f.still_owed), 0)     from fam f)),
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before, 'received_here', l.received_here,
      'remaining', l.ordered - l.received_before,
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'over', (l.counted > l.ordered - l.received_before),
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = l.product_id),                                              -- 형제 합계(제품 단위 · 2026-09-19) — 조각은 fragments[]
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name)
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'receipt_lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', y.id, 'po_line_id', y.po_line_id, 'line_no', y.line_no, 'qty_ea', y.qty_ea, 'bin_id', y.bin_id, 'bin', y.bin, 'zone', y.zone,
      'received_on', y.received_on, 'received_by', y.received_by, 'received_by_name', y.received_by_name, 'note', y.note, 'created_at', y.created_at)
      order by y.line_no, y.bin)
    from rl y), '[]'::jsonb),
  'diffs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'kind', d.kind, 'po_line_id', d.po_line_id, 'line_no', pl.line_no, 'sku', pr.sku,
      'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
      'note', d.note, 'resolved_at', d.resolved_at, 'resolved_by', d.resolved_by, 'resolved_by_name', rb.name,      -- rb = 별칭 서브쿼리(ims_staff 자기 칸과 헷갈리지 않게)
      'resolution', d.resolution, 'resolution_note', d.resolution_note,                                              -- 닫은 이유(차이 닫기 차수 2026-09-19)
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = d.product_id))                                              -- ⭐ 닫을 때 「결국 다 받았나」가 여기 있다
      order by pl.line_no)
    from public.po_receipt_diff d
    left join public.po_line pl on pl.id = d.po_line_id
    join public.product pr on pr.id = d.product_id
    left join public.ims_staff rb on rb.id = d.resolved_by
    where d.receipt_id = p_receipt_id), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'received_here', coalesce(sum(l.received_here), 0),
      'over_lines', count(*) filter (where l.counted > l.ordered - l.received_before),
      'short_lines', count(*) filter (where l.counted < l.ordered - l.received_before),
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.ordered - l.received_before) then 'over_receipt' end,
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end
      ], null)) as v) t
  )
) end;
$$;
comment on function public.po_receipt_detail(uuid) is '⑤ 입고 상세 — ⭐ 계산의 정본(화면은 그린다 · 다시 짜지 않는다 · 2-a → 2-b → 차이 닫기 차수 2026-09-19 다시 냄). header(+ po_closed_at · po_split_from_number · po_split_to[] · ⭐ po_family{root_number, members[{id, po_number, status, closed_at, is_this}], ordered_total, received_total, still_owed}) · lines[] = PO 라인 전부 — ordered · invoiced(표시만) · received_before · received_here · remaining · counted · allocated · unallocated · placed · over · ⭐ family{ordered_total, received_total, still_owed, members, fragments[]}(형제 합계 · 제품 단위 · po_family_lines) · work[] · receipt_lines[] · ⭐ diffs[](+ resolved_by · resolution · resolution_note · family — 닫을 때 「결국 다 받았나」가 여기) · totals(+ received_here · open_diffs) · warnings[]. 이름은 전부 별칭 서브쿼리. 형제가 없으면 자기 자신 하나. 없는 id → null. 정본 §11-i · §11-c';
-- grant·revoke 는 163552 의 것이 유지된다(create or replace)

-- ─────────────────────────────────────────────────────────────
-- 화면(receiving.html · 대화 Claude)이 부르는 모양
--   닫기      sb.rpc("po_receipt_diff_resolve", { p_diff_id, p_resolution, p_note })  → data.open_diffs_left(칩) · data.family(「12 중 12 · 다 받음」) · 거부 문장은 그대로 띄운다
--   되돌리기  sb.rpc("po_receipt_diff_reopen",  { p_diff_id, p_note })
--   상세      sb.rpc("po_receipt_detail", { p_receipt_id }) → diffs[].family(한 줄 · fragments[] 를 펼치면 조각) · header.po_family.members[]
--   차이 큐   sb.from("po_receipt_diff_list") … 이제 resolution · resolution_note 칸이 있다
-- 검증(회신 §4 · psql heredoc · Caleb 이 실행 · 쓰는 것은 rollback) 요지 — ① PO-02011a 12 중 12 · 조각 a 10 · b 2 ② 분할 없는 발주는 자기 하나 ③ 닫으면 세 칸이 함께 ④ open_diffs 0
--   ⑤ over 거부 문장 ⑥ 어휘 밖 거부 ⑦ 이미 닫힌 것 거부(reopen 안내) ⑧ 권한 없는 호출 거부 ⑨ 롤백 뒤 무흔적 · ⬜2 「분할이 합을 보존한다」 실측
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────
