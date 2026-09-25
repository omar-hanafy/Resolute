.PHONY: build test test-intel lint live-test app release install uninstall icon clean

build:
	swift build

test:
	swift test

# The same tests, built for Intel and run under Rosetta.
test-intel:
	Scripts/test-intel.sh

lint:
	shellcheck Scripts/*.sh

# Also switches the main display's refresh rate for a moment and back.
live-test:
	RESOLUTE_LIVE_TESTS=1 swift test --filter LiveDisplayTests

app:
	Scripts/build-app.sh

release:
	Scripts/release.sh

install: app
	Scripts/install.sh

uninstall:
	Scripts/uninstall.sh

icon:
	swift Scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build dist
