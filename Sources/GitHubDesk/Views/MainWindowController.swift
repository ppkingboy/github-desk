import AppKit

final class MainWindowController: NSWindowController {
    private let store: AppStore
    private lazy var mainViewController = MainViewController(store: store)

    init(store: AppStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHub Desk"
        window.minSize = NSSize(width: 980, height: 620)
        window.center()

        super.init(window: window)
        window.contentViewController = mainViewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func refreshRepositories(_ sender: Any?) {
        store.refresh()
    }

    @objc func chooseWorkspace(_ sender: Any?) {
        store.chooseWorkspace()
    }
}
