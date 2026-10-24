// fixtures/product.js → local/seed-product.sql (로컬 Supabase 전용 · 테스트 DB 에 절대 돌리지 않는다)
'use strict';
const fx = require('../fixtures/product');
const F = fx.build(process.argv[2] || 'main');
const q = v => v === null || v === undefined ? 'null' : typeof v === 'boolean' ? String(v) : typeof v === 'number' ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";
const ins = (t, rows) => rows.map(r => { const ks = Object.keys(r); return 'insert into public.' + t + ' (' + ks.join(', ') + ') values (' + ks.map(k => q(r[k])).join(', ') + ');'; }).join('\n');
const out = ['-- 생성물 · make-seed-product.js · ' + new Date().toISOString(), 'begin;',
  "select set_config('ims.description_door', '1', true);",   // product_description_guard — 가짜 행은 전부 null 이라 없어도 되지만 문을 열어 둔다
  'truncate public.product_bom, public.product_barcode, public.product, public.product_family, public.ims_staff cascade;',
  ins('ims_staff', [{ id: fx.STAFF, auth_user_id: '10000000-0000-4000-8000-000000000002', email: 'harness-product@local', name: 'Harness Staff', role: 'manager' }]),
  ins('product_family', F.db.product_family),
  // 부모(parent_product_id 없음) → 세트
  ins('product', F.db.product.filter(r => !r.parent_product_id)), ins('product', F.db.product.filter(r => r.parent_product_id)),
  ins('product_barcode', F.db.product_barcode), ins('product_bom', F.db.product_bom),
  'commit;'];
process.stdout.write(out.join('\n') + '\n');
