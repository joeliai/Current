import UIKit

func makeLabel(
    _ text: String? = nil,
    size: CGFloat = 15,
    weight: UIFont.Weight = .regular,
    color: UIColor = Palette.ink,
    style: UIFont.TextStyle = .body
) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = Palette.font(size, weight: weight, style: style)
    label.textColor = color
    label.numberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    label.adjustsFontForContentSizeCategory = true
    return label
}

func makeStack(
    _ views: [UIView],
    axis: NSLayoutConstraint.Axis = .vertical,
    spacing: CGFloat = 12,
    alignment: UIStackView.Alignment = .fill
) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = axis
    stack.spacing = spacing
    stack.alignment = alignment
    return stack
}

func makeSeparator() -> UIView {
    let view = UIView()
    view.backgroundColor = Palette.separator
    view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    return view
}

func makeSectionHeading(_ title: String, accessory: UIView? = nil) -> UIStackView {
    let label = makeLabel(title, size: 19, weight: .semibold, style: .headline)
    label.accessibilityTraits.insert(.header)
    let stack = makeStack([label], axis: .horizontal, spacing: 12, alignment: .center)
    if let accessory {
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(accessory)
    }
    return stack
}

final class GlassBadge: UIVisualEffectView {
    private let label = makeLabel(size: 11, weight: .semibold, style: .caption1)
    private let imageView = UIImageView()
    private let stack: UIStackView

    init(text: String, symbol: String? = nil) {
        stack = makeStack([], axis: .horizontal, spacing: 5, alignment: .center)
        let glass = UIGlassEffect(style: .regular)
        super.init(effect: UIAccessibility.isReduceTransparencyEnabled ? nil : glass)
        cornerConfiguration = .capsule()
        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = Palette.surface
        }
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        imageView.tintColor = Palette.accent
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -11),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
        set(text: text, symbol: symbol)
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(text: String, symbol: String? = nil, color: UIColor = Palette.accent) {
        label.text = text
        label.textColor = color
        imageView.image = symbol.flatMap { UIImage(systemName: $0) }
        imageView.isHidden = symbol == nil
        imageView.tintColor = color
        accessibilityLabel = text
    }
}

final class MetricTile: UIView {
    let valueLabel = makeLabel(size: 25, weight: .semibold, style: .title2)
    private let title: String
    private let unit: String

    init(title: String, symbol: String, color: UIColor, subtitle: String, unit: String = "W") {
        self.title = title
        self.unit = unit
        super.init(frame: .zero)
        backgroundColor = Palette.surface
        layer.cornerRadius = 8
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        image.tintColor = color
        image.setContentHuggingPriority(.required, for: .horizontal)
        let titleLabel = makeLabel(title, size: 12, weight: .medium, color: Palette.secondary, style: .caption1)
        let top = makeStack([image, titleLabel], axis: .horizontal, spacing: 6, alignment: .center)
        valueLabel.font = Palette.font(25, weight: .semibold, style: .title2, monospaced: true)
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        let subtitleLabel = makeLabel(subtitle, size: 10, color: Palette.secondary, style: .caption2)
        let content = makeStack([top, valueLabel, subtitleLabel], spacing: 7)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
        isAccessibilityElement = true
        set(nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ value: Double?, digits: Int = 1) {
        let number = ReadingFormat.number(value, digits: digits)
        let text = NSMutableAttributedString(
            string: number,
            attributes: [
                .font: Palette.font(25, weight: .semibold, style: .title2, monospaced: true),
                .foregroundColor: Palette.ink,
            ]
        )
        if value != nil {
            text.append(NSAttributedString(
                string: " \(unit)",
                attributes: [
                    .font: Palette.font(12, weight: .medium, style: .caption1),
                    .foregroundColor: Palette.secondary,
                ]
            ))
        }
        valueLabel.attributedText = text
        accessibilityLabel = "\(title), \(value == nil ? "unavailable" : "\(number) \(unit)")"
    }
}

final class AdaptiveMetricStrip: UIStackView {
    init(_ tiles: [UIView]) {
        super.init(frame: .zero)
        tiles.forEach(addArrangedSubview)
        spacing = 10
        updateAxis()
        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (view: AdaptiveMetricStrip, _: UITraitCollection) in
            view.updateAxis()
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAxis() {
        axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        distribution = .fillEqually
    }
}

final class DataRow: UIView {
    private let nameLabel: UILabel
    let valueLabel: UILabel
    private let content: UIStackView

    init(_ name: String, value: String = "Unavailable", symbol: String? = nil, color: UIColor = Palette.secondary) {
        nameLabel = makeLabel(name, size: 15)
        valueLabel = makeLabel(value, size: 15, weight: .medium, color: color)
        let nameViews: [UIView]
        if let symbol {
            let image = UIImageView(image: UIImage(systemName: symbol))
            image.tintColor = color
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15)
            image.widthAnchor.constraint(equalToConstant: 22).isActive = true
            nameViews = [image, nameLabel]
        } else {
            nameViews = [nameLabel]
        }
        let nameStack = makeStack(nameViews, axis: .horizontal, spacing: 10, alignment: .center)
        content = makeStack([nameStack, valueLabel], axis: .horizontal, spacing: 16, alignment: .firstBaseline)
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
        ])
        nameStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateAxis()
        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (view: DataRow, _: UITraitCollection) in
            view.updateAxis()
        }
        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityValue = value
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ text: String, color: UIColor? = nil) {
        valueLabel.text = text
        if let color { valueLabel.textColor = color }
        accessibilityValue = text
    }

    private func updateAxis() {
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        content.axis = accessible ? .vertical : .horizontal
        content.alignment = accessible ? .leading : .firstBaseline
        content.spacing = accessible ? 6 : 16
        valueLabel.textAlignment = accessible ? .left : .right
    }
}

func makeRows(_ rows: [DataRow]) -> UIStackView {
    var items: [UIView] = []
    for (index, row) in rows.enumerated() {
        if index > 0 { items.append(makeSeparator()) }
        items.append(row)
    }
    return makeStack(items, spacing: 0)
}

@MainActor
class MonitorViewController: UIViewController {
    let monitor = BatteryMonitor.shared
    private var observer: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        navigationItem.backButtonDisplayMode = .minimal
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"), style: .plain,
            target: self, action: #selector(showSettings)
        )
        settings.accessibilityLabel = "Settings"
        settings.accessibilityIdentifier = "settingsButton"
        navigationItem.rightBarButtonItem = settings
        observer = NotificationCenter.default.addObserver(
            forName: BatteryMonitor.didUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isViewLoaded, self.view.window != nil else { return }
                self.render()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
    }

    func render() {}

    @objc func showSettings() {
        let controller = UINavigationController(rootViewController: SettingsViewController())
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        present(controller, animated: true)
    }

    func share(session: ChargingSession? = nil, from item: UIBarButtonItem? = nil) {
        do {
            let url = try monitor.export(session: session)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            controller.popoverPresentationController?.barButtonItem = item ?? navigationItem.rightBarButtonItem
            if controller.popoverPresentationController?.barButtonItem == nil {
                controller.popoverPresentationController?.sourceView = view
                controller.popoverPresentationController?.sourceRect = CGRect(
                    x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1
                )
            }
            present(controller, animated: true)
        } catch {
            let alert = UIAlertController(
                title: "Export unavailable",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

class ScrollingMonitorViewController: MonitorViewController {
    let scrollView = UIScrollView()
    let content = UIStackView()
    private var hasAnimated = false

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.accessibilityIdentifier = "contentScroll"
        content.axis = .vertical
        content.spacing = 24
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let preferredWidth = content.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -40
        )
        preferredWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            content.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 660),
            content.widthAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            preferredWidth,
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAnimated, !UIAccessibility.isReduceMotionEnabled else { return }
        hasAnimated = true
        for (index, section) in content.arrangedSubviews.prefix(5).enumerated() {
            section.alpha = 0
            section.transform = CGAffineTransform(translationX: 0, y: 10)
            UIView.animate(
                withDuration: 0.6, delay: Double(index) * 0.055,
                usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                section.alpha = 1
                section.transform = .identity
            }
        }
    }
}
