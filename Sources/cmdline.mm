#import "cmdline.h"

#import "utils.h"

#include <cerrno>
#include <climits>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

constexpr const char *kVersion = "1.2.0";

struct Options {
    bool help = false;
    bool version = false;
    bool listDisplays = false;
    bool listModes = false;
    bool widthSet = false;
    bool heightSet = false;
    bool scaleSet = false;
    bool bitsSet = false;
    bool refreshSet = false;
    bool rotationSet = false;
    bool displaySet = false;
    int width = 0;
    int height = 0;
    double scale = 0.0;
    int bits = 0;
    double refresh = 0.0;
    double rotation = 0.0;
    int displayIndex = 0;
};

void PrintUsage(FILE *stream) {
    std::fprintf(stream,
        "Retina Display Master %s (Apple Silicon)\n"
        "Usage: SetResX [options]\n\n"
        "With no options, the status-bar application starts.\n\n"
        "Display selection:\n"
        "  --display, -d N       Display index, starting at 0 (default: main display)\n"
        "  --displays, -ld       List online displays\n\n"
        "Mode selection:\n"
        "  --width, -w N         Logical width in points\n"
        "  --height, -h N        Logical height in points\n"
        "  --scale, -s N         Backing scale (2.0 selects HiDPI)\n"
        "  --refresh N           Refresh rate in Hz\n"
        "  --bits, -b N          Color depth (32 is supported on Apple Silicon)\n"
        "  --modes, -lm          List available display modes\n"
        "  --rotation, -r N      Compatibility option; rotation is unsupported\n\n"
        "Other:\n"
        "  --help                Show this help\n"
        "  --version             Show the version\n",
        kVersion);
}

bool ParseInt(const char *text, int *value) {
    if (!text || !*text || !value) {
        return false;
    }
    char *end = nullptr;
    errno = 0;
    long parsed = std::strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' ||
        parsed < INT_MIN || parsed > INT_MAX) {
        return false;
    }
    *value = static_cast<int>(parsed);
    return true;
}

bool ParseDouble(const char *text, double *value) {
    if (!text || !*text || !value) {
        return false;
    }
    char *end = nullptr;
    errno = 0;
    double parsed = std::strtod(text, &end);
    if (errno != 0 || end == text || *end != '\0' || !std::isfinite(parsed)) {
        return false;
    }
    *value = parsed;
    return true;
}

bool ReadValue(int argc, const char *argv[], int *index, const char **value) {
    if (!index || !value || *index + 1 >= argc) {
        return false;
    }
    *value = argv[++(*index)];
    return true;
}

bool ParseOptions(int argc, const char *argv[], Options *options) {
    for (int index = 1; index < argc; ++index) {
        const char *arg = argv[index];
        const char *value = nullptr;

        if (std::strcmp(arg, "--help") == 0) {
            options->help = true;
        } else if (std::strcmp(arg, "--version") == 0) {
            options->version = true;
        } else if (std::strcmp(arg, "--displays") == 0 ||
                   std::strcmp(arg, "-ld") == 0) {
            options->listDisplays = true;
        } else if (std::strcmp(arg, "--modes") == 0 ||
                   std::strcmp(arg, "-lm") == 0) {
            options->listModes = true;
        } else if (std::strcmp(arg, "--width") == 0 ||
                   std::strcmp(arg, "-w") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseInt(value, &options->width) || options->width <= 0) {
                return false;
            }
            options->widthSet = true;
        } else if (std::strcmp(arg, "--height") == 0 ||
                   std::strcmp(arg, "-h") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseInt(value, &options->height) || options->height <= 0) {
                return false;
            }
            options->heightSet = true;
        } else if (std::strcmp(arg, "--scale") == 0 ||
                   std::strcmp(arg, "-s") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseDouble(value, &options->scale) || options->scale <= 0.0) {
                return false;
            }
            options->scaleSet = true;
        } else if (std::strcmp(arg, "--refresh") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseDouble(value, &options->refresh) || options->refresh < 0.0) {
                return false;
            }
            options->refreshSet = true;
        } else if (std::strcmp(arg, "--bits") == 0 ||
                   std::strcmp(arg, "-b") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseInt(value, &options->bits) || options->bits <= 0) {
                return false;
            }
            options->bitsSet = true;
        } else if (std::strcmp(arg, "--display") == 0 ||
                   std::strcmp(arg, "-d") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseInt(value, &options->displayIndex) ||
                options->displayIndex < 0) {
                return false;
            }
            options->displaySet = true;
        } else if (std::strcmp(arg, "--rotation") == 0 ||
                   std::strcmp(arg, "-r") == 0) {
            if (!ReadValue(argc, argv, &index, &value) ||
                !ParseDouble(value, &options->rotation)) {
                return false;
            }
            options->rotationSet = true;
        } else {
            return false;
        }
    }
    return true;
}

bool SameDouble(double left, double right) {
    return std::fabs(left - right) < 0.01;
}

const char *HiDPILabel(const RDMDisplayMode &mode) {
    return mode.pixelWidth > mode.width || mode.scale >= 1.5
        ? " (HiDPI)"
        : "";
}

void PrintMode(const RDMDisplayMode &mode, const char *prefix) {
    std::printf(
        "%s%zux%zu%s, scale %.2f, pixels %zux%zu, %.2f Hz, %d bpp\n",
        prefix,
        mode.width,
        mode.height,
        HiDPILabel(mode),
        mode.scale,
        mode.pixelWidth,
        mode.pixelHeight,
        mode.refreshRate,
        mode.bitsPerPixel);
}

void PrintDisplayHeader(size_t index,
                        CGDirectDisplayID display,
                        bool mainDisplay) {
    std::printf("Display %zu%s: id=%u",
                index,
                mainDisplay ? " (Main)" : "",
                display);
    RDMDisplayMode current = {};
    if (RDMCopyCurrentDisplayMode(display, &current)) {
        std::printf(", current %zux%zu%s @ %.2f Hz",
                    current.width,
                    current.height,
                    HiDPILabel(current),
                    current.refreshRate);
        RDMReleaseDisplayMode(&current);
    }
    std::printf("\n");
}

bool ModeMatches(const RDMDisplayMode &mode,
                 const Options &options,
                 int width,
                 int height,
                 double scale) {
    if (options.widthSet && mode.width != static_cast<size_t>(width)) {
        return false;
    }
    if (options.heightSet && mode.height != static_cast<size_t>(height)) {
        return false;
    }
    if (options.scaleSet && !SameDouble(mode.scale, scale)) {
        return false;
    }
    if (options.refreshSet && !SameDouble(mode.refreshRate, options.refresh)) {
        return false;
    }
    if (options.bitsSet && mode.bitsPerPixel != options.bits) {
        return false;
    }
    return true;
}

bool MatchesTargetResolution(const RDMDisplayMode &mode,
                             int width,
                             int height) {
    return mode.width == static_cast<size_t>(width) &&
           mode.height == static_cast<size_t>(height);
}

bool MatchesTargetScale(const RDMDisplayMode &mode, double scale) {
    return SameDouble(mode.scale, scale);
}

bool MatchesRequestedProperties(const RDMDisplayMode &mode,
                                const Options &options) {
    if (options.refreshSet &&
        !SameDouble(mode.refreshRate, options.refresh)) {
        return false;
    }
    if (options.bitsSet && mode.bitsPerPixel != options.bits) {
        return false;
    }
    return true;
}

bool IsPreferredRefresh(const RDMDisplayMode &mode,
                        const Options &options,
                        bool hasCurrent,
                        const RDMDisplayMode &current) {
    if (options.refreshSet) {
        return true;
    }
    return hasCurrent && SameDouble(mode.refreshRate, current.refreshRate);
}

RDMDisplayMode *FindPreferredMode(RDMDisplayMode *modes,
                                  size_t modeCount,
                                  const Options &options,
                                  const RDMDisplayMode &current,
                                  bool hasCurrent,
                                  int targetWidth,
                                  int targetHeight,
                                  double targetScale,
                                  bool requireCurrentScale) {
    RDMDisplayMode *preferred = nullptr;
    RDMDisplayMode *highestRefresh = nullptr;

    for (size_t index = 0; index < modeCount; ++index) {
        RDMDisplayMode &mode = modes[index];
        if (!MatchesTargetResolution(mode, targetWidth, targetHeight) ||
            !MatchesRequestedProperties(mode, options)) {
            continue;
        }
        if (requireCurrentScale &&
            !MatchesTargetScale(mode, targetScale)) {
            continue;
        }

        if (!highestRefresh || mode.refreshRate > highestRefresh->refreshRate) {
            highestRefresh = &mode;
        }
        if (IsPreferredRefresh(mode, options, hasCurrent, current)) {
            preferred = &mode;
            break;
        }
    }

    return preferred ? preferred : highestRefresh;
}

}  // namespace

int cmdline_main(int argc, const char *argv[]) {
    Options options;
    if (!ParseOptions(argc, argv, &options)) {
        std::fprintf(stderr, "Error: invalid option or missing value.\n\n");
        PrintUsage(stderr);
        return 2;
    }

    if (options.help) {
        PrintUsage(stdout);
        return 0;
    }
    if (options.version) {
        std::printf("Retina Display Master %s (Apple Silicon)\n", kVersion);
        return 0;
    }
    if (options.bitsSet && options.bits != 32) {
        std::fprintf(stderr,
            "Error: Apple Silicon desktop modes are 32-bit; --bits must be 32.\n");
        return 2;
    }
    if (options.rotationSet) {
        std::fprintf(stderr,
            "Error: rotation is not supported. Use System Settings > Displays.\n");
        return 2;
    }

    const bool hasModeFilter = options.widthSet || options.heightSet ||
                               options.scaleSet || options.refreshSet ||
                               options.bitsSet;

    CGDirectDisplayID *displays = nullptr;
    uint32_t displayCount = 0;
    if (!RDMGetOnlineDisplays(&displays, &displayCount)) {
        std::fprintf(stderr, "Error: could not query online displays.\n");
        return 1;
    }

    if (options.listDisplays) {
        if (displayCount == 0) {
            std::printf("No online displays.\n");
        } else {
            for (uint32_t index = 0; index < displayCount; ++index) {
                PrintDisplayHeader(index, displays[index],
                                   displays[index] == CGMainDisplayID());
            }
        }
        if (!options.listModes && !hasModeFilter) {
            std::free(displays);
            return 0;
        }
    }

    if (displayCount == 0) {
        std::fprintf(stderr, "Error: no online displays are available.\n");
        std::free(displays);
        return 1;
    }

    CGDirectDisplayID display = CGMainDisplayID();
    if (options.displaySet) {
        if (static_cast<uint32_t>(options.displayIndex) >= displayCount) {
            std::fprintf(stderr,
                         "Error: display index %d is outside 0...%u.\n",
                         options.displayIndex,
                         displayCount - 1);
            std::free(displays);
            return 2;
        }
        display = displays[static_cast<uint32_t>(options.displayIndex)];
    }
    std::free(displays);

    RDMDisplayMode *modes = nullptr;
    size_t modeCount = 0;
    if (!RDMCopyAllDisplayModes(display, &modes, &modeCount)) {
        std::fprintf(stderr, "Error: could not query display modes.\n");
        return 1;
    }
    if (modeCount == 0) {
        std::fprintf(stderr, "Error: no desktop display modes are available.\n");
        RDMFreeDisplayModes(modes, modeCount);
        return 1;
    }

    RDMDisplayMode current = {};
    const bool hasCurrent = RDMCopyCurrentDisplayMode(display, &current);

    if (options.listModes) {
        size_t printed = 0;
        for (size_t index = 0; index < modeCount; ++index) {
            // Only explicit filters constrain --modes. This keeps a bare
            // --modes useful for discovering every mode the display offers.
            if (ModeMatches(modes[index], options,
                            options.width, options.height, options.scale)) {
                PrintMode(modes[index], "mode: ");
                ++printed;
            }
        }
        if (printed == 0) {
            std::fprintf(stderr, "No modes matched the requested filters.\n");
        }
        if (hasCurrent) {
            RDMReleaseDisplayMode(&current);
        }
        RDMFreeDisplayModes(modes, modeCount);
        return printed == 0 ? 1 : 0;
    }

    if (!hasModeFilter) {
        if (!hasCurrent) {
            std::fprintf(stderr, "Error: could not query the current mode.\n");
            RDMFreeDisplayModes(modes, modeCount);
            return 1;
        }
        std::printf("Display id=%u\n", display);
        PrintMode(current, "current: ");
        RDMReleaseDisplayMode(&current);
        RDMFreeDisplayModes(modes, modeCount);
        return 0;
    }

    if (!hasCurrent && (!options.widthSet || !options.heightSet ||
                        !options.scaleSet)) {
        std::fprintf(stderr,
            "Error: specify --width, --height, and --scale when no current mode is available.\n");
        RDMFreeDisplayModes(modes, modeCount);
        return 1;
    }

    int targetWidth = options.widthSet
        ? options.width
        : static_cast<int>(current.width);
    int targetHeight = options.heightSet
        ? options.height
        : static_cast<int>(current.height);
    const double currentScale = hasCurrent ? current.scale : options.scale;
    const double targetScale = options.scaleSet ? options.scale : currentScale;

    // Unspecified dimensions always follow the current logical resolution.
    // Keep the current scale when possible. A refresh-only change may fall
    // back to another backing scale because some displays expose, for
    // example, 120 Hz HiDPI but only 60 Hz at scale 1.0 for that resolution.
    RDMDisplayMode *selected = FindPreferredMode(
        modes, modeCount, options, current, hasCurrent,
        targetWidth, targetHeight, targetScale,
        options.scaleSet || hasCurrent);
    if (!selected && !options.scaleSet && options.refreshSet) {
        selected = FindPreferredMode(
            modes, modeCount, options, current, hasCurrent,
            targetWidth, targetHeight, targetScale, false);
    }

    if (!selected) {
        std::fprintf(stderr, "Error: no mode matched %dx%d",
                     targetWidth, targetHeight);
        if (options.scaleSet || !options.refreshSet) {
            std::fprintf(stderr, " at scale %.2f", targetScale);
        }
        if (options.refreshSet) {
            std::fprintf(stderr, " at %.0f Hz", options.refresh);
        }
        std::fprintf(stderr, ".\n");
        if (hasCurrent) {
            RDMReleaseDisplayMode(&current);
        }
        RDMFreeDisplayModes(modes, modeCount);
        return 1;
    }

    PrintMode(*selected, "selected: ");
    if (hasCurrent && RDMDisplayModesEqual(&current, selected)) {
        std::printf("Mode is already active; no changes made.\n");
        RDMReleaseDisplayMode(&current);
        RDMFreeDisplayModes(modes, modeCount);
        return 0;
    }

    CGError error = RDMSetDisplayMode(display, selected);
    if (error != kCGErrorSuccess) {
        std::fprintf(stderr,
                     "Error: CoreGraphics rejected the display mode (CGError %d).\n",
                     static_cast<int>(error));
        if (hasCurrent) {
            RDMReleaseDisplayMode(&current);
        }
        RDMFreeDisplayModes(modes, modeCount);
        return 1;
    }

    std::printf("Display mode changed permanently.\n");
    if (hasCurrent) {
        RDMReleaseDisplayMode(&current);
    }
    RDMFreeDisplayModes(modes, modeCount);
    return 0;
}
