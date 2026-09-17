import UIKit

/// Separate from UIView's similarly named hook, which is also consulted for
/// an ancestor scroll view's recognizers when a touch starts on the chart.
final class ChartScrubGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }
}

final class PowerChartView: UIView {
    var onScrub: ((ChargingSample?) -> Void)?
    private let scrubDelegate = ChartScrubGestureDelegate()
    private let feedback = UISelectionFeedbackGenerator()
    private let plotLayer = CALayer()
    private let fillLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let endpointsLayer = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private var samples: [ChargingSample] = []
    private var selectedIndex: Int?
    private var clearGeneration = 0
    private var selectedWindow: ChartWindow = .recent
    private var revision: Revision?
    private var preparedSize = CGSize.zero
    private var presentations: [ChartWindow: Presentation] = [:]

    private struct Revision: Equatable {
        var sessionID: UUID?
        var sampleCount: Int
        var lastSample: ChargingSample?
    }

    private struct Presentation {
        var series: PowerChartSeries
        var line: CGPath
        var fill: CGPath
        var endpoints: CGPath
        var timeLabels: [String]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "USB input power chart"
        accessibilityTraits = [.adjustable]
        accessibilityIdentifier = "powerChart"

        let pan = UIPanGestureRecognizer(target: self, action: #selector(scrub(_:)))
        pan.delegate = scrubDelegate
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrub(_:)))
        tap.cancelsTouchesInView = false
        tap.require(toFail: pan)
        addGestureRecognizer(tap)

        plotLayer.masksToBounds = true
        layer.addSublayer(plotLayer)
        for shape in [fillLayer, lineLayer, endpointsLayer, cursorLayer, selectionLayer] {
            plotLayer.addSublayer(shape)
        }
        lineLayer.fillColor = nil
        lineLayer.lineWidth = 2.5
        lineLayer.lineJoin = .round
        lineLayer.lineCap = .round
        cursorLayer.fillColor = nil
        cursorLayer.lineWidth = 1
        cursorLayer.lineDashPattern = [3, 3]
        selectionLayer.lineWidth = 3
        updateColors()
        registerForTraitChanges(
            [UITraitUserInterfaceStyle.self]
        ) { (view: PowerChartView, _: UITraitCollection) in
            view.updateColors()
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var plot: CGRect {
        CGRect(x: 36, y: 12, width: max(1, bounds.width - 44), height: max(1, bounds.height - 42))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plotLayer.frame = plot.insetBy(dx: -3, dy: -3)
        for shape in [fillLayer, lineLayer, endpointsLayer, cursorLayer, selectionLayer] {
            shape.frame = plotLayer.bounds
            shape.contentsScale = traitCollection.displayScale
        }
        CATransaction.commit()
        if preparedSize != plot.size {
            preparePresentations()
            applyPresentation()
        }
    }

    func set(session: ChargingSession?, window: ChartWindow) {
        accessibilityLabel = "\(session?.measurement.title ?? "USB input") power chart"
        let next = Revision(
            sessionID: session?.id, sampleCount: session?.samples.count ?? 0, lastSample: session?.samples.last
        )
        let changed = revision != next
        let changedWindow = selectedWindow != window
        let changedSize = preparedSize != plot.size
        let oldSelection = currentSample
        if changedWindow || revision?.sessionID != next.sessionID { clearSelection() }
        selectedWindow = window
        if changed || changedSize {
            // Recorded samples are append-only. Build both windows on new data,
            // not during each segmented-control tap.
            revision = next
            samples = session?.samples ?? []
            preparePresentations()
        }
        if changed || changedWindow || changedSize {
            if !changedWindow, let oldSelection, let series = presentations[window]?.series {
                if oldSelection.timestamp >= series.start {
                    selectedIndex = series.nearestIndex(to: oldSelection.timestamp)
                } else {
                    clearSelection()
                }
            }
            applyPresentation()
            if currentSample != nil, oldSelection != currentSample { onScrub?(currentSample) }
        }
    }

    private func preparePresentations() {
        preparedSize = plot.size
        presentations = Dictionary(uniqueKeysWithValues: ChartWindow.allCases.map { window in
            let series = PowerChartSeries(samples: samples, window: window, columns: Int(plot.width))
            let line = CGMutablePath()
            let fill = CGMutablePath()
            let endpoints = CGMutablePath()
            for segment in series.segments {
                let points = segment.compactMap { sample in
                    sample.powerWatts.map { point(for: sample.timestamp, watts: $0, series: series) }
                }
                guard let first = points.first, let last = points.last else { continue }
                if points.count > 1 {
                    line.move(to: first)
                    fill.move(to: first)
                    for point in points.dropFirst() {
                        line.addLine(to: point)
                        fill.addLine(to: point)
                    }
                    fill.addLine(to: CGPoint(x: last.x, y: plot.height + 3))
                    fill.addLine(to: CGPoint(x: first.x, y: plot.height + 3))
                    fill.closeSubpath()
                }
                endpoints.addEllipse(in: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
            }
            let labels = [0.0, 0.5, 1.0].map {
                ReadingFormat.time(series.start.addingTimeInterval(series.end.timeIntervalSince(series.start) * $0))
            }
            return (
                window,
                Presentation(
                    series: series, line: line.copy() ?? line, fill: fill.copy() ?? fill,
                    endpoints: endpoints.copy() ?? endpoints, timeLabels: labels
                )
            )
        })
    }

    private func applyPresentation() {
        let presentation = presentations[selectedWindow]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = presentation?.line
        fillLayer.path = presentation?.fill
        endpointsLayer.path = presentation?.endpoints
        CATransaction.commit()
        updateCursor()
        updateAccessibility()
        // Only axes/text need UIView drawing. There is no whole-chart bitmap
        // cross-fade competing with the segmented control's native animation.
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        let series = presentations[selectedWindow]?.series
        let maximumWatts = series?.maximumWatts ?? 30
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.secondary,
        ]
        for step in 0 ... 3 {
            let fraction = Double(step) / 3
            let y = plot.maxY - CGFloat(fraction) * plot.height
            let line = UIBezierPath()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            line.setLineDash([3, 4], count: 2, phase: 0)
            Palette.separator.setStroke()
            line.lineWidth = 0.7
            line.stroke()
            let text = "\(ReadingFormat.number(maximumWatts * fraction, digits: 0))\(step == 3 ? " W" : "")"
            (text as NSString).draw(at: CGPoint(x: 0, y: y - 6), withAttributes: attributes)
        }
        for (index, label) in (presentations[selectedWindow]?.timeLabels ?? []).enumerated() {
            let fraction = CGFloat(index) / 2
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: plot.minX + fraction * (plot.width - size.width), y: plot.maxY + 12),
                withAttributes: attributes
            )
        }
        if series?.samples.isEmpty != false {
            let text = "Awaiting power readings" as NSString
            let emptyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13), .foregroundColor: Palette.secondary,
            ]
            let size = text.size(withAttributes: emptyAttributes)
            text.draw(
                at: CGPoint(x: plot.midX - size.width / 2, y: plot.midY - size.height / 2),
                withAttributes: emptyAttributes
            )
        }
    }

    private func point(for date: Date, watts: Double, series: PowerChartSeries) -> CGPoint {
        let fraction = date.timeIntervalSince(series.start) / max(1, series.end.timeIntervalSince(series.start))
        return CGPoint(
            x: CGFloat(fraction) * plot.width + 3,
            y: (1 - CGFloat(watts / series.maximumWatts)) * plot.height + 3
        )
    }

    private var currentSample: ChargingSample? {
        guard let selectedIndex, let series = presentations[selectedWindow]?.series,
              series.samples.indices.contains(selectedIndex) else { return nil }
        return series.samples[selectedIndex]
    }

    @objc private func scrub(_ gesture: UIGestureRecognizer) {
        guard gesture.state != .cancelled, gesture.state != .failed else {
            clearSelection()
            return
        }
        guard let series = presentations[selectedWindow]?.series else { return }
        let fraction = min(1, max(0, (gesture.location(in: self).x - plot.minX) / plot.width))
        let date = series.start.addingTimeInterval(Double(fraction) * series.end.timeIntervalSince(series.start))
        select(series.nearestIndex(to: date))
        clearGeneration += 1
        if gesture.state == .ended {
            let token = clearGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self, clearGeneration == token else { return }
                clearSelection()
            }
        }
    }

    private func select(_ index: Int?) {
        guard selectedIndex != index else { return }
        selectedIndex = index
        onScrub?(currentSample)
        if currentSample != nil { feedback.selectionChanged() }
        updateCursor()
        updateAccessibility()
    }

    private func clearSelection() {
        clearGeneration += 1
        select(nil)
    }

    private func updateCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let sample = currentSample, let watts = sample.powerWatts,
              let series = presentations[selectedWindow]?.series
        else {
            cursorLayer.path = nil
            selectionLayer.path = nil
            return
        }
        let selected = point(for: sample.timestamp, watts: watts, series: series)
        let cursor = CGMutablePath()
        cursor.move(to: CGPoint(x: selected.x, y: 3))
        cursor.addLine(to: CGPoint(x: selected.x, y: plot.height + 3))
        cursorLayer.path = cursor
        selectionLayer.path = CGPath(
            ellipseIn: CGRect(x: selected.x - 5, y: selected.y - 5, width: 10, height: 10), transform: nil
        )
    }

    private func updateAccessibility() {
        if let sample = currentSample {
            accessibilityValue = "\(ReadingFormat.measurement(sample.powerWatts, unit: "watts")) at \(ReadingFormat.time(sample.timestamp))"
        } else {
            let series = presentations[selectedWindow]?.series
            accessibilityValue = series?.samples.last?.powerWatts.map {
                "Latest \(ReadingFormat.number($0)) watts. \(series?.samples.count ?? 0) samples."
            } ?? "No measured power readings"
        }
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.fillColor = Palette.mint.resolvedColor(with: traitCollection).withAlphaComponent(0.1).cgColor
        lineLayer.strokeColor = Palette.accent.resolvedColor(with: traitCollection).cgColor
        endpointsLayer.fillColor = lineLayer.strokeColor
        cursorLayer.strokeColor = Palette.secondary.resolvedColor(with: traitCollection).withAlphaComponent(0.5).cgColor
        selectionLayer.fillColor = lineLayer.strokeColor
        selectionLayer.strokeColor = Palette.surface.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    override func accessibilityIncrement() {
        guard let count = presentations[selectedWindow]?.series.samples.count, count > 0 else { return }
        select(min(count - 1, (selectedIndex ?? -1) + 1))
    }

    override func accessibilityDecrement() {
        guard let count = presentations[selectedWindow]?.series.samples.count, count > 0 else { return }
        select(max(0, (selectedIndex ?? count) - 1))
    }
}
