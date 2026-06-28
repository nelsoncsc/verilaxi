// video_frame_dpi.cpp — DPI-C helpers for video_frame_source / video_frame_sink.
// Provides pixel-level load (PNG → source) and accumulate/write (sink → PNG).
// Linked into every simulation; safe to link when the SV modules are absent
// (unused functions produce no side effects).

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_ONLY_PNG
#include "stb_image.h"
#include "stb_image_write.h"

#include <svdpi.h>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>

// ─── source state ────────────────────────────────────────────────────────────

static std::vector<uint8_t> g_src_pixels;
static int g_src_total = 0;  // total pixels across all loaded frames
static int g_src_w = 0, g_src_h = 0;

extern "C" void vf_src_load(const char* path) {
    int ch;
    uint8_t* data = stbi_load(path, &g_src_w, &g_src_h, &ch, 3);
    if (!data) {
        fprintf(stderr, "[VF_SRC] failed to load '%s': %s\n",
                path, stbi_failure_reason());
        g_src_w = g_src_h = g_src_total = 0;
        g_src_pixels.clear();
        return;
    }
    g_src_pixels.assign(data, data + g_src_w * g_src_h * 3);
    g_src_total = g_src_w * g_src_h;
    stbi_image_free(data);
    printf("[VF_SRC] loaded '%s' (%dx%d) total_pixels=%d\n",
           path, g_src_w, g_src_h, g_src_total);
}

// Append a second (or Nth) PNG to the source pixel buffer.
// After loading frame 0 with vf_src_load, call this for frames 1..N-1.
// vf_src_get_pixel(idx) naturally addresses across all loaded frames.
extern "C" void vf_src_load_append(const char* path) {
    int w, h, ch;
    uint8_t* data = stbi_load(path, &w, &h, &ch, 3);
    if (!data) {
        fprintf(stderr, "[VF_SRC] failed to load '%s': %s\n",
                path, stbi_failure_reason());
        return;
    }
    if (g_src_total == 0) {
        g_src_w = w;
        g_src_h = h;
    } else if (w != g_src_w || h != g_src_h) {
        fprintf(stderr,
                "[VF_SRC] dimension mismatch for '%s': got %dx%d, expected %dx%d; "
                "clearing source buffer\n",
                path, w, h, g_src_w, g_src_h);
        stbi_image_free(data);
        g_src_w = g_src_h = g_src_total = 0;
        g_src_pixels.clear();
        return;
    }
    g_src_pixels.insert(g_src_pixels.end(), data, data + w * h * 3);
    g_src_total += w * h;
    stbi_image_free(data);
    printf("[VF_SRC] appended '%s' (%dx%d) total_pixels=%d\n",
           path, w, h, g_src_total);
}

// Returns packed RGB24 (R in bits [23:16]) for flat pixel index.
// Wraps across all loaded frames (repeats when idx >= total pixels).
extern "C" int vf_src_get_pixel(int idx) {
    if (g_src_pixels.empty() || g_src_total == 0) return 0;
    int i = (idx % g_src_total) * 3;
    return ((int)g_src_pixels[i]   << 16) |
           ((int)g_src_pixels[i+1] <<  8) |
            (int)g_src_pixels[i+2];
}

extern "C" int vf_src_width()         { return g_src_w; }
extern "C" int vf_src_height()        { return g_src_h; }
extern "C" int vf_src_total_pixels()  { return g_src_total; }

// ─── single-stream sink (original API, used by test_vdma_timing) ─────────────

static std::vector<uint8_t> g_sink_pixels;

extern "C" void vf_sink_push(int rgb24) {
    g_sink_pixels.push_back((rgb24 >> 16) & 0xff);
    g_sink_pixels.push_back((rgb24 >>  8) & 0xff);
    g_sink_pixels.push_back( rgb24        & 0xff);
}

// Writes accumulated pixels as a PNG, then resets the buffer.
extern "C" void vf_sink_write(const char* path, int width, int height) {
    int expected = width * height * 3;
    if ((int)g_sink_pixels.size() != expected) {
        fprintf(stderr, "[VF_SINK] size mismatch: have %zu bytes, expected %d "
                "(%dx%d*3) — skipping write\n",
                g_sink_pixels.size(), expected, width, height);
        g_sink_pixels.clear();
        return;
    }
    if (!stbi_write_png(path, width, height, 3, g_sink_pixels.data(), width * 3))
        fprintf(stderr, "[VF_SINK] failed to write '%s'\n", path);
    else
        printf("[VF_SINK] wrote '%s' (%dx%d)\n", path, width, height);
    g_sink_pixels.clear();
}

// ─── multi-tap sink (used by test_multi_vdma PNG phase) ──────────────────────
// Supports up to 3 taps (indices 0..2).

#define MAX_TAPS 3
static std::vector<uint8_t> g_sink_bufs[MAX_TAPS];
static std::vector<uint8_t> g_sink_last[MAX_TAPS];  // last complete frame per tap

extern "C" void vf_sink_push_n(int tap, int rgb24) {
    if (tap < 0 || tap >= MAX_TAPS) return;
    g_sink_bufs[tap].push_back((rgb24 >> 16) & 0xff);
    g_sink_bufs[tap].push_back((rgb24 >>  8) & 0xff);
    g_sink_bufs[tap].push_back( rgb24        & 0xff);
}

// Write tap N's accumulated pixels as PNG, save a copy for diff, clear buffer.
extern "C" void vf_sink_write_n(int tap, const char* path, int width, int height) {
    if (tap < 0 || tap >= MAX_TAPS) return;
    int expected = width * height * 3;
    if ((int)g_sink_bufs[tap].size() != expected) {
        fprintf(stderr, "[VF_SINK_N] tap%d size mismatch: have %zu, expected %d — skip\n",
                tap, g_sink_bufs[tap].size(), expected);
        g_sink_bufs[tap].clear();
        return;
    }
    if (!stbi_write_png(path, width, height, 3, g_sink_bufs[tap].data(), width * 3))
        fprintf(stderr, "[VF_SINK_N] failed to write '%s'\n", path);
    else
        printf("[VF_SINK_N] tap%d wrote '%s' (%dx%d)\n", tap, path, width, height);
    g_sink_last[tap] = g_sink_bufs[tap];  // keep for diff
    g_sink_bufs[tap].clear();
}

// Compute per-channel absolute difference between the last written frames
// of tap_a and tap_b, amplify by `amplify` (clamped to 255), write as PNG.
// Both taps must have had vf_sink_write_n called before this.
extern "C" void vf_diff_write(int tap_a, int tap_b, const char* path,
                              int width, int height, int amplify) {
    if (tap_a < 0 || tap_a >= MAX_TAPS ||
        tap_b < 0 || tap_b >= MAX_TAPS) return;

    int n = width * height * 3;
    if ((int)g_sink_last[tap_a].size() != n || (int)g_sink_last[tap_b].size() != n) {
        fprintf(stderr, "[VF_DIFF] tap%d or tap%d missing frame data — skip\n",
                tap_a, tap_b);
        return;
    }

    std::vector<uint8_t> diff(n);
    for (int i = 0; i < n; i++) {
        int d = (int)g_sink_last[tap_a][i] - (int)g_sink_last[tap_b][i];
        int v = abs(d) * amplify;
        diff[i] = (uint8_t)(v > 255 ? 255 : v);
    }

    if (!stbi_write_png(path, width, height, 3, diff.data(), width * 3))
        fprintf(stderr, "[VF_DIFF] failed to write '%s'\n", path);
    else
        printf("[VF_DIFF] diff(tap%d,tap%d) wrote '%s' (%dx%d amp=%d)\n",
               tap_a, tap_b, path, width, height, amplify);
}

// ── diff metrics (programmatic, no file) ─────────────────────────────────────
// Number of pixels that differ in ANY channel between the last written frames
// of tap_a and tap_b.  0 = identical frames; >0 = motion / generation lag.
extern "C" int vf_diff_count(int tap_a, int tap_b, int width, int height) {
    if (tap_a < 0 || tap_a >= MAX_TAPS || tap_b < 0 || tap_b >= MAX_TAPS) return -1;
    int n = width * height * 3;
    if ((int)g_sink_last[tap_a].size() != n || (int)g_sink_last[tap_b].size() != n)
        return -1;
    int diff_px = 0;
    for (int p = 0; p < width * height; p++) {
        int b = p * 3;
        if (g_sink_last[tap_a][b]   != g_sink_last[tap_b][b]   ||
            g_sink_last[tap_a][b+1] != g_sink_last[tap_b][b+1] ||
            g_sink_last[tap_a][b+2] != g_sink_last[tap_b][b+2])
            diff_px++;
    }
    return diff_px;
}

// Mean per-channel absolute difference ×1000 (fixed-point, avoids real in DPI).
// e.g. returns 58000 for a mean abs diff of 58.0 LSB.
extern "C" int vf_diff_energy_x1000(int tap_a, int tap_b, int width, int height) {
    if (tap_a < 0 || tap_a >= MAX_TAPS || tap_b < 0 || tap_b >= MAX_TAPS) return -1;
    int n = width * height * 3;
    if ((int)g_sink_last[tap_a].size() != n || (int)g_sink_last[tap_b].size() != n)
        return -1;
    long long acc = 0;
    for (int i = 0; i < n; i++)
        acc += abs((int)g_sink_last[tap_a][i] - (int)g_sink_last[tap_b][i]);
    return (int)((acc * 1000) / n);
}
