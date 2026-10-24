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
            CommandGroup(replacing: .appSettings) {
                Button("Setup & Preferences…") { model.showingKeySheet = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("People") {
                Button("Open Lobby") { model.openLobby() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Connect a Program…") { model.connectRequest = UUID() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button(model.isAway ? "I'm Back" : "Away Message…") {
                    if model.isAway { model.comeBack() } else { model.showingAwaySheet = true }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Toggle("Play Sounds", isOn: $model.soundsOn)
                Toggle("Show Timestamps", isOn: $model.showTimestamps)
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Welcome Guide") { model.showingWelcome = true }
            }
        }

        WindowGroup(id: "im", for: String.self) { $roomID in
            ChatWindowView(roomID: roomID ?? "")
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 740, height: 560)

        Window("Away Message", id: "away") {
            AwayMessageSheet()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("ShadowChat Setup", id: "setup") {
            SetupSheet()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

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
