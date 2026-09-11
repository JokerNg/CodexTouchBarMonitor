import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case chinese
    case english

    private static let defaultsKey = "codexTouchBarLanguage"

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        return Locale.current.identifier.lowercased().hasPrefix("zh") ? .chinese : .english
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.isEnglish ? "System" : "跟随系统"
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum L10n {
    static var isEnglish: Bool {
        AppLanguage.current.resolved == .english
    }

    static var language: String { isEnglish ? "Language" : "语言" }
    static var fiveHour: String { isEnglish ? "5 hours" : "5 小时" }
    static var weeklyLimit: String { isEnglish ? "Weekly" : "周限额" }
    static var appName: String { "CodexTouchBarMonitor" }
    static var hideTouchBar: String { isEnglish ? "Hide Touch Bar" : "隐藏 Touch Bar" }
    static var showTouchBar: String { isEnglish ? "Show Touch Bar" : "显示 Touch Bar" }
    static var refreshData: String { isEnglish ? "Refresh Data" : "立即刷新数据" }
    static var reloadTouchBar: String { isEnglish ? "Reload Touch Bar" : "重新加载 Touch Bar" }
    static var followCodex: String { isEnglish ? "Launch with Codex" : "随 Codex 自动启动" }
    static var hideStatusItem: String { isEnglish ? "Hide Menu Bar Icon" : "隐藏菜单栏图标" }
    static var quit: String { isEnglish ? "Quit" : "退出" }
    static var refreshNow: String { isEnglish ? "Refresh now" : "立即刷新" }
    static var refreshAccessibility: String { isEnglish ? "Refresh Codex usage" : "立即刷新 Codex 用量" }
    static var refreshSuccess: String { isEnglish ? "Refresh succeeded" : "刷新成功" }
    static var refreshFailure: String { isEnglish ? "Refresh failed" : "刷新失败" }
    static var switchHeatmap: String { isEnglish ? "Show 6-month usage chart" : "切换半年用量图" }
    static var returnToResetCards: String { isEnglish ? "Return to reset cards" : "返回重置卡" }
    static var resetCard: String { isEnglish ? "Reset cards" : "重置卡" }
    static var connecting: String { isEnglish ? "Connecting…" : "连接中…" }
    static var connectionFailed: String { isEnglish ? "Connection failed" : "连接失败" }
    static var localCost: String { isEnglish ? "Today cost" : "今日费用" }
    static var localCostTooltip: String { isEnglish ? "Estimated API cost from local session logs" : "根据本地会话日志估算的 API 费用" }
    static var switchTouchBarPage: String { isEnglish ? "Switch Touch Bar page" : "切换 Touch Bar 页面" }
    static var defaultTouchBarPage: String { isEnglish ? "Default Touch Bar page" : "Touch Bar 默认页面" }
    static var rememberPage: String { isEnglish ? "Remember last page" : "记住上次页面" }
    static var autoRotatePages: String { isEnglish ? "Auto-rotate (10 seconds)" : "自动轮播（10 秒）" }

    static func localAmount(_ usage: LocalModelUsage, complete: Bool, decimals: Int = 4) -> String {
        guard complete, let cost = usage.cost else { return "$--" }
        return String(format: "$%.*f", decimals, cost)
    }

    static func cacheRate(_ usage: LocalModelUsage) -> String {
        let rate = usage.input > 0 ? String(format: "%.1f%%", Double(usage.cached) / Double(usage.input) * 100) : "--"
        return isEnglish ? "Cached input: \(rate)" : "缓存命中率：\(rate)"
    }

    static func localUsageDetails(_ snapshot: LocalUsageSnapshot) -> [String] {
        let today = LocalUsageSnapshot.total(snapshot.today)
        let yesterday = LocalUsageSnapshot.total(snapshot.yesterday)
        let todayAmount = localAmount(today, complete: snapshot.isComplete)
        let yesterdayAmount = localAmount(yesterday, complete: snapshot.isComplete)
        let difference: String
        if snapshot.isComplete, let current = today.cost, let previous = yesterday.cost {
            let delta = current - previous
            let amount = String(format: "%@$%.4f", delta < 0 ? "−" : "+", abs(delta))
            let percent = previous > 0 ? String(format: " (%+.1f%%)", delta / previous * 100) : ""
            difference = amount + percent
        } else {
            difference = "--"
        }
        return [
            isEnglish ? "Today estimate: \(todayAmount)" : "今日估算：\(todayAmount)",
            isEnglish ? "Yesterday (full day): \(yesterdayAmount)" : "昨日全天：\(yesterdayAmount)",
            isEnglish ? "Vs yesterday (full day): \(difference)" : "较昨日全天：\(difference)",
            snapshot.isComplete ? cacheRate(today) : (isEnglish ? "Cached input: --" : "缓存命中率：--")
        ]
    }

    static func resetCard(_ count: Int) -> String {
        "\(resetCard) ×\(count)"
    }

    static func resetCardTooltip(_ expiration: String) -> String {
        isEnglish
            ? "Reset cards, \(expiration); click to view 6-month usage"
            : "重置卡，\(expiration)；点击切换半年用量图"
    }

    static func connectionStatus(_ state: RateLimitConnectionState, hasData: Bool) -> String {
        let value: String
        switch state {
        case .idle:
            value = isEnglish ? "Disconnected" : "未连接"
        case .connecting:
            value = isEnglish ? "Connecting…" : "连接中…"
        case .connected:
            value = isEnglish ? "Connected" : "已连接"
        case .failed:
            value = isEnglish
                ? (hasData ? "Connection failed (keeping old data)" : "Connection failed")
                : (hasData ? "连接失败（保留旧数据）" : "连接失败")
        }
        return isEnglish ? "Status: \(value)" : "状态：\(value)"
    }

    static func updated(_ date: Date?) -> String {
        guard let date else {
            return isEnglish ? "Updated: --" : "更新于：--"
        }
        return isEnglish
            ? "Updated: \(clockFormatter.string(from: date))"
            : "更新于：\(clockFormatter.string(from: date))"
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = isEnglish ? "MMM d HH:mm" : "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    static func remaining(_ text: String) -> String {
        isEnglish ? "Left \(text)" : "剩余 \(text)"
    }

    static func yesterdayText(_ tokens: Int?) -> String {
        guard let tokens else { return isEnglish ? "Yday --" : "昨--" }
        return isEnglish ? "Yday \(compactTokens(tokens))" : "昨\(formatWan(tokens))"
    }

    static func cumulativeText(_ tokens: Int?) -> String {
        guard let tokens else { return isEnglish ? "Total --" : "总--" }
        return isEnglish ? "Total \(compactTokens(tokens))" : "总\(formatYi(tokens))"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func formatWan(_ tokens: Int) -> String {
        formatted(Double(tokens) / 10_000) + "万"
    }

    private static func formatYi(_ tokens: Int) -> String {
        formatted(Double(tokens) / 100_000_000) + "亿"
    }

    static func compactTokens(_ tokens: Int) -> String {
        let value: Double
        let unit: String
        switch abs(tokens) {
        case 1_000_000_000...:
            value = Double(tokens) / 1_000_000_000
            unit = "B"
        case 1_000_000...:
            value = Double(tokens) / 1_000_000
            unit = "M"
        case 1_000...:
            value = Double(tokens) / 1_000
            unit = "K"
        default:
            return "\(tokens)"
        }
        return formatted(value) + unit
    }

    private static func formatted(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}
