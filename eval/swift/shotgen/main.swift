// shotgen: renders a synthetic screenshot of a scenario's window and OCRs it with Apple's Vision framework.
// Protocol: JSON lines on stdin {"id","app","title","url","text"} -> JSON lines {"id","png","ocr_text","ocr_ms"}.
// Usage: shotgen <output-dir>. PNGs are written there (gitignored). No real screen is ever captured.
// This is a deliberately plain render (title bar, address bar, wrapped text). It tests the screenshot -> OCR
// -> text path. It does not test how a vision-language model reads thumbnails or layout.

import AppKit
import Foundation
import Vision

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let width = 1280, height = 800

func draw(app: String, title: String, url: String, text: String) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Title bar (AppKit origin is bottom-left)
    NSColor(white: 0.92, alpha: 1).setFill()
    NSRect(x: 0, y: height - 44, width: width, height: 44).fill()
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.black]
    NSAttributedString(string: "\(app)  -  \(title)", attributes: titleAttrs)
        .draw(in: NSRect(x: 80, y: height - 32, width: width - 120, height: 22))

    var top = height - 44
    if !url.isEmpty {
        NSColor(white: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: top - 40, width: width, height: 40).fill()
        NSColor(white: 0.85, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 80, y: top - 33, width: width - 160, height: 26), xRadius: 13, yRadius: 13).fill()
        NSAttributedString(string: url, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
            .draw(in: NSRect(x: 96, y: top - 29, width: width - 190, height: 20))
        top -= 40
    }

    let para = NSMutableParagraphStyle()
    para.lineSpacing = 6
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black, .paragraphStyle: para])
        .draw(in: NSRect(x: 60, y: 40, width: width - 120, height: top - 80))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func ocr(_ rep: NSBitmapImageRep) -> String {
    guard let cg = rep.cgImage else { return "" }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])
    let lines = (req.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        .compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: "\n")
}

func emit(_ obj: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) {
        print(s); fflush(stdout)
    }
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = req["id"] as? String else { emit(["id": "?", "error": "bad_request"]); continue }
    let t0 = Date()
    guard let rep = draw(app: req["app"] as? String ?? "", title: req["title"] as? String ?? "",
                         url: req["url"] as? String ?? "", text: req["text"] as? String ?? "") else {
        emit(["id": id, "error": "render_failed"]); continue
    }
    let path = (outDir as NSString).appendingPathComponent("\(id).png")
    if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    let text = ocr(rep)
    emit(["id": id, "png": path, "ocr_text": text, "ocr_ms": Int(Date().timeIntervalSince(t0) * 1000)])
}
