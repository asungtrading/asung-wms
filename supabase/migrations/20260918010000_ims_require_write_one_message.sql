-- ─────────────────────────────────────────────────────────────
-- ims_require_write — 거부 문장을 하나로 (Asung-IMS) · 2026-09-17 밤
--
-- 앞 차수: 20260918000000(도우미 신설 · d6c3155) · 20260918003000(인보이스·할인 여덟). 둘 다 적용됨 — 고치지 않는다. 이 파일은 도우미 하나만 create or replace.
-- 부르는 함수 열넷(po_create · po_lines_paste · po_line_update · po_line_delete · po_doc_cancel · po_doc_delete ·
--   po_invoice_create · po_invoice_add_po_lines · po_invoice_line_add/update/delete · po_invoice_confirm · po_discount_save · po_discount_delete)은 무접촉 — 시그니처(text, text) 그대로라 호출이 그대로 닿는다.
--
-- ⭐ 왜 [Caleb 실측 2026-09-17] — 종전 도우미는 ims_can_view 로 문장을 둘로 갈랐다:
--   「You can read <묶음> but not change it …」 / 「You do not have <묶음> access …」.
--   그런데 purchasing 만 가진 사람은 ims_can_view('master') = false 인데 **product·supplier 를 다 읽는다** —
--   앞 차수(20260917235000)가 select 정책을 전부 using(true) 로 열었기 때문이다.
--   ⇒ ims_can_view 는 「데이터를 읽을 수 있나」가 아니라 「그 화면에 들어갈 수 있나」다. 둘째 문장은 읽기도 안 되는 것처럼 들려 실물과 어긋난다.
-- ⭐ 처방 — 분기를 없애고 문장 하나. **읽기 여부를 말하지 않는다**(말하면 실물과 어긋난다).
--   「You cannot change <묶음> data — ask an admin to add the '<묶음>' permission — nothing was saved|deleted」
--   ims_can_view 자체는 그대로 둔다(화면 접근 판정 · ③ 차수가 쓴다). 판정은 여전히 ims_can_write 하나.
-- ─────────────────────────────────────────────────────────────

create or replace function public.ims_require_write(p_screen text, p_verb text default 'saved') returns void
  language plpgsql stable
  set search_path = public, pg_temp
as $$
begin
  if public.ims_can_write(p_screen) then
    return;
  end if;
  raise exception 'You cannot change % data — ask an admin to add the ''%'' permission — nothing was %', p_screen, p_screen, p_verb;
end;
$$;
comment on function public.ims_require_write(text, text) is
  '쓰기 RPC 첫머리 — ims_can_write(p_screen) 가 false 면 읽을 수 있는 문장 하나로 거부(RLS 에 닿기 전에). p_verb = saved | deleted. ⚠️ 읽기 여부는 말하지 않는다 — select 는 전 표 열려 있어 ims_can_view 와 어긋난다(2026-09-17 실측). 판정은 ims_can_write 하나 · 이 함수는 문장만';

-- 검증: select ims_require_write('purchasing') 을 purchasing 없는 사람으로 →
--   ERROR: You cannot change purchasing data — ask an admin to add the 'purchasing' permission — nothing was saved
-- select count(*) from pg_proc where proname = 'ims_require_write';   → 1
