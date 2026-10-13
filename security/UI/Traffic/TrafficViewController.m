#import "TrafficViewController.h"
#import "MeshConnectionCell.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshControls.h"
#import "MeshToggle.h"
#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshGuard.h"
#import "MeshConnection.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

static const CGFloat kMargin = 14, kCardHeight = 64;

@interface TrafficViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TrafficViewController {
    MeshToggle *_logSwitch;
    UITableView *_table;
    UILabel *_empty;
    NSArray *_connections;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = [MeshPageHeader height], bottom = 0;
    [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:L(@"Connections") target:self back:@selector(mesh_goBack)]];

    UIView *card = [MeshControls switchCardWithFrame:CGRectMake(kMargin, top + 12, W - 2 * kMargin, kCardHeight) title:L(@"Write down connections")
                                            subtitle:L(@"In and out, stays on this iPod") on:[MeshGuard shared].status.logging
                                              target:self action:@selector(logSwitched:)];
    for (UIView *v in card.subviews) if ([v isKindOfClass:[MeshToggle class]]) _logSwitch = (MeshToggle *)v;
    [self.view addSubview:card];

    CGFloat tableTop = top + 12 + kCardHeight + 10;
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, tableTop, W, H - tableTop - bottom) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = [MeshConnectionCell height];
    _table.dataSource = self;
    _table.delegate = self;
    [self.view addSubview:_table];

    _empty = [MeshControls labelWithFrame:CGRectMake(30, tableTop + 40, W - 60, 60) font:[MeshTheme previewFont] color:[MeshTheme faint]];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    [self.view addSubview:_empty];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged) name:MeshGuardChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:MeshTrafficChangedNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil;   // iOS 5: Delegates sind nicht schwach
    _table.delegate = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)statusChanged {
    _logSwitch.on = [MeshGuard shared].status.logging;
    [_table reloadData];   // Sperrliste kann sich geändert haben
}

- (void)reload {
    [[MeshGuard shared] loadConnections:^(NSArray *list) {
        self->_connections = list;
        self->_empty.text = list.count ? nil
            : ([MeshGuard shared].status.logging ? L(@"No connections yet.") : L(@"Switch on the log to see which app talks to whom."));
        [self->_table reloadData];
    }];
}

- (void)logSwitched:(MeshToggle *)sw {
    [[MeshGuard shared] setLogging:sw.on completion:^(MeshGuardResult r) {
        if (r != MeshGuardResultOK) [MeshPopup info:[MeshGuard describe:r]];
        [self reload];
    }];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)_connections.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    MeshConnectionCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[MeshConnectionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    MeshConnection *c = _connections[(NSUInteger)ip.row];
    [cell showConnection:c blocked:(c.blocked || [[MeshGuard shared].status.blockedHosts containsObject:[c remoteHost]])];
    return cell;
}

// Antippen: Ziel sperren bzw. freigeben. Gilt für alle Apps, weil pf Apps nicht unterscheiden kann.
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    MeshConnection *c = _connections[(NSUInteger)ip.row];
    NSString *host = [c remoteHost];
    if (c.incoming || !host.length) return;
    BOOL blocked = [[MeshGuard shared].status.blockedHosts containsObject:host];
    NSString *option = blocked ? L(@"Unblock this destination") : L(@"Block this destination for all apps");
    [MeshPopup sheet:host options:@[ option ] destructiveIndex:(blocked ? -1 : 0) handler:^(NSInteger idx) {
        if (idx != 0) return;
        [[MeshGuard shared] setHost:host blocked:!blocked completion:^(MeshGuardResult r) {
            if (r != MeshGuardResultOK) { [MeshPopup info:[MeshGuard describe:r]]; return; }
            if (!blocked && ![MeshGuard shared].status.shieldOn) [MeshPopup info:L(@"Blocked. It takes effect as soon as the shield is on.")];
        }];
    }];
}

@end
