import UIKit

/// Covers the web view while the service's first page loads. Until then
/// WKWebView is plain black, and on a slow connection that can last many
/// seconds: App Review took that black screen after "Open Figma" for a button
/// that did nothing (2.1(a), build 6). If it takes long, it says so and
/// offers a reload.
final class LoadingView: UIView {
    static let slowAfter: TimeInterval = 15

    private let spinner = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let button = UIButton(configuration: .filled())
    private var slowTimer: Timer?
    private var onReload: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isHidden = true

        spinner.color = UIColor(white: 1, alpha: 0.7)
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = UIColor(white: 1, alpha: 0.7)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        button.configuration?.title = "Reload"
        button.addAction(UIAction { [weak self] _ in self?.onReload?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [spinner, titleLabel, messageLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: spinner)
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

    /// "Opening Figma…" with a spinner; after `slowAfter` seconds, a hint and
    /// a Reload button.
    func show(serviceName: String, onReload: @escaping () -> Void) {
        self.onReload = onReload
        titleLabel.text = "Opening \(serviceName)…"
        messageLabel.isHidden = true
        button.isHidden = true
        spinner.startAnimating()
        isHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
        slowTimer?.invalidate()
        slowTimer = Timer.scheduledTimer(withTimeInterval: Self.slowAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSlow(serviceName: serviceName) }
        }
    }

    private func showSlow(serviceName: String) {
        guard !isHidden else { return }
        messageLabel.text = "\(serviceName) is taking a while to load. Check your internet connection, or reload."
        messageLabel.isHidden = false
        button.isHidden = false
    }

    func hide() {
        slowTimer?.invalidate()
        slowTimer = nil
        spinner.stopAnimating()
        isHidden = true
        onReload = nil
    }
}
