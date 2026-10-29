#ifndef RDM_APPLICATION_DELEGATE_H
#define RDM_APPLICATION_DELEGATE_H

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface SRApplicationDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    NSMenu *_statusMenu;
    NSStatusItem *_statusItem;
}

- (void)refreshStatusMenu;

@end

#endif
