// Die einzige Stelle mit iOS-Versionsweichen (aus Mesh übernommen).
//
// Mesh Security läuft auf iOS 5.0 bis 6.1 (iPod touch 3G/4G, ARMv7). Alles, was es erst ab
// iOS 6 gibt, wird hier gekapselt. Der übrige Code enthält keine eigenen Versionsabfragen.
#import <UIKit/UIKit.h>

// ARC-Weak-Referenzen gibt es erst ab iOS 5. Darunter (ARCLite) bleibt nur unsafe_unretained;
// der Besitzer muss die Referenz dann selbst in dealloc auf nil setzen.
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 50000
  #define MESH_WEAK   __weak
  #define mesh_weak   weak
#else
  #define MESH_WEAK   __unsafe_unretained
  #define mesh_weak   unsafe_unretained
#endif

// Kurzschreibweise dict[key], array[i] braucht Methoden, die Foundation erst ab iOS 6 hat.
// MeshCompat.m (MeshSubscriptingShim) rüstet sie beim Start nach, wenn sie fehlen: wie Apples
// libarclite, die Theos nicht mitlinkt. Der übrige Code darf die Kurzschreibweise daher benutzen.

// Dispatch-Objekte verwaltet ARC erst ab Deployment-Target iOS 6; darunter von Hand freigeben.
#if OS_OBJECT_USE_OBJC
  #define mesh_dispatch_release(o)
#else
  #define mesh_dispatch_release(o) dispatch_release(o)
#endif

@interface UISlider (MeshCompat)
- (void)mesh_tint:(UIColor *)color;   // Farben setzen, wo möglich (ab iOS 5)
@end

@interface UIViewController (MeshCompat)

// presentViewController:… / dismissViewControllerAnimated:… gibt es ab iOS 5,
// davor presentModalViewController:… / dismissModalViewControllerAnimated:.
- (void)mesh_present:(UIViewController *)vc animated:(BOOL)animated;
- (void)mesh_dismissAnimated:(BOOL)animated;
- (void)mesh_dismissPresentedAnimated:(BOOL)animated;   // schließt, was dieser Controller zeigt (falls etwas)

// Vollbild-Layout unter der Statusleiste (wantsFullScreenLayout, ab iOS 7 entfallen).
- (void)mesh_useFullScreenLayout;

@end
