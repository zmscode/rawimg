#include "rawimg/rawimg.h"
#include "rawimg/bridge.h"

#include <libraw/libraw.h>
#include <cstring>
#include <stdexcept>
#include <string>

namespace rawimg {

Image Image::loadCameraRaw(const std::string& path) {
    LibRaw raw;

    int ret = raw.open_file(path.c_str());
    if (ret != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("LibRaw: failed to open file: ") + libraw_strerror(ret));

    ret = raw.unpack();
    if (ret != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("LibRaw: failed to unpack: ") + libraw_strerror(ret));

    // Process with default params (daylight WB, sRGB output, 8-bit)
    raw.imgdata.params.output_bps = 16;
    raw.imgdata.params.use_camera_wb = 1;
    raw.imgdata.params.output_color = 1; // sRGB
    raw.imgdata.params.no_auto_bright = 0;
    raw.imgdata.params.half_size = 0;

    ret = raw.dcraw_process();
    if (ret != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("LibRaw: processing failed: ") + libraw_strerror(ret));

    libraw_processed_image_t* processed = raw.dcraw_make_mem_image(&ret);
    if (!processed || ret != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("LibRaw: failed to create image: ") + libraw_strerror(ret));

    uint32_t w = processed->width;
    uint32_t h = processed->height;
    int channels = processed->colors;
    int bps = processed->bits;

    // Determine output format
    PixelFormat fmt;
    if (channels == 3 && bps == 16)       fmt = PixelFormat::RGB16;
    else if (channels == 3 && bps == 8)   fmt = PixelFormat::RGB8;
    else if (channels == 1 && bps == 16)  fmt = PixelFormat::Grayscale16;
    else if (channels == 1 && bps == 8)   fmt = PixelFormat::Grayscale8;
    else                                  fmt = PixelFormat::RGB8;

    Image img(w, h, fmt);

    size_t copySize = static_cast<size_t>(w) * h * channels * (bps / 8);
    if (copySize <= img.dataSize())
        memcpy(img.data(), processed->data, copySize);

    LibRaw::dcraw_clear_mem(processed);
    raw.recycle();

    return img;
}

} // namespace rawimg

// --- Bridge function ---

extern "C" {

RawImgHandle rawimg_load_camera_raw(const char* path, char** error_out) {
    try {
        auto* img = new rawimg::Image(rawimg::Image::loadCameraRaw(path));
        return static_cast<RawImgHandle>(img);
    } catch (const std::exception& e) {
        if (error_out) {
            size_t len = strlen(e.what()) + 1;
            *error_out = static_cast<char*>(malloc(len));
            if (*error_out) memcpy(*error_out, e.what(), len);
        }
        return nullptr;
    }
}

int rawimg_is_camera_raw(const char* path) {
    LibRaw raw;
    int ret = raw.open_file(path);
    raw.recycle();
    return (ret == LIBRAW_SUCCESS) ? 1 : 0;
}

} // extern "C"
