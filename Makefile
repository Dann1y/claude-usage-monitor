APP_NAME = Claude Usage Monitor
BUILD_DIR = .build/apple/Products/Release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build install uninstall clean

build:
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/ClaudeUsageMonitor" "$(APP_BUNDLE)/Contents/MacOS/"
	cp Sources/Info.plist "$(APP_BUNDLE)/Contents/"
	cp Sources/Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
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
