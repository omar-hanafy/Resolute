# Contributing to Resolute

Resolute is an Apple silicon beta / release candidate. Read the [validation record](docs/production-readiness.md) before treating a build, passing test or successful mode switch as evidence for broader hardware support.

## Build and check

Use macOS 14 or later and Xcode 16 or later with Swift 6.0 or later. Local validation used Xcode 27 / Swift 6.4. The hosted Xcode 16.0, 26.6 and 27.0 matrix passed builds, tests and app packaging; see the validation record for the exact revision. Select the intended Xcode command-line tools before running:

```sh
make build
make test
make lint        # requires ShellCheck on PATH
make app         # builds an ad hoc signed arm64 app in dist/
```

`make test` runs the library, CLI and app tests. Live display mutations are opt-in. `make live-test` briefly switches the main display and restores it; use `RESOLUTE_LIVE_DISPLAY=<display-name> make live-test` to target another display. Run it locally while able to inspect and recover the screen. See [TESTING.md](TESTING.md) for optional scale/hidden-mode probes and manual checks. Keep manual checks unmarked when they have not actually been run.

## Propose a change

Keep each pull request focused on a reproducible problem or a clear behavior change. Include what changed, the relevant checks and their results, and the Mac/OS/display setup for hardware claims. Add regression coverage for changes to mode selection, confirmation/recovery, display identity or privileged file handling. A fake-backed unit test does not establish working hardware behavior.

- `Sources/ResoluteKit` owns display models, system integration and override storage.
- `Sources/ResoluteApp` owns the menu-bar app, confirmation flow and editor.
- `Sources/resolute` owns the CLI and structured output.
- `Scripts` owns local build, install, uninstall and packaging.

Preserve the CLI's documented [JSON contract](docs/json.md). Validate private-mode records against public modes and reject unknown layouts. Keep privileged override operations constrained to validated files and directories. For new macOS support, follow [the OS validation checklist](docs/new-macos-release.md).

## Report a bug

Open an [issue](https://github.com/omar-hanafy/Resolute/issues) with the steps to reproduce, expected and actual behavior, Resolute version or commit, macOS version, Mac model, and display/cable/adapter setup. Include `resolute doctor`; for mode problems, include `resolute modes -d <display> --all --raw` and say whether the display recovered.

Review diagnostics before posting. `resolute doctor` omits display serial numbers, but reports hardware details and override paths; other commands, fixtures and logs may contain identifiers or personal paths. Include only the relevant, redacted output. Do not post credentials or sensitive security exploit details in a public issue. Use the private reporting channel in [SECURITY.md](SECURITY.md) for vulnerabilities.

## License

Contributions are made under the project's [MIT license](LICENSE). Preserve third-party notices when changing bundled dependencies or distribution packaging.
