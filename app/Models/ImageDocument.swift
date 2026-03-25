import AppKit
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
        panel.allowedContentTypes = [.data, .rawImage, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Select an image file"
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ext = url.pathExtension.lowercased()

        // Try camera raw first (by extension or by probing with LibRaw)
        if Self.cameraRawExtensions.contains(ext) || rawimg_is_camera_raw(url.path) == 1 {
            loadCameraRaw(url: url)
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

    // MARK: - Private

    private func loadCameraRaw(url: URL) {
        if let handle = imageHandle {
            rawimg_destroy(handle)
            imageHandle = nil
        }

        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let handle = rawimg_load_camera_raw(url.path, &errorPtr) else {
            let msg: String
            if let errorPtr = errorPtr {
                msg = String(cString: errorPtr)
                rawimg_free_string(errorPtr)
            } else {
                msg = "Failed to decode camera raw file."
            }
            showError(message: msg)
            return
        }

        applyHandle(handle, fileName: url.lastPathComponent)
    }

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
                  intent: .defaultIntent
              ) else { return }

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
