// Ereignisse, mit denen die Domäne die UI informiert.
// Liegt in Support/, damit jede Schicht sie nutzen kann, ohne MeshGuard zu importieren.
#import <Foundation/Foundation.h>

extern NSString *const MeshGuardChangedNotification;     // Schutzzustand neu gelesen (Chip, Startseite)
extern NSString *const MeshTrafficChangedNotification;   // neue Verbindungen im Protokoll
extern NSString *const MeshWillLockNotification;         // App geht in den Hintergrund: offene Dialoge schließen
