#import "MeshToggle.h"
#import "MeshTheme.h"

static const CGFloat kWidth = 46, kHeight = 28, kInset = 3;

@implementation MeshToggle {
    UIView *_track, *_knob;
    BOOL _moved;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, kWidth, kHeight)])) {
        self.backgroundColor = [UIColor clearColor];
        _track = [[UIView alloc] initWithFrame:self.bounds];
        _track.layer.cornerRadius = kHeight / 2;
        _track.layer.borderWidth = 1;
        _track.userInteractionEnabled = NO;
        [self addSubview:_track];
        CGFloat k = kHeight - 2 * kInset;
        _knob = [[UIView alloc] initWithFrame:CGRectMake(kInset, kInset, k, k)];
        _knob.layer.cornerRadius = k / 2;
        _knob.userInteractionEnabled = NO;
        [self addSubview:_knob];
        [self paint];
    }
    return self;
}

- (instancetype)init { return [self initWithFrame:CGRectZero]; }

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    if (animated) [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ [self paint]; } completion:nil];
    else [self paint];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.4f;
}

// An: Mint-Spur, dunkler Knopf. Aus: erhöhte Fläche mit Rahmen, gedämpfter Knopf.
- (void)paint {
    CGFloat k = _knob.bounds.size.width;
    _knob.frame = CGRectMake(_on ? kWidth - kInset - k : kInset, kInset, k, k);
    _track.backgroundColor = _on ? [MeshTheme accent] : [MeshTheme surface];
    _track.layer.borderColor = (_on ? [MeshTheme accent] : [MeshTheme line]).CGColor;
    _knob.backgroundColor = _on ? [MeshTheme bg] : [MeshTheme muted];
}

// Fingerfreundlich: etwas größere Trefferfläche als die sichtbaren 46 × 28.
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    return CGRectContainsPoint(CGRectInset(self.bounds, -10, -8), p);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { _moved = NO; return YES; }

- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    CGFloat x = [t locationInView:self].x, prev = [t previousLocationInView:self].x;
    if (fabs(x - prev) > 0.5f) _moved = YES;
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    if (!t || !CGRectContainsPoint(CGRectInset(self.bounds, -30, -30), [t locationInView:self])) return;
    // Wischen: Richtung entscheidet; Tippen: umschalten.
    BOOL target = _moved ? [t locationInView:self].x > kWidth / 2 : !_on;
    if (target == _on) return;
    [self setOn:target animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end
