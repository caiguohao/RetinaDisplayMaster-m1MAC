#import "utils.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace {

RDMDisplayMode MakeModeInfo(CGDisplayModeRef mode) {
    RDMDisplayMode info = {};
    info.mode = CGDisplayModeRetain(mode);
    info.width = CGDisplayModeGetWidth(mode);
    info.height = CGDisplayModeGetHeight(mode);
    info.pixelWidth = CGDisplayModeGetPixelWidth(mode);
    info.pixelHeight = CGDisplayModeGetPixelHeight(mode);

    if (info.pixelWidth == 0) {
        info.pixelWidth = info.width;
    }
    if (info.pixelHeight == 0) {
        info.pixelHeight = info.height;
    }

    info.refreshRate = CGDisplayModeGetRefreshRate(mode);
    info.scale = info.width > 0
        ? static_cast<double>(info.pixelWidth) / static_cast<double>(info.width)
        : 1.0;
    info.ioDisplayModeID = CGDisplayModeGetIODisplayModeID(mode);
    // Desktop GUI modes on Apple Silicon are 32-bit. CoreGraphics has not
    // exposed a supported per-mode bit-depth API since macOS 10.11.
    info.bitsPerPixel = 32;
    return info;
}

bool SameScale(double left, double right) {
    return std::fabs(left - right) < 0.01;
}

bool SameRefreshRate(double left, double right) {
    return std::fabs(left - right) < 0.01;
}

}  // namespace

bool RDMGetOnlineDisplays(CGDirectDisplayID **displays, uint32_t *count) {
    if (!displays || !count) {
        return false;
    }

    *displays = nullptr;
    *count = 0;

    uint32_t displayCount = 0;
    CGError error = CGGetOnlineDisplayList(0, nullptr, &displayCount);
    if (error != kCGErrorSuccess) {
        return false;
    }
    if (displayCount == 0) {
        return true;
    }

    auto *result = static_cast<CGDirectDisplayID *>(
        std::calloc(displayCount, sizeof(CGDirectDisplayID)));
    if (!result) {
        return false;
    }

    error = CGGetOnlineDisplayList(displayCount, result, &displayCount);
    if (error != kCGErrorSuccess) {
        std::free(result);
        return false;
    }

    *displays = result;
    *count = displayCount;
    return true;
}

bool RDMCopyAllDisplayModes(CGDirectDisplayID display,
                            RDMDisplayMode **modes,
                            size_t *count) {
    if (!modes || !count) {
        return false;
    }

    *modes = nullptr;
    *count = 0;

    CFMutableDictionaryRef options = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if (!options) {
        return false;
    }
    CFDictionarySetValue(options,
                         kCGDisplayShowDuplicateLowResolutionModes,
                         kCFBooleanTrue);

    CFArrayRef cfModes = CGDisplayCopyAllDisplayModes(display, options);
    CFRelease(options);
    if (!cfModes) {
        return false;
    }

    CFIndex modeCount = CFArrayGetCount(cfModes);
    if (modeCount <= 0) {
        CFRelease(cfModes);
        return true;
    }

    auto *result = static_cast<RDMDisplayMode *>(
        std::calloc(static_cast<size_t>(modeCount), sizeof(RDMDisplayMode)));
    if (!result) {
        CFRelease(cfModes);
        return false;
    }

    size_t usableCount = 0;
    for (CFIndex index = 0; index < modeCount; ++index) {
        auto mode = static_cast<CGDisplayModeRef>(
            const_cast<void *>(CFArrayGetValueAtIndex(cfModes, index)));
        if (!mode || !CGDisplayModeIsUsableForDesktopGUI(mode)) {
            continue;
        }
        result[usableCount++] = MakeModeInfo(mode);
    }
    CFRelease(cfModes);

    if (usableCount == 0) {
        std::free(result);
        return true;
    }

    if (usableCount != static_cast<size_t>(modeCount)) {
        auto *shrunk = static_cast<RDMDisplayMode *>(
            std::realloc(result, usableCount * sizeof(RDMDisplayMode)));
        if (shrunk) {
            result = shrunk;
        }
    }

    *modes = result;
    *count = usableCount;
    return true;
}

bool RDMCopyCurrentDisplayMode(CGDirectDisplayID display,
                               RDMDisplayMode *mode) {
    if (!mode) {
        return false;
    }
    *mode = {};

    CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
    if (!current) {
        return false;
    }

    *mode = MakeModeInfo(current);
    CGDisplayModeRelease(current);
    return mode->mode != nullptr;
}

bool RDMDisplayModesEqual(const RDMDisplayMode *left,
                          const RDMDisplayMode *right) {
    if (!left || !right || !left->mode || !right->mode) {
        return false;
    }

    if (left->ioDisplayModeID >= 0 &&
        left->ioDisplayModeID == right->ioDisplayModeID) {
        return true;
    }

    return left->width == right->width &&
           left->height == right->height &&
           left->pixelWidth == right->pixelWidth &&
           left->pixelHeight == right->pixelHeight &&
           SameRefreshRate(left->refreshRate, right->refreshRate);
}

bool RDMDisplayModesHaveSameResolution(const RDMDisplayMode *left,
                                       const RDMDisplayMode *right) {
    if (!left || !right) {
        return false;
    }
    return left->width == right->width &&
           left->height == right->height &&
           left->pixelWidth == right->pixelWidth &&
           left->pixelHeight == right->pixelHeight &&
           SameScale(left->scale, right->scale);
}

CGError RDMSetDisplayMode(CGDirectDisplayID display,
                          CGDisplayModeRef mode) {
    if (!mode) {
        return kCGErrorIllegalArgument;
    }

    CGDisplayConfigRef config = nullptr;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess) {
        return error;
    }

    error = CGConfigureDisplayWithDisplayMode(config, display, mode, nullptr);
    if (error != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return error;
    }

    return CGCompleteDisplayConfiguration(config, kCGConfigurePermanently);
}

void RDMReleaseDisplayMode(RDMDisplayMode *mode) {
    if (mode && mode->mode) {
        CGDisplayModeRelease(mode->mode);
    }
    if (mode) {
        *mode = {};
    }
}

void RDMFreeDisplayModes(RDMDisplayMode *modes, size_t count) {
    if (!modes) {
        return;
    }
    for (size_t index = 0; index < count; ++index) {
        RDMReleaseDisplayMode(&modes[index]);
    }
    std::free(modes);
}
