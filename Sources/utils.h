#ifndef RDM_UTILS_H
#define RDM_UTILS_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDMDisplayMode {
    CGDisplayModeRef mode;
    size_t width;
    size_t height;
    size_t pixelWidth;
    size_t pixelHeight;
    double refreshRate;
    double scale;
    int32_t ioDisplayModeID;
    int bitsPerPixel;
    bool usesNativeMode;
    int32_t nativeModeIndex;
} RDMDisplayMode;

bool RDMGetOnlineDisplays(CGDirectDisplayID **displays, uint32_t *count);
bool RDMCopyAllDisplayModes(CGDirectDisplayID display,
                            RDMDisplayMode **modes,
                            size_t *count);
bool RDMCopyCurrentDisplayMode(CGDirectDisplayID display,
                               RDMDisplayMode *mode);
bool RDMDisplayModesEqual(const RDMDisplayMode *left,
                          const RDMDisplayMode *right);
bool RDMDisplayModesHaveSameResolution(const RDMDisplayMode *left,
                                       const RDMDisplayMode *right);
bool RDMDisplayModesHaveSameLogicalResolution(const RDMDisplayMode *left,
                                              const RDMDisplayMode *right);
CGError RDMSetDisplayMode(CGDirectDisplayID display,
                          const RDMDisplayMode *mode);
void RDMReleaseDisplayMode(RDMDisplayMode *mode);
void RDMFreeDisplayModes(RDMDisplayMode *modes, size_t count);

#ifdef __cplusplus
}
#endif

#endif
