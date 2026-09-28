import UIKit

/// A short message at the top of the screen that fades out by itself.
final class ToastView: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        textAlignment = .center
        font = .preferredFont(forTextStyle: .footnote)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.75)
        layer.cornerRadius = 10
        layer.masksToBounds = true
        alpha = 0
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pin to the top centre of `view`.
    func install(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])
    }

    func show(_ message: String) {
        text = "  \(message)  "
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 4, options: [.beginFromCurrentState]) { self.alpha = 0 }
        }
    }
}
