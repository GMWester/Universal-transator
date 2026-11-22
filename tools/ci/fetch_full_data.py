#!/usr/bin/env python3
"""Collects the offline data that goes into the "full" desktop installers.

  python3 tools/ci/fetch_full_data.py --repo OWNER/REPO --out offline-data \
      [--budget-mb 1900] [--model m2m100_418M]

Layout written (read by the app, see AppPaths.bundledDataDir):
  offline-data/bundled.json              {packId: {edition, langs, size}}
  offline-data/packs/<packId>.sqlite     unpacked Wiktionary packs
  offline-data/models/<id>/encoder.onnx, decoder.onnx, decoderWithPast.onnx,
                          tokenizer.json, config.json

Packs are taken from the "data-en" release, largest dictionaries first (English
always), until the budget (compressed MB, model included) is used. The budget
keeps each installer below GitHub's 2 GB per-file limit.
"""
import argparse
import gzip
import hashlib
import json
import os
import shutil
import sys
import urllib.request

UA = {'User-Agent': 'universal-translator-ci'}


def get(url, dest=None):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as r:
        if dest is None:
            return r.read()
        with open(dest, 'wb') as f:
            shutil.copyfileobj(r, f, 1 << 20)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--out', default='offline-data')
    ap.add_argument('--budget-mb', type=int, default=1900)
    ap.add_argument('--model', default='m2m100_418M')
    ap.add_argument('--config', default='assets/config/app_config.json')
    a = ap.parse_args()
    os.makedirs(f'{a.out}/packs', exist_ok=True)
    budget = a.budget_mb * 1024 * 1024
    used = 0

    # ---- translation model
    cfg = json.load(open(a.config))
    spec = next((m for m in cfg['translationModels'] if m['id'] == a.model), None)
    if spec:
        mdir = f'{a.out}/models/{spec["id"]}'
        os.makedirs(mdir, exist_ok=True)
        ok = True
        for role, rels in spec['files'].items():
            name = role + ('.json' if role in ('tokenizer', 'config') else '.onnx')
            dest = f'{mdir}/{name}'
            urls = []
            for rel in rels:
                urls.append(f'https://github.com/{a.repo}/releases/download/model-{spec["id"]}/{rel.split("/")[-1]}')
                urls.append(spec['baseUrl'] + rel)
            for u in urls:
                try:
                    get(u, dest)
                    print('model', role, u, os.path.getsize(dest) // 2**20, 'MB')
                    break
                except Exception as e:  # noqa: BLE001
                    print('  failed', u, e)
            if not os.path.exists(dest) and role != 'decoderWithPast':
                ok = False
        if ok:
            used += sum(os.path.getsize(f'{mdir}/{f}') for f in os.listdir(mdir))
        else:
            print('model incomplete, not bundled')
            shutil.rmtree(mdir, ignore_errors=True)

    # ---- dictionary packs
    try:
        man = json.loads(get(f'https://github.com/{a.repo}/releases/download/data-en/manifest-en.json'))
    except Exception as e:  # noqa: BLE001
        print('::warning::no data-en release yet, full installers will contain only the model:', e)
        man = {'packs': []}
    packs = [p for p in man['packs'] if len(p['langs']) == 1]
    packs.sort(key=lambda p: (0 if 'en' in p['langs'] else 1, -sum(v['e'] for v in p['langs'].values())))
    bundled = {}
    for p in packs:
        if used + p['size'] > budget:
            continue
        pid = p['file'].replace('.sqlite.gz', '')
        gz = f'{a.out}/{p["file"]}'
        get(f'https://github.com/{a.repo}/releases/download/data-en/{p["file"]}', gz)
        h = hashlib.sha256(open(gz, 'rb').read()).hexdigest()
        if p.get('sha256') and h != p['sha256']:
            sys.exit(f'checksum mismatch for {p["file"]}')
        with gzip.open(gz, 'rb') as fi, open(f'{a.out}/packs/{pid}.sqlite', 'wb') as fo:
            shutil.copyfileobj(fi, fo, 1 << 20)
        os.remove(gz)
        used += p['size']
        bundled[pid] = {'edition': 'en', 'langs': {k: v['n'] for k, v in p['langs'].items()},
                        'size': p.get('unpacked', 0)}
        print('pack', pid, p['size'] // 2**20, 'MB, total', used // 2**20, 'MB')
    json.dump(bundled, open(f'{a.out}/bundled.json', 'w'), ensure_ascii=False)
    print(f'{len(bundled)} packs bundled, {used // 2**20} MB compressed')


if __name__ == '__main__':
    main()
