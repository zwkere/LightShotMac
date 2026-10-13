import AppKit
import ScreenCaptureKit

@MainActor final class CaptureCoordinator {
    var panels: [CapturePanel] = []
    var busy = false
    var onCapture: ((CGImage)->Void)?
    var onCancel: (()->Void)?
    func start() {
        guard !busy,panels.isEmpty else { return }
        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted { permissionHelp(); return }
            // macOS can require reopening the app after the first grant.
        }
        busy=true
        NSApp.hide(nil)
        Task { [self] in
            do {
                try await Task.sleep(for:.milliseconds(240))
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                var shots: [(NSScreen,CGImage)] = []
                for screen in NSScreen.screens {
                    guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display=content.displays.first(where:{$0.displayID==id.uint32Value}) else { continue }
                    let own=content.applications.filter{$0.processID==ProcessInfo.processInfo.processIdentifier}
                    let filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
                    let config=SCStreamConfiguration()
                    config.width=Int(screen.frame.width*screen.backingScaleFactor)
                    config.height=Int(screen.frame.height*screen.backingScaleFactor)
                    config.showsCursor=false
                    let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                    shots.append((screen,image))
                }
                guard !shots.isEmpty else { throw NSError(domain:"LightShot",code:1,userInfo:[NSLocalizedDescriptionKey:"没有找到可截图的显示器"]) }
                NSApp.unhide(nil);NSApp.activate(ignoringOtherApps:true)
                for (screen,image) in shots {
                    let panel=CapturePanel(screen:screen,image:image)
                    panel.captureView.didFinish={ [weak self] image in self?.finish(image) }
                    panel.captureView.didCancel={ [weak self] in self?.cancel() }
                    panels.append(panel);panel.orderFrontRegardless()
                }
                // Key screen follows the pointer; all displays can still receive mouse selection.
                let mouse=NSEvent.mouseLocation
                let active=panels.first{ $0.frame.contains(mouse) } ?? panels.first
                active?.makeKey();active?.makeFirstResponder(active?.captureView)
                busy=false
            } catch {
                busy=false;NSApp.unhide(nil);NSApp.activate(ignoringOtherApps:true)
                let alert=NSAlert();alert.messageText="截图失败";alert.informativeText="\(error.localizedDescription)\n\n若刚允许屏幕录制，请退出轻截后重新打开。";alert.addButton(withTitle:"好");alert.runModal()
            }
        }
    }
    func finish(_ image:CGImage) { panels.forEach{$0.orderOut(nil)};panels.removeAll();onCapture?(image) }
    func cancel() { panels.forEach{$0.orderOut(nil)};panels.removeAll();onCancel?() }
    func permissionHelp() {
        NSApp.activate(ignoringOtherApps:true)
        let alert=NSAlert();alert.messageText="允许轻截截取屏幕"
        alert.informativeText="请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中开启「轻截」，然后重新打开应用。\n\n文字识别在本机完成。导入图片无需屏幕录制权限。"
        alert.addButton(withTitle:"打开系统设置");alert.addButton(withTitle:"稍后")
        if alert.runModal() == .alertFirstButtonReturn,
           let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
@MainActor final class CapturePanel:NSPanel {
    let captureView:CaptureView
    init(screen:NSScreen,image:CGImage) {
        captureView=CaptureView(image:image)
        super.init(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        title="轻截 · 选择截图区域"
        setFrame(screen.frame,display:false)
        isOpaque=true;backgroundColor = .black;hasShadow=false
        level = .screenSaver;collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        contentView=captureView;isReleasedWhenClosed=false;hidesOnDeactivate=false
    }
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}
@MainActor final class CaptureView:NSView {
    let image:CGImage
    var startPoint:CGPoint?
    var selection=CGRect.zero
    var didFinish:((CGImage)->Void)?
    var didCancel:(()->Void)?
    init(image:CGImage) { self.image=image;super.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
    override func draw(_ dirtyRect:NSRect) {
        guard let ctx=NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState();ctx.translateBy(x:0,y:bounds.height);ctx.scaleBy(x:1,y:-1);ctx.draw(image,in:bounds);ctx.restoreGState()
        let shade=NSBezierPath(rect:bounds)
        if selection.width>0,selection.height>0 { shade.append(NSBezierPath(rect:selection));shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.42).setFill();shade.fill()
        if selection.width>0,selection.height>0 {
            NSColor.systemTeal.setStroke();let outline=NSBezierPath(rect:selection);outline.lineWidth=2;outline.stroke()
            for p in [CGPoint(x:selection.minX,y:selection.minY),CGPoint(x:selection.maxX,y:selection.minY),CGPoint(x:selection.minX,y:selection.maxY),CGPoint(x:selection.maxX,y:selection.maxY)] { NSColor.white.setFill();NSBezierPath(ovalIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)).fill() }
            let w=Int(selection.width*CGFloat(image.width)/bounds.width),h=Int(selection.height*CGFloat(image.height)/bounds.height)
            label("\(w) × \(h) px   松开鼠标开始编辑",at:CGPoint(x:min(selection.minX,bounds.width-290),y:max(16,selection.minY-38)),width:290)
        } else {
            label("拖动选择截图区域    ·    Esc 取消",at:CGPoint(x:(bounds.width-330)/2,y:60),width:330)
        }
    }
    func label(_ text:String,at point:CGPoint,width:CGFloat) {
        NSColor(calibratedWhite:0.08,alpha:0.9).setFill();NSBezierPath(roundedRect:CGRect(origin:point,size:CGSize(width:width,height:32)),xRadius:8,yRadius:8).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:NSColor.white]
        (text as NSString).draw(at:CGPoint(x:point.x+12,y:point.y+8),withAttributes:attrs)
    }
    override func mouseDown(with event:NSEvent) { window?.makeKey();window?.makeFirstResponder(self);startPoint=convert(event.locationInWindow,from:nil);selection = .zero;needsDisplay=true }
    override func mouseDragged(with event:NSEvent) {
        guard let a=startPoint else { return }
        let raw=convert(event.locationInWindow,from:nil),b=CGPoint(x:min(max(raw.x,0),bounds.width),y:min(max(raw.y,0),bounds.height))
        selection=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y));needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        mouseDragged(with:event)
        if selection.width>=4,selection.height>=4,let crop=Raster.crop(image,selection:selection,surface:bounds.size) { didFinish?(crop) }
        else { startPoint=nil;selection = .zero;needsDisplay=true }
    }
    override func rightMouseDown(with event:NSEvent) { didCancel?() }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 { didCancel?() }
        else if event.keyCode==36,let crop=Raster.crop(image,selection:selection,surface:bounds.size) { didFinish?(crop) }
        else { super.keyDown(with:event) }
    }
}
