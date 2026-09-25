.PHONY: build test lint live-test app release install uninstall icon clean

build:
	swift build

test:
	swift test

lint:
	shellcheck Scripts/*.sh

# Switches the selected display's refresh rate and back (main by default).
# Example: RESOLUTE_LIVE_DISPLAY=GM34-CWQ make live-test
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
