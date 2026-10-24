import AppKit
import SwiftUI

struct ChatWindowView: View {
    @EnvironmentObject private var model: AppModel
    let roomID: String
    @StateObject private var compose = ComposeController()
    @State private var pointSize: CGFloat = 12

    private var room: Room? { model.room(roomID) }

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: windowTitle)
            VStack(spacing: 0) {
                menuBar
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
        .frame(minWidth: 620, minHeight: 460)
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

    private var windowTitle: String {
        let name = room?.name ?? "Room"
        let who = model.screenName.isEmpty ? "Me" : model.screenName
        return "\(name) : \(who) - Instant Message"
    }

    private var menuBar: some View {
        HStack(spacing: 4) {
            ClassicMenuButton(title: "File", items: [
                ("Close", "w", { NSApp.keyWindow?.performClose(nil) }),
                ("New Room…", "n", chooseProject)
            ])
            ClassicMenuButton(title: "Edit", items: [
                ("Cut", "x", { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }),
                ("Copy", "c", { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }),
                ("Paste", "v", { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }),
                ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
            ])
            ClassicMenuButton(title: "Insert", items: mentionItems + smileyItems)
            ClassicMenuButton(title: "People", items: peopleItems)
            Spacer(minLength: 8)
            Text(model.statusLine(roomID: roomID))
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: 26)
        .background(AIMTheme.client)
    }

    private var transcript: some View {
        TranscriptView(messages: model.messages[roomID] ?? [])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.top, 8)
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
            .frame(width: 48)
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
            Spacer()
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

    private var mentionItems: [(title: String, key: String, action: () -> Void)] {
        [
            ("@ClaudeCode", "", { compose.insert("@ClaudeCode ") }),
            ("@Codex", "", { compose.insert("@Codex ") }),
            ("@Grok", "", { compose.insert("@Grok ") }),
            ("@CursorGrok", "", { compose.insert("@CursorGrok ") }),
            ("@all", "", { compose.insert("@all ") }),
            ("@room", "", { compose.insert("@room ") })
        ]
    }

    private var smileyItems: [(title: String, key: String, action: () -> Void)] {
        [":)", ":(", ";)", ":D", ":P", ":O", ":'(", "8-)"].map { smiley in
            (smiley, "", { compose.insert(smiley + " ") })
        }
    }

    private var peopleItems: [(title: String, key: String, action: () -> Void)] {
        var items: [(title: String, key: String, action: () -> Void)] = [
            ("Setup…", "", { model.showingKeySheet = true }),
            (model.screenName.isEmpty ? "Me" : model.screenName, "", { compose.insert(model.screenName + " ") })
        ]
        for buddy in model.buddies {
            let state = buddy.online && buddy.enabled ? "" : " (offline)"
            items.append((buddy.id.screenName + state, "", { model.openBuddy(buddy.id) }))
        }
        for buddy in model.buddies {
            let title = buddy.enabled ? "Disable \(buddy.id.screenName)" : "Enable \(buddy.id.screenName)"
            items.append((title, "", { model.setEnabled(buddy.id, enabled: !buddy.enabled) }))
        }
        items.append(("Refresh presence", "", { model.refreshPresence() }))
        return items
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
