#import <UIKit/UIKit.h>

// الإعلانات الخارجية لدوال محرك الصوت C
extern void DiscordEcho_SetEnableEffects(int enabled);
extern void DiscordEcho_SetEffectsAmount(int amount);
extern void DiscordEcho_SetPreset(int preset);
extern float DiscordEcho_GetPeak(void);

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
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISlider *amountSlider;
@property (nonatomic, strong) UILabel *amountLabel;
@property (nonatomic, strong) UISegmentedControl *presetControl;
@property (nonatomic, strong) UISwitch *effectsSwitch;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // 🎛️ الزر العائم الأساسي للفتح
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 50, 50);
    fab.backgroundColor = [UIColor colorWithRed:0.18 green:0.20 blue:0.25 alpha:0.95];
    fab.layer.cornerRadius = 25;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];

    // 📱 اللوحة الرئيسية (EAX Console Style)
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 200, 300, 320)];
    panel.backgroundColor = [UIColor colorWithRed:0.92 green:0.94 blue:0.97 alpha:0.98];
    panel.layer.cornerRadius = 12;
    panel.layer.borderWidth = 1.5;
    panel.layer.borderColor = [UIColor colorWithRed:0.70 green:0.75 blue:0.80 alpha:1.0].CGColor;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // 🏷️ عنوان لوحة التحكم
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, 200, 24)];
    title.text = @"Creative EAX Console";
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1.0];
    [panel addSubview:title];

    // ✕ زر إغلاق اللوحة
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(260, 10, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];

    // ⚙️ مفتاح تفعيل المؤثرات
    UILabel *lblSwitch = [[UILabel alloc] initWithFrame:CGRectMake(14, 50, 180, 24)];
    lblSwitch.text = @"Enable Audio Effects";
    lblSwitch.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [panel addSubview:lblSwitch];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(230, 47, 51, 31)];
    sw.on = YES;
    [sw addTarget:self action:@selector(effectsToggled:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sw];
    self.effectsSwitch = sw;

    // 🏔️ اختيار البيئة (Presets)
    UILabel *lblPreset = [[UILabel alloc] initWithFrame:CGRectMake(14, 95, 200, 20)];
    lblPreset.text = @"Active Preset (Environment)";
    lblPreset.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    lblPreset.textColor = UIColor.darkGrayColor;
    [panel addSubview:lblPreset];

    UISegmentedControl *presetSeg = [[UISegmentedControl alloc] initWithItems:@[@"Haunted Cavern", @"Cathedral", @"Concert Hall"]];
    presetSeg.frame = CGRectMake(14, 120, 272, 32];
    presetSeg.selectedSegmentIndex = 0;
    [presetSeg addTarget:self action:@selector(presetChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:presetSeg];
    self.presetControl = presetSeg;

    // 🎚️ شريط تمرير شدة التأثير
    UILabel *lblAmount = [[UILabel alloc] initWithFrame:CGRectMake(14, 175, 150, 20)];
    lblAmount.text = @"Effects Amount : 50";
    lblAmount.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [panel addSubview:lblAmount];
    self.amountLabel = lblAmount;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 200, 272, 30)];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = 50;
    [slider addTarget:self action:@selector(amountChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    self.amountSlider = slider;
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

- (void)effectsToggled:(UISwitch *)sender {
    DiscordEcho_SetEnableEffects(sender.on ? 1 : 0);
}

- (void)presetChanged:(UISegmentedControl *)sender {
    DiscordEcho_SetPreset((int)sender.selectedSegmentIndex);
}

- (void)amountChanged:(UISlider *)sender {
    int val = (int)lroundf(sender.value);
    self.amountLabel.text = [NSString stringWithFormat:@"Effects Amount : %d", val];
    DiscordEcho_SetEffectsAmount(val);
}

@end

static EchoWindow *gWin;
static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *targetScene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
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
