import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, RateLimitStoreDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = RateLimitStore()
    private let lifecycleMonitor = CodexLifecycleMonitor()
    private var touchBarVisibilityMenuItem: NSMenuItem?
    private var connectionStatusMenuItem: NSMenuItem?
    private var lastUpdatedMenuItem: NSMenuItem?
    private var autoLaunchMenuItem: NSMenuItem?
    private let touchBarController = TouchBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodexAutoLauncher.installOrUpdate()
        CodexAutoLauncher.clearManualQuitLock()

        store.delegate = self
        configureStatusItem()
        configureLifecycleMonitor()
        lifecycleMonitor.start()

        if lifecycleMonitor.codexIsRunningNow() {
            codexDidStart()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBarController.hideSystemTouchBar()
        lifecycleMonitor.stop()
        store.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        return false
    }

    func rateLimitStore(_ store: RateLimitStore, didUpdate state: RateLimitDisplayState) {
        touchBarController.update(with: state)
        updateRateLimitStatusMenu(with: state)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "bolt.horizontal.circle.fill",
            accessibilityDescription: "Codex"
        )
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "CodexTouchBarMonitor"
        statusItem.menu = makeStatusMenu()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let connectionStatusItem = NSMenuItem(title: "状态：未连接", action: nil, keyEquivalent: "")
        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)
        connectionStatusMenuItem = connectionStatusItem

        let lastUpdatedItem = NSMenuItem(title: "更新于：--", action: nil, keyEquivalent: "")
        lastUpdatedItem.isEnabled = false
        menu.addItem(lastUpdatedItem)
        lastUpdatedMenuItem = lastUpdatedItem

        menu.addItem(.separator())

        let visibilityItem = NSMenuItem(
            title: "隐藏 Touch Bar",
            action: #selector(toggleTouchBar(_:)),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        touchBarVisibilityMenuItem = visibilityItem

        let refreshDataItem = NSMenuItem(
            title: "立即刷新数据",
            action: #selector(refreshDataFromMenu(_:)),
            keyEquivalent: ""
        )
        refreshDataItem.target = self
        menu.addItem(refreshDataItem)

        let reloadTouchBarItem = NSMenuItem(
            title: "重新加载 Touch Bar",
            action: #selector(reloadTouchBarFromMenu(_:)),
            keyEquivalent: ""
        )
        reloadTouchBarItem.target = self
        menu.addItem(reloadTouchBarItem)

        let autoLaunchItem = NSMenuItem(
            title: "随 Codex 自动启动",
            action: #selector(toggleAutoLaunchFromMenu(_:)),
            keyEquivalent: ""
        )
        autoLaunchItem.target = self
        autoLaunchItem.state = CodexAutoLauncher.followsCodexLaunch ? .on : .off
        menu.addItem(autoLaunchItem)
        autoLaunchMenuItem = autoLaunchItem

        let hideStatusItem = NSMenuItem(
            title: "隐藏菜单栏图标",
            action: #selector(hideStatusItemFromMenu(_:)),
            keyEquivalent: ""
        )
        hideStatusItem.target = self
        menu.addItem(hideStatusItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func configureLifecycleMonitor() {
        lifecycleMonitor.onCodexStarted = { [weak self] in
            self?.codexDidStart()
        }
        lifecycleMonitor.onCodexStopped = { [weak self] in
            self?.codexDidStop()
        }
    }

    private func codexDidStart() {
        store.start()
        _ = touchBarController.showSystemTouchBar()
        updateTouchBarMenuTitle()
    }

    private func codexDidStop() {
        touchBarController.hideSystemTouchBar()
        store.stop()
        NSApp.terminate(nil)
    }

    @objc private func toggleTouchBar(_ sender: AnyObject?) {
        if touchBarController.isTouchBarVisible {
            touchBarController.hideSystemTouchBar()
        } else {
            _ = touchBarController.showSystemTouchBar()
        }
        updateTouchBarMenuTitle()
    }

    private func updateTouchBarMenuTitle() {
        touchBarVisibilityMenuItem?.title = touchBarController.isTouchBarVisible
            ? "隐藏 Touch Bar"
            : "显示 Touch Bar"
    }

    private func updateRateLimitStatusMenu(with state: RateLimitDisplayState) {
        switch state.connectionState {
        case .idle:
            connectionStatusMenuItem?.title = "状态：未连接"
        case .connecting:
            connectionStatusMenuItem?.title = "状态：连接中…"
        case .connected:
            connectionStatusMenuItem?.title = "状态：已连接"
        case .failed:
            connectionStatusMenuItem?.title = state.lastUpdated == nil
                ? "状态：连接失败"
                : "状态：连接失败（保留旧数据）"
        }

        if let lastUpdated = state.lastUpdated {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = "HH:mm:ss"
            lastUpdatedMenuItem?.title = "更新于：\(formatter.string(from: lastUpdated))"
        } else {
            lastUpdatedMenuItem?.title = "更新于：--"
        }
        connectionStatusMenuItem?.toolTip = state.lastError
    }

    @objc private func refreshDataFromMenu(_ sender: AnyObject?) {
        store.refresh()
    }

    @objc private func reloadTouchBarFromMenu(_ sender: AnyObject?) {
        touchBarController.hideSystemTouchBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }
            _ = self.touchBarController.showSystemTouchBar()
            self.updateTouchBarMenuTitle()
        }
    }

    @objc private func toggleAutoLaunchFromMenu(_ sender: NSMenuItem) {
        CodexAutoLauncher.setFollowsCodexLaunch(sender.state != .on)
        autoLaunchMenuItem?.state = CodexAutoLauncher.followsCodexLaunch ? .on : .off
    }

    @objc private func hideStatusItemFromMenu(_ sender: AnyObject?) {
        statusItem.isVisible = false
    }

    @objc private func quitFromMenu(_ sender: AnyObject?) {
        quitManually()
    }

    private func quitManually() {
        CodexAutoLauncher.markManualQuit()
        quitApp()
    }

    private func quitApp() {
        touchBarController.hideSystemTouchBar()
        lifecycleMonitor.stop()
        store.stop()
        NSApp.terminate(nil)
    }
}
