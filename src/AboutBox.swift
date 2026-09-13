// AboutBox.swift — 「关于」弹窗的构造（App 与验证程序共用同一份代码）
//
// 布局要求：所有内容**垂直方向依次排列、每行水平居中**；
// 底部一行是「GitHub 地址」和「赞助地址」两个**小字超链接**，横向并排。
//
// 实现说明：NSAlert 自带的 messageText / informativeText 走的是 NSTextField 默认的
// `.natural` 对齐（实测为左对齐）且不暴露对齐设置，所以这里把**全部内容**放进自己的
// accessoryView，逐行显式居中；NSAlert 只负责窗口、图标栏与按钮，并把 accessory 水平居中。
import AppKit

enum AboutBox {

    static let repoURL = "https://github.com/wjingshan/dsh-dock-launcher"
    static let sponsorURL = "https://github.com/wjingshan/dsh-dock-launcher#-赞助"

    /// 链接显示文本（去掉 https:// 前缀，更像"地址"）
    static let repoDisplay = "github.com/wjingshan/dsh-dock-launcher"
    static let sponsorDisplay = "github.com/wjingshan/dsh-dock-launcher#-赞助"

    // 版面常量（改这里即可调整间距/字号）
    static let contentWidth: CGFloat = 520
    static let iconSize: CGFloat = 64
    static let linkFontSize: CGFloat = 11

    /// 居中的纯文本标签
    private static func centeredLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = font
        tf.textColor = color
        tf.alignment = .center
        tf.drawsBackground = false
        tf.isBordered = false
        tf.lineBreakMode = .byTruncatingTail
        tf.sizeToFit()
        return tf
    }

    /// 小字超链接：真正的 NSTextField 链接（可点、鼠标变手型），不是按钮伪装
    private static func linkLabel(_ text: String, url: String) -> NSTextField {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: linkFontSize),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: url)!,
        ]
        let tf = NSTextField(labelWithAttributedString: NSAttributedString(string: text, attributes: attrs))
        tf.isSelectable = true                  // 链接可点需要可选
        tf.allowsEditingTextAttributes = true
        tf.drawsBackground = false
        tf.isBordered = false
        tf.alignment = .center
        tf.sizeToFit()
        return tf
    }

    /// 底部一行：两个小字超链接横向并排，整行在容器内水平居中
    static func linksRow(width: CGFloat, spacing: CGFloat = 18) -> NSView {
        let repo = linkLabel(repoDisplay, url: repoURL)
        let sponsor = linkLabel(sponsorDisplay, url: sponsorURL)
        let rowH = max(repo.frame.height, sponsor.frame.height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        let total = repo.frame.width + spacing + sponsor.frame.width
        let startX = max(0, (width - total) / 2)
        repo.setFrameOrigin(NSPoint(x: startX, y: (rowH - repo.frame.height) / 2))
        sponsor.setFrameOrigin(NSPoint(x: startX + repo.frame.width + spacing,
                                       y: (rowH - sponsor.frame.height) / 2))
        container.addSubview(repo)
        container.addSubview(sponsor)
        return container
    }

    /// 全部内容：图标 / 名称 / 版本号 / 底部链接行 —— 每行水平居中、自上而下排列
    static func contentView(appName: String, infoLine: String, width: CGFloat = contentWidth,
                            withIcon: Bool = true) -> NSView {
        let name = centeredLabel(appName, font: .systemFont(ofSize: 15, weight: .semibold),
                                 color: .labelColor)
        let info = centeredLabel(infoLine, font: .systemFont(ofSize: 11, weight: .regular),
                                 color: .secondaryLabelColor)
        let links = linksRow(width: width)

        var height: CGFloat = 0
        if withIcon { height += iconSize + 10 }
        height += name.frame.height + 4 + info.frame.height + 12 + links.frame.height

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var y = height
        if withIcon {
            let iv = NSImageView(frame: NSRect(x: (width - iconSize) / 2, y: y - iconSize,
                                               width: iconSize, height: iconSize))
            iv.image = NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
            iv.imageScaling = .scaleProportionallyUpOrDown
            content.addSubview(iv)
            y -= iconSize + 10
        }
        name.setFrameOrigin(NSPoint(x: (width - name.frame.width) / 2, y: y - name.frame.height))
        content.addSubview(name)
        y -= name.frame.height + 4
        info.setFrameOrigin(NSPoint(x: (width - info.frame.width) / 2, y: y - info.frame.height))
        content.addSubview(info)
        y -= info.frame.height + 12
        links.setFrameOrigin(NSPoint(x: 0, y: y - links.frame.height))
        content.addSubview(links)
        return content
    }

    /// 组装「关于」弹窗：内容全部在 accessoryView 里（自己居中），只留一个「好」按钮
    static func make(appName: String, infoLine: String, okTitle: String, withIcon: Bool = true) -> NSAlert {
        let a = NSAlert()
        a.messageText = ""                       // 内容自绘，避免 NSAlert 的左对齐文本
        a.informativeText = ""
        a.icon = NSImage(size: .zero)            // 抑制 NSAlert 默认的应用图标（我们在内容里放）
        a.alertStyle = .informational
        a.accessoryView = contentView(appName: appName, infoLine: infoLine, withIcon: withIcon)
        a.addButton(withTitle: okTitle)
        return a
    }
}
