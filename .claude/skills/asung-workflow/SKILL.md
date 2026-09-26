---
name: asung-workflow
description: >
  Asung Trading(Caleb)과 함께 IMS·WMS 를 짓는 **일하는 방식**. 설계·코드 지식이 아니라
  「어떻게 주고받는가」다 — 무엇을 만들거나 고치기 **전에** 먼저 읽으세요.
  "지시서", "프롬프트 써줘", "Claude Code", "클로드 코드에 줄", "검토 후 이의 제기",
  "인수인계", "인계 문서", "핸드오버", "스킬 만들어", "스킬 갱신", "SKILL.md", "description 한도",
  "마이그레이션 만들어", "화면 파일", "HTML 써줘", "파일 옮기기", "cp 명령",
  "psql", "SQL 도구", "set role", "권한 검증", "배포", "커밋", "푸시",
  "티키타카", "한 번에 하나씩", "정본", "po-module.md", "차수", "회신 평가"
  가 나오면 추측하지 말고 이 스킬을 먼저 확인하세요.
  ⚠️SQL 도구는 문장마다 연결이 끊긴다 — 권한 검증은 psql heredoc 으로만,
  ⚠️Claude Code 가 만들지 않은 파일을 만들었다고 보고한 적이 있다 — ls -l 출력을 그대로 받아라,
  ⚠️정본은 3,300행 — 지시서에 「전문 금지 · 이 절만」을 반드시 쓴다,
  ⚠️화면 파일은 대화 Claude 가 통째로 쓰고 Claude Code 는 안 고친다,
  ⚠️중단·휴식·마무리를 제안하지 마라 — 멈추는 결정은 Caleb 이 한다,
  ⚠️함수를 고치기 전에 그 함수의 마지막 정의를 grep 으로 찾아라.
---

# Asung — 일하는 방식

⭐ 이 스킬은 **방법**만 담는다. 무엇을 짓는가는 정본과 도메인 스킬에 있다.
관련: `asung-po`(PO 모듈) · `asung-wms` · `asung-inv-ledger` · `cin7-api` · `asung-ops`.

---

## 1. 누가 무엇을 하나

```
대화 Claude   설계 판단 · ⭐ 화면 파일(HTML)을 **통째로** 쓴다 · Claude Code 용 지시서를 **파일로** 쓴다  → 모델 · 대화에만 있는 것은 §3 뼈대 맨 위(2026-09-26)
Claude Code   레포 파일 수정(마이그레이션 · 설계 문서 · 공통 js/css · Edge Function)
              ⚠️ 반드시 「검토 후 이의 제기」 먼저 — 「그대로 만들어라」가 아니다
              ⚠️ 화면 html 은 안 고친다(지시서가 명시적으로 허락할 때만 · 예: <style> 블록만)
              ⭐ [2026-09-24 Caleb] **테스트 DB 에서 「시험 적용 + 검증」을 스스로 돌린다** — begin → 마이그레이션 읽기 → 검증 → rollback 하나(§4 「시험 적용 장치」) · 통과할 때까지 고치고 **횟수·걸린 것·고친 것**을 보고한다
Caleb         git · 배포 · **실제 적용·repair** · 운영 SQL · 파일 옮기기 · ⭐ **눈으로 보는 것은 전부 Caleb** · Claude Code 의 검증 보고를 대화 Claude 와 함께 확인 → 실제 적용 + 확인 검증 한 번 + 커밋
              ⚠️ 개발자가 아닌 실무 전문가다 — 판단의 근거를 말로 설명한다
```

⚠️ **Co-Authored-By 커밋 금지** · git push 는 언제나 Caleb.

---

## 2. ⭐⭐ 티키타카 — 한 번에 하나씩

```
⭐ 선택지·항목·질문을 **한꺼번에 주지 마라.** 하나 정하고 다음으로 간다
⚠️⚠️ **중단·휴식·마무리·새 세션을 제안하지 마라** — 멈추거나 이어가는 결정은 Caleb 이 한다
⭐ 제안할 때는 **안과 대가를 함께.** 「제 생각은 A 입니다」까지 말하되 고르는 것은 Caleb
⚠️ [Caleb] 회신 평가를 길게 늘어놓지 마라 — **할 일을 먼저** 주고 평가는 짧게
⭐ 확인하지 않은 것은 「짐작」이라고 쓴다. 안 본 것은 「안 봤다」
⚠️ 「못 봤다」와 「없다」를 구분한다 · 원인을 모르면 상쇄하지 않는다 · 모르면 비워 둔다
⭐ [2026-09-24 Caleb] **왕복을 줄인다 — 검증은 Claude Code 가 돌리고 결과를 함께 본다.** 「지금방식은 … 왕복이 많아져서 시간이 많이 걸리고 있어. 검증은 꼭 필요하고 확실하게 했으면 좋겠어. 클로드 코드가 검증까지 돌리고 그 결과물을 나와같이 니가 확인해 주는 방식은 어때?」
   ⇒ 검증 파일을 만들면 **곧바로 테스트 DB 에서 시험 적용 + 검증을 돌린다**(§4) · 보고는 요약이 아니라 **원문**(exit · OK 수 · MISMATCH 줄 · 끝부분) + 재발행 diff + 토크나이저 + ⭐ **통과까지 몇 번 돌렸고 무엇이 걸려 어떻게 고쳤는지**(예상값을 바꿨으면 왜 DB 가 맞다고 보는지) · 대화 Claude 가 확인 → Caleb 이 실제 적용 + 확인 검증 한 번 + 커밋
```

---

## 3. ⭐ 지시서 쓰는 법 — `~/asung/prompts/<이름>.md`

### 반드시 들어가는 뼈대
```
맨 위   모델 — Opus(사실을 모으는 조사 · 정해 준 대로 옮기는 문서 · 스킬) · 「⚠️ Fable 필수」 + 이유 한 줄(판단이 든 조사 · 만들기 · 검증) · 애매하면 Fable
        📌 대화에만 있는 것 — 정본 · 레포에 아직 없는 판정 · 실측 · 결정을 **내용 그대로**(가리키지 않는다) · 없으면 「없음」
§0 「⭐ 먼저 — 검토하고 이견을 내라」
   · 「그대로 만들어라가 아니다 — 틀린 곳·빠진 곳·다르게 하는 편이 나은 곳을 먼저 말하라」
   · ⚠️ SQL 을 돌리지 마라(실행은 Caleb) · git 을 건드리지 마라 · 화면 파일을 고치지 마라
   · 확인하지 않은 것은 「짐작」이라고 쓴다
   · ⭐⭐ **읽을 파일 목록 — ⚠️ 전문 금지 · 이 절만**
     (정본이 3,300행이 넘는다. 전문을 읽히면 토큰만 태우고 정작 볼 것을 안 본다)
본문   실측에는 **출처와 날짜**, 판단에는 **근거**. 기각된 안은 왜 기각인지까지 적는다
⬜     「네가 판단해 말하라」 — **안과 이유를 붙여서.** 대화 Claude 의 안도 함께 적으면 대조가 된다
조사   무엇을 어떤 명령으로 확인할지. SQL 은 문장까지 적고 「Caleb 에게 요청하라」
예상값 Caleb 이 실행해 대조한다 · ⚠️ **psql heredoc 으로** 적어라(§5)
끝     git 을 건드리지 마라 · git diff --stat 과 행 수만 보여주고 멈춰라 · 이견에 번호를 붙여라
       정본·CHECKLIST·스킬 갱신은 **말만** 한다
```

### ⭐⭐ 빠뜨리면 사고가 나는 넷
```
① **같은 모양을 grep 으로 훑게 하라**
   「이 문구가 몇 곳에 있는지 세어 보고하라」를 넣는다.
   한 곳만 고치면 문서·코드에 옛 뜻과 새 뜻이 함께 남는다 — 매번 한둘이 더 나온다
   [실사고] 「담을 자리가 셋인 줄 알았는데 넷」 · auth_all 이 안 본 절 다섯 곳에 더 있었다

② **파일을 만들었다는 보고를 믿지 마라**
   [실사고 2026-09-17] Claude Code 가 **만들지 않은 파일**의 행 수·바이트·diff 결과를 사실로 보고했다
   ⇒ 「ls -l · wc -l 출력을 **그대로** 붙여라 · 요약하지 마라」를 지시서에 넣는다
   [실사고 2026-09-26] 「고쳤다」며 grep 원문처럼 붙인 줄이 지어낸 것이었다(명령을 안 돌렸다) — 다음 어서션이 옛 줄을 보고 멈춰 드러났다
   ⇒ 고쳤다는 보고는 **고치기 전후의 ls -l(바이트 · 시각)** 을 함께 · 시각이 안 바뀌었으면 고치지 않은 것이다

③ **함수를 다시 낼 때는 원본과 diff 로 대조하게 하라**
   더한 줄(>)만 있고 바뀐·빠진 줄(<)이 없어야 한다
   [실사고] 옮기다 비분리 공백 정규식을 깨뜨린 것을 그 대조가 잡았다(SKU 붙여넣기가 조용히 틀어질 자리였다)

④ **대화에만 있는 것을 적시하라** [Caleb 2026-09-26]
   Claude Code 는 대화를 못 읽는다 — 정본에 없는 판정을 「§24 판정 10」처럼 가리키면 없는 것을 가리킨 셈이다
   [실사고 2026-09-26] 직원 조사 프롬프트가 정본에 없는 판정 10 을 근거로 적었다 — Claude Code 가 첫머리에 짚었다
   ⇒ 쌓이면 문서 차수를 먼저 돌린다
```

### 크기
```
⭐ 한 차수는 **400~900행**. 넘칠 것 같으면 「나누는 안과 경계를 제안하라」를 넣는다
   나누는 것은 부끄러운 일이 아니다 — 크면 검증이 안 된다
⚠️ 조사만 시키는 차수도 있다 — 「아무것도 만들지 마라 · 회신으로만 답하라」
```

---

## 4. ⚠️ 함수·마이그레이션을 건드리기 전에

```
⚠️⚠️ **그 함수의 마지막 정의가 어디인지 먼저 찾는다**
   grep -rn 'function public\.<이름>' supabase/migrations | tail -3
   [실사고] po_invoice_create 지시서를 옛 파일 기준으로 썼다 — 그대로 갔으면 크레딧 자동 채번이 사라졌다

⚠️ **인자를 늘려 시그니처가 바뀌면** create or replace 가 덮지 못한다(같은 이름 함수가 둘이 된다)
   ⇒ drop function if exists … 뒤 create. 본문만 바뀌면 replace 로 되고 grant·comment 도 남는다

⚠️ **적용된 마이그레이션은 고치지 않는다.** 새 파일을 만든다
⚠️ 적용된 파일을 **두 번 돌리지 마라** — create 로 쓴 새 객체가 전부 걸린다.
   파일이 바뀌어도 **DB 를 다시 맞춰야 하는지부터** 판단한다(주석만 바뀌었으면 재적용하지 않는다)

⚠️ 적용 뒤에는 **실물로 확인한다** — 함수 개수·정책 수·반환 모양(「Success」 한 줄은 적용 증거가 아니다 · §11)

⭐ **마이그레이션 파일 시각은 UTC** — `date -u +%Y%m%d%H%M%S` (2026-09-22: 토론토 밤에 로컬 시각으로 지을 뻔했다 · UTC 로는 다음 날)
⭐⭐ [2026-09-24 Caleb] **Claude Code 가 돌려도 되는 것 = 테스트 DB(`~/.asung-testdb-url`)에서 「시험 적용 + 검증」 하나** — 한 트랜잭션: begin → 마이그레이션 파일 읽기 → 검증 → rollback → 번호 시퀀스 되돌리기(오더·인보이스 0 일 때만 setval)
   ⚠️ 돌리기 전에: 검증 파일에 `commit;` 이 없고 `rollback;` 으로 끝나는지 `grep -nE '^(begin|commit|rollback);'` · 마이그레이션에 begin/commit 없음 · 주소는 `$(cat ~/.asung-testdb-url)` 만(운영 주소·`--linked`·SUPABASE_DB_URL 은 만들지도 않는다 · 메모리 no-direct-prod-requests)
   ⚠️ 실제 적용(`-1 -f`) · `migration repair` · 커밋 · 푸시는 여전히 Caleb — Claude Code 의 실행은 **되돌아가는 것만**
   ⭐ 검증 파일의 틀(시험 적용 장치 — psql 변수 `mig` 로 파일 경로를 받아 begin 뒤에 읽는다 · Caleb 의 확인 실행(이미 적용된 DB)은 `-v mig` 없이 → 건너뜀):
     -- 머리: 시퀀스 현재값은 있을 때만 읽는다(시험 적용이 시퀀스를 만드는 차수도 있다)
     select coalesce((select last_value from pg_sequences where schemaname = 'public' and sequencename = 'so_number_seq'), 0) as so_seq_last, … \gset
     begin;
     \if :{?mig}
     \echo '── 시험 적용(rollback 됨):' :mig
     \i :mig
     \endif
     create function pg_temp.chk(…) …            -- 도우미는 시험 적용 뒤·첫 호출 앞
     … 검증 절 …
     rollback;
     select setval(to_regclass('public.so_number_seq'), :so_seq_last, :'so_seq_called'::boolean) where not exists (select 1 from public.so);   -- to_regclass: 시험 적용이 만든 시퀀스는 rollback 으로 사라져 있다
     실행: Claude Code  psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<파일>.sql -f <검증>.sql 2>&1 | tee /tmp/<이름>.out
           Caleb(확인)  같은 명령에서 -v mig=… 만 뺀다 · 기대 OK 수는 검증 파일 머리에
   ⭐ 기대값은 손으로 적지 말고 **파일 안에서 앞 절의 입력으로 계산**한다(단가·수량을 psql 변수로 두고 합계·세금은 so_detail/so_tax_preview 의 반환을 \gset 으로 받아 비교 · 잔액은 「앞 절 끝 잔액 ± 이 절의 입력」을 SQL 식으로) · 순서 대신 **집합·합**으로 판정(2026-09-24 T6i)
⭐ **적용은 `psql -v ON_ERROR_STOP=1 -1 -f <파일>`**(Caleb) — 한 트랜잭션 · 도중 실패 시 전부 되돌아간다 · 파일에 트랜잭션 begin/commit 이 없는지 먼저 `grep -nE '^(begin|commit);'`(세미콜론까지)
   ⚠️ `^\s*(begin|commit)\b` 로 세면 함수 본문의 plpgsql `begin` 이 걸린다 — 2026-09-23 `20260923154749_price_tier.sql`(트리거 함수 하나)이 첫 사례
   `&& supabase migration repair --status applied <버전> --db-url …` 로 잇는다(적용이 실패하면 이력도 안 적힌다)
⭐ 표를 세우는 차수의 순서 — 프로브 → 판정 → 마이그레이션 → 적재 dryRun → Apply → Verify → SQL 눈 확인 (2026-09-22 손님 적재가 이 순서로 하루에 섰다)
⭐ **날짜 기본값·비교는 `ims_today()`(토론토)** — `current_date` 는 UTC 라 토론토 저녁 8시(겨울 7시) 뒤 내일이다(2026-09-23 · so.order_date · 세일 기간 · 백오더 만료 같은 뿌리 · PO 일곱 · 화면 다섯 ✅ 2026-09-23 · po-module §14)
⭐ **화면의 날짜 기본값은 `torontoToday()`** — `new Date().toISOString().slice(0,10)` 은 UTC 날짜라 금지(2026-09-23 asung-ims 다섯 곳 고침) · 서버 비교(received_on_in_future 류)가 걸린 자리는 **화면 먼저 배포**(반대면 저녁마다 경고)
⚠️ **psql 백슬래시 명령(`\gset` · `\if` · `\echo` …) 줄 끝에 `-- 주석`을 두지 마라** — 인자로 읽는다(`invalid variable name: "--pb"` · 2026-09-23) · 주석은 윗줄로 · 검사 `grep -nE '^\s*\\[a-z]+.*--|\\gset.*--'` 0줄
⚠️ **한 트랜잭션 안에서는 now() 가 전부 같다** — 시각으로 「손댐」을 판정하는 시험은 `updated_at` 을 명시로 뒤로 적는다(`session_replication_role = replica` 로 ims_touch 를 비껴서 · 2026-09-23 so_unconfirm) · 설계도 시각에만 기대지 마라(표시·사슬 먼저)
⚠️ **invoker 창구가 revoke 된 속 함수를 부르면 직원에게만 42501** — postgres 로 `\timing` 을 재면 안 보인다 · 권한이 걸린 시험은 **가짜 직원 신원**(set role authenticated + claims)으로(2026-09-23 so_available → so_available_many)
⚠️ **시험 자료를 뷰 전체에서 고르지 마라** — 제품마다 `ims_inv_balance` 를 다시 계산해 statement timeout 2분(2026-09-23) · 후보를 싸게 좁힌 뒤(활성·가격·sku 순 300) 한 문장(`so_available_many`)으로 · timeout 을 늘려 덮지 마라 · 임시 표는 authenticated 구간에서 못 읽는다(`\gset` 으로 받아 둔다)
⚠️ **CHECK 를 넓힐 때 함수 본문의 같은 값 목록도 훑어라** — [실사고 2026-09-24 ③a′] so_split_reason_ck 만 다섯으로 넓혔는데 so_split 본문의 `p_reason not in (…)` 목록이 넷이라 pick_short 가 거부됐다 ⇒ 어휘를 늘리는 차수는 `grep -rn "'값1','값2'"` 로 제약·함수 본문을 함께 세고 마지막 정의를 재발행한다
⚠️ **stable 함수는 임시 표를 못 쓴다**(INSERT is not allowed in a non-volatile function) — 읽기 창구에 담아 두기가 필요하면 CTE·배열 변수로(2026-09-24 so_backorder_list)
⚠️ **plpgsql 의 record 변수 이름을 조회 별칭으로 쓰지 마라** — `declare r record` 뒤 `from so_reserve r` 은 `r.col` 이 변수로 풀려 `record "r" is not assigned yet`(2026-09-24 ③b 검증 · so_backorder_proceed 재발행에서도 피했다) ⇒ 별칭은 `res`·`x` 처럼 변수와 다른 이름 · ⚠️ **두 번째 실사고 2026-09-25 ④b**(so_merge · `declare r record` + `from so_reserve r` — 두 회차에 걸쳐 한 곳씩 나왔다) ⇒ 함수를 다 쓴 뒤 **`declare` 의 이름마다 그 함수 본문에서 같은 별칭을 grep** 한다
⚠️ **상관 서브쿼리의 칸은 별칭으로 한정하라** — `(select email from ims_staff where id = updated_by)` 의 `updated_by` 는 안쪽 표에 같은 칸이 있으면 **그쪽으로 풀린다**(2026-09-24 inv_config.updated_by 가 빈 값으로 보였다 · 트리거는 채웠었다) ⇒ `c.updated_by`
⚠️ **한 트랜잭션 안에서는 순서를 비교하지 마라** — created_at 이 전부 같다 · 목록을 비교할 때는 **정렬해서**(string_agg … order by 키) 비교한다(2026-09-24 ③b S6 예약 목록)
⚠️ **cron.sql 은 운영 기록이다** — 테스트 DB 에만 등록한 잡은 `[테스트 · Asung-IMS] jobid N` 을 절 머리에 밝히고 「운영에는 등록하지 마라(함수가 없다) · 전환 때 함께」를 적는다(2026-09-24 so-backorder-sweep · 테스트 jobid 1 ≠ 운영 1 wms-poll-orders)
⚠️ **검증 do 블록의 변수는 전부 `v_` 접두 · 임시 표의 칸 이름과 겹치지 않게** — 같은 날 두 번(record 변수 `r` = 별칭 `r` · 변수 `v` = `t_ids.v` → 42702 「column reference is ambiguous」 · 2026-09-24 세금 ② v1) · FROM 이 없는 insert … values 는 안 걸리지만 규칙은 같다 · 블록마다 「선언 변수 ∩ 읽는 표의 칸」을 훑는다
⚠️ **`format('%s', boolean)` 은 `t`/`f` 를 낸다** — 출력 함수를 쓴다(`boolean::text` 는 `true`/`false`) · 기대 문자열이 `manual=false` 면 `::text` 로 캐스트해 넣는다(2026-09-24 세금 ② v2 — 여덟 chk 가 글자만 같은 MISMATCH · DB 는 맞았다)
⚠️ **CHECK 시험은 한 번에 제약 하나만 어기는 자료로 · `get stacked diagnostics … = constraint_name` 으로 이름까지 판정** — 두 제약을 함께 어기면 Postgres 가 하나만 보고하고 나머지는 한 번도 안 돈다(2026-09-24 세금 ② 「tax_rule_id 만 null」이 pair_ck 대신 manual_ck 에 걸렸는데 OK 로 읽었다)
⚠️ **bash 에서 `grep $'\x00'` 은 빈 글자가 된다** — 널 바이트 검사는 `file <파일>` 또는 `grep -cP '\x00'` 로(2026-09-24 · Caleb 실측)
⚠️ **RAISE 의 글자 % 는 %% — 형식 문자열의 % 자리 수와 넘기는 값 수를 주기 전에 센다** — 「50% COD & 50% N30」 같은 문구가 자리표시로 읽혀 do 블록 전체가 「too few parameters specified for RAISE」로 안 돈다(2026-09-24 ⓑ1 검증 v1 · 204행) ⇒ 토크나이저 검사에 RAISE 항목(`$$` 본문의 raise 마다 %(%% 제외) 수 = 값 수)을 더했다 — 마이그레이션(적용이 통과했으니 0)과 검증 파일 둘 다 돌린다
⚠️ **BEFORE 트리거(문지기)는 CHECK 보다 먼저 막는다** — CHECK 만 시험하려면 `session_replication_role = replica` 로 문지기를 끄고, 그때도 다른 CHECK(closed_at 짝 등)를 함께 어기지 않는 자료로(2026-09-24 ⓑ2 T8a · invoiced 로 바꾸며 closed_at 을 남겨 so_closed_at_ck 가 먼저 걸렸다)
⚠️ **번호 시퀀스는 pg_sequences 가 아니라 시퀀스를 직접 읽는다** — pg_sequences.last_value 는 미리 당긴 값을 보이고 is_called 를 `last_value is not null` 로 짐작하면 틀린다 ⇒ `select last_value, is_called from public.<seq>` · 시험 적용이 만드는 시퀀스만 `to_regclass` + `\if` 로 가른다(2026-09-25 ⓒ1 2차 — setval 이 25001·60001 로 밀렸고 Claude Code 가 기준값으로 되돌렸다 · 전후 원문을 보고에)
   ⭐ **죽은 회차가 번호를 당겼으면 되돌리기 전후 원문(last_value · is_called)을 그대로 보고에 붙인다** — 요약하지 마라(2026-09-25 ④a3 · ④b 부터 규칙 · ④a2 보고에는 빠져 있었다) · 되돌리기는 `where not exists (select 1 from public.so)` 처럼 **표가 비어 있을 때만**
⚠️ **시험 적용이 만든 객체를 참조하는 문장은 `\if :{?mig}` 로 가른다** — rollback 뒤 그 표·시퀀스는 없어 파싱에서 죽는다(`relation "public.so_credit" does not exist` · 2026-09-25 ⓒ1 2차 끝 setval) · 확인 실행(-v mig 없음)에서는 반대로 있어야 한다 — 두 갈래를 다 적는다
⚠️ **authenticated 구간(`set local role`)에서 임시 표에 쓰지 마라** — 42501(권한이 없다) · 결과는 `set_config('app.out', v_j::text, true)` 로 내보내고 `reset role` 뒤에 임시 표로 옮긴다(2026-09-25 ④a2 1차)
⚠️ **`\gset` 별칭은 소문자로 접힌다** — 대문자가 섞인 이름(`recv_before_P2`)은 변수가 서지 않아 `syntax error at or near ":"` 가 난다 ⇒ 별칭은 전부 소문자(2026-09-25 ④a2 2차)
⚠️ **출고 전 계획은 출고 전에 담아라** — 출고 뒤에 다시 계산하면 잔고가 바뀌어 다른 값이 나온다(예상이 아니라 계산 시점이 틀린 것 · 2026-09-25 ④a2 4차)
⚠️ **검증의 도우미 초안은 시나리오와 다른 SKU 로** — 같은 SKU 를 쓰면 뒤 오더의 확정이 앞 오더의 백오더 형제를 이어받아 기대가 흔들린다(2026-09-25 ④b 3차 · 재고 넉넉한 SKU 하나를 도우미 전용으로)
⚠️ **재생성(`inv_layer_apply()`) 시험은 `receiving` + `purchasing` 열쇠를 둘 다 가진 로그인으로** — 하나만 있으면 「nothing was rebuilt」로 멈춘다(2026-09-25 ④a3 2차)
⭐ **Caleb 에게 줄 적용 명령은 적용과 `migration repair` 를 `&&` 로 잇는다** — 따로 두 줄로 주면 적용이 실패해도 repair 가 돌아 이력만 「적용됨」이 된다
⚠️ **훑기가 지시 목록 밖의 함수를 찾으면 재발행하고 이유를 보고한다** — ⓒ2 so_payment_void(환불 취소가 크레딧 몫을 함께 풀지 않으면 크레딧이 사라진 채 돈만 돌아온다) · so_invoice_remaining · so_detail 이 목록 밖이었다(2026-09-25) · 「지시서에 없어서 안 고쳤다」는 답이 아니다
⭐ **훑기는 모든 꼴로** — `p.id` · `v_p.id` · `v_c.id` · `c.id` · `credit_id = …` 처럼 변수·별칭 꼴을 전부 · **마이그레이션 전수 + DB 함수·뷰 본문 둘 다**(2026-09-25 so-pay-read-1 이 `p.id` 꼴만 찾아 `v_p.id` 꼴 셋 — alloc_add · attach · detach — 을 놓쳤다 · 다음 차수 첫 회신이 찾았다 · 정본 §22)
⭐ **화면을 쓰기 전에 커밋된 마이그레이션을 raw 로 받아 칸 이름을 읽는다** — 보고서 요약으로 짐작하지 않는다(대화 Claude 규칙 · 2026-09-25)
📌 **화면 한 차수** = 대화 Claude 가 화면 파일 통째로(검사 넷: 단추↔처리 · id 실재 · `node --check` · CSS 클래스 실재) + Claude Code 가 `ims-auth.js` items · CHECKLIST · 한 커밋(asung-ims · 정본 §23)
⭐ ⑤ 부터의 마이그레이션은 첫 문장이 `supabase/ops/guard-test-only.sql` 의 바이트 복사 · 검증 G0 은 **임시 파일에 첫 블록을 써서 diff**(psql `\!` 는 /bin/sh = dash 로 돈다 · `diff <(…)` 는 bash 문법이라 죽는다 · 2026-09-26 ⑤-1) · `\!` 에 psql 변수는 안 들어간다 — 경로는 환경변수로
⚠️ `\gset` 으로 받은 boolean 은 t/f 다 — 글자로 비교하지 말고 `:'x'::boolean` 으로
```

---

## 5. ⚠️⚠️ SQL 을 확인할 때 — 이 프로젝트의 함정

```
⚠️⚠️ **SQL 도구는 문장마다 연결이 끊긴다** [2026-09-17 실측]
   set role · set_config 가 다음 문장에 안 남아 결과가 **전부 거짓**이었다
⇒ ⭐ 권한·세션이 걸린 검증은 **터미널에서 psql heredoc 한 덩어리**로:

psql "$(cat ~/.asung-testdb-url)" -P pager=off <<'EOF'
set role authenticated;
select set_config('request.jwt.claims','{"sub":"<auth_user_id>","role":"authenticated"}',false);
<확인할 문장들>
reset role;
EOF

⚠️ `do $$ … $$` 안에서는 psql 변수(:'x')가 치환되지 않는다
⚠️ 예외가 나면 트랜잭션이 abort 되어 뒤 문장이 전부 실패한다
   ⇒ 호출마다 따로 돌리거나 do … exception when others then raise notice '%', sqlerrm; end 로 감싼다
⚠️ 여러 줄 SQL 은 도구가 `limit 100` 을 엉뚱한 자리에 붙인다 — **한 줄로 붙여서** 준다
⚠️ P0001 은 「에러」가 아니라 **함수가 일부러 막은 것**이다. 문장이 그대로 사람이 읽을 말이다
⚠️ 자리표시자(<id> 같은 것)를 남긴 채 주지 마라 — 그대로 실행된다 · [실사고 2026-09-24] 대화 Claude 가 자리표시자를 남긴 명령을 **다시** 줬다 — 주기 전에 `<`·`…` 를 grep 한다
⚠️⚠️ **쓰기 창구(volatile 함수)를 FROM 의 LATERAL 에서 부르지 마라** — [실사고 2026-09-24 ③a 검증 v1] `from t_so s, lateral so_confirm(s.so_id) r` 이 같은 오더를 두 번 불렀다(「not a draft」 · 재평가 경로는 짐작) ⇒ do 블록에서 한 번씩 부르고 반환을 임시 표(t_out)에 담아 뒤 SELECT 가 읽는다
⚠️ **검증의 확인은 값만 찍지 말고 판정으로** — 「FAIL」 한 단어 금지 · `MISMATCH (<시험>): expected … · actual …`(sqlerrm 포함) · 통과는 OK · 표시 SELECT 옆에 pg_temp.chk(tag, 조건, format(...)) 도우미를 붙인다 · ⚠️ **도우미는 BEGIN 바로 뒤에**(첫 호출보다 앞 · 2026-09-24 두 파일이 정의 전에 불러 첫머리에서 멈췼다) · authenticated 구간(`set local role`)에서는 pg_temp 를 부르지 말고 do 블록으로
⚠️ 시간은 못 바꾼다 — 만료류는 order_date 를 과거로 만들어 시험한다 · `session_replication_role = replica` 는 문지기·touch 를 함께 끈다(packed 만들기 등 · 트랜잭션 안에서만)
⚠️ **검증 파일은 주기 전에 괄호·따옴표·`$$` 를 센다**(토크나이저 · 문장마다 괄호 0 · 끝 상태 code) — 닫는 괄호 하나가 빠지면 psql 은 파일 끝에서 「syntax error at or near ;」만 말하고 **그 앞 절이 전부 안 돈다**(2026-09-24 ⓐ2 v1 · 9)·10)·rollback·setval 이 안 돌았다)
⚠️ **「줄마다 반올림」 예시는 줄 수를 함께** — 같은 30.15 가 한 줄이면 3.92 · 세 줄이면 3.93(2026-09-24 ⓐ1 v1 은 줄 하나를 3.93 으로 적어 틀렸다)
⚠️ **출력을 grep 으로 걸러 볼 때는 모든 절 번호를 넣거나 OK 수를 세라** — 절을 빼고 거르면 「안 돈 것」이 「통과」로 보인다(2026-09-24 대화 Claude 가 9·10 을 빼고 걸러 안 돈 것을 못 봤다)
⚠️ **시험 예상은 앞 절이 남긴 상태를 따라가라** — 6) 에서 떼고 취소한 손 결제가 일반 잔액이 되어 뒤 절의 재발행 때 자동으로 쓰였는데 예상이 그것을 빠뜨렸다(2026-09-24 ⓑ2 T6i · DB 가 맞았다) ⇒ 절마다 「이 절이 끝난 뒤 잔액·상태」를 한 줄 적고 다음 절 예상은 그 줄에서 시작한다
⚠️ **한 트랜잭션 안의 같은 날 결제는 순서가 id 로 갈린다** — paid_on·created_at 이 같아 `order by paid_on, created_at, id` 가 uuid 로 떨어진다(운영에선 요청마다 created_at 이 다르다) ⇒ 순서를 못 박지 말고 집합·합으로 판정하거나 paid_on 을 달리 준다(2026-09-24 ⓑ2 T6i)
⚠️ **검증 결과는 파일로 받아 OK 수와 MISMATCH 를 센다** — `psql … -f <검증> 2>&1 | tee /tmp/<이름>.out` 뒤 `grep -c 'OK '` · `grep -n 'MISMATCH\|ERROR'` · 기대 OK 수를 검증 파일 머리에 적어 둔다(2026-09-24 ⓑ1 100 · ⓑ2 54)  → ⚠️ [2026-09-26] 거르기는 'MISMATCH\|ERROR\|rror:' — 셸 오류(sh: … Syntax error)는 소문자라 ERROR 에 안 걸린다(⑤-1 G0 이 이렇게 사라졌다)
⚠️ **시험 적용 장치의 첫 실물(2026-09-25 ⓒ1 3회 · ⓒ2 2회)에서 걸린 것은 셋 다 검증 파일 쪽이었다** — 임시 표 스키마 접두(마이그레이션 결함 · 시험 적용이 잡았다) · 시퀀스 읽는 법 · 셈 실수(CHECK 수 · 인보이스 장수) ⇒ 예상 개수는 손으로 세지 말고 `pg_constraint`·`count(*)` 로 파일 안에서 뽑아 비교한다 · 기대 OK 수는 통과한 실행에서 받아 머리에 적는다
⭐⭐ **테스트 DB 에 화면 시험 실물이 생긴 뒤(2026-09-25~)의 검증 — 두 방식**(정본 §22-d)
   읽기 창구 = 창구를 부르지 않고 **직접 insert** — 번호 고정(79001~) · 실물 없는 손님 · 전체 집계는 시험 전 `\gset` 값과의 **차이**로 · 시퀀스 무접촉 · 되돌릴 것이 없다
   재발행    = **같은 입력 → 같은 출력** — 전 출력 담기 → `\i` → 후 출력 담기 · 쓰기 창구는 savepoint 안에서 · ⚠️ 되감기는 블록 안 insert 도 지운다(담아 둘 값은 변수로 · 2026-09-25 so-pay-remaining-2 3회차) · 발행처럼 번호를 당기는 창구는 **커서 SELECT 만 떼어** 옛 식 vs 새 함수 행 집합을 대조(인보이스 번호 소모 0)
   ⚠️ 「표가 비어 있을 때만 되돌린다」 시퀀스 가드(§4)는 **이제 안 돈다** — so · so_invoice · so_credit 에 화면 시험 실물(SO-25000~ · 60000~ · CR-01000)이 있다 ⇒ **번호를 당기는 검증은 하지 마라**
```

---

## 6. ⭐ 화면 파일을 쓸 때 (대화 Claude)

```
⚠️⚠️ **뼈대로 삼은 화면에서 진입점까지 그대로 가져온다**
   [실사고] `imsAuth(...)` 로 썼다 ← 실물은 `imsAuth.start({…}, cb)`. 콜백이 안 돌아 화면이 통째로 죽었다
   ⇒ 공통 파일이 내보내는 이름을 grep 으로 먼저 대조한다

⚠️⚠️ **쓰는 CSS 클래스가 실재하는지 전수 대조한다**
   [실사고] `.chead` 를 카드 머리로 썼는데 어디에도 없었다(실물은 `.head` + `<h3><span class="n">`)

⭐ 끝내기 전 검사 넷
   ① data-act 목록 ↔ 핸들러 목록이 일치하는가
   ② getElementById 가 찾는 id 가 전부 실재하는가 (⚠️ 코드가 만드는 id 는 오탐)
   ③ 마지막 <script> 를 node --check 로 문법 검사
   ④ 쓰는 클래스가 공통 CSS 나 로컬에 있는가
   ⚠️ ①~④ 로도 「선언 순서」·「값이 없는 변수 참조」는 안 잡힌다 — 실제로 돌려야 드러난다

⭐ 빌드 표시를 헤더에 둔다 — 어느 판이 도는지 화면에서 읽는다(브라우저 캐시를 가른다)
⭐ 파일을 낼 때 **바이트 수를 함께 말한다**
```

---

## 7. ⭐ 파일 주고받기 — 쓰기와 읽기를 가른다

```
⭐⭐ 읽기 — 레포 파일은 raw 로 **직접 받아** 읽는다. 첨부를 요청하지 마라(asung-wms 는 공개 레포 · 인증 없이 읽힌다)
  curl -s https://raw.githubusercontent.com/asungtrading/asung-wms/main/<경로> -o /tmp/x.raw
  ⚠️ **커밋돼 push 된 것만 보인다** — 로컬에서 고치고 안 올린 것은 안 보인다
  ⚠️ [실사고 2026-09-21] 「레포를 못 읽는다」고 두 번 말하고 첨부를 요청했다. Caleb 이 "public인데?" 하고 물어서야 재 보고 읽혔다

쓰기 — 대화 Claude 가 파일을 만들면 Caleb 이 내려받아 옮긴다
  집 PC  /mnt/c/Users/yoonh/Downloads/     회사  /mnt/c/Users/chang/Downloads/
⭐ [Caleb 요청] cp 에 **옮긴 뒤 지우는 rm 까지 함께** 준다:
  cp <다운로드>/<파일> <대상>/ && wc -c <대상>/<파일> && rm -f <다운로드>/<파일>*
⚠️ 브라우저가 「파일 (1).html」로 받는 일이 있다 — 안 맞으면 ls -lt 로 먼저 보게 한다
⚠️ 바이트 수가 안 맞으면 **옛 판이다.** 그대로 진행하지 마라
```

---

## 8. ⭐ 스킬을 만들고 고칠 때

```
자리    asung-wms/.claude/skills/<이름>/SKILL.md (+ references/)
한도    description **1024자** — pre-commit(scripts/hooks · check-skill-desc.sh)이 검사하고 여유를 출력한다
        ⚠️ **본문 바이트 한도는 없다**[규명 2026-09-21] — 훅·스크립트에 검사 코드 0건(grep) · 같은 폴더의 asung-wms 475,792바이트 · asung-inv-ledger 249,214바이트가
        claude.ai 에 실제로 올라가 쓰이고 있다(대화 Claude 컨텍스트에서 확인). 「14,000바이트」는 이 절의 문장에만 있던 근거 없는 숫자였다. 짧게 유지하는 것은 기준(아래)으로 한다
넣는 기준 ⭐⭐ **「모르면 사고가 나는 것」만.** 재고·수량·돈이 틀어지거나 남의 작업이 사라지는 것
        ❌ 행 수·실측 숫자·역사·오늘 상태 — 정본에 있다(스킬은 포인터여도 된다)
        ❌ 몰라도 사고가 안 나는 것(UI 입도·표시 방식) — references/ 나 정본으로
순서    ⚠️⚠️ **정본에 먼저 적고, 스킬은 그 요약이다.** 반대로 하면 스킬이 정본과 어긋난다
모자라면 ⚠️ **무엇을 왜 뺐는지 보고하게 하라.** 조용히 지우면 지식이 사라진다
description ⚠️ 키워드가 트리거다 — 자르면 필요할 때 스킬이 안 뜬다
        압축 순서 ①범위 표기 ②해소된 함정어 ③다른 스킬과 겹치는 말 ④일반어·영한 중복쌍
⚠️ 「여유 N자」가 본문 바이트인지 description 글자인지 헷갈린 적이 있다 — **각각 재서** 말한다
```

### 올리는 법 — claude.ai 스킬은 zip 으로 바꾼다(2026-09-23 인계 §7 에서 옮김)
```
① Claude Code 가 레포의 .claude/skills/<이름>/SKILL.md 를 고친다 — 정본 먼저 · description 1024자(pre-commit 이 잰다)
② Caleb 이 커밋·푸시(스킬은 레포가 정본 · zip 은 사본)
③ zip — ⚠️ 폴더 겹 없이(스킬 폴더 **안에서** 묶는다)
   회사  cd ~/asung/asung-wms/.claude/skills && for s in <스킬들>; do rm -f /mnt/c/Users/chang/Downloads/$s.zip; (cd $s && zip -r -q /mnt/c/Users/chang/Downloads/$s.zip .); done && ls -l /mnt/c/Users/chang/Downloads
   집    같은 명령에서 chang → yoonh
   ⚠️ references/ 가 있는 스킬(cin7-api · asung-wms · asung-apps-script 등 — ls -d .claude/skills/*/references)은 unzip -l <zip> | grep -c "references/" 가 1 이상인지 본다 — 0 이면 본문만 올라가 참조 파일이 사라진다
      SKILL.md 하나뿐인 스킬(asung-po · asung-so · asung-workflow)은 0 이 맞다
④ claude.ai → 스킬 → 그 스킬 → **바꾸기** 로 zip 을 올린다
⑤ description 여유는 pre-commit 출력으로 본다(날마다 바뀐다 — 여기 적지 않는다) · 여유가 적은 스킬에 키워드를 더할 때는 **먼저 뺄 것을 정한다**(위 압축 순서)
```

---

## 9. ⭐ 인계 문서 (하루 끝에)

```
자리   ~/asung/prompts/ims-handover-<날짜>.md — 다음 대화가 이것을 올린다
담는 것
  §0 시작 순서 — ⭐ **정본을 curl 로 직접 받아 읽게 한다**(기억·캐시로 답하지 않게)
     · 「이것이 보이면 최신, 안 보이면 갱신이 커밋되지 않은 것」이라는 **판별법**을 준다
  선 것 · ⭐⭐ 어기면 되돌리기 어려운 것 · 일하는 방식(이 스킬이 대신한다) ·
  ⚠️ 그날 겪은 실수 · 지금 DB 실물(id·번호까지) · ⭐ 다음 할 일 · 밀린 것 · 환경
끝맺음 ⭐ 「이 문서와 정본이 어긋나면 **정본이 맞다**」
⚠️ 인계 문서는 **하루 지나면 낡는다** — 규칙은 정본과 스킬로 올리고, 인계에는 상태와 다음 할 일만
```

---

## 10. 말투·표기

```
Caleb 에게는 **존댓말** · 자연스럽게 · 기호와 표는 꼭 필요할 때만
화면에 보이는 글자와 코드 주석은 **영어**
Claude Code 용 지시서는 기존 문서 말투 — **단정형·명령조** · ⭐ ⚠️ ⬜ 📌 를 그대로 쓴다
시각은 **토론토 기준**(여름 EDT=UTC-4 · 겨울 EST=UTC-5) — DB·로그는 UTC 라 변환해 말한다
  필요하면 에드먼튼(토론토보다 2시간 느림)도 함께
SQL 을 줄 때는 대상 프로젝트를 밝힌다 — [운영 · asung-WMS] 또는 [테스트 · Asung-IMS]
```

---

## 11. ⚠️ 반복해 겪은 실수 — 뿌리가 같다

```
⚠️ **확인하지 않고 단정한다**
   · 값이 안 맞는 것을 보고 「문서가 틀렸다」고 했는데 그날의 실물이었고 그 뒤 데이터가 움직인 것이었다
     ⇒ **데이터가 움직였을 가능성을 먼저 본다**
   · 프로브를 돌리기 전에 결과를 묘사한 적이 있다
   · 「Success」 한 줄을 보고 적용됐다고 읽었다
   · 예상값 표는 짐작이다 — 검증은 실측과 대조하고, 어긋나면 **DB 와 예상 중 무엇이 틀렸는지 먼저 가린다**
     (2026-09-22: CHECK 「5」 · 시험 4-b 의 A 「f/f/f」 — 둘 다 예상이 틀렸고 DB 가 맞았다)
   · Cin7 의 뜻 모를 값은 **화면으로 대조**한다 — 순서·소거 추론으로 옮기지 않는다(MarketingConsent 0 을 Opt out 으로 짐작 → 화면은 Unknown)
⚠️ **기억으로 쓴다**
   · 공통 함수 호출 모양 · CSS 클래스 이름 · 함수의 마지막 정의 위치
   ⇒ 전부 grep 한 번이면 끝난다. 쓰기 전에 본다
⚠️ **한 곳만 고친다**
   · 같은 코드·문구가 여러 곳에 복사돼 있다 ⇒ grep 으로 세어 보고 전부 고친다
⚠️ **PO 와 대칭인 자리를 기억으로 제안한다**
   [실사고 2026-09-21 · 두 번] SO 형제를 정할 때 ① 「뿌리를 가리키는 칸도 두자」→ PO 2026-09-16 에 이미 기각된 것
   ② 「b 다음은 c 가 맞다고 본다」→ 이미 PO 의 약속(내가 정할 자리가 아니었다)
   ⇒ 정본이 「PO 와 같은 방식」이라고 못 박은 자리는 **PO 를 펴고 시작한다.** raw 로 바로 받는다(§7)
⚠️ **「보고 오겠다」고 말만 하고 안 본다**
   [실사고 2026-09-21] "먼저 po_family 를 보고 오겠습니다" 하고 열지 않았다. Caleb 이 "PO 패밀리 보고 왔어?" 하고 물어서야 봤다
   ⇒ **말했으면 그 턴에 실행한다**
📌 긴 세션일수록 확인 없이 단정하는 경향이 는다 — Caleb 의 검증이 매번 잡아 왔다.
   ⭐ 스스로 「이건 본 것인가 짐작인가」를 묻는다
```
