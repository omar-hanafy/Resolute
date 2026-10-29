import Foundation

/// Who ran the `resolute` command: an agent such as Claude Code, or a person, and the app
/// it ran in, such as Terminal. History says where a change came from with it ("From
/// Claude Code (Terminal)"), and the app's Keep/Revert dialog names who asked.
public struct Requester: Hashable, Sendable, Codable {
    /// The agent that ran the command; nil when a person typed it.
    public var agent: String?
    /// The terminal or app the command ran in; nil when unknown.
    public var app: String?

    public init(agent: String? = nil, app: String? = nil) {
        self.agent = agent
        self.app = app
    }

    /// Who is running this process, from its environment and the processes that started it.
    public static func current() -> Requester {
        identify(environment: ProcessInfo.processInfo.environment, ancestors: Ancestor.current())
    }

    /// Who ran a command that has `environment` and was started by `ancestors`, the nearest
    /// first. Agents mark the commands they run (Claude Code sets CLAUDECODE=1) and terminals
    /// name themselves in TERM_PROGRAM; `sudo` drops both, so the processes count too.
    public static func identify(environment: [String: String], ancestors: [Ancestor] = []) -> Requester {
        let agent = agentName(environment: environment, ancestors: ancestors)
        var app = appName(environment: environment, ancestors: ancestors)
        // An agent in its own app is named once: "Claude Code", not "Claude Code (Claude)".
        if let agent, let shown = app, agent == shown || agent.hasPrefix(shown + " ") {
            app = nil
        }
        return Requester(agent: agent, app: app)
    }

    /// Where History says the change came from.
    public var source: HistoryEntry.Source {
        agent.map { .agent(name: $0, app: app) } ?? .terminal(app: app)
    }

    /// "Claude Code (Terminal)", "Claude Code", "Terminal", or "the resolute command".
    public var name: String { source.name }

    /// A process that started this one.
    public struct Ancestor: Hashable, Sendable {
        /// The executable's file name, such as "claude" or "iTerm2".
        public var name: String
        /// The app it is the program of, or a helper app of; nil for other programs.
        public var bundleIdentifier: String?
        /// That app's name, such as "Terminal".
        public var bundleName: String?

        public init(name: String, bundleIdentifier: String? = nil, bundleName: String? = nil) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.bundleName = bundleName
        }

        /// The processes that started this one, nearest first, up to launchd. A process
        /// whose executable can't be read (another user's, without root) has its short name.
        public static func current() -> [Ancestor] {
            var ancestors: [Ancestor] = []
            var visited: Set<pid_t> = []
            var pid = getppid()
            while pid > 1, ancestors.count < 64, visited.insert(pid).inserted, let info = processInfo(pid) {
                let path = executablePath(pid)
                let bundle = path.flatMap(appBundle(containing:))
                ancestors.append(Ancestor(
                    name: path.map { URL(filePath: $0).lastPathComponent } ?? commandName(info),
                    bundleIdentifier: bundle?.bundleIdentifier,
                    bundleName: bundle.flatMap(name(of:))
                ))
                pid = info.kp_eproc.e_ppid
            }
            return ancestors
        }

        private static func name(of bundle: Bundle) -> String? {
            (bundle.infoDictionary?["CFBundleDisplayName"] ?? bundle.infoDictionary?["CFBundleName"]) as? String
        }

        private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&request, UInt32(request.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
            return info
        }

        private static func commandName(_ info: kinfo_proc) -> String {
            var command = info.kp_proc.p_comm
            return withUnsafeBytes(of: &command) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }

        private static func executablePath(_ pid: pid_t) -> String? {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        /// The app whose program `path` is, or one of its helper apps', named after the
        /// outermost app. Developer tools that only live inside an app (Xcode's `swift`) are
        /// not that app.
        static func appBundle(containing path: String) -> Bundle? {
            appPath(containing: path).flatMap(Bundle.init(path:))
        }

        static func appPath(containing path: String) -> String? {
            let components = URL(filePath: path).pathComponents
            guard components.indices.contains(where: { index in
                components[index].hasSuffix(".app") && components.dropFirst(index + 1).starts(with: ["Contents", "MacOS"])
            }), let outermost = components.firstIndex(where: { $0.hasSuffix(".app") })
            else { return nil }
            return NSString.path(withComponents: Array(components[...outermost]))
        }
    }

    // MARK: - Agents

    /// What agents set on the commands they run, each read from the agent's own code.
    static let agentMarkers: [(variables: [String], name: String)] = [
        (["CLAUDECODE"], "Claude Code"),
        (["CODEX_THREAD_ID", "CODEX_SANDBOX", "CODEX_TOOL_CALL_ID"], "Codex"),
        (["GEMINI_CLI"], "Gemini CLI"),
        (["QWEN_CODE"], "Qwen Code"),
        (["CURSOR_AGENT"], "Cursor"),
        (["ANTIGRAVITY_AGENT"], "Antigravity"),
    ]

    /// Agents' executables, for commands run under `sudo`, which drops their variables.
    static let agentProcesses: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "agy": "Antigravity",
    ]

    /// Names for the first part of AI_AGENT, which Claude Code sets to
    /// "claude-code_<version>_agent".
    static let agentSlugs: [String: String] = [
        "claude-code": "Claude Code", "codex": "Codex", "gemini-cli": "Gemini CLI", "qwen-code": "Qwen Code",
        "cursor": "Cursor", "cursor-agent": "Cursor", "opencode": "OpenCode", "antigravity": "Antigravity",
    ]

    static func agentName(environment: [String: String], ancestors: [Ancestor]) -> String? {
        func isSet(_ key: String) -> Bool {
            guard let value = environment[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return false }
            return value != "0" && value.lowercased() != "false"
        }
        let marked = agentMarkers.filter { $0.variables.contains(where: isSet) }.map(\.name)
            // OpenCode marks its own process, so a person typing in its terminal panel has
            // the mark too; that panel adds one of its own.
            + (isSet("OPENCODE") && !isSet("OPENCODE_TERMINAL") ? ["OpenCode"] : [])
        // Marks pass down, so an agent that another agent started has both: the nearer one ran the command.
        let nearest = ancestors.lazy.compactMap { agentProcesses[$0.name] }
        if marked.count > 1, let name = nearest.first(where: marked.contains) { return name }
        if let name = marked.first { return name }
        if let value = environment["AI_AGENT"], let name = agentName(slug: value) { return name }
        return nearest.first
    }

    /// "Claude Code" for "claude-code_2-1-312_agent"; an agent Resolute doesn't know is
    /// named after its slug ("my-agent" is "My Agent").
    static func agentName(slug value: String) -> String? {
        guard let slug = value.split(separator: "_").first?.trimmingCharacters(in: .whitespaces).lowercased(), !slug.isEmpty else {
            return nil
        }
        if let name = agentSlugs[slug] { return name }
        return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Apps

    /// TERM_PROGRAM, as terminals set it.
    static let terminalPrograms: [String: String] = [
        "Apple_Terminal": "Terminal", "iTerm.app": "iTerm", "ghostty": "Ghostty", "zed": "Zed", "vscode": "VS Code",
        "WarpTerminal": "Warp", "WezTerm": "WezTerm", "Hyper": "Hyper", "Tabby": "Tabby", "rio": "Rio",
    ]

    /// Apps by bundle identifier: the ones __CFBundleIdentifier names, and the ones whose
    /// short name differs from their bundle's ("iTerm", not "iTerm2").
    static let appNames: [String: String] = [
        "com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm", "com.mitchellh.ghostty": "Ghostty",
        "dev.zed.Zed": "Zed", "dev.warp.Warp-Stable": "Warp", "com.github.wez.wezterm": "WezTerm",
        "org.alacritty": "Alacritty", "net.kovidgoyal.kitty": "kitty", "co.zeit.hyper": "Hyper",
        "com.microsoft.VSCode": "VS Code", "com.microsoft.VSCodeInsiders": "VS Code Insiders", "com.vscodium": "VSCodium",
        "com.todesktop.230313mzl4w4u92": "Cursor", "com.exafunction.windsurf": "Windsurf",
        "com.google.antigravity": "Antigravity", "com.anthropic.claudefordesktop": "Claude",
        "ai.opencode.desktop": "OpenCode", "com.apple.dt.Xcode": "Xcode",
    ]

    /// Terminals by executable, for one whose app can't be read.
    static let terminalProcesses: [String: String] = [
        "Terminal": "Terminal", "iTerm2": "iTerm", "ghostty": "Ghostty", "wezterm-gui": "WezTerm",
        "alacritty": "Alacritty", "kitty": "kitty",
    ]

    static func appName(environment: [String: String], ancestors: [Ancestor]) -> String? {
        func value(_ key: String) -> String? {
            environment[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        // OpenCode's terminal panel, where a person types.
        if value("OPENCODE_TERMINAL") == "1" { return "OpenCode" }
        let program = value("TERM_PROGRAM")
        // VS Code's forks say "vscode" too; the app that started the shell tells them apart.
        if let program, program != "vscode", let name = terminalPrograms[program] { return name }
        if let bundle = value("__CFBundleIdentifier"), let name = appNames[bundle] { return name }
        if let program, let name = terminalPrograms[program] { return name }
        // iTerm's own variable also reaches commands run through ssh or tmux.
        if value("LC_TERMINAL") == "iTerm2" { return "iTerm" }
        if value("KITTY_WINDOW_ID") != nil { return "kitty" }
        if value("ALACRITTY_WINDOW_ID") != nil || value("ALACRITTY_SOCKET") != nil { return "Alacritty" }
        for ancestor in ancestors {
            if let identifier = ancestor.bundleIdentifier {
                return appNames[identifier] ?? ancestor.bundleName ?? ancestor.name
            }
            if let name = terminalProcesses[ancestor.name] { return name }
        }
        // A terminal Resolute doesn't know is named as it names itself; tmux or screen
        // say only that much.
        return program
    }
}
