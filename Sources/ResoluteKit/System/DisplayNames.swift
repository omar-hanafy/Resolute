import AppKit
import CoreGraphics

/// Human-readable display names.
enum DisplayNames {
    /// Names from `NSScreen`, keyed by display ID (active displays only). AppKit's screen
    /// list is read on the main thread, also when the command line takes a snapshot.
    static func screenNames() -> [CGDirectDisplayID: String] {
        onMainThread {
            var names: [CGDirectDisplayID: String] = [:]
            for screen in NSScreen.screens {
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                if let number = screen.deviceDescription[key] as? NSNumber {
                    names[number.uint32Value] = screen.localizedName
                }
            }
            return names
        }
    }

    /// Runs `body` on the main thread. From another thread it waits for the main queue,
    /// which the app's run loop, the command line's async `main` and Swift Testing all keep
    /// serving; it would wait forever on a main thread that is waiting for the caller.
    static func onMainThread<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    /// The product name CoreDisplay reports; covers mirrored and inactive displays.
    static func coreDisplayName(for display: CGDirectDisplayID) -> String? {
        typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
        guard let framework = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let symbol = dlsym(framework, "CoreDisplay_DisplayCreateInfoDictionary")
        else { return nil }
        let copyInfo = unsafeBitCast(symbol, to: InfoFunction.self)
        guard let info = copyInfo(display)?.takeRetainedValue() as? [String: Any],
              let names = info["DisplayProductName"] as? [String: String],
              !names.isEmpty
        else { return nil }
        let preferred = Bundle.preferredLocalizations(
            from: Array(names.keys), forPreferences: Locale.preferredLanguages
        ).first
        return preferred.flatMap { names[$0] } ?? names["en_US"] ?? names.values.sorted().first
    }

    static func fallbackName(for display: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(display) != 0 ? "Built-in Display" : "Display \(display)"
    }

    /// Appends " (1)", " (2)", … to names that occur more than once, skipping any suffixed
    /// name already taken, since a display can really be named "Studio (1)".
    static func disambiguate(_ names: [String]) -> [String] {
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        var taken = Set(names)
        var lastNumber: [String: Int] = [:]
        return names.map { name in
            guard counts[name, default: 0] > 1 else { return name }
            var number = lastNumber[name, default: 0]
            var candidate: String
            repeat {
                number += 1
                candidate = "\(name) (\(number))"
            } while taken.contains(candidate)
            lastNumber[name] = number
            taken.insert(candidate)
            return candidate
        }
    }
}
