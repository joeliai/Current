import UIKit

final class ChargeGaugeView: UIView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let colorLayer = CAGradientLayer()
    private let innerTrack = CAShapeLayer()
    private let percentage = UILabel()
    private let caption = makeLabel(
        "BATTERY LEVEL",
        size: 10,
        weight: .medium,
        color: Palette.secondary,
        style: .caption2
    )
    private let bolt = UIImageView(image: UIImage(systemName: "bolt.fill"))
    private let status = GlassBadge(text: "Charging", symbol: "bolt.fill")
    private var level: Double?
    private var charging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(track)
        layer.addSublayer(innerTrack)
        layer.addSublayer(colorLayer)
        colorLayer.mask = progress
        progress.strokeEnd = 0
        colorLayer.startPoint = CGPoint(x: 0, y: 1)
        colorLayer.endPoint = CGPoint(x: 1, y: 0)
        for shape in [track, progress] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 3
            shape.lineCap = .round
        }
        innerTrack.fillColor = UIColor.clear.cgColor
        innerTrack.lineWidth = 1
        percentage.textAlignment = .center
        percentage.numberOfLines = 1
        percentage.adjustsFontSizeToFitWidth = true
        percentage.minimumScaleFactor = 0.7
        caption.textAlignment = .center
        caption.font = Palette.font(10, weight: .medium, style: .caption2, maximumSize: 13)
        caption.adjustsFontForContentSizeCategory = false
        bolt.tintColor = Palette.accent
        bolt.contentMode = .scaleAspectFit
        bolt.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        [percentage, caption, bolt, status].forEach(addSubview)
        isAccessibilityElement = true
        accessibilityLabel = "Battery level"
        accessibilityIdentifier = "batteryGauge"
        registerForTraitChanges(
            [UITraitUserInterfaceStyle.self]
        ) { (view: ChargeGaugeView, _: UITraitCollection) in
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 300, height: max(274, 242 + statusSize.height))
    }

    private var statusSize: CGSize {
        let naturalSize = status.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let width = min(bounds.width > 0 ? bounds.width : 300, naturalSize.width)
        return status.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: 128)
        let radius: CGFloat = min(119, bounds.width / 2 - 16)
        let ticks = UIBezierPath()
        for tick in 0 ..< 76 {
            let angle = CGFloat.pi * 2 / 3 + CGFloat(tick) / 75 * CGFloat.pi * 5 / 3
            let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let inner = CGPoint(x: center.x + cos(angle) * (radius - 13), y: center.y + sin(angle) * (radius - 13))
            ticks.move(to: inner)
            ticks.addLine(to: outer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.path = ticks.cgPath
        track.strokeColor = Palette.separator.resolvedColor(with: traitCollection).cgColor
        progress.path = ticks.cgPath
        progress.strokeColor = UIColor.black.cgColor
        colorLayer.frame = bounds
        colorLayer.colors = [
            Palette.lime.resolvedColor(with: traitCollection).cgColor,
            Palette.mint.resolvedColor(with: traitCollection).cgColor,
            Palette.accent.resolvedColor(with: traitCollection).cgColor,
        ]
        innerTrack.path = UIBezierPath(
            arcCenter: center, radius: radius - 24,
            startAngle: .pi * 2 / 3, endAngle: .pi * 7 / 3, clockwise: true
        ).cgPath
        innerTrack.strokeColor = Palette.separator.withAlphaComponent(0.65).resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
        bolt.frame = CGRect(x: center.x - 13, y: 63, width: 26, height: 28)
        percentage.frame = CGRect(x: center.x - 101, y: 89, width: 202, height: 89)
        caption.frame = CGRect(x: center.x - 85, y: 177, width: 170, height: 20)
        let fitting = statusSize
        status.frame = CGRect(
            x: center.x - min(fitting.width, bounds.width) / 2,
            y: 234, width: min(fitting.width, bounds.width), height: max(30, fitting.height)
        )
    }

    func update(_ snapshot: BatterySnapshot, animated: Bool) {
        let changed = level != snapshot.level
        level = snapshot.level
        let digits = snapshot.level.map { ReadingFormat.number($0 * 100, digits: 0) } ?? "--"
        let text = NSMutableAttributedString(
            string: digits,
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 77, weight: .light),
                .foregroundColor: Palette.ink,
            ]
        )
        if snapshot.level != nil {
            text.append(NSAttributedString(
                string: "%",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 29, weight: .light),
                    .foregroundColor: Palette.secondary,
                    .baselineOffset: 6,
                ]
            ))
        }
        percentage.attributedText = text
        let symbol = snapshot.state == .charging ? "bolt.fill" : snapshot.state == .full ? "checkmark" : "battery.100percent"
        status.set(
            text: snapshot.state.title, symbol: symbol,
            color: snapshot.state.isConnected ? Palette.accent : Palette.secondary
        )
        if changed {
            let target = CGFloat(min(1, max(0, snapshot.level ?? 0)))
            let from = progress.presentation()?.strokeEnd ?? progress.strokeEnd
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progress.strokeEnd = target
            CATransaction.commit()
            if animated, !UIAccessibility.isReduceMotionEnabled {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = from
                animation.toValue = target
                animation.duration = 1.1
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                progress.add(animation, forKey: "charge")
            }
        }
        let shouldPulse = snapshot.state == .charging && !UIAccessibility.isReduceMotionEnabled
        if shouldPulse != charging {
            charging = shouldPulse
            if charging {
                bolt.addSymbolEffect(.pulse, options: .repeating)
            } else {
                bolt.removeAllSymbolEffects()
            }
        }
        bolt.image = UIImage(systemName: symbol)
        accessibilityValue = "\(ReadingFormat.percent(snapshot.level)), \(snapshot.state.title)"
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
