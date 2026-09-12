import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private let store = AppStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let windowController = MainWindowController(store: store)
        self.windowController = windowController
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        store.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "关于 GitHub Desk",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "退出 GitHub Desk",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        let refreshItem = NSMenuItem(
            title: "刷新仓库",
            action: #selector(MainWindowController.refreshRepositories(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        fileMenu.addItem(refreshItem)

        let chooseItem = NSMenuItem(
            title: "选择项目目录",
            action: #selector(MainWindowController.chooseWorkspace(_:)),
            keyEquivalent: "O"
        )
        chooseItem.keyEquivalentModifierMask = [.command, .shift]
        chooseItem.target = self
        fileMenu.addItem(chooseItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func refreshRepositories(_ sender: Any?) {
        store.refresh()
    }

    @objc private func chooseWorkspace(_ sender: Any?) {
        store.chooseWorkspace()
    }
}
