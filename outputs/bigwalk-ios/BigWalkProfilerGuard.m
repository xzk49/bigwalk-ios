#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdatomic.h>

typedef void (*SetMetadata)(void *,int32_t,void *,uint8_t,uint8_t);
static SetMetadata NativeSetMetadata;
static atomic_uint NullMarkers;
static void SetMetadataChecked(void *marker,int32_t index,void *name,uint8_t type,uint8_t unit) {
    // The world-load crash writes marker+0x18 when marker is NULL. Metadata
    // belongs to optional profiler instrumentation, never gameplay or auth.
    if(!marker){
        unsigned count=atomic_fetch_add(&NullMarkers,1)+1;
        if(count<=8)fprintf(stderr,"BIGWALK_PROFILER null_metadata_marker_skipped=%u index=%d\n",count,index);
        return;
    }
    NativeSetMetadata(marker,index,name,type,unit);
}
void BigWalkInstallProfilerGuard(void) {
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *library=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_NOLOAD);
    void *(*resolve)(const char *)=library?dlsym(library,"il2cpp_resolve_icall"):NULL;
    void (*add)(const char *,void *)=library?dlsym(library,"il2cpp_add_internal_call"):NULL;
    const char *name="Unity.Profiling.LowLevel.Unsafe.ProfilerUnsafeUtility::SetMarkerMetadata_Injected(System.IntPtr,System.Int32,UnityEngine.Bindings.ManagedSpanWrapper&,System.Byte,System.Byte)";
    if(resolve && add){
        NativeSetMetadata=resolve(name);
        if(NativeSetMetadata){
            add(name,(void *)SetMetadataChecked);
            fprintf(stderr,"BIGWALK_PROFILER guard_registered=%d\n",resolve(name)==(void *)SetMetadataChecked);
        }
    }
    if(library)dlclose(library);
}
