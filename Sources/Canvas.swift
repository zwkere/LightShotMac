import AppKit
import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var document: ShotDocument
    var zoom: CGFloat
    func makeNSView(context: Context) -> ShotCanvas { ShotCanvas(document:document) }
    func updateNSView(_ view: ShotCanvas, context: Context) { view.document = document; view.zoom = zoom; view.needsDisplay = true }
}
@MainActor final class ShotCanvas: NSView {
    var document: ShotDocument
    var zoom: CGFloat = 1
    var draft: Mark?
    var down = CGPoint.zero
    var moving: Mark?
    var selectedLines: Set<UUID> = []
    var textDrag: CGRect?
    var textInput: NSTextField?
    var textOrigin = CGPoint.zero
    var editingTextID: UUID?
    init(document: ShotDocument) { self.document = document; super.init(frame:.zero); document.finishEditing = { [weak self] in self?.finishText() } }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor: document.textSelection ? .iBeam : document.tool == .select ? .arrow : .crosshair) }
    var imageRect: CGRect { CGRect(origin:.zero,size:CGSize(width:document.size.width*zoom,height:document.size.height*zoom)) }
    override func draw(_ dirtyRect:NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x:0,y:imageRect.height);ctx.scaleBy(x:zoom,y:-zoom)
        ctx.draw(document.original,in:CGRect(origin:.zero,size:document.size));ctx.restoreGState()
        ctx.saveGState();ctx.scaleBy(x:zoom,y:zoom)
        for mark in document.marks {
            let visible = (moving?.id == mark.id) ? moving! : mark
            Raster.draw(visible,context:ctx,image:document.original)
            if mark.id == document.selected && !document.textSelection {
                let r = hitBounds(visible).insetBy(dx:-6/zoom,dy:-6/zoom)
                ctx.setLineWidth(1.5/zoom);ctx.setStrokeColor(NSColor.systemTeal.cgColor);ctx.setLineDash(phase:0,lengths:[5/zoom,3/zoom]);ctx.stroke(r);ctx.setLineDash(phase:0,lengths:[])
            }
        }
        if let draft { Raster.draw(draft,context:ctx,image:document.original) }
        ctx.restoreGState()
        if document.textSelection {
            for line in document.lines {
                let r = displayRect(line.rect)
                ctx.setFillColor(NSColor.systemTeal.withAlphaComponent(selectedLines.contains(line.id) ? 0.32 : 0.10).cgColor)
                ctx.setStrokeColor(NSColor.systemTeal.withAlphaComponent(0.7).cgColor);ctx.setLineWidth(1)
                ctx.fill(r);ctx.stroke(r)
            }
            if let textDrag { ctx.setStrokeColor(NSColor.systemTeal.cgColor);ctx.stroke(textDrag) }
        }
    }
    func displayRect(_ normalized:CGRect) -> CGRect { CGRect(x:normalized.minX*imageRect.width,y:normalized.minY*imageRect.height,width:normalized.width*imageRect.width,height:normalized.height*imageRect.height) }
    func imagePoint(_ event:NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow,from:nil)
        return CGPoint(x:min(max(0,p.x/zoom),document.size.width),y:min(max(0,p.y/zoom),document.size.height))
    }
    func hitBounds(_ mark:Mark) -> CGRect {
        if mark.tool == .text {
            let size = (mark.text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:max(18,mark.width*6),weight:.semibold)])
            return CGRect(origin:mark.points[0],size:size)
        }
        if mark.tool == .pen {
            let xs = mark.points.map(\.x), ys = mark.points.map(\.y)
            return CGRect(x:xs.min() ?? 0,y:ys.min() ?? 0,width:(xs.max() ?? 0)-(xs.min() ?? 0),height:(ys.max() ?? 0)-(ys.min() ?? 0))
        }
        return mark.rect
    }
    override func mouseDown(with event:NSEvent) {
        finishText()
        window?.makeFirstResponder(self)
        down = imagePoint(event)
        if document.textSelection {
            let p = convert(event.locationInWindow,from:nil)
            selectedLines = Set(document.lines.filter { displayRect($0.rect).insetBy(dx:-3,dy:-3).contains(p) }.map(\.id))
            textDrag = CGRect(origin:p,size:.zero);needsDisplay=true;return
        }
        if document.tool == .select {
            document.selected = document.marks.reversed().first { hitBounds($0).insetBy(dx:-8/zoom,dy:-8/zoom).contains(down) }?.id
            moving = document.marks.first { $0.id == document.selected }
            if event.clickCount == 2, let mark=moving, mark.tool == .text {
                moving=nil;startText(at:mark.points[0],existing:mark)
            }
        } else if document.tool == .text {
            startText(at:down,existing:nil)
        } else {
            draft = Mark(tool:document.tool,points:[down,down],color:document.color,width:document.lineWidth)
        }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        let p = imagePoint(event)
        if document.textSelection {
            let end = convert(event.locationInWindow,from:nil), start=CGPoint(x:down.x*zoom,y:down.y*zoom)
            let r=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(start.x-end.x),height:abs(start.y-end.y))
            textDrag=r;selectedLines=Set(document.lines.filter { displayRect($0.rect).intersects(r) }.map(\.id))
        } else if let original=document.marks.first(where:{$0.id==moving?.id}) {
            moving=original.offset(CGSize(width:p.x-down.x,height:p.y-down.y))
        } else if draft != nil {
            if draft?.tool == .pen { draft?.points.append(p) } else { draft?.points=[down,p] }
        }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        if textInput != nil { return }
        if document.textSelection {
            textDrag=nil
            if !selectedLines.isEmpty { document.copyText(document.lines.filter { selectedLines.contains($0.id) }.map(\.text).joined(separator:"\n")) }
        } else if let moving {
            if let old=document.marks.first(where:{$0.id==moving.id}),old.points != moving.points { document.commit(document.marks.map{$0.id==moving.id ? moving : $0}) }
        } else if let draft {
            if draft.tool == .pen || hypot((draft.points.last?.x ?? down.x)-down.x,(draft.points.last?.y ?? down.y)-down.y)>2 { document.add(draft) }
        }
        moving=nil;draft=nil;needsDisplay=true
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==51 || event.keyCode==117 { document.deleteSelected();return }
        if event.keyCode==53 { document.selected=nil;selectedLines=[];textInput?.removeFromSuperview();textInput=nil;editingTextID=nil;needsDisplay=true;return }
        super.keyDown(with:event)
    }
    func startText(at point:CGPoint,existing:Mark?) {
        textOrigin=point;editingTextID=existing?.id
        let fontSize=max(18,(existing?.width ?? document.lineWidth)*6)*zoom
        let field=NSTextField(frame:CGRect(x:point.x*zoom,y:point.y*zoom,width:min(500,max(120,bounds.width-point.x*zoom)),height:max(36,fontSize*1.5)))
        field.stringValue=existing?.text ?? ""
        field.placeholderString="输入文字，回车完成";field.font = .systemFont(ofSize:fontSize,weight:.semibold)
        field.textColor=existing?.color ?? document.color;field.backgroundColor = .white;field.isBezeled=true;field.focusRingType = .none
        field.target=self;field.action=#selector(textEntered)
        addSubview(field);textInput=field;window?.makeFirstResponder(field)
    }
    @objc func textEntered() { finishText();window?.makeFirstResponder(self) }
    func finishText() {
        guard let field=textInput else { return }
        let value=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        if let id=editingTextID,let old=document.marks.first(where:{$0.id==id}) {
            if old.text != value {
                if value.isEmpty { document.commit(document.marks.filter{$0.id != id}) }
                else { var edited=old;edited.text=value;document.commit(document.marks.map{$0.id==id ? edited : $0}) }
            }
        } else if !value.isEmpty { document.add(Mark(tool:.text,points:[textOrigin],color:document.color,width:document.lineWidth,text:value)) }
        field.removeFromSuperview();textInput=nil;editingTextID=nil;needsDisplay=true
    }
}
