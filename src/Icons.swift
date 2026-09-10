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

/// 图标外观变体（跟随系统浅色/深色外观）
enum IconVariant { case dark, light }

/// 当前系统外观对应的图标变体
func currentIconVariant() -> IconVariant {
    let best = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    return best == .darkAqua ? .dark : .light
}

/// 连续圆角(squircle)路径：超椭圆 |x|^n+|y|^n=1 近似 Apple 的连续圆角图标形状
func squirclePath(in rect: NSRect, n: CGFloat = 5.0) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let steps = 240
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / n), st)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

/// 菜单栏图标（模板图）：单色、随菜单栏明暗与强调色自动适配；形状区分状态。
/// 关闭=滑块在左；运行/进行中/提醒=滑块在右；提醒态右上加一个小圆点。
func menuIconTemplate(_ state: LiveState, size: CGFloat = 18) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let pad = size * 0.13
        let cap = rect.insetBy(dx: pad, dy: pad * 1.35)
        let radius = cap.height / 2
        // 胶囊外框（描边）
        let outline = NSBezierPath(roundedRect: cap, xRadius: radius, yRadius: radius)
        NSColor.black.setStroke()
        outline.lineWidth = max(1.1, size * 0.085)
        outline.stroke()
        // 滑块（实心圆）
        let inset = cap.height * 0.16
        let knobSize = cap.height - inset * 2
        let knobOnRight = (state != .off)
        let knobRect = NSRect(x: knobOnRight ? cap.maxX - inset - knobSize : cap.minX + inset,
                              y: cap.minY + inset, width: knobSize, height: knobSize)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        // 提醒态：右上角加小圆点
        if state == .confirm || state == .complete {
            let d = size * 0.26
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - d - pad * 0.4, y: rect.maxY - d - pad * 0.4,
                                        width: d, height: d)).fill()
        }
        return true
    }
    img.isTemplate = true          // 关键：模板图，自动适配菜单栏外观
    return img
}

/// 菜单栏小图标（彩色版，仅用于预览/文档；StatusItem 请用 menuIconTemplate）
func menuIcon(_ state: LiveState, size: CGFloat = 18) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let pad = size * 0.18
        drawCapsule(rect: rect.insetBy(dx: pad, dy: pad), state: state)
        return true
    }
    return img
}

/// 深色/浅色外观的底板绘制（静态图标与发光图标共用，保证外观一致）
private func drawDockBackground(_ rect: NSRect, size: CGFloat, variant: IconVariant) {
    let bg = squirclePath(in: rect)      // 连续圆角(squircle)，更贴合 macOS 26 图标规范
    let g: NSGradient
    switch variant {
    case .dark:
        g = NSGradient(colors: [
            NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.42, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
        ])!
    case .light:
        g = NSGradient(colors: [
            NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.93, alpha: 1),
        ])!
    }
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
func drawIconBrandLabels(ctx: CGContext, capRect: CGRect, size: CGFloat, variant: IconVariant = .dark) {
    // 深色底板用白字，浅色底板用深字，保证对比
    let primary: CGColor
    let secondary: CGColor
    switch variant {
    case .dark:
        primary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
        secondary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
    case .light:
        primary = CGColor(srgbRed: 0.13, green: 0.15, blue: 0.20, alpha: 0.92)
        secondary = CGColor(srgbRed: 0.13, green: 0.15, blue: 0.20, alpha: 0.72)
    }

    // 品牌字字号（相对画布边长）；内容整体收敛，留出规范安全边距
    let topFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.125, nil)
    let botFont = CTFontCreateWithName("HelveticaNeue-Semibold" as CFString, size * 0.102, nil)

    let topDescent = CTFontGetDescent(topFont)
    let botAscent = CTFontGetAscent(botFont)

    // 上方 DeepSeek：文字底边距胶囊顶 gapTop
    let gapTop = size * 0.030
    let topBaseline = capRect.maxY + gapTop + topDescent
    drawCTLabel("DeepSeek", font: topFont, color: primary, ctx: ctx,
                centerX: capRect.midX, baselineY: topBaseline)

    // 下方 HARNESS：文字顶边距胶囊底 gapBot
    let gapBot = size * 0.042
    let botBaseline = capRect.minY - gapBot - botAscent
    drawCTLabel("HARNESS", font: botFont, color: secondary, ctx: ctx,
                centerX: capRect.midX, baselineY: botBaseline)
}

/// Dock 图标的胶囊几何（静态与发光完全一致）；`scale` 供呼吸动画微缩放。
/// 尺寸收敛到 0.66×0.34，使内容落在图标安全网格内（macOS 26 规范要求留白）。
private func dockCapsuleRect(center: CGPoint, size: CGFloat, scale: CGFloat = 1) -> NSRect {
    let capW = size * 0.66 * scale
    let capH = size * 0.34 * scale
    return NSRect(x: center.x - capW / 2, y: center.y - capH / 2, width: capW, height: capH)
}

/// 在任意画布区域绘制「运行态图标」：外观自适应底板 + 标准运行胶囊 + 品牌字
func drawRunningIcon(rect: NSRect, variant: IconVariant = .dark) {
    let size = min(rect.width, rect.height)
    drawDockBackground(rect, size: size, variant: variant)
    let capRect = dockCapsuleRect(center: CGPoint(x: rect.midX, y: rect.midY), size: size)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: variant == .dark ? 0.35 : 0.22)
    sh.shadowBlurRadius = size * 0.06
    sh.shadowOffset = NSSize(width: 0, height: -size * 0.04)
    sh.set()
    drawCapsule(rect: capRect, state: .running)
    NSGraphicsContext.restoreGraphicsState()
    drawBrandLabelsIfAvailable(capRect: capRect, size: size, variant: variant)
}

/// 若存在当前绘制上下文则绘制品牌字（内部封装，避免每个调用点重复取 ctx）
private func drawBrandLabelsIfAvailable(capRect: NSRect, size: CGFloat, variant: IconVariant) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    drawIconBrandLabels(ctx: ctx, capRect: capRect, size: size, variant: variant)
}

/// 超椭圆（squircle）参数化取点，用于沿图标边缘走线
private func squirclePoint(center: CGPoint, size: CGFloat, t: CGFloat, n: CGFloat = 5.0) -> CGPoint {
    let r = size / 2
    let ct = cos(t), st = sin(t)
    return CGPoint(x: center.x + r * copysign(pow(abs(ct), 2 / n), ct),
                   y: center.y + r * copysign(pow(abs(st), 2 / n), st))
}

/// 边缘向内发光：光从图标边缘（squircle 轮廓）向中心方向衰减，`glow` 控制强度与扩散范围。
private func drawInnerEdgeGlow(rect: NSRect, glowC: NSColor, glow: CGFloat) {
    let size = min(rect.width, rect.height)
    let strength = max(0.35, min(1, glow))
    NSGraphicsContext.saveGraphicsState()
    squirclePath(in: rect).addClip()                    // 只画在图标内部
    let layers = 18
    let maxInset = size * (0.10 + 0.14 * glow)          // 呼吸时向内扩散范围伸缩
    for i in 0..<layers {
        let f = CGFloat(i) / CGFloat(layers - 1)        // 0=最外（亮）→ 1=最内（淡）
        let inset = maxInset * f
        let p = squirclePath(in: rect.insetBy(dx: inset, dy: inset))
        let a = strength * (1 - f) * (1 - f) * 0.80 + 0.02
        glowC.withAlphaComponent(a).setStroke()
        p.lineWidth = max(2.0, size * 0.035)
        p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// 边缘内侧「白色流光」：2px 细线沿 squircle 边缘环绕流动，两端渐隐，`strength` 控制亮度。
private func drawEdgeStream(rect: NSRect, phase: CGFloat, strength: CGFloat) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let lineW: CGFloat = 2.0                            // ★ 2px 细线
    let arcSpan: CGFloat = .pi * 0.42                   // 亮弧约占 75°
    let t0 = phase * 2.4                                // 环绕速度（≈2.6s 一圈）
    let steps = 72
    // 线中心向内缩进 lineW/2，使 2px 线正好贴在边缘内侧
    let insetSize = size - lineW
    NSGraphicsContext.saveGraphicsState()
    squirclePath(in: rect).addClip()
    for k in 0..<steps {
        let f0 = CGFloat(k) / CGFloat(steps)
        let f1 = CGFloat(k + 1) / CGFloat(steps)
        let pA = squirclePoint(center: center, size: insetSize, t: t0 + arcSpan * f0)
        let pB = squirclePoint(center: center, size: insetSize, t: t0 + arcSpan * f1)
        let env = sin(.pi * f0)                         // 两端渐隐
        let path = NSBezierPath()
        path.move(to: pA)
        path.line(to: pB)
        path.lineWidth = lineW
        path.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: strength * CGFloat(env) * 0.95).setStroke()
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// 在任意画布区域绘制「提醒发光图标」：边缘向内的呼吸发光 + 边缘内侧 2px 白色流光 + 胶囊 + 品牌字。
func drawPulseIcon(rect: NSRect, glowC: NSColor, glow: CGFloat, capScale: CGFloat = 1,
                   variant: IconVariant = .dark, phase: CGFloat = 0) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size, variant: variant)   // 底板
    drawInnerEdgeGlow(rect: rect, glowC: glowC, glow: glow)  // ① 边缘向内发光（呼吸）
    let strength = max(0.35, min(1, glow))
    drawEdgeStream(rect: rect, phase: phase, strength: strength)  // ② 边缘内侧 2px 白色流光

    // ③ 标准运行胶囊 + 品牌字（与静态完全一致）
    let capRect = dockCapsuleRect(center: center, size: size, scale: capScale)
    drawCapsule(rect: capRect, state: .running)
    drawBrandLabelsIfAvailable(capRect: capRect, size: size, variant: variant)
}

/// Dock 图标（深色圆角底板 + 居中开关 + 品牌字）
func dockIcon(_ state: LiveState, size: CGFloat = 128, variant: IconVariant = .dark) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        if state == .running {
            drawRunningIcon(rect: rect, variant: variant)
        } else {
            drawDockBackground(rect, size: size, variant: variant)
            let capRect = dockCapsuleRect(center: CGPoint(x: rect.midX, y: rect.midY), size: size)
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor(calibratedWhite: 0, alpha: variant == .dark ? 0.35 : 0.22)
            sh.shadowBlurRadius = size * 0.06
            sh.shadowOffset = NSSize(width: 0, height: -size * 0.04)
            sh.set()
            drawCapsule(rect: capRect, state: state)
            NSGraphicsContext.restoreGraphicsState()
            drawBrandLabelsIfAvailable(capRect: capRect, size: size, variant: variant)
        }
        return true
    }
    return img
}

/// 待关注提醒用的「发光」Dock 图标（图像载体；Dock 呼吸动画请用 contentView + drawPulseIcon）
func dockIconPulse(glowColor glowC: NSColor, glow: CGFloat, capScale: CGFloat = 1, variant: IconVariant = .dark, phase: CGFloat = 0) -> NSImage {
    let size: CGFloat = 128
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        drawPulseIcon(rect: rect, glowC: glowC, glow: glow, capScale: capScale, variant: variant, phase: phase)
        return true
    }
    return img
}

/// 在画布区域绘制「任务进行中」的蓝↔绿流动效果：胶囊底色为沿水平方向循环流动的蓝绿渐变 + 白色滑块 + 品牌字。
/// `phase` 递增驱动渐变流动（每 +1 约移动 25% 胶囊宽）。
func drawBusyFlowIcon(rect: NSRect, phase: CGFloat, variant: IconVariant = .dark) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size, variant: variant)
    let capRect = dockCapsuleRect(center: center, size: size)

    // 蓝/绿各两档，但都落在中明度：不发黑、不发白，且蓝绿整体亮度接近（保留轻微明暗层次）
    let brightBlue  = NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.95, alpha: 1)
    let deepBlue    = NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.80, alpha: 1)
    let brightGreen = NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.42, alpha: 1)
    let deepGreen   = NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.34, alpha: 1)

    let capPath = NSBezierPath(roundedRect: capRect, xRadius: capRect.height/2, yRadius: capRect.height/2)
    NSGraphicsContext.saveGraphicsState()
    capPath.addClip()
    // 横向循环流动：亮蓝→深蓝→亮绿→深绿（一个完整周期），平铺整数个周期并以同色收尾，
    // 位移按真实图案周期取模 → 首尾无缝衔接，无断层/跳变。
    let period = capRect.height * 1.6                     // 一个颜色周期长度
    let seq = [brightBlue, deepBlue, brightGreen, deepGreen]
    let repeats = 3                                       // 铺 3 个周期，保证整条胶囊都在渐变范围内
    var colors: [NSColor] = []
    for _ in 0..<repeats { colors.append(contentsOf: seq) }
    colors.append(brightBlue)                             // 收尾同色，首尾相接
    let span = period * CGFloat(repeats)
    let shift = (phase * capRect.height * 0.5).truncatingRemainder(dividingBy: period)
    let grad = NSGradient(colors: colors)!
    grad.draw(from: NSPoint(x: capRect.midX - span / 2 + shift, y: 0),
              to: NSPoint(x: capRect.midX + span / 2 + shift, y: 0),
              options: [])
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

    drawBrandLabelsIfAvailable(capRect: capRect, size: size, variant: variant)
}
