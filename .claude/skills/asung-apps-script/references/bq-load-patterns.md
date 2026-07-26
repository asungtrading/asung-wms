# BQ 적재 패턴 (bq-load-patterns)

Apps Script에서 BigQuery로 데이터를 적재할 때의 표준 패턴.

## diff-check 증분 적재

전체 재적재는 GAS의 6분 실행 제한에 걸립니다. 이미 BQ에 있는 것과 비교해 delta만 올립니다.

대략의 흐름:

```javascript
// 1) BQ에 이미 있는 키 집합을 가져온다
function sd_getExistingKeys_(project, dataset, table) {
  const sql = `SELECT DISTINCT order_key FROM \`${project}.${dataset}.${table}\``;
  const req = { query: sql, useLegacySql: false };
  const res = BigQuery.Jobs.query(req, project);
  const set = {};
  (res.rows || []).forEach(r => { set[r.f[0].v] = true; });
  return set;
}

// 2) Cin7 데이터 중 신규/변경만 추린다
function sd_filterDelta_(cin7Rows, existingKeys) {
  return cin7Rows.filter(row => !existingKeys[sd_makeKey_(row)]);
}

// 3) delta만 적재 (tabledata.insertAll 또는 load job)
```

## 키 생성과 dedup 주의

- `insertId`/`order_key`에 **Status 문자열을 넣지 말 것.** 'Closed'와 'CLOSED'처럼 대소문자만 다른 값이 서로 다른 행으로 적재되어 중복이 생깁니다.
- 키는 안정적인 식별자(주문번호 + 라인 식별자 등)로만 구성.

## 재적재 시 streaming buffer 함정

streaming insert 직후 데이터는 buffer에 머물고, 이 동안 `DELETE`/`UPDATE`가 거부됩니다(`UPDATE or DELETE statement over table … would affect rows in the streaming buffer`).

해결책 (선호 순):

1. **CTAS 통째 교체** — 가장 안전.
   ```sql
   CREATE OR REPLACE TABLE `proj.ds.tbl` AS
   SELECT * FROM `proj.ds.tbl_staging`;
   ```
2. **load job 사용** — streaming(`insertAll`) 대신 load job으로 적재하면 buffer 이슈를 우회. 대량 적재에 적합.
3. 부득이 DELETE가 필요하면 buffer가 빠질 때까지(수십 분) 기다린 뒤 실행.

## report_month 단위 재적재

월별로 갈아끼우는 테이블(`asung_sales_confirmed`)은:

1. 새 월 파일을 staging 테이블에 load
2. 본 테이블에서 해당 `report_month` 파티션을 비우거나, CTAS로 "그 월 제외 + staging" 합치기
3. **여러 달을 한 번에 처리하지 말 것** (netting 버그). 한 번에 한 월.

## BigQuery Advanced Service

- Apps Script에서 `BigQuery.Jobs.query(...)`, `BigQuery.Tabledata.insertAll(...)`, `BigQuery.Jobs.insert(...)`(load job)를 쓰려면 **Advanced Google Service에서 BigQuery API를 켜야** 합니다.
- 대량 적재는 `insertAll`(streaming)보다 load job이 안전(buffer 이슈 없음).
