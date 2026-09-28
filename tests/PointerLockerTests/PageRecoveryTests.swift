import WebKit
import XCTest
@testable import PointerLocker

final class CrashLoopGuardTests: XCTestCase {
    func testReloadsAfterOccasionalCrashes() {
        var guardian = CrashLoopGuard(maxCrashes: 3, window: 60)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 0)), .reload)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 100)), .reload)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 200)), .reload)
    }

    func testGivesUpWhenThePageKeepsCrashing() {
        var guardian = CrashLoopGuard(maxCrashes: 3, window: 60)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 0)), .reload)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 10)), .reload)
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 20)), .giveUp)
    }

    func testAManualReloadStartsOver() {
        var guardian = CrashLoopGuard(maxCrashes: 2, window: 60)
        _ = guardian.recordCrash(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 1)), .giveUp)
        guardian.reset()
        XCTAssertEqual(guardian.recordCrash(at: Date(timeIntervalSince1970: 2)), .reload)
    }
}

final class LoadFailureTests: XCTestCase {
    private func urlError(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }

    func testCancelledAndRedirectedLoadsAreNotFailures() {
        XCTAssertNil(LoadFailure(urlError(NSURLErrorCancelled)))
        // WebKitErrorFrameLoadInterruptedByPolicyChange: the page navigated on
        XCTAssertNil(LoadFailure(NSError(domain: WKError.errorDomain, code: 102)))
    }

    func testNoConnectionCountsAsOffline() {
        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                     NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                     NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff] {
            XCTAssertEqual(LoadFailure(urlError(code))?.isOffline, true, "code \(code)")
        }
    }

    func testOtherErrorsAreShownWithTheirMessage() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse,
                            userInfo: [NSLocalizedDescriptionKey: "Bad server response"])
        let failure = LoadFailure(error)
        XCTAssertEqual(failure?.isOffline, false)
        XCTAssertEqual(failure?.message, "Bad server response")
    }

    func testRemembersTheURLThatFailed() {
        let url = URL(string: "https://play.geforcenow.com/mall/")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSURLErrorFailingURLErrorKey: url])
        XCTAssertEqual(LoadFailure(error)?.url, url)
    }
}
