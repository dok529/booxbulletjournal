#!/usr/bin/env python3
"""Handschrift einer BOOX-Notiz (.note) auf eine neue Version des Vorlagen-PDFs übertragen.

  plan  ALT.note NEU.pdf -o plan.json   Seitenzuordnung vorschlagen (über die Seitenüberschriften)
  build plan.json -o NEU.note           neue Notiz nach dem (geprüften) Plan bauen
  check NEU.note [--strokes datei]      Struktur prüfen, Strich-Übersicht, optional Striche für overlay.swift

Aufruf immer mit python3 -I. Entpackt wird in ein temporäres Verzeichnis (--work).
"""
import argparse
import collections
import io
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pb import encode, getf, parse, setf  # noqa: E402


def jdump(o):
    return json.dumps(o, separators=(",", ":"), ensure_ascii=False).encode()


def fail(msg):
    sys.exit("Fehler: " + msg)


# ---------- Notiz lesen ----------

class Note:
    def __init__(self, path, work=None):
        self.path = os.path.abspath(path)
        self.work = tempfile.mkdtemp(prefix="note-", dir=work)
        with zipfile.ZipFile(path) as z:
            for n in z.namelist():
                if n.startswith("/") or ".." in n.split("/"):
                    fail("verdächtiger Pfad im Archiv: " + n)
            z.extractall(self.work)
        docs = [d for d in os.listdir(self.work) if os.path.isdir(os.path.join(self.work, d))]
        if len(docs) != 1:
            fail("erwartet genau einen Dokumentordner, gefunden: %s" % docs)
        self.doc = docs[0]
        self.dir = os.path.join(self.work, self.doc)
        top = parse(self.read("note/pb/note_info"))
        self.ni = parse(top[0][2])
        self.pages = json.loads(getf(self.ni, 20))["pageNameList"]
        self.dev = json.loads(getf(self.ni, 14))["size"]
        self.vp_file = self.find1("virtual/page/pb")
        self.vp = {}
        for _, _, v in parse(self.read(self.vp_file)):
            r = parse(v)
            self.vp[getf(r, 1).decode()] = r
        self.pm_file = self.find1("pageModel/pb")
        self.pm = [parse(v) for _, _, v in parse(self.read(self.pm_file))]
        pdfs = {getf(r, 10).decode() for r in self.vp.values() if getf(r, 9) == b"import_pdf"}
        if len(pdfs) != 1:
            fail("erwartet Seiten aus genau einem PDF, gefunden: %s" % sorted(pdfs))
        self.pdf = os.path.join(self.dir, pdfs.pop().split("/", 2)[2])
        self.strokes = collections.Counter()
        for zname, page, _, _, recs in self.shapes():
            self.strokes[page] += len(recs)

    def read(self, rel):
        with open(os.path.join(self.dir, rel), "rb") as f:
            return f.read()

    def find1(self, rel):
        fs = os.listdir(os.path.join(self.dir, rel))
        if len(fs) != 1:
            fail("erwartet genau eine Datei in " + rel)
        return rel + "/" + fs[0]

    def ls(self, rel):
        p = os.path.join(self.dir, rel)
        return sorted(os.listdir(p)) if os.path.isdir(p) else []

    def pdf_index(self, pid):
        r = self.vp[pid]
        if getf(r, 9) != b"import_pdf":
            return None
        return json.loads(getf(r, 11))["pageIndex"]

    def width(self, pid):
        r = json.loads(getf(self.vp[pid], 6))
        return r["right"] - r["left"]

    def shapes(self):
        """(Zip-Name, Seiten-ID, Gruppen-ID, Zeitstempel, [Shape-Felder])"""
        for zname in self.ls("shape"):
            page, group, ts = zname[:-4].split("#")
            with zipfile.ZipFile(os.path.join(self.dir, "shape", zname)) as z:
                data = z.read(zname[:-4])
            yield zname, page, group, ts, [parse(v) for _, _, v in parse(data)]

    def label(self, pid, keys=None):
        n = self.pages.index(pid) + 1
        oi = self.pdf_index(pid)
        what = "leere Seite" if oi is None else "PDF %d %s" % (oi + 1, (keys[oi] if keys else "")[:40])
        s = self.strokes.get(pid, 0)
        return "Notizseite %d (%s%s)" % (n, what, ", %d Striche" % s if s else "")


# ---------- PDF ----------

def pdf_keys(path):
    out = subprocess.run(["swift", os.path.join(HERE, "pdf_keys.swift"), path],
                         check=True, capture_output=True, text=True).stdout.splitlines()
    _, w, h = out[0].split("\t")
    return (float(w), float(h)), [l.split("\t", 1)[1] for l in out[1:]]


def pdf_page_objects(data):
    """Objektnummern der Seiten in Seitenreihenfolge (BOOX: pageReferenceId = pdf-<obj>-0)."""
    if b"/ObjStm" in data:
        fail("PDF mit Objekt-Streams wird nicht unterstützt")
    objs = {int(m.group(1)): m.end() for m in re.finditer(rb"(\d+) 0 obj", data)}

    def body(n):
        s = objs[n]
        return data[s:data.index(b"endobj", s)]

    def is_pages(t):
        return re.search(rb"/Type\s*/Pages\b", t) is not None

    roots = [n for n in objs if is_pages(body(n)) and b"/Parent" not in body(n)]
    if len(roots) != 1:
        fail("Seitenbaum des PDFs nicht eindeutig")

    def walk(n):
        t = body(n)
        if not is_pages(t):
            return [n]
        kids = re.search(rb"/Kids\s*\[([^\]]*)\]", t).group(1)
        return [p for k in re.findall(rb"(\d+)\s+0\s+R", kids) for p in walk(int(k))]
    return walk(roots[0])


# ---------- plan ----------

def lcp(a, b):
    n = 0
    while n < min(len(a), len(b)) and a[n] == b[n]:
        n += 1
    return n


def cmd_plan(a):
    old = Note(a.note, a.work)
    _, okeys = pdf_keys(old.pdf)
    _, nkeys = pdf_keys(os.path.abspath(a.pdf))

    # alte PDF-Seite -> neue PDF-Seite: gleicher Schlüssel in Reihenfolge, sonst längstes gleiches Präfix
    bykey = collections.defaultdict(list)
    for i, k in enumerate(nkeys):
        bykey[k].append(i)
    used, omap = set(), {}
    for oi, k in enumerate(okeys):
        cand = [i for i in bykey.get(k, []) if i not in used]
        how = "gleich"
        if not cand:
            best = max(((lcp(k, nk), i) for i, nk in enumerate(nkeys) if i not in used), default=(0, None))
            if best[0] >= 6:
                cand, how = [best[1]], "ähnlich"
        if cand:
            omap[oi] = (cand[0], how)
            used.add(cand[0])

    by_new = collections.defaultdict(list)
    unplaced, aliases = [], {}
    for pid in old.pages:
        oi = old.pdf_index(pid)
        if oi is not None and oi in omap:
            by_new[omap[oi][0]].append(pid)
        elif old.strokes.get(pid):
            unplaced.append(pid)

    # weitere alte Seiten derselben Vorlage (auf dem BOOX kopiert): auf eine freie neue Seite
    # mit gleichem Schlüssel direkt dahinter, sonst als Kopie; ohne Striche nur als Link-Alias
    assigned, copies = {}, collections.defaultdict(list)
    for i in sorted(by_new):
        first, *rest = by_new[i]
        assigned[i] = first
        j = i
        for pid in rest:
            if not old.strokes.get(pid):
                aliases[pid] = first
                continue
            nxt = j + 1
            if nxt < len(nkeys) and nkeys[nxt] == nkeys[i] and nxt not in by_new and nxt not in assigned:
                assigned[nxt] = pid
                j = nxt
            else:
                copies[j].append(pid)

    pages = []
    for i in range(len(nkeys)):
        e = {"pdf": i, "_neu": nkeys[i][:50]}
        if i in assigned:
            pid = assigned[i]
            e["from"] = pid
            e["_alt"] = old.label(pid, okeys) + ("" if omap[old.pdf_index(pid)][1] == "gleich" else " [ähnlich]")
        pages.append(e)
        for pid in copies[i]:
            pages.append({"pdf": i, "_neu": nkeys[i][:50] + " (Kopie)", "from": pid, "_alt": old.label(pid, okeys)})

    plan = {"note": old.path, "pdf": os.path.abspath(a.pdf),
            "title": os.path.splitext(os.path.basename(a.pdf))[0],
            "pages": pages, "aliases": aliases,
            "unplaced": [{"from": pid, "_alt": old.label(pid, okeys)} for pid in unplaced],
            "drop": []}
    with open(a.out, "w") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)

    print("Plan: %d Seiten in der neuen Notiz (neues PDF: %d Seiten), gespeichert in %s"
          % (len(pages), len(nkeys), a.out))
    print("Seiten mit Strichen:")
    for n, e in enumerate(pages, 1):
        if e.get("from") and old.strokes.get(e["from"]):
            print("  neu %3d  <- %s\n           %s" % (n, e["_alt"], e["_neu"]))
    for u in plan["unplaced"]:
        print("  OHNE ZIEL: %s  (id %s)" % (u["_alt"], u["from"]))
    lost = [pid for pid in old.pages if pid not in aliases and pid not in unplaced
            and pid not in [e.get("from") for e in pages] and old.strokes.get(pid)]
    for pid in lost:
        print("  NICHT ÜBERNOMMEN: " + old.label(pid, okeys))


# ---------- build ----------

def affine(s, b, dx, dy):
    return lambda x, y: (s * b * x + dx, s * b * y + dy)


def cmd_build(a):
    with open(a.plan) as f:
        plan = json.load(f)
    if plan.get("unplaced"):
        fail("unplaced ist nicht leer: jede Seite dort einer Seite in pages zuordnen (from) oder in drop eintragen")
    old = Note(plan["note"], a.work)
    with open(plan["pdf"], "rb") as f:
        pdf = f.read()
    objs = pdf_page_objects(pdf)
    (pw, ph), _ = pdf_keys(plan["pdf"])
    pdf_name = os.path.basename(plan["pdf"])
    title = plan.get("title") or os.path.splitext(pdf_name)[0]
    pages = plan["pages"]
    now = int(time.time() * 1000)
    doc = str(uuid.uuid4())

    froms = [e["from"] for e in pages if e.get("from")]
    if len(froms) != len(set(froms)):
        fail("eine alte Seite steht mehrfach als from im Plan")
    for pid in old.strokes:
        if pid not in froms and pid not in plan.get("drop", []):
            fail("Seite mit Strichen fehlt im Plan: " + old.label(pid))
    for e in pages:
        if not 0 <= e["pdf"] < len(objs):
            fail("PDF-Seite %d gibt es nicht" % (e["pdf"] + 1))

    new_ids = [str(uuid.uuid4()) for _ in pages]
    remap = {e["from"]: new_ids[n] for n, e in enumerate(pages) if e.get("from")}
    for dup, first in plan.get("aliases", {}).items():
        if first in remap:
            remap[dup] = remap[first]

    tpl_pid = next(p for p in old.pages if old.pdf_index(p) is not None)
    width0 = old.width(tpl_pid)            # Breite einer PDF-Seite in Notiz-Einheiten
    r6h = width0 * ph / pw
    h7 = width0 * old.dev["height"] / old.dev["width"]

    def rect(l, t, r, b):
        return jdump({"bottom": b, "empty": False, "left": l, "right": r, "stability": 0, "top": t})

    files = {}

    # Striche: je Shape eine Transformation (Grundskalierung alte -> neue Seitenbreite, dann Plan-Transform)
    xf_by_page, region_by_page = {}, {}
    for e in pages:
        if not e.get("from"):
            continue
        t = e.get("transform", {})
        b = width0 / old.width(e["from"])
        xf_by_page[e["from"]] = (t.get("scale", 1.0), b, t.get("dx", 0.0), t.get("dy", 0.0))
        region_by_page[e["from"]] = t.get("region")

    def in_region(bbox, region):
        if not region:
            return True
        cx, cy = (bbox["left"] + bbox["right"]) / 2, (bbox["top"] + bbox["bottom"]) / 2
        return region[0] <= cx <= region[2] and region[1] <= cy <= region[3]

    point_xf = collections.defaultdict(dict)   # Punktedatei -> {Shape-ID: f}
    nlinks = 0
    for zname, page, group, ts, recs in old.shapes():
        if page not in remap or page in plan.get("aliases", {}):
            continue
        s, b, dx, dy = xf_by_page[page]
        out = []
        for r in recs:
            sid, pts = getf(r, 1).decode(), getf(r, 16).decode()
            bbox = json.loads(getf(r, 7))
            ss, sdx, sdy = (s, dx, dy) if in_region(bbox, region_by_page[page]) else (1.0, 0.0, 0.0)
            f = affine(ss, b, sdx, sdy)
            if (ss, b, sdx, sdy) != (1.0, 1.0, 0.0, 0.0):
                l, t = f(bbox["left"], bbox["top"])
                rr, bb = f(bbox["right"], bbox["bottom"])
                setf(r, 7, rect(l, t, rr, bb))
                m = getf(r, 8)
                if m is not None:   # Shape mit Matrix: Transformation vor die Matrix setzen
                    mv = json.loads(m)
                    v = mv["values"]
                    k = ss * b
                    v[0], v[1], v[2] = k * v[0], k * v[1], k * v[2] + sdx
                    v[3], v[4], v[5] = k * v[3], k * v[4], k * v[5] + sdy
                    setf(r, 8, jdump(mv))
                else:
                    point_xf[pts][sid] = f
            bean = getf(r, 10)
            if bean is not None:    # Link auf eine Seite dieser Notiz
                bj = json.loads(bean)
                d = bj["docBean"]
                if d.get("documentId") == old.doc:
                    if d["pageId"] not in remap:
                        fail("Link auf %s, die im Plan fehlt" % old.label(d["pageId"]))
                    d["pageId"] = remap[d["pageId"]]
                    d["pageIndex"] = new_ids.index(d["pageId"])
                    d["documentId"], d["title"] = doc, title
                    d["path"] = d.get("path", "").replace(old.doc, doc)
                    setf(r, 10, jdump(bj))
                    nlinks += 1
            out.append((1, 2, encode(r)))
        name = "%s#%s#%s" % (remap[page], group, ts)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr(name, encode(out))
        files["shape/%s.zip" % name] = buf.getvalue()

    for page in old.ls("point"):
        if page not in remap or page in plan.get("aliases", {}):
            continue
        for fn in old.ls("point/" + page):
            _, pts, tail = fn.split("#")
            data = bytearray(old.read("point/%s/%s" % (page, fn)))
            data[4:40] = remap[page].encode()
            idx = struct.unpack(">I", data[-4:])[0]
            for k in range((len(data) - 4 - idx) // 44):
                ent = data[idx + 44 * k: idx + 44 * k + 44]
                f = point_xf[pts].get(ent[:36].decode())
                if not f:
                    continue
                off, ln = struct.unpack(">II", ent[36:])
                for p in range(off + 4, off + ln, 16):
                    data[p:p + 8] = struct.pack(">ff", *f(*struct.unpack(">ff", data[p:p + 8])))
            files["point/%s/%s#%s#%s" % (remap[page], remap[page], pts, tail)] = bytes(data)

    # Seitenmodelle: Ebenen, aktuelle Ebene und Seitenname kommen von der Quellseite,
    # neue Seiten bekommen nur Ebene 0 und keinen Namen. Striche auf einer fehlenden Ebene zeigt das Gerät nicht an.
    vp_tpl = old.vp[tpl_pid]
    old_pm = {getf(r, 1).decode(): r for r in old.pm}
    pm_doc = old_pm.get(old.doc)
    layer0 = [{"id": 0, "lock": False, "show": True}]
    pm_tpl = [f for f in old_pm[tpl_pid] if f[0] not in (3, 4)]   # 3 = aktuelle Ebene, 4 = Seitenname
    setf(pm_tpl, 2, jdump({"layerList": layer0}))
    vp_out, pm_out = [], []
    for n, (pid, e) in enumerate(zip(new_ids, pages)):
        # Seiteneintrag der Quellseite übernehmen (Zeitstempel und unbekannte Felder bleiben),
        # nur bei neuen Seiten oder Quellen ohne PDF (auf dem Gerät eingefügte leere Seite) die Vorlage
        src = e.get("from")
        if src in old.vp and old.pdf_index(src) is not None:
            r = list(old.vp[src])
        else:
            r = list(vp_tpl)
            setf(r, 2, now, 0); setf(r, 3, now, 0)
        setf(r, 1, pid.encode())
        setf(r, 4, struct.pack("<f", n + 1), 5)
        if json.loads(getf(r, 8)) != json.loads(rect(0.0, 0.0, pw, ph)):   # Seitengröße nur bei geändertem PDF-Format neu
            setf(r, 6, rect(0.0, 0.0, width0, r6h))
            setf(r, 7, rect(0.0, (r6h - h7) / 2, width0, (r6h + h7) / 2))
            setf(r, 8, rect(0.0, 0.0, pw, ph))
        setf(r, 10, ("document/%s/resource/content/%s" % (doc, pdf_name)).encode())
        setf(r, 11, jdump({"pageIndex": e["pdf"], "pageReferenceId": "pdf-%d-0" % objs[e["pdf"]], "pageUUID": ""}))
        vp_out.append((1, 2, encode(r)))
        if src in old_pm:
            r = list(old_pm[src])
        else:
            r = list(pm_tpl)
            setf(r, 5, now, 0); setf(r, 6, now, 0)
        setf(r, 1, pid.encode())
        if src not in old.vp or old.pdf_index(src) is None:   # Quelle war eine leere Seite: Rechteck einer PDF-Seite
            setf(r, 7, getf(pm_tpl, 7))
        pm_out.append((1, 2, encode(r)))
    if pm_doc:
        r = list(pm_doc)
        setf(r, 1, doc.encode()); setf(r, 5, now, 0); setf(r, 6, now, 0)
        pm_out.append((1, 2, encode(r)))
    files[old.vp_file] = encode(vp_out)
    files[old.pm_file] = encode(pm_out)

    ni = list(old.ni)
    setf(ni, 1, doc.encode()); setf(ni, 2, now, 0); setf(ni, 3, now, 0)
    setf(ni, 6, title.encode())
    info = json.loads(getf(ni, 12))
    old_info = info["pageInfoMap"]
    tpl_info = {k: v for k, v in old_info[tpl_pid].items() if k != "title"}
    tpl_info.update(currentLayerId=0, layerList=layer0)
    info["pageInfoMap"] = {}
    for pid, e in zip(new_ids, pages):
        src = e.get("from")
        p = dict(old_info.get(src, tpl_info))
        if src in old.vp and old.pdf_index(src) is None:   # Quelle war eine leere Seite: Größe einer PDF-Seite
            p["width"], p["height"] = old_info[tpl_pid]["width"], old_info[tpl_pid]["height"]
        info["pageInfoMap"][pid] = p
    setf(ni, 12, jdump(info))
    setf(ni, 19, 0, 0)
    setf(ni, 20, jdump({"pageNameList": new_ids}))
    files["note/pb/note_info"] = encode([(1, 2, encode(ni))])

    vd = parse(old.read("virtual/doc/pb/" + old.doc))
    setf(vd, 1, uuid.uuid4().hex.encode()); setf(vd, 2, now, 0); setf(vd, 3, now, 0)
    setf(vd, 4, new_ids[0].encode())
    files["virtual/doc/pb/" + doc] = encode(vd)
    ex = parse(old.read("extra/pb/extra"))
    setf(ex, 4, doc.encode())
    files["extra/pb/extra"] = encode(ex)

    # unverändert: Vorlagen-JSON und Ressourcen-Marker; der Radier-Verlauf (stash) entfällt
    for fn in old.ls("template/json"):
        files["template/json/" + fn] = old.read("template/json/" + fn)
    for fn in old.ls("document/%s/template/json" % old.doc):
        files["document/%s/template/json/%s" % (doc, fn)] = old.read("document/%s/template/json/%s" % (old.doc, fn))
    for fn in old.ls("resource/pb"):
        files["resource/pb/" + fn] = old.read("resource/pb/" + fn)
    files["resource/content/" + pdf_name] = pdf

    if os.path.exists(a.out):
        fail(a.out + " existiert schon")
    dirs = {""}
    for p in files:
        parts = p.split("/")[:-1]
        dirs.update("/".join(parts[:k]) for k in range(1, len(parts) + 1))

    def zinfo(name, is_dir, empty=False):
        zi = zipfile.ZipInfo(name, time.localtime()[:6])
        zi.create_system = 3
        zi.external_attr = ((0o40770 if is_dir else 0o100660) << 16) | (0x10 if is_dir else 0)
        zi.compress_type = zipfile.ZIP_STORED if is_dir or empty else zipfile.ZIP_DEFLATED
        return zi
    with zipfile.ZipFile(a.out, "w") as z:
        for d in sorted(dirs):
            z.writestr(zinfo("%s/%s/" % (doc, d) if d else doc + "/", True), b"")
        for p in sorted(files):
            z.writestr(zinfo("%s/%s" % (doc, p), False, not files[p]), files[p])
    print("%s: %d Seiten, %d Seiten mit Strichen, %d Links umgebogen, Dokument %s"
          % (a.out, len(pages), len([p for p in remap if p in old.strokes and p not in plan.get("aliases", {})]),
             nlinks, doc))


# ---------- check ----------

def cmd_check(a):
    n = Note(a.note, a.work)
    ids = set(n.pages)
    pm_ids = {getf(r, 1).decode() for r in n.pm} - {n.doc}
    pim = set(json.loads(getf(n.ni, 12))["pageInfoMap"])
    if not (ids == set(n.vp) == pm_ids == pim):
        fail("Seiten-IDs in note_info, virtual/page, pageModel und pageInfoMap stimmen nicht überein")
    for i, p in enumerate(n.pages):
        if struct.unpack("<f", getf(n.vp[p], 4))[0] != i + 1:
            fail("Seitennummer in virtual/page passt nicht zu Seite %d" % (i + 1))
    _, keys = pdf_keys(n.pdf)
    objs = pdf_page_objects(open(n.pdf, "rb").read())
    for p in n.pages:
        ref = json.loads(getf(n.vp[p], 11))
        if ref["pageReferenceId"] != "pdf-%d-0" % objs[ref["pageIndex"]]:
            fail("PDF-Verweis falsch auf Seite %d" % (n.pages.index(p) + 1))
    dump = open(a.strokes, "w") if a.strokes else None
    links = []
    layers = {p: {l["id"] for l in v["layerList"]} for p, v in json.loads(getf(n.ni, 12))["pageInfoMap"].items()}
    for zname, page, _, _, recs in n.shapes():
        if page not in ids:
            fail("Striche für unbekannte Seite " + page)
        for r in recs:
            if (getf(r, 6) or 0) not in layers[page]:
                fail("Striche auf Ebene %d, die Seite %d nicht hat" % (getf(r, 6) or 0, n.pages.index(page) + 1))
            bean = getf(r, 10)
            if bean:
                d = json.loads(bean)["docBean"]
                if d.get("documentId") == n.doc:
                    ok = 0 <= d["pageIndex"] < len(n.pages) and n.pages[d["pageIndex"]] == d["pageId"]
                    links.append((n.pages.index(page) + 1, d["pageIndex"] + 1, ok))
    for page in n.ls("point"):
        for fn in n.ls("point/" + page):
            data = n.read("point/%s/%s" % (page, fn))
            if data[4:40].decode() != page:
                fail("Kopf der Punktedatei passt nicht: " + fn)
    print("%s: %d Seiten, PDF %s, Titel %s — Struktur ok" % (a.note, len(n.pages), os.path.basename(n.pdf),
                                                          getf(n.ni, 6).decode()))
    for p in n.pages:
        if n.strokes.get(p):
            oi = n.pdf_index(p)
            print("  Seite %3d  PDF %3d  %4d Striche  %s" % (n.pages.index(p) + 1, oi + 1, n.strokes[p], keys[oi][:45]))
    for src, dst, ok in links:
        print("  Link Seite %d -> Seite %d %s" % (src, dst, "ok" if ok else "FALSCH"))
    if dump:
        write_strokes(n, dump)
        dump.close()
        print("Striche für overlay.swift: " + a.strokes)
    if not all(ok for _, _, ok in links):
        sys.exit(1)


def write_strokes(n, out):
    """Je Seite 'P <Seite> <PDF-Index> <Seitenbreite>', dann 'S x,y ...' mit angewandter Matrix."""
    by_page = collections.defaultdict(list)
    for _, page, _, _, recs in n.shapes():
        by_page[page] += recs
    for page in sorted(by_page, key=n.pages.index):
        pts = {}
        for fn in n.ls("point/" + page):
            data = n.read("point/%s/%s" % (page, fn))
            idx = struct.unpack(">I", data[-4:])[0]
            for k in range((len(data) - 4 - idx) // 44):
                ent = data[idx + 44 * k: idx + 44 * k + 44]
                off, ln = struct.unpack(">II", ent[36:])
                pts[ent[:36].decode()] = [struct.unpack(">ff", data[p:p + 8]) for p in range(off + 4, off + ln, 16)]
        out.write("P %d %d %.4f\n" % (n.pages.index(page) + 1, n.pdf_index(page), n.width(page)))
        for r in by_page[page]:
            m = getf(r, 8)
            v = json.loads(m)["values"] if m else [1, 0, 0, 0, 1, 0]
            line = pts.get(getf(r, 1).decode(), [])
            out.write("S " + " ".join("%.1f,%.1f" % (v[0] * x + v[1] * y + v[2], v[3] * x + v[4] * y + v[5])
                                      for x, y in line) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work", help="Verzeichnis für entpackte Dateien (Standard: System-Temp)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("note"); p.add_argument("pdf"); p.add_argument("-o", "--out", required=True)
    p = sub.add_parser("build")
    p.add_argument("plan"); p.add_argument("-o", "--out", required=True)
    p = sub.add_parser("check")
    p.add_argument("note"); p.add_argument("--strokes")
    a = ap.parse_args()
    {"plan": cmd_plan, "build": cmd_build, "check": cmd_check}[a.cmd](a)


if __name__ == "__main__":
    main()
