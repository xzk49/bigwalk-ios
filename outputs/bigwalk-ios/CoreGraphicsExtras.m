#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdlib.h>

extern void StrayInstallMetalBufferStorage(id<MTLDevice> device);
extern void UnityInstallTextureStorage(id<MTLDevice> device);

// The display bridge exposes display 1 as the iPhone's built-in screen.
bool CGDisplayIsBuiltin(uint32_t display) { return display == 1; }
void CGGetLastMouseDelta(int32_t *x, int32_t *y) {
    void (*readDelta)(int32_t *, int32_t *) = dlsym(RTLD_DEFAULT, "BigWalkReadMouseDelta");
    if (!readDelta) abort();
    readDelta(x, y);
}

// Unity's flagsChanged translator queries this macOS API. The input bridge
// owns actual UIKit/virtual modifier state; never return a fixed flag value.
uint64_t CGEventSourceFlagsState(int32_t stateID) {
    uint64_t (*readFlags)(void)=dlsym(RTLD_DEFAULT,"BigWalkReadModifierFlags");
    if(!readFlags)abort();
    return readFlags();
}
bool CGEventSourceKeyState(int32_t stateID, uint16_t key) {
    bool (*readKey)(uint16_t)=dlsym(RTLD_DEFAULT,"BigWalkReadKeyState");
    if(!readKey)abort();return readKey(key);
}
bool CGEventSourceButtonState(int32_t stateID, uint32_t button) {
    uint64_t (*readButtons)(void)=dlsym(RTLD_DEFAULT,"BigWalkReadMouseButtons");
    if(!readButtons)abort();return button<64?((readButtons()>>button)&1)!=0:false;
}

static BOOL DeviceHasNoSwitchingRole(id device, SEL selector) { return NO; }
static BOOL DeviceDrivesDisplay(id device, SEL selector) { return NO; }
static BOOL DeviceNotRemovable(id device, SEL selector) { return NO; }

static void InstallDeviceMetadata(id<MTLDevice> device) {
    StrayInstallMetalBufferStorage(device);
    UnityInstallTextureStorage(device);
    /* These macOS getters describe automatic GPU switching / external GPUs,
     * neither of which exists on this iPhone. Do not alter feature families. */
    /* Xcode's CaptureMTLDevice advertises macOS getters but forwards them to
     * AGX, where they are absent. Include the concrete class observed in the
     * exception for this A19 device; patch only missing Methods. */
    Class classes[] = {object_getClass(device),
                       [device.name isEqualToString:@"Apple A19 GPU"] ? objc_lookUpClass("AGXG18PDevice") : Nil};
    SEL selectors[] = {sel_registerName("isLowPower"), sel_registerName("isHeadless"),
                       sel_registerName("isRemovable")};
    IMP implementations[] = {(IMP)DeviceHasNoSwitchingRole, (IMP)DeviceDrivesDisplay,
                              (IMP)DeviceNotRemovable};
    for (unsigned c = 0; c < 2; c++) {
        Class cls = classes[c];
        if (!cls) continue;
        for (unsigned i = 0; i < 3; i++) {
            if (!class_getInstanceMethod(cls, selectors[i])) {
                BOOL added = class_addMethod(cls, selectors[i], implementations[i], "B@:");
                fprintf(stderr, "UNITYPROBE METAL_METADATA %s class=%s added=%d value=0\n",
                        sel_getName(selectors[i]), class_getName(cls), added);
            }
        }
    }
}

uint32_t CGDisplayIOServicePort(uint32_t display) {
    /* iOS has no public macOS display registry service. Unity uses this only
     * for the optional DisplayProductName dictionary and accepts no result. */
    fprintf(stderr, "UNITYPROBE DISPLAY_REGISTRY_UNAVAILABLE display=%u\n", display);
    return 0;
}

/* Match CoreGraphics' macOS Copy ownership. The display bridge exposes only
 * display 1; the iPhone's native system GPU drives that screen. Unity resolves
 * this API with dlsym, so a static import audit does not discover it. */
id<MTLDevice> CGDirectDisplayCopyCurrentMetalDevice(uint32_t display) NS_RETURNS_RETAINED;
id<MTLDevice> CGDirectDisplayCopyCurrentMetalDevice(uint32_t display) {
    if (display != 1) return nil;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device) InstallDeviceMetadata(device);
    fprintf(stderr, "UNITYPROBE DISPLAY_METAL_DEVICE display=%u gpu=%s\n",
            display, device.name.UTF8String ?: "none");
    return device;
}
