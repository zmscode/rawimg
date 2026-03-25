import SwiftUI

struct CanvasView: View {
    @ObservedObject var document: ImageDocument

    var body: some View {
        Group {
            if let image = document.displayImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Open a raw image file to get started")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("File > Open or ⌘O")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
