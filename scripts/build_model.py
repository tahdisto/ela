#!/usr/bin/env python3
"""
Build the lightweight Greek accentuation model from Leipzig sentence files.

Outputs (into data/model/):
  lexicon.tsv      key \t form|count \t form|count ...   (sorted desc by count)
  homographs.json  { key: {forms:{f:c}, left:{prevkey:{f:c}}, right:{f:{nextkey:c}}} }
  meta.json        stats

A "key" is the accent-stripped, lowercased, final-sigma-normalized token.
Only AMBIGUOUS keys (>=2 plausible forms) get context tables -> small model.

Train/test split: last TEST_FRAC of each input file is held out (not used to
build the model) so the accuracy harness can measure on unseen text.
"""
import sys, os, json, unicodedata, re, struct
from collections import defaultdict, Counter

TEST_FRAC = 0.10           # fraction of each file held out for testing
MIN_SECOND_COUNT = 3       # 2nd form must appear >= this many times
MIN_SECOND_RATIO = 0.02    # ...and be >= this share of the key total
DIALYTIKA = "̈"       # combining diaeresis (NOT an accent: keep it)

# Greek letter ranges incl. precomposed accented + dialytika forms.
GREEK_TOKEN = re.compile(r"[Ͱ-Ͽἀ-῿]+")

def strip_accent(s: str) -> str:
    """Remove tonos/oxia/varia/perispomeni; keep dialytika. Return NFC."""
    out = []
    for ch in unicodedata.normalize("NFD", s):
        if unicodedata.combining(ch):
            if ch == DIALYTIKA:
                out.append(ch)          # keep diaeresis
            # else drop the accent mark
        else:
            out.append(ch)
    return unicodedata.normalize("NFC", "".join(out))

def norm(tok: str) -> str:
    """Lowercase + final-sigma fix. Used for BOTH stored forms and context."""
    t = tok.lower()
    if t.endswith("σ"):            # trailing σ -> ς
        t = t[:-1] + "ς"
    return t

def key_of(form_norm: str) -> str:
    return strip_accent(form_norm)

def iter_sentences(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            tab = line.find("\t")
            yield line[tab+1:].rstrip("\n") if tab >= 0 else line.rstrip("\n")

def tokenize(sentence):
    """Return list of normalized accented tokens (Greek words only)."""
    return [norm(m.group(0)) for m in GREEK_TOKEN.finditer(sentence)]

VOWELS = set("αεηιουω")

def tonos_count(s: str) -> int:
    """Accent marks (excl. dialytika) in a form."""
    n = 0
    for ch in unicodedata.normalize("NFD", s):
        if unicodedata.combining(ch) and ch != DIALYTIKA:
            n += 1
    return n

def syllable_count(key: str) -> int:
    n, prev = 0, False
    for ch in key:
        v = ch in VOWELS
        if v and not prev:
            n += 1
        prev = v
    return n

def best_valid(key: str, counter: Counter) -> str:
    """Most frequent VALID form. Mirrors Accentuer.bestValid in Swift."""
    forms = counter.most_common()
    multi = syllable_count(key) >= 2
    for form, _ in forms:
        t = tonos_count(form)
        if t > 1:
            continue
        if multi and t == 0:
            continue
        return form
    return forms[0][0]

# ---- binary model emission --------------------------------------------------
# Little-endian. Strings are UTF-8. Keys sorted by raw UTF-8 byte order so the
# Swift reader can binary-search with memcmp.

def _pack_str(b: bytearray, s: str):
    raw = s.encode("utf-8")
    b += struct.pack("<H", len(raw))
    b += raw

def emit_lexicon_bin(path, forms_by_key, ambig):
    # unambiguous keys only (engine checks homographs first)
    keys = sorted((k for k in forms_by_key if k not in ambig),
                  key=lambda k: k.encode("utf-8"))
    records = bytearray()
    offsets = []
    for k in keys:
        offsets.append(len(records))
        _pack_str(records, k)
        _pack_str(records, best_valid(k, forms_by_key[k]))
    with open(path, "wb") as f:
        f.write(b"ELX1")
        f.write(struct.pack("<I", len(keys)))
        f.write(struct.pack("<%dI" % len(offsets), *offsets))
        f.write(records)
    return len(keys), 8 + 4 * len(offsets) + len(records)

def emit_homographs_bin(path, forms_by_key, ambig, left, right):
    keys = sorted(ambig, key=lambda k: k.encode("utf-8"))
    records = bytearray()
    offsets = []
    for k in keys:
        offsets.append(len(records))
        c = forms_by_key[k]
        form_list = [f for f, _ in c.most_common()]
        idx = {f: i for i, f in enumerate(form_list)}
        _pack_str(records, k)
        # forms
        records += struct.pack("<H", len(form_list))
        for f in form_list:
            _pack_str(records, f)
            records += struct.pack("<I", c[f])
        # left: prevKey -> form -> count
        lmap = left.get(k, {})
        records += struct.pack("<I", len(lmap))
        for pk, fc in lmap.items():
            _pack_str(records, pk)
            records += struct.pack("<I", len(fc))
            for f, cnt in fc.items():
                records += struct.pack("<HI", idx[f], cnt)
        # right: form -> nextKey -> count
        rmap = right.get(k, {})
        flat = [(f, nk, cnt) for f, nkc in rmap.items() for nk, cnt in nkc.items()]
        records += struct.pack("<I", len(flat))
        for f, nk, cnt in flat:
            records += struct.pack("<H", idx[f])
            _pack_str(records, nk)
            records += struct.pack("<I", cnt)
    with open(path, "wb") as f:
        f.write(b"EHM1")
        f.write(struct.pack("<I", len(keys)))
        f.write(struct.pack("<%dI" % len(offsets), *offsets))
        f.write(records)
    return len(keys), 8 + 4 * len(offsets) + len(records)


def main():
    files = sys.argv[1:]
    if not files:
        print("usage: build_model.py <sentences.txt> [more...]", file=sys.stderr)
        sys.exit(1)

    # Split into train sentences (test sentences are written out for the harness).
    train_sents, test_sents = [], []
    for path in files:
        sents = list(iter_sentences(path))
        cut = int(len(sents) * (1 - TEST_FRAC))
        train_sents.extend(sents[:cut])
        test_sents.extend(sents[cut:])
    print(f"train sentences: {len(train_sents):,}  test: {len(test_sents):,}")

    # Pass 1: dictionary key -> Counter(form)
    forms_by_key = defaultdict(Counter)
    train_tokens = []
    for s in train_sents:
        toks = tokenize(s)
        train_tokens.append(toks)
        for t in toks:
            forms_by_key[key_of(t)][t] += 1
    print(f"unique keys: {len(forms_by_key):,}")

    # Identify ambiguous keys (homographs worth disambiguating).
    ambig = set()
    for k, c in forms_by_key.items():
        if len(c) < 2:
            continue
        total = sum(c.values())
        top = c.most_common()
        second_cnt = top[1][1]
        if second_cnt >= MIN_SECOND_COUNT and second_cnt / total >= MIN_SECOND_RATIO:
            ambig.add(k)
    print(f"ambiguous keys: {len(ambig):,}")

    # Pass 2: context tables for ambiguous keys only.
    # left[k][prev_key][form] , right[k][form][next_key]
    left = defaultdict(lambda: defaultdict(Counter))
    right = defaultdict(lambda: defaultdict(Counter))
    BOS, EOS = "<s>", "</s>"
    for toks in train_tokens:
        keys = [key_of(t) for t in toks]
        for i, (t, k) in enumerate(zip(toks, keys)):
            if k not in ambig:
                continue
            pk = keys[i-1] if i > 0 else BOS
            nk = keys[i+1] if i+1 < len(keys) else EOS
            left[k][pk][t] += 1
            right[k][t][nk] += 1

    # Emit lexicon.tsv
    os.makedirs("data/model", exist_ok=True)
    with open("data/model/lexicon.tsv", "w", encoding="utf-8") as f:
        for k in sorted(forms_by_key):
            c = forms_by_key[k]
            parts = [f"{form}|{cnt}" for form, cnt in c.most_common()]
            f.write(k + "\t" + "\t".join(parts) + "\n")

    # Emit homographs.json
    homo = {}
    for k in ambig:
        homo[k] = {
            "forms": dict(forms_by_key[k].most_common()),
            "left":  {pk: dict(cc) for pk, cc in left[k].items()},
            "right": {form: dict(cc) for form, cc in right[k].items()},
        }
    with open("data/model/homographs.json", "w", encoding="utf-8") as f:
        json.dump(homo, f, ensure_ascii=False)

    # Emit binary model (what the app actually loads: mmap + binary search)
    lc, lb = emit_lexicon_bin("data/model/lexicon.bin", forms_by_key, ambig)
    hc, hb = emit_homographs_bin("data/model/homographs.bin", forms_by_key, ambig, left, right)
    print(f"binary: lexicon.bin {lc:,} keys / {lb/1e6:.1f}MB   homographs.bin {hc:,} keys / {hb/1e6:.1f}MB")

    # Emit test set for harness
    with open("data/model/test.txt", "w", encoding="utf-8") as f:
        for s in test_sents:
            f.write(s + "\n")

    meta = {
        "train_sentences": len(train_sents),
        "test_sentences": len(test_sents),
        "unique_keys": len(forms_by_key),
        "ambiguous_keys": len(ambig),
    }
    with open("data/model/meta.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print("wrote data/model/{lexicon.tsv,homographs.json,test.txt,meta.json}")
    # show a few interesting homographs
    interesting = [k for k in ("νομος","ποτε","γερος","αλλα","παρα","μονο") if k in homo]
    for k in interesting:
        print(f"  {k}: {forms_by_key[k].most_common()}")

if __name__ == "__main__":
    main()
