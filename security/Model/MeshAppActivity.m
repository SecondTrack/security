#import "MeshAppActivity.h"
#import "MeshConnection.h"

static NSString *const kMeshProcess = @"Mesh", *const kTorProcess = @"mesh-tor";

@implementation MeshAppActivity

+ (NSArray *)activitiesForInstalled:(NSArray *)installed connections:(NSArray *)connections allowedApps:(NSArray *)allowed {
    NSMutableDictionary *hosts = [NSMutableDictionary dictionary], *last = [NSMutableDictionary dictionary];
    for (MeshConnection *c in connections) {
        if (c.incoming) continue;
        NSString *p = [c.process isEqual:kTorProcess] ? kMeshProcess : c.process;   // Tor zählt zu Mesh
        NSMutableSet *set = hosts[p] ?: (hosts[p] = [NSMutableSet set]);
        [set addObject:[c remoteHost]];
        NSDate *prev = last[p];
        if (!prev || [c.time compare:prev] == NSOrderedDescending) last[p] = c.time;
    }
    NSMutableArray *apps = [NSMutableArray array], *others = [NSMutableArray array];
    NSMutableSet *done = [NSMutableSet setWithObject:kTorProcess];
    for (NSDictionary *d in installed) {
        NSString *exe = d[@"executable"];
        if (!exe.length || [done containsObject:exe]) continue;
        [done addObject:exe];
        MeshAppActivity *a = [self entry:exe name:d[@"name"] icon:d[@"iconPath"] isApp:YES hosts:hosts last:last allowed:allowed];
        a->_isMesh = [d[@"bundleId"] hasPrefix:@"de.mesh."];
        a->_isMessenger = [exe isEqual:kMeshProcess] && a->_isMesh;
        [apps addObject:a];
    }
    NSMutableSet *rest = [NSMutableSet setWithArray:hosts.allKeys];
    [rest minusSet:done];
    for (NSString *p in rest) [others addObject:[self entry:p name:p icon:nil isApp:NO hosts:hosts last:last allowed:allowed]];

    [apps sortUsingComparator:^NSComparisonResult(MeshAppActivity *a, MeshAppActivity *b) {
        if (a.isMessenger != b.isMessenger) return a.isMessenger ? NSOrderedAscending : NSOrderedDescending;
        if (a.isMesh != b.isMesh) return a.isMesh ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    [others sortUsingComparator:^NSComparisonResult(MeshAppActivity *a, MeshAppActivity *b) { return [a.name localizedCaseInsensitiveCompare:b.name]; }];
    return [apps arrayByAddingObjectsFromArray:others];
}

+ (instancetype)entry:(NSString *)process name:(NSString *)name icon:(NSString *)icon isApp:(BOOL)isApp
                hosts:(NSDictionary *)hosts last:(NSDictionary *)last allowed:(NSArray *)allowed {
    MeshAppActivity *a = [[MeshAppActivity alloc] init];
    a->_process = [process copy];
    a->_name = [(name.length ? name : process) copy];
    a->_iconPath = [icon copy];
    a->_isApp = isApp;
    a->_destinations = [hosts[process] count];
    a->_lastSeen = last[process];
    a->_allowed = [allowed containsObject:process];
    return a;
}

@end
