# BOOX Bullet Journal

Vorlagen-PDF für ein Bullet Journal auf dem BOOX-Reader, Aufbau nach Ryder
Carrolls Bullet-Journal-Methode. Das PDF in der Notes-App öffnen (nicht als
Vorlage importieren); weitere Seiten mit „Page+“ einfügen.

Navigation über PDF-Links: Index (mit vorbelegten Einträgen für Future Log und
alle Monate) ↔ Future Log, Future-Log-Monatsbalken → Monat, Monatsseiten mit ‹ ›
sowie FUTURE LOG und INDEX, Daily → FUTURE LOG und INDEX, Woche/Tracker → INDEX.
In BOOX Notes bleiben die Links korrekt, auch wenn Seiten eingefügt werden
(getestet).

## Inhalt von `BuJo-Seiten-2026-11_2027-12.pdf`

| Seiten | Inhalt |
|---|---|
| 1 | Index (Thema / Seiten) |
| 2–6 | Future Log, drei Monate pro Seite |
| 7–20 | Monatsseiten Nov 2026 – Dez 2027 (Tagesliste mit KW + Punktraster) |
| 21 | Wochenseite (Aufgaben, Mo–So, Next) |
| 22 | Daily / Collection (Punktraster) |
| 23 | Gewohnheits-Tracker (Tage 1–31) |

Format 458,88 × 597,12 pt (3:4).

## Neu erzeugen

Zeitraum über `startYear`/`startMonth`/`endYear`/`endMonth` oben in
`generate_bujo.swift` einstellen, dann:

```bash
swift generate_bujo.swift
```

Benötigt nur macOS (CoreGraphics/CoreText), keine weiteren Abhängigkeiten.
