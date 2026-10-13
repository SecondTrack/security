// Flacher Schalter im Mesh-Look statt des iOS-6-UISwitch (glänzende Kugel, ON/OFF-Schrift).
// Gleiche Bedienung: Antippen oder Wischen schaltet um und meldet UIControlEventValueChanged.
#import <UIKit/UIKit.h>

@interface MeshToggle : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end
