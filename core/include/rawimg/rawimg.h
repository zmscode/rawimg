#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace rawimg {

constexpr const char* VERSION = "0.1.0";

enum class PixelFormat {
    Grayscale8,
    Grayscale16,
    RGB8,
    RGB16,
    RGBA8,
    RGBA16,
};

inline int channelsFor(PixelFormat fmt) {
    switch (fmt) {
        case PixelFormat::Grayscale8:
        case PixelFormat::Grayscale16: return 1;
        case PixelFormat::RGB8:
        case PixelFormat::RGB16:       return 3;
        case PixelFormat::RGBA8:
        case PixelFormat::RGBA16:      return 4;
    }
}

inline int bytesPerChannel(PixelFormat fmt) {
    switch (fmt) {
        case PixelFormat::Grayscale8:
        case PixelFormat::RGB8:
        case PixelFormat::RGBA8:  return 1;
        case PixelFormat::Grayscale16:
        case PixelFormat::RGB16:
        case PixelFormat::RGBA16: return 2;
    }
}

inline int bytesPerPixel(PixelFormat fmt) {
    return channelsFor(fmt) * bytesPerChannel(fmt);
}

struct Color {
    uint16_t r = 0, g = 0, b = 0, a = 0xFFFF;
};

class Image {
public:
    Image() = default;

    Image(uint32_t width, uint32_t height, PixelFormat format)
        : width_(width), height_(height), format_(format) {
        data_.resize(static_cast<size_t>(width) * height * bytesPerPixel(format), 0);
    }

    uint32_t width() const { return width_; }
    uint32_t height() const { return height_; }
    PixelFormat format() const { return format_; }
    int channels() const { return channelsFor(format_); }
    int depth() const { return bytesPerChannel(format_); }

    uint8_t* data() { return data_.data(); }
    const uint8_t* data() const { return data_.data(); }
    size_t dataSize() const { return data_.size(); }

    size_t rowBytes() const {
        return static_cast<size_t>(width_) * bytesPerPixel(format_);
    }

    bool empty() const { return data_.empty(); }

    // --- Pixel access (Issue #3) ---

    Color getPixel(uint32_t x, uint32_t y) const {
        if (x >= width_ || y >= height_)
            return {};
        return getPixelUnchecked(x, y);
    }

    Color getPixelUnchecked(uint32_t x, uint32_t y) const {
        const uint8_t* p = pixelPtr(x, y);
        return readColor(p);
    }

    void setPixel(uint32_t x, uint32_t y, Color c) {
        if (x >= width_ || y >= height_)
            return;
        setPixelUnchecked(x, y, c);
    }

    void setPixelUnchecked(uint32_t x, uint32_t y, Color c) {
        uint8_t* p = pixelPtr(x, y);
        writeColor(p, c);
    }

    // Row pointer for scanline iteration
    uint8_t* rowPtr(uint32_t y) {
        return data_.data() + static_cast<size_t>(y) * rowBytes();
    }

    const uint8_t* rowPtr(uint32_t y) const {
        return data_.data() + static_cast<size_t>(y) * rowBytes();
    }

    // --- File I/O (Issues #1, #2) ---

    static Image loadRaw(const std::string& path, uint32_t width, uint32_t height,
                         PixelFormat format) {
        Image img(width, height, format);

        std::ifstream file(path, std::ios::binary);
        if (!file)
            throw std::runtime_error("Failed to open file: " + path);

        file.read(reinterpret_cast<char*>(img.data()),
                  static_cast<std::streamsize>(img.dataSize()));

        if (!file)
            throw std::runtime_error("Failed to read expected bytes from: " + path);

        return img;
    }

    bool saveRaw(const std::string& path) const {
        std::ofstream file(path, std::ios::binary);
        if (!file) return false;
        file.write(reinterpret_cast<const char*>(data_.data()),
                   static_cast<std::streamsize>(data_.size()));
        return file.good();
    }

    // Load camera raw files (CR3, CR2, NEF, ARW, etc.) via LibRaw
    static Image loadCameraRaw(const std::string& path);

    // PNG export — converts 16-bit to 8-bit for PNG output
    bool savePng(const std::string& path) const;

    // Convert to 8-bit RGBA for display purposes
    std::vector<uint8_t> toRGBA8() const {
        std::vector<uint8_t> out(static_cast<size_t>(width_) * height_ * 4);

        for (uint32_t y = 0; y < height_; ++y) {
            for (uint32_t x = 0; x < width_; ++x) {
                Color c = getPixelUnchecked(x, y);
                size_t idx = (static_cast<size_t>(y) * width_ + x) * 4;
                // Scale 16-bit to 8-bit
                out[idx + 0] = static_cast<uint8_t>(c.r >> 8 * (depth() - 1));
                out[idx + 1] = static_cast<uint8_t>(c.g >> 8 * (depth() - 1));
                out[idx + 2] = static_cast<uint8_t>(c.b >> 8 * (depth() - 1));
                out[idx + 3] = static_cast<uint8_t>(c.a >> 8 * (depth() - 1));
            }
        }

        return out;
    }

private:
    uint32_t width_ = 0;
    uint32_t height_ = 0;
    PixelFormat format_ = PixelFormat::RGB8;
    std::vector<uint8_t> data_;

    uint8_t* pixelPtr(uint32_t x, uint32_t y) {
        return data_.data() + (static_cast<size_t>(y) * width_ + x) * bytesPerPixel(format_);
    }

    const uint8_t* pixelPtr(uint32_t x, uint32_t y) const {
        return data_.data() + (static_cast<size_t>(y) * width_ + x) * bytesPerPixel(format_);
    }

    Color readColor(const uint8_t* p) const {
        Color c;
        int ch = channels();
        int bpc = depth();

        auto read = [&](int i) -> uint16_t {
            if (bpc == 1) return static_cast<uint16_t>(p[i]);
            // 16-bit little-endian
            return static_cast<uint16_t>(p[i * 2]) | (static_cast<uint16_t>(p[i * 2 + 1]) << 8);
        };

        if (ch >= 1) c.r = read(0);
        if (ch >= 3) { c.g = read(1); c.b = read(2); }
        else         { c.g = c.r; c.b = c.r; } // grayscale → replicate
        if (ch >= 4) c.a = read(3);
        else         c.a = (bpc == 1) ? 0xFF : 0xFFFF;

        return c;
    }

    void writeColor(uint8_t* p, Color c) const {
        int ch = channels();
        int bpc = depth();

        auto write = [&](int i, uint16_t v) {
            if (bpc == 1) { p[i] = static_cast<uint8_t>(v); return; }
            p[i * 2]     = static_cast<uint8_t>(v & 0xFF);
            p[i * 2 + 1] = static_cast<uint8_t>(v >> 8);
        };

        if (ch >= 1) write(0, c.r);
        if (ch >= 3) { write(1, c.g); write(2, c.b); }
        if (ch >= 4) write(3, c.a);
    }
};

} // namespace rawimg
