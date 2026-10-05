#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVFAudio.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <math.h>

static void *Toolbox,*Core;
static BOOL Enabled;
static NSMutableSet *Translated;
static NSMutableDictionary *Units;
static atomic_ullong Callbacks,Nonzero,NonzeroBytes;
static atomic_uint Peak,Errors;
static dispatch_source_t Meter;
@interface BigWalkAudioContext:NSObject { @public AURenderCallbackStruct callback; AudioStreamBasicDescription format; }
@property(nonatomic) BOOL translated;
@end
@implementation BigWalkAudioContext @end
static BigWalkAudioContext *Context(AudioUnit unit){@synchronized(Units){return Units[[NSValue valueWithPointer:unit]];}}
AudioComponent AudioComponentFindNext(AudioComponent previous,const AudioComponentDescription *description){
    AudioComponent (*fn)(AudioComponent,const AudioComponentDescription *)=dlsym(Toolbox,"AudioComponentFindNext");
    if(!Enabled)return fn?fn(previous,description):NULL;
    AudioComponentDescription d=description?*description:(AudioComponentDescription){0};
    BOOL translate=d.componentType==kAudioUnitType_Output&&(d.componentSubType=='ahal'||d.componentSubType=='def '||d.componentSubType=='sys ');
    AudioComponent result=fn?fn(previous,description):NULL;
    if(!result&&translate){d.componentSubType=kAudioUnitSubType_RemoteIO;result=fn(previous,&d);
        if(result)@synchronized(Translated){[Translated addObject:[NSValue valueWithPointer:result]];}}
    fprintf(stderr,"BIGWALK_AUDIO component type=%08x requested=%08x translated=%d found=%d\n",d.componentType,description?description->componentSubType:0,translate&&result!=NULL,result!=NULL);return result;
}
OSStatus AudioComponentInstanceNew(AudioComponent component,AudioComponentInstance *unit){
    OSStatus (*fn)(AudioComponent,AudioComponentInstance *)=dlsym(Toolbox,"AudioComponentInstanceNew");
    OSStatus r=fn(component,unit);if(!Enabled)return r;
    if(!r&&unit&&*unit){BigWalkAudioContext *c=[BigWalkAudioContext new];
        @synchronized(Translated){c.translated=[Translated containsObject:[NSValue valueWithPointer:component]];}
        @synchronized(Units){Units[[NSValue valueWithPointer:*unit]]=c;}}
    fprintf(stderr,"BIGWALK_AUDIO unit_new status=%d\n",(int)r);return r;
}
static OSStatus Render(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *buffers){
    __unsafe_unretained BigWalkAudioContext *c=(__bridge BigWalkAudioContext *)context;
    OSStatus r=c->callback.inputProc(c->callback.inputProcRefCon,flags,time,bus,frames,buffers);
    atomic_fetch_add_explicit(&Callbacks,1,memory_order_relaxed);
    if(r)atomic_fetch_add_explicit(&Errors,1,memory_order_relaxed);
    float peak=0;
    if(!r&&buffers)for(UInt32 b=0;b<buffers->mNumberBuffers;b++){
        const unsigned char *bytes=buffers->mBuffers[b].mData;
        if(bytes)for(UInt32 i=0;i<buffers->mBuffers[b].mDataByteSize;i++)if(bytes[i]){atomic_fetch_add_explicit(&NonzeroBytes,1,memory_order_relaxed);break;}
    }
    if(!r&&c->format.mFormatID==kAudioFormatLinearPCM&&(c->format.mFormatFlags&kAudioFormatFlagIsFloat)&&c->format.mBitsPerChannel==32&&buffers){
        for(UInt32 b=0;b<buffers->mNumberBuffers;b++){
            const float *samples=buffers->mBuffers[b].mData;
            if(samples)for(UInt32 i=0;i<buffers->mBuffers[b].mDataByteSize/sizeof(float);i++){
                float v=fabsf(samples[i]);if(isfinite(v)&&v>peak)peak=v;
            }
        }
    }
    if(peak>0.00001f)atomic_fetch_add_explicit(&Nonzero,1,memory_order_relaxed);
    unsigned value=(unsigned)(fminf(peak,4)*1000000),old=atomic_load_explicit(&Peak,memory_order_relaxed);
    while(value>old&&!atomic_compare_exchange_weak_explicit(&Peak,&old,value,memory_order_relaxed,memory_order_relaxed)){}
    return r;
}
static UInt32 DefaultOutput(void){
    OSStatus (*fn)(UInt32,UInt32 *,void *)=dlsym(Core,"AudioHardwareGetProperty");
    UInt32 value=0,size=4;return fn&&fn('dOut',&size,&value)==0?value:0;
}
OSStatus AudioUnitSetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size){
    OSStatus (*fn)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,const void *,UInt32)=dlsym(Toolbox,"AudioUnitSetProperty");
    if(!Enabled)return fn(unit,property,scope,element,data,size);
    AudioStreamBasicDescription normalized;
    if(property==kAudioUnitProperty_StreamFormat&&data&&size==sizeof(normalized)){
        normalized=*(const AudioStreamBasicDescription *)data;
        if(!isfinite(normalized.mSampleRate)||normalized.mSampleRate<=0){
            double rate=AVAudioSession.sharedInstance.sampleRate;
            if(rate>0){normalized.mSampleRate=rate;data=&normalized;}
        }
    }
    BigWalkAudioContext *c=Context(unit);
    OSStatus r;
    if(c&&property==kAudioUnitProperty_SetRenderCallback&&data&&size==sizeof(AURenderCallbackStruct)){
        c->callback=*(const AURenderCallbackStruct *)data;
        AURenderCallbackStruct wrapped={Render,(__bridge void *)c};r=fn(unit,property,scope,element,&wrapped,sizeof(wrapped));
    }else r=fn(unit,property,scope,element,data,size);
    if(r&&c.translated&&property==2000&&data&&size==4&&*(const UInt32 *)data==DefaultOutput())r=0;
    if(!r&&c&&property==kAudioUnitProperty_StreamFormat&&data&&size==sizeof(AudioStreamBasicDescription)&&scope==kAudioUnitScope_Input&&element==0){
        c->format=*(const AudioStreamBasicDescription *)data;
        fprintf(stderr,"BIGWALK_AUDIO output_format rate=%.0f flags=%x bits=%u channels=%u bytesPerFrame=%u\n",c->format.mSampleRate,c->format.mFormatFlags,c->format.mBitsPerChannel,c->format.mChannelsPerFrame,c->format.mBytesPerFrame);
    }
    fprintf(stderr,"BIGWALK_AUDIO unit_set property=%u scope=%u element=%u size=%u status=%d\n",property,scope,element,size,(int)r);return r;
}
OSStatus AudioUnitGetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,void *data,UInt32 *size){
    OSStatus (*fn)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,void *,UInt32 *)=dlsym(Toolbox,"AudioUnitGetProperty");
    if(!Enabled)return fn(unit,property,scope,element,data,size);
    UInt32 capacity=size?*size:0;OSStatus r=fn(unit,property,scope,element,data,size);
    if(!r&&property==kAudioUnitProperty_StreamFormat&&data&&size&&*size==sizeof(AudioStreamBasicDescription)){
        AudioStreamBasicDescription *format=data;
        if(!isfinite(format->mSampleRate)||format->mSampleRate<=0){
            double rate=AVAudioSession.sharedInstance.sampleRate;
            if(rate>0){format->mSampleRate=rate;fprintf(stderr,"BIGWALK_AUDIO stream_rate_from_active_session=%.0f\n",rate);}
        }
    }
    if(r&&Context(unit).translated&&property==2000&&size&&data&&capacity>=4){UInt32 output=DefaultOutput();if(output){*(UInt32 *)data=output;*size=4;r=0;}}
    fprintf(stderr,"BIGWALK_AUDIO unit_get property=%u scope=%u element=%u size=%u status=%d\n",property,scope,element,size?*size:0,(int)r);return r;
}
OSStatus AudioOutputUnitStart(AudioUnit unit){
    OSStatus (*fn)(AudioUnit)=dlsym(Toolbox,"AudioOutputUnitStart");OSStatus r=fn(unit);if(!Enabled)return r;
    fprintf(stderr,"BIGWALK_AUDIO unit_start status=%d\n",(int)r);return r;
}
OSStatus AudioComponentInstanceDispose(AudioComponentInstance unit){
    OSStatus (*fn)(AudioComponentInstance)=dlsym(Toolbox,"AudioComponentInstanceDispose");OSStatus r=fn(unit);if(!Enabled)return r;
    if(!r)@synchronized(Units){[Units removeObjectForKey:[NSValue valueWithPointer:unit]];}return r;
}
__attribute__((constructor))static void SetupUnits(void){
    Toolbox=dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW|RTLD_LOCAL);
    Core=dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio",RTLD_NOW|RTLD_LOCAL);
    Enabled=[NSProcessInfo.processInfo.arguments containsObject:@"--audio-output-bridge"] || [NSBundle.mainBundle.infoDictionary[@"BigWalkIOSAudioOutput"] boolValue];
    if(!Enabled)return;
    Translated=[NSMutableSet new];Units=[NSMutableDictionary new];
    Meter=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
    dispatch_source_set_timer(Meter,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),10*NSEC_PER_SEC,NSEC_PER_SEC);
    dispatch_source_set_event_handler(Meter,^{fprintf(stderr,"BIGWALK_AUDIO pcm callbacks=%llu nonzero=%llu nonzero_buffers=%llu peak=%.6f errors=%u\n",atomic_load(&Callbacks),atomic_load(&Nonzero),atomic_load(&NonzeroBytes),atomic_exchange(&Peak,0)/1000000.0,atomic_load(&Errors));});dispatch_resume(Meter);
}
