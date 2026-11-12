// 🎛️ DiscordEchoUI: واجهة التحكم لصدى Creative EAX
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

#pragma mark - فك ترميز الصوت

static const double kTargetRate = 48000.0;
static const size_t kMaxSamples = 48000 * 60 * 8;

static float *EchoDecodeFile(NSURL *url, size_t *outCount, BOOL *truncated) {
    *outCount = 0;
    *truncated = NO;
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&err];
    if (!file) return NULL;
    AVAudioFormat *src = file.processingFormat;
    AVAudioChannelCount chans = src.channelCount;
    if (chans < 1 || src.sampleRate <= 0) return NULL;
    AVAudioFormat *dst = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                          sampleRate:kTargetRate
                                                            channels:chans
                                                         interleaved:NO];
    if (!dst) return NULL;
    AVAudioConverter *conv = [[AVAudioConverter alloc] initFromFormat:src toFormat:dst];
    if (!conv) return NULL;

    double est = (double)file.length * kTargetRate / src.sampleRate + 8192.0;
    size_t cap = est > (double)kMaxSamples ? kMaxSamples : (size_t)est;
    float *out = (float *)malloc(cap * sizeof(float));
    if (!out) return NULL;
    size_t n = 0;

    const AVAudioFrameCount chunk = 4096;
    AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:dst frameCapacity:chunk];
    BOOL finished = NO;
    while (!finished && n < cap) {
        NSError *cerr = nil;
        AVAudioConverterOutputStatus st = [conv convertToBuffer:outBuf
                                                          error:&cerr
                                             withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNum, AVAudioConverterInputStatus *status) {
            AVAudioFramePosition remain = file.length - file.framePosition;
            if (remain <= 0 || inNum == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            AVAudioFrameCount want = inNum;
            if ((AVAudioFramePosition)want > remain) want = (AVAudioFrameCount)remain;
            AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:src frameCapacity:want];
            NSError *rerr = nil;
            if (![file readIntoBuffer:inBuf frameCount:want error:&rerr] || inBuf.frameLength == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            *status = AVAudioConverterInputStatus_HaveData;
            return inBuf;
        }];
        if (st == AVAudioConverterOutputStatus_Error) break;
        if (st == AVAudioConverterOutputStatus_EndOfStream ||
            st == AVAudioConverterOutputStatus_InputRanDry) finished = YES;

        AVAudioFrameCount got = outBuf.frameLength;
        float *const *chData = outBuf.floatChannelData;
        for (AVAudioFrameCount i = 0; i < got && n < cap; i++) {
            float s = 0;
            for (AVAudioChannelCount c = 0; c < chans; c++) s += chData[c][i];
            out[n++] = s / (float)chans;
        }
        if (got == 0) finished = YES;
    }
    if (!finished && n >= cap && cap == kMaxSamples) *truncated = YES;
    if (n < 2) { free(out); return NULL; }
    *outCount = n;
    return out;
}

static NSString *EchoTime(float s) {
    int t = (int)lroundf(s < 0 ? 0 : s);
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

#pragma mark - النافذة العائمة

@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma mark - وحدة التحكم

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface EchoController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) NSArray<UIView *> *tabViews;
@property (nonatomic, strong) UILabel *echoLabel;
@property (nonatomic, strong) UILabel *boostLabel;
@property (nonatomic, strong) UILabel *rangeLabel;
@property (nonatomic, strong) UILabel *wFreqLabel;
@property (nonatomic, strong) UISlider *echoSlider;
@property (nonatomic, strong) UISlider *boostSlider;
@property (nonatomic, strong) UISlider *rangeSlider;
@property (nonatomic, strong) UISlider *wFreqSlider;
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic) BOOL robot;
@property (nonatomic, strong) UILabel *gainLabel;
@property (nonatomic, strong) UISlider *gainSlider;
@property (nonatomic, strong) UIProgressView *meter;
@property (nonatomic, strong) UILabel *songLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UISlider *seekSlider;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UILabel *volLabel;
@property (nonatomic, strong) UISlider *volSlider;
@property (nonatomic) BOOL seeking;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation EchoController

- (UILabel *)makeLabelAt:(CGRect)frame size:(CGFloat)size bold:(BOOL)bold alpha:(CGFloat)alpha {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:alpha];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1.0] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    b.backgroundColor = [UIColor colorWithRed:0.78 green:0.80 blue:0.83 alpha:1.0];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithRed:0.65 green:0.67 blue:0.70 alpha:1.0].CGColor;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UISlider *)makeSliderAt:(CGRect)f min:(float)mn max:(float)mx value:(float)v action:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:f];
    s.minimumValue = mn;
    s.maximumValue = mx;
    s.continuous = YES;
    s.value = v;
    s.minimumTrackTintColor = [UIColor colorWithRed:0.15 green:0.45 blue:0.75 alpha:1.0];
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UISwitch *)addToggleTo:(UIView *)parent title:(NSString *)title x:(CGFloat)x y:(CGFloat)y
                    width:(CGFloat)wd on:(BOOL)on action:(SEL)a {
    UILabel *l = [self makeLabelAt:CGRectMake(x, y, wd - 56, 31) size:13 bold:YES alpha:0.9];
    l.textAlignment = NSTextAlignmentLeft;
    l.numberOfLines = 1;
    l.adjustsFontSizeToFitWidth = YES;
    l.text = title;
    [parent addSubview:l];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame = CGRectMake(x + wd - 51, y, 51, 31);
    sw.on = on;
    sw.onTintColor = [UIColor colorWithRed:0.15 green:0.45 blue:0.75 alpha:1.0];
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    return sw;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    int level = EchoInt(kLevelKey, 60);
    int boost = EchoInt(kBoostKey, 140);
    int range = EchoInt(kRangeKey, 65);
    int wfreq = EchoInt(kWFreqKey, 45);
    int eax   = EchoInt(kEAXKey, 1);
    int gain  = EchoInt(kGainKey, 100);
    int pitch = EchoInt(kPitchKey, 0);
    self.robot = EchoInt(kRobotKey, 0) != 0;
    int mvol  = EchoInt(kMusicVolKey, 100);
    int mloop = EchoInt(kMusicLoopKey, 0);
    int mute  = EchoInt(kMuteKey, 0);

    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:0.95];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1.5;
    fab.layer.borderColor = [UIColor colorWithRed:0.55 green:0.58 blue:0.62 alpha:1.0].CGColor;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:22];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [fab addGestureRecognizer:pan];
    [self.view addSubview:fab];
    self.fab = fab;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.88 green:0.90 blue:0.93 alpha:0.97];
    panel.layer.cornerRadius = 14;
    panel.layer.borderWidth = 1.5;
    panel.layer.borderColor = [UIColor colorWithRed:0.68 green:0.71 blue:0.75 alpha:1.0].CGColor;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"EAX صدى", @"🎙️ نبرة", @"🎚️ مضخّم", @"🎵 أغاني"]];
    tabs.frame = CGRectMake(12, 10, kPanelW - 24, 34);
    tabs.selectedSegmentIndex = 0;
    tabs.selectedSegmentTintColor = [UIColor colorWithRed:0.18 green:0.50 blue:0.82 alpha:1.0];
    NSDictionary *darkText = @{ NSForegroundColorAttributeName: [UIColor colorWithRed:0.1 green:0.1 blue:0.12 alpha:1.0] };
    NSDictionary *whiteText = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
    [tabs setTitleTextAttributes:darkText forState:UIControlStateNormal];
    [tabs setTitleTextAttributes:whiteText forState:UIControlStateSelected];
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

    CGFloat w = kPanelW - 28;

    [self addToggleTo:tabEcho title:@"✨ Creative EAX Cavern Mode" x:14 y:2 width:w on:eax != 0 action:@selector(eaxToggled:)];

    self.echoLabel = [self makeLabelAt:CGRectMake(14, 38, w, 18) size:12 bold:YES alpha:0.95];
    [tabEcho addSubview:self.echoLabel];
    self.echoSlider = [self makeSliderAt:CGRectMake(14, 56, w, 22) min:0 max:100 value:level action:@selector(echoChanged:)];
    [tabEcho addSubview:self.echoSlider];

    self.boostLabel = [self makeLabelAt:CGRectMake(14, 80, w, 18) size:12 bold:YES alpha:0.95];
    [tabEcho addSubview:self.boostLabel];
    self.boostSlider = [self makeSliderAt:CGRectMake(14, 98, w, 22) min:100 max:300 value:boost action:@selector(boostChanged:)];
    [tabEcho addSubview:self.boostSlider];

    self.rangeLabel = [self makeLabelAt:CGRectMake(14, 122, w, 18) size:12 bold:YES alpha:0.95];
    [tabEcho addSubview:self.rangeLabel];
    self.rangeSlider = [self makeSliderAt:CGRectMake(14, 140, w, 22) min:0 max:100 value:range action:@selector(rangeChanged:)];
    [tabEcho addSubview:self.rangeSlider];

    self.wFreqLabel = [self makeLabelAt:CGRectMake(14, 164, w, 18) size:12 bold:YES alpha:0.95];
    [tabEcho addSubview:self.wFreqLabel];
    self.wFreqSlider = [self makeSliderAt:CGRectMake(14, 182, w, 22) min:0 max:100 value:wfreq action:@selector(wFreqChanged:)];
    [tabEcho addSubview:self.wFreqSlider];

    UILabel *modLbl = [self makeLabelAt:CGRectMake(14, 208, w, 18) size:11.5 bold:YES alpha:0.8];
    modLbl.textAlignment = NSTextAlignmentLeft;
    modLbl.text = @"🎛️ مودات الكهف (Presets):";
    [tabEcho addSubview:modLbl];

    NSArray *eaxPresets = @[@"كهف عميق", @"استوديو", @"مسرح", @"طبيعي"];
    NSArray *eaxTags    = @[@1, @2, @3, @4];
    CGFloat e_bw = (w - 9) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        CGRect f = CGRectMake(14 + i * (e_bw + 3), 228, e_bw, 32);
        [tabEcho addSubview:[self makeButton:eaxPresets[i] frame:f tag:[eaxTags[i] integerValue] action:@selector(eaxPresetTapped:)]];
    }

    self.pitchLabel = [self makeLabelAt:CGRectMake(14, 4, w, 24) size:14 bold:YES alpha:0.95];
    [tabPitch addSubview:self.pitchLabel];
    self.pitchSlider = [self makeSliderAt:CGRectMake(14, 30, w, 28) min:-12 max:12 value:pitch action:@selector(pitchChanged:)];
    [tabPitch addSubview:self.pitchSlider];

    NSArray *names = @[@"عادي", @"أنثوي", @"عميق", @"عملاق", @"روبوت", @"🎲 عشوائي"];
    CGFloat pbw = (w - 12) / 3.0;
    for (NSInteger i = 0; i < 6; i++) {
        NSInteger col = i % 3, row = i / 3;
        CGRect f = CGRectMake(14 + col * (pbw + 6), 70 + row * 40, pbw, 34);
        [tabPitch addSubview:[self makeButton:names[i] frame:f tag:i action:@selector(presetTapped:)]];
    }

    self.gainLabel = [self makeLabelAt:CGRectMake(14, 4, w, 24) size:14 bold:YES alpha:0.95];
    [tabAmp addSubview:self.gainLabel];
    self.gainSlider = [self makeSliderAt:CGRectMake(14, 30, w, 28) min:100 max:500 value:gain action:@selector(gainChanged:)];
    [tabAmp addSubview:self.gainSlider];

    NSArray *quickNames = @[@"1x", @"1.5x", @"2x", @"3x", @"5x"];
    NSArray *quickTags  = @[@100, @150, @200, @300, @500];
    CGFloat qbw = (w - 6 * 4) / 5.0;
    for (NSInteger i = 0; i < 5; i++) {
        CGRect f = CGRectMake(14 + i * (qbw + 6), 68, qbw, 32);
        [tabAmp addSubview:[self makeButton:quickNames[i] frame:f tag:[quickTags[i] integerValue] action:@selector(gainQuick:)]];
    }

    UIProgressView *meter = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    meter.frame = CGRectMake(14, 130, w, 8);
    meter.trackTintColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    meter.progressTintColor = [UIColor colorWithRed:0.1 green:0.65 blue:0.25 alpha:1.0];
    [tabAmp addSubview:meter];
    self.meter = meter;

    self.songLabel = [self makeLabelAt:CGRectMake(14, 4, w, 32) size:12.5 bold:YES alpha:0.9];
    self.songLabel.text = @"اختر ملف صوتي من مدير الملفات";
    [tabMusic addSubview:self.songLabel];

    [tabMusic addSubview:[self makeButton:@"📂 تحميل ملف صوتي" frame:CGRectMake(14, 40, w, 34) tag:0 action:@selector(chooseSong)]];

    UISlider *seek = [self makeSliderAt:CGRectMake(14, 82, w, 28) min:0 max:1 value:0 action:@selector(seekChanged:)];
    [seek addTarget:self action:@selector(seekBegan:) forControlEvents:UIControlEventTouchDown];
    [seek addTarget:self action:@selector(seekEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [tabMusic addSubview:seek];
    self.seekSlider = seek;

    self.timeLabel = [self makeLabelAt:CGRectMake(14, 110, w, 18) size:11.5 bold:NO alpha:0.75];
    self.timeLabel.text = @"0:00 / 0:00";
    [tabMusic addSubview:self.timeLabel];

    CGFloat hb = (w - 6) / 2.0;
    self.playBtn = [self makeButton:@"▶︎ تشغيل" frame:CGRectMake(14, 134, hb, 34) tag:0 action:@selector(playTapped)];
    [tabMusic addSubview:self.playBtn];
    [tabMusic addSubview:[self makeButton:@"⏹ إيقاف" frame:CGRectMake(14 + hb + 6, 134, hb, 34) tag:0 action:@selector(stopTapped)]];

    self.volLabel = [self makeLabelAt:CGRectMake(14, 174, w, 22) size:14 bold:YES alpha:0.95];
    [tabMusic addSubview:self.volLabel];
    self.volSlider = [self makeSliderAt:CGRectMake(14, 198, w, 28) min:0 max:200 value:mvol action:@selector(volChanged:)];
    [tabMusic addSubview:self.volSlider];

    [self addToggleTo:tabMusic title:@"🔁 تكرار التشغيل" x:14 y:234 width:w on:mloop != 0 action:@selector(loopToggled:)];
    [self addToggleTo:tabMusic title:@"🔇 كتم المايك مع الأغنية" x:14 y:270 width:w on:mute != 0 action:@selector(muteToggled:)];

    [self updateEchoLabel:level];
    [self updateBoostLabel:boost];
    [self updateRangeLabel:range];
    [self updateWFreqLabel:wfreq];
    [self updatePitchLabel];
    [self updateGainLabel:gain];
    [self updateVolLabel:mvol];

    DiscordEcho_SetLevel(level);
    DiscordEcho_SetEchoBoost(boost);
    DiscordEcho_SetRange(range);
    DiscordEcho_SetWhisperFreq(wfreq);
    DiscordEcho_SetEAXMode(eax);
    DiscordEcho_SetGain(gain);
    DiscordEcho_SetPitch(pitch);
    DiscordEcho_SetRobot(self.robot ? 1 : 0);
    DiscordEcho_MusicSetVolume(mvol);
    DiscordEcho_MusicSetLoop(mloop);
    DiscordEcho_SetVoiceMute(mute);
}

- (void)updateEchoLabel:(int)v { self.echoLabel.text = (v == 0) ? @"الصدى: متوقف" : [NSString stringWithFormat:@"حجم صدى الكهف: %d", v]; }
- (void)updateBoostLabel:(int)v { self.boostLabel.text = [NSString stringWithFormat:@"قوة التضخيم (Boost): %d%%", v]; }
- (void)updateRangeLabel:(int)v { self.rangeLabel.text = [NSString stringWithFormat:@"مساحة الكهف (3D): %d", v]; }
- (void)updateWFreqLabel:(int)v { self.wFreqLabel.text = [NSString stringWithFormat:@"تردد الهمس: %d", v]; }
- (void)updatePitchLabel {
    int st = (int)lroundf(self.pitchSlider.value);
    NSString *t = (st == 0) ? @"النبرة: عادية" : [NSString stringWithFormat:@"النبرة: %+d نغمة", st];
    if (self.robot) t = [t stringByAppendingString:@"  ·  🤖 روبوت"];
    self.pitchLabel.text = t;
}
- (void)updateGainLabel:(int)v { self.gainLabel.text = [NSString stringWithFormat:@"مستوى المايك: %d%%", v]; }
- (void)updateVolLabel:(int)v { self.volLabel.text = [NSString stringWithFormat:@"مستوى الأغنية: %d%%", v]; }

- (void)tabChanged:(UISegmentedControl *)sender {
    for (NSUInteger i = 0; i < self.tabViews.count; i++)
        self.tabViews[i].hidden = ((NSInteger)i != sender.selectedSegmentIndex);
}

- (void)saveInt:(int)v key:(NSString *)k {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:k];
}

- (void)eaxToggled:(UISwitch *)s { DiscordEcho_SetEAXMode(s.on ? 1 : 0); [self saveInt:s.on ? 1 : 0 key:kEAXKey]; }
- (void)echoChanged:(UISlider *)s { int v = (int)lroundf(s.value); DiscordEcho_SetLevel(v); [self saveInt:v key:kLevelKey]; [self updateEchoLabel:v]; }
- (void)boostChanged:(UISlider *)s { int v = (int)lroundf(s.value); DiscordEcho_SetEchoBoost(v); [self saveInt:v key:kBoostKey]; [self updateBoostLabel:v]; }
- (void)rangeChanged:(UISlider *)s { int v = (int)lroundf(s.value); DiscordEcho_SetRange(v); [self saveInt:v key:kRangeKey]; [self updateRangeLabel:v]; }
- (void)wFreqChanged:(UISlider *)s { int v = (int)lroundf(s.value); DiscordEcho_SetWhisperFreq(v); [self saveInt:v key:kWFreqKey]; [self updateWFreqLabel:v]; }

- (void)eaxPresetTapped:(UIButton *)b {
    int lvl = 60, bst = 140, rng = 65, wf = 45;
    if (b.tag == 1) { lvl = 75; bst = 200; rng = 85; wf = 65; }
    else if (b.tag == 2) { lvl = 45; bst = 120; rng = 50; wf = 30; }
    else if (b.tag == 3) { lvl = 90; bst = 260; rng = 95; wf = 80; }
    else if (b.tag == 4) { lvl = 55; bst = 130; rng = 60; wf = 40; }

    self.echoSlider.value = lvl; [self echoChanged:self.echoSlider];
    self.boostSlider.value
