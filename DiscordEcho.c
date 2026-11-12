// DiscordEcho: معالج صوت المايك داخل تطبيق (مثل ديسكورد)
//   - تغيير النبرة (pitch) من -12 إلى +12 نغمة + صوت روبوت
//   - صدى: كهف (reverb ممتد) + تكرار (الو الو الو)، يشتغلون مع بعض أو لحالهم
//       شدة 0..100، مضخّم الصدى 100%..400%، مدى الصدى 0..100
//   - تضخيم الصوت من 100% إلى 800% مع حد ناعم يمنع التقطع
//   - مشغّل أغنية: تتمزج داخل المايك فيسمعها اللي معك في الكول
//   - قياس مستوى المايك للعرض في القائمة
// يعمل عبر fishhook: يستبدل AudioUnitRender ويعدّل بيانات المايك قبل ما يرسلها التطبيق.
// الترتيب: نبرة -> روبوت -> صدى -> تضخيم -> (+ الأغنية).

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "fishhook.h"

#define MAX_RATE 48000
#define MAX_BUFS 2
#define LINE_LEN (MAX_RATE * 2)
#define MUSIC_TMP 8192

// ---------- إعدادات تتغير من القائمة ----------
static volatile int   g_level = 50;    // شدة الصدى 0..100
static volatile int   g_boost = 100;   // مضخّم الصدى 100..400 (%)
static volatile int   g_range = 60;    // مدى الصدى 0..100
static volatile int   g_cave  = 1;     // كهف
static volatile int   g_repeat = 1;    // تكرار
static volatile int   g_gain  = 100;   // تضخيم الصوت 100..800 (%)
static volatile int   g_pitch = 0;     // نغمات -12..12
static volatile int   g_robot = 0;     // 0/1
static volatile int   g_voice_mute = 0;// كتم صوتي أثناء الأغنية
static volatile float g_peak  = 0.0f;  // مستوى المايك 0..1

void DiscordEcho_SetLevel(int v)  { g_level = v < 0 ? 0 : (v > 100 ? 100 : v); }
void DiscordEcho_SetEchoBoost(int v) { g_boost = v < 100 ? 100 : (v > 400 ? 400 : v); }
void DiscordEcho_SetRange(int v)  { g_range = v < 0 ? 0 : (v > 100 ? 100 : v); }
void DiscordEcho_SetCave(int on)  { g_cave = on ? 1 : 0; }
void DiscordEcho_SetRepeat(int on){ g_repeat = on ? 1 : 0; }
void DiscordEcho_SetGain(int v)   { g_gain = v < 100 ? 100 : (v > 800 ? 800 : v); }
void DiscordEcho_SetPitch(int v)  { g_pitch = v < -12 ? -12 : (v > 12 ? 12 : v); }
void DiscordEcho_SetRobot(int on) { g_robot = on ? 1 : 0; }
void DiscordEcho_SetVoiceMute(int on) { g_voice_mute = on ? 1 : 0; }
float DiscordEcho_GetPeak(void)   { return g_peak; }

// ---------- حد ناعم: يرفع الصوت بدون ما يقطعه ----------
static float soft_limit(float y) {
    float a = y < 0 ? -y : y;
    if (a <= 0.6f) return y;
    float s = 0.6f + 0.4f * tanhf((a - 0.6f) / 0.4f);
    return y < 0 ? -s : s;
}

// ---------- التكرار (delay مع feedback) ----------
#define REP_GAIN 1.2f
static float g_line[MAX_BUFS][LINE_LEN];
static size_t g_pos[MAX_BUFS];
static int g_cleared[MAX_BUFS];

// ---------- كهف (reverb): 8 مرشحات comb متوازية + 4 allpass متسلسلة ----------
#define RV_COMBS    8
#define RV_APS      4
#define RV_COMB_MAX 8192
#define RV_AP_MAX   2048
#define RV_DAMP     0.40f   // تغميق الذيل (أكبر = أغمق)
#define RV_WET      3.0f

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

static float rv_process(Reverb *rv, float x, float fb, const int *clen, const int *alen) {
    float in = x * 0.015f;
    float acc = 0.0f;
    for (int c = 0; c < RV_COMBS; c++) {
        unsigned p = rv->cpos[c];
        if (p >= (unsigned)clen[c]) p = 0;
        float out = rv->comb[c][p];
        rv->damp[c] = out * (1.0f - RV_DAMP) + rv->damp[c] * RV_DAMP;
        rv->comb[c][p] = in + rv->damp[c] * fb;
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

// ---------- مشغّل الأغنية (مخزّنة كعينات أحادية 48kHz) ----------
typedef struct { float *data; size_t len; } MusicSlot;
static MusicSlot g_mslot[2];
static volatile int    g_mcur = -1;      // الخانة المستخدمة حالياً (-1 = ما فيه)
static volatile int    g_mplaying = 0;
static volatile int    g_mloop = 0;
static volatile int    g_mvol = 100;     // 0..200 (%)
static volatile double g_mpos = 0.0;     // موضع التشغيل بالعينات
static volatile double g_mseek = -1.0;   // طلب قفز (-1 = ما فيه)
static float g_mtmp[MUSIC_TMP];

// تأخذ ملكية المصفوفة (malloc). تتحرر لما تتحمّل أغنية ثانية.
int DiscordEcho_MusicLoad(float *samples, size_t count) {
    if (!samples || count < 2) return 0;
    int next = (g_mcur == 0) ? 1 : 0;
    g_mplaying = 0;
    free(g_mslot[next].data);
    g_mslot[next].data = samples;
    g_mslot[next].len = count;
    g_mpos = 0.0;
    g_mseek = -1.0;
    __sync_synchronize();
    g_mcur = next;
    return 1;
}
void DiscordEcho_MusicPlay(int play) { if (g_mcur >= 0) g_mplaying = play ? 1 : 0; }
void DiscordEcho_MusicStop(void) { g_mplaying = 0; g_mseek = 0.0; g_mpos = 0.0; }
void DiscordEcho_MusicSeek(float frac) {
    int cur = g_mcur;
    if (cur < 0) return;
    if (frac < 0.0f) frac = 0.0f;
    if (frac > 1.0f) frac = 1.0f;
    g_mseek = (double)frac * (double)g_mslot[cur].len;
}
void DiscordEcho_MusicSetVolume(int pct) { g_mvol = pct < 0 ? 0 : (pct > 200 ? 200 : pct); }
void DiscordEcho_MusicSetLoop(int on) { g_mloop = on ? 1 : 0; }
int  DiscordEcho_MusicIsPlaying(void) { return g_mplaying; }
float DiscordEcho_MusicProgress(void) {
    int cur = g_mcur;
    if (cur < 0 || g_mslot[cur].len < 2) return 0.0f;
    double p = g_mpos / (double)g_mslot[cur].len;
    return (float)(p < 0 ? 0 : (p > 1 ? 1 : p));
}
float DiscordEcho_MusicDuration(void) {
    int cur = g_mcur;
    return cur < 0 ? 0.0f : (float)((double)g_mslot[cur].len / 48000.0);
}

// تولّد عينات الأغنية لهذي الدفعة (بمعدل المايك). ترجع 1 إذا فيه أغنية تشتغل.
static int music_generate(float *out, UInt32 frames, float rate) {
    int cur = g_mcur;
    if (cur < 0 || frames == 0 || frames > MUSIC_TMP) return 0;
    const float *d = g_mslot[cur].data;
    size_t len = g_mslot[cur].len;
    if (!d || len < 2) return 0;
    if (g_mseek >= 0.0) {
        double s = g_mseek;
        if (s > (double)(len - 2)) s = (double)(len - 2);
        g_mpos = s;
        g_mseek = -1.0;
    }
    if (!g_mplaying) return 0;
    if (rate < 8000.0f) rate = 48000.0f;
    double step = 48000.0 / (double)rate;
    double pos = g_mpos;
    float vol = (float)g_mvol / 100.0f;
    int loop = g_mloop;
    int on = 1;
    for (UInt32 i = 0; i < frames; i++) {
        float m = 0.0f;
        if (on) {
            if (pos >= (double)(len - 1)) {
                if (loop) { pos = 0.0; }
                else { on = 0; g_mplaying = 0; pos = 0.0; }
            }
            if (on) {
                size_t i0 = (size_t)pos;
                float fr = (float)(pos - (double)i0);
                m = d[i0] + fr * (d[i0 + 1] - d[i0]);
                pos += step;
            }
        }
        out[i] = m * vol;
    }
    g_mpos = pos;
    return 1;
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

static void clear_state(int idx) {
    memset(&g_rv[idx], 0, sizeof(g_rv[idx]));
    memset(g_line[idx], 0, sizeof(g_line[idx]));
    g_pos[idx] = 0;
}

static void process_buffer(int idx, AudioBuffer *ab, const float *mus, UInt32 mus_frames) {
    int is_float = (g_fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    UInt32 bits = g_fmt.mBitsPerChannel;
    if (!((is_float && bits == 32) || (!is_float && bits == 16))) return;

    UInt32 bytes_per = bits / 8;
    size_t n = ab->mDataByteSize / bytes_per;
    UInt32 chans = ab->mNumberChannels ? ab->mNumberChannels : 1;

    int lvl = g_level;
    int gn = g_gain;
    int semis = g_pitch;
    int cave = g_cave, rep = g_repeat;

    int echo_on = lvl > 0 && (cave || rep);
    int ps_on = (semis != 0) && chans == 1;     // النبرة والروبوت للمايك الأحادي فقط
    int robot_on = g_robot && chans == 1;
    int mute = g_voice_mute && mus != NULL;
    int changed = echo_on || ps_on || robot_on || gn != 100 || mus != NULL;

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
        if (!g_cleared[idx]) { clear_state(idx); g_cleared[idx] = 1; }
        g_ps_on[idx] = 0;
        return;
    }

    if (!echo_on) {
        if (!g_cleared[idx]) { clear_state(idx); g_cleared[idx] = 1; }
    } else {
        g_cleared[idx] = 0;
    }

    PitchShifter *ps = &g_ps[idx];
    if (ps_on) {
        if (!g_ps_on[idx]) { memset(ps, 0, sizeof(*ps)); g_ps_on[idx] = 1; }
    } else {
        g_ps_on[idx] = 0;
    }

    float rate = (float)g_fmt.mSampleRate;
    if (rate < 8000.0f) rate = 48000.0f;

    // ----- بارامترات الصدى من "المدى" -----
    float r = (float)g_range / 100.0f;
    float rep_fb    = 0.40f + 0.47f * r;      // كم مرة يتكرر
    float rep_delay = 0.28f + 0.22f * r;      // ثواني بين التكرارات
    float cave_fb   = 0.84f + 0.12f * r;      // طول ذيل الكهف
    float cave_size = 1.4f + 0.8f * r;        // حجم الكهف
    float wet_gain  = ((float)lvl / 100.0f) * ((float)g_boost / 100.0f);

    float gain = (float)gn / 100.0f;
    float ratio = powf(2.0f, (float)semis / 12.0f);
    float rstep = 6.2831853f * 70.0f / rate;

    size_t D = (size_t)(rep_delay * rate) * chans;
    if (D < 1) D = 1;
    if (D >= LINE_LEN) D = LINE_LEN - 1;

    float *line = g_line[idx];
    size_t p = g_pos[idx];
    if (p >= D) p = 0;

    Reverb *rv = &g_rv[idx];
    int clen[RV_COMBS], alen[RV_APS];
    float rs = rate / 44100.0f;
    for (int c = 0; c < RV_COMBS; c++) {
        int L = (int)((float)kCombBase[c] * rs * cave_size) * (int)chans;
        clen[c] = L < 1 ? 1 : (L >= RV_COMB_MAX ? RV_COMB_MAX - 1 : L);
    }
    for (int a = 0; a < RV_APS; a++) {
        int L = (int)((float)kApBase[a] * rs) * (int)chans;
        alen[a] = L < 1 ? 1 : (L >= RV_AP_MAX ? RV_AP_MAX - 1 : L);
    }

    float pk = 0.0f;
    UInt32 ch = 0;
    size_t fi = 0;
    for (size_t i = 0; i < n; i++) {
        float x = is_float ? ((float *)ab->mData)[i]
                           : ((int16_t *)ab->mData)[i] / 32768.0f;
        float y = mute ? 0.0f : x;

        if (ps_on) y = ps_process(ps, y, ratio);

        if (robot_on) {
            y *= 1.4f * sinf(g_robot_phase);
            g_robot_phase += rstep;
            if (g_robot_phase > 6.2831853f) g_robot_phase -= 6.2831853f;
        }

        if (echo_on) {
            float wet = 0.0f;
            float rin = y;
            if (rep) {
                float d = line[p];
                line[p] = y + rep_fb * d;
                wet += d * REP_GAIN;
                rin = y + 0.6f * d;            // الكهف يسمع التكرارات كمان
                if (++p >= D) p = 0;
            }
            if (cave) {
                wet += rv_process(rv, rin, cave_fb, clen, alen) * RV_WET;
            }
            y = y + wet * wet_gain;
        }

        y = soft_limit(y * gain);

        float a = y < 0 ? -y : y;
        if (a > pk) pk = a;

        if (mus && fi < mus_frames) y = soft_limit(y + mus[fi]);

        if (is_float) ((float *)ab->mData)[i] = y;
        else          ((int16_t *)ab->mData)[i] = (int16_t)(y * 32767.0f);

        if (++ch >= chans) { ch = 0; fi++; }
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

    int mus_on = music_generate(g_mtmp, frames, (float)g_fmt.mSampleRate);
    for (UInt32 b = 0; b < io->mNumberBuffers && b < MAX_BUFS; b++) {
        if (io->mBuffers[b].mData)
            process_buffer((int)b, &io->mBuffers[b], mus_on ? g_mtmp : NULL, frames);
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
