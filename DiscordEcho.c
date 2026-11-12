// 🎛️ DiscordEcho.c - محرك معالجة صدى Creative EAX النقي
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

#define SAMPLE_RATE 48000
#define MAX_BUFFER_SAMPLES (SAMPLE_RATE * 60 * 8)

static int g_eax_mode = 1;
static int g_level = 60;
static int g_boost = 140;
static int g_range = 65;
static int g_whisper_freq = 45;
static int g_gain = 100;
static int g_pitch = 0;
static int g_robot = 0;
static int g_voice_mute = 0;

static float g_peak_meter = 0.0f;

#define COMB_COUNT 6
static float *g_comb_buffers[COMB_COUNT];
static int g_comb_sizes[COMB_COUNT] = { 1116, 1356, 1422, 1617, 1848, 2053 };
static int g_comb_indices[COMB_COUNT] = { 0 };

#define AP_COUNT 3
static float *g_ap_buffers[AP_COUNT];
static int g_ap_sizes[AP_COUNT] = { 225, 556, 882 };
static int g_ap_indices[AP_COUNT] = { 0 };

static float *g_music_buffer = NULL;
static size_t g_music_length = 0;
static size_t g_music_position = 0;
static int g_music_playing = 0;
static int g_music_loop = 0;
static int g_music_volume = 100;

void DiscordEcho_InitBuffers(void) {
    for (int i = 0; i < COMB_COUNT; i++) {
        if (!g_comb_buffers[i]) {
            g_comb_buffers[i] = (float *)calloc(g_comb_sizes[i], sizeof(float));
        }
    }
    for (int i = 0; i < AP_COUNT; i++) {
        if (!g_ap_buffers[i]) {
            g_ap_buffers[i] = (float *)calloc(g_ap_sizes[i], sizeof(float));
        }
    }
}

void DiscordEcho_SetLevel(int v) { g_level = v; }
void DiscordEcho_SetEchoBoost(int v) { g_boost = v; }
void DiscordEcho_SetRange(int v) { g_range = v; }
void DiscordEcho_SetWhisperFreq(int v) { g_whisper_freq = v; }
void DiscordEcho_SetEAXMode(int on) { g_eax_mode = on; }
void DiscordEcho_SetGain(int v) { g_gain = v; }
void DiscordEcho_SetPitch(int v) { g_pitch = v; }
void DiscordEcho_SetRobot(int on) { g_robot = on; }
void DiscordEcho_SetVoiceMute(int on) { g_voice_mute = on; }
float DiscordEcho_GetPeak(void) { return g_peak_meter; }

int DiscordEcho_MusicLoad(float *samples, size_t count) {
    if (g_music_buffer) {
        free(g_music_buffer);
        g_music_buffer = NULL;
    }
    if (count > MAX_BUFFER_SAMPLES) count = MAX_BUFFER_SAMPLES;
    g_music_buffer = (float *)malloc(count * sizeof(float));
    if (!g_music_buffer) return 0;
    memcpy(g_music_buffer, samples, count * sizeof(float));
    g_music_length = count;
    g_music_position = 0;
    return 1;
}

void DiscordEcho_MusicPlay(int play) { g_music_playing = play; }
void DiscordEcho_MusicStop(void) { g_music_playing = 0; g_music_position = 0; }
void DiscordEcho_MusicSeek(float frac) {
    if (frac < 0.0f) frac = 0.0f;
    if (frac > 1.0f) frac = 1.0f;
    g_music_position = (size_t)(frac * (float)g_music_length);
}
void DiscordEcho_MusicSetVolume(int pct) { g_music_volume = pct; }
void DiscordEcho_MusicSetLoop(int on) { g_music_loop = on; }
int DiscordEcho_MusicIsPlaying(void) { return g_music_playing && g_music_buffer && (g_music_position < g_music_length); }
float DiscordEcho_MusicProgress(void) {
    if (g_music_length == 0) return 0.0f;
    return (float)g_music_position / (float)g_music_length;
}
float DiscordEcho_MusicDuration(void) {
    return (float)g_music_length / (float)SAMPLE_RATE;
}

// معالجة الصوت بالأنواع القياسية لضمان نجاح البناء وعدم كتم الصوت عند الدرجة 100
void DiscordEcho_ProcessAudio(float *buffer, uint32_t frameCount, uint32_t channels) {
    DiscordEcho_InitBuffers();
    
    float max_val = 0.0f;
    float gain_mult = (float)g_gain / 100.0f;
    float music_vol = (float)g_music_volume / 100.0f;
    float eax_mix = (float)g_level / 100.0f;
    float feedback = 0.65f * ((float)g_boost / 200.0f);
    float room_scale = (float)g_range / 100.0f;

    uint32_t i, c;
    for (i = 0; i < frameCount; i++) {
        float sample = buffer[i * channels];

        if (g_voice_mute) {
            sample = 0.0f;
        } else {
            sample *= gain_mult;
        }

        if (g_music_playing && g_music_buffer && g_music_position < g_music_length) {
            float m_sample = g_music_buffer[g_music_position++] * music_vol;
            sample += m_sample;
            if (g_music_position >= g_music_length) {
                if (g_music_loop) g_music_position = 0;
                else g_music_playing = 0;
            }
        }

        float clean_signal = sample;

        if (g_eax_mode && eax_mix > 0.0f) {
            float reverb_out = 0.0f;
            
            int j;
            for (j = 0; j < COMB_COUNT; j++) {
                int adjusted_size = (int)((float)g_comb_sizes[j] * (0.5f + room_scale * 0.5f));
                int idx = g_comb_indices[j];
                if (idx >= adjusted_size) idx = 0;
                
                float delayed = g_comb_buffers[j][idx];
                float output = sample + (delayed * feedback);
                g_comb_buffers[j][idx] = output;
                g_comb_indices[j] = (idx + 1) % adjusted_size;
                reverb_out += delayed;
            }

            float ap_in = reverb_out * 0.45f;
            int ap;
            for (ap = 0; ap < AP_COUNT; ap++) {
                int idx = g_ap_indices[ap];
                float delayed = g_ap_buffers[ap][idx];
                float output = ap_in + (delayed * 0.5f);
                g_ap_buffers[ap][idx] = output;
                g_ap_indices[ap] = (idx + 1) % g_ap_sizes[ap];
                ap_in = delayed - (output * 0.5f);
            }

            sample = (clean_signal * 0.7f) + (ap_in * eax_mix * 0.5f);
        }

        if (sample > 0.98f) sample = 0.98f;
        if (sample < -0.98f) sample = -0.98f;

        float abs_s = fabsf(sample);
        if (abs_s > max_val) max_val = abs_s;

        for (c = 0; c < channels; c++) {
            buffer[i * channels + c] = sample;
        }
    }

    g_peak_meter = max_val;
}
