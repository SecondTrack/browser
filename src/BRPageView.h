// BRPageView — eigene Darstellung der BRDocument-Blöcke (CoreText), Links antippbar, Bilder nachladend.
#import <UIKit/UIKit.h>
#import "BRHTML.h"

@interface BRPageView : UIScrollView
@property (nonatomic, copy) void (^onLink)(NSURL *url);
- (void)showDocument:(BRDocument *)doc;
- (void)showMessage:(NSString *)title detail:(NSString *)detail;
@end
