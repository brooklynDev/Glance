APP_NAME = Glance
SWIFT_FILE = main.swift
TOOLS_DIR = Tools
RESOURCES_DIR = Resources
BUILD_DIR = build
DIST_DIR = dist
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
APP_STAMP = $(BUILD_DIR)/.$(APP_NAME)-app.stamp
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
APP_RESOURCES_DIR = $(CONTENTS_DIR)/Resources
INFO_PLIST = $(RESOURCES_DIR)/Info.plist
ICON_PNG = $(BUILD_DIR)/$(APP_NAME)-Icon.png
ICONSET = $(BUILD_DIR)/$(APP_NAME).iconset
ICON_FILE = $(APP_RESOURCES_DIR)/$(APP_NAME).icns
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?=
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: build app run sign install uninstall zip notarize validate assess clean

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SWIFT_FILE)
	mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FILE) -o $(BUILD_DIR)/$(APP_NAME) -framework AppKit -framework ApplicationServices -framework Carbon

app: $(APP_STAMP)

$(APP_STAMP): $(MACOS_DIR)/$(APP_NAME) $(CONTENTS_DIR)/Info.plist $(ICON_FILE)
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE)
	touch $(APP_STAMP)

$(MACOS_DIR)/$(APP_NAME): $(SWIFT_FILE)
	mkdir -p $(MACOS_DIR)
	swiftc $(SWIFT_FILE) -o $(MACOS_DIR)/$(APP_NAME) -framework AppKit -framework ApplicationServices -framework Carbon

$(CONTENTS_DIR)/Info.plist: $(INFO_PLIST)
	mkdir -p $(CONTENTS_DIR)
	cp $(INFO_PLIST) $(CONTENTS_DIR)/Info.plist
	plutil -lint $(CONTENTS_DIR)/Info.plist

$(ICON_FILE): $(ICON_PNG)
	mkdir -p $(ICONSET) $(APP_RESOURCES_DIR)
	sips -z 16 16 $(ICON_PNG) --out $(ICONSET)/icon_16x16.png
	sips -z 32 32 $(ICON_PNG) --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32 $(ICON_PNG) --out $(ICONSET)/icon_32x32.png
	sips -z 64 64 $(ICON_PNG) --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128 $(ICON_PNG) --out $(ICONSET)/icon_128x128.png
	sips -z 256 256 $(ICON_PNG) --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256 $(ICON_PNG) --out $(ICONSET)/icon_256x256.png
	sips -z 512 512 $(ICON_PNG) --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512 $(ICON_PNG) --out $(ICONSET)/icon_512x512.png
	cp $(ICON_PNG) $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICON_FILE)

$(ICON_PNG): $(TOOLS_DIR)/GenerateIcon.swift
	mkdir -p $(BUILD_DIR)
	swift $(TOOLS_DIR)/GenerateIcon.swift $(ICON_PNG)

run: app
	open $(APP_BUNDLE)

sign: app
	codesign --force --deep --options runtime --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE)
	touch $(APP_STAMP)

install: app
	mkdir -p $(INSTALL_DIR)
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

zip: app
	mkdir -p $(DIST_DIR)
	ditto -c -k --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(APP_NAME).zip

notarize: sign
	test -n "$(NOTARY_PROFILE)"
	mkdir -p $(DIST_DIR)
	ditto -c -k --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(APP_NAME).zip
	xcrun notarytool submit $(DIST_DIR)/$(APP_NAME).zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP_BUNDLE)
	ditto -c -k --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(APP_NAME).zip

validate: app
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)

assess: app
	spctl --assess --type execute --verbose $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) $(APP_NAME) WindowSwitcher
