// 🎛️ DiscordEchoUI: واجهة التحكم المطورة لصدى Creative EAX
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

static NSString *const kLevelKey = @"DiscordEchoLevel";
static NSString *const kBoostKey = @"DiscordEchoBoost";
static NSString *const kRangeKey = @"DiscordEchoRange";
static NSString *const kEAXKey   = @"DiscordEchoEAX";

static const CGFloat kPanelW = 320;
static const CGFloat kPanelH = 380;

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

@interface EchoController : UIViewController
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *echoLabel;
@property (nonatomic, strong) UISlider *echoSlider;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    int level = EchoInt(kLevelKey, 60);
    int eax   = EchoInt(kEAXKey, 1);

    // الزر العائم لفتح القائمة
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1.5;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];
    self.fab = fab;

    // لوحة التحكم العائمة
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.97];
    panel.layer.cornerRadius = 14;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // شريط مستوى الصدى (0 إلى 100)
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 40, kPanelW - 28, 24)];
    lbl.text = [NSString stringWithFormat:@"مستوى صدى الـ EAX: %d", level];
    lbl.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:lbl];
    self.echoLabel = lbl;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 75, kPanelW - 28, 22)];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = level;
    [slider addTarget:self action:@selector(echoChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    self.echoSlider = slider;

    DiscordEcho_SetLevel(level);
    DiscordEcho_SetEAXMode(eax);
}

- (void)echoChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetLevel(v);
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:kLevelKey];
    self.echoLabel.text = [NSString stringWithFormat:@"مستوى صدى الـ EAX: %d", v];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden) {
        self.panel.frame = CGRectMake(20, 205, kPanelW, kPanelH);
    }
}

@end

static EchoWindow *gWin;

__attribute__((constructor))
static void echo_ui_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *targetScene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)s;
                break;
            }
        }
        if (!targetScene) return;
        gWin = [[EchoWindow alloc] initWithWindowScene:targetScene];
        gWin.windowLevel = UIWindowLevelAlert + 100;
        gWin.backgroundColor = UIColor.clearColor;
        gWin.rootViewController = [EchoController new];
        gWin.hidden = NO;
    });
}
