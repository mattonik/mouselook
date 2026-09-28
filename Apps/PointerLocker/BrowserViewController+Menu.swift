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

        let sensitivity = UIMenu(title: "Mouse sensitivity", image: UIImage(systemName: "cursorarrow.motionlines"),
                                 children: Settings.sensitivityPresets.map { value in
            UIAction(title: String(format: "%g×", value), state: Settings.sensitivity == value ? .on : .off) { [weak self] _ in
                Settings.sensitivity = value
                self?.bridge.sensitivity = Float(value)
            }
        })

        let invert = UIAction(title: "Invert vertical", state: Settings.invertY ? .on : .off) { [weak self] _ in
            Settings.invertY.toggle()
            self?.bridge.invertY = Settings.invertY
        }

        let microphone = UIMenu(title: "Microphone", image: UIImage(systemName: "mic"),
                                children: MicrophoneAccess.allCases.map { access in
            UIAction(title: access.title, state: Settings.microphone == access ? .on : .off) { _ in
                Settings.microphone = access
            }
        })

        let keepAlive = UIMenu(title: "Keep game running in background", image: UIImage(systemName: "moon.zzz"),
                               children: Settings.backgroundKeepAlivePresets.map { preset in
            UIAction(title: preset.title, state: Settings.backgroundKeepAlive == preset.seconds ? .on : .off) { _ in
                Settings.backgroundKeepAlive = preset.seconds
            }
        })

        let profile = ServiceProfile.current
        let identity = UIAction(title: "Use \(profile.name) browser identity (reloads)",
                                attributes: profile.identity == .webKitDefault ? .disabled : [],
                                state: Settings.useServiceIdentity ? .on : .off) { [weak self] _ in
            Settings.useServiceIdentity.toggle()
            self?.applySettingsAndReload()
        }

        let hud = UIAction(title: "Debug overlay (reloads)", state: Settings.debugHUD ? .on : .off) { [weak self] _ in
            Settings.debugHUD.toggle()
            self?.applySettingsAndReload()
        }

        let help = UIAction(title: "Release mouse: hold Esc, ⌘. or three-finger tap", attributes: .disabled) { _ in }

        return [navigation, UIMenu(options: .displayInline, children: [sensitivity, invert, microphone, keepAlive, identity, hud]), help]
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
