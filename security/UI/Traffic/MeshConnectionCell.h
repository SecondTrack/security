// Zeile im Verbindungsprotokoll: Programm und Gegenstelle, darunter Zeit, Richtung, Protokoll, Urteil.
#import <UIKit/UIKit.h>

@class MeshConnection;

@interface MeshConnectionCell : UITableViewCell
+ (CGFloat)height;
- (void)showConnection:(MeshConnection *)connection blocked:(BOOL)blocked;   // blocked: Ziel steht auf der Sperrliste
@end
