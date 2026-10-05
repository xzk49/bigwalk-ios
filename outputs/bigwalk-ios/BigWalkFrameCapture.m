#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#include <stdatomic.h>

static id<CAMetalDrawable> (*NativeNext)(id, SEL);
static void (*NativePresent)(id, SEL, id<MTLDrawable>);
static void (*NativePresentAtTime)(id, SEL, id<MTLDrawable>, CFTimeInterval);
static void (*NativePresentAfter)(id, SEL, id<MTLDrawable>, CFTimeInterval);
static char FrameKey;
static atomic_uint Frames;

static void ReadFrame(id<MTLCommandBuffer> command, id<CAMetalDrawable> drawable) {
    NSNumber *number = objc_getAssociatedObject(drawable, &FrameKey);
    unsigned frame = number.unsignedIntValue;
    if (frame != 1 && frame != 30) return;
    objc_setAssociatedObject(drawable, &FrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id<MTLTexture> texture = drawable.texture;
    NSUInteger width = texture.width, height = texture.height;
    if (texture.framebufferOnly || !width || !height || width > 4096 || height > 4096 ||
        (texture.pixelFormat != MTLPixelFormatBGRA8Unorm && texture.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB)) {
        fprintf(stderr, "BIGWALK_FRAME unavailable frame=%u format=%lu\n", frame, (unsigned long)texture.pixelFormat); return;
    }
    NSUInteger stride = (width * 4 + 255) & ~(NSUInteger)255;
    id<MTLBuffer> pixels = [texture.device newBufferWithLength:stride * height options:MTLResourceStorageModeShared];
    if (!pixels) return;
    id<MTLBlitCommandEncoder> encoder = [command blitCommandEncoder];
    [encoder copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                 sourceSize:MTLSizeMake(width,height,1) toBuffer:pixels destinationOffset:0
     destinationBytesPerRow:stride destinationBytesPerImage:stride * height];
    [encoder endEncoding];
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        if (completed.status != MTLCommandBufferStatusCompleted) {
            fprintf(stderr, "BIGWALK_FRAME gpu_error frame=%u\n", frame); return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ @autoreleasepool {
            CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(pixels.contents, width, height, 8, stride, color,
                                                        kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
            CGImageRef image = context ? CGBitmapContextCreateImage(context) : NULL;
            NSData *png = image ? UIImagePNGRepresentation([UIImage imageWithCGImage:image]) : nil;
            NSString *name = [NSString stringWithFormat:@"BigWalkFrame-%06u.png", frame];
            NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:name];
            BOOL saved = [png writeToFile:path atomically:YES];
            fprintf(stderr, "BIGWALK_FRAME saved=%d frame=%u size=%lux%lu\n", saved, frame, (unsigned long)width, (unsigned long)height);
            if (image) CGImageRelease(image);
            if (context) CGContextRelease(context);
            if (color) CGColorSpaceRelease(color);
        }});
    }];
}
static void Present(id command, SEL selector, id<MTLDrawable> drawable) {
    ReadFrame(command, (id)drawable); NativePresent(command, selector, drawable);
}
static void PresentAtTime(id command, SEL selector, id<MTLDrawable> drawable, CFTimeInterval time) {
    ReadFrame(command, (id)drawable); NativePresentAtTime(command, selector, drawable, time);
}
static void PresentAfter(id command, SEL selector, id<MTLDrawable> drawable, CFTimeInterval time) {
    ReadFrame(command, (id)drawable); NativePresentAfter(command, selector, drawable, time);
}
static id<CAMetalDrawable> Next(id layer, SEL selector) {
    if (![((CAMetalLayer *)layer).name isEqualToString:@"StrayGuestMetalLayer"])
        return NativeNext(layer, selector);
    ((CAMetalLayer *)layer).framebufferOnly = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id<MTLCommandQueue> queue = [((CAMetalLayer *)layer).device newCommandQueue];
        Class cls = object_getClass([queue commandBuffer]);
        if (!cls) return;
        Method method = class_getInstanceMethod(cls, @selector(presentDrawable:));
        if (method) { NativePresent = (void *)method_getImplementation(method); class_replaceMethod(cls, @selector(presentDrawable:), (IMP)Present, method_getTypeEncoding(method)); }
        method = class_getInstanceMethod(cls, @selector(presentDrawable:atTime:));
        if (method) { NativePresentAtTime = (void *)method_getImplementation(method); class_replaceMethod(cls, @selector(presentDrawable:atTime:), (IMP)PresentAtTime, method_getTypeEncoding(method)); }
        method = class_getInstanceMethod(cls, @selector(presentDrawable:afterMinimumDuration:));
        if (method) { NativePresentAfter = (void *)method_getImplementation(method); class_replaceMethod(cls, @selector(presentDrawable:afterMinimumDuration:), (IMP)PresentAfter, method_getTypeEncoding(method)); }
        fprintf(stderr, "BIGWALK_FRAME observer_class=%s\n", class_getName(cls));
    });
    id<CAMetalDrawable> drawable = NativeNext(layer, selector);
    if (drawable) objc_setAssociatedObject(drawable, &FrameKey, @(atomic_fetch_add(&Frames, 1) + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return drawable;
}
__attribute__((constructor)) static void InstallFrameCapture(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--capture-frame"]) return;
    Method method = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
    NativeNext = (void *)method_getImplementation(method);
    class_replaceMethod(CAMetalLayer.class, @selector(nextDrawable), (IMP)Next, method_getTypeEncoding(method));
}
