#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "AppKitBridge.h"

// UITextField owns composition and candidate selection. Only committed text
// reaches the original Unity NSTextInputClient; never synthesize ASCII for IME.
static BOOL CommitText(NSView *view, NSString *text) {
    if(!text.length)return YES;
    SEL ranged=NSSelectorFromString(@"insertText:replacementRange:");
    SEL plain=NSSelectorFromString(@"insertText:");
    @try {
        if([view respondsToSelector:ranged])
            ((void(*)(id,SEL,id,NSRange))objc_msgSend)(view,ranged,text,NSMakeRange(NSNotFound,0));
        else if([view respondsToSelector:plain])
            ((void(*)(id,SEL,id))objc_msgSend)(view,plain,text);
        else {fprintf(stderr,"BIGWALK_TEXT unavailable=insertText receiver=%s\n",object_getClassName(view));return NO;}
        fprintf(stderr,"BIGWALK_TEXT committed_utf16=%lu receiver=%s\n",(unsigned long)text.length,object_getClassName(view));
        return YES;
    } @catch(NSException *exception) {
        fprintf(stderr,"BIGWALK_TEXT exception=%s reason=%s\n",exception.name.UTF8String,exception.reason.UTF8String);
        return NO;
    }
}
static void PostKey(NSWindow *window, uint16_t code, NSString *characters, NSUInteger flags) {
    for(NSNumber *type in @[@10,@11]){
        NSEvent *event=[NSEvent new];event.type=type.unsignedIntegerValue;event.keyCode=code;
        event.characters=characters;event.charactersIgnoringModifiers=characters;
        event.modifierFlags=flags;event.windowNumber=window.windowNumber;
        event.timestamp=NSProcessInfo.processInfo.systemUptime;
        [NSApp postEvent:event atStart:NO];
    }
    fprintf(stderr,"BIGWALK_TEXT key=%u modifiers=%lu\n",code,(unsigned long)flags);
}
@interface BigWalkTextEntryActions : NSObject
@property(strong) NSView *guest;
@property(strong) NSWindow *window;
@property(weak) UITextField *field;
@property(weak) UIAlertController *alert;
- (void)backspace;
- (void)clearGameField;
- (void)returnToGame;
@end
@implementation BigWalkTextEntryActions
- (void)backspace {
    if(self.field.text.length || self.field.markedTextRange)[self.field deleteBackward];
    else PostKey(self.window,51,@"\x7f",0);
}
- (void)clearGameField {
    PostKey(self.window,0,@"a",1u<<20);
    PostKey(self.window,51,@"\x7f",0);
}
- (void)returnToGame {
    [self.field unmarkText];
    if(!CommitText(self.guest,self.field.text))return;
    [self.alert dismissViewControllerAnimated:YES completion:^{PostKey(self.window,36,@"\r",0);}];
}
@end
static char TextEntryActionsKey;

void BigWalkShowTextEntry(UIView *canvas) {
    NSCAssert(NSThread.isMainThread,@"Screen text entry belongs to UIKit's main thread");
    SEL viewSelector=NSSelectorFromString(@"cocoaView");
    NSView *view=[canvas respondsToSelector:viewSelector]?((id(*)(id,SEL))objc_msgSend)(canvas,viewSelector):nil;
    NSWindow *window=view.window?:NSApp.keyWindow;
    NSView *receiver=window.firstResponder;
    if(![receiver respondsToSelector:NSSelectorFromString(@"insertText:replacementRange:")] &&
       ![receiver respondsToSelector:NSSelectorFromString(@"insertText:")])receiver=view?:window.contentView;
    UIViewController *presenter=window.nativeWindow.rootViewController;
    if(!presenter || presenter.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"输入文字"
        message:@"先点游戏中的输入框，再打开键盘。输入的文字会填入该位置。"
        preferredStyle:UIAlertControllerStyleAlert];
    BigWalkTextEntryActions *actions=[BigWalkTextEntryActions new];actions.guest=receiver;
    actions.window=window;actions.alert=alert;
    objc_setAssociatedObject(alert,&TextEntryActionsKey,actions,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){
        actions.field=field;field.placeholder=@"房间名、加入码或聊天内容";
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.spellCheckingType=UITextSpellCheckingTypeNo;
        field.keyboardType=UIKeyboardTypeDefault;
        UIToolbar *bar=[[UIToolbar alloc]initWithFrame:CGRectMake(0,0,canvas.bounds.size.width,44)];
        bar.items=@[[[UIBarButtonItem alloc]initWithTitle:@"退格" style:UIBarButtonItemStylePlain target:actions action:@selector(backspace)],
            [[UIBarButtonItem alloc]initWithTitle:@"清空游戏输入框" style:UIBarButtonItemStylePlain target:actions action:@selector(clearGameField)],
            [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
            [[UIBarButtonItem alloc]initWithTitle:@"输入并回车" style:UIBarButtonItemStyleDone target:actions action:@selector(returnToGame)]];
        field.inputAccessoryView=bar;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"输入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [actions.field unmarkText];CommitText(actions.guest,actions.field.text);
    }]];
    [presenter presentViewController:alert animated:YES completion:^{
        [actions.field becomeFirstResponder];
        fprintf(stderr,"BIGWALK_TEXT keyboard_presented=1 native_first_responder=%d receiver=%s\n",
            actions.field.isFirstResponder,object_getClassName(actions.guest));
    }];
}

// Explicit diagnostic traverses the same UTF-16 adapter as the native field.
// It is inert on normal icon launch and changes neither saved rooms nor auth.
void BigWalkProbeTextEntry(void) {
    NSView *view=NSApp.keyWindow.contentView;
    fprintf(stderr,"BIGWALK_TEXT probe_started=1\n");
    CommitText(view,@"BW键盘Test7");
    BigWalkShowTextEntry(view.nativeView);
}
