#!/usr/bin/env python3
# shop-photo-imp-2a — Shopify 전용 사진 가져오기 계획 자료 만들기(판정 1182 · 1183 · 1196 · deferred 387)
#   노트북 조사 결과(레포 밖 · ~/asung/scratch/spi · spd)를 읽어 계획 적재 SQL 한 파일을 만든다 — DB · Shopify 를 부르지 않는다(읽기만 · 쓰는 것은 --out 파일 하나).
#   ⚠️ 계획 자료(url · gid)는 레포에 넣지 않는다 — 이 스크립트와 자료 md5 만 레포 · 커밋 글에 남긴다.
#   입력: spi/pics_md5.json(가져올 사진 822) · spi/rows.json(사진 줄 1,764 — 상품 gid) · spd/res.json(same 1,578) · spd/listing.tsv(media gid · Shopify 순서)
#         spd/ims.tsv · spd/ims_h.tsv(IMS 사진 id · 메타 뺀 md5) · spd/shop_h.tsv(CDN 통파일 md5 · 크기 · 형식)
#   출력: select jsonb_pretty(public.shop_photo_plan_load('<json>'::jsonb)); 한 문장 — 갈 곳(1180 · 1181 · 1196) · 건너뜀(1184) · dup 은 DB 창구가 셈하고 expect 와 단언한다
#   쓰기: python3 scripts/shop-photo-plan-build.py [--spi DIR] [--spd DIR] [--out FILE]
import argparse, collections, csv, hashlib, json, os, re, sys

ap = argparse.ArgumentParser()
home = os.path.expanduser('~/asung/scratch')
ap.add_argument('--spi', default=home + '/spi'); ap.add_argument('--spd', default=home + '/spd'); ap.add_argument('--out', default=home + '/spi/plan_load.sql')
a = ap.parse_args()
INPUTS = [(a.spi, 'pics_md5.json'), (a.spi, 'rows.json'), (a.spd, 'res.json'), (a.spd, 'listing.tsv'), (a.spd, 'ims.tsv'), (a.spd, 'ims_h.tsv'), (a.spd, 'shop_h.tsv')]
rd = lambda d, f: [r for r in csv.reader(open(d + '/' + f), delimiter='\t')]
base = lambda u: u.split('?')[0]
stem = lambda u: base(u).split('/')[-1].rsplit('.', 1)[0]
IMS_BASE = 'https://fazgmyvzzhqybtvtktyg.supabase.co/storage/v1/object/public/product-images/'

pics = json.load(open(a.spi + '/pics_md5.json')); rows = json.load(open(a.spi + '/rows.json')); res = json.load(open(a.spd + '/res.json'))
L = {(r[0], r[1]): r for r in rd(a.spd, 'listing.tsv')}
sh = {r[0]: r for r in rd(a.spd, 'shop_h.tsv')}; ih = {r[0]: r for r in rd(a.spd, 'ims_h.tsv')}
imsl = collections.defaultdict(list); path2id = {}
for r in rd(a.spd, 'ims.tsv'): imsl[(r[0], r[1])].append(r[2]); path2id[r[3]] = r[2]
# 상품마다 media 순서(Shopify 순서 · 판정 1140) — listing.tsv 열 9 「gid=url …」
POS = {}; GID = {}
for (st, g), l in L.items():
    for n, x in enumerate(p for p in l[9].split(' ') if '=' in p):
        gid, url = x.split('=', 1); POS[(st, gid)] = n + 1; GID[(st, g, base(url))] = gid
ROW = {(r['st'], r['gid']): r for r in rows}

out_pics = []
for n, p in enumerate(pics):
    k = p['pick']; s = sh[k['url']]
    if not p['found']: sys.exit('not found in IMS: ' + p['tgt'])
    gids = [dict(st=st, g=ROW[(st, gid)]['g'], gid=gid, url=ROW[(st, gid)]['url'], pos=POS[(st, gid)]) for st, gid in p['gids']]
    out_pics.append(dict(n=n, kind=p['kind'], owner=p['owner'], tgt=p['tgt'], gray=bool(p['gray']), md5=k['md5'], file_md5=s[4], size=int(s[3]), ct=s[2], w=k['w'], h=k['h'],
                         st=k['st'], g=k['g'], gid=k['gid'], url=k['url'], pos=POS[(k['st'], k['gid'])], names=sorted({stem(u) for u in p['urls']}), gids=gids))

out_same = []
for r in res:
    if r['k2'] != 'same': continue
    st, g = r['st'], r['g']; gid = GID[(st, g, base(r['url']))]
    if r['k'] == 'same_md5':                                   # 메타 뺀 md5 가 같은 IMS 사진(그 상품의 첫 줄 · analyze.py 와 같은 고르기)
        img = [i for i in imsl[(st, g)] if ih.get(i, [0] * 6)[5] == sh[r['url']][5]][0]
    else:                                                      # pHash 후보 → 픽셀 대조(final.py)가 고른 것 = px[0] 의 IMS 주소
        img = path2id[r['px'][0][4][len(IMS_BASE):]]
    out_same.append(dict(st=st, g=g, gid=gid, url=r['url'], pos=POS[(st, gid)], img=img, how=r['k']))

C = collections.Counter
same_planned = len({(x['st'], x['img']) for x in out_same})
expect = {                                                     # 판정 1196(Caleb 11-11): 패밀리 445 + 109 · 제품 65 + 61 + 36 + 106 · 건너뜀 4 — DB 가 셈한 수와 다르면 적재가 통째로 거부된다
    'total': 822, 'cover': 445, 'family': 109, 'r1180': 65, 'variant': 61, 'single': 36, 'r1181': 106, 'to_family': 554, 'to_product': 268, 'skipped': 4, 'gray': 84,
    'pair_same': len(out_same), 'pair_same_planned': same_planned, 'pair_same_dup': len(out_same) - same_planned, 'pair_import': sum(len(p['gids']) for p in out_pics),
}
src = {f: hashlib.md5(open(d + '/' + f, 'rb').read()).hexdigest() for d, f in INPUTS}
plan = dict(source=src, expect=expect, pics=out_pics, same=out_same)
body = json.dumps(plan, ensure_ascii=False, separators=(',', ':'))
tag = '$plan$'
if tag in body: sys.exit('dollar tag collision')
sql = "select jsonb_pretty(public.shop_photo_plan_load(" + tag + body + tag + "::jsonb));\n"
open(a.out, 'w').write(sql)
print('pics', len(out_pics), dict(C(p['kind'] for p in out_pics)))
print('same', len(out_same), dict(C(x['how'] for x in out_same)), 'planned', same_planned, 'dup', len(out_same) - same_planned)
print('import pair rows', expect['pair_import'], '(pic x store)', len({(p['n'], x['st']) for p in out_pics for x in p['gids']}))
print('expect', json.dumps(expect))
print('out', a.out, len(sql), 'bytes md5', hashlib.md5(sql.encode()).hexdigest())
