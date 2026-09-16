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
	@# launchctl unload below only stops the copy it manages. One started any
	@# other way — double-clicked, an old login item — would survive and be
	@# joined by a second, giving two identical panels at one position.
	@#
	@# Matched by bundle path from any location, not just /Applications: `make
	@# bundle` leaves a PRRadar.app in the checkout, and a copy double-clicked
	@# from there would otherwise outlive the install and, being first, keep the
	@# freshly installed one from starting at all. `make run` is unaffected — it
	@# runs .build/debug/PRRadar, which is not inside a bundle.
	@pkill -f 'PRRadar\.app/Contents/MacOS/PRRadar' 2>/dev/null || true
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

# Prepended to every release's generated notes. The update chip in the drawer
# links to the release page, so this is what someone reads the instant they act
# on the chip. Without it they land on a bare commit list: a page that confirms
# there is an update but not how to take it.
define RELEASE_NOTES
**To update:** `cd pr-radar && git pull && make install`

Pull before installing. The version comes from *your* checkout, so building a
stale tree leaves the update chip showing after you have already updated.
endef
export RELEASE_NOTES

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
	@gh release create "v$(VERSION)" --title "PR Radar $(VERSION)" \
		--notes "$$RELEASE_NOTES" --generate-notes
	@echo "==> done. Collaborators watching releases are notified by GitHub,"
	@echo "    and running copies show an update chip within six hours."
