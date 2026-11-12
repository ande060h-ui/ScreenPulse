// The answer window: a visible, floating HUD panel.

import AppKit

@MainActor
final class AnswerPanel: NSPanel {
    enum Phase { case idle, working, done, error }

    private let textView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: AppInfo.name)
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private let questionField = NSTextField()
    private let copyButton = NSButton()
    private var raw = ""
    private var phase: Phase = .idle
    private var appearanceObserver: NSKeyValueObservation?

    var onAskAgain: ((String) -> Void)?
    /// The model currently being tried / answering (shown in the status line).
    var modelName = ""

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = AppInfo.name
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }
        minSize = NSSize(width: 300, height: 170)
        level = .statusBar                     // stays above other windows, including full-screen apps
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true          // does not steal focus unless you type in the field
        // Shown on all Spaces and on top of full-screen windows, so you never switch desktop.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        // sharingType is deliberately NOT changed: the window stays visible to screen recording and screen sharing.

        let root = NSVisualEffectView()
        root.material = .popover
        root.state = .active
        root.blendingMode = .behindWindow
        contentView = root

        // — Header: icon, title, status, close —
        let icon = NSImageView(image: BrandIcon.menuBarImage())
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.layer?.cornerRadius = 9
        iconBg.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(icon)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.spacing = 6
        statusRow.alignment = .centerY
        let titles = NSStackView(views: [titleLabel, statusRow])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1

        let close = Self.iconButton("xmark", size: 11, weight: .bold, target: self, action: #selector(hideSelf))
        close.toolTip = "Hide (Esc)"
        let header = NSStackView(views: [iconBg, titles, NSView(), close])
        header.alignment = .centerY
        header.spacing = 10
        titles.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sep = NSBox(); sep.boxType = .separator

        // — Answer —
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        // — Footer: question field in a soft capsule —
        questionField.placeholderString = "Ask about the screenshot…"
        questionField.isBordered = false
        questionField.drawsBackground = false
        questionField.focusRingType = .none
        questionField.font = .systemFont(ofSize: 13)
        questionField.target = self
        questionField.action = #selector(askAgain)
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let send = Self.iconButton("arrow.up.circle.fill", size: 20, weight: .regular, target: self, action: #selector(askAgain))
        send.contentTintColor = .controlAccentColor
        send.toolTip = "Ask again (↩)"
        let capsule = NSStackView(views: [questionField, send])
        capsule.spacing = 6
        capsule.alignment = .centerY
        capsule.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 6)
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 16
        capsule.layer?.borderWidth = 0.5

        copyButton.target = self
        copyButton.action = #selector(copyAnswer)
        Self.styleIcon(copyButton, "doc.on.doc", size: 13, weight: .medium)
        copyButton.toolTip = "Copy answer"
        let footer = NSStackView(views: [capsule, copyButton])
        footer.spacing = 8
        footer.alignment = .centerY

        for v in [header, sep, scroll, footer] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconBg.widthAnchor.constraint(equalToConstant: 32), iconBg.heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor), icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
            statusDot.widthAnchor.constraint(equalToConstant: 7), statusDot.heightAnchor.constraint(equalToConstant: 7),
            close.widthAnchor.constraint(equalToConstant: 24), close.heightAnchor.constraint(equalToConstant: 24),

            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            sep.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            sep.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sep.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            capsule.heightAnchor.constraint(equalToConstant: 34),
            copyButton.widthAnchor.constraint(equalToConstant: 30), copyButton.heightAnchor.constraint(equalToConstant: 30),
        ])
        applyPhase(.idle)
        refreshColors()
        // Light/dark mode changes: refresh layer colours (they do not follow automatically).
        appearanceObserver = observe(\.effectiveAppearance) { panel, _ in
            MainActor.assumeIsolated { panel.refreshColors(); panel.applyPhase(panel.phase) }
        }
    }

    override var canBecomeKey: Bool { true } // so the question field can be used

    /// Esc hides the window.
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    @objc private func hideSelf() { orderOut(nil) }


    private func refreshColors() {
        guard let capsule = questionField.superview else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            capsule.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            capsule.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        }
    }

    // MARK: Buttons

    private static func styleIcon(_ b: NSButton, _ symbol: String, size: CGFloat, weight: NSFont.Weight) {
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
        b.contentTintColor = .secondaryLabelColor
    }

    private static func iconButton(_ symbol: String, size: CGFloat, weight: NSFont.Weight, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton()
        b.target = target
        b.action = action
        styleIcon(b, symbol, size: size, weight: weight)
        return b
    }

    // MARK: Position and display

    func positionTopRight() {
        let mouse = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let f = s.visibleFrame
        setFrameOrigin(NSPoint(x: f.maxX - frame.width - 16, y: f.maxY - frame.height - 16))
    }

    func show() {
        // If the window is on a different screen than the pointer, move it there.
        let mouse = NSEvent.mouseLocation
        let wasHidden = !isVisible
        if !isVisible || !(screen.map { NSMouseInRect(mouse, $0.frame, false) } ?? false) { positionTopRight() }
        if wasHidden {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        } else {
            orderFrontRegardless()
        }
    }

    // MARK: Status

    func setStatus(_ s: String, _ newPhase: Phase = .idle) {
        statusLabel.stringValue = s
        applyPhase(newPhase)
    }

    private func applyPhase(_ p: Phase) {
        phase = p
        guard let layer = statusDot.layer else { return }
        let color: NSColor
        switch p {
        case .idle: color = .tertiaryLabelColor
        case .working: color = .controlAccentColor
        case .done: color = .systemGreen
        case .error: color = .systemRed
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { layer.backgroundColor = color.cgColor }
        layer.removeAnimation(forKey: "pulse")
        if p == .working {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.25
            a.duration = 0.7
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: "pulse")
        }
    }

    // MARK: Answer text

    func clear() { raw = ""; render() }
    func append(_ s: String) {
        raw += s
        render()
        textView.scrollToEndOfDocument(nil)
    }
    var answerText: String { raw }
    var customQuestion: String { questionField.stringValue }

    /// The first line becomes a clear headline (e.g. "Answer: B"); the rest is body text.
    /// Light markdown: **bold**, bullet lists and # headings.
    private func render() {
        let out = NSMutableAttributedString()
        let body = NSMutableParagraphStyle()
        body.lineHeightMultiple = 1.22
        body.paragraphSpacing = 6
        let bullet = body.mutableCopy() as! NSMutableParagraphStyle
        bullet.headIndent = 14
        bullet.firstLineHeadIndent = 0
        let headStyle = body.mutableCopy() as! NSMutableParagraphStyle
        headStyle.paragraphSpacing = 10

        let lines = raw.components(separatedBy: "\n")
        var firstContent = true
        for (i, var line) in lines.enumerated() {
            var font = NSFont.systemFont(ofSize: 14)
            var color = NSColor.labelColor
            var para = body
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if firstContent && !trimmed.isEmpty && trimmed.count <= 80 {
                font = .systemFont(ofSize: 19, weight: .semibold)
                para = headStyle
                line = trimmed.replacingOccurrences(of: "**", with: "")
                firstContent = false
            } else if trimmed.hasPrefix("#") {
                line = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                font = .systemFont(ofSize: 15, weight: .semibold)
                if !trimmed.isEmpty { firstContent = false }
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                line = "•  " + trimmed.dropFirst(2)
                para = bullet
                color = .labelColor
                firstContent = false
            } else if !trimmed.isEmpty {
                firstContent = false
            }
            out.append(Self.inlineBold(line, font: font, color: color, para: para))
            if i < lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: para]))
            }
        }
        textView.textStorage?.setAttributedString(out)
        fitToContent()
    }

    /// Short answer (e.g. "Answer: C") → compact window. Answer with explanation → wider and taller.
    /// The top edge stays put, so the window grows downwards.
    private func fitToContent() {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let isShort = lines.count <= 1 && text.count <= 60
        let width: CGFloat = isShort ? 360 : 440

        var f = frame
        let top = f.maxY
        if abs(f.width - width) > 0.5 {
            f.origin.x = f.maxX - width       // the right edge stays put (the window sits top-right)
            f.size.width = width
            setFrame(f, display: false)
            contentView?.layoutSubtreeIfNeeded()
        }
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let textH = ceil(lm.usedRect(for: tc).height) + textView.textContainerInset.height * 2
        let chrome: CGFloat = 132                 // header + separator + footer + margins
        let maxH = (screen ?? NSScreen.main).map { $0.visibleFrame.height * 0.7 } ?? 600
        let h = min(max(chrome + textH, minSize.height), maxH)
        guard abs(f.height - h) > 0.5 || abs(f.maxY - top) > 0.5 else { return }
        f.size.height = h
        f.origin.y = top - h
        setFrame(f, display: true)
    }

    private static func inlineBold(_ s: String, font: NSFont, color: NSColor, para: NSParagraphStyle) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        for (i, part) in s.components(separatedBy: "**").enumerated() {
            out.append(NSAttributedString(string: part, attributes: [
                .font: i % 2 == 1 ? bold : font, .foregroundColor: color, .paragraphStyle: para,
            ]))
        }
        return out
    }

    // MARK: Actions

    @objc private func askAgain() { onAskAgain?(questionField.stringValue) }
    @objc private func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
        Self.styleIcon(copyButton, "checkmark", size: 13, weight: .semibold)
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            Self.styleIcon(self.copyButton, "doc.on.doc", size: 13, weight: .medium)
        }
    }
}
