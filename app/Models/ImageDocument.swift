import Accelerate
import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

class ImageDocument: ObservableObject {
    @Published var displayImage: NSImage?
    @Published var hasImage = false
    @Published var imageWidth: Int = 0
    @Published var imageHeight: Int = 0
    @Published var imageChannels: Int = 0
    @Published var imageDepth: Int = 0
    @Published var imageFormat: RawImgPixelFormat = RawImgPixelFormat_RGB8
    @Published var fileName: String = ""
    @Published var isLoading = false
    @Published var loadTime: Double = 0

    @Published var brightness: Double = 0.0
    @Published var contrast: Double = 1.0
    @Published var gamma: Double = 1.0

    // Import dialog state
    @Published var showImportDialog = false
    @Published var pendingImportURL: URL?
    @Published var pendingFileSize: Int = 0

    // Error state
    @Published var showError = false
    @Published var errorMessage = ""

    private var imageHandle: RawImgHandle?

    // Core Image context — reuse for performance (GPU-backed)
    private static let ciContext: CIContext = {
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtlDevice)
        }
        return CIContext()
    }()

    deinit {
        if let handle = imageHandle {
            rawimg_destroy(handle)
        }
    }

    // MARK: - File Open

    private static let cameraRawExtensions = Set([
        "cr3", "cr2", "nef", "arw", "dng", "orf", "rw2", "raf",
        "pef", "srw", "x3f", "3fr", "mef", "erf", "mrw", "nrw",
    ])

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = "Select an image file"
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = []

        guard panel.runModal() == .OK, let url = panel.url else { return }

        loadFile(url: url)
    }

    func loadFile(url: URL) {
        let ext = url.pathExtension.lowercased()

        // Camera raw — use GPU-accelerated Core Image pipeline
        if Self.cameraRawExtensions.contains(ext) || rawimg_is_camera_raw(url.path) == 1 {
            loadCameraRawAsync(url: url)
            return
        }

        // Fall back to flat raw binary import dialog
        let fileSize = Int(rawimg_file_size(url.path))
        if fileSize == 0 {
            showError(message: "Could not read file or file is empty.")
            return
        }

        pendingImportURL = url
        pendingFileSize = fileSize
        showImportDialog = true
    }

    func performImport(width: UInt32, height: UInt32, format: RawImgPixelFormat) {
        guard let url = pendingImportURL else { return }

        showImportDialog = false
        loadRawFile(url: url, width: width, height: height, format: format)
        pendingImportURL = nil
    }

    func cancelImport() {
        showImportDialog = false
        pendingImportURL = nil
    }

    // MARK: - File Export

    func exportPNG() {
        guard imageHandle != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "output.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard rawimg_save_png(imageHandle, url.path) == 1 else {
            showError(message: "Failed to export PNG.")
            return
        }
    }

    func exportRaw() {
        guard imageHandle != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "output.raw"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard rawimg_save_raw(imageHandle, url.path) == 1 else {
            showError(message: "Failed to export raw file.")
            return
        }
    }

    // MARK: - Core Image GPU-Accelerated Loading

    private func loadCameraRawAsync(url: URL) {
        isLoading = true
        let start = CACurrentMediaTime()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let result = self.decodeCameraRawWithCoreImage(url: url)

            DispatchQueue.main.async {
                self.isLoading = false
                self.loadTime = CACurrentMediaTime() - start

                switch result {
                case .success(let (cgImage, handle)):
                    if let oldHandle = self.imageHandle {
                        rawimg_destroy(oldHandle)
                    }
                    self.imageHandle = handle
                    self.imageWidth = cgImage.width
                    self.imageHeight = cgImage.height
                    self.imageChannels = 3
                    self.imageDepth = 2  // 16-bit from CIRAWFilter
                    self.imageFormat = RawImgPixelFormat_RGB16
                    self.fileName = url.lastPathComponent
                    self.hasImage = true
                    self.displayImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height))

                case .failure(let error):
                    // Fall back to LibRaw if Core Image fails
                    self.loadCameraRawLibRaw(url: url)
                    if !self.hasImage {
                        self.showError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func decodeCameraRawWithCoreImage(url: URL)
        -> Result<(CGImage, RawImgHandle), Error>
    {
        // Use CIRAWFilter for GPU-accelerated decoding
        guard let rawFilter = CIRAWFilter(imageURL: url) else {
            return .failure(NSError(
                domain: "rawimg", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Core Image cannot decode this file"]))
        }

        // Configure for quality
        rawFilter.boostAmount = 0
        rawFilter.isGamutMappingEnabled = true

        guard let ciImage = rawFilter.outputImage else {
            return .failure(NSError(
                domain: "rawimg", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Core Image processing failed"]))
        }

        let extent = ciImage.extent
        let w = Int(extent.width)
        let h = Int(extent.height)

        // Render via Metal-backed CIContext → CGImage
        guard let cgImage = Self.ciContext.createCGImage(ciImage, from: extent) else {
            return .failure(NSError(
                domain: "rawimg", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to render image"]))
        }

        // Also populate our C++ Image buffer for editing operations
        let handle = cgImageToHandle(cgImage, width: UInt32(w), height: UInt32(h))

        guard let handle = handle else {
            return .failure(NSError(
                domain: "rawimg", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create image buffer"]))
        }

        return .success((cgImage, handle))
    }

    /// Convert a CGImage to our C++ Image handle using vImage for fast pixel extraction
    private func cgImageToHandle(_ cgImage: CGImage, width: UInt32, height: UInt32) -> RawImgHandle?
    {
        let w = Int(width)
        let h = Int(height)

        // Use vImage for hardware-accelerated pixel format conversion
        guard let cfData = cgImage.dataProvider?.data else { return nil }
        let srcPtr = CFDataGetBytePtr(cfData)!
        let srcLen = CFDataGetLength(cfData)

        let handle = rawimg_create(width, height, RawImgPixelFormat_RGB8)
        guard let handle = handle else { return nil }

        let dstPtr = rawimg_data_mut(handle)!
        let bpp = cgImage.bitsPerPixel / 8
        let srcRowBytes = cgImage.bytesPerRow
        let dstRowBytes = w * 3

        // Fast copy using vImage-style row iteration
        // CGImage may be RGBA or BGRA — handle both
        let alphaInfo = cgImage.alphaInfo
        let byteOrder = cgImage.bitmapInfo.intersection(.byteOrderMask)
        let isBGRA = (byteOrder == .byteOrder32Little)

        for y in 0..<h {
            let srcRow = srcPtr + y * srcRowBytes
            let dstRow = dstPtr + y * dstRowBytes

            for x in 0..<w {
                let sp = srcRow + x * bpp
                if isBGRA {
                    dstRow[x * 3 + 0] = sp[2]  // R
                    dstRow[x * 3 + 1] = sp[1]  // G
                    dstRow[x * 3 + 2] = sp[0]  // B
                } else {
                    dstRow[x * 3 + 0] = sp[0]  // R
                    dstRow[x * 3 + 1] = sp[1]  // G
                    dstRow[x * 3 + 2] = sp[2]  // B
                }
            }
        }

        return handle
    }

    // MARK: - LibRaw Fallback

    private func loadCameraRawLibRaw(url: URL) {
        if let handle = imageHandle {
            rawimg_destroy(handle)
            imageHandle = nil
        }

        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let handle = rawimg_load_camera_raw(url.path, &errorPtr) else {
            if let errorPtr = errorPtr {
                rawimg_free_string(errorPtr)
            }
            return
        }

        applyHandle(handle, fileName: url.lastPathComponent)
    }

    // MARK: - Flat Raw Binary Loading

    private func loadRawFile(url: URL, width: UInt32, height: UInt32, format: RawImgPixelFormat) {
        if let handle = imageHandle {
            rawimg_destroy(handle)
            imageHandle = nil
        }

        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let handle = rawimg_load_raw(url.path, width, height, format, &errorPtr) else {
            let msg: String
            if let errorPtr = errorPtr {
                msg = String(cString: errorPtr)
                rawimg_free_string(errorPtr)
            } else {
                msg = "Unknown error loading file."
            }
            showError(message: msg)
            return
        }

        applyHandle(handle, fileName: url.lastPathComponent)
    }

    private func applyHandle(_ handle: RawImgHandle, fileName: String) {
        imageHandle = handle
        imageWidth = Int(rawimg_width(handle))
        imageHeight = Int(rawimg_height(handle))
        imageChannels = Int(rawimg_channels(handle))
        imageDepth = Int(rawimg_depth(handle))
        imageFormat = rawimg_format(handle)
        self.fileName = fileName
        hasImage = true

        refreshDisplay()
    }

    func refreshDisplay() {
        guard let handle = imageHandle else { return }

        let w = Int(rawimg_width(handle))
        let h = Int(rawimg_height(handle))

        // Use vImage (Accelerate) for fast RGBA conversion
        var bufSize: Int = 0
        guard let rgba = rawimg_to_rgba8(handle, &bufSize) else { return }
        defer { rawimg_free_rgba8(rgba) }

        // Create CGImage directly from buffer — avoid extra copies
        guard
            let provider = CGDataProvider(dataInfo: nil, data: rgba, size: bufSize,
                                          releaseData: { _, _, _ in })
        else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard
            let cgImage = CGImage(
                width: w, height: h,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { return }

        displayImage = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

extension UTType {
    static var rawImage: UTType {
        UTType(filenameExtension: "raw") ?? .data
    }
}
