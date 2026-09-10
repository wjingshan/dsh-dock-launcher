// 绘制 macOS 应用图标：深色圆角底板 + 绿色拨动开关（ON 状态）+ 品牌字（上 DeepSeek / 下 HARNESS）
// 几何与 Icons.swift（Dock 运行时图标）保持一致。用法: draw_icon <输出 PNG 路径>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreText

// MARK: - 颜色助手（CG 坐标，y 向上；视觉顶部为 y=size）

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let size: CGFloat = 1024

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: draw_icon <out.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func addRounded(_ rect: CGRect, _ radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
}

func fillVerticalGradient(_ rect: CGRect, radius: CGFloat, top: CGColor, bottom: CGColor) {
    ctx.saveGState()
    addRounded(rect, radius)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

// MARK: - 背景：全幅深色圆角底板（浅色扫光，左上亮右下暗）

let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgRadius: CGFloat = 236
// 先铺满画布不透明深底（避免 Dock 上露出透明角/壁纸），再在其上画圆角渐变
ctx.setFillColor(rgb(12, 14, 20))
ctx.fill(bgRect)
ctx.saveGState()
addRounded(bgRect, bgRadius)
ctx.clip()
do {
    let grad = CGGradient(colorsSpace: cs, colors: [rgb(66, 77, 101), rgb(32, 37, 50), rgb(16, 18, 24)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
}
// 底板顶部淡淡的玻璃高光
ctx.setFillColor(rgb(255, 255, 255, 0.055))
ctx.fill(CGRect(x: 0, y: size * 0.86, width: size, height: size * 0.14))
ctx.restoreGState()
// 底板边缘内描边
ctx.saveGState()
addRounded(bgRect.insetBy(dx: 3, dy: 3), bgRadius - 3)
ctx.setStrokeColor(rgb(255, 255, 255, 0.10))
ctx.setLineWidth(5)
ctx.strokePath()
ctx.restoreGState()

// MARK: - 中央拨动开关（与 Dock 图标同几何：0.70 × 0.36 居中，滑块靠右）

let capW = size * 0.70
let capH = size * 0.36
let pillRect = CGRect(x: (size - capW) / 2, y: (size - capH) / 2, width: capW, height: capH)
let pillRadius = pillRect.height / 2

// 1) 胶囊下方的投影（浮起感）
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -70), blur: 100, color: rgb(0, 0, 0, 0.42))
fillVerticalGradient(pillRect, radius: pillRadius, top: rgb(66, 222, 120), bottom: rgb(16, 163, 71))
ctx.restoreGState()

// 2) 绿色渐变胶囊主体（上亮下暗，有立体感）
fillVerticalGradient(pillRect, radius: pillRadius, top: rgb(74, 233, 130), bottom: rgb(22, 175, 77))

// 3) 胶囊顶部高光层（上半部的半透明白，做出玻璃反光）
ctx.saveGState()
addRounded(pillRect, pillRadius)
ctx.clip()
let gloss = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: pillRect.midX, y: pillRect.maxY - 12), end: CGPoint(x: pillRect.midX, y: pillRect.midY), options: [])
ctx.restoreGState()

// 4) 胶囊边缘内描边（轻微受光轮廓）
ctx.saveGState()
addRounded(pillRect.insetBy(dx: 4, dy: 4), pillRadius - 4)
ctx.setStrokeColor(rgb(255, 255, 255, 0.16))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// 5) 白色滑块（带自身投影与垂直渐变）
let knobInset = pillRect.height * 0.12
let knobDiameter = pillRect.height - knobInset * 2
let knobRadius = knobDiameter / 2
let knobCenter = CGPoint(x: pillRect.maxX - knobInset - knobRadius, y: pillRect.midY)
let knobRect = CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius, width: knobDiameter, height: knobDiameter)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -42), blur: 52, color: rgb(0, 0, 0, 0.35))
ctx.beginPath()
ctx.addEllipse(in: knobRect)
ctx.clip()
let knobGrad = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255), rgb(224, 229, 236)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(knobGrad, start: CGPoint(x: knobRect.midX, y: knobRect.maxY), end: CGPoint(x: knobRect.midX, y: knobRect.minY), options: [])
ctx.restoreGState()

// 6) 滑块上的小高光（顶部内弧线）
ctx.saveGState()
ctx.beginPath()
ctx.addEllipse(in: knobRect.insetBy(dx: 16, dy: 16))
ctx.setStrokeColor(rgb(255, 255, 255, 0.55))
ctx.setLineWidth(10)
ctx.setLineCap(CGLineCap.round)
ctx.strokePath()
ctx.restoreGState()

// MARK: - 品牌字（上 DeepSeek / 下 HARNESS），与 Icons.swift 同参数

func drawCTLineText(_ text: String, font: CTFont, color: CGColor, centerX: CGFloat, baselineY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: centerX - w / 2, y: baselineY)
    CTLineDraw(line, ctx)
}

let topFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.135, nil)
let botFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.110, nil)
let topDescent = CTFontGetDescent(topFont)
let botAscent = CTFontGetAscent(botFont)

// 上方 DeepSeek
let gapTop = size * 0.030
let topBaseline = pillRect.maxY + gapTop + topDescent
drawCTLineText("DeepSeek", font: topFont, color: rgb(255, 255, 255, 0.96),
               centerX: pillRect.midX, baselineY: topBaseline)
// 下方 HARNESS
let gapBot = size * 0.042
let botBaseline = pillRect.minY - gapBot - botAscent
drawCTLineText("HARNESS", font: botFont, color: rgb(255, 255, 255, 0.92),
               centerX: pillRect.midX, baselineY: botBaseline)

// MARK: - 输出 PNG

let image = ctx.makeImage()!
let destURL = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(destURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("failed to write png\n".utf8))
    exit(1)
}
print("icon written to \(outPath)")
