#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#include <mach/mach_time.h>
#include <math.h>
typedef int32_t (*OutputCallback)(void *,const CVTimeStamp *,const CVTimeStamp *,uint64_t,uint64_t *,void *);
@interface StrayDisplayLink : NSObject
@property(nonatomic, strong) CADisplayLink *nativeLink;
@property(nonatomic) OutputCallback callback;
@property(nonatomic) void *context;
@property(nonatomic) uint32_t display;
@property(atomic) BOOL running;
@property(atomic, strong) NSThread *worker;
@property(nonatomic, strong) dispatch_semaphore_t ready;
@property(nonatomic, strong) dispatch_semaphore_t finished;
@property(nonatomic) unsigned nativeTicks;
@end
@implementation StrayDisplayLink
- (void)runDisplayThread {
    @autoreleasepool {
        self.nativeLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.nativeLink addToRunLoop:NSRunLoop.currentRunLoop forMode:NSRunLoopCommonModes];
        fprintf(stderr,"BIGWALK_DISPLAY_LINK worker_started main_thread=%d\n",NSThread.isMainThread);
        dispatch_semaphore_signal(self.ready);
        // Unity waits for vblank on its main thread. CADisplayLink must keep
        // producing physical display timestamps on an independent run loop.
        while(self.running) {
            @autoreleasepool { [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
        }
        [self.nativeLink invalidate];self.nativeLink=nil;
        dispatch_semaphore_signal(self.finished);
    }
}
- (void)tick:(CADisplayLink *)link {
    if(++self.nativeTicks==1)fprintf(stderr,"BIGWALK_DISPLAY_LINK first_native_tick=1\n");
    [self outputAt:link.timestamp next:link.targetTimestamp];
}
- (void)outputAt:(CFTimeInterval)timestamp next:(CFTimeInterval)target {
    if(!self.running || !self.callback)return;
    CVTimeStamp now={0},output={0};now.videoTimeScale=1000000000;
    now.videoTime=(int64_t)llround(timestamp*1e9);now.hostTime=mach_absolute_time();now.rateScalar=1;
    now.videoRefreshPeriod=(int64_t)llround((target-timestamp)*1e9);now.flags=kCVTimeStampVideoHostTimeValid|kCVTimeStampVideoRefreshPeriodValid|kCVTimeStampRateScalarValid;
    output=now;output.videoTime=(int64_t)llround(target*1e9);mach_timebase_info_data_t info;mach_timebase_info(&info);
    output.hostTime+=(uint64_t)((target-timestamp)*1e9*info.denom/info.numer);uint64_t flags=0;
    self.callback((__bridge void *)self,&now,&output,0,&flags,self.context);
}
@end
static StrayDisplayLink *Value(void *link){return (__bridge StrayDisplayLink *)link;}
int32_t CVDisplayLinkCreateWithActiveCGDisplays(void **output){if(!output)return -6661;StrayDisplayLink *link=[StrayDisplayLink new];link.display=1;*output=(void *)CFBridgingRetain(link);return 0;}
int32_t CVDisplayLinkSetCurrentCGDisplay(void *link,uint32_t display){if(!link || display!=1)return -6661;Value(link).display=display;return 0;}
uint32_t CVDisplayLinkGetCurrentCGDisplay(void *link){return link?Value(link).display:0;}
int32_t CVDisplayLinkSetOutputCallback(void *link,OutputCallback callback,void *context){if(!link || !callback)return -6661;Value(link).callback=callback;Value(link).context=context;return 0;}
int32_t CVDisplayLinkStart(void *value){if(!value)return -6661;StrayDisplayLink *link=Value(value);if(!link.callback)return -6661;
    @synchronized(link){if(link.running)return 0;link.running=YES;
        link.ready=dispatch_semaphore_create(0);link.finished=dispatch_semaphore_create(0);
        link.worker=[[NSThread alloc]initWithTarget:link selector:@selector(runDisplayThread) object:nil];
        link.worker.name=@"BIGWALK CVDisplayLink";[link.worker start];}
    if(dispatch_semaphore_wait(link.ready,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))){link.running=NO;return -6660;}return 0;
}
int32_t CVDisplayLinkStop(void *value){if(!value)return -6661;StrayDisplayLink *link=Value(value);
    if(!link.running)return 0;link.running=NO;
    if(NSThread.currentThread!=link.worker && dispatch_semaphore_wait(link.finished,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC)))return -6660;
    return 0;}
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(void *value){if(!value)return 0;CADisplayLink *link=Value(value).nativeLink;return link.duration?:1.0/MAX(1,UIScreen.mainScreen.maximumFramesPerSecond);}
void CVDisplayLinkRelease(void *link){if(link){CVDisplayLinkStop(link);CFRelease(link);}}
