// Entry point of the Rex Changes panel. Rex loads this dylib through a weak
// LC_LOAD_WEAK_DYLIB command that rexmod's patch adds; the constructor waits
// for the app's main run loop and then hands over to Swift.
#import <Foundation/Foundation.h>

extern void rexmod_panel_start(void);

__attribute__((constructor)) static void rexmod_panel_init(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID hasPrefix:@"com.superlogical.rex"]) {
        return; // only ever run inside the Rex app
    }
    if (getenv("REXMOD_PANEL_DISABLE") != NULL) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        rexmod_panel_start();
    });
}

#include <notify.h>

void rexmod_notify_register(const char *name, void (^handler)(void)) {
    int token = 0;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        handler();
    });
}
