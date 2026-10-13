// Zustand und Protokollzeilen des Helfers: was ankommt, wird streng gelesen; Unbekanntes bleibt unbekannt.
#import "MeshTest.h"
#import "MeshGuardStatus.h"
#import "MeshConnection.h"
#import "MeshException.h"
#import "MeshHelper.h"
#import "MeshAppActivity.h"

int main(void) {
    @autoreleasepool {
        NSDictionary *f = [MeshHelper fieldsFromOutput:@"helper=1\nshield=1\npf=1\ncut=0\nlog=1\nalpine_root=0\nalpine_mobile=0\nssh=1\npw=1\nexcept=tcp:22,udp:5353,icmp:1,tcp:0,tcp:99999,tcp:8080x\n=x\nkaputt\n"];
        check(f[@""] == nil && f.count == 10, "Zeilen ohne Schlüssel übersprungen");

        MeshGuardStatus *s = [MeshGuardStatus statusFromFields:f];
        check(s.helperReachable && s.shieldOn && s.logging && s.passwordGenerated && s.sshListening, "Flags gelesen");
        check(s.level == MeshLevelShielded, "abgeschirmt + bestätigt");
        check(s.exceptions.count == 2, "nur gültige Ausnahmen");
        MeshException *ssh = s.exceptions[0];
        check([ssh.proto isEqual:@"tcp"] && ssh.port == 22 && [ssh.name isEqual:@"SSH"], "SSH-Ausnahme");
        check([s.exceptions[1] name] == nil, "unbekannter Dienst ohne Namen");

        NSMutableDictionary *m = [f mutableCopy];
        m[@"pf"] = @"0";
        check([MeshGuardStatus statusFromFields:m].level == MeshLevelOpen, "Datei sagt an, pf aus = offen");
        m = [f mutableCopy]; m[@"cut"] = @"1";
        check([MeshGuardStatus statusFromFields:m].level == MeshLevelCut, "Notschalter geht vor");
        m = [f mutableCopy]; m[@"shield"] = @"yes";
        check(![MeshGuardStatus statusFromFields:m].shieldOn, "nur \"1\" zählt als an");
        check([MeshGuardStatus statusFromFields:@{ @"shield": @"1" }].level == MeshLevelUnknown, "ohne helper=1 unbekannt");
        check([MeshGuardStatus unknown].level == MeshLevelUnknown && [MeshGuardStatus unknown].exceptions.count == 0, "unknown");

        MeshConnection *c = [MeshConnection connectionFromLine:@"1760000000\tout\ttcp\tMobileSafari\t192.168.1.5:50123\t93.184.216.34:443\tblock"];
        check(c && !c.incoming && c.blocked && [c.process isEqual:@"MobileSafari"], "Verbindung gelesen");
        check([c.time timeIntervalSince1970] == 1760000000, "Zeit");
        check([MeshConnection connectionFromLine:@"1760000000\tout\ttcp\tX\ta\tb"] == nil, "zu wenig Felder");
        check([MeshConnection connectionFromLine:@"1760000000\tsideways\ttcp\tX\ta\tb\tpass"] == nil, "unbekannte Richtung");
        check([MeshConnection connectionFromLine:@"1760000000\tin\ticmp\tX\ta\tb\tpass"] == nil, "unbekanntes Protokoll");
        check([MeshConnection connectionFromLine:@"1760000000\tin\ttcp\tX\ta\tb\tmaybe"] == nil, "unbekanntes Urteil");
        check([MeshConnection connectionFromLine:@"0\tin\ttcp\tX\ta\tb\tpass"] == nil, "Zeit 0");
        check([MeshConnection connectionFromLine:@"1760000000\tin\ttcp\t\ta\tb\tpass"] == nil, "leerer Prozess");
        NSArray *conns = @[
            [MeshConnection connectionFromLine:@"1760000100\tout\ttcp\tMeshMusic\t10.0.0.2:1\t1.2.3.4:443\tpass"],
            [MeshConnection connectionFromLine:@"1760000200\tout\ttcp\tMeshMusic\t10.0.0.2:2\t1.2.3.5:443\tpass"],
            [MeshConnection connectionFromLine:@"1760000150\tout\ttcp\tMeshMusic\t10.0.0.2:3\t1.2.3.4:80\tpass"],
            [MeshConnection connectionFromLine:@"1760000300\tout\ttcp\tMobileSafari\t10.0.0.2:4\t2a00:1450::1:443\tpass"],
            [MeshConnection connectionFromLine:@"1760000400\tin\ttcp\tsshd\t10.0.0.2:22\t10.0.0.9:5000\tpass"],
        ];
        check([[conns[0] remoteHost] isEqual:@"1.2.3.4"] && [[conns[3] remoteHost] isEqual:@"2a00:1450::1"], "Gegenstelle ohne Port (v4/v6)");
        NSMutableArray *withTor = [conns mutableCopy];
        [withTor addObject:[MeshConnection connectionFromLine:@"1760000500\tout\ttcp\tmesh-tor\t10.0.0.2:5\t64.65.62.58:443\tpass"]];
        NSArray *installed = @[ @{ @"name": @"Musik", @"executable": @"MeshMusic", @"bundleId": @"de.mesh.music", @"iconPath": @"/x/Icon@2x.png" },
                                @{ @"name": @"Safari", @"executable": @"MobileSafari", @"bundleId": @"com.apple.mobilesafari" },
                                @{ @"name": @"Abc", @"executable": @"Abc", @"bundleId": @"com.x.abc" },
                                @{ @"name": @"Mesh", @"executable": @"Mesh", @"bundleId": @"de.mesh.ios" } ];
        NSArray *apps = [MeshAppActivity activitiesForInstalled:installed connections:withTor allowedApps:@[ @"Mesh", @"mesh-tor", @"MobileSafari", @"Fremd" ]];
        check(apps.count == 4, "vier Apps, Tor bei Mesh, keine Systemprozesse ohne Verkehr");
        MeshAppActivity *mesh = apps[0], *music = apps[1], *abc = apps[2], *safari = apps[3];
        check([mesh.name isEqual:@"Mesh"] && mesh.isMessenger && mesh.allowed && mesh.destinations == 1, "Mesh zuerst, Tor-Verkehr zählt");
        check([music.name isEqual:@"Musik"] && music.isMesh && !music.allowed && music.destinations == 2, "Mesh-Apps danach, nicht erlaubt");
        check([abc.name isEqual:@"Abc"] && !abc.lastSeen && !abc.allowed, "übrige nach Name");
        check([safari.process isEqual:@"MobileSafari"] && safari.allowed, "erlaubt");
        check(![[apps valueForKey:@"process"] containsObject:@"mesh-tor"], "mesh-tor nicht extra");
        NSArray *off = [MeshAppActivity activitiesForInstalled:installed connections:withTor allowedApps:@[ @"MobileSafari" ]];
        check([off[0] isMessenger] && ![off[0] allowed], "Mesh lässt sich ausschalten");
        NSArray *none = [MeshAppActivity activitiesForInstalled:[installed subarrayWithRange:NSMakeRange(0, 3)] connections:conns allowedApps:@[]];
        check(![[none valueForKey:@"isMessenger"] containsObject:@YES] && [[none[0] name] isEqual:@"Musik"], "ohne Mesh: Mesh-Apps oben, kein Mesh-Eintrag");
        NSDictionary *af = [MeshHelper fieldsFromOutput:@"helper=1\napps=MeshMusic,Tube\n"];
        check([[MeshGuardStatus statusFromFields:af].allowedApps isEqual:(@[ @"MeshMusic", @"Tube" ])], "erlaubte Apps gelesen");
        return testsDone();
    }
}
