#import "TouchKeyboard.h"
#import "AppKitBridge.h"
#include <math.h>
#include <dlfcn.h>

extern void BigWalkTouchKey(uint16_t code, NSString *characters, BOOL down);
extern void BigWalkTouchMouseButton(NSUInteger button, BOOL down);
extern void BigWalkTouchMouseDelta(CGFloat dx, CGFloat dy);
extern void BigWalkTouchMouseStop(void);
extern void BigWalkPostPointer(CGFloat x, CGFloat y, BOOL down);

@class BigWalkKeyControl;
@interface BigWalkTouchKeyboard ()
@property(strong) NSMutableArray<BigWalkKeyControl *> *controls;
@property(nonatomic) CGFloat controlScale;
@end

// Opt-in end-to-end probe: read Unity's actual held-key/button state after
// dispatch, then read it again after release. Normal launches never run it.
void BigWalkProbeTouchKeyboard(void) {
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--probe-touch-keyboard"])return;
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
    if(!domain||!assemblies||!image||!imageName||!classGet||!method||!invoke||!unbox)return;
    size_t count=0;const void **as=assemblies(domain(),&count);void *input=NULL;
    for(size_t i=0;i<count;i++){const void *im=image(as[i]);if(!strcmp(imageName(im),"UnityEngine.InputLegacyModule.dll")){input=classGet(im,"UnityEngine","Input");break;}}
    const void *getKey=input?method(input,"GetKeyInt",1):NULL;
    const void *getMouse=input?method(input,"GetMouseButton",1):NULL;
    if(!getKey||!getMouse){fprintf(stderr,"BIGWALK_TOUCH_PROBE unavailable=UnityInput\n");return;}
    NSArray *cases=@[@[@13,@119,@"w",@0],@[@56,@304,@"",@0],@[@59,@306,@"",@0],@[@0,@0,@"",@1],@[@1,@1,@"",@1]];
    NSMutableArray *results=[NSMutableArray new];
    for(NSUInteger i=0;i<cases.count;i++){
        NSArray *item=cases[i];BOOL mouse=[item[3]boolValue];uint16_t code=[item[0]unsignedShortValue];int query=[item[1]intValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(15+i*2)*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            // Never click the last-selected menu entry during a diagnostic.
            // Move via a harmless up event to the top-center blank margin.
            if(mouse)BigWalkPostPointer(.5,.03,NO);
            if(mouse)BigWalkTouchMouseButton(code,YES);else BigWalkTouchKey(code,item[2],YES);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                int value=query;void *args[]={&value},*exception=NULL;
                void *box=invoke(mouse?getMouse:getKey,NULL,args,&exception);BOOL held=box&&!exception?*(bool *)unbox(box):NO;
                if(mouse)BigWalkTouchMouseButton(code,NO);else BigWalkTouchKey(code,item[2],NO);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                    int releaseValue=query;void *releaseArgs[]={&releaseValue},*releaseException=NULL;
                    void *releaseBox=invoke(mouse?getMouse:getKey,NULL,releaseArgs,&releaseException);BOOL released=releaseBox&&!releaseException?!*(bool *)unbox(releaseBox):NO;
                    [results addObject:@{@"mouse":@(mouse),@"keycode":@(query),@"held_observed":@(held),@"release_observed":@(released),@"passed":@(held&&released)}];
                    fprintf(stderr,"BIGWALK_TOUCH_PROBE mouse=%d keycode=%d held=%d released=%d\n",mouse,query,held,released);
                    NSString *document=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
                    [[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[document stringByAppendingPathComponent:@"BigWalkTouchKeyboardProbe.json"] atomically:YES];
                });
            });
        });
    }
}
@interface BigWalkKeyControl : UIView
@property(weak) BigWalkTouchKeyboard *owner;
@property(copy) NSString *label, *characters;
@property(nonatomic) uint16_t code;
@property(nonatomic) NSInteger kind; // 0 key, 1 WASD pad, 2 look pad, 3/4 mouse buttons
@property(strong) UITouch *held;
@property(nonatomic) BOOL pressed;
@property(nonatomic) NSUInteger directions, generation;
@property(nonatomic) CGPoint lastPoint;
@property(nonatomic) CGRect placement;
- (void)cancelInput;
@end
@implementation BigWalkKeyControl
- (instancetype)init {if((self=[super init])){self.backgroundColor=UIColor.clearColor;self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;self.multipleTouchEnabled=NO;}return self;}
- (void)drawRect:(CGRect)rect {
    CGFloat radius=self.kind==1||self.kind==2?rect.size.height/2:12;
    UIBezierPath *shape=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect,1,1) cornerRadius:radius];
    [[UIColor colorWithWhite:self.pressed?.38:.12 alpha:self.kind==2?.28:.62]setFill];[shape fill];
    [[UIColor colorWithWhite:1 alpha:.45]setStroke];shape.lineWidth=1;[shape stroke];
    NSDictionary *style=@{NSFontAttributeName:[UIFont systemFontOfSize:self.kind==1?19:14 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor};
    if(self.kind==1){
        NSArray *letters=@[@"W",@"A",@"S",@"D"];
        NSArray *points=@[[NSValue valueWithCGPoint:CGPointMake(.5,.16)],[NSValue valueWithCGPoint:CGPointMake(.17,.5)],[NSValue valueWithCGPoint:CGPointMake(.5,.81)],[NSValue valueWithCGPoint:CGPointMake(.83,.5)]];
        for(NSUInteger i=0;i<4;i++){NSString *s=letters[i];CGPoint p=[(NSValue *)points[i] CGPointValue];CGSize z=[s sizeWithAttributes:style];[s drawAtPoint:CGPointMake(rect.size.width*p.x-z.width/2,rect.size.height*p.y-z.height/2) withAttributes:style];}
    }else{NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;NSMutableDictionary *styles=[style mutableCopy];styles[NSParagraphStyleAttributeName]=paragraph;CGSize z=[self.label boundingRectWithSize:CGSizeMake(rect.size.width-4,100) options:NSStringDrawingUsesLineFragmentOrigin attributes:styles context:nil].size;[self.label drawInRect:CGRectMake(2,(rect.size.height-z.height)/2,rect.size.width-4,z.height+1) withAttributes:styles];}
}
- (void)setDown:(BOOL)down {
    if(self.pressed==down)return;self.pressed=down;
    if(self.kind==0)BigWalkTouchKey(self.code,self.characters,down);
    else if(self.kind==3||self.kind==4)BigWalkTouchMouseButton(self.kind-3,down);
    [self setNeedsDisplay];
}
- (void)setDirections:(NSUInteger)directions {
    NSUInteger old=_directions;_directions=directions;
    uint16_t codes[]={13,0,1,2};NSString *chars[]={@"w",@"a",@"s",@"d"};
    for(NSUInteger i=0;i<4;i++)if((old^(directions))&(1u<<i))BigWalkTouchKey(codes[i],chars[i],(directions&(1u<<i))!=0);
}
- (void)updatePad:(UITouch *)touch {
    CGPoint p=[touch locationInView:self];CGFloat x=(p.x-CGRectGetMidX(self.bounds))/(self.bounds.size.width*.5),y=(p.y-CGRectGetMidY(self.bounds))/(self.bounds.size.height*.5);
    NSUInteger directions=0;if(y<-.22)directions|=1;if(x<-.22)directions|=2;if(y>.22)directions|=4;if(x>.22)directions|=8;[self setDirections:directions];
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if(self.held)return;self.generation++;self.held=touches.anyObject;self.lastPoint=[self.held locationInView:self];[self.owner.canvas becomeFirstResponder];
    [self setDown:YES];if(self.kind==1)[self updatePad:self.held];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!self.held||![touches containsObject:self.held])return;
    if(self.kind==1)[self updatePad:self.held];
    if(self.kind==2){CGPoint p=[self.held locationInView:self];NSWindow *window=NSApp.keyWindow;CGRect viewport=window.contentView.layer.frame;
        CGFloat sx=viewport.size.width>0?window.contentView.bounds.size.width/viewport.size.width:1;
        CGFloat sy=viewport.size.height>0?window.contentView.bounds.size.height/viewport.size.height:1;
        BigWalkTouchMouseDelta((p.x-self.lastPoint.x)*sx*self.owner.sensitivity,(p.y-self.lastPoint.y)*sy*self.owner.sensitivity);self.lastPoint=p;}
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!self.held||![touches containsObject:self.held])return;self.held=nil;
    if(self.kind==1||self.kind==2){[self cancelInput];return;}
    // Let at least one normal game frame observe a short tap. A subsequent
    // press invalidates this release, so it cannot cancel the newer hold.
    NSUInteger generation=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.generation==generation)[self setDown:NO];});
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {[self cancelInput];}
- (void)cancelInput {self.generation++;self.held=nil;if(self.kind==1)[self setDirections:0];if(self.kind==2)BigWalkTouchMouseStop();[self setDown:NO];}
- (BOOL)accessibilityActivate {if(self.kind==1||self.kind==2)return NO;self.generation++;[self setDown:YES];NSUInteger generation=self.generation;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self.generation==generation)[self setDown:NO];});return YES;}
@end

@implementation BigWalkTouchKeyboard
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.backgroundColor=UIColor.clearColor;self.multipleTouchEnabled=YES;self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.sensitivity=1;self.controlScale=1;self.controls=[NSMutableArray new];
        // Verified from the fixed build's serialized Rewired keyboard maps.
        NSArray *keys=@[
            @[@"Shift\n奔跑",@56,@"",@.09,@.40,@72,@42],
            @[@"Ctrl\n蹲下",@59,@"",@.09,@.87,@72,@42],
            @[@"Q\n左手",@12,@"q",@.82,@.39,@64,@44],
            @[@"E\n右手",@14,@"e",@.93,@.39,@64,@44],
            @[@"Space\n跳跃",@49,@" ",@.90,@.87,@100,@48],
            @[@"Esc\n返回",@53,@"\x1b",@.06,@.09,@60,@38],
            @[@"Enter\n确认/聊天",@36,@"\r",@.93,@.09,@86,@38],
            @[@"V\n静音",@9,@"v",@.20,@.09,@60,@38],
            @[@"Z\n坐下",@6,@"z",@.34,@.09,@76,@38]];
        for(NSArray *key in keys){BigWalkKeyControl *c=[BigWalkKeyControl new];c.owner=self;c.label=key[0];c.code=[key[1]unsignedShortValue];c.characters=key[2];c.placement=CGRectMake([key[3]doubleValue],[key[4]doubleValue],[key[5]doubleValue],[key[6]doubleValue]);c.accessibilityLabel=[c.label stringByReplacingOccurrencesOfString:@"\n" withString:@" "];[self.controls addObject:c];[self addSubview:c];}
        NSArray *pads=@[@[@1,@"WASD",@.19,@.65,@132,@132],@[@2,@"拖动\n转视角",@.72,@.66,@112,@112],@[@3,@"左键\n使用",@.85,@.62,@68,@48],@[@4,@"右键\n放下",@.95,@.62,@68,@48]];
        for(NSArray *pad in pads){BigWalkKeyControl *c=[BigWalkKeyControl new];c.owner=self;c.kind=[pad[0]integerValue];c.label=pad[1];c.accessibilityLabel=c.label;c.placement=CGRectMake([pad[2]doubleValue],[pad[3]doubleValue],[pad[4]doubleValue],[pad[5]doubleValue]);[self.controls addObject:c];[self addSubview:c];}
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelAll) name:UIApplicationWillResignActiveNotification object:nil];
        fprintf(stderr,"BIGWALK_TOUCH_KEYBOARD installed=1 controls=%lu\n",(unsigned long)self.controls.count);
    }return self;
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)configureOpacity:(CGFloat)opacity scale:(CGFloat)scale {self.controlScale=scale;for(UIView *c in self.controls)c.alpha=opacity;[self setNeedsLayout];}
- (void)layoutSubviews {[super layoutSubviews];CGRect r=CGRectInset(UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets),8,8);CGFloat unit=MIN(1,r.size.height/360)*self.controlScale;for(BigWalkKeyControl *c in self.controls){CGRect p=c.placement;CGFloat w=MIN(r.size.width,MAX(28,p.size.width*unit)),h=MIN(r.size.height,MAX(28,p.size.height*unit));CGFloat x=r.origin.x+r.size.width*p.origin.x,y=r.origin.y+r.size.height*p.origin.y;c.frame=CGRectMake(MAX(r.origin.x,MIN(CGRectGetMaxX(r)-w,x-w/2)),MAX(r.origin.y,MIN(CGRectGetMaxY(r)-h,y-h/2)),w,h);[c setNeedsDisplay];}}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {for(UIView *c in self.controls)if(!c.hidden&&CGRectContainsPoint(c.frame,p))return YES;return NO;}
- (NSDictionary *)layoutReport {
    NSMutableArray *items=[NSMutableArray new];NSUInteger visible=0;
    for(BigWalkKeyControl *c in self.controls){
        BOOL displayed=!self.hidden&&!c.hidden&&self.alpha>.01&&c.alpha>.01&&self.window!=nil&&!self.window.hidden;
        if(displayed&&!CGRectIsEmpty(c.frame))visible++;
        [items addObject:@{@"label":c.label,@"frame":NSStringFromCGRect(c.frame),@"visible":@(displayed)}];
    }
    return @{@"hidden":@(self.hidden),@"attached_to_window":@(self.window!=nil),
             @"bounds":NSStringFromCGRect(self.bounds),@"visible_control_count":@(visible),@"controls":items};
}
- (void)cancelAll {for(BigWalkKeyControl *c in self.controls)[c cancelInput];}
@end
