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
-- 20261008170700_po_tax_1.sql — po-tax-1 (2026-10-08 · 회사 PC) · PO 매입 세금 ① 규칙 FK · 세금 식 · 낼 돈
--   Caleb 결정(2026-10-08 · 판정 번호는 다음 문서 차수): ① 세금 규칙의 출처 = 공급처(supplier.tax_rule) → PO 머리 · 줄은 머리를 따른다(null = 머리) · 직원이 머리를 고치고 특별한 줄만 줄에서
--   ② 반올림은 SO 와 PO 모두 줄마다(모양 A) — 줄마다 round(줄 × rate/100, 2) · 문서 할인 체인은 「할인 줄」 하나로 보고 그 세금을 한 번 매겨 뺀다 · 규칙 묶음(같은 규칙의 줄)마다
--   ③ 매입 세금은 상품 원가에 넣지 않는다(원가 창구 무접촉 — po-tax-0 §3-9) ④ PO 는 예상 세금 · 세금 포함 합계를 보인다 ⑤ 인보이스는 찍힌 총액(total_amount)이 낼 돈의 정본 그대로 ·
--      「줄 합(체인 뒤) + 계산한 세금」이 대조값 · 다르면 기존 경고 total_differs_from_lines ⑥ 「USD 인데 세율 > 0」 경고 없음 ⑦ 공급처 데이터는 안 고친다
--   po-tax-0 보고에서 받은 것: FK + 원문 짝(so 모양 · 짝 CHECK) · supplier 는 원문 그대로(PO 머리에서 이름 → id · 못 풀면 경고) · 세금은 저장하지 않고 식 한 곳에서 · 공급처 크레딧도 같은 식 ·
--      낼 돈 = payable_net(payable 줄만 세금 포함) · 결제 창구는 뷰 값을 받는다 · 세금은 문서 통화(환산 없음) · tax_inclusive 는 기록만(true 면 경고) · 계정은 안 쓴다(QBO 때) ·
--      머리 규칙을 고치는 길 = 표 트리거(PostgREST 직접 쓰기) · backfill po 29 · po_invoice.total_amount 주석 정정
--   이 차수 밖: po_charge 세금 칸 · tf_charge_* · 비용 결제 갈래(po-tax-2) · 할인 → 원가(그 뒤) · 화면(대화 Claude)
--   대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/po-tax-1-verify.sql
--
--   ① 칸 — po.tax_rule_id · po_line.tax_rule_id · po_invoice.tax_rule + tax_rule_id · po_invoice_line.tax_rule + tax_rule_id · FK 인덱스 넷 · 짝 CHECK 넷(backfill 뒤에 건다) · 주석
--   ② 짝 트리거 하나(po_tax_rule_pair · 네 표 BEFORE INSERT OR UPDATE OF tax_rule_id, tax_rule) — id 가 오면 원문 채우기 · 원문이 오면 id 풀기 · 둘 다 바뀌면 id 가 이긴다 · purchase · 활성이 아니면 거부(읽을 문장)
--      네 표 전부에 거는 이유: po 머리는 PostgREST 직접 쓰기(po.html saveHead) · po_invoice 머리도 같다(invoices.html data-head) · 줄 둘은 창구가 쓰지만 같은 검사를 창구마다 다시 적지 않는다(식 한 곳)
--   ③ backfill — po.tax_rule 원문 29행 이름 → id(풀리지 않는 이름이 있으면 멈춘다) · po_invoice 는 줄이 가리키는 PO 의 규칙이 하나면 그것 · 아니면 공급처 규칙 이름 → id(po-tax-1 §0-4 · 지시서 밖 · 없으면 모든 기존 장에 tax_rule_missing)
--   ④ 식 한 곳 — 뷰 po_tax_group(규칙 묶음마다 한 행 · doc_kind po|invoice) · 줄 세금은 so_tax_amount(amount, rate_pct) 재사용(같은 식 · round(a × r/100, 2) · 이름만 SO)
--      묶음 세금 = Σ줄 round(줄 × rate) − round(묶음 할인 × rate) · 묶음 할인 = goods_in_rule − round(goods_in_rule × factor, 2) · other/charge 줄은 체인 없이 줄마다 · payable 변형(payable 줄만)
--      ⚠️ 돈(세금 전 · computed_total 의 앞부분)은 그대로 문서 전체에 한 번 round(goods_sum × factor, 2) + other_sum — 묶음이 둘이면 Σ묶음 taxable 과 1센트 갈릴 수 있다(세금만 묶음으로 · po-tax-1 §0-1)
--   ⑤ 재발행 — po_invoice_money(20260916190000:118 · 세금 · 세금 포함 · 뒤에 칸 아홉) · po_list(20260929190928 · 뒤에 넷) · po_detail(20260916190000:364) · po_invoice_detail(20260916210000:425) · po_invoice_list(20260916210000:379) ·
--      po_create(20260924001820:16) · po_invoice_create(20260924001820:256) · po_line_update(20260918000000:343) · po_invoice_line_add(20260918003000) · po_invoice_line_update(20260918003000) · po_invoice_add_po_lines(20260918003000)
--      시그니처 전부 그대로(create or replace · grant · comment 유지) · 반환은 열쇠만 더했다 · 뷰는 칸을 뒤에만
--   ⑥ 실물 확인 do 블록 — 어긋나면 전부 되돌린다

-- ═══ ① 칸 · 인덱스 · 주석 (CHECK 는 ③ backfill 뒤) ═══
alter table public.po
  add column if not exists tax_rule_id uuid references public.ref_tax_rule (id) on delete no action;        -- ⭐ FK + 원문(tax_rule) 짝 · 머리 규칙 · 줄 null = 이것
alter table public.po_line
  add column if not exists tax_rule_id uuid references public.ref_tax_rule (id) on delete no action;        -- 줄 예외만(null = 머리)
alter table public.po_invoice
  add column if not exists tax_rule    text,
  add column if not exists tax_rule_id uuid references public.ref_tax_rule (id) on delete no action;        -- 만들 때 원천(PO → credit_for 인보이스 → 공급처)에서 복사 · 초안에서 사람이 바꾼다
alter table public.po_invoice_line
  add column if not exists tax_rule    text,
  add column if not exists tax_rule_id uuid references public.ref_tax_rule (id) on delete no action;        -- 줄 예외만(null = 머리) · PO 줄 규칙을 물려받는다
create index if not exists po_tax_rule_idx              on public.po (tax_rule_id);
create index if not exists po_line_tax_rule_idx         on public.po_line (tax_rule_id);
create index if not exists po_invoice_tax_rule_idx      on public.po_invoice (tax_rule_id);
create index if not exists po_invoice_line_tax_rule_idx on public.po_invoice_line (tax_rule_id);

comment on column public.po.tax_rule_id              is 'po-tax-1 ⭐ 세금 규칙 FK → ref_tax_rule(id · direction purchase · 활성) · 원문 tax_rule 과 짝 CHECK po_tax_rule_pair_ck · 짝 트리거 po_tax_rule_pair 가 한쪽을 주면 다른 쪽을 채운다 · po_create 가 공급처 규칙 이름을 풀어 넣는다(못 풀면 둘 다 null + 경고 tax_rule_unknown) · 줄(po_line.tax_rule_id) null = 이것을 따른다 · 2026-10-08';
comment on column public.po.tax_rule                 is 'po-tax-1 — 문서 기본 세금규칙 이름(ref_tax_rule.name 원문 · FK tax_rule_id 와 짝) · po_create 가 supplier.tax_rule 을 그날 값으로 복사한다 · ⭐ 줄(po_line.tax_rule)이 null 이면 이것을 따르고 값이 있으면 줄이 덮는다 · 세금 계산은 뷰 po_tax_group(줄마다 반올림 · 할인 줄 한 번 · 규칙 묶음) — 예상 금액 · 원가에는 안 들어간다 · PostgREST 로 이름을 쓰면 트리거가 id 를 풀고 purchase · 활성이 아니면 거부 · 2026-10-08(옛 「계산 없음 · ref_tax_rule 미결」 2026-09-16 을 대신한다)';
comment on column public.po.tax_inclusive            is 'po-tax-1 — 기록만 · default false · [실측 2026-10-08] 37 행 전부 false · 규칙 14 전부 inclusive false · 세금 포함 단가 공급처 실물 없음 ⇒ 계산은 늘 세금 별도(exclusive) · true 면 po_detail 경고 tax_inclusive_not_supported(막지 않는다 · 포함 계산 갈래는 실물이 나오면)';
comment on column public.po_line.tax_rule_id         is 'po-tax-1 — 줄 예외 규칙 FK(null = 머리 po.tax_rule_id 를 따른다 · 면세 품목 등) · 원문 tax_rule 과 짝 CHECK po_line_tax_rule_pair_ck · 트리거 po_tax_rule_pair · po_line_update 열쇠 tax_rule(이름) · tax_rule_id · "" = 머리로 되돌림 · 인보이스 줄이 만들 때 물려받는다 · 2026-10-08';
comment on column public.po_line.tax_rule            is 'po-tax-1 — 줄 예외 규칙 이름(ref_tax_rule.name 원문 · FK tax_rule_id 와 짝) · null = 머리를 따른다 · [실측 2026-10-08] 95 행 전부 null · 2026-10-08(옛 「product.purchase_tax_rule 을 복사 제안」은 쓰지 않는다 — 출처는 공급처 → PO 머리)';
comment on column public.po_invoice.tax_rule_id      is 'po-tax-1 ⭐ 인보이스 · 크레딧 머리 규칙 FK(purchase · 활성) · 원문 tax_rule 과 짝 CHECK po_invoice_tax_rule_pair_ck · 트리거 po_tax_rule_pair · po_invoice_create 가 원천(PO → credit_for 인보이스 → 공급처 이름)에서 복사 · 초안에서 사람이 바꾼다(PostgREST 이름 쓰기) · 확정 뒤 잠금은 창구 선(줄 · 할인과 같다 · 머리 PostgREST 쓰기는 화면이 draft 만 연다) · 줄 null = 이것 · 세금은 뷰 po_tax_group → po_invoice_money(저장하지 않는다 · rate_pct 불변 트리거가 재현을 보장) · 2026-10-08';
comment on column public.po_invoice.tax_rule         is 'po-tax-1 — 머리 규칙 이름(원문 · FK 와 짝) · 2026-10-08';
comment on column public.po_invoice_line.tax_rule_id is 'po-tax-1 — 줄 예외 규칙 FK(null = 머리) · 짝 CHECK po_invoice_line_tax_rule_pair_ck · 트리거 po_tax_rule_pair · 만들 때 PO 줄(po_line.tax_rule_id)을 물려받는다 · charge · other 줄도 머리 규칙(국내 운임 HST — 다르면 줄에서) · po_invoice_line_add/_update 열쇠 tax_rule · tax_rule_id · 2026-10-08';
comment on column public.po_invoice_line.tax_rule    is 'po-tax-1 — 줄 예외 규칙 이름(원문 · FK 와 짝) · null = 머리 · 2026-10-08';
comment on column public.po_invoice.total_amount     is '⭐ 인보이스에 찍힌 총액(인보이스 통화 · ⭐ 세금 포함 — 공급처가 찍은 그대로) — 정본(§3-b 「인보이스 금액이 정본이라 장부는 맞는다」). 대조값 = 줄 합(체인 뒤) + 계산한 세금(po_invoice_money.computed_total · po-tax-1) · 다르면 입력 오류 · 반올림 · 규칙 다름 — 경고 total_differs_from_lines(막지 않는다). 두 곳에 적는 것이 아니라 대조값이다. CHECK 없음 · 크레딧은 doc_kind credit 의 양수 금액(§11-g 크레딧 노트 · 2026-09-16 「음수 인보이스(짐작)」 정정 · po-tax-1 2026-10-08)';

-- ═══ ② 짝 트리거 — 네 표 하나의 함수 ═══
create or replace function public.po_tax_rule_pair() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_r        public.ref_tax_rule%rowtype;
  v_by_id    boolean;
  v_by_name  boolean;
begin
  -- po-tax-1 · 짝 트리거: id 가 오면 원문을 채우고 · 원문이 오면 id 를 푼다 · 둘 다 바뀌면 id 가 이긴다 · purchase 방향 · 활성 규칙만(아니면 읽을 문장으로 거부)
  if tg_op = 'INSERT' then
    v_by_id   := new.tax_rule_id is not null;
    v_by_name := (not v_by_id) and new.tax_rule is not null;
  else
    v_by_id   := new.tax_rule_id is distinct from old.tax_rule_id;
    v_by_name := (not v_by_id) and new.tax_rule is distinct from old.tax_rule;
  end if;
  if v_by_id then
    if new.tax_rule_id is null then
      new.tax_rule := null;
    else
      select * into v_r from public.ref_tax_rule r where r.id = new.tax_rule_id;
      if not found then raise exception 'Tax rule % does not exist — nothing was saved', new.tax_rule_id; end if;
      if v_r.direction <> 'purchase' or not v_r.is_active then
        raise exception 'Tax rule "%" is not an active purchase tax rule (direction %, active %) — pick a purchase rule from Settings › Tax rules — nothing was saved', v_r.name, v_r.direction, v_r.is_active;
      end if;
      new.tax_rule := v_r.name;
    end if;
  elsif v_by_name then
    if new.tax_rule is null then
      new.tax_rule_id := null;
    else
      select * into v_r from public.ref_tax_rule r where r.name = new.tax_rule;
      if not found then raise exception 'Tax rule "%" is not known — pick a purchase rule from Settings › Tax rules — nothing was saved', new.tax_rule; end if;
      if v_r.direction <> 'purchase' or not v_r.is_active then
        raise exception 'Tax rule "%" is not an active purchase tax rule (direction %, active %) — pick a purchase rule from Settings › Tax rules — nothing was saved', v_r.name, v_r.direction, v_r.is_active;
      end if;
      new.tax_rule_id := v_r.id;
    end if;
  end if;
  return new;
end;
$$;
comment on function public.po_tax_rule_pair() is 'po-tax-1 — po · po_line · po_invoice · po_invoice_line BEFORE INSERT OR UPDATE OF tax_rule_id, tax_rule · FK 와 원문을 짝으로 채운다(id → 이름 · 이름 → id · 둘 다 바뀌면 id) · purchase 방향 · 활성만(아니면 거부 — 비활성 규칙이 이미 적힌 행은 다른 칸을 고쳐도 안 걸린다: 바뀐 쪽만 본다) · PostgREST 직접 쓰기(po.html · invoices.html 머리)와 창구가 같은 검사를 지난다 · 2026-10-08';
revoke all on function public.po_tax_rule_pair() from public, anon;
create trigger po_tax_rule_pair              before insert or update of tax_rule_id, tax_rule on public.po              for each row execute function public.po_tax_rule_pair();
create trigger po_line_tax_rule_pair         before insert or update of tax_rule_id, tax_rule on public.po_line         for each row execute function public.po_tax_rule_pair();
create trigger po_invoice_tax_rule_pair      before insert or update of tax_rule_id, tax_rule on public.po_invoice      for each row execute function public.po_tax_rule_pair();
create trigger po_invoice_line_tax_rule_pair before insert or update of tax_rule_id, tax_rule on public.po_invoice_line for each row execute function public.po_tax_rule_pair();

-- ═══ ③ backfill — po 29 이름 → id · po_invoice 는 PO 규칙 하나 → 공급처 이름 · 풀리지 않는 po 원문이 있으면 멈춘다 · 그 뒤 짝 CHECK 넷 ═══
update public.po p set tax_rule_id = r.id
from public.ref_tax_rule r
where r.name = p.tax_rule and r.direction = 'purchase' and r.is_active and p.tax_rule is not null and p.tax_rule_id is null;
do $$
declare v_n int; v_names text;
begin
  select count(*), string_agg(distinct tax_rule, ' · ') into v_n, v_names from public.po where tax_rule is not null and tax_rule_id is null;
  if v_n > 0 then
    raise exception 'po-tax-1 backfill: % PO row(s) carry a tax rule name that is not an active purchase rule (%) — fix the names first — nothing was applied', v_n, v_names;
  end if;
end $$;
update public.po_invoice i set tax_rule_id = x.rule_id                                   -- 줄이 가리키는 PO 의 규칙이 하나면 그것
from (
  select il.po_invoice_id, min(p.tax_rule_id::text)::uuid as rule_id
  from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po p on p.id = pl.po_id
  where p.tax_rule_id is not null
  group by il.po_invoice_id
  having count(distinct p.tax_rule_id) = 1
) x
where x.po_invoice_id = i.id and i.tax_rule_id is null;
update public.po_invoice i set tax_rule_id = r.id                                        -- 아니면 공급처 규칙 이름(활성 purchase 만)
from public.supplier s join public.ref_tax_rule r on r.name = s.tax_rule and r.direction = 'purchase' and r.is_active
where s.id = i.supplier_id and i.tax_rule_id is null;
alter table public.po              add constraint po_tax_rule_pair_ck              check ((tax_rule_id is null) = (tax_rule is null));
alter table public.po_line         add constraint po_line_tax_rule_pair_ck         check ((tax_rule_id is null) = (tax_rule is null));
alter table public.po_invoice      add constraint po_invoice_tax_rule_pair_ck      check ((tax_rule_id is null) = (tax_rule is null));
alter table public.po_invoice_line add constraint po_invoice_line_tax_rule_pair_ck check ((tax_rule_id is null) = (tax_rule is null));
comment on constraint po_tax_rule_pair_ck              on public.po              is 'po-tax-1 — FK(tax_rule_id) 와 원문(tax_rule)은 함께 있거나 함께 없다 · 트리거 po_tax_rule_pair 가 채운다';
comment on constraint po_line_tax_rule_pair_ck         on public.po_line         is 'po-tax-1 — FK 와 원문은 함께 있거나 함께 없다(줄 예외 · null = 머리)';
comment on constraint po_invoice_tax_rule_pair_ck      on public.po_invoice      is 'po-tax-1 — FK 와 원문은 함께 있거나 함께 없다';
comment on constraint po_invoice_line_tax_rule_pair_ck on public.po_invoice_line is 'po-tax-1 — FK 와 원문은 함께 있거나 함께 없다(줄 예외 · null = 머리)';

-- ═══ ④ 식 한 곳 — 뷰 po_tax_group(규칙 묶음마다 한 행) ═══
-- 줄 세금 = so_tax_amount(줄 금액, rate_pct) = round(줄 × rate/100, 2)(SO 와 같은 함수 · 판정 3) · 묶음 할인 = goods − round(goods × factor, 2)(체인은 goods 에만 · §11-e) · 묶음 세금 = Σ줄 − round(할인 × rate)
-- rate 를 모르는 묶음(규칙 null)은 tax_amount null — 읽는 쪽이 tax_rule_missing 으로 알린다 · 묶음 금액 · 세금은 문서 통화 · 환산 없음
create view public.po_tax_group
  with (security_invoker = true) as
with po_l as (
  select 'po'::text as doc_kind, pl.po_id as doc_id, true as is_goods, true as is_payable,
         round(pl.qty_ea * pl.unit_price, 2) as amt, coalesce(pl.tax_rule_id, p.tax_rule_id) as rule_id
  from public.po_line pl join public.po p on p.id = pl.po_id
),
inv_l as (
  select 'invoice'::text, il.po_invoice_id, il.line_kind = 'goods', il.is_payable,
         round(il.qty_ea * il.unit_price, 2), coalesce(il.tax_rule_id, i.tax_rule_id)
  from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
),
l as (select * from po_l union all select * from inv_l),
f as (
  select 'po'::text as doc_kind, po_id as doc_id, public.po_mul(1 - percent / 100) as factor from public.po_discount group by po_id
  union all
  select 'invoice'::text, po_invoice_id, public.po_mul(1 - percent / 100) from public.po_invoice_discount group by po_invoice_id
),
g as (
  select l.doc_kind, l.doc_id, l.rule_id, r.name as tax_rule, r.rate_pct, coalesce(f.factor, 1) as factor,
         count(*)::int                                                                   as line_count,
         coalesce(sum(l.amt) filter (where l.is_goods), 0)                               as goods_amount,
         coalesce(sum(l.amt) filter (where not l.is_goods), 0)                           as other_amount,
         coalesce(sum(l.amt) filter (where l.is_goods and l.is_payable), 0)              as goods_payable,
         coalesce(sum(l.amt) filter (where not l.is_goods and l.is_payable), 0)          as other_payable,
         case when r.rate_pct is null then null else coalesce(sum(public.so_tax_amount(l.amt, r.rate_pct)), 0) end                                  as lines_tax,
         case when r.rate_pct is null then null else coalesce(sum(public.so_tax_amount(l.amt, r.rate_pct)) filter (where l.is_payable), 0) end      as payable_lines_tax
  from l
  left join public.ref_tax_rule r on r.id = l.rule_id
  left join f on f.doc_kind = l.doc_kind and f.doc_id = l.doc_id
  group by l.doc_kind, l.doc_id, l.rule_id, r.name, r.rate_pct, f.factor
)
select
  g.doc_kind, g.doc_id, g.rule_id as tax_rule_id, g.tax_rule, g.rate_pct, g.line_count,
  g.goods_amount, g.other_amount,
  g.goods_amount - round(g.goods_amount * g.factor, 2)                                                           as discount_amount,
  round(g.goods_amount * g.factor, 2) + g.other_amount                                                           as taxable_amount,
  g.lines_tax,
  public.so_tax_amount(g.goods_amount - round(g.goods_amount * g.factor, 2), g.rate_pct)                         as discount_tax,
  g.lines_tax - public.so_tax_amount(g.goods_amount - round(g.goods_amount * g.factor, 2), g.rate_pct)           as tax_amount,
  g.goods_payable, g.other_payable,
  g.goods_payable - round(g.goods_payable * g.factor, 2)                                                         as payable_discount,
  round(g.goods_payable * g.factor, 2) + g.other_payable                                                         as payable_taxable,
  g.payable_lines_tax - public.so_tax_amount(g.goods_payable - round(g.goods_payable * g.factor, 2), g.rate_pct) as payable_tax
from g;
comment on view public.po_tax_group is 'po-tax-1 ⭐⭐ 매입 세금 식의 정본 — 발주(doc_kind po · doc_id = po.id) · 인보이스 · 크레딧(invoice · po_invoice.id)의 규칙 묶음(같은 규칙의 줄)마다 한 행. 줄 규칙 = coalesce(줄, 머리) · 줄 세금 = so_tax_amount(round(qty×단가,2), rate_pct)(줄마다 반올림 · SO 와 같은 식 · Caleb 2026-10-08 모양 A) · 묶음 할인 = goods − round(goods × 체인 factor, 2)(체인은 goods 에만 · po_mul) · tax_amount = Σ줄 세금 − round(할인 × rate, 2) · payable_* 는 is_payable 줄만(인보이스 낼 돈 · 크레딧 뺄 돈 · PO 는 전부 payable) · 규칙을 모르는 묶음은 tax null(읽는 쪽 tax_rule_missing) · 문서 통화 · 환산 없음 · ⚠️ 돈의 세금 전 부분은 po_invoice_money · po_list 가 문서 전체에 한 번 round 한다(묶음 둘이면 Σ묶음 taxable 과 1센트 갈릴 수 있다 · 세금만 묶음) · po_invoice_money · po_list · po_detail · po_invoice_detail 이 읽는다 · security_invoker · 2026-10-08';
revoke all on public.po_tax_group from anon;
grant select on public.po_tax_group to authenticated;


-- ═══ ⑤-1 po_invoice_money 재발행 — 마지막 정의 20260916190000:118 · 세금 CTE t · 머리 규칙 · computed_total · payable_net 에 세금을 더한다 · 뒤에 아홉 칸 · 식의 정본 그대로 이 뷰 ═══
create or replace view public.po_invoice_money
  with (security_invoker = true) as
with l as (
  select po_invoice_id,
         count(*)::int                                                                                       as line_count,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind = 'goods'), 0)                  as goods_sum,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind <> 'goods'), 0)                 as other_sum,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind = 'goods' and is_payable), 0)   as goods_payable,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind <> 'goods' and is_payable), 0)  as other_payable
  from public.po_invoice_line
  group by po_invoice_id
),
d as (
  select po_invoice_id, public.po_mul(1 - percent / 100) as factor
  from public.po_invoice_discount
  group by po_invoice_id
),
a as (
  select po_invoice_id, coalesce(sum(amount), 0) as alloc_total
  from public.po_payment_alloc
  where po_invoice_id is not null
  group by po_invoice_id
),
t as (                                         -- po-tax-1 · 세금(뷰 po_tax_group · 규칙 묶음 합) · 규칙을 모르는 묶음이 하나라도 있으면 null(tax_rule_missing)
  select doc_id as po_invoice_id,
         count(*)::int                                                              as tax_rule_groups,
         bool_or(tax_rule_id is null)                                               as tax_rule_missing,
         case when bool_or(rate_pct is null) then null else sum(tax_amount) end     as tax_amount,
         case when bool_or(rate_pct is null) then null else sum(payable_tax) end    as payable_tax
  from public.po_tax_group
  where doc_kind = 'invoice'
  group by doc_id
),
base as (
  select i.id, i.doc_kind, i.status, i.credit_for_invoice_id, i.total_amount,
         i.tax_rule_id, i.tax_rule, r.rate_pct,                                      -- po-tax-1 · 머리 규칙
         coalesce(t.tax_rule_groups, 0)   as tax_rule_groups,
         coalesce(t.tax_rule_missing, false) as tax_rule_missing,
         t.tax_amount,
         t.payable_tax,
         coalesce(l.line_count, 0)     as line_count,
         coalesce(l.goods_sum, 0)      as goods_sum,
         coalesce(l.other_sum, 0)      as other_sum,
         coalesce(l.goods_payable, 0)  as goods_payable,
         coalesce(l.other_payable, 0)  as other_payable,
         coalesce(d.factor, 1)         as factor,
         coalesce(a.alloc_total, 0)    as alloc_total
  from public.po_invoice i
  left join l on l.po_invoice_id = i.id
  left join d on d.po_invoice_id = i.id
  left join a on a.po_invoice_id = i.id
  left join t on t.po_invoice_id = i.id
  left join public.ref_tax_rule r on r.id = i.tax_rule_id
),
calc as (
  select b.*,
         round(b.goods_sum * b.factor, 2) + b.other_sum                                       as taxable_amount,   -- po-tax-1 · 세금 전(옛 computed_total)
         round(b.goods_payable * b.factor, 2) + b.other_payable                               as payable_taxable,  -- po-tax-1 · 세금 전(옛 payable_net)
         round(b.goods_sum * b.factor, 2) + b.other_sum + coalesce(b.tax_amount, 0)           as computed_total,   -- po-tax-1 · + 세금(모르면 0 · tax_rule_missing)
         round(b.goods_payable * b.factor, 2) + b.other_payable + coalesce(b.payable_tax, 0)  as payable_net       -- po-tax-1 · 낼 돈(payable 줄 + 그 세금)
  from base b
),
cr as (                                        -- 인보이스에 붙은 크레딧의 뺄 돈 합 (취소 제외)
  select credit_for_invoice_id as invoice_id, coalesce(sum(payable_net), 0) as credit_total
  from calc
  where doc_kind = 'credit' and status <> 'cancelled' and credit_for_invoice_id is not null
  group by credit_for_invoice_id
)
select
  c.id, c.doc_kind, c.status, c.credit_for_invoice_id, c.total_amount,
  c.line_count, c.goods_sum, c.other_sum, c.goods_payable, c.other_payable,
  c.factor,                                                              -- ⚠️ 원래 factor(40자리까지) · 표시는 읽는 쪽이 round(…,6)
  c.computed_total,
  c.total_amount - c.computed_total                                      as diff,
  c.payable_net,
  c.alloc_total,
  case when c.doc_kind = 'invoice' then coalesce(cr.credit_total, 0) else 0 end                          as credit_total,
  case when c.doc_kind = 'invoice' then c.payable_net - c.alloc_total - coalesce(cr.credit_total, 0) end  as unpaid,
  case when c.doc_kind = 'credit' and c.credit_for_invoice_id is null then c.payable_net - c.alloc_total end as remaining,
  -- ── po-tax-1 · 뒤에 더한 아홉 칸 ──
  c.taxable_amount,                                                      -- 세금 전 계산값(= 옛 computed_total)
  c.tax_amount,                                                          -- 계산한 세금(문서 통화 · 규칙 모르면 null)
  c.payable_taxable,                                                     -- 세금 전 낼 돈(= 옛 payable_net)
  c.payable_tax,                                                         -- payable 줄의 세금
  c.tax_rule_id, c.tax_rule, c.rate_pct,                                 -- 머리 규칙(줄이 덮으면 묶음이 둘 이상)
  c.tax_rule_groups, c.tax_rule_missing
from calc c
left join cr on cr.invoice_id = c.id;
comment on view public.po_invoice_money is '⑤ 인보이스·크레딧 한 장의 돈 — ⭐⭐ 미지급 식의 정본(2026-09-16 · po_list 와 po_detail 이 같이 읽는다). 줄 금액 round(qty×단가,2) · 할인 체인은 goods 줄에만(po_mul) · ⭐ [po-tax-1 2026-10-08] 세금(뷰 po_tax_group · 줄마다 반올림 · 할인 줄 한 번 · 규칙 묶음)을 더했다 — computed_total = round(goods_sum×factor,2) + other_sum + tax_amount(규칙 모르면 0 · tax_rule_missing) = 찍힌 total_amount 의 대조값 · payable_net = payable 줄 합(체인 적용) + payable_tax = 낼 돈(크레딧: 뺄 돈 · 세금 포함) · unpaid = payable_net − 충당 − 붙은 크레딧 · 음수면 받을 돈 · remaining = 안 붙은 크레딧 · 뒤에 아홉 칸 taxable_amount(옛 computed_total) · tax_amount · payable_taxable(옛 payable_net) · payable_tax · tax_rule_id · tax_rule · rate_pct · tax_rule_groups · tax_rule_missing · 세금은 문서 통화 · factor 는 원래 값 — 표시는 읽는 쪽이 6자리로. security_invoker. 정본 po-module §13 · §11-g';

-- ═══ ⑤-2 po_list 재발행 — 마지막 정의 20260929190928 · CTE tx · 뒤에 네 칸(tax_rule_id · tax_rule · tax_amount · total_with_tax) · 앞 38 칸 무변 ═══
create or replace view public.po_list
  with (security_invoker = true) as
with l as (
  select po_id,
         count(*)::int                                      as line_count,
         coalesce(sum(qty_ea), 0)                           as ordered_qty,
         coalesce(sum(round(qty_ea * unit_price, 2)), 0)    as subtotal
  from public.po_line
  group by po_id
),
r as (
  select pl.po_id, coalesce(sum(rl.qty_ea), 0) as received_qty
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  group by pl.po_id
),
d as (
  select po_id, public.po_mul(1 - percent / 100) as factor
  from public.po_discount
  group by po_id
),
c as (
  select po_id, coalesce(sum(amount), 0) as charge_total
  from public.po_charge_alloc
  group by po_id
),
sp as (
  select split_from_id as po_id, count(*)::int as split_to_count
  from public.po
  where split_from_id is not null
  group by split_from_id
),
il as (
  select x.po_invoice_id, pl.po_id,
         coalesce(sum(x.qty_ea)                          filter (where x.line_kind = 'goods'), 0) as goods_qty,
         coalesce(sum(round(x.qty_ea * x.unit_price, 2)) filter (where x.line_kind = 'goods'), 0) as goods_amount
  from public.po_invoice_line x
  join public.po_line pl on pl.id = x.po_line_id
  group by x.po_invoice_id, pl.po_id
),
inv as (
  select x.po_id,
         count(*)::int                        as invoice_count,
         coalesce(sum(x.goods_qty), 0)        as invoiced_qty,
         coalesce(sum(x.goods_amount), 0)     as invoiced_total,
         coalesce(sum(m.alloc_total), 0)      as paid,
         coalesce(sum(m.unpaid), 0)           as unpaid
  from il x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_invoice_money m on m.id = i.id
  where i.doc_kind = 'invoice' and i.status <> 'cancelled'
  group by x.po_id
),
cred as (                                     -- 걸린 크레딧(줄 · credit_for) — ⚠️ credit_po_id 는 채번의 축이라 여기 안 센다(po_detail credits[] 와 같은 집합)
  select po_id, count(*)::int as credit_count
  from (
    select x.po_id, x.po_invoice_id as credit_id
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
    union
    select x.po_id, k.id
    from public.po_invoice k
    join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
  ) u
  group by po_id
),
chg as (
  select a.po_id,
         count(*)::int                 as charge_count,
         coalesce(sum(m.paid), 0)      as paid,
         coalesce(sum(m.unpaid), 0)    as unpaid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  where c.status <> 'cancelled'
  group by a.po_id
),
cinv as (                                     -- inv-basis-2 · 판정 88 ③: 확정 goods 인보이스 합(크레딧 · 초안 제외) — 입고 목록(오피스 · 창고)이 거르는 재료
  select pl.po_id, coalesce(sum(x.qty_ea), 0) as confirmed_invoiced_qty
  from public.po_invoice_line x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_line pl on pl.id = x.po_line_id
  where x.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'
  group by pl.po_id
),
tx as (                                       -- po-tax-1 · 예상 세금(뷰 po_tax_group · 규칙 묶음 합 · 규칙 모르는 묶음이 있으면 null)
  select doc_id as po_id, case when bool_or(rate_pct is null) then null else sum(tax_amount) end as tax_amount
  from public.po_tax_group
  where doc_kind = 'po'
  group by doc_id
),
nums as (                                     -- 검색용 문서 번호 모음(취소 포함) · ⭐ [2026-09-16 저녁] + 공급처 참조 번호 · 번호를 낸 발주 경로(줄 없는 크레딧도 그 발주에서 찾힌다)
  select po_id, string_agg(distinct num, ' ' order by num) as doc_numbers
  from (
    select x.po_id, k.invoice_number as num
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    union
    select x.po_id, k.invoice_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit'
    union
    select x.po_id, k.supplier_ref_number
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.supplier_ref_number is not null
    union
    select x.po_id, k.supplier_ref_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.supplier_ref_number is not null
    union
    select k.credit_po_id, k.invoice_number
    from public.po_invoice k where k.credit_po_id is not null
    union
    select k.credit_po_id, k.supplier_ref_number
    from public.po_invoice k where k.credit_po_id is not null and k.supplier_ref_number is not null
    union
    select a.po_id, c.charge_number
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
  ) u
  group by po_id
)
select
  p.id,
  p.po_number,
  p.status,
  p.order_date,
  p.supplier_id,
  s.name                                                       as supplier_name,
  cur.code                                                     as currency_code,
  coalesce(l.line_count, 0)                                    as line_count,
  coalesce(l.ordered_qty, 0)                                   as ordered_qty,
  coalesce(r.received_qty, 0)                                  as received_qty,
  coalesce(l.subtotal, 0)                                      as subtotal,
  round(coalesce(d.factor, 1), 6)                              as discount_factor,
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2)    as net_total,
  coalesce(c.charge_total, 0)                                  as charge_total,
  sf.po_number                                                 as split_from_number,
  coalesce(sp.split_to_count, 0)                               as split_to_count,
  p.confirmed_at,
  p.closed_at,
  p.cancelled_at,
  p.note,
  p.created_at,
  p.updated_at,
  p.required_by,
  coalesce(inv.invoice_count, 0)                               as invoice_count,
  coalesce(inv.invoiced_qty, 0)                                as invoiced_qty,
  coalesce(inv.invoiced_total, 0)                              as invoiced_total,
  coalesce(cred.credit_count, 0)                               as credit_count,
  coalesce(chg.charge_count, 0)                                as charge_count,
  coalesce(inv.paid, 0) + coalesce(chg.paid, 0)                as paid_total,
  coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0)            as unpaid_total,
  nums.doc_numbers,
  case when coalesce(l.line_count, 0) = 0                                                   then 'none'
       when p.status = 'draft' or (p.status = 'cancelled' and p.confirmed_at is null)       then 'partial'
       else 'done' end                                         as order_phase,
  case when coalesce(inv.invoiced_qty, 0) = 0                                               then 'none'
       when inv.invoiced_qty < coalesce(l.ordered_qty, 0)                                   then 'partial'
       else 'done' end                                         as invoice_phase,
  case when coalesce(r.received_qty, 0) = 0                                                 then 'none'
       when r.received_qty < coalesce(l.ordered_qty, 0)                                     then 'partial'
       else 'done' end                                         as receipt_phase,
  case when coalesce(chg.charge_count, 0) = 0                                               then 'none'
       else 'done' end                                         as charge_phase,
  case when coalesce(inv.invoice_count, 0) + coalesce(chg.charge_count, 0) = 0              then 'none'
       when coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0) > 0
            then case when coalesce(inv.paid, 0) + coalesce(chg.paid, 0) > 0 then 'partial' else 'none' end
       else 'done' end                                         as payment_phase,
  (cinv.po_id is not null)                                     as has_confirmed_invoice,     -- inv-basis-2 · 끝에 더한 두 칸(앞 36 칸 무변)
  coalesce(cinv.confirmed_invoiced_qty, 0)                     as confirmed_invoiced_qty,
  p.tax_rule_id,                                               -- po-tax-1 · 끝에 더한 네 칸(앞 38 칸 무변)
  p.tax_rule,
  tx.tax_amount,                                                                                       -- 예상 세금(문서 통화 · 규칙 모르면 null)
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2) + tx.tax_amount  as total_with_tax         -- 세금 포함 합계(예상 · 세금 모르면 null)
from public.po p
join public.supplier     s   on s.id   = p.supplier_id
join public.ref_currency cur on cur.id = p.currency_id
left join l    on l.po_id    = p.id
left join r    on r.po_id    = p.id
left join d    on d.po_id    = p.id
left join c    on c.po_id    = p.id
left join public.po sf on sf.id = p.split_from_id
left join sp   on sp.po_id   = p.id
left join inv  on inv.po_id  = p.id
left join cred on cred.po_id = p.id
left join chg  on chg.po_id  = p.id
left join nums on nums.po_id = p.id
left join cinv on cinv.po_id = p.id
left join tx   on tx.po_id   = p.id;
comment on view public.po_list is '⑤ 발주 목록 — PostgREST 로 표처럼 읽는다(§10-j 3-a). security_invoker. 기존 22칸(164539) + 넓은 목록 14칸(190000) + inv-basis-2 두 칸 그대로. ⭐ [po-tax-1 2026-10-08] 뒤에 네 칸 — tax_rule_id · tax_rule(머리 규칙) · tax_amount(예상 세금 · 뷰 po_tax_group · 줄마다 반올림 · 할인 줄 한 번 · 규칙 모르는 묶음이 있으면 null) · total_with_tax(net_total + tax_amount · 세금 모르면 null) · 세금은 문서 통화 · 원가 아님. 돈의 정본은 po_invoice_money · po_charge_money(unpaid_total · paid_total 은 문서 기준 — 세로로 더하면 두 번 센다). 정본 po-module §13 · §13-g';

-- ═══ ⑤-3 po_invoice_list 재발행 — 마지막 정의 20260916210000:379 · 뒤에 네 칸(tax_rule_id · tax_rule · taxable_amount · tax_amount) ═══
create or replace view public.po_invoice_list
  with (security_invoker = true) as
with pos as (
  select il.po_invoice_id,
         count(distinct pl.po_id)::int                                   as po_count,
         string_agg(distinct x.po_number, ' ' order by x.po_number)      as po_numbers
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  join public.po x on x.id = pl.po_id
  group by il.po_invoice_id
)
select
  i.id, i.doc_kind, i.invoice_number, i.invoice_date, i.due_date, i.status,
  i.supplier_id, s.name as supplier_name,
  i.currency_id, cur.code as currency_code, i.exchange_rate,
  i.payment_term_name,
  i.total_amount,
  round(m.factor, 6)      as discount_factor,
  m.computed_total, m.diff, m.payable_net,
  m.alloc_total,
  m.credit_total, m.unpaid, m.remaining,
  m.line_count,
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,
  i.credit_for_invoice_id, f.invoice_number as credit_for_number,
  i.confirmed_at, i.cancelled_at, i.note, i.created_at, i.updated_at,
  -- ── 새 3칸 (2026-09-16 저녁) ──
  i.supplier_ref_number,                              -- 공급처가 보내온 크레딧 노트 번호(참조) · 검색 .or 에 한 항 더
  i.credit_po_id,                                     -- 번호를 낸 발주(채번의 축)
  cp.po_number as credit_po_number,
  -- ── po-tax-1 · 뒤에 더한 네 칸 ──
  i.tax_rule_id, i.tax_rule,
  m.taxable_amount, m.tax_amount
from public.po_invoice i
join public.po_invoice_money m on m.id = i.id
join public.supplier s on s.id = i.supplier_id
join public.ref_currency cur on cur.id = i.currency_id
left join public.po_invoice f on f.id = i.credit_for_invoice_id
left join public.po cp on cp.id = i.credit_po_id
left join pos on pos.po_invoice_id = i.id;
comment on view public.po_invoice_list is '⑤ 인보이스·크레딧 목록 — PostgREST 로 표처럼(§10-j 3-a). 돈은 po_invoice_money(식 없음) · po_numbers = 줄이 가리키는 발주 번호 모음(검색) · credit_for_number · supplier_ref_number · credit_po_id · credit_po_number. ⭐ [po-tax-1 2026-10-08] 뒤에 네 칸 tax_rule_id · tax_rule(머리 규칙) · taxable_amount(세금 전 계산값) · tax_amount(계산한 세금 · 규칙 모르면 null) — computed_total · diff · payable_net 은 이제 세금 포함. security_invoker. 정본 po-module §13-h · §11-g';

-- ═══ ⑤-4 po_detail 재발행 — 마지막 정의 20260916190000:364 · header tax_rule_id · rate_pct · lines[].tax_rule_id · totals taxable_amount · tax_amount · total_with_tax · tax_groups · warnings[](tax_rule_missing · tax_inclusive_not_supported) · invoices[] · credits[] tax_amount ═══
create or replace function public.po_detail(p_po_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po where id = p_po_id
),
lines as (
  select pl.*,
         pr.sku,
         pr.name                                   as product_name,
         up.sku                                    as entered_unit_sku,
         coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = pl.id), 0) as received_qty,
         round(pl.qty_ea * pl.unit_price, 2)       as amount
  from public.po_line pl
  join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = pl.entered_unit_product_id
  where pl.po_id = p_po_id
),
disc as (
  select * from public.po_discount where po_id = p_po_id
),
tot as (
  select coalesce((select sum(amount) from lines), 0)                        as subtotal,
         coalesce((select public.po_mul(1 - percent / 100) from disc), 1)     as factor,
         coalesce((select sum(qty_ea) from lines), 0)                         as ordered_qty,
         coalesce((select sum(received_qty) from lines), 0)                   as received_qty,
         coalesce((select sum(amount) from public.po_charge_alloc where po_id = p_po_id), 0) as charge_total,
         (select case when bool_or(g.rate_pct is null) then null else sum(g.tax_amount) end
            from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id)   as tax_amount,        -- po-tax-1 · 예상 세금(규칙 모르는 묶음이 있으면 null)
         (select bool_or(g.tax_rule_id is null) from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id) as tax_rule_missing
),
txg as (                                      -- po-tax-1 · 규칙 묶음마다(화면이 「HST ON 13% 1,202.44 · Zero-rated 0.00」로 그린다)
  select * from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id
),
rcpt as (
  select rl.*, pl.line_no, pr.sku, b.name as bin_name, w.name as warehouse_name, st.name as received_by_name
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  join public.product pr on pr.id = pl.product_id
  join public.ref_bin b on b.id = rl.bin_id
  join public.ref_warehouse w on w.id = b.warehouse_id
  left join public.ims_staff st on st.id = rl.received_by
  where pl.po_id = p_po_id
),
inv_ids as (                                  -- 이 발주의 라인을 가리키는 문서(인보이스·크레딧 둘 다 · 줄 수준 · 머리에 PO 칸 없음)
  select distinct il.po_invoice_id
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  where pl.po_id = p_po_id
),
shares as (                                   -- ⭐ 캐럿용 — 문서 하나가 어느 발주에 몇 줄·몇 개·얼마(할인 전 줄 합)씩 걸렸나 (§11-g 인보이스 하나가 발주 둘에)
  select il.po_invoice_id, pl.po_id, x.po_number, x.status as po_status,
         count(*)::int                                                           as line_count,
         coalesce(sum(il.qty_ea) filter (where il.line_kind = 'goods'), 0)       as qty_ea,
         coalesce(sum(round(il.qty_ea * il.unit_price, 2)), 0)                   as amount
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  join public.po x on x.id = pl.po_id
  where il.po_invoice_id in (select po_invoice_id from inv_ids)
     or il.po_invoice_id in (select k.id from public.po_invoice k where k.doc_kind = 'credit' and k.credit_for_invoice_id in (select po_invoice_id from inv_ids))
  group by il.po_invoice_id, pl.po_id, x.po_number, x.status
),
cred as (                                     -- ⭐ 크레딧 — 이 발주의 라인을 가리키거나 · 이 발주의 인보이스를 가리키는(조정 크레딧 · 라인 없음) 것 · 돈은 po_invoice_money
  select c.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         f.invoice_number as credit_for_number,
         f.supplier_id    as credit_for_supplier_id,
         f.doc_kind       as credit_for_doc_kind,
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff, m.tax_amount,
         m.payable_net    as credit_net,
         m.alloc_total    as used,
         m.remaining,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = c.id and pl.po_id = p_po_id)::int                       as lines_for_this_po
  from public.po_invoice c
  join public.po_invoice_money m on m.id = c.id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  left join public.po_invoice f on f.id = c.credit_for_invoice_id
  where c.doc_kind = 'credit'
    and (c.id in (select po_invoice_id from inv_ids)
         or c.credit_for_invoice_id in (select po_invoice_id from inv_ids))
),
inv as (                                      -- 인보이스만 · 돈은 po_invoice_money(⭐ 식의 정본이 거기로 갔다)
  select i.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff, m.payable_net, m.tax_amount,
         m.alloc_total as paid,
         m.credit_total,
         m.unpaid,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = i.id and pl.po_id = p_po_id)::int                       as lines_for_this_po
  from public.po_invoice i
  join public.po_invoice_money m on m.id = i.id
  join public.supplier s on s.id = i.supplier_id
  join public.ref_currency cur on cur.id = i.currency_id
  where i.doc_kind = 'invoice'
    and i.id in (select po_invoice_id from inv_ids)
),
chg as (                                      -- 이 발주에 배분된 비용 · 돈은 po_charge_money
  select c.*, a.amount as alloc_amount, s.name as supplier_name, cur.code as currency_code,
         m.paid, m.unpaid, m.alloc_sum, m.unallocated
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  where a.po_id = p_po_id
),
pay as (                                      -- 이 발주의 인보이스에 걸린 결제 + 이 발주에 배분된 비용 문서에 걸린 결제 + 쓴 크레딧
  select pm.*, pa.amount as alloc_amount,
         case when pa.po_charge_id is not null then 'charge'
              when i.doc_kind = 'credit'        then 'credit'
              else 'invoice' end                                       as target_kind,
         coalesce(i.invoice_number, c.charge_number)                             as target_number,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_charge  c on c.id = pa.po_charge_id
  where pa.po_invoice_id in (select po_invoice_id from inv_ids)
     or pa.po_invoice_id in (select id from cred)
     or pa.po_charge_id  in (select id from chg)
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'po_number', p.po_number, 'status', p.status, 'order_date', p.order_date,
      'required_by', p.required_by,                                                                  -- ⭐ 새
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'currency_id', p.currency_id, 'currency_code', cur.code, 'exchange_rate', p.exchange_rate,   -- currency_id 새(편집용)
      'payment_term_id', p.payment_term_id,                                                          -- 새(편집용)
      'payment_term_name', coalesce(p.payment_term_name, pt.name),
      'ship_to_warehouse_id', p.ship_to_warehouse_id,                                                -- 새(편집용)
      'ship_to_warehouse', w.name,
      'tax_rule', p.tax_rule, 'tax_inclusive', p.tax_inclusive,                                      -- ⭐ 새 · 줄 tax_rule null = 이것을 따른다
      'tax_rule_id', p.tax_rule_id, 'rate_pct', tr.rate_pct,                                        -- po-tax-1 · FK · 머리 세율
      'inventory_account_id', p.inventory_account_id, 'inventory_account_code', p.inventory_account_code,
      'inventory_account_name', ia.name,                                                             -- ⭐ 새
      'supplier_contact_name', p.supplier_contact_name, 'supplier_contact_phone', p.supplier_contact_phone,
      'supplier_contact_email', p.supplier_contact_email,                                            -- ⭐ 새 · 그날의 연락처
      'supplier_address_line1', p.supplier_address_line1, 'supplier_address_line2', p.supplier_address_line2,
      'supplier_city', p.supplier_city, 'supplier_state_province', p.supplier_state_province,
      'supplier_postal_code', p.supplier_postal_code, 'supplier_country', p.supplier_country,       -- ⭐ 새 · 그날의 주소
      'split_from_number', sf.po_number,
      'split_to', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'po_number', x.po_number, 'status', x.status) order by x.po_number)
                             from public.po x where x.split_from_id = p.id), '[]'::jsonb),
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', p.confirmed_at, 'closed_at', p.closed_at, 'cancelled_at', p.cancelled_at,
      'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.supplier s on s.id = p.supplier_id
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_payment_term pt on pt.id = p.payment_term_id
    left join public.ref_warehouse w on w.id = p.ship_to_warehouse_id
    left join public.ref_account ia on ia.id = p.inventory_account_id
    left join public.ref_tax_rule tr on tr.id = p.tax_rule_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = p.created_by
    left join public.ims_staff fb on fb.id = p.confirmed_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'product_id', product_id, 'sku', sku, 'product_name', product_name,
      'supplier_sku', supplier_sku, 'qty_ea', qty_ea, 'received_qty', received_qty,
      'remaining_qty', qty_ea - received_qty,
      'entered_unit_sku', entered_unit_sku, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'tax_rule', tax_rule, 'tax_rule_id', tax_rule_id, 'note', note) order by line_no)   -- tax_rule null = 머리를 따른다 · po-tax-1 tax_rule_id
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'seq', seq, 'name', name, 'percent', percent,
                                        'supplier_discount_id', supplier_discount_id, 'note', note) order by seq)
    from disc), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'subtotal', subtotal,
      'discount_factor', round(factor, 6),
      'discount_amount', round(subtotal - subtotal * factor, 2),
      'net_total', round(subtotal * factor, 2),
      'charge_total', charge_total,
      'ordered_qty', ordered_qty,
      'received_qty', received_qty,
      -- ── po-tax-1 · 예상 세금(문서 통화 · 원가 아님) ──
      'taxable_amount', round(subtotal * factor, 2),
      'tax_amount', tax_amount,
      'total_with_tax', round(subtotal * factor, 2) + tax_amount,
      'tax_groups', coalesce((select jsonb_agg(jsonb_build_object('tax_rule_id', g.tax_rule_id, 'tax_rule', g.tax_rule, 'rate_pct', g.rate_pct, 'line_count', g.line_count,
                                                                  'taxable_amount', g.taxable_amount, 'discount_amount', g.discount_amount, 'tax_amount', g.tax_amount)
                                               order by g.tax_rule nulls last) from txg g), '[]'::jsonb))
    from tot
  ),
  'warnings', (                                 -- po-tax-1 · 규칙 없는 줄 · 세금 포함 단가 표시
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select tax_rule_missing from tot) then 'tax_rule_missing' end,
        case when (select tax_inclusive from p) then 'tax_inclusive_not_supported' end
      ], null)) as w) t
  ),
  'receipts', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'po_line_id', po_line_id, 'line_no', line_no, 'sku', sku,
      'received_on', received_on, 'received_by_name', received_by_name,
      'bin_name', bin_name, 'warehouse_name', warehouse_name, 'qty_ea', qty_ea, 'note', note)
      order by received_on, line_no, bin_name)
    from rcpt), '[]'::jsonb),
  'invoices', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'invoice_number', invoice_number, 'invoice_date', invoice_date, 'due_date', due_date, 'status', status,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),
      'total_amount', total_amount,
      'computed_total', computed_total,
      'diff', diff,
      'payable_net', payable_net,
      'tax_amount', tax_amount,                                                            -- po-tax-1
      'paid', paid,
      'credit_total', credit_total,
      'unpaid', unpaid,                                                                    -- 음수면 받을 돈(credit due)
      -- ⭐ 캐럿 — 이 인보이스가 걸린 발주 전부(이 발주 포함) · amount 는 할인 전 줄 합(할인은 문서 단위라 발주 몫으로 안 내린다)
      'po_shares', coalesce((select jsonb_agg(jsonb_build_object('po_id', sh.po_id, 'po_number', sh.po_number, 'po_status', sh.po_status,
                                                                 'line_count', sh.line_count, 'qty_ea', sh.qty_ea, 'amount', sh.amount) order by sh.po_number)
                             from shares sh where sh.po_invoice_id = inv.id), '[]'::jsonb))
      order by invoice_date, invoice_number)
    from inv), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status,
      'credit_for_invoice_id', credit_for_invoice_id, 'credit_for_number', credit_for_number,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),
      'total_amount', total_amount,
      'computed_total', computed_total,
      'diff', diff,
      'credit_net', credit_net,
      'tax_amount', tax_amount,                                                            -- po-tax-1
      'used', used,
      'remaining', remaining,                                                              -- 안 붙은 크레딧만 · 붙은 것은 null
      'warnings', (select coalesce(jsonb_agg(w), '[]'::jsonb) from unnest(array_remove(array[
                    case when credit_for_invoice_id is not null and used > 0 then 'attached_and_used' end,
                    case when credit_for_doc_kind = 'credit' then 'credit_for_is_credit' end,
                    case when credit_for_supplier_id is not null and credit_for_supplier_id <> supplier_id then 'credit_for_other_supplier' end
                  ], null)) as w),
      -- ⭐ 캐럿 — 크레딧 줄이 걸린 발주 전부(조정 크레딧은 줄이 없어 빈 배열)
      'po_shares', coalesce((select jsonb_agg(jsonb_build_object('po_id', sh.po_id, 'po_number', sh.po_number, 'po_status', sh.po_status,
                                                                 'line_count', sh.line_count, 'qty_ea', sh.qty_ea, 'amount', sh.amount) order by sh.po_number)
                             from shares sh where sh.po_invoice_id = cred.id), '[]'::jsonb))
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'charges', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'charge_number', charge_number, 'kind', kind, 'description', description, 'charge_date', charge_date,
      'status', status, 'supplier_name', supplier_name, 'currency_code', currency_code,
      'total_amount', total_amount,
      'alloc_amount', alloc_amount,                                                        -- 이 발주에 박힌 배분
      'paid', paid,
      'unpaid', unpaid,                                                                    -- 문서 전체 기준
      'unallocated', unallocated,                                                          -- 총액 − 배분 합 · 0 이 정상
      -- ⭐ 캐럿 — 그 청구서의 배분 전부(이 발주 포함) · [실물] CBSA 2,547.37 = PO-02001a 597.49 + PO-02002 1,949.88
      'allocs', coalesce((select jsonb_agg(jsonb_build_object('po_id', a.po_id, 'po_number', x.po_number, 'po_status', x.status, 'amount', a.amount) order by x.po_number)
                          from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = chg.id), '[]'::jsonb))
      order by charge_date, charge_number)
    from chg), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'paid_on', paid_on, 'reference', reference,
      'target_kind', target_kind, 'target_number', target_number, 'alloc_amount', alloc_amount,
      'amount', amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
      'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb)
) end;
$$;
comment on function public.po_detail(uuid) is '⑤ 발주 상세 — jsonb 하나(header · lines · discounts · totals · receipts · invoices · credits · charges · payments · ⭐ warnings). 발주 쪽 계산(할인 체인 po_mul · 라인 round(qty×단가,2) · 입고 줄 합)은 여기 · 인보이스·크레딧·비용 한 장의 돈은 po_invoice_money · po_charge_money. ⭐ [po-tax-1 2026-10-08] 예상 세금(원가 아님 · 문서 통화): header tax_rule_id · rate_pct · lines[].tax_rule_id(null = 머리) · totals taxable_amount(= net_total) · tax_amount(뷰 po_tax_group 묶음 합 · 규칙 모르면 null) · total_with_tax · tax_groups[](규칙마다 taxable · 할인 · 세금) · warnings[] tax_rule_missing(규칙 모르는 줄) · tax_inclusive_not_supported(기록 칸이 true · 계산은 세금 별도) · invoices[] · credits[] 에 tax_amount. 캐럿 — invoices[].po_shares · credits[].po_shares · charges[].allocs. security invoker. 정본 po-module §13 · §11-e·f·g';

-- ═══ ⑤-5 po_invoice_detail 재발행 — 마지막 정의 20260916210000:425 · header 규칙 셋 · money 세금 여섯 + tax_groups[] · lines[] 줄 규칙 · 적용 규칙 · 줄 세금 · warnings tax_rule_missing ═══
create or replace function public.po_invoice_detail(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with i as (
  select * from public.po_invoice where id = p_invoice_id
),
m as (
  select * from public.po_invoice_money where id = p_invoice_id
),
lines as (
  select il.*,
         pl.po_id, x.po_number, pl.line_no as po_line_no, pl.qty_ea as po_qty_ea, pl.unit_price as po_unit_price,
         pr.sku, pr.name as product_name, up.sku as entered_unit_sku,
         round(il.qty_ea * il.unit_price, 2) as amount,
         tr.name as tax_rule_effective, tr.rate_pct,                                                     -- po-tax-1 · coalesce(줄, 머리)
         public.so_tax_amount(round(il.qty_ea * il.unit_price, 2), tr.rate_pct) as tax_amount,          -- po-tax-1 · 줄 세금(할인 줄은 묶음에서 뺀다 · money.tax_groups)
         case when il.po_line_id is not null
              then coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) end as received_qty,
         case when il.po_line_id is not null
              then coalesce((select sum(x2.qty_ea) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
                              where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                                and i2.id <> p_invoice_id), 0) end as other_invoiced_qty
  from public.po_invoice_line il
  left join public.po_line pl on pl.id = il.po_line_id
  left join public.po x on x.id = pl.po_id
  left join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = il.entered_unit_product_id
  left join public.ref_tax_rule tr on tr.id = coalesce(il.tax_rule_id, (select tax_rule_id from i))
  where il.po_invoice_id = p_invoice_id
),
shares as (
  select l.po_id, l.po_number, x.status as po_status, count(*)::int as line_count,
         coalesce(sum(l.qty_ea) filter (where l.line_kind = 'goods'), 0) as qty_ea,
         coalesce(sum(l.amount), 0) as amount
  from lines l join public.po x on x.id = l.po_id
  where l.po_id is not null
  group by l.po_id, l.po_number, x.status
),
cred as (
  select c.id, c.invoice_number, c.invoice_date, c.status, c.total_amount, c.supplier_ref_number, cm.payable_net as credit_net, cm.alloc_total as used
  from public.po_invoice c join public.po_invoice_money cm on cm.id = c.id
  where c.credit_for_invoice_id = p_invoice_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_invoice_id = p_invoice_id
)
select case when not exists (select 1 from i) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', i.id, 'doc_kind', i.doc_kind, 'invoice_number', i.invoice_number, 'invoice_date', i.invoice_date, 'due_date', i.due_date, 'status', i.status,
      'supplier_ref_number', i.supplier_ref_number,                                          -- ⭐ 새 · 공급처가 보내온 크레딧 노트 번호(참조) · PostgREST 로 고친다
      'credit_po_id', i.credit_po_id, 'credit_po_number', cp.po_number,                     -- ⭐ 새 · 번호를 낸 발주
      'supplier_id', i.supplier_id, 'supplier_name', s.name,
      'currency_id', i.currency_id, 'currency_code', cur.code, 'exchange_rate', i.exchange_rate,
      'payment_term_id', i.payment_term_id, 'payment_term_name', coalesce(i.payment_term_name, pt.name),
      'total_amount', i.total_amount,
      'tax_rule_id', i.tax_rule_id, 'tax_rule', i.tax_rule, 'rate_pct', m.rate_pct,          -- po-tax-1 · 머리 규칙(초안에서 PostgREST 로 이름을 고친다)
      'credit_for_invoice_id', i.credit_for_invoice_id, 'credit_for_number', f.invoice_number, 'credit_for_status', f.status,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', i.confirmed_at, 'cancelled_at', i.cancelled_at, 'note', i.note, 'created_at', i.created_at, 'updated_at', i.updated_at)
    from i
    cross join m
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    left join public.ref_payment_term pt on pt.id = i.payment_term_id
    left join public.po_invoice f on f.id = i.credit_for_invoice_id
    left join public.po cp on cp.id = i.credit_po_id
    left join public.ims_staff cb on cb.id = i.created_by
    left join public.ims_staff fb on fb.id = i.confirmed_by
  ),
  'money', (
    select jsonb_build_object(
      'line_count', m.line_count, 'goods_sum', m.goods_sum, 'other_sum', m.other_sum, 'goods_payable', m.goods_payable, 'other_payable', m.other_payable,
      'discount_factor', round(m.factor, 6),
      'computed_total', m.computed_total, 'diff', m.diff,
      'payable_net', m.payable_net,
      'alloc_total', m.alloc_total,
      'credit_total', m.credit_total, 'unpaid', m.unpaid, 'remaining', m.remaining,
      -- ── po-tax-1 · 세금(문서 통화 · 규칙 모르면 null + 경고 tax_rule_missing) ──
      'taxable_amount', m.taxable_amount, 'tax_amount', m.tax_amount,
      'payable_taxable', m.payable_taxable, 'payable_tax', m.payable_tax,
      'tax_rule_groups', m.tax_rule_groups,
      'tax_groups', coalesce((select jsonb_agg(jsonb_build_object('tax_rule_id', g.tax_rule_id, 'tax_rule', g.tax_rule, 'rate_pct', g.rate_pct, 'line_count', g.line_count,
                                                                  'taxable_amount', g.taxable_amount, 'discount_amount', g.discount_amount, 'lines_tax', g.lines_tax,
                                                                  'discount_tax', g.discount_tax, 'tax_amount', g.tax_amount, 'payable_taxable', g.payable_taxable, 'payable_tax', g.payable_tax)
                                               order by g.tax_rule nulls last)
                               from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id), '[]'::jsonb))
    from m
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'line_kind', line_kind, 'po_line_id', po_line_id, 'po_id', po_id, 'po_number', po_number, 'po_line_no', po_line_no,
      'sku', sku, 'product_name', product_name, 'description', description,
      'qty_ea', qty_ea, 'entered_unit_sku', entered_unit_sku, 'entered_unit_product_id', entered_unit_product_id, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'is_payable', is_payable, 'note', note,
      'tax_rule_id', tax_rule_id, 'tax_rule', tax_rule, 'tax_rule_effective', tax_rule_effective, 'rate_pct', rate_pct, 'tax_amount', tax_amount,   -- po-tax-1 · 줄 규칙(null = 머리) · 적용 규칙 · 줄 세금
      'po_qty_ea', po_qty_ea, 'po_unit_price', po_unit_price,
      'received_qty', received_qty, 'other_invoiced_qty', other_invoiced_qty,
      'qty_diff', case when line_kind = 'goods' then qty_ea - received_qty end)
      order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq, 'name', d.name, 'percent', d.percent, 'supplier_discount_id', d.supplier_discount_id, 'note', d.note) order by d.seq)
    from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), '[]'::jsonb),
  'po_shares', coalesce((
    select jsonb_agg(jsonb_build_object('po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'line_count', line_count, 'qty_ea', qty_ea, 'amount', amount) order by po_number)
    from shares), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status, 'total_amount', total_amount,
                                        'supplier_ref_number', supplier_ref_number,                                   -- ⭐ 새
                                        'credit_net', credit_net, 'used', used)
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when i.doc_kind = 'credit' and i.credit_for_invoice_id is not null and m.alloc_total > 0 then 'attached_and_used' end,
        case when f.doc_kind = 'credit' then 'credit_for_is_credit' end,
        case when f.supplier_id is not null and f.supplier_id <> i.supplier_id then 'credit_for_other_supplier' end,
        case when i.total_amount = 0 then 'total_amount_zero' end,
        case when m.diff <> 0 then 'total_differs_from_lines' end,
        case when m.line_count = 0 then 'no_lines' end,
        case when m.tax_rule_missing then 'tax_rule_missing' end                                 -- po-tax-1 · 규칙 모르는 줄이 있다(세금 0 으로 더했다)
      ], null)) as w
      from i cross join m left join public.po_invoice f on f.id = i.credit_for_invoice_id) t
  )
) end;
$$;
comment on function public.po_invoice_detail(uuid) is '⑤ 인보이스·크레딧 상세 — 한 장을 깊게(invoices.html). header · money(po_invoice_money 그대로) · lines[](발주 대조 · qty_diff) · discounts[] · po_shares[] · credits[] · payments[] · warnings[]. ⭐ [po-tax-1 2026-10-08] header tax_rule_id · tax_rule · rate_pct(초안에서 PostgREST 로 이름을 고친다 · 짝 트리거) · money taxable_amount · tax_amount · payable_taxable · payable_tax · tax_rule_groups · tax_groups[](규칙마다 줄 세금 합 · 할인 세금 · 세금) · lines[] tax_rule_id · tax_rule(줄 예외 · null = 머리) · tax_rule_effective · rate_pct · tax_amount(줄마다 반올림 · 할인 줄 세금은 묶음에서) · warnings tax_rule_missing. computed_total · payable_net 은 세금 포함 · diff = 찍힌 총액 − computed_total. 정본 po-module §13-h · §11-g';

-- ═══ ⑤-6 po_create 재발행 — 마지막 정의 20260924001820:16 · 공급처 규칙 이름 → id(활성 purchase) · 못 풀면 둘 다 null + 경고 tax_rule_unknown:<원문>(막지 않는다 · Caleb 결정 1) · 반환 tax_rule_id ═══
create or replace function public.po_create(
  p_supplier_id  uuid,
  p_warehouse_id uuid default null,
  p_order_date   date default null,
  p_note         text default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_cur       uuid;
  v_wh        uuid;
  v_wh_n      int;
  v_ct        public.supplier_contact%rowtype;   -- 그날의 연락처
  v_ct_n      int;
  v_ct_def_n  int;
  v_ad        public.supplier_address%rowtype;   -- 그날의 주소
  v_ad_n      int;
  v_ad_bil_n  int;
  v_acct_code text;
  v_acct_id   uuid;
  v_tax_id    uuid;                               -- po-tax-1 · 공급처 규칙 이름 → id(활성 purchase 만 · 못 풀면 둘 다 null + 경고)
  v_tax_name  text;
  v_po_id     uuid;
  v_po_number text;
  v_disc      int := 0;
  v_warn      text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b: RLS 에 닿기 전에 읽을 수 있는 말로

  -- 만든 사람 — 서버 유도(§10-h 열쇠 auth_user_id) · 행이 없으면 아무것도 안 쓴다
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then
    raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
  end if;
  -- ⚠️ 비활성·미판정 공급처는 막지 않는다 — 판정은 화면의 정돈 규칙(§10-j 3-b) 한곳에. 여기서는 알리기만
  if not v_sup.is_active then v_warn := array_append(v_warn, 'supplier_inactive'); end if;
  if v_sup.is_purchasable is distinct from true then v_warn := array_append(v_warn, 'supplier_not_purchasable'); end if;

  -- 통화 — 공급처 기본통화 · 없으면 inv_config.base_currency · 그것도 없으면 예외(po.currency_id 는 not null)
  v_cur := v_sup.currency_id;
  if v_cur is null then
    select c.id into v_cur
    from public.ref_currency c
    join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
    if v_cur is null then
      raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
    end if;
    v_warn := array_append(v_warn, 'currency_defaulted');
  end if;

  -- 창고 — 준 것 · 아니면 기본 창고가 정확히 하나일 때만(짐작으로 고르지 않는다)
  v_wh := p_warehouse_id;
  if v_wh is null then
    select count(*), (array_agg(w.id))[1] into v_wh_n, v_wh
    from public.ref_warehouse w where w.is_default and w.is_active;
    if coalesce(v_wh_n, 0) <> 1 then
      v_wh := null;
      v_warn := array_append(v_warn, 'warehouse_unset');
    end if;
  end if;

  -- ⭐ 그날의 연락처 — 활성 중 is_default 가 정확히 하나면 그것 · 아니면 활성이 정확히 하나면 그것 · 그 외 null + 경고
  --    [실측 2026-09-16] 활성 226 중 기본 정확히 하나 159 · 기본 없이 하나 20 · 0건 44 ⇒ 179 곳을 덮는다
  select count(*), count(*) filter (where c.is_default) into v_ct_n, v_ct_def_n
  from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  if v_ct_def_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active and c.is_default;
  elsif v_ct_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  elsif v_ct_n = 0 then
    v_warn := array_append(v_warn, 'contact_unset');
  else
    v_warn := array_append(v_warn, 'contact_ambiguous');
  end if;

  -- ⭐ 그날의 주소 — 활성 1건이면 그것 · 여럿이면 Billing 이 정확히 하나면 그것 · 그 외 null + 경고 (§3-b B 규칙 · DefaultForType 은 안 담았다)
  --    ⚠️ [실측] 활성 226 중 주소 0건 143 ⇒ address_unset 이 대다수에서 뜬다 — 화면이 오류처럼 그리면 안 된다(말만)
  select count(*), count(*) filter (where a.type = 'Billing') into v_ad_n, v_ad_bil_n
  from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  if v_ad_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  elsif v_ad_n > 1 and v_ad_bil_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active and a.type = 'Billing';
  elsif v_ad_n = 0 then
    v_warn := array_append(v_warn, 'address_unset');
  else
    v_warn := array_append(v_warn, 'address_ambiguous');
  end if;

  -- 세금규칙 — 공급처 원문 그대로(실측 226/226 채움 · 비어 있으면 알리기만)
  if v_sup.tax_rule is null then v_warn := array_append(v_warn, 'tax_rule_unset'); end if;
  -- po-tax-1 · 이름 → id(활성 purchase 규칙만) · 못 풀면 머리를 비우고 알린다(막지 않는다 · 짝 트리거가 거부하기 전에 여기서 가른다)
  if v_sup.tax_rule is not null then
    select r.id, r.name into v_tax_id, v_tax_name from public.ref_tax_rule r where r.name = v_sup.tax_rule and r.direction = 'purchase' and r.is_active;
    if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_unknown:' || v_sup.tax_rule); end if;
  end if;

  -- ⭐ 재고 자산 계정 — inv_config po_inventory_account_code → ref_account.code (없으면 null + 경고 · 활성 여부는 안 본다 — 기본값이 비활성이면 그것이 보여야 한다)
  select k.value into v_acct_code from public.inv_config k where k.key = 'po_inventory_account_code';
  if v_acct_code is not null then
    select r.id into v_acct_id from public.ref_account r where r.code = v_acct_code;
  end if;
  if v_acct_id is null then
    v_acct_code := null;                                  -- 코드가 표에 없으면 원문도 박지 않는다(짐작 값을 남기지 않는다)
    v_warn := array_append(v_warn, 'inventory_account_unset');
  end if;

  -- ① po 한 행 — po_number 는 기본값 po_next_number() · 결제조건은 FK + 원문 · 연락처·주소는 원문만(그날 값)
  insert into public.po (status, supplier_id, currency_id, payment_term_id, payment_term_name, ship_to_warehouse_id, order_date, created_by, note,
                         tax_rule, tax_rule_id, inventory_account_id, inventory_account_code,
                         supplier_contact_name, supplier_contact_phone, supplier_contact_email,
                         supplier_address_line1, supplier_address_line2, supplier_city, supplier_state_province, supplier_postal_code, supplier_country)
  values ('draft', p_supplier_id, v_cur, v_sup.payment_term_id, v_sup.payment_term_name, v_wh, coalesce(p_order_date, public.ims_today()), v_staff, p_note,
          v_tax_name, v_tax_id, v_acct_id, v_acct_code,
          v_ct.name, v_ct.phone, v_ct.email,
          v_ad.line1, v_ad.line2, v_ad.city, v_ad.state_province, v_ad.postal_code, v_ad.country)
  returning id, po_number into v_po_id, v_po_number;

  -- ② supplier_discount → po_discount 복사(예상 층 · §11-e · 활성만 · seq 그대로 · 원천 id 를 남긴다) — 지금 0행 · 채우면 듣는다
  insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id)
  select v_po_id, d.seq, d.name, d.percent, d.id
  from public.supplier_discount d
  where d.supplier_id = p_supplier_id and d.is_active
  order by d.seq;
  get diagnostics v_disc = row_count;

  return jsonb_build_object(
    'id', v_po_id, 'po_number', v_po_number, 'status', 'draft',
    'currency_id', v_cur, 'ship_to_warehouse_id', v_wh, 'payment_term_name', v_sup.payment_term_name,
    'tax_rule', v_tax_name, 'tax_rule_id', v_tax_id, 'inventory_account_code', v_acct_code,       -- po-tax-1 · 푼 값(못 풀면 null · warnings tax_rule_unknown:<원문>)
    'supplier_contact_name', v_ct.name, 'supplier_contact_email', v_ct.email,
    'supplier_address_line1', v_ad.line1,
    'discounts_copied', v_disc,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤-7 po_invoice_create 재발행 — 마지막 정의 20260924001820:256 · 머리 규칙 복사(credit_for 인보이스 → PO → 공급처 이름) · 경고 tax_rule_missing · tax_rule_differs_between_pos(크레딧 축 PO) · 줄은 PO 줄 · 인보이스 줄 규칙을 물려받는다 · 반환 tax_rule_id · tax_rule ═══
create or replace function public.po_invoice_create(
  p_doc_kind              text,                       -- 'invoice' | 'credit'
  p_invoice_number        text    default null,       -- 인보이스: 필수(공급처 번호) · 크레딧: 안 주면 자동(우리 번호) · 주면 그대로
  p_po_id                 uuid    default null,       -- 인보이스: 필수 · 크레딧: 머리 원천 둘째 · 크레딧 번호의 축(credit_po_id)
  p_credit_for_invoice_id uuid    default null,       -- 크레딧만 · 있으면 줄 자동 채우기(차이) · 그 인보이스의 발주가 하나면 그것이 번호의 축
  p_supplier_id           uuid    default null,       -- 크레딧 머리 원천 셋째(조정 크레딧 · CN-<연도>-<n>)
  p_invoice_date          date    default null,       -- 안 주면 오늘 · 조정 번호의 연도
  p_due_date              date    default null,
  p_total_amount          numeric default null,       -- 찍힌 총액 · 안 주면 0 + 경고
  p_copy_discounts        boolean default true,       -- 인보이스만
  p_commit                boolean default false,      -- false = 미리 보기
  p_line_qty              jsonb   default null        -- ⭐ 새 · 인보이스만 · { "<po_line_id>": <qty_ea> } · null 이면 미청구 수량 전부(지금 그대로) · 키에 없는 라인·0 은 줄 없음('skipped')
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_num          text;
  v_num_src      text;
  v_kind_label   text;
  v_po           public.po%rowtype;
  v_for          public.po_invoice%rowtype;
  v_sup          public.supplier%rowtype;
  v_source       text;
  v_supplier_id  uuid;  v_currency_id uuid;  v_rate numeric;  v_pt_id uuid;  v_pt_name text;
  v_tax_id       uuid;  v_tax_name text;                                                                       -- po-tax-1 · 머리 규칙(원천과 같은 순서)
  v_sup_name     text;  v_cur_code text;
  v_credit_po_id uuid;  v_credit_po_number text;  v_po_n int;
  v_exists       int;
  v_inv_id       uuid;
  v_warn         text[] := '{}';
  v_lines        jsonb  := '[]'::jsonb;
  v_discs        jsonb  := '[]'::jsonb;
  v_n            int := 0;
  v_ins          int := 0;
  v_ok           int := 0;
  v_skip         int := 0;
  v_disc_n       int := 0;
  r              record;
  v_verdict      text;
  v_qty          numeric;
  v_req          numeric;
  v_full         boolean;
  v_msgs         text[];
  -- ⭐ p_line_qty
  v_use_qty      boolean := false;
  v_req_total    numeric;
  v_bad_n        int;
  v_bad_txt      text;
  v_keep_n       int;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_doc_kind not in ('invoice', 'credit') then
    raise exception 'p_doc_kind must be ''invoice'' or ''credit'' — nothing was saved';
  end if;
  v_kind_label := case p_doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := nullif(regexp_replace(coalesce(p_invoice_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if p_doc_kind = 'invoice' and v_num is null then
    raise exception 'Invoice number is required — it is the supplier''s number — nothing was saved';
  end if;

  -- ⭐ p_line_qty 는 인보이스만 — 크레딧에 주면 거부(조용히 무시하면 화면 실수를 덮는다)
  if p_line_qty is not null then
    if p_doc_kind <> 'invoice' then
      raise exception 'p_line_qty is for invoices only — a credit note is filled from invoice minus received — nothing was saved';
    end if;
    if jsonb_typeof(p_line_qty) <> 'object' then
      raise exception 'p_line_qty must be a JSON object { "<po_line_id>": qty } — nothing was saved';
    end if;
    v_use_qty := true;
  end if;

  -- ── 머리의 원천 (210000 그대로) ──
  if p_doc_kind = 'invoice' then
    if p_po_id is null then
      raise exception 'An invoice starts from a PO — p_po_id is required — nothing was saved';
    end if;
    if p_credit_for_invoice_id is not null then
      raise exception 'p_credit_for_invoice_id is for credit notes only — nothing was saved';
    end if;
  end if;

  if p_credit_for_invoice_id is not null then
    select * into v_for from public.po_invoice where id = p_credit_for_invoice_id;
    if not found then
      raise exception 'Invoice % not found (credit_for) — nothing was saved', p_credit_for_invoice_id;
    end if;
    if v_for.doc_kind <> 'invoice' then
      raise exception 'Credit note cannot be for another credit note (%) — nothing was saved', v_for.invoice_number;
    end if;
    v_supplier_id := v_for.supplier_id; v_currency_id := v_for.currency_id; v_rate := v_for.exchange_rate;
    v_pt_id := v_for.payment_term_id;   v_pt_name := v_for.payment_term_name;   v_source := 'invoice';
    v_tax_id := v_for.tax_rule_id;      v_tax_name := v_for.tax_rule;                                           -- po-tax-1
  end if;

  if p_po_id is not null then
    select * into v_po from public.po where id = p_po_id;
    if not found then
      raise exception 'PO % not found — nothing was saved', p_po_id;
    end if;
    if v_source is null then
      v_supplier_id := v_po.supplier_id; v_currency_id := v_po.currency_id; v_rate := v_po.exchange_rate;
      v_pt_id := v_po.payment_term_id;   v_pt_name := v_po.payment_term_name;   v_source := 'po';
      v_tax_id := v_po.tax_rule_id;      v_tax_name := v_po.tax_rule;                                           -- po-tax-1
    elsif v_po.supplier_id <> v_supplier_id then
      raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_for.invoice_number;
    elsif v_po.tax_rule_id is not null and v_tax_id is not null and v_po.tax_rule_id <> v_tax_id then
      v_warn := array_append(v_warn, 'tax_rule_differs_between_pos');                                           -- po-tax-1 · 크레딧 축 PO 의 규칙 ≠ credit_for 인보이스의 규칙
    end if;
  end if;

  if v_source is null then
    if p_supplier_id is null then
      raise exception 'A credit note needs one of: p_credit_for_invoice_id, p_po_id or p_supplier_id — nothing was saved';
    end if;
    select * into v_sup from public.supplier where id = p_supplier_id;
    if not found then
      raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
    end if;
    v_supplier_id := v_sup.id; v_pt_id := v_sup.payment_term_id; v_pt_name := v_sup.payment_term_name; v_source := 'supplier';
    v_currency_id := v_sup.currency_id;
    if v_sup.tax_rule is not null then                                                                          -- po-tax-1 · 공급처 이름 → id(활성 purchase · 못 풀면 null + 경고)
      select r.id, r.name into v_tax_id, v_tax_name from public.ref_tax_rule r where r.name = v_sup.tax_rule and r.direction = 'purchase' and r.is_active;
      if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_unknown:' || v_sup.tax_rule); end if;
    end if;
    if v_currency_id is null then
      select c.id into v_currency_id from public.ref_currency c join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
      if v_currency_id is null then
        raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
      end if;
      v_warn := array_append(v_warn, 'currency_defaulted');
    end if;
  end if;

  select s.name into v_sup_name from public.supplier s where s.id = v_supplier_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_currency_id;

  -- ── ⭐ p_line_qty 검사 넷 — 저장 전에 · 미리 보기에서도 같은 판정 ──
  if v_use_qty then
    -- ③ 그 PO 의 라인이 아닌 키(uuid 가 아닌 키도 여기서 걸린다 — ::uuid 가 invalid_text_representation 을 낸다 · 아래 exception 절이 읽을 문장으로)
    select count(*), string_agg(k.key, ', ' order by k.key) into v_bad_n, v_bad_txt
    from jsonb_each_text(p_line_qty) k
    where not exists (select 1 from public.po_line l where l.id = k.key::uuid and l.po_id = p_po_id);
    if v_bad_n > 0 then
      raise exception 'p_line_qty has % key(s) that are not lines of PO % (%) — nothing was saved', v_bad_n, v_po.po_number, v_bad_txt;
    end if;
    -- ② 숫자 아님 · 음수  ① 미청구 초과  — 라인 번호·SKU·수량을 문장에
    for r in
      select u.line_no, u.sku, u.remaining_qty, k.value as raw
      from jsonb_each_text(p_line_qty) k
      join public.po_uninvoiced_lines(p_po_id) u on u.po_line_id = k.key::uuid
      order by u.line_no
    loop
      if r.raw is null then continue; end if;                                   -- null 값 = 0 과 같다(줄 없음)
      if r.raw !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then
        raise exception 'Line % (%) of PO %: requested quantity "%" is not a number — nothing was saved', r.line_no, r.sku, v_po.po_number, r.raw;
      end if;
      v_req := r.raw::numeric;
      if v_req < 0 then
        raise exception 'Line % (%) of PO %: requested quantity % is negative — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req;
      end if;
      if v_req > r.remaining_qty then
        -- ⚠️ 넘겨 받으면 다음 장의 remaining 이 음수가 되고 초과 입고의 음수와 같은 모양이라 사후 구별이 안 된다(§11-b · po_line_update 와 같은 이유)
        raise exception 'Line % (%) of PO %: requested % EA but only % EA remain uninvoiced — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req, r.remaining_qty;
      end if;
    end loop;
    -- ④ 남길 줄이 하나도 없다(전부 0·null) — 줄 0개 인보이스는 확정이 어차피 막는다 · 만들기에서 막아 못 쓰는 문서를 안 남긴다
    select count(*) into v_keep_n
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' and k.value::numeric > 0;
    if v_keep_n = 0 then
      raise exception 'p_line_qty leaves no line to invoice on PO % — give at least one quantity above 0 — nothing was saved', v_po.po_number;
    end if;
    select coalesce(sum(k.value::numeric), 0) into v_req_total
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$';
  end if;

  -- ── ⭐ 크레딧 — 번호의 축(credit_po_id)과 번호 (210000 그대로) ──
  if p_doc_kind = 'credit' then
    if p_po_id is not null then
      v_credit_po_id := v_po.id;
    elsif p_credit_for_invoice_id is not null then
      select count(distinct pl.po_id), (array_agg(distinct pl.po_id))[1] into v_po_n, v_credit_po_id
      from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
      where il.po_invoice_id = p_credit_for_invoice_id;
      if coalesce(v_po_n, 0) > 1 then
        v_credit_po_id := null;
        v_warn := array_append(v_warn, 'credit_po_ambiguous');
      end if;
    end if;
    if v_credit_po_id is not null then
      select po_number into v_credit_po_number from public.po where id = v_credit_po_id;
    end if;

    if v_num is null then
      v_num := public.po_credit_next_number(v_credit_po_id, extract(year from coalesce(p_invoice_date, public.ims_today()))::int);
      v_num_src := case when v_credit_po_id is not null then 'auto_po' else 'auto_year' end;
      if not p_commit then v_warn := array_append(v_warn, 'number_is_provisional'); end if;
    else
      v_num_src := 'given';
      v_warn := array_append(v_warn, 'credit_number_manual');
    end if;
  else
    v_num_src := 'given';
  end if;

  -- ── 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부 (그대로) ──
  select count(*) into v_exists from public.po_invoice
   where supplier_id = v_supplier_id and doc_kind = p_doc_kind and invoice_number = v_num;
  if v_exists > 0 then
    if p_commit then
      raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, v_sup_name;
    end if;
    v_warn := array_append(v_warn, 'invoice_number_exists');
  end if;
  if p_total_amount is null then v_warn := array_append(v_warn, 'total_amount_missing'); end if;
  if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;                          -- po-tax-1 · 머리 규칙 없음(세금 0 으로 계산된다 · 초안에서 고른다)
  if p_doc_kind = 'credit' and p_due_date is not null then v_warn := array_append(v_warn, 'due_date_on_credit'); end if;

  -- ── commit: 머리 한 행 (그대로) ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then
      raise exception 'No active staff record for this login — nothing was saved';
    end if;
    insert into public.po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name,
                                   currency_id, exchange_rate, total_amount, status, created_by, credit_for_invoice_id, credit_po_id, tax_rule_id, tax_rule)
    values (v_supplier_id, p_doc_kind, v_num, coalesce(p_invoice_date, public.ims_today()), p_due_date, v_pt_id, v_pt_name,
            v_currency_id, v_rate, coalesce(p_total_amount, 0), 'draft', v_staff, p_credit_for_invoice_id, v_credit_po_id, v_tax_id, v_tax_name)   -- po-tax-1
    returning id into v_inv_id;
  end if;

  -- ── 줄 ──
  if p_doc_kind = 'invoice' then
    -- ⭐ 바뀐 블록 — p_line_qty 가 있으면 키에 있는 라인만 그 수량으로 · 없으면 미청구 수량 전부(그대로)
    for r in
      select u.*,
             case when v_use_qty then (select nullif(regexp_replace(k.value, '\s', '', 'g'), '')::numeric
                                         from jsonb_each_text(p_line_qty) k where k.key::uuid = u.po_line_id) end as requested_qty,
             case when v_use_qty then (p_line_qty ? u.po_line_id::text) end as in_keys
      from public.po_uninvoiced_lines(p_po_id) u
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
      v_req := case when v_use_qty and coalesce(r.in_keys, false) then coalesce(r.requested_qty, 0) end;   -- 준 값(null 값은 0)
      if r.remaining_qty <= 0 then
        -- 청구할 것이 없다 — 사실이 더 세다(키에 있고 0 이든 없든 · 0 초과는 위 ① 이 이미 막았다)
        v_verdict := 'fully_invoiced';
        v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
      elsif v_use_qty and coalesce(v_req, 0) = 0 then
        -- ⭐ 이번 인보이스에 안 실렸다(키에 없음 · 0 · null) — 줄 없음 · lines[] 에는 담는다
        v_verdict := 'skipped'; v_skip := v_skip + 1;
        v_msgs := array_append(v_msgs, case when coalesce(r.in_keys, false) then 'requested 0 — not on this invoice' else 'not in p_line_qty — not on this invoice' end);
      else
        v_verdict := 'ok'; v_ok := v_ok + 1;
        v_qty := case when v_use_qty then v_req else r.remaining_qty end;
        v_full := (v_qty = r.qty_ea);                                          -- 단위 칸 넷은 주문 수량과 같을 때만(그대로)
        if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced on other invoice(s) — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
        if v_use_qty and v_qty < r.remaining_qty then v_msgs := array_append(v_msgs, format('requested %s of %s remaining', v_qty, r.remaining_qty)); end if;
        if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                              entered_unit_product_id, entered_qty, entered_pack_factor, tax_rule_id)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                  case when v_full then r.entered_unit_product_id end,
                  case when v_full then r.entered_qty end,
                  case when v_full then r.entered_pack_factor end,
                  (select pl.tax_rule_id from public.po_line pl where pl.id = r.po_line_id));                   -- po-tax-1 · PO 줄 예외 규칙을 물려받는다(null = 머리) · 짝 트리거가 이름을 채운다
        end if;
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
        'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
        'requested_qty', v_req,                                                                   -- ⭐ 새 · 준 값(안 줬으면 null)
        'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;       -- p_line_qty 가 있으면 ④ 가 먼저 막아 여기 안 온다

    if p_copy_discounts then
      for r in select d.seq, d.name, d.percent, d.supplier_discount_id from public.po_discount d where d.po_id = p_po_id order by d.seq loop
        v_disc_n := v_disc_n + 1;
        if p_commit then
          insert into public.po_invoice_discount (po_invoice_id, seq, name, percent, supplier_discount_id)
          values (v_inv_id, r.seq, r.name, r.percent, r.supplier_discount_id);
        end if;
        v_discs := v_discs || jsonb_build_object('seq', r.seq, 'name', r.name, 'percent', r.percent, 'supplier_discount_id', r.supplier_discount_id, 'inserted', p_commit);
      end loop;
      if v_disc_n > 0 then v_warn := array_append(v_warn, 'discounts_copied_from_po'); end if;
    end if;

  elsif p_credit_for_invoice_id is not null then
    -- 크레딧 (210000 그대로)
    for r in
      select il.po_line_id, il.qty_ea as invoice_qty, il.unit_price, pl.line_no as po_line_no, x.po_number, pr.sku, il.tax_rule_id,
             coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) as received_qty,
             (select count(distinct x2.po_invoice_id) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
               where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                 and i2.id <> p_credit_for_invoice_id)::int as other_invoices
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po x on x.id = pl.po_id
      join public.product pr on pr.id = pl.product_id
      where il.po_invoice_id = p_credit_for_invoice_id and il.line_kind = 'goods'
      order by il.line_no
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := r.invoice_qty - r.received_qty;
      if r.other_invoices > 0 then v_msgs := array_append(v_msgs, format('line_has_other_invoices (%s) — difference may belong to another invoice', r.other_invoices)); end if;
      if v_qty > 0 then
        v_verdict := 'ok'; v_ok := v_ok + 1;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable, tax_rule_id)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true, r.tax_rule_id);           -- po-tax-1 · 인보이스 줄 규칙 그대로
        end if;
      elsif v_qty = 0 then
        v_verdict := 'no_difference'; v_msgs := array_append(v_msgs, 'invoiced = received');
      else
        v_verdict := 'over_received'; v_msgs := array_append(v_msgs, 'received more than invoiced — not a credit (§11-i difference)');
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', r.po_number, 'po_line_no', r.po_line_no, 'sku', r.sku,
        'invoice_qty', r.invoice_qty, 'received_qty', r.received_qty, 'diff_qty', v_qty,
        'qty_ea', case when v_verdict = 'ok' then v_qty end, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_qty_difference'); end if;
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'id', v_inv_id, 'doc_kind', p_doc_kind,
    'invoice_number', v_num, 'number_source', v_num_src,
    'credit_po_id', v_credit_po_id, 'credit_po_number', v_credit_po_number,
    'header_source', v_source,
    'supplier_id', v_supplier_id, 'supplier_name', v_sup_name, 'currency_id', v_currency_id, 'currency_code', v_cur_code,
    'payment_term_name', v_pt_name, 'total_amount', coalesce(p_total_amount, 0),
    'tax_rule_id', v_tax_id, 'tax_rule', v_tax_name,                                                            -- po-tax-1
    'line_count', case when p_commit then v_ins else v_ok end,
    'skipped_count', v_skip,                                                      -- ⭐ 새 · 이번에 뺀 라인 수(p_line_qty 없으면 0)
    'requested_total', v_req_total,                                               -- ⭐ 새 · 준 수량의 합(p_line_qty 없으면 null)
    'lines', v_lines,
    'discounts', v_discs, 'discounts_copied', v_disc_n,
    'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, coalesce(v_sup_name, 'this supplier');
  when invalid_text_representation then
    -- p_line_qty 의 키가 uuid 모양이 아니다(k.key::uuid) — 읽을 문장으로
    raise exception 'p_line_qty keys must be po_line_id uuids — one of them is not (%) — nothing was saved', sqlerrm;
end;
$$;

-- ═══ ⑤-8 po_line_update 재발행 — 마지막 정의 20260918000000:343 · 열쇠 tax_rule(이름 · 짝 트리거가 id · 활성 purchase 아니면 거부) · tax_rule_id · "" = 머리로 ═══
create or replace function public.po_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line   public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_recv   numeric;
  v_qty    numeric;
  v_line_no int;                                                -- ②-b: 0행이면 v_line 이 null 로 덮이므로 번호를 미리 든다
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_line from public.po_line where id = p_line_id;
  if not found then
    raise exception 'PO line % not found — nothing was saved', p_line_id;
  end if;
  v_line_no := v_line.line_no;
  select * into v_po from public.po where id = v_line.po_id;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be changed (closed = receiving finished) — nothing was saved', v_po.po_number, v_po.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;

  select coalesce(sum(qty_ea), 0) into v_recv from public.po_receipt_line where po_line_id = p_line_id;

  if p_patch ? 'qty_ea' then
    v_qty := (p_patch->>'qty_ea')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'qty_ea must be a positive number — nothing was saved';
    end if;
    -- ⭐ 받은 것보다 적게 줄일 수 없다(§1 ①) — 100 시켜 90 온 것은 라인 수정이 아니라 입고 90 · 크레딧 10 이다
    if v_qty < v_recv then
      raise exception 'Line % of %: cannot set quantity to % — % already received. Quantity must be at least the received quantity. Nothing was saved',
        v_line.line_no, v_po.po_number, v_qty, v_recv;
    end if;
  end if;

  update public.po_line set
    qty_ea                  = case when p_patch ? 'qty_ea'                  then (p_patch->>'qty_ea')::numeric                 else qty_ea end,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric             else unit_price end,
    supplier_sku            = case when p_patch ? 'supplier_sku'            then nullif(p_patch->>'supplier_sku', '')          else supplier_sku end,
    tax_rule                = case when p_patch ? 'tax_rule'                then nullif(p_patch->>'tax_rule', '')              else tax_rule end,      -- po-tax-1 · 이름(활성 purchase 만 · 짝 트리거가 id 를 풀고 아니면 거부) · "" = 머리로
    tax_rule_id             = case when p_patch ? 'tax_rule_id'             then nullif(p_patch->>'tax_rule_id', '')::uuid      else tax_rule_id end,   -- po-tax-1 · id 로 줘도 된다(둘 다 오면 id · 트리거)
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                  else note end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric  else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric else entered_pack_factor end
  where id = p_line_id
  returning * into v_line;
  if not found then                                             -- ②-b: 권한은 있었는데 0행 — 그 사이 지워졌거나 정책이 감췼다
    raise exception 'Line % of % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_po.po_number;
  end if;
  -- CHECK(qty_ea > 0 · unit_price >= 0 · entered_unit_ck)는 표가 그대로 지킨다 — 어기면 표의 예외가 그대로 올라간다

  return jsonb_build_object('line', to_jsonb(v_line), 'received_qty', v_recv, 'po_number', v_po.po_number, 'status', v_po.status);
end;
$$;

-- ═══ ⑤-9 po_invoice_line_add 재발행 — 마지막 정의 20260918003000 · 열쇠 tax_rule · tax_rule_id · goods 는 PO 줄 규칙을 물려받는다 · 경고 tax_rule_differs_between_pos ═══
create or replace function public.po_invoice_line_add(
  p_invoice_id uuid,
  p_line       jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_pl     public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_kind   text;  v_pol uuid;  v_desc text;  v_qty numeric;  v_price numeric;  v_pay boolean;
  v_tax_id uuid;  v_tax_name text;                                                              -- po-tax-1 · 줄 예외 규칙(없으면 goods 는 PO 줄 규칙 · 그 밖 null = 머리)
  v_next   int;   v_cnt int;   v_dup int;
  v_row    public.po_invoice_line%rowtype;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;

  v_kind  := coalesce(nullif(p_line->>'line_kind', ''), 'goods');
  v_pol   := nullif(p_line->>'po_line_id', '')::uuid;
  v_desc  := nullif(p_line->>'description', '');
  v_qty   := nullif(p_line->>'qty_ea', '')::numeric;
  v_price := coalesce(nullif(p_line->>'unit_price', '')::numeric, 0);
  v_pay   := coalesce(nullif(p_line->>'is_payable', '')::boolean, true);
  v_tax_id   := nullif(p_line->>'tax_rule_id', '')::uuid;                                      -- po-tax-1
  v_tax_name := nullif(p_line->>'tax_rule', '');

  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' then
    if v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — use line_kind charge/other with a description for anything else — nothing was saved'; end if;
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % % — nothing was saved', v_po.po_number, lower(case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end), v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
    if v_qty is null then raise exception 'qty_ea is required for a goods line — nothing was saved'; end if;
    select count(*) into v_dup from public.po_invoice_line where po_invoice_id = p_invoice_id and po_line_id = v_pol;
    if v_dup > 0 then v_warn := array_append(v_warn, 'line_already_on_invoice'); end if;      -- 막지 않는다(부분 선적이 한 장에 두 줄로 올 수 있다 · 짐작) · 알린다
    if v_tax_id is null and v_tax_name is null then v_tax_id := v_pl.tax_rule_id; end if;     -- po-tax-1 · PO 줄 예외 규칙을 물려받는다(null = 머리)
    if v_po.tax_rule_id is not null and v_inv.tax_rule_id is not null and v_po.tax_rule_id <> v_inv.tax_rule_id then v_warn := array_append(v_warn, 'tax_rule_differs_between_pos'); end if;   -- po-tax-1
  else
    if v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
    v_qty := coalesce(v_qty, 1);
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable,
                                      entered_unit_product_id, entered_qty, entered_pack_factor, note, tax_rule_id, tax_rule)
  values (p_invoice_id, v_next, v_kind, case when v_kind = 'goods' then v_pol end, v_desc, v_qty, v_price, v_pay,
          nullif(p_line->>'entered_unit_product_id', '')::uuid, nullif(p_line->>'entered_qty', '')::numeric,
          nullif(p_line->>'entered_pack_factor', '')::numeric, nullif(p_line->>'note', ''), v_tax_id, v_tax_name)   -- po-tax-1 · 짝 트리거가 다른 쪽을 채운다 · 활성 purchase 아니면 거부
  returning * into v_row;
  -- CHECK(target · unit_price >= 0 · entered_unit_ck)는 표가 지킨다 — 어기면 표의 예외가 그대로 올라간다

  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
  return jsonb_build_object('line', to_jsonb(v_row), 'line_count', v_cnt, 'invoice_number', v_inv.invoice_number, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤-10 po_invoice_line_update 재발행 — 마지막 정의 20260918003000 · 열쇠 tax_rule · tax_rule_id ═══
create or replace function public.po_invoice_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line_no int;                                                -- ②-b: 0행이면 v_row 가 null 로 덮이므로 번호를 미리 든다
  v_row   public.po_invoice_line%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_pl    public.po_line%rowtype;
  v_po    public.po%rowtype;
  v_kind  text;  v_pol uuid;  v_desc text;  v_qty numeric;
  v_warn  text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was saved', p_line_id; end if;
  v_line_no := v_row.line_no;
  select * into v_inv from public.po_invoice where id = v_row.po_invoice_id;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft (confirmed = accepted into the books; reopen first) — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'p_patch must be a JSON object — nothing was saved'; end if;

  -- 새 값(patch 우선 · 없으면 기존) — CHECK 위반을 표의 예외 대신 읽을 문장으로 먼저 낸다
  v_kind := case when p_patch ? 'line_kind'   then coalesce(nullif(p_patch->>'line_kind', ''), 'goods') else v_row.line_kind end;
  v_pol  := case when p_patch ? 'po_line_id'  then nullif(p_patch->>'po_line_id', '')::uuid            else v_row.po_line_id end;
  v_desc := case when p_patch ? 'description' then nullif(p_patch->>'description', '')                 else v_row.description end;
  v_qty  := case when p_patch ? 'qty_ea'      then nullif(p_patch->>'qty_ea', '')::numeric             else v_row.qty_ea end;
  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' and v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — nothing was saved'; end if;
  if v_kind <> 'goods' and v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
  if v_qty is null then raise exception 'qty_ea is required — nothing was saved'; end if;
  if v_kind = 'goods' and (p_patch ? 'po_line_id') and v_pol is distinct from v_row.po_line_id then
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % — nothing was saved', v_po.po_number, v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
  end if;

  update public.po_invoice_line set
    line_kind               = v_kind,
    po_line_id              = case when v_kind = 'goods' then v_pol else null end,                     -- goods 가 아니면 라인 참조를 비운다
    description             = v_desc,
    qty_ea                  = v_qty,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric                    else unit_price end,
    is_payable              = case when p_patch ? 'is_payable'              then coalesce((p_patch->>'is_payable')::boolean, true)     else is_payable end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid  else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric           else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric   else entered_pack_factor end,
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                           else note end,
    tax_rule                = case when p_patch ? 'tax_rule'                then nullif(p_patch->>'tax_rule', '')                       else tax_rule end,       -- po-tax-1 · 이름(짝 트리거가 id · 활성 purchase 만) · "" = 머리로
    tax_rule_id             = case when p_patch ? 'tax_rule_id'             then nullif(p_patch->>'tax_rule_id', '')::uuid               else tax_rule_id end    -- po-tax-1 · id(둘 다 오면 id)
  where id = p_line_id
  returning * into v_row;
  if not found then                                             -- ②-b
    raise exception 'Line % of % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_inv.invoice_number;
  end if;

  return jsonb_build_object('line', to_jsonb(v_row), 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤-11 po_invoice_add_po_lines 재발행 — 마지막 정의 20260918003000 · 줄은 PO 줄 규칙 · 경고 tax_rule_differs_between_pos ═══
create or replace function public.po_invoice_add_po_lines(
  p_invoice_id uuid,
  p_po_id      uuid,
  p_commit     boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_po     public.po%rowtype;
  v_next   int;
  v_n      int := 0;  v_ok int := 0;  v_ins int := 0;
  v_warn   text[] := '{}';
  v_lines  jsonb := '[]'::jsonb;
  v_msgs   text[];
  v_verdict text;  v_qty numeric;  v_full boolean;
  r        record;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.doc_kind <> 'invoice' then
    raise exception 'Credit note % — PO lines are added to invoices only (add credit lines one by one) — nothing was saved', v_inv.invoice_number;
  end if;
  if v_inv.status <> 'draft' then
    raise exception 'Invoice % is % — lines can be changed only while draft (confirmed = accepted into the books) — nothing was saved', v_inv.invoice_number, v_inv.status;
  end if;
  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  if v_po.supplier_id <> v_inv.supplier_id then
    raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_inv.invoice_number;
  end if;
  if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
  if v_po.tax_rule_id is not null and v_inv.tax_rule_id is not null and v_po.tax_rule_id <> v_inv.tax_rule_id then
    v_warn := array_append(v_warn, 'tax_rule_differs_between_pos');                                            -- po-tax-1 · 이 PO 의 머리 규칙 ≠ 인보이스 머리 규칙(줄은 PO 줄 규칙 · 머리는 사람이 고른다)
  end if;

  select coalesce(max(line_no), 0) into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  for r in select * from public.po_uninvoiced_lines(p_po_id) loop
    v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
    if r.remaining_qty > 0 then
      v_verdict := 'ok'; v_qty := r.remaining_qty; v_full := (r.remaining_qty = r.qty_ea); v_ok := v_ok + 1;
      if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
      if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
      v_next := v_next + 1;
      if p_commit then
        v_ins := v_ins + 1;
        insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                            entered_unit_product_id, entered_qty, entered_pack_factor, tax_rule_id)
        values (p_invoice_id, v_next, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                case when v_full then r.entered_unit_product_id end, case when v_full then r.entered_qty end, case when v_full then r.entered_pack_factor end,
                (select pl.tax_rule_id from public.po_line pl where pl.id = r.po_line_id));                     -- po-tax-1 · PO 줄 예외 규칙(null = 머리)
      end if;
    else
      v_verdict := 'fully_invoiced';
      v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
    end if;
    v_lines := v_lines || jsonb_build_object(
      'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
      'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
      'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
      'line_no', case when v_verdict = 'ok' then v_next end,
      'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
  end loop;
  if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;

  return jsonb_build_object('committed', p_commit, 'invoice_id', p_invoice_id, 'invoice_number', v_inv.invoice_number,
                            'po_id', p_po_id, 'po_number', v_po.po_number, 'lines', v_lines, 'inserted', v_ins, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑥ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from information_schema.columns where table_schema = 'public'
    and ((table_name = 'po' and column_name = 'tax_rule_id') or (table_name = 'po_line' and column_name = 'tax_rule_id')
      or (table_name = 'po_invoice' and column_name in ('tax_rule', 'tax_rule_id')) or (table_name = 'po_invoice_line' and column_name in ('tax_rule', 'tax_rule_id')));
  if v_n <> 6 then v_bad := v_bad || format(' columns(%s)', v_n); end if;
  select count(*) into v_n from pg_constraint where conname in ('po_tax_rule_pair_ck', 'po_line_tax_rule_pair_ck', 'po_invoice_tax_rule_pair_ck', 'po_invoice_line_tax_rule_pair_ck');
  if v_n <> 4 then v_bad := v_bad || format(' checks(%s)', v_n); end if;
  select count(*) into v_n from pg_trigger where tgname in ('po_tax_rule_pair', 'po_line_tax_rule_pair', 'po_invoice_tax_rule_pair', 'po_invoice_line_tax_rule_pair') and not tgisinternal;
  if v_n <> 4 then v_bad := v_bad || format(' triggers(%s)', v_n); end if;
  if to_regclass('public.po_tax_group') is null then v_bad := v_bad || ' po_tax_group'; end if;
  select count(*) into v_n from public.po where tax_rule is not null and tax_rule_id is null;
  if v_n <> 0 then v_bad := v_bad || format(' po_unresolved(%s)', v_n); end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    and p.proname in ('po_detail', 'po_invoice_detail', 'po_create', 'po_invoice_create', 'po_line_update', 'po_invoice_line_add', 'po_invoice_line_update', 'po_invoice_add_po_lines') and p.prosrc like '%po-tax-1%';
  if v_n <> 8 then v_bad := v_bad || format(' bodies(%s)', v_n); end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    and p.proname in ('po_detail', 'po_invoice_detail', 'po_create', 'po_invoice_create', 'po_line_update', 'po_invoice_line_add', 'po_invoice_line_update', 'po_invoice_add_po_lines');
  if v_n <> 8 then v_bad := v_bad || format(' duplicate-signatures(%s)', v_n); end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'po_list';
  if v_n <> 42 then v_bad := v_bad || format(' po_list_columns(%s)', v_n); end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_money';
  if v_n <> 27 then v_bad := v_bad || format(' po_invoice_money_columns(%s)', v_n); end if;
  if v_bad <> '' then raise exception 'po-tax-1 self-check failed:% — nothing was applied', v_bad; end if;
end $$;
