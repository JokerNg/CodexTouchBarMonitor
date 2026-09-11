import Foundation

struct LocalModelUsage {
    var input = 0
    var cached = 0
    var output = 0
    var cost: Double?
    var tokens: Int { input + output }
}

struct LocalUsageSnapshot {
    var day: Date
    var today: [String: LocalModelUsage] = [:]
    var yesterday: [String: LocalModelUsage] = [:]
    var isComplete = true

    static func total(_ usage: [String: LocalModelUsage]) -> LocalModelUsage {
        usage.values.reduce(LocalModelUsage(cost: 0)) { sum, value in
            LocalModelUsage(input: sum.input + value.input, cached: sum.cached + value.cached,
                output: sum.output + value.output,
                cost: sum.cost.flatMap { accumulated in value.cost.map { accumulated + $0 } })
        }
    }
}

final class LocalUsageCost {
    private var refreshing = false
    private var lastRefresh = Date.distantPast
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexTouchBarMonitor/litellm-prices.json")

    // Called on the main thread; disk scanning and price parsing stay off the UI thread.
    func refresh(force: Bool = false, completion: @escaping (LocalUsageSnapshot, String?) -> Void) {
        guard !refreshing, force || Date().timeIntervalSince(lastRefresh) > 60 else { return }
        refreshing = true
        let cacheURL = self.cacheURL
        DispatchQueue.global(qos: .utility).async {
            let cached = try? Data(contentsOf: cacheURL)
            let modified = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let finish: (Data?, String?) -> Void = { data, priceWarning in
                DispatchQueue.global(qos: .utility).async {
                    let prices = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] } ?? [:]
                    let (usage, warning) = Self.scan(prices: prices)
                    DispatchQueue.main.async {
                        self.refreshing = false
                        guard Calendar.current.isDateInToday(usage.day) else {
                            self.refresh(force: true, completion: completion)
                            return
                        }
                        self.lastRefresh = Date()
                        completion(usage, warning ?? priceWarning)
                    }
                }
            }
            if cached != nil, let modified, Date().timeIntervalSince(modified) < 86400 {
                finish(cached, nil)
                return
            }
            let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
            URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, response, _ in
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let prices = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
                      prices.values.contains(where: { $0["input_cost_per_token"] is Double }) else {
                    finish(cached, L10n.isEnglish ? "Prices unavailable or cached" : "价格更新失败，使用缓存或显示未知")
                    return
                }
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
                finish(data, nil)
            }.resume()
        }
    }

    static func cost(_ usage: LocalModelUsage, price: [String: Any]?) -> Double? {
        guard var price else { return nil }
        // Apply long-context tiers per request, before aggregating daily tokens.
        let prefix = "input_cost_per_token_above_"
        let tiers = price.keys.filter { $0.hasPrefix(prefix) }.compactMap { key -> (Int, String)? in
            let suffix = String(key.dropFirst(prefix.count))
            guard suffix.hasSuffix("k_tokens"), let thousands = Int(suffix.dropLast(8)) else { return nil }
            return (thousands * 1000, "_above_" + suffix)
        }.sorted { $0.0 < $1.0 }
        for (threshold, suffix) in tiers where usage.input > threshold {
            for key in ["input_cost_per_token", "output_cost_per_token", "cache_read_input_token_cost"] {
                if let value = price[key + suffix] { price[key] = value }
            }
        }
        guard let input = price["input_cost_per_token"] as? Double,
              let output = price["output_cost_per_token"] as? Double,
              input.isFinite, output.isFinite, input >= 0, output >= 0 else { return nil }
        let cached = price["cache_read_input_token_cost"] as? Double
        guard usage.cached == 0 || (cached != nil && cached!.isFinite && cached! >= 0) else { return nil }
        return Double(usage.input - usage.cached) * input
            + Double(usage.cached) * (cached ?? 0) + Double(usage.output) * output
    }

    static func scan(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
                     now: Date = Date(), calendar: Calendar = .current, prices: [String: [String: Any]] = [:]) -> (LocalUsageSnapshot, String?) {
        let start = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var snapshot = LocalUsageSnapshot(day: start)
        var warning: String?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in
                warning = L10n.isEnglish ? "Some session files could not be read" : "部分会话文件无法读取"
                return true
            }) else {
                snapshot.isComplete = false
                return (snapshot, L10n.isEnglish ? "Session directory unavailable" : "无法读取会话目录")
            }
        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let secondsParser = ISO8601DateFormatter()
        var days: [Date: [String: LocalModelUsage]] = [:]
        var seen = Set<String>()
        // ponytail: rescan files modified since yesterday; add offsets if scanning becomes slow.
        for case let file as URL in files where file.pathExtension == "jsonl" {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < yesterday { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else {
                warning = L10n.isEnglish ? "Some session files could not be read" : "部分会话文件无法读取"
                continue
            }
            defer { try? handle.close() }
            var model = "unknown"
            var previous: [String: Int]?
            var pending = Data()
            func consume(_ line: Data) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = object["type"] as? String,
                      let payload = object["payload"] as? [String: Any] else { return }
                if type == "turn_context" {
                    model = payload["model"] as? String ?? "unknown"
                    return
                }
                guard type == "event_msg", payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Int] else { return }
                let old = previous
                previous = total
                guard total != old,
                      let timestamp = object["timestamp"] as? String,
                      let date = dateParser.date(from: timestamp) ?? secondsParser.date(from: timestamp),
                      date >= yesterday, date < end else { return }
                let day = calendar.startOfDay(for: date)
                // Copied fork history retains timestamps and counters. Do not bill it twice.
                let key = timestamp + ":" + total.keys.sorted().map { "\($0)=\(total[$0]!)" }.joined(separator: ",")
                guard seen.insert(key).inserted else { return }
                let last = info["last_token_usage"] as? [String: Int]
                let reset = old == nil || (total["total_tokens"] ?? 0) < (old?["total_tokens"] ?? 0)
                func delta(_ name: String) -> Int {
                    max(0, reset ? (last?[name] ?? 0) : (total[name] ?? 0) - (old?[name] ?? 0))
                }
                let input = delta("input_tokens")
                let request = LocalModelUsage(input: input, cached: min(input, delta("cached_input_tokens")), output: delta("output_tokens"))
                let pricingModel = model == "codex-auto-review" ? "gpt-5.6-luna" : model
                let requestCost = delta("cache_write_input_tokens") == 0
                    ? Self.cost(request, price: prices[pricingModel] ?? prices["openai/" + pricingModel]) : nil
                var usage = days[day]?[model] ?? LocalModelUsage(cost: 0)
                if let accumulated = usage.cost, let requestCost { usage.cost = accumulated + requestCost }
                else { usage.cost = nil }
                usage.input += input
                usage.cached += min(input, delta("cached_input_tokens"))
                usage.output += delta("output_tokens")
                days[day, default: [:]][model] = usage
            }
            do {
                while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        consume(Data(pending[..<newline]))
                        pending.removeSubrange(...newline)
                    }
                }
                // An unterminated line may still be in the process of being written.
            } catch {
                warning = L10n.isEnglish ? "Some session files could not be read" : "部分会话文件无法读取"
            }
        }
        snapshot.today = days[start] ?? [:]
        snapshot.yesterday = days[yesterday] ?? [:]
        snapshot.isComplete = warning == nil
        return (snapshot, warning)
    }
}
