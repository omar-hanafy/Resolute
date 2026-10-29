import Foundation
import MachO
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Settings › About (Figma 42:789): the icon, the name, the version and what it runs on, what
/// Resolute is, its links, and the credits. About Resolute in the main menu opens it.
struct AboutSettings: View {
    let info: AboutInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Settings.spacing) {
            VStack(spacing: Metrics.Settings.About.spacing) {
                AppIconView()
                    .frame(width: Metrics.Settings.About.iconSize, height: Metrics.Settings.About.iconSize)
                Text("Resolute")
                    .textStyle(.title1)
                    .foregroundStyle(Palette.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(info.versionLine)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .multilineTextAlignment(.center)
                Text("Pick any resolution and refresh rate for your Mac’s displays, including the ones macOS hides. A ground-up successor to RDM.")
                    .textStyle(.body)
                    .foregroundStyle(Palette.labelPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.Settings.About.descriptionWidth)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Metrics.Settings.About.linkSpacing) {
                    Button("GitHub") { ResoluteLinks.repository.open() }
                    Button("Changelog") { ResoluteLinks.changelog.open() }
                    Button("Report a Problem…") { ResoluteLinks.newIssue.open() }
                        .accessibilityHint("Opens a new issue on GitHub. Copy Report in Command Line & Agents adds the details.")
                }
                .padding(.top, Metrics.Settings.About.linksTopPadding)
            }
            .padding(Metrics.Settings.About.insets)
            .frame(maxWidth: .infinity)
            GroupedSection(insets: Metrics.Settings.About.creditsInsets, spacing: Metrics.Settings.About.creditsSpacing) {
                Text("Credits")
                    .textStyle(.bodyEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("The idea and the override-file format come from RDM by Avi Alkalay and its forks, including usr-sse2’s resolution editor. Display mirroring follows fcanas/mirror-displays.")
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("MIT License · © 2026 Omar Khaled")
                    .textStyle(.subheadline)
                    .foregroundStyle(Palette.labelTertiary)
            }
        }
    }
}

/// What About says Resolute is and runs on: "Version 0.4.0 · macOS 27 Golden Gate · Apple
/// silicon and Intel".
struct AboutInfo: Equatable, Sendable {
    var version: String
    /// "macOS 27 Golden Gate": the macOS this Mac runs.
    var system: String
    /// "Apple silicon and Intel" for a universal app, "Apple silicon" for an arm64-only one.
    var architectures: String

    var versionLine: String {
        "Version \(version) · \(system) · \(architectures)"
    }

    /// This copy of Resolute on this Mac.
    static var current: AboutInfo {
        AboutInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ResoluteVersion.string,
            system: systemName(ProcessInfo.processInfo.operatingSystemVersion),
            architectures: architectureNames(Bundle.main.executableArchitectures?.map(\.intValue) ?? [])
        )
    }

    /// "macOS 27 Golden Gate", "macOS 15 Sequoia": the major version and its name, or the
    /// version alone for a release this copy doesn't know.
    static func systemName(_ version: OperatingSystemVersion) -> String {
        let names = [14: "Sonoma", 15: "Sequoia", 26: "Tahoe", 27: "Golden Gate"]
        guard let name = names[version.majorVersion] else { return "macOS \(version.majorVersion).\(version.minorVersion)" }
        return "macOS \(version.majorVersion) \(name)"
    }

    /// The Mac families the app's executable runs on natively; the current Mac's when the
    /// executable doesn't say.
    static func architectureNames(_ architectures: [Int]) -> String {
        let arm = architectures.contains(Int(CPU_TYPE_ARM64))
        let intel = architectures.contains(Int(CPU_TYPE_X86_64))
        switch (arm, intel) {
        case (true, true): return "Apple silicon and Intel"
        case (false, true): return "Intel"
        case (true, false): return "Apple silicon"
        case (false, false):
            #if arch(arm64)
            return "Apple silicon"
            #else
            return "Intel"
            #endif
        }
    }
}
