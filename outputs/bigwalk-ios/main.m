#import <UIKit/UIKit.h>
#import <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <os/proc.h>

static void Stage(NSString *message) {
    fprintf(stderr, "BIGWALK_STAGE %s\n", message.UTF8String);
}
@interface BigWalkHost : UIResponder <UIApplicationDelegate>
@property(strong) UIWindow *window;
@end
@implementation BigWalkHost
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    application.idleTimerDisabled = YES;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.window.bounds, 30, 30)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 0;
    label.text = @"BIG WALK iOS\n正在验证原始 ARM64 引擎……";
    [controller.view addSubview:label];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    // PlayerMain owns a nested main run loop. A long-running main-queue block
    // prevents that loop from draining later main-queue work reentrantly.
    // Start from a one-shot run-loop timer while retaining the main-thread ABI.
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:NO block:^(NSTimer *timer) {
        NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSString *log = [documents stringByAppendingPathComponent:@"runtime-console.log"];
        int fd = open(log.fileSystemRepresentation, O_CREAT | O_TRUNC | O_WRONLY, 0600);
        if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
        setvbuf(stdout, NULL, _IONBF, 0); setvbuf(stderr, NULL, _IONBF, 0);
        Stage([NSString stringWithFormat:@"HOST_STARTED pid=%d", getpid()]);
        Stage([NSString stringWithFormat:@"AVAILABLE_MEMORY bytes=%llu", (unsigned long long)os_proc_available_memory()]);
        // The first-run rebind migration removes this directory unconditionally.
        // Create its sandbox parent before entering the original managed code.
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
        NSURL *bindings = [[support URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier]
                          URLByAppendingPathComponent:@"user_data/control_bindings" isDirectory:YES];
        NSError *directoryError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:bindings withIntermediateDirectories:YES
                                                    attributes:nil error:&directoryError]) {
            Stage([NSString stringWithFormat:@"SAVE_DIRECTORY_ERROR %@", directoryError]);
            label.text = directoryError.localizedDescription; return;
        }
        Stage(@"SAVE_DIRECTORY_READY");
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"UnityPlayer.framework/UnityPlayer"];
        void *unity = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (!unity) {
            NSString *error = [NSString stringWithUTF8String:dlerror() ?: "unknown loader error"];
            Stage(error); label.text = error; return;
        }
        Stage(@"UNITYPLAYER_LOADED");
        int (*entry)(int, const char **) = dlsym(unity, "_Z10PlayerMainiPPKc");
        Stage(entry ? @"PLAYERMAIN_FOUND" : @"PLAYERMAIN_MISSING");
        if (!entry || [NSProcessInfo.processInfo.arguments containsObject:@"--load-only"]) return;
        void (*bindWindow)(UIWindow *) = dlsym(RTLD_DEFAULT, "StrayAppKitBindHostWindow");
        if (bindWindow) bindWindow(self.window);
        NSString *contents = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"GuestGame/Contents"];
        [NSFileManager.defaultManager changeCurrentDirectoryPath:[contents stringByAppendingPathComponent:@"Resources"]];
        NSString *executable = [contents stringByAppendingPathComponent:@"MacOS/Big Walk"];
        NSString *playerLog = [documents stringByAppendingPathComponent:@"Player.log"];
        const char *arguments[] = {executable.fileSystemRepresentation, "-force-metal", "-logFile", playerLog.fileSystemRepresentation, NULL};
        Stage(@"PLAYERMAIN_CALL");
        int code = entry(4, arguments);
        Stage([NSString stringWithFormat:@"PLAYERMAIN_RETURN %d", code]);
    }];
    return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application { application.idleTimerDisabled = NO; }
- (void)applicationWillEnterForeground:(UIApplication *)application { application.idleTimerDisabled = YES; }
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(BigWalkHost.class)); }
}
