import UIKit

/// The window's root: onboarding until a service is chosen, then the browser
/// for it. iPadOS asks the root for pointer lock (and the home indicator,
/// status bar and edge gestures), so those are forwarded to the browser.
final class RootViewController: UIViewController {
    private(set) var browser: BrowserViewController?
    private var onboarding: OnboardingHostingController?

    /// Not while onboarding covers the browser: the game underneath can't
    /// take the pointer from it.
    override var childViewControllerForPointerLock: UIViewController? {
        presentedViewController is OnboardingHostingController ? nil : browser
    }
    override var childForHomeIndicatorAutoHidden: UIViewController? { browser }
    override var childForStatusBarHidden: UIViewController? { browser ?? onboarding }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { browser }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch LaunchRoute.resolve(serviceID: Settings.serviceID) {
        case .onboarding: showOnboarding(start: .welcome, cancellable: false)
        case .browser: showBrowser()
        }
    }

    // MARK: Children

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    private func remove(_ child: UIViewController?) {
        guard let child else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    private func showBrowser() {
        browser?.tearDown()
        remove(browser)
        remove(onboarding)
        onboarding = nil
        let browser = BrowserViewController()
        browser.root = self
        self.browser = browser
        embed(browser)
        refreshSystemPreferences()
    }

    private func refreshSystemPreferences() {
        setNeedsUpdateOfPrefersPointerLocked()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: Onboarding

    /// First launch embeds onboarding; from Settings it's presented over the
    /// browser and can be cancelled.
    func showOnboarding(start: OnboardingFlow.Start, cancellable: Bool) {
        let controller = OnboardingHostingController(
            start: start,
            onFinish: { [weak self] profile in self?.finishOnboarding(with: profile) },
            onCancel: cancellable ? { [weak self] in
                self?.dismiss(animated: true) { self?.setNeedsUpdateOfPrefersPointerLocked() }
            } : nil
        )
        if browser == nil {
            onboarding = controller
            embed(controller)
        } else {
            // Over, not full screen: the browser stays in the window, so a game
            // underneath keeps running instead of going hidden.
            controller.modalPresentationStyle = .overFullScreen
            browser?.forceUnlock()
            present(controller, animated: true)
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    private func finishOnboarding(with profile: ServiceProfile) {
        let rebuild = browser == nil || ServiceSwitch.needsRebuild(current: Settings.serviceID, chosen: profile.id)
        let finish = { [weak self] in
            OnboardingCompletion.finish(with: profile)
            let proceed: () -> Void = { [weak self] in
                if rebuild { self?.showBrowser() } else { self?.setNeedsUpdateOfPrefersPointerLocked() }
            }
            if self?.presentedViewController != nil { self?.dismiss(animated: true, completion: proceed) } else { proceed() }
        }
        guard rebuild, let browser else { return finish() }
        // A new browser ends a game running in the current one: ask first.
        browser.sessionPhase { [weak self] phase in
            guard let self, phase != .none else { return finish() }
            let alert = UIAlertController(title: "Switch to \(profile.name)?",
                                          message: "Switching ends your current game session.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Switch", style: .destructive) { _ in finish() })
            (self.presentedViewController ?? self).present(alert, animated: true)
        }
    }

    // MARK: From Settings

    /// Settings ▸ Switch service…: the chooser. Leaving a running game is
    /// confirmed only if a different service is picked.
    func switchService() {
        showOnboarding(start: .chooser, cancellable: true)
    }

    /// Settings ▸ Show setup guide: Get ready for the current service.
    func showSetupGuide() {
        showOnboarding(start: .getReady(ServiceProfile.current), cancellable: true)
    }
}
