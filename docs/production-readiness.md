# Release-candidate validation — 2026-09-25

Resolute 0.3.0 is an Apple silicon beta / release candidate. This record describes local validation of recovery, privileged file handling and release packaging. It does not establish full hardware coverage or readiness for notarized distribution. Test results below describe the reviewed working tree on this date; they do not automatically cover later changes.

## Candidate and environment

- Review started from `b499b27`; the results below cover the subsequent recovery, filesystem and packaging changes in the 0.3.0 candidate.
- Version: **0.3.0**. A GitHub `v0.3.0` draft existed at review time; a draft is not a published or validated distribution.
- Runtime: **macOS 26.7 (25G229), Mac17,7, native arm64**. Compiler: **Xcode 27.0 (27A266a), Swift 6.4**, macOS 27 SDK. Building with that SDK is not evidence of running on macOS 27.
- Only the built-in display was connected: **1512 × 982 logical**, **3024 × 1964 render buffer**, **120 Hz reported**. The external GM34-CWQ's override was present but its monitor was disconnected.

## Defects fixed

| Area | Result |
| --- | --- |
| Hidden-mode confirmation | Refuse unattended hidden switches before mutation. Bound all input reads by one monotonic deadline; partial input and terminal signal flushing cannot leave a blocking read. Only `y` or `yes` keeps a CLI trial. |
| Recovery | Verify the current state before Keep and after private rollback; retain refused restores for retry. Bind recovery to display identity and mode properties, and resolve changed IDs conservatively. A trial needs an enumerated target and a known return mode. |
| App lifecycle | Late Keep clicks revert. Escape only closes its own confirmation. Quit and other actions cannot interrupt a trial or override write; abandoning pending recovery requires an explicit choice. |
| Editor | Keep saves, Add Resolution and discard dialogs associated with the intended display through disconnects, selection changes and external edits. |
| Privileged overrides | Reject symlinks, hardlinks, special files, redirected parents and writable/ACL-bearing privileged paths. Validate backup identity before restore/prune and read regular files without blocking on FIFOs. |
| Enumeration | Reject malformed private dimensions and conflicting mode IDs; reject ambiguous exact display names; release CoreDisplay framework handles. |
| Compiler and test compatibility | Account for older ScreenCaptureKit concurrency annotations, simplify typed resolution-byte decoding, and test lock deadlines/cancellation with a controlled clock while retaining real filesystem locks. |
| Install and distribution | Stage the new app before replacing the working installation; preserve unrelated CLI files/links. Build arm64 by default, retain `UNIVERSAL=1`, and include project/dependency license texts. Pin CI checkout and verify the downloaded linter checksum. |

## Verification

- **The automated suite passed with no failures.** The final pre-publication run reported 455 tests: 271 library/script, 83 CLI and 101 app tests. That total includes eight explicit skips: seven opt-in live tests and one case-sensitive-volume test on this case-insensitive volume. Skips are not hardware validation. They cover injected disconnects, changing identities/catalogs, rollback refusals, modal lifecycle, filesystem attacks, conflicts, backup round trips and install failures. Script integration tests run serially so their real-process deadlines do not compete with one another's startup.
- **5 live tests passed** on the built-in display, including public CoreGraphics switching, private SkyLight switching and the trial/revert path. These briefly changed refresh at the same resolution using application-lifetime scope, then restored the original mode. All 132 private/public mode records remained trusted.
- The actual Custom Resolutions window was rendered through ScreenCaptureKit and visually inspected; menu diagnostic output also completed. This proves rendering, not every interactive accessibility or hardware scenario.
- Apple silicon release build and bundle signature checks passed with an **ad hoc** identity. ZIP/DMG packaging, checksums and included release notes were checked locally. These artifacts are not Developer ID signed or notarized.
- ShellCheck, actionlint 1.7.12, zizmor with `--offline --strict-collection` and `git diff --check` passed. CI definitions now select Apple silicon on macOS 15/Xcode 16, macOS 26/Xcode 26 and the Xcode 27 hosted preview. Hosted CI is run manually during preparation while the repository is private; see the [workflow runs](https://github.com/omar-hanafy/Resolute/actions/workflows/ci.yml) for the exact tested revision. The private-repository manual-run policy is preserved.

The hosted runner labels/toolchains were checked against [GitHub's runner inventory](https://github.com/actions/runner-images#available-images), [macOS 15 arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md), and [Xcode 27 image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). The exact `xcode-27` label is registered in the linter configuration because its built-in label list predates that hosted preview.

## Remaining release gates and limits

1. **Distribution:** exercise Developer ID signing, notarization, stapling and Gatekeeper on the intended downloadable artifact. The keychain reported zero valid code-signing identities during this review; the successful local ad hoc build does not satisfy this gate.
2. **External hardware:** the GM34-CWQ follow-up below validates scaling, refresh switching and hidden-mode return. Mirroring, a controlled hotplug during recovery, sleep/wake, reboot and other display models still need [TESTING.md](../TESTING.md).
3. **Privilege integration:** production scripts and filesystem protections passed tests in isolated locations, including root-policy rejection without elevation. No real elevated installation/removal of a system override was performed in this review. Verify the complete administrator prompt, save, backup and restore path on a test Mac before distribution.
4. **OS coverage:** the configured hosted matrix and macOS 14 minimum still need actual runs. Intel is optional compilation compatibility and was not tested here.
5. **Identity:** monitors reporting identical or missing serial numbers cannot always be distinguished. Rebinding to a changed display ID requires a unique nonzero serial match. Identical devices with reused IDs remain a hardware identity limitation; ambiguous recovery must not guess.
6. **Recovery boundaries:** Force Quit, crashes, power/input changes and indefinitely absent hardware can defeat automatic restoration. Recovery is not a separate watchdog service. Session trials end at logout. User-writable staging directories do not have the same parent-replacement protection as the root-owned production directories.

Resolute controls exposed display modes, mirroring and native scale overrides. It does not currently implement DDC brightness/input/power, virtual displays, HDR/chroma configuration, or negotiated link-bandwidth measurement. A render-buffer size is not physical output timing, and an override cannot guarantee refresh, bandwidth or lossless scaling.

## Connected GM34-CWQ follow-up — 2026-09-25

The external monitor was connected over USB-C at **2580 × 1080 HiDPI, 5160 × 2160 backing, 144 Hz** with the existing override byte-for-byte unchanged. The display ID was 3; the built-in screen remained main at ID 1. This exposed a test-coverage gap: main-only live tests would still exercise the built-in screen. The suite now accepts an explicit display selector and opt-in scale/hidden-mode probes.

**Seven live tests passed targeting GM34-CWQ.** Public and private refresh switching returned to 144 Hz. Resolution-only trials selected 3010 × 1260, 2752 × 1152, 2408 × 1008, 2236 × 936, 2064 × 864 and 1720 × 720 at 144 Hz, each returning to the original 2580 × 1080 mode. A genuinely hidden 2048 × 858 mode, rendered at 4096 × 1716 at 144 Hz, also applied and reverted. The hidden test exercises the real private setter; it is not the listed-mode stand-in used on the built-in screen.

Independent IORegistry/CG reports before and after agree on **3440 × 1440 physical output at 144 Hz**, four HBR2 lanes at 5.4 Gbit/s per lane, and unchanged modes, mirroring state and desktop bounds on both displays. CoreGraphics readback was checked at every tested size; physical-link timing was measured at the restored baseline before and after the sequence, not at every intermediate size. No profile was written and no manual color controls were changed. Active chroma, range and HDR were not measured by that collector; no optical frame-delivery or lossless-image claim follows.

Visual inspection after the sequence found readable text with no lingering flicker or black screen. This is subjective recovery evidence, not a measured chroma/optical-frame result. The raw before/after reports and live-test log are not included in this repository; these results are a recorded validation summary, not independently reproducible artifacts.

This verifies the current connected state and programmatic mode/revert paths. It does not certify a timed UI countdown, hotplug during recovery, sleep/wake or reboot. Interactive menu testing was not completed during this follow-up. The external-display follow-up added opt-in tests and documentation; it did not revalidate a new release artifact.

## Public-repository preparation

- Gitleaks 8.30.1 found no secrets in Git history across all reachable refs, or in a snapshot of tracked and non-ignored new files. The downloaded scanner was verified against its official release asset SHA-256. A clean scan is not a guarantee that every sensitive value can be detected.
- Historical text blobs contained no personal home-directory paths in a targeted scan. The tracked screenshot was reviewed for personal data. Git author attribution remains in history and becomes visible with the repository; history was not rewritten.
- The source license and bundled dependency license are included. Current build/contribution documentation identifies Apple silicon as the primary target and separates source availability from binary-distribution validation.
- Keep the release a draft/prerelease until the intended distribution checks are complete. Publishing the source does not require notarization; distributing a notarized app does.
- When making the repository public, enable and verify GitHub private vulnerability reporting if available, then document that working channel. It was unavailable while this repository was private. Public issues are for ordinary bugs, not confidential reports.
