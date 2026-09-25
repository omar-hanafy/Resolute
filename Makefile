.PHONY: build test lint live-test app install uninstall icon clean

build:
	swift build

test:
	swift test

lint:
	shellcheck Scripts/*.sh

# Also switches the main display's refresh rate for a moment and back.
live-test:
	RESOLUTE_LIVE_TESTS=1 swift test --filter LiveDisplayTests

app:
	Scripts/build-app.sh

install: app
	Scripts/install.sh

uninstall:
	Scripts/uninstall.sh

icon:
	swift Scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build dist
