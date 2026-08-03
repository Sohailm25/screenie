struct AutomaticRequestRateLimiter {
    let maximumRequests: Int
    let window: Duration
    private var acceptedInstants: [ContinuousClock.Instant] = []

    init(maximumRequests: Int, window: Duration) {
        self.maximumRequests = maximumRequests
        self.window = window
    }

    mutating func accept(at instant: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        let cutoff = instant.advanced(by: .zero - window)
        acceptedInstants.removeAll { $0 <= cutoff }
        guard acceptedInstants.count < maximumRequests else { return false }
        acceptedInstants.append(instant)
        return true
    }
}
