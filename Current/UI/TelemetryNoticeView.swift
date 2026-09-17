import UIKit

final class TelemetryNoticeView: UIView {
    var onDetails: (() -> Void)?
    private let titleLabel = makeLabel(size: 15, weight: .semibold, color: Palette.amber, style: .headline)
    private let messageLabel = makeLabel(size: 13, color: Palette.secondary, style: .footnote)

    init(identifier: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = identifier
        isHidden = true
        titleLabel.accessibilityTraits.insert(.header)
        messageLabel.accessibilityIdentifier = "\(identifier).message"
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "info.circle")
        configuration.baseForegroundColor = Palette.amber
        let details = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onDetails?()
        })
        details.accessibilityLabel = "Source diagnostics"
        details.accessibilityIdentifier = "\(identifier).details"
        details.widthAnchor.constraint(equalToConstant: 44).isActive = true
        details.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let heading = makeStack([titleLabel, details], axis: .horizontal, spacing: 8, alignment: .center)
        let content = makeStack([heading, messageLabel], spacing: 0)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let bottom = content.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            bottom,
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }
}
