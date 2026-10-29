#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import "SRApplicationDelegate.h"
#import "cmdline.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            return cmdline_main(argc, argv);
        }

        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];

        SRApplicationDelegate *delegate =
            [[SRApplicationDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
