// Zeile der App-Liste: Icon (oder Symbol-Kachel), Name, Zustand, Schalter.
#import <UIKit/UIKit.h>

@class MeshAppActivity;

@interface MeshAppCell : UITableViewCell
+ (CGFloat)height;
@property (nonatomic, readonly) UISwitch *toggle;
- (void)showApp:(MeshAppActivity *)app icon:(UIImage *)icon;
@end
