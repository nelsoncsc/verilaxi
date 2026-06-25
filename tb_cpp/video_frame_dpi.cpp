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
#include <vector>
#include <string>

// ─── source state ────────────────────────────────────────────────────────────

static std::vector<uint8_t> g_src_pixels;
static int g_src_w = 0, g_src_h = 0;

extern "C" void vf_src_load(const char* path) {
    int ch;
    uint8_t* data = stbi_load(path, &g_src_w, &g_src_h, &ch, 3);
    if (!data) {
        fprintf(stderr, "[VF_SRC] failed to load '%s': %s\n",
                path, stbi_failure_reason());
        g_src_w = g_src_h = 0;
        return;
    }
    g_src_pixels.assign(data, data + g_src_w * g_src_h * 3);
    stbi_image_free(data);
    printf("[VF_SRC] loaded '%s' (%dx%d)\n", path, g_src_w, g_src_h);
}

// Returns packed RGB24 (R in bits [23:16]) for flat pixel index.
// Wraps if idx >= total pixels (repeats the image for multi-frame runs).
extern "C" int vf_src_get_pixel(int idx) {
    if (g_src_pixels.empty()) return 0;
    int total = g_src_w * g_src_h;
    int i = (idx % total) * 3;
    return ((int)g_src_pixels[i] << 16) |
           ((int)g_src_pixels[i+1] << 8) |
            (int)g_src_pixels[i+2];
}

extern "C" int vf_src_width()  { return g_src_w; }
extern "C" int vf_src_height() { return g_src_h; }

// ─── sink state ──────────────────────────────────────────────────────────────

static std::vector<uint8_t> g_sink_pixels;

extern "C" void vf_sink_push(int rgb24) {
    g_sink_pixels.push_back((rgb24 >> 16) & 0xff);
    g_sink_pixels.push_back((rgb24 >>  8) & 0xff);
    g_sink_pixels.push_back( rgb24        & 0xff);
}

// Writes accumulated pixels as a PNG, then resets the buffer.
// width/height must match exactly the number of pixels pushed since
// the last vf_sink_write (or simulation start).
extern "C" void vf_sink_write(const char* path, int width, int height) {
    int expected = width * height * 3;
    if ((int)g_sink_pixels.size() != expected) {
        fprintf(stderr, "[VF_SINK] size mismatch: have %zu bytes, expected %d "
                "(%dx%d*3) — skipping write\n",
                g_sink_pixels.size(), expected, width, height);
        g_sink_pixels.clear();
        return;
    }
    if (!stbi_write_png(path, width, height, 3, g_sink_pixels.data(), width * 3)) {
        fprintf(stderr, "[VF_SINK] failed to write '%s'\n", path);
    } else {
        printf("[VF_SINK] wrote '%s' (%dx%d)\n", path, width, height);
    }
    g_sink_pixels.clear();
}
