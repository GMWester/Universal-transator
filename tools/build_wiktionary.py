#!/usr/bin/env python3
"""Converts a Wiktextract dump (kaikki.org) into offline SQLite language packs.

  python3 tools/build_wiktionary.py --edition en \
      --input raw-wiktextract-data.jsonl.gz --out build/packs [--min-pack 3000]

The input is the newline-delimited JSON produced by wiktextract
(https://kaikki.org/dictionary/rawdata.html). It is streamed, so the
multi-GB file never has to be uncompressed on disk.

Output (in --out):
  wikt-<edition>-<lang>.sqlite.gz   one pack per large language
  wikt-<edition>-misc<N>.sqlite.gz  small languages bundled together
  manifest-<edition>.json           pack list: file, size, sha256, languages

Pack schema (also documented in docs/DATA_FORMAT.md):
  meta(key, value)
  langs(code, name, entries, has_ipa, g2p, chars)
  entries(id, lang, word, norm, pos, data)     data = zlib(JSON)
  forms(lang, norm, entry_id, tags)            inflected form -> entry
  ipa(lang, norm, ipa)                         pronunciation per word (TTS)
  senses(id, word, pos, gloss)                 translation-table senses
  tr(sense_id, lang, word, norm, roman, tags)  translations of those senses
  gloss_fts(gloss)  FTS5, rowid = entries.id   reverse lookup by meaning
"""
import argparse
import collections
import gzip
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import sys
import unicodedata
import zlib

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS langs(code TEXT PRIMARY KEY, name TEXT, entries INTEGER,
  has_ipa INTEGER, g2p TEXT, chars TEXT);
CREATE TABLE IF NOT EXISTS entries(id INTEGER PRIMARY KEY, lang TEXT, word TEXT,
  norm TEXT, pos TEXT, data BLOB);
CREATE TABLE IF NOT EXISTS forms(lang TEXT, norm TEXT, entry_id INTEGER, tags TEXT);
CREATE TABLE IF NOT EXISTS ipa(lang TEXT, norm TEXT, ipa TEXT, PRIMARY KEY(lang, norm));
CREATE TABLE IF NOT EXISTS senses(id INTEGER PRIMARY KEY, word TEXT, pos TEXT, gloss TEXT);
CREATE TABLE IF NOT EXISTS tr(sense_id INTEGER, lang TEXT, word TEXT, norm TEXT,
  roman TEXT, tags TEXT);
"""
INDEXES = """
CREATE INDEX IF NOT EXISTS entries_norm ON entries(lang, norm);
CREATE INDEX IF NOT EXISTS forms_norm ON forms(lang, norm);
CREATE INDEX IF NOT EXISTS tr_norm ON tr(lang, norm);
CREATE INDEX IF NOT EXISTS tr_sense ON tr(sense_id, lang);
CREATE INDEX IF NOT EXISTS senses_word ON senses(word);
"""


def norm(s):
    """Lookup key: NFC, lower case, no combining accents for Latin/Greek/Cyrillic
    stress marks, collapsed spaces. Must match Normalizer.key() in the app."""
    s = unicodedata.normalize('NFKD', s.strip().lower())
    s = ''.join(c for c in s if c not in '́̀́̀̏̑')
    s = unicodedata.normalize('NFC', s)
    return re.sub(r'\s+', ' ', s)


def clean_ipa(s):
    s = s.strip()
    if len(s) >= 2 and s[0] in '/[' and s[-1] in '/]':
        s = s[1:-1]
    s = s.split(',')[0].split('~')[0].strip()
    return s.strip('/[] ')


def compact_entry(e):
    senses = []
    for s in e.get('senses', [])[:40]:
        g = s.get('glosses') or s.get('raw_glosses') or []
        if not g:
            continue
        d = {'g': g[:3]}
        if s.get('tags'):
            d['t'] = s['tags'][:8]
        if s.get('topics'):
            d['p'] = s['topics'][:5]
        ex = []
        for x in s.get('examples', [])[:3]:
            t = x.get('text')
            if t:
                ex.append([t[:300], (x.get('english') or x.get('translation') or '')[:300],
                           (x.get('roman') or '')[:300]])
        if ex:
            d['x'] = ex
        fo = s.get('form_of') or s.get('alt_of')
        if fo and isinstance(fo, list) and isinstance(fo[0], dict) and fo[0].get('word'):
            d['f'] = fo[0]['word']
        syn = [x.get('word') for x in s.get('synonyms', [])[:8] if x.get('word')]
        if syn:
            d['sy'] = syn
        senses.append(d)
    sounds = []
    for snd in e.get('sounds', []):
        if snd.get('ipa'):
            sounds.append([snd['ipa'], ' '.join(snd.get('tags', [])[:4])])
        if len(sounds) >= 6:
            break
    forms = []
    for f in e.get('forms', [])[:80]:
        if f.get('form') and f['form'] != '-':
            forms.append([f['form'], ' '.join(f.get('tags', [])[:6])])
    d = {'s': senses}
    if sounds:
        d['ip'] = sounds
    if forms:
        d['fm'] = forms
    et = e.get('etymology_text')
    if et:
        d['et'] = et[:1500]
    for k, key in (('synonyms', 'sy'), ('antonyms', 'an'), ('derived', 'de'), ('related', 're')):
        v = [x.get('word') for x in e.get(k, [])[:15] if isinstance(x, dict) and x.get('word')]
        if v:
            d[key] = v
    return d


# --------------------------------------------------------------------------
# Grapheme-to-phoneme learning (language independent)
# --------------------------------------------------------------------------
MODIFIERS = set('ʰʷʲˠˤˀⁿˡʼːˑ̥̬̩̯̪̺̻̹̜̟̠̃̊̈̽̚ʱ˞̴̰̤̼̝̞̘̙')
STRIP_IPA = set('ˈˌ.‿|‖ ()-')
TONE = set('˥˦˧˨˩0123456789')


def ipa_segments(ipa):
    segs = []
    for ch in unicodedata.normalize('NFD', ipa):
        if ch in STRIP_IPA or ch in TONE:
            continue
        if segs and (unicodedata.combining(ch) or ch in MODIFIERS or ch in '͜͡'):
            segs[-1] += ch
        elif segs and segs[-1].endswith(('͡', '͜')):
            segs[-1] += ch
        else:
            segs.append(ch)
    return segs


def graphemes(word):
    out = []
    for ch in unicodedata.normalize('NFC', word.lower()):
        if unicodedata.combining(ch) and out:
            out[-1] += ch
        elif ch.isalpha() or unicodedata.category(ch).startswith('M'):
            out.append(ch)
    return out


def learn_g2p(pairs, iters=4, max_pairs=15000):
    """m2m-style EM alignment of 1-2 graphemes to 0-2 phoneme segments.
    Returns {"r": {chunk: [[ctx, phon, count], ...]}} for the runtime applier."""
    data = []
    for w, ipa in pairs[:max_pairs]:
        g, p = graphemes(w), ipa_segments(ipa)
        if 0 < len(g) <= 20 and 0 < len(p) <= 25:
            data.append((g, p))
    if len(data) < 30:
        return None
    prob = collections.defaultdict(lambda: 1.0)

    def align(g, p):
        n, m = len(g), len(p)
        best = [[(-1e18, None)] * (m + 1) for _ in range(n + 1)]
        best[0][0] = (0.0, None)
        for i in range(n + 1):
            for j in range(m + 1):
                sc = best[i][j][0]
                if sc <= -1e17:
                    continue
                for a in (1, 2):
                    if i + a > n:
                        continue
                    gk = ''.join(g[i:i + a])
                    for b in (0, 1, 2):
                        if j + b > m:
                            continue
                        pk = ' '.join(p[j:j + b])
                        v = sc + math.log(prob[(gk, pk)] + 1e-9) - (0.5 if a == 2 else 0) - (0.7 if b == 0 else 0)
                        if v > best[i + a][j + b][0]:
                            best[i + a][j + b] = (v, (i, j, gk, pk, a))
        if best[n][m][1] is None:
            return None
        path, i, j = [], n, m
        while (i, j) != (0, 0):
            _, bp = best[i][j]
            pi, pj, gk, pk, a = bp
            path.append((pi, gk, pk, a))
            i, j = pi, pj
        return path[::-1]

    for _ in range(iters):
        counts = collections.Counter()
        tot = collections.Counter()
        for g, p in data:
            path = align(g, p)
            if not path:
                continue
            for _, gk, pk, _a in path:
                counts[(gk, pk)] += 1
                tot[gk] += 1
        prob = collections.defaultdict(float)
        for (gk, pk), c in counts.items():
            prob[(gk, pk)] = c / tot[gk]
    rules = collections.defaultdict(collections.Counter)
    for g, p in data:
        path = align(g, p)
        if not path:
            continue
        for (pos, gk, pk, units) in path:
            left = g[pos - 1] if pos > 0 else '^'
            right_i = pos + units
            right = g[right_i] if right_i < len(g) else '$'
            pk = pk.replace(' ', '')
            rules[gk][('', pk)] += 1
            rules[gk][('L' + left, pk)] += 1
            rules[gk][('R' + right, pk)] += 1
    out = {}
    for gk, c in rules.items():
        base = c.most_common()
        best_plain = next((x for x in base if x[0][0] == ''), None)
        if not best_plain or best_plain[1] < 2:
            continue
        lst = [['', best_plain[0][1], best_plain[1]]]
        for (ctx, pk), n in base:
            if ctx and n >= 3 and pk != best_plain[0][1]:
                lst.append([ctx, pk, n])
            if len(lst) >= 12:
                break
        out[gk] = lst
    return {'r': out}


def apply_g2p(g2p, word, m2):
    """Python copy of LearnedG2p.convert() in lib/speech/g2p.dart."""
    rules = g2p['r']
    g = graphemes(word)
    out, i = [], 0

    def pick(rs, i, n):
        left = 'L' + (g[i - 1] if i > 0 else '^')
        right = 'R' + (g[i + n] if i + n < len(g) else '$')
        best = None
        for ctx, ph, c in rs:
            if (ctx == left or ctx == right) and (best is None or c > best[2]):
                best = (ctx, ph, c)
        return (best or rs[0])[1]

    while i < len(g):
        ph, used = None, 1
        if i + 1 < len(g):
            r2 = rules.get(g[i] + g[i + 1])
            if r2 and r2[0][2] >= m2:
                ph, used = pick(r2, i, 2), 2
        if ph is None:
            r1 = rules.get(g[i])
            if r1:
                ph = pick(r1, i, 1)
        out.append(ph or '')
        i += used
    return ''.join(out)


def _edit(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def g2p_error(g2p, pairs, m2):
    """Mean phoneme error rate on held-out (word, ipa) pairs."""
    tot, n = 0.0, 0
    for w, ipa in pairs:
        ref = ipa_segments(ipa)
        if not ref:
            continue
        hyp = ipa_segments(apply_g2p(g2p, w, m2))
        tot += min(1.0, _edit(hyp, ref) / len(ref))
        n += 1
    return tot / n if n else 1.0


def learn_checked_g2p(pairs, max_error=0.35):
    """Learns rules on 90% of the words, tunes the two-letter threshold on the
    other 10% and only returns rules that are accurate enough to be spoken."""
    if len(pairs) < 60:
        return None
    test = pairs[::10]
    train = [p for i, p in enumerate(pairs) if i % 10]
    g2p = learn_g2p(train)
    if not g2p:
        return None
    best = min(((g2p_error(g2p, test[:400], m2), m2) for m2 in (3, 10, 30, 100, 10**9)))
    err, m2 = best
    g2p['m2'] = m2
    g2p['err'] = round(err, 3)
    return g2p if err <= max_error else None


# --------------------------------------------------------------------------
TMP_IPA = """
CREATE TABLE IF NOT EXISTS ipa_scored(lang TEXT, norm TEXT, ipa TEXT, score INTEGER, PRIMARY KEY(lang, norm));
"""
# Parts of speech whose pronunciation is not the word's normal reading
# (e.g. German "IM" read as letters must not become the IPA of "im").
WEAK_POS = {'abbrev', 'name', 'symbol', 'character', 'letter', 'prefix', 'suffix', 'infix',
            'interfix', 'circumfix', 'affix', 'romanization', 'phrase', 'proverb', 'punct',
            'combining_form', 'contraction'}
WEAK_TAGS = ('unstressed', 'weak', 'obsolete', 'dated', 'archaic', 'rare', 'nonstandard', 'colloquial')


def best_ipa(entry_word, pos, sounds):
    """Pick the most suitable IPA of an entry and give it a score."""
    best, best_sc = None, -10**9
    for i, (ipa_raw, tags) in enumerate(sounds):
        ipa = clean_ipa(ipa_raw)
        if not ipa:
            continue
        sc = 100 - i
        if any(t in tags.lower() for t in WEAK_TAGS):
            sc -= 15
        if sc > best_sc:
            best, best_sc = ipa, sc
    if best is None:
        return None, 0
    if pos in WEAK_POS:
        best_sc -= 40
    if entry_word != entry_word.lower():
        best_sc -= 25
    return best, best_sc


# ---------------------------------------------------------------- eSpeak NG
# Fills in IPA for every headword and inflected form Wiktionary has no
# pronunciation for (eSpeak NG is only used here, at build time). Languages
# written without vowels (Arabic, Persian, Hebrew ...) and Chinese / Japanese
# characters are excluded: eSpeak cannot read those reliably.
ESPEAK_SKIP = {'zh', 'cmn', 'yue', 'hak', 'nan', 'wuu', 'ja', 'ar', 'fa', 'ur', 'he', 'ps', 'sd',
               'ug', 'yi', 'ks', 'arz', 'apc', 'ary', 'acm', 'ajp', 'afb', 'aeb', 'arq'}
ESPEAK_ALIAS = {'en': 'en-us', 'fr': 'fr-fr', 'pt': 'pt', 'no': 'nb', 'nn': 'nb', 'vi': 'vi',
                'grc': 'grc', 'la': 'la', 'zh-min-nan': None}
WORD_OK = re.compile(r"^[^\W\d_][\w'’-]*$")


def espeak_voices():
    import subprocess
    try:
        out = subprocess.run(['espeak-ng', '--voices'], capture_output=True, text=True, check=True).stdout
    except Exception:
        return set()
    return {line.split()[1] for line in out.splitlines()[1:] if len(line.split()) > 1}


def _espeak_run(voice, words):
    import subprocess
    data = ''.join(w + '.\n' for w in words)  # the period keeps output aligned 1 line per word
    try:
        r = subprocess.run(['espeak-ng', '-q', '--ipa', '-v', voice, '-b', '1'], input=data.encode(),
                           capture_output=True, timeout=900)
    except Exception:
        return None
    lines = r.stdout.decode('utf-8', 'replace').split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return lines


def _espeak_aligned(voice, words):
    """[(word, ipa)] - a batch whose output is misaligned (some words make
    eSpeak print extra lines) is split in halves until it lines up."""
    lines = _espeak_run(voice, words)
    if lines is None:
        return []
    if len(lines) == len(words):
        return list(zip(words, lines))
    if len(words) == 1:
        return [(words[0], ' '.join(l.strip() for l in lines if l.strip()))]
    mid = len(words) // 2
    return _espeak_aligned(voice, words[:mid]) + _espeak_aligned(voice, words[mid:])


def _espeak_batch(args):
    voice, words = args
    out = []
    for w, ipa in _espeak_aligned(voice, words):
        ipa = ipa.strip()
        if not ipa or '(' in ipa:  # "(en)..." means eSpeak switched language / spelled it out
            continue
        out.append((w, ipa))
    return out


def espeak_fill(db, langs, voices, jobs):
    from multiprocessing import Pool
    total = 0
    with Pool(jobs) as pool:
        for lang in langs:
            if lang in ESPEAK_SKIP:
                continue
            voice = ESPEAK_ALIAS.get(lang, lang)
            if not voice or voice not in voices:
                continue
            words = [r[0] for r in db.execute(
                """SELECT DISTINCT n FROM (SELECT norm AS n FROM entries WHERE lang=?
                   UNION SELECT norm AS n FROM forms WHERE lang=?)
                   WHERE n NOT IN (SELECT norm FROM ipa_scored WHERE lang=?)""", (lang, lang, lang))]
            words = [w for w in words if WORD_OK.match(w) and len(w) <= 40]
            if not words:
                continue
            batches = [(voice, words[i:i + 2000]) for i in range(0, len(words), 2000)]
            n = 0
            for res in pool.imap_unordered(_espeak_batch, batches):
                db.executemany('INSERT OR IGNORE INTO ipa_scored VALUES(?,?,?,10)',
                               [(lang, w, ipa) for w, ipa in res])
                n += len(res)
            db.commit()
            total += n
            print(f'  espeak {lang} ({voice}): {n} of {len(words)} words', flush=True)
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--edition', default='en')
    ap.add_argument('--input', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--work', default=None, help='scratch dir for the intermediate DB')
    ap.add_argument('--min-pack', type=int, default=3000,
                    help='languages with fewer entries are bundled into misc packs')
    ap.add_argument('--misc-size', type=int, default=60000, help='entries per misc pack')
    ap.add_argument('--only', default='', help='comma-separated language codes (testing)')
    ap.add_argument('--version', default='1')
    ap.add_argument('--no-espeak', action='store_true', help='do not fill missing IPA with eSpeak NG')
    ap.add_argument('--jobs', type=int, default=os.cpu_count() or 2)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    work = a.work or a.out
    os.makedirs(work, exist_ok=True)
    only = set(x for x in a.only.split(',') if x)

    tmp = os.path.join(work, f'all-{a.edition}.sqlite')
    if os.path.exists(tmp):
        os.remove(tmp)
    db = sqlite3.connect(tmp)
    db.executescript('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;' + SCHEMA + TMP_IPA)
    lang_names = {}
    counts = collections.Counter()
    ipa_pairs = collections.defaultdict(list)
    chars = collections.defaultdict(collections.Counter)
    sense_id = 0
    eid = 0
    opener = gzip.open if a.input.endswith('.gz') else open
    with opener(a.input, 'rt', encoding='utf-8') as f:
        for n, line in enumerate(f):
            if n % 200000 == 0:
                print(f'{n:>10} lines, {eid} entries, {sense_id} senses', flush=True)
                db.commit()
            try:
                e = json.loads(line)
            except ValueError:
                continue
            word = e.get('word')
            lang = e.get('lang_code')
            if not word or not lang or 'redirect' in e or e.get('pos') == 'hard-redirect':
                continue
            if only and lang not in only:
                continue
            lang_names.setdefault(lang, e.get('lang') or lang)
            eid += 1
            counts[lang] += 1
            key = norm(word)
            d = compact_entry(e)
            db.execute('INSERT INTO entries VALUES(?,?,?,?,?,?)',
                       (eid, lang, word, key, e.get('pos', ''),
                        zlib.compress(json.dumps(d, ensure_ascii=False, separators=(',', ':')).encode(), 6)))
            for fm, tags in d.get('fm', []):
                k2 = norm(fm)
                if k2 != key and len(k2) < 80:
                    db.execute('INSERT INTO forms VALUES(?,?,?,?)', (lang, k2, eid, tags))
            if d.get('ip'):
                ipa, sc = best_ipa(word, e.get('pos', ''), d['ip'])
                if ipa:
                    # keep the best-scoring pronunciation per word
                    db.execute('''INSERT INTO ipa_scored VALUES(?,?,?,?)
                                  ON CONFLICT(lang, norm) DO UPDATE SET ipa=excluded.ipa, score=excluded.score
                                  WHERE excluded.score > ipa_scored.score''', (lang, key, ipa, sc))
                    if ' ' not in word and sc >= 60 and len(ipa_pairs[lang]) < 20000:
                        ipa_pairs[lang].append((word, ipa))
            if counts[lang] <= 50000 and ' ' not in word:
                chars[lang].update(word)
            # translation tables
            trs = list(e.get('translations', []))
            for s in e.get('senses', []):
                for t in s.get('translations', []):
                    t = dict(t)
                    t.setdefault('sense', (s.get('glosses') or [''])[0])
                    trs.append(t)
            by_sense = collections.defaultdict(list)
            for t in trs:
                if t.get('word'):
                    by_sense[t.get('sense') or ''].append(t)
            for sense, items in by_sense.items():
                sense_id += 1
                db.execute('INSERT INTO senses VALUES(?,?,?,?)', (sense_id, word, e.get('pos', ''), sense[:300]))
                db.execute('INSERT INTO tr VALUES(?,?,?,?,?,?)',
                           (sense_id, lang, word, key, '', 'source'))
                for t in items:
                    tl = t.get('code') or t.get('lang_code')
                    if not tl:
                        continue
                    db.execute('INSERT INTO tr VALUES(?,?,?,?,?,?)',
                               (sense_id, tl, t['word'], norm(t['word']), t.get('roman', ''),
                                ' '.join(t.get('tags', [])[:4])))
                    lang_names.setdefault(tl, t.get('lang') or tl)
    db.commit()
    print('indexing', flush=True)
    db.executescript(INDEXES)
    if not a.no_espeak:
        voices = espeak_voices()
        if voices:
            print('filling missing pronunciations with eSpeak NG', flush=True)
            n = espeak_fill(db, sorted(counts), voices, a.jobs)
            print(f'  {n} pronunciations added', flush=True)
        else:
            print('eSpeak NG not installed: missing pronunciations stay empty', flush=True)
    db.execute('INSERT OR REPLACE INTO ipa SELECT lang, norm, ipa FROM ipa_scored')
    db.commit()

    # ---- pack assignment
    big = sorted([l for l, c in counts.items() if c >= a.min_pack], key=lambda l: -counts[l])
    small = sorted([l for l, c in counts.items() if c < a.min_pack])
    # languages that only appear as translation targets
    tr_only = [r[0] for r in db.execute('SELECT DISTINCT lang FROM tr') if r[0] not in counts]
    small += sorted(tr_only)
    packs = [(f'wikt-{a.edition}-{l}', [l]) for l in big]
    cur, size, k = [], 0, 1
    for l in small:
        cur.append(l)
        size += counts.get(l, 0) + 1
        if size >= a.misc_size:
            packs.append((f'wikt-{a.edition}-misc{k}', cur))
            cur, size, k = [], 0, k + 1
    if cur:
        packs.append((f'wikt-{a.edition}-misc{k}', cur))

    manifest = {'edition': a.edition, 'version': a.version, 'packs': []}
    for name, langs in packs:
        print('pack', name, len(langs), flush=True)
        path = os.path.join(work, name + '.sqlite')
        if os.path.exists(path):
            os.remove(path)
        p = sqlite3.connect(path)
        p.executescript('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;' + SCHEMA)
        p.execute('CREATE VIRTUAL TABLE gloss_fts USING fts5(gloss, content=\'\', tokenize=\'unicode61 remove_diacritics 2\')')
        p.execute('ATTACH DATABASE ? AS src', (tmp,))
        ql = ','.join('?' * len(langs))
        p.execute(f'INSERT INTO entries SELECT * FROM src.entries WHERE lang IN ({ql})', langs)
        p.execute(f'INSERT INTO forms SELECT * FROM src.forms WHERE lang IN ({ql})', langs)
        p.execute(f'INSERT INTO ipa SELECT * FROM src.ipa WHERE lang IN ({ql})', langs)
        p.execute(f'INSERT INTO tr SELECT * FROM src.tr WHERE lang IN ({ql})', langs)
        p.execute('INSERT INTO senses SELECT * FROM src.senses WHERE id IN (SELECT sense_id FROM main.tr)')
        p.commit()
        for rid, blob in p.execute('SELECT id, data FROM entries').fetchall():
            d = json.loads(zlib.decompress(blob))
            gl = ' ; '.join(g for s in d.get('s', []) if 'f' not in s for g in s.get('g', [])[:1])
            if gl:
                p.execute('INSERT INTO gloss_fts(rowid, gloss) VALUES(?,?)', (rid, gl[:1000]))
        for l in langs:
            g2p = learn_checked_g2p(ipa_pairs.get(l, []))
            ch = ''.join(c for c, _ in chars[l].most_common(400) if not c.isspace())
            p.execute('INSERT INTO langs VALUES(?,?,?,?,?,?)',
                      (l, lang_names.get(l, l), counts.get(l, 0), 1 if ipa_pairs.get(l) else 0,
                       json.dumps(g2p, ensure_ascii=False) if g2p else None, ch))
        p.executemany('INSERT INTO meta VALUES(?,?)', [
            ('edition', a.edition), ('version', a.version), ('name', name),
            ('format', '1')])
        p.executescript(INDEXES)
        p.commit()
        p.execute('DETACH DATABASE src')
        p.execute('VACUUM')
        p.close()
        gz = os.path.join(a.out, name + '.sqlite.gz')
        h = hashlib.sha256()
        with open(path, 'rb') as fi, gzip.open(gz, 'wb', compresslevel=6) as fo:
            while True:
                b = fi.read(1 << 20)
                if not b:
                    break
                fo.write(b)
        with open(gz, 'rb') as fi:
            for b in iter(lambda: fi.read(1 << 20), b''):
                h.update(b)
        manifest['packs'].append({
            'file': name + '.sqlite.gz', 'size': os.path.getsize(gz),
            'unpacked': os.path.getsize(path), 'sha256': h.hexdigest(),
            'langs': {l: {'n': lang_names.get(l, l), 'e': counts.get(l, 0)} for l in langs}})
        os.remove(path)
    json.dump(manifest, open(os.path.join(a.out, f'manifest-{a.edition}.json'), 'w'),
              ensure_ascii=False, indent=0)
    db.close()
    os.remove(tmp)
    print('done', len(manifest['packs']), 'packs')


if __name__ == '__main__':
    main()
