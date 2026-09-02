import AppKit

final class TouchBarRateLimitsView: NSView {
    private let codexIconView = NSImageView()
    private let resetCreditIconView = NSImageView()
    private let resetCreditCountLabel = NSTextField(labelWithString: "重置券 ×--")
    private let resetCreditExpirationLabel = NSTextField(labelWithString: "--")
    private let resetCreditDetails = NSStackView()
    private let resetCreditCard = NSStackView()
    private let fiveHourRow = TouchBarLimitRow(title: "5 小时")
    private let weeklyRow = TouchBarLimitRow(title: "周限额")
    private let rows = NSStackView()

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with state: RateLimitDisplayState) {
        updateResetCreditCard(state.resetCredits)

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
            fiveHourRow.updatePlaceholder(title: "5 小时", usageText: "昨--")
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
        guard let resetCredits else {
            resetCreditCard.isHidden = true
            return
        }

        resetCreditCountLabel.stringValue = "重置券 ×\(resetCredits.availableCount)"
        resetCreditExpirationLabel.stringValue = resetCredits.expirationText
        resetCreditCard.toolTip = "重置券，\(resetCredits.expirationText)"
        resetCreditCard.isHidden = false
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        codexIconView.image = Self.codexIcon()
        codexIconView.imageAlignment = .alignCenter
        codexIconView.imageScaling = .scaleProportionallyUpOrDown
        codexIconView.translatesAutoresizingMaskIntoConstraints = false
        codexIconView.toolTip = "Codex"

        resetCreditIconView.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "重置券"
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

        let content = NSStackView(views: [codexIconView, rows, resetCreditCard])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.setCustomSpacing(2, after: codexIconView)
        content.setCustomSpacing(8, after: rows)

        addSubview(content)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 606),
            heightAnchor.constraint(equalToConstant: 30),
            codexIconView.widthAnchor.constraint(equalToConstant: 34),
            codexIconView.heightAnchor.constraint(equalToConstant: 30),
            fiveHourRow.widthAnchor.constraint(equalToConstant: 450),
            weeklyRow.widthAnchor.constraint(equalToConstant: 450),
            resetCreditCard.widthAnchor.constraint(equalToConstant: 112),
            resetCreditCard.heightAnchor.constraint(equalToConstant: 30),
            resetCreditIconView.widthAnchor.constraint(equalToConstant: 14),
            resetCreditIconView.heightAnchor.constraint(equalToConstant: 14),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
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

    func updatePlaceholder(title: String, usageText: String) {
        titleLabel.stringValue = title
        batteryBar.isHidden = false
        batteryBar.remainingPercent = 0
        batteryBar.isDimmed = true
        remainingLabel.stringValue = "剩余 --"
        resetLabel.stringValue = "--"
        usageLabel.stringValue = usageText
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
