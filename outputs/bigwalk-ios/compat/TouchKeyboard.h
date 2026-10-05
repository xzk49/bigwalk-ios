#import <UIKit/UIKit.h>
@interface BigWalkTouchKeyboard : UIView
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic) CGFloat sensitivity;
- (void)cancelAll;
- (void)configureOpacity:(CGFloat)opacity scale:(CGFloat)scale;
- (NSDictionary *)layoutReport;
@end
