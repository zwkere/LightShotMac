import AppKit
let dir=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let n=size*scale
        let image=NSImage(size:NSSize(width:n,height:n))
        image.lockFocus()
        let factor=CGFloat(n)/1024
        let context=NSGraphicsContext.current!.cgContext
        context.scaleBy(x:factor,y:factor)
        NSColor(red:0.03,green:0.53,blue:0.49,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:205,yRadius:205).fill()
        let gradient=NSGradient(starting:NSColor(red:0.10,green:0.72,blue:0.63,alpha:1),ending:NSColor(red:0.02,green:0.41,blue:0.43,alpha:1))!
        gradient.draw(in:NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:205,yRadius:205),angle:-90)
        NSColor.white.setStroke()
        let path=NSBezierPath();path.lineWidth=43;path.lineCapStyle = .round;path.lineJoinStyle = .round
        for (x,y,dx,dy) in [(CGFloat(255),CGFloat(755),CGFloat(1),CGFloat(-1)),(769,755,-1,-1),(255,269,1,1),(769,269,-1,1)] {
            path.move(to:NSPoint(x:x,y:y+dy*130));path.line(to:NSPoint(x:x,y:y));path.line(to:NSPoint(x:x+dx*130,y:y))
        }
        path.stroke()
        NSColor.white.setFill()
        for (y,w) in [(CGFloat(590),CGFloat(270)),(505,270),(420,175)] { NSBezierPath(roundedRect:NSRect(x:377,y:y,width:w,height:28),xRadius:14,yRadius:14).fill() }
        image.unlockFocus()
        let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
        let suffix=scale==2 ? "@2x" : ""
        try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
