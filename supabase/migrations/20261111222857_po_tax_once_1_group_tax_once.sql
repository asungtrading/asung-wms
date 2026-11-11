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

-- po-tax-once-1: 공급처 쪽 세금(po_tax_group · 인보이스 · 크레딧 · PO)을 「규칙 묶음 소계에 한 번」 매기고 한 번 반올림한다 (2026-11-11 · 지시서 ~/asung/prompts/po-tax-once-1.md · 판정 1193 · §0 이견 1 ~ 7)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — PGCONNECT_TIMEOUT=10 psql -X -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied · supabase db push 금지
-- 무엇:
--   · 1193 묶음마다 tax_amount = so_tax_amount(taxable_amount, rate_pct) · payable_tax = so_tax_amount(payable_taxable, rate_pct) — 소계(체인 할인을 뺀 goods + other)에 한 번 · 옛 식 = Σ줄 세금 − round(할인 × rate, 2)
--   · 뷰 po_tax_group 하나만 다시 낸다(create or replace · 칸 18 개의 이름 · 순서 · 형 그대로 · security_invoker 다시 적음) — 크레딧은 po_invoice 의 doc_kind credit 이라 같은 뷰 · 같은 식(이견 1)
--   · lines_tax · discount_tax 는 식 그대로 「참고값」(줄마다 셈했을 때의 값) — tax_amount 는 더 이상 이 둘의 차가 아니다 · 안쪽 payable_lines_tax 는 쓰는 곳이 없어져 뺀다
--   · 주석 셋(po_tax_group · po_invoice_money · po_list)의 「줄마다 반올림」 글을 고친다
-- 재발행: 뷰 하나(원본 = 20261008170700_po_tax_1.sql 164 행 · DB pg_get_viewdef md5 fa625ffda6fbf611bad2fe466fdd972d) · 함수 0
-- 무변: so_tax_amount(SO 와 같이 쓴다 · 손님 판매 세금 셈 무접촉) · po_invoice_money · po_list · po_invoice_list 의 정의(묶음 세금을 더하기만 한다) · po_invoice_detail(줄 세금 칸은 그대로 줄마다 — 화면이 판정 1194 로 그 칸을 뺀다)
--       · po_invoice_discount_parts · qbo_bill_body(읽는 칸 그대로 · TaxLine 금액 = 과세 소계 × 세율) · po_charge(찍힌 세금) · 원가 · 결제 배분 · EF · cron
-- 실물(2026-11-11 읽기): 바뀌는 문서 셋 — 확정 인보이스 하나(세금 +0.01 · 찍힌 합계와 차이 0.01 → 0) · PO 둘(+0.01 · −0.12) · 보낸 Bill 9 장 · 결제 배분 4 줄 · 지문은 무변
-- ⚠️ 줄마다 반올림하는 공급처의 인보이스는 찍힌 합계와 차이(diff)로 멈춘다(조용히 틀리지 않는다 · 1193) · 묶음 둘 + 체인 할인의 세금 전 1 센트 틈(po_invoice_money 는 문서 전체에 한 번 round)은 그대로
-- 새 표 0 · FK 0 → 컷오버 날 지우는 순서 영향 없음 · 시퀀스 0 · 권한 무변(create or replace 는 ACL 을 지킨다)
-- 검증 supabase/tests/po_tax_once_1_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

-- ═══════════════ ⓪ 원본 가드 — 뷰 원본 md5 · 아직 미적용 · 칸 · 옵션 · 주석의 옛 글 ═══════════════
do $$
declare v_bad text := ''; v_def text := pg_get_viewdef('public.po_tax_group'::regclass, true);
begin
  if v_def not like '%payable_lines_tax%' then v_bad := v_bad || ' (po-tax-once-1 already applied?)';
  elsif md5(v_def) is distinct from 'fa625ffda6fbf611bad2fe466fdd972d' then v_bad := v_bad || ' po_tax_group(view md5 ' || md5(v_def) || ')'; end if;
  if (select string_agg(a.attname, ',' order by a.attnum) from pg_attribute a where a.attrelid = 'public.po_tax_group'::regclass and a.attnum > 0 and not a.attisdropped)
     is distinct from 'doc_kind,doc_id,tax_rule_id,tax_rule,rate_pct,line_count,goods_amount,other_amount,discount_amount,taxable_amount,lines_tax,discount_tax,tax_amount,goods_payable,other_payable,payable_discount,payable_taxable,payable_tax' then v_bad := v_bad || ' po_tax_group(columns)'; end if;
  if (select c.reloptions::text from pg_class c where c.oid = 'public.po_tax_group'::regclass) is distinct from '{security_invoker=true}' then v_bad := v_bad || ' po_tax_group(options)'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_tax_amount') is distinct from '3408f7cd2707de5e89528ac40d0d0810' then v_bad := v_bad || ' so_tax_amount(md5)'; end if;
  if position('줄마다 반올림 · 할인 줄 한 번 · 규칙 묶음' in coalesce(obj_description('public.po_invoice_money'::regclass), '')) = 0 then v_bad := v_bad || ' po_invoice_money(comment text)'; end if;
  if position('줄마다 반올림 · 할인 줄 한 번 · 규칙 모르는' in coalesce(obj_description('public.po_list'::regclass), '')) = 0 then v_bad := v_bad || ' po_list(comment text)'; end if;
  if v_bad <> '' then raise exception 'po-tax-once-1 guard failed —%. Nothing was changed.', v_bad; end if;
end $$;

-- ═══════════════ ① 뷰 po_tax_group — 묶음 소계에 한 번(원본과 다른 줄은 끝에 「po-tax-once-1」 표시) ═══════════════
create or replace view public.po_tax_group
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
         case when r.rate_pct is null then null else coalesce(sum(public.so_tax_amount(l.amt, r.rate_pct)), 0) end                                  as lines_tax
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
  public.so_tax_amount(round(g.goods_amount * g.factor, 2) + g.other_amount, g.rate_pct)                         as tax_amount,   -- po-tax-once-1
  g.goods_payable, g.other_payable,
  g.goods_payable - round(g.goods_payable * g.factor, 2)                                                         as payable_discount,
  round(g.goods_payable * g.factor, 2) + g.other_payable                                                         as payable_taxable,
  public.so_tax_amount(round(g.goods_payable * g.factor, 2) + g.other_payable, g.rate_pct)                       as payable_tax   -- po-tax-once-1
from g;

-- ═══════════════ ② 주석 셋 ═══════════════
comment on view public.po_tax_group is 'po-tax-1 · po-tax-once-1 ⭐⭐ 매입 세금 식의 정본 — 발주(doc_kind po · doc_id = po.id) · 인보이스 · 크레딧(invoice · po_invoice.id · 크레딧도 이 갈래)의 규칙 묶음(같은 규칙의 줄)마다 한 행. 줄 규칙 = coalesce(줄, 머리) · 묶음 할인 = goods − round(goods × 체인 factor, 2)(체인은 goods 에만 · po_mul) · taxable_amount = round(goods × factor, 2) + other · ⭐ [po-tax-once-1 2026-11-11 · 판정 1193] tax_amount = so_tax_amount(taxable_amount, rate_pct) — 묶음 소계에 한 번 매기고 한 번 반올림(옛 식 = Σ줄 세금 − round(할인 × rate, 2)) · payable_tax = so_tax_amount(payable_taxable, rate_pct) · lines_tax(Σ줄마다 반올림한 세금) · discount_tax(round(할인 × rate, 2))는 참고값 — tax_amount 는 이 둘의 차가 아니다 · 줄마다 반올림하는 공급처의 인보이스는 찍힌 합계와 diff 로 멈춘다 · payable_* 는 is_payable 줄만(인보이스 낼 돈 · 크레딧 뺄 돈 · PO 는 전부 payable) · 규칙을 모르는 묶음은 tax null(읽는 쪽 tax_rule_missing) · 문서 통화 · 환산 없음 · ⚠️ 돈의 세금 전 부분은 po_invoice_money · po_list 가 문서 전체에 한 번 round 한다(묶음 둘이면 Σ묶음 taxable 과 1센트 갈릴 수 있다 · 세금만 묶음) · 손님 판매(SO) 세금 셈과 무관(so_tax_amount 함수만 같이 쓴다) · po_invoice_money · po_list · po_detail · po_invoice_detail · qbo_bill_body 가 읽는다 · security_invoker';
do $$
begin
  execute format('comment on view public.po_invoice_money is %L',
    replace(obj_description('public.po_invoice_money'::regclass), '줄마다 반올림 · 할인 줄 한 번 · 규칙 묶음', '규칙 묶음 소계에 한 번 반올림[po-tax-once-1 2026-11-11 · 판정 1193 · 옛 식은 줄마다] · 규칙 묶음'));
  execute format('comment on view public.po_list is %L',
    replace(obj_description('public.po_list'::regclass), '줄마다 반올림 · 할인 줄 한 번 · 규칙 모르는', '규칙 묶음 소계에 한 번 반올림[po-tax-once-1 2026-11-11 · 판정 1193 · 옛 식은 줄마다] · 규칙 모르는'));
end $$;

-- ═══════════════ ③ 착지 — 새 정의 md5 · 칸 · 옵션 · 권한 · 주석 ═══════════════
do $$
declare v_bad text := ''; v_def text := pg_get_viewdef('public.po_tax_group'::regclass, true);
begin
  if md5(v_def) is distinct from '3f979ecbe76829db115d28c1398341ed' then v_bad := v_bad || ' po_tax_group(new view md5 ' || md5(v_def) || ')'; end if;   -- landing-def-md5
  if v_def like '%payable_lines_tax%' then v_bad := v_bad || ' po_tax_group(payable_lines_tax still there)'; end if;
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum) from pg_attribute a where a.attrelid = 'public.po_tax_group'::regclass and a.attnum > 0 and not a.attisdropped)
     is distinct from 'doc_kind:text,doc_id:uuid,tax_rule_id:uuid,tax_rule:text,rate_pct:numeric(7,4),line_count:integer,goods_amount:numeric,other_amount:numeric,discount_amount:numeric,taxable_amount:numeric,lines_tax:numeric,discount_tax:numeric,tax_amount:numeric,goods_payable:numeric,other_payable:numeric,payable_discount:numeric,payable_taxable:numeric,payable_tax:numeric' then v_bad := v_bad || ' po_tax_group(columns)'; end if;
  if (select c.reloptions::text from pg_class c where c.oid = 'public.po_tax_group'::regclass) is distinct from '{security_invoker=true}' then v_bad := v_bad || ' po_tax_group(options)'; end if;
  if (select c.relacl::text from pg_class c where c.oid = 'public.po_tax_group'::regclass) is distinct from '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' then v_bad := v_bad || ' po_tax_group(acl)'; end if;
  if (select count(*) from pg_class c where c.oid in ('public.po_tax_group'::regclass, 'public.po_invoice_money'::regclass, 'public.po_list'::regclass) and obj_description(c.oid) like '%po-tax-once-1%' and obj_description(c.oid) not like '%줄마다 반올림 · 할인 줄 한 번%') <> 3 then v_bad := v_bad || ' (comments)'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_tax_amount') is distinct from '3408f7cd2707de5e89528ac40d0d0810' then v_bad := v_bad || ' so_tax_amount(md5)'; end if;
  if v_bad <> '' then raise exception 'po-tax-once-1 landing check failed —%. Nothing was changed.', v_bad; end if;
end $$;
