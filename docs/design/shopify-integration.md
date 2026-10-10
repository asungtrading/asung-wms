# Shopify 연동 — 설계 정본

작성: 2026-10-08 · 회사 PC · 판정 362 ~ 381(원문 표는 `so-module.md` §53-a) · Caleb 이 판정 81 의 순서를 바꿔 1단계가 끝나기 전에 2단계 Shopify 연동 설계를 시작했다(「샤피파이와 ims를 인테그레이션 해서 … 먼저 만들어 놓고 싶어」 · `ims-principles.md` §6-c)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 Shopify 둘뿐이다. Cin7 은 「지금까지 상품을 Shopify 로 보내던 것」의 참고일 뿐이다(Caleb 「지금 설계에는 cin7을 개입시키지 말아줘」).
~~⚠️ 상태: **설계만** — 마이그레이션 · EF · 화면 없음. 만들기 순서는 매입 세금 → 할인 원가 → 상품 설명 칸 → Shopify(판정 381).~~
⭐ 상태 [2026-10-10 · so-module §56] **① 바탕 · ② 상품 보내기 실물(테스트 DB · 시험 스토어)** — DB shop-1a `584aaf0` · shop-2a1 `81d779c` · shop-2a2 `0d3eb6e` · EF shop-1b `9d67484` · shop-2b `2f6136f` · 화면 Settings → Shopify Stores(asung-ims ss v1 · v1a) · cron jobid 42 · 43 · 순서(Caleb 「그 순서로 가자」 · 2026-10-09) ① 바탕 → ② 상품 보내기 → ③ 재고 → ④ 오더 받기 → ⑤ 오더 상태 · 판정 403 ~ 413(원문 so-module §56-a)
⭐ [2026-10-10 · tag-0] 화면 shop-2c(asung-ims shop v1 · pr v5 · fam v3 `32dae11` · v1a `f3fabf9` · v1b `e563a8e` · 아래 §3-h) · 판정 414 ~ 416 · 다음 판정 번호 417

---

## 1. 스토어 (판정 362)

```
시험     시험 스토어 하나를 새로 만들어 시험한다 — Caleb 「시험 스토어는 하나로 충분해」
컷오버   실제 스토어 둘을 붙인다 — asung.ca(도매) · aonebeauty.com(매장 픽업 · 카드 결제)
설정     스토어는 IMS 안의 「설정 한 줄」 — 주소 · 열쇠 · 판매 티어 / 비교 티어 짝 · 브랜치 규칙(§4)
```
- ⭐ 실물 [2026-10-09 · so-module §56-b] 시험 스토어 **asung-ims-test.myshopify.com**(organization 「Asung Trading」 · Advanced) · Dev Dashboard 앱 **Asung IMS**(수동 · v1scopes · 권한 10 · embedded false · client credentials 24h 토큰) · 위치 Toronto · Edmonton
- ⚠️ 비밀 SHOPIFY_IMS_CLIENT_ID · SECRET 은 **테스트 프로젝트 `fazgmyvzzhqybtvtktyg`** 에만(운영 `gftpcnkxbdjzzfvzwcfl` 과 다르다)
- 설정 한 줄 = 표 `shop_store`(code · shop_domain · kind asung | aone · sale_tier_id · compare_tier_id · send_tags) · 위치 짝 = `shop_location`(Shopify 위치 GID ↔ warehouse_id · 대조는 GID 로만) · 쓰기는 admin 창구 `shop_store_save` · 화면 Settings → Shopify Stores · 위치 짝 Toronto ↔ Asung Trading Inc. · Edmonton ↔ Asung - Edmonton
- 연결 확인 = EF `shopify` action ping(scope 10 대조 · 위치 대조) · 호출 기록 `shop_call_log`(90 일)

### 1-a. 컷오버 — 보냄의 첫 상태 (판정 420)
- 스토어별 보냄(`shop_listing`)의 첫 상태 = **지금 실제 스토어** — asung.ca · aonebeauty.com 에 올라가 있는 상품을 SKU 로 맞춰 그것만 켠다 · family 는 Shopify 상품의 변형 SKU 로
- **ASS(asung.ca) · AOS(aonebeauty.com) 태그는 보냄을 정하지 않는다**(Caleb 「사실 지금은 별 의미가 없는 것 같아. 없는 것들도 많고」) — 두 태그는 다른 Cin7 태그처럼 IMS 에 남는다 · Shopify 로 보낼지는 다른 내부 표식(EDM_NoSale · BOTH_NoSale_Stock · DISC_* · 케이스 태그)과 함께 스토어 CSV 를 본 뒤
- 지금 받는 CSV 는 판정용 · **컷오버 날은 앱(Asung IMS)이 실제 스토어에서 상품 목록을 직접 읽어** 같은 규칙으로 맞춘다(Caleb 「컷오버때는 한 번 더 해야 할꺼야」)

## 2. 오더 들어오기

### 2-a. 받는 길 (판정 363)
- 웹훅 + 주기적 확인을 함께 쓴다(웹훅이 빠져도 확인이 줍는다) · Shopify 오더 번호로 두 번 들어가지 않게 한다

### 2-b. 손님 찾기 4단계 (판정 364)
```
① Shopify 계정 번호로 이어진 손님 → 그 손님
② 이메일이 IMS 손님 하나에만 있다 → 그 손님 · 이때 계정 번호를 이어 둔다
③ 이메일이 여럿에 있다 → 「확인 필요」로 멈추고 직원이 고른다 · 고르면 이어 둔다
④ 없다 → 새 손님(스토어 티어) · 이어 둔다
```
- 근거 실측(테스트 DB · Caleb 2026-10-08): 활성 연락처 이메일 9,414 중 66 개가 손님 237 명에 겹친다 · 최대 18(herabeauty) · clorebeauty 14 · bswcanada 13 · bci 6 — 체인의 회계 · 구매 이메일
- Caleb 「체인매장도 각각의 스토어 어카운트를 지녀」 — 그래서 ① 이 첫째다

### 2-c. 브랜치 (판정 365)
```
asung.ca          손님의 기본 브랜치 · 비었으면 주소로 — AB · BC · SK → Edmonton · 나머지 → Toronto
aonebeauty.com    늘 Toronto
재고로 고르지 않는다   Caleb 「인벤토리로 하게 되면 오더도 갈라지고 복잡한게 너무 많아서」
다른 브랜치 요청   IMS 의 확정 되돌리기(supervisor) → 창고 변경 → 다시 확정 — ⬜ 이 장면은 끝에서 끝 시험을 아직 안 했다
```

### 2-d. 상품 (판정 366)
- SKU 글자 그대로 찾는다(Shopify SKU = 우리 SKU) · Shopify 에서 상품을 만들지 않는다 · 웹 세트 판매는 하나뿐
- 못 찾은 줄(없음 · 꺼짐 · 판매 안 함)이 있으면 자동 확정하지 않고 **초안 + 확인 필요**

### 2-e. 가격 (판정 367)
- Shopify 금액을 쓰되 정가 · 할인을 갈라 담는다 · IMS 계산과 다르면 경고
- Shopify 가격 · 손님 기본 할인 · 딜은 앱 「Wholesale All In One」 이 웹에 같은 규칙으로 건다(Caleb) · ⬜ 앱이 할인을 오더 데이터에 남기는 모양은 시험 스토어에서 확인

### 2-f. 세금 (판정 368)
- IMS 가 계산한다(줄마다 · so-module §16) · Shopify 세금과 다르면 경고 · Caleb 「샤피파이도 줄마다 계산해」

### 2-g. 운임 (판정 369)
```
asung.ca          운임 없이 내려온다 · 출고 때 IMS 에서 넣는다
aonebeauty.com    손님이 낸 배송비를 확정 값으로 — Ship & invoice 가 고치지 않는다
무료 배송          「운임 + 운임 할인 100%」로 담는다(so-module §52 운임 할인)
                  ⚠️ 그러려면 Shopify 의 「$50 이상 Free」 배송 요금 줄을 「무료 배송 자동 할인」으로 바꿔야 한다 — 지금은 요금 조건 방식이라 원래 운임이 데이터에 없다
                  Caleb 「다로 하자」 · Shopify 에서 고치는 법은 대화 Claude 가 단계별로 알려 준다(앱 할인과 겹침 확인 포함 · so-module 미룬 148)
```

### 2-h. 결제 (판정 370)
- AONE 카드 결제는 「이미 받은 돈」으로 읽는다 · Shopify 가 수수료를 떼고 묶어 입금한 것을 맞추는 일은 회계(QBO 때) · 환불도 읽는다

### 2-i. 상태 (판정 371)
- 깨끗하면 저절로 확정 · 재고 없는 줄은 확정이 백오더로 저절로 갈라낸다(되돌리고 나누고 다시 확정할 일이 없다)

### 2-j. Shopify 에서 취소 (판정 372)
- Release 전이고 IMS 에서 손대지 않았으면 IMS 도 저절로 취소 · 아니면 Action Center 알림
- 웹 오더는 원칙상 고치지 않는다 — Caleb 「오더 변경은 원칙적으로 불가 · 캔슬하고 다시 넣거나 추가오더」

---

## 3. 나가는 쪽 — 상품 · 재고

### 3-a. 칸의 주인 (판정 373)
```
IMS           제목 · 설명 · 사진(변형별 사진 지정) · Vendor · Type · 태그 · SKU · 바코드 · 무게 · 가격 · 비교가 · 위치별 재고 · Active/Draft · 품절 판매 · 변형 구조
Shopify(사람)  Collections · 메타필드 · SEO · Shopify Category · Theme · 판매 채널 퍼블리시
```
- Caleb 「샤피파이에서 직접 고치는 것은 거의 없어」
- ⭐ [2026-10-10 · 판정 413] **Active/Draft 도 IMS** — 상품 데이터의 주인은 IMS(「IMS 주권」 · 판정 409 사진 · 410 태그 · 413 status 가 한 원칙) · status = 보냄 켜짐 + 켜진 변형 ≥ 1 이면 ACTIVE · 아니면 ARCHIVED(판정 405) · Shopify 에서 손으로 바꾼 Draft/Active 는 다음 IMS 보내기 때 덮인다 · **상품을 숨기는 정식 길 = IMS 「보냄 끄기」 하나** · 판매 채널 퍼블리시만 사람 몫(IMS 는 보내지도 건드리지도 않는다)
- ⭐ 실물(shop-2b · `_shared/shopify-product.ts` FORBIDDEN_INPUT_KEYS) — 사람 칸(collections · metafields · seo · category · templateSuffix 등)은 productSet 에 **절대 넣지 않는다**(deno test 가 증명) · 사람이 붙인 Collection 「Home page」 가 productSet 뒤에도 남았다(so-module §56-d 1)

### 3-b. 상품 모양 · 사진 (판정 374)
- Shopify 상품 하나 = IMS family 하나(옵션 · 변형)
- family 에 「웹 대표 사진」 칸 — 고르지 않으면 첫 변형의 대표 사진
- 변형마다 그 변형의 대표 사진을 지정해 올린다(지금은 변형 사진이 비어 손으로 지정 중)
- ⭐ 실물 [2026-10-09 · shop-2a1 · shop-2b] 「웹 대표 사진」 = `product_family.web_image_id`(→ product_image · 구성원 사진만 · 쓰기 shop_listing_set op family_web_image_set) · 사진 순서 web_image_id → 변형 대표 → 나머지
- ⭐ 사진은 **IMS 사진 목록으로 Shopify 를 맞춘다**(판정 409) — 목록에 없는 Shopify 사진(사람이 올린 것 · 옛 파일)은 지워진다(media_removed_unknown)
- 사진 짝: Shopify 에 올릴 때 파일 이름 = `<product_image id>.<확장자>` → Shopify CDN 주소의 **파일 이름 줄기 = product_image id** · **보내기 직전에 Shopify 상품 media 를 읽어** READY + url 인 것만 줄기로 짝(shop_media) → 짝이 있으면 `{id}` 만 보낸다 · 처리 중이거나 짝이 없으면 originalSource + `duplicateResolutionMode REPLACE`(같은 이름이면 바꿔치기 — 쌓이지 않는다 · 실물) · 직원 push 는 2 초 × 2 다시 읽기 · hash 가 같으면 직전 읽기도 없다
- alt = IMS `product.name`(payload files[].alt) — Shopify 에서 `<상품명> - <옵션 값>` 꼴로 보이는 것은 IMS 상품 이름이 그 꼴이라서 · ⚠️ 이미 짝지은 사진은 `{id}` 만 보내므로 이름을 고쳐도 Shopify alt 는 따라가지 않는다(so-module 미룬 168)

### 3-c. 보냄 · 퍼블리시 (판정 375)
- 상품마다 스토어별 「이 스토어로 보냄」 표시를 직원이 켠다
- **퍼블리시(웹에 보이기)는 Shopify 에서 사람이** — Caleb 정정 「listed, unlisted는 … 샤피파이로 제품을 보냈냐 안보냈냐 아닌가?」(보냄 ≠ 보임)
- ⭐ 실물 = 표 `shop_listing`(스토어 × family | 낱개 · is_on) · 창구 `shop_listing_set`(ims_require_write(shopify) · op listing_on · listing_off · push_now · family_web_image_set) · Shopify 쪽 짝 `shop_product` · `shop_variant` · `shop_media`
```
판정 404  세트는 기본으로 보내지 않는다 · sellable 세트만(지금 BEL43475-12 하나) 사람이 보냄을 켤 수 있다
판정 405  보냄을 끄면 ARCHIVED(지우지 않는다 · 다시 켜면 ACTIVE) · family 의 활성 구성원이 0 이 돼도 ARCHIVED · 끄기 전에 큐(shop-2a2 · 실물 큐 8)
판정 406  꺼진 구성원(not (is_active and sellable))은 변형을 지우지 않는다 — variants 목록에 그대로 담고 그 변형만 inventoryPolicy DENY + 재고 0(③) → Sold out · 이력 유지
판정 407  켜진 변형은 inventoryPolicy CONTINUE(품절이어도 오더를 받는다)
판정 413  status 도 IMS(위 3-a) · 숨기는 정식 길 = 보냄 끄기 하나
```
- ⭐ 실물(so-module §56-d 5) — 퍼블리시된 상품도 IMS 를 따라간다: 시험 스토어에서 ANN01001 을 Online Store 에 퍼블리시 → IMS 가격 바꾸기 두 번 → 온라인 스토어에 20 ~ 30 초 뒤 반영 · **퍼블리시 유지**(productSet 이 퍼블리시를 풀지 않는다) · EF 는 publish 를 부르지 않는다(payload 에 퍼블리시 칸 없음) · 퍼블리시 확인은 상품 목록 Channels 칸 · 상품의 Publishing 칸(변형 표의 「All channels」 가 아니다 · §56-f 2)

### 3-d. 재고 올리기 (판정 376)
- 바뀐 SKU 는 즉시 + 하루 몇 번 전체 맞추기 · 위치별(Shopify 위치 Edmonton · Toronto)
- Shopify 의 **Available** 에 맞춘다 — On hand 로 올리면 웹 오더가 두 번 빠진다 · ⬜ 시험 스토어에서 숫자 대조

### 3-e. 상품 정보 올리기 (판정 377 · 408 · 409 · 410 · 412 · 414)
- 바뀌면 즉시 + 새벽 전체 맞추기 · ~~IMS 가 주인인 칸은 새벽에 IMS 값으로 되돌아간다~~ → ~~⚠️ [2026-10-10 · so-module §56-f 9 · 미룬 165 · 열림 · 판정 거리] 구현은 새벽에 되돌리지 않는다~~ → ⭐ [2026-10-10 · **판정 414** · Caleb 「A」] 새벽 맞추기(ims-shop-nightly)는 지금대로 — **IMS 쪽 바뀜을 트리거가 놓친 것을 잡는 안전망**이다 · IMS 쪽 내용이 지난번 보낸 것과 같으면 Shopify 를 읽지도 쓰지도 않는다(skipped_same_hash) · Shopify 에서 사람이 손으로 고친 값(가격 · Draft 등)은 그 상품이 IMS 에서 다음에 바뀔 때 IMS 값으로 덮인다(판정 413) · 근거 판정 373 「샤피파이에서 직접 고치는 것은 거의 없어」 · 기각: 새벽에 Shopify 를 읽어 대조 · 새벽에 hash 무시하고 전부 보냄(매일 4 천여 상품을 읽거나 쓰는 비용)
- 보낼 내용 = `shop_product_payload(store, family | product)` → jsonb 한 곳(title · description_html 원문 · vendor · product_type · tags · status · options · variants · files · blocks · hash) · hash = blocks · listing_on 을 뺀 payload 의 md5 · `shop_product.last_hash` 와 같으면 안 보낸다(push `--force` 만 예외)
- ⭐ productSet 의 목록 칸(variants · files · tags …)은 **보낸 대로 맞추고 빠진 것은 지운다** — 그래서 사람 칸(collections · metafields · seo · category · templateSuffix)은 절대 보내지 않고 · 꺼진 구성원도 variants 에 담는다(판정 406)
- 판정 408 Compare-at 이 Price 와 같아도 보낸다(null 이면 안 보냄) · 판정 409 사진은 IMS 목록대로(3-b) · 판정 410 태그는 IMS 가 주인 — 지금 product_tag 0 행이라 `shop_store.send_tags` false = tags 칸을 아예 안 보낸다 · ⚠️ **Cin7 태그를 IMS 로 적재한 뒤에** SQL 로 켠다(켜면 빈 목록이 스토어 태그를 전부 지운다)
- ⭐ [2026-10-10 · 판정 417 · 418 · so-module §57] **태그 적재 실물**(테스트 DB) — `docs/probes/ImsLoadProductTag.gs`(asung-wms `c61ba04`) · product_tag **63,501 줄 · 전부 source cin7** · 종류 1,193 · 제품 12,321 · 대소문자만 다른 묶음 50 은 제품 수가 가장 많은 철자 하나로 합쳤다(판정 417 · manual > 제품 수 > 앞글자 대문자 > 대문자 수 > 사전순 · 공백 · 빈 조각 · 중복 정리 · Cin7 원본은 안 바꾼다) · IMS 에 없는 Cin7 제품 679 의 태그 2,727 줄은 버리고 목록만(판정 418 · 제품 적재를 고친 뒤 다시 돌린다) · send_tags 는 아직 false
- ⚠️ **운영 순서: 태그 적재 → send_tags 켜기 → 보냄 켜기** — payload 는 send_tags 와 상관없이 tags · send_tags 를 담고 hash 에 넣는다(shop_2a1 267 · 270 행) ⇒ 보냄을 먼저 켜면 태그 적재 · send_tags 켜기가 켜진 상품 전부를 다시 보낸다(실물: 적재 직후 큐 17 · 18 reason product_tag) · 보낼 태그의 범위(ASS · AOS · 내부 표식 · 케이스 태그)는 스토어 CSV 를 본 뒤(판정 420 · so-module 미룬 179)
- 판정 412 설명 거르기 → 3-f
- 큐 = `shop_push_queue`(대상마다 열린 줄 하나 · `shop_queue_add` 한 곳) · 큐 트리거 `*_shop_queue` 16(product · product_family · product_price · product_image · product_tag · product_barcode · ref_brand · ref_category · AFTER STATEMENT) · ⚠️ reason 은 「그 대상의 첫 트리거」 — 이름 + 가격이 함께 바뀌면 product 만 남는다(진단할 때 reason 만 믿지 않는다)
- cron [테스트 DB] **jobid 42 ims-shop-drain 1 분마다**(열린 큐가 없으면 EF 를 부르지 않는다 · 한 회차 ≤ 20 건) · **jobid 43 ims-shop-nightly 08:00 UTC**(= 토론토 04:00 EDT · 03:00 EST · shop_queue_all) · 킬 스위치 `select cron.alter_job(42, active := false);` · `(43, …)` · 기록 `supabase/ops/cron.sql`
- 실물 끝에서 끝(so-module §56-d 4): 가격 저장 → 큐 → 다음 분 cron → EF 3 초 → Shopify 반영

### 3-f. 상품 설명 (판정 381 · 401 · 402)
- IMS 자기 설명 칸(상품 · family) · 서식 편집기(굵게 · 제목 · 목록 · 링크 · 위험한 태그는 거른다)
- ~~처음 내용은 IMS 안의 cin7_description 에서 한 번 · 재적재도 이 칸을 채운다 · 그 뒤 IMS 가 주인~~ → [2026-10-09 · 판정 401 · desc-1b 9184853] **복사하지 않는다** — 값 = `coalesce(description_html, cin7_description)` · description_html null = Cin7 원문을 따른다(재적재가 바꾸면 저절로 따라감) · IMS 에서 한 번 고치면 IMS 가 주인(재적재가 안 건드린다 · 문지기 product_description_guard) · '' = 일부러 비움 · 고친 시각 · 사람이 남아 솎아내기(뷰 product_description_edited) · 되돌리기(op description_follow_cin7)
- ⭐ 보내기는 뷰 `product_description` 의 `html_effective` 만 읽는다 · 원문 칸을 직접 보내지 않는다
  → [2026-10-10 · docs-1010 실물 확인] shop-2a1 `shop_product_payload` 는 뷰를 거치지 않고 **같은 식** `coalesce(description_html, cin7_description)` 을 표에서 직접 읽는다(`20261009200731_shop_2a1_listing.sql` 224 · 250 행) — 값은 같다 · 거르기는 EF(아래)
- ⭐ 거르기(판정 402)의 허락 · 거름 목록은 화면과 Shopify 보내기가 같다 — ~~화면(asung-ims `ims-desc.js` · DOMPurify)과 **같은 규칙을 Shopify 보내기에서도**~~ → [2026-10-09 · 판정 412] **엔진은 다르다**: 화면 = DOMPurify(`ims-desc.js`) · Shopify 보내기 = EF 의 **규칙 기반** 거르기(`_shared/shopify-clean.ts` · DOMPurify + jsdom 은 Supabase Edge Runtime 에서 안 돈다 — 실측 「Requires run access」 · linkedom 은 조용히 안 거른다) + **안전장치** 거른 결과를 보내기 직전 DB `ims_html_forbidden` 에 넣어 하나라도 걸리면 그 상품은 보내지 않는다(error · 다음 상품 계속 · IMS 에서 설명을 한 번 고쳐 저장하면 풀린다) — 허락: 서식 · 표 · style= · 모든 출처 img · `ref_embed_host` 에 있는 host 의 iframe(유튜브 · 페이스북) / 거름: 그 밖의 iframe(POWR) · script · on…= · javascript: · object · embed · form · meta · link · base · 허락 출처는 표에서 읽는다(코드에 박지 않는다)
- DB 는 판별만(`ims_html_forbidden` · 창구가 저장을 막는다) · 원문(cin7_description)은 POWR 가 든 채 그대로 남는다 — 그래서 보내는 쪽이 반드시 거른다
- Caleb 「어서 세워야 해」 · 순서: 매입 세금 → 할인 원가 → 설명 칸 → Shopify

### 3-g. 가격 · 비교가 (판정 403 · 403 고침 · 408)
```
Price       스토어의 sale_tier_id — purpose sale 티어만(창구가 막는다)
Compare-at  스토어의 compare_tier_id — purpose 를 묶지 않는다(sale · compare · Price 와 같은 티어도) · 비워도 된다(null = 안 보냄) · reference 티어는 둘 다 막기
asung.ca        Price Wholesale · Compare-at wholesalespecia CAD
aonebeauty.com  Price AONE · Compare-at ComparedPrice CAD
시험 스토어     asung.ca 를 흉내(Wholesale · wholesalespecia CAD)
세일가          Wholesale All In One 앱이 정한다 — IMS 가 Compare-at 으로 세일을 표현하지 않는다
```
- 값 = `shop_tier_price`(so_price_for 와 같은 식 · purpose 를 가리지 않음 · ⬜ 같은 식 두 곳 — so-module 미룬 171) · 판정 408 같은 값이어도 보낸다
- 실물: **Compare-at < Price 도 Shopify 가 경고 없이 받는다**(ANN01001 Blue/Small Price 1.59 · Compare-at 1.49 · so-module §56-d 1)

### 3-h. 화면 — 상품 · family 의 Shopify 카드 (shop-2c · 판정 404 ~ 407 · 413 · 415 · 416)
```
자리       products.html · families.html 의 Shopify 카드(공통 파일 asung-ims ims-shop.js · imsShop.card · imsShop.wire)
한 줄      스토어마다 — 보냄 · 켠/끈 사람과 시각 · Shopify 상태 · 마지막 결과 · 에러 · 「Sending…」
Turn on / Turn off   창구 shop_listing_set 두 번 부르기(old = 화면이 본 is_on 글자) → 큐 → cron · 그 뒤 큐가 빌 때까지 4 초마다 다시 읽기(최대 2 분)
Send now   판정 415 — 큐를 거치지 않고 바로(EF shopify action push · 직원 길 · 서버가 ims_can_write('shopify')) · 결과(ok · 바뀐 것 없음 · 에러)를 그 자리에
Open in Shopify      https://admin.shopify.com/store/<도메인 앞부분>/products/<gid 숫자>
First photo on Shopify   families.html — family_web_image_set(구성원의 켜진 사진 · Default = 첫 변형 대표) → 큐 → cron
단추       권한 shopify 만 · family 구성원 상품은 family 링크만(family 로만 보낸다) · 꺼진 구성원은 sold out 안내(406) · sellable 아닌 세트는 안내만(404)
Edit 안    판정 416 — Shopify · Description · Photos 카드를 단추 없이 읽기만(제목 옆 「Save or Cancel first to change this」)
```
- 판정 416 의 이유: 세 카드는 Edit 의 Save 와 **따로 저장된다** — 사진은 올리는 순간 Storage · 설명은 자기 편집기와 비교 규칙 · Shopify 는 행동이고 늘 DB 에 저장된 값을 보낸다(Edit 중 저장 전에 Send now 를 누르면 옛 값이 간다) · 기각: 안내 한 줄만(「없어진 것처럼 보인다」)
- 켜기 · 끄기 직후 카드에 「last send ok」 와 「Sending…」 이 잠깐 함께 보일 수 있다 — EF 가 Shopify 결과를 적은 시각과 큐 줄을 닫은 시각 사이를 읽은 것 · 다음 다시 읽기(4 초)에 사라진다(결함 아님 · so-module §56-c)
- ⚠️ 창구 shop_listing_set 의 op push_now(큐에 넣기)는 남아 있지만 지금 화면 · tools 는 부르지 않는다(Send now 는 EF push · tools/shopify-push.sh push 도 EF)
- 시험 실물(2026-10-10 · 전부 통과)은 so-module §56-c · 점검 항목은 asung-ims CHECKLIST 7-zh

---

## 4. 오더 상태 · 문서

### 4-a. asung.ca (판정 378)
```
들어오는 순간     주인은 IMS
운송사 + 송장번호  넣는 순간 Shopify 에 「발송 + 송장번호」 — 손님에게 발송 메일은 Shopify 가 보낸다
Pickup · Delivery  운송사 칸의 두 항목(Delivery = 우리 차량) — 고르면 송장 없이 「발송됨」만 · 메일 없음
백오더            같은 Shopify 오더에 두 번째 발송
```

### 4-b. aonebeauty.com (판정 379)
```
Pickup 오더       운송사 Pickup 을 미리 채운다
Ship & invoice    누르는 순간 Shopify 「Ready for pickup」(손님 메일) — 서류까지 끝나 픽업 스테이션에 놓기 바로 전 (단추 이름 판정 382)
그 뒤             「Waiting for pickup」 칩 · 손님이 찾아가면 「Picked up」 단추(메일 없음)
안 찾아감          크레딧 노트(재고 복원 · 재입고 수수료는 그때 판단)
환불              직원이 Shopify 에서 하고 IMS 가 읽어 크레딧에 붙인다
```

### 4-c. 오더 문서 메일 (판정 380)
- asung.ca 직원은 오더 안에서 손님에게 최종 인보이스 · 결제 요청 · 패킹 리스트를 메일로 보낸다
- **IMS 오더 문서 메일 기능이 컷오버 전에 필요** — 인보이스 인쇄(so-module 미룬 127)가 먼저 · 미룬 147

---

## 5. ⬜ 열린 확인 거리 (시험 스토어에서)

```
① 앱(Wholesale All In One)이 할인을 오더 데이터에 남기는 모양(2-e)
② 무료 배송 자동 할인과 앱 할인의 겹침 · Shopify 설정 바꾸는 법(2-g · 대화 Claude)
③ Available 숫자 대조 — 위치별 · 웹 오더 직후(3-d)
④ 다른 브랜치로 바꾸기 장면 끝에서 끝(2-c)
⑤ 컷오버 뒤 앱 규칙(딜 · 손님 할인) 두 번 입력 — IMS 와 앱(so-module 미룬 149)
```

## 6. 갱신

- 새 판정은 so-module 의 그날 절에 원문 표 · 이 파일에는 주제별로 옮긴다(판정 번호를 단다)
- 이 문서와 so-module 표가 어긋나면 **판정 원문(so-module)이 맞다**
- [2026-10-09 · so-module §55] §3-f 를 판정 401 · 402 · desc-1b(9184853) 실물로 고침 — 복사 없음 · 보내기는 product_description 뷰만 · 거르기는 ims-desc.js 와 같은 규칙(→ 목록만 같고 엔진은 판정 412)
- [2026-10-10 · so-module §56 · docs-1010] 상태 줄 · §1 시험 스토어 실물 · §3-a 판정 413 · §3-b 사진 실물 · §3-c 판정 404 ~ 407 · 413 · 퍼블리시 유지 · §3-e 판정 408 ~ 410 · 412 · 큐 · cron 42 · 43 · 「새벽에 되돌림」 어긋남 열림 · §3-f 판정 412 · §3-g 가격(판정 403 · 403 고침 · 408) 새로
- [2026-10-10 · so-module §56 이어 붙임 · tag-0] 상태 줄에 shop-2c · §3-e 「새벽에 되돌림」 어긋남을 판정 414 로 닫음(새벽 맞추기 = 안전망) · §3-h 화면 새로(shop-2c · 판정 415 Send now 바로 · 416 Edit 안 읽기만)
- [2026-10-10 오후 · so-module §57 · stock-0] §3-e 태그 적재 실물(c61ba04 · 63,501 · 판정 417 · 418) · 운영 순서(태그 적재 → send_tags → 보냄) · §1-a 컷오버 보냄 첫 상태 새로(판정 420)
