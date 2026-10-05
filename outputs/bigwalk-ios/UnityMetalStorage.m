#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdio.h>
#include <mach/mach.h>

static uint64_t PhysicalFootprint(void) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS
        ? info.phys_footprint : 0;
}

@interface NSObject (UnityNativeTextures)
- (id<MTLTexture>)unity_nativeTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
    __attribute__((objc_method_family(new)));
@end

@interface UnityTextureStorageAdapter : NSObject @end
@implementation UnityTextureStorageAdapter
- (id<MTLTexture>)unity_textureWithDescriptor:(MTLTextureDescriptor *)descriptor
    __attribute__((objc_method_family(new))) {
    if ((NSUInteger)descriptor.storageMode == 1) {
        /* Keep the guest's descriptor intact, including format, dimensions,
         * mip count and usage. Unified Shared memory supplies CPU access. */
        descriptor = [descriptor copy];
        descriptor.storageMode = MTLStorageModeShared;
        static atomic_uint translations;
        unsigned count = atomic_fetch_add(&translations, 1) + 1;
        if (count <= 32)
            fprintf(stderr, "UNITYPROBE MANAGED_TEXTURE_TO_SHARED format=%lu size=%lux%lu count=%u\n",
                    (unsigned long)descriptor.pixelFormat, (unsigned long)descriptor.width,
                    (unsigned long)descriptor.height, count);
    }
    id<MTLTexture> texture = [self unity_nativeTextureWithDescriptor:descriptor];
    static atomic_uint allocations;
    unsigned sequence = atomic_fetch_add(&allocations, 1) + 1;
    if (sequence <= 48 || sequence % 128 == 0 || texture.allocatedSize >= 32 * 1024 * 1024) {
        id<MTLDevice> device = (id<MTLDevice>)self;
        fprintf(stderr, "BIGWALK_TEXTURE seq=%u format=%lu type=%lu size=%lux%lux%lu mips=%lu slices=%lu storage=%lu bytes=%lu gpu_live=%lu footprint=%llu\n",
            sequence, (unsigned long)descriptor.pixelFormat, (unsigned long)descriptor.textureType,
            (unsigned long)descriptor.width, (unsigned long)descriptor.height, (unsigned long)descriptor.depth,
            (unsigned long)descriptor.mipmapLevelCount, (unsigned long)descriptor.arrayLength,
            (unsigned long)descriptor.storageMode, (unsigned long)texture.allocatedSize,
            (unsigned long)device.currentAllocatedSize, (unsigned long long)PhysicalFootprint());
    }
    return texture;
}
@end

void UnityInstallTextureStorage(id<MTLDevice> device) {
    if (!device.hasUnifiedMemory) return;
    Class cls = object_getClass(device);
    SEL native = @selector(newTextureWithDescriptor:);
    SEL saved = @selector(unity_nativeTextureWithDescriptor:);
    Method method = class_getInstanceMethod(cls, native);
    Method adapter = class_getInstanceMethod(UnityTextureStorageAdapter.class,
                                            @selector(unity_textureWithDescriptor:));
    if (!method || !adapter || !class_addMethod(cls, saved, method_getImplementation(method),
                                                method_getTypeEncoding(method))) return;
    class_replaceMethod(cls, native, method_getImplementation(adapter), method_getTypeEncoding(method));
    fprintf(stderr, "UNITYPROBE TEXTURE_STORAGE_ADAPTER class=%s\n", class_getName(cls));
}
