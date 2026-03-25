#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
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

class Image {
public:
    Image() = default;

    Image(uint32_t width, uint32_t height, PixelFormat format)
        : width_(width), height_(height), format_(format) {
        size_t size = static_cast<size_t>(width) * height
                      * channelsFor(format) * bytesPerChannel(format);
        data_.resize(size, 0);
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
        return static_cast<size_t>(width_) * channelsFor(format_) * bytesPerChannel(format_);
    }

    bool empty() const { return data_.empty(); }

private:
    uint32_t width_ = 0;
    uint32_t height_ = 0;
    PixelFormat format_ = PixelFormat::RGB8;
    std::vector<uint8_t> data_;
};

} // namespace rawimg
