import Foundation

protocol RateLimitStoreDelegate: AnyObject {
    func rateLimitStore(_ store: RateLimitStore, didUpdate state: RateLimitDisplayState)
}

final class RateLimitStore {
    weak var delegate: RateLimitStoreDelegate?

    private let client = CodexAppServerClient()
    private var timer: Timer?
    private var state = RateLimitDisplayState.initial
    private var refreshInFlight = false
    private var tokenUsageInFlight = false
    private var isStarted = false

    func start() {
        guard !isStarted else {
            refresh()
            return
        }
        isStarted = true

        client.onRateLimitsUpdated = { [weak self] in
            self?.refresh()
        }

        client.start { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.refresh()
                self.startTimer()
            case .failure:
                break
            }
        }
    }

    func stop() {
        isStarted = false
        refreshInFlight = false
        tokenUsageInFlight = false
        timer?.invalidate()
        timer = nil
        client.stop()
    }

    func refresh() {
        guard !refreshInFlight else {
            return
        }

        refreshInFlight = true

        client.readRateLimits { [weak self] result in
            guard let self else {
                return
            }

            self.refreshInFlight = false

            switch result {
            case .success(let response):
                self.apply(response)
            case .failure:
                break
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func apply(_ response: GetAccountRateLimitsResponse) {
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let windows = classifyWindows(primary: snapshot.primary, secondary: snapshot.secondary)

        state.fiveHour = windows.fiveHour
        state.weekly = windows.weekly
        state.resetCredits = response.rateLimitResetCredits.map(ResetCreditSummary.init)
        state.lastUpdated = Date()
        publish()
        refreshTokenUsage()
    }

    private func classifyWindows(primary: RateLimitWindow?, secondary: RateLimitWindow?) -> (fiveHour: LimitMeter?, weekly: LimitMeter?) {
        let candidates = [primary, secondary].compactMap { $0 }

        var fiveHourWindow = candidates.first { window in
            guard let duration = window.windowDurationMins else {
                return false
            }
            return abs(duration - 300) < 30
        }

        var weeklyWindow = candidates.first { window in
            guard let duration = window.windowDurationMins else {
                return false
            }
            return duration >= 7 * 24 * 60 - 60
        }

        // Older app-server versions relied on primary/secondary ordering and did
        // not always include durations. Only use that fallback when two distinct
        // windows are present, so a weekly-only window is never duplicated as 5h.
        if primary != nil, secondary != nil {
            fiveHourWindow = fiveHourWindow ?? primary
            weeklyWindow = weeklyWindow ?? secondary
        } else if fiveHourWindow == nil, weeklyWindow == nil {
            weeklyWindow = primary ?? secondary
        }

        let fiveHour = fiveHourWindow.map {
            LimitMeter(window: $0)
        }

        let weekly = weeklyWindow.map {
            LimitMeter(window: $0)
        }

        return (fiveHour, weekly)
    }

    private func publish() {
        delegate?.rateLimitStore(self, didUpdate: state)
    }

    private func refreshTokenUsage() {
        guard !tokenUsageInFlight else {
            return
        }

        tokenUsageInFlight = true
        client.readUsage { [weak self] result in
            guard let self else {
                return
            }

            self.tokenUsageInFlight = false
            guard self.isStarted else {
                return
            }

            guard case .success(let response) = result else {
                return
            }

            self.state.tokenUsage = TokenUsageSummary(response: response)
            self.publish()
        }
    }
}
