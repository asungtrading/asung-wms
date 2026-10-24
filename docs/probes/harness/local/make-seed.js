// fixtures/customer.js → local/seed-customer.sql (로컬 Supabase 전용 · 테스트 DB 에 절대 돌리지 않는다)
'use strict';
const fx = require('../fixtures/customer');
const F = fx.build(process.argv[2] || 'main');
const q = v => v === null || v === undefined ? 'null' : typeof v === 'boolean' ? String(v) : typeof v === 'number' ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";
const ins = (t, rows) => rows.map(r => { const ks = Object.keys(r); return 'insert into public.' + t + ' (' + ks.join(', ') + ') values (' + ks.map(k => q(r[k])).join(', ') + ');'; }).join('\n');
const out = ['-- 생성물 · make-seed.js · ' + new Date().toISOString(), 'begin;',
  'truncate public.customer_contact, public.customer_address, public.customer, public.ims_staff, public.ref_currency, public.ref_payment_term, public.ref_account, public.ref_warehouse cascade;',
  ins('ims_staff', [{ id: fx.STAFF, auth_user_id: '10000000-0000-4000-8000-000000000001', email: 'harness@local', name: 'Harness Staff', role: 'manager' }]),
  ins('ref_currency', F.db.ref_currency), ins('ref_payment_term', F.db.ref_payment_term),
  ins('ref_account', F.db.ref_account.map(r => Object.assign({ account_class: r.code === '_61_' ? 'ASSET' : 'REVENUE' }, r))),
  ins('ref_warehouse', F.db.ref_warehouse),
  // 부모가 먼저(FK) — parent_id 가 없는 행 → 있는 행
  ins('customer', F.db.customer.filter(r => !r.parent_id)), ins('customer', F.db.customer.filter(r => r.parent_id)),
  ins('customer_address', F.db.customer_address), ins('customer_contact', F.db.customer_contact),
  'commit;'];
process.stdout.write(out.join('\n') + '\n');
