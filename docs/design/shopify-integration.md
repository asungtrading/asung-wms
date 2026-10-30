# Shopify 연동 — 설계 정본

작성: 2026-10-08 · 회사 PC · 판정 362 ~ 381(원문 표는 `so-module.md` §53-a) · Caleb 이 판정 81 의 순서를 바꿔 1단계가 끝나기 전에 2단계 Shopify 연동 설계를 시작했다(「샤피파이와 ims를 인테그레이션 해서 … 먼저 만들어 놓고 싶어」 · `ims-principles.md` §6-c)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 Shopify 둘뿐이다. Cin7 은 「지금까지 상품을 Shopify 로 보내던 것」의 참고일 뿐이다(Caleb 「지금 설계에는 cin7을 개입시키지 말아줘」).
~~⚠️ 상태: **설계만** — 마이그레이션 · EF · 화면 없음. 만들기 순서는 매입 세금 → 할인 원가 → 상품 설명 칸 → Shopify(판정 381).~~
⭐ 상태 [2026-10-10 · so-module §56] **① 바탕 · ② 상품 보내기 실물(테스트 DB · 시험 스토어)** — DB shop-1a `584aaf0` · shop-2a1 `81d779c` · shop-2a2 `0d3eb6e` · EF shop-1b `9d67484` · shop-2b `2f6136f` · 화면 Settings → Shopify Stores(asung-ims ss v1 · v1a) · cron jobid 42 · 43 · 순서(Caleb 「그 순서로 가자」 · 2026-10-09) ① 바탕 → ② 상품 보내기 → ③ 재고 → ④ 오더 받기 → ⑤ 오더 상태 · 판정 403 ~ 413(원문 so-module §56-a)
⭐ [2026-10-10 · tag-0] 화면 shop-2c(asung-ims shop v1 · pr v5 · fam v3 `32dae11` · v1a `f3fabf9` · v1b `e563a8e` · 아래 §3-h) · 판정 414 ~ 416 · 다음 판정 번호 417
⭐ [2026-10-10 저녁 · so-module §58] **③ 재고 올리기 끝**(테스트 DB · 시험 스토어 · 끝에서 끝) — DB stock-1a `8feb7b3` · EF stock-1b `0192bf3` · 화면 stock-1c(asung-ims shop v2 `8f41b93`) · cron jobid 44 · 45 · 46 · 판정 421 ~ 425(아래 §3-d) · 다음 판정 번호 **426** · 할 일 §7(테마 글자 · Caleb)
⭐ [2026-10-10 밤 · so-module §59] 태그 보내기 = IMS 태그 전부(판정 426) · 품절 판매를 스토어마다 `shop_store.oos_policy`(판정 427) · 단종 DENY(판정 428) · 171 정리(판정 429) — DB shop-pol `8cd08a7` · 화면 ss v2(asung-ims `34ea859`) · 다음 판정 번호 **430**
⭐ [2026-10-11 · so-module §60] **④ 오더 받기 끝**(테스트 DB · 시험 스토어 · 끝에서 끝) — DB ord-1a1 `901e4c7` · ord-1a2 `98b92bd` · EF + 받은 일 표 ord-1b · 1b2 `7eeaf3a` · ord-1b3 `e425d3e` · 화면 ord-1c(asung-ims wo v1 · so v5r · nav v7 `f66419f` · wo v1a `8df43b7`) · cron 47 · 48 · 판정 430 ~ 435(아래 §2) · 다음 판정 번호 **436**
⭐ [2026-10-13 · so-module §61] **⑤ 오더 상태 판정**(조사 ful-0 · 쓰기 0 · 짓기는 아직) — 판정 436 ~ 449(아래 §4 · 4-d ~ 4-g 새로) · 다음 판정 번호 **450** · 할 일 §7(Caleb 넷)
⭐ [2026-10-13 · so-module §62] **⑤ 오더 상태 짓기 끝**(테스트 DB · 시험 스토어 · 끝에서 끝) — DB ful-1a `be5688c` · ful-2a(ful-2 `113df27`) · ful-1b `021ecc6` · ful-1c `4c476b2` · EF fulfill_drain ful-2 · 1b · ful-2c `20ec11d` · cron jobid 49 · 화면 ful-3a(asung-ims so v5s `716397d` · v5s1 `f5ac4ab`) · ful-3b(set v2 · wo v2 · bo v3a `e7409fd` · wo v2a `4a242e3` · v2b `8402402`) · 판정 450 ~ 456(아래 §4-h) · 다음 판정 번호 **457**
⭐ [2026-10-13 밤 ~ 10-14 · so-module §63] **⑤ 나가지 않을 몫 · 경고 확인함 · 결제 상태 끝**(테스트 DB · 시험 스토어) — DB ful-4a `8ae674d` · ful-4b4 `cc51dce` · ful-4b5 `4a54ee1` · ful-5a `a283ff9` · pay-1a `1971887` · pay-2a · 2b `9afa520` · EF order_drain ful-4b `71c4e13` · 4b1 `b2b4220` · 4b2 `5fce768` · 4b3 `70f1c18` · paid_drain pay-2b · cron jobid 50 · 51 · 52 · 53 · 화면 안 A(asung-ims wo v3 `8d84c68` · so v5t `b00ae2b` ~ v5t4 `7482e4b` · inv v2e `c8d0a8d` · v2e1 `3c61b75` · wo v4 `25bbeba` · v4a `2e1a3cf` · v4b `7482e4b`) · 판정 457 ~ 469(아래 §4-e · 4-g · 4-i) · 다음 판정 번호 **470**
⭐ [2026-10-14 오후 · so-module §63-h] **카드 캡처 자동 기록 · Restock 다시 보내기**(테스트 DB · 시험 스토어) — DB pay-3a `760c0d7` · stk-r1 `45a1e15` · 화면 asung-ims so v5t5 · wo v4c `26db7ef` · 판정 470 ~ 472(아래 §2-h · §3-d · §4-e · §4-g) · 다음 판정 번호 **473**
⭐ [2026-10-14 · so-module §64] **asung.ca 웹 운임 = SO 견적 운임 줄**(판정 473 · 미룬 191 닫음) — DB frt-1a `7d2a16a`(속 함수 shop_order_freight · 정보 freight_estimate_from_shopify) · 화면 asung-ims so v5t7 · wo v4d `0de7561` · ⚠️ aone 운임 「확정 · Ship & invoice 가 고치지 않음」(판정 369)은 **글에만 있고 코드 표지 없음**(so-module 미룬 236) · 다음 판정 번호 **493**
⭐ [2026-10-27 · so-module §82 · §83] **실제 두 스토어를 「연결됐지만 잠든」 채 붙임**(live · auth_mode · store_live · 판정 811 ~ 816 · 아래 §1) · **기존 상품 잇기를 실제 스토어 크기로**(plan 31 s → 2 s · apply 묶음 500 · dup_target · 판정 829 · 830 · 832 · 아래 §1-b) · **콤보 재고**(판정 831 · 아래 §3-d) — DB shop-live-1 `7747baf` · link-perf-1 `7b01fbc` · link-perf-2 `31c67c4` · link-dup-1 `f1f9c87` · link-perf-3 `52c43af` · shop-combo-1 `18ce4f0` · 화면 asung-ims ss v4 `f7d8a80` · v4a `ae4c45b` · v5 `a429201` · v5a `32d7023` · 다음 판정 번호 **833**

⭐ [2026-10-30 · so-module §90] **컷 전 웹 오더는 `ims-import` 태그만**(판정 889 · shop-cut-1 `9d61370` · 814 의 「손으로 Fulfill」 대체 · 아래 §2-a) · **asung · aone 사진 보내기 끔**(판정 890 · shop-img-off-1 `1268bd1` · 409 · 560 을 두 스토어에서 멈춤 · §3-b) · **원산지 두 글자**(판정 884 · shop-coo-1 `902937e` · §3-e) · 조사 shop-risk-0 · shop-photo-0 요지(§3-b · §5) · send_tags 는 **결정 대기**(deferred 394) · 다음 판정 번호 **891**
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
- ⭐ [2026-10-27 · 판정 811 ~ 815 · shop-live-1 `7747baf` · so-module §82] **두 스위치** — `is_active` = 연결 · 읽기(ping · link_read · link_poll · link_plan · link_apply · order_read · webhooks_list) / `live` = 일한다(상품 · 재고 · 오더 · 발송 · 결제 쓰기 · 웹훅 받기 · 주기 확인) — **일하는 길은 전부 is_active and live**
  - 창구 `shop_store_save`: **store_set** 은 live 를 켜지 않는다(새 행 live false · 있는 행 live 무접촉 · auth_mode 받음) · **store_off** 는 live 도 끈다 · **store_live** {code, live, orders_from}(admin) — 켜면 orders_polled_at = orders_from(판정 814 · Cin7 의 Shopify 연결을 끈 컷 시각) + 그 스토어 재고 **전부 force**(815 · shop_stock_queue_all)
  - live 전: 재고 대상 0(shop_stock_targets · 큐 0) · 상품 · 오더 · 발송 · 결제 큐 줄은 **열어 둔 채 대기**(EF queueGate wait) · **웹훅은 무시**(200 · 기록만 「ignored: store not live」) · 잇기(Read → Plan → Apply)는 된다 · push_batch 는 미리 보기만
  - `auth_mode`(813): client_credentials(같은 조직 · 토큰 24 h · `<PREFIX>_CLIENT_ID` · `_CLIENT_SECRET`) | stored_token(`<PREFIX>_ACCESS_TOKEN` 을 읽기만) — ⚠️ 지금 stored_token 스토어는 없다(아래 Aone)
  - cron(테스트 DB): Shopify 쪽은 **jobid 42 ~ 53**(42 · 43 상품 · 44 ~ 46 재고 · 47 · 48 오더 받기 · 49 발송 · 50 나가지 않을 몫 · **51 order_drain = 실제 orderEdit** · 52 paid-scan · **53 paid_drain = 실제 markAsPaid**) — 실제 스토어 행이 있어도 일하는 길은 live 가 막는다(행을 넣고 여러 번 돈 뒤 asung 몫 inbox · shop_order · push_queue · stock_queue · listing 전부 0 · §82-c)
  - 새 스토어를 붙일 때: **myshopify 도메인을 확인**(asung.ca 의 관리 핸들은 asung-trading · aonebeauty.com 은 aone-beauty-health) · 적용 순서 **DB → EF → 행**
- ⭐ [2026-10-27 · §82-c] **실제 스토어(테스트 DB)**

| code | 주소 | 앱 · 비밀 | live | 위치 짝 |
|---|---|---|---|---|
| asung | asung-trading.myshopify.com(asung.ca) | Asung IMS · SHOPIFY_IMS | f | Toronto → Asung Trading Inc. · Edmonton → Asung - Edmonton |
| aone | aone-beauty-health.myshopify.com(aonebeauty.com) | Asung IMS Aone(Aone 조직) · SHOPIFY_AONE | f | Aonebeauty TOR → Asung Trading Inc. · **Aonebeauty EDM 은 짝 없음**(Caleb 「이 상태로 둘께」 · §1-a 판정 427) |
| test | asung-ims-test.myshopify.com | Asung IMS · SHOPIFY_IMS | t | 둘 |

- ⭐ [2026-10-27 · 판정 809 · 812 · 813 · 816 전제 바뀜] **Aone 은 자기 Shopify 조직이 따로 있다**(「Aone Beauty Supply…」) — Aone 관리 화면 → Settings → Apps → Develop apps 로 그 조직에 전용 앱 「Asung IMS Aone」 을 만들어 설치 · **client credentials(Automatic)** · 보관 토큰 · `tools/shopify-oauth-exchange.sh`(816)는 쓰이지 않는다(코드는 남김)
- Shopify 사실(2026-10-27): client credentials 는 **앱과 스토어가 같은 조직일 때만** · Dev Dashboard 의 Distribution(설치 링크) 카드는 **Partner 조직의 앱에만** · Dev Dashboard Stores 목록에는 Dev 스토어만 보인다 · 스토어를 다른 조직으로 옮기려면 Shopify Payments 를 꺼야 한다 · 관리 화면의 옛 커스텀 앱은 2026-01-01 부터 새로 못 만든다

### 1-a. 컷오버 — 보냄의 첫 상태 (판정 420)
- 스토어별 보냄(`shop_listing`)의 첫 상태 = **지금 실제 스토어** — asung.ca · aonebeauty.com 에 올라가 있는 상품을 SKU 로 맞춰 그것만 켠다 · family 는 Shopify 상품의 변형 SKU 로
- **ASS(asung.ca) · AOS(aonebeauty.com) 태그는 보냄을 정하지 않는다**(Caleb 「사실 지금은 별 의미가 없는 것 같아. 없는 것들도 많고」) — 두 태그는 다른 Cin7 태그처럼 IMS 에 남는다 · Shopify 로 보낼지는 다른 내부 표식(EDM_NoSale · BOTH_NoSale_Stock · DISC_* · 케이스 태그)과 함께 스토어 CSV 를 본 뒤
- 지금 받는 CSV 는 판정용 · **컷오버 날은 앱(Asung IMS)이 실제 스토어에서 상품 목록을 직접 읽어** 같은 규칙으로 맞춘다(Caleb 「컷오버때는 한 번 더 해야 할꺼야」)
- ⭐ [2026-10-10 밤 · 판정 426 · 427 · 429 · so-module §59] 컷오버 때 함께 할 것:
  - **aone 스토어 행** — `oos_policy = 'deny'` · **위치 짝은 Toronto ↔ Asung Trading Inc. 하나**(Shopify 는 DENY 에서 스토어의 모든 위치 Available 을 합쳐 본다 — Edmonton 을 짝지으면 Toronto 에 없는 것도 팔린다) · aone Shopify 의 Edmonton 위치 숫자는 비우거나 판매에서 뺀다(미룬 188)
  - **asung.ca 재고 상태 태그 · 메타필드 구현을 끈다**(Caleb · `outofstock-edm` · `outofstock-tor` · `instock-edm` · `instock-tor` 태그와 Restock Date · out of stock date 메타필드를 쓰던 것) — 안 끄면 IMS 가 지운 태그를 다시 붙인다 · 메타필드는 사람 칸이라 IMS 무접촉(미룬 187)
  - **171 정리** — asung.ca 에서 단종이 아닌데 deny 인 SKU 171 개를 IMS 에서 하나씩(단종 켜기 · sellable 끄기 · 그냥 두기) · 그대로 두면 컷오버 날 CONTINUE 로 풀린다 · 검토 CSV `~/asung/prompts/csv/review-deny-171.csv`(미룬 186) · 단종 712 개 continue → DENY 는 판정 428 대로 · aone continue 21 은 스토어 설정대로 DENY

### 1-b. 기존 상품 잇기 (판정 420 실행 · 555 ~ 563 · 815 · 829 · 830 · 832 · 원문 so-module §67 · §68 · §82 · §83)

```
순서      Read(EF link_read · bulk · Shopify 읽기만) → Plan(shop_link_plan · 줄마다 판정 · version +1) → Apply(shop_link_apply · 묶음 500 · 화면 ss v5 가 되풀이 · 큐 없음 · hash 심기) → Push(shop_link_push_batch · 브랜드 · 묶음 단위 · live 만)
          live 전에도 Read · Plan · Apply 된다(815) · 컷오버 직전 Read → Plan 을 한 번 더
판정      link(하나에 하나 · family 전부 · family 일부 = partial_family 557) · link_off(Shopify DRAFT · ARCHIVED 558 · 562 — 잇되 보냄 끔)
          block — no_sku · dup_sku · not_in_ims(변형 여럿) · shape_mismatch(556) · set_not_sellable · already_linked_other · gid_linked_elsewhere · dup_target(830)
          report — not_in_ims(변형 하나) · 표시만 — inactive · discontinued · option_name_diff · sku_case · no_ims_images(559) · already_linked(멱등) · status_unknown · no_variants
          (원천: shop_link_plan 의 comment · 화면 shopify-stores.html LK_WHY — 둘이 같은 코드 열아홉)
dup_target 같은 IMS 대상(family 또는 낱개)을 이 판의 Shopify 상품 둘 이상(link · link_off)이 가리키면 전부 block · changes.dup_target {count · gids · handles}(자기 줄 빠짐 · (handle, gid) 순)
          고치기 = Shopify 에서 한 페이지로 합친다 — 남길 페이지에 사이즈를 변형으로 더하고 옛 페이지를 지운다(한 변형씩 지우기 → 추가) · Archive 로는 안 풀린다(link_off 도 센다) → Read → Plan
          기각: 하나 잇고 나머지 report(지우기를 잊으면 같은 SKU 두 번 · 옛 재고로 팔림)
속도      plan — 5,079 상품 31 s → 1.9 s(link-perf-1 · 집합 + product_sku_lower_idx) · 이어진 4,938 · 통계 낡음 약 12 s → 2.1 s(link-perf-3 · ⑤ 임시 표) · dup_target 문장 1.6 → 2.0 s
          apply — 한 번에 69.5 ~ 78.3 s → 묶음 500 × 10 · 묶음 최대 2.4 ~ 2.8 s(link-perf-2 · 판정 829) · 한 번에(p_limit null)는 16 ~ 24 s 라 화면은 늘 묶음
          (authenticated statement_timeout 8 s — 넘으면 「canceling statement due to statement timeout」)
```
- 실제 스토어 판(2026-10-27 밤 · 둘 다 Apply 안 함 · so-module §83-c): asung planned v2 · 5,079 상품 · link 4,938 · block 91 · report 50 · dup_target 16(3 묶음) · 556 모양 다름 2 · 같은 SKU 둘 30 / aone planned v1 · 4,519 · link 4,355 · block 114 · report 50 · dup_target 19(6 묶음) · 556 모양 다름 48 · 같은 SKU 둘 4
- IMS 에 없는 SKU 448 가운데 447 은 마지막 상품 적재 뒤 들어온 신제품(LAC · LAG · AS8 · AS9) — 컷오버 전 상품 재적재로 들어온다
- ⭐ **컷오버 순서: 상품 재적재 → Shopify 페이지 정리 확인 → asung · aone Read → Plan(dup_target 0) → Apply links → Cin7 의 Shopify 연결 끔 → Go live(store_live · orders_from = 끈 시각) → ~~send_tags 켜기~~ → [2026-10-30] send_tags 는 **결정 대기**(켜면 이어진 상품 전부 다시 보내기 · 약 8 시간 짐작 · 555 와 충돌 · deferred 394)** — 순서가 바뀌면 신제품이 not_in_ims 인 채 Apply 된다 · 명령 · 확인 · 멈춤은 reload-procedure §P-2 13b
- 열림: apply 의 옛 dup 갈래(「뒤의 것이 이김」) → 「거부 · plan again」(deferred 355) · 556 모양 다름 aone 48 · asung 2 줄마다 보기(deferred 357)

## 2. 오더 들어오기

### 2-a. 받는 길 (판정 363 · 431 ① · 실물 ord-1b · 1b3)
- 웹훅 + 주기적 확인을 함께 쓴다(웹훅이 빠져도 확인이 줍는다) · Shopify 오더 번호로 두 번 들어가지 않게 한다
- [2026-10-11 · so-module §60] 실물 모양:
```
웹훅          Shopify → EF shopify(헤더 X-Shopify-Topic 이 있으면 이 길) · HMAC = 그 스토어 secret_prefix 의 CLIENT_SECRET · 몸(REST 모양)에서 오더 GID 만 → 받은 일 표(shop_order_inbox) → 바로 200
              구독 셋 ORDERS_CREATE · UPDATED · CANCELLED(shop-specific · webhooks_subscribe · 권한 manager = shopify)
              orders/updated 가 orders/create 보다 먼저 오기도 한다 → 받은 일은 오더마다 열린 줄 하나라 한 줄로 합쳐진다
주기 확인      cron 48 · 15 분 · orders(updated_at:> 마지막 − 5 분) → **바뀐 오더만** 받은 일에(updatedAt 을 shop_order.shopify_updated_at 과 견줌 · ord-1b3)
drain         cron 47 · 1 분 · 받은 일 → GraphQL 로 다시 읽기 → shop_order_ingest(원문 먼저 · 판정 431 ①) → received 면 shop_order_process → SO
              그 뒤 받은 일 없이 received 인 오더(직원이 풀었다)를 저장된 원문으로 process(sweep)
60 일          지난 오더는 끌어오지 않는다(read_all_orders 신청 안 함)
```
- ⭐ [2026-10-30 · **판정 889** · shop-cut-1 `9d61370` · so-module §90] **컷 전 웹 오더** — 스토어마다 `shop_store.orders_cut_at`(붙박이 컷 시각 · live 가 false → true 로 처음 켜질 때 트리거 `shop_store_cut_on_live` 가 orders_polled_at(store_live 의 orders_from)을 한 번 베낀다 · null = 막기 꺼짐)
```
막기      Shopify createdAt 이 컷 시각보다 앞선 오더는 IMS 에 아직 없으면 **어떤 길로도 저절로 안 받는다**(poll · 웹훅 · 다음 달 환불 · Capture · 메모로 바뀌어도)
          막힌 오더는 inbox 에 안 쌓고 shop_call_log 에 「skipped_cut N (… #이름)」 · ingest 도 막는다(shop_order_import_tagged)
통과      Shopify 오더 태그 `ims-import`(대소문자 · 앞뒤 빈칸 무시 · 낱말 하나) — poll 이 createdAt · tags 를 읽는다
          ⚠️ 태그는 **18:00(컷) 뒤에** 단다 — 앞에 달면 그 오더의 바뀐 시각(updatedAt)이 컷 앞이라 poll 이 안 읽는다(지웠다 다시 달면 됨)
          들어온 뒤에는 태그를 지워도 된다(그 오더는 평소대로 Shopify 를 따라간다) · 그 오더를 IMS 에서 손으로 다시 만들지 않는다
대체      판정 814 의 「그 전에 들어와 안 나간 웹 오더는 Shopify 에서 손으로 Fulfill」 을 대체
고치기    orders_cut_at 은 지금 SQL 로만(update public.shop_store set orders_cut_at = … where code = …) · 화면 · store_set 칸은 deferred 392
실물      테스트 스토어 #1038(태그) → SO-25277 · #1039(태그 없음) → skipped_cut
```
- 직원 안내(영어 · 10-30 Caleb 에게 준 글): 「After 6 pm today, for every web order that was still open in Cin7, add the tag ims-import to the order in Shopify; it comes into IMS at the next 15-minute poll. Orders created before 6 pm without that tag stay with Cin7 and never come in, even if they are later captured, refunded or edited. Once an order is in IMS you may remove the tag — it keeps following Shopify as usual.」 · 매뉴얼 1 장 sales-web-orders 에 같은 뜻(옛 시스템 이름 없이)
- ⚠️ [shop-risk-0] 실제 두 스토어는 웹훅 구독 **0** — 오더는 15 분 poll(cron 48)로만 들어온다(deferred 401)
- **보호된 손님 정보는 신청 없이 된다(확정 · 2026-10-11 · order-read #1001)** — 손님 · 이메일 · 전화 · 주소가 다 읽힌다 · Dev Dashboard 에 신청 칸 없음

### 2-b. 손님 찾기 4단계 (판정 364)
```
① Shopify 계정 번호로 이어진 손님 → 그 손님
② 이메일이 IMS 손님 하나에만 있다 → 그 손님 · 이때 계정 번호를 이어 둔다
③ 이메일이 여럿에 있다 → 「확인 필요」로 멈추고 직원이 고른다 · 고르면 이어 둔다
④ 없다 → 새 손님(스토어 티어) · 이어 둔다
```
- 근거 실측(테스트 DB · Caleb 2026-10-08): 활성 연락처 이메일 9,414 중 66 개가 손님 237 명에 겹친다 · 최대 18(herabeauty) · clorebeauty 14 · bswcanada 13 · bci 6 — 체인의 회계 · 구매 이메일
- Caleb 「체인매장도 각각의 스토어 어카운트를 지녀」 — 그래서 ① 이 첫째다

### 2-c. 브랜치 (판정 365 → 430)
```
~~asung.ca          손님의 기본 브랜치 · 비었으면 주소로 — AB · BC · SK → Edmonton · 나머지 → Toronto~~ → 판정 430
asung.ca          **배송지 주 먼저** — AB · BC · SK → Edmonton · 그 밖 → Toronto · 주가 없으면 손님 기본(Caleb 「배송지 주를 먼저 본다 A가 맞아 보여」)
                  근거: 손님 9,469 중 기본 Edmonton 135 뿐 · 배송지 AB 손님도 기본 Toronto 667 · Edmonton 86 — 손님 기본은 지역을 말하지 않는다
aonebeauty.com    늘 Toronto(위치 짝이 하나뿐인 스토어는 그것 · 판정 427)
⚠️ Edmonton 은 창고 이름(%edmonton%)으로 찾는다 — ref_warehouse 에 지역 칸이 없다(so-module 미룬 192)
재고로 고르지 않는다   Caleb 「인벤토리로 하게 되면 오더도 갈라지고 복잡한게 너무 많아서」
다른 브랜치 요청   IMS 의 확정 되돌리기(supervisor) → 창고 변경 → 다시 확정 — ⬜ 이 장면은 끝에서 끝 시험을 아직 안 했다
```

### 2-d. 상품 (판정 366)
- SKU 글자 그대로 찾는다(Shopify SKU = 우리 SKU) · Shopify 에서 상품을 만들지 않는다 · 웹 세트 판매는 하나뿐
- 못 찾은 줄(없음 · 꺼짐 · 판매 안 함)이 있으면 자동 확정하지 않고 **초안 + 확인 필요**

### 2-e. 가격 · 할인 어긋남 (판정 367 · 431 · 433)
- Shopify 금액을 쓰되 정가 · 할인을 갈라 담는다 · IMS 계산과 다르면 경고
- Shopify 가격 · 손님 기본 할인 · 딜은 앱 「Wholesale All In One」 이 웹에 같은 규칙으로 건다(Caleb) · ~~⬜ 앱이 할인을 오더 데이터에 남기는 모양은 시험 스토어에서 확인~~ → ✅ asung.ca 오더 CSV 50(so-module §60-b): 앱 오더 47 은 **할인을 줄마다**(Lineitem price = 정가 · Lineitem discount) · 할인 코드 0 · 운임 0 · NetTerm · pending · 앱은 시험 스토어에 설치할 수 없었다
```
판정 431    Caleb 「할인은 현재는 cin7과 샤피파이 wholesale all in one을 동기화하기 어려워서 양쪽에 똑같이 만들어서 쓰고 있어」 → 「그대로 짓자」
            줄 = 손님이 본 정가 · 할인 그대로 · discount_source **shopify** · 만든 사람 = 시스템 직원(Shopify)
            IMS 규칙 계산과 다르면 경고 discount_mismatch(SKU · Shopify % · IMS %) · 정가가 다르면 list_price_mismatch — 두 곳 손 맞추기의 안전망 · 값은 바꾸지 않는다
판정 433    shopify 줄은 다시 매기기(so_line_requote · so_line_update · so_reprice)에서 건너뛴다 — 직원이 수량 · 손님을 바꿔도 할인 % 그대로
            ⚠️ 같은 SKU 를 직원이 더 넣으면 shopify 줄에 합쳐진다(할인 % 그대로 · 수량만 · 미룬 194)
오더 전체 할인  0 으로 두고 경고 order_discount_dropped(ord-1a2 이견 6 · 기본으로 둔 것)
```

### 2-f. 세금 (판정 368)
- IMS 가 계산한다(줄마다 · so-module §16) · Shopify 세금과 다르면 경고 · Caleb 「샤피파이도 줄마다 계산해」

### 2-g. 운임 (판정 369)
```
asung.ca          운임 없이 내려온다 · 출고 때 IMS 에서 넣는다
                  ⚠️ [2026-10-11 · CSV] 앱 오더(NetTerm)는 운임 0 이 맞지만 **~~일반 웹 결제~~ → custom 결제 방식 3 중 2 가 운임을 받았다**(→ so-module §61-c · 결제는 50 모두 pending)(AS-6994 Expedited Parcel 11.69 · AS-6995 13.92) — 판정은 열어 둠(Caleb 조사 · 미룬 191) · 지금은 받은 오더에 금액 · 제목만 · SO 운임 줄 없음 · 경고 freight_not_applied
                  → [2026-10-14 · 판정 473 · so-module §64] **asung 종류 스토어 · Shopify 운임 > 0 이면 SO 운임 줄에 견적으로**(결제 방식 이름 무관 · 「Pay on Invoice」 가 asung.ca 의 유일한 수동 결제 방식) · Ship & invoice 에서 실제 운임으로 고친다 · 정보 freight_estimate_from_shopify(처리됨) · freight_not_applied 더 안 붙임 · NetTerm 앱 오더는 운임 0 이라 그대로 · frt-1a `7d2a16a`
aonebeauty.com    손님이 낸 배송비를 확정 값으로 — Ship & invoice 가 고치지 않는다
                  ⚠️ [2026-10-14 · frt-1a 이견 1] 이 「확정」 은 **글에만 있고 코드 표지가 없다** — 지금 코드로는 aone 운임도 Ship & invoice 에서 고칠 수 있다 · aone 운영 전에 고정 표지를 둘지(so-module 미룬 236 · 옛 「474 후보」 — 판정 아님)
무료 배송          「운임 + 운임 할인 100%」로 담는다(so-module §52 운임 할인)
                  ⚠️ 그러려면 Shopify 의 「$50 이상 Free」 배송 요금 줄을 「무료 배송 자동 할인」으로 바꿔야 한다 — 지금은 요금 조건 방식이라 원래 운임이 데이터에 없다
                  Caleb 「다로 하자」 · Shopify 에서 고치는 법은 대화 Claude 가 단계별로 알려 준다(앱 할인과 겹침 확인 포함 · so-module 미룬 148)
```

### 2-h. 결제 (판정 370)
- AONE 카드 결제는 「이미 받은 돈」으로 읽는다 · Shopify 가 수수료를 떼고 묶어 입금한 것을 맞추는 일은 회계(QBO 때) · 환불도 읽는다
- [2026-10-13] 환불을 읽은 뒤 = 판정 440(4-e) · Net 오더를 IMS 가 Paid 로 알리기 = 판정 449(4-e · 옆 길)
- [2026-10-14] 결제는 IMS 에서만 기록한다 — Shopify 에서만 결제 표시되면 경고 paid_in_shopify(판정 468) · IMS 에서 다 결제되면 IMS 가 Shopify 를 Paid 로(판정 469 · 4-e)
- [2026-10-14 오후] SO 가 생긴 뒤의 Shopify 카드 캡처(CAPTURE · SALE · gateway 가 manual 아님)는 받기가 IMS 결제로 적는다 — 거래 GID 표지로 두 번 적지 않음 · manual 은 그대로 468 경고(판정 470 · 4-e) · 운영 사실: asung.ca 는 전부 Net · aone 은 카드 · PayPal 을 직원이 수동 Capture → aone 결제는 470 이 덮고 370 ⑦ 은 그대로 · ⑦ 을 gateway 로 가르는 것은 조건 셋 전에(판정 471 · 4-e · so-module 미룬 230)

### 2-i. 상태 (판정 371)
- 깨끗하면 저절로 확정 · 재고 없는 줄은 확정이 백오더로 저절로 갈라낸다(되돌리고 나누고 다시 확정할 일이 없다)

### 2-j. Shopify 에서 취소 (판정 372 → 434)
- Release 전이고 IMS 에서 손대지 않았으면 IMS 도 저절로 취소 · 아니면 Action Center 알림
- 웹 오더는 원칙상 고치지 않는다 — Caleb 「오더 변경은 원칙적으로 불가 · 캔슬하고 다시 넣거나 추가오더」
- [판정 434 · Caleb 「그렇게 정하자」] **「손대지 않았음」 = SO 가 만들어진 뒤(so_baseline_at) IMS 에서 so · 줄 · 운임이 한 번도 안 바뀜** — 조심스러운 쪽
```
SO 전(received · needs_review · error)   그냥 닫는다(closed_before_so · error 도 — ord-1b2)
SO draft | confirmed + 안 바뀜          시스템이 so_cancel → 자동 취소(경고 auto_cancelled 하나 · 「손으로 확인」 경고는 붙이지 않는다 — ord-1b2) · 실물 18 초
바뀜(changed_in_ims) · 창고 뒤(in_warehouse)   경고만 cancel_needs_review(+ updated_after_so · cancelled_in_shopify) · SO 무접촉
취소 실패                               cancel_failed
```
- Shopify 에서 오더가 바뀌면(취소 아님) SO 는 무접촉 · 경고 updated_after_so(실물 #1002 메모 고침)

### 2-k. 화면 — Web Orders · 채널 × 들어온 길 (판정 432 · 435 · asung-ims ord-1c)
```
Web Orders(shopify-orders.html · Sales 탭 · 열쇠 sales)   받은 웹 오더 목록 · 상세(손님 · 브랜치 · 줄 · 까닭 · 경고 · SO 링크 · Shopify 관리자 링크) · 손님 고르기 · 못 찾은 줄 고르기 · 지금 처리(shopify)
                                                          Open SO = so.html?so=<SO 번호>(wo v1a)
새 손님(판정 432)   웹으로 처음 온 손님은 시스템 직원이 만들고 바로 검토 완료 · 첫 오더도 자동 확정
채널(판정 435)      **Warehouse 그대로** · 들어온 길 = so.intake shopify — Caleb 「B가 맞을 것 같아」 → 「A로 바꾸자」(대화 Claude 「A 로도 통계는 intake 로 가른다」)
                   Sales Orders 목록 Channel 「Warehouse · Shopify」 · 필터 Shopify (web) · 상세 칩 「From Shopify · #ref」(→ Web Orders)
통계 · 보고서       「채널 × 들어온 길(intake) × 웹 스토어」 로 나눈다 — 예: asung.ca 웹 매출 = intake shopify + 스토어 asung
```

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
- ⭐ 사진은 **IMS 사진 목록으로 Shopify 를 맞춘다**(판정 409) — 목록에 없는 Shopify 사진(사람이 올린 것 · 옛 파일)은 지워진다(media_removed_unknown) → [2026-10-30 · 판정 890] **asung · aone 은 사진을 보내지 않는다**(아래)
- ⭐⭐ [2026-10-30 · **판정 890** · shop-img-off-1 `1268bd1` · `20261030192911` · so-module §90] 스토어마다 **`shop_store.send_images`**(기본 true) — false 면 payload 의 files [] · 변형 image_id null(판정 559 꼴) · EF 가 files 키 · 변형 file 을 안 보낸다(안전띠) ⇒ Shopify 사진이 그대로 · 값 · 재고 · 제목 · 설명 · 상태 · 태그는 평소대로
  - **asung · aone = false**(10-30) · 시험 스토어 true · 사진은 hash 밖(사진만 바뀐 일 → skipped_same_hash) · false → true 로 켜는 순간 스토어 트리거가 켜진 listing 전부를 상품 큐에(사진이 그때 나간다) · 끄기는 줄 0 · 바꾸기 = SQL(화면 칸 · 뷰 칸 · 새 스토어 기본값은 deferred 388)
  - ⚠️ Apply links **전에** 적용해야 했다(nightly 가 전부 다시 안 보내게) — 10-30 Apply 전에 적용함
  - ⇒ 판정 409 · 560(Cin7 이 올린 사진을 IMS 사진으로 다시 올림)은 두 스토어에서 **멈춤** · 다시 켜는 것은 Shopify 전용 사진을 IMS 로 가져온 뒤(deferred 387)
  - 확인 거리: 브랜드별 첫 push 때 상품 하나가 Shopify 사진 그대로인지(deferred 395 · REST 둘째 겹 대신)
- [2026-10-30 · 조사 shop-photo-0 · 읽기만 · 890 의 근거] 첫 push 때 그 상품의 Shopify media **전부** 지워지고 IMS 파일을 새로 올린다(짝 0) · 같은 그림 asung 15,976(중복 4,817) · aone 12,702(중복 3,385) · **Shopify 전용(그림 손실) asung 1,849 장 · 971 상품 · aone 1,415 장 · 751 상품**(`…fam` 패밀리 표지 419 · 394 — Cin7 패밀리 첨부일 수 있고 IMS 는 제품 단위라 자리 없음 · pricebreak 370 · 108 · 옛 GUID 345 · 260 · 색상 코드 131 · 117) · Cin7 → IMS 사진 가져오기 빈 곳은 skip 23 뿐 · 구성원 primary 사진 없는 변형 asung 218 · aone 179
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
          → [판정 425] 재고 0 은 IMS 가용과 상관없이(stock-1b 실물) · 손님 글자는 테마 「Sold out」 → 「Not available」(§7 · 사람 몫)
판정 407  ~~켜진 변형은 inventoryPolicy CONTINUE(품절이어도 오더를 받는다)~~ → 판정 427 · 428 로 바뀜(아래)
판정 427  품절 판매는 스토어마다 — shop_store.oos_policy · asung.ca continue · aonebeauty.com deny(Toronto 재고만) · 시험 스토어 continue
판정 428  단종(is_discontinued) 변형은 스토어 설정과 상관없이 DENY — 남은 재고까지만 · 재고 숫자는 그대로(0 으로 만들지 않음)
          ⇒ inventoryPolicy = 꺼진 구성원 DENY(+ 재고 0 · 406) → 단종 DENY(428) → 스토어 deny → DENY → 그 밖 CONTINUE(shop_variant_payload · shop-pol 8cd08a7)
판정 413  status 도 IMS(위 3-a) · 숨기는 정식 길 = 보냄 끄기 하나
```
- ⭐ 실물(so-module §56-d 5) — 퍼블리시된 상품도 IMS 를 따라간다: 시험 스토어에서 ANN01001 을 Online Store 에 퍼블리시 → IMS 가격 바꾸기 두 번 → 온라인 스토어에 20 ~ 30 초 뒤 반영 · **퍼블리시 유지**(productSet 이 퍼블리시를 풀지 않는다) · EF 는 publish 를 부르지 않는다(payload 에 퍼블리시 칸 없음) · 퍼블리시 확인은 상품 목록 Channels 칸 · 상품의 Publishing 칸(변형 표의 「All channels」 가 아니다 · §56-f 2)
- ⭐ [shop-pol `8cd08a7`] 스토어 칸(oos_policy · send_tags · sale_tier_id · compare_tier_id)을 바꾸면 트리거 `shop_store_shop_queue_u` 가 그 스토어의 켜진 대상 전부를 상품 큐에(reason store) · 화면 Settings → Shopify Stores(ss v2)의 「Sell when out of stock」 Allow | Don't allow · blocks no_price 의 「켜진 변형」 = is_active and sellable(inventoryPolicy 가 아니다)

### 3-d. 재고 올리기 (판정 376 → 421 ~ 425 · so-module §58)
- ~~바뀐 SKU 는 즉시 + 하루 몇 번 전체 맞추기 · 위치별(Shopify 위치 Edmonton · Toronto)~~ → 아래 판정 421 ~ 423
- Shopify 의 **Available** 에 맞춘다 — On hand 로 올리면 웹 오더가 두 번 빠진다 · ~~⬜ 시험 스토어에서 숫자 대조~~ → ✅ 대조 끝(2026-10-10 · 아래 실물)
```
숫자 (421)   위치마다 IMS 가용 = inv_available_base(장부 − 판매 예약 − 트랜스퍼 예약) · 음수 0 · 버퍼 없음
            세트 ⌊낱개 가용 ÷ pack_factor⌋ · 꺼진 구성원 0(IMS 가용과 상관없이 · 425)
보내기 (421)  Shopify Available 에 직접(name available · On hand 아님) · 비교 없이 changeFromQuantity null(IMS 주권)
            · @idempotent 키(큐 줄 id 포함 — 새벽에 같은 수량을 다시 보내도 「이미 처리됨」으로 막히지 않게)
            · 위치가 아이템에 안 붙었으면 inventoryActivate 먼저(nodes 로 읽어 없는 짝만)
줄 (422)     상품 큐와 따로 shop_stock_queue(스토어 × 변형) · 묶어 보낸다(한 호출 100 · 짐작) · 마지막으로 보낸 숫자(shop_stock_sent · 위치 단위)와 같으면 안 보냄
즉시 (421)   inv_ledger · so_reserve · inv_transfer(+ line) · product · shop_listing 트리거 13 → 큐 → cron 1 분(ims-stock-drain) → [2026-10-27 · 831] + product_bom 3 = **16**
낮 (423)     매시 정각 diff — 지금 가용 vs 보낸 숫자 · 다른 것만 줄에(Shopify 호출 0)
새벽 (423)   08:15 UTC 전부 force — Shopify 쪽 어긋남(웹 오더 · 사람 손)을 IMS 값으로 덮는 안전망
            · 상품 새벽(414 · 덮지 않음)과 다른 까닭 = 재고는 Shopify 가 오더마다 스스로 바꾼다
꺼짐 (425)   꺼진 구성원 = DENY + 재고 0 · ARCHIVED(보냄 꺼짐)는 재고를 안 보낸다 · 끄는 순간에도 안 보냄 · 다시 켜면 전부(force)
콤보 (831)   [2026-10-27 · shop-combo-1 `18ce4f0` · so-module §83] 콤보(product_bom 에 켜진 줄이 있는 부모) = 위치마다 min(구성품 재고 키마다 ⌊가용 ÷ need_ea⌋)
            · need_ea = 콤보 하나에 드는 낱개(quantity × 구성품 pack_factor · 재고 키 coalesce(parent_product_id, id)로 묶음) · SO 화면 가용(so_lines_available)과 같은 셈
            · 구성품 하나라도 꺼짐(is_active false · sellable false) 또는 가용 0 → 콤보 0 · is_off 는 콤보 자신 기준 · 콤보 자신의 장부 잔고는 보지 않는다
            · Release 한 콤보(켜진 줄 0)는 낱개 갈래(자기 가용 · 보통 0)
            · 큐: shop_stock_queue_add 가 바뀐 상품(또는 그 재고 키)을 구성품으로 가진 콤보를 더한다 — 트리거 · diff · nightly 가 다 이 한 곳을 지난다
            · product_bom 트리거 셋(i · u · d · AFTER STATEMENT) — 콤보 정의 · Release 가 그 콤보를 force 로 큐에(reason product_bom · update 는 바뀐 줄만)
            · 실물: 콤보 17 × 위치 2 = 34 줄 SO 셈과 같음 · 기각: 콤보 재고 추적 끔(asung.ca · aonebeauty.com 에서 콤보가 지금 팔린다)
```
- 큐 넣기 한 곳 `shop_stock_queue_add`(낱개 → 그 sellable 세트로 펼침 · [831] 그 콤보로 펼침 · 열린 줄 하나) · 보낼 숫자 한 곳 `shop_stock_payload(store, pids)` · 화면 뷰 `shop_stock_list` · 마이그레이션 `20261010194732_stock_1a_queue.sql`
- EF `shopify` action **stock_drain**(cron · 한 회차 열린 줄 ≤ 500 · 40 s · 못 보낸 줄은 열어 둠) · **stock_push**(직원 · 화면 「Send stock now」 · 대상 하나 force) · 순수 함수 `_shared/shopify-stock.ts`
- cron [테스트 DB] **jobid 44 ims-stock-drain `* * * * *`**(열린 재고 줄이 없으면 EF 를 안 부른다) · **45 ims-stock-diff `0 * * * *`** · **46 ims-stock-nightly `15 8 * * *`**(상품 nightly 43 · 08:00 뒤 15 분) · 킬 스위치 `select cron.alter_job(44, active := false);` · `(45, …)` · `(46, …)` · 기록 `supabase/ops/cron.sql`
- ⭐ 실물(2026-10-10 · so-module §58-c): 첫 손 drain ok 11 · 22 숫자 · activate 11(Edmonton) · calls 13 · cost 147 · 6 s · ANN03907 Toronto 43 · Edmonton 1(Available = On hand · Committed 0) · ANN01001 Blue/Small 32 · 8 · **원장 −1 → 48 초 뒤 Shopify 42**(사람 손 없이 · Edmonton 은 안 보냄 = 위치 단위) · 구성원 끄기 → 0 · 0 · Sell when out of stock Off → 켜기 → 57 · 5 · On
- 화면 = §3-h(shop v2)
- ⭐ [2026-10-14 오후 · **판정 472** · stk-r1 · so-module §63-h] **Shopify 안에서 재고가 돌아오면 그 SKU 를 IMS 값으로 다시 보낸다** — 밀기는 IMS 가 움직일 때만 줄에 들어가고 보낸 숫자와 같으면 안 보내므로(422) Shopify 의 Restock(+1)이 다음 IMS 변동까지 남았다(실측 ANN01002 Toronto 보냄 34 · Shopify 35)
```
받기가 넣는다   ① 새 환불의 restockType CANCEL · RETURN · LEGACY_RESTOCK 줄(NO_RESTOCK 만 뺌 · 463 0 원 메아리 · 466 흡수와 무관)
              ② IMS 오더 고치기(order_drain · restock true) — Shopify 가 0 원 Refund 의 CANCEL 줄로 남겨 ① 에 잡힌다(실측 #1009 · #1011)
              ③ 처음 본 Shopify 취소 — 취소 원문에 restock 표지가 없어 그 오더 줄 제품 전부 · SO 생기기 전 취소는 넣지 않음(IMS 예약이 없었다 · 짐작)
넣기           shop_stock_queue_add(스토어 · 제품들 · reason shopify_restock · force) 그대로 — 열린 줄 하나 · 낱개면 sellable 세트 더함 · 켜진 listing 만 · 다음 ims-stock-drain(1 분)이 Available 을 IMS 값으로 덮는다(force 는 skipped_same 을 넘는다)
안전망         새벽 force(423 · cron 46 ims-stock-nightly 08:15 UTC)가 이미 있었다 — 어긋남은 길어야 다음 새벽까지였고 472 는 그 공백을 메운다
물건이 돌아왔다  IMS 크레딧 노트로 IMS 재고를 올리는 것이 맞는 길(그러면 저절로 다시 보내진다)
손으로         제품 화면 Shopify 카드 「Send stock now」(stock_push · force · 큐 없이)는 **family 단위**(ANN01001 ~ 01015 한 번에)
실물           #1013 Shopify 취소(Restock) 19:41:56 → ANN01005 Toronto +1 → 19:42:01 큐 shopify_restock force → 19:43:06 drain ok → Toronto 0(IMS 값)
```

### 3-e. 상품 정보 올리기 (판정 377 · 408 · 409 · 410 · 412 · 414)
- 바뀌면 즉시 + 새벽 전체 맞추기 · ~~IMS 가 주인인 칸은 새벽에 IMS 값으로 되돌아간다~~ → ~~⚠️ [2026-10-10 · so-module §56-f 9 · 미룬 165 · 열림 · 판정 거리] 구현은 새벽에 되돌리지 않는다~~ → ⭐ [2026-10-10 · **판정 414** · Caleb 「A」] 새벽 맞추기(ims-shop-nightly)는 지금대로 — **IMS 쪽 바뀜을 트리거가 놓친 것을 잡는 안전망**이다 · IMS 쪽 내용이 지난번 보낸 것과 같으면 Shopify 를 읽지도 쓰지도 않는다(skipped_same_hash) · Shopify 에서 사람이 손으로 고친 값(가격 · Draft 등)은 그 상품이 IMS 에서 다음에 바뀔 때 IMS 값으로 덮인다(판정 413) · 근거 판정 373 「샤피파이에서 직접 고치는 것은 거의 없어」 · 기각: 새벽에 Shopify 를 읽어 대조 · 새벽에 hash 무시하고 전부 보냄(매일 4 천여 상품을 읽거나 쓰는 비용)
- 보낼 내용 = `shop_product_payload(store, family | product)` → jsonb 한 곳(title · description_html 원문 · vendor · product_type · tags · status · options · variants · files · blocks · hash) · hash = blocks · listing_on 을 뺀 payload 의 md5 · `shop_product.last_hash` 와 같으면 안 보낸다(push `--force` 만 예외)
- ⭐ productSet 의 목록 칸(variants · files · tags …)은 **보낸 대로 맞추고 빠진 것은 지운다** — 그래서 사람 칸(collections · metafields · seo · category · templateSuffix)은 절대 보내지 않고 · 꺼진 구성원도 variants 에 담는다(판정 406)
- 판정 408 Compare-at 이 Price 와 같아도 보낸다(null 이면 안 보냄) · 판정 409 사진은 IMS 목록대로(3-b · → asung · aone 은 890 으로 사진 안 보냄) · 판정 410 태그는 IMS 가 주인 — 지금 product_tag 0 행이라 `shop_store.send_tags` false = tags 칸을 아예 안 보낸다 · ⚠️ **Cin7 태그를 IMS 로 적재한 뒤에** SQL 로 켠다(켜면 빈 목록이 스토어 태그를 전부 지운다)
- ⭐ [2026-10-10 · 판정 417 · 418 · so-module §57] **태그 적재 실물**(테스트 DB) — `docs/probes/ImsLoadProductTag.gs`(asung-wms `c61ba04`) · product_tag **63,501 줄 · 전부 source cin7** · 종류 1,193 · 제품 12,321 · 대소문자만 다른 묶음 50 은 제품 수가 가장 많은 철자 하나로 합쳤다(판정 417 · manual > 제품 수 > 앞글자 대문자 > 대문자 수 > 사전순 · 공백 · 빈 조각 · 중복 정리 · Cin7 원본은 안 바꾼다) · IMS 에 없는 Cin7 제품 679 의 태그 2,727 줄은 버리고 목록만(판정 418 · 제품 적재를 고친 뒤 다시 돌린다) · send_tags 는 아직 false
- ⚠️ **운영 순서: 태그 적재 → send_tags 켜기 → 보냄 켜기** — payload 는 send_tags 와 상관없이 tags · send_tags 를 담고 hash 에 넣는다(shop_2a1 267 · 270 행) ⇒ 보냄을 먼저 켜면 태그 적재 · send_tags 켜기가 켜진 상품 전부를 다시 보낸다(실물: 적재 직후 큐 17 · 18 reason product_tag) · 보낼 태그의 범위(ASS · AOS · 내부 표식 · 케이스 태그)는 스토어 CSV 를 본 뒤(판정 420 · so-module 미룬 179)
- ⭐ [2026-10-10 밤 · **판정 426**] 보내는 태그 = **IMS 태그 전부**(내부 표식 ASS · AOS · EDM_NoSale · BOTH_NoSale_Stock · DISC_* · 케이스 태그 포함 — 지금 Cin7 도 전부 올린다 · 판정 420 이 미룬 답) · asung.ca 의 재고 상태 태그(outofstock-edm 656 · outofstock-tor 624 · instock-edm 95 · instock-tor 56)는 IMS 가 태그를 보내면 사라진다(그대로 둔다 · 그 구현은 컷오버 때 끈다 §1-a) · 시험 스토어 send_tags **켜짐**(실물: ANN01001FAM 7 · ANN03907 11 태그 · so-module §59-d) · ⚠️ 창구 shop_store_save 는 send_tags 를 받지 않는다 — 화면(ss v2)은 읽기만 · 켜기는 관리자 SQL(미룬 189)
- 판정 412 설명 거르기 → 3-f
- ⭐ [2026-10-29 밤 · **판정 884** · shop-coo-1 `902937e` · so-module §90] **원산지(countryCodeOfOrigin) = 두 글자** — `_shared/shopify-product.ts` countryAlpha2 가 세 글자 코드를 ISO 표로 바꾸고(XKX → XK) Shopify CountryCode 에 있는 것만 보낸다 · Shopify 에 없는 ISO = AQ AS FM GU MH MP PR PW VI · Shopify 에만 = AC AN TA XK ZZ(ZZ 는 뺌) · 모르는 코드는 **그 칸만 빼고** 보내고 성공 글에 「coo dropped: SKU=code」 · 저장 값 product.country_of_origin_code 는 세 글자 그대로 · 오류는 last_hash 를 안 써서 다시 시도 · 원산지 있는 상품 996
  - 대가: 칸을 빼고 성공한 상품은 표가 그 코드를 알게 돼도 저절로 다시 안 간다(「coo dropped」 를 보고 force push) · 칸을 빼면 Shopify 의 옛 값이 남는다(짐작 · 문서 안 봄 · deferred 402)
- ⚠️ [2026-10-30 · shop-risk-0] **send_tags 를 켜면 이어진 상품 전부 다시 보내기**(스토어 트리거 · asung 5,044 · aone 약 4,379 · 1 분 20 건 → 약 8 시간 짐작) — 판정 555(사람이 브랜드 · 묶음 단위로 나눠 보낸다)와 충돌 · 컷오버 밤에 켜지 않는 쪽으로 기울어 있다 · **결정 대기**(deferred 394)
- ⚠️ [2026-10-30 · shop-risk-0 · 짐작] 비교가가 없는 asung 변형 1,795 는 compareAtPrice 칸을 안 보낸다(Shopify 옛 값이 남는지 모름) · IMS 설명이 빈 대상 asung 23 · aone 19 — 빈 descriptionHtml 이 Shopify 설명을 지울 수 있다(deferred 402)
- 큐 = `shop_push_queue`(대상마다 열린 줄 하나 · `shop_queue_add` 한 곳) · 큐 트리거 `*_shop_queue` 16(product · product_family · product_price · product_image · product_tag · product_barcode · ref_brand · ref_category · AFTER STATEMENT) · ⚠️ reason 은 「그 대상의 첫 트리거」 — 이름 + 가격이 함께 바뀌면 product 만 남는다(진단할 때 reason 만 믿지 않는다)
- ⭐ [판정 424 · stock-1a ① · stock-1b ②] 상품 줄 20 칸 — ① 새벽 맞추기(shop_queue_all)는 hash 를 미리 비교해 **바뀐 것만** 줄에(실물: 바뀐 것 없으면 0) ② skipped_same_hash 는 drain 20 칸에 세지 않는다(한 회차 20 건 보냄 또는 40 s) · 판정 414 그대로
- cron [테스트 DB] **jobid 42 ims-shop-drain 1 분마다**(열린 큐가 없으면 EF 를 부르지 않는다 · 한 회차 ≤ 20 건 — 보낸 것만 센다 · 424 ②) · **jobid 43 ims-shop-nightly 08:00 UTC**(= 토론토 04:00 EDT · 03:00 EST · shop_queue_all) · 킬 스위치 `select cron.alter_job(42, active := false);` · `(43, …)` · 기록 `supabase/ops/cron.sql`
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
단추       권한 shopify 만 · family 구성원 상품은 family 링크만(family 로만 보낸다) · 꺼진 구성원은 ~~sold out~~ → not available 안내(406 · 425 · shop v2) · sellable 아닌 세트는 안내만(404)
Stock on Shopify   shop v2(stock-1c `8f41b93`) — 스토어 줄마다 위치별 표(뷰 shop_stock_list 만 읽는다 · 낱개 한 줄 · family 는 변형마다 · 보낸 시각 · 에러 · sending…) · family 구성원 화면에도 숫자
Send stock now     EF stock_push(권한 shopify · 대상 하나 force · 결과 「Stock sent · N numbers」 그 자리에) · Edit 안에서는 표만(416)
Edit 안    판정 416 — Shopify · Description · Photos 카드를 단추 없이 읽기만(제목 옆 「Save or Cancel first to change this」)
```
- 판정 416 의 이유: 세 카드는 Edit 의 Save 와 **따로 저장된다** — 사진은 올리는 순간 Storage · 설명은 자기 편집기와 비교 규칙 · Shopify 는 행동이고 늘 DB 에 저장된 값을 보낸다(Edit 중 저장 전에 Send now 를 누르면 옛 값이 간다) · 기각: 안내 한 줄만(「없어진 것처럼 보인다」)
- 켜기 · 끄기 직후 카드에 「last send ok」 와 「Sending…」 이 잠깐 함께 보일 수 있다 — EF 가 Shopify 결과를 적은 시각과 큐 줄을 닫은 시각 사이를 읽은 것 · 다음 다시 읽기(4 초)에 사라진다(결함 아님 · so-module §56-c)
- ⚠️ 창구 shop_listing_set 의 op push_now(큐에 넣기)는 남아 있지만 지금 화면 · tools 는 부르지 않는다(Send now 는 EF push · tools/shopify-push.sh push 도 EF)
- 시험 실물(2026-10-10 · 전부 통과)은 so-module §56-c · 점검 항목은 asung-ims CHECKLIST 7-zh

---

## 4. 오더 상태 · 문서

### 4-a. asung.ca (판정 378 → 436 ~ 449 가 채운다 · so-module §61)
```
들어오는 순간     주인은 IMS
~~운송사 + 송장번호  넣는 순간 Shopify 에 「발송 + 송장번호」~~ → [2026-10-13] 보내는 순간 = Ship & invoice 하나(송장은 그때 이미 손에 있다 · Caleb) — 손님에게 발송 메일은 Shopify 가 보낸다
                  방아쇠 = so.shipped_at 이 null → 값(상태 아님 — 인보이스 취소 · 재발행은 fulfilled ↔ shipped 를 오가 두 번 보낸다 · 한 SO 는 한 번만 출고)
~~Pickup · Delivery  운송사 칸의 두 항목(Delivery = 우리 차량)~~ → [2026-10-13] 운송사 표의 종류 pickup · delivery(판정 436 · 4-d) — 송장 없이 「발송됨」만 · 메일 없음
백오더            같은 Shopify 오더에 두 번째 발송(형제 SO 의 shipped_at)
픽업 손님         asung.ca 결제에서는 Local pickup 을 못 고른다 · Wholesale All In One 오더는 픽업 손님도 shipping 으로 내려온다 → 운송사 pickup 으로 위 길
                  Shopify 오더의 배송 방식이 PICK_UP 이면 스토어와 무관하게 4-b 픽업 흐름(판정 444)
손님 계정         asung.ca 손님은 자기 계정에서 오더 상태를 본다 · 일부 발송으로 남은 오더에 문의가 간혹 온다 → 4-e(판정 441 · 449)
```

### 4-b. aonebeauty.com (판정 379 → 439 · 443 · 444 · 446 · 440 바뀜)
```
가르기            Shopify 오더의 배송 방식(deliveryMethod)으로 — PICK_UP = 아래 픽업 흐름 · 그 밖(SHIPPING 등) = 4-a(378) 그대로(판정 444 · 446)
                  aone 은 배송 오더가 픽업보다 훨씬 많다(Caleb) — 시험도 aone 배송 장면을 픽업보다 먼저
Pickup 오더       운송사 Pickup 을 미리 채운다 → [2026-10-13] 받을 때 IMS 가 채운다(판정 454 · ful-1b · 4-h)
Ship & invoice    누르는 순간 Shopify 「Ready for pickup」(손님 메일) — 서류까지 끝나 픽업 스테이션에 놓기 바로 전 (단추 이름 판정 382)
그 뒤             「Waiting for pickup」 칩 · 손님이 찾아가면 「Picked up」 단추(메일 없음)
                  SO 상태는 건드리지 않는다(Ship & invoice 로 이미 fulfilled) · Shopify 로 보낸 발송 기록에 준비됨 · 찾아감 시각 · 칩 · 단추는 그 칸으로(판정 443)
안 찾아감          크레딧 노트(재고 복원 · 재입고 수수료는 그때 판단)
~~환불              직원이 Shopify 에서 하고 IMS 가 읽어 크레딧에 붙인다~~ → [2026-10-13 · 판정 440 바뀜] 직원이 Shopify 에서 환불 · IMS 가 다시 받을 때 읽어 원문 + 「Shopify 에서 환불됨」 경고 · 크레딧 노트는 직원이 화면에서(자동 크레딧 없음 · 4-e)
```

### 4-c. 오더 문서 메일 (판정 380)
- asung.ca 직원은 오더 안에서 손님에게 최종 인보이스 · 결제 요청 · 패킹 리스트를 메일로 보낸다
- **IMS 오더 문서 메일 기능이 컷오버 전에 필요** — 인보이스 인쇄(so-module 미룬 127)가 먼저 · 미룬 147
- [2026-10-13] 이 메일을 지을 때 「Shopify 가 보내는 발송 메일은 IMS 가 안 보낸다」(같은 순간 메일 둘 — 짐작 · so-module 미룬 206)
- [2026-10-19 · so-module §66] ✅ 오더 문서 메일 섰다(테스트) — 최종 인보이스 · 크레딧 · SO · Ship Ready 수동 + 최종 인보이스만 손님 칸 자동(판정 529) · From info@(530) · PDF 첨부 · IMS 는 배송 통지를 보내지 않는다 · Shopify 배송 메일과 두 통 문제(미룬 206)는 그대로 · Shopify 오더 인보이스도 손님 칸대로(Shopify 는 인보이스를 안 보낸다 — 짐작)

### 4-d. 운송사 · 송장 · 고침 (판정 436 · 437 · 438)
```
운송사            작은 표에서 고른다(자유 글자 금지) · 항목 = 우리 이름 · Shopify 이름 · 종류(carrier · pickup · delivery) · 손님 기본 운송사도 이 표에서(판정 436)
                  종류가 손님 메일을 정한다 — carrier = 메일 · pickup · delivery = 메일 없음
                  Shopify 이름은 Shopify 운송사 목록의 이름을 대소문자 그대로(목록에 없으면 글자만 실리고 링크가 없다) · ~~Purolator · UPS 는 못 봤다(§7)~~ → [2026-10-13] Purolator 는 있다(실물 · 판정 450) · UPS 는 못 봤다(§7)
                  ~~지금은 so.carrier · customer.default_carrier 가 자유 글자다(테스트 DB 「PICKUP TOR」 류) — 판정 436 으로 표가 된다~~ → [2026-10-13] 표 ref_carrier 가 섰다(ful-1a · 4-h) · 글자 칸은 그 순간의 이름으로 남는다
송장              칸은 하나 그대로 · 쉼표 · 줄바꿈으로 여럿을 받아 Shopify numbers[] 로 나눠 보낸다 · 보통은 대표 번호 하나(Freightcom 도 대표 번호 하나 · 판정 437)
고침              Ship & invoice 뒤에도 운송사 · 송장번호만 고치는 창구 → Shopify fulfillmentTrackingInfoUpdate · 손님 메일 다시 안 보냄(판정 438)
                  종류가 바뀌는 고침(carrier ↔ pickup · delivery)은 막는다 · 발송 뒤 송장 「넣기」 창구는 짓지 않는다(빈 송장을 처음 채우는 경계 — so-module 미룬 208 → 판정 452 로 닫힘 · carrier 면 Ship & invoice 때 송장 필수)
```

### 4-e. 나가지 않을 몫 · 환불 · 결제 상태 (판정 439 · 440 · 441 · 449)
```
가르기            나가지 않을 몫(이어받기 · 만료 · 더 원하지 않음)은 Shopify 가 돈을 받았느냐로 — 스토어로 가르지 않는다(판정 439)
받은 오더          지금은 aone 카드뿐 — IMS 「환불할 몫」 경고 · 직원이 Shopify 에서 환불 · 환불을 IMS 가 읽으면 경고가 풀린다(판정 439)
받지 않은 오더(Net) IMS 가 그 몫이 닫히는 순간 Shopify 오더에서 지운다(orderEdit) → 손님 계정에도 Fulfilled · 손님 메일 없음(끌 수 있는지는 짐작 · 시험)(판정 441)
                  앱 권한 write_order_edits 를 더한다(짓는 차수에서 Caleb · §7) · 지금 asung.ca 는 모두 이 길(so-module §61-c — Shopify 가 받은 돈 0)
환불 읽기          IMS 가 오더를 다시 받을 때 Shopify 환불을 읽어 원문 + 「Shopify 에서 환불됨」 경고 · 크레딧 노트는 직원이 화면에서(자동 크레딧 없음 — 재고 복원 · 재입고 수수료는 금액으로 알 수 없다)(판정 440)
결제 상태          Net 오더가 IMS 에서 다 결제되는 순간 IMS 가 Shopify 오더를 Paid 로(판정 449 · ⑤ 와 따로 한 차수 · 「다 결제」 규칙은 그때)
                  orderMarkAsPaid ~~✅ VALID~~(write_orders · 남은 금액 전부만 · ~~사용자 권한 mark_orders_as_paid 가 앱 토큰에 걸리는지는 시험~~ · so-module §61-b) · 판정 370(aone 카드 읽기)과 옆 길
                  → [2026-10-14 · so-module §63] 「VALID」 의 근거였던 MCP validate 도구는 지금 no-op(pay-0) · 실물로 확인: 앱 토큰에서 mark_orders_as_paid 가 막히지 않았다 · 손님 메일 없음(#1007)
돈 받음 가르기      PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED = 받은 오더(경고 refund_due) · 그 밖 = 오더 고치기(판정 457) · 방아쇠 15 분 스캔(458) · restock true(459) · 되돌리기 뒤 되살리지 않음(460 · 경고 shopify_qty_removed) · warned_qty(461) · 큐 shop_order_queue(462)
IMS 가 시킨 환불    refund_due 로 시킨 환불을 직원이 Shopify 에서 하면 받기가 알아본다 — refunded_in_shopify 없음 · 그 줄의 gap 을 닫음 · refund_due 는 「처리됨」(settled_at · settled_refunds)(판정 466)
                  짝은 금액이 아니라 Shopify 줄 GID · 수량(IMS 1.68 vs Shopify 1.49 — 세금) · 받기가 removed_qty = quantity − currentQuantity 를 적는다(상한 quantity − sent — 반품 RETURN 도 currentQuantity 를 줄인다 · 수량 0 인 줄도 lineItems 에 남는다)
결제는 IMS 에서만   직원은 Shopify 에서 Mark as paid 를 하지 않는다(판정 468 ① · Shopify 직원 권한에서 뺄 수 있으면 뺀다 · Caleb)
                  안전망: SO 가 생긴 뒤 Shopify 결제 상태가 PAID · PARTIALLY_PAID 로 바뀌었는데 IMS 가 시킨 것이 아니면 경고 paid_in_shopify {from, to, ims_remaining} · IMS 인보이스가 다 갚아졌으면 없음 · IMS 장부 무접촉(판정 468 ② · pay-1a)
「다 결제」         웹 오더 SO 뭉치(shop_so_family)에 열린 오더가 없고 살아 있는 인보이스 남은 돈이 모두 0(인보이스 ≥ 1) — 0 이 된 길은 묻지 않는다(판정 469 · shop_order_paid_state)
                  15 분 스캔 shop_paid_scan(cron 52 · 8 · 23 · 38 · 53 분) → 큐 mark_paid → EF paid_drain(cron 53 · */5) — Shopify 읽기 → IMS 다시 판정 → paid_push_at 을 보내기 전에 → orderMarkAsPaid → PAID 확인
                  대상 PENDING · PARTIALLY_PAID · EXPIRED · 빈 값 · **AUTHORIZED 제외**(orderMarkAsPaid 가 승인 카드를 capture 한다) · 권한으로 보이는 오류는 한 번에 · 5 회면 경고 mark_paid_failed
                  Paid 뒤 IMS 가 다시 미수면 경고 shopify_paid_ims_owed(Shopify 는 되돌릴 명령이 없다) · 실물 #1007: Shopify 타임라인 「Asung IMS manually marked $1.49 CAD as paid」 · Gateway Manual · 손님 메일 없음 · 끝난 오더는 Shopify 가 자동 보관
                  기각: 열린 백오더가 있어도 Paid(457 이 거짓 refund_due) · orderCreateManualPayment(금액 칸 Shopify Plus 전용 · 메모 · 멱등 · 지우기 없음 · 시험 스토어는 Advanced)
카드 캡처          [2026-10-14 오후 · 판정 470 · pay-3a] SO 가 생긴 뒤 Shopify 결제 상태가 바뀌면 거래(transaction)의 gateway 로 가른다 — 카드 거래(CAPTURE · SALE · SUCCESS · gateway 가 manual 아님)는 받기가 IMS 결제를 적는다(370 과 같은 창구 so_payment_add · method shopify)
                  두 번 적지 않기 = 표지 표 shop_order_transaction(거래 GID 유니크 · 370 ⑦ 도 남긴다) · 손 표시 = gateway manual · gift_card · store_credit · 빈 값 → 지금처럼 paid_in_shopify(468) · test 거래는 오더 test 와 같을 때만
                  결제 손님 = 청구처 · 붙이기 = 인보이스 남은 돈 → 열린 가족 SO 보증금 → 받아 둔 돈(창구 규칙 그대로) · 정보 card_payment_recorded(settled — 열린 경고 아님) · 금액 · 통화 어긋남 · 창구 거부 = card_payment_failed(받기는 끝까지)
                  실물 #1015 Bogus 13.49 Capture → IMS 결제 13.49(계좌 _104_ · 보증금 SO-25094) · 표지 1 · 경고 없음 · 재받기에 두 번 안 적음 · 기각: 경고만(카드 캡처마다 손일 · 빠뜨리면 손님이 미수 · 연체로 보이고 독촉)
운영 결제 사실      [판정 471] asung.ca = 전부 Net(Shopify 결제 없음 · 운임은 IMS 에서 나중) · aonebeauty.com = 카드 · PayPal · 직원이 Shopify 에서 수동 Capture · 운임은 Shopify 에서 따로 → aone 결제는 470 이 덮는다
                  370 ⑦(받는 순간 PAID · aone 만 · gateway 안 봄)은 그대로 · ⑦ 을 gateway 로 가르는 차수는 **asung.ca 에 checkout 결제를 켤 때 · aone 을 자동 캡처로 바꿀 때 · aone 드래프트에 Mark as paid 를 쓰게 될 때** 가운데 하나보다 먼저(so-module 미룬 230)
                  시험 스토어 결제 캡처 = Manually(aone 과 같은 조건 · 되돌리지 않는다 — Automatically 면 asung 종류 시험 스토어의 checkout 카드 주문이 이 미룬 틈으로 들어간다) · PayPal 거래 모양은 못 봤다(미룬 231)
```

### 4-f. 위치 · 합친 오더 (판정 445 · 442)
```
위치              Shopify 오더의 출고 위치는 보내는 순간 한 곳에서 맞춘다 — 다르면 fulfillmentOrderMove → 보냄(판정 445)
                  옮기는 것은 Shopify 기록뿐 — 실제 픽 · 팩 · 출고는 처음부터 IMS 창고(판정 430) · 실물: #1002 Shopify Toronto ↔ SO-25081 Edmonton(so-module §61-b)
합친 SO           줄 계보(split_from_line_id · so_line_merge_source)로 원래 Shopify 오더를 찾아 오더마다 발송을 따로 · 같은 송장 · 메일은 오더마다(판정 442)
이어받기           이어받은 몫은 받은 쪽 오더로 · 앞 오더는 4-e · 이어받기는 같은 손님 · 같은 제품의 유상 줄이 다음 오더에 있을 때만(코드 · so-module §61-b) · 남은 확인 미룬 201
```

### 4-g. 메아리 · 되돌리기 (판정 447 · 448)
```
메아리            IMS 가 보낸 발송마다 Shopify 가 돌려주는 GID 를 저장 · 오더를 다시 받을 때 견준다 — 우리 것 = 경고 없음 · 모르는 발송 = 「Shopify 에서 발송됨」 경고(SO 무접촉)(판정 447)
                  받기 쿼리에 fulfillments · refunds 를 더한다 · 환불은 4-e(판정 440) · ~~지금은 SO 뒤 바뀜이면 종류 없이 updated_after_so 하나~~ → [2026-10-13] 지어졌다(ful-1b · 4-h 메아리)
되돌리기          Shopify 발송 되돌리기는 짓지 않는다 · 드물게 생기면 직원이 Shopify 에서 취소(447 경고로 보인다) · 인보이스 취소와 묶지 않는다(재발행 때 발송 메일 두 번)(판정 448)
0 원 메아리        [2026-10-13 · 판정 463] 새 환불이 금액 0 그리고 createdAt 이 v_push − 5 초 ~ + 2 분이면 refunded_in_shopify 없음(Shopify 는 restock 한 줄 지우기를 금액 0 Refund 로 남긴다 · #1011) · 0 이 아니면 창 안이어도 경고
환불 흡수          [2026-10-14 · 판정 466] IMS 가 refund_due 로 시킨 환불(줄 GID · 수량이 흡수 몫 안)은 경고 없음 · 흡수된 환불이 있는 받기는 updated_after_so 도 없음(4-e)
결제 표시 창       [2026-10-14 · 판정 468] IMS 가 보낸 결제 표시는 shop_order.paid_push_at −5 초 ~ +2 분(받는 오더의 updatedAt) 창으로 거른다 — paid_in_shopify · updated_after_so 둘 다 없음
                  last_push_at(오더 고치기 · 발송 메아리 447 ⓑ · 463)과 칸을 나눈다 — 같이 쓰면 그 2 분의 직원 Mark as paid · 0 원 환불 판정이 섞인다 · 실물 #1007 paid_push_at 이 updatedAt 보다 먼저
재고 메아리        [2026-10-14 오후 · 판정 472] 0 원 메아리 환불(463 이 경고를 거르는 것)도 restockType CANCEL 이면 재고 다시 보내기로 잡힌다 — 경고는 걸러도 Shopify 재고는 움직였다(오더 고치기 restock true · 실측 #1009 · #1011 · §3-d)
```

---

### 4-h. 짓기 실물 (판정 450 ~ 456 · ful-1a · 2 · 1b · 1c · 2c · ful-3a · 3b · so-module §62)
```
운송사 표        ref_carrier(이름 · Shopify 이름 · 종류 carrier | pickup | delivery · 켜기 · 끄기) · 시작 7 = Pickup · Delivery · Canada Post · Purolator · UPS · Canpar · FedEx(판정 450)
                 그 밖은 Settings 의 Carrier 표에서 직원이 더한다(set v2 · master 쓰기 · 종류는 못 바꿈 · 지우지 않고 끈다) · Pickup 을 창고로 나누지 않는다
                 so.carrier_id · customer.default_carrier_id(FK) · 글자 칸은 그 순간 이름 · 손님 기본 글자가 표에 없으면 id 만 비우고 글자는 남긴다(판정 451)
                 so_header_update 는 carrier_id 열쇠(또는 표 이름과 같은 글자)만 받는다 · 초안만 · so_merge 는 carrier_id 도 비운다(ful-1c)
Ship & invoice   so_finalize(판정 452) — 계보가 Shopify 에 닿는 SO 만 운송사 필수 · 고르면 켜진 표 행 · 종류 carrier 면 모든 SO 송장 필수 · pickup · delivery 면 송장 비움
                 쉼표 · 줄바꿈으로 나눔(437) · Shopify 배송 방식 PICK_UP 오더에 종류 carrier 는 막음 · 운송사를 고르는 것은 오피스
방아쇠            so_ship 끝(shipped_at · qty_shipped · 형제 split 뒤)에서 shop_fulfill_enqueue → 큐 ship + 결과 표 shop_fulfillment(SO × Shopify 오더) · 줄 shop_fulfillment_line(계보 함수)
                 unique(so_id, kind) — 인보이스 취소 · 재발행이 두 번 넣지 못한다
큐 · 비우기       shop_fulfill_queue kind 셋을 쓴다 — ship · picked_up · tracking_fix(ready_pickup 은 검사 조건에만 있고 안 쓴다 · Ready 는 ship 갈래)
                 EF shopify action fulfill_drain · cron jobid 49 ims-fulfill-drain(1 분 · 열린 줄이 없으면 EF 호출 0 · timeout 45000) · 킬 스위치 select cron.alter_job(49, active := false);
                 한 회차 ≤ 20 줄 · 40 s · 5 회 실패면 큐 done error + 경고 fulfill_failed
보내기(ship)      FO 읽기 → 짝(Shopify 남은 수량으로 자름 · 경고 fulfill_cut) → 위치 맞추기 fulfillmentOrderMove(옮겨진 FO 의 줄 id 로 다시 짝)
                 → 실패면 원래 FO 로 그대로 보내고 경고 fulfill_location_mismatch(판정 453)
                 → 종류 pickup + PICK_UP FO = fulfillmentOrderLineItemsPreparedForPickup(손님 Ready 메일 · ready_at) · 그 밖 fulfillmentCreate(carrier = 송장 · 메일 / pickup · delivery = 송장 없음 · 메일 없음)
받아 적기 둘       ① 보냈는데 못 적은 것 — 보낼 것이 0 이면 우리 발송(송장 겹침 · 큐 뒤 송장 없는 발송)을 GID 로 받아 적는다(fulfillmentCreate 에 @idempotent 없음) · 없으면 skipped + fulfill_nothing_left
                 ② 이미 Ready — 직원이 Shopify 에서 먼저 Mark as ready 면 PreparedForPickup 이 NO_LINE_ITEMS_TO_PREPARE_FOR_FULFILLMENT_ORDER 로 거절 → sent · ready_at = FO updatedAt(짐작) · 「adopted: already ready in Shopify」 · 경고 없음(ful-2c)
                 FO 상태 IN_PROGRESS 로 미리 가르지 않는다 — 「준비됨」의 표시가 아니다 · 틀리면 Ready 메일이 한 번도 안 간다
픽업 오더 받기     Shopify 배송 방식 PICK_UP(판정 454) — 브랜치 = 픽업 위치와 짝인 IMS 창고 · 세금 = 손님 주소의 주 먼저(오더 배송지 → 청구지 → Shopify 손님 기본 → IMS 손님 주소) · 없으면 픽업 창고의 주
                 tax_rule manual · 배송지 주소 비움(contact · phone 만) · 운송사 Pickup 미리 채움 · 깨끗하면 자동 확정
                 섞임(SHIPPING + PICK_UP) · 픽업 위치 둘 · 짝 없는 픽업 위치 = needs_review · shop_order.delivery_method · pickup_location_gid
Picked up         창구 so_picked_up(판정 443 · 455 · ful-1c) — so.picked_up_at · picked_up_by(SO 상태 무접촉)
                 Shopify 픽업 행이 sent + Ready 면 큐 picked_up → 픽업 FO 에 fulfillmentCreate(notify false) → Shopify 「Picked up on …」 · 메일 없음(실물)
                 pending 이면 거절(1 분 뒤) · error · skipped 면 IMS 만 + 경고 pickup_not_sent · Shopify 에서 먼저 Picked up 했으면 받아 적는다(adopt)
픽업 칩           목록 Status 칸 「waiting for pickup」 → 「picked up」(판정 455) — 채널 warehouse ∧ 운송사 종류 pickup ∧ shipped_at ∧ picked_up_at · counter · pos 는 칩 없음
                 목록은 so 표를 직접 읽고 운송사 종류는 carrier:carrier_id(kind,name) 로 끼워 읽는다 · 거르기 「Waiting for pickup」 때만 !inner
송장 고치기        창구 so_tracking_fix(판정 438) — 출고된 SO · 켜진 표 행 · 종류가 바뀌는 고침 거절 · pickup · delivery 는 고칠 송장이 없다 · 큐 tracking_fix → fulfillmentTrackingInfoUpdate(notify false · 실물 「updated tracking info」 · 메일 없음)
메아리(447)       우리 쓰기마다 last_push_at · 다시 받을 때 ⓐ 새로 보인 fulfillment GID 가 모두 우리 것 · 또는 ⓑ updatedAt 이 last_push_at −5 s ~ +2 min → updated_after_so 없음
                 Shopify updatedAt 은 초 단위로 잘린다 · 실측 지연 0.12 s · 0.49 s · 0.51 s · 모르는 GID = fulfilled_in_shopify · 새 환불 = refunded_in_shopify(원문은 raw · 판정 440)
                 「Ready for pickup」 은 updatedAt 을 안 바꾼다(실물)
Ready 뒤 배송     판정 456 — 손님이 픽업 대신 배송을 원하면 지금처럼 취소하고 다시 주문(IMS 크레딧 노트 + Shopify 취소 · 새 오더는 손님이 배송으로) · 짓는 것 없음
                 근거: Shopify Ready 화면엔 Mark as picked up 하나 · Edit 로 운임은 되지만 배송 방식은 그대로 · IMS 는 출고 뒤 운임 창구가 없다(so_charge_set 은 draft 만)
경고 코드          ⑤ 가 더한 15(Web Orders WARN_LBL · wo v2 · 전체 27) — 발송 fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · 밖의 변화 fulfilled_in_shopify · refunded_in_shopify
                 픽업 · 송장 pickup_failed · pickup_not_sent · tracking_fix_failed · 픽업 받기 pickup_tax_from_location · pickup_tax_unknown · pickup_carrier_missing · pickup_locations_differ · pickup_location_unpaired · delivery_mixed
```

### 4-i. 경고 확인함 · 화면 안 A (판정 467 · 화면 안 A · so-module §63)
```
확인함            웹 오더 경고마다 「확인함」 — 지우지 않고 acked_at · acked_by · acked_by_name · acked_note · 화면 회색(판정 467 · 창구 shop_order_warning_ack · ful-5a)
                  목록 숫자는 열린 것만 — shop_order_list.open_warning_count(처리됨 settled · 확인함 acked 제외) · 처리됨은 손으로 못 바꾼다 · 열린 refund_due 는 메모 필수 · 다시 열기(Reopen) 된다
                  원소는 자리(1 부터) + code + at 셋으로 찾는다(옛 목록으로 누르면 「changed elsewhere — reload」)
화면 안 A          Web Orders 를 SO 로 합친다(Caleb · 판정 번호 없음) — Web Orders = SO 가 안 된 것의 받은 편지함(기본 Open · 검토 필요 · 오류 · SO 전 취소 · 손님 고르기 · 줄 짝 맞추기는 여기만)
                  SO 가 생긴 오더는 Web Orders 머리 아래 「handled on SO-…」(경고 · 결제 · 발송은 SO 에서)
                  SO 상세 「Shopify」 칸 — 웹 번호 · 결제 상태 · Total = ordered · refunded · kept vs IMS · Paid in Shopify 줄(IMS 가 표시한 시각 · 아직이면 까닭 shop_order_paid_state) · 배송 · 경고 + Mark checked / Reopen
                  형제 SO 는 뭉치로 찾는다 · SO 목록 「N web warnings」 · 인보이스 목록 web #… · 상세 Web order 줄 · 검색은 search_text 가 오더 ref 를 이미 담는다
                  기각 안 B(SO 목록에 SO 없는 줄까지 섞기) · 화면 asung-ims wo v3 · v4 · v4a · v4b · so v5t ~ v5t4 · inv v2e · v2e1
Process waiting   「Process waiting now」 = 받은 오더(Waiting)를 SO 로 만드는 cron(1 분)을 지금 돌리는 단추 · Shopify 에서 당겨오는 단추가 아니다
                  손님은 받기 단계가 저절로 만든다(계정 → 이메일 → 없으면 새로 · Needs review 는 같은 이메일 여럿 · 정보 없음 · 생성 막힘 · 비활성 · SKU 못 찾음)
```

## 5. ⬜ 열린 확인 거리 (시험 스토어에서)

```
~~① 앱(Wholesale All In One)이 할인을 오더 데이터에 남기는 모양(2-e)~~ → ✅ 줄마다(asung.ca CSV · so-module §60-b · 앱은 시험 스토어에 설치 못 함)
② 무료 배송 자동 할인과 앱 할인의 겹침 · Shopify 설정 바꾸는 법(2-g · 대화 Claude)
~~③ Available 숫자 대조 — 위치별 · 웹 오더 직후(3-d)~~ → ✅ 위치별 대조 끝(2026-10-10 · 3-d 실물) · ✅ 웹 오더 직후도(2026-10-11 · #1001 확정 → 재고 drain 이 Available 을 줄임)
④ 다른 브랜치로 바꾸기 장면 끝에서 끝(2-c)
⑤ 컷오버 뒤 앱 규칙(딜 · 손님 할인) 두 번 입력 — IMS 와 앱(so-module 미룬 149) · 어긋나면 discount_mismatch 경고가 잡는다(판정 431)
~~⑥ 보호된 손님 정보(ord-0 ⬜1)~~ → ✅ 신청 없이 된다(2026-10-11 · 2-a)
⑦ ~~asung.ca 웹 결제 오더 운임~~ → asung.ca custom 결제 방식 오더의 운임 → ✅ [2026-10-14] 판정 473(§2-g · frt-1a)(→ so-module §61-c) — 지금은 받은 오더에 금액 · 제목만 · 경고 freight_not_applied(Caleb 조사 중 · so-module 미룬 191)
~~⑧ ⑤ 시험 — ful-0 보고 ⬜8 ① 운송사 + 송장 둘 → 발송 메일 · 위치 옮김 · 메아리 없음 ② Delivery → 메일 없음 ③ 백오더 두 번째 발송 ④ 픽업 Ready → Picked up ⑤ 송장 고침 → 메일 없음(aone 배송 장면을 픽업보다 먼저 · 판정 446 · ful-4)~~ → ✅ 다섯 다 끝(2026-10-13 · so-module §62-c) · aone 스토어 장면은 컷오버 때
~~⑨ 「Picked up」 mutation — 전용은 못 봤다 · 짐작: 픽업 FO 에 fulfillmentCreate(notifyCustomer false) · ⑧ ④ 에서(so-module 미룬 209)~~ → ✅ 그 길이 맞다 · 「Picked up on …」 · 메일 없음(§62-c)
~~⑩ 오더 고치기(orderEdit) 의 손님 메일 끄기 · 환불이 남은 몫을 지우는가 · orderMarkAsPaid 의 사용자 권한이 앱 토큰에 걸리는가(판정 441 · 439 · 449 · so-module 미룬 209 → 210 · 211 · 212)~~ → ✅ 셋 다(so-module §63-c) — 오더 고치기 메일 없음(#1011) · Unfulfilled 환불이 currentQuantity 를 줄인다(③-b · 466) · mark_orders_as_paid 가 앱 토큰에서 막히지 않았다(#1007 · 메일 없음)
⑪ 이미 Ready 로 받아 적은 ready_at(FO updatedAt)이 Mark as ready 시각과 같은가(so-module 미룬 217)
⑫ UPS 가 Shopify 운송사 목록에 있는가(판정 450 · 미룬 218)
~~⑬ [판정 후보 470] Shopify Restock(CANCEL · RETURN)이 Shopify available 만 +1 — IMS 재고 밀기는 「지난번 보낸 값과 같으면 건너뜀」이라 다음 IMS 재고 변동까지 Shopify 가 더 판다(Toronto ANN01002 IMS 34 · Shopify 35 → 반품 환불 뒤 36) · order_drain 의 restock true 도 같다(so-module 미룬 222)~~ → ✅ 판정 472(후보 470 의 답 · stk-r1 · #1013 취소 실물 · §3-d)
~~⑭ 468 거르기가 PARTIALLY_PAID → PARTIALLY_PAID(상태가 안 바뀐 두 번째 결제 표시)를 못 잡는다(so-module 미룬 225) · AUTHORIZED 오더 시험(미룬 228 ③)~~ → ⑭ 468 거르기의 PARTIALLY_PAID → PARTIALLY_PAID(미룬 225)는 그대로 열림 · ✅ AUTHORIZED 오더 시험(#1014 · Capture → PAID · so-module §63-h-2)
✅ [2026-10-14 오후] so-module 미룬 228 확인 거리 셋 — ① 웹 오더 확정이 이어받기를 한다(#1013 → SO-25092 · SO-25088 백오더 superseded) ② 0 개 Shopify 오더는 Voided · Fulfillment not required · $0.00(#1009 · 취소 아님 · 메일 없음) ③ AUTHORIZED(#1014)
⑮ aone 첫 PayPal 오더의 거래 원문 — gateway 글자 · AUTHORIZATION → CAPTURE 로 오는지(판정 471 · so-module 미룬 231) · 수동 결제 방식(현금 · 수표)의 gateway 글자(미룬 233 · manual 로 짐작)
[2026-10-30 · shop-risk-0 · 읽기만 · so-module §90-d] 실제 두 스토어 — 컷오버 · Go live 때 다시 볼 것
⑯ send_tags 켤지 — 켜면 이어진 상품 전부 다시 보내기(asung 5,044 · aone 약 4,379 · 약 8 시간 짐작 · 555 와 충돌) · 결정 대기(deferred 394)
⑰ inventoryPolicy 바뀜 — asung DENY → CONTINUE 198(켜짐 · 단종 아님) · CONTINUE → DENY 단종 811 · 꺼짐 11 · aone CONTINUE → DENY 21 · review-deny-171.csv Decision 173 줄 전부 빈칸(171 정리 · deferred 186 · §7)
⑱ 첫 재고 force asung 8,849 · aone 7,110 줄(약 18 · 15 분 짐작) · asung Edmonton inventoryActivate 가 걸림돌일 수 있음(Q5 미확인 · deferred 400)
⑲ 실제 두 스토어 웹훅 구독 0 — 15 분 poll 만(deferred 401)
⑳ 칸을 빼거나 빈 값을 보낼 때 Shopify 쪽 값 — 원산지 「coo dropped」(884) · compareAt 없는 asung 변형 1,795 · 빈 설명 asung 23 · aone 19(짐작 · deferred 402)
㉑ 브랜드별 첫 push 때 상품 하나가 Shopify 사진 그대로인지(890 · deferred 395)
```

## 6. 갱신

- 새 판정은 so-module 의 그날 절에 원문 표 · 이 파일에는 주제별로 옮긴다(판정 번호를 단다)
- 이 문서와 so-module 표가 어긋나면 **판정 원문(so-module)이 맞다**
- [2026-10-09 · so-module §55] §3-f 를 판정 401 · 402 · desc-1b(9184853) 실물로 고침 — 복사 없음 · 보내기는 product_description 뷰만 · 거르기는 ims-desc.js 와 같은 규칙(→ 목록만 같고 엔진은 판정 412)
- [2026-10-10 · so-module §56 · docs-1010] 상태 줄 · §1 시험 스토어 실물 · §3-a 판정 413 · §3-b 사진 실물 · §3-c 판정 404 ~ 407 · 413 · 퍼블리시 유지 · §3-e 판정 408 ~ 410 · 412 · 큐 · cron 42 · 43 · 「새벽에 되돌림」 어긋남 열림 · §3-f 판정 412 · §3-g 가격(판정 403 · 403 고침 · 408) 새로
- [2026-10-10 · so-module §56 이어 붙임 · tag-0] 상태 줄에 shop-2c · §3-e 「새벽에 되돌림」 어긋남을 판정 414 로 닫음(새벽 맞추기 = 안전망) · §3-h 화면 새로(shop-2c · 판정 415 Send now 바로 · 416 Edit 안 읽기만)
- [2026-10-10 오후 · so-module §57 · stock-0] §3-e 태그 적재 실물(c61ba04 · 63,501 · 판정 417 · 418) · 운영 순서(태그 적재 → send_tags → 보냄) · §1-a 컷오버 보냄 첫 상태 새로(판정 420)
- [2026-10-10 저녁 · so-module §58 · docs-1010c] 상태 줄에 ③ 끝 · §3-c 판정 406 옆 425 · §3-d 재고를 판정 421 ~ 425 · stock-1a · 1b · 1c 실물 · cron 44 · 45 · 46 으로 채움 · §3-e 판정 424 · §3-h shop v2 · §5 ③ 닫힘 · §7 할 일 새로
- [2026-10-10 밤 · so-module §59 · docs-1010d] 상태 줄 · §1-a 컷오버 할 것(aone 위치 짝 Toronto 하나 · 재고 상태 태그 구현 끄기 · 171 정리) · §3-c 판정 427 · 428(407 바뀜) · 스토어 트리거 · §3-e 판정 426 · §7 테마 글자 asung.ca 에만 · 할 일 둘
- [2026-10-11 · so-module §60 · docs-1011] 상태 줄에 ④ 끝 · §2-a 실물 모양 · 보호된 손님 정보 확정 · §2-c 판정 430(365 바뀜) · §2-e 판정 431 · 433 · CSV · §2-j 판정 434 · §2-k 화면 · 채널 × intake(판정 432 · 435) 새로 · §5 ① ③ 닫힘 · ⑥ 닫힘 · ⑦ 운임 · §7 그대로
- [2026-10-13 · so-module §61 · docs-1013] 상태 줄에 ⑤ 판정 · §2-h 에 440 · 449 포인터 · §2-g 「일반 웹 결제」 정정(→ §61-c) · §4-a · 4-b 를 판정 436 ~ 449 로(옛 글귀 ~~ ~~ · 4-b 크레딧 줄 → 440 바뀜) · §4-c 미룬 줄 하나 · §4-d 운송사 · 송장 · 고침 · §4-e 나가지 않을 몫 · 환불 · 결제 상태 · §4-f 위치 · 합친 오더 · §4-g 메아리 · 되돌리기 새로 · §5 ⑦ 정정 · ⑧ ~ ⑩ 새로 · §7 Caleb 넷
- [2026-10-13 · so-module §62 · docs-1013b] 상태 줄에 ⑤ 짓기 끝 · §4-b Pickup 오더 줄 · §4-d Purolator · 운송사 표 · 미룬 208 닫힘 · §4-g 메아리 지어짐 · §4-h 짓기 실물 새로(판정 450 ~ 456 · cron 49 · kind 셋 · 받아 적기 둘) · §5 ⑧ ⑨ 닫힘 · ⑪ ⑫ 새로 · §7 갱신
- [2026-10-14 · so-module §63 · docs-1014] 상태 줄에 ⑤ 나가지 않을 몫 · 확인함 · 결제 상태 끝 · §2-h 468 · 469 포인터 · §4-e 457 ~ 462 · 466 · 468 · 469 · orderMarkAsPaid 실물(옛 「✅ VALID」 · 「시험」 ~~ ~~) · §4-g 463 · 466 · 468(paid_push_at 창) · §4-i 경고 확인함 · 화면 안 A 새로 · §5 ⑩ 닫힘 · ⑬ ⑭ 새로 · §7 write_order_edits 닫힘
- [2026-10-14 오후 · so-module §63-h · docs-1014b] 상태 줄 · §2-h 470 · 471 포인터 · §3-d 판정 472(받기의 다시 보내기 · nightly 안전망 · family 단위 Send stock now) · §4-e 카드 캡처(470) · 운영 결제 사실(471 · ⑦ 미룬 조건 셋) · §4-g 재고 메아리(472) · §5 ⑬ 닫힘 · ⑭ 반 닫힘 · 미룬 228 ① ② ③ 닫힘 · ⑮ 새로
- [2026-10-14 밤 · so-module §64 · docs-1014c] 상태 줄에 frt-1a · §2-g 판정 473(asung 운임 견적) · aone 운임 「확정」 은 코드 표지 없음(미룬 236) · §5 ⑦ 닫힘
- [2026-10-27 · so-module §82 · §83 · docs-1027c] 상태 줄 · §1 live · auth_mode · 창구 op 셋 · cron 42 ~ 53 · 웹훅 live 전 무시 · 실제 스토어 셋 · Aone 조직(809 · 813 · 816 전제 바뀜) · Shopify 사실 · §1-b 기존 상품 잇기 새로(link-dup-1 이견 1 — 잇기 절이 없었다) · §3-d 콤보(831) · 트리거 16 · §7 할 일 여섯
- [2026-10-30 · so-module §90 · docs-1030] 상태 줄 · §1-b 컷오버 순서의 send_tags → 결정 대기(394) · §2-a 컷 전 웹 오더(판정 889 · 814 대체) · 웹훅 구독 0 · §3-b 사진 보내기 끔(판정 890 · 409 · 560 멈춤) · shop-photo-0 요지 · §3-e 원산지(판정 884) · send_tags 전부 다시 보내기 · 비교가 · 빈 설명 · §5 ⑯ ~ ㉑ · §7 store_live · send_tags · 171 줄

## 7. 할 일 — 사람 몫 (리마인드)

```
[ ] 테마 글자 「Sold out」 → 「Not available」 (판정 425 · ⭐ Caleb 할 일 · 리마인드 요청 · so-module 미룬 180)
    Online Store → Themes → Edit default theme content → 「Sold out」 검색 → Not available
    시험 스토어 먼저 → 컷오버 때 ~~asung.ca · aonebeauty.com~~ → **asung.ca 에만**(판정 427 · aone 은 DENY 스토어라 「Sold out」 이 맞는 표시)
    까닭: asung.ca 는 0 에서도 판다(CONTINUE · 판정 427) → 그 글자는 꺼진 구성원 · 단종(DENY)에게만 뜬다
[ ] asung.ca 재고 상태 태그 · 메타필드 구현 끄기 (판정 426 · Caleb · 컷오버 때 · so-module 미룬 187)
[ ] 171 정리 — review-deny-171.csv 의 Decision 칸(discontinue | unsell | keep) (판정 429 · Caleb · 컷오버 전 · 미룬 186) — [2026-10-30 · shop-risk-0] Decision 173 줄 전부 빈칸 · 아직 열림
[ ] Shopify 운송사 목록에 ~~Purolator ·~~ UPS 가 있는지 (판정 436 · 450 · Caleb · 관리자 발송 화면의 운송사 고르기 · Purolator ✅ 실물 · so-module 미룬 202 → 218)
[x] 시험 스토어 Local pickup 켜기 (판정 443 · 444 · Caleb · Toronto 만 켬 · 2026-10-13 · 미룬 203 닫힘)
[x] 앱 권한 write_order_edits 더하기 (판정 441 · Caleb · Dev Dashboard · 짓는 차수에서 · 미룬 200 · 210) — v2orderedits Active · 시험 스토어 Install app → Update data access(2026-10-13 · so-module §63-c)
[ ] ImsLoadCustomer(GAS) 편집기 원본이 default_carrier 글자만 보내는지 (판정 451 · Caleb · 미룬 219)
[x] 시험 운송사 「Test Freight」 끄기 (Settings · 꺼짐 확인 ref_carrier is_active f · 2026-10-13 18:52:25 UTC)
[ ] asung.ca `custom` 결제 방식의 실제 이름 (Caleb · Settings → Payments → Manual payment methods · 운임 191 과 함께 · 미룬 205)
[ ] Shopify 페이지 합치기 — 두 스토어 아홉 묶음(asung 3 · aone 6 · 페이지 35 → 9 · 변형 26) (판정 830 · 담당자 · 컷오버 전 · 안내문 · 엑셀 shopify-ims-diff-2026-10-27.xlsx 는 레포 밖 · §1-b)
    남길 페이지에 사이즈를 변형으로 더하고 옛 페이지를 지운다(한 변형씩 지우기 → 추가) · Archive 로는 안 풀린다 → 끝나면 Read → Plan 에서 dup_target 0
[ ] Aonebeauty EDM 위치 — Shopify 쪽 재고 숫자(비우거나 판매에서 빼기)와 그 위치가 온라인 주문을 받는지(짐작: 위치 설정의 온라인 주문 처리) (Caleb · 컷오버 전 · §1-a · 미룬 188 · IMS 는 그 위치에 재고를 안 보낸다 — 짝 없음)
[ ] asung · aone `send_tags` 켜기 (관리자 SQL · 판정 426 · 창구가 받지 않는다 · ⚠️ 태그 적재 뒤에만 — 빈 태그로 켜면 스토어 태그를 지운다 · 켜면 스토어 트리거가 그 스토어 상품 전부를 큐에) — [2026-10-30] **켤지 결정 대기**(전부 다시 보내기 약 8 시간 · 555 와 충돌 · deferred 394)
[ ] store_live — 스토어마다 Go live(orders_from = Cin7 의 Shopify 연결을 끈 시각 · **분까지** · 판정 814 · ~~그 전 안 나간 웹 오더는 Shopify 에서 손으로 Fulfill~~ → [2026-10-30 · 판정 889] 18:00 뒤 직원이 그 웹 오더에 `ims-import` 태그 · §2-a) (Caleb · 컷오버 날)
[ ] 컷오버 순서 — 상품 재적재 → Shopify 페이지 정리 확인 → asung · aone Read → Plan → Apply links → Cin7 의 Shopify 연결 끔 → Go live → ~~send_tags~~(결정 대기 · deferred 394) (§1-b · so-module §83-c · reload-procedure §P-2 13b)
[ ] 556 모양 다름 aone 48 · asung 2 줄마다 보기 · CRO85680 확인 (Caleb · 컷오버 전 · deferred 357)
```
