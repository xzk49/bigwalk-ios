#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

// Use the game's exported IL2CPP reflection API and genuine QualitySettings
// property. Texture descriptors and uploaded data must retain matching layouts.
void BigWalkApplyTextureProfile(void) {
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger index = [arguments indexOfObject:@"--texture-mip-limit"];
    NSString *value = [NSBundle.mainBundle.infoDictionary[@"BigWalkTextureMipmapLimit"] description];
    if (index != NSNotFound && index + 1 < arguments.count) value = arguments[index + 1];
    if (![@[@"0", @"1", @"2", @"3"] containsObject:value]) return;
    int32_t limit = value.intValue;
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_NOLOAD);
    if (!library) { fprintf(stderr, "BIGWALK_QUALITY unavailable=GameAssembly\n"); return; }
    void *(*domainGet)(void) = dlsym(library, "il2cpp_domain_get");
    const void **(*assembliesGet)(void *, size_t *) = dlsym(library, "il2cpp_domain_get_assemblies");
    const void *(*imageGet)(const void *) = dlsym(library, "il2cpp_assembly_get_image");
    const char *(*imageName)(const void *) = dlsym(library, "il2cpp_image_get_name");
    void *(*classGet)(const void *, const char *, const char *) = dlsym(library, "il2cpp_class_from_name");
    const void *(*methodGet)(void *, const char *, int) = dlsym(library, "il2cpp_class_get_method_from_name");
    void *(*invoke)(const void *, void *, void **, void **) = dlsym(library, "il2cpp_runtime_invoke");
    void *(*unbox)(void *) = dlsym(library, "il2cpp_object_unbox");
    if (!domainGet || !assembliesGet || !imageGet || !imageName || !classGet || !methodGet || !invoke || !unbox) {
        fprintf(stderr, "BIGWALK_QUALITY unavailable=reflection_exports\n"); dlclose(library); return;
    }
    size_t count = 0;
    void *domain = domainGet();
    const void **assemblies = domain ? assembliesGet(domain, &count) : NULL;
    void *quality = NULL;
    for (size_t i = 0; assemblies && i < count; ++i) {
        const void *image = imageGet(assemblies[i]);
        const char *name = imageName(image);
        if (name && strcmp(name, "UnityEngine.CoreModule.dll") == 0) {
            quality = classGet(image, "UnityEngine", "QualitySettings"); break;
        }
    }
    const void *setter = quality ? methodGet(quality, "set_globalTextureMipmapLimit", 1) : NULL;
    const void *getter = quality ? methodGet(quality, "get_globalTextureMipmapLimit", 0) : NULL;
    if (!setter || !getter) {
        // This release strips the managed accessors. The corresponding native
        // icall names are still present in the audited UnityPlayer string table.
        void *(*resolve)(const char *) = dlsym(library, "il2cpp_resolve_icall");
        void (*nativeSet)(int32_t) = resolve ? resolve("UnityEngine.QualitySettings::set_globalTextureMipmapLimit") : NULL;
        int32_t (*nativeGet)(void) = resolve ? resolve("UnityEngine.QualitySettings::get_globalTextureMipmapLimit") : NULL;
        if (nativeSet && nativeGet) {
            int32_t before = nativeGet();
            nativeSet(limit);
            fprintf(stderr, "BIGWALK_QUALITY texture_mip_limit requested=%d before=%d actual=%d route=native_icall\n",
                    limit, before, nativeGet());
        } else {
            fprintf(stderr, "BIGWALK_QUALITY unavailable=QualitySettings_icalls assemblies=%zu\n", count);
        }
        dlclose(library); return;
    }
    void *exception = NULL;
    void *parameters[] = {&limit};
    invoke(setter, NULL, parameters, &exception);
    if (exception) { fprintf(stderr, "BIGWALK_QUALITY setter_exception\n"); dlclose(library); return; }
    void *boxed = invoke(getter, NULL, NULL, &exception);
    int32_t actual = -1;
    if (boxed && !exception) memcpy(&actual, unbox(boxed), sizeof actual);
    fprintf(stderr, "BIGWALK_QUALITY texture_mip_limit requested=%d actual=%d\n", limit, actual);
    dlclose(library);
}
