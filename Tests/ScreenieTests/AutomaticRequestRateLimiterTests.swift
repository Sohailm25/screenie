import Foundation
import Testing
@testable import Screenie

@Suite("Automatic request rate limiter")
struct AutomaticRequestRateLimiterTests {
    @Test("The configured number of requests is accepted inside one window")
    func acceptsConfiguredRequestCount() {
        var limiter = AutomaticRequestRateLimiter(maximumRequests: 2, window: .seconds(60))
        let start = ContinuousClock().now

        let first = limiter.accept(at: start)
        let second = limiter.accept(at: start.advanced(by: .seconds(1)))
        let third = limiter.accept(at: start.advanced(by: .seconds(2)))

        #expect(first)
        #expect(second)
        #expect(!third)
    }

    @Test("An expired request frees capacity")
    func removesExpiredRequests() {
        var limiter = AutomaticRequestRateLimiter(maximumRequests: 1, window: .seconds(60))
        let start = ContinuousClock().now

        let first = limiter.accept(at: start)
        let afterWindow = limiter.accept(at: start.advanced(by: .seconds(60)))

        #expect(first)
        #expect(afterWindow)
    }
}
