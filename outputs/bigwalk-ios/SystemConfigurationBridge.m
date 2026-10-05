#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

// iOS's desktop dynamic-store query returns NULL. Supply the device name
// exposed by UIKit, with Copy ownership expected by the original Unity caller.
CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store, CFStringEncoding *encoding) {
    if (encoding) *encoding = kCFStringEncodingUTF8;
    NSString *name = UIDevice.currentDevice.name;
    fprintf(stderr, "BIGWALK_DEVICE_NAME_COPY length=%lu\n", (unsigned long)name.length);
    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)name);
}
