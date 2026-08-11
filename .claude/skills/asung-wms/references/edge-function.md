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

⚠️ **2026-08-04 공용화**: Cin7 HTTP 레이어(`CIN7_BASE`·`cin7Headers()`·`cin7()`·`cin7Get`·`cin7ErrInfo()`·`sleep`)는 **`supabase/functions/_shared/cin7.ts`** 로 추출돼 hello·receiving 이 함께 import 한다(위 코드 블록의 `cin7Headers` 정의는 역사 기록). `cin7()` 은 429 백오프(1.5s→3s, 상한 2회) 후 소진 시 `err.status=429` 를 실어 throw — 호출부가 "회차 조기 종료" 를 택할 수 있다. ⚠️ **이 파일을 바꾸면 두 함수 모두 재배포**(각 함수는 배포 시점 번들 사용 — 한쪽만 배포하면 조용히 갈라진다). `supabase functions deploy` 가 `_shared` 상대 import 를 번들에 포함함은 실증됨(Supabase 공식 권장 패턴, CLI 2.109.1).

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

**확대 폴링**(3단계 위에 얹음): saleList AUTHORISED **페이지네이션**(POLL_LIMIT 100 × POLL_MAX_PAGES 3 = 300 스캔), `SKIP_PICKED`, **상세조회 전 dedup**(`existingSaleIds()`: cin7_sale_id in.(...) 청크 50), `MAX_DETAIL` 60캡(detail_capped 플래그), DETAIL_DELAY_MS 250. 진단필드(dry-run·commit 공통): `pages_scanned·candidates·after_skip_picked·already_exists·fresh_candidates·detail_fetched·detail_capped·would_insert` + 2026-08-04 추가분(아래).
- ⚠️ **이 필드들이 응답에 없으면 옛날(50건 1페이지) 버전이 배포된 것.** `supabase functions download hello`로 받은 소스가 stale일 수 있으니, 확대판(POLL_MAX_PAGES 상수 존재)으로 덮어쓴 뒤 deploy. 배포 전 `grep POLL_MAX_PAGES supabase/functions/hello/index.ts` 로 확인.

**429·굶주림 수정 + 진단 확장 (2026-08-04 — SO-14100·SO-14106 미유입 실사고, 규칙 12)**
- **429**: saleList 루프가 공용 `cin7Get()`(_shared) 사용 — 백오프(1.5s→3s, 상한 2회) 소진 시 **throw 없이 회차 조기 종료**(앞 페이지 분량은 정상 처리), `rate_limited`/`rate_limited_at_page` 노출. 429 외 4xx/5xx 는 기존대로 throw. 예전엔 `!ok` 즉시 throw 라 2·3페이지 429 면 회차 전체가 500 으로 죽었다. `/sale` 상세조회의 기존 429 처리(60초 대기 후 그 오더 스킵)는 그대로 raw fetch.
- **상세조회 순서 = 최신 오더번호 내림차순**: saleList 는 오름차순 + 비대상(`2.Release to WMS` 아님) 오더는 저장되지 않아 매 회차 fresh 에 잔류 → `MAX_DETAIL` 60 예산을 선점해 **최신 오더 영구 굶주림**(SO-14106 이 캡에 잘리는 2건 중 하나). 정렬 키 = OrderNumber 숫자부(`Number(String(n).replace(/\D/g,""))`) 내림차순. 규칙 20 오름차순 함정의 두 번째 사례.
- **진단 필드 추가**: `list_total`(saleList Total) · `list_fetched` · `truncated`(list_fetched < list_total) · `oldest_scanned`/`newest_scanned`(스캔한 오더번호 범위) · `rate_limited(+rate_limited_at_page)` · `detail_capped_orders`(캡에 잘린 오더 목록 — 최신 우선이라 잘리는 건 가장 오래된 fresh. **회차마다 계속 자라면** "확인했으나 비대상" 기억 테이블 도입 재검토). `skipped_detail` 은 `already_exists` 에 더해 **`skip_picked`**(reason + picking_status)도 포함.
- 스캔 범위(100×3)는 실측상 충분(`list_total` 140, truncated false) — Limit 상향·UpdatedSince 병용 불필요. `truncated:true` 가 재검토 신호. "안 들어온다" 진단 순서는 규칙 12.

**"확인했으나 비대상" 기억 스킵 (2026-08-11 — `wms_polled_sales` · 백로그 17번 해소)**
- **왜**: 비대상 오더는 저장되지 않아 매 회차 fresh 에 잔류 → 같은 ~51건의 `/sale` 상세를 5분마다 다시 읽었다(회차당 52콜 · 하루 ~15,000콜 · 상세 50건×250ms ≈ 25초 버스트가 60/60 창을 소진 — 트랜스퍼 Apply 429 의 원인). ⚠️ 캡 상향은 답이 아니다(콜이 늘어 악화 — PO 목록 "상한 증설은 시간 벌기" 함정과 동일).
- **신호 실측(SO-14516, 2026-08-11)**: saleList 항목에 `Updated` 가 있고, `AdditionalAttribute1` 을 릴리즈로 바꾸면 **Updated 만 바뀐다**(Status·OrderStatus·CombinedPickingStatus 전부 그대로) — 목록에서 볼 수 있는 유일한 변경 신호. `AdditionalAttribute1` 은 목록에 없다(판정은 상세조회만).
- **스킵 = 기억에 있고 AND `Updated` 가 저장값과 정확히 같고(⚠️ 문자열 비교 — 파싱하면 .29Z/.290Z 차이가 흡수돼 "다른데 같다" 오판. 그래서 `cin7_updated` 컬럼은 text) AND 확인이 TTL(1시간) 이내.** 위치 = already_exists dedup 직후 3b 단계(fresh 배열 자체가 줄어 내림차순 정렬·MAX_DETAIL 캡은 무접촉). memset 조회는 **already_exists 통과 후보만**(청크 in.() — `polledMemory()`).
- ⚠️ **Updated 는 신호가 아니라 트리거다** — "릴리즈됐다"가 아니라 "뭔가 바뀌었으니 읽어봐라". 판정은 언제나 상세조회. 무관한 수정(코멘트·주소·수량)으로 바뀌어도 헛읽기 1회뿐(누락 없음). **TTL 1시간은 순수 보험** — 신호가 실패해도 최대 1시간 안에 반드시 다시 읽힌다(`memory_ttl_expired` 로 발동 관측, 0 근처가 정상).
- ⚠️⚠️ **기록의 급소**: 기록은 **"상세조회 성공 + 판정 결과 비대상"** 일 때만(코드상 판정 분기 안 — 429/실패는 continue 로 도달 불가 = 구조적 보장). 쓰기는 `?commit=1` 만(읽기·스킵 판정은 dry-run 공통 — dry-run 이 프로덕션 동작을 반영). 안 읽은 것을 기억하면 Updated 가 다시 바뀔 때까지 영영 안 읽힌다.
- ⚠️ **경합(설계상 허용 — 2026-08-11 명시)**: saleList 조회와 그 오더의 상세조회 사이에 릴리즈되면 목록의 Updated 가 옛값이라 기억과 일치해 그 회차를 건너뛴다. **다음 회차(≤5분)에 들어오므로 누락이 아니라 최대 한 회차 지연이다** — 종전에는 같은 회차에 잡혔다(이번 변경으로 새로 생긴 좁은 경합).
- **정리**: 릴리즈로 저장 성공 시 그 기억 행 best-effort DELETE(memory_rows 감시 청결용 — 실패해도 already_exists 가 먼저 거른다) · commit 회차 끝에 `checked_at < now()-30일` purge 1콜(활성 행은 TTL 재확인 upsert 로 매시간 갱신되므로 30일 미갱신 = 목록 이탈. "목록에 없는 id 삭제"는 truncated 회차 대량 오삭제 위험이라 기각).
- **킬 스위치**: `POLL_MEMORY_TTL_MS = 3600_000` — **0 이면 조회·스킵·기록·purge 전부 비활성 = 현행 동작 복귀**(상수 1줄 + 재배포).
- **진단 추가**(기존 필드 무변): `skipped_unchanged`(기억 스킵 건수 — 개별 행은 skipped_detail 에 안 실음, 사용자 결정) · `memory_ttl_expired`(보험 발동) · `memory_rows`(증식 감시) · `detail_rate_limited`(상세 429 로 조용히 건너뛴 건수 — ⚠️ 종전엔 **어디에도 안 남았다**: fresh 51 vs detail_fetched 50 의 1 차이가 이 경로였다. 60초 sleep 구조는 무변 — 백로그 별건, 이 카운트로 빈도 관측 후 판단).

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
- `?action=pos[&search=]` — 리시빙 준비 PO. **서버 조회 = `Status=INVOICED` + `Status=RECEIVING` 각각(2회 호출 — `PurchaseList.ID` 기준 dedup, 호출 사이 sleep 250ms, `search` 는 양쪽에 동일 전달)**. ⚠️ 2026-08-04 전환 — 종전 `InvoiceStatus=AUTHORISED`+`PAID` 서버 필터 방식 폐기: PAID 는 지불을 마친 **모든** PO(실측 877건, 그중 리시빙 대상 0건)를 돌려줘 전량을 긁어 클라이언트에서 버리는 구조였고, 오름차순 정렬 + 페이지 상한(1000×3) 조합에서 PO 가 쌓이면 **최신 PO 부터 조용히 잘린다**(PO-01081 형 사고의 재발 경로 — 상한 증설은 시간 벌기일 뿐). **Invoice First 는 클라이언트 검사로 이동**: `InvoiceStatus` 가 `AUTHORISED`/`PAID` **정확 일치**일 때만 통과, 그 외 값(DRAFT 등 = 인보이스 미승인)은 제외하고 값별 카운트를 console.warn 으로 남긴다(예상 밖 값이 조용히 새지 않게). 클라이언트 제외 4종은 그대로(⚠️ 모두 includes — "RECEIVED / CREDITED" 같은 복합 상태 실재, 정확 일치는 새는 원인이었음): Status 에 VOID/COMPLETED/CREDITED 포함 제외 + **RECEIVED 포함 제외(단 RECEIVING 은 유지 — 부분입고 진행중)** + Type 에 Service 포함 제외(운송·관세 — 물건 없음) + StockReceivedStatus=AUTHORISED 제외.
  - ⚠️ **실측 2026-08-04 (purchaseList, 전체 PO 1,129건)** — 전환의 근거:
    1. **`Status` 서버 필터는 동작한다**: `Status=INVOICED` → Total 73 · `Status=RECEIVING` → Total 5. 현재 리시빙 대상 8건은 전부 INVOICED(Simple Purchase / StockReceivedStatus=NOT AVAILABLE). RECEIVING 5건은 전부 StockReceivedStatus=AUTHORISED 라 지금은 클라이언트 필터에서 걸러지지만 "부분입고 진행중은 유지" 의도(규칙 20)로 계속 조회한다.
    2. **여러 값 동시 요청은 불가** — `Status=INVOICED,RECEIVING` 도 `INVOICED|RECEIVING` 도 Total 0 → 상태별 개별 조회 + dedup(호출 수는 종전 2회와 동일).
    3. **`Type` 서버 필터는 무시된다** (Simple/Advanced/Service Purchase 모두 무필터와 동일 결과) → Service 제외는 클라이언트 유지.
    4. **`StockReceivedStatus=NOT AVAILABLE` 서버 필터는 동작한다**(Total 585) — ⚠️ 2026-07-28 의 "무시된다"는 `RestockReceivedStatus` 로 **파라미터 이름을 잘못 쓴 것**이었다(정답은 `StockReceivedStatus`). 그래도 서버엔 걸지 않는다 — RECEIVING 유지 의도와 충돌(전부 AUTHORISED 라 서버에서 걸면 사라진다).
    5. `InvoiceStatus=PAID` 877건 중 `Status=INVOICED` 교집합은 **1건** — PAID 전량 조회의 나머지 876건은 전부 낭비였다.
  - ⚠️ **`Limit=1000`(`PO_PAGE_LIMIT`) + 페이지 상한 3**(`while (page <= PO_MAX_PAGES)`) + 조회 사이 sleep 유지. 조기 종료 조건은 **같은 상수**를 써야 한다(`items.length < PO_PAGE_LIMIT`) — 어긋나면 첫 페이지에서 무조건 루프가 끊긴다. **정렬이 PO 번호 오름차순(잘리면 최신부터 누락)이라는 사실은 Status 전환 후에도 전제다** (2026-07-28 실측: PAID Total 825 가 Limit=1000 의 page1 에 전부 들어오고 page2 는 0건 · UpdatedSince 는 지불 갱신 때문에 날짜 창이 PO 번호 최신성을 보장 못해 폐기 — 상세는 SKILL.md 규칙 20).
  - **진단 필드 (최상위, 규칙 12 dry-run 진단과 같은 취지)**: `scanned` = 상태별 실제 가져온 행수(필터 전, 예 `{"INVOICED":73,"RECEIVING":5}`) · `totals` = 상태별 서버 보고 Total · `truncated` = **Total 대비 덜 받은 상태가 있으면 true**(페이지 상한이든 응답 잘림이든 — 종전 "페이지 상한 도달"보다 강한 판정). ⚠️ **`pos` 배열의 구조·필드명은 불변** — receiver.html 이 `j.pos` 만 읽는다. 진단 필드는 추가만.
- `?action=po&id=&type=` — Simple/Advanced 자동 분기(`/purchase` vs `/advanced-purchase`), Lines 위치 d.Lines || d.Order.Lines 양쪽 방어. 스냅샷 배치 조인(in.() 청크 50)으로 base_sku·factor·expected_base(=qty×factor)·이미지·scannable_barcodes 정규화.
  - **엔드포인트 폴백 (2026-08-05, ⚠️ 현장 미검증)**: `poRaw()` 가 400 이면 반대 엔드포인트로 **1회** 재시도(429·404·5xx 는 대상 아님 — 기존 경로 불변, 반대쪽도 실패하면 원래 에러). 반환은 `{data, resolvedType, fellBack}` — 폴백 시 교정 타입이 `poDetail` 의 `cin7_type` 반환값에 실리고 receiver 가 receipt 생성 시 그대로 저장한다(`po.cin7_type||p.type`). 폴백 발동은 console.warn 2회(poRaw: 시도 순서·성공 경로 / poDetail: PO 번호·원래→교정 타입) — 화면이 조용히 열리면 purchaseList `Type` 이 틀렸다는 사실을 아무도 못 본다.
- `?action=transfers` — stockTransferList Status='IN TRANSIT'. warehouse = normWarehouse(ToLocation).
- `?action=transfer&id=` — /stockTransfer 상세 + 동일 정규화. to_location_raw·to_guid(기본 착지 bin) 포함.
- `?action=apply&receipt_id=N` — **dry-run 계획**(아무것도 안 씀): 대상 라인(received>0 & 승인됨 & bin 있음), 스킵 사유(off-PO 미승인/승인됨이지만 PO에 없음/bin 없음), 수량 변환(received_base÷factor — 안 나눠떨어지면 에러), 단계 설명.
- `?action=apply&receipt_id=N&commit=1&by=이름` — 실제 쓰기 (아래).

**Apply commit 흐름**:
- 공통 가드: `applied_at` 있으면 거부(이중 방지), status=completed 만. ⚠️ **예외 = 트랜스퍼의 실패 bin 재시도**(`apply_note` 에 `failed_moves(N)` N>0 + 남은 그룹 있음) — 아래 참조.
- **PO**: → **아래 "applyCommit PO 경로 (2026-07-31 전면 개정 — 트랜스퍼 보호 장치 이식)" 절을 볼 것.** 요약: ⓪discrepancy 선기록 → ①인보이스 AUTHORISED/PAID 확인(Invoice First) → ②pending bin 그룹을 청크로 POST /purchase/stock DRAFT(+`exported_base` 체크포인트 — PO 의미 = "문서에 실은 양") → ③**authorize 게이트**: 모든 bin 이 문서에 실린 마지막 회차에만 1회 authorize(미완이면 DRAFT 유지) → ④receipt PATCH.
- **트랜스퍼**: → **아래 "트랜스퍼 경로 (2026-07-28 전면 개정)" 절을 볼 것.** 요약: ⓪discrepancy 선기록 → ①PUT COMPLETED(**원본 수량 그대로**, resume 이면 스킵) → ②`min(received,expected)` 캡된 bin 이동 + `exported_base` 체크포인트 → ③receipt PATCH.
- 성공 시 wms_receipts PATCH: applied_at/by/apply_note(로그 조인).

**binGuid(창고, bin이름)** — ⚠️ **2026-07-28 전면 교체 (TR-02935 실사고)**: `/ref/location` 은 **Total 2678 인데 Limit 500 에서 잘린다.** 반환 500행 = 최상위 창고 2행 + **토론토 child-location 498행뿐, 에드먼튼 child 는 0행**(전부 뒤 페이지) → 에드먼튼 bin GUID 조회가 **첫 호출부터 throw** 했다. 토론토도 안전하지 않았다(Bins[] 2047 개인데 child 498행만 들어옴 — PO-01066·PO-00965 가 성공한 건 그 bin 이 우연히 앞 페이지에 있었기 때문).
- ✅ **GUID 출처는 최상위 창고 행(`ParentID` 없음)의 `Bins[]` 하나뿐. 페이지네이션 불필요** — Bins[] 에 전량 들어있다(실측: `Asung - Edmonton` 628개 / `Asung Trading Inc.` 2047개). 원소 = `{"ID","Name","IsDeprecated","IsStaging"}`. 실측 EZ010101 → `b997fb39-…` · EG030102 → `07f87571-…`. 최상위 2행은 응답 앞머리라 `Limit=500` 한 번으로 충분(잘림은 child 행에서만).
- ❌ **child-location 이름 매칭 경로 제거.** child 의 `Name` 은 bin 이름이 아니다(실측 예 `"071164313169"` — 바코드류) → 처음부터 매칭될 수 없는 죽은 폴백이었다. 되살리지 말 것.
- **`binMap(창고)`**: 창고 키 → `Map<대문자 bin, {id, name}>`, 요청 내 캐시(`_binMaps` + `_locCache`). 창고 매칭은 `WH_NAME[normWarehouse(입력)]` 정확일치 → 폴백으로 최상위 행 이름의 `normWarehouse` 비교(그래서 `'edmonton'` 과 `"Asung - Edmonton"` 둘 다 받는다). 비교는 `trim().toUpperCase()`, `IsDeprecated` 는 제외. ⚠️ **`name` 은 Cin7 원본 대소문자 보존** — `EZ01Pallet05` 같은 혼합표기가 있고 putaway_bin·`to_location_raw` 비교(이미 제자리 스킵)·프린트가 이 표기를 쓴다. 대문자는 조회 key 로만.
- **`tryBinGuid()` = throw 안 하는 버전.** Apply 는 GUID 못 찾은 bin 의 **라인만 스킵**하고 나머지를 계속 쓴다(아래).
- ⚠️ Cin7 쓰기 API 는 이름("창고: bin") 거부 — 반드시 GUID.

**부분 스킵 (2026-07-28 · PO 는 2026-07-31 개정)**: TR-02935 의 피해가 커진 직접 원인은 "bin 한 건 실패 → **전체 throw** → 원 TR 은 COMPLETED 인데 receipt PATCH(`applied_at`)·discrepancy 까지 유실" 이었다.
- **PO**: GUID 못 찾은 bin 은 그룹째 스킵(그룹 루프 안에서 판정). **"하나도 해석 안 되면 throw" 는 "이번 회차가 GUID 스킵 말고 아무것도 안 했고 이전 회차 진행(lines_exported)도 0" 일 때만** — 청크 도입 후에는 이전 회차의 DRAFT 가 Cin7 에 있을 수 있어, 진행이 있으면 절대 throw 하지 않는다(기록이 끊긴다). ⚠️ **스킵이 하나라도 있으면 authorize 보류(DRAFT 유지)** — 2026-07-31 부터 이 방침이 미처리·실패·격리까지 확장됐다(아래 authorize 게이트).
- **트랜스퍼**: PUT COMPLETED 이후 구간은 **절대 throw 하지 않는다**(Cin7 이 이미 되돌릴 수 없게 바뀜) → 스킵하고 남은 bin 계속 이동, receipt PATCH·discrepancy 까지 반드시 도달.
- 노출: Apply 응답 최상위 **`skipped_bins: [{sku, bin, reason}]`** + `log` 의 `WARN` 줄(admin alert 이 이미 `WARN` 접두를 감지) + `apply_note` 에 `skipped_bins: [...]` 한 줄(JSON, 800자 컷).

## receiving EF — 2026-07-24 실측 반영 업데이트

**action=bins** (신규): `?action=bins&warehouse=` → Cin7 `/ref/location` 에서 그 창고 전체 bin(빈 자리 포함) `[{bin,id}]`. 빈 지정 드롭다운 소스(신제품 새 자리). ⚠️ **2026-07-28: `binMap()` 과 같은 소스(최상위 창고 행의 `Bins[]`)로 통일** — 예전 "Bins[] + child-location 둘 다 수집" 방식은 같은 Limit 잘림에 걸려 **에드먼튼 bin 이 통째로 빠져 있었다**. 정렬 없이 반환(receiver.html `sortBins` 가 정렬), 원본 대소문자 유지.

**applyCommit PO 경로 (2026-07-31 전면 개정 — 트랜스퍼 보호 장치 이식. 이전 "전량 일괄 POST → 무조건 authorize" 판을 대체)**:

Cin7 형태(실측 확정 — 불변): Date = `YYYY-MM-DDT00:00:00Z` · **문서당 bin 1개**(bin 별 분할 POST, 콜 간 sleep 400 — 섞으면 400 "Lines is invalid") · 같은 (SKU+bin) 병합 · **Authorize = POST {Status:'AUTHORISED', Lines:[]}**(PUT 405) · Invoice First 선확인 — ⚠️ **정정 (2026-08-05): `/purchase/invoice` 가 아니다.** 종전 표기 `GET /purchase/invoice` 는 Advanced PO 에서 400 "deprecated"(실측) — 현행은 **PO 상세 응답의 Invoice 블록**(`poRaw()`+`invoiceBlock()`, `cin7_type` 으로 엔드포인트 선택 + **400 시 반대 엔드포인트 1회 폴백**·성공하면 `wms_receipts.cin7_type` 교정 PATCH(비차단), ⚠️ 폴백은 현장 미검증)으로 AUTHORISED/PAID 확인. 조회 실패는 "Invoice check failed"(미승인과 메시지 분리 — authorize 오처방 방지), 판정은 fail-open 유지(규칙 21).

1. **buildApplyPlan po 절**: planLines 에 `move_base`·`pending_base` 를 계산해 — ~~=qty_base, 캡 없음(received 그대로)~~ → ⚠️⚠️ **2026-08-10 개정: `expected_source='invoice'` receipt 는 초과를 인보이스 수량까지 클램프**(`po_clamp.ts` `applyPoInvoiceClamp` — SKU 단위 budget 을 planLines id 순으로 소진, **마지막 PO 라인부터** 잘림("마지막 bin 부터" 아님 — bin 채움 시각 미기록·updated_at 부적격, 필요 시 first_received_at 신설 선행 · **SKU 합계 expected 0 = 공장 백오더는 통과** · 'order'(구형·폴백)는 종전대로 received 전량 · qty_units 도 클램프값/factor 로 재계산돼 Simple POST·Advanced stage1/2 가 자동 반영 · 잘린 라인은 plan `capped_to_invoice[]` + steps "1b) CAPPED…" + commit 로그 "CAPPED to invoice quantity" 로 노출 · 검증 `po_clamp_test.ts` deno test). 이 클램프는 트랜스퍼 캡(아래)과 수식이 같지만 expected 0 처리가 정반대 — 한쪽 수정 시 반대쪽 확인. **`pending_base>0` 만 bin 그룹으로** 묶고 트랜스퍼 v3 처럼 "미시도 먼저, 실패 이력 뒤로" 정렬. ⚠️ **라인 all-or-nothing**: `exported_already < qty_base` 면(체크포인트 PATCH 일부 실패 잔재) 전량 pending — 부분 수량은 factor 로 안 나눠떨어질 수 있고, 중복 재전송은 Cin7 이 400 으로 거부한다(아래). plan 에 `groups`/`fail_counts`/`quarantined_bins`/`chunk_size`/`time_budget_ms`/`progress` 노출(트랜스퍼와 동일 계약). 재개 게이트 `retryFailed` 는 **2026-07-31 부터 소스 무관**(`failed_moves(N)`/`groups_remaining(N)`/`permanently_failed(N)` 마커).
2. **그룹 루프 (트랜스퍼와 같은 구조)**: 격리 판정(연속 3회+) → **공용 `chunkGuard()`**(그룹 12/시간 20초/429/실패 6초 — 트랜스퍼와 같은 상수·판정, Cin7 POST **앞**) → GUID 미해석 스킵 → `POST /purchase/stock DRAFT` → 실패는 **수집만 하고 계속**(전체 throw 제거 — 429 는 failed_moves 에 안 넣고 회차 조기 종료, 400 재시도 없음) → 성공 시 `markExported` 체크포인트. ⚠️ **PO 의 `exported_base` = "Cin7 stock received 문서에 실은 양"**(트랜스퍼의 "bin 으로 옮긴 양"과 다름 — authorize 여부와 무관).
3. **⚠️⚠️ authorize 게이트 (PO 고유 — 1회 제약)**: authorize 는 **그룹 루프 밖**에서, `groups_remaining + failed_moves + permanently_failed + skipped_bins(고유 bin) === 0` 인 회차에만 **딱 한 번** 시도한다. 하나라도 남으면 apply_note 에 `"Cin7 document left as DRAFT - N bin(s) pending (...)"` 을 남기고 보류 — 회차마다 시도하면 Simple PO 의 1회 제약을 위반하고, 부분 문서를 authorize 하면 빠진 수량을 API 로 채울 수 없다. 응답 `authorized: true|false|null`(false=시도 실패 → 기존 방침대로 WARN+DRAFT+Cin7 수동, null=보류/트랜스퍼).
4. **receipt PATCH**: apply_note 매 회차 갱신 + `applied_at` 은 done:true 회차에만(트랜스퍼와 동일). 미완 receipt 은 admin 에 `Continue apply`/`Retry failed bins` + **`Cin7 DRAFT — N bin(s) pending` 배지**로 남는다.
- **되읽기 회복(checkpoint repair)은 PO 미적용** — "POST 성공 후 체크포인트 누락" 잔여물의 재전송은 **400 `Cannot add duplicate value`** 로 거부된다(실측, stock-write.md — 같은 Product+Location 이 이미 stock received 에 있으면 발생): 조용한 이중 계상 없음, 이 에러 = 그 라인은 이미 DRAFT 에 있음(Cin7 화면 확인 후 마무리 — WARN·admin 알림에 안내). 필요성이 실측되면 별도 검토(백로그 6번).
- 잔여 엣지: authorize 성공 직후 receipt PATCH 전에 EF 가 죽으면 다음 회차의 authorize 재시도가 400 (WARN "may already be AUTHORISED") — 문서는 이미 AUTHORISED, Cin7 에서 상태만 확인.

**진단 팁**: cin7() 실패 throw 에 `| SENT: {body}` 포함(디버깅용, 유지). Cin7 "Lines is invalid" 는 대개 (a)여러 bin 섞임 (b)같은 SKU+bin 중복 (c)PO 에 없는 SKU — SENT 로 격리. GAS `WmsPoStockWriteTest.gs` 의 `psMultiLineTest`(bin별 분할 검증)·`psAuthorizeTest`(PUT/POST 판별) 패턴 재사용.

**트랜스퍼(창고간)** — 이 시점 기록은 "같은창고 bin↔bin 기준, 재설계 필요" 였다. **해소됨**: 2026-07-25 창고간 실측 → 2026-07-28 전면 개정(아래 절). 히스토리로만 남긴다.

## receiving EF — 트랜스퍼 경로 (2026-07-28 전면 개정, 이전 2026-07-25 판을 대체)

⚠️⚠️ **폐기된 이전 판**: "실물 수량으로 덮어쓰기(`recvBySku` → `TransferQuantity` 교체) + `changed` 로그" 는 **제거됐다.**
**Cin7 은 트랜스퍼 완료 PUT 의 `TransferQuantity` 변경을 조용히 무시한다** (실측 2026-07-28, 신규 IN TRANSIT **TR-03267**): SENT 에 변경값이 정확히 실려 나가고 PUT 200 이 떨어지지만 **되읽으면 원본 그대로**다 — `AS93113` 원본 2 → 요청 4 → **저장 2** / `AS92700` 원본 4 → 요청 2 → **저장 4**. **증가·감소 양방향 모두 무시**(API 제약, 코드 버그 아님). 되살리지 말 것. **PO stock received 의 초과 허용은 별개이고 사실이다 — PO 경로는 손대지 않는다.**

**buildApplyPlan transfer 절**
- `transferDetail()` 로 원본 조회. **Status 는 `IN TRANSIT`(신규) 또는 `COMPLETED`(재개) 만 통과** → `plan.mode = "new" | "resume"`. 그 외는 throw. ⚠️ 예전엔 IN TRANSIT 만 허용해 **TR-02935 가 영구히 큐에 갇혔다**(원 TR 은 COMPLETED 인데 bin 이동 미완).
- **⚠️ `applied_at` 게이트의 예외 = 실패한 bin 이동 재시도 (2026-07-28)**: 부분 성공에서도 receipt PATCH 까지 도달하므로 `applied_at` 만으로 막으면 실패한 bin 을 영영 못 옮긴다. **두 겹 게이트**를 통과하면 `applied_at` 이 있어도 재개한다:
  ```ts
  const failedNote = /failed_moves\((\d+)\)/.exec(String(rcpt.apply_note || ""));
  const retryFailed = src0 === "transfer" && !!failedNote && Number(failedNote[1]) > 0;   // ① 표식
  if (rcpt.applied_at && !retryFailed) throw new Error(... " already applied at " ...);
  // … 트랜스퍼 절 끝: ② 실제로 옮길 그룹이 남아 있는가
  if (rcpt.applied_at && retryFailed && !moves.length) throw new Error("… nothing left to retry …");
  ```
  → `plan.mode="resume"`(PUT SKIP) · **`plan.retry=true`** · `action` 에 `(RETRY — …)`. 실패 그룹은 `exported_base` 가 안 찍혀 있어 `pending_base>0` 로 자동 재대상. discrepancy 선기록은 `ignore-duplicates` 라 재실행 안전(확인만). ⚠️ **`failed_moves(N)` 포맷은 EF 정규식·admin.html 이 공유하는 계약이다 — 한쪽만 바꾸지 말 것.**
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
- **plan 노출 필드**: `mode` · `transfer{number,status,landing_bin,landing_label,to_location_raw,to_guid}` · `lines[]`(`move_base`/`pending_base`/`parts` 포함) · `groups[]`(**`pending_base>0` 인 라인만**) · **`leftover_at_landing:[{sku,qty,where}]`**(`where`=`landing_label`) · **`excluded_from_move:[{sku,bin,received,moved,not_moved,reason}]`** · `skipped` · `discrepancies` · **`chunk_size`**(=`APPLY_MAX_GROUPS`)·**`time_budget_ms`**(=`APPLY_TIME_BUDGET_MS`) · **`progress{lines_total, lines_exported}`**(청크 진행률의 시작값 — admin 이 캡 규칙을 JS 로 재계산하지 않고 이 값+commit 응답 필드를 그대로 표시).
- **`parts`**: merge 는 (order_sku + putaway_bin) 기준이라 여러 receipt 라인이 한 planLine 이 된다 → `parts:[{id,received_base,exported_base}]` 를 실어 `exported_base` 체크포인트를 쓸 수 있게 한다.

**applyCommit 실행 순서 (⚠️ 이 순서가 핵심 — 규칙 27 R12)**
1. **⓪ discrepancy 선기록** — `POST wms_discrepancies?on_conflict=receipt_id,sku` + Prefer `resolution=ignore-duplicates,return=minimal`. **Cin7 을 건드리기 전**이고 **실패하면 throw 로 중단**한다(아래 참조). PO·트랜스퍼 공통.
2. **① PUT 완료** — `plan.mode==="resume"` 면 **건너뛰고** 로그만 남긴다. 신규면 `PUT /stockTransfer {TaskID, Status:'COMPLETED', From, To, CostDistributionType, InTransitAccount, DepartureDate, CompletionDate, Reference, Lines: det.Lines, SkipOrder:true}` — **`Lines` 는 원본 그대로**(수량 변경은 무시된다). Date 는 `YYYY-MM-DDT00:00:00Z`.
3. **② 캡된 bin 이동 + `exported_base` 체크포인트** — `plan.groups` 순회. 착지 bin 이면 스킵, GUID 못 찾으면 그 그룹만 스킵(WARN, `skipped_bins`), `pending_base>0` 인 라인만 `POST /stockTransfer {Status:'COMPLETED', From: det.To, To: binGuid(wh,g.bin), Lines:[{SKU:base_sku, TransferQuantity: pending_base}], SkipOrder:true}` (sleep 300).
   - ⚠️ **From 은 항상 `det.To`**. 창고 GUID면 "bin 없는 재고"를, 집결 bin GUID면 그 bin 을 꺼냄 — 둘 다 실측 200.
   - ⚠️⚠️ **POST 가 실패해도 throw 하지 않는다 — 그 그룹만 기록하고 다음으로 (2026-07-28, TR-02935 재개 Apply)**. 실측: 첫 그룹이 400 `"Available quantity for product (SKU: AS97745 …) is 0.0000000000, cannot transfer 2"`(From = 집결 bin `b997fb39-…` EZ010101) 를 내며 **344 라인 중 1 건이 나머지 143 개 bin 이동을 전부 막았다.** 원인은 **리시빙 완료와 Apply 사이의 시차 동안 재고가 이미 움직인 것** — 버그가 아니라 정상 상황이다.
     ```ts
     let res; try { res = await cin7("POST", "/stockTransfer", mini); }
     catch (e) { const info = cin7ErrInfo(e);
       failedMoves.push({ bin: g.bin, skus: […base_sku], qty: Σpending_base, ...info });
       log.push("WARN bin move -> … FAILED (HTTP …): " + info.cin7_error + " …");
       await sleep(300); continue; }          // ⚠️ throw 금지 — 되돌릴 수 없는 구간(R12)
     movedBins++;
     ```
   - **`cin7ErrInfo(e)`** — `cin7()` 이 Error 에 실어 보낸 `status`/`body` 에서 `{http_status, cin7_error}` 를 뽑는다. `cin7_error` = Cin7 응답의 **`Exception` 원문**(배열 응답도 처리, JSON 아니면 원문 300자 컷). 메시지 문자열 파싱이 아니라 구조화된 필드를 쓴다.
   - 성공 직후 `markExported(p)` → `PATCH wms_receipt_lines?id=eq.<part.id> {exported_base}` (`move_base` 를 parts 순서대로 각 라인 `received_base` 한도까지 배분, **절대값이라 재실행 idempotent**). ⚠️ 되돌릴 수 없는 쓰기 뒤이므로 **PATCH 실패에도 throw 금지 — WARN 만**(빠지면 재Apply 가 같은 bin 을 두 번 옮긴다).
   - 재Apply 시 `exported_base` 가 찬 라인은 `pending_base=0` → 그룹째 스킵.
4. **잔량·미이동 로그** — `LEFTOVER stays in <landing_label> (remove in Cin7 with a manual stock adjustment): SKU xN` + `not moved (Cin7 holds none of it): …`. ⚠️ **위치 표현이 (a)/(b) 로 다르다** — (b) bin 이름 / (a) `"Asung - Edmonton (no bin)"`. 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다.
5. **③ receipt PATCH** — `status='completed'` + `applied_at`/`applied_by`/`apply_note`(로그 조인, 위 LEFTOVER·skipped_bins 줄 포함). ⚠️ **bin 이동이 전부 실패해도 여기까지 온다** — 안 그러면 receipt 이 큐에 갇히고 discrepancy 만 남는다(TR-02935).

**부분 성공 판정 & 노출 (2026-07-28)** — 트랜스퍼 경로. **판정 기준은 `failed_moves.length > 0`** 하나다(log 의 WARN 문자열 아님):
- **EF 응답 최상위**: `failed_moves: [{bin, skus:[…], qty, http_status, cin7_error}]` + `moved_bins`(성공한 그룹 수). `ok:true` 지만 부분 성공이다.
- **`apply_note`**: `failed_moves(N): [ …JSON 900자 컷… ]` 한 줄 + `PARTIAL — N moved, M failed …` 안내 줄. ⚠️ **`failed_moves(<정수>):` 포맷은 계약이다** — buildApplyPlan 의 재시도 게이트 정규식과 admin.html 의 CIN7 열 표시가 같은 패턴을 읽는다.
- **admin.html**: History CIN7 열 = `✓ Applied` 대신 **`⚠ Applied (N bins failed)`**(warn 색, title 에 apply_note 전문) · Apply 목록에 **그대로 남고** 버튼이 `Retry failed bins` · Apply 후 알림에 "N moved / M failed" + bin·SKU·Cin7 에러 요약 + *"Fix the stock in Cin7, then Apply again — only the failed bins will be retried."* · dry-run confirm 의 Mode 줄에 `RETRY`.
- ✅ **PO 경로에도 2026-07-31 이식** — 같은 판정(`failed_moves.length > 0`)·같은 마커·같은 admin 기계장치를 쓰되, 후속 안내가 다르다: "착지 지점의 재고" 가 아니라 **"authorize 안 된 DRAFT 문서"**(위 applyCommit PO 경로 절 — authorize 게이트).

**discrepancy 기록 (PO·트랜스퍼 공통) — ⚠️ 2026-07-28 순서·실패정책 역전**: buildApplyPlan 이 SKU 단위로 received vs expected 를 비교해 `plan.discrepancies[]`(reason `recv_over`/`recv_short`/`recv_off_po`) 생성. 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 기록이 통째로 유실됐다(TR-02935 실사고). 지금은 **맨 처음**이고 **실패 시 Apply 중단**(`"discrepancy log failed - NOTHING was written to Cin7"`) — 새 정책에서 이 큐는 **유일한 보정 지시서**라 기록 없이 재고를 옮기면 차이를 되찾을 수 없다. `sb()` 헬퍼 4번째 인자 `prefer` 사용.

- ⚠️⚠️ **2026-07-29 — 이 선기록이 실제로는 전부 400 이었다 (규칙 29).** `on_conflict=receipt_id,sku` 가 가리키는 `uq_disc_receipt_sku` 가 **부분(partial) 유니크**(`WHERE receipt_id IS NOT NULL`)여서 PostgREST 가 추론하지 못했다 → **`42P10 there is no unique or exclusion constraint matching the ON CONFLICT specification`**. 새 정책에서는 이 실패가 곧 Apply 중단이라 Cin7 쓰기 자체가 막혔고, 그 전(선기록 이전 판)에는 **리시빙 discrepancy 가 조용히 한 건도 안 들어가고 있었다.** 인덱스를 WHERE 절 없는 전체 유니크로 교체해 해소 — `supabase/wms_disc_uq_fix.sql`. **EF 코드는 그대로**(`on_conflict` 조합을 바꾸는 게 아니라 인덱스를 고치는 것이 맞다). 📌 앞으로 `on_conflict` 를 쓸 컬럼 조합은 **`pg_indexes` 로 전체 유니크인지 먼저 확인**한다.

**청크 처리 — 그룹 수 + 시간 예산 이중 가드 (✅ 2026-07-31 v2, 규칙 30-2 해소)**
- **`APPLY_MAX_GROUPS = 12` + `APPLY_TIME_BUDGET_MS = 20000`** — 먼저 걸리는 쪽에서 회차를 끊는다. 실측 근거: TR-02935(144 그룹, 1회차 81 라인 후 무응답)·TR-03144(327 라인/100+ 그룹, 매 회차 30~40 그룹 부근 타임아웃으로 `applied_at`·`apply_note` 둘 다 null). ⚠️ **1차 구현(상한 30 만)은 배포 후에도 첫 회차조차 완주하지 못했다**(TR-03144 — `exported_base` 210→225→250 전진, `apply_note` null 지속) — 실패 그룹도 왕복+sleep 을 소비하고 Cin7 응답 속도가 날마다 달라 그룹 수만으로는 회차 시간을 못 가둔다. **원칙: 회차는 반드시 완주해야 한다 — 완주 못 하면 기록이 안 남아 원인 추적 불가.**
- **시간 예산의 기준점 = 요청 시작 t0**(Deno.serve 진입 직후 — buildApplyPlan·PUT 도 EF 한도에 포함되므로). **판정은 그룹 루프 머리, 즉 Cin7 POST 앞에서만** — 반쯤 옮긴 그룹을 만들지 않는다. 끊은 가드는 `stopped_by:"groups"|"time"` 으로 응답·apply_note 양쪽에 남긴다(429 만이면 null + `rate_limited`) — 다음 상한 조정의 근거.
- **상한 카운트 = 이번 회차에 Cin7 POST 를 실제로 시도한 그룹 수(성공+실패)** — 실패도 왕복 1회를 먹는다. 착지 bin 스킵·already-exported 스킵·GUID 미해석 스킵은 상한에 안 센다. 가드 도달 이후 그룹은 **아무것도 하지 않고** `groups_remaining` 으로만 센다.
- **종료부(apply_note PATCH + 응답 반환)는 회차의 가장 값싼 마지막 동작** — Cin7 호출·무거운 재조회 금지. `lines_moved` 는 DB 재조회 없이 plan.progress.lines_exported + 이번 회차 markExported 수. **receipt PATCH 가 실패해도 응답은 반환한다**(log 에 WARN + 응답 `note_saved:false`; done 회차였다면 applied_at 도 미기록 → 다음 Apply 가 DB 재조회로 수렴해 PATCH 만 재시도, 이중 이동 없음).
- **청크 경계에서 이중 이동 없음**: 성공 그룹은 POST 직후 `markExported` 로 `exported_base` 가 찍히고, 미처리 그룹은 안 찍힌다. commit 은 매 호출 `buildApplyPlan` 이 DB 를 다시 읽으므로 다음 회차의 `pending_base>0` 필터가 미처리 그룹만 다시 집는다 — 기존 재시도 경로와 같은 메커니즘. (남는 구멍은 종전과 동일: `exported_base` PATCH 자체가 실패하면 WARN 만 남고 재이동 위험 — R10.)
- **commit 응답 추가 필드**: `done`(잔여 0 이면 true) · `groups_total`(이번 회차 후보 = 시도+잔여) · `groups_moved` · `groups_remaining` · `lines_moved`/`lines_total`(receipt 라인 기준 **누적** — plan.progress.lines_exported + 이번 회차 0→양수 전환 수) · `rate_limited` · `stopped_by:"groups"|"time"|"fail_budget"|null` · `note_saved` · `source`("po"|"transfer" — admin 문구 분기용) · `authorized`(PO 전용 — 위 authorize 게이트). 기존 `failed_moves`/`moved_bins`/`skipped_bins`/`log` 유지. dry-run plan 에는 `chunk_size`+`time_budget_ms`. **2026-07-31 부터 PO·트랜스퍼 공통**(청크 판정·마커·진행률 전부).
- **`applied_at` 은 done:true 회차에만.** 중간 회차는 `apply_note` 만 매 회차 갱신(정상 종료에서 항상 기록이 남는다 — R14 의 반대 방향 보증): 진행 줄 `CHUNK - N group(s) moved this round · x/y lines exported` + 계약 표식 **`groups_remaining(N):`** 한 줄. ⚠️ `failed_moves(N):` 처럼 **EF 정규식(buildApplyPlan 재개 게이트)과 admin.html(Continue apply 버튼·History `⏸ N groups left` 표시)이 공유하는 계약 포맷** — 한쪽만 바꾸지 말 것.
- **재개 게이트 확장**: `retryFailed = transfer && (failed_moves(N)>0 || groups_remaining(N)>0)` — applied_at 이 이미 찍힌 부분실패 receipt 의 재시도 회차가 다시 청크에 걸려도(done:false 인데 applied_at 은 과거 값) 다음 Apply 가 막히지 않는다. ⚠️ **2026-07-31 PO 이식에서 갱신**: `transfer` 제한은 폐지 — **소스 무관**, 마커도 `permanently_failed(N)` 포함(위 buildApplyPlan po 절·아래 v3).
- **429**: `cin7()` 이 백오프(1.5s→3s, **상한 2회**) 후에도 429 면 `status=429` 를 실어 throw → 그룹 루프가 **`failed_moves` 에 넣지 않고**(재시도 대상 표식이 어긋난다) `rate_limited=true` 로 회차를 조기 종료, 잔여는 다음 회차. 그룹 간 sleep 은 **300→150ms**.
- **admin 자동 반복 (admin.html applyToCin7)**: `done:false` 면 commit 을 재호출(회차 사이 dry-run 없음). 진행률은 EF 응답 필드 그대로: 버튼 `Applying… 210/327` + 배너 `Applying… 210 / 327 lines · 58 bin groups left`. **Stop 버튼**(배너·모달 노트 양쪽) = 회차 경계에서 멈춤 — exported_base 체크포인트까지 안전, receipt 은 큐에 남아 `Continue apply` 로 재개. ~~**무한 루프 가드** = 한 회차 `groups_moved===0`(남은 그룹 전부 실패·429 지속)이면 중단 + 실패 목록 alert / 회차 상한 `APPLY_MAX_ROUNDS=20`~~ ⚠️ **v3 에서 정정 — 이 가드가 실측 사고의 공범이었다**(아래 v3: `groups_moved===0 && groups_tried===0` 2회 연속만 중단, 상한 30). `beforeunload` 경고·재진입 차단(applyBusy)·rAF 150ms 타임아웃·`loadRecv().catch()` 격리는 자동 반복 전체 구간 유지.
- ✅ **PO 경로 이식 완료 (2026-07-31)** — 청크·체크포인트·실패 격리 전부 + PO 고유 **authorize 게이트**(위 applyCommit PO 경로 절). 가드 판정은 공용 `chunkGuard()` 로 추출(트랜스퍼 동작 불변 — 같은 상수·같은 순서의 판정을 헬퍼로 옮긴 것뿐).

**청크 v3 + 목적지 되읽기 회복 (✅ 2026-07-31 배포 — TR-03144 실측으로 v2 의 구멍 2개를 막음, 규칙 21 청크 절 v3·④)**

- **구멍 1 — 실패 그룹이 미처리 그룹을 가로막았다.** v2 배포 후 실측 apply_note: `CHUNK - 0 group(s) moved, 3 failed · stopped_by=time` — **실패 3그룹만으로 20초 예산 전소**(Cin7 400 응답이 느리고 그룹당 SKU 5~7개, 예 EU060503). 실패가 plan.groups 앞쪽이라 매 회차 그것부터 시도하고 끝나 **46개 미처리 그룹 영구 정지** + v2 무한루프 가드(`groups_moved===0`)가 자동 반복까지 중단. 실패 사유는 전부 `Available quantity … is 0` — 사람이 고치기 전엔 재시도해도 영원히 실패한다. 조치:
  - **① 정렬**: buildApplyPlan 이 그룹을 **미시도 먼저, 실패 이력(연속 실패 수 오름차순) 뒤로** — 매 회차 실제 전진 보장. 순서는 시도 순서일 뿐 이중 이동과 무관(무엇을 옮길지는 매 회차 DB 재조회 `pending_base>0` 가 정함).
  - **② 격리**: 같은 bin **연속 `APPLY_QUARANTINE_FAILS`(3)회 실패** → `permanently_failed` 분류("N bin(s) need manual fixing in Cin7"). **`groups_remaining` 에 세지 않으므로** 격리만 남으면 `done:true`(applied_at 찍힘). 해제 = admin `Retry failed bins` → **`&retry_failed=1`**(dry-run + **첫 commit 회차에만** 부착 — 자동 회차마다 붙이면 격리에 영영 못 도달)이 fail 카운트 리셋.
  - **③ 실패 예산**: 회차당 실패 이력 그룹 시도에 `APPLY_FAIL_BUDGET_MS`(6000ms)만 — 초과분은 다음 회차(`stopped_by:"fail_budget"`). 400 은 재시도 없음 — `cin7()` 백오프는 429 전용.
  - **연속 실패 카운트는 apply_note 의 `fail_counts:{"BIN":n}` 마커**로 회차 간 이월(성공=삭제·실패=+1·미시도=이월). 429 는 카운트 제외(rate limit 가 실패로 둔갑해 멀쩡한 bin 이 격리되면 안 된다). ⚠️ **`failed_moves(N):` 뒤 JSON 은 900자 컷이라 이미 깨진 JSON — 파싱 금지**(cin7_error 300자 × SKU 5~7개). fail_counts 컴팩트 마커가 따로 있는 이유다. **계약 마커 4개** = `failed_moves(N):`·`groups_remaining(N):`·`permanently_failed(N):`·`fail_counts:{...}` — EF·admin.html 공유.
  - **admin v3**: 버튼 우선순위 = 미처리 있으면 **`Continue apply`**(실패분은 정렬 뒤에서 함께, 격리 제외) / 미처리 0·실패만 남으면 **`Retry failed bins`**. 무한루프 가드 = `groups_moved===0 && groups_tried===0` **2회 연속**만 중단(시도가 있으면 실패 카운트가 전진해 격리로 반드시 수렴), `APPLY_MAX_ROUNDS` 20→**30**. EF 응답에 `groups_tried`·`permanently_failed` 추가.
- **구멍 2 — 회차가 Cin7 POST 와 markExported PATCH 사이에서 죽으면 잔여물이 남는다.** TR-03144 격리 10 bin/25 라인 수동 확인 → **전부 이미 목표 bin 도착**(죽은 회차 수와 격리 bin 수 거의 일치). → **목적지 되읽기 회복(checkpoint repair)**: `Available quantity … is 0` 400 **패턴에만**(다른 400 은 조회 무의미) 목적지 bin 을 `GET /ref/productavailability?Sku=` 로 되읽어 — **SKU 정확 일치 + 창고 `normWarehouse` + Bin 정확 일치, OnHand 합**(Available 은 판매 배정 차감이라 도착 재고를 놓친다 — R11: 근거는 되읽은 값) — **pending_base 이상이면** `exported_base` 를 기록하고 완료 간주. 오판 방지: "이상" 비교(기존 재고 bin 은 더 많을 수 있음) · 조회 실패/응답 잘림(`Total > 반환 행수`)/수량 부족 → 실패 유지 · 그룹 내 **전 라인 확인 = 그룹 완료**(일부만이면 라인만 기록, 그룹은 실패) · 시간 예산(20초/실패 6초) 부족 시 조회 생략(완주 최우선). 응답·apply_note 에 `checkpoint_repaired: N`(측정용 — 계약 마커 아님). **근본 원인은 v3 완주 보장으로 해소 — 이 경로는 잔여물 정리·드문 엣지용.** v3 이후에도 N 이 계속 나오면 다른 원인 신호(규칙 27 R10). **PO 미적용**(위 PO 절 — `Cannot add duplicate value` 400 이 대신 시끄럽게 막는다).

## 폴링 EF `hello` — Reference 저장 (2026-07-25)

`extractReference(d)` 추가: `d.CustomerReference` → 폴백 `d.Reference`. `wms_orders.reference` 로 저장, dry-run `would_insert` 에도 노출해 유입 확인 가능. ⚠️ **`wms_order_reference.sql`(컬럼 추가)을 배포보다 먼저** — 없으면 insert 400.

## 폴링 EF `hello` — Order Date 저장 (2026-08-02)

`wms_orders` insert 에 `order_date: (d.OrderDate || c.OrderDate || "").slice(0, 10) || null` 추가(`d`=`/sale` 상세, `c`=`saleList` 항목 — **상세 우선, 목록 폴백**). 앞 10자만 잘라 `date` 컬럼에 넣는다(`ship_by` 와 같은 방식).

- 마이그레이션 `supabase/migrations/20260802000000_wms_order_date.sql`. ⚠️ **컬럼을 EF 배포보다 먼저** — Reference 때와 같은 함정이고 더 나쁘다: 헤더 insert 가 통째로 실패하므로 **오더 유입이 전면 중단**된다.
- ⚠️ **신규 유입분부터만 찬다** — 기존 행은 null, 소급 백필 없음. 픽리스트 인쇄(`wms-picklist.js`)가 값 없으면 줄/열을 생략하므로 옛 오더도 깔끔히 찍힌다.
