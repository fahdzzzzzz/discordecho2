#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define MAX_DELAY_SAMPLES 48000

static int   g_enableEffects = 1;
static int   g_effectsAmount = 50; // من 0 إلى 100
static int   g_presetMode = 0;     // 0: Haunted Cavern, 1: Cathedral, 2: Concert Hall
static float g_delayBuffer[MAX_DELAY_SAMPLES];
static int   g_delayIndex = 0;
static float g_peakLevel = 0.0f;

void DiscordEcho_SetEnableEffects(int enabled) { g_enableEffects = enabled; }
void DiscordEcho_SetEffectsAmount(int amount) { g_effectsAmount = amount; }
void DiscordEcho_SetPreset(int preset) { g_presetMode = preset; }

float DiscordEcho_GetPeak(void) { return g_peakLevel; }

void DiscordEcho_ProcessStream(float *inputBuffer, float *outputBuffer, int numSamples) {
    float maxVal = 0.0f;
    
    // تحديد وقت التأخير بناءً على الـ Preset (مثل الكهف المسكون أو القاعة)
    int delaySamples = 12000;
    float feedback = 0.7f;
    
    if (g_presetMode == 0) { // Haunted Cavern (صدى عميق وواسع)
        delaySamples = 16000;
        feedback = 0.82f;
    } else if (g_presetMode == 1) { // Cathedral (كاتدرائية)
        delaySamples = 22000;
        feedback = 0.88f;
    } else if (g_presetMode == 2) { // Concert Hall (قاعة حفلات)
        delaySamples = 8000;
        feedback = 0.55f;
    }

    float amountFactor = (float)g_effectsAmount / 100.0f;

    for (int i = 0; i < numSamples; i++) {
        float sample = inputBuffer[i];
        
        if (g_enableEffects && g_effectsAmount > 0) {
            int readIdx = (g_delayIndex - delaySamples + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
            float delayedSample = g_delayBuffer[readIdx];
            
            float wet = sample + (delayedSample * feedback);
            g_delayBuffer[g_delayIndex] = wet;
            
            // خلط الصوت الأساسي مع الصدى بنسبة Effects Amount
            sample = (sample * (1.0f - (0.5f * amountFactor))) + (wet * (0.5f * amountFactor));
        }
        
        g_delayIndex = (g_delayIndex + 1) % MAX_DELAY_SAMPLES;

        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;

        float absVal = fabsf(sample);
        if (absVal > maxVal) maxVal = absVal;

        outputBuffer[i] = sample;
    }
    g_peakLevel = maxVal;
}
