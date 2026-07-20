/* Asung WMS shared login module
   ─────────────────────────────────────────────
   Usage (at the top of each screen script):
     wmsAuth.start({ requireManager:false }, (sb, me) => { ... });
   Pass requireManager:true to allow only manager/admin (workers denied).
   - Session is kept automatically by Supabase in the browser → stays logged in after one login.
   - Sign out: wmsAuth.signOut()
   - After login a "Change Password" button is auto-inserted next to #logoutBtn.
   - Login screen "Forgot your password?" → sends a reset link by email.
*/
(function(){
  const cfg = window.WMS_CONFIG || {};
  let sb=null, me=null, onReady=null, opts={};

  function injectStyles(){
    if(document.getElementById("wmsAuthStyle")) return;
    const s=document.createElement("style"); s.id="wmsAuthStyle";
    s.textContent=`
      #wmsLogin{position:fixed;inset:0;z-index:9999;background:#f7f8fa;display:flex;align-items:center;justify-content:center;font-family:"Inter",system-ui,-apple-system,"Malgun Gothic","Apple SD Gothic Neo",sans-serif}
      #wmsLogin .card{width:360px;max-width:92vw;background:#fff;border:1px solid #e5e9ef;border-radius:16px;box-shadow:0 4px 24px rgba(16,22,30,.08);padding:30px 28px}
      #wmsLogin h2{margin:0 0 4px;font-size:19px;color:#12161c}
      #wmsLogin .sub{margin:0 0 20px;color:#6b7686;font-size:13px}
      #wmsLogin label{display:block;font-size:11px;font-family:ui-monospace,Menlo,monospace;color:#6b7686;text-transform:uppercase;letter-spacing:.04em;margin:12px 0 5px}
      #wmsLogin input{width:100%;border:1px solid #e5e9ef;border-radius:9px;padding:11px 12px;font-size:14px;font-family:inherit}
      #wmsLogin input:focus{outline:none;border-color:#2f6df6;box-shadow:0 0 0 3px rgba(47,109,246,.12)}
      #wmsLogin button.main{width:100%;margin-top:18px;border:0;background:#12161c;color:#fff;border-radius:9px;padding:12px;font:inherit;font-size:14px;font-weight:700;cursor:pointer}
      #wmsLogin button.main:disabled{opacity:.6;cursor:default}
      #wmsLogin .err{margin-top:12px;color:#dc2626;font-size:12.5px;min-height:16px;font-weight:600}
      #wmsLogin .ok{margin-top:6px;color:#16a34a;font-size:12.5px;min-height:16px;font-weight:600}
      #wmsLogin .brand{font-family:ui-monospace,Menlo,monospace;font-weight:800;font-size:13px;color:#12161c;margin-bottom:14px}
      #wmsLogin .linkrow{margin-top:14px;text-align:center}
      #wmsLogin .link{background:none;border:0;color:#2f6df6;font:inherit;font-size:12.5px;font-weight:600;cursor:pointer;padding:4px;width:auto;margin:0}
      #wmsPwModal{position:fixed;inset:0;z-index:10000;background:rgba(16,22,30,.45);display:none;align-items:center;justify-content:center;font-family:"Inter",system-ui,-apple-system,"Malgun Gothic","Apple SD Gothic Neo",sans-serif}
      #wmsPwModal.show{display:flex}
      #wmsPwModal .card{width:340px;max-width:92vw;background:#fff;border-radius:16px;box-shadow:0 12px 40px rgba(0,0,0,.3);padding:26px 24px}
      #wmsPwModal h3{margin:0 0 4px;font-size:17px;color:#12161c}
      #wmsPwModal p{margin:0 0 16px;color:#6b7686;font-size:12.5px}
      #wmsPwModal label{display:block;font-size:11px;font-family:ui-monospace,Menlo,monospace;color:#6b7686;text-transform:uppercase;margin:10px 0 5px}
      #wmsPwModal input{width:100%;border:1px solid #e5e9ef;border-radius:9px;padding:11px 12px;font-size:14px;font-family:inherit}
      #wmsPwModal input:focus{outline:none;border-color:#2f6df6;box-shadow:0 0 0 3px rgba(47,109,246,.12)}
      #wmsPwModal .row{display:flex;gap:8px;margin-top:18px}
      #wmsPwModal .row button{flex:1;border:0;border-radius:9px;padding:11px;font:inherit;font-size:13.5px;font-weight:700;cursor:pointer}
      #wmsPwModal .cancel{background:#eef1f6;color:#12161c}
      #wmsPwModal .save{background:#12161c;color:#fff}
      #wmsPwModal .msg{margin-top:12px;font-size:12.5px;font-weight:600;min-height:16px}
      #wmsPwModal .msg.err{color:#dc2626} #wmsPwModal .msg.ok{color:#16a34a}
    `;
    document.head.appendChild(s);
  }

  /* login screen */
  function showLogin(prefillMsg){
    injectStyles();
    let el=document.getElementById("wmsLogin");
    if(!el){
      el=document.createElement("div"); el.id="wmsLogin";
      el.innerHTML=`<div class="card">
        <div class="brand">ASUNG WMS</div>
        <h2>Sign In</h2>
        <p class="sub">Sign in with your company email and password.</p>
        <label>Email</label>
        <input id="wmsEmail" type="email" autocomplete="username" placeholder="you@asung.ca">
        <label>Password</label>
        <input id="wmsPw" type="password" autocomplete="current-password" placeholder="XXXXXXXX">
        <button class="main" id="wmsLoginBtn">Sign In</button>
        <div class="err" id="wmsErr"></div>
        <div class="ok" id="wmsOk"></div>
        <div class="linkrow"><button class="link" id="wmsForgot">Forgot your password?</button></div>
      </div>`;
      document.body.appendChild(el);
      document.getElementById("wmsLoginBtn").onclick=doLogin;
      document.getElementById("wmsForgot").onclick=doForgot;
      document.getElementById("wmsPw").addEventListener("keydown",e=>{if(e.key==="Enter")doLogin();});
      document.getElementById("wmsEmail").addEventListener("keydown",e=>{if(e.key==="Enter")document.getElementById("wmsPw").focus();});
    }
    el.style.display="flex";
    if(prefillMsg) document.getElementById("wmsErr").textContent=prefillMsg;
    setTimeout(()=>{const f=document.getElementById("wmsEmail"); if(f)f.focus();},50);
  }
  function hideLogin(){ const el=document.getElementById("wmsLogin"); if(el)el.style.display="none"; }
  function loginErr(m){ const e=document.getElementById("wmsErr"),o=document.getElementById("wmsOk"); if(o)o.textContent=""; if(e)e.textContent=m||""; }
  function loginOk(m){ const e=document.getElementById("wmsErr"),o=document.getElementById("wmsOk"); if(e)e.textContent=""; if(o)o.textContent=m||""; }

  async function doLogin(){
    loginErr("");
    const email=document.getElementById("wmsEmail").value.trim();
    const pw=document.getElementById("wmsPw").value;
    if(!email||!pw){ loginErr("Enter your email and password."); return; }
    const btn=document.getElementById("wmsLoginBtn"); btn.disabled=true; btn.textContent="Signing in…";
    try{
      const {error}=await sb.auth.signInWithPassword({email,password:pw});
      if(error){ loginErr("Sign-in failed: check your email or password."); btn.disabled=false; btn.textContent="Sign In"; return; }
      const ok=await resolveIdentity();
      if(!ok){ btn.disabled=false; btn.textContent="Sign In"; return; }
      hideLogin(); btn.disabled=false; btn.textContent="Sign In";
      attachAccountControls();
      onReady(sb, me);
    }catch(e){ loginErr("Error: "+(e.message||e)); btn.disabled=false; btn.textContent="Sign In"; }
  }

  /* forgot password (email link) */
  async function doForgot(){
    const email=document.getElementById("wmsEmail").value.trim();
    if(!email){ loginErr("Enter your email first, then click this."); return; }
    loginErr("");
    try{
      const redirectTo=location.origin+location.pathname;
      const {error}=await sb.auth.resetPasswordForEmail(email,{redirectTo});
      if(error){ loginErr("Send failed: "+error.message); return; }
      loginOk("A reset link has been sent to your email. Please check your inbox.");
    }catch(e){ loginErr("Error: "+(e.message||e)); }
  }

  /* change-password modal */
  function ensurePwModal(){
    injectStyles();
    let m=document.getElementById("wmsPwModal");
    if(m) return m;
    m=document.createElement("div"); m.id="wmsPwModal";
    m.innerHTML=`<div class="card">
      <h3>Change Password</h3>
      <p>Enter a new password (at least 6 characters).</p>
      <label>New password</label>
      <input id="wmsNewPw" type="password" autocomplete="new-password" placeholder="XXXXXXXX">
      <label>Confirm new password</label>
      <input id="wmsNewPw2" type="password" autocomplete="new-password" placeholder="XXXXXXXX">
      <div class="row"><button class="cancel" id="wmsPwCancel">Cancel</button><button class="save" id="wmsPwSave">Change</button></div>
      <div class="msg" id="wmsPwMsg"></div>
    </div>`;
    document.body.appendChild(m);
    document.getElementById("wmsPwCancel").onclick=()=>{ m.classList.remove("show"); };
    document.getElementById("wmsPwSave").onclick=savePw;
    document.getElementById("wmsNewPw2").addEventListener("keydown",e=>{if(e.key==="Enter")savePw();});
    return m;
  }
  function showChangePw(){ const m=ensurePwModal(); document.getElementById("wmsNewPw").value=""; document.getElementById("wmsNewPw2").value=""; document.getElementById("wmsPwMsg").textContent=""; m.classList.add("show"); setTimeout(()=>document.getElementById("wmsNewPw").focus(),50); }
  async function savePw(){
    const msg=document.getElementById("wmsPwMsg"); msg.className="msg";
    const p1=document.getElementById("wmsNewPw").value, p2=document.getElementById("wmsNewPw2").value;
    if(p1.length<6){ msg.className="msg err"; msg.textContent="Must be at least 6 characters."; return; }
    if(p1!==p2){ msg.className="msg err"; msg.textContent="Passwords do not match."; return; }
    const btn=document.getElementById("wmsPwSave"); btn.disabled=true; btn.textContent="Changing…";
    try{
      const {error}=await sb.auth.updateUser({password:p1});
      if(error){ msg.className="msg err"; msg.textContent="Change failed: "+error.message; btn.disabled=false; btn.textContent="Change"; return; }
      msg.className="msg ok"; msg.textContent="Password changed successfully.";
      setTimeout(()=>{ const mm=document.getElementById("wmsPwModal"); if(mm)mm.classList.remove("show"); btn.disabled=false; btn.textContent="Change"; },1200);
    }catch(e){ msg.className="msg err"; msg.textContent="Error: "+(e.message||e); btn.disabled=false; btn.textContent="Change"; }
  }

  /* after login: auto-insert "Change Password" button next to #logoutBtn */
  function attachAccountControls(){
    const lo=document.getElementById("logoutBtn");
    if(!lo || document.getElementById("wmsPwBtn")) return;
    const b=document.createElement("button");
    b.id="wmsPwBtn"; b.type="button"; b.textContent="Change Password"; b.title="Change password";
    b.className=lo.className;
    if(lo.getAttribute("style")) b.setAttribute("style", lo.getAttribute("style"));
    b.onclick=showChangePw;
    lo.parentNode.insertBefore(b, lo);
  }

  async function resolveIdentity(){
    const {data:{user}}=await sb.auth.getUser();
    if(!user){ loginErr("Could not verify session."); return false; }
    const {data,error}=await sb.from("wms_staff").select("*").eq("email",user.email).maybeSingle();
    if(error){ loginErr("Staff lookup failed: "+error.message); return false; }
    if(!data){ loginErr("This account is not registered. Please contact your administrator."); await sb.auth.signOut(); return false; }
    if(data.active===false){ loginErr("This account is inactive."); await sb.auth.signOut(); return false; }
    if(opts.requireManager && !(data.role==="manager"||data.role==="admin")){
      loginErr("This screen is for managers and admins only."); await sb.auth.signOut(); return false;
    }
    me=data; return true;
  }

  const wmsAuth={
    async start(options, cb){
      if(typeof options==="function"){ cb=options; options={}; }
      opts=options||{}; onReady=cb;
      if(!cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_ANON_KEY.includes("PASTE_")){
        injectStyles(); showLogin(""); loginErr("Setup needed: add the anon key to wms-config.js.");
        return;
      }
      sb=supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
      window.sb=sb;
      sb.auth.onAuthStateChange((event)=>{ if(event==="PASSWORD_RECOVERY"){ showChangePw(); } });
      const {data:{session}}=await sb.auth.getSession();
      if(session){
        const ok=await resolveIdentity();
        if(ok){ hideLogin(); attachAccountControls(); onReady(sb, me); return; }
      }
      showLogin("");
    },
    async signOut(){ if(sb){ await sb.auth.signOut(); } location.reload(); },
    changePassword(){ showChangePw(); },
    get me(){ return me; },
    get sb(){ return sb; },
  };
  window.wmsAuth=wmsAuth;
})();
