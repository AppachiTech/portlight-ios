# Portlight developer tasks. App targets need a Mac with Xcode and XcodeGen.

.PHONY: help project open test test-core ipa ota icon fixtures clean

help:
	@echo "make project   Generate Portlight.xcodeproj (needs xcodegen)"
	@echo "make open      Generate and open in Xcode"
	@echo "make test      Run the core tests (Linux or macOS; SSH tests need sshd)"
	@echo "make ipa       Build an unsigned Portlight.ipa into build/"
	@echo "make ota URL=https://... IPA=build/Portlight-signed.ipa"
	@echo "               Write manifest.plist + install page for a private install"
	@echo "make icon      Redraw the app icon"
	@echo "make fixtures  Regenerate key test fixtures (needs ssh-keygen, openssl)"

project:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate

open: project
	open Portlight.xcodeproj

test test-core:
	cd PortlightCore && swift test

ipa: project
	scripts/build_unsigned_ipa.sh

ota:
	@test -n "$(URL)" || { echo "Set URL to where the files will be served, e.g. make ota URL=https://dl.example.com/portlight"; exit 1; }
	scripts/make_ota_manifest.py --base-url "$(URL)" --ipa "$(or $(IPA),build/Portlight.ipa)" --out build/ota

icon:
	scripts/gen_app_icon.py

fixtures:
	scripts/gen_key_fixtures.sh

clean:
	rm -rf build Portlight.xcodeproj PortlightCore/.build
