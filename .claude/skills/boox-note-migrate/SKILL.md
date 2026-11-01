---
name: boox-note-migrate
description: Überträgt die Handschrift einer BOOX-Notiz (.note, z. B. „BuJo-2027 V1.note“) auf eine neue Version des Vorlagen-PDFs und erzeugt daraus eine neue .note-Datei. Verwende diesen Skill immer, wenn eine .note-Datei auf ein neues oder geändertes PDF umziehen soll – etwa „migriere die Note auf V3“, „übertrag meine Einträge ins neue BuJo-PDF“, „Inhalte der alten Notiz in die neue Version“, „neue Note-Datei mit dem aktuellen PDF“ – auch wenn das Wort „Skill“ oder „migrieren“ nicht fällt. Nicht zum bloßen Ansehen/Lesen einer Notiz.
---

# BOOX-Notiz auf neue PDF-Version migrieren

Eine BOOX-Notiz, die aus einem PDF erstellt wurde, speichert die Handschrift als Vektorstriche je Seite, das PDF liegt nur als Hintergrund darin. Ändert sich das PDF (neue Seiten, anderes Layout), überträgt dieser Skill die Striche Seite für Seite auf das neue PDF. Das Ergebnis ist eine neue .note, die der Nutzer auf das Gerät kopiert. Gerendert wird nichts: Die Striche bleiben editierbare Vektoren.

Die Skripte liegen in `scripts/` (Pfad relativ zu diesem Skill). Python immer mit `-I` starten, Arbeitsdateien in den Scratchpad legen (`--work`), nie neben die Notiz.

## Ablauf

### 1. Eingaben klären

- **Alte Notiz**: die .note mit der Handschrift.
- **Neues PDF**: Prüfe mit `git status`/`git log`, ob das PDF dem aktuellen Stand entspricht. Ein uncommittetes oder gerade neu erzeugtes PDF kann sich während der Arbeit noch ändern. Kopiere es deshalb vor `plan` in den Scratchpad und arbeite mit dieser Kopie. Prüfe vor dem Abschluss, dass sie noch der Datei im Repo entspricht (`cmp`). Hat sich das PDF zwischendurch geändert, plane neu und sag es dem Nutzer.
- **Ausgabe**: standardmäßig `<PDF-Name ohne .pdf>.note` neben dem PDF. Bestehende Dateien werden nie überschrieben (`build` bricht ab).

### 2. Plan erzeugen

```bash
python3 -I scripts/notemig.py --work <scratch> plan ALT.note <scratch>/NEU.pdf -o <scratch>/plan.json
```

`plan` ordnet jede alte Seite über ihre PDF-Überschrift (erste Textzeile) einer neuen PDF-Seite zu. Auf dem BOOX kopierte Seiten (mehrere Notizseiten mit derselben Vorlagenseite) werden zu Kopien der neuen Seite. Gibt es im neuen PDF schon eine freie gleichnamige Folgeseite, z. B. eine zweite Daily, landen sie dort. Kopierte Seiten ohne Striche entfallen, bleiben aber Link-Ziele.

Die Ausgabe listet alle Seiten mit Strichen. Prüfe sie und lege sie dem Nutzer vor:
- **„[ähnlich]“**: Die Überschrift hat sich geändert, die Zuordnung ist nur geraten. Bestätigen lassen.
- **„OHNE ZIEL“**: Striche auf einer leeren Seite ohne PDF-Vorlage (auf dem Gerät eingefügt). Frag, wohin sie sollen, z. B. auf eine Collection.
- **„NICHT ÜBERNOMMEN“**: alte Vorlagenseite ohne Entsprechung im neuen PDF. Frag nach.

### 3. Layoutänderungen prüfen

Gleiche Überschrift heißt nicht gleiches Layout. Baue einmal ohne Transformationen in den Scratchpad, erzeuge Kontrollbilder (siehe Schritt 5) und vergleiche sie mit der alten Notiz auf der alten Vorlage. Typische Fälle: Im Index kommt ein vorbelegter Eintrag dazu und die Handschrift liegt dann darauf, oder Zeilen und Raster verschieben sich. Die Maße stehen in `generate_bujo.swift` und lassen sich in Notiz-Einheiten umrechnen (siehe unten). Frag den Nutzer, ob verschoben oder 1:1 übernommen werden soll. Entscheide das nicht stillschweigend: Es ist seine Handschrift.

### 4. Plan anpassen und bauen

`plan.json` direkt bearbeiten:

```json
{
 "title": "BuJo-2027 V3",
 "pages": [
  {"pdf": 1, "from": "<alte Seiten-ID>", "transform": {"dy": 85.17}},
  {"pdf": 146, "from": "<ID der leeren Seite>"}
 ],
 "aliases": {"<kopierte Seite ohne Striche>": "<ihr Original>"},
 "unplaced": [],
 "drop": []
}
```

- `pages`: die neue Notiz in Seitenreihenfolge. `pdf` ist der 0-basierte PDF-Index, `from` die alte Seite, deren Striche hierher kommen. Für eine zusätzliche Kopie einer Vorlagenseite einen weiteren Eintrag mit derselben `pdf` einfügen.
- `transform` (optional): `scale`, `dx`, `dy` in Notiz-Einheiten der neuen Seite. `region` `[links, oben, rechts, unten]` in alten Koordinaten beschränkt die Transformation auf Striche, deren Mitte darin liegt, z. B. nur die linke Index-Spalte. Die Umrechnung von leeren Seiten (1860 breit) auf PDF-Seiten (2100 breit) macht `build` selbst.
- `unplaced` muss leer sein. Jede Seite daraus bekommt ein Ziel in `pages` oder kommt mit Zustimmung des Nutzers in `drop`.
- `_alt`/`_neu` sind nur Beschriftungen.

```bash
python3 -I scripts/notemig.py --work <scratch> build <scratch>/plan.json -o "<Ziel>.note"
```

### 5. Prüfen

```bash
python3 -I scripts/notemig.py --work <scratch> check "<Ziel>.note" --strokes <scratch>/striche.txt
swift scripts/overlay.swift <scratch>/NEU.pdf <scratch>/striche.txt <scratch>/kontrolle
```

`check` prüft die Seiten-IDs, die PDF-Verweise, die Punktedateien und die Link-Ziele. `overlay.swift` legt die Striche rot über die PDF-Seiten. Sieh dir die Kontrollbilder der Seiten mit Strichen selbst an, verkleinert mit `sips -Z 900`. Sie dienen nur deiner Prüfung: Leg sie nicht ins Projekt und zeig sie nur, wenn der Nutzer danach fragt.

### 6. Berichten

Nenne die Zieldatei, die Seitenzahl und eine knappe Tabelle „alte Seite → neue Seite“ für die Seiten mit Strichen. Dazu jede Verschiebung oder Sonderbehandlung und die umgebogenen Links. Sag ausdrücklich, dass die Datei auf dem Gerät noch nicht getestet ist und die alte Notiz bis dahin bleiben sollte. Der Radier-Verlauf (`stash`) wird nicht übernommen. Die neue Notiz bekommt eine neue Dokument-ID und kollidiert daher nicht mit der alten.

## Datenschutz

Die Notiz enthält persönliche Einträge. Schreib keine Seiten-IDs, Inhalte oder Seitenzuordnungen einer konkreten Notiz in die Skripte oder in diesen Skill. Alles Notizspezifische gehört in `plan.json` im Scratchpad. Gib Inhalte der Handschrift in Antworten nur wieder, wenn der Nutzer danach fragt.

## Einheiten

PDF-Seiten haben in der Notiz die Breite aus `virtual/page` (bei diesem BuJo 2100). Ein PDF-Punkt entspricht also `2100 / 458.88 ≈ 4.576` Einheiten. Eine Index-Zeile (`rowH` aus `drawIndex`) ist etwa 18.61 pt hoch, das sind 85.17 Einheiten. Die y-Achse zeigt nach unten.

Wenn etwas am Format nicht passt (Fehlermeldung, neue Gerätesoftware), lies `references/format.md`.
