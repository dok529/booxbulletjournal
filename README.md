# BOOX Bullet Journal

Vorlagen-PDF für ein Bullet Journal auf dem BOOX-Reader, Aufbau nach Ryder
Carrolls Bullet-Journal-Methode. Das PDF in der Notes-App öffnen (nicht als
Vorlage importieren); weitere Seiten mit „Page+“ einfügen.

Navigation über PDF-Links:

- Deckblatt: Monatsleiste → Monat
- Index: vorbelegte Einträge für Future Log, alle Monate und die Wochen
- Future Log: Monatsbalken → Monat, INDEX
- Monat: ‹ › Vor-/Folgemonat, KW-Badges → Woche, FUTURE LOG, INDEX
- Woche: ‹ › Vor-/Folgewoche, Monatsknöpfe (z. B. DEZ, JAN) → Monat, INDEX
- Wochen-Daily: KW → Woche, Monatsknöpfe → Monat, FUTURE LOG, INDEX
- Daily: FUTURE LOG, INDEX · Gewohnheit: KW-Beschriftungen → Woche, INDEX
- Alle Seiten außer Deckblatt und Gewohnheit: Knopf ✓ unten rechts → Gewohnheitsseite

In BOOX Notes bleiben die Links korrekt, auch wenn Seiten eingefügt werden
(getestet).

## Inhalt von `BuJo-2027 V1.pdf`

| Seiten | Inhalt |
|---|---|
| 1 | Deckblatt mit Zeitraum und Monatsleiste |
| 2 | Index (Thema / Seiten) |
| 3–7 | Future Log, drei Monate pro Seite |
| 8–21 | Monatsseiten Nov 2026 – Dez 2027 (Tagesliste mit KW + Punktraster) |
| 22–145 | KW 44/2026 – KW 52/2027, je zwei Seiten: Wochenseite (Aufgaben, Mo–So mit Datum, Next) und Wochen-Daily (Datumsbereich, Punktraster) |
| 146 | Daily / Collection (Punktraster) |
| 147 | Gewohnheits-Tracker: eine Seite pro Gewohnheit (auf dem BOOX kopieren), alle Wochen des Zeitraums als Zeilen Mo–So |

Format 458,88 × 597,12 pt (3:4).

## Vorschau

| Deckblatt | Index | Future Log |
|:---:|:---:|:---:|
| <img src="previews/deckblatt.png" width="260" alt="Deckblatt"> | <img src="previews/index.png" width="260" alt="Index"> | <img src="previews/future-log.png" width="260" alt="Future Log"> |
| **Monat** | **Woche** | **Wochen-Daily** |
| <img src="previews/monat.png" width="260" alt="Monatsseite"> | <img src="previews/woche.png" width="260" alt="Wochenseite"> | <img src="previews/wochen-daily.png" width="260" alt="Wochen-Daily"> |
| **Daily / Collection** | **Gewohnheit** | |
| <img src="previews/daily.png" width="260" alt="Daily / Collection"> | <img src="previews/gewohnheit.png" width="260" alt="Gewohnheits-Tracker"> | |

## Neu erzeugen

Zeitraum über `startYear`/`startMonth`/`endYear`/`endMonth` oben in
`generate_bujo.swift` einstellen, dann PDF und Vorschaubilder erzeugen:

```bash
swift generate_bujo.swift && swift render_previews.swift
```

Nach jeder Layout-Änderung beide Befehle ausführen und `previews/` mit
committen, damit die Vorschau aktuell bleibt.

Benötigt nur macOS (CoreGraphics/CoreText), keine weiteren Abhängigkeiten.
