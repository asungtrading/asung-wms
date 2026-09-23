-- SO 쓰기 ①c — 운임·서비스 줄 금액은 음수를 막는다(판정 Caleb 2026-09-23 · ①b 회신 8 에 대한 판정)
-- 근거: 돌려줄 돈은 크레딧 노트가 담는다(so-module 8-g) — 음수 운임을 열면 같은 일을 하는 길이 둘이 되고 「운임을 얼마 받았나」가 섞인다 · 안 받으면 줄을 안 넣거나 0
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
-- ① CHECK so_charge_amount_ck (amount >= 0) — so_charge.amount 는 NOT NULL(20260923133042:276)이라 null 구멍 없음(§10 머리 규칙 확인)
-- ② so_charge_set 을 다시 낸다(마지막 정의 20260923191030:843 · create or replace · 시그니처 그대로 → grant·comment 유지) — 더한 줄은 음수 거부 셋뿐(원본과 diff 로 대조 · 회신)
-- ⚠️ 그 밖은 건드리지 않는다 — so_line_update 의 surcharge_amount 는 이 판정 밖(부가 요금 % · 금액 · 판정 7 짝만)

-- ═══ ① CHECK ═══
alter table public.so_charge
  add constraint so_charge_amount_ck check (amount >= 0);
comment on constraint so_charge_amount_ck on public.so_charge is '①c 판정(Caleb 2026-09-23) — 운임·서비스 금액은 0 이상 · 돌려줄 돈은 크레딧 노트(8-g) · amount 는 NOT NULL 이라 null 규칙 무관';

-- ═══ ② so_charge_set — 사람이 읽을 거부 문장(CHECK 앞) ═══
create or replace function public.so_charge_set(
  p_so_id       uuid,
  p_name        text,
  p_amount      numeric,
  p_charge_id   uuid default null,
  p_description text default null,
  p_tax_rule    text default null,
  p_account_id  uuid default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'A charge needs a name — nothing was saved';
  end if;
  if p_amount is null then
    raise exception 'A charge needs an amount — nothing was saved';
  end if;
  if p_amount < 0 then                                          -- ①c 판정(Caleb 2026-09-23) — 돌려줄 돈은 크레딧 노트(8-g) · CHECK so_charge_amount_ck 가 마지막 문
    raise exception 'A charge cannot be negative — use a credit note — nothing was saved';
  end if;

  if p_account_id is not null then
    select * into v_acct from public.ref_account where id = p_account_id;
    if not found then
      raise exception 'Account not found — nothing was saved';
    end if;
  end if;

  if p_charge_id is null then
    if p_account_id is null then
      select * into v_acct from public.ref_account where code = '_99_';          -- 기본 Freight Sales · 없으면 비우고 알린다(짐작 값을 박지 않는다)
      if not found then v_warn := array_append(v_warn, 'charge_account_unset'); end if;
    end if;
    select coalesce(max(line_no), 0) + 1 into v_next from public.so_charge where so_id = p_so_id;
    insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by)
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, nullif(trim(p_tax_rule), ''), v_acct.id, v_acct.code, v_staff)
    returning * into v_ch;
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch), 'warnings', to_jsonb(v_warn));
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
  end if;
  update public.so_charge c set
    name         = v_name,
    description  = nullif(trim(p_description), ''),
    amount       = p_amount,
    tax_rule     = nullif(trim(p_tax_rule), ''),
    account_id   = case when p_account_id is not null then v_acct.id   else c.account_id end,
    account_code = case when p_account_id is not null then v_acct.code else c.account_code end,
    updated_by   = v_staff
  where c.id = p_charge_id
  returning * into v_ch;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not saved — it may have been removed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('action', 'updated', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch), 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 검증(Caleb · psql heredoc · 회신에 따로) — 음수 거부(P0001 문장) · 0 통과 · 110.50 통과 · 표 직접 insert 음수 → 23514 so_charge_amount_ck · 시험은 번호 직접(SO-99999t) · 시퀀스 무접촉
