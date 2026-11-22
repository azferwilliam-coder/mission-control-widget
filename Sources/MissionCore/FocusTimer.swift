import Foundation

/// A simple focus countdown: tap to start, tap to pause, reset from the right-click menu.
public struct FocusTimer: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }

    public var duration: TimeInterval
    public private(set) var state: State = .idle

    public init(duration: TimeInterval = 25 * 60) {
        self.duration = max(60, duration)
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: return duration
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let r): return r
        case .finished: return 0
        }
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Start, pause or resume, depending on where it is.
    public mutating func toggle(at now: Date) {
        switch state {
        case .idle, .finished:
            state = .running(endsAt: now.addingTimeInterval(duration))
        case .running(let end):
            state = .paused(remaining: max(0, end.timeIntervalSince(now)))
        case .paused(let r):
            state = .running(endsAt: now.addingTimeInterval(r))
        }
    }

    public mutating func reset() {
        state = .idle
    }

    /// Call every tick. Returns true exactly once, at the moment the countdown reaches zero.
    public mutating func tick(at now: Date) -> Bool {
        if case .running(let end) = state, now >= end {
            state = .finished(at: end)
            return true
        }
        return false
    }

    /// The dot stays coral for a minute after a focus session ends, then calms down.
    public func justFinished(at now: Date, window: TimeInterval = 60) -> Bool {
        if case .finished(let at) = state { return now.timeIntervalSince(at) < window }
        return false
    }

    /// Words beside the countdown.
    public func caption(at now: Date) -> String {
        switch state {
        case .idle: return "tap to start"
        case .running: return "left"
        case .paused: return "paused"
        case .finished: return "done"
        }
    }
}
