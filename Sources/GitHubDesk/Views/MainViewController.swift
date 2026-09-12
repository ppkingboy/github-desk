import AppKit
import Combine

final class MainViewController: NSViewController {
    private let store: AppStore
    private let sidebar = SidebarView()
    private let contentStack = NSStackView()
    private let searchField = NSSearchField()
    private let pathLabel = makeLabel("", font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
    private let noticeLabel = makeLabel("", font: .systemFont(ofSize: 11, weight: .semibold), color: AppTheme.accent)
    private let refreshButton = ActionButton(handler: {})
    private let accountButton = NSPopUpButton()
    private var cancellables = Set<AnyCancellable>()
    private var lastPresentedAlertID: UUID?
    private var toastWorkItem: DispatchWorkItem?

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = FlippedView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view = rootView

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.onSelect = { [weak self] section in
            self?.store.section = section
        }

        let topBar = buildTopBar()
        let scrollView = buildScrollView()

        rootView.addSubview(sidebar)
        rootView.addSubview(topBar)
        rootView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),

            topBar.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            topBar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindStore()
        sidebar.update(store: store)
        render()
    }

    private func buildTopBar() -> NSView {
        searchField.placeholderString = "搜索仓库"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 230).isActive = true

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let selectButton = ActionButton(
            title: "选择目录",
            systemImage: "folder",
            handler: { [weak self] in self?.store.chooseWorkspace() }
        )
        selectButton.controlSize = .small

        refreshButton.title = "刷新"
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.imagePosition = .imageLeading
        refreshButton.controlSize = .small
        refreshButton.handler = { [weak self] in self?.store.refresh() }

        accountButton.controlSize = .small
        accountButton.bezelStyle = .rounded
        accountButton.target = self
        accountButton.action = #selector(accountSelectionChanged(_:))
        accountButton.translatesAutoresizingMaskIntoConstraints = false
        accountButton.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let newProjectButton = ActionButton(
            title: "新建项目",
            systemImage: "plus.square",
            handler: { [weak self] in self?.presentNewProject() }
        )
        newProjectButton.controlSize = .small

        let syncAllButton = ActionButton(
            title: "批量同步",
            systemImage: "arrow.triangle.2.circlepath",
            handler: { [weak self] in self?.store.batchSync() }
        )
        syncAllButton.controlSize = .small

        noticeLabel.isHidden = true

        let bar = makeStack(
            [
                searchField, pathLabel, noticeLabel, makeSpacer(),
                newProjectButton, syncAllButton, accountButton, selectButton, refreshButton
            ],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )
        bar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return bar
    }

    private func buildScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28)
        ])

        return scrollView
    }

    private func bindStore() {
        store.$section
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sidebar.update(store: self.store)
                self.render()
            }
            .store(in: &cancellables)

        store.$localRepositories
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sidebar.update(store: self.store)
                self.render()
            }
            .store(in: &cancellables)

        store.$remoteRepositories
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sidebar.update(store: self.store)
                self.render()
            }
            .store(in: &cancellables)

        store.$accounts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sidebar.update(store: self.store)
                self.pathLabel.stringValue = "工作区：\(self.store.workspaceRootPath)"
                self.updateAccountButton()
            }
            .store(in: &cancellables)

        store.$currentAccountID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sidebar.update(store: self.store)
                self.updateAccountButton()
                self.render()
            }
            .store(in: &cancellables)

        store.$workspaceRootPath
            .receive(on: RunLoop.main)
            .sink { [weak self] path in
                self?.pathLabel.stringValue = "工作区：\(path)"
            }
            .store(in: &cancellables)

        store.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak self] isRefreshing in
                self?.refreshButton.isEnabled = !isRefreshing
                self?.refreshButton.title = isRefreshing ? "刷新中" : "刷新"
            }
            .store(in: &cancellables)

        store.$busyRepositoryID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        store.$alert
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in
                guard let self, self.lastPresentedAlertID != alert.id else { return }
                self.lastPresentedAlertID = alert.id
                self.presentError(alert)
                self.store.alert = nil
            }
            .store(in: &cancellables)

        store.$toastMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.showNotice(message)
            }
            .store(in: &cancellables)

        store.$loginPresentation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] presentation in
                self?.presentLogin(presentation)
            }
            .store(in: &cancellables)

        store.$batchSyncReport
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] report in
                self?.presentBatchSyncReport(report)
            }
            .store(in: &cancellables)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        store.searchText = sender.stringValue
        render()
    }

    @objc private func accountSelectionChanged(_ sender: NSPopUpButton) {
        guard let representedObject = sender.selectedItem?.representedObject as? Int else { return }

        switch representedObject {
        case -1:
            store.beginLogin()
        case -2:
            presentAccountManager()
        default:
            guard let account = store.accounts.first(where: { $0.id == representedObject }) else { return }
            store.switchAccount(to: account)
        }
    }

    private func updateAccountButton() {
        let menu = NSMenu()

        if store.accounts.isEmpty {
            let loginItem = NSMenuItem(title: "登录 GitHub…", action: nil, keyEquivalent: "")
            loginItem.representedObject = -1
            menu.addItem(loginItem)
        } else {
            for account in store.accounts {
                let item = NSMenuItem(
                    title: "\(account.displayName) · @\(account.login)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.representedObject = account.id
                item.state = account.id == store.currentAccountID ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())
            let addItem = NSMenuItem(title: "添加账号…", action: nil, keyEquivalent: "")
            addItem.representedObject = -1
            menu.addItem(addItem)
            let manageItem = NSMenuItem(title: "账号管理…", action: nil, keyEquivalent: "")
            manageItem.representedObject = -2
            menu.addItem(manageItem)
        }

        accountButton.menu = menu
        if let account = store.currentAccount {
            accountButton.title = "@\(account.login)"
            accountButton.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "账号")
        } else {
            accountButton.title = "登录"
            accountButton.image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: "登录")
        }
    }

    private func render() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        pathLabel.stringValue = "工作区：\(store.workspaceRootPath)"
        updateAccountButton()

        switch store.section ?? .overview {
        case .overview:
            renderDashboard()
        case .local:
            renderLocalRepositories()
        case .remote:
            renderRemoteRepositories()
        }
    }

    private func renderDashboard() {
        addFullWidth(
            makePageHeader(
                title: "仓库概览",
                subtitle: "扫描本地项目，处理差异，并连接到 GitHub。",
                count: nil
            )
        )

        let metrics = NSStackView(views: [
            makeMetricCard(
                title: "本地项目",
                value: "\(store.localRepositories.count)",
                detail: "工作区中发现的 Git 仓库",
                image: "folder",
                color: AppTheme.info
            ),
            makeMetricCard(
                title: "已同步",
                value: "\(store.syncedCount)",
                detail: "本地与 GitHub 状态一致",
                image: "checkmark.circle",
                color: AppTheme.accent
            ),
            makeMetricCard(
                title: "待处理",
                value: "\(store.needsAttentionCount)",
                detail: "存在提交、推送或拉取差异",
                image: "exclamationmark.triangle",
                color: AppTheme.warning
            ),
            makeMetricCard(
                title: "未发布",
                value: "\(store.localOnlyCount)",
                detail: "尚未创建 GitHub 远程仓库",
                image: "arrow.up.forward.square",
                color: AppTheme.danger
            )
        ])
        metrics.orientation = .horizontal
        metrics.alignment = .top
        metrics.distribution = .fillEqually
        metrics.spacing = 12
        addFullWidth(metrics)

        let attention = store.attentionRepositories
        addFullWidth(makeSectionHeader(title: "需要处理", detail: attention.isEmpty ? "没有待处理事项" : "\(attention.count) 个项目"))
        if attention.isEmpty {
            addFullWidth(makeMessageCard(
                title: "所有已连接的仓库都处于同步状态。",
                systemImage: "checkmark.seal.fill",
                color: AppTheme.accent
            ))
        } else {
            for repository in attention {
                addFullWidth(makeAttentionCard(repository))
            }
        }

        addFullWidth(makeSectionHeader(title: "最近项目", detail: "显示前 5 个仓库"))
        if store.localRepositories.isEmpty {
            addFullWidth(makeEmptyState(
                title: "还没有发现本地项目",
                message: "选择包含代码项目的文件夹，GitHub Desk 会自动找出其中的 Git 仓库。",
                systemImage: "folder.badge.questionmark",
                actionTitle: "选择项目目录",
                action: { [weak self] in self?.store.chooseWorkspace() }
            ))
        } else {
            for repository in store.localRepositories.prefix(5) {
                addFullWidth(makeCompactRepositoryCard(repository))
            }
        }
    }

    private func renderLocalRepositories() {
        addFullWidth(makePageHeader(
            title: "本地项目",
            subtitle: "查看连接状态，并执行提交、拉取和推送。",
            count: store.filteredLocalRepositories.count
        ))

        guard !store.filteredLocalRepositories.isEmpty else {
            addFullWidth(makeEmptyState(
                title: store.localRepositories.isEmpty ? "没有发现 Git 仓库" : "没有匹配的项目",
                message: store.localRepositories.isEmpty
                    ? "选择一个项目目录，或确认项目已经执行过 git init。"
                    : "尝试修改搜索关键词。",
                systemImage: "folder.badge.questionmark",
                actionTitle: store.localRepositories.isEmpty ? "选择项目目录" : nil,
                action: store.localRepositories.isEmpty ? { [weak self] in self?.store.chooseWorkspace() } : nil
            ))
            return
        }

        for repository in store.filteredLocalRepositories {
            addFullWidth(makeLocalRepositoryCard(repository))
        }
    }

    private func renderRemoteRepositories() {
        addFullWidth(makePageHeader(
            title: "GitHub 仓库",
            subtitle: "显示当前尚未克隆到本地工作区的远程仓库。",
            count: store.remoteOnlyRepositories.count
        ))

        guard !store.remoteOnlyRepositories.isEmpty else {
            addFullWidth(makeEmptyState(
                title: "没有待克隆仓库",
                message: "已发现的所有 GitHub 仓库都已经存在本地副本，或当前搜索结果为空。",
                systemImage: "checkmark.circle",
                actionTitle: nil,
                action: nil
            ))
            return
        }

        for repository in store.remoteOnlyRepositories {
            addFullWidth(makeRemoteRepositoryCard(repository))
        }
    }

    private func addFullWidth(_ subview: NSView) {
        contentStack.addArrangedSubview(subview)
        subview.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makePageHeader(title: String, subtitle: String, count: Int?) -> NSView {
        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 28, weight: .semibold))
        let subtitleLabel = makeLabel(subtitle, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let textStack = makeStack([titleLabel, subtitleLabel], orientation: .vertical, spacing: 5)

        var views: [NSView] = [textStack, makeSpacer()]
        if let count {
            views.append(makeLabel("\(count)", font: .systemFont(ofSize: 22, weight: .semibold), color: .secondaryLabelColor))
        }

        let header = makeStack(views, orientation: .horizontal, spacing: 12, alignment: .top)
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        return header
    }

    private func makeMetricCard(
        title: String,
        value: String,
        detail: String,
        image: String,
        color: NSColor
    ) -> NSView {
        let icon = makeIcon(image, color: color, size: 15)
        let valueLabel = makeLabel(value, font: .systemFont(ofSize: 25, weight: .semibold), color: .labelColor)
        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13, weight: .semibold))
        let detailLabel = makeLabel(detail, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        let top = makeStack([icon, makeSpacer(), valueLabel], orientation: .horizontal, spacing: 8, alignment: .centerY)
        let bottom = makeStack([titleLabel, detailLabel], orientation: .vertical, spacing: 2)
        let stack = makeStack([top, bottom], orientation: .vertical, spacing: 12)

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            card.heightAnchor.constraint(equalToConstant: 108)
        ])
        return card
    }

    private func makeSectionHeader(title: String, detail: String) -> NSView {
        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 16, weight: .semibold))
        let detailLabel = makeLabel(detail, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        return makeStack(
            [titleLabel, makeSpacer(), detailLabel],
            orientation: .horizontal,
            spacing: 12,
            alignment: .firstBaseline
        )
    }

    private func makeMessageCard(title: String, systemImage: String, color: NSColor) -> NSView {
        let icon = makeIcon(systemImage, color: color, size: 15)
        let label = makeLabel(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let row = makeStack([icon, label, makeSpacer()], orientation: .horizontal, spacing: 10, alignment: .centerY)
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeEmptyState(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> NSView {
        let icon = makeIcon(systemImage, color: AppTheme.accent, size: 32)
        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 17, weight: .semibold))
        let messageLabel = makeLabel(message, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, maximumLines: 3)
        messageLabel.alignment = .center

        var views: [NSView] = [icon, titleLabel, messageLabel]
        if let actionTitle, let action {
            let button = ActionButton(title: actionTitle, isPrimary: true, handler: action)
            views.append(button)
        }

        let stack = makeStack(views, orientation: .vertical, spacing: 10, alignment: .centerX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = FlippedView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 55),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -55),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        return container
    }

    private func makeAttentionCard(_ repository: LocalRepository) -> NSView {
        let icon = makeIcon(repository.status.systemImage, color: repository.status.color, size: 14)
        let title = makeLabel(repository.name, font: .systemFont(ofSize: 13, weight: .semibold))
        let detail = makeLabel(repository.syncSummary, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let text = makeStack([title, detail], orientation: .vertical, spacing: 2)
        let badge = BadgeView(
            title: repository.status.title,
            color: repository.status.color,
            systemImage: repository.status.systemImage
        )
        let button = ActionButton(title: "查看", handler: { [weak self] in
            self?.store.section = .local
        })
        button.controlSize = .small

        let row = makeStack([icon, text, makeSpacer(), badge, button], orientation: .horizontal, spacing: 10, alignment: .centerY)
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func makeCompactRepositoryCard(_ repository: LocalRepository) -> NSView {
        let icon = makeIcon("chevron.left.forwardslash.chevron.right", color: AppTheme.info, size: 14)
        let title = makeLabel(repository.name, font: .systemFont(ofSize: 13, weight: .semibold))
        let path = makeLabel(
            repository.path,
            font: .monospacedSystemFont(ofSize: 10, weight: .regular),
            color: .secondaryLabelColor
        )
        let text = makeStack([title, path], orientation: .vertical, spacing: 2)
        let branch = makeLabel(repository.branch, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let reveal = ActionButton(
            systemImage: "folder",
            handler: { [weak self] in self?.store.reveal(repository) }
        )
        reveal.controlSize = .small
        reveal.toolTip = "在 Finder 中显示"

        let row = makeStack([icon, text, makeSpacer(), branch, reveal], orientation: .horizontal, spacing: 10, alignment: .centerY)
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
        return card
    }

    private func makeLocalRepositoryCard(_ repository: LocalRepository) -> NSView {
        let icon = makeIcon("chevron.left.forwardslash.chevron.right", color: AppTheme.info, size: 15)
        let title = makeLabel(repository.name, font: .systemFont(ofSize: 15, weight: .semibold))
        let path = makeLabel(
            repository.path,
            font: .monospacedSystemFont(ofSize: 10, weight: .regular),
            color: .secondaryLabelColor
        )
        let metadata = makeLabel(
            "\(repository.branch)  ·  \(repository.syncSummary)  ·  健康 \(repository.health.score)%  ·  \(repository.shortLastCommitDate)",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )

        var badgeViews: [NSView] = [
            BadgeView(
                title: repository.status.title,
                color: repository.status.color,
                systemImage: repository.status.systemImage
            )
        ]
        if let remote = repository.remote {
            badgeViews.append(BadgeView(
                title: remote.isPublic ? "公开" : "私有",
                color: remote.isPublic ? AppTheme.info : .secondaryLabelColor,
                systemImage: remote.isPublic ? "globe" : "lock"
            ))
        }
        let badges = makeStack(badgeViews, orientation: .horizontal, spacing: 6, alignment: .centerY)

        let text = makeStack([title, path, metadata, badges], orientation: .vertical, spacing: 6)
        let actions = makeLocalActions(repository)
        let row = makeStack([icon, text, makeSpacer(), actions], orientation: .horizontal, spacing: 14, alignment: .top)

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            text.widthAnchor.constraint(greaterThanOrEqualToConstant: 440)
        ])

        if store.busyRepositoryID == repository.id {
            card.alphaValue = 0.72
        }
        return card
    }

    private func makeLocalActions(_ repository: LocalRepository) -> NSView {
        if store.busyRepositoryID == repository.id {
            let progress = NSProgressIndicator()
            progress.style = .spinning
            progress.controlSize = .small
            progress.startAnimation(nil)
            progress.translatesAutoresizingMaskIntoConstraints = false
            progress.widthAnchor.constraint(equalToConstant: 24).isActive = true
            return progress
        }

        var views: [NSView] = []

        switch repository.status {
        case .localOnly:
            views.append(ActionButton(
                title: "发布",
                systemImage: "arrow.up.forward.square",
                isPrimary: true,
                handler: { [weak self] in self?.presentPublish(repository) }
            ))
        case .unmatchedRemote:
            views.append(ActionButton(
                title: "检查",
                handler: { [weak self] in self?.store.reveal(repository) }
            ))
        case .needsSync:
            if repository.behind > 0 {
                views.append(ActionButton(
                    title: "拉取",
                    systemImage: "arrow.down",
                    isPrimary: true,
                    handler: { [weak self] in self?.store.pull(repository) }
                ))
            } else if repository.isDirty {
                views.append(ActionButton(
                    title: "提交",
                    systemImage: "arrow.up.circle",
                    isPrimary: true,
                    handler: { [weak self] in self?.presentCommit(repository) }
                ))
            } else {
                views.append(ActionButton(
                    title: "推送",
                    systemImage: "arrow.up",
                    isPrimary: true,
                    handler: { [weak self] in self?.store.push(repository) }
                ))
            }
        case .synced:
            let synced = ActionButton(title: "已同步", systemImage: "checkmark") {}
            synced.isEnabled = false
            views.append(synced)
        }

        let menuButton = ActionButton(systemImage: "ellipsis", handler: {})
        menuButton.toolTip = "更多操作"
        menuButton.controlSize = .small
        menuButton.handler = { [weak self, weak menuButton] in
            guard let self, let menuButton else { return }
            self.showLocalMenu(for: repository, relativeTo: menuButton)
        }
        views.append(menuButton)

        return makeStack(views, orientation: .horizontal, spacing: 8, alignment: .centerY)
    }

    private func showLocalMenu(for repository: LocalRepository, relativeTo button: NSButton) {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "在 Finder 中显示", systemImage: "folder") { [weak self] in
            self?.store.reveal(repository)
        })

        if repository.remote != nil {
            menu.addItem(ActionMenuItem(title: "在 GitHub 中打开", systemImage: "safari") { [weak self] in
                self?.store.openOnGitHub(repository)
            })
        }

        if repository.hasUpstream {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(title: "拉取", systemImage: "arrow.down") { [weak self] in
                self?.store.pull(repository)
            })
            menu.addItem(ActionMenuItem(title: "推送", systemImage: "arrow.up") { [weak self] in
                self?.store.push(repository)
            })
        }

        if repository.isDirty && repository.remote != nil {
            menu.addItem(ActionMenuItem(title: "提交并推送", systemImage: "arrow.up.circle") { [weak self] in
                self?.presentCommit(repository)
            })
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "补齐仓库基础文件", systemImage: "checklist") { [weak self] in
            self?.presentStandardize(repository)
        })

        if let remote = repository.remote {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(
                title: remote.isPublic ? "设为私有" : "设为公开",
                systemImage: remote.isPublic ? "lock" : "globe"
            ) { [weak self] in
                self?.confirmVisibilityChange(
                    repository,
                    visibility: remote.isPublic ? .privateRepository : .publicRepository
                )
            })
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.maxX - 4, y: button.bounds.minY - 4),
            in: button
        )
    }

    private func makeRemoteRepositoryCard(_ repository: GitHubRepository) -> NSView {
        let icon = makeIcon("shippingbox", color: AppTheme.accent, size: 15)
        let title = makeLabel(repository.name, font: .systemFont(ofSize: 15, weight: .semibold))
        let slug = makeLabel(
            repository.nameWithOwner,
            font: .monospacedSystemFont(ofSize: 10, weight: .regular),
            color: AppTheme.info
        )
        let description = makeLabel(
            repository.description ?? "暂无项目说明",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            maximumLines: 2
        )
        let metadata = makeLabel(
            "\(repository.primaryLanguage ?? "未知语言")  ·  更新于 \(repository.shortUpdatedAt)",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        let badges = makeStack([
            BadgeView(
                title: repository.isPublic ? "公开" : "私有",
                color: repository.isPublic ? AppTheme.info : .secondaryLabelColor,
                systemImage: repository.isPublic ? "globe" : "lock"
            )
        ], orientation: .horizontal, spacing: 6)
        let text = makeStack([title, slug, description, metadata, badges], orientation: .vertical, spacing: 6)

        let clone = ActionButton(
            title: "克隆",
            systemImage: "arrow.down.to.line",
            isPrimary: true,
            handler: { [weak self] in
                self?.chooseAccount(title: "选择克隆使用的账号") { account in
                    self?.store.clone(repository, account: account)
                }
            }
        )
        let open = ActionButton(
            systemImage: "safari",
            handler: { [weak self] in self?.store.openOnGitHub(repository) }
        )
        open.toolTip = "在 GitHub 中打开"
        let actions = makeStack([clone, open], orientation: .horizontal, spacing: 8, alignment: .centerY)

        let row = makeStack([icon, text, makeSpacer(), actions], orientation: .horizontal, spacing: 14, alignment: .top)
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            text.widthAnchor.constraint(greaterThanOrEqualToConstant: 440)
        ])

        if store.busyRepositoryID == repository.idString {
            card.alphaValue = 0.72
        }
        return card
    }

    private func presentPublish(_ repository: LocalRepository) {
        let alert = NSAlert()
        alert.messageText = "发布到 GitHub"
        alert.informativeText = repository.hasCommits
            ? "创建公开仓库并推送当前分支。未提交的文件不会自动包含。"
            : "这个项目还没有提交。继续后会创建一次 Initial commit，然后发布。"
        alert.addButton(withTitle: "创建并发布")
        alert.addButton(withTitle: "取消")

        let nameField = NSTextField(string: RepositoryName.sanitize(repository.name))
        let descriptionField = NSTextField(string: "")
        let visibilityPopup = NSPopUpButton()
        visibilityPopup.addItems(withTitles: ["公开", "私有"])
        visibilityPopup.selectItem(at: 0)

        let form = makeStack([
            makeLabel("仓库名称", font: .systemFont(ofSize: 11, weight: .medium)),
            nameField,
            makeLabel("项目说明", font: .systemFont(ofSize: 11, weight: .medium)),
            descriptionField,
            makeLabel("可见性", font: .systemFont(ofSize: 11, weight: .medium)),
            visibilityPopup
        ], orientation: .vertical, spacing: 5)
        nameField.widthAnchor.constraint(equalToConstant: 390).isActive = true
        descriptionField.widthAnchor.constraint(equalToConstant: 390).isActive = true
        visibilityPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 178))
        form.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 10),
            form.trailingAnchor.constraint(equalTo: accessory.trailingAnchor, constant: -10),
            form.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 6),
            form.bottomAnchor.constraint(lessThanOrEqualTo: accessory.bottomAnchor, constant: -6)
        ])
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = RepositoryName.sanitize(nameField.stringValue)
        guard name != "repository" || !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentError(AppAlert(title: "仓库名称无效", message: "请输入至少一个字母或数字。"))
            return
        }

        chooseAccount(title: "选择发布使用的账号") { [weak self] account in
            self?.store.publish(
                PublishRequest(
                    repository: repository,
                    name: name,
                    description: descriptionField.stringValue,
                    visibility: visibilityPopup.indexOfSelectedItem == 0 ? .publicRepository : .privateRepository
                ),
                account: account
            )
        }
    }

    private func presentCommit(_ repository: LocalRepository) {
        let alert = NSAlert()
        alert.messageText = "提交并推送"
        alert.informativeText = "\(repository.name) 中有 \(repository.changedFileCount) 个未提交文件。"
        alert.addButton(withTitle: "提交并推送")
        alert.addButton(withTitle: "取消")

        let messageField = NSTextField(string: "")
        messageField.placeholderString = "提交说明，例如：更新登录页面"
        messageField.frame = NSRect(x: 0, y: 0, width: 390, height: 26)
        alert.accessoryView = messageField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            presentError(AppAlert(title: "缺少提交说明", message: "请填写这次修改的目的。"))
            return
        }

        store.commitAndPush(CommitRequest(repository: repository, message: message))
    }

    private func confirmVisibilityChange(
        _ repository: LocalRepository,
        visibility: RepositoryVisibility
    ) {
        let alert = NSAlert()
        alert.messageText = "切换为\(visibility.title)仓库？"
        alert.informativeText = visibility == .publicRepository
            ? "仓库内容、提交记录和文件将对所有人可见。公开后无法保证内容没有被复制或索引。"
            : "仓库将不再对公众可见，但已有克隆和镜像不会因此消失。"
        alert.alertStyle = visibility == .publicRepository ? .warning : .informational
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.confirmVisibilityChange(VisibilityChange(repository: repository, visibility: visibility))
    }

    private func presentAccountManager() {
        let alert = NSAlert()
        alert.messageText = "GitHub 账号管理"
        alert.informativeText = store.currentAccount.map {
            "当前账号：\($0.displayName) · @\($0.login)"
        } ?? "尚未添加 GitHub 账号。"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        popup.addItems(withTitles: store.accounts.map { "\($0.displayName) · @\($0.login)" })
        if let currentAccountID = store.currentAccountID,
           let index = store.accounts.firstIndex(where: { $0.id == currentAccountID }) {
            popup.selectItem(at: index)
        }
        alert.accessoryView = popup

        alert.addButton(withTitle: "添加账号")
        if !store.accounts.isEmpty {
            alert.addButton(withTitle: "切换")
            alert.addButton(withTitle: "移除")
        }
        alert.addButton(withTitle: "关闭")

        let response = alert.runModal()
        let baseIndex = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

        if response.rawValue == baseIndex {
            store.beginLogin()
            return
        }

        if !store.accounts.isEmpty {
            if response.rawValue == baseIndex + 1 {
                let index = max(0, popup.indexOfSelectedItem)
                guard store.accounts.indices.contains(index) else { return }
                store.switchAccount(to: store.accounts[index])
                return
            }

            if response.rawValue == baseIndex + 2 {
                let index = max(0, popup.indexOfSelectedItem)
                guard store.accounts.indices.contains(index) else { return }
                confirmRemoveAccount(store.accounts[index])
            }
        }
    }

    private func confirmRemoveAccount(_ account: GitHubAccount) {
        let alert = NSAlert()
        alert.messageText = "移除 GitHub 账号？"
        alert.informativeText = "将删除 \(account.login) 保存在这台 Mac Keychain 中的令牌，不影响 GitHub 账号或远程仓库。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeAccount(account)
        }
    }

    private func presentLogin(_ presentation: LoginPresentation) {
        let alert = NSAlert()
        alert.messageText = "在浏览器中完成 GitHub 登录"
        alert.informativeText = "浏览器已打开。\n\n验证码：\(presentation.userCode)\n\n输入验证码并确认授权后，应用会自动完成登录。"
        alert.addButton(withTitle: "复制验证码")
        alert.addButton(withTitle: "取消登录")

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(presentation.userCode, forType: .string)
            showNotice("验证码已复制")
        } else {
            store.cancelLogin()
        }
    }

    private func presentNewProject() {
        chooseAccount(title: "选择新项目使用的账号") { [weak self] account in
            guard let self else { return }

            let alert = NSAlert()
            alert.messageText = "新建并发布项目"
            alert.informativeText = "项目会创建在 \(self.store.workspaceRootPath)"
            alert.addButton(withTitle: "创建项目")
            alert.addButton(withTitle: "取消")

            let nameField = NSTextField(string: "")
            nameField.placeholderString = "项目名称"
            let descriptionField = NSTextField(string: "")
            descriptionField.placeholderString = "项目说明"
            let visibilityPopup = NSPopUpButton()
            visibilityPopup.addItems(withTitles: ["公开", "私有"])
            visibilityPopup.selectItem(at: 0)

            let form = makeStack([
                makeLabel("项目名称", font: .systemFont(ofSize: 11, weight: .medium)),
                nameField,
                makeLabel("项目说明", font: .systemFont(ofSize: 11, weight: .medium)),
                descriptionField,
                makeLabel("可见性", font: .systemFont(ofSize: 11, weight: .medium)),
                visibilityPopup
            ], orientation: .vertical, spacing: 5)
            nameField.widthAnchor.constraint(equalToConstant: 390).isActive = true
            descriptionField.widthAnchor.constraint(equalToConstant: 390).isActive = true
            visibilityPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true

            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 178))
            form.translatesAutoresizingMaskIntoConstraints = false
            accessory.addSubview(form)
            NSLayoutConstraint.activate([
                form.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 10),
                form.trailingAnchor.constraint(equalTo: accessory.trailingAnchor, constant: -10),
                form.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 6),
                form.bottomAnchor.constraint(lessThanOrEqualTo: accessory.bottomAnchor, constant: -6)
            ])
            alert.accessoryView = accessory

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let projectName = RepositoryName.sanitize(nameField.stringValue)
            guard projectName != "repository" else {
                self.presentError(AppAlert(title: "项目名称无效", message: "请输入至少一个字母或数字。"))
                return
            }

            self.store.createProject(
                name: projectName,
                description: descriptionField.stringValue,
                visibility: visibilityPopup.indexOfSelectedItem == 0 ? .publicRepository : .privateRepository,
                account: account
            )
        }
    }

    private func presentStandardize(_ repository: LocalRepository) {
        chooseAccount(title: "选择仓库体检使用的账号") { [weak self] _ in
            guard let self else { return }

            let alert = NSAlert()
            alert.messageText = "补齐仓库基础文件"
            alert.informativeText = "将检查并补充 README、.gitignore、基础 CI；可选择同时添加 MIT License。不会自动提交。"
            alert.addButton(withTitle: "开始补齐")
            alert.addButton(withTitle: "取消")

            let licenseCheckbox = NSButton(checkboxWithTitle: "添加 MIT License", target: nil, action: nil)
            licenseCheckbox.state = .off
            alert.accessoryView = licenseCheckbox

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.store.standardize(repository, includeMITLicense: licenseCheckbox.state == .on)
        }
    }

    private func chooseAccount(
        title: String,
        completion: @escaping (GitHubAccount) -> Void
    ) {
        if store.accounts.isEmpty {
            store.beginLogin()
            return
        }

        if store.accounts.count == 1, let account = store.accounts.first {
            completion(account)
            return
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "选择一个 GitHub 账号执行本次操作。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton()
        popup.addItems(withTitles: store.accounts.map { "\($0.displayName) · @\($0.login)" })
        if let currentAccountID = store.currentAccountID,
           let index = store.accounts.firstIndex(where: { $0.id == currentAccountID }) {
            popup.selectItem(at: index)
        }
        popup.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = max(0, popup.indexOfSelectedItem)
        guard store.accounts.indices.contains(index) else { return }
        completion(store.accounts[index])
    }

    private func presentBatchSyncReport(_ report: BatchSyncReport) {
        let alert = NSAlert()
        alert.messageText = "批量同步完成"
        alert.informativeText = [
            "成功 \(report.succeeded.count)",
            "跳过 \(report.skipped.count)",
            "失败 \(report.failed.count)",
            ([report.succeeded, report.skipped, report.failed]
                .flatMap { $0 }
                .prefix(10)
                .joined(separator: "\n"))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        alert.addButton(withTitle: "关闭")
        alert.runModal()
        store.batchSyncReport = nil
    }

    private func presentError(_ alertData: AppAlert) {
        let alert = NSAlert()
        alert.messageText = alertData.title
        alert.informativeText = alertData.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showNotice(_ message: String) {
        toastWorkItem?.cancel()
        noticeLabel.stringValue = message
        noticeLabel.isHidden = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.noticeLabel.isHidden = true
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
