#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#import "AppKitBridge.h"
#import <objc/message.h>
#import <objc/runtime.h>
extern void BigWalkApplyTextureProfile(void);
extern void BigWalkPostPointer(CGFloat x, CGFloat y, BOOL down);
extern void BigWalkProbeTextEntry(void);
extern void BigWalkInstallProfilerGuard(void);
extern void BigWalkProbeEOSDeviceLogin(void);
extern void BigWalkInspectInputConfig(void);
extern void BigWalkProbeTouchKeyboard(void);
extern void BigWalkInstallMobileResolution(void);
extern void BigWalkInspectAudio(void);

@interface NSMenuItem : NSObject
@property(weak) id target;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
@end
@interface NSMenu : NSObject
- (instancetype)initWithTitle:(NSString *)title;
- (void)addItem:(NSMenuItem *)item;
@end
@interface NSApplication (ProbeRunLoop)
- (NSEvent *)nextEventMatchingMask:(uint64_t)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue;
@end

static void BootstrapCall(id target, NSString *name, id argument) {
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector]) return;
    fprintf(stderr, "UNITYPROBE CALLBACK %s %s\n", object_getClassName(target), name.UTF8String);
    if ([name hasSuffix:@":"])
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
    else ((void (*)(id, SEL))objc_msgSend)(target, selector);
}

NSString *const NSApplicationDidChangeScreenParametersNotification = @"NSApplicationDidChangeScreenParametersNotification";
NSString *const NSTextInputContextKeyboardSelectionDidChangeNotification = @"NSTextInputContextKeyboardSelectionDidChangeNotification";

int NSApplicationMain(int argc, const char **argv) {
    NSCAssert(NSThread.isMainThread, @"Guest Cocoa bootstrap must run on the UIKit main thread");
    NSString *root = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"GuestGame/Contents"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@"Info.plist"]];
    Class principal = NSClassFromString(info[@"NSPrincipalClass"]);
    Class delegateClass = NSClassFromString(@"PlayerAppDelegate");
    if (!principal || !delegateClass || ![principal isSubclassOfClass:NSApplication.class]) {
        fprintf(stderr, "UNITYPROBE BOOTSTRAP_CLASS_MISMATCH\n"); abort();
    }
    /* Reconstruct the connections verified in this game's MainMenu.nib.
     * This is a Unity startup adapter, not a general macOS NIB decoder.
     */
    NSApplication *app = [principal new];
    app.windows = [NSMutableArray new];
    app.events = [NSMutableArray new];
    NSApp = app;
    app.delegate = [delegateClass new];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Big Walk"];
    NSArray *connections = @[@[@"m_FullscreenMenuItem", @"Full Screen", @"ToggleFullscreen:"],
                              @[@"m_HideMenuItem", @"Hide", @"hide:"],
                              @[@"m_QuitMenuItem", @"Quit", @"terminate:"]];
    for (NSArray *connection in connections) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:connection[1] action:NSSelectorFromString(connection[2]) keyEquivalent:@""];
        item.target = [connection[0] isEqual:@"m_FullscreenMenuItem"] ? app.delegate : app;
        [menu addItem:item];
        [app.delegate setValue:item forKey:connection[0]];
    }
    app.mainMenu = menu;
    app.running = YES;
    fprintf(stderr, "UNITYPROBE BOOTSTRAP_CONNECTED\n");
    /* Unity's delegate can enter its own NSApplication run loop from
     * applicationDidFinishLaunching:. Keep a small main-queue heartbeat so
     * we can distinguish that normal hand-off from a synchronous crash or
     * deadlock when running the guest on iOS. */
    dispatch_source_t heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                           dispatch_get_main_queue());
    dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              2 * NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(heartbeat, ^{
        fprintf(stderr, "UNITYPROBE HEARTBEAT running=%d\n", app.running);
    });
    dispatch_resume(heartbeat);
    BootstrapCall(app, @"awakeFromNib", nil);
    BootstrapCall(app.delegate, @"awakeFromNib", nil);
    BootstrapCall(app.delegate, @"applicationWillFinishLaunching:",
                  [NSNotification notificationWithName:@"NSApplicationWillFinishLaunchingNotification" object:app]);
    fprintf(stderr, "UNITYPROBE BEFORE_APPLICATION_DID_FINISH\n");
    @try {
        BootstrapCall(app.delegate, @"applicationDidFinishLaunching:",
                      [NSNotification notificationWithName:@"NSApplicationDidFinishLaunchingNotification" object:app]);
    } @catch (NSException *exception) {
        fprintf(stderr, "UNITYPROBE CALLBACK_EXCEPTION %s %s\n",
                exception.name.UTF8String, exception.reason.UTF8String);
        abort();
    }
    fprintf(stderr, "UNITYPROBE AFTER_APPLICATION_DID_FINISH\n");
    fprintf(stderr, "UNITYPROBE LAUNCH_CALLBACKS_COMPLETE\n");
    BigWalkApplyTextureProfile();
    BigWalkInstallProfilerGuard();
    BigWalkProbeEOSDeviceLogin();
    BigWalkInspectInputConfig();
    BigWalkProbeTouchKeyboard();
    BigWalkInstallMobileResolution();
    BigWalkInspectAudio();
    if([NSProcessInfo.processInfo.arguments containsObject:@"--probe-keyboard"]){
        [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer){BigWalkProbeTextEntry();}];
    }
    // Opt-in diagnostic performs a normal pointer press/release at the visible
    // welcome Continue button. It never changes game state or account flags.
    if([NSProcessInfo.processInfo.arguments containsObject:@"--probe-continue"]){
        [NSTimer scheduledTimerWithTimeInterval:10 repeats:NO block:^(NSTimer *timer){
            BigWalkPostPointer(.49,.89,YES);
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *release){
                BigWalkPostPointer(.49,.89,NO);
            }];
        }];
    }
    /* Keep PlayerMain alive until the guest stops, while servicing Foundation
     * timers and UIKit's existing run loop. Do not enter UIApplicationMain twice.
     */
    while (app.running) {
        @autoreleasepool {
            for (unsigned i = 0; i < 256; i++) {
                id event = [app nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
                if (!event) break;
                [app sendEvent:event];
            }
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    dispatch_source_cancel(heartbeat);
    return 0;
}
@interface NSInputManager : NSObject @end
@implementation NSInputManager
+ (id)currentInputManager { return nil; }
@end
@interface NSTrackingArea : NSObject
@property CGRect rect;
@property NSUInteger options;
@property(weak) id owner;
@property(strong) NSDictionary *userInfo;
@end
@implementation NSTrackingArea
- (instancetype)initWithRect:(CGRect)rect options:(NSUInteger)options owner:(id)owner userInfo:(NSDictionary *)info {
    if ((self = [super init])) { _rect = rect; _options = options; _owner = owner; _userInfo = info; }
    return self;
}
@end
@interface NSViewController : NSObject
@property(strong) id view;
@end
@implementation NSViewController
@end
@interface NSOpenGLContext : NSObject @end
@implementation NSOpenGLContext
- (instancetype)init { fprintf(stderr, "UNITYPROBE UNSUPPORTED NSOpenGLContext\n"); abort(); }
@end
