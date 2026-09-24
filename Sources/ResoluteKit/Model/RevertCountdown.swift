import Foundation

/// The "keep this display mode?" countdown shown after switching to a hidden mode.
public struct RevertCountdown: Equatable, Sendable {
    public let deadline: Date

    public init(start: Date = Date(), duration: TimeInterval = 15) {
        deadline = start.addingTimeInterval(duration)
    }

    public func secondsRemaining(at date: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(date).rounded(.up)))
    }

    public func isExpired(at date: Date) -> Bool {
        date >= deadline
    }

    public func message(at date: Date) -> String {
        let seconds = secondsRemaining(at: date)
        return "The previous mode comes back in \(seconds) second\(seconds == 1 ? "" : "s") unless you keep this one."
    }
}
