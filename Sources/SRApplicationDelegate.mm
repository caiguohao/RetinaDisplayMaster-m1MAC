#import "SRApplicationDelegate.h"

#import "ResMenuItem.h"
#import "utils.h"

#include <cmath>
#include <cstdlib>

namespace {

NSString *ResolutionKey(const RDMDisplayMode &mode) {
    return [NSString stringWithFormat:@"%zux%zu@%.2f",
                                      mode.width, mode.height, mode.scale];
}

bool IsHiDPI(const RDMDisplayMode &mode) {
    return mode.pixelWidth > mode.width || mode.scale >= 1.5;
}

NSString *ResolutionTitle(const RDMDisplayMode &mode) {
    if (IsHiDPI(mode)) {
        return [NSString stringWithFormat:@"%zu x %zu (HiDPI)",
                                          mode.width, mode.height];
    }
    return [NSString stringWithFormat:@"%zu x %zu", mode.width, mode.height];
}

bool BetterResolutionCandidate(const ResMenuItem *candidate,
                               const ResMenuItem *existing,
                               const RDMDisplayMode *current) {
    if (!existing) {
        return true;
    }
    if (current) {
        const RDMDisplayMode *candidateInfo = candidate.modeInfo;
        const RDMDisplayMode *existingInfo = existing.modeInfo;
        if (RDMDisplayModesEqual(current, candidateInfo)) {
            return true;
        }
        if (RDMDisplayModesEqual(current, existingInfo)) {
            return false;
        }
    }
    return candidate.refreshRate > existing.refreshRate;
}

NSMutableArray<ResMenuItem *> *SortedMenuItems(
    NSDictionary<NSString *, ResMenuItem *> *items) {
    NSMutableArray<ResMenuItem *> *sorted =
        [NSMutableArray arrayWithArray:items.allValues];
    [sorted sortUsingSelector:@selector(compareResMenuItem:)];
    return sorted;
}

}  // namespace

@implementation SRApplicationDelegate

- (void)showAbout {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:self];
}

- (void)quit {
    [NSApp terminate:self];
}

- (ResMenuItem *)menuItemForMode:(const RDMDisplayMode *)mode
                         display:(CGDirectDisplayID)display {
    ResMenuItem *item = [[ResMenuItem alloc] initWithDisplay:display mode:mode];
    item.target = self;
    item.action = @selector(setMode:);
    return item;
}

- (void)refreshStatusMenu {
    NSMenu *newMenu = [[NSMenu alloc] initWithTitle:@""];

    CGDirectDisplayID *displays = nullptr;
    uint32_t displayCount = 0;
    if (!RDMGetOnlineDisplays(&displays, &displayCount)) {
        NSMenuItem *errorItem = [[NSMenuItem alloc]
            initWithTitle:@"Unable to query displays"
                   action:nil
            keyEquivalent:@""];
        errorItem.enabled = NO;
        [newMenu addItem:errorItem];
    } else if (displayCount == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc]
            initWithTitle:@"No online displays"
                   action:nil
            keyEquivalent:@""];
        emptyItem.enabled = NO;
        [newMenu addItem:emptyItem];
    } else {
        for (uint32_t displayIndex = 0;
             displayIndex < displayCount;
             ++displayIndex) {
            CGDirectDisplayID display = displays[displayIndex];
            NSString *displayName = display == CGMainDisplayID()
                ? @"Main Display"
                : [NSString stringWithFormat:@"Display %u", displayIndex + 1];
            NSMenuItem *heading = [[NSMenuItem alloc]
                initWithTitle:displayName
                       action:nil
                keyEquivalent:@""];
            heading.enabled = NO;
            [newMenu addItem:heading];

            RDMDisplayMode current = {};
            const bool hasCurrent = RDMCopyCurrentDisplayMode(display, &current);

            RDMDisplayMode *modes = nullptr;
            size_t modeCount = 0;
            if (!RDMCopyAllDisplayModes(display, &modes, &modeCount) ||
                modeCount == 0) {
                NSMenuItem *emptyItem = [[NSMenuItem alloc]
                    initWithTitle:@"No usable display modes"
                           action:nil
                    keyEquivalent:@""];
                emptyItem.enabled = NO;
                [newMenu addItem:emptyItem];
                RDMFreeDisplayModes(modes, modeCount);
                if (hasCurrent) {
                    RDMReleaseDisplayMode(&current);
                }
                [newMenu addItem:[NSMenuItem separatorItem]];
                continue;
            }

            NSMutableDictionary<NSString *, ResMenuItem *> *byResolution =
                [NSMutableDictionary dictionary];
            NSMutableArray<ResMenuItem *> *allItems =
                [NSMutableArray arrayWithCapacity:modeCount];

            for (size_t modeIndex = 0; modeIndex < modeCount; ++modeIndex) {
                ResMenuItem *item =
                    [self menuItemForMode:&modes[modeIndex] display:display];
                if (!item) {
                    continue;
                }
                [allItems addObject:item];

                NSString *key = ResolutionKey(modes[modeIndex]);
                ResMenuItem *existing = byResolution[key];
                if (BetterResolutionCandidate(item, existing,
                                              hasCurrent ? &current : nullptr)) {
                    byResolution[key] = item;
                }
            }

            NSArray<ResMenuItem *> *resolutions = SortedMenuItems(byResolution);
            ResMenuItem *activeResolution = nil;
            if (hasCurrent) {
                for (ResMenuItem *item in resolutions) {
                    if (RDMDisplayModesHaveSameResolution(&current,
                                                          item.modeInfo)) {
                        activeResolution = item;
                        break;
                    }
                }
            }

            NSString *resolutionTitle = hasCurrent
                ? ResolutionTitle(current)
                : @"Resolution";
            NSMenuItem *resolutionMenu = [[NSMenuItem alloc]
                initWithTitle:resolutionTitle
                       action:nil
                keyEquivalent:@""];
            NSMenu *resolutionSubmenu = [[NSMenu alloc] initWithTitle:@""];
            for (ResMenuItem *item in resolutions) {
                [item setTextFormat:1];
                item.state = (item == activeResolution) ? NSControlStateValueOn
                                                        : NSControlStateValueOff;
                [resolutionSubmenu addItem:item];
            }
            resolutionMenu.submenu = resolutionSubmenu;
            [newMenu addItem:resolutionMenu];

            if (hasCurrent) {
                NSMutableDictionary<NSNumber *, ResMenuItem *> *byRefresh =
                    [NSMutableDictionary dictionary];
                for (size_t modeIndex = 0;
                     modeIndex < modeCount;
                     ++modeIndex) {
                    if (!RDMDisplayModesHaveSameLogicalResolution(
                            &current, &modes[modeIndex])) {
                        continue;
                    }
                    ResMenuItem *item =
                        [self menuItemForMode:&modes[modeIndex]
                                     display:display];
                    if (!item) {
                        continue;
                    }
                    NSNumber *key = @(llround(item.refreshRate * 100.0));
                    ResMenuItem *existing = byRefresh[key];
                    const bool candidateUsesCurrentResolution =
                        RDMDisplayModesHaveSameResolution(
                            &current, item.modeInfo);
                    const bool existingUsesCurrentResolution = existing &&
                        RDMDisplayModesHaveSameResolution(
                            &current, existing.modeInfo);
                    if (!existing ||
                        RDMDisplayModesEqual(&current, item.modeInfo) ||
                        candidateUsesCurrentResolution ||
                        (!existingUsesCurrentResolution &&
                         item.scale > existing.scale)) {
                        byRefresh[key] = item;
                    }
                }

                NSMutableArray<ResMenuItem *> *refreshes =
                    [NSMutableArray arrayWithArray:byRefresh.allValues];
                [refreshes sortUsingComparator:^NSComparisonResult(
                    ResMenuItem *left, ResMenuItem *right) {
                    if (left.refreshRate > right.refreshRate) {
                        return NSOrderedAscending;
                    }
                    if (left.refreshRate < right.refreshRate) {
                        return NSOrderedDescending;
                    }
                    return NSOrderedSame;
                }];

                if (refreshes.count > 0) {
                    NSString *refreshTitle = current.refreshRate > 0.0
                        ? [NSString stringWithFormat:@"%.0f Hz",
                                                     current.refreshRate]
                        : @"Refresh Rate";
                    NSMenuItem *refreshMenu = [[NSMenuItem alloc]
                        initWithTitle:refreshTitle
                               action:nil
                        keyEquivalent:@""];
                    NSMenu *refreshSubmenu =
                        [[NSMenu alloc] initWithTitle:@""];
                    for (ResMenuItem *item in refreshes) {
                        [item setTextFormat:2];
                        item.state = RDMDisplayModesEqual(&current,
                                                          item.modeInfo)
                            ? NSControlStateValueOn
                            : NSControlStateValueOff;
                        [refreshSubmenu addItem:item];
                    }
                    refreshMenu.submenu = refreshSubmenu;
                    if (refreshes.count == 1) {
                        refreshMenu.enabled = NO;
                    }
                    [newMenu addItem:refreshMenu];
                }
            }

            RDMFreeDisplayModes(modes, modeCount);
            if (hasCurrent) {
                RDMReleaseDisplayMode(&current);
            }
            [newMenu addItem:[NSMenuItem separatorItem]];
        }
    }

    std::free(displays);

    NSMenuItem *about = [[NSMenuItem alloc]
        initWithTitle:@"About Retina Display Master"
               action:@selector(showAbout)
        keyEquivalent:@""];
    about.target = self;
    [newMenu addItem:about];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit"
               action:@selector(quit)
        keyEquivalent:@""];
    quit.target = self;
    [newMenu addItem:quit];

    newMenu.delegate = self;
    _statusMenu = newMenu;
    _statusItem.menu = newMenu;
}

- (void)setMode:(ResMenuItem *)item {
    CGError error = RDMSetDisplayMode(item.displayID, item.modeInfo);
    if (error != kCGErrorSuccess) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Could not change the display mode";
        alert.informativeText = [NSString stringWithFormat:
            @"CoreGraphics returned error %d. The selected mode may be in use "
            @"by a full-screen app or unavailable while the display is mirrored.",
            static_cast<int>(error)];
        [alert runModal];
        return;
    }
    [self refreshStatusMenu];
}

- (void)screenParametersChanged:(NSNotification *)notification {
    (void)notification;
    [self refreshStatusMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    _statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSSquareStatusItemLength];

    NSImage *statusImage = [NSImage imageNamed:@"StatusIcon"];
    if (!statusImage) {
        statusImage = [NSImage imageWithSystemSymbolName:@"display"
                                accessibilityDescription:@"Retina Display Master"];
    }
    [statusImage setTemplate:YES];
    _statusItem.button.image = statusImage;
    _statusItem.button.toolTip = @"Retina Display Master";
    _statusItem.button.accessibilityLabel = @"Retina Display Master";

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(screenParametersChanged:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:nil];

    [self refreshStatusMenu];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
