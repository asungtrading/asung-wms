/* Asung WMS 공통 설정
   ─────────────────────────────────────────────
   anon key는 "공개용(publishable)" 키입니다. 클라이언트 코드에 넣어도 안전하며,
   실제 데이터 보호는 Supabase RLS(행 수준 보안)가 담당합니다.
   ↓ 아래 PASTE_YOUR_ANON_PUBLIC_KEY_HERE 자리에 Supabase 대시보드의
     Settings → API → Project API keys → "anon public" 키를 붙여넣으세요.
*/
window.WMS_CONFIG = {
  SUPABASE_URL: "https://gftpcnkxbdjzzfvzwcfl.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdmdHBjbmt4YmRqenpmdnp3Y2ZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQzOTA1MjYsImV4cCI6MjA5OTk2NjUyNn0.eaTHZbcvv2NhefRcYjMNKF-3BrNJ9qFt1Yyn-mNSyKk"
};
