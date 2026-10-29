#import "ResMenuItem.h"

@implementation ResMenuItem

- (instancetype)initWithDisplay:(CGDirectDisplayID)display
                           mode:(const RDMDisplayMode *)mode {
    if (!mode || !mode->mode) {
        return nil;
    }

    self = [super initWithTitle:@"" action:@selector(setMode:) keyEquivalent:@""];
    if (self) {
        _display = display;
        _mode = *mode;
        _mode.mode = CGDisplayModeRetain(mode->mode);
        [self setTextFormat:0];
    }
    return self;
}

- (void)dealloc {
    if (_mode.mode) {
        CGDisplayModeRelease(_mode.mode);
    }
}

- (NSString *)resolutionTitle {
    if ([self isHiDPI]) {
        return [NSString stringWithFormat:@"%zu x %zu (HiDPI)",
                                          _mode.width, _mode.height];
    }
    return [NSString stringWithFormat:@"%zu x %zu", _mode.width, _mode.height];
}

- (void)setTextFormat:(int)textFormat {
    NSString *title = nil;

    if (textFormat == 1) {
        title = [self resolutionTitle];
    } else if (textFormat == 2) {
        title = [NSString stringWithFormat:@"%.0f Hz", _mode.refreshRate];
    } else {
        NSString *resolution = [self resolutionTitle];
        if (_mode.refreshRate > 0.0) {
            title = [NSString stringWithFormat:@"%@, %.0f Hz",
                                               resolution, _mode.refreshRate];
        } else {
            title = resolution;
        }
    }

    [self setTitle:title];
}

- (CGDirectDisplayID)displayID {
    return _display;
}

- (CGDisplayModeRef)displayMode {
    return _mode.mode;
}

- (const RDMDisplayMode *)modeInfo {
    return &_mode;
}

- (int)colorDepth {
    return _mode.bitsPerPixel;
}

- (size_t)modeWidth {
    return _mode.width;
}

- (size_t)modeHeight {
    return _mode.height;
}

- (double)refreshRate {
    return _mode.refreshRate;
}

- (double)scale {
    return _mode.scale;
}

- (BOOL)isHiDPI {
    return _mode.pixelWidth > _mode.width || _mode.scale >= 1.5;
}

- (NSComparisonResult)compareResMenuItem:(ResMenuItem *)otherItem {
    if (_mode.scale != otherItem.scale) {
        return _mode.scale > otherItem.scale
            ? NSOrderedAscending
            : NSOrderedDescending;
    }
    if (_mode.width != otherItem.modeWidth) {
        return _mode.width > otherItem.modeWidth
            ? NSOrderedAscending
            : NSOrderedDescending;
    }
    if (_mode.height != otherItem.modeHeight) {
        return _mode.height > otherItem.modeHeight
            ? NSOrderedAscending
            : NSOrderedDescending;
    }
    if (_mode.refreshRate != otherItem.refreshRate) {
        return _mode.refreshRate > otherItem.refreshRate
            ? NSOrderedAscending
            : NSOrderedDescending;
    }
    return NSOrderedSame;
}

@end
