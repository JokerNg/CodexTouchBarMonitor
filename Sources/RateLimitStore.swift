import Foundation

protocol RateLimitStoreDelegate: AnyObject {
    func rateLimitStore(_ store: RateLimitStore, didUpdate state: RateLimitDisplayState)
}

final class RateLimitStore {
    weak var delegate: RateLimitStoreDelegate?
    var onManualRefreshResult: ((Bool) -> Void)?
    private var manualRefreshPending = false
    private var manualRefreshTimeout: DispatchWorkItem?

    func refreshManually() {
        guard !manualRefreshPending else { return }
        manualRefreshPending = true
        guard isStarted else {
            finishManualRefresh(false)
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishManualRefresh(false)
        }
        manualRefreshTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        refresh()
    }

    private func finishManualRefresh(_ success: Bool) {
        guard manualRefreshPending else { return }
        manualRefreshPending = false
        manualRefreshTimeout?.cancel()
        manualRefreshTimeout = nil
        onManualRefreshResult?(success)
    }

    private let client = CodexAppServerClient()
    private var timer: Timer?
    private var reconnectTimer: Timer?
    private var state = RateLimitDisplayState.initial
    private var refreshInFlight = false
    private var tokenUsageInFlight = false
    private var isStarted = false
    private let reconnectInterval: TimeInterval = 10

    func start() {
        guard !isStarted else {
            refresh()
            return
        }
        isStarted = true

        client.onRateLimitsUpdated = { [weak self] in
            self?.refresh()
        }
        client.onProcessTerminated = { [weak self] in
            self?.handleClientTermination()
        }

        state.connectionState = .connecting
        state.lastError = nil
        publish()
        connect()
    }

    func stop() {
        finishManualRefresh(false)
        isStarted = false
        refreshInFlight = false
        tokenUsageInFlight = false
        timer?.invalidate()
        timer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        client.onRateLimitsUpdated = nil
        client.onProcessTerminated = nil
        client.stop()
    }

    func refresh() {
        guard isStarted else {
            return
        }

        if state.connectionState == .failed {
            connect()
            return
        }

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
                self.state.connectionState = .connected
                self.state.lastError = nil
                self.apply(response)
            case .failure(let error):
                self.handleFailure(error)
            }
        }
    }

    private func connect() {
        guard isStarted else {
            return
        }

        reconnectTimer?.invalidate()
        reconnectTimer = nil
        state.connectionState = .connecting
        publish()

        client.start { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                guard self.isStarted else {
                    return
                }
                self.state.connectionState = .connected
                self.state.lastError = nil
                self.publish()
                self.startTimer()
                self.refresh()
            case .failure(let error):
                self.handleFailure(error)
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

    private func handleClientTermination() {
        handleFailure(CodexAppServerError.processUnavailable)
    }

    private func handleFailure(_ error: Error) {
        finishManualRefresh(false)
        guard isStarted else {
            return
        }

        refreshInFlight = false
        tokenUsageInFlight = false
        client.stop()
        state.connectionState = .failed
        state.lastError = error.localizedDescription
        publish()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isStarted, reconnectTimer == nil else {
            return
        }

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: false) { [weak self] _ in
            self?.reconnectTimer = nil
            self?.connect()
        }
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
                self.finishManualRefresh(false)
                return
            }

            self.state.tokenUsage = TokenUsageSummary(response: response)
            self.publish()
            self.finishManualRefresh(true)
        }
    }
}
