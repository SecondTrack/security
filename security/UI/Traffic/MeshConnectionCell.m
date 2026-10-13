#import "MeshConnectionCell.h"
#import "MeshConnection.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshControls.h"
#import "MeshL10n.h"

static const CGFloat kRowHeight = 58, kTextX = 52;

@implementation MeshConnectionCell {
    UIImageView *_dir;
    UILabel *_title, *_meta, *_verdict;
}

+ (CGFloat)height { return kRowHeight; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [MeshTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleGray;
        CGFloat W = [UIScreen mainScreen].bounds.size.width;
        _dir = [[UIImageView alloc] initWithFrame:CGRectMake(16, (kRowHeight - 22) / 2, 22, 22)];
        [self.contentView addSubview:_dir];
        _title = [MeshControls labelWithFrame:CGRectMake(kTextX, 10, W - kTextX - 76, 20) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
        [self.contentView addSubview:_title];
        _meta = [MeshControls labelWithFrame:CGRectMake(kTextX, 31, W - kTextX - 16, 16) font:[MeshTheme monoFont] color:[MeshTheme faint]];
        [self.contentView addSubview:_meta];
        _verdict = [MeshControls labelWithFrame:CGRectMake(W - 86, 10, 70, 20) font:[MeshTheme labelFont] color:[MeshTheme accent]];
        _verdict.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_verdict];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(kTextX, kRowHeight - 0.5f, W - kTextX, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self.contentView addSubview:line];
    }
    return self;
}

- (void)showConnection:(MeshConnection *)c blocked:(BOOL)blocked {
    static NSDateFormatter *fmt;
    if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm:ss"; }
    UIColor *color = blocked ? [MeshTheme danger] : c.incoming ? [MeshTheme accent] : [MeshTheme muted];
    _dir.image = [MeshGlyphs icon:(c.incoming ? @"back" : @"forward") color:color size:22];
    _title.text = [NSString stringWithFormat:@"%@ → %@", c.process, c.incoming ? c.local : c.remote];
    _meta.text = [NSString stringWithFormat:@"%@  %@  %@", [fmt stringFromDate:c.time], c.incoming ? L(@"in") : L(@"out"), c.proto];
    _verdict.text = blocked ? L(@"BLOCKED") : nil;
    _verdict.textColor = color;
}

@end
