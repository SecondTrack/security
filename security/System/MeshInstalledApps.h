// Installierte Apps (System, Cydia, App Store): Anzeigename, Programmname (wie der Kern ihn als
// Prozessnamen meldet) und das größte Icon im Bundle.
#import <Foundation/Foundation.h>

@interface MeshInstalledApp : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *name;         // Anzeigename auf dem Home-Bildschirm
@property (nonatomic, copy) NSString *executable;   // CFBundleExecutable = Prozessname
@property (nonatomic, copy) NSString *iconPath;     // nil: kein Icon gefunden
@end

@interface MeshInstalledApps : NSObject
// Ohne Mesh Security selbst und ohne versteckte System-Bundles (SBAppTags "hidden").
+ (NSArray *)scan;
@end
