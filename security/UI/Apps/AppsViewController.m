#import "AppsViewController.h"
#import "MeshAppCell.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshControls.h"
#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshGuard.h"
#import "MeshAppActivity.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

static const CGFloat kMargin = 16;

@interface AppsViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation AppsViewController {
    UITableView *_table;
    UILabel *_intro;
    NSArray *_apps, *_system;   // MeshAppActivity: installierte Apps, Systemprozesse
    NSCache *_icons;            // Pfad → UIImage
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = [MeshPageHeader height];
    [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:L(@"Apps") target:self back:@selector(mesh_goBack)]];
    _icons = [[NSCache alloc] init];
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, top, W, H - top) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = [MeshAppCell height];
    _table.dataSource = self;
    _table.delegate = self;
    _intro = [MeshControls labelWithFrame:CGRectMake(kMargin, 12, W - 2 * kMargin, 0) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    _intro.numberOfLines = 0;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 60)];
    [head addSubview:_intro];
    _table.tableHeaderView = head;
    [self.view addSubview:_table];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:MeshGuardChangedNotification object:nil];
    [self updateIntro];
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

- (void)updateIntro {
    _intro.text = [MeshGuard shared].status.shieldOn
        ? L(@"Only apps that are switched on may go online.")
        : L(@"Takes effect while the shield is on: then only apps that are switched on may go online.");
    CGFloat w = _intro.frame.size.width;
    CGSize sz = [_intro.text sizeWithFont:_intro.font constrainedToSize:CGSizeMake(w, 200) lineBreakMode:NSLineBreakByWordWrapping];
    _intro.frame = CGRectMake(_intro.frame.origin.x, 12, w, sz.height);
    UIView *head = _table.tableHeaderView;
    head.frame = CGRectMake(0, 0, head.frame.size.width, sz.height + 20);
    _table.tableHeaderView = head;   // neu setzen, damit die Tabelle die Höhe übernimmt
}

- (void)reload {
    [self updateIntro];
    [[MeshGuard shared] loadApps:^(NSArray *all) {
        NSMutableArray *apps = [NSMutableArray array], *system = [NSMutableArray array];
        for (MeshAppActivity *a in all) [(a.isApp ? apps : system) addObject:a];
        self->_apps = apps;
        self->_system = system;
        [self->_table reloadData];
    }];
}

- (NSArray *)rowsIn:(NSInteger)section { return section == 0 ? _apps : _system; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)[self rowsIn:section].count; }

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return [self rowsIn:section].count ? 30 : 0; }

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 30)];
    v.backgroundColor = [MeshTheme bg];
    [v addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(kMargin, 8, tv.bounds.size.width - 2 * kMargin, 16)
                                                text:(section == 0 ? L(@"APPS") : L(@"SYSTEM"))]];
    return v;
}

- (UIImage *)iconFor:(MeshAppActivity *)a {
    if (!a.iconPath) return nil;
    UIImage *img = [_icons objectForKey:a.iconPath];
    if (!img && (img = [UIImage imageWithContentsOfFile:a.iconPath])) [_icons setObject:img forKey:a.iconPath];
    return img;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    MeshAppCell *cell = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[MeshAppCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];
        [cell.toggle addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
    }
    MeshAppActivity *a = [self rowsIn:ip.section][(NSUInteger)ip.row];
    [cell showApp:a icon:[self iconFor:a]];
    cell.toggle.tag = ip.section * 100000 + ip.row;
    return cell;
}

- (void)switched:(UISwitch *)sw {
    NSArray *rows = [self rowsIn:sw.tag / 100000];
    NSUInteger row = (NSUInteger)(sw.tag % 100000);
    if (row >= rows.count) return;
    MeshAppActivity *a = rows[row];
    [[MeshGuard shared] setApp:a.process allowed:sw.on completion:^(MeshGuardResult r) {
        if (r != MeshGuardResultOK) [MeshPopup info:[MeshGuard describe:r]];
        [self reload];
    }];
}

@end
