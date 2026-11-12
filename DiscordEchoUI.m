// 🎛️ DiscordEchoUI: واجهة التحكم المطورة لصدى Creative EAX وتردد الهمس
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

