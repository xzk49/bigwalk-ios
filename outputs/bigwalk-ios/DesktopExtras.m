#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#include <stdint.h>
#include <math.h>

#if defined(BUILD_CARBON)
CFTypeRef TISCopyCurrentKeyboardLayoutInputSource(void);
CFTypeRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) { return TISCopyCurrentKeyboardLayoutInputSource(); }
CFTypeRef TISCopyCurrentKeyboardInputSource(void) { return TISCopyCurrentKeyboardLayoutInputSource(); }
double GetCurrentEventTime(void) { return CACurrentMediaTime(); }
const CFStringRef kTISNotifySelectedKeyboardInputSourceChanged = CFSTR("kTISNotifySelectedKeyboardInputSourceChanged");
const CFStringRef kTISPropertyInputSourceID = CFSTR("kTISPropertyInputSourceID");
const CFStringRef kTISPropertyInputSourceType = CFSTR("kTISPropertyInputSourceType");
const CFStringRef kTISTypeKeyboardLayout = CFSTR("kTISTypeKeyboardLayout");
#endif

#if defined(BUILD_COREVIDEO)
int32_t CVDisplayLinkCreateWithActiveCGDisplays(void **);
int32_t CVDisplayLinkCreateWithCGDisplay(uint32_t display, void **link) {
    if (display != 1) return -6661;
    return CVDisplayLinkCreateWithActiveCGDisplays(link);
}
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(void *link) {
    extern double CVDisplayLinkGetActualOutputVideoRefreshPeriod(void *);
    double period = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link);
    return (CVTime){.timeValue=(int64_t)llround(period * 1000000000), .timeScale=1000000000, .flags=0};
}
#endif
