import AppKit
import SwiftUI
import Carbon

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    var statusItem:NSStatusItem?
    var home:NSWindow?
    var editors:[NSWindow]=[]
    let captureCoordinator=CaptureCoordinator()
    let shortcuts=ShortcutController()
    var settings:SettingsController?
    var captureMenuItem:NSMenuItem?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        makeMenus()
        makeStatusItem()
        shortcuts.onPressed={ [weak self] in
            guard let self else { return }
            if let settings=self.settings,settings.recording { settings.accept(self.shortcuts.current) }
            else { self.newCapture() }
        }
        shortcuts.start()
        captureCoordinator.onCapture={ [weak self] image in self?.showEditor(image) }
        captureCoordinator.onCancel={ NSApp.activate(ignoringOtherApps:true) }
        if CommandLine.arguments.contains("--demo") { showEditor(SelfTest.fixture()) } else { showHome() }
        NSApp.activate(ignoringOtherApps:true)
    }
    func makeMenus() {
        let main=NSMenu()
        let appMenu=NSMenu()
        appMenu.addItem(item("关于轻截",#selector(about),""));appMenu.addItem(item("设置…",#selector(showSettings),","));appMenu.addItem(.separator())
        appMenu.addItem(item("屏幕录制权限…",#selector(permission),""));appMenu.addItem(.separator())
        appMenu.addItem(item("隐藏轻截",#selector(NSApplication.hide(_:)),"h",target:NSApp))
        appMenu.addItem(item("退出轻截",#selector(NSApplication.terminate(_:)),"q",target:NSApp))
        let appRoot=NSMenuItem();appRoot.submenu=appMenu;main.addItem(appRoot)
        let file=NSMenu(title:"文件")
        file.addItem(item("新截图",#selector(newCapture),"n"))
        file.addItem(item("打开图片…",#selector(openImage),"o"))
        file.addItem(item("粘贴图片",#selector(pasteImage),"",target:self))
        file.addItem(.separator());file.addItem(item("保存图片…",#selector(saveImage),"s"));file.addItem(item("复制图片",#selector(copyImage),"\r"))
        file.addItem(.separator());file.addItem(item("关闭窗口",#selector(NSWindow.performClose(_:)),"w",target:nil))
        let fileRoot=NSMenuItem(title:"文件",action:nil,keyEquivalent:"");fileRoot.submenu=file;main.addItem(fileRoot)
        let edit=NSMenu(title:"编辑")
        edit.addItem(item("撤销标注",#selector(undoMark),"z"));let redo=item("重做标注",#selector(redoMark),"z");redo.keyEquivalentModifierMask=[.command,.shift];edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("剪切",#selector(NSText.cut(_:)),"x",target:nil));edit.addItem(item("复制",#selector(NSText.copy(_:)),"c",target:nil));edit.addItem(item("粘贴",#selector(NSText.paste(_:)),"v",target:nil));edit.addItem(item("全选",#selector(NSText.selectAll(_:)),"a",target:nil))
        edit.addItem(.separator());let copyAll=item("复制全部识别文字",#selector(copyAllText),"c");copyAll.keyEquivalentModifierMask=[.command,.shift];edit.addItem(copyAll)
        let editRoot=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");editRoot.submenu=edit;main.addItem(editRoot)
        let windowMenu=NSMenu(title:"窗口");windowMenu.addItem(item("显示主窗口",#selector(showHome),"0"))
        let windowRoot=NSMenuItem(title:"窗口",action:nil,keyEquivalent:"");windowRoot.submenu=windowMenu;main.addItem(windowRoot)
        NSApp.mainMenu=main;NSApp.windowsMenu=windowMenu
    }
    func item(_ title:String,_ action:Selector,_ key:String,target:AnyObject?=nil)->NSMenuItem {
        let value=NSMenuItem(title:title,action:action,keyEquivalent:key)
        value.target=target ?? self
        // Responder chain actions must not target AppDelegate.
        if [#selector(NSText.cut(_:)),#selector(NSText.copy(_:)),#selector(NSText.paste(_:)),#selector(NSText.selectAll(_:)),#selector(NSWindow.performClose(_:))].contains(action) { value.target=nil }
        return value
    }
    func makeStatusItem() {
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem?.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:"轻截")
        let menu=NSMenu();let captureItem=item("开始截图    \(shortcuts.current.display)",#selector(newCapture),"");captureMenuItem=captureItem;menu.addItem(captureItem);menu.addItem(item("打开图片…",#selector(openImage),""));menu.addItem(item("粘贴图片",#selector(pasteImage),""));menu.addItem(.separator());menu.addItem(item("显示主窗口",#selector(showHome),""));menu.addItem(item("设置…",#selector(showSettings),""));menu.addItem(item("屏幕录制权限…",#selector(permission),""));menu.addItem(.separator());menu.addItem(item("退出轻截",#selector(NSApplication.terminate(_:)),"",target:NSApp));statusItem?.menu=menu
    }
    @objc func showSettings() {
        if settings==nil {
            settings=SettingsController(shortcuts:shortcuts)
            settings?.didSave={ [weak self] in self?.captureMenuItem?.title="开始截图    \(self?.shortcuts.current.display ?? "")" }
        }
        settings?.show()
    }
    @objc func showHome() {
        if home == nil {
            let root=HomeView(shortcuts:shortcuts,showSettings:{[weak self] in self?.showSettings()},capture:{[weak self] in self?.newCapture()},importImage:{[weak self] in self?.openImage()},pasteImage:{[weak self] in self?.pasteImage()})
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:560),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="轻截";window.titlebarAppearsTransparent=true;window.contentView=NSHostingView(rootView:root);window.minSize=NSSize(width:620,height:540);window.isReleasedWhenClosed=false;window.center();home=window
        }
        home?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func showEditor(_ image:CGImage) {
        let document=ShotDocument(image:image)
        let root=EditorView(document:document,capture:{ [weak self] in self?.newCapture() })
        let window=EditorWindow(document:document)
        window.title="轻截 · 截图编辑";window.contentView=NSHostingView(rootView:root)
        window.titlebarAppearsTransparent=true;window.minSize=NSSize(width:900,height:640);window.isReleasedWhenClosed=false
        if let screen=NSScreen.main {
            let frame=screen.visibleFrame
            window.setContentSize(NSSize(width:min(1180,frame.width-60),height:min(780,frame.height-80)))
        }
        window.center();editors.removeAll{ !$0.isVisible };editors.append(window)
        home?.orderOut(nil);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    var document:ShotDocument? { (NSApp.keyWindow as? EditorWindow)?.document }
    @objc func newCapture() { captureCoordinator.start() }
    @objc func permission() { captureCoordinator.permissionHelp() }
    @objc func openImage() {
        NSApp.activate(ignoringOtherApps:true)
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        if panel.runModal() == .OK,let url=panel.url { loadImage(url) }
    }
    func loadImage(_ url:URL) {
        guard let image=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { error("无法打开这张图片。请使用 PNG、JPEG 或 TIFF 文件。");return }
        showEditor(image)
    }
    @objc func pasteImage() {
        guard let image=NSImage(pasteboard:.general)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { error("剪贴板中没有图片。请先复制一张图片。");return };showEditor(image)
    }
    @objc func saveImage() { document?.save() }
    @objc func copyImage() { document?.copyImage() }
    @objc func copyAllText() { document?.copyText() }
    @objc func undoMark() { document?.undo() }
    @objc func redoMark() { document?.redo() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"轻截",.applicationVersion:"1.1.0",.version:"2",.credits:NSAttributedString(string:"区域截图 · 标注修改 · 本地 OCR\n快捷键 \(shortcuts.current.display) / 复制图片 ⌘↩ / 复制全文 ⇧⌘C\n\n使用 Apple ScreenCaptureKit 与 Vision，识别过程无需联网。")])
    }
    func error(_ message:String) { NSApp.activate(ignoringOtherApps:true);let alert=NSAlert();alert.messageText="轻截";alert.informativeText=message;alert.runModal() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { if !flag { showHome() };return true }
    func application(_ sender:NSApplication,openFiles filenames:[String]) { for path in filenames { loadImage(URL(fileURLWithPath:path)) };sender.reply(toOpenOrPrint:.success) }
    func applicationWillTerminate(_ notification:Notification) { settings?.endRecording();shortcuts.stop() }
}
@MainActor final class EditorWindow:NSWindow {
    let document:ShotDocument
    init(document:ShotDocument) {
        self.document=document
        super.init(contentRect:NSRect(x:0,y:0,width:1120,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    }
}
