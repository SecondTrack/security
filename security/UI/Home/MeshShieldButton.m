#import "MeshShieldButton.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"

static const CGFloat kSize = 136, kGlyph = 58;

@implementation MeshShieldButton {
    UIImageView *_glyph;
    UIActivityIndicatorView *_spinner;
}

+ (CGFloat)size { return kSize; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, kSize, kSize)])) {
        self.layer.cornerRadius = kSize / 2;
        self.layer.borderWidth = 3;
        _glyph = [[UIImageView alloc] initWithFrame:CGRectMake((kSize - kGlyph) / 2, (kSize - kGlyph) / 2, kGlyph, kGlyph)];
        _glyph.userInteractionEnabled = NO;
        [self addSubview:_glyph];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.center = CGPointMake(kSize / 2, kSize / 2);
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
    }
    return self;
}

- (void)showLevel:(MeshLevel)level busy:(BOOL)busy {
    BOOL on = level == MeshLevelShielded;
    UIColor *c = level == MeshLevelCut ? [MeshTheme danger] : on ? [MeshTheme accent] : [MeshTheme faint];
    self.backgroundColor = on ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    self.layer.borderColor = (on ? c : [MeshTheme line]).CGColor;
    _glyph.image = [MeshGlyphs icon:(level == MeshLevelCut ? @"power" : on ? @"shield" : @"shieldoff") color:c size:kGlyph];
    _glyph.hidden = busy;
    self.enabled = !busy && level != MeshLevelUnknown;
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}

@end
