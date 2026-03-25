#include "rawimg/rawimg.h"
#include "stb_image_write.h"

namespace rawimg {

bool Image::savePng(const std::string& path) const {
    if (empty()) return false;

    // Convert to 8-bit RGBA for PNG output
    auto rgba = toRGBA8();
    int stride = static_cast<int>(width_) * 4;

    return stbi_write_png(path.c_str(),
                          static_cast<int>(width_),
                          static_cast<int>(height_),
                          4, rgba.data(), stride) != 0;
}

} // namespace rawimg
