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
                    Menu {
                        Button("Export as PNG...") {
                            document.exportPNG()
                        }
                        Button("Export as Raw...") {
                            document.exportRaw()
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            document.openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPNG)) { _ in
            document.exportPNG()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRaw)) { _ in
            document.exportRaw()
        }
        .sheet(isPresented: $document.showImportDialog) {
            if let url = document.pendingImportURL {
                ImportDialog(
                    fileURL: url,
                    fileSize: document.pendingFileSize,
                    onImport: { width, height, format in
                        document.performImport(width: width, height: height, format: format)
                    },
                    onCancel: {
                        document.cancelImport()
                    }
                )
            }
        }
        .alert("Error", isPresented: $document.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(document.errorMessage)
        }
    }
}
