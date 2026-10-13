#import "MeshAppCell.h"
#import "MeshAppActivity.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshControls.h"
#import "MeshL10n.h"

static const CGFloat kRowHeight = 60, kIcon = 40, kTextX = 68;

@implementation MeshAppCell {
    UIImageView *_icon;
    UILabel *_name, *_detail;
}

+ (CGFloat)height { return kRowHeight; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [MeshTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        CGFloat W = [UIScreen mainScreen].bounds.size.width;
        _icon = [[UIImageView alloc] initWithFrame:CGRectMake(16, (kRowHeight - kIcon) / 2, kIcon, kIcon)];
        _icon.layer.cornerRadius = 9;
        _icon.clipsToBounds = YES;
        _icon.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_icon];
        _name = [MeshControls labelWithFrame:CGRectMake(kTextX, 11, W - kTextX - 80, 20) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
        [self.contentView addSubview:_name];
        _detail = [MeshControls labelWithFrame:CGRectMake(kTextX, 32, W - kTextX - 80, 16) font:[MeshTheme timeFont] color:[MeshTheme muted]];
        [self.contentView addSubview:_detail];
        _toggle = [[UISwitch alloc] init];
        _toggle.onTintColor = [MeshTheme accent];
        _toggle.center = CGPointMake(W - 16 - _toggle.bounds.size.width / 2, kRowHeight / 2);
        [self.contentView addSubview:_toggle];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(kTextX, kRowHeight - 0.5f, W - kTextX, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self.contentView addSubview:line];
    }
    return self;
}

- (void)showApp:(MeshAppActivity *)a icon:(UIImage *)icon {
    if (icon) {
        _icon.image = icon;
        _icon.contentMode = UIViewContentModeScaleAspectFill;
        _icon.backgroundColor = [UIColor clearColor];
    } else {   // Systemprozess oder App ohne Icon: Symbol-Kachel
        _icon.image = [MeshGlyphs icon:(a.isApp ? @"apps" : @"traffic") color:[MeshTheme muted] size:20];
        _icon.contentMode = UIViewContentModeCenter;
        _icon.backgroundColor = [MeshTheme surfaceHi];
    }
    _icon.alpha = a.allowed ? 1 : 0.45f;
    _name.text = a.name;
    if (!a.allowed) {
        _detail.text = a.isMessenger ? L(@"No internet, Tor off too") : L(@"No internet");
        _detail.textColor = [MeshTheme muted];
    } else {
        if (a.isMessenger) _detail.text = L(@"Allowed, with Tor");
        else _detail.text = a.lastSeen ? LF(@"Allowed · %lu destinations", (unsigned long)a.destinations) : L(@"Allowed");
        _detail.textColor = [MeshTheme accent];
    }
    _toggle.on = a.allowed;
}

@end
