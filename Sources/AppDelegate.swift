import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, RateLimitStoreDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = RateLimitStore()
    private let lifecycleMonitor = CodexLifecycleMonitor()
    private var touchBarVisibilityMenuItem: NSMenuItem?
    private var connectionStatusMenuItem: NSMenuItem?
    private var lastUpdatedMenuItem: NSMenuItem?
    private var refreshDataMenuItem: NSMenuItem?
    private var reloadTouchBarMenuItem: NSMenuItem?
    private var autoLaunchMenuItem: NSMenuItem?
    private var hideStatusItemMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var languageMenuItem: NSMenuItem?
    private var languageSubmenuItems: [AppLanguage: NSMenuItem] = [:]
    private let touchBarController = TouchBarController()
    private var latestState = RateLimitDisplayState.initial

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodexAutoLauncher.installOrUpdate()
        CodexAutoLauncher.clearManualQuitLock()

        store.delegate = self
        touchBarController.onRefresh = { [weak self] in
            self?.store.refreshManually()
        }
        store.onManualRefreshResult = { [weak self] success in
            self?.touchBarController.showRefreshResult(success)
        }
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
        latestState = state
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
        button.toolTip = L10n.appName
        statusItem.menu = makeStatusMenu()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let connectionStatusItem = NSMenuItem(title: L10n.connectionStatus(.idle, hasData: false), action: nil, keyEquivalent: "")
        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)
        connectionStatusMenuItem = connectionStatusItem

        let lastUpdatedItem = NSMenuItem(title: L10n.updated(nil), action: nil, keyEquivalent: "")
        lastUpdatedItem.isEnabled = false
        menu.addItem(lastUpdatedItem)
        lastUpdatedMenuItem = lastUpdatedItem

        menu.addItem(.separator())

        let visibilityItem = NSMenuItem(
            title: L10n.hideTouchBar,
            action: #selector(toggleTouchBar(_:)),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        touchBarVisibilityMenuItem = visibilityItem

        let refreshDataItem = NSMenuItem(
            title: L10n.refreshData,
            action: #selector(refreshDataFromMenu(_:)),
            keyEquivalent: ""
        )
        refreshDataItem.target = self
        menu.addItem(refreshDataItem)
        refreshDataMenuItem = refreshDataItem

        let reloadTouchBarItem = NSMenuItem(
            title: L10n.reloadTouchBar,
            action: #selector(reloadTouchBarFromMenu(_:)),
            keyEquivalent: ""
        )
        reloadTouchBarItem.target = self
        menu.addItem(reloadTouchBarItem)
        reloadTouchBarMenuItem = reloadTouchBarItem

        let languageItem = NSMenuItem(title: L10n.language, action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(changeLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
            languageSubmenuItems[language] = item
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        languageMenuItem = languageItem
        updateLanguageMenuState()

        let autoLaunchItem = NSMenuItem(
            title: L10n.followCodex,
            action: #selector(toggleAutoLaunchFromMenu(_:)),
            keyEquivalent: ""
        )
        autoLaunchItem.target = self
        autoLaunchItem.state = CodexAutoLauncher.followsCodexLaunch ? .on : .off
        menu.addItem(autoLaunchItem)
        autoLaunchMenuItem = autoLaunchItem

        let hideStatusItem = NSMenuItem(
            title: L10n.hideStatusItem,
            action: #selector(hideStatusItemFromMenu(_:)),
            keyEquivalent: ""
        )
        hideStatusItem.target = self
        menu.addItem(hideStatusItem)
        hideStatusItemMenuItem = hideStatusItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.quit,
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenuItem = quitItem
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
            ? L10n.hideTouchBar
            : L10n.showTouchBar
    }

    private func updateRateLimitStatusMenu(with state: RateLimitDisplayState) {
        connectionStatusMenuItem?.title = L10n.connectionStatus(
            state.connectionState,
            hasData: state.lastUpdated != nil
        )
        lastUpdatedMenuItem?.title = L10n.updated(state.lastUpdated)
        connectionStatusMenuItem?.toolTip = state.lastError
    }

    private func updateLanguageMenuState() {
        let currentLanguage = AppLanguage.current
        for (language, item) in languageSubmenuItems {
            item.state = language == currentLanguage ? .on : .off
        }
    }

    private func updateMenuLanguage() {
        languageMenuItem?.title = L10n.language
        refreshDataMenuItem?.title = L10n.refreshData
        reloadTouchBarMenuItem?.title = L10n.reloadTouchBar
        autoLaunchMenuItem?.title = L10n.followCodex
        hideStatusItemMenuItem?.title = L10n.hideStatusItem
        quitMenuItem?.title = L10n.quit
        for (language, item) in languageSubmenuItems {
            item.title = language.displayName
        }
        updateLanguageMenuState()
        updateTouchBarMenuTitle()
        updateRateLimitStatusMenu(with: latestState)
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            return
        }
        AppLanguage.set(language)
        updateMenuLanguage()
        touchBarController.applyLanguage()
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
