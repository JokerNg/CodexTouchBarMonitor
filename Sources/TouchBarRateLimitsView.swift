import AppKit
import QuartzCore

final class TouchBarRateLimitsView: NSView {
    var onRefresh: (() -> Void)?

    private let codexIconButton = NSButton()
    private let refreshBadgeView = NSImageView()
    private let resetCreditIconView = NSImageView()
    private let resetCreditCountLabel = NSTextField(labelWithString: "重置卡 ×--")
    private let pageDots = NSStackView()
    private let cardPageDot = NSView()
    private let heatmapPageDot = NSView()
    private let resetCreditExpirationLabel = NSTextField(labelWithString: "--")
    private let resetCreditDetails = NSStackView()
    private let resetCreditCard = NSStackView()
    private let fiveHourRow = TouchBarLimitRow(title: "5 小时")
    private let weeklyRow = TouchBarLimitRow(title: "周限额")
    private let rows = NSStackView()
    private let heatmapView = UsageHeatmapView()
    private let heatmapToggleButton = NSButton()
    private var preferredHeatmap = UserDefaults.standard.bool(forKey: "showUsageHeatmap")
    private var showingHeatmap = false
    private var hasResetCredits = false

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with state: RateLimitDisplayState) {
        heatmapView.buckets = state.tokenUsage?.dailyUsageBuckets ?? []
        heatmapToggleButton.isEnabled = !heatmapView.buckets.isEmpty
        updateResetCreditCard(state.resetCredits)
        setHeatmapVisible(
            !heatmapView.buckets.isEmpty && (!hasResetCredits || preferredHeatmap)
        )

        if let fiveHour = state.fiveHour {
            fiveHourRow.isHidden = false
            fiveHourRow.updateLimit(
                title: "5 小时",
                meter: fiveHour,
                usageText: state.tokenUsage?.yesterdayText ?? "昨--"
            )
        } else if state.lastUpdated != nil {
            fiveHourRow.isHidden = true
        } else {
            fiveHourRow.isHidden = false
            fiveHourRow.updatePlaceholder(
                title: "5 小时",
                usageText: "昨--",
                statusText: state.connectionState == .failed ? "连接失败" : "连接中…"
            )
        }

        if let weekly = state.weekly {
            weeklyRow.isHidden = false
            weeklyRow.updateLimit(
                title: "周限额",
                meter: weekly,
                usageText: state.tokenUsage?.cumulativeText ?? "总--"
            )
        } else if state.lastUpdated != nil {
            weeklyRow.isHidden = true
        } else {
            weeklyRow.isHidden = false
            weeklyRow.updatePlaceholder(title: "周限额", usageText: "总--")
        }
    }

    private func updateResetCreditCard(_ resetCredits: ResetCreditSummary?) {
        guard let resetCredits, resetCredits.availableCount > 0 else {
            hasResetCredits = false
            resetCreditCard.isHidden = true
            return
        }

        hasResetCredits = true
        resetCreditCountLabel.stringValue = "重置卡 ×\(resetCredits.availableCount)"
        resetCreditExpirationLabel.stringValue = resetCredits.expirationText
        resetCreditCard.toolTip = "重置卡，\(resetCredits.expirationText)；点击切换半年用量图"
        let color: NSColor = resetCredits.isExpiringSoon
            ? .systemRed
            : NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 1.0)
        resetCreditIconView.contentTintColor = color
        resetCreditCountLabel.textColor = color
        resetCreditExpirationLabel.textColor = resetCredits.isExpiringSoon
            ? NSColor.systemRed.withAlphaComponent(0.92)
            : NSColor(calibratedRed: 0.65, green: 0.80, blue: 0.9, alpha: 0.82)
        resetCreditCard.isHidden = showingHeatmap
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        codexIconButton.image = Self.codexIcon()
        codexIconButton.imagePosition = .imageOnly
        codexIconButton.imageScaling = .scaleProportionallyUpOrDown
        codexIconButton.isBordered = false
        codexIconButton.focusRingType = .none
        codexIconButton.target = self
        codexIconButton.action = #selector(refreshTapped)
        codexIconButton.translatesAutoresizingMaskIntoConstraints = false
        codexIconButton.toolTip = "立即刷新"
        codexIconButton.setAccessibilityLabel("立即刷新 Codex 用量")

        let refreshColor = NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 1.0)
        if let symbol = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)) {
            let image = NSImage(size: symbol.size)
            image.lockFocus()
            symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            refreshColor.setFill()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceIn)
            image.unlockFocus()
            image.isTemplate = false
            refreshBadgeView.image = image
        }
        refreshBadgeView.imageScaling = .scaleProportionallyUpOrDown
        refreshBadgeView.translatesAutoresizingMaskIntoConstraints = false
        refreshBadgeView.wantsLayer = true
        codexIconButton.addSubview(refreshBadgeView)

        resetCreditIconView.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "重置卡"
        )
        resetCreditIconView.contentTintColor = NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 1.0)
        resetCreditIconView.imageScaling = .scaleProportionallyUpOrDown
        resetCreditIconView.translatesAutoresizingMaskIntoConstraints = false

        resetCreditCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        resetCreditCountLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 1.0)
        resetCreditCountLabel.lineBreakMode = .byClipping

        resetCreditExpirationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        resetCreditExpirationLabel.textColor = NSColor(calibratedRed: 0.65, green: 0.80, blue: 0.9, alpha: 0.82)
        resetCreditExpirationLabel.lineBreakMode = .byClipping

        resetCreditDetails.setViews([resetCreditCountLabel, resetCreditExpirationLabel], in: .leading)
        resetCreditDetails.translatesAutoresizingMaskIntoConstraints = false
        resetCreditDetails.orientation = .vertical
        resetCreditDetails.alignment = .leading
        resetCreditDetails.spacing = 0

        resetCreditCard.setViews([resetCreditIconView, resetCreditDetails], in: .leading)
        resetCreditCard.translatesAutoresizingMaskIntoConstraints = false
        resetCreditCard.orientation = .horizontal
        resetCreditCard.alignment = .centerY
        resetCreditCard.spacing = 4
        resetCreditCard.isHidden = true

        rows.setViews([fiveHourRow, weeklyRow], in: .leading)
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        let content = NSStackView(views: [codexIconButton, rows, resetCreditCard])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.setCustomSpacing(2, after: codexIconButton)
        content.setCustomSpacing(8, after: rows)

        addSubview(content)

        heatmapView.translatesAutoresizingMaskIntoConstraints = false
        heatmapView.isHidden = true
        addSubview(heatmapView)

        pageDots.translatesAutoresizingMaskIntoConstraints = false
        pageDots.orientation = .vertical
        pageDots.spacing = 2
        for dot in [cardPageDot, heatmapPageDot] {
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 1.5
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 3),
                dot.heightAnchor.constraint(equalToConstant: 3)
            ])
            pageDots.addArrangedSubview(dot)
        }
        addSubview(pageDots)

        heatmapToggleButton.title = ""
        heatmapToggleButton.isBordered = false
        heatmapToggleButton.isTransparent = true
        heatmapToggleButton.focusRingType = .none
        heatmapToggleButton.target = self
        heatmapToggleButton.action = #selector(toggleHeatmap)
        heatmapToggleButton.translatesAutoresizingMaskIntoConstraints = false
        heatmapToggleButton.setAccessibilityLabel("切换半年用量图")
        addSubview(heatmapToggleButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 606),
            heightAnchor.constraint(equalToConstant: 30),
            codexIconButton.widthAnchor.constraint(equalToConstant: 34),
            codexIconButton.heightAnchor.constraint(equalToConstant: 30),
            refreshBadgeView.widthAnchor.constraint(equalToConstant: 10),
            refreshBadgeView.heightAnchor.constraint(equalToConstant: 10),
            refreshBadgeView.trailingAnchor.constraint(equalTo: codexIconButton.trailingAnchor),
            refreshBadgeView.bottomAnchor.constraint(equalTo: codexIconButton.bottomAnchor, constant: -1),
            fiveHourRow.widthAnchor.constraint(equalToConstant: 450),
            weeklyRow.widthAnchor.constraint(equalToConstant: 450),
            resetCreditCard.widthAnchor.constraint(equalToConstant: 112),
            resetCreditCard.heightAnchor.constraint(equalToConstant: 30),
            resetCreditIconView.widthAnchor.constraint(equalToConstant: 14),
            resetCreditIconView.heightAnchor.constraint(equalToConstant: 14),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            heatmapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heatmapView.centerYAnchor.constraint(equalTo: centerYAnchor),
            heatmapView.widthAnchor.constraint(equalToConstant: 112),
            heatmapView.heightAnchor.constraint(equalToConstant: 30),
            heatmapToggleButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            heatmapToggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            heatmapToggleButton.widthAnchor.constraint(equalToConstant: 112),
            heatmapToggleButton.heightAnchor.constraint(equalToConstant: 30),
            pageDots.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageDots.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }

    @objc private func refreshTapped() {
        guard codexIconButton.isEnabled else { return }
        codexIconButton.isEnabled = false
        layoutSubtreeIfNeeded()
        if let layer = refreshBadgeView.layer {
            let frame = layer.frame
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
            CATransaction.commit()
        }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 0.45
        refreshBadgeView.layer?.add(animation, forKey: "refresh")
        onRefresh?()
    }

    func showRefreshResult(_ success: Bool) {
        refreshBadgeView.layer?.removeAnimation(forKey: "refresh")
        let original = refreshBadgeView.image
        if let symbol = NSImage(systemSymbolName: success ? "checkmark" : "exclamationmark", accessibilityDescription: success ? "刷新成功" : "刷新失败")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)) {
            let image = NSImage(size: symbol.size)
            image.lockFocus()
            symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            (success ? NSColor(calibratedRed: 0.16, green: 0.86, blue: 1, alpha: 1) : NSColor.systemRed).setFill()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceIn)
            image.unlockFocus()
            image.isTemplate = false
            refreshBadgeView.image = image
        }
        codexIconButton.setAccessibilityLabel(success ? "刷新成功" : "刷新失败")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.refreshBadgeView.image = original
            self.codexIconButton.isEnabled = true
            self.codexIconButton.setAccessibilityLabel("立即刷新 Codex 用量")
        }
    }

    @objc private func toggleHeatmap() {
        guard !heatmapView.buckets.isEmpty else {
            return
        }

        preferredHeatmap = !showingHeatmap
        UserDefaults.standard.set(preferredHeatmap, forKey: "showUsageHeatmap")
        setHeatmapVisible(preferredHeatmap)
    }

    private func setHeatmapVisible(_ visible: Bool) {
        showingHeatmap = visible
        heatmapView.isHidden = !showingHeatmap
        resetCreditCard.isHidden = showingHeatmap || !hasResetCredits
        pageDots.isHidden = !hasResetCredits
        heatmapToggleButton.isHidden = pageDots.isHidden
        let active = NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.16, alpha: 1).cgColor
        let inactive = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        cardPageDot.layer?.backgroundColor = showingHeatmap ? inactive : active
        heatmapPageDot.layer?.backgroundColor = showingHeatmap ? active : inactive
        heatmapToggleButton.toolTip = showingHeatmap ? "点击返回重置卡" : "点击切换半年用量图"
        heatmapToggleButton.setAccessibilityLabel(
            showingHeatmap ? "返回重置卡" : "切换半年用量图"
        )
    }

    private static func codexIcon() -> NSImage {
        let iconPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png",
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png",
            "/Applications/Codex.app/Contents/Resources/icon.icns"
        ]

        for path in iconPaths {
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 30, height: 30)
                return image
            }
        }

        let appPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        for path in appPaths where FileManager.default.fileExists(atPath: path) {
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: 30, height: 30)
            return image
        }

        let bundledIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
        let image = bundledIconPath.flatMap(NSImage.init(contentsOfFile:))
            ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
            ?? NSImage(size: NSSize(width: 30, height: 30))
        image.size = NSSize(width: 30, height: 30)
        return image
    }
}

private final class TouchBarLimitRow: NSView {
    private let titleLabel: NSTextField
    private let batteryBar = SegmentedBatteryBar()
    private let remainingLabel = NSTextField(labelWithString: "剩余 --")
    private let resetLabel = NSTextField(labelWithString: "--")
    private let separatorLabel = NSTextField(labelWithString: "|")
    private let usageLabel = NSTextField(labelWithString: "--")

    init(title: String) {
        self.titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLimit(title: String, meter: LimitMeter, usageText: String) {
        titleLabel.stringValue = title
        batteryBar.isHidden = false
        batteryBar.remainingPercent = meter.remainingPercent
        batteryBar.isDimmed = false
        remainingLabel.stringValue = "剩余 \(meter.remainingText)"
        resetLabel.stringValue = meter.resetText
        usageLabel.stringValue = usageText
    }

    func updatePlaceholder(title: String, usageText: String, statusText: String = "--") {
        titleLabel.stringValue = title
        batteryBar.isHidden = false
        batteryBar.remainingPercent = 0
        batteryBar.isDimmed = true
        remainingLabel.stringValue = "剩余 --"
        resetLabel.stringValue = statusText
        usageLabel.stringValue = usageText
    }

    func setUsageHidden(_ hidden: Bool) {
        usageLabel.isHidden = hidden
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.78, green: 0.92, blue: 1.0, alpha: 1.0)
        titleLabel.alignment = .right

        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        remainingLabel.textColor = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        remainingLabel.lineBreakMode = .byTruncatingTail

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        resetLabel.textColor = NSColor(calibratedRed: 0.74, green: 0.86, blue: 0.94, alpha: 0.92)
        resetLabel.lineBreakMode = .byTruncatingTail

        separatorLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        separatorLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 0.66)
        separatorLabel.alignment = .center

        usageLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        usageLabel.textColor = NSColor(calibratedRed: 0.65, green: 0.80, blue: 0.9, alpha: 0.82)
        usageLabel.lineBreakMode = .byTruncatingTail

        let statusContainer = NSView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        batteryBar.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.addSubview(batteryBar)

        let row = NSStackView(views: [
            titleLabel,
            statusContainer,
            remainingLabel,
            resetLabel,
            separatorLabel,
            usageLabel
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.setCustomSpacing(4, after: titleLabel)
        row.setCustomSpacing(0, after: remainingLabel)
        row.setCustomSpacing(4, after: resetLabel)
        row.setCustomSpacing(4, after: separatorLabel)

        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 15),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),
            statusContainer.widthAnchor.constraint(equalToConstant: 126),
            statusContainer.heightAnchor.constraint(equalToConstant: 12),
            batteryBar.widthAnchor.constraint(equalToConstant: 126),
            batteryBar.heightAnchor.constraint(equalToConstant: 12),
            batteryBar.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            batteryBar.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            remainingLabel.widthAnchor.constraint(equalToConstant: 66),
            resetLabel.widthAnchor.constraint(equalToConstant: 110),
            separatorLabel.widthAnchor.constraint(equalToConstant: 7),
            usageLabel.widthAnchor.constraint(equalToConstant: 68),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}


private final class UsageHeatmapView: NSView {
    var buckets: [DailyUsageBucket] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let latestKey = buckets.map(\.startDate).max(),
              let latestDate = Self.dateFormatter.date(from: latestKey) else {
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2

        let weekdayOffset = (calendar.component(.weekday, from: latestDate) + 5) % 7
        guard let latestWeekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: latestDate),
              let firstWeekStart = calendar.date(byAdding: .day, value: -25 * 7, to: latestWeekStart) else {
            return
        }

        let totals = Dictionary(grouping: buckets, by: \.startDate)
            .mapValues { $0.reduce(0) { $0 + $1.tokens } }
        let cellSize = NSSize(width: 3, height: 3)
        let gap = NSSize(width: 1, height: 1)
        let gridWidth = 26 * cellSize.width + 25 * gap.width
        let gridHeight = 7 * cellSize.height + 6 * gap.height
        let origin = NSPoint(
            x: floor((bounds.width - gridWidth) / 2),
            y: (bounds.height - gridHeight) / 2
        )


        for week in 0..<26 {
            for day in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: week * 7 + day,
                    to: firstWeekStart
                ) else {
                    continue
                }

                let key = Self.dateFormatter.string(from: date)
                let rect = NSRect(
                    x: origin.x + CGFloat(week) * (cellSize.width + gap.width),
                    y: origin.y + CGFloat(day) * (cellSize.height + gap.height),
                    width: cellSize.width,
                    height: cellSize.height
                )
                color(for: totals[key] ?? 0).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private func color(for tokens: Int) -> NSColor {
        let brightness: CGFloat
        switch tokens {
        case ...0:
            return NSColor(calibratedWhite: 0.12, alpha: 1)
        case ..<25_000_000:
            brightness = 0.30
        case ..<50_000_000:
            brightness = 0.45
        case ..<75_000_000:
            brightness = 0.60
        case ..<100_000_000:
            brightness = 0.78
        default:
            brightness = 1.0
        }
        return NSColor(
            calibratedRed: 0.16 * brightness,
            green: 0.86 * brightness,
            blue: brightness,
            alpha: 1
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
