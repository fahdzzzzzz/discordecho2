// 🎛️ DiscordEchoUI - واجهة التحكم العائمة المستقرة
#import <UIKit/UIKit.h>

extern void DiscordEcho_SetLevel(int v);
extern void DiscordEcho_SetEAXMode(int on);

@interface EchoController : UIViewController
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *echoLabel;
@end

@implementation EchoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // الزر العائم 🔘
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];

    // لوحة التحكم 📋
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 205, 320, 220)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.97];
    panel.layer.cornerRadius = 14;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // شريط مستوى الصدى 🎚️
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 20, 292, 24)];
    lbl.text = @"مستوى صدى الـ EAX: 60";
    lbl.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:lbl];
    self.echoLabel = lbl;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 60, 292, 22)];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = 60;
    [slider addTarget:self action:@selector(echoChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
}

- (void)echoChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetLevel(v);
    self.echoLabel.text = [NSString stringWithFormat:@"مستوى صدى الـ EAX: %d", v];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

@end

static UIWindow *gWin;

__attribute__((constructor))
static void initUI() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = UIWindowLevelAlert + 100;
        window.backgroundColor = UIColor.clearColor;
        window.rootViewController = [EchoController new];
        window.hidden = NO;
        gWin = window;
    });
}
