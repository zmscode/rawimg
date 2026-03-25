import AppKit
import SwiftUI

class ImageDocument: ObservableObject {
    @Published var displayImage: NSImage?
    @Published var hasImage = false
    @Published var imageWidth: Int = 0
    @Published var imageHeight: Int = 0
    @Published var imageChannels: Int = 0

    @Published var brightness: Double = 0.0
    @Published var contrast: Double = 1.0
    @Published var gamma: Double = 1.0

    private var imageHandle: RawImgHandle?

    deinit {
        if let handle = imageHandle {
            rawimg_destroy(handle)
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.message = "Select a raw image file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // TODO: prompt user for dimensions/format when loading raw files
        // For now, attempt to load as 512x512 RGB8 as a placeholder
        loadRawFile(url: url, width: 512, height: 512, format: RawImgPixelFormat_RGB8)
    }

    func exportFile() {
        guard let image = displayImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "output.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }

    private func loadRawFile(url: URL, width: UInt32, height: UInt32, format: RawImgPixelFormat) {
        if let handle = imageHandle {
            rawimg_destroy(handle)
        }

        guard let handle = rawimg_load_raw(url.path, width, height, format) else {
            return
        }

        imageHandle = handle
        imageWidth = Int(rawimg_width(handle))
        imageHeight = Int(rawimg_height(handle))
        imageChannels = Int(rawimg_channels(handle))
        hasImage = true

        refreshDisplay()
    }

    private func refreshDisplay() {
        guard let handle = imageHandle else { return }

        let w = Int(rawimg_width(handle))
        let h = Int(rawimg_height(handle))
        let channels = Int(rawimg_channels(handle))

        guard let srcData = rawimg_data(handle) else { return }
        let dataSize = rawimg_data_size(handle)

        // Convert to RGBA for display
        let rgbaSize = w * h * 4
        var rgba = [UInt8](repeating: 255, count: rgbaSize)

        for i in 0..<(w * h) {
            let srcOffset = i * channels
            let dstOffset = i * 4

            if srcOffset + channels <= dataSize {
                switch channels {
                case 1:
                    rgba[dstOffset] = srcData[srcOffset]
                    rgba[dstOffset + 1] = srcData[srcOffset]
                    rgba[dstOffset + 2] = srcData[srcOffset]
                case 3:
                    rgba[dstOffset] = srcData[srcOffset]
                    rgba[dstOffset + 1] = srcData[srcOffset + 1]
                    rgba[dstOffset + 2] = srcData[srcOffset + 2]
                case 4:
                    rgba[dstOffset] = srcData[srcOffset]
                    rgba[dstOffset + 1] = srcData[srcOffset + 1]
                    rgba[dstOffset + 2] = srcData[srcOffset + 2]
                    rgba[dstOffset + 3] = srcData[srcOffset + 3]
                default:
                    break
                }
            }
        }

        let data = Data(rgba)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: w, height: h,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: w * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return }

        displayImage = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }
}
