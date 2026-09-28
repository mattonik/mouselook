import UIKit

/// Covers the page with a message and one action, for when it can't be
/// shown: no connection, a failed load, a page that keeps crashing.
final class StatusOverlayView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let button = UIButton(configuration: .filled())
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.9)
        isHidden = true

        imageView.tintColor = UIColor(white: 1, alpha: 0.6)
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = UIColor(white: 1, alpha: 0.7)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        button.addAction(UIAction { [weak self] _ in self?.action?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, messageLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(symbol: String, title: String, message: String, buttonTitle: String, action: @escaping () -> Void) {
        imageView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        messageLabel.text = message
        button.configuration?.title = buttonTitle
        self.action = action
        isHidden = false
    }

    func hide() {
        isHidden = true
        action = nil
    }
}
