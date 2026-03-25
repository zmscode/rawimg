import SwiftUI
import UniformTypeIdentifiers

struct ImportDialog: View {
	let fileURL: URL
	let fileSize: Int
	let onImport: (UInt32, UInt32, RawImgPixelFormat) -> Void
	let onCancel: () -> Void

	@State private var widthText: String = "512"
	@State private var heightText: String = "512"
	@State private var selectedFormat: RawImgPixelFormat = RawImgPixelFormat_RGB8

	@State private var errorMessage: String?

	private static let formats: [(String, RawImgPixelFormat)] = [
		("Grayscale 8-bit", RawImgPixelFormat_Grayscale8),
		("Grayscale 16-bit", RawImgPixelFormat_Grayscale16),
		("RGB 8-bit", RawImgPixelFormat_RGB8),
		("RGB 16-bit", RawImgPixelFormat_RGB16),
		("RGBA 8-bit", RawImgPixelFormat_RGBA8),
		("RGBA 16-bit", RawImgPixelFormat_RGBA16),
	]

	private var parsedWidth: UInt32? {
		UInt32(widthText)
	}

	private var parsedHeight: UInt32? {
		UInt32(heightText)
	}

	private var expectedSize: Int {
		guard let w = parsedWidth, let h = parsedHeight else { return 0 }
		return Int(rawimg_expected_size(w, h, selectedFormat))
	}

	private var sizeMatch: Bool {
		expectedSize == fileSize && expectedSize > 0
	}

	var body: some View {
		VStack(spacing: 0) {
			// Header
			VStack(spacing: 4) {
				Image(systemName: "doc.badge.gearshape")
					.font(.system(size: 36))
					.foregroundStyle(.secondary)
				Text("Import Raw Image")
					.font(.headline)
				Text(fileURL.lastPathComponent)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.top, 20)
			.padding(.bottom, 16)

			Divider()

			// Form
			Form {
				Section("Dimensions") {
					HStack {
						VStack(alignment: .leading) {
							Text("Width")
								.font(.caption)
								.foregroundStyle(.secondary)
							TextField("Width", text: $widthText)
								.textFieldStyle(.roundedBorder)
						}
						Text("x")
							.foregroundStyle(.secondary)
							.padding(.top, 14)
						VStack(alignment: .leading) {
							Text("Height")
								.font(.caption)
								.foregroundStyle(.secondary)
							TextField("Height", text: $heightText)
								.textFieldStyle(.roundedBorder)
						}
					}
				}

				Section("Pixel Format") {
					Picker("Format", selection: $selectedFormat) {
						ForEach(Self.formats, id: \.1.rawValue) { name, format in
							Text(name).tag(format)
						}
					}
					.labelsHidden()
				}

				Section("File Info") {
					LabeledContent("File size", value: formatBytes(fileSize))
					LabeledContent("Expected size", value: formatBytes(expectedSize))

					if parsedWidth != nil && parsedHeight != nil && expectedSize > 0 {
						HStack {
							Image(
								systemName: sizeMatch
									? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
							)
							.foregroundColor(sizeMatch ? .green : .orange)
							Text(
								sizeMatch
									? "Dimensions match file size"
									: "Size mismatch — image may be cropped or padded"
							)
							.font(.caption)
							.foregroundColor(sizeMatch ? .secondary : .orange)
						}
					}
				}
			}
			.formStyle(.grouped)
			.scrollDisabled(true)

			if let error = errorMessage {
				Text(error)
					.font(.caption)
					.foregroundStyle(.red)
					.padding(.horizontal)
			}

			Divider()

			// Buttons
			HStack {
				Button("Cancel") {
					onCancel()
				}
				.keyboardShortcut(.cancelAction)

				Spacer()

				Button("Import") {
					performImport()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(parsedWidth == nil || parsedHeight == nil)
			}
			.padding()
		}
		.frame(width: 380)
	}

	private func performImport() {
		guard let w = parsedWidth, let h = parsedHeight else {
			errorMessage = "Invalid dimensions"
			return
		}
		guard w > 0 && h > 0 else {
			errorMessage = "Width and height must be greater than 0"
			return
		}
		guard w <= 65536 && h <= 65536 else {
			errorMessage = "Maximum dimension is 65536"
			return
		}
		errorMessage = nil
		onImport(w, h, selectedFormat)
	}

	private func formatBytes(_ bytes: Int) -> String {
		if bytes < 1024 { return "\(bytes) B" }
		if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
		return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
	}
}
