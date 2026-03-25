import SwiftUI

@main
struct RawImgApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Export as PNG...") {
                    NotificationCenter.default.post(name: .exportPNG, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Export as Raw...") {
                    NotificationCenter.default.post(name: .exportRaw, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
    static let exportPNG = Notification.Name("exportPNG")
    static let exportRaw = Notification.Name("exportRaw")
}
