#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <execinfo.h>

// Scoped to the guest libraries' libSystem imports. Preserve native exit
// behavior while recording who requested termination in the next device run.
__attribute__((noreturn)) void ProbeGuestExit(int status) __asm__("_exit");
__attribute__((noreturn)) void ProbeGuestExit(int status) {
    void (*native)(int) = dlsym(RTLD_NEXT, "exit");
    fprintf(stderr, "BIGWALK_EXIT_REQUEST status=%d\n", status);
    void *frames[32];
    int count = backtrace(frames, 32);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    if (native) native(status);
    _exit(status);
}

int _NSGetExecutablePath(char *buffer, uint32_t *size) {
    if (!size) return -1;
    NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"GuestGame/Contents/MacOS/Big Walk"];
    uint32_t required = (uint32_t)strlen(path.fileSystemRepresentation) + 1;
    if (!buffer || *size < required) { *size = required; return -1; }
    memcpy(buffer, path.fileSystemRepresentation, required);
    return 0;
}

static _Thread_local char MappedLoaderError[4096];
static _Thread_local BOOL HasMappedLoaderError;
static char *(*NativeLoaderError)(void);
__attribute__((constructor)) static void InitializeLoaderDiagnostics(void) {
    NativeLoaderError = dlsym(RTLD_NEXT, "dlerror");
    if (!NativeLoaderError) abort();
}
char *ProbeGuestDlerror(void) __asm__("_dlerror");
char *ProbeGuestDlerror(void) {
    if (HasMappedLoaderError) { HasMappedLoaderError = NO; return MappedLoaderError; }
    return NativeLoaderError();
}
void *ProbeGuestDlopen(const char *, int) __asm__("_dlopen");
void *ProbeGuestDlopen(const char *filename, int mode) {
    typedef void *(*Fn)(const char *, int);
    static Fn native;
    if (!native) native = (Fn)dlsym(RTLD_NEXT, "dlopen");
    if (!native || native == ProbeGuestDlopen) abort();
    HasMappedLoaderError = NO;
    NSDictionary *mapping = @{@"GameAssembly.dylib": @"GameAssembly", @"lib_burst_generated.bundle": @"Burst",
        @"libsteam_api.dylib": @"SteamAPI", @"steam_api.bundle": @"SteamAPI",
        @"libEOSSDK-Mac-Shipping.dylib": @"EOSSDK", @"AudioPluginDissonance.bundle": @"Dissonance",
        @"MicrophoneUtility_macos.dylib": @"Microphone", @"Rewired_MacOS.bundle": @"Rewired", @"opus.bundle": @"Opus"};
    NSString *name = filename ? mapping[@(filename).lastPathComponent] : nil;
    if (name) {
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.framework/%@", name, [name isEqualToString:@"GameAssembly"] ? @"GameAssembly.dylib" : name]];
        fprintf(stderr, "UNITYPROBE GUEST_DLOPEN %s -> %s\n", filename, path.fileSystemRepresentation);
        void *handle = native(path.fileSystemRepresentation, mode);
        if (!handle) {
            const char *error = NativeLoaderError();
            if (error) {
                snprintf(MappedLoaderError, sizeof MappedLoaderError, "%s", error);
                HasMappedLoaderError = YES;
                fprintf(stderr, "BIGWALK_PLUGIN_LOAD_ERROR %s: %s\n", filename, MappedLoaderError);
            }
        }
        return handle;
    }
    return native(filename, mode);
}
