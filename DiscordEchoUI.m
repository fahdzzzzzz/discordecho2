#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
#include <stdlib.h>

extern void DiscordEcho_SetLevel(int v);
extern void DiscordEcho_SetEchoBoost(int v);
extern void DiscordEcho_SetRange(int v);
extern void DiscordEcho_SetWhisperFreq(int v);
extern void DiscordEcho_SetEAXMode(int on);
extern void DiscordEcho_SetGain(int v);
extern void DiscordEcho_SetPitch(int v);
extern void DiscordEcho_SetRobot(int on);
extern void DiscordEcho_SetVoiceMute(int on);
extern float DiscordEcho_GetPeak(void);
extern int   DiscordEcho_MusicLoad(float *samples, size_t count);
extern void  DiscordEcho_MusicPlay(int play);
extern void  DiscordEcho_MusicStop(void);
extern void  DiscordEcho_MusicSeek(float frac);
extern void  DiscordEcho_MusicSetVolume(int pct);
extern void  DiscordEcho_MusicSetLoop(int on);
extern int   DiscordEcho_MusicIsPlaying(void);
extern float DiscordEcho_MusicProgress(void);
extern float DiscordEcho_MusicDuration(void);

static NSString *const kLevelKey = @"DiscordEchoLevel";
static NSString *const kBoostKey = @"DiscordEchoBoost";
static NSString *const kRangeKey = @"DiscordEchoRange";
static NSString *const kWFreqKey = @"DiscordEchoWFreq";
static NSString *const kEAXKey   = @"DiscordEchoEAX";
static NSString *const kGainKey  = @"DiscordEchoGain";
static NSString *const kPitchKey = @"DiscordEchoPitch";
static NSString *const kRobotKey = @"DiscordEchoRobot";
static NSString *const kMusicVolKey = @"DiscordEchoMusicVol";
static NSString *const kMusicLoopKey = @"DiscordEchoMusicLoop";
static NSString *const kMuteKey  = @"DiscordEchoVoiceMute";

static const CGFloat kPanelW = 320;
static const CGFloat kPanelH = 480;
static const CGFloat kTabTop = 56;

static int EchoInt(NSString *key, int def) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:key] ? (int)[d integerForKey:key] : def;
}

@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface EchoController : UIViewController
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) NSArray<UIView *> *tabViews;
@property (nonatomic, strong) UISlider *echoSlider;
@property (nonatomic, strong) UISlider *boostSlider;
@property (nonatomic, strong) UISlider *rangeSlider;
@property (nonatomic, strong) UISlider *wFreqSlider;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic) BOOL robot;
@property (nonatomic, strong) UISlider *gainSlider;
@property (nonatomic, strong) UIProgressView *meter;
@property (nonatomic, strong) UILabel *songLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UISlider *seekSlider;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UISlider *volSlider;
@property (nonatomic) BOOL seeking;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation EchoController

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1.0] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    b.backgroundColor = [UIColor colorWithRed:0.78 green:0.80 blue:0.83 alpha:1.0];
    b.layer.cornerRadius = 8;
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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    int level = EchoInt(kLevelKey, 60);
    int boost = EchoInt(kBoostKey, 140);
    int range = EchoInt(kRangeKey, 65);
    int eax   = EchoInt(kEAXKey, 1);

    // الزر العائم الأساسي للفتح
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];
    self.fab = fab;

    // اللوحة الرئيسية
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.97];
    panel.layer.cornerRadius = 14;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // زر إغلاق اللوحة (✕) بزيادة وضوحه
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kPanelW - 38, 10, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];

    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"EAX صدى", @"🎙️ نبرة", @"🎚️ مضخّم", @"🎵 أغاني"]];
    tabs.frame = CGRectMake(12, 10, kPanelW - 54, 34);
    tabs.selectedSegmentIndex = 0;
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:tabs];
    self.tabs = tabs;

    CGRect cf = CGRectMake(0, kTabTop, kPanelW, kPanelH - kTabTop);
    UIView *tabEcho = [[UIView alloc] initWithFrame:cf];
    UIView *tabPitch = [[UIView alloc] initWithFrame:cf];
    UIView *tabAmp = [[UIView alloc] initWithFrame:cf];
    UIView *tabMusic = [[UIView alloc] initWithFrame:cf];
    self.tabViews = @[tabEcho, tabPitch, tabAmp, tabMusic];
    for (UIView *v in self.tabViews) { [panel addSubview:v]; v.hidden = (v != tabEcho); }

    // تطبيق القيم الأولية على محرك C
    DiscordEcho_SetLevel(level);
    DiscordEcho_SetEchoBoost(boost);
    DiscordEcho_SetRange(range);
    DiscordEcho_SetEAXMode(eax);
}

- (void)tabChanged:(UISegmentedControl *)sender {
    for (NSUInteger i = 0; i < self.tabViews.count; i++)
        self.tabViews[i].hidden = ((NSInteger)i != sender.selectedSegmentIndex);
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

@end

#pragma clang diagnostic pop

static EchoWindow *gWin;
static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *targetScene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            targetScene = (UIWindowScene *)s;
            break;
        }
    }
    if (!targetScene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:targetScene];
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

__attribute__((constructor))
static void echo_ui_init(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        echo_setup_window();
    }];
}
