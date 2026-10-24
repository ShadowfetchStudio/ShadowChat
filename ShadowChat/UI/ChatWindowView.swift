import AppKit
import SwiftUI

struct ChatWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let roomID: String
    @StateObject private var compose = ComposeController()
    @State private var pointSize: CGFloat = 12
    @State private var copiedLabel: String?

    private var room: Room? { model.room(roomID) }

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: windowTitle)
            VStack(spacing: 0) {
                menuBar
                if isStopped {
                    stoppedBanner
                }
                transcript
                formatBar
                composeBox
                toolbar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AIMTheme.client)
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIMTheme.frameBlue)
        .overlay(WindowConfigurator(title: windowTitle).frame(width: 0, height: 0))
        .frame(minWidth: 660, minHeight: 500)
        .preferredColorScheme(.light)
        .onAppear { compose.onSend = send }
        .alert("ShadowChat", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
        .sheet(isPresented: $model.showingKeySheet) {
            SetupSheet()
                .environmentObject(model)
        }
    }

    private var isStopped: Bool {
        (engine?.phase ?? room?.runState ?? .stopped) == .stopped
    }

    private var windowTitle: String {
        let name = room?.name ?? "Room"
        let who = model.screenName.isEmpty ? "Me" : model.screenName
        return "\(name) : \(who) - Instant Message"
    }

    private var menuBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ClassicMenuButton(title: "File", items: [
                    ("New Room…", "n", chooseProject),
                    ("Copy Connect Prompt", "k", { copyForPreset(model.selectedConnectPreset) }),
                    ("Export Transcript…", "e", { model.exportTranscript(roomID: roomID) }),
                    ("Commands (/help)", "", { model.runCommand(.help, roomID: roomID) }),
                    ("Who Is Here (/who)", "", { model.runCommand(.who, roomID: roomID) }),
                    ("Clear Room History", "", { model.clearRoomMessages(roomID: roomID) }),
                    ("Close", "w", { NSApp.keyWindow?.performClose(nil) })
                ])
                ClassicMenuButton(title: "Edit", items: [
                    ("Cut", "x", { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }),
                    ("Copy", "c", { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }),
                    ("Paste", "v", { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }),
                    ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
                ])
                ClassicMenuButton(title: "Insert", items: mentionItems + smileyItems)
                ClassicMenuButton(title: "People", items: peopleItems)
                ClassicMenuButton(title: "Connect", items: connectMenuItems)
                Spacer(minLength: 8)
                if let copiedLabel {
                    Text("✓ \(copiedLabel)")
                        .font(AIMTheme.font(size: 10, bold: true))
                        .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.13))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(height: 26)
            Text(model.statusLine(roomID: roomID))
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
        }
        .background(AIMTheme.client)
    }

    private var stoppedBanner: some View {
        HStack(spacing: 6) {
            Text("Room is Stopped — press Start to let helpers answer, or Copy Prompt to bring in another app.")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("▶ Start") {
                model.start(roomID: roomID)
            }
            .buttonStyle(AIMButtonStyle())
            Button("◎ Roundtable") {
                model.startRoundtable(roomID: roomID)
            }
            .buttonStyle(AIMButtonStyle())
            ClassicMenuButton(title: "Copy Prompt ▾", items: connectMenuItems)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AIMTheme.client)
                .overlay(BevelOverlay(raised: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AIMTheme.cream)
        .overlay(BevelOverlay(raised: false))
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private var transcript: some View {
        TranscriptView(messages: model.messages[roomID] ?? [])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(AIMTheme.client)
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach([10, 12, 14, 18, 24], id: \.self) { size in
                    Button("\(size) pt") {
                        pointSize = CGFloat(size)
                        compose.setPointSize(CGFloat(size))
                    }
                }
            } label: {
                Text("\(Int(pointSize))")
                    .frame(width: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            Button("B") { compose.toggleBold() }
                .buttonStyle(AIMButtonStyle())
            Button("I") { compose.toggleItalic() }
                .buttonStyle(AIMButtonStyle())
            Button("U") { compose.toggleUnderline() }
                .buttonStyle(AIMButtonStyle())
            Button("@") { compose.insert("@") }
                .buttonStyle(AIMButtonStyle())
            Button(":)") { compose.insert(":) ") }
                .buttonStyle(AIMButtonStyle())
            ForEach(["@all", "@GrokBot", "@Muse", "@Antigravity", "@Claude", "@Codex", "@Grok"], id: \.self) { tag in
                Button(tag) { compose.insert(tag + " ") }
                    .buttonStyle(AIMButtonStyle())
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AIMTheme.client)
    }

    private var composeBox: some View {
        ComposeBox(controller: compose)
            .frame(height: 110)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .background(AIMTheme.client)
    }

    private var toolbar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            CaptionTool(title: "Start", sunken: engine?.phase == .running) {
                model.start(roomID: roomID)
            } icon: {
                Text("▶").font(AIMTheme.font(size: 12, bold: true)).foregroundStyle(.black)
            }
            CaptionTool(title: "Pause", sunken: engine?.phase == .paused) {
                model.pause(roomID: roomID)
            } icon: {
                Text("❚❚").font(AIMTheme.font(size: 10, bold: true)).foregroundStyle(.black)
            }
            CaptionTool(title: "Stop", sunken: engine?.phase == .stopped) {
                model.stop(roomID: roomID)
            } icon: {
                Text("■").font(AIMTheme.font(size: 11, bold: true)).foregroundStyle(.black)
            }
            CaptionTool(title: "Roundtable", sunken: room?.roundtable ?? false) {
                model.setRoundtable(roomID: roomID, on: !(room?.roundtable ?? false))
            } icon: {
                Text("◎").font(AIMTheme.font(size: 14)).foregroundStyle(.black)
            }
            CaptionTool(title: "Connect") {
                model.selectConnectRoom(room?.name ?? "Lobby", copyToClipboard: true)
                openWindow(id: "connect")
            } icon: {
                Text("C").font(AIMTheme.font(size: 13, bold: true)).foregroundStyle(.black)
            }
            VStack(spacing: 2) {
                Text("Turns")
                    .font(AIMTheme.font(size: 10))
                HStack(spacing: 2) {
                    Button("−") { model.changeTurnLimit(roomID: roomID, delta: -1) }
                        .buttonStyle(AIMButtonStyle())
                    Text("\(room?.turnLimit ?? 4)")
                        .font(AIMTheme.font(size: 12, bold: true))
                        .frame(width: 22)
                    Button("+") { model.changeTurnLimit(roomID: roomID, delta: 1) }
                        .buttonStyle(AIMButtonStyle())
                }
            }
            .foregroundStyle(.black)
            Toggle("Allow file changes", isOn: fileChangesBinding)
                .toggleStyle(.checkbox)
                .font(AIMTheme.font(size: 11))
                .foregroundStyle(.black)
            Spacer(minLength: 8)
            CaptionTool(title: "Send", action: send) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AIMTheme.client)
    }

    private var engine: TurnEngine? { model.engines[roomID] }

    private var fileChangesBinding: Binding<Bool> {
        Binding(
            get: { room?.allowFileChanges ?? false },
            set: { model.setAllowFileChanges(roomID: roomID, allowed: $0) }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    private var connectMenuItems: [(title: String, key: String, action: () -> Void)] {
        var items: [(title: String, key: String, action: () -> Void)] = [
            ("Open Connect Window…", "", {
                model.selectConnectRoom(room?.name ?? "Lobby", copyToClipboard: false)
                openWindow(id: "connect")
            })
        ]
        for preset in ConnectPreset.featured {
            items.append(("Copy Prompt for \(preset.displayName)", "", {
                copyForPreset(preset)
            }))
        }
        for preset in ConnectPreset.additional {
            items.append(("Copy Prompt for \(preset.displayName)", "", {
                copyForPreset(preset)
            }))
        }
        return items
    }

    private var mentionItems: [(title: String, key: String, action: () -> Void)] {
        var tags = [
            "@all",
            "@room",
            "@GrokBot",
            "@Muse",
            "@Antigravity",
            "@ClaudeCode",
            "@Codex",
            "@Grok",
            "@CursorGrok",
            "@Claude",
            "@Cursor",
            "@Gemini",
            "@ChatGPT"
        ]
        for guest in model.joinedGuests {
            let tag = "@\(guest)"
            if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                tags.append(tag)
            }
        }
        return tags.map { tag in
            (tag, "", { compose.insert(tag + " ") })
        }
    }

    private var smileyItems: [(title: String, key: String, action: () -> Void)] {
        [":)", ":(", ";)", ":D", ":P", ":O", ":'(", "8-)"].map { smiley in
            (smiley, "", { compose.insert(smiley + " ") })
        }
    }

    private var peopleItems: [(title: String, key: String, action: () -> Void)] {
        var items: [(title: String, key: String, action: () -> Void)] = [
            ("Setup…", "", { model.showingKeySheet = true }),
            ("Connect External Program…", "", {
                model.selectConnectRoom(room?.name ?? "Lobby", copyToClipboard: false)
                openWindow(id: "connect")
            }),
            (model.screenName.isEmpty ? "Me" : model.screenName, "", { compose.insert(model.screenName + " ") })
        ]
        for buddy in model.buddies {
            let state = buddy.online && buddy.enabled ? "" : " (offline)"
            items.append((buddy.id.screenName + state, "", { model.openBuddy(buddy.id) }))
        }
        for guest in model.joinedGuests {
            items.append(("\(guest) (connected)", "", { compose.insert("@\(guest) ") }))
        }
        for buddy in model.buddies {
            let title = buddy.enabled ? "Disable \(buddy.id.screenName)" : "Enable \(buddy.id.screenName)"
            items.append((title, "", { model.setEnabled(buddy.id, enabled: !buddy.enabled) }))
        }
        items.append(("Refresh presence", "", { model.refreshPresence() }))
        return items
    }

    private func copyForPreset(_ preset: ConnectPreset) {
        let targetRoom = room?.name ?? "Lobby"
        _ = model.selectConnectPreset(preset, roomName: targetRoom, copyToClipboard: true)
        copiedLabel = "Copied \(preset.buttonTitle) prompt"
    }

    private func send() {
        let plain = compose.plainText()
        let rtf = compose.rtfData()
        model.sendHuman(roomID: roomID, plain: plain, rtf: rtf)
        if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compose.clear()
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder for a ShadowChat room."
        if panel.runModal() == .OK, let url = panel.url {
            model.addProjectRoom(path: url.path)
        }
    }
}
