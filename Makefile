APP_NAME = Claude Usage Monitor
MACOS_MIN = 14.0
SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
# The SwiftPM build system records the deployment target as the SDK version
# (sdk 14.0), which makes AppKit fall back to the legacy window look (square
# popover corners, old material). Pass the real SDK version to the linker.
SWIFT_BUILD = swift build -c release --arch arm64 --arch x86_64 \
	-Xlinker -platform_version -Xlinker macos -Xlinker $(MACOS_MIN) -Xlinker $(SDK_VERSION)
# The universal output dir differs between toolchains (.build/apple vs .build/out), so ask SwiftPM.
BUILD_DIR = $(shell $(SWIFT_BUILD) --show-bin-path 2>/dev/null)
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build install uninstall clean

build:
	$(SWIFT_BUILD)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/ClaudeUsageMonitor" "$(APP_BUNDLE)/Contents/MacOS/"
	cp Sources/Info.plist "$(APP_BUNDLE)/Contents/"
	cp Sources/Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@otool -l "$(APP_BUNDLE)/Contents/MacOS/ClaudeUsageMonitor" | grep -q "sdk $(SDK_VERSION)" \
		|| (echo "error: binary does not record SDK $(SDK_VERSION)"; exit 1)
	@echo "Build complete: $(APP_BUNDLE)"

install: build
	@echo "Installing to /Applications..."
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "/Applications/"
	@echo "Installed! Opening $(APP_NAME)..."
	open "/Applications/$(APP_NAME).app"

uninstall:
	rm -rf "/Applications/$(APP_NAME).app"
	@echo "Uninstalled $(APP_NAME)"

clean:
	swift package clean
	@echo "Cleaned build artifacts"
