"""Vergleicht die Seitendaten von alter und neuer Notiz feldweise je Quellseite aus dem Plan.

Aufruf: python3 -I compare.py --work <scratch> ALT.note NEU.note plan.json

Gibt je Datensatz (vp = virtual/page, pm = pageModel, pageInfo = note_info-pageInfoMap) und Feld aus,
auf wie vielen Seiten es sich unterscheidet. Erwartet sind nur: vp 1/4/10/11 und pm 1
(Seiten-ID, Seitennummer, PDF-Pfad, PDF-Verweis). Alles andere ist ein Verlust und muss erklärt werden.
"""
import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from notemig import Note  # noqa: E402
from pb import getf  # noqa: E402

EXPECTED = {("vp", 1), ("vp", 4), ("vp", 10), ("vp", 11), ("pm", 1)}

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--work")
ap.add_argument("old")
ap.add_argument("new")
ap.add_argument("plan")
a = ap.parse_args()

old, new = Note(a.old, a.work), Note(a.new, a.work)
with open(a.plan) as f:
    pages = json.load(f)["pages"]
oi = json.loads(getf(old.ni, 12))["pageInfoMap"]
ni = json.loads(getf(new.ni, 12))["pageInfoMap"]
opm = {getf(r, 1).decode(): r for r in old.pm}
npm = {getf(r, 1).decode(): r for r in new.pm}

diffs = collections.Counter()
for pid, e in zip(new.pages, pages):
    src = e.get("from")
    if not src:
        continue
    for name, x, y in (("vp", old.vp[src], new.vp[pid]), ("pm", opm[src], npm[pid])):
        fx, fy = {f: v for f, _, v in x}, {f: v for f, _, v in y}
        for f in set(fx) | set(fy):
            if fx.get(f) != fy.get(f):
                diffs[(name, f)] += 1
    for k in set(oi[src]) | set(ni[pid]):
        if oi[src].get(k) != ni[pid].get(k):
            diffs[("pageInfo", k)] += 1

for k, v in sorted(diffs.items(), key=str):
    print("%-10s %-16s %4d Seiten  %s" % (k[0], k[1], v, "erwartet" if k in EXPECTED else "PRÜFEN"))
if any(k not in EXPECTED for k in diffs):
    sys.exit(1)
