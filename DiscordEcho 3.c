// DiscordEcho: معالج صوت المايك داخل تطبيق (مثل ديسكورد)
//   - تغيير النبرة (pitch) من -12 إلى +12 نغمة
//   - صوت روبوت (ring modulation)
//   - صدى من 0 إلى 100، بنمطين: تكرار (الو الو الو) أو كهف (reverb ممتد)
//   - تضخيم الصوت من 100% إلى 400%
//   - قياس مستوى المايك للعرض في القائمة
// يعمل عبر fishhook: يستبدل AudioUnitRender ويعدّل بيانات المايك قبل ما يرسلها التطبيق.
// الترتيب: نبرة -> روبوت -> صدى -> تضخيم.

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "fishhook.h"

#define ECHO_DELAY_SEC 0.30f
#define MAX_FEEDBACK   0.60f
#define MAX_MIX        1.20f

#define MAX_RATE 48000
#define MAX_BUFS 2
#define LINE_LEN (MAX_RATE * 2)

// ---------- إعدادات تتغير من القائمة ----------
static volatile int   g_level = 50;    // صدى 0..100
static volatile int   g_gain  = 100;   // تضخيم 100..400 (%)
static volatile int   g_pitch = 0;     // نغمات -12..12
static volatile int   g_robot = 0;     // 0/1
static volatile float g_peak  = 0.0f;  // مستوى المايك 0..1
static volatile int   g_mode  = 0;     // 0 = تكرار، 1 = كهف

void DiscordEcho_SetLevel(int level) {
    if (level < 0) level = 0;
    if (level > 100) level = 100;
    g_level = level;
}
void DiscordEcho_SetGain(int gain) {
    if (gain < 100) gain = 100;
    if (gain > 400) gain = 400;
    g_gain = gain;
}
void DiscordEcho_SetPitch(int semitones) {
    if (semitones < -12) semitones = -12;
    if (semitones > 12) semitones = 12;
    g_pitch = semitones;
}
void DiscordEcho_SetRobot(int on) { g_robot = on ? 1 : 0; }
void DiscordEcho_SetMode(int mode) { g_mode = mode ? 1 : 0; }
float DiscordEcho_GetPeak(void) { return g_peak; }

// ---------- الصدى ----------
static float g_line[MAX_BUFS][LINE_LEN];
static size_t g_pos[MAX_BUFS];
static int g_cleared[MAX_BUFS];

// ---------- كهف (reverb): 8 مرشحات comb متوازية + 4 allpass متسلسلة ----------
#define RV_COMBS    8
#define RV_APS      4
#define RV_COMB_MAX 8192
#define RV_AP_MAX   2048
#define RV_SIZE     1.8f    // حجم الكهف (أكبر = أوسع)
#define RV_FEEDBACK 0.90f   // طول الذيل
#define RV_DAMP     0.40f   // تغميق الذيل (أكبر = أغمق)
#define RV_WET      3.0f    // قوة الكهف عند شدة 100

typedef struct {
    float comb[RV_COMBS][RV_COMB_MAX];
    float damp[RV_COMBS];
    unsigned cpos[RV_COMBS];
    float ap[RV_APS][RV_AP_MAX];
    unsigned apos[RV_APS];
} Reverb;

static Reverb g_rv[MAX_BUFS];
static const int kCombBase[RV_COMBS] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
static const int kApBase[RV_APS] = {556, 441, 341, 225};

static float rv_process(Reverb *rv, float x, const int *clen, const int *alen) {
    float in = x * 0.015f;
    float acc = 0.0f;
    for (int c = 0; c < RV_COMBS; c++) {
        unsigned p = rv->cpos[c];
        if (p >= (unsigned)clen[c]) p = 0;
        float out = rv->comb[c][p];
        rv->damp[c] = out * (1.0f - RV_DAMP) + rv->damp[c] * RV_DAMP;
        rv->comb[c][p] = in + rv->damp[c] * RV_FEEDBACK;
        if (++p >= (unsigned)clen[c]) p = 0;
        rv->cpos[c] = p;
        acc += out;
    }
    for (int a = 0; a < RV_APS; a++) {
        unsigned p = rv->apos[a];
        if (p >= (unsigned)alen[a]) p = 0;
        float b = rv->ap[a][p];
        float out = b - acc;
        rv->ap[a][p] = acc + b * 0.5f;
        if (++p >= (unsigned)alen[a]) p = 0;
        rv->apos[a] = p;
        acc = out;
    }
    return acc;
}

// ---------- مغيّر النبرة (خط تأخير بنافذتين متداخلتين) ----------
#define PS_WIN 2048
#define PS_BUF 4096   // لازم يكون من مضاعفات 2 وأكبر من PS_WIN + 2

typedef struct {
    float buf[PS_BUF];
    unsigned w;
    float d;
} PitchShifter;

static PitchShifter g_ps[MAX_BUFS];
static int g_ps_on[MAX_BUFS];
static float g_win[1025];
static float g_robot_phase;

static float ps_tap(const PitchShifter *ps, float d) {
    int di = (int)d;
    float fr = d - (float)di;
    float a = ps->buf[(ps->w - (unsigned)di) & (PS_BUF - 1)];
    float b = ps->buf[(ps->w - (unsigned)di - 1u) & (PS_BUF - 1)];
    return a + fr * (b - a);
}

static float ps_process(PitchShifter *ps, float x, float ratio) {
    ps->buf[ps->w & (PS_BUF - 1)] = x;
    float d1 = ps->d;
    float d2 = d1 + PS_WIN * 0.5f;
    if (d2 >= PS_WIN) d2 -= PS_WIN;
    float y = g_win[(int)(d1 * (1024.0f / PS_WIN))] * ps_tap(ps, d1)
            + g_win[(int)(d2 * (1024.0f / PS_WIN))] * ps_tap(ps, d2);
    ps->w++;
    ps->d += 1.0f - ratio;
    if (ps->d >= PS_WIN) ps->d -= PS_WIN;
    if (ps->d < 0.0f) ps->d += PS_WIN;
    return y;
}

// ---------- الهوك ----------
static AudioUnit g_unit;
static AudioStreamBasicDescription g_fmt;
static int g_have_fmt;

static OSStatus (*orig_render)(AudioUnit, AudioUnitRenderActionFlags *,
                               const AudioTimeStamp *, UInt32, UInt32,
                               AudioBufferList *);

static void update_peak(float pk) {
    float prev = g_peak * 0.8f;
    g_peak = pk > prev ? pk : prev;
}

static void process_buffer(int idx, AudioBuffer *ab) {
    int is_float = (g_fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    UInt32 bits = g_fmt.mBitsPerChannel;
    if (!((is_float && bits == 32) || (!is_float && bits == 16))) return;

    UInt32 bytes_per = bits / 8;
    size_t n = ab->mDataByteSize / bytes_per;
    UInt32 chans = ab->mNumberChannels ? ab->mNumberChannels : 1;

    int lvl = g_level;
    int gn = g_gain;
    int semis = g_pitch;
    int mode = g_mode;

    int echo_on = lvl > 0;
    int ps_on = (semis != 0) && chans == 1;     // النبرة والروبوت للمايك الأحادي فقط
    int robot_on = g_robot && chans == 1;
    int changed = echo_on || ps_on || robot_on || gn != 100;

    // لا شي مفعّل: بس نقيس المستوى ونخلي الصوت يمر كما هو
    if (!changed) {
        float pk = 0.0f;
        for (size_t i = 0; i < n; i++) {
            float x = is_float ? ((float *)ab->mData)[i]
                               : ((int16_t *)ab->mData)[i] / 32768.0f;
            float a = x < 0 ? -x : x;
            if (a > pk) pk = a;
        }
        update_peak(pk);
        if (!g_cleared[idx]) {
            memset(&g_rv[idx], 0, sizeof(g_rv[idx]));
            memset(g_line[idx], 0, sizeof(g_line[idx]));
            g_pos[idx] = 0;
            g_cleared[idx] = 1;
        }
        g_ps_on[idx] = 0;
        return;
    }

    if (!echo_on) {
        if (!g_cleared[idx]) {
            memset(&g_rv[idx], 0, sizeof(g_rv[idx]));
            memset(g_line[idx], 0, sizeof(g_line[idx]));
            g_pos[idx] = 0;
            g_cleared[idx] = 1;
        }
    } else {
        g_cleared[idx] = 0;
    }

    PitchShifter *ps = &g_ps[idx];
    if (ps_on) {
        if (!g_ps_on[idx]) {
            memset(ps, 0, sizeof(*ps));
            g_ps_on[idx] = 1;
        }
    } else {
        g_ps_on[idx] = 0;
    }

    float gain = (float)gn / 100.0f;
    float k = (float)lvl / 100.0f;
    float feedback = k * MAX_FEEDBACK;
    float mix = k * MAX_MIX;
    float ratio = powf(2.0f, (float)semis / 12.0f);
    float rate = (float)g_fmt.mSampleRate;
    if (rate < 8000.0f) rate = 48000.0f;
    float rstep = 6.2831853f * 70.0f / rate;

    size_t D = (size_t)(ECHO_DELAY_SEC * rate) * chans;
    if (D < 1) D = 1;
    if (D >= LINE_LEN) D = LINE_LEN - 1;

    float *line = g_line[idx];

    Reverb *rv = &g_rv[idx];
    int clen[RV_COMBS], alen[RV_APS];
    float rs = rate / 44100.0f;
    for (int c = 0; c < RV_COMBS; c++) {
        int L = (int)((float)kCombBase[c] * rs * RV_SIZE) * (int)chans;
        clen[c] = L < 1 ? 1 : (L >= RV_COMB_MAX ? RV_COMB_MAX - 1 : L);
    }
    for (int a = 0; a < RV_APS; a++) {
        int L = (int)((float)kApBase[a] * rs) * (int)chans;
        alen[a] = L < 1 ? 1 : (L >= RV_AP_MAX ? RV_AP_MAX - 1 : L);
    }
    size_t p = g_pos[idx];
    if (p >= D) p = 0;

    float pk = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float x = is_float ? ((float *)ab->mData)[i]
                           : ((int16_t *)ab->mData)[i] / 32768.0f;
        float y = x;

        if (ps_on) y = ps_process(ps, y, ratio);

        if (robot_on) {
            y *= 1.4f * sinf(g_robot_phase);
            g_robot_phase += rstep;
            if (g_robot_phase > 6.2831853f) g_robot_phase -= 6.2831853f;
        }

        if (echo_on) {
            if (mode == 1) {
                float w = rv_process(rv, y, clen, alen);
                y = y + w * (k * RV_WET);
            } else {
                float d = line[p];
                line[p] = y + feedback * d;
                y = y + mix * d;
                if (++p >= D) p = 0;
            }
        }

        y *= gain;
        if (y > 1.0f) y = 1.0f;
        if (y < -1.0f) y = -1.0f;

        float a = y < 0 ? -y : y;
        if (a > pk) pk = a;

        if (is_float) ((float *)ab->mData)[i] = y;
        else          ((int16_t *)ab->mData)[i] = (int16_t)(y * 32767.0f);
    }
    if (echo_on) g_pos[idx] = p;
    update_peak(pk);
}

static OSStatus my_render(AudioUnit unit, AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts, UInt32 bus,
                          UInt32 frames, AudioBufferList *io) {
    OSStatus st = orig_render(unit, flags, ts, bus, frames, io);
    if (st != noErr || bus != 1 || io == NULL) return st;   // bus 1 = المايك

    if (unit != g_unit || !g_have_fmt) {
        UInt32 sz = sizeof(g_fmt);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 1, &g_fmt, &sz) == noErr) {
            g_unit = unit;
            g_have_fmt = 1;
        } else {
            g_have_fmt = 0;
            return st;
        }
    }

    for (UInt32 b = 0; b < io->mNumberBuffers && b < MAX_BUFS; b++) {
        if (io->mBuffers[b].mData) process_buffer((int)b, &io->mBuffers[b]);
    }
    return st;
}

__attribute__((constructor))
static void init(void) {
    for (int i = 0; i <= 1024; i++) {
        float s = sinf(3.14159265f * (float)i / 1024.0f);
        g_win[i] = s * s;
    }
    struct rebinding r = { "AudioUnitRender", (void *)my_render, (void **)&orig_render };
    rebind_symbols(&r, 1);
}
