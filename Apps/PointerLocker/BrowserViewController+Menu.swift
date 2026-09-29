import UIKit
import WebKit

/// The ⋯ button in the bottom-left corner and its menu.
extension BrowserViewController {
    func setUpMenuButton() {
        menuButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        menuButton.tintColor = .white
        menuButton.alpha = 0.6
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menuItems() ?? [])
        }])
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            menuButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func menuItems() -> [UIMenuElement] {
        let navigation = UIMenu(options: .displayInline, children: [
            UIAction(title: "Back", image: UIImage(systemName: "chevron.backward"),
                     attributes: webView.canGoBack ? [] : .disabled) { [weak self] _ in self?.webView.goBack() },
            UIAction(title: "Reload", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.webView.reload() },
            UIAction(title: "Home", image: UIImage(systemName: "house")) { [weak self] _ in
                self?.webView.load(URLRequest(url: Settings.homeURL))
            },
            UIAction(title: "Open URL…", image: UIImage(systemName: "link")) { [weak self] _ in self?.promptForURL() },
        ])
        let settings = UIAction(title: "Settings…", image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.showSettings()
        }
        return [servicesSection(), navigation, settings].compactMap { $0 }
    }

    /// Switch between services straight from the menu (no chooser, no Get
    /// ready); the current one is checked. A running game is confirmed first.
    private func servicesSection() -> UIMenu? {
        let entries = ServiceSwitch.menuEntries(current: Settings.serviceID)
        guard !entries.isEmpty else { return nil }
        let actions = entries.map { entry in
            UIAction(title: entry.name, subtitle: entry.subtitle, image: UIImage(systemName: entry.symbol),
                     state: entry.isCurrent ? .on : .off) { [weak self] _ in
                guard !entry.isCurrent, let profile = ServiceProfile.profile(id: entry.id) else { return }
                self?.root?.switchTo(profile)
            }
        }
        return UIMenu(options: .displayInline, children: actions)
    }

    private func promptForURL() {
        let alert = UIAlertController(title: "Open URL", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.webView.url?.absoluteString ?? Settings.homeURL.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let url = Self.normalizedURL(alert.textFields?.first?.text) else { return }
            self?.webView.load(URLRequest(url: url))
        })
        alert.addAction(UIAlertAction(title: "Open and set as Home", style: .default) { [weak self] _ in
            guard let url = Self.normalizedURL(alert.textFields?.first?.text) else { return }
            Settings.homeURL = url
            self?.webView.load(URLRequest(url: url))
        })
        present(alert, animated: true)
    }

    /// "example.com" → https://example.com; empty → nil.
    static func normalizedURL(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
    }
}
