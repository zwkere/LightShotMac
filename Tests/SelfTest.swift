import AppKit
import Carbon

@MainActor enum SelfTest {
    static func fixture()->CGImage {
        let ctx=CGContext(data:nil,width:960,height:600,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:960,height:600))
        ctx.translateBy(x:0,y:600);ctx.scaleBy(x:1,y:-1)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
        let teal=NSColor(red:0.06,green:0.56,blue:0.51,alpha:1)
        teal.setFill();NSBezierPath(roundedRect:CGRect(x:50,y:45,width:92,height:28),xRadius:14,yRadius:14).fill()
        ("OCR DEMO" as NSString).draw(at:CGPoint(x:62,y:50),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.bold),.foregroundColor:NSColor.white])
        ("把截图，变成可用的文字。" as NSString).draw(at:CGPoint(x:50,y:112),withAttributes:[.font:NSFont.systemFont(ofSize:42,weight:.semibold),.foregroundColor:NSColor.black])
        ("Swift OCR · 轻截本地识别" as NSString).draw(at:CGPoint(x:50,y:193),withAttributes:[.font:NSFont.systemFont(ofSize:27),.foregroundColor:teal])
        ("选中、修改、复制文字，一气呵成。" as NSString).draw(at:CGPoint(x:50,y:260),withAttributes:[.font:NSFont.systemFont(ofSize:28),.foregroundColor:NSColor.darkGray])
        ("Hello macOS 12345" as NSString).draw(at:CGPoint(x:50,y:323),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:27,weight:.regular),.foregroundColor:NSColor.black])
        NSColor(calibratedWhite:0.94,alpha:1).setFill();NSBezierPath(roundedRect:CGRect(x:50,y:405,width:860,height:130),xRadius:16,yRadius:16).fill()
        ("使用上方工具栏，画一个框或添加箭头。" as NSString).draw(at:CGPoint(x:73,y:431),withAttributes:[.font:NSFont.systemFont(ofSize:24),.foregroundColor:NSColor.darkGray])
        ("点击「图上选字」，直接复制截图中的文字。" as NSString).draw(at:CGPoint(x:73,y:479),withAttributes:[.font:NSFont.systemFont(ofSize:24),.foregroundColor:NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState();return ctx.makeImage()!
    }
    static func run()->Int32 {
        var failures=0
        func check(_ value:Bool,_ name:String) { print("\(value ? "PASS" : "FAIL") \(name)");if !value { failures+=1 } }
        check(CaptureShortcut.default.display == "⌃⌘A", "default shortcut display")
        check(CaptureShortcut(keyCode:0,modifiers:0).validationError != nil, "reject unmodified typing keys")
        check(CaptureShortcut(keyCode:0,modifiers:UInt32(shiftKey)).validationError != nil, "reject shift-only typing keys")
        check(CaptureShortcut(keyCode:12,modifiers:UInt32(cmdKey)).validationError != nil, "protect app command shortcuts")
        let suite="local.zwkere.lightshot.test.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(Data("bad data".utf8),forKey:CaptureShortcut.preferenceKey)
        check(CaptureShortcut.load(from:defaults) == .default, "recover from invalid saved shortcut")
        let modifiers=UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let first=CaptureShortcut(keyCode:80,modifiers:modifiers)
        let second=CaptureShortcut(keyCode:79,modifiers:modifiers)
        first.save(to:defaults)
        check(CaptureShortcut.load(from:defaults)==first,"persist and reload custom shortcut")
        let controller=ShortcutController(defaults:defaults)
        controller.start()
        check(controller.registrationError.isEmpty,"register custom global shortcut")
        var blocker:EventHotKeyRef?
        let blocked=RegisterEventHotKey(second.keyCode,second.modifiers,EventHotKeyID(signature:0x54455354,id:999),GetEventDispatcherTarget(),0,&blocker)
        check(blocked==noErr,"reserve shortcut for conflict test")
        if blocked==noErr {
            check(controller.apply(second) != nil && controller.current==first && CaptureShortcut.load(from:defaults)==first,"collision preserves current and saved shortcut")
            if let blocker { UnregisterEventHotKey(blocker) }
        }
        check(controller.apply(second)==nil && controller.current==second && CaptureShortcut.load(from:defaults)==second,"switch shortcut and persist only after success")
        var reclaimed:EventHotKeyRef?
        let free=RegisterEventHotKey(first.keyCode,first.modifiers,EventHotKeyID(signature:0x54455354,id:998),GetEventDispatcherTarget(),0,&reclaimed)
        check(free==noErr,"release previous global shortcut after replacement")
        if let reclaimed { UnregisterEventHotKey(reclaimed) }
        var pressed=0
        controller.onPressed={ pressed += 1 }
        var event:EventRef?
        let created=CreateEvent(nil,UInt32(kEventClassKeyboard),UInt32(kEventHotKeyPressed),GetCurrentEventTime(),EventAttributes(kEventAttributeUserEvent),&event)
        if created==noErr,let event {
            var keyID=EventHotKeyID(signature:0x4C534D43,id:2)
            SetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),MemoryLayout<EventHotKeyID>.size,&keyID)
            let delivered=SendEventToEventTarget(event,GetEventDispatcherTarget())
            check(delivered==noErr && pressed==1,"dispatch registered Carbon hotkey to screenshot callback")
            keyID.id=1
            SetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),MemoryLayout<EventHotKeyID>.size,&keyID)
            _ = SendEventToEventTarget(event,GetEventDispatcherTarget())
            check(pressed==1,"ignore queued events from the replaced shortcut")
            ReleaseEvent(event)
        } else { check(false,"create hotkey integration event") }
        controller.stop()
        let image=fixture()
        check(image.width==960 && image.height==600,"fixture dimensions")
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("test-results")
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try? Raster.png(image)?.write(to:directory.appendingPathComponent("fixture.png"))
        let crop=Raster.crop(image,selection:CGRect(x:25,y:50,width:150,height:100),surface:CGSize(width:480,height:300))
        check(crop?.width==300 && crop?.height==200,"Retina 2x crop coordinates")
        check(Raster.crop(image,selection:CGRect(x:0,y:0,width:0,height:0),surface:CGSize(width:480,height:300))==nil,"reject zero-sized crop")
        if let crop { try? Raster.png(crop)?.write(to:directory.appendingPathComponent("crop.png")) }
        let doc=ShotDocument(image:image)
        let rect=Mark(tool:.rectangle,points:[CGPoint(x:40,y:100),CGPoint(x:730,y:165)],color:.systemRed,width:4)
        doc.add(rect);check(doc.marks.count==1 && doc.undoStack.count==1,"add annotation")
        doc.undo();check(doc.marks.isEmpty && doc.redoStack.count==1,"undo annotation")
        doc.redo();check(doc.marks.count==1 && doc.redoStack.isEmpty,"redo annotation")
        doc.selected=rect.id;doc.deleteSelected();check(doc.marks.isEmpty,"delete selected annotation")
        doc.undo();doc.add(Mark(tool:.arrow,points:[CGPoint(x:780,y:290),CGPoint(x:700,y:330)],color:.systemRed,width:5))
        doc.add(Mark(tool:.ellipse,points:[CGPoint(x:700,y:190),CGPoint(x:900,y:255)],color:.systemBlue,width:4))
        doc.add(Mark(tool:.pen,points:[CGPoint(x:60,y:370),CGPoint(x:150,y:380),CGPoint(x:270,y:375)],color:.systemOrange,width:6))
        doc.add(Mark(tool:.text,points:[CGPoint(x:680,y:55)],color:.systemRed,width:4,text:"测试标注"))
        doc.add(Mark(tool:.mosaic,points:[CGPoint(x:53,y:323),CGPoint(x:347,y:355)],color:.black,width:7))
        let rendered=doc.rendered();check(rendered?.width==960 && rendered?.height==600,"render every annotation at native resolution")
        if let rendered { let png=Raster.png(rendered);check(png != nil,"PNG encoding");try? png?.write(to:directory.appendingPathComponent("annotated.png")) }
        do {
            let lines=try Recognizer.recognize(image),text=lines.map(\.text).joined(separator:"\n")
            print("OCR:\n\(text)")
            check(text.contains("Swift") && text.contains("12345"),"English OCR and digits")
            check(text.contains("复制") && text.contains("截图"),"Chinese OCR")
            check(lines.allSatisfy{$0.rect.minY>=0 && $0.rect.maxY<=1 && $0.rect.width>0},"OCR boxes use top-left normalized coordinates")
            try text.write(to:directory.appendingPathComponent("ocr.txt"),atomically:true,encoding:.utf8)
            if let crop {
                let cropText=try Recognizer.recognize(crop).map(\.text).joined()
                check(cropText.contains("截图"),"crop contains the expected top-left text")
            }
        } catch { check(false,"OCR error: \(error)") }
        print("\(failures==0 ? "ALL CHECKS PASSED" : "\(failures) CHECKS FAILED")")
        return failures==0 ? 0:1
    }
}
