// ============================================================
// ASUNG IMS — 설명 HTML 거르기 (_shared · shop-2b · shop-2b-fix 판정 412 · 2026-10-09 · 판정 402 · shop-2-0 ⬜5)
//   ⭐ 설정(FORBID_TAGS · ADD_ATTR · ADD_TAGS)은 asung-ims/ims-desc.js 와 **글자 그대로** 같다 — 한쪽을 바꾸면 다른 쪽도(시험 ④ 가 대조한다)
//   판정 412: 보내기는 **규칙 기반**(rulesClean) 하나 — DOMPurify + jsdom 은 Edge Runtime 에서 안 돈다(실측 "Requires run access" · 번들 1.5 MB) · linkedom 은 조용히 안 거른다(shop-2-0 이견 1)
//   안전장치: 거른 결과를 보내기 직전에 DB 의 ims_html_forbidden(html) 에 넣어 하나라도 걸리면 그 상품은 보내지 않는다(index.ts pushOne · forbiddenAfterClean)
//   근거: IMS 에서 고친 설명은 저장 때 화면 DOMPurify + 서버 판별을 거쳤다 · Cin7 원문은 전수 실측에서 script · on…= · javascript: 0 · iframe · meta 뿐 — 규칙이 잡고, 놓친 것은 판별이 막는다
//   ⚠️ 이 파일을 바꾸면 shopify 함수를 재배포한다: supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg
// ============================================================

export const CLEAN_CONFIG = {                                                 // ims-desc.js 의 clean() 과 같은 세 목록
  ADD_TAGS: ["iframe"],
  ADD_ATTR: ["allow", "allowfullscreen", "frameborder", "scrolling", "target"],
  FORBID_TAGS: ["script", "style", "object", "embed", "form", "meta", "link", "base"],
};
export type CleanResult = { html: string; removed: string[]; engine: "rules" };

export function iframeHost(src: string | null | undefined): string {           // ims-desc.js 훅과 같은 셈 — 못 읽으면 ''(= 지운다)
  try { const h = new URL(String(src ?? ""), "https://invalid.local").host.toLowerCase(); return h === "invalid.local" ? "" : h; } catch { return ""; }
}
const SRC_RE = /\ssrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i;

// ── 규칙 기반 — 금지 태그는 열고 닫는 짝과 속을 통째로 · 허락 밖 iframe 요소 통째로 · on*= 속성 · 링크 속성의 javascript: ──
export function rulesClean(html: string, hosts: Set<string>): CleanResult {
  const removed: string[] = [];
  let s = String(html ?? "");
  for (const t of CLEAN_CONFIG.FORBID_TAGS) {
    const paired = new RegExp("<" + t + "(\\s[^>]*)?>[\\s\\S]*?<\\/" + t + "\\s*>", "gi");
    s = s.replace(paired, () => { removed.push("<" + t + ">"); return ""; });
    const single = new RegExp("<\\/?" + t + "(\\s[^>]*)?\\/?>", "gi");
    s = s.replace(single, () => { removed.push("<" + t + ">"); return ""; });
  }
  s = s.replace(/<iframe(\s[^>]*)?>[\s\S]*?<\/iframe\s*>|<iframe(\s[^>]*)?\/?>/gi, (m) => {
    const sm = m.match(SRC_RE);
    const host = iframeHost(sm ? (sm[1] ?? sm[2] ?? sm[3] ?? "") : "");
    if (host && hosts.has(host)) return m;
    removed.push("iframe" + (host ? " (" + host + ")" : ""));
    return "";
  });
  s = s.replace(/<([a-z][a-z0-9-]*)(\s[^>]*)>/gi, (_m, tag: string, attrs: string) => {
    let a = attrs.replace(/\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, (x) => { removed.push(x.trim().split("=")[0].toLowerCase() + "="); return ""; });
    a = a.replace(/\s+(href|src|action|formaction|xlink:href)\s*=\s*(?:"\s*javascript:[^"]*"|'\s*javascript:[^']*'|javascript:[^\s>]+)/gi, () => { removed.push("javascript: link"); return ""; });
    return "<" + tag + a + ">";
  });
  return { html: s, removed, engine: "rules" };
}
export const cleanHtml = (html: string, hosts: Set<string>): CleanResult => rulesClean(html, hosts);

// ── 안전장치 — DB 판별(ims_html_forbidden)의 반환이 비지 않으면 보내지 않는다 · 문장 하나(순수 · 시험은 가짜 판별로) ──
export const FORBIDDEN_AFTER_CLEAN = "description_forbidden_after_clean";
export function forbiddenAfterClean(codes: string[] | null | undefined): string | null {
  const c = (codes ?? []).map((x) => String(x)).filter(Boolean);
  return c.length ? FORBIDDEN_AFTER_CLEAN + ":" + c.join(",") : null;
}
