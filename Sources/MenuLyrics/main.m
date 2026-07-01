#import <AppKit/AppKit.h>
#import "MLAppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        MLAppDelegate *delegate = [[MLAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
