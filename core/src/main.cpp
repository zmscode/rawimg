#include "rawimg/rawimg.h"
#include "rawimg/bridge.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <new>

// --- C bridge implementation ---

static char* make_error(const char* msg) {
    if (!msg) return nullptr;
    size_t len = strlen(msg) + 1;
    char* out = static_cast<char*>(malloc(len));
    if (out) memcpy(out, msg, len);
    return out;
}

extern "C" {

// --- Lifecycle ---

RawImgHandle rawimg_create(uint32_t width, uint32_t height, RawImgPixelFormat format) {
    try {
        auto* img = new rawimg::Image(width, height, static_cast<rawimg::PixelFormat>(format));
        return static_cast<RawImgHandle>(img);
    } catch (...) {
        return nullptr;
    }
}

void rawimg_destroy(RawImgHandle handle) {
    delete static_cast<rawimg::Image*>(handle);
}

// --- File I/O ---

RawImgHandle rawimg_load_raw(const char* path, uint32_t width, uint32_t height,
                             RawImgPixelFormat format, char** error_out) {
    try {
        auto* img = new rawimg::Image(
            rawimg::Image::loadRaw(path, width, height, static_cast<rawimg::PixelFormat>(format)));
        return static_cast<RawImgHandle>(img);
    } catch (const std::exception& e) {
        if (error_out) *error_out = make_error(e.what());
        return nullptr;
    }
}

int rawimg_save_raw(RawImgHandle handle, const char* path) {
    if (!handle) return 0;
    return static_cast<rawimg::Image*>(handle)->saveRaw(path) ? 1 : 0;
}

int rawimg_save_png(RawImgHandle handle, const char* path) {
    if (!handle) return 0;
    return static_cast<rawimg::Image*>(handle)->savePng(path) ? 1 : 0;
}

void rawimg_free_string(char* str) {
    free(str);
}

// --- Properties ---

uint32_t rawimg_width(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->width();
}

uint32_t rawimg_height(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->height();
}

RawImgPixelFormat rawimg_format(RawImgHandle handle) {
    return static_cast<RawImgPixelFormat>(static_cast<rawimg::Image*>(handle)->format());
}

int rawimg_channels(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->channels();
}

int rawimg_depth(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->depth();
}

// --- Pixel buffer access ---

const uint8_t* rawimg_data(RawImgHandle handle) {
    if (!handle) return nullptr;
    return static_cast<rawimg::Image*>(handle)->data();
}

uint8_t* rawimg_data_mut(RawImgHandle handle) {
    if (!handle) return nullptr;
    return static_cast<rawimg::Image*>(handle)->data();
}

size_t rawimg_data_size(RawImgHandle handle) {
    if (!handle) return 0;
    return static_cast<rawimg::Image*>(handle)->dataSize();
}

uint8_t* rawimg_to_rgba8(RawImgHandle handle, size_t* out_size) {
    if (!handle) return nullptr;
    auto* img = static_cast<rawimg::Image*>(handle);

    try {
        auto rgba = img->toRGBA8();
        size_t size = rgba.size();
        uint8_t* buf = static_cast<uint8_t*>(malloc(size));
        if (!buf) return nullptr;
        memcpy(buf, rgba.data(), size);
        if (out_size) *out_size = size;
        return buf;
    } catch (...) {
        return nullptr;
    }
}

void rawimg_free_rgba8(uint8_t* buf) {
    free(buf);
}

// --- Pixel access ---

void rawimg_get_pixel(RawImgHandle handle, uint32_t x, uint32_t y,
                      uint16_t* r, uint16_t* g, uint16_t* b, uint16_t* a) {
    if (!handle) return;
    rawimg::Color c = static_cast<rawimg::Image*>(handle)->getPixel(x, y);
    if (r) *r = c.r;
    if (g) *g = c.g;
    if (b) *b = c.b;
    if (a) *a = c.a;
}

void rawimg_set_pixel(RawImgHandle handle, uint32_t x, uint32_t y,
                      uint16_t r, uint16_t g, uint16_t b, uint16_t a) {
    if (!handle) return;
    static_cast<rawimg::Image*>(handle)->setPixel(x, y, {r, g, b, a});
}

// --- Utility ---

size_t rawimg_expected_size(uint32_t width, uint32_t height, RawImgPixelFormat format) {
    auto fmt = static_cast<rawimg::PixelFormat>(format);
    return static_cast<size_t>(width) * height * rawimg::bytesPerPixel(fmt);
}

size_t rawimg_file_size(const char* path) {
    try {
        return static_cast<size_t>(std::filesystem::file_size(path));
    } catch (...) {
        return 0;
    }
}

} // extern "C"
