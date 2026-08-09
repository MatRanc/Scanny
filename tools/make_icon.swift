import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Draws an icon matching the in-app About glyph (doc.text.viewfinder): a white
// outlined document with text lines, framed by viewfinder corner brackets, on
// the blue gradient. Core Graphics renders reliably headless.

let N = 1024
let cs = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
let white = color(1, 1, 1)

// Opaque (no alpha), App Store rejects icons with alpha.
guard let ctx = CGContext(
    data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("ctx") }

// Top-left coordinate space (y grows down).
ctx.translateBy(x: 0, y: CGFloat(N))
ctx.scaleBy(x: 1, y: -1)

// Background gradient (matches About: 0.23/0.63/1.0 -> 0.07/0.40/0.88).
let grad = CGGradient(colorsSpace: cs,
                      colors: [color(0.23, 0.63, 1.0), color(0.07, 0.40, 0.88)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: N), options: [])

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(white)
ctx.setFillColor(white)

// Document outline with a folded top-right corner.
let docX: CGFloat = 336, docY: CGFloat = 300, docW: CGFloat = 352, docH: CGFloat = 440
let maxX = docX + docW, maxY = docY + docH
let r: CGFloat = 30, fold: CGFloat = 72

let doc = CGMutablePath()
doc.move(to: CGPoint(x: docX + r, y: docY))
doc.addLine(to: CGPoint(x: maxX - fold, y: docY))
doc.addLine(to: CGPoint(x: maxX, y: docY + fold))
doc.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - r, y: maxY), radius: r)
doc.addArc(tangent1End: CGPoint(x: docX, y: maxY), tangent2End: CGPoint(x: docX, y: maxY - r), radius: r)
doc.addArc(tangent1End: CGPoint(x: docX, y: docY), tangent2End: CGPoint(x: docX + r, y: docY), radius: r)
doc.closeSubpath()
ctx.setLineWidth(24)
ctx.addPath(doc)
ctx.strokePath()

// Text lines.
let lineX = docX + 52
let widths: [CGFloat] = [248, 248, 248, 158]
var lineY: CGFloat = docY + fold + 44
for w in widths {
    let rect = CGRect(x: lineX, y: lineY, width: w, height: 22)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
    lineY += 58
}

// Viewfinder corner brackets framing the document.
ctx.setLineWidth(30)
let arm: CGFloat = 84
let lx: CGFloat = 252, rx: CGFloat = 772, ty: CGFloat = 264, by: CGFloat = 776

func bracket(_ pts: [CGPoint]) {
    let p = CGMutablePath()
    p.move(to: pts[0]); p.addLine(to: pts[1]); p.addLine(to: pts[2])
    ctx.addPath(p); ctx.strokePath()
}
bracket([CGPoint(x: lx, y: ty + arm), CGPoint(x: lx, y: ty), CGPoint(x: lx + arm, y: ty)])
bracket([CGPoint(x: rx - arm, y: ty), CGPoint(x: rx, y: ty), CGPoint(x: rx, y: ty + arm)])
bracket([CGPoint(x: lx, y: by - arm), CGPoint(x: lx, y: by), CGPoint(x: lx + arm, y: by)])
bracket([CGPoint(x: rx - arm, y: by), CGPoint(x: rx, y: by), CGPoint(x: rx, y: by - arm)])

// Write PNG.
guard let image = ctx.makeImage() else { fatalError("image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
guard let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fatalError("dest") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(outPath)")
