#!/usr/bin/env bash
# tools/gotenberg-secrets.sh — EF doc 의 Gotenberg 비밀 셋을 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg)에 넣는다(doc-2 · 2026-10-19 · 판정 523)
#   값은 화면 · 셸 기록 · 레포에 남기지 않는다 — 비밀번호는 read -rs(안 보임) · 0600 임시 파일 → supabase secrets set --env-file → 지움(gmail-oauth-ims.sh 와 같은 꼴)
#   비밀번호의 원천 = GCP Secret Manager gotenberg-basic-pass 판 1 — 두 길:
#     (가) Cloud Shell 에서 `gcloud secrets versions access 1 --secret gotenberg-basic-pass --project asung-ims-mail` 로 보고(화면에 한 번 찍힌다 · 그 Cloud Shell 창은 닫는다) 여기 붙여 넣는다
#     (나) 이 WSL 에 gcloud 가 있으면(2026-10-19 실측: 없다) `gcloud … | tools/gotenberg-secrets.sh --stdin` 으로 파이프 — 화면에 안 찍힌다
#   실행: tools/gotenberg-secrets.sh            (물어본다)   /   gcloud secrets versions access 1 --secret gotenberg-basic-pass --project asung-ims-mail | tools/gotenberg-secrets.sh --stdin
set -euo pipefail
REF="${IMS_PROJECT_REF:-fazgmyvzzhqybtvtktyg}"                       # ⚠️ 테스트 프로젝트 — 운영(gftpcnkxbdjzzfvzwcfl)은 컷오버 때 따로
URL="${GOTENBERG_URL:-https://gotenberg-926704977469.northamerica-northeast2.run.app}"
USER_NAME="${GOTENBERG_USER:-ims}"
if [[ "${1:-}" == "--stdin" ]]; then
  PASS="$(cat)"; PASS="${PASS%$'\n'}"
else
  read -rsp "Gotenberg password for user ${USER_NAME} (not echoed): " PASS; echo
fi
[[ -n "$PASS" ]] || { echo "empty password — nothing was set" >&2; exit 1; }
ENVF="$(mktemp)"; chmod 0600 "$ENVF"; trap 'rm -f "$ENVF"' EXIT
printf 'GOTENBERG_URL=%s\nGOTENBERG_USER=%s\nGOTENBERG_PASS=%s\n' "$URL" "$USER_NAME" "$PASS" > "$ENVF"
supabase secrets set --env-file "$ENVF" --project-ref "$REF" >/dev/null
echo "set GOTENBERG_URL · GOTENBERG_USER · GOTENBERG_PASS on project ${REF} (password length ${#PASS} · not shown)"
