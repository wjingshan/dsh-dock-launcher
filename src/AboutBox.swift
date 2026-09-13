// AboutBox.swift — 「关于」弹窗（自建窗口）
//
// 早期版本用 NSAlert：即使把 messageText / informativeText 置空，NSAlert 仍会为它们
// 预留垂直空间，导致窗口上方出现一大片空白、内容整体靠下。改成自建窗口后：
//   · 窗口尺寸 = 内容尺寸 + 四周等距留白 → 内容天然整体居中（上下留白相等）
//   · 每行水平居中
//   · GitHub / 赞助为**按钮**（不再是超链接文字）
import AppKit

/// 用类而不是 enum：按钮的 target/action 需要 `@objc` 方法，而 `@objc` 不能用在 enum 的静态成员上。
final class AboutBox: NSObject {

    static let repoURL = "https://github.com/wjingshan/dsh-dock-launcher"
    static let sponsorURL = "https://github.com/wjingshan/dsh-dock-launcher#-赞助"

    static let iconSize: CGFloat = 64
    static let padding: CGFloat = 26          // 四周等距留白（上下相等 ⇒ 整体居中）
    static let gapIconName: CGFloat = 12
    static let gapNameInfo: CGFloat = 3
    static let gapInfoButtons: CGFloat = 22
    static let gapButtonsOK: CGFloat = 10     // 链接按钮行与「好」之间的行距
    static let buttonGap: CGFloat = 10

    private static var window: NSWindow?      // 持有引用，避免窗口被释放

    private static func centeredLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.alignment = .center
        l.drawsBackground = false
        l.isBordered = false
        return l
    }

    /// 构建（不显示）「关于」窗口，便于预览与布局验证
    static func makeWindow(appName: String, infoLine: String, okTitle: String,
                           repoTitle: String, sponsorTitle: String) -> NSWindow {
        let name = centeredLabel(appName, font: .systemFont(ofSize: 15, weight: .semibold),
                                 color: .labelColor)
        let info = centeredLabel(infoLine, font: .systemFont(ofSize: 11, weight: .regular),
                                 color: .secondaryLabelColor)

        let icon = NSImageView()
        icon.image = NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
        ])

        let repo = NSButton(title: repoTitle, target: self, action: #selector(openRepo))
        repo.bezelStyle = .rounded
        let sponsor = NSButton(title: sponsorTitle, target: self, action: #selector(openSponsor))
        sponsor.bezelStyle = .rounded
        let ok = NSButton(title: okTitle, target: self, action: #selector(closeAbout))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"                       // 回车＝关闭

        // 两个链接按钮一行，「好」单独换行放到下一行（各自居中）
        let linkButtons = NSStackView(views: [repo, sponsor])
        linkButtons.orientation = .horizontal
        linkButtons.spacing = buttonGap
        linkButtons.alignment = .centerY

        let stack = NSStackView(views: [icon, name, info, linkButtons, ok])
        stack.orientation = .vertical
        stack.alignment = .centerX                     // 每行水平居中
        stack.spacing = 0
        stack.setCustomSpacing(gapIconName, after: icon)
        stack.setCustomSpacing(gapNameInfo, after: name)
        stack.setCustomSpacing(gapInfoButtons, after: info)
        stack.setCustomSpacing(gapButtonsOK, after: linkButtons)

        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),   // 整体居中
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -padding),
        ])

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = appName
        w.isReleasedWhenClosed = false
        w.contentView = content
        content.layoutSubtreeIfNeeded()
        w.setContentSize(content.fittingSize)
        return w
    }

    /// 构建并居中显示
    static func show(appName: String, infoLine: String, okTitle: String,
                     repoTitle: String, sponsorTitle: String) {
        if window == nil {
            window = makeWindow(appName: appName, infoLine: infoLine, okTitle: okTitle,
                                repoTitle: repoTitle, sponsorTitle: sponsorTitle)
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 动作

    @objc private static func openRepo() {
        if let u = URL(string: repoURL) { NSWorkspace.shared.open(u) }
    }

    @objc private static func openSponsor() {
        if let u = URL(string: sponsorURL) { NSWorkspace.shared.open(u) }
    }

    @objc private static func closeAbout() {
        window?.close()
    }
}
