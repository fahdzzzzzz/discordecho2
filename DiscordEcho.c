// 🏔️ DiscordEcho: محرك المعالجة الصوتية وتحكم EAX
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define MAX_DELAY_SAMPLES 16384

// متغيرات التحكم في الحالة الصوتية
static int   g_level = 60;
static int   g_boost = 140;
static int   g_range = 65;
static int   g_whisperFreq = 45;
static int   g_eaxMode = 1;
static int   g_gain = 100;
static int   g_pitch = 0;
static int   g_robot = 0;
static int   g_voiceMute = 0;
static float g_peakLevel = 0.0f;

// متغيرات تشغيل الموسيقى الخلفية
static float *g_musicBuffer = NULL;
static size_t g_musicCount = 0;
static size_t g_musicPosition = 0;
static int   g_musicPlaying = 0;
static int   g_musicLoop = 0;
static int   g_musicVolume = 100;

// 🎛️ دوال التحكم المطلوبة من واجهة المستخدم
void DiscordEcho_SetLevel(int v) { g_level = v; }
void DiscordEcho_SetEchoBoost(int v) { g_boost = v; }
void DiscordEcho_SetRange(int v) { g_range = v; }
void DiscordEcho_SetWhisperFreq(int v) { g_whisperFreq = v; }
void DiscordEcho_SetEAXMode(int on) { g_eaxMode = on; }
void DiscordEcho_SetGain(int v) { g_gain = v; }
void DiscordEcho_SetPitch(int v) { g_pitch = v; }
void DiscordEcho_SetRobot(int on) { g_robot = on; }
void DiscordEcho_SetVoiceMute(int on) { g_voiceMute = on; }

float DiscordEcho_GetPeak(void) {
    return g_peakLevel;
}

// 🎵 دوال إدارة تشغيل ملفات الأغاني
int DiscordEcho_MusicLoad(float *samples, size_t count) {
    if (g_musicBuffer) {
        free(g_musicBuffer);
        g_musicBuffer = NULL;
    }
    g_musicBuffer = samples;
    g_musicCount = count;
    g_musicPosition = 0;
    return 1;
}

void DiscordEcho_MusicPlay(int play) {
    g_musicPlaying = play;
}

void DiscordEcho_MusicStop(void) {
    g_musicPlaying = 0;
    g_musicPosition = 0;
}

void DiscordEcho_MusicSeek(float frac) {
    if (g_musicCount > 0) {
        if (frac < 0.0f) frac = 0.0f;
        if (frac > 1.0f) frac = 1.0f;
        g_musicPosition = (size_t)(frac * (float)g_musicCount);
    }
}

void DiscordEcho_MusicSetVolume(int pct) {
    g_musicVolume = pct;
}

void DiscordEcho_MusicSetLoop(int on) {
    g_musicLoop = on;
}

int DiscordEcho_MusicIsPlaying(void) {
    return g_musicPlaying && g_musicBuffer != NULL;
}

float DiscordEcho_MusicProgress(void) {
    if (g_musicCount == 0) return 0.0f;
    return (float)g_musicPosition / (float)g_musicCount;
}

float DiscordEcho_MusicDuration(void) {
    if (g_musicCount == 0) return 0.0f;
    // العينة بمعدل 48kHz
    return (float)g_musicCount / 48000.0f;
}

// 🔊 معالجة تدفق الصوت الأساسي
void DiscordEcho_ProcessStream(float *inputBuffer, float *outputBuffer, int numSamples) {
    float maxVal = 0.0f;
    for (int i = 0; i < numSamples; i++) {
        float sample = g_voiceMute ? 0.0f : inputBuffer[i];
        
        // دمج صوت الموسيقى إذا كانت قيد التشغيل
        if (g_musicPlaying && g_musicBuffer && g_musicPosition < g_musicCount) {
            float musicSample = g_musicBuffer[g_musicPosition++] * ((float)g_musicVolume / 100.0f);
            sample += musicSample;
            if (g_musicPosition >= g_musicCount) {
                if (g_musicLoop) {
                    g_musicPosition = 0;
                } else {
                    g_musicPlaying = 0;
                }
            }
        }

        // تطبيق مضخم الصوت العام (Gain)
        sample *= ((float)g_gain / 100.0f);

        // قياس الذروة لعرض مؤشر الصوت (VU Meter)
        float absVal = fabsf(sample);
        if (absVal > maxVal) maxVal = absVal;

        // الحد من تجاوز الإشارة لتفادي التشويش
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;

        outputBuffer[i] = sample;
    }
    g_peakLevel = maxVal;
}
