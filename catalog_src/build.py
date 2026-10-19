"""catalog_src/*.txt -> assets/catalog.json

Kullanım:  python catalog_src/build.py [sürüm]
Sürümü her katalog değişikliğinde artırın; uygulama yalnızca daha yüksek sürümü kabul eder.
"""
import json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
version = int(sys.argv[1]) if len(sys.argv) > 1 else 1

TR = str.maketrans('çğıöşüÇĞİÖŞÜ', 'cgiosuCGIOSU')


def slug(name):
    s = name.translate(TR).lower()
    s = re.sub(r'[^a-z0-9]+', '-', s).strip('-')
    return s


def num(x):
    f = float(x)
    return int(f) if f == int(f) else f


items = []
for line in open(os.path.join(here, 'items.txt'), encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    name, emoji, cat, unit, price, flags = line.split('|')
    items.append({'name': name, 'emoji': emoji, 'cat': cat, 'unit': unit,
                  'price': float(price), 'meat': 'm' in flags,
                  'animal': 'a' in flags or 'm' in flags})
names = {i['name'] for i in items}
assert len(names) == len(items), 'yinelenen malzeme'

recipes, seen = [], set()
for f in ['kahvalti.txt', 'ana_1.txt', 'ana_2.txt']:
    for n, line in enumerate(open(os.path.join(here, f), encoding='utf-8'), 1):
        line = line.strip()
        if not line:
            continue
        parts = line.split('|')
        assert len(parts) == 6, f'{f}:{n} alan sayısı {len(parts)}'
        name, emoji, minutes, meals, ing, steps = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
        rid = slug(name)
        assert rid not in seen, f'yinelenen tarif {rid}'
        seen.add(rid)
        ings = {}
        for pair in ing.split(','):
            k, q = pair.rsplit(':', 1)
            assert k in names, f'{f}:{n} {name}: bilinmeyen malzeme {k}'
            ings[k] = num(q)
        recipes.append({'id': rid, 'name': name, 'emoji': emoji, 'minutes': int(minutes),
                        'meals': [int(c) for c in meals], 'ing': ings,
                        'steps': [s.strip() for s in steps.split(';') if s.strip()]})

out = {'version': version, 'items': items, 'recipes': recipes}
os.makedirs(os.path.join(here, '..', 'assets'), exist_ok=True)
with open(os.path.join(here, '..', 'assets', 'catalog.json'), 'w', encoding='utf-8') as fh:
    json.dump(out, fh, ensure_ascii=False, separators=(',', ':'))

meat = {i['name'] for i in items if i['meat']}
animal = {i['name'] for i in items if i['animal']}
print(f'sürüm {version}: {len(items)} malzeme, {len(recipes)} tarif')
for m, label in enumerate(['kahvaltı', 'öğle', 'akşam']):
    rs = [r for r in recipes if m in r['meals']]
    veg = [r for r in rs if not (set(r['ing']) & meat)]
    vegan = [r for r in rs if not (set(r['ing']) & animal)]
    print(f'  {label}: {len(rs)} tarif (vejetaryen {len(veg)}, vegan {len(vegan)})')
