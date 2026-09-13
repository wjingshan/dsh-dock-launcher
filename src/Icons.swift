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
func drawIconBrandLabels(ctx: CGContext, capRect: CGRect, size: CGFloat, variant: IconVariant = .dark,
                         labelSpread: CGFloat = 0) {
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

    // 上方 DeepSeek：文字底边距胶囊顶 gapTop；labelSpread > 0 时向上让开
    let gapTop = size * 0.030
    let topBaseline = capRect.maxY + gapTop + topDescent + labelSpread
    drawCTLabel("DeepSeek", font: topFont, color: primary, ctx: ctx,
                centerX: capRect.midX, baselineY: topBaseline)

    // 下方 HARNESS：文字顶边距胶囊底 gapBot；labelSpread > 0 时向下让开
    let gapBot = size * 0.042
    let botBaseline = capRect.minY - gapBot - botAscent - labelSpread
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
    // 裁剪区向内缩 1px。addClip() 会把裁剪路径按像素网格取整，若直接用底板轮廓裁剪，
    // 沿轮廓描的发光会把底板最外圈那一圈半透明像素覆盖成**不透明** —— 量出来底板就从
    // 106px 变成 108px（比其它状态大 1px/边），而且光其实溢出了图标轮廓。
    // 内缩 1px 后，最外圈保持底板自身的抗锯齿，七个状态轮廓严格一致。
    squirclePath(in: rect.insetBy(dx: 1, dy: 1)).addClip()                    // 只画在图标内部
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
    // 同 drawInnerEdgeGlow：内缩 1px，避免 addClip() 的像素取整把底板最外圈压成不透明
    squirclePath(in: rect.insetBy(dx: 1, dy: 1)).addClip()
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
func drawPulseIcon(rect: NSRect, glowC: NSColor, glow: CGFloat,
                   variant: IconVariant = .dark, phase: CGFloat = 0) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size, variant: variant)   // 底板
    drawInnerEdgeGlow(rect: rect, glowC: glowC, glow: glow)  // ① 边缘向内发光（呼吸）
    let strength = max(0.35, min(1, glow))
    drawEdgeStream(rect: rect, phase: phase, strength: strength)  // ② 边缘内侧 2px 白色流光

    // ③ 标准运行胶囊 + 品牌字（与静态完全一致）
    // 胶囊本身**不缩放**：这里曾经乘过一个 1±0.04 的呼吸系数，导致「任务完成」态的药丸
    // 在 66–72px 之间来回变，与关闭 / 空闲 / 进行中的 68px 对不齐（实测偏差 ±4%）。
    // 呼吸只保留在边缘发光上 —— 四个状态的胶囊必须严格同尺寸。
    // 投影参数与 drawRunningIcon / dockIcon 完全一致（这两态原本缺投影）。
    let capRect = dockCapsuleRect(center: center, size: size)
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
func dockIconPulse(glowColor glowC: NSColor, glow: CGFloat, variant: IconVariant = .dark, phase: CGFloat = 0) -> NSImage {
    let size: CGFloat = 128
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        drawPulseIcon(rect: rect, glowC: glowC, glow: glow, variant: variant, phase: phase)
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

    // 多色极光：蓝 → 青 → 绿 → 紫（都落在中明度、亮度接近，不发黑/不发白）
    let auroraBlue   = NSColor(calibratedRed: 0.10, green: 0.42, blue: 1.00, alpha: 1)
    let auroraCyan   = NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.90, alpha: 1)
    let auroraGreen  = NSColor(calibratedRed: 0.16, green: 0.86, blue: 0.38, alpha: 1)
    let auroraViolet = NSColor(calibratedRed: 0.24, green: 0.30, blue: 0.98, alpha: 1)

    let capPath = NSBezierPath(roundedRect: capRect, xRadius: capRect.height/2, yRadius: capRect.height/2)
    // 胶囊投影：与静态两态（关闭 / 运行空闲）用同一组参数。这两态原本没有投影——
    // 静态态是在 drawCapsule 外面套了一层 NSShadow，而这里和 drawPulseIcon 都漏掉了。
    // 必须在 addClip() 之前做：极光渐变是在 capPath 的裁剪区内绘制的，裁剪会把投影一并裁掉；
    // 所以先用带投影的实心胶囊画一遍轮廓，它随后被不透明渐变完全盖住，只剩向外扩散的投影。
    NSGraphicsContext.saveGraphicsState()
    let capShadow = NSShadow()
    capShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: variant == .dark ? 0.35 : 0.22)
    capShadow.shadowBlurRadius = size * 0.06
    capShadow.shadowOffset = NSSize(width: 0, height: -size * 0.04)
    capShadow.set()
    // 注意填充色必须**不透明**：NSShadow 是拿被绘制内容的 alpha 去生成投影的，
    // 用 black 0.55 打底只能得到 55% 强度的投影（实测 +0.034，而静态态是 +0.114）。
    // 这里用一个不透明的色带色，投影强度即与静态态一致；渐变色带随后把它完全盖住。
    auroraBlue.setFill()
    capPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    capPath.addClip()
    // 多色极光色带：一个颜色循环 = 1.3×胶囊宽（每秒正好 1 个循环），铺 3 个循环 + 同色收尾。
    // 位移必须对 cycle 取模：phase 是绝对时间戳（约 8 亿秒），一旦漏掉取模，色带会被推出画布几万像素，
    // 胶囊里就只剩底板色 + 白色扫光 —— 看起来正是「蓝绿渐变消失，只有微弱白色流动」。
    let cycle = capRect.width * 1.3
    let seq = [auroraBlue, auroraCyan, auroraGreen, auroraViolet]
    var colors: [NSColor] = []
    for _ in 0..<4 { colors.append(contentsOf: seq) }
    colors.append(auroraBlue)                    // 收尾同色，首尾相接
    let span = cycle * 4        // 必须正好覆盖上面 colors 里铺的 4 个完整循环：
                                // 否则 shift 的回绕周期（cycle）与渐变实际图案周期（span/4）不一致，
                                // 每绕一圈接缝处颜色就会跳变（表现为周期性卡顿尖峰）。
    let shift = (phase * capRect.width * 1.3).truncatingRemainder(dividingBy: cycle)
    let grad = NSGradient(colors: colors)!
    // 区间左端始终比胶囊左边缘靠左 (span - 胶囊宽)，保证任何相位下胶囊都被完整覆盖
    let fromX = capRect.minX - (span - capRect.width) + shift
    grad.draw(from: NSPoint(x: fromX, y: 0),
              to: NSPoint(x: fromX + span, y: 0),
              options: [])

    // 柔和极光扫过：一道很宽很淡的白光缓慢掠过（非细亮线）
    let sweepW = capRect.width * 0.42
    let sweepPeriod = capRect.width + sweepW
    let sweepShift = (phase * sweepPeriod / 2).truncatingRemainder(dividingBy: sweepPeriod)   // 每 2 秒正好掠过 1 次 ⇒ 与 2 秒循环对齐
    let sweepRect = NSRect(x: capRect.minX - sweepW + sweepShift, y: capRect.minY,
                           width: sweepW, height: capRect.height)
    let sweepGrad = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.0),
        NSColor(calibratedWhite: 1, alpha: 0.26),
        NSColor(calibratedWhite: 1, alpha: 0.0),
    ])!
    sweepGrad.draw(in: sweepRect, angle: 0)
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

// MARK: 「需要你介入」提醒 —— 右上角圆点脉冲

/// 在任意画布上绘制「圆点脉冲」提醒：正常运行图标 + 右上角圆点（带一层裁剪在底板内的柔和扩散）。
/// 几何参数经出界量测：圆点留 margin、扩散光裁剪在圆角内，整枚图标不会超出画布。
/// - Parameter pulse: 脉冲缩放（约 0.86…1.12），由 animBeat() 的双频呼吸驱动
func drawDotPulseIcon(rect: NSRect, dotColor: NSColor, pulse: CGFloat, variant: IconVariant = .dark) {
    let size = min(rect.width, rect.height)
    drawRunningIcon(rect: rect, variant: variant)      // 底板 + 开关胶囊 + 品牌字

    let r = size * 0.120 * pulse
    let margin = size * 0.035
    let c = CGPoint(x: rect.maxX - margin - r, y: rect.maxY - margin - r)

    // ① 柔和扩散：多层递减 alpha 的圆，裁剪在底板内，避免溢出画布
    NSGraphicsContext.saveGraphicsState()
    squirclePath(in: rect).addClip()
    let layers = 7
    for i in 0..<layers {
        let f = CGFloat(i) / CGFloat(layers - 1)
        let rr = r * (1.20 + 0.85 * f)
        dotColor.withAlphaComponent(0.15 * (1 - f) * min(1, pulse)).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // ② 圆点本体（带投影，与底板上其它元素保持一致的打光）
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.50)
    sh.shadowBlurRadius = r * 0.30
    sh.shadowOffset = NSSize(width: 0, height: -r * 0.06)
    sh.set()
    dotColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

/// 圆点脉冲图（供 Dock tile 的动画视图使用）
func dockIconDotPulse(dotColor: NSColor, pulse: CGFloat, size: CGFloat = 128,
                      variant: IconVariant = .dark) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        drawDotPulseIcon(rect: rect, dotColor: dotColor, pulse: pulse, variant: variant)
        return true
    }
}

// MARK: 「需要你介入」变形动画（品牌字分开 → 白圆点放大成正圆 → 几何蓝色问号浮现 → 静止或轻微循环）

/// 时间轴与几何参数（改这里即可微调节奏与比例）
enum AskMorph {
    static let intro: CGFloat = 0.90           // 开场变形时长（秒）：0.5s 时动作全堆在前段，肉眼看像“啪”地一下，读不出变形过程
    static let circleRFrac: CGFloat = 0.240    // 背景面板（圆角正方形）的半边长 / 图标边长
    static let questionInkFrac: CGFloat = 0.420 // 问号墨迹高度 / 图标边长
    static let spreadFrac: CGFloat = 0.125     // 品牌字上下分开距离 / 图标边长
    static let questionDelay: CGFloat = 0.25   // 问号在变形进度 25% 处才开始出现
    static let questionColor = NSColor(calibratedRed: 0.11, green: 0.47, blue: 1.00, alpha: 1)
    static let checkInkWFrac: CGFloat = 0.300   // 对勾墨迹宽度 / 图标边长
    // 多选「淡化叠加」循环的时间比例（均占一个循环周期）：
    //   先画一笔（drawFrac）→ 画完立即从起点开始淡掉（fadeFrac）→ 旧笔迹还剩 overlapKeepFrac 时，
    //   新一笔从起点重新画 —— 此时旧笔迹尾巴仍在淡出，两笔同框。
    // 约束：drawFrac + (1 − overlapKeepFrac)·fadeFrac = 1（保证新笔恰好在本轮结束时起笔）。
    // 当前 0.595 + 0.45×0.90 = 1.0 ✓
    static let cycleDrawFrac: CGFloat = 0.595
    static let cycleFadeFrac: CGFloat = 0.90
    static let cycleOverlapKeepFrac: CGFloat = 0.55
}

/// 圆圈里的符号形态：单选/普通提问用问号，多选问题用对勾
enum AskSymbol: Int, CaseIterable {
    case question = 0   // 蓝色几何问号
    case check          // 蓝色几何对勾（按进度"书写"出来）
}

/// 落定之后的循环手法（供选择）
enum AskMorphLoop: Int, CaseIterable {
    case still = 0        // ① 完全静止
    case breathe          // ② 极轻呼吸（圆 + 问号整体 ±3.5% 缩放）
    case ripple           // ③ 扩散环（细环向外扩散淡出，雷达 ping）
    case brightness       // ④ 亮度呼吸（问号透明度起伏，无位移）
    case sheen            // ⑤ 光带扫过（一道柔光斜掠圆面）
    case dotPulse         // ⑥ 圆点脉冲（只有问号下方那个点轻微搏动）
    case drawCheck        // ⑦ 循环书写对勾（保持 → 淡出 → 重新写出；多选用）

    var name: String {
        switch self {
        case .still: return "静止"
        case .breathe: return "轻呼吸"
        case .ripple: return "扩散环"
        case .brightness: return "亮度呼吸"
        case .sheen: return "光带扫过"
        case .dotPulse: return "圆点脉冲"
        case .drawCheck: return "循环书写"
        }
    }

    /// 循环周期（秒）—— 都取 1.5 的整分数，便于并排对比且无缝循环
    var period: CGFloat {
        switch self {
        case .still: return 1.5
        case .breathe: return 1.5
        case .ripple: return 0.75
        case .brightness: return 0.75
        case .sheen: return 1.5
        case .dotPulse: return 0.75
        case .drawCheck: return 3.2     // 书写动作要看得清，周期放长
        }
    }
}

// ── 几何绘制的问号（不用字体：等宽圆头描边，避免卡通观感） ──────────────

/// 单位空间下的问号构造参数（H = 1 表示整枚问号的墨迹高度，比例对齐真实字体字形）
/// 结构：碗形弧（195° → -60°，顺时针）→ 近乎垂直下延的竖杆 → 空隙 → 与笔画同宽的圆点
private enum TechQ {
    static let strokeW: CGFloat = 0.210        // 笔画宽度（比 Helvetica-Bold 更粗一档）
    static let arcCenter = CGPoint(x: 0, y: 0.725)
    static let arcRadius: CGFloat = 0.1975     // 碗形中径（外径 = 0.55）
    static let arcStart: CGFloat = 195         // 度
    static let arcEnd: CGFloat = -60
    static let tailC1 = CGPoint(x: 0.060, y: 0.500)   // 承接弧末端的切线方向
    static let tailC2 = CGPoint(x: 0.000, y: 0.420)
    static let tailEnd = CGPoint(x: 0.000, y: 0.300)  // 竖杆收在中心线上
    static let dotRadius: CGFloat = 0.085
    static let dotCenter = CGPoint(x: 0, y: 0.085)
}

/// 已按目标尺寸与位置变换好的问号几何
struct TechQuestion {
    var hookOutline: CGPath      // 描边外轮廓（可直接填充）
    var dot: CGPath              // 下方圆点（可直接填充）
    var strokeWidth: CGFloat
    var dotCenter: CGPoint
    var inkBounds: CGRect
}

/// 生成一个墨迹高度为 `inkHeight`、**墨迹中心严格位于 `center`** 的问号
func makeTechQuestion(center: CGPoint, inkHeight: CGFloat) -> TechQuestion {
    let shape = NSBezierPath()
    shape.appendArc(withCenter: TechQ.arcCenter, radius: TechQ.arcRadius,
                    startAngle: TechQ.arcStart, endAngle: TechQ.arcEnd, clockwise: true)
    shape.curve(to: TechQ.tailEnd, controlPoint1: TechQ.tailC1, controlPoint2: TechQ.tailC2)
    let hookOutline = shape.cgPath.copy(strokingWithWidth: TechQ.strokeW,
                                        lineCap: .round, lineJoin: .round, miterLimit: 10)
    let dot = CGPath(ellipseIn: CGRect(x: TechQ.dotCenter.x - TechQ.dotRadius,
                                       y: TechQ.dotCenter.y - TechQ.dotRadius,
                                       width: TechQ.dotRadius * 2,
                                       height: TechQ.dotRadius * 2), transform: nil)
    let raw = hookOutline.boundingBox.union(dot.boundingBox)
    let s = inkHeight / raw.height
    let t = CGAffineTransform(translationX: -raw.midX, y: -raw.midY)
        .concatenating(CGAffineTransform(scaleX: s, y: s))
        .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    var tt = t
    let hook = hookOutline.copy(using: &tt) ?? hookOutline
    let dotT = dot.copy(using: &tt) ?? dot
    return TechQuestion(hookOutline: hook, dot: dotT, strokeWidth: TechQ.strokeW * s,
                        dotCenter: TechQ.dotCenter.applying(t),
                        inkBounds: hook.boundingBox.union(dotT.boundingBox))
}

/// 画几何问号：蓝色填充 + 淡内阴影（裁到轮廓内，再沿内缘压一圈模糊暗边）
/// - Parameter dotScale: 圆点单独缩放（用于「圆点脉冲」），绕圆点自身中心缩放
func drawTechQuestion(_ q: TechQuestion, color: NSColor, dotScale: CGFloat = 1) {
    let hook = NSBezierPath(cgPath: q.hookOutline)
    NSGraphicsContext.saveGraphicsState()
    hook.addClip()
    color.setFill()
    hook.fill()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
    sh.shadowBlurRadius = q.strokeWidth * 0.30
    sh.shadowOffset = NSSize(width: 0, height: -q.strokeWidth * 0.16)
    sh.set()
    (color.blended(withFraction: 0.32, of: .black) ?? color).setStroke()
    hook.lineWidth = q.strokeWidth * 0.30
    hook.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    if dotScale != 1 {
        let tf = NSAffineTransform()
        tf.translateX(by: q.dotCenter.x, yBy: q.dotCenter.y)
        tf.scale(by: dotScale)
        tf.translateX(by: -q.dotCenter.x, yBy: -q.dotCenter.y)
        tf.concat()
    }
    color.setFill()
    NSBezierPath(cgPath: q.dot).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// ── 几何绘制的对勾（等宽圆头描边，支持按进度"书写"） ──────────────────

/// 已按目标尺寸与位置变换好的对勾几何
struct TechCheck {
    var partialOutline: CGPath     // 按书写进度截取后的描边外轮廓
    var strokeWidth: CGFloat
    var inkBounds: CGRect          // 完整对勾的墨迹范围（定尺寸用，不随进度漂移）
}

/// - Parameter reveal: 书写进度 0…1（从左往右写出）
func makeTechCheck(center: CGPoint, inkWidth: CGFloat, reveal: CGFloat) -> TechCheck? {
    let p0 = CGPoint(x: -0.66, y: 0.06)
    let p1 = CGPoint(x: -0.18, y: -0.46)
    let p2 = CGPoint(x: 0.70, y: 0.46)
    let w: CGFloat = 0.30
    let l1 = hypot(p1.x - p0.x, p1.y - p0.y)
    let l2 = hypot(p2.x - p1.x, p2.y - p1.y)
    let want = max(0.001, min(1, reveal)) * (l1 + l2)

    let partial = NSBezierPath()
    partial.move(to: p0)
    if want <= l1 {
        let f = l1 > 0 ? want / l1 : 0
        partial.line(to: CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f))
    } else {
        partial.line(to: p1)
        let f = l2 > 0 ? (want - l1) / l2 : 0
        partial.line(to: CGPoint(x: p1.x + (p2.x - p1.x) * f, y: p1.y + (p2.y - p1.y) * f))
    }
    let partialOutline = partial.cgPath.copy(strokingWithWidth: w, lineCap: .round,
                                            lineJoin: .round, miterLimit: 10)
    let full = NSBezierPath()
    full.move(to: p0); full.line(to: p1); full.line(to: p2)
    let fullOutline = full.cgPath.copy(strokingWithWidth: w, lineCap: .round,
                                      lineJoin: .round, miterLimit: 10)
    let raw = fullOutline.boundingBox
    let sc = inkWidth / raw.width
    let t = CGAffineTransform(translationX: -raw.midX, y: -raw.midY)
        .concatenating(CGAffineTransform(scaleX: sc, y: sc))
        .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    var tt = t
    guard let moved = partialOutline.copy(using: &tt) else { return nil }
    return TechCheck(partialOutline: moved, strokeWidth: w * sc,
                     inkBounds: fullOutline.boundingBox.applying(t))
}

/// 对勾笔画在书写进度 `reveal` 处的前端点（“笔尖”）的实际坐标。
/// 与 makeTechCheck 使用完全相同的几何与归一化变换，保证亮笔头严格落在笔画上。
func techCheckTip(center: CGPoint, inkWidth: CGFloat, reveal: CGFloat) -> CGPoint? {
    let p0 = CGPoint(x: -0.66, y: 0.06)
    let p1 = CGPoint(x: -0.18, y: -0.46)
    let p2 = CGPoint(x: 0.70, y: 0.46)
    let w: CGFloat = 0.30
    let l1 = hypot(p1.x - p0.x, p1.y - p0.y)
    let l2 = hypot(p2.x - p1.x, p2.y - p1.y)
    let want = max(0, min(1, reveal)) * (l1 + l2)
    let tip: CGPoint
    if want <= l1 {
        let f = l1 > 0 ? want / l1 : 0
        tip = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
    } else {
        let f = l2 > 0 ? (want - l1) / l2 : 0
        tip = CGPoint(x: p1.x + (p2.x - p1.x) * f, y: p1.y + (p2.y - p1.y) * f)
    }
    let full = NSBezierPath()
    full.move(to: p0); full.line(to: p1); full.line(to: p2)
    let fullOutline = full.cgPath.copy(strokingWithWidth: w, lineCap: .round,
                                      lineJoin: .round, miterLimit: 10)
    let raw = fullOutline.boundingBox
    let sc = inkWidth / raw.width
    let t = CGAffineTransform(translationX: -raw.midX, y: -raw.midY)
        .concatenating(CGAffineTransform(scaleX: sc, y: sc))
        .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    return tip.applying(t)
}

/// 画「正在淡出」的对勾笔画段 [from, to]（均为 0…1 的比例）。
/// 用一条「透明 → 实心」的线性渐变填充，渐变起点即当前淡化推进位置 ——
/// 起点之前由 drawsBeforeStartLocation 填成完全透明，于是观感就是笔迹从起点一点点褪掉，
/// 而不是被「擦短」（形状变短）或整条同时变淡。
func drawFadingCheck(center: CGPoint, inkWidth: CGFloat, color: NSColor,
                     from: CGFloat, to: CGFloat) {
    guard to > from, to - from > 0.004,
          let body = makeTechCheck(center: center, inkWidth: inkWidth, reveal: to),
          let pA = techCheckTip(center: center, inkWidth: inkWidth, reveal: from),
          let pB = techCheckTip(center: center, inkWidth: inkWidth, reveal: to),
          let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.addPath(body.partialOutline)
    ctx.clip()
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [color.withAlphaComponent(0).cgColor,
                                      color.cgColor,
                                      color.cgColor] as CFArray,
                             locations: [0, 0.34, 1]) {
        ctx.drawLinearGradient(grad, start: pA, end: pB,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()
}

/// 画对勾：蓝色填充 + 与问号一致的淡内阴影
func drawTechCheck(_ c: TechCheck, color: NSColor) {
    let bez = NSBezierPath(cgPath: c.partialOutline)
    NSGraphicsContext.saveGraphicsState()
    bez.addClip()
    color.setFill()
    bez.fill()
    let sh = NSShadow()
    sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
    sh.shadowBlurRadius = c.strokeWidth * 0.30
    sh.shadowOffset = NSSize(width: 0, height: -c.strokeWidth * 0.16)
    sh.set()
    (color.blended(withFraction: 0.32, of: .black) ?? color).setStroke()
    bez.lineWidth = c.strokeWidth * 0.30
    bez.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// 按时间绘制一帧「需要你介入」动画
/// - Parameters:
///   - time: 距动画开始的秒数。0…AskMorph.intro 为变形段，之后按 `loop` 循环。
///   - loop: 落定后的循环手法（`.still` 即变形结束后完全静止）
func drawAskMorphIcon(rect: NSRect, time: CGFloat, loop: AskMorphLoop = .breathe,
                      variant: IconVariant = .dark, reverse: Bool = false,
                      symbol: AskSymbol = .question) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    drawDockBackground(rect, size: size, variant: variant)

    let p = min(1, max(0, time / AskMorph.intro))
    // smoothstep（前段慢 → 中段快 → 末段收），让每一段变形都看得清；
    // 反向（收回到开关）用镜像曲线：从 1 平滑收到 0
    func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
    let ease = reverse ? smoothstep(1 - p) : smoothstep(p)
    let settled = ease > 0.995                     // 是否已处于"落定"外形（含反向刚起步时）
    let capRect = dockCapsuleRect(center: center, size: size)

    // ① 胶囊与白色圆点：随变形淡出（圆点由下面的白圆接手放大）
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(1 - ease)
    drawCapsule(rect: capRect, state: .running)
    NSGraphicsContext.restoreGraphicsState()

    // ② 品牌字上下分开：DeepSeek 向上、HARNESS 向下，靠近图标边缘
    if let ctx = NSGraphicsContext.current?.cgContext {
        drawIconBrandLabels(ctx: ctx, capRect: capRect, size: size, variant: variant,
                            labelSpread: size * AskMorph.spreadFrac * ease)
    }

    // ③ 白色圆点 → 居中大正圆
    let inset = capRect.height * 0.12
    let knobSize = capRect.height - inset * 2
    let knobCenter = CGPoint(x: capRect.maxX - inset - knobSize / 2,
                             y: capRect.minY + inset + knobSize / 2)
    let knobR = knobSize / 2
    let bigR = size * AskMorph.circleRFrac
    let r0 = knobR + (bigR - knobR) * ease
    let c0 = CGPoint(x: knobCenter.x + (center.x - knobCenter.x) * ease,
                     y: knobCenter.y + (center.y - knobCenter.y) * ease)

    // 落定后的循环相位
    let lt = max(0, time - AskMorph.intro)
    let wave = 0.5 + 0.5 * sin(lt / loop.period * 2 * .pi)          // 0…1
    let breathe = (loop == .breathe && settled) ? 1 + 0.035 * wave : 1

    let r = r0 * breathe
    let c = CGPoint(x: center.x + (c0.x - center.x) * breathe,
                    y: center.y + (c0.y - center.y) * breathe)

    // 背景面板几何：圆角正方形（macOS squircle 风格，圆角 ≈ 边长的 24%）。
    // 传入半径即返回以 c 为中心、边长 2×半径 的圆角方形路径。
    func panelPath(_ radius: CGFloat) -> NSBezierPath {
        let rect = NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        let corner = radius * 0.48          // = 边长 × 0.24
        return NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    }

    // ③a 环境蓝光（面板后面一层很淡的光）
    if ease > 0.05 {
        let layers = 10
        for i in 0..<layers {
            let f = CGFloat(i) / CGFloat(layers - 1)
            let rr = r * (1.02 + 0.30 * f)
            AskMorph.questionColor.withAlphaComponent(0.055 * (1 - f) * ease).setFill()
            panelPath(rr).fill()
        }
    }

    // ③b 面板本体：径向渐变（中心纯白 → 边缘极淡冷灰），带投影
    // 关键：透明度跟随变形进度 ⇒ 正向时从"圆点"淡入、反向时淡出回"圆点"，
    // 两套绘制（我的面板 vs 图标自带的圆点）交叉淡化，收尾不会跳
    let circle = panelPath(r)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(min(1, ease * 2.5))
    let circleShadow = NSShadow()
    circleShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.38)
    circleShadow.shadowBlurRadius = r * 0.16
    circleShadow.shadowOffset = NSSize(width: 0, height: -r * 0.05)
    circleShadow.set()
    if let g = NSGradient(colors: [NSColor.white,
                                   NSColor(calibratedRed: 0.906, green: 0.933, blue: 0.965, alpha: 1)]) {
        g.draw(in: circle, relativeCenterPosition: .zero)
    } else {
        NSColor.white.setFill(); circle.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // ③c 发丝外环
    if ease > 0.15 {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, (ease - 0.15) / 0.85))
        let outer = panelPath(r + 1.5)
        outer.lineWidth = 1.0
        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        outer.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    // ③d 扩散环（落定后才有）
    if loop == .ripple, settled {
        let rings = 2
        for i in 0..<rings {
            var ph = (lt / loop.period) + CGFloat(i) / CGFloat(rings)
            ph = ph.truncatingRemainder(dividingBy: 1)
            // 从面板外一点起始、sin 包络淡入淡出，避免起始相位与面板边重合而被读成"双圈"
            let rr = r * (1.06 + 0.34 * ph)
            let ring = panelPath(rr)
            ring.lineWidth = 1.5
            AskMorph.questionColor.withAlphaComponent(0.38 * sin(.pi * ph) * ease).setStroke()
            ring.stroke()
        }
    }

    // ③e 亮度呼吸：面板内一层蓝色柔光随呼吸明暗（问号本体不动、不变淡）
    if loop == .brightness, settled, ease > 0.2 {
        let glowR = r * 0.98
        if let g = NSGradient(colors: [AskMorph.questionColor.withAlphaComponent(0.38 * wave * ease),
                                       AskMorph.questionColor.withAlphaComponent(0.0)]) {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            g.draw(in: panelPath(glowR), relativeCenterPosition: .zero)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // ④ 蓝色问号：从小到大浮现（反向时随之收回），墨迹中心严格在图标中心
    //    显现程度一律跟随变形进度 ease（而不是原始 p），否则反向收尾时问号会残留到最后一帧
    let qp = min(1, max(0, (ease - AskMorph.questionDelay) / (1 - AskMorph.questionDelay)))
    guard qp > 0.001, r > 4 else { return }
    let qEase = reverse ? qp : 1 - pow(1 - qp, 3)

    // 循环「重描」（多选）：对勾始终完整不消失，一道高亮笔头带着拖尾沿笔画循环描过。
    // 本体 reveal 落定后固定为 1；高亮靠「起点淡入、终点淡出」收尾，
    // 所以循环回到起点时是「已淡出 → 再淡入」，不会出现跳变。
    let checkReveal = qEase

    // 亮度呼吸：只改透明度，不产生位移
    let qAlpha = min(1, qp * 1.8)                                     // 问号本体保持清晰，不靠变淡做呼吸
    var qColor = AskMorph.questionColor
    if loop == .brightness, settled {
        // 只做很轻的深浅变化（12%），主要明暗交给圆内那层柔光
        qColor = AskMorph.questionColor.blended(withFraction: 0.12 * (1 - wave), of: .black) ?? qColor
    }
    let dotScale: CGFloat = (loop == .dotPulse && settled) ? 1 + 0.30 * wave : 1

    NSGraphicsContext.saveGraphicsState()
    let tf = NSAffineTransform()
    tf.translateX(by: center.x, yBy: center.y)
    tf.scale(by: breathe * (0.35 + 0.65 * qEase))
    tf.translateX(by: -center.x, yBy: -center.y)
    tf.concat()
    NSGraphicsContext.current?.cgContext.setAlpha(qAlpha)
    switch symbol {
    case .question:
        let q = makeTechQuestion(center: center, inkHeight: size * AskMorph.questionInkFrac)
        drawTechQuestion(q, color: qColor, dotScale: dotScale)
    case .check:
        if loop == .drawCheck, settled, !reverse {
            // 循环「淡化叠加」（无笔头、无收笔）：
            //   画一笔 → 画完从**起点**开始颜色逐渐变淡 → 淡到只剩 1/3 时新一笔从起点重画，
            //   旧笔迹的尾巴继续淡出 —— 两笔在时间上叠加。
            //   每轮用一条「透明 → 实心」的线性渐变填充笔画：渐变起点即当前淡化推进位置，
            //   起点之前由 drawsBeforeStartLocation 填成透明，自然形成「从起点褪掉」的观感。
            let u = (lt / loop.period).truncatingRemainder(dividingBy: 1)
            let dFrac = AskMorph.cycleDrawFrac
            let eFrac = AskMorph.cycleFadeFrac
            let inkW = size * AskMorph.checkInkWFrac
            // 本轮：画到 head；画完后起点侧淡出到 erase
            let head = smoothstep(min(1, u / dFrac))
            let erase = u > dFrac ? smoothstep(min(1, (u - dFrac) / eFrac)) : 0
            drawFadingCheck(center: center, inkWidth: inkW, color: qColor, from: erase, to: head)
            // 上一轮：只剩尾巴在继续淡出（u=0 时正好淡掉 2/3、还剩 1/3）
            let prevErase = smoothstep(min(1, max(0, (u + 1 - dFrac) / eFrac)))
            if prevErase < 0.999 {
                drawFadingCheck(center: center, inkWidth: inkW, color: qColor, from: prevErase, to: 1)
            }
        } else {
            // 变形段随 ease 写出、反向时倒着收回（其他循环模式也走这里）
            if let check = makeTechCheck(center: center,
                                         inkWidth: size * AskMorph.checkInkWFrac,
                                         reveal: checkReveal) {
                drawTechCheck(check, color: qColor)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    // ⑤ 光带扫过：裁在圆内，一道柔光斜掠（画在问号之上，很淡）
    if loop == .sheen, settled {
        let sweep = (lt / loop.period).truncatingRemainder(dividingBy: 1)
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        let band = size * 0.16
        let startX = c.x - r * 1.6 + sweep * (r * 3.2)
        let layers = 26
        for i in 0..<layers {
            let f = CGFloat(i) / CGFloat(layers - 1)
            let x = startX + (f - 0.5) * band
            let a = 0.22 * sin(.pi * f)                      // 中间最亮、两端渐隐
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x - band * 0.5, y: c.y - r * 1.5))
            line.line(to: NSPoint(x: x + band * 0.5, y: c.y + r * 1.5))
            line.lineWidth = band / CGFloat(layers) * 1.6
            NSColor(calibratedWhite: 1, alpha: a * ease).setStroke()
            line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
