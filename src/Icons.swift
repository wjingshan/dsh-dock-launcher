// Icons.swift — 开关图标绘制（Dock 图标 + 菜单栏小图标）
// 用 AppKit/CoreText 绘制「拨动开关 + 品牌字」图形，按状态改变颜色与滑块位置。
import AppKit
import CoreText

enum LiveState {
    case off       // 服务已停止（红色，滑块在左）
    case running   // 服务运行中、空闲（绿色，滑块在右）
    case busy      // 任务运行中（蓝色，滑块在右）
    case confirm   // 任务需要确认（橙色，滑块在右）
    case complete  // 任务刚完成（绿色，短暂过渡）
}

/// 各状态的视觉参数
private func stateStyle(_ state: LiveState) -> (capsule: NSColor, knobRight: Bool) {
    switch state {
    case .off:
        // 关闭态：红色（断电隐喻），滑块拨到左侧
        return (NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.30, alpha: 1), false)
    case .running:
        return (NSColor(calibratedRed: 0.11, green: 0.79, blue: 0.42, alpha: 1), true)
    case .busy:
        return (NSColor(calibratedRed: 0.24, green: 0.57, blue: 0.96, alpha: 1), true)
    case .confirm:
        return (NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.10, alpha: 1), true)
    case .complete:
        return (NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.46, alpha: 1), true)
    }
}

/// 画出胶囊 + 圆钮（用于菜单栏小图标，无背景）
private func drawCapsule(rect: NSRect, state: LiveState) {
    let style = stateStyle(state)
    let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    NSColor(calibratedWhite: 0.0, alpha: 0.55).setFill()
    capsule.fill()

    let styleCapsule = style.capsule
    styleCapsule.setFill()
    capsule.fill()

    let inset = rect.height * 0.12
    let knobSize = rect.height - inset * 2
    let knobRect = NSRect(x: style.knobRight ? rect.maxX - inset - knobSize : rect.minX + inset,
                          y: rect.minY + inset,
                          width: knobSize, height: knobSize)
    let knob = NSBezierPath(ovalIn: knobRect)
    // 滑块阴影
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
    sh.shadowBlurRadius = knobSize * 0.10
    sh.shadowOffset = NSSize(width: 0, height: -knobSize * 0.08)
    sh.set()
    NSColor.white.setFill()
    knob.fill()
    NSGraphicsContext.restoreGraphicsState()
}

/// 菜单栏小图标（纯胶囊 + 圆钮，透明背景，适合 status item）
func menuIcon(_ state: LiveState, size: CGFloat = 18) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let pad = size * 0.18
        drawCapsule(rect: rect.insetBy(dx: pad, dy: pad), state: state)
        return true
    }
    return img
}

/// 深色圆角底板（静态图标与发光图标共用，保证外观一致）
private func drawDockBackground(_ rect: NSRect, size: CGFloat) {
    let corner = size * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let g = NSGradient(colors: [
        NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
    ])!
    g.draw(in: bg, angle: -90)
}

/// 用 CoreText 在指定 CGContext（y 向上）绘制一行文字。
private func drawCTLabel(_ text: String, font: CTFont, color: CGColor,
                         ctx: CGContext, centerX: CGFloat, baselineY: CGFloat) {
    let attr: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attr))
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: centerX - w / 2, y: baselineY)
    CTLineDraw(line, ctx)
}

/// 在药丸开关的上/下空白处画品牌字（上 DeepSeek / 下 HARNESS）。
/// 与 App 图标(.icns)共用同一布局参数，保证 Dock 与文件图标一致。坐标 y 向上。
func drawIconBrandLabels(ctx: CGContext, capRect: CGRect, size: CGFloat) {
    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    let muted = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)

    // 品牌字字号（相对画布边长）。用户要求较初版放大 70%，即 ×1.7。
    let topFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.135, nil)
    let botFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.110, nil)

    let topAscent = CTFontGetAscent(topFont)
    let topDescent = CTFontGetDescent(topFont)
    let botAscent = CTFontGetAscent(botFont)

    // 上方 DeepSeek：文字底边距胶囊顶 gapTop
    let gapTop = size * 0.030
    let topBaseline = capRect.maxY + gapTop + topDescent
    drawCTLabel("DeepSeek", font: topFont, color: white, ctx: ctx,
                centerX: capRect.midX, baselineY: topBaseline)

    // 下方 HARNESS：文字顶边距胶囊底 gapBot
    let gapBot = size * 0.042
    let botBaseline = capRect.minY - gapBot - botAscent
    drawCTLabel("HARNESS", font: botFont, color: muted, ctx: ctx,
                centerX: capRect.midX, baselineY: botBaseline)

    _ = topAscent
}

/// Dock 图标的胶囊几何（静态与发光完全一致）；`scale` 供呼吸动画微缩放
private func dockCapsuleRect(center: CGPoint, size: CGFloat, scale: CGFloat = 1) -> NSRect {
    let capW = size * 0.70 * scale
    let capH = size * 0.36 * scale
    return NSRect(x: center.x - capW / 2, y: center.y - capH / 2, width: capW, height: capH)
}

/// 在任意画布区域绘制「运行态图标」：深色圆角底板 + 标准运行胶囊 + 品牌字
func drawRunningIcon(rect: NSRect) {
    let size = min(rect.width, rect.height)
    drawDockBackground(rect, size: size)
    let capRect = dockCapsuleRect(center: CGPoint(x: rect.midX, y: rect.midY), size: size)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
    sh.shadowBlurRadius = size * 0.06
    sh.shadowOffset = NSSize(width: 0, height: -size * 0.04)
    sh.set()
    drawCapsule(rect: capRect, state: .running)
    NSGraphicsContext.restoreGraphicsState()
    drawBrandLabelsIfAvailable(capRect: capRect, size: size)
}

/// 若存在当前绘制上下文则绘制品牌字（内部封装，避免每个调用点重复取 ctx）
private func drawBrandLabelsIfAvailable(capRect: NSRect, size: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    drawIconBrandLabels(ctx: ctx, capRect: capRect, size: size)
}

/// 在任意画布区域绘制「提醒发光图标」：与 drawRunningIcon 完全同几何（胶囊可按 scale 呼吸缩放），
/// 外加霓虹光晕（glow 0~1）与品牌字。供 Dock 动画视图与 NSImage 两种载体共用。
func drawPulseIcon(rect: NSRect, glowC: NSColor, glow: CGFloat, capScale: CGFloat = 1) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size)
    let capRect = dockCapsuleRect(center: center, size: size, scale: capScale)

    // 霓虹光晕：多层同心胶囊描边，径向亮度按平方快速衰减（中心亮、外圈迅速淡出，不再“一团绿雾”），
    // 且光晕外扩范围随 glow 呼吸伸缩，层次更透气、更有“光”的质感。
    let strength = max(0.35, min(1, glow))
    NSGraphicsContext.saveGraphicsState()
    let layers = 16
    let maxExpand = size * (0.15 + 0.09 * glow) * capScale   // 呼吸时外圈随之扩展/收缩
    let capW = capRect.width
    let baseR = capRect.height / 2
    for i in 0..<layers {
        let f = CGFloat(i) / CGFloat(layers - 1)
        let expand = maxExpand * f
        let r = baseR + expand
        let gp = NSBezierPath(roundedRect:
            NSRect(x: center.x - (capW/2 + expand), y: center.y - r,
                   width: capW + expand*2, height: r*2),
            xRadius: r, yRadius: r)
        // 平方衰减：内圈亮、外圈淡；并留出最外圈的“空隙感”
        let a = strength * (1 - f) * (1 - f) * 0.95 + 0.02
        glowC.withAlphaComponent(a).setStroke()
        gp.lineWidth = max(2.0, size * 0.030)
        gp.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    // 干净地画标准运行胶囊（与静态完全一致）
    drawCapsule(rect: capRect, state: .running)
    drawBrandLabelsIfAvailable(capRect: capRect, size: size)
}

/// Dock 图标（深色圆角底板 + 居中开关 + 品牌字）
func dockIcon(_ state: LiveState, size: CGFloat = 128) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        if state == .running {
            drawRunningIcon(rect: rect)
        } else {
            drawDockBackground(rect, size: size)
            let capRect = dockCapsuleRect(center: CGPoint(x: rect.midX, y: rect.midY), size: size)
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
            sh.shadowBlurRadius = size * 0.06
            sh.shadowOffset = NSSize(width: 0, height: -size * 0.04)
            sh.set()
            drawCapsule(rect: capRect, state: state)
            NSGraphicsContext.restoreGraphicsState()
            drawBrandLabelsIfAvailable(capRect: capRect, size: size)
        }
        return true
    }
    return img
}

/// 待关注提醒用的「发光」Dock 图标（图像载体；Dock 呼吸动画请用 contentView + drawPulseIcon）
func dockIconPulse(glowColor glowC: NSColor, glow: CGFloat, capScale: CGFloat = 1) -> NSImage {
    let size: CGFloat = 128
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        drawPulseIcon(rect: rect, glowC: glowC, glow: glow, capScale: capScale)
        return true
    }
    return img
}

/// 在画布区域绘制「任务进行中」的蓝↔绿流动效果：胶囊底色为沿水平方向循环流动的蓝绿渐变 + 白色滑块 + 品牌字。
/// `phase` 递增驱动渐变流动（每 +1 约移动 25% 胶囊宽）。
func drawBusyFlowIcon(rect: NSRect, phase: CGFloat) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size)
    let capRect = dockCapsuleRect(center: center, size: size)

    let blue = NSColor(calibratedRed: 0.15, green: 0.47, blue: 0.95, alpha: 1)
    let green = NSColor(calibratedRed: 0.10, green: 0.74, blue: 0.34, alpha: 1)

    let capPath = NSBezierPath(roundedRect: capRect, xRadius: capRect.height/2, yRadius: capRect.height/2)
    NSGraphicsContext.saveGraphicsState()
    capPath.addClip()
    // 蓝/绿多段平滑渐变（分段清晰 + 过渡柔和，不硬边、不混成一团），沿水平方向循环流动
    let stripeW = capRect.height * 1.20
    let cycle = stripeW * 2
    let shift = (phase * stripeW * 0.50).truncatingRemainder(dividingBy: cycle)
    let grad = NSGradient(colors: [blue, green, blue, green, blue])!
    grad.draw(from: NSPoint(x: capRect.minX - cycle + shift, y: 0),
              to: NSPoint(x: capRect.minX + cycle + shift, y: 0),
              options: [])

    // 白色高光扫过：一道透明→白→透明的**斜向 45° 亮带**，沿胶囊对角线快速扫过
    let diag = sqrt(capRect.width * capRect.width + capRect.height * capRect.height)
    let sweepShift = (phase * capRect.height * 0.9).truncatingRemainder(dividingBy: diag)
    NSGraphicsContext.saveGraphicsState()
    let tf = NSAffineTransform()
    tf.translateX(by: center.x, yBy: center.y)
    tf.rotate(byDegrees: 45)
    tf.concat()
    let sweepW = capRect.height * 0.50
    let sweepRect = NSRect(x: sweepShift - diag, y: -capRect.height * 1.5,
                           width: sweepW, height: capRect.height * 3.0)
    let sweepGrad = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.0),
        NSColor(calibratedWhite: 1, alpha: 0.34),
        NSColor(calibratedWhite: 1, alpha: 0.0),
    ])!
    sweepGrad.draw(in: sweepRect, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    // 胶囊内描边（受光轮廓）
    NSGraphicsContext.saveGraphicsState()
    let edge = NSBezierPath(roundedRect: capRect.insetBy(dx: 1.5, dy: 1.5),
                            xRadius: capRect.height/2 - 1.5, yRadius: capRect.height/2 - 1.5)
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    edge.lineWidth = 1.2
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // 白色滑块（右），与 drawCapsule 一致
    let inset = capRect.height * 0.12
    let knobSize = capRect.height - inset * 2
    let knobRect = NSRect(x: capRect.maxX - inset - knobSize, y: capRect.minY + inset,
                          width: knobSize, height: knobSize)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.30)
    sh.shadowBlurRadius = knobSize * 0.10
    sh.shadowOffset = NSSize(width: 0, height: -knobSize * 0.06)
    sh.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: knobRect).fill()
    NSGraphicsContext.restoreGraphicsState()

    drawBrandLabelsIfAvailable(capRect: capRect, size: size)
}
