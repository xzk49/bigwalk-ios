#import <UIKit/UIKit.h>
#import "MobileResolutionGeometry.h"
BOOL BigWalkMobileResolutionEnabled(void);
void BigWalkReadViewport(CGSize *points, CGFloat *backingScale);
void BigWalkInstallMobileResolution(void);
void BigWalkViewportChanged(CGSize points);
void BigWalkAddResolutionControls(UIStackView *stack);
