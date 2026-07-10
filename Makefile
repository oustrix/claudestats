CONFIG ?= debug
APP := ClaudeStats.app
BUNDLE_ID := com.oustrix.claudestats
MIN_MACOS := 26.0

.PHONY: build test run app clean

build:
	swift build -c $(CONFIG)

test:
	swift test

run:
	swift run ClaudeStatsApp

# Assembles the .app by hand: SPM emits a bare executable, and macOS needs a bundle with an
# Info.plist, otherwise the window never takes focus and the app stays invisible in the Dock.
app: CONFIG = release
app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp "$$(swift build -c release --show-bin-path)/ClaudeStatsApp" $(APP)/Contents/MacOS/ClaudeStats
	printf '%s' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>CFBundleName</key><string>ClaudeStats</string>' \
	  '<key>CFBundleDisplayName</key><string>ClaudeStats</string>' \
	  '<key>CFBundleExecutable</key><string>ClaudeStats</string>' \
	  '<key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '<key>CFBundlePackageType</key><string>APPL</string>' \
	  '<key>CFBundleShortVersionString</key><string>0.1.0</string>' \
	  '<key>CFBundleVersion</key><string>1</string>' \
	  '<key>LSMinimumSystemVersion</key><string>$(MIN_MACOS)</string>' \
	  '<key>NSHighResolutionCapable</key><true/>' \
	  '</dict></plist>' \
	  > $(APP)/Contents/Info.plist
	@echo "built: $(APP)"

clean:
	rm -rf .build $(APP)
