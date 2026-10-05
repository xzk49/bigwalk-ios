#import <Foundation/Foundation.h>
#include <unistd.h>

// iOS exposes our own process and bundle; it does not expose a desktop process
// inventory. EOS uses runningApplicationsWithBundleIdentifier: to find helpers.
// An unavailable helper must remain absent rather than acquire a fake identity.
@interface NSRunningApplication : NSObject
+ (instancetype)currentApplication;
+ (instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid;
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier;
@end

@implementation NSRunningApplication
+ (instancetype)currentApplication {
    static NSRunningApplication *application;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ application = [self new]; });
    return application;
}
+ (instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid {
    return pid == getpid() ? self.currentApplication : nil;
}
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier {
    NSString *actual = NSBundle.mainBundle.bundleIdentifier;
    BOOL matches = identifier.length && [identifier isEqualToString:actual];
    fprintf(stderr, "BIGWALK_RUNNING_APPLICATION query=%s current_match=%d\n",
            identifier.UTF8String ?: "(null)", matches);
    return matches ? @[self.currentApplication] : @[];
}
- (NSString *)bundleIdentifier { return NSBundle.mainBundle.bundleIdentifier; }
- (NSURL *)bundleURL { return NSBundle.mainBundle.bundleURL; }
- (NSURL *)executableURL { return NSBundle.mainBundle.executableURL; }
- (pid_t)processIdentifier { return getpid(); }
@end
