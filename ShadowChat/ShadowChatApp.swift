import AppKit
import SwiftUI

@main
struct ShadowChatApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("ShadowChat", id: "buddies") {
            BuddyListView()
                .background(QuitHandler())
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 330, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        WindowGroup(id: "im", for: String.self) { $roomID in
            ChatWindowView(roomID: roomID ?? "")
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 740, height: 560)

        Window("ShadowChat System", id: "connect") {
            SystemConnectView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 740, height: 560)
    }
}

private struct QuitHandler: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.stopAll()
            }
    }
}
