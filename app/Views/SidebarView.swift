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
}
