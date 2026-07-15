CONFIG ?= debug
APP := ClaudeStats.app
BUNDLE_ID := com.oustrix.claudestats
MIN_MACOS := 26.0

APPS_DIR ?= /Applications

.PHONY: build test run dump icon app install clean

build:
	swift build -c $(CONFIG)

test:
	swift test

run:
	swift run ClaudeStatsApp

# Prints the same aggregates the dashboard draws, for cross-checking against ccusage or jq.
# Pass a different transcript root with: make dump ROOT=/path/to/projects
dump:
	@swift run -c release ClaudeStatsDump $(ROOT)

# Regenerates icon/AppIcon.icns from icon/AppIcon.html via the system WebKit.
# Only needs re-running when the artwork changes; `make app` calls it too.
icon:
	sh icon/build.sh

# Assembles the .app by hand: SPM emits a bare executable, and macOS needs a bundle with an
# Info.plist, otherwise the window never takes focus and the app stays invisible in the Dock.
app: CONFIG = release
app: build icon
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/ClaudeStatsApp" $(APP)/Contents/MacOS/ClaudeStats
	cp icon/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	printf '%s' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>CFBundleName</key><string>ClaudeStats</string>' \
	  '<key>CFBundleDisplayName</key><string>ClaudeStats</string>' \
	  '<key>CFBundleExecutable</key><string>ClaudeStats</string>' \
	  '<key>CFBundleIconFile</key><string>AppIcon</string>' \
	  '<key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '<key>CFBundlePackageType</key><string>APPL</string>' \
	  '<key>CFBundleShortVersionString</key><string>0.1.0</string>' \
	  '<key>CFBundleVersion</key><string>1</string>' \
	  '<key>LSMinimumSystemVersion</key><string>$(MIN_MACOS)</string>' \
	  '<key>NSHighResolutionCapable</key><true/>' \
	  '</dict></plist>' \
	  > $(APP)/Contents/Info.plist
	@echo "built: $(APP)"

# Builds the bundle from the current state and drops it into the Applications folder,
# replacing any previous copy. Override the destination with: make install APPS_DIR=~/Applications
install: app
	rm -rf "$(APPS_DIR)/$(APP)"
	cp -R $(APP) "$(APPS_DIR)/$(APP)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APPS_DIR)/$(APP)"
	@echo "installed: $(APPS_DIR)/$(APP)"

clean:
	rm -rf .build $(APP)
