.PHONY: build test lint live-test app release install uninstall icon assets gallery clean

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
	swift Scripts/make-icon.swift Design/AppIcon/default.pdf Resources/AppIcon.icns

# Re-embeds the artwork in Design/ into ResoluteDesign after a Figma export.
assets:
	swift Scripts/embed-assets.swift

# Renders every design-system and app scene, in Light and Dark, for comparing with Figma.
gallery:
	Scripts/render-gallery.sh .build/gallery

clean:
	rm -rf .build dist
