#import <UIKit/UIKit.h>

extern void DiscordEcho_SetLevel(int v);
extern void DiscordEcho_SetEAXMode(int on);
extern void DiscordEcho_SetHauntedCavernMode(int enabled);

@interface EchoController : UIViewController
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *echoLabel;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // الزر العائم 🎛️
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];

    // لوحة التحكم 📋
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 205, 320, 250)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.98];
    panel.layer.cornerRadius = 16;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // العنوان
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, 288, 24)];
    titleLbl.text = @"إعدادات صدى الكهف المسكون";
    titleLbl.font = [UIFont boldSystemFontOfSize:16];
    [panel addSubview:titleLbl];

    // مفتاح تفعيل وضع الكهف المسكون Haunted Cavern
    UISwitch *cavernSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(16, 60, 51, 31)];
    cavernSwitch.on = NO;
    [cavernSwitch addTarget:self action:@selector(cavernToggled:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:cavernSwitch];

    UILabel *switchLbl = [[UILabel alloc] initWithFrame:CGRectMake(80, 60, 224, 31)];
    switchLbl.text = @"تفعيل وضع Haunted Cavern";
    switchLbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [panel addSubview:switchLbl];

    // شريط مستوى الصدى 🎚️
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 110, 288, 22)];
    lbl.text = @"مستوى الصدى: 60";
    lbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [panel addSubview:lbl];
    self.echoLabel = lbl;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 142, 288, 30)];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = 60;
    [slider addTarget:self action:@selector(echoChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
}

- (void)echoChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetLevel(v);
    self.echoLabel.text = [NSString stringWithFormat:@"مستوى الصدى: %d", v];
}

- (void)cavernToggled:(UISwitch *)sw {
    DiscordEcho_SetHauntedCavernMode(sw.isOn ? 1 : 0);
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

@end

// فكرة السماح للمسة بالمرور من خلال النافذة الشفافة للألعاب/البرامج
@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

static EchoWindow *gWin;

__attribute__((constructor))
static void echo_ui_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *targetScene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)s;
                break;
            }
        }
        if (targetScene) {
            gWin = [[EchoWindow alloc] initWithWindowScene:targetScene];
        } else {
            gWin = [[EchoWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        gWin.windowLevel = UIWindowLevelAlert + 100;
        gWin.backgroundColor = UIColor.clearColor;
        gWin.rootViewController = [EchoController new];
        gWin.hidden = NO;
    });
}
