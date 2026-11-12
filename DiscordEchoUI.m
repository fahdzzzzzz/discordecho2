// DiscordEchoUI: قائمة عائمة بثلاث تبويبات: الصدى، النبرة، المضخّم
// زر 🎙 تسحبه في الشاشة، والضغط عليه يفتح القائمة.

#import <UIKit/UIKit.h>
#include <math.h>
#include <stdlib.h>

extern void DiscordEcho_SetLevel(int level);
extern void DiscordEcho_SetGain(int gain);
extern void DiscordEcho_SetPitch(int semitones);
extern void DiscordEcho_SetRobot(int on);
extern float DiscordEcho_GetPeak(void);

static NSString *const kLevelKey = @"DiscordEchoLevel";
static NSString *const kGainKey  = @"DiscordEchoGain";
static NSString *const kPitchKey = @"DiscordEchoPitch";
static NSString *const kRobotKey = @"DiscordEchoRobot";

static const CGFloat kPanelW = 300;
static const CGFloat kPanelH = 280;
static const CGFloat kTabTop = 56;

// نافذة شفافة تمرر اللمس لديسكورد إلا لما تلمس الزر أو القائمة
@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface EchoController : UIViewController
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UIView *tabEcho;
@property (nonatomic, strong) UIView *tabPitch;
@property (nonatomic, strong) UIView *tabAmp;
@property (nonatomic, strong) UISlider *echoSlider;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic, strong) UISlider *gainSlider;
@property (nonatomic, strong) UILabel *echoLabel;
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UILabel *gainLabel;
@property (nonatomic, strong) UIProgressView *meter;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL robot;
@end

@implementation EchoController

#pragma mark - عناصر مساعدة

- (UILabel *)makeLabelAt:(CGRect)frame size:(CGFloat)size bold:(BOOL)bold alpha:(CGFloat)alpha {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 10;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UISlider *)makeSliderAt:(CGRect)f min:(float)mn max:(float)mx value:(float)v action:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:f];
    s.minimumValue = mn;
    s.maximumValue = mx;
    s.continuous = YES;
    s.value = v;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

#pragma mark - بناء الواجهة

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    int level = [d objectForKey:kLevelKey] ? (int)[d integerForKey:kLevelKey] : 50;
    int gain  = [d objectForKey:kGainKey]  ? (int)[d integerForKey:kGainKey]  : 100;
    int pitch = [d objectForKey:kPitchKey] ? (int)[d integerForKey:kPitchKey] : 0;
    self.robot = [d boolForKey:kRobotKey];

    // الزر العائم
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1;
    fab.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    [fab setTitle:@"🎙" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:24];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [fab addGestureRecognizer:pan];
    [self.view addSubview:fab];
    self.fab = fab;

    // القائمة
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    panel.layer.cornerRadius = 16;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // التبويبات
    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"الصدى", @"النبرة", @"المضخّم"]];
    tabs.frame = CGRectMake(16, 12, kPanelW - 32, 34);
    tabs.selectedSegmentIndex = 0;
    tabs.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    NSDictionary *white = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
    [tabs setTitleTextAttributes:white forState:UIControlStateNormal];
    [tabs setTitleTextAttributes:white forState:UIControlStateSelected];
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:tabs];
    self.tabs = tabs;

    CGRect cf = CGRectMake(0, kTabTop, kPanelW, kPanelH - kTabTop);
    self.tabEcho  = [[UIView alloc] initWithFrame:cf];
    self.tabPitch = [[UIView alloc] initWithFrame:cf];
    self.tabAmp   = [[UIView alloc] initWithFrame:cf];
    [panel addSubview:self.tabEcho];
    [panel addSubview:self.tabPitch];
    [panel addSubview:self.tabAmp];
    self.tabPitch.hidden = YES;
    self.tabAmp.hidden = YES;

    CGFloat w = kPanelW - 32;

    // ----- تبويب الصدى -----
    self.echoLabel = [self makeLabelAt:CGRectMake(16, 6, w, 26) size:17 bold:YES alpha:1];
    [self.tabEcho addSubview:self.echoLabel];
    self.echoSlider = [self makeSliderAt:CGRectMake(16, 38, w, 30) min:0 max:100 value:level action:@selector(echoChanged:)];
    [self.tabEcho addSubview:self.echoSlider];
    UILabel *echoHint = [self makeLabelAt:CGRectMake(16, 82, w, 40) size:12 bold:NO alpha:0.55];
    echoHint.text = @"0 = إيقاف  ·  100 = أقوى صدى";
    [self.tabEcho addSubview:echoHint];

    // ----- تبويب النبرة -----
    self.pitchLabel = [self makeLabelAt:CGRectMake(16, 4, w, 26) size:16 bold:YES alpha:1];
    [self.tabPitch addSubview:self.pitchLabel];
    self.pitchSlider = [self makeSliderAt:CGRectMake(16, 32, w, 30) min:-12 max:12 value:pitch action:@selector(pitchChanged:)];
    [self.tabPitch addSubview:self.pitchSlider];

    NSArray *names = @[@"عادي", @"بنت", @"رجل", @"وحش", @"روبوت", @"🎲 عشوائي"];
    for (NSInteger i = 0; i < 6; i++) {
        NSInteger col = i % 3, row = i / 3;
        CGRect f = CGRectMake(16 + col * 92, 76 + row * 42, 84, 34);
        [self.tabPitch addSubview:[self makeButton:names[i] frame:f tag:i action:@selector(presetTapped:)]];
    }
    UILabel *pitchHint = [self makeLabelAt:CGRectMake(16, 164, w, 40) size:12 bold:NO alpha:0.55];
    pitchHint.text = @"حرّك الشريط أو اختر نمط جاهز.\nروبوت = صوت معدني، وعشوائي = مفاجأة";
    [self.tabPitch addSubview:pitchHint];

    // ----- تبويب المضخّم -----
    self.gainLabel = [self makeLabelAt:CGRectMake(16, 4, w, 26) size:16 bold:YES alpha:1];
    [self.tabAmp addSubview:self.gainLabel];
    self.gainSlider = [self makeSliderAt:CGRectMake(16, 32, w, 30) min:100 max:300 value:gain action:@selector(gainChanged:)];
    [self.tabAmp addSubview:self.gainSlider];

    NSArray *quickNames = @[@"عادي", @"×1.5", @"×2", @"×3"];
    NSArray *quickTags  = @[@100, @150, @200, @300];
    for (NSInteger i = 0; i < 4; i++) {
        CGRect f = CGRectMake(16 + i * 69, 72, 61, 32);
        [self.tabAmp addSubview:[self makeButton:quickNames[i] frame:f tag:[quickTags[i] integerValue] action:@selector(gainQuick:)]];
    }

    UILabel *meterLabel = [self makeLabelAt:CGRectMake(16, 114, w, 18) size:13 bold:NO alpha:0.7];
    meterLabel.text = @"مستوى المايك";
    [self.tabAmp addSubview:meterLabel];

    UIProgressView *meter = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    meter.frame = CGRectMake(16, 138, w, 8);
    meter.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    meter.progressTintColor = [UIColor systemGreenColor];
    [self.tabAmp addSubview:meter];
    self.meter = meter;

    UILabel *ampHint = [self makeLabelAt:CGRectMake(16, 158, w, 46) size:12 bold:NO alpha:0.55];
    ampHint.text = @"تكلّم وشوف الشريط. إذا صار أحمر الصوت يتقطع، خفّض التضخيم.";
    [self.tabAmp addSubview:ampHint];

    [self updateEchoLabel:level];
    [self updatePitchLabel];
    [self updateGainLabel:gain];

    DiscordEcho_SetLevel(level);
    DiscordEcho_SetGain(gain);
    DiscordEcho_SetPitch(pitch);
    DiscordEcho_SetRobot(self.robot ? 1 : 0);
}

#pragma mark - تحديث النصوص

- (void)updateEchoLabel:(int)level {
    self.echoLabel.text = (level == 0)
        ? @"الصدى: متوقف"
        : [NSString stringWithFormat:@"شدة الصدى: %d", level];
}

- (void)updatePitchLabel {
    int st = (int)lroundf(self.pitchSlider.value);
    NSString *t = (st == 0) ? @"النبرة: عادية"
                            : [NSString stringWithFormat:@"النبرة: %+d نغمة", st];
    if (self.robot) t = [t stringByAppendingString:@"  ·  🤖 روبوت"];
    self.pitchLabel.text = t;
}

- (void)updateGainLabel:(int)gain {
    self.gainLabel.text = [NSString stringWithFormat:@"تضخيم الصوت: %d%%", gain];
}

#pragma mark - الأحداث

- (void)tabChanged:(UISegmentedControl *)sender {
    self.tabEcho.hidden  = (sender.selectedSegmentIndex != 0);
    self.tabPitch.hidden = (sender.selectedSegmentIndex != 1);
    self.tabAmp.hidden   = (sender.selectedSegmentIndex != 2);
}

- (void)echoChanged:(UISlider *)s {
    int level = (int)lroundf(s.value);
    DiscordEcho_SetLevel(level);
    [[NSUserDefaults standardUserDefaults] setInteger:level forKey:kLevelKey];
    [self updateEchoLabel:level];
}

- (void)applyPitch:(int)st robot:(BOOL)robot {
    if (st < -12) st = -12;
    if (st > 12) st = 12;
    self.pitchSlider.value = st;
    self.robot = robot;
    DiscordEcho_SetPitch(st);
    DiscordEcho_SetRobot(robot ? 1 : 0);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:st forKey:kPitchKey];
    [d setBool:robot forKey:kRobotKey];
    [self updatePitchLabel];
}

- (void)pitchChanged:(UISlider *)s {
    [self applyPitch:(int)lroundf(s.value) robot:self.robot];
}

- (void)presetTapped:(UIButton *)b {
    switch (b.tag) {
        case 0: [self applyPitch:0  robot:NO];  break;   // عادي
        case 1: [self applyPitch:5  robot:NO];  break;   // بنت
        case 2: [self applyPitch:-4 robot:NO];  break;   // رجل
        case 3: [self applyPitch:-9 robot:NO];  break;   // وحش
        case 4: [self applyPitch:0  robot:YES]; break;   // روبوت
        default: {                                         // عشوائي
            int st = (int)arc4random_uniform(21) - 10;
            [self applyPitch:st robot:(arc4random_uniform(4) == 0)];
        }
    }
}

- (void)gainChanged:(UISlider *)s {
    int gain = (int)lroundf(s.value);
    DiscordEcho_SetGain(gain);
    [[NSUserDefaults standardUserDefaults] setInteger:gain forKey:kGainKey];
    [self updateGainLabel:gain];
}

- (void)gainQuick:(UIButton *)b {
    self.gainSlider.value = (float)b.tag;
    [self gainChanged:self.gainSlider];
}

#pragma mark - مقياس المايك

- (void)startMeter {
    if (self.timer) return;
    __weak EchoController *ws = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.07 repeats:YES block:^(NSTimer *t) {
        EchoController *s = ws;
        if (!s || s.panel.hidden || s.tabAmp.hidden) return;
        float pk = DiscordEcho_GetPeak();
        if (pk > 1.0f) pk = 1.0f;
        s.meter.progress = pk;
        s.meter.progressTintColor = (pk > 0.98f) ? [UIColor systemRedColor]
                                  : (pk > 0.8f)  ? [UIColor systemOrangeColor]
                                                 : [UIColor systemGreenColor];
    }];
}

- (void)stopMeter {
    [self.timer invalidate];
    self.timer = nil;
}

#pragma mark - تحريك القائمة

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (self.panel.hidden) {
        [self stopMeter];
    } else {
        [self positionPanel];
        [self startMeter];
    }
}

- (void)positionPanel {
    CGRect b = self.view.bounds;
    CGFloat w = kPanelW, h = kPanelH;
    CGFloat x = CGRectGetMidX(self.fab.frame) - w / 2;
    x = MAX(10, MIN(x, b.size.width - w - 10));
    CGFloat y = CGRectGetMaxY(self.fab.frame) + 10;
    if (y + h > b.size.height - 10) y = CGRectGetMinY(self.fab.frame) - h - 10;
    self.panel.frame = CGRectMake(x, y, w, h);
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.view];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

- (void)clampFab {
    CGRect b = self.view.bounds;
    UIEdgeInsets s = self.view.safeAreaInsets;
    CGFloat r = 26;
    CGPoint c = self.fab.center;
    c.x = MAX(r + s.left, MIN(c.x, b.size.width - r - s.right));
    c.y = MAX(r + s.top,  MIN(c.y, b.size.height - r - s.bottom));
    self.fab.center = c;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

@end

static EchoWindow *gWin;

static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:scene];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

__attribute__((constructor))
static void echo_ui_init(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    DiscordEcho_SetLevel([d objectForKey:kLevelKey] ? (int)[d integerForKey:kLevelKey] : 50);
    DiscordEcho_SetGain([d objectForKey:kGainKey] ? (int)[d integerForKey:kGainKey] : 100);
    DiscordEcho_SetPitch([d objectForKey:kPitchKey] ? (int)[d integerForKey:kPitchKey] : 0);
    DiscordEcho_SetRobot([d boolForKey:kRobotKey] ? 1 : 0);

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { echo_setup_window(); }];
}
