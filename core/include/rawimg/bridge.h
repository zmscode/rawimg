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

// --- Lifecycle ---

/// Create a new blank image. Caller must call rawimg_destroy() when done.
RawImgHandle rawimg_create(uint32_t width, uint32_t height, RawImgPixelFormat format);

/// Destroy an image and free its memory.
void rawimg_destroy(RawImgHandle handle);

// --- File I/O ---

/// Load raw binary pixel data from a file.
/// Returns NULL on failure; sets error_out if non-NULL (caller must free with rawimg_free_string).
RawImgHandle rawimg_load_raw(const char* path, uint32_t width, uint32_t height,
                             RawImgPixelFormat format, char** error_out);

/// Save image as raw binary. Returns 1 on success, 0 on failure.
int rawimg_save_raw(RawImgHandle handle, const char* path);

/// Save image as PNG. Returns 1 on success, 0 on failure.
int rawimg_save_png(RawImgHandle handle, const char* path);

/// Free a string allocated by the library (e.g. error messages).
void rawimg_free_string(char* str);

// --- Properties ---

uint32_t rawimg_width(RawImgHandle handle);
uint32_t rawimg_height(RawImgHandle handle);
RawImgPixelFormat rawimg_format(RawImgHandle handle);
int rawimg_channels(RawImgHandle handle);
int rawimg_depth(RawImgHandle handle);

// --- Pixel buffer access ---

/// Access the raw pixel buffer (read-only).
const uint8_t* rawimg_data(RawImgHandle handle);

/// Access the raw pixel buffer (mutable).
uint8_t* rawimg_data_mut(RawImgHandle handle);

size_t rawimg_data_size(RawImgHandle handle);

/// Get a pointer to an RGBA8 conversion of the image for display.
/// Caller must free the returned buffer with rawimg_free_rgba8.
/// Returns NULL on failure. Sets out_size to the buffer size.
uint8_t* rawimg_to_rgba8(RawImgHandle handle, size_t* out_size);

/// Free a buffer returned by rawimg_to_rgba8.
void rawimg_free_rgba8(uint8_t* buf);

// --- Pixel access ---

/// Get pixel at (x, y). Out-of-bounds returns zeros.
void rawimg_get_pixel(RawImgHandle handle, uint32_t x, uint32_t y,
                      uint16_t* r, uint16_t* g, uint16_t* b, uint16_t* a);

/// Set pixel at (x, y). Out-of-bounds is a no-op.
void rawimg_set_pixel(RawImgHandle handle, uint32_t x, uint32_t y,
                      uint16_t r, uint16_t g, uint16_t b, uint16_t a);

// --- Utility ---

/// Get expected file size for given dimensions and format.
size_t rawimg_expected_size(uint32_t width, uint32_t height, RawImgPixelFormat format);

/// Get the file size at the given path. Returns 0 on failure.
size_t rawimg_file_size(const char* path);

#ifdef __cplusplus
}
#endif
