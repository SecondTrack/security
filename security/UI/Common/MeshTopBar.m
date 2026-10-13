#import "MeshTopBar.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshGuard.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

static const CGFloat kBarHeight = 66, kChipHeight = 28;

@implementation MeshTopBar {
    UILabel *_title, *_subtitle;
    UIView *_chip;
    UIImageView *_chipIcon;
    UILabel *_chipLabel;
}

+ (CGFloat)height { return [MeshTheme topInset] + kBarHeight; }

- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title subtitle:(NSString *)subtitle {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, [MeshTopBar height])])) {
        CGFloat top = [MeshTheme topInset];
        UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake(14, top + 14, 38, 38)];
        logo.image = [MeshGlyphs logo:38];
        [self addSubview:logo];
        _title = [self addLabel:title font:[MeshTheme brandFont] color:[MeshTheme ink] frame:CGRectMake(62, top + 12, width - 180, 30)];
        _subtitle = [self addLabel:subtitle font:[MeshTheme timeFont] color:[MeshTheme muted] frame:CGRectMake(62, top + 43, width - 180, 14)];

        _chip = [[UIView alloc] init];
        _chip.layer.cornerRadius = kChipHeight / 2;
        _chip.layer.borderWidth = 1;
        _chip.layer.borderColor = [MeshTheme line].CGColor;
        _chipIcon = [[UIImageView alloc] initWithFrame:CGRectMake(11, (kChipHeight - 15) / 2, 15, 15)];
        [_chip addSubview:_chipIcon];
        _chipLabel = [[UILabel alloc] init];
        _chipLabel.font = [MeshTheme timeFont];
        _chipLabel.backgroundColor = [UIColor clearColor];
        [_chip addSubview:_chipLabel];
        [_chip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:[MeshGuard shared] action:@selector(refresh)]];
        [self addSubview:_chip];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatus)
                                                     name:MeshGuardChangedNotification object:nil];
        [self updateStatus];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (UILabel *)addLabel:(NSString *)text font:(UIFont *)font color:(UIColor *)color frame:(CGRect)frame {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text; l.font = font; l.textColor = color; l.backgroundColor = [UIColor clearColor];
    l.adjustsFontSizeToFitWidth = YES;
    [self addSubview:l];
    return l;
}

// Chip passt sich der Textbreite an und steht rechtsbündig; der Titel nimmt den Rest.
- (void)updateStatus {
    MeshGuardStatus *s = [MeshGuard shared].status;
    NSString *text, *icon = @"shield";
    UIColor *color, *fill = [MeshTheme surface];
    switch (s.level) {
        case MeshLevelShielded: text = L(@"Shielded"); color = [MeshTheme accent]; fill = [MeshTheme accentDeep]; break;
        case MeshLevelOpen:     text = L(@"Open");      color = [MeshTheme muted]; icon = @"shieldoff"; break;
        case MeshLevelCut:      text = L(@"Cut off");   color = [MeshTheme danger]; icon = @"power"; break;
        default:                text = L(@"Checking …"); color = [MeshTheme faint]; break;
    }
    _chipLabel.text = text;
    _chipLabel.textColor = color;
    _chipIcon.image = [MeshGlyphs icon:icon color:color size:15];
    _chip.backgroundColor = fill;
    CGFloat W = self.bounds.size.width, lw = [text sizeWithFont:[MeshTheme timeFont]].width, chipW = 32 + lw + 12;
    _chip.frame = CGRectMake(W - 14 - chipW, [MeshTheme topInset] + 20, chipW, kChipHeight);
    _chipLabel.frame = CGRectMake(32, 0, lw + 4, kChipHeight);
    CGFloat textW = CGRectGetMinX(_chip.frame) - 8 - 62;
    _title.frame = CGRectMake(62, _title.frame.origin.y, textW, _title.frame.size.height);
    _subtitle.frame = CGRectMake(62, _subtitle.frame.origin.y, textW, _subtitle.frame.size.height);
}

@end
