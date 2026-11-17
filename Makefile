# Batteri – menu bar app.
#
#   make test      run the unit tests
#   make app       build Batteri.app with the engine inside, signed for this Mac only
#   make run       build and open it
#   make install   copy it to /Applications
#   make screenshots  render docs/*.png from made-up devices
#   make release   build, sign with a Developer ID and zip (see release.mk)
#   make clean
#
# A release needs your own signing identity. Put it in release.mk, which is not checked in:
#   SIGN_ID = Developer ID Application: Your Name (TEAMID)

APP = Batteri
BUNDLE = build/$(APP).app
BINARY = .build/release/$(APP)
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
SIGN_ID ?= -
-include release.mk

# The hardened runtime only lets the bundled Python load its own libraries when everything
# is signed by the same team, so it is used for real identities and not for ad-hoc builds.
ifeq ($(SIGN_ID),-)
SIGN_FLAGS = --force --timestamp=none
else
SIGN_FLAGS = --force --options runtime --timestamp
endif

.PHONY: test app run install release clean sign screenshots

test:
	swift test

$(BINARY): Package.swift $(shell find Sources -name '*.swift')
	swift build -c release --product $(APP)

app: $(BINARY)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	scripts/bundle-engine.sh $(BUNDLE)/Contents/Resources/engine
	$(MAKE) sign
	@echo "Built $(BUNDLE)"

# Every Mach-O file inside the bundled Python has to be signed before the app itself.
sign:
	find $(BUNDLE)/Contents/Resources/engine -type f \( -name '*.so' -o -name '*.dylib' -o -perm +111 \) -print0 \
	  | xargs -0 file | grep 'Mach-O' | cut -d: -f1 \
	  | while read f; do codesign $(SIGN_FLAGS) --sign "$(SIGN_ID)" "$$f"; done
	codesign $(SIGN_FLAGS) --entitlements Resources/Batteri.entitlements \
	  --sign "$(SIGN_ID)" $(BUNDLE)
	codesign --verify --deep --strict $(BUNDLE)

run: app
	open $(BUNDLE)

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/$(APP).app

screenshots: app
	rm -rf build/snapshots
	$(BUNDLE)/Contents/MacOS/$(APP) --snapshots build/snapshots
	cp build/snapshots/panel.png build/snapshots/panel-dark.png build/snapshots/sign-in.png build/snapshots/settings.png docs/

release:
	@if [ "$(SIGN_ID)" = "-" ]; then echo "Set SIGN_ID in release.mk first."; exit 1; fi
	$(MAKE) app
	cd build && ditto -c -k --keepParent $(APP).app $(APP)-$(VERSION).zip
	@echo "Signed build: build/$(APP)-$(VERSION).zip – notarize it before sharing:"
	@echo "  xcrun notarytool submit build/$(APP)-$(VERSION).zip --keychain-profile <profile> --wait"
	@echo "  xcrun stapler staple $(BUNDLE)"

clean:
	rm -rf build .build
