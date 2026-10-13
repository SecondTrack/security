#import "MeshGuard.h"
#import "MeshHelper.h"
#import "MeshHelperProtocol.h"
#import "MeshConnection.h"
#import "MeshAppActivity.h"
#import "MeshInstalledApps.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

@implementation MeshGuard {
    dispatch_queue_t _queue;
    BOOL _refreshQueued;   // eine Abfrage wartet schon: weitere Anfragen hängen sich an sie an
}

+ (instancetype)shared {
    static MeshGuard *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [[MeshGuard alloc] init]; });
    return g;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("de.mesh.security.helper", DISPATCH_QUEUE_SERIAL);
        _status = [MeshGuardStatus unknown];
    }
    return self;
}

static MeshGuardResult resultForCode(int code) {
    switch (code) {
        case MG_OK:            return MeshGuardResultOK;
        case MG_ERR_CALLER:    return MeshGuardResultRefused;
        case MG_ERR_FOREIGN:   return MeshGuardResultForeignRules;
        case MG_ERR_PASSWORD:  return MeshGuardResultPassword;
        case MG_ERR_LIMIT:     return MeshGuardResultLimit;
        case -1:
        case MG_ERR_PRIV:      return MeshGuardResultNoHelper;
        default:               return MeshGuardResultFailed;
    }
}

// Auf der Queue: Status lesen und auf Main veröffentlichen.
- (void)readStatus {
    MeshHelperResult *r = [MeshHelper run:@[ @MG_CMD_STATUS ] input:nil];
    MeshGuardStatus *s = r.code == MG_OK ? [MeshGuardStatus statusFromFields:r.fields] : [MeshGuardStatus unknown];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_status = s;
        [[NSNotificationCenter defaultCenter] postNotificationName:MeshGuardChangedNotification object:self];
    });
}

// Mehrere Anfragen kurz hintereinander (Start, Seite erscheint, App aktiv) kosten nur eine Abfrage:
// jede startet pfctl auf dem langsamen iPod.
- (void)refresh {
    if (_refreshQueued) return;
    _refreshQueued = YES;
    dispatch_async(_queue, ^{
        dispatch_sync(dispatch_get_main_queue(), ^{ self->_refreshQueued = NO; });
        [self readStatus];
    });
}

// Befehl ausführen, danach Status neu lesen, dann completion auf Main.
- (void)run:(NSArray *)args completion:(MeshGuardDone)done {
    dispatch_async(_queue, ^{
        MeshGuardResult res = resultForCode([MeshHelper run:args input:nil].code);
        [self readStatus];
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(res); });
    });
}

- (void)setShield:(BOOL)on completion:(MeshGuardDone)done { [self run:@[ @MG_CMD_SHIELD, on ? @"on" : @"off" ] completion:done]; }
- (void)setCut:(BOOL)cut completion:(MeshGuardDone)done { [self run:@[ @MG_CMD_CUT, cut ? @"on" : @"off" ] completion:done]; }
- (void)setLogging:(BOOL)on completion:(MeshGuardDone)done { [self run:@[ @MG_CMD_LOG, on ? @"on" : @"off" ] completion:done]; }
- (void)resetAll:(MeshGuardDone)done { [self run:@[ @MG_CMD_RESET ] completion:done]; }

- (void)addException:(MeshException *)e completion:(MeshGuardDone)done {
    [self run:@[ @MG_CMD_EXCEPT, @"add", e.proto, [NSString stringWithFormat:@"%ld", (long)e.port] ] completion:done];
}

- (void)removeException:(MeshException *)e completion:(MeshGuardDone)done {
    [self run:@[ @MG_CMD_EXCEPT, @"del", e.proto, [NSString stringWithFormat:@"%ld", (long)e.port] ] completion:done];
}

- (void)setHost:(NSString *)host blocked:(BOOL)blocked completion:(MeshGuardDone)done {
    [self run:@[ @MG_CMD_BLOCK, blocked ? @"add" : @"del", host ] completion:done];
}

- (void)setApp:(NSString *)name allowed:(BOOL)allowed completion:(MeshGuardDone)done {
    [self run:@[ @MG_CMD_APP, allowed ? @"allow" : @"block", name ] completion:done];
}

- (void)loadApps:(void (^)(NSArray *))done {
    // Bundles lesen dauert auf dem iPod etwas: nicht auf dem Main-Thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *installed = [NSMutableArray array];
        for (MeshInstalledApp *a in [MeshInstalledApps scan]) {
            NSMutableDictionary *d = [@{ @"name": a.name, @"executable": a.executable, @"bundleId": a.bundleId } mutableCopy];
            if (a.iconPath) d[@"iconPath"] = a.iconPath;
            [installed addObject:d];
        }
        [self loadConnections:^(NSArray *connections) {
            done([MeshAppActivity activitiesForInstalled:installed connections:connections allowedApps:self->_status.allowedApps]);
        }];
    });
}

- (void)loadPassword:(void (^)(NSString *))done {
    dispatch_async(_queue, ^{
        MeshHelperResult *r = [MeshHelper run:@[ @MG_CMD_PASSWORD ] input:nil];
        NSString *pw = r.code == MG_OK ? r.fields[@"pw"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(pw.length ? pw : nil); });
    });
}

- (void)loadConnections:(void (^)(NSArray *))done {
    dispatch_async(_queue, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *line in [MeshHelper run:@[ @MG_CMD_CONNS ] input:nil].lines) {
            MeshConnection *c = [MeshConnection connectionFromLine:line];
            if (c) [list insertObject:c atIndex:0];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(list); });
    });
}

+ (NSString *)describe:(MeshGuardResult)result {
    switch (result) {
        case MeshGuardResultOK:           return L(@"Done.");
        case MeshGuardResultNoHelper:     return L(@"The system helper is missing or has no root rights. Please reinstall Mesh Security.");
        case MeshGuardResultRefused:      return L(@"The system helper refused the request.");
        case MeshGuardResultForeignRules: return L(@"Another firewall is already active. Mesh Security leaves it untouched.");
        case MeshGuardResultPassword:     return L(@"The password could not be changed. Everything has been undone.");
        case MeshGuardResultLimit:        return L(@"That is the maximum number of exceptions.");
        case MeshGuardResultFailed:       return L(@"That did not work. The previous state has been restored.");
    }
    return nil;
}

@end
