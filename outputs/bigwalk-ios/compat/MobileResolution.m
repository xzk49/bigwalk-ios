#import "MobileResolution.h"
#import "AppKitBridge.h"
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <string.h>
#include <mach/mach.h>

static const int32_t Tiers[]={720,900,1080,1440};
static NSString *const TierKey=@"BigWalkMobileResolutionShortEdge";
static BOOL Ready;
static CGSize LastViewport;
static NSUInteger ResizeGeneration;
static const void *SetResolution, *GetWidth, *GetHeight, *GetResolutions;
static void *(*Invoke)(const void *,void *,void **,void **);
static void *(*Unbox)(void *);
static size_t (*ArrayLength)(void *);
static NSMutableArray *ProbeResults;
static BOOL Probing;
static void (*NativeDrawableSize)(id,SEL,CGSize);
static int32_t ReadInt(const void *method);
static BWRenderSize Requested(int32_t tier);
typedef struct {int32_t width,height;uint32_t numerator,denominator;} BWResolutionValue;
typedef struct {void *data;int32_t size,updateFlags;} BWBlittableArray;
static uint32_t RenderRefreshRate;
static void (*NativeResolutions)(BWBlittableArray *);
static void RenderResolutions(BWBlittableArray *result) {
    if(!result)return;
    // Audited Unmarshal<Resolution> copies flag 1 raw data into a genuine
    // managed array without freeing that data. Each calling thread owns its
    // buffer, and the binding copies it before returning to game code.
    static _Thread_local BWResolutionValue values[4];
    for(unsigned i=0;i<4;i++){BWRenderSize size=Requested(Tiers[i]);
        if(!size.width){NativeResolutions(result);return;}
        values[i]=(BWResolutionValue){size.width,size.height,RenderRefreshRate,1};}
    *result=(BWBlittableArray){values,4,1};
}

static void InstallRenderModeEnumeration(void *library,const void *coreImage) {
    void *(*classGet)(const void *,const char *,const char *)=dlsym(library,"il2cpp_class_from_name");
    const void *(*methodGet)(void *,const char *,int)=dlsym(library,"il2cpp_class_get_method_from_name");
    const void *(*param)(const void *,uint32_t)=dlsym(library,"il2cpp_method_get_param");
    const void *(*returns)(const void *)=dlsym(library,"il2cpp_method_get_return_type");
    char *(*typeName)(const void *)=dlsym(library,"il2cpp_type_get_name");
    void (*release)(void *)=dlsym(library,"il2cpp_free");
    void *(*fields)(void *,void **)=dlsym(library,"il2cpp_class_get_fields");
    const char *(*fieldName)(void *)=dlsym(library,"il2cpp_field_get_name");
    int32_t (*fieldOffset)(void *)=dlsym(library,"il2cpp_field_get_offset");
    int32_t (*valueSize)(void *,uint32_t *)=dlsym(library,"il2cpp_class_value_size");
    void *(*resolve)(const char *)=dlsym(library,"il2cpp_resolve_icall");
    void (*add)(const char *,void *)=dlsym(library,"il2cpp_add_internal_call");
    if(!classGet||!methodGet||!param||!returns||!typeName||!release||!fields||!fieldName||!fieldOffset||!valueSize||!resolve||!add)return;
    void *screen=classGet(coreImage,"UnityEngine","Screen"),*wrapper=classGet(coreImage,"UnityEngine.Bindings","BlittableArrayWrapper");
    const void *method=screen?methodGet(screen,"get_resolutions_Injected",1):NULL;if(!method||!wrapper)return;
    char *parameter=typeName(param(method,0)),*returned=typeName(returns(method));
    BOOL signature=parameter&&!strcmp(parameter,"UnityEngine.Bindings.BlittableArrayWrapper&")&&returned&&!strcmp(returned,"System.Void");
    if(parameter)release(parameter);if(returned)release(returned);uint32_t alignment;
    if(!signature||valueSize(wrapper,&alignment)!=sizeof(BWBlittableArray))return;
    unsigned matched=0;void *iterator=NULL,*field;
    while((field=fields(wrapper,&iterator))){const char *name=fieldName(field);int32_t offset=fieldOffset(field);
        if(!strcmp(name,"data")&&offset==16)matched|=1;
        if(!strcmp(name,"size")&&offset==24)matched|=2;
        if(!strcmp(name,"updateFlags")&&offset==28)matched|=4;}
    if(matched!=7)return;
    const char *name="UnityEngine.Screen::get_resolutions_Injected(UnityEngine.Bindings.BlittableArrayWrapper&)";
    NativeResolutions=resolve(name);if(!NativeResolutions)return;
    RenderRefreshRate=(uint32_t)UIScreen.mainScreen.maximumFramesPerSecond;
    add(name,(void *)RenderResolutions);
    fprintf(stderr,"BIGWALK_RESOLUTION binding_adapter_registered=%d wrapper_size=%zu modes=4\n",resolve(name)==(void *)RenderResolutions,sizeof(BWBlittableArray));
}

static void InspectRendering(void *library, const void *coreImage) {
    NSArray *arguments=NSProcessInfo.processInfo.arguments;
    BOOL qualityProbe=[arguments containsObject:@"--probe-quality-presets"];
    if(![arguments containsObject:@"--inspect-mobile-rendering"]&&![arguments containsObject:@"--probe-graphics-settings"]&&!qualityProbe)return;
    void *(*classGet)(const void *,const char *,const char *)=dlsym(library,"il2cpp_class_from_name");
    const void *(*methodGet)(void *,const char *,int)=dlsym(library,"il2cpp_class_get_method_from_name");
    const void *(*param)(const void *,uint32_t)=dlsym(library,"il2cpp_method_get_param");
    const void *(*returns)(const void *)=dlsym(library,"il2cpp_method_get_return_type");
    char *(*typeName)(const void *)=dlsym(library,"il2cpp_type_get_name");
    void (*release)(void *)=dlsym(library,"il2cpp_free");
    void *(*fields)(void *,void **)=dlsym(library,"il2cpp_class_get_fields");
    const char *(*fieldName)(void *)=dlsym(library,"il2cpp_field_get_name");
    int32_t (*fieldOffset)(void *)=dlsym(library,"il2cpp_field_get_offset");
    int32_t (*valueSize)(void *,uint32_t *)=dlsym(library,"il2cpp_class_value_size");
    NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSMutableDictionary *layout=[NSMutableDictionary new];
    if(classGet&&methodGet&&param&&returns&&typeName&&release&&fields&&fieldName&&fieldOffset&&valueSize){
        void *screen=classGet(coreImage,"UnityEngine","Screen");
        for(NSString *name in @[@"get_resolutions",@"get_resolutions_Injected"]){const void *method=methodGet(screen,name.UTF8String,[name hasSuffix:@"Injected"]?1:0);if(!method)continue;
            NSMutableDictionary *record=[NSMutableDictionary new];char *type=typeName(returns(method));if(type){record[@"returns"]=@(type);release(type);}
            if([name hasSuffix:@"Injected"]){type=typeName(param(method,0));if(type){record[@"parameter"]=@(type);release(type);}}
            void *entry=*(void *const *)method;Dl_info info;
            if(entry&&dladdr(entry,&info)&&strstr(info.dli_fname,"GameAssembly")){
                record[@"entry_rva"]=@((uintptr_t)entry-(uintptr_t)info.dli_fbase);
                record[@"code_160_bytes"]=[[NSData dataWithBytes:entry length:160]base64EncodedStringWithOptions:0];}
            layout[name]=record;
        }
        void *wrapper=classGet(coreImage,"UnityEngine.Bindings","BlittableArrayWrapper");
        if(wrapper){uint32_t alignment;layout[@"wrapper_size"]=@(valueSize(wrapper,&alignment));NSMutableArray *items=[NSMutableArray new];void *iterator=NULL,*field;
            while((field=fields(wrapper,&iterator)))[items addObject:@{@"name":@(fieldName(field)),@"offset":@(fieldOffset(field))}];layout[@"wrapper_fields"]=items;}
        [[NSJSONSerialization dataWithJSONObject:layout options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"BigWalkRenderingLayout.json"] atomically:YES];
    }
    if(![arguments containsObject:@"--probe-graphics-settings"]&&!qualityProbe)return;
    void *(*resolve)(const char *)=dlsym(library,"il2cpp_resolve_icall");
    int32_t (*getLevel)(void)=resolve?resolve("UnityEngine.QualitySettings::GetQualityLevel"):NULL;
    int32_t (*getMip)(void)=resolve?resolve("UnityEngine.QualitySettings::get_globalTextureMipmapLimit"):NULL;
    if(qualityProbe&&classGet&&methodGet&&param&&returns&&typeName&&release&&getLevel){
        void *quality=classGet(coreImage,"UnityEngine","QualitySettings");const void *setLevel=quality?methodGet(quality,"SetQualityLevel",2):NULL;
        BOOL valid=setLevel!=NULL;
        const char *names[]={"System.Int32","System.Boolean"};
        if(valid)for(unsigned i=0;i<2;i++){char *actual=typeName(param(setLevel,i));valid=valid&&actual&&!strcmp(actual,names[i]);if(actual)release(actual);}
        if(valid){char *actual=typeName(returns(setLevel));valid=actual&&!strcmp(actual,"System.Void");if(actual)release(actual);}
        if(valid){int32_t saved=getLevel();
            // Exercise the six desktop presets through the original managed
            // API. Ordinary icon launches never run this diagnostic.
            for(int32_t level=0;level<6;level++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(7+level*6)*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                int32_t requested=level;bool expensive=true;void *parameters[]={&requested,&expensive},*exception=NULL;
                Invoke(setLevel,NULL,parameters,&exception);fprintf(stderr,"BIGWALK_QUALITY_PROBE requested=%d actual=%d mip=%d exception=%d\n",requested,getLevel(),getMip?getMip():-1,exception!=NULL);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,43*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                int32_t requested=saved;bool expensive=true;void *parameters[]={&requested,&expensive},*exception=NULL;
                Invoke(setLevel,NULL,parameters,&exception);fprintf(stderr,"BIGWALK_QUALITY_PROBE restored=%d actual=%d mip=%d exception=%d\n",saved,getLevel(),getMip?getMip():-1,exception!=NULL);
            });
        }else fprintf(stderr,"BIGWALK_QUALITY_PROBE signature_rejected=1\n");
    }
    NSMutableArray *samples=[NSMutableArray new];__block unsigned count=0;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        task_vm_info_data_t memory={0};mach_msg_type_number_t size=TASK_VM_INFO_COUNT;
        BOOL measured=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&memory,&size)==KERN_SUCCESS;
        NSDictionary *sample=@{@"seconds":@(++count),@"quality_level":@(getLevel?getLevel():-1),@"texture_mip_limit":@(getMip?getMip():-1),@"screen_width":@(ReadInt(GetWidth)),@"screen_height":@(ReadInt(GetHeight)),@"footprint_bytes":@(measured?memory.phys_footprint:0)};
        [samples addObject:sample];[[NSJSONSerialization dataWithJSONObject:samples options:0 error:nil]writeToFile:[dir stringByAppendingPathComponent:@"BigWalkGraphicsProbe.json"] atomically:YES];
        if(count%5==0)fprintf(stderr,"BIGWALK_GRAPHICS sample=%u quality=%d mip=%d screen=%dx%d footprint=%llu\n",count,[sample[@"quality_level"]intValue],[sample[@"texture_mip_limit"]intValue],[sample[@"screen_width"]intValue],[sample[@"screen_height"]intValue],(unsigned long long)[sample[@"footprint_bytes"]unsignedLongLongValue]);
        if(count>=90)[timer invalidate];
    }];
}

BOOL BigWalkMobileResolutionEnabled(void) {return [NSBundle.mainBundle.infoDictionary[@"BigWalkMobileResolutionPresets"]boolValue];}
static int32_t CurrentTier(void) {int32_t value=(int32_t)[NSUserDefaults.standardUserDefaults integerForKey:TierKey];for(unsigned i=0;i<4;i++)if(value==Tiers[i])return value;return 900;}
static NSString *TierName(int32_t tier) {return tier==1440?@"1.5K":[NSString stringWithFormat:@"%dp",tier];}
static int32_t ReadInt(const void *method) {if(!method||!Invoke)return -1;void *exception=NULL,*box=Invoke(method,NULL,NULL,&exception);return box&&!exception?*(int32_t *)Unbox(box):-1;}
static BWRenderSize Requested(int32_t tier) {CGSize points;BigWalkReadViewport(&points,NULL);return BWRenderSizeForViewport(points.width,points.height,tier);}

// Observe, never rewrite, the drawable requested by Unity. This also keeps
// the touch settings synchronized when the original graphics menu is used.
static void DrawableSizeChanged(id layer, SEL selector, CGSize size) {
    CGSize before=((CAMetalLayer *)layer).drawableSize;NativeDrawableSize(layer,selector,size);
    if(![((CAMetalLayer *)layer).name isEqualToString:@"StrayGuestMetalLayer"]||CGSizeEqualToSize(before,size))return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(!Ready||Probing)return;
        for(unsigned i=0;i<4;i++){BWRenderSize target=Requested(Tiers[i]);
            if((int32_t)size.width==target.width&&(int32_t)size.height==target.height&&ReadInt(GetWidth)==target.width&&ReadInt(GetHeight)==target.height){
                [NSUserDefaults.standardUserDefaults setInteger:Tiers[i] forKey:TierKey];
                [NSNotificationCenter.defaultCenter postNotificationName:@"BigWalkResolutionChanged" object:nil];break;}
        }
    });
}

static NSDictionary *ReadReport(int32_t tier) {
    NSWindow *window=NSApp.keyWindow;CGSize points;CGFloat scale;BigWalkReadViewport(&points,&scale);
    BWRenderSize requested=Requested(tier);int32_t width=ReadInt(GetWidth),height=ReadInt(GetHeight);
    CALayer *layer=window.contentView.layer;BOOL metal=[layer isKindOfClass:CAMetalLayer.class];CGSize drawable=metal?((CAMetalLayer *)layer).drawableSize:CGSizeZero;
    BOOL passed=width==requested.width&&height==requested.height&&metal&&(int32_t)drawable.width==width&&(int32_t)drawable.height==height;
    NSMutableArray *modes=[NSMutableArray new];for(unsigned i=0;i<4;i++){BWRenderSize size=Requested(Tiers[i]);[modes addObject:@{@"tier":@(Tiers[i]),@"width":@(size.width),@"height":@(size.height)}];}
    NSMutableArray *unityModes=[NSMutableArray new];
    if(GetResolutions&&ArrayLength){void *exception=NULL,*array=Invoke(GetResolutions,NULL,NULL,&exception);
        // Audited Unity 6 Resolution is 16 bytes (width, height, RefreshRate),
        // and IL2CPP Array's payload begins at byte 32. Bounded to four modes.
        size_t count=array&&!exception?ArrayLength(array):0;
        if(count<=4)for(size_t i=0;i<count;i++){int32_t dimensions[2];memcpy(dimensions,(char *)array+32+i*16,8);[unityModes addObject:@{@"width":@(dimensions[0]),@"height":@(dimensions[1])}];}
    }
    return @{@"tier":@(tier),@"requested_width":@(requested.width),@"requested_height":@(requested.height),@"screen_width":@(width),@"screen_height":@(height),@"drawable_width":@(drawable.width),@"drawable_height":@(drawable.height),@"viewport_width":@(points.width),@"viewport_height":@(points.height),@"backing_scale":@(scale),@"layer_frame":NSStringFromCGRect(layer.frame),@"canvas_bounds":NSStringFromCGRect(window.contentView.nativeView.bounds),@"modes":modes,@"unity_modes":unityModes,@"render_size_matches":@(passed)};
}
static void WriteReport(NSDictionary *report) {
    NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"BigWalkResolutionReport.json"] atomically:YES];
    if(Probing){[ProbeResults addObject:report];[[NSJSONSerialization dataWithJSONObject:ProbeResults options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"BigWalkResolutionProbe.json"] atomically:YES];}
    fprintf(stderr,"BIGWALK_RESOLUTION observed tier=%d requested=%dx%d screen=%dx%d drawable=%dx%d match=%d\n",[report[@"tier"]intValue],[report[@"requested_width"]intValue],[report[@"requested_height"]intValue],[report[@"screen_width"]intValue],[report[@"screen_height"]intValue],[report[@"drawable_width"]intValue],[report[@"drawable_height"]intValue],[report[@"render_size_matches"]boolValue]);
}
static BOOL ApplyTier(int32_t tier, BOOL persist) {
    if(!Ready)return NO;BWRenderSize size=Requested(tier);if(!size.width)return NO;
    // Windowed describes the guest's render surface. UIKit still occupies
    // the whole device window; do not change the physical display timing.
    int32_t mode=3;struct {uint32_t numerator,denominator;} refresh={0,1};
    void *args[]={&size.width,&size.height,&mode,&refresh},*exception=NULL;
    Invoke(SetResolution,NULL,args,&exception);if(exception){fprintf(stderr,"BIGWALK_RESOLUTION setter_exception=1\n");return NO;}
    fprintf(stderr,"BIGWALK_RESOLUTION requested tier=%d size=%dx%d guest_mode=windowed\n",tier,size.width,size.height);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{NSDictionary *report=ReadReport(tier);
        if(persist&&[report[@"render_size_matches"]boolValue])[NSUserDefaults.standardUserDefaults setInteger:tier forKey:TierKey];
        WriteReport(report);[NSNotificationCenter.defaultCenter postNotificationName:@"BigWalkResolutionChanged" object:nil];});
    return YES;
}
void BigWalkViewportChanged(CGSize points) {
    if(!BigWalkMobileResolutionEnabled()||points.width<=0||points.height<=0)return;
    double before=LastViewport.height>0?LastViewport.width/LastViewport.height:0,after=points.width/points.height;LastViewport=points;
    if(!Ready||fabs(before-after)<.00001)return;
    NSUInteger generation=++ResizeGeneration;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(generation==ResizeGeneration)ApplyTier(CurrentTier(),NO);});
}

@interface BWResolutionPicker : NSObject
@property(weak) UILabel *label;
@property(weak) UISegmentedControl *picker;
- (void)refresh;
- (void)changed:(UISegmentedControl *)sender;
@end
@implementation BWResolutionPicker
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh {int32_t tier=CurrentTier();BWRenderSize size=Requested(tier);self.label.text=[NSString stringWithFormat:@"画面分辨率 · %@ (%d×%d)",TierName(tier),size.width,size.height];for(unsigned i=0;i<4;i++)if(tier==Tiers[i])self.picker.selectedSegmentIndex=i;self.picker.enabled=Ready;}
- (void)changed:(UISegmentedControl *)sender {if(sender.selectedSegmentIndex<0||sender.selectedSegmentIndex>3)return;if(!ApplyTier(Tiers[sender.selectedSegmentIndex],YES)){[self refresh];self.label.text=@"当前无法切换分辨率";}else[self refresh];}
@end
void BigWalkAddResolutionControls(UIStackView *stack) {
    if(!BigWalkMobileResolutionEnabled())return;
    BWResolutionPicker *actions=[BWResolutionPicker new];UILabel *label=[UILabel new];label.textColor=UIColor.whiteColor;label.font=[UIFont systemFontOfSize:14];actions.label=label;[stack addArrangedSubview:label];
    UISegmentedControl *picker=[[UISegmentedControl alloc]initWithItems:@[@"720p",@"900p",@"1080p",@"1.5K"]];actions.picker=picker;picker.accessibilityLabel=@"画面分辨率";
    [picker addTarget:actions action:@selector(changed:) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:picker];
    // UIControls do not retain targets. Retain through the view's association.
    static char ActionsKey;objc_setAssociatedObject(picker,&ActionsKey,actions,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(refresh) name:@"BigWalkResolutionChanged" object:nil];[actions refresh];
}

void BigWalkInstallMobileResolution(void) {
    if(!BigWalkMobileResolutionEnabled())return;
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *lib=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_NOLOAD);if(!lib)return;
    void *(*domain)(void)=dlsym(lib,"il2cpp_domain_get");const void **(*assemblies)(void *,size_t *)=dlsym(lib,"il2cpp_domain_get_assemblies");const void *(*image)(const void *)=dlsym(lib,"il2cpp_assembly_get_image");const char *(*imageName)(const void *)=dlsym(lib,"il2cpp_image_get_name");void *(*classGet)(const void *,const char *,const char *)=dlsym(lib,"il2cpp_class_from_name");const void *(*method)(void *,const char *,int)=dlsym(lib,"il2cpp_class_get_method_from_name");
    const void *(*paramType)(const void *,uint32_t)=dlsym(lib,"il2cpp_method_get_param");char *(*typeName)(const void *)=dlsym(lib,"il2cpp_type_get_name");void (*release)(void *)=dlsym(lib,"il2cpp_free");int32_t (*valueSize)(void *,uint32_t *)=dlsym(lib,"il2cpp_class_value_size");
    Invoke=dlsym(lib,"il2cpp_runtime_invoke");Unbox=dlsym(lib,"il2cpp_object_unbox");ArrayLength=dlsym(lib,"il2cpp_array_length");
    if(!domain||!assemblies||!image||!imageName||!classGet||!method||!paramType||!typeName||!release||!valueSize||!Invoke||!Unbox)return;
    size_t count=0;const void **as=assemblies(domain(),&count);void *screen=NULL,*resolution=NULL,*refresh=NULL;const void *coreImage=NULL;
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);const char *name=imageName(im);if(name&&!strcmp(name,"UnityEngine.CoreModule.dll")){coreImage=im;screen=classGet(im,"UnityEngine","Screen");resolution=classGet(im,"UnityEngine","Resolution");refresh=classGet(im,"UnityEngine","RefreshRate");break;}}
    SetResolution=screen?method(screen,"SetResolution",4):NULL;GetWidth=screen?method(screen,"get_width",0):NULL;GetHeight=screen?method(screen,"get_height",0):NULL;GetResolutions=screen?method(screen,"get_resolutions",0):NULL;
    if(!SetResolution||!GetWidth||!GetHeight||!resolution||!refresh)return;
    const char *expected[]={"System.Int32","System.Int32","UnityEngine.FullScreenMode","UnityEngine.RefreshRate"};
    for(unsigned i=0;i<4;i++){char *actual=typeName(paramType(SetResolution,i));BOOL valid=actual&&!strcmp(actual,expected[i]);if(actual)release(actual);if(!valid){fprintf(stderr,"BIGWALK_RESOLUTION signature_rejected parameter=%u\n",i);return;}}
    uint32_t align;int32_t resolutionSize=valueSize(resolution,&align),refreshSize=valueSize(refresh,&align);if(resolutionSize!=16||refreshSize!=8){fprintf(stderr,"BIGWALK_RESOLUTION value_layout_rejected resolution=%d refresh=%d\n",resolutionSize,refreshSize);return;}
    Ready=YES;BigWalkReadViewport(&LastViewport,NULL);fprintf(stderr,"BIGWALK_RESOLUTION installed=1 resolution_stride=%d refresh_size=%d\n",resolutionSize,refreshSize);
    InstallRenderModeEnumeration(lib,coreImage);
    InspectRendering(lib,coreImage);
    Method drawableSetter=class_getInstanceMethod(CAMetalLayer.class,@selector(setDrawableSize:));
    if(drawableSetter){NativeDrawableSize=(void *)method_getImplementation(drawableSetter);class_replaceMethod(CAMetalLayer.class,@selector(setDrawableSize:),(IMP)DrawableSizeChanged,method_getTypeEncoding(drawableSetter));}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ApplyTier(CurrentTier(),NO);});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--probe-mobile-resolutions"]){
        ProbeResults=[NSMutableArray new];int32_t saved=CurrentTier();
        for(unsigned i=0;i<4;i++){int32_t tier=Tiers[i];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(12+i*4)*NSEC_PER_SEC),dispatch_get_main_queue(),^{Probing=YES;ApplyTier(tier,NO);});}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,29*NSEC_PER_SEC),dispatch_get_main_queue(),^{Probing=NO;ApplyTier(saved,NO);});
    }
}
