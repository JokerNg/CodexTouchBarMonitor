import AppKit

final class SegmentedBatteryBar: NSView {
    var remainingPercent: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }

    var isDimmed: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 11)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - 2.5,
            width: max(0, bounds.width),
            height: 5
        )
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.17, alpha: 0.95).setFill()
        trackPath.fill()

        let progress = CGFloat(max(0, min(100, remainingPercent)) / 100)
        let progressWidth = trackRect.width * progress
        guard !isDimmed, progressWidth > 0 else {
            return
        }

        let progressRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: progressWidth,
            height: trackRect.height
        )
        let progressPath = NSBezierPath(
            roundedRect: progressRect,
            xRadius: progressRect.height / 2,
            yRadius: progressRect.height / 2
        )
        accentColor.withAlphaComponent(0.96).setFill()
        progressPath.fill()
    }

    private var accentColor: NSColor {
        if isDimmed {
            return NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.58, alpha: 1.0)
        }
        if remainingPercent <= 20 {
            return .systemRed
        }
        if remainingPercent <= 45 {
            return NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.16, alpha: 1.0)
        }
        return NSColor(calibratedRed: 0.16, green: 0.86, blue: 1.0, alpha: 1.0)
    }
}
