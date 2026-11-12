#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define MAX_DELAY_SAMPLES 48000 // مخزن مؤقت للصدى (ثانية كاملة)

// 🎛️ متغيرات التحكم في الحالة الصوتية
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

// مخزن الذاكرة المؤقت للصدى
static float g_delayBuffer[MAX_DELAY_SAMPLES];
static int   g_delayIndex = 0;

// 🎵 متغيرات تشغيل الموسيقى
static float *g_musicBuffer = NULL;
static size_t g_musicCount = 0;
static size_t g_musicPosition = 0;
static int   g_musicPlaying = 0;
static int   g_musicLoop = 0;
static int   g_musicVolume = 100;

// دوال الضبط والتحكم
void DiscordEcho_SetLevel(int v) { g_level = v; }
void DiscordEcho_SetEchoBoost(int v) { g_boost = v; }
void DiscordEcho_SetRange(int v) { g_range = v; }
void DiscordEcho_SetWhisperFreq(int v) { g_whisperFreq = v; }
void DiscordEcho_SetEAXMode(int on) { g_eaxMode = on; }
void DiscordEcho_SetGain(int v) { g_gain = v; }
void DiscordEcho_SetPitch(int v) { g_pitch = v; }
void DiscordEcho_SetRobot(int on) { g_robot = on; }
void DiscordEcho_SetVoiceMute(int on) { g_voiceMute = on; }

float DiscordEcho_GetPeak(void) { return g_peakLevel; }

int DiscordEcho_MusicLoad(float *samples, size_t count) {
    if (g_musicBuffer) { free(g_musicBuffer); g_musicBuffer = NULL; }
    g_musicBuffer = samples;
    g_musicCount = count;
    g_musicPosition = 0;
    return 1;
}

void DiscordEcho_MusicPlay(int play) { g_musicPlaying = play; }
void DiscordEcho_MusicStop(void) { g_musicPlaying = 0; g_musicPosition = 0; }
void DiscordEcho_MusicSeek(float frac) {
    if (g_musicCount > 0) {
        if (frac < 0.0f) frac = 0.0f;
        if (frac > 1.0f) frac = 1.0f;
        g_musicPosition = (size_t)(frac * (float)g_musicCount);
    }
}
void DiscordEcho_MusicSetVolume(int pct) { g_musicVolume = pct; }
void DiscordEcho_MusicSetLoop(int on) { g_musicLoop = on; }
int DiscordEcho_MusicIsPlaying(void) { return g_musicPlaying && g_musicBuffer != NULL; }
float DiscordEcho_MusicProgress(void) {
    if (g_musicCount == 0) return 0.0f;
    return (float)g_musicPosition / (float)g_musicCount;
}
float DiscordEcho_MusicDuration(void) {
    if (g_musicCount == 0) return 0.0f;
    return (float)g_musicCount / 48000.0f;
}

// 🔊 معالجة تدفق الصوت والصدى الحقيقي
void DiscordEcho_ProcessStream(float *inputBuffer, float *outputBuffer, int numSamples) {
    float maxVal = 0.0f;
    
    // حساب مسافة التأخير بناءً على إعدادات المدى (Range) والصدى (Level)
    int delaySamples = (int)((float)g_range / 100.0f * 12000.0f) + 1200;
    if (delaySamples >= MAX_DELAY_SAMPLES) delaySamples = MAX_DELAY_SAMPLES - 1;
    
    float feedbackGain = (float)g_level / 150.0f;
    float boostMultiplier = (float)g_boost / 100.0f;

    for (int i = 0; i < numSamples; i++) {
        float sample = g_voiceMute ? 0.0f : inputBuffer[i];
        
        // تطبيق صدى الكهف (EAX Delay & Feedback)
        if (g_eaxMode && g_level > 0) {
            int readIdx = (g_delayIndex - delaySamples + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
            float delayedSample = g_delayBuffer[readIdx];
            
            float wetSample = sample + (delayedSample * feedbackGain);
            g_delayBuffer[g_delayIndex] = wetSample;
            
            sample = (sample * 0.6f) + (wetSample * 0.4f * boostMultiplier);
        }
        
        g_delayIndex = (g_delayIndex + 1) % MAX_DELAY_SAMPLES;

        // تأثير الروبوت البسيط (Modulation)
        if (g_robot) {
            float mod = (i % 100 < 50) ? 1.0f : 0.5f;
            sample *= mod;
        }

        // دمج الخلفية الموسيقية
        if (g_musicPlaying && g_musicBuffer && g_musicPosition < g_musicCount) {
            float musicSample = g_musicBuffer[g_musicPosition++] * ((float)g_musicVolume / 100.0f);
            sample += musicSample;
            if (g_musicPosition >= g_musicCount) {
                if (g_musicLoop) g_musicPosition = 0;
                else g_musicPlaying = 0;
            }
        }

        // تطبيق مضخم الصوت (Gain)
        sample *= ((float)g_gain / 100.0f);

        float absVal = fabsf(sample);
        if (absVal > maxVal) maxVal = absVal;

        // الحد من التجاوز لمنع التشويش
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;

        outputBuffer[i] = sample;
    }
    g_peakLevel = maxVal;
}
