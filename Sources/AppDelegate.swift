import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, RateLimitStoreDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = RateLimitStore()
    private let localUsage = LocalUsageCost()
    private let usageMenu = NSMenu()
    private var usageMenuItem: NSMenuItem?
    private var usageSnapshot: LocalUsageSnapshot?
    private var usageTimer: Timer?
    private let defaultPageMenuItem = NSMenuItem()
    private var usageWarning: String?
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
            self?.refreshLocalUsage(force: true)
        }
        store.onManualRefreshResult = { [weak self] success in
            self?.touchBarController.showRefreshResult(success)
        }
        configureStatusItem()
        refreshLocalUsage()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshLocalUsage(force: true)
        }
        usageTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshUsageAfterClockChange), name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshUsageAfterClockChange), name: NSWorkspace.didWakeNotification, object: nil)
        configureLifecycleMonitor()
        lifecycleMonitor.start()

        if lifecycleMonitor.codexIsRunningNow() {
            codexDidStart()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        menu.delegate = self

        let connectionStatusItem = NSMenuItem(title: L10n.connectionStatus(.idle, hasData: false), action: nil, keyEquivalent: "")
        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)
        connectionStatusMenuItem = connectionStatusItem

        let lastUpdatedItem = NSMenuItem(title: L10n.updated(nil), action: nil, keyEquivalent: "")
        lastUpdatedItem.isEnabled = false
        menu.addItem(lastUpdatedItem)
        lastUpdatedMenuItem = lastUpdatedItem

        let usageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        usageItem.submenu = usageMenu
        menu.addItem(usageItem)
        usageMenuItem = usageItem
        updateUsageMenu()

        menu.addItem(defaultPageMenuItem)
        updateDefaultPageMenu()

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

    func menuWillOpen(_ menu: NSMenu) {
        refreshLocalUsage()
    }

    private func refreshLocalUsage(force: Bool = false) {
        if let snapshot = usageSnapshot, !Calendar.current.isDateInToday(snapshot.day) {
            usageSnapshot = nil
            usageWarning = nil
            touchBarController.updateLocalUsage(nil, warning: nil)
            updateUsageMenu()
        }
        localUsage.refresh(force: force) { [weak self] usage, warning in
            self?.usageSnapshot = usage
            self?.usageWarning = warning
            self?.touchBarController.updateLocalUsage(usage, warning: warning)
            self?.updateUsageMenu()
        }
    }

    @objc private func refreshUsageAfterClockChange(_ notification: Notification) {
        refreshLocalUsage(force: true)
    }

    private func updateDefaultPageMenu() {
        defaultPageMenuItem.title = L10n.defaultTouchBarPage
        let menu = NSMenu()
        let selected = UserDefaults.standard.string(forKey: "defaultTouchBarPage") ?? "remember"
        for (key, title) in [("remember", L10n.rememberPage), ("rotate", L10n.autoRotatePages)] + TouchBarPage.allCases.map({ ($0.rawValue, $0.title) }) {
            let item = NSMenuItem(title: title, action: #selector(changeDefaultPage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = key == selected ? .on : .off
            menu.addItem(item)
        }
        defaultPageMenuItem.submenu = menu
    }

    @objc private func changeDefaultPage(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if key == "remember" {
            UserDefaults.standard.removeObject(forKey: "defaultTouchBarPage")
        } else if key == "rotate" || TouchBarPage(rawValue: key) != nil {
            UserDefaults.standard.set(key, forKey: "defaultTouchBarPage")
        }
        touchBarController.applyDefaultPage()
        updateDefaultPageMenu()
    }

    private func updateUsageMenu() {
        usageMenuItem?.title = L10n.isEnglish ? "Today's local usage · estimated cost" : "今日本地用量 · 估算费用"
        usageMenu.removeAllItems()
        func add(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            usageMenu.addItem(item)
        }
        add(L10n.isEnglish ? "API estimate (USD), not subscription charges" : "API 价格估算（美元），非订阅账单")
        if let snapshot = usageSnapshot {
            L10n.localUsageDetails(snapshot).forEach(add)
            usageMenu.addItem(.separator())
        }
        let modelUsage = usageSnapshot?.today ?? [:]
        for model in modelUsage.keys.sorted() {
            let usage = modelUsage[model]!
            let cost = usage.cost.map { String(format: "$%.4f", $0) }
                ?? (L10n.isEnglish ? "Price unknown" : "价格未知")
            let label = model == "codex-auto-review" ? "\(model) (≈ gpt-5.6-luna)" : model
            add("\(label): \(NumberFormatter.localizedString(from: NSNumber(value: usage.tokens), number: .decimal)) tokens · \(cost) · \(L10n.cacheRate(usage))")
        }
        if modelUsage.isEmpty {
            add(usageSnapshot != nil ? (L10n.isEnglish ? "No usage today" : "今日暂无用量") : (L10n.isEnglish ? "Loading…" : "读取中…"))
        }
        if let usageWarning { add(usageWarning) }
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
        updateUsageMenu()
        updateDefaultPageMenu()
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
        refreshLocalUsage(force: true)
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
