import Foundation
import Observation

/// Work for the main thread's next run loop turn, in every common mode. Unlike work queued on
/// the main actor or the main dispatch queue, it also runs inside a modal alert or a menu that
/// opened while main-actor work was under way, as the Keep/Revert countdown does when a menu
/// choice starts a trial.
enum MainRunLoop {
    static func perform(_ body: @escaping @MainActor @Sendable () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { body() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

/// Runs `body` now, and again whenever an observable value it read changes, until cancelled
/// or released: how AppKit objects (the status item, the window's title) follow the app
/// model the way SwiftUI views do.
///
/// A change is taken up at the main run loop's next turn, after the change is made and also
/// while a modal alert is up, so the menu bar icon can count down with the Keep/Revert
/// question.
@MainActor
final class ObservationLoop {
    private let body: @MainActor () -> Void
    private var isCancelled = false

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
        run()
    }

    func cancel() {
        isCancelled = true
    }

    private func run() {
        guard !isCancelled else { return }
        withObservationTracking {
            body()
        } onChange: { [weak self] in
            MainRunLoop.perform { [weak self] in self?.run() }
        }
    }
}

/// Calls `handler` on the main thread each time `name` is posted to `center` (by `object`,
/// when given), until released.
final class NotificationToken {
    private let center: NotificationCenter
    private let observer: any NSObjectProtocol

    init(
        center: NotificationCenter,
        name: Notification.Name,
        object: AnyObject? = nil,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        observer = center.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        center.removeObserver(observer)
    }
}
