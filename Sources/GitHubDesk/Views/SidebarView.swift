import AppKit

final class SidebarView: NSVisualEffectView {
    var onSelect: ((WorkspaceSection) -> Void)?
    var onAccount: (() -> Void)?

    private let overviewButton = ActionButton(handler: {})
    private let localButton = ActionButton(handler: {})
    private let remoteButton = ActionButton(handler: {})
    private let accountDot = NSView()
    private let accountLabel = makeLabel("尚未登录", font: .systemFont(ofSize: 12, weight: .semibold))
    private let accountDetail = makeLabel(
        "添加或切换 GitHub 账号",
        font: .systemFont(ofSize: 10),
        color: .secondaryLabelColor
    )
    private let accountButton = ActionButton(title: "账号管理", systemImage: "person.crop.circle", handler: {})

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .behindWindow
        state = .active
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(store: AppStore) {
        overviewButton.title = "  总览    \(store.localRepositories.count)"
        localButton.title = "  本地项目    \(store.localRepositories.count)"
        remoteButton.title = "  GitHub 仓库    \(store.remoteOnlyRepositories.count)"

        let selected = store.section ?? .overview
        updateButton(overviewButton, selected: selected == .overview)
        updateButton(localButton, selected: selected == .local)
        updateButton(remoteButton, selected: selected == .remote)

        if let account = store.currentAccount {
            accountLabel.stringValue = "\(account.displayName) · @\(account.login)"
            accountDetail.stringValue = "当前 GitHub 账号"
        } else {
            accountLabel.stringValue = "尚未登录"
            accountDetail.stringValue = "添加或切换 GitHub 账号"
        }
        accountDot.layer?.backgroundColor = (store.currentAccount == nil ? AppTheme.warning : AppTheme.accent).cgColor
    }

    private func buildView() {
        let brandIcon = makeIcon("chevron.left.forwardslash.chevron.right", color: AppTheme.accent, size: 17)
        let brandTitle = makeLabel("GitHub Desk", font: .systemFont(ofSize: 16, weight: .semibold))
        let brandSubtitle = makeLabel("本地仓库工作台", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        let brandText = makeStack(
            [brandTitle, brandSubtitle],
            orientation: .vertical,
            spacing: 2
        )
        let brand = makeStack(
            [brandIcon, brandText],
            orientation: .horizontal,
            spacing: 9,
            alignment: .centerY
        )

        configureNavigationButton(
            overviewButton,
            systemImage: "square.grid.2x2",
            action: { [weak self] in self?.select(.overview) }
        )
        configureNavigationButton(
            localButton,
            systemImage: "folder",
            action: { [weak self] in self?.select(.local) }
        )
        configureNavigationButton(
            remoteButton,
            systemImage: "shippingbox",
            action: { [weak self] in self?.select(.remote) }
        )

        let navigationTitle = makeLabel(
            "工作台",
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: .tertiaryLabelColor
        )

        let navigation = makeStack(
            [navigationTitle, overviewButton, localButton, remoteButton],
            orientation: .vertical,
            spacing: 6
        )

        accountDot.translatesAutoresizingMaskIntoConstraints = false
        accountDot.wantsLayer = true
        accountDot.layer?.cornerRadius = 4
        accountDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        accountDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let accountText = makeStack(
            [accountLabel, accountDetail],
            orientation: .vertical,
            spacing: 1
        )
        let account = makeStack(
            [accountDot, accountText, makeSpacer(), accountButton],
            orientation: .horizontal,
            spacing: 9,
            alignment: .centerY
        )
        accountButton.controlSize = .small
        accountButton.handler = { [weak self] in self?.onAccount?() }

        let divider = makeDivider()
        let content = makeStack(
            [brand, navigation, makeSpacer(), divider, account],
            orientation: .vertical,
            spacing: 18
        )
        content.alignment = .leading
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            overviewButton.widthAnchor.constraint(equalTo: content.widthAnchor),
            localButton.widthAnchor.constraint(equalTo: content.widthAnchor),
            remoteButton.widthAnchor.constraint(equalTo: content.widthAnchor),
            account.widthAnchor.constraint(equalTo: content.widthAnchor),
            divider.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }

    private func configureNavigationButton(
        _ button: ActionButton,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.alignment = .left
        button.isBordered = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.handler = action
    }

    private func updateButton(_ button: NSButton, selected: Bool) {
        button.contentTintColor = selected ? AppTheme.accent : .secondaryLabelColor
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = selected
            ? AppTheme.accent.withAlphaComponent(0.1).cgColor
            : NSColor.clear.cgColor
    }

    private func select(_ section: WorkspaceSection) {
        onSelect?(section)
    }
}
