#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

typedef struct {UInt32 selector,scope,element;} GuestAudioAddress;
static void *HAL;
static BOOL Enabled;
static void Trace(const char *call,UInt32 object,UInt32 selector,UInt32 scope,UInt32 size,OSStatus status){
    if(!Enabled)return;
    char s[5]={(selector>>24)&255,(selector>>16)&255,(selector>>8)&255,selector&255,0};
    fprintf(stderr,"BIGWALK_AUDIO %s object=%u selector=%s scope=%08x size=%u status=%d\n",call,object,s,scope,size,(int)status);
}
OSStatus AudioHardwareGetPropertyInfo(UInt32 selector,UInt32 *size,Boolean *writable){
    OSStatus (*fn)(UInt32,UInt32 *,Boolean *)=dlsym(HAL,"AudioHardwareGetPropertyInfo");
    OSStatus r=fn?fn(selector,size,writable):-1;Trace("hardware_info",1,selector,0,size?*size:0,r);return r;
}
OSStatus AudioHardwareGetProperty(UInt32 selector,UInt32 *size,void *data){
    OSStatus (*fn)(UInt32,UInt32 *,void *)=dlsym(HAL,"AudioHardwareGetProperty");
    OSStatus r=fn?fn(selector,size,data):-1;Trace("hardware_get",1,selector,0,size?*size:0,r);return r;
}
OSStatus AudioDeviceGetPropertyInfo(UInt32 object,UInt32 channel,Boolean input,UInt32 selector,UInt32 *size,Boolean *writable){
    OSStatus (*fn)(UInt32,UInt32,Boolean,UInt32,UInt32 *,Boolean *)=dlsym(HAL,"AudioDeviceGetPropertyInfo");
    OSStatus r=fn?fn(object,channel,input,selector,size,writable):-1;Trace("device_info",object,selector,input,size?*size:0,r);return r;
}
OSStatus AudioDeviceGetProperty(UInt32 object,UInt32 channel,Boolean input,UInt32 selector,UInt32 *size,void *data){
    OSStatus (*fn)(UInt32,UInt32,Boolean,UInt32,UInt32 *,void *)=dlsym(HAL,"AudioDeviceGetProperty");
    UInt32 capacity=size?*size:0;
    OSStatus r=fn?fn(object,channel,input,selector,size,data):-1;
    // The legacy Mac name selector is absent on iOS's otherwise valid HAL
    // route object. Return the actual active route name with the old C ABI.
    if(Enabled&&r&&selector=='name'&&size&&data&&capacity){
        AVAudioSession *session=AVAudioSession.sharedInstance;
        NSArray *ports=input?session.currentRoute.inputs:session.currentRoute.outputs;
        NSString *name=[ports.firstObject portName];
        if(name.length){NSData *bytes=[name dataUsingEncoding:NSUTF8StringEncoding];
            UInt32 required=(UInt32)bytes.length+1;
            if(capacity>=required){memcpy(data,bytes.bytes,bytes.length);((char *)data)[bytes.length]=0;*size=required;r=0;}
        }
    }
    Trace("device_get",object,selector,input,size?*size:0,r);return r;
}
OSStatus AudioObjectGetPropertyDataSize(UInt32 object,const GuestAudioAddress *a,UInt32 qsize,const void *q,UInt32 *size){
    OSStatus (*fn)(UInt32,const GuestAudioAddress *,UInt32,const void *,UInt32 *)=dlsym(HAL,"AudioObjectGetPropertyDataSize");
    OSStatus r=fn?fn(object,a,qsize,q,size):-1;Trace("object_size",object,a?a->selector:0,a?a->scope:0,size?*size:0,r);return r;
}
OSStatus AudioObjectGetPropertyData(UInt32 object,const GuestAudioAddress *a,UInt32 qsize,const void *q,UInt32 *size,void *data){
    OSStatus (*fn)(UInt32,const GuestAudioAddress *,UInt32,const void *,UInt32 *,void *)=dlsym(HAL,"AudioObjectGetPropertyData");
    OSStatus r=fn?fn(object,a,qsize,q,size,data):-1;Trace("object_get",object,a?a->selector:0,a?a->scope:0,size?*size:0,r);return r;
}
__attribute__((constructor))static void SetupBigWalkAudioHAL(void){
    HAL=dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio",RTLD_NOW|RTLD_LOCAL);
    Enabled=[NSProcessInfo.processInfo.arguments containsObject:@"--audio-output-bridge"] || [NSBundle.mainBundle.infoDictionary[@"BigWalkIOSAudioOutput"] boolValue];
    if(!Enabled)return;
    AVAudioSession *s=AVAudioSession.sharedInstance;NSError *error=nil;
    BOOL ok=[s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    if(ok)ok=[s setPreferredSampleRate:48000 error:&error];
    if(ok)ok=[s setActive:YES error:&error];
    fprintf(stderr,"BIGWALK_AUDIO session active=%d rate=%.0f channels=%lu route=%s error=%s\n",ok,s.sampleRate,(unsigned long)s.outputNumberOfChannels,s.currentRoute.description.UTF8String,error.description.UTF8String?:"none");
}
