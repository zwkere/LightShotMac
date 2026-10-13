import AppKit
import SwiftUI
import Vision
import UniformTypeIdentifiers

enum DrawingTool: String, CaseIterable, Identifiable {
    case select, rectangle, ellipse, arrow, pen, text, mosaic
    var id: Self { self }
    var title: String { switch self { case .select: return "选择"; case .rectangle: return "矩形"; case .ellipse: return "圆形"; case .arrow: return "箭头"; case .pen: return "画笔"; case .text: return "文字"; case .mosaic: return "马赛克" } }
    var symbol: String { switch self { case .select: return "cursorarrow"; case .rectangle: return "rectangle"; case .ellipse: return "circle"; case .arrow: return "arrow.up.right"; case .pen: return "pencil.tip"; case .text: return "textformat"; case .mosaic: return "square.grid.3x3.fill" } }
}
struct Mark {
    var id = UUID()
    var tool: DrawingTool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    func offset(_ delta: CGSize) -> Mark {
        var result = self
        result.points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return result
    }
}
struct TextLine: Identifiable, Sendable {
    let id = UUID()
    var text: String
    var rect: CGRect // normalized, top-left origin
}
struct Recognizer {
    static func recognize(_ image: CGImage) throws -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> TextLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let r = observation.boundingBox
            return TextLine(text: text, rect: CGRect(x: r.minX, y: 1-r.maxY, width: r.width, height: r.height))
        }
        // Group approximately aligned rows before sorting horizontally, avoiding an inconsistent comparator.
        let sorted = lines.sorted { $0.rect.minY < $1.rect.minY }
        var rows: [[TextLine]] = []
        for line in sorted {
            if let last = rows.last, let first = last.first,
               abs(first.rect.midY-line.rect.midY) < min(first.rect.height, line.rect.height) * 0.5 {
                rows[rows.count-1].append(line)
            } else { rows.append([line]) }
        }
        return rows.flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }
}
@MainActor final class ShotDocument: ObservableObject {
    let original: CGImage
    @Published var zoom: CGFloat = 1
    @Published var fitting = true
    @Published var showText = true
    var finishEditing: (() -> Void)?
    @Published var marks: [Mark] = []
    @Published var tool: DrawingTool = .select
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 4
    @Published var selected: UUID?
    @Published var lines: [TextLine] = []
    @Published var recognizedText = ""
    @Published var isRecognizing = false
    @Published var textSelection = false
    @Published var notice = ""
    @Published var recognitionError = ""
    @Published var undoStack: [[Mark]] = []
    @Published var redoStack: [[Mark]] = []
    private var recognitionID = UUID()
    init(image: CGImage) { original = image }
    var size: CGSize { CGSize(width: original.width, height: original.height) }
    func commit(_ newMarks: [Mark]) {
        undoStack.append(marks)
        marks = newMarks
        redoStack.removeAll()
    }
    func add(_ mark: Mark) { commit(marks + [mark]) }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(marks); marks = previous; selected = nil }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(marks); marks = next; selected = nil }
    func deleteSelected() { guard let selected else { return }; commit(marks.filter { $0.id != selected }); self.selected = nil }
    func rendered() -> CGImage? { finishEditing?(); return Raster.render(original, marks: marks) }
    func copyImage() {
        guard let image = rendered(), let data = Raster.png(image) else { flash("无法生成图片"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        flash("图片已复制，可直接粘贴")
    }
    func copyText(_ text: String? = nil) {
        let value = text ?? recognizedText
        guard !value.isEmpty else { flash("没有可复制的文字"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        flash("文字已复制")
    }
    func flash(_ message: String) {
        notice = message
        Task { try? await Task.sleep(for: .seconds(2.7)); if notice == message { notice = "" } }
    }
    func recognize() {
        guard let image = rendered() else { return }
        let token = UUID(); recognitionID = token
        isRecognizing = true; recognitionError = ""
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try Recognizer.recognize(image) }.value
                guard token == recognitionID else { return }
                lines = result
                recognizedText = result.map(\.text).joined(separator: "\n")
                isRecognizing = false
                if result.isEmpty { recognitionError = "没有识别到文字。试试更清晰或更大的截图。" }
            } catch {
                guard token == recognitionID else { return }
                isRecognizing = false; recognitionError = "识别失败：\(error.localizedDescription)"
            }
        }
    }
    func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "轻截_\(formatter.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url, let image = rendered(), let data = Raster.png(image) else { return }
        do { try data.write(to: url, options: .atomic); flash("图片已保存") } catch { flash("保存失败：\(error.localizedDescription)") }
    }
}
enum Raster {
    static func png(_ image: CGImage) -> Data? { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) }
    static func render(_ image: CGImage, marks: [Mark]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
        ctx.translateBy(x: 0,y: CGFloat(image.height)); ctx.scaleBy(x: 1,y: -1)
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        for mark in marks { draw(mark, context: ctx, image: image) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
    static func draw(_ mark: Mark, context ctx: CGContext, image: CGImage) {
        guard let a = mark.points.first else { return }
        let b = mark.points.last ?? a
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(mark.width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        switch mark.tool {
        case .rectangle: ctx.stroke(mark.rect)
        case .ellipse: ctx.strokeEllipse(in: mark.rect)
        case .pen:
            ctx.beginPath(); ctx.move(to: a)
            if mark.points.count == 1 { ctx.addLine(to: CGPoint(x: a.x+0.1,y:a.y+0.1)) }
            for p in mark.points.dropFirst() { ctx.addLine(to: p) }; ctx.strokePath()
        case .arrow:
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            let angle = atan2(b.y-a.y,b.x-a.x), length = max(15, mark.width*4)
            ctx.move(to: b)
            ctx.addLine(to: CGPoint(x:b.x-length*cos(angle-0.45),y:b.y-length*sin(angle-0.45)))
            ctx.addLine(to: CGPoint(x:b.x-length*cos(angle+0.45),y:b.y-length*sin(angle+0.45)))
            ctx.closePath(); ctx.fillPath()
        case .text:
            let attrs: [NSAttributedString.Key:Any] = [.font: NSFont.systemFont(ofSize: max(18,mark.width*6), weight:.semibold), .foregroundColor:mark.color]
            (mark.text as NSString).draw(at:a,withAttributes:attrs)
        case .mosaic:
            // Deliberately opaque blocks; no translucent sensitive pixels survive export.
            let rect = mark.rect.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
            guard rect.width>0,rect.height>0 else { return }
            let block = max(12,mark.width*5)
            guard let sample = image.cropping(to:rect.integral),
                  let tiny = CGContext(data:nil,width:max(1,Int(ceil(rect.width/block))),height:max(1,Int(ceil(rect.height/block))),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            tiny.interpolationQuality = .low
            tiny.draw(sample,in:CGRect(x:0,y:0,width:tiny.width,height:tiny.height))
            guard let pixels = tiny.makeImage() else { return }
            ctx.clip(to:rect); ctx.interpolationQuality = .none
            ctx.translateBy(x:rect.minX,y:rect.maxY); ctx.scaleBy(x:1,y:-1)
            ctx.draw(pixels,in:CGRect(origin:.zero,size:rect.size))
        case .select: break
        }
    }
    static func crop(_ image: CGImage, selection: CGRect, surface: CGSize) -> CGImage? {
        guard surface.width>0,surface.height>0 else { return nil }
        let rect = CGRect(x:selection.minX*CGFloat(image.width)/surface.width,y:selection.minY*CGFloat(image.height)/surface.height,width:selection.width*CGFloat(image.width)/surface.width,height:selection.height*CGFloat(image.height)/surface.height)
            .integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
        guard rect.width>=2,rect.height>=2 else { return nil }
        return image.cropping(to:rect)
    }
}
