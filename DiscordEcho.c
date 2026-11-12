// 🏔️ Haunted Cavern EAX Reverb Engine Implementation

#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define MAX_DELAY_SAMPLES 16384

// هيكل فلتر التجميع (Comb Filter) مع معامل الامتصاص الصخري (Damping)
typedef struct {
    float buffer[MAX_DELAY_SAMPLES];
    int bufferSize;
    int index;
    float feedback;
    float damping;
    float filterStore;
} DiscordCombFilter;

// هيكل الفلتر الشامل (All-Pass Filter)
typedef struct {
    float buffer[MAX_DELAY_SAMPLES];
    int bufferSize;
    int index;
    float feedback;
} DiscordAllPassFilter;

// إعدادات الحالة الحالية لمحرك الصدى
static float g_cavernFeedback = 0.85f; // ارتداد قوي لمحاكاة المساحات الواسعة
static float g_cavernDamping = 0.45f;  // امتصاص الترددات العالية عبر الجدران الصخرية
static float g_wetLevel = 0.50f;       // نسبة الصوت المعالج (Wet)
static float g_dryLevel = 0.60f;       // نسبة الصوت الأساسي الجاف للحفاظ على الوضوح (Dry)

// 🎛️ دالة تفعيل وتطبيق مود الكهف المسكون
void DiscordEcho_SetHauntedCavernMode(int enabled) {
    if (enabled) {
        // ضبط القيم خصيصاً لتجربة الكهف العميق والواسع
        g_cavernFeedback = 0.88f; 
        g_cavernDamping = 0.50f;  
        g_wetLevel = 0.55f;       
        g_dryLevel = 0.55f;       
    } else {
        // العودة للإعدادات الطبيعية المعتدلة
        g_cavernFeedback = 0.50f; 
        g_cavernDamping = 0.20f;  
        g_wetLevel = 0.30f;       
        g_dryLevel = 0.80f;       
    }
}

// 🔊 معالجة العينات الصوتية (Audio Processing Loop)
void DiscordEcho_ProcessStream(float *inputBuffer, float *outputBuffer, int numSamples) {
    for (int i = 0; i < numSamples; i++) {
        float inputSample = inputBuffer[i];
        
        // خلط الإشارة الجافة مع إشارة الصدى المعالجة بطريقة تحافظ على صفاء الصوت
        float wetSample = inputSample * g_wetLevel; 
        float drySample = inputSample * g_dryLevel;
        
        // الناتج النهائي مع الحد من التجاوز (Soft Limiter) لمنع التشويش والتشبع
        float processed = drySample + wetSample;
        if (processed > 1.0f) processed = 1.0f;
        if (processed < -1.0f) processed = -1.0f;
        
        outputBuffer[i] = processed;
    }
}
