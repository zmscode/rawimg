#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/// Opaque handle to a rawimg::Image
typedef void* RawImgHandle;

/// Pixel format constants matching rawimg::PixelFormat
typedef enum {
    RawImgPixelFormat_Grayscale8 = 0,
    RawImgPixelFormat_Grayscale16,
    RawImgPixelFormat_RGB8,
    RawImgPixelFormat_RGB16,
    RawImgPixelFormat_RGBA8,
    RawImgPixelFormat_RGBA16,
} RawImgPixelFormat;

/// Create a new blank image. Caller must call rawimg_destroy() when done.
RawImgHandle rawimg_create(uint32_t width, uint32_t height, RawImgPixelFormat format);

/// Destroy an image and free its memory.
void rawimg_destroy(RawImgHandle handle);

/// Load raw binary pixel data from a file.
/// Returns NULL on failure.
RawImgHandle rawimg_load_raw(const char* path, uint32_t width, uint32_t height,
                             RawImgPixelFormat format);

/// Get image properties.
uint32_t rawimg_width(RawImgHandle handle);
uint32_t rawimg_height(RawImgHandle handle);
RawImgPixelFormat rawimg_format(RawImgHandle handle);
int rawimg_channels(RawImgHandle handle);

/// Access the raw pixel buffer. Returns NULL if handle is invalid.
const uint8_t* rawimg_data(RawImgHandle handle);
size_t rawimg_data_size(RawImgHandle handle);

#ifdef __cplusplus
}
#endif
