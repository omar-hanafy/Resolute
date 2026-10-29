import Foundation

/// Where Resolute keeps what the app and the `resolute` command share: presets, history and
/// the channel the command uses to ask the app. Tests pass their own root.
public struct SupportLocations: Hashable, Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Resolute` of the person using the Mac. Under `sudo`
    /// it is still the invoking person's folder, so `sudo resolute …` and the app share it.
    public static var standard: SupportLocations {
        SupportLocations(root: personHome.appending(path: "Library/Application Support/Resolute", directoryHint: .isDirectory))
    }

    public var presetsFile: URL { root.appending(path: "presets.json") }
    public var historyFile: URL { root.appending(path: "history.jsonl") }
    /// The socket the running app listens on for the command's requests.
    public var agentSocket: URL { root.appending(path: "agent.sock") }

    /// The home folder of the person who ran Resolute, looking past `sudo`.
    static var personHome: URL {
        if geteuid() == 0, let user = ProcessInfo.processInfo.environment["SUDO_USER"],
           let entry = getpwnam(user), let directory = entry.pointee.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
