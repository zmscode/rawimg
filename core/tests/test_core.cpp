#include "rawimg/rawimg.h"
#include "rawimg/bridge.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

static void test_create_and_properties() {
    rawimg::Image img(100, 50, rawimg::PixelFormat::RGB8);
    assert(img.width() == 100);
    assert(img.height() == 50);
    assert(img.channels() == 3);
    assert(img.depth() == 1);
    assert(img.dataSize() == 100 * 50 * 3);
    assert(!img.empty());
    printf("  PASS: create_and_properties\n");
}

static void test_pixel_access_rgb8() {
    rawimg::Image img(10, 10, rawimg::PixelFormat::RGB8);
    rawimg::Color c{255, 128, 64, 255};
    img.setPixel(5, 3, c);

    auto got = img.getPixel(5, 3);
    assert(got.r == 255);
    assert(got.g == 128);
    assert(got.b == 64);

    // Out of bounds returns zeros
    auto oob = img.getPixel(100, 100);
    assert(oob.r == 0 && oob.g == 0 && oob.b == 0);

    printf("  PASS: pixel_access_rgb8\n");
}

static void test_pixel_access_gray16() {
    rawimg::Image img(4, 4, rawimg::PixelFormat::Grayscale16);
    rawimg::Color c{1000, 0, 0, 0xFFFF};
    img.setPixel(2, 2, c);

    auto got = img.getPixel(2, 2);
    assert(got.r == 1000);
    assert(got.g == 1000); // grayscale replicates
    assert(got.b == 1000);

    printf("  PASS: pixel_access_gray16\n");
}

static void test_pixel_access_rgba8() {
    rawimg::Image img(4, 4, rawimg::PixelFormat::RGBA8);
    rawimg::Color c{10, 20, 30, 40};
    img.setPixel(1, 1, c);

    auto got = img.getPixel(1, 1);
    assert(got.r == 10);
    assert(got.g == 20);
    assert(got.b == 30);
    assert(got.a == 40);

    printf("  PASS: pixel_access_rgba8\n");
}

static void test_raw_roundtrip() {
    const char* path = "/tmp/rawimg_test_roundtrip.raw";
    rawimg::Image img(8, 8, rawimg::PixelFormat::RGB8);
    for (uint32_t y = 0; y < 8; ++y)
        for (uint32_t x = 0; x < 8; ++x)
            img.setPixelUnchecked(x, y, {static_cast<uint16_t>(x * 30),
                                          static_cast<uint16_t>(y * 30),
                                          100, 255});

    assert(img.saveRaw(path));

    auto loaded = rawimg::Image::loadRaw(path, 8, 8, rawimg::PixelFormat::RGB8);
    assert(loaded.width() == 8);
    assert(loaded.height() == 8);
    assert(loaded.dataSize() == img.dataSize());
    assert(memcmp(loaded.data(), img.data(), img.dataSize()) == 0);

    printf("  PASS: raw_roundtrip\n");
}

static void test_png_export() {
    const char* path = "/tmp/rawimg_test_export.png";
    rawimg::Image img(16, 16, rawimg::PixelFormat::RGB8);
    for (uint32_t y = 0; y < 16; ++y)
        for (uint32_t x = 0; x < 16; ++x)
            img.setPixelUnchecked(x, y, {static_cast<uint16_t>(x * 16),
                                          static_cast<uint16_t>(y * 16),
                                          128, 255});

    assert(img.savePng(path));

    // Verify PNG file was created and has reasonable size
    std::ifstream f(path, std::ios::ate | std::ios::binary);
    assert(f.good());
    auto size = f.tellg();
    assert(size > 0);

    printf("  PASS: png_export (size=%lld bytes)\n", (long long)size);
}

static void test_to_rgba8() {
    rawimg::Image img(2, 2, rawimg::PixelFormat::Grayscale8);
    img.setPixel(0, 0, {100, 0, 0, 255});
    img.setPixel(1, 0, {200, 0, 0, 255});

    auto rgba = img.toRGBA8();
    assert(rgba.size() == 2 * 2 * 4);
    // Pixel (0,0) should be R=100, G=100, B=100, A=255 (grayscale replicated)
    assert(rgba[0] == 100);
    assert(rgba[1] == 100);
    assert(rgba[2] == 100);
    assert(rgba[3] == 255);

    printf("  PASS: to_rgba8\n");
}

static void test_bridge_api() {
    RawImgHandle h = rawimg_create(32, 24, RawImgPixelFormat_RGBA8);
    assert(h != nullptr);
    assert(rawimg_width(h) == 32);
    assert(rawimg_height(h) == 24);
    assert(rawimg_channels(h) == 4);
    assert(rawimg_depth(h) == 1);
    assert(rawimg_data_size(h) == 32 * 24 * 4);
    assert(rawimg_data(h) != nullptr);

    rawimg_set_pixel(h, 0, 0, 255, 128, 64, 200);
    uint16_t r, g, b, a;
    rawimg_get_pixel(h, 0, 0, &r, &g, &b, &a);
    assert(r == 255);
    assert(g == 128);
    assert(b == 64);
    assert(a == 200);

    size_t rgba_size = 0;
    uint8_t* rgba = rawimg_to_rgba8(h, &rgba_size);
    assert(rgba != nullptr);
    assert(rgba_size == 32 * 24 * 4);
    rawimg_free_rgba8(rgba);

    assert(rawimg_expected_size(100, 100, RawImgPixelFormat_RGB8) == 30000);

    rawimg_destroy(h);
    printf("  PASS: bridge_api\n");
}

static void test_load_error() {
    char* err = nullptr;
    RawImgHandle h = rawimg_load_raw("/nonexistent/path.raw", 10, 10,
                                      RawImgPixelFormat_RGB8, &err);
    assert(h == nullptr);
    assert(err != nullptr);
    printf("  PASS: load_error (msg: %s)\n", err);
    rawimg_free_string(err);
}

int main() {
    printf("Running rawimg core tests...\n");

    test_create_and_properties();
    test_pixel_access_rgb8();
    test_pixel_access_gray16();
    test_pixel_access_rgba8();
    test_raw_roundtrip();
    test_png_export();
    test_to_rgba8();
    test_bridge_api();
    test_load_error();

    printf("\nAll tests passed!\n");
    return 0;
}
