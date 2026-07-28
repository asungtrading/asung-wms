# WMS Edge Function

로컬: `~/asung-wms/supabase/functions/hello/index.ts` (Deno/TypeScript). 배포: `supabase functions deploy hello`. 현재 연습 함수명 `hello` 재활용 중.

## 공통 헬퍼 (1·2·3단계 공유)

```typescript
const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";

function cin7Headers(): HeadersInit {
  return {
    "api-auth-accountid": Deno.env.get("CIN7_ACCOUNT_ID") ?? "",
    "api-auth-applicationkey": Deno.env.get("CIN7_APPLICATION_KEY") ?? "",
    "Content-Type": "application/json",
  };
}
function normWarehouse(loc: string): string {
  return /edmonton/i.test(loc || "") ? "edmonton" : "toronto";
}
async function sbSelect(path: string): Promise<any[]> {  // Supabase REST 조회
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, { headers: { apikey: key, Authorization: "Bearer " + key } });
  if (!resp.ok) throw new Error("Supabase " + resp.status + ": " + (await resp.text()).slice(0,300));
  return await resp.json();
}
```
⚠️ `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`는 Edge Function에 자동 주입(별도 secrets 등록 불필요, GAS용과 별개).

## assembleLine() — 라인 정규화+조립 (2단계, 순수함수. 3단계·프론트 재사용)

라인 하나를 받아: ①스냅샷 조회(order_sku 기준) ②정규화(base_sku·factor는 스냅샷에서, `required_base=ordered_qty×factor`) ③**bin 조회는 base_sku 기준**(재고는 낱개=base로 쌓임) ④flags 계산. 반환: order_sku, base_sku, is_variant, ordered_qty, factor, required_base, product_name, is_selling, available_total, bins[{bin,zone,available}], flags[].

```typescript
async function assembleLine(ln: any, warehouse: string) {
  const orderSku = (ln.SKU ?? "").trim();
  const orderedQty = Number(ln.Quantity) || 0;
  const snap = await sbSelect("wms_sku_snapshot?sku=eq." + encodeURIComponent(orderSku) + "&limit=1");
  const s = snap[0] ?? null;
  const baseSku = s?.base_sku ?? orderSku;
  const factor  = s?.factor ?? 1;
  const requiredBase = orderedQty * factor;
  const bins = await sbSelect(
    "wms_sku_bins?sku=eq." + encodeURIComponent(baseSku) +   // ⚠️ base_sku 로 조회
    "&warehouse=eq." + warehouse + "&is_current=eq.true&order=available.desc");
  const flags: string[] = [];
  if (!s) flags.push("no_snapshot");
  if (s && s.is_selling === false) flags.push("not_sellable");
  if (bins.length === 0) flags.push("no_bin");
  const totalAvail = bins.reduce((sum, b) => sum + (Number(b.available)||0), 0);
  if (bins.length > 0 && totalAvail < requiredBase) flags.push("short_stock");
  return { order_sku: orderSku, base_sku: baseSku, is_variant: s?.is_variant ?? false,
    ordered_qty: orderedQty, factor, required_base: requiredBase,
    product_name: s?.product_name ?? ln.Name ?? "(스냅샷 없음)", is_selling: s?.is_selling ?? null,
    available_total: totalAvail, bins: bins.map(b => ({bin:b.bin,zone:b.zone,available:Number(b.available)||0})),
    flags };
}
```

## 1·2단계 흐름 (검증 완료, 저장 안 함)

특정 오더(SO-13284) 하나로 파이프라인 검증:
1. `saleList?Limit=5&Search={orderNo}` → OrderNumber 매칭으로 SaleID
2. `/sale?ID={saleId}` 상세 → `AdditionalAttributes.AdditionalAttribute1` 확인 + `Location`(→normWarehouse) + `Order.Lines`
3. 각 라인 `assembleLine()` → JSON 응답

**SO-13284 검증결과**(edmonton): 3라인 DEL11336/DEL12355/DEL45022 전부 factor1 base, bin EZ01Pallet04 zone Z, available 17/9/12, is_selling true, flags 전부 빈배열, total_required_base=28.

## 3단계 (완료 · 검증됨, 2026-07-18)

import 파이프라인 완성. 흐름: saleList AUTHORISED 50건 폴링 → `SKIP_PICKED`(CombinedPickingStatus='PICKED' 스킵) → 각 `/sale` 상세 `AdditionalAttribute1='2.Release to WMS'`만 → dedup(`cin7_sale_id` 있으면 스킵) → `assembleLine()` 정규화 → `needsReview`(라인 flag 있으면 true) → **`?commit=1`일 때만 저장**(기본 dry-run 안전장치). `wms_orders` insert(return=representation로 id 회수) → `wms_order_lines` insert, 라인 실패 시 헤더 롤백.
- 검증: dry-run SO-13284만 would_insert, commit 후 inserted 1, 재실행 skipped 1(already_exists) = dedup 작동. 라인 base_sku·factor·req_base·bin·zone·is_selling 저장 확인.
- `wms_orders.needs_review` 컬럼 추가됨.
- ⬜ 남은 것: 폴링 스케줄(자동 import 크론). 현재 수동 호출.

## 확대 폴링 + 자동 스케줄러 (2026-07-21, LIVE)

**확대 폴링**(3단계 위에 얹음): saleList AUTHORISED **페이지네이션**(POLL_LIMIT 100 × POLL_MAX_PAGES 3 = 300 스캔), `SKIP_PICKED`, **상세조회 전 dedup**(`existingSaleIds()`: cin7_sale_id in.(...) 청크 50), `MAX_DETAIL` 60캡(detail_capped 플래그), DETAIL_DELAY_MS 250. dry-run 진단필드: `pages_scanned·candidates·after_skip_picked·already_exists·fresh_candidates·detail_fetched·detail_capped·would_insert`.
- ⚠️ **이 필드들이 응답에 없으면 옛날(50건 1페이지) 버전이 배포된 것.** `supabase functions download hello`로 받은 소스가 stale일 수 있으니, 확대판(POLL_MAX_PAGES 상수 존재)으로 덮어쓴 뒤 deploy. 배포 전 `Select-String -Path ...\hello\index.ts -Pattern "POLL_MAX_PAGES"`로 확인.

**자동 스케줄러**(`wms_schedule_polling.sql`): pg_cron + pg_net. 잡 `wms-poll-orders` `*/5 * * * *` → 함수 `?commit=1` anon Bearer 호출. 검증: `select * from cron.job;` / 실행이력 `cron.job_run_details`(succeeded) / 응답 `net._http_response`(status_code 200).
- ⚠️ **net._http_response가 null로 남을 수 있음**(pg_net 타임아웃 ~5초 초과, 상세조회 여럿 돌 때). **저장은 됐을 수 있으니 진실은 `wms_orders.imported_at`으로 확인.**
- ⚠️ **Cin7 병행운영**: 유입 전 상태변경→유입안됨(정상), Cin7에서 PICKED→SKIP_PICKED 제외("안 들어온다" 최빈원인), **유입 후 변경→WMS 모름**(dedup, 재조회 안 함 — 병행 테스트 위험, 자동감지 백로그).

## 호출 (테스트) — bash + curl
```bash
ANON="<anon public key>"
BASE="https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1"

# dry-run (저장 안 함)
curl -s "$BASE/hello" -H "Authorization: Bearer $ANON" | jq .

# 저장까지: ?commit=1
curl -s "$BASE/hello?commit=1" -H "Authorization: Bearer $ANON" | jq .
```
⚠️ 이전 기록의 PowerShell 예시(`Invoke-RestMethod`)는 낡았다 — 개발환경은 WSL2 Ubuntu + bash. 여기선 진짜 curl 이라 `-H` 정상 동작.

## Edge Function `receiving` (2026-07-23, hello 와 별개 함수)

로컬 `supabase/functions/receiving/index.ts`. 배포 `supabase functions deploy receiving`. 브라우저 호출용 CORS 포함, anon Bearer.

**액션**:
- `?action=pos[&search=]` — 리시빙 준비 PO. **필터 4중**: purchaseList **`InvoiceStatus` AUTHORISED + PAID(2회 호출 병합 — `PurchaseList.ID` 기준 dedup, 호출 사이 sleep 250ms, `search` 는 양쪽에 동일 전달)**(서버 파라미터 유지 — Invoice First. 제거하면 DRAFT/NOT AVAILABLE/VOIDED 까지 긁어와 스캔량↑·게이트 느슨해짐) + Status 에 VOID/COMPLETED/CREDITED 포함 제외 + **Status 에 RECEIVED 포함 제외(단 RECEIVING 은 유지 — 부분입고 진행중)** + Type 에 Service 포함 제외(운송·관세 — 물건 없음) + StockReceivedStatus=AUTHORISED 제외. ⚠️ 상태는 "RECEIVED / CREDITED" 같은 복합 문자열이라 includes 로 검사(정확 일치는 새는 원인이었음). ⚠️ **PAID 포함은 실측 근거 있음 (2026-07-28)**: PO-01081(Exod, Simple Purchase, Status=INVOICED / InvoiceStatus=**PAID** / StockReceivedStatus=NOT AVAILABLE)이 `Search=PO-01081` 단독으론 Total 1 인데 `&InvoiceStatus=AUTHORISED` 를 붙이면 Total 0 → 목록에서 통째로 사라졌다. Apply 경로(`/purchase/invoice`)는 이미 AUTHORISED·PAID 둘 다 인정하므로 목록만 좁아 "Apply 는 되는데 목록에 안 뜨는" 불일치였다.
  - ⚠️ **`Limit=1000`(`PO_PAGE_LIMIT`) + 페이지 상한 3**(`while (page <= PO_MAX_PAGES)`). 조기 종료 조건은 **같은 상수**를 써야 한다(`items.length < PO_PAGE_LIMIT`) — 100 으로 남으면 825 < 1000 이라 첫 페이지에서 무조건 루프가 끊긴다. 실측상 PAID 는 page1 한 번으로 끝나므로 상태별 호출은 사실상 1회.
  - ⚠️ **실측 근거 4줄 (2026-07-28, purchaseList, InvoiceStatus=PAID, Total 825)** — AUTHORISED+PAID 2회 병합을 배포해도 PO-01081 이 무검색 목록에 계속 안 뜬 진짜 원인은 **페이지 상한**이었다(`search=PO-01081` 로는 정상):
    1. **정렬은 PO 번호 오름차순.** page1 = PO-00004~ 이고 최신 PO 는 마지막 페이지 — Page=9 에서 PO-01081 확인. 기존 `Limit=100`+`page<=3`(=300건) 은 옛 PO 300건만 읽고, 그 300건은 거의 다 StockReceivedStatus=AUTHORISED 로 걸러져 목록에 **한 건도 추가되지 않았다**.
    2. **Limit=1000 이 동작한다.** page1 에 825건 전부(PO-00004~PO-01081), page2 는 0건.
    3. **UpdatedSince 는 부적합** — 동작은 한다(30일 124건 / 60일 249건 / 90일 331건). 그런데 60일 창의 page1 도 PO-00004 부터 시작한다: 지불 처리로 옛 PO 가 계속 갱신되므로 **날짜 창이 PO 번호의 최신성을 보장하지 못한다.** → 180일 창(`PO_PAID_LOOKBACK_DAYS`) 방식은 **폐기**(상수·`paidSince`/`since` 코드 전부 제거).
    4. **RestockReceivedStatus 는 무시된다** — NOT AVAILABLE·DRAFT 모두 Total 825 = 무필터와 동일. 서버 쪽에서 못 좁히니 StockReceivedStatus 제외는 계속 클라이언트(루프 안)에서 한다.
  - **📌 향후**: PO 총건수가 2000 을 넘기 시작하면 상한(`PO_PAGE_LIMIT` × `PO_MAX_PAGES`)을 다시 봐야 한다.
  - **진단 필드 (최상위, 규칙 12 dry-run 진단과 같은 취지)**: `scanned` = 상태별로 실제 가져온 행 수(필터 전) 예 `{"AUTHORISED":n,"PAID":825}` · `truncated` = 페이지 상한에 걸려 더 있는데 못 읽은 상태가 있으면 true. 상한에 걸린 사실이 응답에 안 보여 원인 파악에 왕복이 여러 번 필요했던 게 추가 이유. ⚠️ **`pos` 배열의 구조·필드명은 불변** — receiver.html 이 `j.pos` 만 읽는다. 진단 필드는 추가만.
- `?action=po&id=&type=` — Simple/Advanced 자동 분기(`/purchase` vs `/advanced-purchase`), Lines 위치 d.Lines || d.Order.Lines 양쪽 방어. 스냅샷 배치 조인(in.() 청크 50)으로 base_sku·factor·expected_base(=qty×factor)·이미지·scannable_barcodes 정규화.
- `?action=transfers` — stockTransferList Status='IN TRANSIT'. warehouse = normWarehouse(ToLocation).
- `?action=transfer&id=` — /stockTransfer 상세 + 동일 정규화. to_location_raw·to_guid(기본 착지 bin) 포함.
- `?action=apply&receipt_id=N` — **dry-run 계획**(아무것도 안 씀): 대상 라인(received>0 & 승인됨 & bin 있음), 스킵 사유(off-PO 미승인/승인됨이지만 PO에 없음/bin 없음), 수량 변환(received_base÷factor — 안 나눠떨어지면 에러), 단계 설명.
- `?action=apply&receipt_id=N&commit=1&by=이름` — 실제 쓰기 (아래).

**Apply commit 흐름**:
- 공통 가드: `applied_at` 있으면 거부(이중 방지), status=completed 만.
- **PO**: ①`/purchase/invoice` 로 인보이스 AUTHORISED/PAID 확인(아니면 에러 — Invoice First) ②POST /purchase/stock DRAFT — 라인마다 {Date(필수), SKU:order_sku, Quantity:received_base÷factor, LocationID:binGuid(창고,putaway_bin), Received:false} ③Authorize = {TaskID, Status:'AUTHORISED', Lines:[]} 재요청 — **미실측 단계**, 실패 시 WARN 로그만(DRAFT 남음 → Cin7 수동 Authorize).
- **트랜스퍼**: → **아래 "트랜스퍼 경로 (2026-07-28 전면 개정)" 절을 볼 것.** 요약: ⓪discrepancy 선기록 → ①PUT COMPLETED(**원본 수량 그대로**, resume 이면 스킵) → ②`min(received,expected)` 캡된 bin 이동 + `exported_base` 체크포인트 → ③receipt PATCH.
- 성공 시 wms_receipts PATCH: applied_at/by/apply_note(로그 조인).

**binGuid(창고, bin이름)** — ⚠️ **2026-07-28 전면 교체 (TR-02935 실사고)**: `/ref/location` 은 **Total 2678 인데 Limit 500 에서 잘린다.** 반환 500행 = 최상위 창고 2행 + **토론토 child-location 498행뿐, 에드먼튼 child 는 0행**(전부 뒤 페이지) → 에드먼튼 bin GUID 조회가 **첫 호출부터 throw** 했다. 토론토도 안전하지 않았다(Bins[] 2047 개인데 child 498행만 들어옴 — PO-01066·PO-00965 가 성공한 건 그 bin 이 우연히 앞 페이지에 있었기 때문).
- ✅ **GUID 출처는 최상위 창고 행(`ParentID` 없음)의 `Bins[]` 하나뿐. 페이지네이션 불필요** — Bins[] 에 전량 들어있다(실측: `Asung - Edmonton` 628개 / `Asung Trading Inc.` 2047개). 원소 = `{"ID","Name","IsDeprecated","IsStaging"}`. 실측 EZ010101 → `b997fb39-…` · EG030102 → `07f87571-…`. 최상위 2행은 응답 앞머리라 `Limit=500` 한 번으로 충분(잘림은 child 행에서만).
- ❌ **child-location 이름 매칭 경로 제거.** child 의 `Name` 은 bin 이름이 아니다(실측 예 `"071164313169"` — 바코드류) → 처음부터 매칭될 수 없는 죽은 폴백이었다. 되살리지 말 것.
- **`binMap(창고)`**: 창고 키 → `Map<대문자 bin, {id, name}>`, 요청 내 캐시(`_binMaps` + `_locCache`). 창고 매칭은 `WH_NAME[normWarehouse(입력)]` 정확일치 → 폴백으로 최상위 행 이름의 `normWarehouse` 비교(그래서 `'edmonton'` 과 `"Asung - Edmonton"` 둘 다 받는다). 비교는 `trim().toUpperCase()`, `IsDeprecated` 는 제외. ⚠️ **`name` 은 Cin7 원본 대소문자 보존** — `EZ01Pallet05` 같은 혼합표기가 있고 putaway_bin·`to_location_raw` 비교(이미 제자리 스킵)·프린트가 이 표기를 쓴다. 대문자는 조회 key 로만.
- **`tryBinGuid()` = throw 안 하는 버전.** Apply 는 GUID 못 찾은 bin 의 **라인만 스킵**하고 나머지를 계속 쓴다(아래).
- ⚠️ Cin7 쓰기 API 는 이름("창고: bin") 거부 — 반드시 GUID.

**부분 스킵 (2026-07-28)**: TR-02935 의 피해가 커진 직접 원인은 "bin 한 건 실패 → **전체 throw** → 원 TR 은 COMPLETED 인데 receipt PATCH(`applied_at`)·discrepancy 까지 유실" 이었다.
- **PO**: bin GUID 를 **쓰기 전에 전부 해석** → 못 찾은 bin 은 라인 스킵. **하나도 해석 안 되면 throw**(아직 아무것도 안 썼으므로 receipt 을 큐에 남겨 bin 고쳐 재Apply 하는 게 맞다). ⚠️ **스킵이 하나라도 있으면 auto-authorize 를 건너뛴다** — authorize 는 되돌릴 수 없고 Simple PO 는 1회뿐이라 DRAFT 로 남겨 매니저가 Cin7 에서 빠진 라인을 채우고 직접 authorize 하게 한다(WARN 로그로 안내).
- **트랜스퍼**: PUT COMPLETED 이후 구간은 **절대 throw 하지 않는다**(Cin7 이 이미 되돌릴 수 없게 바뀜) → 스킵하고 남은 bin 계속 이동, receipt PATCH·discrepancy 까지 반드시 도달.
- 노출: Apply 응답 최상위 **`skipped_bins: [{sku, bin, reason}]`** + `log` 의 `WARN` 줄(admin alert 이 이미 `WARN` 접두를 감지) + `apply_note` 에 `skipped_bins: [...]` 한 줄(JSON, 800자 컷).

## receiving EF — 2026-07-24 실측 반영 업데이트

**action=bins** (신규): `?action=bins&warehouse=` → Cin7 `/ref/location` 에서 그 창고 전체 bin(빈 자리 포함) `[{bin,id}]`. 빈 지정 드롭다운 소스(신제품 새 자리). ⚠️ **2026-07-28: `binMap()` 과 같은 소스(최상위 창고 행의 `Bins[]`)로 통일** — 예전 "Bins[] + child-location 둘 다 수집" 방식은 같은 Limit 잘림에 걸려 **에드먼튼 bin 이 통째로 빠져 있었다**. 정렬 없이 반환(receiver.html `sortBins` 가 정렬), 원본 대소문자 유지.

**applyCommit PO 경로 — 실측 확정 형태**:
- Date = `YYYY-MM-DDT00:00:00Z` (자정, 밀리초 없이).
- ⚠️ **bin 별 분할 POST**: plan.lines 를 putaway_bin 으로 그룹핑 → bin 마다 별도 `POST /purchase/stock {Status:DRAFT, Lines:[...그 bin 라인만...]}` (콜 간 sleep 400). **한 문서에 여러 bin 섞으면 400 "Lines is invalid"** (실측 PO-00965).
- buildApplyPlan 이 같은 (SKU+bin) 라인 수량 합산 병합(중복 라인 400 방지).
- **Authorize = `POST` "/purchase/stock" {Status:'AUTHORISED', Lines:[]}** (PUT 은 405 — 실측). 실패 시 WARN(DRAFT 는 남음).
- 성공 시 wms_receipts PATCH: **status='completed'** + applied_at/by/apply_note.
- Invoice First: `/purchase/invoice` 로 AUTHORISED/PAID 선확인.

**진단 팁**: cin7() 실패 throw 에 `| SENT: {body}` 포함(디버깅용, 유지). Cin7 "Lines is invalid" 는 대개 (a)여러 bin 섞임 (b)같은 SKU+bin 중복 (c)PO 에 없는 SKU — SENT 로 격리. GAS `WmsPoStockWriteTest.gs` 의 `psMultiLineTest`(bin별 분할 검증)·`psAuthorizeTest`(PUT/POST 판별) 패턴 재사용.

**트랜스퍼(창고간)** — 이 시점 기록은 "같은창고 bin↔bin 기준, 재설계 필요" 였다. **해소됨**: 2026-07-25 창고간 실측 → 2026-07-28 전면 개정(아래 절). 히스토리로만 남긴다.

## receiving EF — 트랜스퍼 경로 (2026-07-28 전면 개정, 이전 2026-07-25 판을 대체)

⚠️⚠️ **폐기된 이전 판**: "실물 수량으로 덮어쓰기(`recvBySku` → `TransferQuantity` 교체) + `changed` 로그" 는 **제거됐다.**
**Cin7 은 트랜스퍼 완료 PUT 의 `TransferQuantity` 변경을 조용히 무시한다** (실측 2026-07-28, 신규 IN TRANSIT **TR-03267**): SENT 에 변경값이 정확히 실려 나가고 PUT 200 이 떨어지지만 **되읽으면 원본 그대로**다 — `AS93113` 원본 2 → 요청 4 → **저장 2** / `AS92700` 원본 4 → 요청 2 → **저장 4**. **증가·감소 양방향 모두 무시**(API 제약, 코드 버그 아님). 되살리지 말 것. **PO stock received 의 초과 허용은 별개이고 사실이다 — PO 경로는 손대지 않는다.**

**buildApplyPlan transfer 절**
- `transferDetail()` 로 원본 조회. **Status 는 `IN TRANSIT`(신규) 또는 `COMPLETED`(재개) 만 통과** → `plan.mode = "new" | "resume"`. 그 외는 throw. ⚠️ 예전엔 IN TRANSIT 만 허용해 **TR-02935 가 영구히 큐에 갇혔다**(원 TR 은 COMPLETED 인데 bin 이동 미완).
- **착지 지점 (규칙 21 (a)/(b))** — `to_location_raw` 예 `"Asung - Edmonton: EZ010101"`:
  ```ts
  const landingRaw = String(det.to_location_raw || "").trim();
  const ci = landingRaw.indexOf(":");
  const landingBin = ci >= 0 ? landingRaw.slice(ci + 1).trim() : "";   // (a) 창고만이면 ""
  const landingLabel = landingBin || ((landingRaw || WH_NAME[rcpt.warehouse]) + " (no bin)");
  ```
  ⚠️ **trim + undefined 방어 필수.** (a) 는 콜론이 없어 `split(":")[1]` 이 undefined 이고, 앞 공백이 남으면 "이미 제자리" 스킵 판정이 어긋나 **From==To 이동을 쏴서 400** 이 난다. 스킵 비교는 대문자로 (`g.bin.toUpperCase() === landingBin.toUpperCase()`).
- **⚠️⚠️ bin 이동 수량 캡 `min(received_base, expected_base)`** — 완료 후 착지 지점에 앉는 건 **보낸 수량**이므로 초과분은 Cin7 에 존재하지 않는다(옮기려 하면 400). SKU 단위 budget(=expected 합)을 planLines 순서대로 소진:
  - `p.move_base` = 캡된 이동량 · `p.pending_base` = `move_base − exported_already`(재개 시 남은 몫)
  - **초과 라인** → expected 만큼만 이동(예 APR15412 expected 24 / received 48 → 24 만) · **부족 라인** → received 만 이동, `expected − received` 는 착지 지점에 남는다(**의도된 동작**) · **off-transfer SKU** → expected 0 → 캡 0 → 이동 제외, `recv_off_po` discrepancy 로만.
- **plan 노출 필드**: `mode` · `transfer{number,status,landing_bin,landing_label,to_location_raw,to_guid}` · `lines[]`(`move_base`/`pending_base`/`parts` 포함) · `groups[]`(**`pending_base>0` 인 라인만**) · **`leftover_at_landing:[{sku,qty,where}]`**(`where`=`landing_label`) · **`excluded_from_move:[{sku,bin,received,moved,not_moved,reason}]`** · `skipped` · `discrepancies`.
- **`parts`**: merge 는 (order_sku + putaway_bin) 기준이라 여러 receipt 라인이 한 planLine 이 된다 → `parts:[{id,received_base,exported_base}]` 를 실어 `exported_base` 체크포인트를 쓸 수 있게 한다.

**applyCommit 실행 순서 (⚠️ 이 순서가 핵심 — 규칙 27 R12)**
1. **⓪ discrepancy 선기록** — `POST wms_discrepancies?on_conflict=receipt_id,sku` + Prefer `resolution=ignore-duplicates,return=minimal`. **Cin7 을 건드리기 전**이고 **실패하면 throw 로 중단**한다(아래 참조). PO·트랜스퍼 공통.
2. **① PUT 완료** — `plan.mode==="resume"` 면 **건너뛰고** 로그만 남긴다. 신규면 `PUT /stockTransfer {TaskID, Status:'COMPLETED', From, To, CostDistributionType, InTransitAccount, DepartureDate, CompletionDate, Reference, Lines: det.Lines, SkipOrder:true}` — **`Lines` 는 원본 그대로**(수량 변경은 무시된다). Date 는 `YYYY-MM-DDT00:00:00Z`.
3. **② 캡된 bin 이동 + `exported_base` 체크포인트** — `plan.groups` 순회. 착지 bin 이면 스킵, GUID 못 찾으면 그 그룹만 스킵(WARN, `skipped_bins`), `pending_base>0` 인 라인만 `POST /stockTransfer {Status:'COMPLETED', From: det.To, To: binGuid(wh,g.bin), Lines:[{SKU:base_sku, TransferQuantity: pending_base}], SkipOrder:true}` (sleep 300).
   - ⚠️ **From 은 항상 `det.To`**. 창고 GUID면 "bin 없는 재고"를, 집결 bin GUID면 그 bin 을 꺼냄 — 둘 다 실측 200.
   - 성공 직후 `markExported(p)` → `PATCH wms_receipt_lines?id=eq.<part.id> {exported_base}` (`move_base` 를 parts 순서대로 각 라인 `received_base` 한도까지 배분, **절대값이라 재실행 idempotent**). ⚠️ 되돌릴 수 없는 쓰기 뒤이므로 **PATCH 실패에도 throw 금지 — WARN 만**(빠지면 재Apply 가 같은 bin 을 두 번 옮긴다).
   - 재Apply 시 `exported_base` 가 찬 라인은 `pending_base=0` → 그룹째 스킵.
4. **잔량·미이동 로그** — `LEFTOVER stays in <landing_label> (remove in Cin7 with a manual stock adjustment): SKU xN` + `not moved (Cin7 holds none of it): …`. ⚠️ **위치 표현이 (a)/(b) 로 다르다** — (b) bin 이름 / (a) `"Asung - Edmonton (no bin)"`. 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다.
5. **③ receipt PATCH** — `status='completed'` + `applied_at`/`applied_by`/`apply_note`(로그 조인, 위 LEFTOVER·skipped_bins 줄 포함).

**discrepancy 기록 (PO·트랜스퍼 공통) — ⚠️ 2026-07-28 순서·실패정책 역전**: buildApplyPlan 이 SKU 단위로 received vs expected 를 비교해 `plan.discrepancies[]`(reason `recv_over`/`recv_short`/`recv_off_po`) 생성. 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 기록이 통째로 유실됐다(TR-02935 실사고). 지금은 **맨 처음**이고 **실패 시 Apply 중단**(`"discrepancy log failed - NOTHING was written to Cin7"`) — 새 정책에서 이 큐는 **유일한 보정 지시서**라 기록 없이 재고를 옮기면 차이를 되찾을 수 없다. `sb()` 헬퍼 4번째 인자 `prefer` 사용.

## 폴링 EF `hello` — Reference 저장 (2026-07-25)

`extractReference(d)` 추가: `d.CustomerReference` → 폴백 `d.Reference`. `wms_orders.reference` 로 저장, dry-run `would_insert` 에도 노출해 유입 확인 가능. ⚠️ **`wms_order_reference.sql`(컬럼 추가)을 배포보다 먼저** — 없으면 insert 400.
