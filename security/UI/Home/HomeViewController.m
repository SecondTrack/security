#import "HomeViewController.h"
#import "MeshShieldButton.h"
#import "TrafficViewController.h"
#import "AppsViewController.h"
#import "MeshScreen.h"
#import "MeshTopBar.h"
#import "MeshMenuRow.h"
#import "MeshControls.h"
#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshGuard.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

static const CGFloat kMargin = 14;

@implementation HomeViewController {
    UIScrollView *_scroll;
    MeshShieldButton *_shield;
    NSString *_password;     // erzeugtes Passwort, solange abgeschirmt
    BOOL _busy;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = [MeshTopBar height];
    [self.view addSubview:[[MeshTopBar alloc] initWithWidth:W title:L(@"Security") subtitle:L(@"Mesh · protection for your iPod")]];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, top, W, H - top)];
    [self.view addSubview:_scroll];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged) name:MeshGuardChangedNotification object:nil];
    [self rebuild];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[MeshGuard shared] refresh];
}

- (void)statusChanged {
    MeshGuardStatus *s = [MeshGuard shared].status;
    if (s.passwordGenerated && s.shieldOn && !_password) {
        [[MeshGuard shared] loadPassword:^(NSString *pw) { self->_password = pw; [self rebuild]; }];
    }
    if (!s.passwordGenerated || !s.shieldOn) _password = nil;
    [self rebuild];
}

#pragma mark - Aufbau

- (void)rebuild {
    for (UIView *v in [_scroll.subviews copy]) [v removeFromSuperview];
    MeshGuardStatus *s = [MeshGuard shared].status;
    MeshLevel level = s.level;
    BOOL on = level == MeshLevelShielded;
    CGFloat W = _scroll.bounds.size.width, cw = W - 2 * kMargin, y = 20;

    _shield = [[MeshShieldButton alloc] initWithFrame:CGRectMake((W - [MeshShieldButton size]) / 2, y, 0, 0)];
    [_shield showLevel:level busy:_busy];
    [_shield addTarget:self action:@selector(toggleShield) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_shield];
    y += [MeshShieldButton size] + 14;

    UILabel *head = [MeshControls labelWithFrame:CGRectMake(kMargin, y, cw, 26) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    head.textAlignment = NSTextAlignmentCenter;
    head.text = level == MeshLevelCut ? L(@"Everything is disconnected") : on ? L(@"Shielded") : level == MeshLevelOpen ? L(@"Not shielded") : L(@"Checking your iPod …");
    [_scroll addSubview:head];
    y += 28;
    y += 8;
    // Klarer Knopf unter dem Schild: der Kreis allein sieht nicht nach Schalter aus. Während der Helfer
    // arbeitet, sagt er das und ist gesperrt.
    if (level == MeshLevelOpen || on) {
        CGFloat bw = 210, bh = 42;
        CGRect f = CGRectMake((W - bw) / 2, y, bw, bh);
        NSString *title = _busy ? L(@"Please wait …") : on ? L(@"Undo shield") : L(@"Shield now");
        UIButton *b = (on || _busy) ? [MeshControls secondaryButtonWithFrame:f title:title target:self action:@selector(toggleShield)]
                                    : [MeshControls primaryButtonWithFrame:f title:title target:self action:@selector(toggleShield)];
        b.layer.cornerRadius = bh / 2;
        b.titleLabel.font = [MeshTheme bodyFont];
        b.enabled = !_busy;
        [_scroll addSubview:b];
        y += bh + 16;
    }
    if (on && _password) y = [self addPasswordCardAt:y width:cw] + 14;
    y = [self addFactsAt:y width:cw status:s on:on] + 18;
    y = [self addExceptionsAt:y width:W status:s] + 18;
    if (s.blockedHosts.count) y = [self addBlockedAt:y width:W status:s] + 18;

    [_scroll addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(kMargin + 2, y, cw, 16) text:L(@"MORE")]];
    y += 22;
    y = [MeshMenuRow addTo:_scroll y:y width:W icon:@"apps" title:L(@"Apps")
                  subtitle:LF(@"%lu may go online", (unsigned long)(s.allowedApps.count - ([s.allowedApps containsObject:@"mesh-tor"] ? 1 : 0)))
                    target:self action:@selector(openApps)];
    y = [MeshMenuRow addTo:_scroll y:y width:W icon:@"traffic" title:L(@"Connections")
                  subtitle:(s.logging ? L(@"Being written down, tap one to block it") : L(@"See which app talks to whom")) target:self action:@selector(openTraffic)];
    y = [MeshMenuRow addTo:_scroll y:y width:W icon:@"power" title:(s.cut ? L(@"Reconnect") : L(@"Disconnect everything"))
                  subtitle:(s.cut ? L(@"Lift the emergency switch") : L(@"Emergency switch, Mesh included")) target:self action:@selector(toggleCut)];
    y = [MeshMenuRow addTo:_scroll y:y width:W icon:@"reset" title:L(@"Reset everything")
                  subtitle:L(@"Back to how the iPod was before") target:self action:@selector(resetAll)];
    _scroll.contentSize = CGSizeMake(W, y + 24);
}

// Karte mit dem erzeugten Passwort: groß, Festbreite, damit es sich abschreiben lässt.
- (CGFloat)addPasswordCardAt:(CGFloat)y width:(CGFloat)cw {
    UIView *card = [MeshControls cardWithFrame:CGRectMake(kMargin, y, cw, 112)];
    [card addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(14, 12, cw - 28, 16) text:L(@"NEW PASSWORD FOR ROOT AND MOBILE")]];
    UILabel *pw = [MeshControls labelWithFrame:CGRectMake(14, 32, cw - 28, 34) font:[UIFont fontWithName:@"Menlo-Bold" size:26] ?: [MeshTheme monoBigFont]
                                         color:[MeshTheme accent]];
    pw.text = _password;
    pw.textAlignment = NSTextAlignmentCenter;
    [card addSubview:pw];
    UILabel *n = [MeshControls labelWithFrame:CGRectMake(14, 70, cw - 28, 32) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    n.text = L(@"Replaces \"alpine\" for SSH. Write it down. Switching off brings \"alpine\" back.");
    n.numberOfLines = 2;
    [card addSubview:n];
    [_scroll addSubview:card];
    return y + 112;
}

// Was der Schalter tut (aus) bzw. was gerade gilt (an), je Zeile mit Symbol.
- (CGFloat)addFactsAt:(CGFloat)y width:(CGFloat)cw status:(MeshGuardStatus *)s on:(BOOL)on {
    NSArray *facts;
    BOOL alpine = s.rootHasDefaultPassword || s.mobileHasDefaultPassword;
    if (on) facts = @[
        @[ @"key",    alpine ? L(@"Default password \"alpine\" is still active") : L(@"No default password") , @(!alpine) ],
        @[ @"lock",   L(@"All incoming ports are closed"), @YES ],
        @[ @"apps",   L(@"Only allowed apps go online"), @YES ],
        @[ @"wifi",   s.exceptions.count ? LF(@"%lu exceptions, only from your Wi-Fi", (unsigned long)s.exceptions.count) : L(@"No exceptions"), @YES ],
    ];
    else facts = @[
        @[ @"key",    alpine ? L(@"Replaces the default password \"alpine\"") : L(@"Your password stays as it is"), @(!alpine) ],
        @[ @"lock",   L(@"Closes every incoming port you do not need"), @NO ],
        @[ @"apps",   L(@"Only Mesh and the apps you allow go online"), @NO ],
        @[ @"reset",  L(@"Switching off undoes everything"), @NO ],
    ];
    UIView *card = [MeshControls cardWithFrame:CGRectMake(kMargin, y, cw, 14 + facts.count * 32)];
    CGFloat fy = 10;
    for (NSArray *f in facts) {
        BOOL good = [f[2] boolValue];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(14, fy + 4, 20, 20)];
        iv.image = [MeshGlyphs icon:f[0] color:(on ? (good ? [MeshTheme accent] : [MeshTheme danger]) : [MeshTheme muted]) size:20];
        [card addSubview:iv];
        UILabel *l = [MeshControls labelWithFrame:CGRectMake(46, fy, cw - 60, 28) font:[MeshTheme previewFont] color:[MeshTheme ink]];
        l.text = f[1];
        l.adjustsFontSizeToFitWidth = YES;
        [card addSubview:l];
        fy += 32;
    }
    [_scroll addSubview:card];
    return y + card.frame.size.height;
}

- (CGFloat)addExceptionsAt:(CGFloat)y width:(CGFloat)W status:(MeshGuardStatus *)s {
    [_scroll addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(kMargin + 2, y, W - 2 * kMargin, 16) text:L(@"EXCEPTIONS")]];
    y += 22;
    for (NSUInteger i = 0; i < s.exceptions.count; i++) {
        MeshException *e = s.exceptions[i];
        NSString *title = e.name ?: LF(@"Port %ld", (long)e.port);
        NSString *sub = LF(@"%@ %ld · only from your Wi-Fi", [e.proto uppercaseString], (long)e.port);
        MeshMenuRow *row = [MeshMenuRow rowAtY:y width:W icon:@"wifi" title:title subtitle:sub];
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(tapException:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:row];
        y += [MeshMenuRow height];
    }
    return [MeshMenuRow addTo:_scroll y:y width:W icon:@"add" title:L(@"Add exception")
                     subtitle:L(@"Keep a port reachable from your Wi-Fi") target:self action:@selector(addException)];
}

// Gesperrte Ziele (aus dem Verbindungsprotokoll); Antippen gibt frei.
- (CGFloat)addBlockedAt:(CGFloat)y width:(CGFloat)W status:(MeshGuardStatus *)s {
    [_scroll addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(kMargin + 2, y, W - 2 * kMargin, 16) text:L(@"BLOCKED DESTINATIONS")]];
    y += 22;
    for (NSUInteger i = 0; i < s.blockedHosts.count; i++) {
        MeshMenuRow *row = [MeshMenuRow rowAtY:y width:W icon:@"close" title:s.blockedHosts[i]
                                      subtitle:(s.shieldOn ? L(@"Blocked for all apps") : L(@"Takes effect when shielded"))];
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(tapBlocked:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:row];
        y += [MeshMenuRow height];
    }
    return y;
}

#pragma mark - Aktionen

- (void)tapBlocked:(UIButton *)row {
    NSString *host = [MeshGuard shared].status.blockedHosts[(NSUInteger)row.tag];
    [MeshPopup sheet:host options:@[ L(@"Unblock this destination") ] destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx == 0) [[MeshGuard shared] setHost:host blocked:NO completion:^(MeshGuardResult r) {
            if (r != MeshGuardResultOK) [MeshPopup info:[MeshGuard describe:r]];
        }];
    }];
}


static void report(MeshGuardResult r) { if (r != MeshGuardResultOK) [MeshPopup info:[MeshGuard describe:r]]; }

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self rebuild];
}

- (void)toggleShield {
    MeshGuardStatus *s = [MeshGuard shared].status;
    if (!s.shieldOn) {
        [self setBusy:YES];
        [[MeshGuard shared] setShield:YES completion:^(MeshGuardResult r) { [self setBusy:NO]; report(r); }];
        return;
    }
    NSString *msg = s.passwordGenerated ? L(@"All ports open again and the password goes back to \"alpine\".")
                                        : L(@"All ports open again.");
    [MeshPopup confirm:L(@"Undo the shield?") message:msg action:L(@"Undo") destructive:YES handler:^(BOOL ok) {
        if (!ok) return;
        [self setBusy:YES];
        [[MeshGuard shared] setShield:NO completion:^(MeshGuardResult r) { [self setBusy:NO]; report(r); }];
    }];
}

- (void)tapException:(UIButton *)row {
    MeshException *e = [MeshGuard shared].status.exceptions[(NSUInteger)row.tag];
    [MeshPopup sheet:(e.name ?: LF(@"Port %ld", (long)e.port)) options:@[ L(@"Remove exception") ] destructiveIndex:0 handler:^(NSInteger idx) {
        if (idx == 0) [[MeshGuard shared] removeException:e completion:^(MeshGuardResult r) { report(r); }];
    }];
}

- (void)addException {
    NSArray *options = @[ L(@"SSH (TCP 22)"), L(@"FileTransfer (TCP 8080)"), L(@"Other port …") ];
    [MeshPopup sheet:L(@"ADD EXCEPTION") options:options destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx == 0) [self add:[[MeshException alloc] initWithProto:@"tcp" port:22]];
        else if (idx == 1) [self add:[[MeshException alloc] initWithProto:@"tcp" port:8080]];
        else if (idx == 2) [self askPort];
    }];
}

- (void)askPort {
    [MeshPopup input:L(@"Other port") message:L(@"Number between 1 and 65535") placeholder:@"5000" secure:NO numeric:YES
             handler:^(NSString *text, BOOL ok) {
        if (!ok) return;
        NSInteger port = text.integerValue;
        if (port < 1 || port > 65535 || ![text isEqual:[NSString stringWithFormat:@"%ld", (long)port]]) {
            [MeshPopup info:L(@"Please enter a number between 1 and 65535.")];
            return;
        }
        [MeshPopup sheet:LF(@"Port %ld", (long)port) options:@[ @"TCP", @"UDP" ] destructiveIndex:-1 handler:^(NSInteger idx) {
            if (idx >= 0) [self add:[[MeshException alloc] initWithProto:(idx == 0 ? @"tcp" : @"udp") port:port]];
        }];
    }];
}

- (void)add:(MeshException *)e { [[MeshGuard shared] addException:e completion:^(MeshGuardResult r) { report(r); }]; }

- (void)openApps { [self.navigationController pushViewController:[[AppsViewController alloc] init] animated:YES]; }

- (void)openTraffic { [self.navigationController pushViewController:[[TrafficViewController alloc] init] animated:YES]; }

// Trennen ohne Rückfrage (Notfall), Wiederverbinden mit Rückfrage.
- (void)toggleCut {
    if (![MeshGuard shared].status.cut) { [[MeshGuard shared] setCut:YES completion:^(MeshGuardResult r) { report(r); }]; return; }
    [MeshPopup confirm:L(@"Reconnect?") message:L(@"The emergency switch is lifted. The shield stays as it was.")
                action:L(@"Reconnect") destructive:NO handler:^(BOOL ok) {
        if (ok) [[MeshGuard shared] setCut:NO completion:^(MeshGuardResult r) { report(r); }];
    }];
}

- (void)resetAll {
    [MeshPopup confirm:L(@"Reset everything?")
               message:L(@"The shield, exceptions, emergency switch and connection log are removed. The password goes back to how it was.")
                action:L(@"Reset") destructive:YES handler:^(BOOL ok) {
        if (ok) [[MeshGuard shared] resetAll:^(MeshGuardResult r) { [MeshPopup info:[MeshGuard describe:r]]; }];
    }];
}

@end
