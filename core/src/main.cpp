#include "rawimg/rawimg.h"
#include "rawimg/bridge.h"

#include <cstdio>
#include <cstring>
#include <fstream>

// --- C bridge implementation ---

extern "C" {

RawImgHandle rawimg_create(uint32_t width, uint32_t height, RawImgPixelFormat format) {
    auto* img = new rawimg::Image(width, height, static_cast<rawimg::PixelFormat>(format));
    return static_cast<RawImgHandle>(img);
}

void rawimg_destroy(RawImgHandle handle) {
    delete static_cast<rawimg::Image*>(handle);
}

RawImgHandle rawimg_load_raw(const char* path, uint32_t width, uint32_t height,
                             RawImgPixelFormat format) {
    auto* img = new rawimg::Image(width, height, static_cast<rawimg::PixelFormat>(format));

    std::ifstream file(path, std::ios::binary);
    if (!file) {
        delete img;
        return nullptr;
    }

    file.read(reinterpret_cast<char*>(img->data()),
              static_cast<std::streamsize>(img->dataSize()));

    if (!file) {
        delete img;
        return nullptr;
    }

    return static_cast<RawImgHandle>(img);
}

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

const uint8_t* rawimg_data(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->data();
}

size_t rawimg_data_size(RawImgHandle handle) {
    return static_cast<rawimg::Image*>(handle)->dataSize();
}

} // extern "C"
