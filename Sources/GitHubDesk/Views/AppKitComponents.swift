import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class CardView: NSView {
    init(cornerRadius: CGFloat = 8) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BadgeView: NSView {
    init(title: String, color: NSColor, systemImage: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = 5

        var views: [NSView] = []
        if let systemImage {
            views.append(makeIcon(systemImage, color: color, size: 10))
        }

        let label = makeLabel(
            title,
            font: .systemFont(ofSize: 11, weight: .medium),
            color: color
        )
        views.append(label)

        let stack = makeStack(views, orientation: .horizontal, spacing: 4, alignment: .centerY)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ActionButton: NSButton {
    var handler: () -> Void

    init(
        title: String = "",
        systemImage: String? = nil,
        style: NSButton.BezelStyle = .rounded,
        isPrimary: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        bezelStyle = style
        target = self
        action = #selector(invoke)
        if isPrimary {
            bezelColor = AppTheme.accent
            contentTintColor = .white
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: "")
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        target = self
        action = #selector(invoke)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

func makeLabel(
    _ text: String,
    font: NSFont = .systemFont(ofSize: 13),
    color: NSColor = .labelColor,
    maximumLines: Int = 1
) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    label.maximumNumberOfLines = maximumLines
    label.lineBreakMode = maximumLines == 1 ? .byTruncatingTail : .byWordWrapping
    return label
}

func makeIcon(_ systemImage: String, color: NSColor, size: CGFloat = 16) -> NSImageView {
    let imageView = NSImageView()
    imageView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
    imageView.contentTintColor = color
    imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.widthAnchor.constraint(equalToConstant: size + 6).isActive = true
    imageView.heightAnchor.constraint(equalToConstant: size + 6).isActive = true
    return imageView
}

func makeSpacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}

func makeStack(
    _ views: [NSView],
    orientation: NSUserInterfaceLayoutOrientation,
    spacing: CGFloat = 8,
    alignment: NSLayoutConstraint.Attribute = .leading
) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = orientation
    stack.spacing = spacing
    stack.alignment = alignment
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func configureCard(_ view: NSView, padding: CGFloat = 14) {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    view.layer?.cornerRadius = 8
    view.layer?.borderWidth = 1
    view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
}

func makeDivider() -> NSBox {
    let divider = NSBox()
    divider.boxType = .separator
    divider.translatesAutoresizingMaskIntoConstraints = false
    return divider
}
