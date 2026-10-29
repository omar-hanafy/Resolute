import Foundation

/// What Settings › Command Line & Agents › Teach your agent gives an agent: the commands,
/// the JSON keys and the hidden-mode rule (Figma 42:295). Copy Agent Instructions puts it on
/// the clipboard; Install Claude Code Skill… writes it as a Claude Code skill.
enum AgentInstructions {
    /// The three commands the page shows, as Figma writes them.
    static let exampleCommands = [
        "resolute displays --json",
        "resolute set 1496x967 -d main",
        "resolute preset apply Coding",
    ]

    /// The instructions, in Markdown, for pasting into an agent's rules or a prompt.
    static let text = """
        # Changing display modes with Resolute

        This Mac has Resolute. Use its `resolute` command to read and change display modes.

        ## Commands

        - `resolute displays --json`: the displays, each with its `index`, `id`, `name` and `currentMode`.
        - `resolute modes -d <display> --json`: a display's modes, grouped by size.
        - `resolute set <width>x<height> -d <display>`: switch to a size in points, keeping the refresh rate. `--refresh <hz>` changes the refresh rate, `--default` goes back to the display's default mode, `--dry-run` shows what would change.
        - `resolute preset list --json` and `resolute preset apply <name>`: the person's saved setups.
        - `resolute mirror on`, `resolute mirror off`.
        - `resolute history --json`: the last 7 days of changes, with who asked for each.

        `-d` takes `main`, an index from `resolute displays`, `id:<number>`, or part of a display's name.

        ## JSON

        All of these but `mirror` take `--json`. Every key is always present, with `null` when there is no value; later versions may add keys. A command that fails prints no JSON, so check the exit status first. `resolute set --json` reports `result`: `applied`, `kept` or `reverted`.

        ## Hidden modes

        Prefer the modes `resolute modes` lists. A hidden mode needs `--allow-hidden`, and only a person at the display can keep one: the display shows Keep or Revert, and if nobody answers it switches back. Ask for a hidden mode only when the person asked for it and is at the Mac, and never try to answer the dialog yourself.

        Every change is kept in Resolute's History with your name, and the person can undo it.
        """

    /// The Claude Code skill: the instructions under a name and a description that tell
    /// Claude Code when to load them.
    static var skill: String {
        """
        ---
        name: resolute
        description: Read and change this Mac's display resolutions, refresh rates, mirroring and presets with the resolute command. Use when the person asks to change a display's resolution, refresh rate or mirroring, or to apply a display preset.
        ---

        \(text)

        """
    }
}

/// Writes the Claude Code skill: `~/.claude/skills/resolute/SKILL.md`, where Claude Code
/// finds the skills of every project.
struct ClaudeCodeSkill {
    /// Claude Code's skills folder; tests give a folder of their own.
    var skillsFolder: URL

    static let live = ClaudeCodeSkill(
        skillsFolder: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/skills", directoryHint: .isDirectory)
    )

    var file: URL {
        skillsFolder.appending(path: "resolute/SKILL.md", directoryHint: .notDirectory)
    }

    /// "~/.claude/skills/resolute/SKILL.md", as the confirmation names it.
    var displayPath: String {
        (file.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    /// Whether a Resolute skill is there already, so the confirmation says it replaces it.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    func install() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(AgentInstructions.skill.utf8).write(to: file, options: .atomic)
    }
}
