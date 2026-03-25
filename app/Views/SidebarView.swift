import SwiftUI

struct SidebarView: View {
    @ObservedObject var document: ImageDocument

    var body: some View {
        List {
            if document.hasImage {
                Section("Image Info") {
                    LabeledContent("Width", value: "\(document.imageWidth)px")
                    LabeledContent("Height", value: "\(document.imageHeight)px")
                    LabeledContent("Channels", value: "\(document.imageChannels)")
                    LabeledContent("Depth", value: "\(document.imageDepth * 8)-bit")
                    LabeledContent("Format", value: formatName(document.imageFormat))
                }

                Section("Adjustments") {
                    VStack(alignment: .leading) {
                        Text("Brightness")
                        Slider(value: $document.brightness, in: -100...100)
                    }

                    VStack(alignment: .leading) {
                        Text("Contrast")
                        Slider(value: $document.contrast, in: 0.0...3.0)
                    }

                    VStack(alignment: .leading) {
                        Text("Gamma")
                        Slider(value: $document.gamma, in: 0.1...5.0)
                    }
                }
            } else {
                Text("No image loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private func formatName(_ format: RawImgPixelFormat) -> String {
        switch format {
        case RawImgPixelFormat_Grayscale8:  return "Grayscale 8-bit"
        case RawImgPixelFormat_Grayscale16: return "Grayscale 16-bit"
        case RawImgPixelFormat_RGB8:        return "RGB 8-bit"
        case RawImgPixelFormat_RGB16:       return "RGB 16-bit"
        case RawImgPixelFormat_RGBA8:       return "RGBA 8-bit"
        case RawImgPixelFormat_RGBA16:      return "RGBA 16-bit"
        default:                            return "Unknown"
        }
    }
}
