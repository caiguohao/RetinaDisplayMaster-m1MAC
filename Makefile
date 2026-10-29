APP_NAME := RetinaDisplayMaster
BUNDLE := build/$(APP_NAME).app
CONTENTS := $(BUNDLE)/Contents
EXECUTABLE := $(CONTENTS)/MacOS/SetResX
SOURCES := $(wildcard Sources/*.mm)
HEADERS := $(wildcard Sources/*.h)
RESOURCES := $(wildcard Resources/*)
ARCH ?= arm64
MIN_MACOS ?= 11.0
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
CXX := xcrun --sdk macosx clang++
CXXFLAGS := -std=c++17 -fobjc-arc -arch $(ARCH) \
	-mmacosx-version-min=$(MIN_MACOS) -I Sources \
	-nostdinc++ -isystem $(SDKROOT)/usr/include/c++/v1 \
	-Wall -Wextra -Wpedantic
LDFLAGS := -framework Foundation -framework AppKit -framework CoreGraphics
ZIP := dist/$(APP_NAME)-m1-arm64.zip

.PHONY: all app build test clean dist install

all: app

app: $(EXECUTABLE)

build:
	@mkdir -p build

$(EXECUTABLE): $(SOURCES) $(HEADERS) Sources/Info.plist $(RESOURCES) | build
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	$(CXX) $(CXXFLAGS) $(SOURCES) $(LDFLAGS) -o $@
	@cp Sources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/* $(CONTENTS)/Resources/
	@plutil -lint $(CONTENTS)/Info.plist >/dev/null
	@xattr -cr $(BUNDLE)
	@xattr -dr com.apple.FinderInfo $(BUNDLE) 2>/dev/null || true
	@codesign --force --sign - --timestamp=none $(BUNDLE)
	@xattr -dr com.apple.FinderInfo $(BUNDLE) 2>/dev/null || true
	@codesign --verify --deep --strict $(BUNDLE)
	@echo "Built $(BUNDLE) ($(ARCH))"

test: app
	@$(EXECUTABLE) --version
	@$(EXECUTABLE) --help >/dev/null
	@file $(EXECUTABLE)
	@TESTDIR=$$(mktemp -d "$${TMPDIR:-/tmp}/rdm-test.XXXXXX"); \
	trap 'rm -rf "$$TESTDIR"' EXIT; \
	ditto "$(BUNDLE)" "$$TESTDIR/$(APP_NAME).app"; \
	xattr -cr "$$TESTDIR/$(APP_NAME).app"; \
	codesign --verify --deep --strict --verbose=2 "$$TESTDIR/$(APP_NAME).app"; \
	"$$TESTDIR/$(APP_NAME).app/Contents/MacOS/SetResX" --version

dist: app
	@mkdir -p dist
	@rm -f $(ZIP)
	@ditto -c -k --norsrc --noextattr --noqtn --keepParent $(BUNDLE) $(ZIP)
	@echo "Created $(ZIP)"

install: dist
	@DEST="$${DEST:-$$HOME/Applications}"; \
	mkdir -p "$$DEST"; \
	ditto "$(BUNDLE)" "$$DEST/$(APP_NAME).app"; \
	xattr -cr "$$DEST/$(APP_NAME).app"; \
	xattr -dr com.apple.FinderInfo "$$DEST/$(APP_NAME).app" 2>/dev/null || true; \
	codesign --verify --deep --strict "$$DEST/$(APP_NAME).app"; \
	echo "Installed $$DEST/$(APP_NAME).app"

clean:
	@rm -rf build dist
