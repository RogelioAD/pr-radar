.PHONY: build test run print bundle install uninstall clean release

build:
	swift build

test:
	swift test

# Run unbundled for quick UI iteration (notifications fall back to osascript).
run: build
	./.build/debug/PRRadar

# One fetch, printed to stdout — check data parity against gh without the GUI.
print: build
	./.build/debug/PRRadar --print

bundle:
	./Scripts/bundle.sh

# Installs to /Applications and registers the login item.
install: bundle
	@echo "==> installing to /Applications"
	@rm -rf /Applications/PRRadar.app
	@cp -R PRRadar.app /Applications/PRRadar.app
	@echo "==> registering login item"
	@mkdir -p ~/Library/LaunchAgents
	@/usr/libexec/PlistBuddy -c "Clear dict" \
		-c "Add :Label string com.rogelioacosta.prradar" \
		-c "Add :ProgramArguments array" \
		-c "Add :ProgramArguments:0 string /Applications/PRRadar.app/Contents/MacOS/PRRadar" \
		-c "Add :RunAtLoad bool true" \
		-c "Add :KeepAlive bool false" \
		-c "Add :ProcessType string Interactive" \
		~/Library/LaunchAgents/com.rogelioacosta.prradar.plist >/dev/null
	@launchctl unload ~/Library/LaunchAgents/com.rogelioacosta.prradar.plist 2>/dev/null || true
	@launchctl load ~/Library/LaunchAgents/com.rogelioacosta.prradar.plist
	@echo "==> running. right-click the badge for the menu (including Quit)."

uninstall:
	-launchctl unload ~/Library/LaunchAgents/com.rogelioacosta.prradar.plist 2>/dev/null
	-rm -f ~/Library/LaunchAgents/com.rogelioacosta.prradar.plist
	-pkill -f /Applications/PRRadar.app/Contents/MacOS/PRRadar
	-rm -rf /Applications/PRRadar.app
	@echo "==> uninstalled"

clean:
	swift package clean
	rm -rf .build PRRadar.app

# Cut a release, which is what tells everyone running PR Radar that there is a
# newer build: the app checks the repo's latest release, and anyone watching
# the repo for releases gets an email from GitHub.
#
#   make release VERSION=1.1.0
release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=1.1.0" && exit 1)
	@test -z "$$(git status --porcelain)" || (echo "working tree is dirty" && exit 1)
	@echo "==> stamping $(VERSION)"
	@/usr/bin/sed -i '' 's/^VERSION=".*"/VERSION="$(VERSION)"/' Scripts/bundle.sh
	@$(MAKE) --no-print-directory test
	@git add Scripts/bundle.sh
	@git commit -q -m "Release $(VERSION)"
	@git tag -a "v$(VERSION)" -m "PR Radar $(VERSION)"
	@git push -q origin main --follow-tags
	@echo "==> publishing release v$(VERSION)"
	@gh release create "v$(VERSION)" --title "PR Radar $(VERSION)" --generate-notes
	@echo "==> done. Collaborators watching releases are notified by GitHub,"
	@echo "    and running copies show an update chip within six hours."
