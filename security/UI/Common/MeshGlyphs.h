// Symbole (24er-Raster, Strichstärke 1,9, runde Enden) und das Logo, als Vektorpfade gezeichnet
// und als UIImage geliefert. Pfade und Parser wie in Mesh; Schutz-Symbole neu dazu.
#import <UIKit/UIKit.h>

@interface MeshGlyphs : NSObject
// Linien-Symbol nach Name: back, forward, check, close, shield, shieldoff, key, lock, power, onion,
// traffic, apps, wifi, guide, reset, alert, eye, add, timer. Farbe und Kantenlänge in Punkten.
+ (UIImage *)icon:(NSString *)name color:(UIColor *)color size:(CGFloat)size;
// Logo: Mesh-Knoten im Schild, quadratisch.
+ (UIImage *)logo:(CGFloat)size;
@end
