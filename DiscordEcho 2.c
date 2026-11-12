#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "fishhook.h"

#define MAX_CHANNELS 2
#define MAX_DELAY 4096

static volatile int g_level = 50;
static volatile float g_peak = 0.0f;

void DiscordEcho_SetLevel(int level) {
    if (level < 0) level = 0;
    if (level > 100) level = 100;
    g_level = level;
}

float DiscordEcho_GetPeak(void) {
    return g_peak;
}

typedef struct {
    float *buffer;
    unsigned size;
    unsigned pos;
    float feedback;
    float damping;
    float filter;
} Comb;

typedef struct {
    float *buffer;
    unsigned size;
    unsigned pos;
} Delay;

static Comb combL[4], combR[4];
static Delay earlyL[5], earlyR[5];
static float *memory;
static double sampleRate = 48000.0;
static int initialized = 0;
static AudioUnit g_unit;
static AudioStreamBasicDescription g_fmt;
static int g_have_fmt;

static OSStatus (*orig_render)(
    AudioUnit,
    AudioUnitRenderActionFlags *,
    const AudioTimeStamp *,
    UInt32,
    UInt32,
    AudioBufferList *
);

static void init_dsp(double rate) {
    if (initialized) return;

    sampleRate = rate > 8000 ? rate : 48000;

    const int combMs[4] = {29, 37, 41, 43};
    const int earlyMs[5] = {7, 13, 19, 29, 43};

    size_t total = 0;

    for (int i = 0; i < 4; i++)
        total += (size_t)(sampleRate * combMs[i] / 1000.0) + 8;

    for (int i = 0; i < 5; i++)
        total += (size_t)(sampleRate * earlyMs[i] / 1000.0) * 2 + 16;

    memory = (float *)calloc(total, sizeof(float));
    if (!memory) return;

    float *ptr = memory;

    for (int i = 0; i < 4; i++) {
        unsigned n = (unsigned)(sampleRate * combMs[i] / 1000.0);
        combL[i].buffer = ptr;
        combL[i].size = n;
        ptr += n;

        combR[i].buffer = ptr;
        combR[i].size = n + 3;
        ptr += n + 3;
    }

    for (int i = 0; i < 5; i++) {
        unsigned n = (unsigned)(sampleRate * earlyMs[i] / 1000.0);

        earlyL[i].buffer = ptr;
        earlyL[i].size = n;
        ptr += n;

        earlyR[i].buffer = ptr;
        earlyR[i].size = n + 2;
        ptr += n + 2;
    }

    initialized = 1;
}

static float comb_process(Comb *c, float input) {
    if (!c->buffer || !c->size) return 0;

    float out = c->buffer[c->pos];

    c->filter = out * (1.0f - c->damping)
              + c->filter * c->damping;

    c->buffer[c->pos] =
        input + c->filter * c->feedback;

    c->pos++;
    if (c->pos >= c->size) c->pos = 0;

    return out;
}

static float early_process(Delay *d, float input) {
    if (!d->buffer || !d->size) return 0;

    float out = d->buffer[d->pos];
    d->buffer[d->pos] = input;

    d->pos++;
    if (d->pos >= d->size) d->pos = 0;

    return out;
}

static void process_sample(
    float *left,
    float *right,
    int channels
) {
    float xL = *left;
    float xR = channels > 1 ? *right : xL;

    float level = (float)g_level / 100.0f;

    float room = 0.65f + level * 0.25f;
    float wet = level * 0.30f;

    float earlyGain[5] = {
        0.20f, 0.16f, 0.12f, 0.09f, 0.06f
    };

    float reflectionL = 0;
    float reflectionR = 0;

    for (int i = 0; i < 5; i++) {
        reflectionL += early_process(&earlyL[i], xL)
                     * earlyGain[i];

        reflectionR += early_process(&earlyR[i], xR)
                     * earlyGain[i];
    }

    float inputL = xL + reflectionL * 0.35f;
    float inputR = xR + reflectionR * 0.35f;

    float revL = 0;
    float revR = 0;

    for (int i = 0; i < 4; i++) {
        combL[i].feedback = room;
        combR[i].feedback = room;

        combL[i].damping = 0.30f;
        combR[i].damping = 0.30f;

        revL += comb_process(&combL[i], inputL);
        revR += comb_process(&combR[i], inputR);
    }

    revL *= 0.25f;
    revR *= 0.25f;

    float outL = xL * (1.0f - wet * 0.25f)
               + (revL + reflectionL) * wet;

    float outR = xR * (1.0f - wet * 0.25f)
               + (revR + reflectionR) * wet;

    if (outL > 1) outL = 1;
    if (outL < -1) outL = -1;
    if (outR > 1) outR = 1;
    if (outR < -1) outR = -1;

    *left = outL;
    if (channels > 1) *right = outR;

    float peak = fmaxf(fabsf(outL), fabsf(outR));
    if (peak > g_peak) g_peak = peak;
}

static OSStatus my_render(
    AudioUnit unit,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *ts,
    UInt32 bus,
    UInt32 frames,
    AudioBufferList *io
) {
    OSStatus status = orig_render(
        unit, flags, ts, bus, frames, io
    );

    if (status != noErr || !io) return status;

    if (unit != g_unit || !g_have_fmt) {
        UInt32 size = sizeof(g_fmt);

        if (AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            bus,
            &g_fmt,
            &size
        ) == noErr) {
            g_unit = unit;
            g_have_fmt = 1;
            init_dsp(g_fmt.mSampleRate);
        } else {
            return status;
        }
    }

    if (!initialized || g_fmt.mBitsPerChannel != 32 ||
        !(g_fmt.mFormatFlags & kAudioFormatFlagIsFloat))
        return status;

    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        AudioBuffer *ab = &io->mBuffers[b];

        if (!ab->mData) continue;

        int channels = (int)ab->mNumberChannels;
        if (channels < 1) channels = 1;
        if (channels > 2) channels = 2;

        float *samples = (float *)ab->mData;
        size_t count = ab->mDataByteSize / sizeof(float);

        for (size_t i = 0; i + channels <= count; i += channels) {
            float L = samples[i];
            float R = channels > 1 ? samples[i + 1] : L;

            process_sample(&L, &R, channels);

            samples[i] = L;
            if (channels > 1) samples[i + 1] = R;
        }
    }

    return status;
}

__attribute__((constructor))
static void init(void) {
    struct rebinding r = {
        "AudioUnitRender",
        (void *)my_render,
        (void **)&orig_render
    };

    rebind_symbols(&r, 1);
}
