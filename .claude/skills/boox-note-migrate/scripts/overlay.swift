// Kontrollbild: Striche (aus `notemig.py check --strokes`) rot über die PDF-Seite gelegt, je Seite ein PNG.
// Nur zur Prüfung, nicht als Ergebnis gedacht.
// Aufruf: swift overlay.swift Datei.pdf striche.txt Ausgabeordner
import AppKit
import PDFKit

let args = CommandLine.arguments
let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
let text = try! String(contentsOfFile: args[2], encoding: .utf8)
let outDir = args[3]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var pages: [(page: Int, pdf: Int, width: CGFloat, strokes: [[CGPoint]])] = []
for l in text.split(separator: "\n") {
    let p = l.split(separator: " ")
    if p[0] == "P" {
        pages.append((Int(p[1])!, Int(p[2])!, CGFloat(Double(p[3])!), []))
    } else {
        pages[pages.count - 1].strokes.append(p.dropFirst().map {
            let c = $0.split(separator: ",")
            return CGPoint(x: Double(c[0])!, y: Double(c[1])!)
        })
    }
}

for pg in pages {
    guard let page = doc.page(at: pg.pdf) else { continue }
    let box = page.bounds(for: .mediaBox)
    let k = pg.width / box.width
    let w = Int(pg.width), h = Int(box.height * k)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.saveGState()
    ctx.scaleBy(x: k, y: k)
    page.draw(with: .mediaBox, to: ctx)
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(red: 0.85, green: 0, blue: 0, alpha: 1))
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for s in pg.strokes where !s.isEmpty {
        ctx.move(to: CGPoint(x: s[0].x, y: CGFloat(h) - s[0].y))
        for q in s.dropFirst() { ctx.addLine(to: CGPoint(x: q.x, y: CGFloat(h) - q.y)) }
        ctx.strokePath()
    }
    let url = URL(fileURLWithPath: "\(outDir)/seite-\(String(format: "%03d", pg.page)).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
print("\(pages.count) Kontrollbilder in \(outDir)")
