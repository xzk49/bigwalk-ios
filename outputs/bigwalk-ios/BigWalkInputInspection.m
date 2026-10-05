#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

// Read a few serialization types, without enumerating or initializing the
// hundreds of thousands of objects in the world.
void BigWalkInspectInputConfig(void) {
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--inspect-input"])return;
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *lib=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_NOLOAD);
    if(!lib)return;
    void *(*domain)(void)=dlsym(lib,"il2cpp_domain_get");
    const void **(*assemblies)(void *,size_t *)=dlsym(lib,"il2cpp_domain_get_assemblies");
    const void *(*image)(const void *)=dlsym(lib,"il2cpp_assembly_get_image");
    const char *(*imageName)(const void *)=dlsym(lib,"il2cpp_image_get_name");
    void *(*classGet)(const void *,const char *,const char *)=dlsym(lib,"il2cpp_class_from_name");
    void *(*fields)(void *,void **)=dlsym(lib,"il2cpp_class_get_fields");
    const char *(*fieldName)(void *)=dlsym(lib,"il2cpp_field_get_name");
    void *(*fieldType)(void *)=dlsym(lib,"il2cpp_field_get_type");
    void *(*classFromType)(void *)=dlsym(lib,"il2cpp_class_from_type");
    char *(*typeName)(void *)=dlsym(lib,"il2cpp_type_get_name");
    uint32_t (*flags)(void *)=dlsym(lib,"il2cpp_field_get_flags");
    void *(*parent)(void *)=dlsym(lib,"il2cpp_class_get_parent");
    const char *(*className)(void *)=dlsym(lib,"il2cpp_class_get_name");
    void (*release)(void *)=dlsym(lib,"il2cpp_free");
    if(!domain||!assemblies||!image||!imageName||!classGet||!fields||!fieldName||!fieldType||!classFromType||!typeName||!flags||!parent||!className||!release){dlclose(lib);return;}
    size_t count=0;const void **as=assemblies(domain(),&count);void *config=NULL;
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);const char *name=imageName(im);
        if(name&&!strcmp(name,"Rewired_Core.dll")){config=classGet(im,"Rewired.Data","ConfigVars");break;}}
    if(config){
        NSMutableArray<NSValue *> *types=[NSMutableArray arrayWithObject:[NSValue valueWithPointer:config]];
        void *it=NULL,*f=NULL;
        while((f=fields(config,&it))){const char *name=fieldName(f);
            if(!strcmp(name,"platformVars_windowsStandalone")||!strcmp(name,"platformVars_linuxStandalone")||!strcmp(name,"platformVars_osxStandalone"))
                [types addObject:[NSValue valueWithPointer:classFromType(fieldType(f))]];}
        for(NSValue *value in types){
            fprintf(stderr,"BIGWALK_INPUT_TYPE root=%s\n",className(value.pointerValue));
            for(void *c=value.pointerValue;c&&strcmp(className(c),"Object");c=parent(c)){
                fprintf(stderr,"BIGWALK_INPUT_TYPE class=%s\n",className(c));it=NULL;
                while((f=fields(c,&it))){char *name=typeName(fieldType(f));
                    fprintf(stderr,"BIGWALK_INPUT_FIELD name=%s type=%s flags=%x\n",fieldName(f),name?name:"?",flags(f));
                    if(name)release(name);}
            }
        }
    }
    void *(*objectClass)(void *)=dlsym(lib,"il2cpp_object_get_class");
    const void *(*method)(void *,const char *,int)=dlsym(lib,"il2cpp_class_get_method_from_name");
    void *(*invoke)(const void *,void *,void **,void **)=dlsym(lib,"il2cpp_runtime_invoke");
    void *(*unbox)(void *)=dlsym(lib,"il2cpp_object_unbox");
    void *reInput=NULL;
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);const char *name=imageName(im);
        if(name&&!strcmp(name,"Rewired_Core.dll")){reInput=classGet(im,"Rewired","ReInput");break;}}
    const void *screenResolutions=NULL;
    size_t (*arrayLength)(void *)=dlsym(lib,"il2cpp_array_length");
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);const char *name=imageName(im);
        if(name&&!strcmp(name,"UnityEngine.CoreModule.dll")){void *screen=classGet(im,"UnityEngine","Screen");
            if(screen&&method)screenResolutions=method(screen,"get_resolutions",0);break;}}
    if(reInput&&objectClass&&method&&invoke&&unbox){
        const void *ready=method(reInput,"get_isReady",0),*getConfig=method(reInput,"get_configuration",0);
        __block unsigned checks=0;
        [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer){
            if(checks==0&&screenResolutions&&arrayLength){
                void *error=NULL;void *modes=invoke(screenResolutions,NULL,NULL,&error);
                fprintf(stderr,"BIGWALK_DISPLAY original_resolution_enumeration count=%zu exception=%d\n",modes&&!error?arrayLength(modes):0,error!=NULL);
            }
            void *exception=NULL,*box=ready?invoke(ready,NULL,NULL,&exception):NULL;
            BOOL isReady=box&&!exception?*(bool *)unbox(box):NO;
            void *configObject=getConfig?invoke(getConfig,NULL,NULL,&exception):NULL;
            BOOL apple=NO;
            if(configObject&&!exception){const void *getter=method(objectClass(configObject),"get_useAppleGameControllerFramework",0);
                box=getter?invoke(getter,configObject,NULL,&exception):NULL;apple=box&&!exception?*(bool *)unbox(box):NO;}
            GCController *controller=GCController.controllers.firstObject;
            fprintf(stderr,"BIGWALK_INPUT_STATUS ready=%d apple_backend=%d controllers=%lu A_handler=%d leftX_handler=%d\n",
                    isReady,apple,(unsigned long)GCController.controllers.count,controller.extendedGamepad.buttonA.valueChangedHandler!=nil,
                    controller.extendedGamepad.leftThumbstick.xAxis.valueChangedHandler!=nil);
            if(++checks>=6)[timer invalidate];
        }];
    }
    dlclose(lib);
}
