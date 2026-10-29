#ifndef RDM_RES_MENU_ITEM_H
#define RDM_RES_MENU_ITEM_H

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import "utils.h"

@interface ResMenuItem : NSMenuItem {
    CGDirectDisplayID _display;
    RDMDisplayMode _mode;
}

- (instancetype)initWithDisplay:(CGDirectDisplayID)display
                           mode:(const RDMDisplayMode *)mode;
- (void)setTextFormat:(int)textFormat;
- (CGDirectDisplayID)displayID;
- (CGDisplayModeRef)displayMode;
- (const RDMDisplayMode *)modeInfo;
- (int)colorDepth;
- (size_t)modeWidth;
- (size_t)modeHeight;
- (double)refreshRate;
- (double)scale;
- (BOOL)isHiDPI;
- (NSComparisonResult)compareResMenuItem:(ResMenuItem *)otherItem;

@end

#endif
