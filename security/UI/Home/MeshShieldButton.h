// Großer runder Schalter mit Schild. Farbe und Symbol folgen dem Zustand.
#import <UIKit/UIKit.h>
#import "MeshGuardStatus.h"

@interface MeshShieldButton : UIButton
+ (CGFloat)size;
- (void)showLevel:(MeshLevel)level busy:(BOOL)busy;
@end
