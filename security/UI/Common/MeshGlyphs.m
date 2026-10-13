#import "MeshGlyphs.h"
#include <math.h>
#import "MeshTheme.h"

// Symbolpfade im 24×24-Raster (wie in der Android-App)
static NSString *pathFor(NSString *name) {
    static NSDictionary *d = nil;
    if (!d) d = @{
        @"back":       @"M15,4l-8,8l8,8",
        @"forward":    @"M9,4l8,8l-8,8",
        @"check":      @"M5,12l5,5l9,-11",
        @"close":      @"M6,6l12,12 M18,6l-12,12",
        @"shield":     @"M12,3l7,3v5c0,4.5 -3,7.5 -7,9c-4,-1.5 -7,-4.5 -7,-9v-5z M9,12l2,2l4,-4",
        @"shieldoff":  @"M12,3l7,3v5c0,4.5 -3,7.5 -7,9c-4,-1.5 -7,-4.5 -7,-9v-5z M9,9l6,6 M15,9l-6,6",
        @"key":        @"M20.5,3.5l-8,8 M18.3,5.7l1.6,1.6 M15.3,8.7l1.6,1.6 M8.6,12.4a3.4,3.4 0 1 0 0.01,0",
        @"lock":       @"M6,11h12a1,1 0 0 1 1,1v7a1,1 0 0 1 -1,1h-12a1,1 0 0 1 -1,-1v-7a1,1 0 0 1 1,-1z M8,11v-3a4,4 0 0 1 8,0v3 M12,14.5v2",
        @"power":      @"M12,3v8 M7,6.5a7,7 0 1 0 10,0",
        @"onion":      @"M12,5C16,7 19,10.5 19,14.5A7,6 0 0 1 5,14.5C5,10.5 8,7 12,5z M12,8.5C14.5,10 15.5,12.5 15.5,14.5A3.5,4 0 0 1 8.5,14.5C8.5,12.5 9.5,10 12,8.5z M12,5V2.5 M12,4C13,3 14.5,2.5 15.5,2.8",   // Tor
        @"traffic":    @"M4,8h13 M14,5l3,3l-3,3 M20,16h-13 M10,13l-3,3l3,3",
        @"apps":       @"M5,5h5v5h-5z M14,5h5v5h-5z M5,14h5v5h-5z M14,14h5v5h-5z",
        @"wifi":       @"M3,9a13,13 0 0 1 18,0 M6,12.5a8.5,8.5 0 0 1 12,0 M9,16a4,4 0 0 1 6,0 M12,19.2v0.3",
        @"guide":      @"M12,3a9,9 0 1 0 0.01,0z M15.5,8.5l-2,5l-5,2l2,-5z",
        @"reset":      @"M4,12a8,8 0 1 0 2.3,-5.6 M4,4v4h4",
        @"alert":      @"M12,3a9,9 0 1 0 0.01,0z M12,7.5v6 M12,16.2v0.6",
        @"add":        @"M12,5v14 M5,12h14",
        @"timer":      @"M12,5a8,8 0 1 0 0.01,0z M12,9v4l2.5,2 M10,2h4",
        @"eye":        @"M2,12c3,-5 7,-7 10,-7c3,0 7,2 10,7c-3,5 -7,7 -10,7c-3,0 -7,-2 -10,-7z M12,9a3,3 0 1 0 0.01,0",
    };
    return d[name];
}

// Mini-SVG-Pfad-Parser (M/L/H/V/C/A/Z, absolut+relativ; Kreisbögen mit rx=ry)
static double readNum(const char *s, int n, int *i) {
    while (*i < n && (s[*i] == ' ' || s[*i] == ',')) (*i)++;
    int st = *i;
    if (*i < n && (s[*i] == '+' || s[*i] == '-')) (*i)++;
    while (*i < n && ((s[*i] >= '0' && s[*i] <= '9') || s[*i] == '.')) (*i)++;
    if (*i < n && (s[*i] == 'e' || s[*i] == 'E')) {
        (*i)++;
        if (*i < n && (s[*i] == '+' || s[*i] == '-')) (*i)++;
        while (*i < n && s[*i] >= '0' && s[*i] <= '9') (*i)++;
    }
    return atof([[NSString stringWithFormat:@"%.*s", *i-st, s+st] UTF8String]);
}

// Kreisbogen von cur nach end mit Radius r (SVG-Flags large-arc und sweep).
static void arcTo(UIBezierPath *p, CGPoint cur, CGPoint end, double r, int large, int sweep) {
    if (r <= 0 || (fabs(cur.x - end.x) < 0.0001 && fabs(cur.y - end.y) < 0.0001)) { [p addLineToPoint:end]; return; }
    double mx = (cur.x + end.x) / 2, my = (cur.y + end.y) / 2;
    double dx = (cur.x - end.x) / 2, dy = (cur.y - end.y) / 2;
    double dsq = dx * dx + dy * dy, dist = sqrt(dsq);
    if (dist > r) r = dist;
    double h = sqrt(fmax(0, r * r - dsq));
    double ux = -dy / dist, uy = dx / dist;            // Einheitssenkrechte zur Sehne
    double sign = (large != sweep) ? -1 : 1;
    double cx = mx + sign * h * ux, cy = my + sign * h * uy;
    double a0 = atan2(cur.y - cy, cur.x - cx), a1 = atan2(end.y - cy, end.x - cx);
    [p addArcWithCenter:CGPointMake(cx, cy) radius:r startAngle:a0 endAngle:a1 clockwise:(sweep == 1)];
}

static CGPoint point(CGPoint cur, BOOL relative, double x, double y) {
    return relative ? CGPointMake(cur.x + x, cur.y + y) : CGPointMake(x, y);
}

static UIBezierPath *bezierFromSVG(NSString *d) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    const char *s = d.UTF8String;
    int n = (int)strlen(s), i = 0;
    CGPoint cur = CGPointZero, start = CGPointZero;
    char cmd = 0;
    while (i < n) {
        while (i < n && (s[i] == ' ' || s[i] == ',')) i++;
        if (i >= n) break;
        char c = s[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) { cmd = c; i++; }
        BOOL rel = cmd >= 'a';
        char upper = rel ? cmd - 32 : cmd;
        if (upper == 'M') {
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            cur = start = point(cur, rel, x, y);
            [p moveToPoint:cur];
            cmd = rel ? 'l' : 'L';                         // weitere Paare sind Linien
        } else if (upper == 'L') {
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            cur = point(cur, rel, x, y);
            [p addLineToPoint:cur];
        } else if (upper == 'H') {
            double x = readNum(s, n, &i);
            cur = CGPointMake(rel ? cur.x + x : x, cur.y);
            [p addLineToPoint:cur];
        } else if (upper == 'V') {
            double y = readNum(s, n, &i);
            cur = CGPointMake(cur.x, rel ? cur.y + y : y);
            [p addLineToPoint:cur];
        } else if (upper == 'C') {
            double x1 = readNum(s, n, &i), y1 = readNum(s, n, &i);
            double x2 = readNum(s, n, &i), y2 = readNum(s, n, &i);
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            CGPoint end = point(cur, rel, x, y);
            [p addCurveToPoint:end controlPoint1:point(cur, rel, x1, y1) controlPoint2:point(cur, rel, x2, y2)];
            cur = end;
        } else if (upper == 'A') {
            double rx = readNum(s, n, &i);
            readNum(s, n, &i);                             // ry: nur Kreisbögen
            readNum(s, n, &i);                             // Drehung
            int large = (int)readNum(s, n, &i), sweep = (int)readNum(s, n, &i);
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            CGPoint end = point(cur, rel, x, y);
            arcTo(p, cur, end, rx, large, sweep);
            cur = end;
        } else if (upper == 'Z') {
            [p closePath];
            cur = start;
        } else {
            i++;
        }
    }
    return p;
}

@implementation MeshGlyphs

+ (UIImage *)icon:(NSString *)name color:(UIColor *)color size:(CGFloat)size {
    NSString *d = pathFor(name);
    if (!d) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), size / 24.0, size / 24.0);
    UIBezierPath *bp = bezierFromSVG(d);
    bp.lineWidth = 1.9;
    bp.lineCapStyle = kCGLineCapRound;
    bp.lineJoinStyle = kCGLineJoinRound;
    [color setStroke];
    [bp stroke];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Logo: Schild mit dem Mesh-Knoten darin (Raster 108 wie das Mesh-Logo).
+ (UIImage *)logo:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), size / 108.0, size / 108.0);
    UIColor *accent = [MeshTheme accent];

    UIBezierPath *shield = [UIBezierPath bezierPath];
    [shield moveToPoint:CGPointMake(54, 12)];
    [shield addLineToPoint:CGPointMake(88, 25)];
    [shield addLineToPoint:CGPointMake(88, 50)];
    [shield addCurveToPoint:CGPointMake(54, 96) controlPoint1:CGPointMake(88, 72) controlPoint2:CGPointMake(73, 88)];
    [shield addCurveToPoint:CGPointMake(20, 50) controlPoint1:CGPointMake(35, 88) controlPoint2:CGPointMake(20, 72)];
    [shield addLineToPoint:CGPointMake(20, 25)];
    [shield closePath];
    shield.lineWidth = 4;
    shield.lineJoinStyle = kCGLineJoinRound;
    [[accent colorWithAlphaComponent:0.14] setFill];
    [shield fill];
    [accent setStroke];
    [shield stroke];

    // Knoten wie im Mesh-Logo, kleiner und etwas nach oben gerückt
    CGPoint center = CGPointMake(54, 51);
    CGPoint nodes[6] = { {72, 51}, {63, 35.4}, {45, 35.4}, {36, 51}, {45, 66.6}, {63, 66.6} };
    [[accent colorWithAlphaComponent:0.55] setStroke];
    UIBezierPath *links = [UIBezierPath bezierPath];
    links.lineWidth = 2.2;
    links.lineCapStyle = kCGLineCapRound;
    for (int j = 0; j < 6; j++) { [links moveToPoint:center]; [links addLineToPoint:nodes[j]]; }
    [links stroke];
    [accent setFill];
    for (int j = 0; j < 6; j++)
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(nodes[j].x - 4, nodes[j].y - 4, 8, 8)] fill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - 7, center.y - 7, 14, 14)] fill];
    [[MeshTheme bg] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - 2.5, center.y - 2.5, 5, 5)] fill];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
