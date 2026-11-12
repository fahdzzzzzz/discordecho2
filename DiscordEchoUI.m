// 🎛️ DiscordEchoUI - واجهة التحكم الكاملة لصدى Creative EAX
#import <UIKit/UIKit.h>

extern void DiscordEcho_SetLevel(int v);
extern void DiscordEcho_SetEAXMode(int on);

@interface EchoController : UIViewController
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *echoLabel;
@property (nonatomic, strong) UISlider *echoSlider;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // الزر العائم للتحكم 📱
    UIButton *fab = [ButtonWithTouchArea buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    fab.layer.shadowColor = UIColor.blackColor.CGColor;
    fab.layer.shadowOffset = CGSizeMake(0, 4);
    fab.layer.shadowOpacity = 0.3;
    fab.layer.shadowRadius = 4;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];

    // لوحة التحكم المنسدلة 📋
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 205, 320, 260)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.98];
    panel.layer.cornerRadius = 16;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOffset = CGSizeMake(0, 6);
    panel.layer.shadowOpacity = 0.4;
    panel.layer.shadowRadius = 8;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // عنوان اللوحة 🏷️
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, 288, 24)];
    titleLbl.text = @"إعدادات صدى Creative EAX";
    titleLbl.font = [UIFont boldSystemFontOfSize:16];
    titleLbl.textColor = UIColor.darkGrayColor;
    [panel addSubview:titleLbl];

    // شريط مستوى الصدى 🎚️
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 60, 288, 22)];
    lbl.text = @"مستوى صدى الـ EAX: 60";
    lbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [panel addSubview:lbl];
    self.echoLabel = lbl;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 92, 288, 30)];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = 60;
    [slider addTarget:self action:@selector(echoChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    self.echoSlider = slider;

    // زر تفعيل/إلغاء وضع الـ EAX 🔘
    UISwitch *eaxSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(16, 144, 51, 31)];
    eaxSwitch.on = YES;
    [eaxSwitch addTarget:self action:@selector(eaxToggled:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:eaxSwitch];

    UILabel *switchLbl = [[UILabel alloc] initWithFrame:CGRectMake(80, 144, 224, 31)];
    switchLbl.text = @"تفعيل تأثير EAX";
    switchLbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [panel addSubview:switchLbl];
}

- (void)echoChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetLevel(v);
    self.echoLabel.text = [NSString stringWithFormat:@"مستوى صدى الـ EAX: %d", v];
}

- (void)eaxToggled:(UISwitch *)sw {
    DiscordEcho_SetEAXMode(sw.isOn ? 1 : 0);
}

- (void)togglePanel {
