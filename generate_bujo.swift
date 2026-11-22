// Erzeugt ein Bullet-Journal-PDF für BOOX Notes: Deckblatt, Index, Regelseite, Future Log,
// Monatsseiten (Tagesliste + Punktraster), Wochen mit Wochen-Daily und Gewohnheitsseite.
// Navigationsknöpfe sind echte PDF-Links mit festen Seitenzielen; BOOX Notes
// passt sie an, wenn auf dem Gerät Seiten eingefügt werden.
// Aufruf: swift generate_bujo.swift [Ausgabe.pdf]

import Foundation
import CoreGraphics
import CoreText
import PDFKit

// MARK: - Einstellungen

let startYear = 2026, startMonth = 11
let endYear = 2027, endMonth = 12
let futureExtraMonths = 3   // Future Log reicht so viele Monate über das Ende hinaus (ohne Monatsseite)
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "BuJo-2027 V3.pdf"

// Seitenformat wie der Original-Planer (OnPlanners, vertikal)
let W: CGFloat = 458.88, H: CGFloat = 597.12
let margin: CGFloat = 16
let dotSpacing: CGFloat = 14.173 // 5 mm

// Kopfbereich (von oben): Mitte der Überschrift, Trennlinie, Beginn des Inhalts
let headMid: CGFloat = 20, headRule: CGFloat = 34, contentTop: CGFloat = 40

let monthNames = ["JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI",
                  "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"]
let weekdayShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"] // Index = Calendar.weekday - 1

let dark = CGColor(gray: 0, alpha: 1)
let light = CGColor(gray: 0.91, alpha: 1)
let rule = CGColor(gray: 0, alpha: 1)
let black = CGColor(gray: 0, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

// MARK: - Zeichenhilfen (Koordinaten von oben links)

func font(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }

func line(_ text: String, _ f: CTFont, _ color: CGColor, kern: CGFloat = 0) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): kern,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }

/// Zeichnet Text; `x`/`yMid` = linker Rand bzw. vertikale Mitte (von oben gemessen).
func drawText(_ ctx: CGContext, _ l: CTLine, x: CGFloat, yMid: CGFloat, f: CTFont) {
    let capHeight = CTFontGetCapHeight(f)
    ctx.textPosition = CGPoint(x: x, y: H - yMid - capHeight / 2)
    CTLineDraw(l, ctx)
}

func drawCentered(_ ctx: CGContext, _ text: String, f: CTFont, color: CGColor, cx: CGFloat, yMid: CGFloat, kern: CGFloat = 0) {
    let l = line(text, f, color, kern: kern)
    drawText(ctx, l, x: cx - (width(l) - kern) / 2, yMid: yMid, f: f)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: H - y - h, width: w, height: h) }

func strokeLine(_ ctx: CGContext, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
    ctx.move(to: CGPoint(x: x1, y: H - y1))
    ctx.addLine(to: CGPoint(x: x2, y: H - y2))
    ctx.strokePath()
}

func pill(_ ctx: CGContext, _ r: CGRect, radius: CGFloat) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

// MARK: - Links (werden beim Zeichnen gesammelt und am Ende per PDFKit eingefügt)

var links: [(page: Int, rect: CGRect, target: Int)] = []
var currentPage = 0
var habitInNav = true   // Gewohnheits-Knopf ✓ als letzter Knopf in der Kopfzeile (pro Seite in page() gesetzt)
let habitMark = "✓"
var habitTarget = 0     // Gewohnheitsseite, auf die ✓ zeigt: die des Jahres der Seite (pro Seite gesetzt)

func link(_ r: CGRect, to target: Int) { links.append((currentPage, r, target)) }

/// Navigationsknöpfe rechts in der Kopfzeile, von links nach rechts angeordnet, ggf. mit Gewohnheits-Knopf am Ende.
/// Gibt den linken Rand des ersten Knopfs zurück.
@discardableResult
func navButtons(_ ctx: CGContext, _ items: [(label: String, target: Int)], minWidth: CGFloat = 46) -> CGFloat {
    let items = habitInNav ? items + [(habitMark, habitTarget)] : items
    let f = font("AvenirNext-DemiBold", 7.5)
    let h: CGFloat = 17, gap: CGFloat = 5
    let widths = items.map { $0.label.count <= 1 ? 20 : max(minWidth, width(line($0.label, f, white, kern: 1)) + 16) }
    var x = W - margin - widths.reduce(0, +) - gap * CGFloat(items.count - 1)
    let left = x
    for (item, w) in zip(items, widths) {
        let r = rect(x, headMid - h / 2, w, h)
        ctx.setFillColor(dark)
        pill(ctx, r, radius: 3)
        if item.label == habitMark {
            checkMark(ctx, r)
        } else {
            drawCentered(ctx, item.label, f: item.label.count <= 1 ? font("AvenirNext-Bold", 16) : f,
                         color: white, cx: r.midX, yMid: headMid, kern: item.label.count <= 1 ? 0 : 1)
        }
        link(r, to: item.target)
        x += w + gap
    }
    return left
}

// MARK: - Monatsseite

var cal = Calendar(identifier: .iso8601)
cal.locale = Locale(identifier: "de_DE")

func drawMonth(_ ctx: CGContext, index i: Int) {
    let (year, month) = months[i]
    let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
    let days = cal.range(of: .day, in: .month, for: first)!.count
    habitTarget = trackerPage(forYear: year)

    // Kopf: Monat und Jahr als Überschrift, rechts Navigation
    let titleFont = font("AvenirNext-Regular", 18)
    drawText(ctx, line("\(monthNames[month - 1]) \(year)", titleFont, black, kern: 1.5), x: margin, yMid: headMid, f: titleFont)
    var nav: [(label: String, target: Int)] = []
    if i > 0 { nav.append(("‹", monthPage(i - 1))) }
    if i < months.count - 1 { nav.append(("›", monthPage(i + 1))) }
    nav += [("FUTURE", futurePage(forMonth: i)), ("INDEX", indexPage)]
    navButtons(ctx, nav)

    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)

    // Linke Spalte: ein Eintrag pro Tag
    let listX = margin, listW: CGFloat = 200
    let top = contentTop, bottom = H - margin
    let rowH = (bottom - top) / CGFloat(days)
    let diam = min(rowH - 3, 14)
    let numFont = font("AvenirNext-Medium", 7.5)
    let dayFont = font("Menlo-Regular", 7.5)
    let kwFont = font("AvenirNext-DemiBold", 7)

    for d in 1...days {
        let date = cal.date(from: DateComponents(year: year, month: month, day: d))!
        let wd = cal.component(.weekday, from: date) // 1 = So, 2 = Mo, … 7 = Sa
        let weekend = wd == 1 || wd == 7
        let y = top + CGFloat(d - 1) * rowH
        let mid = y + rowH / 2

        if weekend {
            ctx.setFillColor(light)
            ctx.fill(rect(listX, y, listW, rowH))
        }
        ctx.setStrokeColor(rule)
        ctx.setLineWidth(0.5)
        strokeLine(ctx, listX, y + rowH, listX + listW, y + rowH)

        // Tagesnummer im eckigen Kasten wie die KW-Knöpfe: Werktage gefüllt, Wochenende umrandet
        let circle = rect(listX + 1, mid - diam / 2, diam, diam)
        if weekend {
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(0.8)
            ctx.addPath(CGPath(roundedRect: circle.insetBy(dx: 0.4, dy: 0.4), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.strokePath()
        } else {
            ctx.setFillColor(dark)
            pill(ctx, circle, radius: 3)
        }
        drawCentered(ctx, String(d), f: numFont, color: weekend ? dark : white, cx: circle.midX, yMid: mid)
        drawText(ctx, line(weekdayShort[wd - 1], dayFont, black), x: listX + diam + 4, yMid: mid, f: dayFont)

        if wd == 2 || d == 1 {
            // KW-Badge in Größe der Tageskreise, Ecken wie die KW-Spaltenköpfe; verlinkt auf die Wochenseite
            let kw = cal.component(.weekOfYear, from: date)
            let bw: CGFloat = 17
            ctx.setFillColor(dark)
            pill(ctx, rect(listX + listW - bw - 1, mid - diam / 2, bw, diam), radius: 3)
            drawCentered(ctx, String(kw), f: kwFont, color: white, cx: listX + listW - bw / 2 - 1, yMid: mid)
            link(rect(listX + listW - bw - 5, y, bw + 5, rowH), to: weekPage(weekIndex(of: date)))
        }
    }
    ctx.setStrokeColor(rule)
    ctx.setLineWidth(0.5)
    strokeLine(ctx, listX, top, listX + listW, top)

    // Rechts neben der Tagesliste (Alastair): Freitext, dann die leere Spalte und je KW eine Spalte am rechten Rand
    let last = cal.date(from: DateComponents(year: year, month: month, day: days))!
    var mondays: [Date] = []
    var w = cal.dateInterval(of: .weekOfYear, for: first)!.start
    while w <= last {
        mondays.append(w)
        w = cal.date(byAdding: .day, value: 7, to: w)!
    }
    let kwCols = mondays.map { mo in
        AlastairCol(w: dotSpacing, grey: nil, head: pillHead(String(cal.component(.weekOfYear, from: mo)), target: weekPage(weekIndex(of: mo)), font: kwFont))
    }
    let offen = AlastairCol(w: dotSpacing, grey: nil, head: offenHead)
    alastairBlock(ctx, [offen] + kwCols, left: false, x0: listX + listW + 12, x1: W - margin, top: top, headH: 16, bottom: bottom)
}

// MARK: - Alastair-Spaltenblock: Spalten links oder rechts vom Fließtext

struct AlastairCol {
    let w: CGFloat
    let grey: Bool?                       // nil: nach Abstand zum Text (am Text grau, dann abwechselnd)
    let head: (CGContext, CGRect) -> Void // Kopf in der Spalte zeichnen
}

/// Spalten in Leserichtung (links → rechts). Bei left stehen sie am linken Rand, sonst am rechten.
/// Zeichnet Grau, Köpfe und das Punktraster (auf den Spaltengrenzen); gibt den Textbereich zurück.
@discardableResult
func alastairBlock(_ ctx: CGContext, _ cols: [AlastairCol], left: Bool, x0: CGFloat, x1: CGFloat, top: CGFloat, headH: CGFloat, bottom: CGFloat) -> (CGFloat, CGFloat) {
    let total = cols.reduce(0) { $0 + $1.w }
    let start = left ? snapUp(x0, gridX0) : snapDown(x1 - total, gridX0)   // Spaltengrenzen auf dem gemeinsamen Raster
    var x = start
    for (k, c) in cols.enumerated() {
        let d = left ? cols.count - 1 - k : k
        if c.grey ?? (d % 2 == 0) {
            ctx.setFillColor(light)
            ctx.fill(rect(x, top, c.w, bottom - top))
        }
        c.head(ctx, rect(x, top, c.w, headH))
        x += c.w
    }
    dots(ctx, x0: x0, y0: top + headH + 2, x1: x1, y1: bottom)
    return left ? (start + total, x1) : (x0, start)
}

func offenHead(_ ctx: CGContext, _ r: CGRect) {
    let b = CGRect(x: r.minX + 0.75, y: r.maxY - 2 - 12, width: r.width - 1.5, height: 12)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.8)
    ctx.addPath(CGPath(roundedRect: b.insetBy(dx: 0.4, dy: 0.4), cornerWidth: 3, cornerHeight: 3, transform: nil))
    ctx.strokePath()
}

func pillHead(_ text: String, target: Int?, font f: CTFont) -> (CGContext, CGRect) -> Void {
    return { ctx, r in
        let b = CGRect(x: r.minX + 0.75, y: r.maxY - 2 - 12, width: r.width - 1.5, height: 12)
        ctx.setFillColor(dark)
        pill(ctx, b, radius: 3)
        drawCentered(ctx, text, f: f, color: white, cx: b.midX, yMid: H - b.midY, kern: 0.6)
        if let t = target { link(b, to: t) }
    }
}

// MARK: - Weitere Seiten: Deckblatt, Index, Future Log, Gewohnheits-Tracker

let cTop = contentTop, cBottom = H - margin, cLeft = margin, cRight = W - margin
let gridDot = CGColor(gray: 0, alpha: 1)

func pageTitle(_ ctx: CGContext, _ title: String, writeLine: CGFloat = 0) {
    let f = font("AvenirNext-Regular", 18)
    let l = line(title, f, black, kern: 1.5)
    drawText(ctx, l, x: margin, yMid: headMid, f: f)
    if writeLine > 0 {
        let x0 = margin + width(l) + 8
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.6)
        strokeLine(ctx, x0, headMid + 8, x0 + writeLine, headMid + 8)
    }
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)
}

func label(_ ctx: CGContext, _ s: String, x: CGFloat, yMid: CGFloat, color: CGColor = dark) {
    let f = font("AvenirNext-DemiBold", 7.5)
    drawText(ctx, line(s, f, color, kern: 1.2), x: x, yMid: yMid, f: f)
}

// Gemeinsames Punktraster für alle Seiten: Punkte bei gridX0 + n·dotSpacing und gridY0 + n·dotSpacing,
// damit sie beim Blättern an derselben Stelle bleiben
let gridX0 = margin, gridY0 = contentTop + 24 + dotSpacing / 2 - 2 * dotSpacing

func snapUp(_ v: CGFloat, _ o: CGFloat) -> CGFloat { o + (((v - o) / dotSpacing) - 0.001).rounded(.up) * dotSpacing }
func snapDown(_ v: CGFloat, _ o: CGFloat) -> CGFloat { o + (((v - o) / dotSpacing) + 0.001).rounded(.down) * dotSpacing }

/// Punkte des gemeinsamen Rasters innerhalb des Rechtecks
func dots(_ ctx: CGContext, x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) {
    dotGrid(ctx, x0: snapUp(x0, gridX0), x1: snapDown(x1, gridX0), y0: snapUp(y0, gridY0), y1: snapDown(y1, gridY0))
}

/// Punktraster als PDF-Kachelmuster statt Einzelpunkten (kleinere Datei, schnelleres Blättern).
/// x0/y0 = erster Punkt, x1/y1 = letzter Punkt (Koordinaten von oben links), Abstand dotSpacing.
func dotGrid(_ ctx: CGContext, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat) {
    guard x1 >= x0, y1 >= y0 else { return }
    var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, c in
        c.setFillColor(gridDot)
        c.fillEllipse(in: CGRect(x: dotSpacing / 2 - 0.65, y: dotSpacing / 2 - 0.65, width: 1.3, height: 1.3))
    }, releaseInfo: nil)
    let m = CGAffineTransform(translationX: x0 - dotSpacing / 2, y: H - y1 - dotSpacing / 2)
    guard let pattern = CGPattern(info: nil, bounds: CGRect(x: 0, y: 0, width: dotSpacing, height: dotSpacing), matrix: m,
                                  xStep: dotSpacing, yStep: dotSpacing, tiling: .noDistortion, isColored: true,
                                  callbacks: &callbacks) else { return }
    ctx.saveGState()
    ctx.setFillColorSpace(CGColorSpace(patternBaseSpace: nil)!)
    var alpha: CGFloat = 1
    ctx.setFillPattern(pattern, colorComponents: &alpha)
    ctx.fill(rect(x0 - 0.7, y0 - 0.7, x1 - x0 + 1.4, y1 - y0 + 1.4))
    ctx.restoreGState()
}

// 0) Deckblatt: Titel + Zeitraum, unten alle Monate nach Jahren als Links
func drawCover(_ ctx: CGContext) {
    let f = font("AvenirNext-Regular", 40)
    drawText(ctx, line("BULLET", f, black, kern: 4), x: margin, yMid: 90, f: f)
    drawText(ctx, line("JOURNAL", f, black, kern: 4), x: margin, yMid: 140, f: f)
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, 172, W - margin, 172)
    let first = months[0], last = months[months.count - 1]
    let pf = font("AvenirNext-Medium", 10)
    let period = "\(monthNames[first.month - 1]) \(first.year) – \(monthNames[last.month - 1]) \(last.year)"
    drawText(ctx, line(period, pf, dark, kern: 2.5), x: margin, yMid: 190, f: pf)

    // Monatsleiste: eine Zeile pro Jahr, Monate an fester Position Jan–Dez
    let years = Array(Set(months.map { $0.year })).sorted()
    let bf = font("AvenirNext-DemiBold", 7.5)
    let gap: CGFloat = 4, bw = (W - 2 * margin - 11 * gap) / 12, bh: CGFloat = 18
    var y = H - margin - CGFloat(years.count) * 40 + 8
    for yr in years {
        label(ctx, String(yr), x: margin, yMid: y - 10)
        for (i, mo) in months.enumerated() where mo.year == yr {
            let r = rect(margin + CGFloat(mo.month - 1) * (bw + gap), y, bw, bh)
            ctx.setFillColor(dark)
            pill(ctx, r, radius: 3)
            drawCentered(ctx, String(monthNames[mo.month - 1].prefix(3)), f: bf, color: white, cx: r.midX, yMid: y + bh / 2, kern: 0.8)
            link(r, to: monthPage(i))
        }
        y += 40
    }
}

// 1) Index: zwei Spalten mit Thema + Seiten
func drawIndex(_ ctx: CGContext) {
    pageTitle(ctx, "INDEX")
    navButtons(ctx, [("FUTURE", futurePage(forMonth: 0))])
    let gap: CGFloat = 16, colW = (cRight - cLeft - gap) / 2, headH: CGFloat = 20
    let rows = 28, rowH = (cBottom - cTop - headH) / CGFloat(rows)
    for c in 0..<2 {
        let x = cLeft + CGFloat(c) * (colW + gap)
        label(ctx, "THEMA", x: x, yMid: cTop + headH / 2)
        let sf = font("AvenirNext-DemiBold", 7.5)
        let sl = line("SEITEN", sf, dark, kern: 1.2)
        drawText(ctx, sl, x: x + colW - width(sl), yMid: cTop + headH / 2, f: sf)
        ctx.setStrokeColor(dark); ctx.setLineWidth(0.8)
        strokeLine(ctx, x, cTop + headH, x + colW, cTop + headH)
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
        for r in 1...rows { let y = cTop + headH + CGFloat(r) * rowH; strokeLine(ctx, x, y, x + colW, y) }
        strokeLine(ctx, x + colW - 44, cTop + headH, x + colW - 44, cBottom)
    }

    // Vorbelegt: Regeln, Future Log und alle Monate als Links. Ohne Seitenzahl, weil sich die
    // Seitenzahlen auf dem BOOX durch eingefügte Seiten verschieben.
    let entries = [("Regeln", rulesPage), ("Jahresziele \(endYear)", goalsPage), ("Future Log", futurePage(forMonth: 0))]
        + months.indices.map { ("\(monthNames[months[$0].month - 1].capitalized) \(months[$0].year)", monthPage($0)) }
        + [("Wochen (ab KW \(cal.component(.weekOfYear, from: weeks[0])))", weekPage(0)),
           ("Gewohnheiten", trackerPage), ("Collections", collectionPage)]
    let ef = font("AvenirNext-Regular", 9.5)
    for (r, (text, target)) in entries.prefix(rows).enumerated() {
        let rowTop = cTop + headH + CGFloat(r) * rowH
        drawText(ctx, line(text, ef, black), x: cLeft + 2, yMid: rowTop + rowH / 2 + 1, f: ef)
        drawText(ctx, line("›", ef, dark), x: cLeft + colW - 44 - 10, yMid: rowTop + rowH / 2 + 1, f: ef)
        link(rect(cLeft, rowTop, colW - 44, rowH), to: target)
    }
}

// 2) Future Log nach der Alastair-Methode: ein Kalenderquartal pro Seite, links eine Spalte je Monat
//    (Bullet in die Spalte des Monats), rechts die Liste; nur Punktraster. Monatsknöpfe verlinken auf die Monatsseite.
func drawFuture(_ ctx: CGContext, page p: Int) {
    let group = futureGroups[p]
    let (fy, fm) = futureMonths[group.first!], (_, lm) = futureMonths[group.last!]
    let span = fm == lm ? monthNames[fm - 1] : "\(monthNames[fm - 1]) – \(monthNames[lm - 1])"
    habitTarget = trackerPage(forYear: min(fy, endYear))
    let tf = font("AvenirNext-Regular", 18), rf = font("AvenirNext-Medium", 8.5)
    let title = line("FUTURE LOG \(fy)", tf, black, kern: 1.5)
    drawText(ctx, title, x: margin, yMid: headMid, f: tf)
    drawText(ctx, line(span, rf, dark, kern: 0.8), x: margin + width(title) + 8, yMid: headMid + 1, f: rf)
    var nav: [(label: String, target: Int)] = []
    if p > 0 { nav.append(("‹", goalsPage + p)) }
    if p < futureCount - 1 { nav.append(("›", goalsPage + 2 + p)) }
    navButtons(ctx, nav + [("INDEX", indexPage)])
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)

    // Spalten links (Alastair): je Monat zwei Punktabstände, die leere Spalte am Text
    let pf = font("AvenirNext-DemiBold", 7)
    let monthCols = group.map { mi in
        AlastairCol(w: 2 * dotSpacing, grey: nil,
                    head: pillHead(String(monthNames[futureMonths[mi].month - 1].prefix(3)), target: mi < months.count ? monthPage(mi) : nil, font: pf))
    }
    let offen = AlastairCol(w: dotSpacing, grey: nil, head: offenHead)
    alastairBlock(ctx, monthCols + [offen], left: true, x0: cLeft, x1: cRight, top: cTop + 2, headH: 20, bottom: cBottom)
}

// 4) Gewohnheits-Tracker: eine Seite pro Gewohnheit und Kalenderjahr, alle Wochen des Jahres in zwei Spalten (Mo–So)
func drawTracker(_ ctx: CGContext, year yr: Int) {
    // Flacher Kopf mit kleiner Überschrift, damit mehr Platz für die Wochenzeilen bleibt
    let hMid: CGFloat = 14, hRule: CGFloat = 24, cBottom = H - 8
    let tf = font("AvenirNext-Regular", 11)
    let tl = line("GEWOHNHEIT", tf, black, kern: 1)
    drawText(ctx, tl, x: margin, yMid: hMid, f: tf)
    let bh: CGFloat = 15, bw: CGFloat = 46
    let br = rect(W - margin - bw, hMid - bh / 2, bw, bh)
    ctx.setFillColor(dark); pill(ctx, br, radius: 3)
    drawCentered(ctx, "INDEX", f: font("AvenirNext-DemiBold", 7.5), color: white, cx: br.midX, yMid: hMid, kern: 1)
    link(br, to: indexPage)
    let tx = margin + width(tl) + 8
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.6)
    strokeLine(ctx, tx, hMid + 5, tx + 190, hMid + 5)
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, hRule, W - margin, hRule)

    // Legende: eine durchgehende Schreibzeile
    label(ctx, "LEGENDE", x: cLeft, yMid: hRule + 13)
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
    strokeLine(ctx, cLeft + 50, hRule + 17, cRight, hRule + 17)

    // Alle Wochen (Montag), die mindestens einen Tag des Jahres enthalten, auf zwei Spalten verteilt
    let jan1 = cal.date(from: DateComponents(year: yr, month: 1, day: 1))!
    let dec31 = cal.date(from: DateComponents(year: yr, month: 12, day: 31))!
    var yearWeeks: [Date] = []
    var w = cal.dateInterval(of: .weekOfYear, for: jan1)!.start
    while w <= dec31 { yearWeeks.append(w); w = cal.date(byAdding: .day, value: 7, to: w)! }
    let perCol = (yearWeeks.count + 1) / 2
    let columns = [Array(yearWeeks[..<perCol]), Array(yearWeeks[perCol...])]
    let top = hRule + 22, yearH: CGFloat = 13, headH: CGFloat = 10, gap: CGFloat = 12
    let colW = (cRight - cLeft - gap) / 2, labW: CGFloat = 34
    let cw = (colW - labW) / 7, rh = (cBottom - top - yearH - headH) / CGFloat(perCol)
    let hf = font("Menlo-Bold", 6), nf = font("AvenirNext-Medium", 4.8), bf = font("AvenirNext-Bold", 4.8)
    let kf = font("AvenirNext-DemiBold", 6.5), yf = font("AvenirNext-DemiBold", 9)
    let outside = CGColor(gray: 0.82, alpha: 1)

    ctx.setFillColor(dark)
    pill(ctx, rect(cLeft, top, cRight - cLeft, yearH - 2), radius: 2.5)
    drawCentered(ctx, String(yr), f: yf, color: white, cx: (cLeft + cRight) / 2, yMid: top + (yearH - 2) / 2, kern: 2)
    for (col, rows) in columns.enumerated() {
        let bx = cLeft + CGFloat(col) * (colW + gap), x0 = bx + labW, gt = top + yearH
        for (k, l) in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated() {
            if k >= 5 {
                ctx.setFillColor(light)
                ctx.fill(rect(x0 + CGFloat(k) * cw, gt, cw, headH + CGFloat(rows.count) * rh))
            }
            drawCentered(ctx, l, f: hf, color: black, cx: x0 + (CGFloat(k) + 0.5) * cw, yMid: gt + headH / 2)
        }
        for (r, monday) in rows.enumerated() {
            let y = gt + headH + CGFloat(r) * rh
            drawText(ctx, line("KW \(cal.component(.weekOfYear, from: monday))", kf, dark, kern: 0.3), x: bx, yMid: y + rh / 2, f: kf)
            // Nur Wochen im Zeitraum haben eine Wochenseite
            if let wi = weeks.firstIndex(of: monday) { link(rect(bx, y, labW - 4, rh), to: weekPage(wi)) }
            for k in 0..<7 {
                let day = cal.date(byAdding: .day, value: k, to: monday)!
                let cell = rect(x0 + CGFloat(k) * cw, y, cw, rh)
                if cal.component(.year, from: day) != yr {
                    ctx.setFillColor(outside)
                    ctx.fill(cell)
                    continue
                }
                // Tageszahl klein oben links; am Monatsersten mit Monatskürzel und Stufenlinie
                let dn = cal.component(.day, from: day)
                if dn == 1 {
                    let mon = String(monthNames[cal.component(.month, from: day) - 1].prefix(3))
                    drawText(ctx, line("1. \(mon)", bf, black), x: cell.minX + 1.5, yMid: y + 3.8, f: bf)
                    ctx.setStrokeColor(black); ctx.setLineWidth(1.2)
                    strokeLine(ctx, cell.minX, y, cell.minX, y + rh)
                    strokeLine(ctx, cell.minX, y, x0 + 7 * cw, y)
                    if k > 0 { strokeLine(ctx, x0, y + rh, cell.minX, y + rh) }
                } else {
                    drawText(ctx, line(String(dn), nf, black), x: cell.minX + 1.5, yMid: y + 3.8, f: nf)
                }
            }
            ctx.setStrokeColor(rule); ctx.setLineWidth(0.4)
            strokeLine(ctx, bx, y + rh, x0 + 7 * cw, y + rh)
        }
        ctx.setStrokeColor(dark); ctx.setLineWidth(0.8)
        strokeLine(ctx, bx, gt + headH, x0 + 7 * cw, gt + headH)
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.3)
        for k in 0...7 {
            strokeLine(ctx, x0 + CGFloat(k) * cw, gt + headH, x0 + CGFloat(k) * cw, gt + headH + CGFloat(rows.count) * rh)
        }
    }
}

// MARK: - Gewohnheits-Knopf: weißes Häkchen im dunklen Knopf, ohne Text

func checkMark(_ ctx: CGContext, _ r: CGRect) {
    ctx.saveGState()
    ctx.setStrokeColor(white); ctx.setLineWidth(1.7); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: r.minX + 6, y: r.midY + 0.5))
    ctx.addLine(to: CGPoint(x: r.minX + 9, y: r.minY + 4.5))
    ctx.addLine(to: CGPoint(x: r.maxX - 5.5, y: r.maxY - 4.5))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Wochen-Daily (nach jeder Wochenseite): Datumsbereich als Überschrift, freies Punktraster

func weekRange(_ days: [Date], shortYear: Bool = false) -> String {
    let df = DateFormatter()
    df.dateFormat = "dd.MM."
    let yf = DateFormatter()
    yf.dateFormat = shortYear ? "dd.MM.yy" : "dd.MM.yyyy"
    let sameYear = cal.component(.year, from: days[0]) == cal.component(.year, from: days[6])
    return "\((sameYear ? df : yf).string(from: days[0])) – \(yf.string(from: days[6]))"
}

/// Monate des Zeitraums, die eine Woche berührt, als Navigationsknöpfe
func monthButtons(_ days: [Date]) -> [(label: String, target: Int)] {
    var result: [(label: String, target: Int)] = []
    var seen = Set<Int>()
    for d in days {
        let ym = (cal.component(.year, from: d), cal.component(.month, from: d))
        if let mi = months.firstIndex(where: { $0 == ym }), seen.insert(mi).inserted {
            result.append((String(monthNames[ym.1 - 1].prefix(3)), monthPage(mi)))
        }
    }
    return result
}

/// Future-Log-Seite des ersten Monats im Zeitraum, den die Woche berührt
func futurePage(forWeek days: [Date]) -> Int {
    let mi = days.lazy.compactMap { d in
        months.firstIndex { $0 == (cal.component(.year, from: d), cal.component(.month, from: d)) }
    }.first ?? 0
    return futurePage(forMonth: mi)
}

func drawWeekDaily(_ ctx: CGContext, index wi: Int) {
    let monday = weeks[wi]
    let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    habitTarget = trackerPage(forYear: cal.component(.yearForWeekOfYear, from: monday))
    let nav = [("KW \(cal.component(.weekOfYear, from: monday))", weekPage(wi))] + monthButtons(days)
        + [("FUTURE", futurePage(forWeek: days)), ("INDEX", indexPage)]
    let navLeft = navButtons(ctx, nav, minWidth: 34)
    // Datumsbereich als Überschrift; bei voller Kopfzeile mit zweistelligem Jahr
    let tf = font("AvenirNext-Regular", 15)
    var title = line(weekRange(days), tf, black, kern: 1)
    if margin + width(title) > navLeft - 6 { title = line(weekRange(days, shortYear: true), tf, black, kern: 1) }
    drawText(ctx, title, x: margin, yMid: headMid, f: tf)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)
    dots(ctx, x0: cLeft, y0: cTop, x1: cRight, y1: cBottom)
}

// Collection: leere Schreiblinie für das Thema, Punktraster über die ganze Seite
func drawCollection(_ ctx: CGContext) {
    let navLeft = navButtons(ctx, [("FUTURE", futurePage(forMonth: 0)), ("INDEX", indexPage)])
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headMid + 8, navLeft - 16, headMid + 8)
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)
    dots(ctx, x0: cLeft, y0: cTop, x1: cRight, y1: cBottom)
}

// MARK: - Wochenseite (Alastair-Methode: Mo–So + Next links, Bullet-Spalte, Aufgaben rechts; Stil wie Monatsseite)

func drawWeek(_ ctx: CGContext, index wi: Int) {
    let monday = weeks[wi]
    let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    habitTarget = trackerPage(forYear: cal.component(.yearForWeekOfYear, from: monday))

    // Kopf: KW und Datumsbereich, rechts Navigation (Vor-/Folgewoche, berührte Monate, Index)
    let titleFont = font("AvenirNext-Regular", 18)
    let title = line("KW \(cal.component(.weekOfYear, from: monday))", titleFont, black, kern: 1.5)
    drawText(ctx, title, x: margin, yMid: headMid, f: titleFont)

    var nav: [(label: String, target: Int)] = []
    if wi > 0 { nav.append(("‹", weekPage(wi - 1))) }
    if wi < weeks.count - 1 { nav.append(("›", weekPage(wi + 1))) }
    nav += monthButtons(days)
    nav += [("FUTURE", futurePage(forWeek: days)), ("INDEX", indexPage)]
    let navLeft = navButtons(ctx, nav, minWidth: 30)

    // Datumsbereich; bei voller Kopfzeile (Jahreswechsel, zwei Monatsknöpfe) mit zweistelligem Jahr
    let rf = font("AvenirNext-Medium", 8.5), rx = margin + width(title) + 8
    var range = line(weekRange(days), rf, dark, kern: 0.5)
    if rx + width(range) > navLeft - 6 { range = line(weekRange(days, shortYear: true), rf, dark, kern: 0.5) }
    drawText(ctx, range, x: rx, yMid: headMid + 1, f: rf)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)

    // Spalten links (Alastair), je ein Punktabstand: Mo–So und die leere Spalte am Text;
    // leere Spalte grau, Wochenende weiß, Mo/Mi/Fr grau
    let top = contentTop, bottom = H - margin
    let dateFont = font("AvenirNext-Medium", 6)
    let dayCols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated().map { (i, label) in
        AlastairCol(w: dotSpacing, grey: [0, 2, 4].contains(i), head: { ctx, r in
            // Tagesknopf wie die KW- und Monatsknöpfe, darunter das Datum
            let b = CGRect(x: r.minX + 0.75, y: r.maxY - 2 - 12, width: r.width - 1.5, height: 12)
            ctx.setFillColor(dark)
            pill(ctx, b, radius: 3)
            drawCentered(ctx, label, f: font("AvenirNext-DemiBold", 6.5), color: white, cx: b.midX, yMid: top + 8)
            drawCentered(ctx, String(cal.component(.day, from: days[i])), f: dateFont, color: dark, cx: r.midX, yMid: top + 19)
        })
    }
    let offen = AlastairCol(w: dotSpacing, grey: true, head: offenHead)
    alastairBlock(ctx, dayCols + [offen], left: true, x0: margin, x1: W - margin, top: top, headH: 24, bottom: bottom)
}

// MARK: - Regelseite (nach dem Index): Bullets, was wohin, Migrationsrhythmus, Faustregeln

func textAttrs(_ f: CTFont, _ color: CGColor) -> [NSAttributedString.Key: Any] {
    [NSAttributedString.Key(kCTFontAttributeName as String): f,
     NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
}

/// Absatz mit **fett**-Markierung, umbrochen auf `w`; gibt die Höhe zurück.
@discardableResult
func paragraph(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, w: CGFloat) -> CGFloat {
    let regular = font("AvenirNext-Regular", 8), bold = font("AvenirNext-DemiBold", 8)
    let s = NSMutableAttributedString()
    for (i, part) in text.components(separatedBy: "**").enumerated() {
        s.append(NSAttributedString(string: part, attributes: textAttrs(i % 2 == 1 ? bold : regular, dark)))
    }
    var lineHeight: CGFloat = 10.5
    let style = withUnsafePointer(to: &lineHeight) {
        CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: $0)], 1)
    }
    s.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: style, range: NSRange(location: 0, length: s.length))
    let fs = CTFramesetterCreateWithAttributedString(s)
    let h = ceil(CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: w, height: .greatestFiniteMagnitude), nil).height)
    CTFrameDraw(CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: rect(x, y, w, h), transform: nil), nil), ctx)
    return h
}

/// Abschnittskopf (Versalien, gesperrt) mit Linie; gibt den Beginn des Inhalts zurück.
func section(_ ctx: CGContext, _ title: String, y: CGFloat) -> CGFloat {
    label(ctx, title, x: cLeft, yMid: y + 5)
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.5)
    strokeLine(ctx, cLeft, y + 12, cRight, y + 12)
    return y + 18
}

/// Zeile mit dunklem Etikett links und umbrochenem Text rechts; gibt die Zeilenhöhe zurück.
func labelRow(_ ctx: CGContext, _ name: String, _ text: String, y: CGFloat) -> CGFloat {
    let labelW: CGFloat = 78, tx = cLeft + labelW + 8, tw = cRight - tx - 4
    ctx.setFillColor(dark)
    pill(ctx, rect(cLeft, y, labelW, 13), radius: 3)
    drawCentered(ctx, name, f: font("AvenirNext-DemiBold", 7), color: white, cx: cLeft + labelW / 2, yMid: y + 6.5, kern: 1)
    return max(14, paragraph(ctx, text, x: tx, y: y + 0.5, w: tw))
}

func drawRules(_ ctx: CGContext) {
    pageTitle(ctx, "REGELN")
    navButtons(ctx, [("FUTURE", futurePage(forMonth: 0)), ("INDEX", indexPage)])

    // Bullets: zwei Spalten, Symbol + Bedeutung
    var y = section(ctx, "BULLETS", y: cTop + 2)
    let bullets: [[(String, String)]] = [
        [("•", "**Aufgabe**"), ("/", "**angefangen**; zweiter Strich macht daraus ×"), ("×", "**erledigt**"),
         (">", "**migriert**: verschoben oder in Collection")],
        [("<", "**zurückgestellt**: Monatsseite oder Future Log"), ("○", "**Termin**, Ereignis"),
         ("–", "**Notiz**, Gedanke, Beobachtung, Fakt"), ("=", "**Stimmung**, Gefühl, körperliches Empfinden")],
    ]
    let symFont = font("AvenirNext-Medium", 13)
    let colW = (cRight - cLeft) / 2, rowH: CGFloat = 14
    for (c, col) in bullets.enumerated() {
        for (r, (sym, text)) in col.enumerated() {
            let x = cLeft + CGFloat(c) * colW, yy = y + CGFloat(r) * rowH
            drawCentered(ctx, sym, f: symFont, color: dark, cx: x + 7, yMid: yy + 6.5)
            paragraph(ctx, text, x: x + 20, y: yy + 1, w: colW - 26)
        }
    }
    y += CGFloat(bullets.map(\.count).max()!) * rowH + 2
    y += paragraph(ctx, "Aufgabe **durchgestrichen** = hinfällig.",
                   x: cLeft, y: y, w: cRight - cLeft) + 4
    y += paragraph(ctx, "**Leere Spalte** (Future Log, Monat, Woche): was außerhalb dieses Zeitraums passiert. **•** noch offen, "
                   + "**>** nächster Zeitraum oder Collection, **<** zurück auf Monat / Future Log, **×** erledigt ohne festen Tag.",
                   x: cLeft, y: y, w: cRight - cLeft) + 10

    // Was wohin: vom Langfristigen zum Heute
    y = section(ctx, "WAS WOHIN", y: y)
    y += paragraph(ctx, "**Daily** = erfassen · **Woche** = die eine Handlungsliste · **Monat** und **Future Log** = später.",
                   x: cLeft, y: y, w: cRight - cLeft) + 6
    let places: [(String, String)] = [
        ("FUTURE LOG", "Fristen und Vorhaben **ohne festen Tag** ab dem nächsten Monat als Liste, Bullet in die **Spalte des Monats**; "
            + "**feste Termine** gleich auf die Monatsseite. Auch **aktive Collections mit Aufgaben** vermerken."),
        ("MONAT", "**Die Monatsseite ist das Future Log der Wochen.** Links an den Tag: Termine und Fristen dieses Monats, "
            + "**feste Termine** auch Monate im Voraus. Rechts als Liste: Projekte, Themen, **aktive Collections** "
            + "und Aufgaben des Monats, Bullet in die **Spalte der Woche**."),
        ("WOCHE", "Aufgaben und Termine **dieser Woche** als Liste, Bullet in die **Spalte des Tages**."),
        ("DAILY", "Tageslog: Datum als Überschrift, dann kurz mit Bullets notieren. **Stimmungen mit =**, "
            + "gern eingerückt unter dem auslösenden Ereignis; sie werden nicht migriert."),
        ("COLLECTION", "Alles **ohne Datum**: Ideen, Listen, Projekte, Recherchen. Neue Collection sofort in den Index eintragen."),
        ("GEWOHNHEIT", "Was sich **regelmäßig wiederholt**: eine Seite pro Gewohnheit, täglich abhaken."),
        ("INDEX", "Neue Collections und Seiten, die du wiederfinden willst, mit Link-Symbol eintragen."),
    ]
    for (name, text) in places { y += labelRow(ctx, name, text, y: y) + 5 }
    y += 3

    // Rhythmus der Migration
    y = section(ctx, "RHYTHMUS", y: y)
    let rhythm: [(String, String)] = [
        ("TÄGLICH", "Morgens die Daily datieren, über den Tag mitloggen. Abends abhaken: × oder in der Woche weiterplanen."),
        ("WÖCHENTLICH", "☐ Dailys durchgehen, Offenes in die Woche\n"
            + "☐ Jede offene •: Zeichen in die **leere Spalte**, oder streichen\n"
            + "☐ **Monatsseite**: was fällt in die neue Woche?\n"
            + "☐ Collections überfliegen"),
        ("MONATLICH", "**Future Log** des neuen Monats auf die Monatsseite übertragen, offene Themen migrieren oder streichen. "
            + "**=-Einträge** überfliegen: Was wiederholt sich?"),
    ]
    for (name, text) in rhythm { y += labelRow(ctx, name, text, y: y) + 5 }
    y += 3

    // Faustregeln als Frage → Ziel
    y = section(ctx, "FAUSTREGELN", y: y)
    let rules = [("Fester Termin?", "Monatsseite des Termins"), ("Später, aber ohne festen Tag?", "Future Log"),
                 ("Diese Woche?", "Wochenseite"), ("Diesen Monat, aber nicht diese Woche?", "Monatsseite")]
    let qf = font("AvenirNext-Regular", 8), af = font("AvenirNext-DemiBold", 8)
    for (i, (q, a)) in rules.enumerated() {
        let x = cLeft + CGFloat(i % 2) * colW, yy = y + CGFloat(i / 2) * 13
        let ql = line(q, qf, dark)
        drawText(ctx, ql, x: x, yMid: yy + 5, f: qf)
        drawText(ctx, line("→ " + a, af, dark), x: x + width(ql) + 5, yMid: yy + 5, f: af)
    }
    y += CGFloat((rules.count + 1) / 2) * 13 + 2
    paragraph(ctx, "Migrieren ist ein Filter: Was das Abschreiben nicht wert ist, wird gestrichen.", x: cLeft, y: y, w: cRight - cLeft)
}

// MARK: - Jahresziele (nach den Regeln): je Lebensbereich Zufriedenheit 1–10 und Ziele sammeln, dann nach kurz/mittel/lang sortieren

func smallLabel(_ ctx: CGContext, _ s: String, x: CGFloat, yMid: CGFloat) {
    let f = font("AvenirNext-DemiBold", 6)
    drawText(ctx, line(s, f, dark, kern: 1), x: x, yMid: yMid, f: f)
}

func drawGoals(_ ctx: CGContext) {
    pageTitle(ctx, "JAHRESZIELE \(endYear)")
    navButtons(ctx, [("FUTURE", futurePage(forMonth: 0)), ("INDEX", indexPage)])

    // Sammeln: sechs Lebensbereiche, je Skala „heute“ und Schreiblinien
    var y = section(ctx, "SAMMELN NACH BEREICHEN", y: cTop + 2)
    let areas = ["GESUNDHEIT", "BEZIEHUNGEN", "BERUF", "FINANZEN", "LERNEN", "FREIZEIT"]
    let gap: CGFloat = 8, bw = (cRight - cLeft - 2 * gap) / 3, bh: CGFloat = 122, lineH: CGFloat = 15
    let sf = font("AvenirNext-Medium", 4.5)
    for (k, a) in areas.enumerated() {
        let x = cLeft + CGFloat(k % 3) * (bw + gap), by = y + CGFloat(k / 3) * (bh + gap)
        ctx.setFillColor(light)
        ctx.fill(rect(x, by, bw, 14))
        label(ctx, a, x: x + 5, yMid: by + 7, color: black)
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
        ctx.stroke(rect(x, by, bw, bh))
        smallLabel(ctx, "HEUTE", x: x + 5, yMid: by + 24)
        let d: CGFloat = 8.5, sx = x + 34, step = (bw - 34 - 5 - d) / 9
        for n in 0..<10 {
            let c = rect(sx + CGFloat(n) * step, by + 24 - d / 2, d, d)
            ctx.strokeEllipse(in: c)
            drawCentered(ctx, String(n + 1), f: sf, color: dark, cx: c.midX, yMid: by + 24)
        }
        var ly = by + 34 + lineH
        while ly < by + bh - 6 {
            strokeLine(ctx, x + 5, ly, x + bw - 5, ly)
            ly += lineH
        }
    }
    y += 2 * bh + gap + 10

    // Sortieren nach Zeithorizont
    y = section(ctx, "SORTIEREN", y: y)
    let cols = [("KURZ", "Wochen"), ("MITTEL", "Monate"), ("LANG", "über das Jahr")]
    let tf = font("AvenirNext-Regular", 7), pf = font("AvenirNext-DemiBold", 7.5)
    for (k, c) in cols.enumerated() {
        let x = cLeft + CGFloat(k) * (bw + gap)
        ctx.setFillColor(dark)
        pill(ctx, rect(x, y, bw, 14), radius: 3)
        drawCentered(ctx, c.0, f: pf, color: white, cx: x + bw / 2, yMid: y + 7, kern: 1)
        drawCentered(ctx, c.1, f: tf, color: dark, cx: x + bw / 2, yMid: y + 22)
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
        var ly = y + 28 + lineH
        while ly < cBottom - 24 {
            strokeLine(ctx, x, ly, x + bw, ly)
            ly += lineH
        }
    }
}

// MARK: - PDF schreiben

var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
let info: [CFString: Any] = [kCGPDFContextTitle: "Bullet Journal Seiten", kCGPDFContextCreator: "generate_bujo.swift"]
guard let ctx = CGContext(URL(fileURLWithPath: output) as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
    fatalError("Kann \(output) nicht anlegen")
}

func page(habit: Bool = true, _ draw: (CGContext) -> Void) {
    ctx.beginPDFPage(nil)
    ctx.setFillColor(white)
    ctx.fill(mediaBox)
    habitInNav = habit
    habitTarget = trackerPage(forYear: startYear)
    draw(ctx)
    ctx.endPDFPage()
    currentPage += 1
}

// Alle Monate des Zeitraums
var months: [(year: Int, month: Int)] = []
var (y, m) = (startYear, startMonth)
while (y, m) <= (endYear, endMonth) {
    months.append((y, m))
    (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
}
// Monate im Future Log: der Zeitraum plus die ersten Monate danach
var futureMonths = months
for _ in 0..<futureExtraMonths {
    futureMonths.append((y, m))
    (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
}
// Future-Log-Seiten: je Kalenderquartal eine Seite (angebrochene Quartale am Anfang und Ende mit weniger Monaten)
var futureGroups: [[Int]] = []
for (i, fm) in futureMonths.enumerated() {
    if i > 0, (futureMonths[i - 1].year, (futureMonths[i - 1].month - 1) / 3) == (fm.year, (fm.month - 1) / 3) {
        futureGroups[futureGroups.count - 1].append(i)
    } else {
        futureGroups.append([i])
    }
}

// Alle Wochen vom Montag vor dem ersten bis einschließlich zum letzten Tag des Zeitraums
let firstDay = cal.date(from: DateComponents(year: months[0].year, month: months[0].month, day: 1))!
let lastDay = cal.date(byAdding: DateComponents(month: 1, day: -1),
                       to: cal.date(from: DateComponents(year: endYear, month: endMonth, day: 1))!)!
var weeks: [Date] = []
var w = cal.dateInterval(of: .weekOfYear, for: firstDay)!.start
while w <= lastDay {
    weeks.append(w)
    w = cal.date(byAdding: .day, value: 7, to: w)!
}
func weekIndex(of date: Date) -> Int { cal.dateComponents([.day], from: weeks[0], to: date).day! / 7 }

// Seitenaufteilung (0-basiert): Deckblatt, dann wie im Buch Index, Regeln, Jahresziele, Future Log, Monate,
// danach alle Wochen (je Wochenseite + Wochen-Daily), die Gewohnheitsseite und zwei Collections
let indexPage = 1
let rulesPage = indexPage + 1
let goalsPage = rulesPage + 1
let futureCount = futureGroups.count
func futurePage(forMonth i: Int) -> Int { goalsPage + 1 + futureGroups.firstIndex { $0.contains(i) }! }
func monthPage(_ i: Int) -> Int { goalsPage + 1 + futureCount + i }
func weekPage(_ i: Int) -> Int { monthPage(months.count) + 2 * i }
let trackerPage = weekPage(weeks.count)
func trackerPage(forYear y: Int) -> Int { trackerPage + y - startYear }
let collectionPage = trackerPage(forYear: endYear) + 1

page(habit: false, drawCover)
page(drawIndex)
page(habit: false, drawRules)
page(drawGoals)
for p in 0..<futureCount { page { drawFuture($0, page: p) } }
for i in months.indices { page { drawMonth($0, index: i) } }
for i in weeks.indices {
    page { drawWeek($0, index: i) }
    page { drawWeekDaily($0, index: i) }
}
for y in startYear...endYear { page(habit: false) { drawTracker($0, year: y) } }
page(drawCollection)
page(drawCollection)
ctx.closePDF()

// Links als GoTo-Annotationen mit explizitem Seitenziel einfügen
let doc = PDFDocument(url: URL(fileURLWithPath: output))!
for l in links {
    let a = PDFAnnotation(bounds: l.rect, forType: .link, withProperties: nil)
    a.action = PDFActionGoTo(destination: PDFDestination(page: doc.page(at: l.target)!, at: CGPoint(x: 0, y: H)))
    a.border = PDFBorder()
    a.border?.lineWidth = 0
    doc.page(at: l.page)!.addAnnotation(a)
}
let tmp = output + ".tmp"
doc.write(to: URL(fileURLWithPath: tmp))
_ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: output), withItemAt: URL(fileURLWithPath: tmp))
print("\(output): \(currentPage) Seiten, \(links.count) Links")
