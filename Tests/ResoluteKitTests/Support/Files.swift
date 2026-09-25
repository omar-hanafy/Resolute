import Foundation
@testable import ResoluteKit

/// A fresh temporary directory. Its name contains a space and a single quote, so every
/// test that writes files also checks path quoting.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "Resolute Tests 'quoted' \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func hexData(_ hex: String) -> Data {
    Data(TestData.bytes(hex: hex.replacingOccurrences(of: " ", with: "")))
}

/// The override RDM wrote on the development Mac for a 5120×2160 monitor, byte for byte.
let rdmOverrideXML = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DisplayProductName</key>
	<string></string>
	<key>scale-resolutions</key>
	<array>
		<data>
		AAAUAAAACHA=
		</data>
		<data>
		AAAUAAAACHAAAAALAKAAAA==
		</data>
	</array>
	<key>target-default-ppmm</key>
	<real>10.01</real>
</dict>
</plist>
"""

/// Collects the scripts an installer asks to run, without running them.
actor ScriptRecorder {
    private(set) var scripts: [String] = []

    func record(_ script: String) {
        scripts.append(script)
    }
}

struct RecordingRunner: CommandRunning {
    let recorder: ScriptRecorder

    func run(_ script: String) async throws {
        await recorder.record(script)
    }
}

/// Runs scripts with /bin/sh under `umask 077`, as a strict `sudo` setup would.
struct StrictUmaskRunner: CommandRunning {
    func run(_ script: String) async throws {
        try await ShellCommandRunner().run("umask 077; " + script)
    }
}

/// Runs scripts through `osascript` without administrator rights: the app's own path,
/// minus the password prompt.
struct UnprivilegedAppleScriptRunner: CommandRunning {
    func run(_ script: String) async throws {
        let source = AppleScript.doShellScript(script, withAdministratorPrivileges: false)
        try await Subprocess.run("/usr/bin/osascript", arguments: ["-e", source])
    }
}
