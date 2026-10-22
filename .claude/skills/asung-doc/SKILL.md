---
name: asung-doc
description: >
  Asung Trading IMS 의 문서 — 문서 템플릿(판) · 인쇄 · 서버 PDF · 문서 메일. 인보이스 · 크레딧 노트 · SO · Ship Ready(PROFORMA) · Internal Receipt 를 찍거나 보내거나 판을 고칠 때 먼저 읽으세요.
  "doc_template", "doc_data", "doc_field_catalog", "자리표", "판 올리기", "Use this version",
  "Settings → Documents", "ims-doc.js", "Mustache", "인쇄", "Print invoice", "Gotenberg", "Cloud Run",
  "doc_file", "documents 버킷", "doc-brand", "EF doc", "서명 URL", "문서 메일", "doc_mail_send",
  "waiting_pdf", "ims-mail-pdf", "cron 57", "final_invoice_mail", "info@", "인보이스 메모", "doc_mail_skip"
  가 나오면 추측하지 말고 이 스킬과 정본 so-module §66 을 확인하세요.
  ⚠️판에 meta 태그 · 스크립트 · 바깥 주소 금지(DB 가 거부) — 판 글자는 ASCII(EF 가 charset 을 끼운다),
  ⚠️값의 꼴(돈 · 날짜)은 doc_data 가 만든다 — 판은 셈하지 않는다,
  ⚠️「0 이면 빈칸」은 doc_data 가 — Mustache 는 "0.00" 도 있음으로 읽는다.
---

# Asung 문서 스킬 — 판 · 인쇄 · 서버 PDF · 문서 메일

⭐ **설계 정본 `docs/design/so-module.md` §66**(판정 521 ~ 530 · 함수 지도 66-d · 실물 66-c) — 여기는 「모르면 사고가 나는 것」과 포인터만. 이 스킬과 정본이 어긋나면 **정본이 맞다**.
관련 스킬: `asung-so`(인보이스 · 크레딧 · Ship & invoice — 4-g · 4-i · 4-s 메일 기계) · `asung-workflow`(지시서 · 검증 · 파일 옮기기) · `asung-ops`(asung-ops 레포 · Gotenberg · cron 운영)
⚠️ 전부 **테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg)** 에만 있다 — 운영 전환은 mail-5 묶음(so-module 미룬 244 · 256).

## 0. 판정 요약 (원문은 §66-a)

```
521  컷오버 2026-11-01(일) 아침에 반드시 = 문서 템플릿 · 최종 인보이스 메일 · 발주앱 · 드라이브 · QuickBooks 는 며칠 뒤(drive_file_id null = 아직)
     안 A — 틀(배치)은 IMS 의 「판」 · 직원은 글과 켜고 끄기만 Settings 에서 · 배치 바꾸기 = 대화 Claude 가 새 판을 통째로
522  판 쓰기 = 열쇠 doc_template(admin 은 역할로 · supervisor 는 Staff 에서 켰을 때만 · manager · worker 안 됨)
523  서버 PDF = Gotenberg(회사 Cloud Run 토론토) · 화면 인쇄 = 브라우저 인쇄
524  모든 문서 머리에 두 지점(토론토 · 에드먼튼) — 창고와 상관없이 같은 머리
525  회사 글 · 문서 글 고치기 = ims_can_write('master')
526  Notes = so_invoice.note · so_credit.note(오더 메모 아님 — 직원 메모가 새지 않게)
527  Unit price = 할인 전(list_price) · 금액 = 수량 × 단가 × (1 − 할인)
528  Due = 찍는 순간 남은 금액(so_invoice_remaining) · 0 이면 줄 없음 · 발행 때 종이 그대로는 남긴 PDF(doc_file)로
529  최종 인보이스 자동 메일 = customer.final_invoice_mail(기본 꺼짐 · 바꾸기 manager 이상) · 컷오버 전 손으로 켠다
530  문서 메일 From info@asung.ca · Reply-To info@ · 이름 Asung Trading(키 mail_doc_*) · ims@ 에 Send mail as 등록 ✅
문서 다섯   final_invoice(제목 INVOICE) · credit_note · sales_order(손님에게도) · ship_ready(PROFORMA · Ship & invoice 직전) · internal_receipt(지역 배송 서명 · 메일 없음 · 작은 「INTERNAL USE ONLY」)
            패킹 슬립 없음(WMS 에 있다)
```

## 1. ⭐⭐ 판(template) — 모르면 사고

```
⭐⭐ 판에 쓸 수 있는 이름은 doc_field_catalog(kind) 하나 — 20261019144030_doc_1a_template_base.sql:371 · 목록 밖 자리표는 올릴 때 거부된다
     ⇒ 판을 쓰기 전에 그 kind 의 목록을 DB 에서 받아 본다: select public.doc_field_catalog('final_invoice');
⭐⭐ 올릴 때 검사 doc_template_check(kind, body, mode) — 크기 200 KB · Mustache 꼬리표는 {{x}} {{#s}} {{^s}} {{/s}} {{! }} 만({{{ }}} · {{& }} · {{> }} · {{= =}} 거부)
     · 금지 HTML script · iframe · object · embed · form · meta · link · base · on…= · javascript: · 바깥 주소(http:// · https:// · //) · @import
     ⚠️ <meta charset> 도 거부다 — 판 안 글자는 ASCII 로(— · · · é 같은 글자는 &mdash; · &middot; 꼴) · 서버 PDF 는 EF 가 보내기 직전 <head> 에 charset 을 끼운다
     ⚠️ 판을 미리 흉내 내는 도구를 만들면 DB 금지 목록 그대로 — 예외를 두면 DB 거부를 놓친다(§66-e 1)
⭐⭐ 판은 셈하지 않는다 — 돈 · 날짜 · 수량 · 퍼센트는 doc_data 가 글자로 준다(doc_fmt_money · qty · pct · date · 날짜 꼴 키 doc_date_format = DDMONYYYY)
⭐⭐ 「0 이면 빈칸」 — Mustache 는 "0.00" 글자를 「있음」 으로 읽어 {{#due}} 줄을 그린다 ⇒ 0 인 돈은 doc_data 가 "" 로(doc_fmt_money_nz) · 판에서 0 을 거르려 하지 마라
     빈칸 대상: due · deposit · credit · balance_forward · paid · SO prepaid · net 단가(오더 할인이 없으면) — 크레딧 노트는 그대로
⭐ 로고는 {{company.logo_url}}(doc-brand 버킷 · doc_public_base_url 로 만든 주소) — 판에 주소를 직접 쓰면 「바깥 주소」 로 거부
⭐ 쓰는 판 = kind 마다 하나(doc_template_active) · 새 판 저장 ≠ 쓰기 — Use this version(doc_template_publish)을 눌러야 바뀐다 · 옛 판은 지우지 않는다(되돌리기 = 옛 판을 다시 Use)
⭐ 판 파일은 레포 밖 — DB doc_template 이 정본(테스트 쓰는 판: final_invoice v5 · internal_receipt v2 · sales_order v2 · ship_ready v2 · credit_note v2 · 2026-10-19)
```

### 판 고치는 순서 (대화 Claude ↔ Caleb)
```
① 대화 Claude 가 그 kind 의 doc_field_catalog 와 쓰는 판(doc_template_get)을 받아 새 판을 **통째로** 쓴다(부분 고침 아님)
② Caleb 이 Settings → Documents → 그 문서 탭 → 새 판 붙이기 → **Check**(doc_template_check 결과)
③ **Preview** — 실제 문서 번호를 넣어 그 문서로 미리 본다(sandbox iframe · 스크립트 없음)
④ **Save**(새 판 · 아직 안 씀) → **Use this version**(쓰는 판으로)
⑤ 인쇄 · PDF 로 한 장 확인 — 이상하면 옛 판을 다시 Use
⚠️ 글(제목 · 메일 제목 · 메일 글 · 켜고 끄기 show_upc · show_comment · show_charge_code)은 판이 아니다 — Settings 의 칸에서 직원이 고친다(master · doc_setting_set)
```

## 2. ⭐⭐ 데이터 창구 doc_data — 모르면 사고

```
⭐⭐ doc_data(kind, ref) 하나가 화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 모두의 재료 — 같은 ref 면 같은 글자 · 다른 길로 셈하지 마라
     ref: final_invoice · internal_receipt {invoice_id} · credit_note {credit_id} · sales_order {so_id} · ship_ready {orders:[{so_id, …}]}(Ship & invoice 창과 같은 입력)
     반환 {docs:[…]} · ship_ready 는 + groups[](인보이스가 갈리면 장이 여럿)
⭐⭐ Ship Ready 의 돈은 발행과 같은 식 — so_invoice_rule_pick · so_invoice_apply_plan · so_tax_preview(…, p_over) · so_invoice_preview 를 so_invoice_issue 가 함께 쓴다
     ⇒ 발행 쪽만 고치면 미리 보기와 갈린다 · 고치면 「옛 발행 = 새 발행」 · 「미리 보기 = 발행」 두 겹 대조를 다시(doc-1b2)
⭐ Ship Ready 는 sales 권한이 있는 **직원 로그인**으로만 만든다(so_finalize 미리 보기) — 서버 일꾼(service 길)은 못 만든다
⭐ Due 는 찍는 순간 so_invoice_remaining — 같은 인보이스도 결제 뒤 다시 찍으면 Due 가 바뀐다 · 발행 때 종이는 doc_file(남긴 PDF)
⭐ 메모(Notes)는 so_invoice.note · so_credit.note — 쓰는 창구 so_invoice_note_set · so_credit_note_set(sales 쓰기 · issued 만 · 2000 자 · 빈 글 → null)
⭐ [2026-10-22 · crn-1 · crn-2 · so-module §70-b] credit_note — **가격 조정 줄(price_adjustment)은 제품 표에** · 수량 = qty_adjusted · 단가 = 개당 차액(unit_price_before − after) · 설명 「Price adjustment 9.49 → 7.99 — <제품명>」 · charges 로 안 간다 · 참조 크레딧의 참조 번호는 credit.invoice_number 자리에 이미 찍힌다(판 credit_note v2 무변)
⭐ [2026-10-21 · svc-1c · so-module §69] charges 의 qty · unit_price 는 **수량 × 단가 비용 줄(서비스)** 에서만 채워진다 — 운임 · 할인 줄은 "" · 꼴은 doc_fmt_qty(천 단위 쉼표 없음 · 1200) · doc_fmt_money · 판(final_invoice v5 · credit_note v2)은 이미 Qty · Unit price 칸을 그린다 · 크레딧 노트의 서비스 줄은 금액만(qty "")
```

## 3. ⭐⭐ 서버 PDF — Gotenberg · EF doc · doc_file

```
⭐⭐ 화면 인쇄는 브라우저(ims-doc.js printDoc · 숨은 iframe) — Gotenberg 를 안 거친다 · 서버 PDF 는 메일 첨부 · 보관용만
⭐⭐ EF doc(supabase/functions/doc · _shared/doc.ts · config.toml verify_jwt=false) — action render {kind, ref, reason print|send|reprint|preview, template_id?} · url {doc_file_id} · status
     문 둘: 직원 JWT(그 JWT 로 DB 를 부른다 · RLS 그대로) · x-ims-cron-key = IMS_CRON_SECRET(service · ship_ready 거부)
     저장 documents/<kind>/<번호>-t<판>-<시각>.pdf(비공개 버킷 · 10 MB · pdf 만) + doc_file 한 줄(doc_file_add · service 만) · 돌려주는 서명 URL 120 s
⭐⭐ doc_file 은 지우지 않는다(doc_file_guard) · drive_file_id 는 한 번만(doc_file_drive_set · 드라이브 보내기 = 컷오버 뒤 · null = 아직)
⚠️ 같은 초에 같은 문서 두 장 → doc_file_path_uq 거부(미룬 255) · 쪽 수(pages)는 짐작값
Gotenberg 실물  GCP asung-ims-mail · northamerica-northeast2 · 서비스 gotenberg · gotenberg/gotenberg:8 · 기본 인증(사용자 ims · 비밀번호 Secret Manager gotenberg-basic-pass 판 1)
                · JavaScript 끔 · 2 GiB · 0 ~ 2 대 · 동시 4 · Cloud Run 요청 60 s · ⚠️ Gotenberg 자체 --api-timeout 은 기본 30 s(바꾸지 않았다)
                · Cloud Run 문 검사 끔(--no-invoker-iam-check · 문은 기본 인증) · 실행 신분 gotenberg-run@asung-ims-mail.iam.gserviceaccount.com
                · 첫 호출은 0 대에서 깨어나 ~4 s · 요청 = POST /forms/chromium/convert/html(files index.html · preferCssPageSize · printBackground)
비밀(테스트 · 이름만)  GOTENBERG_URL · GOTENBERG_USER · GOTENBERG_PASS — tools/gotenberg-secrets.sh(read -rs · 0600 파일 · secrets set --env-file) · 운영엔 없다
점검            EF doc {"action":"status"} → secrets 셋 true · gotenberg reachable · /health
```

## 4. ⭐⭐ 문서 메일 — 모르면 사고

```
⭐⭐ 길: 직원 Send(doc_mail_send commit true) → mail_outbox 한 줄 status waiting_pdf → cron 57 ims-mail-pdf → EF mail {"action":"pdf"}
         → doc_mail_pdf_claim → EF doc render(reason send · service 길) → doc_mail_attach(→ queued · attachments) → cron 55 drain → Gmail(multipart/mixed · PDF 첨부) → sent
     ship_ready 만 예외 — 화면이 직원 JWT 로 PDF 를 먼저 만들고 doc_file_id 를 넘긴다(바로 queued)
⭐⭐ 메일 기계(so-module §65 · asung-so 4-s)의 규칙이 그대로 걸린다 — mail_enabled off 면 둘 다 선다 · 시험 DB 는 받는 이 = mail_redirect_to(caleb@) · 제목 [TEST → 원래] · unknown 은 자동으로 안 건드린다
⭐⭐ 첨부가 없는 메일(백오더 알림)의 MIME 은 mail-2b 바이트 그대로 — _shared/mail.ts buildMime 의 첨부 갈래를 고치면 deno test ⑫(황금 문자열 · sha256 935c24c3…)가 지켜야 한다
⭐⭐ 자동(529) = so_invoice 의 deferrable 트리거 so_invoice_doc_mail_auto(발행이 커밋될 때) — 청구처 손님 칸이 켜져 있고 issued 일 때 한 줄
     건너뜀은 doc_mail_skip(no_email · reissue(같은 오더에 앞 인보이스) · error) — **메일 때문에 발행이 서지 않는다** · so_invoice_issue 를 고쳐 메일을 넣지 마라
⭐ 받는 이 = 판정 498 고르기(doc_mail_recipient) — 기본 연락처 → 주소 모양인 다른 활성 연락처 → 없음 · 직원은 창에서 한 주소로 고칠 수 있다 · include_in_email 은 미정(미룬 249)
⭐ 제목 · 본문 = doc_setting 의 mail_subject · mail_body 를 doc_data 로 채움(doc_mail_fill · 스칼라 {{a.b}} 만) — 줄에 박힌다(뒤에 글을 고쳐도 이미 넣은 줄은 그대로)
⭐ internal_receipt 는 메일 없음(거부) · 문서 메일 취소는 doc_mail_cancel(waiting_pdf · queued · 메모 필수) — 백오더 창구 mail_outbox_resolve 가 아니다
⭐ PDF 실패 = doc_mail_pdf_failed — 10 분 뒤 다시 · 세 번째는 failed(사람이 doc_mail_list 로 본다)
⭐ 손님 칸 final_invoice_mail 은 customer_update 로만(manager 이상 · 같은 값은 sales 도 통과) · 적재(ImsLoadCustomer)는 이 칸을 보내지 않는다
킬 스위치  PDF 단계만: select cron.alter_job(57, active := false) · 메일 전체: inv_config mail_enabled = off(admin · 먼저 이것)
⚠️ 테스트 DB 는 메일이 켜져 있고 cron 이 돈다 — 시험은 반드시 rollback · 시험에서 doc_mail_pdf_claim · mail_claim 을 부르지 마라(실제 큐를 잠근다)
```

## 5. 화면 (asung-ims · 화면 파일은 대화 Claude 가 통째로)

```
ims-doc.js        공통 — Mustache 4.2.0 을 파일 안에(CDN 아님 · define · module · exports 를 가리고 this = window · §66-e 2) · printDoc · printBtn · mailDialog · mailList · noteDialog
settings.html     Settings → Documents(set v4 · v4a) — 회사 글 · 지점 둘 · 로고 · 날짜 꼴 · 문서 다섯 탭 · 판 목록 · Check · Preview · Save · Use this version · 글 · 켜고 끄기
so-invoices.html  Print invoice · Print delivery receipt(internal_receipt) · Email to customer… · Emails 칸 · Note 고치기(inv v2f · v2g)
so-credits.html   Print credit note · Email to customer… · Emails · Note(cr v2e · v2f)
so.html           Print order · Email order… · Ship & invoice 창의 Ship Ready(인쇄 · Email Ship Ready… — PDF 먼저) · 끝낸 뒤 Print · Email invoice…(so v5t8 · v5t9)
pos.html          끝낸 판매 Print invoice(pos v1.9)
customers.html    상세 Final invoice emails 줄(cs v4b · 바꾸기 manager 이상)
Send              누르면 창을 바로 닫고 아래 안내 4 초(ims-doc v3a) · 메일은 1 ~ 2 분 뒤
```

## 6. 운영 전환 때 할 것 (mail-5 묶음 · 미룬 244 · 256 · 257)

```
마이그레이션 doc-1a ~ doc-3a2 일곱(20261019144030 · 152102 · 155731 · 172034 · 181014 · 184432 · 190500) — 앞 IMS 묶음 · 메일 여섯과 함께
EF doc · mail 배포 · 운영 비밀 GOTENBERG_URL · USER · PASS(tools/gotenberg-secrets.sh 에 IMS_PROJECT_REF) · cron 57(+ 54 ~ 56)
회사 글 · 로고 · 판 다섯을 운영 DB 로(판은 DB 가 정본) · doc_public_base_url 운영 값(운영 DB 를 어디로 하나와 함께) → [2026-10-22 · 판정 617 · so-module §70-d] 운영 = 지금 테스트 DB 그대로(승격) — 옮길 것 없음 · doc_public_base_url 도 그대로(fazgmyvzzhqybtvtktyg)
mail_redirect_to 비우기 · final_invoice_mail 손님 켜기(Caleb · 몇십 명) · GAS 정지(백오더)와 같은 날
```

## 7. 이 스킬을 갱신할 때

- 새 사실은 **정본 §66(그 뒤 절)에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄.
- `description` 은 1024자(pre-commit `scripts/check-skill-desc.sh`) · 문서 · 메일 키워드는 이 스킬에 — `asung-so` description 은 건드리지 않는다(여유 13 자 · 2026-10-19).
- 옛 문장은 `~~취소선~~ + [정정 날짜]`.
