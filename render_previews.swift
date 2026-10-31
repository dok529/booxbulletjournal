// Rendert je eine Beispielseite pro Seitentyp aus dem erzeugten PDF als PNG nach previews/.
// Aufruf (nach generate_bujo.swift): swift render_previews.swift [BuJo.pdf]

import AppKit
import PDFKit

let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "BuJo-Seiten-2026-11_2027-12.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else { fatalError("Kann \(pdfPath) nicht öffnen") }

let monthNames = ["JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI",
                  "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"]

/// Erste Textzeile der Seite ohne Leerzeichen (gesperrte Schrift wird als "D AT U M" extrahiert)
func firstLine(_ i: Int) -> String {
    String((doc.page(at: i)?.string ?? "").split(separator: "\n").first ?? "").replacingOccurrences(of: " ", with: "")
}

/// Erste Seite, deren Überschrift die Bedingung erfüllt
func find(_ match: (String) -> Bool) -> Int? { (0..<doc.pageCount).first { match(firstLine($0)) } }

let types: [(file: String, page: Int?)] = [
    ("index", find { $0.hasPrefix("INDEX") }),
    ("future-log", find { $0.hasPrefix("FUTURELOG") }),
    ("monat", find { l in monthNames.contains { l.hasPrefix($0 + "20") } }),
    ("woche", find { $0.hasPrefix("WOCHE") }),
    ("daily", find { $0.hasPrefix("DATUM/THEMA") }),
    ("gewohnheit", find { $0.hasPrefix("GEWOHNHEIT") }),
]

let scale: CGFloat = 1.5
try? FileManager.default.createDirectory(atPath: "previews", withIntermediateDirectories: true)
for t in types {
    guard let i = t.page, let page = doc.page(at: i) else { fatalError("Seitentyp \(t.file) nicht gefunden") }
    let box = page.bounds(for: .mediaBox)
    let w = Int(box.width * scale), h = Int(box.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "previews/\(t.file).png"))
    print("previews/\(t.file).png  ← Seite \(i + 1)")
}
