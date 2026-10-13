import AppKit
import Carbon
import Combine

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let `default` = CaptureShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | cmdKey))
    static let preferenceKey = "captureShortcut.v1"
    static let keys: [UInt32:String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
        36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"空格",50:"`",
        64:"F17",65:"小键盘 .",67:"小键盘 *",69:"小键盘 +",75:"小键盘 /",76:"小键盘 ↩",78:"小键盘 −",79:"F18",80:"F19",81:"小键盘 =",
        82:"小键盘 0",83:"小键盘 1",84:"小键盘 2",85:"小键盘 3",86:"小键盘 4",87:"小键盘 5",88:"小键盘 6",89:"小键盘 7",91:"小键盘 8",92:"小键盘 9",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",118:"F4",120:"F2",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result:UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
    static func symbols(_ modifiers:UInt32)->String {
        var label=""
        for (flag,symbol) in [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")] {
            if modifiers & UInt32(flag) != 0 { label += symbol }
        }
        return label
    }
    var display:String { Self.symbols(modifiers) + (Self.keys[keyCode] ?? "?") }
    var validationError:String? {
        let mask=UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard modifiers & ~mask == 0, modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return "请至少搭配 Control、Option 或 Command 中的一个键。" }
        guard Self.keys[keyCode] != nil else { return "请使用字母、数字、方向键或功能键。Esc 用于取消录入。" }
        let cmd=UInt32(cmdKey),shiftCmd=UInt32(cmdKey | shiftKey)
        let appKeys:Set<UInt32>=[0,1,6,7,8,9,12,13,31,36,43,45,4]
        if modifiers == cmd && appKeys.contains(keyCode) || modifiers == shiftCmd && [UInt32(6),8].contains(keyCode) {
            return "这个组合用于应用中的常用操作，请再加一个修饰键或换一个键。"
        }
        if keyCode == 49 && [cmd,UInt32(cmdKey | optionKey),UInt32(controlKey)].contains(modifiers) || modifiers == shiftCmd && [UInt32(20),21,23,22].contains(keyCode) {
            return "这个组合通常由 macOS 使用，请选择其他快捷键。"
        }
        return nil
    }
    static func load(from defaults:UserDefaults = .standard)->CaptureShortcut {
        guard let data=defaults.data(forKey:preferenceKey),let value=try? JSONDecoder().decode(Self.self,from:data),value.validationError==nil else { return .default }
        return value
    }
    func save(to defaults:UserDefaults = .standard) { if let data=try? JSONEncoder().encode(self) { defaults.set(data,forKey:Self.preferenceKey) } }
}

@MainActor final class ShortcutController: ObservableObject {
    @Published private(set) var current: CaptureShortcut
    @Published private(set) var registrationError = ""
    private var hotKey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var localMonitor:Any?
    private var activeID:UInt32 = 0
    private let defaults:UserDefaults
    var onPressed:(()->Void)?
    init(defaults:UserDefaults = .standard) { self.defaults=defaults;current=CaptureShortcut.load(from:defaults) }
    func start() {
        guard handler==nil else { return }
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let pointer=Unmanaged.passUnretained(self).toOpaque()
        let result=InstallEventHandler(GetEventDispatcherTarget(),{ _,event,pointer in
            guard let pointer,let event else { return OSStatus(eventNotHandledErr) }
            var id=EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)==noErr else { return OSStatus(eventNotHandledErr) }
            let owner=Unmanaged<ShortcutController>.fromOpaque(pointer).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard id.signature==0x4C534D43,id.id==owner.activeID else { return OSStatus(eventNotHandledErr) }
                owner.onPressed?();return noErr
            }
        },1,&type,pointer,&handler)
        guard result==noErr else { registrationError="无法启动快捷键服务（\(result)）。";return }
        _ = apply(current,persist:false)
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            let handled=MainActor.assumeIsolated { () -> Bool in
                guard let self,self.hotKey != nil,!event.isARepeat,
                      UInt32(event.keyCode)==self.current.keyCode,
                      CaptureShortcut.carbonModifiers(event.modifierFlags)==self.current.modifiers else { return false }
                self.onPressed?();return true
            }
            return handled ? nil : event
        }
    }
    // Register the replacement first. A collision leaves the working shortcut and saved preference intact.
    @discardableResult func apply(_ candidate:CaptureShortcut,persist:Bool = true)->String? {
        if let error=candidate.validationError { return error }
        if candidate==current,hotKey != nil { return nil }
        let nextID=activeID &+ 1
        var replacement:EventHotKeyRef?
        let result=RegisterEventHotKey(candidate.keyCode,candidate.modifiers,EventHotKeyID(signature:0x4C534D43,id:nextID),GetEventDispatcherTarget(),0,&replacement)
        guard result==noErr,let replacement else {
            let message="\(candidate.display) 无法注册，可能已被系统或其他应用占用。请选择其他组合。"
            if hotKey==nil { registrationError=message }
            return message
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey=replacement;activeID=nextID;current=candidate;registrationError=""
        if persist { candidate.save(to:defaults) }
        return nil
    }
    func stop() { if let localMonitor { NSEvent.removeMonitor(localMonitor) };localMonitor=nil;if let hotKey { UnregisterEventHotKey(hotKey) };hotKey=nil;if let handler { RemoveEventHandler(handler) };handler=nil }
}

@MainActor final class SettingsController:NSObject,NSWindowDelegate {
    let shortcuts:ShortcutController
    let window:NSWindow
    let recordButton=NSButton()
    let saveButton=NSButton()
    let feedback=NSTextField(wrappingLabelWithString:"")
    let activeLabel=NSTextField(labelWithString:"")
    private var monitor:Any?
    private(set) var recording=false
    private var draft:CaptureShortcut
    var didSave:(()->Void)?
    init(shortcuts:ShortcutController) {
        self.shortcuts=shortcuts;draft=shortcuts.current
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:530,height:330),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init()
        window.title="轻截 · 设置";window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.delegate=self;window.center()
        let root=NSView();window.contentView=root
        let title=NSTextField(labelWithString:"截图快捷键");title.font = .systemFont(ofSize:20,weight:.semibold)
        let detail=NSTextField(wrappingLabelWithString:"点击下方按钮，然后按下你想使用的组合键。\n快捷键在其他应用中也可使用，保存后立即生效。")
        detail.font = .systemFont(ofSize:13);detail.textColor = .secondaryLabelColor
        recordButton.title=draft.display;recordButton.font = .monospacedSystemFont(ofSize:18,weight:.medium);recordButton.bezelStyle = .rounded;recordButton.target=self;recordButton.action=#selector(beginRecording);recordButton.setAccessibilityLabel("录入截图快捷键")
        activeLabel.font = .systemFont(ofSize:12);activeLabel.textColor = .secondaryLabelColor
        feedback.font = .systemFont(ofSize:12);feedback.textColor = .secondaryLabelColor
        let restore=NSButton(title:"恢复默认",target:self,action:#selector(restoreDefault));restore.bezelStyle = .rounded
        saveButton.title="保存";saveButton.bezelStyle = .rounded;saveButton.keyEquivalent="\r";saveButton.target=self;saveButton.action=#selector(save)
        let cancel=NSButton(title:"取消",target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}"
        let buttons=NSStackView(views:[restore,NSView(),cancel,saveButton]);buttons.orientation = .horizontal;buttons.spacing=10;buttons.distribution = .fill
        let stack=NSStackView(views:[title,detail,recordButton,activeLabel,feedback,buttons]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:25),
            recordButton.widthAnchor.constraint(equalToConstant:260),recordButton.heightAnchor.constraint(equalToConstant:40),detail.widthAnchor.constraint(equalTo:stack.widthAnchor),feedback.widthAnchor.constraint(equalTo:stack.widthAnchor),feedback.heightAnchor.constraint(greaterThanOrEqualToConstant:35),buttons.widthAnchor.constraint(equalTo:stack.widthAnchor)
        ])
        refresh()
    }
    func show() { endRecording();draft=shortcuts.current;feedback.stringValue=shortcuts.registrationError;feedback.textColor = shortcuts.registrationError.isEmpty ? .secondaryLabelColor : .systemRed;refresh();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    func refresh() { recordButton.title=recording ? "按下组合键…（Esc 取消）" : draft.display;activeLabel.stringValue="当前快捷键：\(shortcuts.current.display)";saveButton.isEnabled = !recording }
    @objc func beginRecording() {
        if recording { endRecording();refresh();return }
        recording=true;feedback.stringValue="至少包含 Control、Option 或 Command，搭配一个其他键。";feedback.textColor = .secondaryLabelColor;refresh()
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self,self.recording,event.window===self.window,self.window.isKeyWindow else { return false }
                if event.keyCode==53 { self.endRecording();self.refresh();self.feedback.stringValue="已取消录入，快捷键未更改。" }
                else if !event.isARepeat { self.accept(CaptureShortcut(keyCode:UInt32(event.keyCode),modifiers:CaptureShortcut.carbonModifiers(event.modifierFlags))) }
                return true
            }
            return handled ? nil : event
        }
    }
    func accept(_ candidate:CaptureShortcut) {
        if let error=candidate.validationError { feedback.stringValue=error;feedback.textColor = .systemRed;return }
        endRecording();draft=candidate;feedback.stringValue="点击保存即可启用 \(candidate.display)。";feedback.textColor = .secondaryLabelColor;refresh()
    }
    func endRecording() { recording=false;if let monitor { NSEvent.removeMonitor(monitor) };monitor=nil }
    @objc func save() {
        guard !recording else { return }
        if let error=shortcuts.apply(draft) { feedback.stringValue=error;feedback.textColor = .systemRed;return }
        refresh();feedback.stringValue="已保存，\(shortcuts.current.display) 现在可以截图。";feedback.textColor = .systemGreen;didSave?()
    }
    @objc func restoreDefault() { endRecording();draft = .default;refresh();feedback.stringValue="默认快捷键为 \(draft.display)，点击保存生效。";feedback.textColor = .secondaryLabelColor }
    @objc func cancel() { endRecording();window.performClose(nil) }
    func windowWillClose(_ notification:Notification) { endRecording() }
    func windowDidResignKey(_ notification:Notification) { if recording { endRecording();refresh();feedback.stringValue="已取消录入，快捷键未更改。" } }
}
