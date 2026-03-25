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

    // The C++ pixel buffer — populated lazily, only when editing needs it
    private var imageHandle: RawImgHandle?
    private var handleIsDirty = false

    // Retained CGImage for display (avoids re-rendering from C++ buffer)
    private var sourceCGImage: CGImage?
    private var sourceURL: URL?

    // Core Image context — reuse, GPU-backed via Metal
    private static let ciContext: CIContext = {
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtlDevice, options: [
                .cacheIntermediates: false,
            ])
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

        // Camera raw — detect by extension only (no file I/O on main thread)
        if Self.cameraRawExtensions.contains(ext) {
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
        ensureHandle()
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
        ensureHandle()
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

            // Step 1: Try Core Image (GPU-accelerated)
            var cgImage: CGImage?
            var ciDecoded = false

            if let rawFilter = CIRAWFilter(imageURL: url) {
                rawFilter.boostAmount = 0
                rawFilter.isGamutMappingEnabled = true

                if let ciImage = rawFilter.outputImage {
                    let extent = ciImage.extent
                    cgImage = Self.ciContext.createCGImage(ciImage, from: extent)
                    ciDecoded = (cgImage != nil)
                }
            }

            // Step 2: Fall back to LibRaw on CPU if Core Image failed
            var librawHandle: RawImgHandle?
            if !ciDecoded {
                var errorPtr: UnsafeMutablePointer<CChar>?
                librawHandle = rawimg_load_camera_raw(url.path, &errorPtr)
                if let errorPtr = errorPtr {
                    rawimg_free_string(errorPtr)
                }
            }

            let elapsed = CACurrentMediaTime() - start

            DispatchQueue.main.async {
                self.isLoading = false
                self.loadTime = elapsed

                if let oldHandle = self.imageHandle {
                    rawimg_destroy(oldHandle)
                    self.imageHandle = nil
                }

                if let cg = cgImage {
                    // Display directly from CGImage — no pixel copy
                    self.sourceCGImage = cg
                    self.sourceURL = url
                    self.handleIsDirty = true  // C++ buffer not yet populated
                    self.imageWidth = cg.width
                    self.imageHeight = cg.height
                    self.imageChannels = 3
                    self.imageDepth = 1
                    self.imageFormat = RawImgPixelFormat_RGB8
                    self.fileName = url.lastPathComponent
                    self.hasImage = true
                    self.displayImage = NSImage(
                        cgImage: cg,
                        size: NSSize(width: cg.width, height: cg.height))

                } else if let handle = librawHandle {
                    // LibRaw fallback — C++ buffer is already populated
                    self.sourceCGImage = nil
                    self.sourceURL = url
                    self.handleIsDirty = false
                    self.applyHandle(handle, fileName: url.lastPathComponent)

                } else {
                    self.showError(message: "Failed to decode camera raw file.")
                }
            }
        }
    }

    // MARK: - Lazy C++ Buffer Population

    /// Ensures the C++ Image handle is populated (for editing/export).
    /// Called lazily — only when an operation actually needs the pixel buffer.
    func ensureHandle() {
        guard handleIsDirty, let cg = sourceCGImage else { return }

        let w = cg.width
        let h = cg.height

        if let oldHandle = imageHandle {
            rawimg_destroy(oldHandle)
            imageHandle = nil
        }

        imageHandle = cgImageToHandle(cg)
        handleIsDirty = false
    }

    /// Convert CGImage → C++ Image handle using vImage for fast format conversion
    private func cgImageToHandle(_ cgImage: CGImage) -> RawImgHandle? {
        let w = cgImage.width
        let h = cgImage.height

        // Use vImage to convert to a known RGB888 format
        guard var srcBuffer = try? vImage_Buffer(cgImage: cgImage) else { return nil }
        defer { srcBuffer.free() }

        // Create destination buffer for RGB8 (3 bytes per pixel)
        let handle = rawimg_create(UInt32(w), UInt32(h), RawImgPixelFormat_RGB8)
        guard let handle = handle else { return nil }

        let dstPtr = rawimg_data_mut(handle)!

        // Use vImage to convert ARGB/RGBA → planar or just extract RGB
        // The source from vImage_Buffer(cgImage:) is typically ARGB8888
        let srcPtr = srcBuffer.data.assumingMemoryBound(to: UInt8.self)
        let srcRowBytes = srcBuffer.rowBytes
        let srcBpp = srcRowBytes / w  // bytes per pixel in source

        // Determine pixel layout from the CGImage
        let alphaInfo = cgImage.alphaInfo
        let byteOrder = cgImage.bitmapInfo.intersection(.byteOrderMask)

        // Figure out R,G,B offsets in the source pixel
        let rOff: Int
        let gOff: Int
        let bOff: Int

        if byteOrder == .byteOrder32Little {
            // BGRA layout
            rOff = 2; gOff = 1; bOff = 0
        } else if alphaInfo == .first || alphaInfo == .noneSkipFirst || alphaInfo == .premultipliedFirst {
            // ARGB layout
            rOff = 1; gOff = 2; bOff = 3
        } else {
            // RGBA layout (default)
            rOff = 0; gOff = 1; bOff = 2
        }

        // Bulk copy with stride — much faster than per-pixel in Swift
        for y in 0..<h {
            let srcRow = srcPtr + y * srcRowBytes
            let dstRow = dstPtr + y * w * 3

            for x in 0..<w {
                let sp = srcRow + x * srcBpp
                let dp = dstRow + x * 3
                dp[0] = sp[rOff]
                dp[1] = sp[gOff]
                dp[2] = sp[bOff]
            }
        }

        return handle
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

        sourceCGImage = nil
        handleIsDirty = false
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

        var bufSize: Int = 0
        guard let rgba = rawimg_to_rgba8(handle, &bufSize) else { return }
        defer { rawimg_free_rgba8(rgba) }

        let data = Data(bytes: rgba, count: bufSize)
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
