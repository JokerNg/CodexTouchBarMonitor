import AppKit

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private enum TouchBarIdentifiers {
        static let touchBar = NSTouchBar.CustomizationIdentifier("com.wangjiaxuan666.CodexTouchBarMonitor.touchBar")
        static let limits = NSTouchBarItem.Identifier("com.wangjiaxuan666.CodexTouchBarMonitor.limits")
    }

    private let touchBarView = TouchBarRateLimitsView()
    private var currentState = RateLimitDisplayState.initial
    private var presentedTouchBar: NSTouchBar?

    var isTouchBarVisible: Bool {
        presentedTouchBar != nil
    }

    var onRefresh: (() -> Void)? {
        get { touchBarView.onRefresh }
        set { touchBarView.onRefresh = newValue }
    }

    func showRefreshResult(_ success: Bool) {
        touchBarView.showRefreshResult(success)
    }

    func applyLanguage() {
        touchBarView.update(with: currentState)
    }

    func makeQuotaTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.customizationIdentifier = TouchBarIdentifiers.touchBar
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [TouchBarIdentifiers.limits]
        return touchBar
    }

    @discardableResult
    func showSystemTouchBar() -> Bool {
        if presentedTouchBar != nil {
            return true
        }

        let touchBar = makeQuotaTouchBar()
        touchBarView.update(with: currentState)
        guard SystemModalTouchBar.present(touchBar) else {
            return false
        }

        presentedTouchBar = touchBar
        return true
    }

    func hideSystemTouchBar() {
        guard let touchBar = presentedTouchBar else {
            return
        }

        SystemModalTouchBar.dismiss(touchBar)
        presentedTouchBar = nil
    }

    func update(with state: RateLimitDisplayState) {
        currentState = state
        touchBarView.update(with: state)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case TouchBarIdentifiers.limits:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = touchBarView
            return item
        default:
            return nil
        }
    }
}
