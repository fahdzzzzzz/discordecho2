// DiscordEcho: معالج صوت المايك (محاكاة EAX 3D احترافية)
#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "fishhook.h"

#define MAX_RATE 48000
#define MAX_BUFS 2
#define LINE_LEN (MAX_RATE * 1)
#define MUSIC_TMP 8192

static volatile int   g_level = 60;
static volatile int   g_boost = 150;
static volatile int   g_range = 70;
static volatile int   g_eax_mode = 1;
static volatile int   g_gain  = 100;
static volatile int   g_pitch = 0;
static volatile int   g_robot = 0;
static volatile int   g_voice_mute = 0;
static volatile float g_peak  = 0.0f;

void DiscordEcho_SetLevel(int v)  { g_level = v < 0 ? 0 : (v > 100 ? 100 : v); }
void DiscordEcho_SetEchoBoost(int v) { g_boost = v < 100 ? 100 : (v > 400 ? 400 : v); }
void DiscordEcho_SetRange(int v)  { g_range = v < 0 ? 0 : (v > 100 ? 100 : v); }
void DiscordEcho_SetEAXMode(int on) { g_eax_mode = on ? 1 : 0; }
void DiscordEcho_SetGain(int v)   { g_gain = v < 100 ? 100 : (v > 800 ? 800 : v); }
void DiscordEcho_SetPitch(int v)  { g_pitch = v < -12 ? -12 : (v > 12 ? 12 : v); }
void DiscordEcho_SetRobot(int on) { g_robot = on ? 1 : 0; }
void DiscordEcho_SetVoiceMute(int on) { g_voice_mute = on ? 1 : 0; }
float DiscordEcho_GetPeak(void)   { return g_peak; }

static float soft_limit(float y) {
    float a = y < 0 ? -y : y;
    if (a <= 0.6f) return y;
    float s = 0.6f + 0.4f * tanhf((a - 0.6f) / 0.4f);
    return y < 0 ? -s : s;
}

static float g_line[MAX_BUFS][LINE_LEN];
static size_t g_pos[MAX_BUFS];
static int g_cleared[MAX_BUFS];

#define RV_COMBS    4
#define RV_APS      2
#define RV_COMB_MAX 4096
#define RV_AP_MAX   1024
#define RV_DAMP     0.45f
#define RV_WET      1.8f

typedef struct {
    float comb[RV_COMBS][RV_COMB_MAX];
    float damp[RV_COMBS];
    unsigned cpos[RV_COMBS];
    float ap[RV_APS][RV_AP_MAX];
    unsigned apos[RV_APS];
} Reverb;

static Reverb g_rv[MAX_BUFS];
static const int kCombBase[RV_COMBS] = {1116, 1188, 1277, 1356};
static const int kApBase[RV_APS] = {556, 441};

static float rv_process(Reverb *rv, float x, float fb, const int *clen, const int *alen) {
    float in = x * 0.04f;
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

#define PS_WIN 2048
#define PS_BUF 4096

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

typedef struct { float *data; size_t len; } MusicSlot;
static MusicSlot g_mslot[2];
static volatile int    g_mcur = -1;
static volatile int    g_mplaying = 0;
static volatile int    g_mloop = 0;
static volatile int    g_mvol = 100;
static volatile double g_mpos = 0.0;
static volatile double g_mseek = -1.0;
static float g_mtmp[MUSIC_TMP];

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
    int eax = g_eax_mode;

    int echo_on = lvl > 0 && eax;
    int ps_on = (semis != 0) && chans == 1;
    int robot_on = g_robot && chans == 1;
    int mute = g_voice_mute && mus != NULL;
    int changed = echo_on || ps_on || robot_on || gn != 100 || mus != NULL;

    if (!changed) {
        float pk = 0.0f;
        for (size_
