import Foundation

struct GetAccountRateLimitsResponse: Codable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsResponse?
}

struct GetAccountUsageResponse: Codable {
    let summary: AccountUsageSummary?
    let dailyUsageBuckets: [DailyUsageBucket]?
}

struct AccountUsageSummary: Codable {
    let lifetimeTokens: Int?
}

struct DailyUsageBucket: Codable, Equatable {
    let startDate: String
    let tokens: Int
}

struct RateLimitSnapshot: Codable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct RateLimitWindow: Codable {
    let usedPercent: Double
    let windowDurationMins: Double?
    let resetsAt: Double?
}

struct RateLimitResetCreditsResponse: Codable {
    let availableCount: Int
    let credits: [RateLimitResetCreditResponse]?
}

struct RateLimitResetCreditResponse: Codable {
    let status: String?
    let expiresAt: Double?
}

struct LimitMeter: Equatable {
    let remainingPercent: Double
    private let resetDate: Date?

    var remainingText: String {
        "\(Int(remainingPercent.rounded()))%"
    }

    var resetText: String {
        guard let resetDate else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current

        formatter.dateFormat = "MM月dd日 HH:mm"

        return formatter.string(from: resetDate)
    }

    init(window: RateLimitWindow) {
        self.remainingPercent = max(0, min(100, 100 - window.usedPercent))
        self.resetDate = Self.date(fromEpoch: window.resetsAt)
    }

    private static func date(fromEpoch value: Double?) -> Date? {
        guard let value else {
            return nil
        }

        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

struct RateLimitDisplayState: Equatable {
    var fiveHour: LimitMeter?
    var weekly: LimitMeter?
    var resetCredits: ResetCreditSummary?
    var tokenUsage: TokenUsageSummary?
    var lastUpdated: Date?
    var connectionState: RateLimitConnectionState
    var lastError: String?

    static let initial = RateLimitDisplayState(
        fiveHour: nil,
        weekly: nil,
        resetCredits: nil,
        tokenUsage: nil,
        lastUpdated: nil,
        connectionState: .idle,
        lastError: nil
    )
}

enum RateLimitConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed
}

struct ResetCreditSummary: Equatable {
    let availableCount: Int
    let earliestExpirationDate: Date?

    var isExpiringSoon: Bool {
        guard let earliestExpirationDate else {
            return false
        }
        return earliestExpirationDate.timeIntervalSinceNow <= 3 * 24 * 60 * 60
    }

    var expirationText: String {
        guard let earliestExpirationDate else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: earliestExpirationDate)
    }

    init(response: RateLimitResetCreditsResponse) {
        availableCount = max(0, response.availableCount)
        earliestExpirationDate = response.credits?
            .filter { $0.status == nil || $0.status == "available" }
            .compactMap { credit in
                guard let value = credit.expiresAt else {
                    return nil
                }
                let seconds = value > 10_000_000_000 ? value / 1000 : value
                return Date(timeIntervalSince1970: seconds)
            }
            .min()
    }
}

struct TokenUsageSummary: Equatable {
    let yesterdayTokens: Int?
    let cumulativeTokens: Int?
    let dailyUsageBuckets: [DailyUsageBucket]

    init(response: GetAccountUsageResponse, calendar: Calendar = .current, now: Date = Date()) {
        dailyUsageBuckets = response.dailyUsageBuckets ?? []

        if !dailyUsageBuckets.isEmpty,
           let yesterday = calendar.date(
               byAdding: .day,
               value: -1,
               to: calendar.startOfDay(for: now)
           ) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let yesterdayKey = formatter.string(from: yesterday)
            yesterdayTokens = dailyUsageBuckets
                .filter { $0.startDate == yesterdayKey }
                .reduce(0) { $0 + $1.tokens }
        } else {
            yesterdayTokens = nil
        }

        cumulativeTokens = response.summary?.lifetimeTokens
    }

    var yesterdayText: String {
        guard let yesterdayTokens else {
            return "昨--"
        }
        return "昨\(Self.formatAsWan(yesterdayTokens))"
    }

    var cumulativeText: String {
        guard let cumulativeTokens else {
            return "总--"
        }
        return "总\(Self.formatAsYi(cumulativeTokens))"
    }

    private static func formatAsWan(_ tokens: Int) -> String {
        let value = Double(tokens) / 10_000
        return "\(formatted(value))万"
    }

    private static func formatAsYi(_ tokens: Int) -> String {
        let value = Double(tokens) / 100_000_000
        return "\(formatted(value))亿"
    }

    private static func formatted(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}
