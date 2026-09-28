import Foundation
import WebKit

/// Decides what to do when the web content process dies (a crash, or the
/// system reclaiming memory): reload, unless it keeps happening, in which
/// case reloading would only loop.
struct CrashLoopGuard {
    enum Decision: Equatable { case reload, giveUp }

    var maxCrashes = 3
    var window: TimeInterval = 60
    private var crashes: [Date] = []

    init(maxCrashes: Int = 3, window: TimeInterval = 60) {
        self.maxCrashes = maxCrashes
        self.window = window
    }

    mutating func recordCrash(at date: Date = Date()) -> Decision {
        crashes = crashes.filter { date.timeIntervalSince($0) < window } + [date]
        return crashes.count >= maxCrashes ? .giveUp : .reload
    }

    /// After the user reloads by hand.
    mutating func reset() {
        crashes.removeAll()
    }
}

/// A page load that failed in a way worth telling the user about.
struct LoadFailure {
    let isOffline: Bool
    let message: String
    let url: URL?

    private static let offlineCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
        NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
    ]

    /// nil for "failures" that aren't: a cancelled load (the user or the page
    /// navigated elsewhere) or a load WebKit handed off to a policy decision.
    init?(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return nil }
        if error.domain == WKError.errorDomain && error.code == 102 { return nil } // frame load interrupted by policy change
        isOffline = error.domain == NSURLErrorDomain && Self.offlineCodes.contains(error.code)
        message = error.localizedDescription
        url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }
}
