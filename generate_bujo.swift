// Erzeugt ein Bullet-Journal-PDF für BOOX Notes: Deckblatt, Index, Future Log,
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
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "BuJo-2027 V1.pdf"

// Seitenformat wie der Original-Planer (OnPlanners, vertikal)
let W: CGFloat = 458.88, H: CGFloat = 597.12
let margin: CGFloat = 16
let dotSpacing: CGFloat = 14.173 // 5 mm

// Kopfbereich (von oben): Mitte der Überschrift, Trennlinie, Beginn des Inhalts
let headMid: CGFloat = 20, headRule: CGFloat = 34, contentTop: CGFloat = 40

let monthNames = ["JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI",
                  "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"]
let weekdayShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"] // Index = Calendar.weekday - 1

let dark = CGColor(gray: 0.30, alpha: 1)
let light = CGColor(gray: 0.92, alpha: 1)
let rule = CGColor(gray: 0.55, alpha: 1)
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

func link(_ r: CGRect, to target: Int) { links.append((currentPage, r, target)) }

/// Navigationsknöpfe rechts in der Kopfzeile, von links nach rechts angeordnet.
/// Gibt den linken Rand des ersten Knopfs zurück.
@discardableResult
func navButtons(_ ctx: CGContext, _ items: [(label: String, target: Int)], minWidth: CGFloat = 46) -> CGFloat {
    let f = font("AvenirNext-DemiBold", 7.5)
    let h: CGFloat = 17, gap: CGFloat = 5
    let widths = items.map { $0.label.count <= 1 ? 20 : max(minWidth, width(line($0.label, f, white, kern: 1)) + 16) }
    var x = W - margin - widths.reduce(0, +) - gap * CGFloat(items.count - 1)
    let left = x
    for (item, w) in zip(items, widths) {
        let r = rect(x, headMid - h / 2, w, h)
        ctx.setFillColor(dark)
        pill(ctx, r, radius: 3)
        drawCentered(ctx, item.label, f: item.label.count <= 1 ? font("AvenirNext-Bold", 16) : f,
                     color: white, cx: r.midX, yMid: headMid, kern: item.label.count <= 1 ? 0 : 1)
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

    // Kopf: Monat und Jahr als Überschrift, rechts Navigation
    let titleFont = font("AvenirNext-Regular", 18)
    drawText(ctx, line("\(monthNames[month - 1]) \(year)", titleFont, black, kern: 1.5), x: margin, yMid: headMid, f: titleFont)
    var nav: [(label: String, target: Int)] = []
    if i > 0 { nav.append(("‹", monthPage(i - 1))) }
    if i < months.count - 1 { nav.append(("›", monthPage(i + 1))) }
    nav += [("FUTURE LOG", futurePage(forMonth: i)), ("INDEX", indexPage)]
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

        let circle = rect(listX + 1, mid - diam / 2, diam, diam)
        if weekend {
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(0.8)
            ctx.strokeEllipse(in: circle.insetBy(dx: 0.4, dy: 0.4))
        } else {
            ctx.setFillColor(dark)
            ctx.fillEllipse(in: circle)
        }
        drawCentered(ctx, String(d), f: numFont, color: weekend ? dark : white, cx: circle.midX, yMid: mid)
        drawText(ctx, line(weekdayShort[wd - 1], dayFont, black), x: listX + diam + 4, yMid: mid, f: dayFont)

        if wd == 2 || d == 1 {
            // KW-Badge verlinkt auf die Wochenseite
            let kw = cal.component(.weekOfYear, from: date)
            let bw: CGFloat = 17
            ctx.setFillColor(dark)
            pill(ctx, rect(listX + listW - bw - 1, mid - diam / 2, bw, diam), radius: diam / 2)
            drawCentered(ctx, String(kw), f: kwFont, color: white, cx: listX + listW - bw / 2 - 1, yMid: mid)
            link(rect(listX + listW - bw - 5, y, bw + 5, rowH), to: weekPage(weekIndex(of: date)))
        }
    }
    ctx.setStrokeColor(rule)
    ctx.setLineWidth(0.5)
    strokeLine(ctx, listX, top, listX + listW, top)

    // Rechts: Punktraster
    let gridX0 = listX + listW + 12, gridX1 = W - margin
    let cols = Int((gridX1 - gridX0) / dotSpacing), rows = Int((bottom - top) / dotSpacing)
    let offX = gridX0 + ((gridX1 - gridX0) - CGFloat(cols) * dotSpacing) / 2
    let offY = top + ((bottom - top) - CGFloat(rows) * dotSpacing) / 2
    ctx.setFillColor(CGColor(gray: 0.4, alpha: 1))
    let r: CGFloat = 0.65
    for i in 0...cols {
        for j in 0...rows {
            let x = offX + CGFloat(i) * dotSpacing, y = offY + CGFloat(j) * dotSpacing
            ctx.fillEllipse(in: rect(x - r, y - r, 2 * r, 2 * r))
        }
    }
}

// MARK: - Weitere Seiten: Deckblatt, Index, Future Log, Gewohnheits-Tracker

let cTop = contentTop, cBottom = H - margin, cLeft = margin, cRight = W - margin
let gridDot = CGColor(gray: 0.4, alpha: 1)

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

func dots(_ ctx: CGContext, x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) {
    let cols = Int((x1 - x0) / dotSpacing), rows = Int((y1 - y0) / dotSpacing)
    let ox = x0 + ((x1 - x0) - CGFloat(cols) * dotSpacing) / 2
    let oy = y0 + ((y1 - y0) - CGFloat(rows) * dotSpacing) / 2
    ctx.setFillColor(gridDot)
    for i in 0...cols { for j in 0...rows {
        let x = ox + CGFloat(i) * dotSpacing, y = oy + CGFloat(j) * dotSpacing
        ctx.fillEllipse(in: rect(x - 0.65, y - 0.65, 1.3, 1.3))
    } }
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
    navButtons(ctx, [("FUTURE LOG", futurePage(forMonth: 0))])
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

    // Vorbelegt: Future Log und alle Monate als Links. Ohne Seitenzahl, weil sich die
    // Seitenzahlen auf dem BOOX durch eingefügte Seiten verschieben.
    let entries = [("Future Log", futurePage(forMonth: 0))]
        + months.indices.map { ("\(monthNames[months[$0].month - 1].capitalized) \(months[$0].year)", monthPage($0)) }
        + [("Wochen (ab KW \(cal.component(.weekOfYear, from: weeks[0])))", weekPage(0)),
           ("Gewohnheiten", trackerPage)]
    let ef = font("AvenirNext-Regular", 9.5)
    for (r, (text, target)) in entries.prefix(rows).enumerated() {
        let rowTop = cTop + headH + CGFloat(r) * rowH
        drawText(ctx, line(text, ef, black), x: cLeft + 2, yMid: rowTop + rowH / 2 + 1, f: ef)
        drawText(ctx, line("›", ef, dark), x: cLeft + colW - 44 - 10, yMid: rowTop + rowH / 2 + 1, f: ef)
        link(rect(cLeft, rowTop, colW - 44, rowH), to: target)
    }
}

// 2) Future Log: drei Monate pro Seite, je Mini-Kalender + Punktraster; Monatsbalken verlinken auf die Monatsseite
func drawFuture(_ ctx: CGContext, page p: Int) {
    pageTitle(ctx, "FUTURE LOG")
    navButtons(ctx, [("INDEX", indexPage)])
    let secH = (cBottom - cTop) / 3, barH: CGFloat = 17
    let mf = font("Menlo-Regular", 6.5), mfb = font("Menlo-Bold", 6.5)
    for s in 0..<min(3, months.count - 3 * p) {
        let mi = 3 * p + s, (y, m) = months[mi]
        let top = cTop + CGFloat(s) * secH
        let bar = rect(cLeft, top, cRight - cLeft, barH)
        ctx.setFillColor(dark)
        pill(ctx, bar, radius: 3)
        label(ctx, "\(monthNames[m - 1]) \(y)", x: cLeft + 8, yMid: top + barH / 2, color: white)
        let more = line("ZUM MONAT ›", font("AvenirNext-DemiBold", 7.5), white, kern: 1.2)
        drawText(ctx, more, x: cRight - 8 - width(more), yMid: top + barH / 2, f: font("AvenirNext-DemiBold", 7.5))
        link(bar, to: monthPage(mi))

        // Mini-Kalender Mo–So
        let calX = cLeft, calW: CGFloat = 126, cellW = calW / 7, cellH: CGFloat = 15
        let calTop = top + barH + 6
        for (i, d) in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated() {
            drawCentered(ctx, d, f: mfb, color: i >= 5 ? rule : black, cx: calX + (CGFloat(i) + 0.5) * cellW, yMid: calTop + cellH / 2)
        }
        let first = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let offset = (cal.component(.weekday, from: first) + 5) % 7 // Mo = 0
        for d in 1...days {
            let idx = offset + d - 1, col = idx % 7, row = idx / 7
            let cx = calX + (CGFloat(col) + 0.5) * cellW, cy = calTop + cellH * (CGFloat(row) + 1.5)
            if col >= 5 { ctx.setFillColor(light); ctx.fill(rect(cx - cellW / 2, cy - cellH / 2, cellW, cellH)) }
            drawCentered(ctx, String(d), f: mf, color: black, cx: cx, yMid: cy)
        }
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
        strokeLine(ctx, calX + calW + 8, top + barH + 6, calX + calW + 8, top + secH - 8)
        dots(ctx, x0: calX + calW + 16, y0: top + barH + 6, x1: cRight, y1: top + secH - 8)
    }
}

// 4) Gewohnheits-Tracker: eine Seite pro Gewohnheit, alle Wochen des Zeitraums als Zeilen (Mo–So)
func drawTracker(_ ctx: CGContext) {
    pageTitle(ctx, "GEWOHNHEIT", writeLine: 190)
    navButtons(ctx, [("INDEX", indexPage)])

    // Legende: eine durchgehende Schreibzeile
    label(ctx, "LEGENDE", x: cLeft, yMid: cTop + 6)
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
    strokeLine(ctx, cLeft + 50, cTop + 10, cRight, cTop + 10)

    let top = cTop + 24, headH: CGFloat = 12, gap: CGFloat = 12
    let perCol = (weeks.count + 1) / 2
    let colW = (cRight - cLeft - gap) / 2, labW: CGFloat = 40
    let cw = (colW - labW) / 7, rh = (cBottom - top - headH) / CGFloat(perCol)
    let hf = font("Menlo-Bold", 6), nf = font("AvenirNext-Medium", 4.8), bf = font("AvenirNext-Bold", 4.8)
    let kf = font("AvenirNext-DemiBold", 6.5)
    let outside = CGColor(gray: 0.82, alpha: 1)

    for col in 0..<2 {
        let bx = cLeft + CGFloat(col) * (colW + gap), x0 = bx + labW
        for (k, l) in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated() {
            if k >= 5 {
                ctx.setFillColor(light)
                ctx.fill(rect(x0 + CGFloat(k) * cw, top, cw, cBottom - top))
            }
            drawCentered(ctx, l, f: hf, color: k >= 5 ? rule : black, cx: x0 + (CGFloat(k) + 0.5) * cw, yMid: top + headH / 2)
        }
        for r in 0..<perCol {
            let wi = col * perCol + r
            guard wi < weeks.count else { break }
            let y = top + headH + CGFloat(r) * rh
            drawText(ctx, line("KW \(cal.component(.weekOfYear, from: weeks[wi]))", kf, dark, kern: 0.3), x: bx, yMid: y + rh / 2, f: kf)
            link(rect(bx, y, labW - 4, rh), to: weekPage(wi))
            for k in 0..<7 {
                let day = cal.date(byAdding: .day, value: k, to: weeks[wi])!
                let cell = rect(x0 + CGFloat(k) * cw, y, cw, rh)
                if day < firstDay || day > lastDay {
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
                    drawText(ctx, line(String(dn), nf, CGColor(gray: 0.35, alpha: 1)), x: cell.minX + 1.5, yMid: y + 3.8, f: nf)
                }
            }
            ctx.setStrokeColor(rule); ctx.setLineWidth(0.4)
            strokeLine(ctx, bx, y + rh, x0 + 7 * cw, y + rh)
        }
        ctx.setStrokeColor(dark); ctx.setLineWidth(0.8)
        strokeLine(ctx, bx, top + headH, x0 + 7 * cw, top + headH)
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.3)
        for k in 0...7 {
            strokeLine(ctx, x0 + CGFloat(k) * cw, top + headH, x0 + CGFloat(k) * cw, top + headH + CGFloat(perCol) * rh)
        }
    }
}

// MARK: - Gewohnheits-Knopf (unten rechts über dem Inhalt, ohne Text, mit Häkchen)

func habitButton(_ ctx: CGContext) {
    let s: CGFloat = 20
    let r = rect(W - margin - s, H - margin - s, s, s)
    ctx.setFillColor(dark)
    pill(ctx, r, radius: 4)
    ctx.saveGState()
    ctx.setStrokeColor(white); ctx.setLineWidth(1.8); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: r.minX + 5.5, y: r.midY + 0.5))
    ctx.addLine(to: CGPoint(x: r.minX + 8.8, y: r.minY + 6))
    ctx.addLine(to: CGPoint(x: r.maxX - 5, y: r.maxY - 5.5))
    ctx.strokePath()
    ctx.restoreGState()
    link(r, to: trackerPage)
}

// MARK: - Wochen-Daily (nach jeder Wochenseite): Datumsbereich als Überschrift, freies Punktraster

func weekRange(_ days: [Date]) -> String {
    let df = DateFormatter()
    df.dateFormat = "dd.MM."
    let yf = DateFormatter()
    yf.dateFormat = "dd.MM.yyyy"
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

func drawWeekDaily(_ ctx: CGContext, index wi: Int) {
    let monday = weeks[wi]
    let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    let tf = font("AvenirNext-Regular", 15)
    drawText(ctx, line(weekRange(days), tf, black, kern: 1), x: margin, yMid: headMid, f: tf)
    let nav = [("KW \(cal.component(.weekOfYear, from: monday))", weekPage(wi))] + monthButtons(days)
        + [("FUTURE LOG", futurePage(forMonth: 0)), ("INDEX", indexPage)]
    navButtons(ctx, nav, minWidth: 34)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)
    dots(ctx, x0: cLeft, y0: cTop, x1: cRight, y1: cBottom)
}

// MARK: - Wochenseite (Aufbau wie "Weekly Rolling.pdf": Aufgaben + Mo–So + Next, Stil wie Monatsseite)

func drawWeek(_ ctx: CGContext, index wi: Int) {
    let monday = weeks[wi]
    let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }

    // Kopf: KW und Datumsbereich, rechts Navigation (Vor-/Folgewoche, berührte Monate, Index)
    let titleFont = font("AvenirNext-Regular", 18)
    let title = line("KW \(cal.component(.weekOfYear, from: monday))", titleFont, black, kern: 1.5)
    drawText(ctx, title, x: margin, yMid: headMid, f: titleFont)
    let range = weekRange(days)
    let rf = font("AvenirNext-Medium", 9)
    drawText(ctx, line(range, rf, dark, kern: 1), x: margin + width(title) + 10, yMid: headMid + 1, f: rf)

    var nav: [(label: String, target: Int)] = []
    if wi > 0 { nav.append(("‹", weekPage(wi - 1))) }
    if wi < weeks.count - 1 { nav.append(("›", weekPage(wi + 1))) }
    nav += monthButtons(days)
    nav.append(("INDEX", indexPage))
    navButtons(ctx, nav)
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, headRule, W - margin, headRule)

    let top = contentTop, bottom = H - margin
    let rows = 21, colW: CGFloat = 22, headH: CGFloat = 24, box: CGFloat = 14
    let taskRight = W - margin - 8 * colW
    let rowH = (bottom - top - headH) / CGFloat(rows)

    // Spaltenköpfe, Wochenende grau hinterlegt
    let headFont = font("AvenirNext-DemiBold", 7.5)
    drawText(ctx, line("AUFGABEN", headFont, dark, kern: 1.2), x: margin, yMid: top + headH / 2, f: headFont)
    let dayFont = font("Menlo-Bold", 7), dateFont = font("AvenirNext-Medium", 6.5)
    for (i, label) in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So", "Nx"].enumerated() {
        let x = taskRight + CGFloat(i) * colW
        if i == 5 || i == 6 {
            ctx.setFillColor(light)
            ctx.fill(rect(x + 1, top, colW - 2, bottom - top))
        }
        if i < 7 {
            drawCentered(ctx, label, f: dayFont, color: black, cx: x + colW / 2, yMid: top + 7)
            drawCentered(ctx, String(cal.component(.day, from: days[i])), f: dateFont, color: dark, cx: x + colW / 2, yMid: top + 17)
        } else {
            drawCentered(ctx, label, f: dayFont, color: black, cx: x + colW / 2, yMid: top + headH / 2)
        }
    }
    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.8)
    strokeLine(ctx, margin, top + headH, W - margin, top + headH)

    // Zeilen: Schreiblinie links, Abhak-Kästchen rechts
    for r in 0..<rows {
        let y = top + headH + CGFloat(r) * rowH
        ctx.setStrokeColor(rule)
        ctx.setLineWidth(0.5)
        strokeLine(ctx, margin, y + rowH, taskRight - 4, y + rowH)
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(0.6)
        for i in 0..<8 {
            let cx = taskRight + (CGFloat(i) + 0.5) * colW, cy = y + rowH / 2
            let b = rect(cx - box / 2, cy - box / 2, box, box)
            ctx.addPath(CGPath(roundedRect: b, cornerWidth: 2.4, cornerHeight: 2.4, transform: nil))
            ctx.strokePath()
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
    draw(ctx)
    if habit { habitButton(ctx) }
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

// Seitenaufteilung (0-basiert): Deckblatt, dann wie im Buch Index, Future Log, Monate,
// danach alle Wochen (je Wochenseite + Wochen-Daily) und die Gewohnheitsseite
let indexPage = 1
let futureCount = (months.count + 2) / 3
func futurePage(forMonth i: Int) -> Int { indexPage + 1 + i / 3 }
func monthPage(_ i: Int) -> Int { indexPage + 1 + futureCount + i }
func weekPage(_ i: Int) -> Int { monthPage(months.count) + 2 * i }
let trackerPage = weekPage(weeks.count)

page(habit: false, drawCover)
page(drawIndex)
for p in 0..<futureCount { page { drawFuture($0, page: p) } }
for i in months.indices { page { drawMonth($0, index: i) } }
for i in weeks.indices {
    page { drawWeek($0, index: i) }
    page { drawWeekDaily($0, index: i) }
}
page(habit: false, drawTracker)
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
