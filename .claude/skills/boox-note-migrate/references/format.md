# BOOX-.note-Format (aus Notizen von einem Go 10.3, Stand Nov. 2026)

Nicht offiziell dokumentiert, durch Analyse ermittelt. Zum Untersuchen: entpacken und `scripts/pb.py` (`parse`) auf die Protobuf-Dateien anwenden.

## Archiv

ZIP mit einem Ordner `<Dokument-UUID>/`, Verzeichniseinträge unkomprimiert, Dateien deflate.

| Pfad | Inhalt |
|---|---|
| `note/pb/note_info` | Protobuf, ein Feld 1 mit der Dokument-Nachricht (siehe unten) |
| `virtual/page/pb/<id>` | eine Nachricht je Seite: Seite ↔ PDF-Seite |
| `pageModel/pb/<id>` | eine Nachricht je Seite (2 Ebenen-JSON, 3 aktuelle Ebene, 4 Seitenname, 7 Seitenrechteck) plus eine mit der Dokument-UUID. Ebenen und Name müssen je Seite erhalten bleiben: Striche auf einer Ebene, die die Seite nicht hat, zeigt das Gerät nicht an |
| `virtual/doc/pb/<Dokument-UUID>` | Dokumentansicht; Feld 4 = aktuelle Seite, Feld 9 = Vorlage für neue leere Seiten |
| `extra/pb/extra` | Feld 4 = Dokument-UUID |
| `resource/content/<Name>.pdf` | das Vorlagen-PDF |
| `resource/pb/<uuid>#<ts>` | leere Markierungsdatei |
| `template/json/<id>.template_json`, gespiegelt unter `document/<Dokument-UUID>/template/json/` | Layout-Vorlage leerer Seiten |
| `shape/<Seiten-ID>#<Gruppen-UUID>#<ts>.zip` | ZIP mit einer Datei gleichen Namens (ohne .zip): Shape-Liste der Seite |
| `point/<Seiten-ID>/<Seiten-ID>#<Punkte-UUID>#points` | Punktdaten der Shapes |
| `stash/...` | Radier- und Undo-Verlauf, wird nicht übernommen |

## note_info (Felder der inneren Nachricht)

1 Dokument-UUID · 2/3 erstellt/geändert (ms) · 6 Titel · 12 JSON mit `pageInfoMap` (je Seiten-ID: `layerList`, `currentLayerId`, optional `title` = Seitenname, Breite/Höhe; leere Seiten 1860×2480, PDF-Seiten 2100×2732) · 14 JSON mit Gerät und Größe · 19 zuletzt geöffnete Seite (0-basiert) · 20 JSON `{"pageNameList": [...]}` = Seitenreihenfolge. Felder 28, 32, 39 sind unbekannt und werden unverändert übernommen.

## virtual/page (je Seite)

1 Seiten-ID · 2/3 Zeitstempel · 4 float32 little-endian = Seitennummer (1-basiert) · 6 Seitenrechteck in Notiz-Einheiten (PDF-Seite: 2100 × 2100·h/b) · 7 dasselbe auf Bildschirm-Seitenverhältnis 3:4 erweitert und vertikal zentriert · 8 PDF-MediaBox in pt · 9 `import_pdf` oder `geo_layout` (leere Seite) · 10 `document/<Dokument-UUID>/resource/content/<pdf>` bzw. Vorlagenpfad · 11 JSON `{"pageIndex": n, "pageReferenceId": "pdf-<Objektnummer>-0"}`. Die Objektnummer ist die des Seitenobjekts im PDF (in Seitenbaum-Reihenfolge).

## Shapes (je Eintrag in der Shape-Liste)

1 Shape-ID · 2/3 Zeitstempel · 5 float32 Stiftbreite · 6 Ebene (fehlt = 0) · 7 JSON-Begrenzungsrechteck (nach Matrix) · 8 optional JSON `{"values": [a,b,c,d,e,f,0,0,1]}` (Android-Matrix: x' = a·x + b·y + c, y' = d·x + e·y + f) für verschobene/skalierte Shapes · 10 optional Link: JSON mit `docBean` (documentId, pageId, pageIndex 0-basiert, title, path) · 11 JSON Stiftparameter · 12 Typ (22 Strich, 5 Linie, 2 Kreis, 15 Pfeil/Linie, 33 Link-Symbol, 60 weitere) · 16 Punkte-UUID · 18 Gruppen-UUID (= Mitte des Zip-Namens).

## Punktedatei

Big-endian. Kopf: 4 Byte Version, 36 Byte Seiten-ID, 36 Byte Punkte-UUID. Dann Blöcke je Shape: 4 Byte, danach je Punkt 16 Byte (`float x, float y, int16, int16 Druck, uint32 Zeit`). Am Ende das Verzeichnis: je Shape 36 Byte Shape-ID, `uint32 Offset`, `uint32 Länge` (Länge inkl. der 4 Byte). Die letzten 4 Byte geben den Offset des Verzeichnisses an. Die Koordinaten liegen im Rechteck aus `virtual/page` Feld 6 (y nach unten), die Matrix aus Feld 8 kommt noch dazu.
