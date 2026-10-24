#!/usr/bin/env bash
# tools/gdrive-oauth-ims.sh — ims@asung.ca 의 구글 드라이브 열쇠(리프레시 토큰 · 범위 drive.file 하나 · 판정 702)를 받아 테스트 프로젝트 비밀에 바로 넣는다 (drive-2 · 2026-10-24 · gmail-oauth-ims.sh 꼴 그대로)
#   ⚠️ 메일 열쇠(GMAIL_*)는 손대지 않는다 — 같은 OAuth 클라이언트(ims-mail-tool)의 둘째 Client secret 을 쓴다(Caleb 2026-10-24) · 드라이브 비밀 셋은 따로(GDRIVE_OAUTH_CLIENT_ID · GDRIVE_OAUTH_CLIENT_SECRET · GDRIVE_REFRESH_TOKEN_IMS · drive-2 가=A)
#   Caleb 이 회사 PC(WSL)에서 한 번 돌린다. 값은 화면 · 기록 · 레포에 남기지 않는다(Client Secret 은 read -rs · 토큰은 0600 임시 파일 → supabase secrets set --env-file → 지움).
#   흐름: Client ID · Secret 묻기 → 동의 URL(login_hint=ims@asung.ca · prompt=consent · access_type=offline · drive.file + openid email · PKCE S256 · state)
#         → 브라우저(Windows)에서 ims@asung.ca 로 로그인 · 허용 → 루프백 http://127.0.0.1:<port> 로 code 받기(못 받으면 주소창 URL 을 붙여 넣기)
#         → 토큰 교환 → id_token 의 email 이 ims@asung.ca 가 아니면 멈춤(Caleb 계정으로 동의하는 실수 막기) → drive.file 범위 · 리프레시 토큰 확인
#         → supabase secrets set GDRIVE_OAUTH_CLIENT_ID · GDRIVE_OAUTH_CLIENT_SECRET · GDRIVE_REFRESH_TOKEN_IMS --project-ref fazgmyvzzhqybtvtktyg
#   --print-only: 비밀을 넣지 않고 「넣는 명령」 을 값 자리를 <…> 로 가려 찍는다(값은 임시 파일에만 · 끝나면 지운다 · drive-2 나=A)
#   열쇠가 되는지(files.list 가 drive.file 로 보이는지 · 이견 7)는 배포 뒤 EF drive {"action":"status"} 가 확인한다
#   준비(Google Cloud 콘솔 · 한 번): OAuth 동의 화면 User type = Internal(Workspace — Testing 상태의 External 은 리프레시 토큰이 7 일 뒤 끝난다 · Google OAuth 문서)
#         · Drive API 사용(2026-10-24 켬) · OAuth 클라이언트 유형 = Desktop app(루프백 127.0.0.1 · 포트 자유 — Google installed-app 문서)
#   쓰기:  bash tools/gdrive-oauth-ims.sh              # 실제
#          bash tools/gdrive-oauth-ims.sh --print-only # 동의까지 같고 비밀은 안 넣는다 · 명령만(값 가림)
#          bash tools/gdrive-oauth-ims.sh --self-test  # 네트워크 없이 URL · PKCE · id_token 검사 · env 파일 꼴만 시험
set -euo pipefail
REF="fazgmyvzzhqybtvtktyg"
EXPECT="ims@asung.ca"
if [ "${1:-}" = "--self-test" ]; then exec python3 -I - --self-test <<<"$(sed -n "/^: <<'__PY__'\$/,/^__PY__\$/p" "$0" | sed '1d;$d')"; fi
PRINT_ONLY=0; [ "${1:-}" = "--print-only" ] && PRINT_ONLY=1
command -v supabase >/dev/null || { echo "STOP — supabase CLI not found (install it, then run again)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "STOP — python3 not found" >&2; exit 2; }
read -rp  "OAuth Client ID (Desktop app ims-mail-tool, ends with .apps.googleusercontent.com): " CID
read -rsp "OAuth Client Secret — the SECOND secret made for Drive (not shown): " CSECRET; echo
[ -n "$CID" ] && [ -n "$CSECRET" ] || { echo "STOP — Client ID and Secret are both needed" >&2; exit 2; }
TMP=$(mktemp -d); chmod 700 "$TMP"; trap 'rm -rf "$TMP"' EXIT
PYF="$TMP/oauth.py"; sed -n "/^: <<'__PY__'\$/,/^__PY__\$/p" "$0" | sed '1d;$d' > "$PYF"
ENVF="$TMP/secrets.env"
CID="$CID" CSECRET="$CSECRET" EXPECT="$EXPECT" ENVF="$ENVF" python3 -I "$PYF"
if [ "$PRINT_ONLY" = 1 ]; then
  echo "print-only — nothing was set. The command that would run (values hidden):"
  echo "  supabase secrets set --env-file <0600 temp file with GDRIVE_OAUTH_CLIENT_ID=<id> GDRIVE_OAUTH_CLIENT_SECRET=<secret> GDRIVE_REFRESH_TOKEN_IMS=<token>> --project-ref $REF"
  rm -f "$ENVF"; exit 0
fi
echo "Putting three secrets into the test project ($REF) …"
supabase secrets set --env-file "$ENVF" --project-ref "$REF" >/dev/null
rm -f "$ENVF"
echo "OK — Drive key for $EXPECT is set. Check: supabase secrets list --project-ref $REF  → GDRIVE_OAUTH_CLIENT_ID · GDRIVE_OAUTH_CLIENT_SECRET · GDRIVE_REFRESH_TOKEN_IMS are listed."
echo "Next: deploy EF drive, then POST {\"action\":\"status\"} with x-ims-cron-key — token_ok · list_ok must both be true (list_ok = files.list works with drive.file)."
exit 0
: <<'__PY__'
import base64, hashlib, http.server, json, os, secrets, select, socket, subprocess, sys, threading, urllib.parse, urllib.request

SCOPES = "openid email https://www.googleapis.com/auth/drive.file"

def pkce():
    v = base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()          # 64 글자(43 ~ 128)
    c = base64.urlsafe_b64encode(hashlib.sha256(v.encode()).digest()).rstrip(b"=").decode()
    return v, c

def auth_url(cid, redirect, challenge, state, hint):
    q = {"client_id": cid, "redirect_uri": redirect, "response_type": "code", "scope": SCOPES, "access_type": "offline", "prompt": "consent",
         "login_hint": hint, "code_challenge": challenge, "code_challenge_method": "S256", "state": state, "include_granted_scopes": "false"}
    return "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(q)

def id_email(id_token):
    try:
        body = id_token.split(".")[1]; body += "=" * (-len(body) % 4)
        j = json.loads(base64.urlsafe_b64decode(body))
        return (j.get("email") or "").lower(), bool(j.get("email_verified"))
    except Exception:
        return "", False

def check_tokens(tok, expect):
    """returns an error sentence or None"""
    email, verified = id_email(tok.get("id_token", ""))
    if email != expect.lower() or not verified:
        return f"the consent was given by {email or 'an unknown account'}, not {expect} — open the link again in a private window and sign in as {expect}"
    if "https://www.googleapis.com/auth/drive.file" not in tok.get("scope", "").split():
        return "the drive.file permission was not granted — tick it on the consent page"
    if not tok.get("refresh_token"):
        return "Google gave no refresh token — remove the app at myaccount.google.com/permissions (signed in as ims@) and run again"
    return None

def env_lines(cid, csecret, refresh):
    for v in (cid, csecret, refresh):
        if "\n" in v or '"' in v: raise ValueError("unexpected character in a value")
    return f'GDRIVE_OAUTH_CLIENT_ID="{cid}"\nGDRIVE_OAUTH_CLIENT_SECRET="{csecret}"\nGDRIVE_REFRESH_TOKEN_IMS="{refresh}"\n'

def self_test():
    v, c = pkce(); assert 43 <= len(v) <= 128 and "=" not in c
    u = urllib.parse.urlparse(auth_url("cid.apps.googleusercontent.com", "http://127.0.0.1:5555", c, "st", "ims@asung.ca")); q = dict(urllib.parse.parse_qsl(u.query))
    assert u.netloc == "accounts.google.com" and q["login_hint"] == "ims@asung.ca" and q["prompt"] == "consent" and q["access_type"] == "offline" and q["code_challenge_method"] == "S256"
    assert q["scope"].split() == ["openid", "email", "https://www.googleapis.com/auth/drive.file"] and q["redirect_uri"] == "http://127.0.0.1:5555"
    mk = lambda claims: "h." + base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode() + ".s"
    good = {"id_token": mk({"email": "IMS@asung.ca", "email_verified": True}), "scope": "openid https://www.googleapis.com/auth/drive.file email", "refresh_token": "r"}
    assert check_tokens(good, "ims@asung.ca") is None
    assert "not ims@asung.ca" in check_tokens({**good, "id_token": mk({"email": "caleb@asung.ca", "email_verified": True})}, "ims@asung.ca")
    assert "drive.file" in check_tokens({**good, "scope": "openid email https://www.googleapis.com/auth/gmail.send"}, "ims@asung.ca")   # 메일 범위만 있는 열쇠는 거부
    assert "no refresh token" in check_tokens({**good, "refresh_token": ""}, "ims@asung.ca")
    assert env_lines("a", "b", "c").count("\n") == 3 and env_lines("a", "b", "c").startswith("GDRIVE_OAUTH_CLIENT_ID=")
    print("self-test OK — URL · PKCE · id_token account check · drive.file scope · refresh token · env file")

def main():
    cid, csecret, expect, envf = os.environ["CID"], os.environ["CSECRET"], os.environ["EXPECT"], os.environ["ENVF"]
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    redirect = f"http://127.0.0.1:{port}"
    verifier, challenge = pkce(); state = secrets.token_urlsafe(16)
    got = {}
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            got.update(dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query)))
            self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8"); self.end_headers()
            self.wfile.write("Done — you can close this tab and go back to the terminal.".encode())
        def log_message(self, *a): pass
    srv = http.server.HTTPServer(("127.0.0.1", port), H); threading.Thread(target=srv.handle_request, daemon=True).start()
    url = auth_url(cid, redirect, challenge, state, expect)
    print("\n1) A browser tab opens (if not, copy this link into a browser):\n\n" + url + "\n")
    print(f"2) Sign in as {expect} (use a private window if another account is signed in) and press Allow.")
    print("3) If the tab then says the site can't be reached, copy the whole address bar and paste it here, then Enter.\n")
    try: subprocess.run(["explorer.exe", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)   # WSL → Windows 브라우저(짐작 — 안 열리면 위 링크를 붙여 넣기)
    except Exception: pass
    for _ in range(600):                                                                  # 최대 10 분
        if got: break
        r, _, _ = select.select([sys.stdin], [], [], 1.0)
        if r:
            line = sys.stdin.readline().strip()
            if line: got.update(dict(urllib.parse.parse_qsl(urllib.parse.urlparse(line).query)))
    srv.server_close()
    if not got: sys.exit("STOP — no answer from the browser in 10 minutes. Run the tool again.")
    if got.get("error"): sys.exit(f"STOP — Google said {got['error']}. If it is access_denied, press Allow next time; if it is admin_policy_enforced, set the consent screen to Internal.")
    if got.get("state") != state: sys.exit("STOP — the answer does not belong to this run (state mismatch). Run the tool again.")
    body = urllib.parse.urlencode({"client_id": cid, "client_secret": csecret, "code": got.get("code", ""), "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}), timeout=30) as resp:
            tok = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        j = json.loads(e.read() or b"{}"); sys.exit(f"STOP — token exchange failed: {e.code} {j.get('error', '')} {j.get('error_description', '')} — check the Client ID / Secret (Desktop app) and run again.")
    err = check_tokens(tok, expect)
    if err: sys.exit("STOP — " + err)
    fd = os.open(envf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: f.write(env_lines(cid, csecret, tok["refresh_token"]))
    print(f"Consent confirmed for {expect} (drive.file).")

if __name__ == "__main__":
    self_test() if "--self-test" in sys.argv else main()
__PY__
