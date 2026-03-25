import SwiftUI

struct ContentView: View {
    @StateObject private var document = ImageDocument()

    var body: some View {
        NavigationSplitView {
            SidebarView(document: document)
                .frame(minWidth: 220)
        } detail: {
            CanvasView(document: document)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    document.openFile()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                if document.hasImage {
                    Button {
                        document.exportFile()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            document.openFile()
        }
    }
}
