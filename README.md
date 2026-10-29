# Retina Display Master for Apple Silicon

A native **arm64** status-bar utility for switching macOS display modes,
including HiDPI modes and non-default resolutions. This version is based on
[Arya McCarthy's RetinaDisplayMaster](https://github.com/aryamccarthy/RetinaDisplayMaster)
and replaces its Intel-era binary and private CoreGraphics APIs with public,
Apple Silicon-compatible APIs.

## Why this fork exists

The original repository ships an x86_64 executable and uses private `CGS*`
functions with hard-coded internal structures. Those APIs are not a safe way to
enumerate or change modes on Apple Silicon. This fork:

- builds a native `arm64` application;
- uses `CGDisplayCopyAllDisplayModes`, `CGDisplayModeGetPixelWidth/Height`,
  `CGDisplayModeGetRefreshRate`, and `CGConfigureDisplayWithDisplayMode`;
- identifies HiDPI modes from logical size, pixel size, and backing scale;
- keeps the selected mode permanently with `kCGConfigurePermanently`;
- updates the menu after display reconfiguration and hot-plug events;
- retains the command-line mode alongside the status-bar application.

The resulting binary targets macOS 11 or newer and will not run on Intel Macs.

## Build

Requirements:

- an Apple Silicon Mac;
- macOS 11 or newer;
- Xcode Command Line Tools (`xcode-select --install`).

```sh
make test       # compile and verify the arm64 binary and ad-hoc signature
make dist       # create dist/RetinaDisplayMaster-m1-arm64.zip
```

The generated application is:

```text
build/RetinaDisplayMaster.app
```

## Install

Install into your user Applications folder:

```sh
./installer.sh
# or
make install
```

To install into the system Applications folder:

```sh
DEST=/Applications make install
```

Launch `Retina Display Master.app`; it appears in the menu bar without a Dock
icon. The menu lists every online display, its resolutions, and available
refresh rates. Resolutions marked **HiDPI** use a 2x backing scale.

## Command line

The same executable can be used without starting the menu-bar UI:

```sh
APP="build/RetinaDisplayMaster.app/Contents/MacOS/SetResX"

"$APP" --displays
"$APP" --modes
"$APP" --modes --width 1920
"$APP" --width 1920 --height 1080 --scale 2
"$APP" --display 1 --scale 1
```

`--scale 2` selects a HiDPI mode. Unspecified width, height, or scale values
are taken from the current mode when changing modes. Add `--refresh 60` to
choose a refresh rate. With no filters, `--modes` lists every available desktop
mode; any supplied filters are applied directly.

All options:

```text
--display, -d N       Display index, starting at 0 (default: main display)
--displays, -ld       List online displays
--width, -w N         Logical width in points
--height, -h N        Logical height in points
--scale, -s N         Backing scale (2.0 selects HiDPI)
--refresh N           Refresh rate in Hz
--bits, -b N          Color depth (32 is supported on Apple Silicon)
--modes, -lm          List available display modes
--rotation, -r N      Compatibility option; rotation is unsupported
--help                Show help
--version             Show the version
```

## Signing

Builds are signed ad-hoc so they can run locally. They are not notarized for
distribution. If you need to distribute a build outside your Mac, sign it with
a Developer ID certificate and submit it to Apple's notarization service.

## Attribution and license

Original Retina Display Master by Paul Griffin, with UI and HiDPI improvements
by Arya McCarthy. This Apple Silicon adaptation preserves the original project's
GNU General Public License v3.0 licensing.
