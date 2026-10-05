#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

/* Local registration and lifecycle delivery. No desktop AppleEvent IPC. */
@interface NSAppleEventManager : NSObject
@property(strong) NSMutableDictionary *handlers;
@end
@implementation NSAppleEventManager
+ (instancetype)sharedAppleEventManager {
    static NSAppleEventManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [self new]; manager.handlers = [NSMutableDictionary new];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                NSDictionary *record = manager.handlers[@"61657674:71756974"];
                if (!record) return;
                id handler = record[@"handler"];
                SEL selector = NSSelectorFromString(record[@"selector"]);
                ((void (*)(id, SEL, id, id))objc_msgSend)(handler, selector, nil, nil);
            }];
    });
    return manager;
}
- (void)setEventHandler:(id)handler andSelector:(SEL)selector forEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID {
    NSMethodSignature *signature = [handler methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 4 || strcmp(signature.methodReturnType, "v")) {
        [NSException raise:NSInvalidArgumentException format:@"Unsupported local AppleEvent handler ABI"];
    }
    NSString *key = [NSString stringWithFormat:@"%08x:%08x", eventClass, eventID];
    self.handlers[key] = @{@"handler": handler, @"selector": NSStringFromSelector(selector)};
    fprintf(stderr, "UNITYPROBE LOCAL_EVENT_REGISTER %s %s\n", key.UTF8String, NSStringFromSelector(selector).UTF8String);
}
- (void)removeEventHandlerForEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID {
    [self.handlers removeObjectForKey:[NSString stringWithFormat:@"%08x:%08x", eventClass, eventID]];
}
@end
