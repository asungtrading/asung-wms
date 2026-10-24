// fixtures/supplier.js → local/seed-supplier.sql (로컬 Supabase 전용 · 테스트 DB 에 절대 돌리지 않는다)
'use strict';
const fx = require('../fixtures/supplier');
const F = fx.build(process.argv[2] || 'main');
const q = v => v === null || v === undefined ? 'null' : typeof v === 'boolean' ? String(v) : typeof v === 'number' ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";
const ins = (t, rows) => rows.map(r => { const ks = Object.keys(r); return 'insert into public.' + t + ' (' + ks.join(', ') + ') values (' + ks.map(k => q(r[k])).join(', ') + ');'; }).join('\n');
const out = ['-- 생성물 · make-seed-supplier.js · ' + new Date().toISOString(), 'begin;',
  'truncate public.product_supplier, public.supplier_contact, public.supplier_address, public.supplier, public.product, public.ims_staff, public.ref_currency, public.ref_payment_term, public.ref_account cascade;',
  ins('ims_staff', [{ id: fx.STAFF, auth_user_id: '10000000-0000-4000-8000-000000000003', email: 'harness-supplier@local', name: 'Harness Staff', role: 'manager' }]),
  ins('ref_currency', F.db.ref_currency), ins('ref_payment_term', F.db.ref_payment_term), ins('ref_account', F.db.ref_account),
  ins('supplier', F.db.supplier), ins('supplier_address', F.db.supplier_address), ins('supplier_contact', F.db.supplier_contact),
  ins('product', F.db.product), ins('product_supplier', F.db.product_supplier),
  'commit;'];
process.stdout.write(out.join('\n') + '\n');
