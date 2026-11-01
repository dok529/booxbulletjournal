# BOOX Bullet Journal

Vorlagen-PDF für ein Bullet Journal auf dem BOOX-Reader, Aufbau nach Ryder
Carrolls Bullet-Journal-Methode. Das PDF in der Notes-App öffnen (nicht als
Vorlage importieren).

Zusätzliche Seiten nicht über „Page+“ einfügen, sondern in der
Seitenübersicht kopieren: Nach jeder Wochenseite folgen zwei Wochen-Dailys.
Bevor die letzte freie Daily der Woche beschrieben wird, diese Daily in der
Seitenübersicht kopieren. So liegt immer eine leere Daily mit allen Links
bereit. Genauso eine Gewohnheitsseite pro Gewohnheit und weitere
Collections kopieren.

Navigation über PDF-Links:

- Deckblatt: Monatsleiste → Monat
- Index: vorbelegte Einträge für Future Log, alle Monate, die Wochen, die Gewohnheiten und die Collections
- Future Log: Monatsbalken → Monat, INDEX
- Monat: ‹ › Vor-/Folgemonat, KW-Badges → Woche, FUTURE, INDEX
- Woche: ‹ › Vor-/Folgewoche, Monatsknöpfe (z. B. DEZ, JAN) → Monat, FUTURE, INDEX
- Wochen-Daily: KW → Woche, Monatsknöpfe → Monat, FUTURE, INDEX
- Gewohnheit: KW-Beschriftungen → Woche, INDEX
- Collection: FUTURE, INDEX
- Alle Seiten außer Deckblatt und Gewohnheit: Knopf ✓ unten rechts → Gewohnheitsseite

In BOOX Notes bleiben die Links korrekt, auch wenn Seiten eingefügt oder
kopiert werden; kopierte Seiten behalten ihre eigenen Links (getestet).

## Inhalt von `BuJo-2027 V1.pdf`

| Seiten | Inhalt |
|---|---|
| 1 | Deckblatt mit Zeitraum und Monatsleiste |
| 2 | Index (Thema / Seiten) |
| 3–7 | Future Log, drei Monate pro Seite |
| 8–21 | Monatsseiten Nov 2026 – Dez 2027 (Tagesliste mit KW + Punktraster) |
| 22–207 | KW 44/2026 – KW 52/2027, je drei Seiten: Wochenseite (Aufgaben, Mo–So mit Datum, Next) und zwei Wochen-Dailys (Datumsbereich, Punktraster) |
| 208 | Gewohnheits-Tracker: eine Seite pro Gewohnheit (auf dem BOOX kopieren), alle Wochen des Zeitraums als Zeilen Mo–So |
| 209–210 | Collections: leere Schreiblinie für das Thema, Punktraster |

Format 458,88 × 597,12 pt (3:4).

## Vorschau

| Deckblatt | Index | Future Log |
|:---:|:---:|:---:|
| <img src="previews/deckblatt.png" width="260" alt="Deckblatt"> | <img src="previews/index.png" width="260" alt="Index"> | <img src="previews/future-log.png" width="260" alt="Future Log"> |
| **Monat** | **Woche** | **Wochen-Daily** |
| <img src="previews/monat.png" width="260" alt="Monatsseite"> | <img src="previews/woche.png" width="260" alt="Wochenseite"> | <img src="previews/wochen-daily.png" width="260" alt="Wochen-Daily"> |
| **Gewohnheit** | **Collection** | |
| <img src="previews/gewohnheit.png" width="260" alt="Gewohnheits-Tracker"> | <img src="previews/collection.png" width="260" alt="Collection"> | |

## Neu erzeugen

Zeitraum über `startYear`/`startMonth`/`endYear`/`endMonth` oben in
`generate_bujo.swift` einstellen, dann PDF und Vorschaubilder erzeugen:

```bash
swift generate_bujo.swift && swift render_previews.swift
```

Nach jeder Layout-Änderung beide Befehle ausführen und `previews/` mit
committen, damit die Vorschau aktuell bleibt.

Benötigt nur macOS (CoreGraphics/CoreText), keine weiteren Abhängigkeiten.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Gilt für Skripte und das erzeugte PDF.
