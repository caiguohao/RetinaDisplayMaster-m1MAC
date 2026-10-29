#import "utils.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <vector>

namespace {

constexpr size_t kNativeModeRecordLength = 212;
constexpr size_t kNativeModeFlagsOffset = 4;
constexpr size_t kNativeModeWidthOffset = 8;
constexpr size_t kNativeModeHeightOffset = 12;
constexpr size_t kNativeModeRefreshRateOffset = 190;
constexpr size_t kNativeModePixelWidthOffset = 200;
constexpr size_t kNativeModePixelHeightOffset = 204;
constexpr uint32_t kNativeModeUnsupportedFlag = 0x40000000;

using SLSGetNumberOfDisplayModesFn =
    int32_t (*)(uint32_t display, int32_t *count);
using SLSGetDisplayModeDescriptionOfLengthFn =
    int32_t (*)(uint32_t display,
                int32_t modeIndex,
                void *description,
                int32_t descriptionLength);
using SLSConfigureDisplayModeFn =
    int32_t (*)(CGDisplayConfigRef config,
                uint32_t display,
                int32_t modeIndex);

struct SkyLightDisplayModesAPI {
    SLSGetNumberOfDisplayModesFn getNumberOfDisplayModes = nullptr;
    SLSGetDisplayModeDescriptionOfLengthFn getDisplayModeDescription = nullptr;
    SLSConfigureDisplayModeFn configureDisplayMode = nullptr;

    SkyLightDisplayModesAPI() {
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            return;
        }
        getNumberOfDisplayModes =
            reinterpret_cast<SLSGetNumberOfDisplayModesFn>(
                dlsym(handle, "SLSGetNumberOfDisplayModes"));
        getDisplayModeDescription =
            reinterpret_cast<SLSGetDisplayModeDescriptionOfLengthFn>(
                dlsym(handle, "SLSGetDisplayModeDescriptionOfLength"));
        configureDisplayMode =
            reinterpret_cast<SLSConfigureDisplayModeFn>(
                dlsym(handle, "SLSConfigureDisplayMode"));
    }

    bool CanEnumerate() const {
        return getNumberOfDisplayModes && getDisplayModeDescription;
    }
};

SkyLightDisplayModesAPI &GetSkyLightDisplayModesAPI() {
    // Intentionally keep the private framework loaded for the lifetime of the
    // process so the resolved function pointers remain valid.
    static SkyLightDisplayModesAPI api;
    return api;
}

template <typename T>
T ReadNativeModeField(const unsigned char *record, size_t offset) {
    T value = {};
    std::memcpy(&value, record + offset, sizeof(value));
    return value;
}

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
    info.nativeModeIndex = -1;
    return info;
}

bool SameScale(double left, double right) {
    return std::fabs(left - right) < 0.01;
}

bool SameRefreshRate(double left, double right) {
    return std::fabs(left - right) < 0.01;
}

bool SameVisibleMode(const RDMDisplayMode &left,
                     const RDMDisplayMode &right) {
    return left.width == right.width &&
           left.height == right.height &&
           left.pixelWidth == right.pixelWidth &&
           left.pixelHeight == right.pixelHeight &&
           SameScale(left.scale, right.scale) &&
           SameRefreshRate(left.refreshRate, right.refreshRate);
}

bool MakeNativeModeInfo(const unsigned char *record,
                        int32_t modeIndex,
                        RDMDisplayMode *info) {
    if (!record || !info) {
        return false;
    }

    const uint32_t flags =
        ReadNativeModeField<uint32_t>(record, kNativeModeFlagsOffset);
    if ((flags & kNativeModeUnsupportedFlag) != 0) {
        return false;
    }

    const uint32_t width =
        ReadNativeModeField<uint32_t>(record, kNativeModeWidthOffset);
    const uint32_t height =
        ReadNativeModeField<uint32_t>(record, kNativeModeHeightOffset);
    const uint16_t refreshRate =
        ReadNativeModeField<uint16_t>(record, kNativeModeRefreshRateOffset);
    const uint32_t pixelWidth =
        ReadNativeModeField<uint32_t>(record, kNativeModePixelWidthOffset);
    const uint32_t pixelHeight =
        ReadNativeModeField<uint32_t>(record, kNativeModePixelHeightOffset);
    if (width == 0 || height == 0 || pixelWidth == 0 || pixelHeight == 0 ||
        refreshRate == 0) {
        return false;
    }

    const double scale = static_cast<double>(pixelWidth) /
                         static_cast<double>(width);
    if (!std::isfinite(scale) || scale <= 0.0) {
        return false;
    }

    RDMDisplayMode nativeMode = {};
    nativeMode.width = width;
    nativeMode.height = height;
    nativeMode.pixelWidth = pixelWidth;
    nativeMode.pixelHeight = pixelHeight;
    nativeMode.refreshRate = refreshRate;
    nativeMode.scale = scale;
    nativeMode.ioDisplayModeID = -1;
    nativeMode.bitsPerPixel = 32;
    nativeMode.usesNativeMode = true;
    nativeMode.nativeModeIndex = modeIndex;
    *info = nativeMode;
    return true;
}

void MergeSkyLightDisplayModes(CGDirectDisplayID display,
                               std::vector<RDMDisplayMode> *modes) {
    if (!modes) {
        return;
    }

    SkyLightDisplayModesAPI &api = GetSkyLightDisplayModesAPI();
    if (!api.CanEnumerate()) {
        return;
    }

    int32_t nativeModeCount = 0;
    if (api.getNumberOfDisplayModes(display, &nativeModeCount) !=
            kCGErrorSuccess ||
        nativeModeCount <= 0) {
        return;
    }

    unsigned char record[kNativeModeRecordLength] = {};
    for (int32_t modeIndex = 0; modeIndex < nativeModeCount; ++modeIndex) {
        std::memset(record, 0, sizeof(record));
        if (api.getDisplayModeDescription(
                display, modeIndex, record,
                static_cast<int32_t>(sizeof(record))) != kCGErrorSuccess) {
            continue;
        }

        RDMDisplayMode nativeMode = {};
        if (!MakeNativeModeInfo(record, modeIndex, &nativeMode)) {
            continue;
        }

        const bool duplicate = std::any_of(
            modes->begin(), modes->end(),
            [&nativeMode](const RDMDisplayMode &existing) {
                return SameVisibleMode(existing, nativeMode);
            });
        if (!duplicate) {
            modes->push_back(nativeMode);
        }
    }
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

    std::vector<RDMDisplayMode> result;
    if (cfModes) {
        const CFIndex modeCount = CFArrayGetCount(cfModes);
        if (modeCount > 0) {
            result.reserve(static_cast<size_t>(modeCount));
        }
        for (CFIndex index = 0; index < modeCount; ++index) {
            auto mode = static_cast<CGDisplayModeRef>(
                const_cast<void *>(CFArrayGetValueAtIndex(cfModes, index)));
            if (!mode || !CGDisplayModeIsUsableForDesktopGUI(mode)) {
                continue;
            }
            result.push_back(MakeModeInfo(mode));
        }
        CFRelease(cfModes);
    }

    // Apple Silicon can keep HiDPI and high-refresh modes in SkyLight while
    // omitting them from CGDisplayCopyAllDisplayModes. Merge any usable modes
    // that are not already represented by the public catalog.
    MergeSkyLightDisplayModes(display, &result);

    if (result.empty()) {
        return true;
    }

    auto *output = static_cast<RDMDisplayMode *>(
        std::calloc(result.size(), sizeof(RDMDisplayMode)));
    if (!output) {
        for (RDMDisplayMode &mode : result) {
            RDMReleaseDisplayMode(&mode);
        }
        return false;
    }

    for (size_t index = 0; index < result.size(); ++index) {
        output[index] = result[index];
    }

    *modes = output;
    *count = result.size();
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
    if (!left || !right) {
        return false;
    }

    // An IODisplayModeID is not sufficient by itself: macOS can expose
    // several CoreGraphics modes with different scaling or refresh metadata.
    // Compare every property that affects what the user sees.
    return left->width == right->width &&
           left->height == right->height &&
           left->pixelWidth == right->pixelWidth &&
           left->pixelHeight == right->pixelHeight &&
           SameScale(left->scale, right->scale) &&
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

bool RDMDisplayModesHaveSameLogicalResolution(const RDMDisplayMode *left,
                                              const RDMDisplayMode *right) {
    if (!left || !right) {
        return false;
    }
    return left->width == right->width &&
           left->height == right->height;
}

CGError RDMSetDisplayMode(CGDirectDisplayID display,
                          const RDMDisplayMode *mode) {
    if (!mode) {
        return kCGErrorIllegalArgument;
    }

    if (mode->usesNativeMode) {
        SkyLightDisplayModesAPI &api = GetSkyLightDisplayModesAPI();
        if (!api.configureDisplayMode) {
            return kCGErrorIllegalArgument;
        }

        CGDisplayConfigRef config = nullptr;
        CGError error = CGBeginDisplayConfiguration(&config);
        if (error != kCGErrorSuccess) {
            return error;
        }

        const int32_t result = api.configureDisplayMode(
            config, display, mode->nativeModeIndex);
        if (result != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(config);
            return static_cast<CGError>(result);
        }

        return CGCompleteDisplayConfiguration(config,
                                              kCGConfigurePermanently);
    }

    if (!mode->mode) {
        return kCGErrorIllegalArgument;
    }

    CGDisplayConfigRef config = nullptr;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess) {
        return error;
    }

    error = CGConfigureDisplayWithDisplayMode(
        config, display, mode->mode, nullptr);
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
