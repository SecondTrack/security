#import "MeshGuardStatus.h"
#import "MeshException.h"

@implementation MeshGuardStatus

+ (instancetype)unknown { return [[self alloc] init]; }

static BOOL flag(NSDictionary *f, NSString *key) { return [f[key] isEqual:@"1"]; }

+ (instancetype)statusFromFields:(NSDictionary *)f {
    MeshGuardStatus *s = [[self alloc] init];
    s->_exceptions = @[];
    s->_blockedHosts = @[];
    s->_allowedApps = @[];
    if (![f[@"helper"] isEqual:@"1"]) return s;
    s->_helperReachable = YES;
    s->_shieldOn = flag(f, @"shield") && flag(f, @"pf");
    s->_cut = flag(f, @"cut");
    s->_logging = flag(f, @"log");
    s->_rootHasDefaultPassword = flag(f, @"alpine_root");
    s->_mobileHasDefaultPassword = flag(f, @"alpine_mobile");
    s->_sshListening = flag(f, @"ssh");
    s->_passwordGenerated = flag(f, @"pw");
    NSMutableArray *ex = [NSMutableArray array];
    for (NSString *t in [f[@"except"] componentsSeparatedByString:@","]) {
        MeshException *e = [MeshException exceptionFromToken:t];
        if (e) [ex addObject:e];
    }
    s->_exceptions = ex;
    NSMutableArray *bl = [NSMutableArray array];
    for (NSString *h in [f[@"blocked"] componentsSeparatedByString:@","]) if (h.length) [bl addObject:h];
    s->_blockedHosts = bl;
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *a in [f[@"apps"] componentsSeparatedByString:@","]) if (a.length) [apps addObject:a];
    s->_allowedApps = apps;
    return s;
}

- (MeshLevel)level {
    if (!_helperReachable) return MeshLevelUnknown;
    if (_cut) return MeshLevelCut;
    return _shieldOn ? MeshLevelShielded : MeshLevelOpen;
}

@end
