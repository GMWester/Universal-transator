#!/usr/bin/env python3
"""Builds the offline data bundled inside the app (assets/data/).

Sources (all openly licensed, see DATA_LICENSES.md):
  * Glottolog CLDF   - list of all ~8 600 languages, families, ISO 639-3 codes
  * Unicode CLDR     - language names in ~650 display languages, exemplar
                       characters, likely scripts
  * WALS CLDF        - 192 typological features (word order, morphology ...)
                       for ~2 600 languages + chapter texts + examples
  * Grambank CLDF    - 195 grammatical features for ~2 400 languages
  * Unicode (via the Python `regex` module) - every character of every script

Usage:
  python3 tools/build_assets.py --src DIR --out assets/data

DIR must contain: glottolog-cldf/, wals/, grambank/, cldr-core-*/,
cldr-localenames-full-*/, cldr-misc-full-*/ (see tools/fetch_sources.sh).
"""
import argparse
import csv
import glob
import gzip
import html
import json
import os
import re
import sys
import unicodedata

import regex  # pip install regex

csv.field_size_limit(10**9)


def read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def write_gz(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = json.dumps(obj, ensure_ascii=False, separators=(',', ':')).encode()
    with open(path, 'wb') as raw:
        with gzip.GzipFile(fileobj=raw, mode='wb', compresslevel=9, mtime=0) as f:
            f.write(data)
    print(f'  {path}: {len(data)//1024} KiB raw, {os.path.getsize(path)//1024} KiB gz')


def one(pattern):
    m = sorted(glob.glob(pattern))
    if not m:
        sys.exit(f'missing source: {pattern}')
    return m[-1]


# --------------------------------------------------------------------------
# Languages
# --------------------------------------------------------------------------

def build_languages(src):
    gl = read_csv(f'{src}/glottolog-cldf/cldf/languages.csv')
    by_gc = {r['ID']: r for r in gl}
    cldr_core = one(f'{src}/cldr-core-*/package')
    alias = json.load(open(f'{cldr_core}/supplemental/aliases.json'))[
        'supplemental']['metadata']['alias']['languageAlias']
    # ISO 639-3 -> ISO 639-1 (Wiktionary and CLDR use 2-letter codes when one exists)
    iso3_to_1 = {}
    for k, v in alias.items():
        rep = v.get('_replacement', '')
        if len(k) == 3 and v.get('_reason') == 'overlong' and len(rep) == 2:
            iso3_to_1[k] = rep
    ldata = json.load(open(f'{cldr_core}/supplemental/languageData.json'))[
        'supplemental']['languageData']
    scripts = {}
    for k, v in ldata.items():
        base = k.split('-alt-')[0]
        scripts.setdefault(base, [])
        for s in v.get('_scripts', []):
            if s not in scripts[base]:
                scripts[base].append(s)
    likely = json.load(open(f'{cldr_core}/supplemental/likelySubtags.json'))[
        'supplemental']['likelySubtags']

    wals = {r['Glottocode']: r['ID'] for r in read_csv(f'{src}/wals/cldf/languages.csv') if r['Glottocode']}

    langs = {}
    for r in gl:
        if r['Level'] != 'language':
            continue
        iso3 = r['ISO639P3code']
        code = iso3_to_1.get(iso3, iso3) or r['ID']
        fam = by_gc.get(r['Family_ID'], {}).get('Name', '') if r['Family_ID'] else ''
        e = {'c': code, 'n': r['Name'], 'g': r['ID']}
        if iso3:
            e['i'] = iso3
        if fam:
            e['f'] = fam
        if r['Macroarea']:
            e['a'] = r['Macroarea']
        if r['ID'] in wals:
            e['w'] = wals[r['ID']]
        langs[code] = e

    # CLDR languages that Glottolog doesn't list as a language (e.g. macrolanguages)
    en_names = json.load(open(one(f'{src}/cldr-localenames-full-*/package') +
                              '/main/en/languages.json'))['main']['en']['localeDisplayNames']['languages']
    for code, name in en_names.items():
        if '-alt-' in code or '-' in code or code in ('und', 'root', 'mul', 'zxx'):
            continue
        if code not in langs:
            langs[code] = {'c': code, 'n': name}
        else:
            langs[code]['n'] = name  # CLDR English names are the common ones

    # Macrolanguages (zh, ar, fa, ms ...) borrow grammar data from their main
    # individual language (cmn, arb, pes, zsm ...), as listed by CLDR.
    by_iso3 = {e.get('i'): e for e in langs.values() if e.get('i')}
    for k, v in alias.items():
        if v.get('_reason') == 'macrolanguage' and len(k) == 3:
            macro = v.get('_replacement', '')
            m, ind = langs.get(macro), by_iso3.get(k)
            if m and ind and 'g' not in m:
                for key in ('g', 'f', 'a', 'w'):
                    if key in ind:
                        m[key] = ind[key]
    for code, e in langs.items():
        sc = scripts.get(code)
        if not sc:
            ls = likely.get(code)
            if ls:
                parts = ls.split('-')
                if len(parts) > 1 and len(parts[1]) == 4:
                    sc = [parts[1]]
        if sc:
            e['s'] = sc
    out = sorted(langs.values(), key=lambda e: e['n'].lower())
    return out, iso3_to_1


def build_names(src, out_dir, langs):
    base = one(f'{src}/cldr-localenames-full-*/package') + '/main'
    codes = {l['c'] for l in langs}
    index = []
    for loc in sorted(os.listdir(base)):
        p = f'{base}/{loc}/languages.json'
        if not os.path.exists(p):
            continue
        names = json.load(open(p))['main'][loc]['localeDisplayNames']['languages']
        names = {k: v for k, v in names.items() if '-alt-' not in k and (k in codes or '-' in k)}
        # Regional variants (en-GB, fr-CA ...) only store differences.
        if '-' in loc:
            parent = loc.split('-')[0]
            pp = f'{base}/{parent}/languages.json'
            if os.path.exists(pp):
                pn = json.load(open(pp))['main'][parent]['localeDisplayNames']['languages']
                names = {k: v for k, v in names.items() if pn.get(k) != v}
            if not names:
                continue
        elif len(names) < 30:
            continue
        own = names.get(loc) or names.get(loc.split('-')[0])
        if own is None:
            own_p = f'{base}/{loc.split("-")[0]}/languages.json'
            if os.path.exists(own_p):
                own = json.load(open(own_p))['main'][loc.split('-')[0]]['localeDisplayNames']['languages'].get(loc.split('-')[0])
        index.append({'c': loc, 'own': own or loc, 'count': len(names)})
        write_gz(f'{out_dir}/names/{loc}.json.gz', names)
    write_gz(f'{out_dir}/names_index.json.gz', index)


# --------------------------------------------------------------------------
# Grammar (WALS + Grambank)
# --------------------------------------------------------------------------

def strip_html(s):
    s = re.sub(r'(?is)<(script|style).*?</\1>', ' ', s)
    s = re.sub(r'(?i)<br\s*/?>|</p>|</h\d>|</li>|</tr>', '\n', s)
    s = re.sub(r'(?i)<li[^>]*>', '• ', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = html.unescape(s)
    s = re.sub(r'[ \t\r\f\v]+', ' ', s)
    s = re.sub(r'\n\s*\n+', '\n\n', s)
    return s.strip()


AREA_GROUP = {  # WALS area id -> app section
    '1': 'sounds', '2': 'word', '3': 'word', '4': 'sentence', '5': 'word',
    '6': 'sentence', '7': 'sentence', '8': 'sentence', '9': 'lexicon',
    '10': 'other', '11': 'other',
}


def build_grammar(src, out_dir):
    W = f'{src}/wals/cldf'
    G = f'{src}/grambank/cldf'
    areas = {r['ID']: r['Name'] for r in read_csv(f'{W}/areas.csv')}
    chapters = {r['ID']: r for r in read_csv(f'{W}/chapters.csv')}
    params = []
    pidx = {}
    docs = {}
    for r in read_csv(f'{W}/parameters.csv'):
        ch = chapters.get(r['Chapter_ID'], {})
        area = ch.get('Area_ID', '')
        pidx[r['ID']] = len(params)
        params.append({'id': r['ID'], 'src': 'wals', 'name': r['Name'],
                       'area': areas.get(area, ''), 'grp': AREA_GROUP.get(area, 'other'),
                       'doc': 'wals:' + r['Chapter_ID'], 'codes': {}})
        dp = f'{W}/docs/chapter_{r["Chapter_ID"]}.html'
        if os.path.exists(dp) and ('wals:' + r['Chapter_ID']) not in docs:
            docs['wals:' + r['Chapter_ID']] = {
                'title': ch.get('Name', r['Name']),
                'author': ch.get('Contributor', ''),
                'url': f'https://wals.info/chapter/{r["Chapter_ID"]}',
                'text': strip_html(open(dp, encoding='utf-8').read())}
    for r in read_csv(f'{W}/codes.csv'):
        params[pidx[r['Parameter_ID']]]['codes'][r['Number']] = r['Name']

    for r in read_csv(f'{G}/parameters.csv'):
        if r['Word_Order'] == '1':
            grp, area = 'sentence', 'Word order'
        elif r['Boundness'] == '1' or r['Flexivity'] == '1':
            grp, area = 'word', 'Morphology'
        elif r['Gender_or_Noun_Class'] == '1':
            grp, area = 'word', 'Gender / noun class'
        elif r['Locus_of_Marking'] == '1':
            grp, area = 'sentence', 'Marking of relations'
        else:
            grp, area = 'other', 'Grammatical categories'
        pidx[r['ID']] = len(params)
        params.append({'id': r['ID'], 'src': 'grambank', 'name': r['Name'], 'area': area,
                       'grp': grp, 'doc': 'gb:' + r['ID'], 'codes': {}})
        docs['gb:' + r['ID']] = {'title': r['Name'], 'author': 'Grambank',
                                 'url': f'https://grambank.clld.org/parameters/{r["ID"]}',
                                 'text': r['Description'].strip()}
    for r in read_csv(f'{G}/codes.csv'):
        params[pidx[r['Parameter_ID']]]['codes'][r['Name']] = r['Description']

    wl = {r['ID']: r['Glottocode'] for r in read_csv(f'{W}/languages.csv')}
    examples = {}
    for r in read_csv(f'{W}/examples.csv'):
        examples[r['ID']] = [r['Primary_Text'], r['Analyzed_Word'], r['Gloss'], r['Translated_Text']]
    used_examples = {}
    langs = {}
    for r in read_csv(f'{W}/values.csv'):
        gc = wl.get(r['Language_ID'])
        if not gc:
            continue
        v = {'v': r['Value']}
        exs = [e for e in (r.get('Example_ID') or '').split(';') if e in examples]
        if exs:
            v['x'] = exs
            for e in exs:
                used_examples[e] = examples[e]
        langs.setdefault(gc, {})[pidx[r['Parameter_ID']]] = v
    for r in read_csv(f'{G}/values.csv'):
        if r['Value'] in ('', '?'):
            continue
        gc = r['Language_ID']
        langs.setdefault(gc, {})[pidx[r['Parameter_ID']]] = {'v': r['Value']}
    # compact: lang -> [[paramIndex, value, [examples]]...]
    packed = {}
    for gc, d in langs.items():
        packed[gc] = [[k, v['v']] + ([v['x']] if 'x' in v else []) for k, v in sorted(d.items())]
    write_gz(f'{out_dir}/grammar.json.gz', {
        'params': params, 'langs': packed, 'examples': used_examples,
        'groups': {'sentence': 'Sentence structure', 'word': 'Word structure',
                   'sounds': 'Sounds', 'lexicon': 'Vocabulary', 'other': 'Other features'}})
    write_gz(f'{out_dir}/grammar_docs.json.gz', docs)


# --------------------------------------------------------------------------
# Characters
# --------------------------------------------------------------------------

def ranges(cps):
    out = []
    for cp in sorted(cps):
        if out and out[-1][1] == cp - 1:
            out[-1][1] = cp
        else:
            out.append([cp, cp])
    return out


def build_characters(src, out_dir, langs):
    cldr_core = one(f'{src}/cldr-core-*/package')
    script_meta = json.load(open(f'{cldr_core}/scriptMetadata.json'))['scriptMetadata'] \
        if os.path.exists(f'{cldr_core}/scriptMetadata.json') else {}
    en_scripts = json.load(open(one(f'{src}/cldr-localenames-full-*/package') +
                                '/main/en/scripts.json'))['main']['en']['localeDisplayNames']['scripts']
    assigned = ''.join(chr(c) for c in range(0x20, 0x110000)
                       if unicodedata.category(chr(c)) not in ('Cn', 'Cs', 'Co', 'Cc'))
    scripts = {}
    needed = set(en_scripts.keys())
    for l in langs:
        needed.update(l.get('s', []))
    for sc in sorted(needed):
        if len(sc) != 4:
            continue
        try:
            pat = regex.compile(r'\p{Script=%s}' % sc)
        except Exception:
            continue
        cps = [ord(ch) for ch in pat.findall(assigned)]
        if not cps:
            continue
        scripts[sc] = {'n': en_scripts.get(sc, sc), 'r': ranges(cps)}
    print(f'  {len(scripts)} scripts')

    names = {}
    for ch in assigned:
        cp = ord(ch)
        n = unicodedata.name(ch, '')
        if not n or n.startswith(('CJK UNIFIED IDEOGRAPH', 'HANGUL SYLLABLE', 'TANGUT IDEOGRAPH',
                                  'CJK COMPATIBILITY IDEOGRAPH', 'KHITAN SMALL SCRIPT CHARACTER',
                                  'NUSHU CHARACTER', 'EGYPTIAN HIEROGLYPH')):
            continue
        names[cp] = n
    write_gz(f'{out_dir}/char_names.json.gz', {format(k, 'x'): v for k, v in names.items()})

    misc = one(f'{src}/cldr-misc-full-*/package') + '/main'
    exemplars = {}
    for loc in sorted(os.listdir(misc)):
        p = f'{misc}/{loc}/characters.json'
        if not os.path.exists(p):
            continue
        c = json.load(open(p))['main'][loc]['characters']
        e = {k: c[k] for k in ('exemplarCharacters', 'auxiliary', 'index', 'numbers', 'punctuation')
             if k in c and isinstance(c[k], str)}
        if e:
            exemplars[loc] = e
    write_gz(f'{out_dir}/characters.json.gz', {'scripts': scripts, 'exemplars': exemplars,
                                               'unicode': unicodedata.unidata_version})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--out', default='assets/data')
    a = ap.parse_args()
    print('languages')
    langs, _ = build_languages(a.src)
    write_gz(f'{a.out}/languages.json.gz', langs)
    print(f'  {len(langs)} languages')
    print('language names')
    build_names(a.src, a.out, langs)
    print('grammar')
    build_grammar(a.src, a.out)
    print('characters')
    build_characters(a.src, a.out, langs)


if __name__ == '__main__':
    main()
