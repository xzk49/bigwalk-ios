#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
void BigWalkInspectAudio(void){
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--audio-output-bridge"] && ![NSBundle.mainBundle.infoDictionary[@"BigWalkIOSAudioOutput"] boolValue])return;
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *lib=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_NOLOAD);if(!lib)return;
    void *(*domain)(void)=dlsym(lib,"il2cpp_domain_get");
    const void **(*assemblies)(void *,size_t *)=dlsym(lib,"il2cpp_domain_get_assemblies");
    const void *(*image)(const void *)=dlsym(lib,"il2cpp_assembly_get_image");
    const char *(*imageName)(const void *)=dlsym(lib,"il2cpp_image_get_name");
    void *(*classGet)(const void *,const char *,const char *)=dlsym(lib,"il2cpp_class_from_name");
    const void *(*method)(void *,const char *,int)=dlsym(lib,"il2cpp_class_get_method_from_name");
    void *(*invoke)(const void *,void *,void **,void **)=dlsym(lib,"il2cpp_runtime_invoke");
    void *(*unbox)(void *)=dlsym(lib,"il2cpp_object_unbox");
    if(!domain||!assemblies||!image||!imageName||!classGet||!method||!invoke||!unbox){dlclose(lib);return;}
    void *listener=NULL,*settings=NULL,*application=NULL;size_t count=0;const void **as=assemblies(domain(),&count);
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);const char *name=imageName(im);
        if(name&&!strcmp(name,"UnityEngine.AudioModule.dll")){listener=classGet(im,"UnityEngine","AudioListener");settings=classGet(im,"UnityEngine","AudioSettings");}
        if(name&&!strcmp(name,"UnityEngine.CoreModule.dll"))application=classGet(im,"UnityEngine","Application");
    }
    const void *volume=listener?method(listener,"get_volume",0):NULL,*pause=listener?method(listener,"get_pause",0):NULL;
    const void *rate=settings?method(settings,"get_outputSampleRate",0):NULL,*time=settings?method(settings,"get_dspTime",0):NULL;
    const void *focus=application?method(application,"get_isFocused",0):NULL;
    __block unsigned n=0;
    [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer){
        void *e=NULL,*v=volume?invoke(volume,NULL,NULL,&e):NULL;float gain=v&&!e?*(float *)unbox(v):-1;
        e=NULL;v=pause?invoke(pause,NULL,NULL,&e):NULL;int paused=v&&!e?*(bool *)unbox(v):-1;
        e=NULL;v=rate?invoke(rate,NULL,NULL,&e):NULL;int hz=v&&!e?*(int *)unbox(v):-1;
        e=NULL;v=time?invoke(time,NULL,NULL,&e):NULL;double dsp=v&&!e?*(double *)unbox(v):-1;
        e=NULL;v=focus?invoke(focus,NULL,NULL,&e):NULL;int active=v&&!e?*(bool *)unbox(v):-1;
        fprintf(stderr,"BIGWALK_AUDIO unity volume=%.3f paused=%d output_rate=%d dsp_time=%.3f focused=%d\n",gain,paused,hz,dsp,active);
        if(++n>=12)[timer invalidate];
    }];dlclose(lib);
}
