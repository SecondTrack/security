// Leiste der Hauptseiten: Logo, Titel, Untertitel und Schutz-Chip.
// Der Chip folgt MeshGuardChangedNotification von selbst; Antippen liest den Zustand neu.
#import <UIKit/UIKit.h>

@interface MeshTopBar : UIView
+ (CGFloat)height;   // inklusive MeshTheme topInset
- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title subtitle:(NSString *)subtitle;
@end
