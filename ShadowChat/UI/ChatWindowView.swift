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
        .ignoresSafeArea(.container, edges: .top)
        .overlay(WindowConfigurator(title: windowTitle).frame(width: 0, height: 0))
        .frame(minWidth: 680, minHeight: 520)
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
            HStack(spacing: 6) {
                ClassicMenuButton(title: "File", items: [
                    ("New Room…", "n", chooseProject),
                    ("Copy Connect Prompt", "k", { copyForPreset(model.selectedConnectPreset) }),
                    ("Copy Context Handoff Packet (/handoff)", "h", {
                        _ = model.copyHandoffPacket(roomID: roomID)
                        copiedLabel = "Copied Handoff Packet"
                    }),
                    ("Export Transcript…", "e", { model.exportTranscript(roomID: roomID) }),
                    ("---", "", {}),
                    ("Multi-Program Status (/apps)", "", { model.runCommand(.apps, roomID: roomID) }),
                    ("Multi-AI Review (/review)", "", { model.runCommand(.review(""), roomID: roomID) }),
                    ("Commands (/help)", "", { model.runCommand(.help, roomID: roomID) }),
                    ("Who Is Here (/who)", "", { model.runCommand(.who, roomID: roomID) }),
                    ("---", "", {}),
                    ("Clear Room History", "", { model.clearRoomMessages(roomID: roomID) }),
                    ("Close", "w", { NSApp.keyWindow?.performClose(nil) })
                ])
                ClassicMenuButton(title: "Edit", items: [
                    ("Cut", "x", { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }),
                    ("Copy", "c", { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }),
                    ("Paste", "v", { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }),
                    ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
                ])
                ClassicMenuButton(title: "Insert", items: mentionItems + [("— Smileys —", "", {})] + smileyItems)
                ClassicMenuButton(title: "People", items: peopleItems)
                ClassicMenuButton(title: "Connect", items: connectMenuItems)
                Spacer(minLength: 8)
                if let copiedLabel {
                    Text("✓ \(copiedLabel)")
                        .font(AIMTheme.font(size: 10, bold: true))
                        .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.13))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(height: 24)

            HStack(spacing: 6) {
                PresenceDot(state: isStopped ? .offline : .online)
                Text(model.statusLine(roomID: roomID))
                    .font(AIMTheme.font(size: 10))
                    .foregroundStyle(.black.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if room?.roundtable == true {
                    Text("◎ Roundtable On")
                        .font(AIMTheme.font(size: 10, bold: true))
                        .foregroundStyle(Color(red: 0.08, green: 0.34, blue: 0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AIMTheme.groupHeader.opacity(0.45))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.75)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(AIMTheme.bevelDark.opacity(0.35)).frame(height: 1)
            }
        }
        .background(AIMTheme.client)
    }

    private var stoppedBanner: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Room is Stopped — press Start to let helpers answer, or Copy Prompt to bring in another app.")
                .font(AIMTheme.font(size: 10.5))
                .foregroundStyle(.black)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button("▶ Start") {
                model.start(roomID: roomID)
            }
            .buttonStyle(AIMButtonStyle(compact: true))
            Button("◎ Roundtable") {
                model.startRoundtable(roomID: roomID)
            }
            .buttonStyle(AIMButtonStyle(compact: true))
            ClassicMenuButton(title: "Copy Prompt ▾", fontSize: 11, items: connectMenuItems)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(height: 22)
                .background(AIMTheme.client)
                .overlay(BevelOverlay(raised: true))
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AIMTheme.cream)
        .overlay(BevelOverlay(raised: false))
        .padding(.horizontal, 8)
        .padding(.top, 5)
    }

    private var transcript: some View {
        TranscriptView(messages: model.messages[roomID] ?? [], scrollToBottom: true)
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
            ClassicMenuButton(
                title: "\(Int(pointSize)) pt ▾",
                fontSize: 10.5,
                items: [10, 12, 14, 18, 24].map { size in
                    ("\(size) pt", "", {
                        pointSize = CGFloat(size)
                        compose.setPointSize(CGFloat(size))
                    })
                }
            )
            .padding(.horizontal, 3)
            .frame(height: 20)
            .background(AIMTheme.client)
            .overlay(BevelOverlay(raised: true))
            .fixedSize()

            Button("B") { compose.toggleBold() }
                .buttonStyle(AIMButtonStyle(chip: true))
            Button("I") { compose.toggleItalic() }
                .buttonStyle(AIMButtonStyle(chip: true))
            Button("U") { compose.toggleUnderline() }
                .buttonStyle(AIMButtonStyle(chip: true))
            Button(":)") { compose.insert(":) ") }
                .buttonStyle(AIMButtonStyle(chip: true))

            Rectangle()
                .fill(AIMTheme.bevelDark.opacity(0.45))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(["@all", "@coders", "@thinkers", "@bridge", "@GrokBot", "@Muse", "@Antigravity", "@Claude", "@Codex", "@Grok"], id: \.self) { tag in
                        Button(tag) { compose.insert(tag + " ") }
                            .buttonStyle(AIMButtonStyle(chip: true))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AIMTheme.client)
    }

    private var composeBox: some View {
        ComposeBox(controller: compose)
            .frame(height: 106)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .background(AIMTheme.client)
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 6) {
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

            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("Turns")
                        .font(AIMTheme.font(size: 9.5, bold: true))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Button("−") { model.changeTurnLimit(roomID: roomID, delta: -1) }
                            .buttonStyle(AIMButtonStyle(compact: true))
                        Text("\(room?.turnLimit ?? 4)")
                            .font(AIMTheme.font(size: 11.5, bold: true))
                            .frame(width: 20)
                            .lineLimit(1)
                        Button("+") { model.changeTurnLimit(roomID: roomID, delta: 1) }
                            .buttonStyle(AIMButtonStyle(compact: true))
                    }
                }
                .foregroundStyle(.black)

                Toggle("Allow file changes", isOn: fileChangesBinding)
                    .toggleStyle(.checkbox)
                    .font(AIMTheme.font(size: 10.5))
                    .foregroundStyle(.black)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 46)
            .background(AIMTheme.groupHeader.opacity(0.4))
            .overlay(BevelOverlay(raised: false))

            Spacer(minLength: 6)

            CaptionTool(title: "Send", action: send) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .padding(.top, 2)
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
        let targetRoom = room?.name ?? "Lobby"
        var items: [(title: String, key: String, action: () -> Void)] = [
            ("Open Connect Window…", "", {
                model.selectConnectRoom(targetRoom, copyToClipboard: false)
                openWindow(id: "connect")
            }),
            ("Copy Context Handoff Packet (/handoff)", "", {
                _ = model.copyHandoffPacket(roomID: roomID)
                copiedLabel = "Copied Handoff Packet"
            }),
            ("Multi-Program Status (/apps)", "", {
                model.runCommand(.apps, roomID: roomID)
            }),
            ("---", "", {})
        ]
        for preset in ConnectPreset.installedPresets() {
            items.append(("Copy & Open \(preset.displayName) ↗", "", {
                model.copyAndOpenApp(for: preset, roomName: targetRoom)
                copiedLabel = "Opened \(preset.buttonTitle)"
            }))
        }
        items.append(("---", "", {}))
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
            "@coders",
            "@thinkers",
            "@bridge",
            "@local",
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
            ("---", "", {}),
            (model.screenName.isEmpty ? "Me" : model.screenName, "", { compose.insert(model.screenName + " ") })
        ]
        for buddy in model.buddies {
            let state = buddy.online && buddy.enabled ? "" : " (offline)"
            items.append((buddy.id.screenName + state, "", { model.openBuddy(buddy.id) }))
        }
        for guest in model.joinedGuests {
            items.append(("\(guest) (connected)", "", { compose.insert("@\(guest) ") }))
        }
        items.append(("---", "", {}))
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
