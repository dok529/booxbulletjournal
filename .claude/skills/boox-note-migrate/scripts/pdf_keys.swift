// Gibt Seitengröße und je Seite einen Schlüssel aus (erste Textzeile ohne Leerraum),
// über den plan Seiten zwischen alter und neuer PDF-Version zuordnet.
// Aufruf: swift pdf_keys.swift Datei.pdf
import PDFKit

guard CommandLine.arguments.count > 1,
      let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write("PDF nicht lesbar\n".data(using: .utf8)!)
    exit(1)
}
let box = doc.page(at: 0)!.bounds(for: .mediaBox)
print("SIZE\t\(box.width)\t\(box.height)")
for i in 0..<doc.pageCount {
    let first = (doc.page(at: i)?.string ?? "").split(separator: "\n").first.map(String.init) ?? ""
    print("\(i)\t\(first.filter { !$0.isWhitespace })")
}
