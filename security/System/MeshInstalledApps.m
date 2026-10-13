#import "MeshInstalledApps.h"

@implementation MeshInstalledApp
@end

@implementation MeshInstalledApps

static NSString *stringIn(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] && [v length] ? v : nil;
}

// Icon-Dateinamen aus allen Schreibweisen (iOS 3: CFBundleIconFile, ab 4: CFBundleIconFiles, ab 5: CFBundleIcons).
static NSArray *iconNames(NSDictionary *info) {
    NSMutableArray *names = [NSMutableArray array];
    id icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        id primary = icons[@"CFBundlePrimaryIcon"];
        id files = [primary isKindOfClass:[NSDictionary class]] ? primary[@"CFBundleIconFiles"] : nil;
        if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
    }
    id files = info[@"CFBundleIconFiles"];
    if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
    NSString *one = stringIn(info, @"CFBundleIconFile");
    if (one) [names addObject:one];
    [names addObjectsFromArray:@[ @"Icon", @"icon" ]];
    return names;
}

// Größtes vorhandenes Icon: zu jedem Namen auch @2x/~iphone und mit/ohne .png probieren.
static NSString *bestIcon(NSString *dir, NSDictionary *info) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *best = nil;
    unsigned long long bestSize = 0;
    for (id n in iconNames(info)) {
        if (![n isKindOfClass:[NSString class]]) continue;
        NSString *base = [n hasSuffix:@".png"] ? [n stringByDeletingPathExtension] : n;
        for (NSString *suffix in @[ @"@2x.png", @"@2x~iphone.png", @".png", @"~iphone.png", @"" ]) {
            NSString *path = [dir stringByAppendingPathComponent:[base stringByAppendingString:suffix]];
            unsigned long long size = [[fm attributesOfItemAtPath:path error:NULL] fileSize];
            if (size > bestSize && [path hasSuffix:@".png"]) { best = path; bestSize = size; }
        }
    }
    return best;
}

static void addBundle(NSString *dir, NSMutableDictionary *out) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bid = stringIn(info, @"CFBundleIdentifier"), *exe = stringIn(info, @"CFBundleExecutable");
    if (!bid || !exe || [bid isEqual:[[NSBundle mainBundle] bundleIdentifier]]) return;
    id tags = info[@"SBAppTags"];
    if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) return;
    MeshInstalledApp *a = [[MeshInstalledApp alloc] init];
    a.bundleId = bid;
    a.executable = exe;
    a.name = stringIn(info, @"CFBundleDisplayName") ?: stringIn(info, @"CFBundleName") ?: [[dir lastPathComponent] stringByDeletingPathExtension];
    a.iconPath = bestIcon(dir, info);
    out[bid] = a;
}

+ (NSArray *)scan {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *f in [fm contentsOfDirectoryAtPath:@"/Applications" error:NULL])
        if ([f hasSuffix:@".app"]) addBundle([@"/Applications" stringByAppendingPathComponent:f], out);
    // App-Store-Apps: /var/mobile/Applications/<UUID>/<Name>.app
    NSString *store = @"/var/mobile/Applications";
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:store error:NULL]) {
        NSString *dir = [store stringByAppendingPathComponent:uuid];
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:NULL])
            if ([f hasSuffix:@".app"]) addBundle([dir stringByAppendingPathComponent:f], out);
    }
    return out.allValues;
}

@end
