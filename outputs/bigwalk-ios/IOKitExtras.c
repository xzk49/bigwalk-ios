#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

/*
 * Unity's macOS player registers for system-power notifications during its
 * AppKit launch callback.  iOS exposes the IOKit symbol, but its implementation
 * assumes a non-null macOS IONotificationPortRef and dereferences it before
 * returning.  IORegisterForSystemPower intentionally produces no port on iOS,
 * so the stock call crashes before Unity can continue.  Return one inert
 * run-loop source for this optional notification path; display/input startup
 * does not depend on power events.
 */
CFRunLoopSourceRef IONotificationPortGetRunLoopSource(void *notificationPort) {
    static CFRunLoopSourceRef source;
    if (!source) {
        CFRunLoopSourceContext context = {0};
        source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
    }
    fprintf(stderr, "UNITYPROBE IOKIT_POWER_SOURCE port=%p source=%p\n",
            notificationPort, source);
    return source;
}
