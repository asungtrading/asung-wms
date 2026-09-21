# 재적재 절차 — 운영 `asung-WMS` → 테스트 `Asung-IMS`

작성 2026-09-21 · **성격: 컷오버 절차의 초판**
한 줄 요약: 운영 `asung-WMS` 의 Cin7 축을 테스트 `Asung-IMS` 로 가져오되 **IMS 가 낸 것은 건드리지 않는다.**

⚠️ **이 문서가 정본이다.** `ledger-design.md` §테스트 DB 의 **재복사 절차**(세 단계 + ②′ 비우기 · `truncate inv_config;` 먼저)는
이 문서로 대체됐다. 그 절의 **최초 구축 절차와 함정 넷**(IPv6 · Docker · URL 파일 · `inv_config` 중복 키)은 그대로 유효하다 —
빈 테스트 DB 를 새로 만들 때는 여전히 그쪽을 본다.

⚠️ 옛 절차가 왜 이제 안 되나 — 옛 절차는 **테스트가 비어 있다는 전제**로 쓰였다. 지금은 테스트에만 있는 것이 많다:

| | 옛 절차 | 지금 |
|---|---|---|
| 제외 12표 | 로그성이라 뺐다 | **필요하다** — `inv_missing_lines` 554 · `inv_conflicts` 128 은 감지 기록 |
| `truncate inv_config;` | 함정 4의 처방 | ⚠️ **IMS 설정 2행이 사라진다**(`po_create` 가 멈춘다) |
| `inv_ledger` | 빈 표에 붓는다 | ⚠️ **`id` 유니크 충돌로 막힌다** |
| `inv_layer` 계열 | 운영 0행이라 무해 | ⚠️ **테스트 41,479행이 사라진다** |
| `wms_` 표 | 넷만 제외 | **26개 전부 범위 밖**이어야 한다 |

### 배경 — 두 홉

컷오버(목표 2027-01-01)는 **`Asung-IMS` 를 운영으로 승격**하는 쪽으로 확정됐다(2026-09-21).
Caleb: "컷오버때도, cin7에서 바로 가져오지 않고, asung-wms에 일단 오고 그것을 가져오는 것이 더 안전할 것 같아."
Caleb(승격을 택한 근거 · 2026-09-21): "컷오버 시점에 wms는 cin7접점이 끊기는데, 그 것을 메우고 문제없는지 확인하기 보다는, 미리 wms를 ims에 맞게 최적화 해놓고 검증을 하는게 더 나아 보여."
⇒ 운영 `asung-WMS` 가 Cin7 을 긁고, 그것을 `Asung-IMS` 로 복사한다. **이 절차는 그 두 번째 홉이다.**

📌 본문은 **단일판**(17표 한 번에 덤프 · 한 트랜잭션 복원)이다. 2026-09-21 1차 실행은 2단 덤프(16표 + 원장 별도)로 했고,
같은 날 2차 실행이 본문 단일판을 그대로 돌려 **실증했다**(11:29 덤프). 경위·실측은 §N. 열린 항목은 **§O** 에 모아 둔다.

---

## §A 표를 세 갈래로 가른다 (실측 2026-09-21)

**A 갈래 — 운영으로 갈아 끼움 (16)**
```
inv_snapshot · inv_compare · inv_compare_runs · inv_snapshot_runs
inv_collect_runs · inv_missing_lines · inv_missing_docs · inv_conflicts
inv_voided_docs · inv_balance_diffs · inv_cost · inv_doc_cost
inv_doc_state · inv_sync_state · inv_sku_types · inv_bin_notes
```
근거(실측): `doc_number` 를 가진 여섯 표에서 `RCV-%` **0건** · `collector` 값이 전부 `inv-collect@…`·`inv-cost@…`·`inv-doc-cost@…` ·
`inv_balance_diffs` 의 사람 확인 31행이 운영 53행에 **내용까지 일치** · `inv_bin_notes` 1행 양쪽 동일.
📌 09-10 재복사에서 `inv_doc_cost` 의 테스트 전용 `manual@2026-09-10` 2행이 운영 것으로 교체된 선례가 있다 —
A 갈래에 넣기 전 「IMS 가 낸 행이 없다」를 **매 회차** 위 방식으로 다시 본다.

**B 갈래 — 행 단위로 가름 (2)**
- `inv_ledger` — `source='ims'` 를 지킨다(2026-09-21 기준 4행). 운영에서 오는 것은 `cin7`·`manual`.
- `inv_config` — `baseline_snapshot_key` **외 전부** 지킨다. IMS 2행: `base_currency`(09-11) · `po_inventory_account_code`(09-16) · 둘 다 `po_create` 가 읽는다.

**C 갈래 — 손대지 않음 (3)**
- `inv_layer` · `inv_layer_consume` · `inv_layer_cost_add`
- 운영 0행(실측 확인) · 덮으면 테스트 것이 사라진다 · 재적재 후 **함수로 재생성**한다(§H).

**범위 밖 — `wms_` 26개** → §M. ⚠️ 승격을 택했으므로 컷오버 때 결국 이사해야 한다. 이 절차의 범위는 아니다.

⚠️ **16개 이름은 이 문서 세 자리에 반복된다** — §A(이 목록) · §D(`not in`) · §E(`truncate`). **바꿀 때 셋 다 고친다.**
어긋나면 §D 검산 「COPY 목록 = 기대 목록」이 잡는다 — 그 검산을 건너뛰지 않는 이유다.

---

## §B 전제 확인 — 네 관문

**① `pg_dump --version` 이 서버 버전 이상인가**
⚠️ 숫자를 박지 마라 — PC 마다 다르다(같은 세션에서 16.10 과 18.6 이 둘 다 나왔다). 조건으로 적는다.
실측 2026-09-21: 서버 17.6 · 클라이언트 18.6 ⇒ 통과.
📌 `supabase db dump` 는 Docker 컨테이너의 `pg_dump` 를 쓰므로 이 관문은 **§E 의 `psql`** 쪽 클라이언트에 대한 것이다.

**② 마이그레이션이 양쪽 자리인가**
```bash
cd ~/asung/asung-wms
supabase migration list --linked                                # 운영
supabase migration list --db-url "$(cat ~/.asung-testdb-url)"   # 테스트
```
실측 2026-09-21: 운영 Remote 빈 줄 ~~**52**(`20260911144606`~`20260920181910`)~~ → 오후 **53**(`20260911144606`~`20260921161933` = IMS 모듈 + `po_in` 순서 수정) · 테스트 빈 줄 **0**.
```bash
# 53 의 근거 — 레포에서 센다 (지시서 초안의 51 은 오기 · 09-21 오후 20260921161933 추가로 52 → 53)
ls supabase/migrations/ | awk '$0 >= "20260911144606"' | wc -l     # 53
```
⭐ 이 방향은 **안전하다** — 운영에 없는 표가 테스트에 더 있으니 덤프를 부을 자리가 다 있다.
⛔ 반대(테스트 빈 줄 > 0)면 복원이 막힌다. 처방: `supabase db push --db-url "$(cat ~/.asung-testdb-url)"` — ⚠️ 사람이 실행.
⬜ 운영 일괄 배포 판단(53개를 올리면 이 기준값이 바뀐다) — §O.

⚠️ **조건 하나 더** — 테스트만 앞선 마이그레이션이 **A 갈래 16표의 컬럼을 바꾸지 않았는가.** 바꿨으면 운영 `COPY` 의 컬럼 목록이 안 맞는다.
```bash
# 운영에 없는 첫 마이그레이션 이후 파일에서 16표를 alter 하는 것을 찾는다 — 기대: 출력 없음
ls supabase/migrations/ | awk '$0 >= "20260911144606"' | while read f; do
  grep -liE 'alter table (public\.)?inv_(snapshot|compare|compare_runs|snapshot_runs|collect_runs|missing_lines|missing_docs|conflicts|voided_docs|balance_diffs|cost|doc_cost|doc_state|sync_state|sku_types|bin_notes)\b' "supabase/migrations/$f"
done
```
실측 2026-09-21: **0건.** (`20260911144606` 자리는 그때의 「운영에 없는 첫 마이그레이션」으로 바꿔 쓴다.)

**③ 운영이 Cin7 을 어디까지 읽었나**
```sql
-- [asung-WMS (운영)]
select source_key, last_cursor,
       last_run_at at time zone 'America/Toronto' as last_run,
       last_ok_at  at time zone 'America/Toronto' as last_ok, note
from inv_sync_state order by source_key;
```
⚠️⚠️ **이 관문이 두 홉 방식의 유일한 약점을 막는다.** 운영이 Cin7 을 어디까지 읽었는지가 그대로 IMS 의 지평선이 된다.
커서가 멈춘 채 복사하면 그 상태를 옮기면서 「깨끗하게 옮겼다」고 판단하게 된다.
· 멈춘 축이 있고 **이유를 안다** → 알고 넘어간다
· 멈춘 축이 있고 **이유를 모른다** → ⛔ 여기서 멈춘다. 재적재보다 그것이 먼저다
실측 2026-09-21: 여덟 축 전부 당일 오전 정상 · `transfer` 는 `TR-04495` 에서 정지(원인 기지 = `TR-04496` ORDERED 블로킹) ⇒ 알고 넘어감.

**④ 컷오버 날 — 덤프 전 운영 cron 을 정지한다**
📌 테스트 재적재 때는 건너뛴다. 컷오버 때는 필수다.
운영이 계속 긁는 채로 덤프하면 「덤프 시각 이후 운영에 들어온 사건」이 승격된 DB 에 없다. ③ 의 커서를 읽고 → cron 정지 → 마지막 회차가 끝났는지 확인 → §D 로.
⭐ 단일판(17표 한 덤프)이라 표끼리는 한 스냅샷이지만, **Cin7 과의 시점**은 cron 을 멈춰야 고정된다.
⬜ 정지 명령(`cron.unschedule` 목록)은 컷오버 설계에서 `supabase/ops/cron.sql` 기준으로 만든다 — §O.

---

## §C 되돌릴 자리 만들기

```sql
-- [Asung-IMS (테스트)]
-- ⛔ 창 가드 — 이 문장이 멈추면 테스트(Asung-IMS) 창이 아니다. 아래를 돌리지 마라 (po_line 은 IMS 전용 표 · 20260916144201)
do $$ begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'po_line') then
    raise exception 'not Asung-IMS (test): po_line missing — this window is the production project';
  end if;
end $$;

create schema if not exists reload_backup;
drop table if exists reload_backup.ledger_ims;
drop table if exists reload_backup.config_ims;
drop table if exists reload_backup.layer;
drop table if exists reload_backup.layer_consume;
drop table if exists reload_backup.layer_cost_add;

create table reload_backup.ledger_ims     as select * from inv_ledger where source = 'ims';
create table reload_backup.config_ims     as select * from inv_config where key <> 'baseline_snapshot_key';
create table reload_backup.layer          as select * from inv_layer;
create table reload_backup.layer_consume  as select * from inv_layer_consume;
create table reload_backup.layer_cost_add as select * from inv_layer_cost_add;

select 'ledger_ims' t, count(*) from reload_backup.ledger_ims
union all select 'config_ims', count(*) from reload_backup.config_ims
union all select 'layer', count(*) from reload_backup.layer
union all select 'layer_consume', count(*) from reload_backup.layer_consume
union all select 'layer_cost_add', count(*) from reload_backup.layer_cost_add;
```
📌 SQL Editor 가 「destructive operations」·「tables without RLS」 경고를 낸다. **둘 다 넘어간다** — 지우는 것은 직전 회차 백업뿐이고,
`reload_backup` 은 PostgREST 에 노출되지 않는다. `Run without RLS`.
⚠️ 이 구조는 **직전 회차 백업을 덮어쓴다.** 회차별 보관이 필요하면 스키마명에 날짜를 붙인다.
📌 백업의 용도가 갈래마다 다르다 — `ledger_ims`·`config_ims` 는 **복원용**, `layer*` 셋은 **대조용**(§H 가 어차피 재생성한다). §L 참조.
⛔ **창 가드가 SQL 머리에 있는 이유** — 2026-09-21 하루에 두 번 SQL Editor 창이 다른 프로젝트에 머물러 있었다. 이 절은 **테스트에 쓰는** 절이라
운영 창에서 돌리면 운영에 `reload_backup` 스키마가 생긴다. `po_line` 은 IMS 전용 표라 그것이 없으면 운영이다 — 멈춘다. §G·§H 도 같다.

실측 2026-09-21: 1차 `4 · 2 · 19,401 · 21,328 · 750` · 2차 `4 · 2 · 23,327 · 30,971 · 2,173`(1차 §H 재생성 결과가 그대로 백업됐다)

---

## §D 덤프 — 제외 목록을 손으로 적지 않는다

⚠️⚠️ **이것이 이 절차의 핵심 장치다.** 제외 목록을 손으로 적으면 빠뜨렸을 때 **들어오는 쪽으로 실패**한다(`wms_order_lines` 49,903행이 딸려 온다).
쿼리로 뽑으면 빠뜨릴 수가 없고, 운영에 표가 늘어도 다음 회차에 자동 반영된다.

⭐ **17표를 한 번에 뜬다** — A 갈래 16 + `inv_ledger`. `pg_dump` 는 한 스냅샷 트랜잭션으로 읽으므로 **커서(`inv_sync_state`)·문서 상태·원가·원장이 같은 시점**이 된다.
(1차 실행은 16표와 원장을 따로 떠서 시점이 갈렸다 — §N.)

```sql
-- [asung-WMS (운영)] — 17개만 남기고 나머지를 -x 인자로 뽑는다 · must_be_zero 가 0 이어야 운영 창이다
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'po_line') as must_be_zero,
  (select string_agg('-x public.' || c.relname, ' ' order by c.relname)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname not in (
       'inv_snapshot','inv_compare','inv_compare_runs','inv_snapshot_runs',
       'inv_collect_runs','inv_missing_lines','inv_missing_docs','inv_conflicts',
       'inv_voided_docs','inv_balance_diffs','inv_cost','inv_doc_cost',
       'inv_doc_state','inv_sync_state','inv_sku_types','inv_bin_notes',
       'inv_ledger')) as exclude_args;
```
📌 `must_be_zero` 가 1 이면 테스트 창이다(`po_line` 은 IMS 전용 표). 2026-09-21 하루에 두 번 실제로 그랬다 — 대화 Claude 가 `[asung-WMS (운영)]` 이라
적었지만 SQL Editor 창이 테스트에 머물러 IMS 표가 섞인 목록이 나왔다.
⚠️ 다만 **이 칸은 습관용이다** — 이 쿼리는 창이 틀려도 덤프 결과가 같다. `pg_dump --help` 원문: "An exclude pattern failing to match any objects is not
considered an error" — 운영에 없는 IMS 표의 `-x` 는 무시된다. 창 실수가 **정말 위험한 자리는 반대편**(테스트에 쓰는 §C·§G·§H)이고 그쪽엔 멈추는 가드를 넣었다.
📌 운영 기준 결과는 **30개**(`inv_config` · `inv_layer` 계열 3 · `wms_` 26 · 2026-09-21 실측).

그 문자열을 그대로 붙여 덤프한다:
```bash
cd ~/asung/asung-wms && supabase db dump --linked --data-only --use-copy --schema public \
  <뽑은 -x 문자열> -f ~/reload-17.sql
```
⚠️ `--schema public` 필수 — 없으면 `auth`·`storage` 가 들어온다
⚠️ Docker Desktop 이 떠 있어야 한다(`supabase db dump` 는 컨테이너로 `pg_dump` 를 돈다)
⚠️ `cd` 는 **레포 안**이어야 `--linked` 가 듣는다
📌 `pg_dump` 가 순환 FK 경고(`wms_pallets`·`inv_layer`)를 낼 수 있다 — 데이터 전용 덤프에 그 표는 없고, 경고는 무해하다(09-10 실측).

**검산 — 붓기 전에 여기서 잡는다**
```bash
ls -lh ~/reload-17.sql
grep -c '^COPY ' ~/reload-17.sql                                        # 기대 17
grep '^COPY ' ~/reload-17.sql | awk '{print $2}' | sort                  # §A 16 + "public"."inv_ledger"
grep -c '^COPY "auth"\|^COPY "storage"' ~/reload-17.sql                 # 기대 0
grep -c '^CREATE \|^ALTER TABLE.*ADD CONSTRAINT\|^DROP ' ~/reload-17.sql # 기대 0
head -1 ~/reload-17.sql   # 기대: SET session_replication_role = replica;
grep -c 'setval' ~/reload-17.sql                                         # 기대 ≥ 1 (시퀀스 복원)
date '+%F %T %Z'           # ⚠️ 덤프 시각을 §J 용으로 적어 둔다
```
📌 `replica` 줄이 중요하다 — 그 설정이 있어야 복원 중 트리거가 멈춘다. 없으면 `ims_touch()` 같은 트리거가 돌아 `updated_at` 이 전부 오늘로 덮인다.

실측 2026-09-21: 1차(10:46 · 16표판) 63M · COPY 16 · 목록 일치 · auth 0 · DDL 0 · replica 확인 ·
2차(**11:29:48 EDT** · 17표 단일판) **107M · COPY 17 · auth 0 · DDL 0 · replica 확인 · setval 14**.

---

## §E 복원 — 한 트랜잭션

⭐ pre(비우기) → 덤프 → post(원장 마무리)를 **`psql --single-transaction` 하나**로 돈다. 어디서 실패해도 **통째로 되돌아간다** —
테스트가 「비었는데 안 채워진」 상태나 「A 는 새것 · 원장은 옛것」 상태로 남지 않는다.

```bash
cat > ~/reload-pre.sql <<'SQL'
truncate table
  public.inv_balance_diffs, public.inv_bin_notes, public.inv_collect_runs,
  public.inv_compare, public.inv_compare_runs, public.inv_conflicts,
  public.inv_cost, public.inv_doc_cost, public.inv_doc_state,
  public.inv_missing_docs, public.inv_missing_lines, public.inv_sku_types,
  public.inv_snapshot, public.inv_snapshot_runs, public.inv_sync_state,
  public.inv_voided_docs,
  public.inv_ledger
  restart identity cascade;
SQL

cat > ~/reload-post.sql <<'SQL'
-- 원장 시퀀스를 운영 최대값 위로 (덤프 끝의 setval 과 중복돼도 무해)
select setval(pg_get_serial_sequence('public.inv_ledger','id'),
              (select max(id) from public.inv_ledger));

-- IMS 행을 id 없이 되넣는다 → 운영 최대값 위의 새 번호를 받는다 (근거 §F)
insert into public.inv_ledger
  (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type,
   doc_type, doc_number, doc_task_id, line_ref, amount, source, raw, created_at)
select occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type,
       doc_type, doc_number, doc_task_id, line_ref, amount, source, raw, created_at
from reload_backup.ledger_ims order by id;

select source, count(*), min(id), max(id) from public.inv_ledger group by source order by source;
SQL

psql "$(cat ~/.asung-testdb-url)" --single-transaction -v ON_ERROR_STOP=1 \
  -f ~/reload-pre.sql -f ~/reload-17.sql -f ~/reload-post.sql > ~/reload.log 2>&1; echo "exit=$?"
tail -5 ~/reload.log
```
📌 `restart identity` 로 시퀀스가 1이 되지만 **덤프가 끝에서 `setval` 로 맞춰 준다**(1차 실행 확인). post 의 `setval` 은 그 위에 한 번 더 — 겹쳐도 무해하다.
📌 `cascade` 는 이 17개를 참조하는 외래키가 **0개**임을 확인하고 쓴다(2026-09-21 레포 grep: `references inv_ledger` 0 · A 갈래 16표 참조 0).
새 표가 이 17개를 참조하기 시작하면 `cascade` 가 **그 표를 함께 비운다** — 회차마다 grep 을 다시 한다.

⚠️ **post 의 15컬럼 목록은 `inv_ledger` 16컬럼 − `id` 다**(2026-09-21 기준 · `ADD COLUMN` 이력 0). 원장에 컬럼이 늘면 **이 문장이 조용히 빠뜨린다** —
`inv_ledger` 컬럼을 바꾸는 마이그레이션은 이 문장도 함께 고친다.
⬜ 대안: `insert into public.inv_ledger overriding user value select * from reload_backup.ledger_ims order by id;` —
`generated always` 식별자에 공급된 `id` 를 무시하고 시퀀스를 쓰므로 컬럼 수에 무관하다. **이번 차수에 채택하지 않았다.**
다음 회차에 `begin; … rollback;` 으로 확인한 뒤 바꾼다 — §O.

실측 2026-09-21: 1차(2단) `setval 8932566` · `INSERT 0 4` · `cin7 39,913` · `manual 1,606` · `ims 4`(id 8,932,567~570) ·
2차(단일판 · 이 절 그대로) **exit=0 · `setval 8947418` · `INSERT 0 4` · `cin7 39,996` · `manual 1,606` · `ims 4`(id 8,947,419~422)**.

---

## §F `inv_ledger.id` 를 왜 이렇게 다루나

운영 `max_id` 가 테스트보다 크다(2026-09-21: 8,932,566 대 5,425,297). 운영 행을 `id` 까지 그대로 넣으면 IMS 행과 번호가 겹쳐 **유니크 제약에 걸려 멈춘다.**
그래서 **운영 행은 `id` 를 보존**하고, **IMS 행은 `id` 없이** 넣어 운영 최대값 위의 새 번호를 받게 한다.

⭐ 운영 `id` 를 보존하는 이유: `inv_missing_lines.existing_ledger_id` 가 운영 원장 `id` 를 숫자로 들고 있다. 같이 넘어오므로 번호가 그대로여야 가리키는 곳이 맞다.
⭐ IMS 행의 `id` 가 바뀌어도 되는 이유(실측 2026-09-21): `inv_ledger.id` 를 가리키는 **외래키 0개** · 숫자로 들고 있는 컬럼은 `existing_ledger_id` 하나뿐이고
그 표는 Cin7 축 전용이라 **IMS 행을 가리킬 수 없다**(운영 `ims` 0행).
📌 `created_at` 을 그대로 옮기는 것은 IMS 사건의 기록 시각을 지키기 위해서다.

---

## §G `inv_config` — truncate 금지

⛔ **옛 절차의 `truncate inv_config;` 를 따르지 마라.** IMS 설정 2행이 사라지고 `po_create` 가 기준통화·계정과목을 못 찾아 발주 생성이 멈춘다.

`inv_config` 는 §D 덤프에 **없다**(17표 밖). 운영의 `baseline_snapshot_key` 와 값이 같은지만 확인한다:
```sql
-- [asung-WMS (운영)] 과 [Asung-IMS (테스트)] 양쪽에서
select key, value, updated_at from inv_config order by key;
```
다르면 **그 행만** 갱신한다 — `key` 기준 upsert. `delete` 후 `insert` 금지.
```sql
-- [Asung-IMS (테스트)] — 운영 값이 다를 때만
-- ⛔ 창 가드 — 이 문장이 멈추면 테스트(Asung-IMS) 창이 아니다. 아래를 돌리지 마라 (po_line 은 IMS 전용 표 · 20260916144201)
do $$ begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'po_line') then
    raise exception 'not Asung-IMS (test): po_line missing — this window is the production project';
  end if;
end $$;

insert into inv_config (key, value, note, updated_at)
values ('baseline_snapshot_key', '<운영 value>', '<운영 note>', '<운영 updated_at>')
on conflict (key) do update
  set value = excluded.value, note = excluded.note, updated_at = excluded.updated_at;
```
확인 — `po_create` 가 읽는 두 행이 살아 있는가:
```sql
-- [Asung-IMS (테스트)] — 기대 2행
select key, value from inv_config where key in ('base_currency','po_inventory_account_code');
```
실측 2026-09-21: 양쪽 `2026-08-20-initial` · `updated_at` 까지 일치 ⇒ 갱신 불필요 · IMS 2행 유지.
⭐ 기초선이 같다는 것은 **두 DB 의 잔고가 같은 출발점 위에 있다**는 뜻이다.

---

## §H 레이어 재생성

```sql
-- [Asung-IMS (테스트)] — 가드 포함 다섯 문장을 한 번에 돌린다
-- ⛔ 창 가드 — 이 문장이 멈추면 테스트(Asung-IMS) 창이 아니다. 아래를 돌리지 마라 (po_line 은 IMS 전용 표 · 20260916144201)
do $$ begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'po_line') then
    raise exception 'not Asung-IMS (test): po_line missing — this window is the production project';
  end if;
end $$;

select set_config('request.jwt.claims',
  (select jsonb_build_object('sub', auth_user_id, 'role', 'authenticated')::text
     from ims_staff where email = 'caleb@asung.ca'), true);

truncate inv_layer, inv_layer_consume, inv_layer_cost_add cascade;
select inv_layer_seed_baseline('2026-08-20-initial', false);
select jsonb_pretty(inv_layer_apply());
```
⚠️ **한 번에 돌린다** — `set_config` 의 `true` 는 트랜잭션 한정이라 나눠 돌리면 권한이 풀리고 `apply()` 가 「nothing was rebuilt」를 낸다.
⚠️ `seed_baseline(key, true)` 는 소진 기록이 있으면 거부한다(`refusing to replace baseline: … have consume rows`) — `truncate` 셋 먼저.
📌 `cascade` 가 안전한 근거(2026-09-21 레포 grep): `inv_layer` 를 참조하는 외래키는 셋이고 **전부 가족 안**이다 —
`inv_layer.parent_layer_id`(자기참조) · `inv_layer_cost_add.layer_id` · `inv_layer_consume.layer_id`.
⚠️ 새 표가 `inv_layer` 를 참조하기 시작하면 `cascade` 가 그 표를 **함께 비운다** — 회차마다 grep 을 다시 한다.
📌 `begin; … rollback;` 으로 먼저 봐도 반환은 읽힌다. 실측상 롤백판과 실행판의 반환이 **한 칸도 다르지 않았다**(재생성은 결정적이다).

**실측 2026-09-21 반환 — 다음 회차 비교 기준 (`20260921161933` 수정판 · 원장 `cin7 39,996` = 11:29 덤프 기준)**
```
short_events 0                 ← 수정 전 2   (✅ 20260921161933 — 같은 날 po_in 을 유입 맨 앞에 · 정본 ledger-design 16번)
consume_rows 31,039            ← 수정 전 31,037
transfer_layers_created 7,619  ← 수정 전 7,617
inv_layer 23,346
layers_created 1,762 · landed_rows 1,857 · freight_rows 316 · cost_unknown_layers 0
transfer_unknown_layers 259 · transfer_unknown_qty 2,559
credit_unknown_layers 1 (⏸ CR-00592 · 판매 창고 ≠ 반품 창고 · ledger-design 「⬜ 남은 것」) · freight_no_basis 2 (627.95)
processed_po_in · processed_sale_out · processed_transfer · elapsed_ms · landed/freight 금액 — 미기록 · 다음 회차에 채움
ims: receipts_posted 3 · layers_created 3 · over_posted 1 · over_layers 1
     charges_unvisited 1 (2,547.37) · skipped_by_event 여덟 키 전부 0
```
⚠️ **이 값은 원장 `cin7 39,996` 기준이다. 원장이 달라지면 값도 달라진다** — 아침(39,913)과 오전(39,996) 값을 섞어 읽고 「레이어만 다르다」고 없는 문제를 만든 것이
오늘 있었다(ledger-design 16번 「레이어 17 차이」). §J 의 규칙(시각과 함께)이 그래서 있다.

~~수정 전 기준값(09-21 오전 · `20260921161933` 이전 판 · 원장 `cin7 39,913`): elapsed_ms 13,560 · layers_created 1,762 · consume_rows 30,971 ·
transfer_layers_created 7,601 · transfer_unknown 259 / 2,559 · landed_rows 1,857 (13,807.94) · freight_rows 316 (807.64) · freight_no_basis 2 (627.95) ·
processed_po_in 1,766 · processed_sale_out 24,480 · processed_transfer 14,924 · cost_unknown_layers 0 · short_events 2 · credit_unknown_layers 1 · ims 블록 동일~~
⭐ `cost_unknown_layers 0` ← 09-20 에는 85 였다. 운영 `inv_cost` 3,619행이 오면서 닫혔다(ledger-design 「이식이 남긴 것」 ✅).
⭐ **`skipped_by_event` 여덟 키가 0 인 것이 IMS 가 온전하다는 증거다.** 0 이 아닌 키가 있으면 그 사건의 창구를 만들 때다.

실측 결과 표: ~~`inv_layer 23,327` · `consume 30,971`(09-21 오전 · 수정 전)~~ → **`inv_layer 23,346` · `consume 31,039`**(수정판) · `cost_add 2,173`(landed 1,857 + freight 316) · `po_line 3` · `:over 1`

---

## §I 검산

**① 원장 — 백업과 맞는가**
```sql
-- [Asung-IMS (테스트)]
select source, count(*) from inv_ledger group by source order by source;   -- ims = reload_backup.ledger_ims 행 수
select count(*) from inv_ledger l join reload_backup.ledger_ims b
  on (l.doc_number, l.line_ref, l.sku, l.warehouse, l.event_type) =
     (b.doc_number, b.line_ref, b.sku, b.warehouse, b.event_type)
 where l.source = 'ims';                                                     -- 기대 = ims 행 수
```

**② 레이어 ↔ 원장**
```sql
-- [Asung-IMS (테스트)]
with layer as (select sku, warehouse, sum(remaining_qty) as layer_qty
               from inv_layer_open group by sku, warehouse),
bal as (select sku, warehouse, sum(qty) as bal_qty
        from inv_balance group by sku, warehouse)
select coalesce(b.warehouse,l.warehouse) as warehouse,
       count(*) as rows,
       sum(coalesce(l.layer_qty,0) - coalesce(b.bal_qty,0)) as gap_sum,
       count(*) filter (where coalesce(b.bal_qty,0) < 0) as balance_negative
from bal b full join layer l using (sku, warehouse)
where coalesce(l.layer_qty,0) <> coalesce(b.bal_qty,0)
group by 1;
```

⚠️⚠️ **기대값은 「0」이 아니다.** 올바른 기대값:
- **실제 창고 두 곳(`Asung Trading Inc.` · `Asung - Edmonton`)이 0행**
- `IN_TRANSIT` 한 줄만 나오는 것이 정상 — **알려진 잔재**다

실측 2026-09-21: 비교 16,014칸 · 어긋남 259칸 · **전부 `IN_TRANSIT`**(gap_sum 2,559 · 음수 잔고 222칸) · 실제 창고 **0**

**왜 `IN_TRANSIT` 만 어긋나나**
`IN_TRANSIT` 은 실제 창고가 아니라 운송 중 물건이 머무는 가상 창고다. 기초선(08-20) 이전에 출발해 이후에 도착한 트랜스퍼는 원장에 **나가는 사건만** 있어
잔고가 음수가 된다. 원장은 음수를 허용하지만 레이어는 `inv_layer_qty_ck(qty > 0)` 때문에 없는 물건을 소진할 수 없어 0 에서 멈추므로, 그 차이가 그대로 gap 이 된다.
⇒ **기초선 가로지름**이고 재적재의 결함이 아니다(09-10 재복사 때도 같은 259칸 · +2,559 였다). 재기준선이 지운다.

⚠️ **조사 기록**: 이 259·2,559 가 `apply()` 반환의 `transfer_unknown_layers 259`·`transfer_unknown_qty 2,559` 와 값이 같아
대화 Claude 가 「`transfer/unknown` 레이어다」라고 단정했으나, 열어 보니 `has_unknown_layer 0` 이었다. **수가 같다는 것이 같은 대상이라는 뜻은 아니다.**
(결과적으로 같은 사건 집합이었으나 근거를 확인하기 전에 결론을 말했다.)
📌 반환값의 259 는 **만든 수**이고 `inv_layer_open` 의 82 는 **아직 안 팔린 수**다 — 같은 축이 아니다.

**③ 격리 — 테스트가 여전히 Cin7 미연결인가**
```sql
-- [Asung-IMS (테스트)] — 기대 0
select count(*) from cron.job;
```
재적재가 cron 을 만들지는 않지만, 옛 절차의 핵심 격리 조건이라 당일 목록에 둔다. Edge Function 도 배포 0 이어야 한다.

---

## §J 기대값을 적는 방식

⚠️ **기대값에는 「행 수를 센 시각」을 함께 적는다.**
실측 2026-09-21: 이른 시각에 센 운영 값과 10:46 덤프 사이에 cron 이 계속 돌아 `inv_collect_runs +40` · `inv_doc_state +7` 이 났다.
시각을 안 적으면 다음 회차에 이것을 보고 「어긋났다」고 판단한다.
⭐ 나머지 열넷이 안 변한 것이 오히려 정상의 증거다 — 회차 로그와 문서 커서만 늘고 원장·스냅샷·감지 표는 그대로였다.
📌 §D 검산의 `date` 줄이 이 시각이다.

---

## §K 이 절차가 지우는 것 — 알고 쓴다

**`inv_snapshot` 의 옛 키가 사라진다.**
`inv_compare_run()` 이 보존 14일로 오래된 키를 지운다(`20260824130759_inv_compare_run.sql:170` · `snapshot_key not like '%-initial'` · `-initial` 은 불가침).
테스트는 대조가 안 돌아 옛 키가 남아 있지만, 재적재로 운영 것을 부으면 사라진다.
📌 이 표는 `qty` 와 `value` 를 둘 다 담는다 — **날짜별 재고 평가액 이력**이다.
09-10 재복사 때 `2026-08-27-compare` 가 소멸한 것도 같은 이유다(스킬의 ⬜ 가 닫힌다).

**Caleb 판정 2026-09-21: 지운다.**
> "월말 평가액은 지금은 사라져도 괜찮아. 어차피 재고 평가액은 흐르는거니 말이야."

⇒ 08-31 월말 평가액(2,985,775.96)이 사라지는 것을 알고 내린 결정이다.
⬜ 월별 평가액 보존은 **컷오버 설계와 함께** 다룬다(§O) — 그때 `value` 의 출처가 Cin7 에서 IMS 레이어로 바뀌므로
(정의가 다르다 · 09-10 대조에서 절대합 차이가 순액의 18배) 출처를 구분할 장치가 함께 필요하다.

---

## §L 되돌리기 — 단계별

| 실패 지점 | 그때 테스트 상태 | 조치 |
|---|---|---|
| §C 백업 | 아무것도 안 바뀜 | 고치고 다시 |
| §D 덤프·검산 | 아무것도 안 바뀜 | 덤프만 다시. 검산이 어긋나면 **붓지 않는다** |
| §E `psql` 중 오류 | **자동 롤백** — 17표 전부 재적재 전 그대로 | `~/reload.log` 의 첫 ERROR 를 고치고 같은 명령 다시 |
| §E 성공 뒤 문제 발견 | A 16표·원장 cin7/manual = 운영 덤프 시점 · ims = 새 id | ims 행만: `truncate inv_ledger` 가 아니라 `delete … where source='ims'` 후 post 의 INSERT 재실행. cin7/manual 은 **재덤프**(§D 부터) |
| §G 갱신 실수 | `baseline_snapshot_key` 한 행 | `reload_backup.config_ims` 는 그 키를 안 담는다 — 운영 값을 다시 읽어 upsert |
| §H `apply()` 오류 | `set_config` 트랜잭션 안이라 **자동 롤백** · 레이어 셋은 truncate 전 그대로 | 메시지대로 고치고 네 문장 다시 |
| §H 성공 뒤 문제 발견 | 레이어 새것 | `truncate` 셋 → `insert into inv_layer overriding system value select * from reload_backup.layer` 등 셋 복사(세 표의 `id` 가 전부 `generated always as identity` 라 **`overriding system value` 필수** · FK 가 가족 안이라 id 보존 가능 · 순서 `layer` → `cost_add` → `consume`) → 그 뒤 세 시퀀스 `setval`. 다만 **원장이 이미 새것이면 옛 레이어는 원장과 맞지 않는다** — 대조용이지 정답이 아니다 |

⭐ A 갈래는 백업이 없다 — **정본이 운영**이라 언제든 재덤프로 복원된다. 그래서 `reload_backup` 에 넣지 않는다.
⚠️ 되돌릴 수 없는 것 하나: §K 의 `inv_snapshot` 옛 키. 백업하지 않는다는 결정이다.

---

## §M 범위 밖 — `wms_` 26개

⚠️ 승격을 택했으므로 **컷오버 때 결국 이사해야 한다.** 이 절차의 범위는 아니다. 여기 적어 두는 이유는 안 적으면 컷오버 날 잊기 때문이다.
```
wms_discrepancies · wms_drop_locations · wms_health_runs · wms_image_sync_runs
wms_order_lines · wms_orders · wms_pack_task_lines · wms_pack_tasks
wms_pallet_items · wms_pallets · wms_pick_task_lines · wms_pick_tasks
wms_polled_sales · wms_receipt_lines · wms_receipt_stage_events · wms_receipts
wms_refresh_requests · wms_reports · wms_rollback_archive · wms_rollback_log
wms_sku_bins · wms_sku_snapshot · wms_staff · wms_task_holds
wms_waves · wms_zone_sequence
```
(2026-09-21 레포 grep · `create table` 26건. 컷오버 설계 때 운영 `pg_class` 로 다시 센다.)
⬜ 이사 절차는 별도 항목(§O) — `wms_pallets` 순환 FK · `wms_staff` 와 `ims_staff` 의 관계 · `wms_rollback_archive` 보존 여부가 그때의 논점이다.

---

## §N 실행 경위 — 2026-09-21 (1차 2단 덤프 · 2차 단일판)

본문 단일판은 1차에서 배운 것을 반영한 것이고, 2차가 그것을 그대로 돌려 실증했다. 둘 다 **성공했다.**

### 1차 — 2단 덤프 (10:46 / 10:51)

1. §B ①~③ 통과(④ 없음 — 테스트 재적재).
2. §C 백업 `4 · 2 · 19,401 · 21,328 · 750`.
3. **16표 덤프** `~/reload-16.sql`(10:46 · 63M · COPY 16 · auth 0 · DDL 0 · replica).
4. **16표 복원** — `reload-truncate.sql`(16표 `restart identity cascade`) + `reload-16.sql` 을 `--single-transaction`.
5. **원장 덤프를 따로** — `inv_ledger` 만 남기고 전부 `-x`(제외 목록은 §D 방식) → `~/reload-ledger.sql` · COPY 1.
6. **원장 복원** — `reload-ledger-pre.sql`(`truncate inv_ledger restart identity`) + `reload-ledger.sql` + `reload-ledger-post.sql`(setval + ims 15컬럼 INSERT) 을 `--single-transaction`.
   결과 `setval 8932566` · `INSERT 0 4` · `cin7 39,913` · `manual 1,606` · `ims 4`(id 8,932,567~570).
7. §G 확인 — 갱신 불필요.
8. §H 재생성 — 반환은 §H 기준값 그대로.
9. §I ② — 실제 창고 0 · `IN_TRANSIT` 259칸.

⚠️ **왜 본문을 바꿨나** — 3 과 5 가 **다른 시각의 덤프**다. 그 사이 운영 cron 이 돌았으면 `inv_sync_state` 커서·`inv_doc_state`·`inv_cost` 는 10:46 시점,
원장은 그 뒤 시점이 된다. 테스트엔 cron 이 없어 그 어긋남이 영구히 남고, §B ③ 이 지키려던 「커서 = 지평선」이 깨진다.
컷오버 절차로는 안 된다. ⇒ 17표 한 덤프 · 한 트랜잭션(§D·§E).
📌 1차는 운영 원장이 커서와 어긋나도 테스트 용도엔 무해했다(다음 재적재가 덮는다). ~~컷오버 전 **단일판으로 한 번 리허설**한다 — ⬜.~~

### 2차 — 단일판 리허설 (11:29) ✅

✅ **단일판 리허설 완료 (2026-09-21 · 2차 실행 · 본문 §B~§I 그대로)**
```
§C 백업 4 · 2 · 23,327 · 30,971 · 2,173
§B ③ 여덟 축 정상 · transfer 는 TR-04495 정지(TR-04496 ORDERED 블로킹 · 기지)
§D 덤프 11:29:48 EDT · 107M · COPY 17 · auth 0 · DDL 0 · replica 확인 · setval 14
§E 복원 exit=0 · setval 8,947,418 · INSERT 0 4
   → cin7 39,996 · manual 1,606 · ims 4(id 8,947,419~422)
§H 재생성 elapsed_ms 14,250 · IMS 블록 전부 동일
§I 검산 실제 창고 0 · IN_TRANSIT 259 · gap 2,559
```
⭐ **얻은 것**: 17표 한 덤프로 커서·문서 상태·원가·원장이 **같은 시점**(11:29:48)이 됐다. 그리고 2단판(아침)과 단일판(오전)이 IMS 블록·`IN_TRANSIT` 잔재까지
같은 결과를 냈다. 2차의 §H 반환은 `20260921161933` **이전 판**(`short_events 2`)이고, 수정판 적용 후 기준값은 §H 에 있다.

---

## §O 남은 것 — 한 자리에 모은다

컷오버 당일 펴 볼 문서라 열린 항목을 흩어 두지 않는다. 본문엔 한 줄과 「§O」 포인터만 있다.

- ⬜ **관문 ④ cron 정지 명령 목록** — `supabase/ops/cron.sql` 기준으로 `cron.unschedule` 목록을 만든다(§B ④). 컷오버 설계에서.
- ⬜ **`wms_` 26개 이사 절차** — 논점: `wms_pallets` 순환 FK · `wms_staff` 와 `ims_staff` 의 관계 · `wms_rollback_archive` 보존 여부(§M).
- ⬜ **`overriding user value` 전환** — post 의 15컬럼 INSERT 를 컬럼 수에 무관한 문장으로. 다음 회차 `begin; … rollback;` 확인 뒤(§E).
- ⬜ **운영 일괄 배포 판단** — 운영 Remote 빈 줄 **53**(`20260911144606`~`20260921161933` · 2026-09-21 실측). 전부 올리면 IMS 모듈 전체가 운영 DB 에 빈 표로 선다.
  **Caleb 판정 2026-09-21: 계속 보류**(`po_in` 순서 수정 `20260921161933` 도 IMS 모듈 53개와 함께 올라가므로 운영 배포 보류).
  ⚠️ 올리면 §B ② 의 기준값(운영 53 · 테스트 0)이 바뀐다 — 그때 이 문서를 함께 고친다.
- ⬜ **월별 평가액 보존** — 컷오버 설계와 함께. `value` 의 출처가 Cin7 → IMS 레이어로 바뀌므로 출처 구분 장치가 필요(§K).
- ✅ ~~단일판 리허설 한 번(컷오버 전)~~ — 2026-09-21 2차 실행(§N).
