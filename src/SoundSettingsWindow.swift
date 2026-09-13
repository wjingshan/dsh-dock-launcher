// SoundSettingsWindow.swift — 「提示音设置」独立弹窗
//
// 为什么不做多级菜单：五种提示 × (音效 / 试听 / 重复次数) 在菜单里要翻三层，
// 而且看不到彼此的相对关系。这里改成一张对齐的表格窗口，一屏看清「哪个提示
// 用哪个音效、响几次」，改哪一格就是改那一格。
import AppKit

private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

final class SoundSettingsWindow: NSObject, NSWindowDelegate {

    static let shared = SoundSettingsWindow()
    private override init() { super.init() }

    private var window: NSWindow?
    private var soundPopups: [String: NSPopUpButton] = [:]     // key = slot.rawValue
    private var repeatPopups: [String: NSPopUpButton] = [:]
    private var previewButtons: [String: NSButton] = [:]
    private var auditionCheck: NSButton?
    private let sounds = Sounds.available()

    // MARK: 显示

    func show() {
        if window == nil { build() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 仅构建并刷新状态，不显示窗口（供预览 / 布局验证使用）
    func buildForPreview() { if window == nil { build() }; refresh() }

    /// 已构建的窗口（供预览 / 布局验证读取视图树）
    var previewWindow: NSWindow? { window }

    // MARK: 构建

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = L("sound.window.title")
        w.isReleasedWhenClosed = false
        w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)

        // 标题 + 说明
        let title = NSTextField(labelWithString: L("sound.window.title"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitle = NSTextField(labelWithString: L("sound.window.subtitle"))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(separator())
        root.setCustomSpacing(4, after: title)
        root.setCustomSpacing(14, after: subtitle)

        // 表头
        let headers = [L("sound.column.slot"), L("sound.column.sound"), "", L("sound.column.repeat")]
            .map { text -> NSView in
                let l = NSTextField(labelWithString: text)
                l.font = .systemFont(ofSize: 11, weight: .semibold)
                l.textColor = .secondaryLabelColor
                return l
            }

        // 每种提示一行
        var rows: [[NSView]] = [headers]
        for slot in SoundSlot.allCases {
            rows.append(rowViews(for: slot))
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 2).xPlacement = .center
        grid.column(at: 3).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        root.addArrangedSubview(grid)
        root.addArrangedSubview(separator())

        // 底部一行：自动试听开关在左，按钮在右
        let audition = NSButton(checkboxWithTitle: L("menu.sound.auditionOnSelect"),
                                target: self, action: #selector(toggleAudition(_:)))
        auditionCheck = audition
        let reset = NSButton(title: L("sound.reset"), target: self, action: #selector(resetDefaults))
        reset.bezelStyle = .rounded
        let done = NSButton(title: L("button.done"), target: self, action: #selector(closeWindow))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bottom = NSStackView(views: [audition, spacer, reset, done])
        bottom.orientation = .horizontal
        bottom.spacing = 10
        bottom.alignment = .centerY
        bottom.distribution = .fill
        root.addArrangedSubview(bottom)
        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -44).isActive = true

        let content = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        w.contentView = content

        // 让窗口尺寸跟随内容
        let fitting = root.fittingSize
        w.setContentSize(NSSize(width: max(520, fitting.width), height: fitting.height))
        window = w
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// 一行：提示名 / 音效下拉 / 试听按钮 / 重复次数下拉
    private func rowViews(for slot: SoundSlot) -> [NSView] {
        let key = slot.rawValue

        let name = NSTextField(labelWithString: slot.localizedName)
        name.font = .systemFont(ofSize: 13)

        let sound = NSPopUpButton(frame: .zero, pullsDown: false)
        sound.addItems(withTitles: sounds.isEmpty ? [slot.soundName] : sounds)
        sound.selectItem(withTitle: slot.soundName)
        sound.identifier = NSUserInterfaceItemIdentifier(key)
        sound.target = self
        sound.action = #selector(soundChanged(_:))
        sound.widthAnchor.constraint(equalToConstant: 130).isActive = true
        soundPopups[key] = sound

        let preview = NSButton(image: NSImage(systemSymbolName: "speaker.wave.2.fill",
                                              accessibilityDescription: L("menu.sound.preview"))!,
                               target: self, action: #selector(previewSound(_:)))
        preview.bezelStyle = .texturedRounded
        preview.identifier = NSUserInterfaceItemIdentifier(key)
        preview.toolTip = L("menu.sound.preview")
        previewButtons[key] = preview

        let repeatView: NSView
        if slot.supportsRepeat {
            let pop = NSPopUpButton(frame: .zero, pullsDown: false)
            pop.addItems(withTitles: [1, 2, 3, 5, SoundSlot.untilHover].map { Sounds.repeatLabel($0) })
            pop.selectItem(at: [1, 2, 3, 5, SoundSlot.untilHover].firstIndex(of: slot.repeatCount) ?? 0)
            pop.identifier = NSUserInterfaceItemIdentifier(key)
            pop.target = self
            pop.action = #selector(repeatChanged(_:))
            pop.widthAnchor.constraint(equalToConstant: 175).isActive = true
            repeatPopups[key] = pop
            repeatView = pop
        } else {
            let dash = NSTextField(labelWithString: "—")
            dash.textColor = .tertiaryLabelColor
            repeatView = dash
        }
        return [name, sound, preview, repeatView]
    }

    // MARK: 刷新与动作

    /// 从 UserDefaults 重新读取，同步到控件（重置/外部改动后调用）
    private func refresh() {
        for slot in SoundSlot.allCases {
            let key = slot.rawValue
            soundPopups[key]?.selectItem(withTitle: slot.soundName)
            if let pop = repeatPopups[key] {
                let values = [1, 2, 3, 5, SoundSlot.untilHover]
                pop.selectItem(at: values.firstIndex(of: slot.repeatCount) ?? 0)
            }
        }
        auditionCheck?.state = SoundCenter.shared.auditionOnSelect ? .on : .off
    }

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue, let slot = SoundSlot(rawValue: key),
              let title = sender.titleOfSelectedItem else { return }
        slot.setSound(title)
        // 试听刚选的音效（可在底部开关里关掉）
        if SoundCenter.shared.auditionOnSelect { SoundCenter.shared.preview(slot) }
    }

    @objc private func previewSound(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let slot = SoundSlot(rawValue: key) else { return }
        SoundCenter.shared.preview(slot)
    }

    @objc private func repeatChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue, let slot = SoundSlot(rawValue: key) else { return }
        let values = [1, 2, 3, 5, SoundSlot.untilHover]
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < values.count else { return }
        slot.setRepeat(values[idx])
    }

    @objc private func toggleAudition(_ sender: NSButton) {
        SoundCenter.shared.auditionOnSelect = (sender.state == .on)
    }

    @objc private func resetDefaults() {
        for slot in SoundSlot.allCases {
            slot.setSound(slot.defaultSound)
            slot.setRepeat(1)
        }
        refresh()
    }

    @objc private func closeWindow() {
        SoundCenter.shared.stop()
        window?.close()
    }
}
