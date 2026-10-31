# BOOX Bullet Journal

Vorlagen-PDF für ein Bullet Journal auf dem BOOX-Reader. Alle Seiten sind einzeln
und ohne Links, damit man sie auf dem BOOX in ein eigenes Notizbuch übernehmen
und beliebig oft kopieren kann. Aufbau nach Ryder Carrolls Bullet-Journal-Methode.

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
