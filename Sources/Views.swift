import AppKit
import SwiftUI

let accent = Color(red:0.06,green:0.56,blue:0.51)
struct HomeView:View {
    @ObservedObject var shortcuts:ShortcutController
    let showSettings:()->Void
    let capture:()->Void
    let importImage:()->Void
    let pasteImage:()->Void
    var body:some View {
        VStack(spacing:0) {
            HStack { Label("轻截",systemImage:"viewfinder").font(.system(size:18,weight:.semibold));Spacer();Text("为文字与灵感，截取一刻").foregroundStyle(.secondary).font(.system(size:12)) }.padding(24)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius:26).fill(accent.opacity(0.08)).frame(width:110,height:110)
                Image(systemName:"viewfinder").font(.system(size:51,weight:.light)).foregroundStyle(accent)
                Image(systemName:"text.viewfinder").font(.system(size:20)).foregroundStyle(accent).padding(8).background(.background,in:RoundedRectangle(cornerRadius:9)).offset(x:42,y:40)
            }
            Text("截图，即刻变成文字").font(.system(size:29,weight:.semibold)).padding(.top,25)
            Text("选一块屏幕，标注重点，复制图片或文字。\n中文与英文识别，全部在本机完成。")
                .font(.system(size:14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top,9)
            Button(action:capture) { HStack(spacing:12) { Image(systemName:"plus.viewfinder");Text("开始截图").fontWeight(.semibold);Text(shortcuts.current.display).font(.system(size:12,design:.monospaced)).opacity(0.8) }.padding(.horizontal,25).padding(.vertical,12) }.buttonStyle(.plain).foregroundStyle(.white).background(accent,in:RoundedRectangle(cornerRadius:10)).padding(.top,27).keyboardShortcut("n",modifiers:.command)
            HStack(spacing:18) {
                Button(action:importImage) { Label("打开图片",systemImage:"photo") }.keyboardShortcut("o",modifiers:.command)
                Button(action:pasteImage) { Label("粘贴图片",systemImage:"doc.on.clipboard") }.keyboardShortcut("v",modifiers:.command)
                Button(action:showSettings) { Label("设置",systemImage:"gearshape") }
            }.buttonStyle(.plain).font(.system(size:13)).foregroundStyle(.secondary).padding(.top,18)
            if !shortcuts.registrationError.isEmpty { Text(shortcuts.registrationError).font(.system(size:11)).foregroundStyle(.red).padding(.horizontal,40).padding(.top,12) }
            Spacer()
            HStack(spacing:28) { feature("pencil.tip","轻松标注");feature("text.viewfinder","本地 OCR");feature("doc.on.doc","一键复制") }.padding(.bottom,29)
            Divider()
            HStack { Image(systemName:"menubar.rectangle");Text("也可以从顶部菜单栏快速截图");Spacer();Text("轻截 1.1").foregroundStyle(.tertiary) }.font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,24).padding(.vertical,14)
        }.frame(minWidth:620,minHeight:520).background(Color(nsColor:.windowBackgroundColor))
    }
    func feature(_ icon:String,_ title:String)->some View { Label(title,systemImage:icon).font(.system(size:12)).foregroundStyle(.secondary) }
}
struct EditorView:View {
    @ObservedObject var document:ShotDocument
    let capture:()->Void
    let colors:[NSColor]=[.systemRed,.systemOrange,.systemYellow,.systemGreen,.systemBlue,.systemPurple,.white,.black]
    var body:some View {
        VStack(spacing:0) {
            header
            Divider()
            HStack(spacing:0) {
                VStack(spacing:0) {
                    tools
                    Divider()
                    GeometryReader { geometry in
                        let fit=min((geometry.size.width-72)/document.size.width,(geometry.size.height-60)/document.size.height,1)
                        let scale=document.fitting ? max(0.05,fit) : document.zoom
                        ScrollView([.horizontal,.vertical]) {
                            CanvasRepresentable(document:document,zoom:scale)
                                .frame(width:document.size.width*scale,height:document.size.height*scale)
                                .background(.white).shadow(color:.black.opacity(0.17),radius:15,y:5)
                                .padding(36)
                                .frame(minWidth:geometry.size.width,minHeight:geometry.size.height)
                        }
                        .background(Color(nsColor:NSColor(calibratedWhite:0.92,alpha:1)))
                    }
                    footer
                }.frame(minWidth:530)
                if document.showText { Divider();textSidebar.frame(width:300) }
            }
        }.frame(minWidth:900,minHeight:620).background(Color(nsColor:.windowBackgroundColor))
        .onAppear { document.recognize() }
    }
    var header:some View {
        HStack(spacing:12) {
            Image(systemName:"viewfinder").font(.system(size:20,weight:.medium)).foregroundStyle(accent)
            VStack(alignment:.leading,spacing:3) { Text("截图编辑").font(.system(size:15,weight:.semibold));Text("\(document.original.width) × \(document.original.height) px").font(.system(size:11)).foregroundStyle(.secondary) }
            Spacer()
            Button(action:capture) { Label("新截图",systemImage:"plus.viewfinder") }.keyboardShortcut("n",modifiers:.command)
            Button { document.showText.toggle() } label:{ Image(systemName:"sidebar.right") }.help("显示 / 隐藏文字面板")
            Button { document.save() } label:{ Label("保存",systemImage:"square.and.arrow.down") }.keyboardShortcut("s",modifiers:.command)
            Button { document.copyImage() } label:{ Label("复制图片",systemImage:"doc.on.doc").fontWeight(.semibold) }.buttonStyle(.borderedProminent).tint(accent).keyboardShortcut(.return,modifiers:.command)
        }.buttonStyle(.bordered).controlSize(.regular).padding(.horizontal,20).padding(.vertical,15)
    }
    var tools:some View {
        HStack(spacing:5) {
            ForEach(DrawingTool.allCases) { tool in
                Button { document.textSelection=false;document.tool=tool } label: {
                    Image(systemName:tool.symbol).font(.system(size:16)).frame(width:33,height:31)
                        .foregroundStyle(document.tool==tool && !document.textSelection ? accent : Color.primary)
                        .background(document.tool==tool && !document.textSelection ? accent.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).help(tool.title)
            }
            Divider().frame(height:22).padding(.horizontal,5)
            ColorPicker("标注颜色", selection: Binding(get: { Color(nsColor:document.color) }, set: { document.color=NSColor($0) }), supportsOpacity:false)
                .labelsHidden().frame(width:27).help("标注颜色")
            Menu {
                ForEach([CGFloat(2),4,7,11],id:\.self) { width in Button("\(Int(width)) px") { document.lineWidth=width } }
            } label:{ Text("\(Int(document.lineWidth)) px").font(.system(size:11)).frame(width:40) }.menuStyle(.borderlessButton).fixedSize().help("笔画粗细 / 文字大小")
            Spacer(minLength:2)
            Button { document.undo() } label:{ Image(systemName:"arrow.uturn.backward") }.disabled(document.undoStack.isEmpty).help("撤销 ⌘Z").keyboardShortcut("z",modifiers:.command)
            Button { document.redo() } label:{ Image(systemName:"arrow.uturn.forward") }.disabled(document.redoStack.isEmpty).help("重做 ⇧⌘Z").keyboardShortcut("z",modifiers:[.command,.shift])
        }.buttonStyle(.plain).padding(.horizontal,16).padding(.vertical,9)
    }
    var footer:some View {
        HStack(spacing:10) {
            if !document.notice.isEmpty { Image(systemName:"checkmark.circle.fill").foregroundStyle(accent);Text(document.notice).foregroundStyle(accent) }
            else { Text(document.textSelection ? "点击文字或框选多行，自动复制" : document.tool == .select ? "选择标注可拖动 · Delete 删除" : document.tool == .text ? "点击图片输入文字 · 回车完成" : "在图片上拖动以添加\(document.tool.title)").foregroundStyle(.secondary) }
            Spacer()
            Button { document.fitting=true } label:{ Text("适应") }.foregroundStyle(document.fitting ? accent : .secondary)
            Button { if document.fitting { document.zoom=1 };document.fitting=false;document.zoom=max(0.1,document.zoom/1.25) } label:{ Image(systemName:"minus.magnifyingglass") }
            Text(document.fitting ? "自动" : "\(Int(document.zoom*100))%").monospacedDigit().frame(width:38)
            Button { if document.fitting { document.zoom=1 };document.fitting=false;document.zoom=min(3,document.zoom*1.25) } label:{ Image(systemName:"plus.magnifyingglass") }
        }.buttonStyle(.plain).font(.system(size:11)).padding(.horizontal,16).padding(.vertical,12)
    }
    var textSidebar:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Label("识别文字",systemImage:"text.viewfinder").font(.system(size:14,weight:.semibold));Spacer();if document.isRecognizing { ProgressView().controlSize(.small) } else { Text("本地 OCR").font(.system(size:10)).foregroundStyle(accent).padding(.horizontal,7).padding(.vertical,4).background(accent.opacity(0.09),in:Capsule()) } }.padding(18)
            Text("选中文字后按 ⌘C 复制，也可以直接修改。")
                .font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,18).padding(.bottom,13)
            HStack(spacing:8) {
                Button { document.recognize() } label:{ Label("重新识别",systemImage:"arrow.clockwise") }.disabled(document.isRecognizing)
                Button { document.textSelection.toggle();document.selected=nil } label:{ Label("图上选字",systemImage:"cursorarrow.and.square.on.square.dashed") }
                    .tint(document.textSelection ? accent : nil).disabled(document.lines.isEmpty)
            }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal,18).padding(.bottom,15)
            Divider()
            if document.isRecognizing && document.recognizedText.isEmpty {
                VStack(spacing:10) { ProgressView();Text("正在识别截图中的文字…").font(.system(size:12)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if !document.recognitionError.isEmpty && document.recognizedText.isEmpty {
                VStack(spacing:12) { Image(systemName:"text.magnifyingglass").font(.system(size:30)).foregroundStyle(.tertiary);Text(document.recognitionError).font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                NativeTextEditor(text:$document.recognizedText).padding(10).background(Color(nsColor:.textBackgroundColor))
            }
            Divider()
            HStack { Text("\(document.recognizedText.count) 字符").font(.system(size:11)).foregroundStyle(.secondary);Spacer();Text("可编辑 · 可选择").font(.system(size:10)).foregroundStyle(.tertiary) }.padding(.horizontal,18).padding(.top,12)
            Button { document.copyText() } label:{ Label("复制全部文字",systemImage:"doc.on.doc").frame(maxWidth:.infinity).padding(.vertical,5) }.buttonStyle(.borderedProminent).tint(accent).disabled(document.recognizedText.isEmpty).keyboardShortcut("c",modifiers:[.command,.shift]).padding(16)
        }.background(Color(nsColor:.windowBackgroundColor))
    }
    func colorName(_ color:NSColor)->String {
        if color == .systemRed { return "红色" };if color == .systemOrange { return "橙色" };if color == .systemYellow { return "黄色" };if color == .systemGreen { return "绿色" };if color == .systemBlue { return "蓝色" };if color == .systemPurple { return "紫色" };if color == .white { return "白色" };return "黑色"
    }
}
struct NativeTextEditor:NSViewRepresentable {
    @Binding var text:String
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=true;scroll.borderType = .noBorder
        let view=NSTextView(frame:NSRect(x:0,y:0,width:280,height:400));view.minSize=NSSize(width:0,height:0);view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);view.isRichText=false;view.isEditable=true;view.isSelectable=true;view.font = .systemFont(ofSize:14);view.textContainerInset=CGSize(width:8,height:12);view.autoresizingMask=[.width];view.isVerticallyResizable=true;view.isHorizontallyResizable=false
        view.textContainer?.widthTracksTextView=true;view.delegate=context.coordinator
        view.string=text;scroll.documentView=view;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) { context.coordinator.parent=self;guard let view=scroll.documentView as? NSTextView else{return};if view.string != text { view.string=text } }
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:NativeTextEditor
        init(_ parent:NativeTextEditor) {self.parent=parent}
        func textDidChange(_ notification:Notification) { if let view=notification.object as? NSTextView { parent.text=view.string } }
    }
}
