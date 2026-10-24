// fixtures/tag.js → local/seed-tag.sql (로컬 Supabase 전용 · 테스트 DB 에 절대 돌리지 않는다) · ldfix-1d
'use strict';
const fx = require('../fixtures/tag');
const F = fx.build(process.argv[2] || 'main');
const q = v => v === null || v === undefined ? 'null' : typeof v === 'boolean' ? String(v) : typeof v === 'number' ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";
const ins = (t, rows) => rows.map(r => { const ks = Object.keys(r); return 'insert into public.' + t + ' (' + ks.join(', ') + ') values (' + ks.map(k => q(r[k])).join(', ') + ');'; }).join('\n');
const out = ['-- 생성물 · make-seed-tag.js · ' + new Date().toISOString(), 'begin;',
  'truncate public.so_deal_target, public.so_deal_line, public.so_deal, public.shop_listing, public.shop_store, public.ref_price_tier, public.product_tag, public.product, public.ref_currency cascade;',
  ins('ref_currency', F.db.ref_currency), ins('ref_price_tier', F.db.ref_price_tier),
  ins('product', F.db.product), ins('product_tag', F.db.product_tag),
  ins('shop_store', F.db.shop_store), ins('shop_listing', F.db.shop_listing),
  ins('so_deal', F.db.so_deal), ins('so_deal_line', F.db.so_deal_line), ins('so_deal_target', F.db.so_deal_target),
  'commit;'];
process.stdout.write(out.join('\n') + '\n');
