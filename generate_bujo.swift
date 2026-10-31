// Erzeugt ein PDF ohne Links mit Monatsseiten (Tagesliste + Punktraster)
// und einer generischen Wochenseite (Layout wie "Weekly Rolling.pdf").
// Aufruf: swift generate_bujo.swift [Ausgabe.pdf]

import Foundation
import CoreGraphics
import CoreText

// MARK: - Einstellungen

let startYear = 2026, startMonth = 11
let endYear = 2027, endMonth = 12
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "BuJo-Seiten-\(startYear)-\(String(format: "%02d", startMonth))_\(endYear)-\(String(format: "%02d", endMonth)).pdf"

// Seitenformat wie der Original-Planer (OnPlanners, vertikal)
let W: CGFloat = 458.88, H: CGFloat = 597.12
let margin: CGFloat = 16
let dotSpacing: CGFloat = 14.173 // 5 mm

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

// MARK: - Monatsseite

var cal = Calendar(identifier: .iso8601)
cal.locale = Locale(identifier: "de_DE")

func drawMonth(_ ctx: CGContext, year: Int, month: Int) {
    let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
    let days = cal.range(of: .day, in: .month, for: first)!.count

    // Kopf: Monat und Jahr als Überschrift
    let titleFont = font("AvenirNext-Regular", 18)
    drawText(ctx, line("\(monthNames[month - 1]) \(year)", titleFont, black, kern: 1.5), x: margin, yMid: 30, f: titleFont)

    ctx.setStrokeColor(dark)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, 48, W - margin, 48)

    // Linke Spalte: ein Eintrag pro Tag
    let listX = margin, listW: CGFloat = 200
    let top: CGFloat = 56, bottom = H - margin
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
            let kw = cal.component(.weekOfYear, from: date)
            let bw: CGFloat = 17
            ctx.setFillColor(dark)
            pill(ctx, rect(listX + listW - bw - 1, mid - diam / 2, bw, diam), radius: diam / 2)
            drawCentered(ctx, String(kw), f: kwFont, color: white, cx: listX + listW - bw / 2 - 1, yMid: mid)
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

// MARK: - Weitere Seiten: Index, Future Log, Daily/Collection, Gewohnheits-Tracker

let cTop: CGFloat = 56, cBottom = H - margin, cLeft = margin, cRight = W - margin
let gridDot = CGColor(gray: 0.4, alpha: 1)

func pageTitle(_ ctx: CGContext, _ title: String, writeLine: CGFloat = 0) {
    let f = font("AvenirNext-Regular", 18)
    let l = line(title, f, black, kern: 1.5)
    drawText(ctx, l, x: margin, yMid: 30, f: f)
    if writeLine > 0 {
        let x0 = margin + width(l) + 8
        ctx.setStrokeColor(rule); ctx.setLineWidth(0.6)
        strokeLine(ctx, x0, 38, x0 + writeLine, 38)
    }
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, 48, W - margin, 48)
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

// 1) Index: zwei Spalten mit Thema + Seiten
func drawIndex(_ ctx: CGContext) {
    pageTitle(ctx, "INDEX")
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
}

// 2) Future Log: drei Monate pro Seite, je Mini-Kalender + Punktraster
func drawFuture(_ ctx: CGContext, year: Int, month: Int, months: Int = 3) {
    pageTitle(ctx, "FUTURE LOG")
    let secH = (cBottom - cTop) / 3, barH: CGFloat = 17
    let mf = font("Menlo-Regular", 6.5), mfb = font("Menlo-Bold", 6.5)
    var (y, m) = (year, month)
    for s in 0..<months {
        let top = cTop + CGFloat(s) * secH
        ctx.setFillColor(dark)
        pill(ctx, rect(cLeft, top, cRight - cLeft, barH), radius: 3)
        label(ctx, "\(monthNames[m - 1]) \(y)", x: cLeft + 8, yMid: top + barH / 2, color: white)

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
        (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
    }
}

// 3) Daily / Collection: Thema- bzw. Datumslinie + Seitenzahl, darunter Punktraster
func drawDaily(_ ctx: CGContext) {
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.6)
    strokeLine(ctx, margin, 38, W - margin - 70, 38)
    label(ctx, "DATUM / THEMA", x: margin, yMid: 18, color: rule)
    label(ctx, "SEITE", x: W - margin - 56, yMid: 18, color: rule)
    strokeLine(ctx, W - margin - 56, 38, W - margin, 38)
    ctx.setStrokeColor(dark)
    strokeLine(ctx, margin, 48, W - margin, 48)
    dots(ctx, x0: cLeft, y0: cTop, x1: cRight, y1: cBottom)
}

// 4) Gewohnheits-Tracker (undatiert): Gewohnheiten × Tage 1–31
func drawTracker(_ ctx: CGContext) {
    pageTitle(ctx, "GEWOHNHEITEN", writeLine: 120)
    let nameW: CGFloat = 112, headH: CGFloat = 20, rows = 24
    let colW = (cRight - cLeft - nameW) / 31, rowH = (cBottom - cTop - headH) / CGFloat(rows)
    let x0 = cLeft + nameW
    label(ctx, "GEWOHNHEIT", x: cLeft, yMid: cTop + headH / 2)
    let nf = font("Menlo-Bold", 5.5)
    ctx.setFillColor(light)
    ctx.fill(rect(x0, cTop, cRight - x0, headH))
    for d in 1...31 { drawCentered(ctx, String(d), f: nf, color: black, cx: x0 + (CGFloat(d) - 0.5) * colW, yMid: cTop + headH / 2) }
    ctx.setStrokeColor(dark); ctx.setLineWidth(0.8)
    strokeLine(ctx, cLeft, cTop + headH, cRight, cTop + headH)
    ctx.setStrokeColor(rule); ctx.setLineWidth(0.5)
    for r in 1...rows { let y = cTop + headH + CGFloat(r) * rowH; strokeLine(ctx, cLeft, y, cRight, y) }
    for d in 0...31 {
        ctx.setLineWidth(d % 7 == 0 ? 0.9 : 0.4)
        strokeLine(ctx, x0 + CGFloat(d) * colW, cTop, x0 + CGFloat(d) * colW, cBottom)
    }
}

// MARK: - Wochenseite (Aufbau wie "Weekly Rolling.pdf": Aufgaben + Mo–So + Next, Stil wie Monatsseite)

func drawWeek(_ ctx: CGContext) {
    // Kopf: "WOCHE" mit Schreiblinie
    let titleFont = font("AvenirNext-Regular", 18)
    let title = line("WOCHE", titleFont, black, kern: 1.5)
    drawText(ctx, title, x: margin, yMid: 30, f: titleFont)
    let lineX = margin + width(title) + 8
    ctx.setStrokeColor(rule)
    ctx.setLineWidth(0.6)
    strokeLine(ctx, lineX, 38, lineX + 120, 38)
    ctx.setStrokeColor(dark)
    strokeLine(ctx, margin, 48, W - margin, 48)

    let top: CGFloat = 56, bottom = H - margin
    let rows = 21, colW: CGFloat = 22, headH: CGFloat = 24, box: CGFloat = 14
    let taskRight = W - margin - 8 * colW
    let rowH = (bottom - top - headH) / CGFloat(rows)

    // Spaltenköpfe, Wochenende grau hinterlegt
    let headFont = font("AvenirNext-DemiBold", 7.5)
    drawText(ctx, line("AUFGABEN", headFont, dark, kern: 1.2), x: margin, yMid: top + headH / 2, f: headFont)
    let dayFont = font("Menlo-Bold", 7)
    for (i, label) in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So", "Nx"].enumerated() {
        let x = taskRight + CGFloat(i) * colW
        if i == 5 || i == 6 {
            ctx.setFillColor(light)
            ctx.fill(rect(x + 1, top, colW - 2, bottom - top))
        }
        drawCentered(ctx, label, f: dayFont, color: black, cx: x + colW / 2, yMid: top + headH / 2)
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

func page(_ draw: (CGContext) -> Void) {
    ctx.beginPDFPage(nil)
    ctx.setFillColor(white)
    ctx.fill(mediaBox)
    draw(ctx)
    ctx.endPDFPage()
}

// Alle Monate des Zeitraums
var months: [(year: Int, month: Int)] = []
var (y, m) = (startYear, startMonth)
while (y, m) <= (endYear, endMonth) {
    months.append((y, m))
    (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
}

// Reihenfolge wie im Buch: Index, Future Log, Monate, danach die undatierten Vorlagen
var count = 0
page { drawIndex($0) }
count += 1
for i in stride(from: 0, to: months.count, by: 3) {
    let first = months[i]
    page { drawFuture($0, year: first.year, month: first.month, months: min(3, months.count - i)) }
    count += 1
}
for mo in months {
    page { drawMonth($0, year: mo.year, month: mo.month) }
    count += 1
}
for draw in [drawWeek, drawDaily, drawTracker] {
    page(draw)
    count += 1
}
ctx.closePDF()
print("\(output): \(count) Seiten")
