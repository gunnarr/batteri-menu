# Batteri – menu bar app.
#
#   make test      run the unit tests
#   make app       build Batteri.app with the engine inside, signed for this Mac only
#   make run       build and open it
#   make install   copy the built app to /Applications
#   make screenshots  render docs/*.png from made-up devices
#   make release   build, sign, notarize and zip (see release.mk)
#   make clean
#
# A release needs your own signing identity and notary key. Put them in release.mk, which
# is not checked in. The Sparkle signing key is read from the keychain (generate_keys).
#   SIGN_ID = Developer ID Application: Your Name (TEAMID)
#   NOTARY_KEY = /path/to/AuthKey_XXXXXXXXXX.p8
#   NOTARY_KEY_ID = XXXXXXXXXX
#   NOTARY_ISSUER = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

APP = Batteri
BUNDLE = build/$(APP).app
BINARY = .build/release/$(APP)
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
SIGN_ID ?= -
SPARKLE = .build/artifacts/sparkle/Sparkle
SPARKLE_FRAMEWORK = $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
REPO_URL = https://github.com/gunnarr/batteri-menu
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
	mkdir -p $(BUNDLE)/Contents/Frameworks
	cp -R $(SPARKLE_FRAMEWORK) $(BUNDLE)/Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(BUNDLE)/Contents/MacOS/$(APP) 2>/dev/null || true
	scripts/bundle-engine.sh $(BUNDLE)/Contents/Resources/engine
	$(MAKE) sign
	@echo "Built $(BUNDLE)"

# Every Mach-O file inside the bundled Python has to be signed before the app itself.
sign:
	find $(BUNDLE)/Contents/Resources/engine -type f \( -name '*.so' -o -name '*.dylib' -o -perm +111 \) -print0 \
	  | xargs -0 file | grep 'Mach-O' | cut -d: -f1 \
	  | while read f; do codesign $(SIGN_FLAGS) --sign "$(SIGN_ID)" "$$f"; done
	@# Sparkle's helpers are signed from the inside out, then the framework itself.
	for part in Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc \
	            Versions/B/Autoupdate Versions/B/Updater.app ""; do \
	  codesign $(SIGN_FLAGS) --sign "$(SIGN_ID)" "$(BUNDLE)/Contents/Frameworks/Sparkle.framework/$$part"; \
	done
	codesign $(SIGN_FLAGS) --entitlements Resources/Batteri.entitlements \
	  --sign "$(SIGN_ID)" $(BUNDLE)
	codesign --verify --deep --strict $(BUNDLE)

run: app
	open $(BUNDLE)

# Installs the app that is already built, so a notarized release build stays notarized.
install:
	@[ -d $(BUNDLE) ] || { echo "Build it first: make app (or make release)"; exit 1; }
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app

screenshots: app
	rm -rf build/snapshots
	$(BUNDLE)/Contents/MacOS/$(APP) --snapshots build/snapshots
	cp build/snapshots/panel.png build/snapshots/panel-dark.png build/snapshots/sign-in.png build/snapshots/settings.png docs/

# Signs with your Developer ID, has Apple notarize the app, staples the ticket and zips it.
# release.mk must set SIGN_ID, NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER.
release:
	@if [ "$(SIGN_ID)" = "-" ] || [ -z "$(NOTARY_KEY)" ]; then \
	  echo "Set SIGN_ID, NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER in release.mk first."; exit 1; fi
	$(MAKE) app
	rm -f build/$(APP).zip
	cd build && ditto -c -k --keepParent $(APP).app notarize.zip
	xcrun notarytool submit build/notarize.zip --key "$(NOTARY_KEY)" --key-id "$(NOTARY_KEY_ID)" \
	  --issuer "$(NOTARY_ISSUER)" --wait
	xcrun stapler staple $(BUNDLE)
	rm build/notarize.zip
	cd build && ditto -c -k --keepParent $(APP).app $(APP).zip
	spctl -a -vv $(BUNDLE)
	@# The update feed. generate_appcast signs the archive with the Sparkle key in the
	@# keychain and adds the new version to appcast.xml.
	rm -rf build/appcast && mkdir -p build/appcast
	cp build/$(APP).zip build/appcast/
	[ ! -f appcast.xml ] || cp appcast.xml build/appcast/
	scripts/release-notes.py $(VERSION) > build/appcast/$(APP).html
	$(SPARKLE)/bin/generate_appcast --download-url-prefix "$(REPO_URL)/releases/download/v$(VERSION)/" \
	  --link "$(REPO_URL)" --embed-release-notes build/appcast
	cp build/appcast/appcast.xml appcast.xml
	@echo "Release build: build/$(APP).zip (version $(VERSION))"
	@echo "Now publish, in this order, so nobody is offered a file that is not there yet:"
	@echo "  gh release create v$(VERSION) build/$(APP).zip --title '$(APP) $(VERSION)' --notes-file <notes>"
	@echo "  git commit appcast.xml && git push"

clean:
	rm -rf build .build
