#if DEBUG
import Foundation

/// App Store screenshots (tools/app-store/capture.sh) launch the app with
/// `-screenshotScene <scene>`, next to `-serviceID <id>` for the service:
///
///   getReady  onboarding opens at Get ready, with a mouse and keyboard connected
///   settings  Settings opens over the browser, with the service checks passed
///
/// Debug builds only.
enum ScreenshotScene: String {
    case getReady, settings

    static var current: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "screenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }
}
#endif
