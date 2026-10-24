import AppKit
import SwiftUI

struct BuddyListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var expanded: Set<String> = ["Agents", "Bridge Programs", "Buddies", "Rooms"]
    @State private var selection: Selection?

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: model.signedOn ? (model.screenName.isEmpty ? "Me" : model.screenName) : "Sign On")
            VStack(spacing: 0) {
                if model.signedOn {
                    groupList
                    signedOnToolbar
                } else {
                    logoPanel
                    signOnPanel
                    Spacer(minLength: 0)
                }
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AIMTheme.client)
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIMTheme.frameBlue)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(WindowConfigurator(title: "ShadowChat").frame(width: 0, height: 0))
        .frame(minWidth: 320, minHeight: 580)
        .preferredColorScheme(.light)
        .onAppear { if !model.showingWelcome { openWindow(id: "connect") } }
        .onChange(of: model.connectRequest) { _, _ in openWindow(id: "connect") }
        .onChange(of: model.openRequest) { _, request in
            guard let request else { return }
            openWindow(id: "im", value: request.id)
        }
        .alert("ShadowChat", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
        .sheet(isPresented: $model.showingKeySheet) {
            SetupSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showingWelcome) {
            WelcomeSheet()
                .environmentObject(model)
        }
    }

    private var logoPanel: some View {
        VStack(spacing: 6) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(BevelOverlay(raised: false))
            Text("ShadowChat")
                .font(AIMTheme.font(size: 20, bold: true))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.65), radius: 0, x: 1, y: 1)
            Text("Multi-Program AI Messenger")
                .font(AIMTheme.font(size: 10, bold: true))
                .foregroundStyle(AIMTheme.cream.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [AIMTheme.logoBlue, AIMTheme.frameBlue],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(BevelOverlay(raised: true))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(AIMTheme.client)
    }

    private var signOnPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Name")
                    .font(AIMTheme.font(size: 12, bold: true))
                    .foregroundStyle(.black)
                TextField("Me", text: $model.screenName)
                    .textFieldStyle(.plain)
                    .font(AIMTheme.font(size: 13))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .overlay(BevelOverlay(raised: false))
                    .onSubmit { model.signOn() }
                Text("Local sign on. No password leaves this Mac.")
                    .font(AIMTheme.font(size: 10))
                    .foregroundStyle(.black.opacity(0.72))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("1-Click Copy Prompt (Paste into any AI app):")
                    .font(AIMTheme.font(size: 10, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach([ConnectPreset.grokBot, .muse, .claude]) { preset in
                        Button(preset.buttonTitle) {
                            _ = model.selectConnectPreset(preset, copyToClipboard: true)
                            openWindow(id: "connect")
                        }
                        .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectPreset == preset, compact: true, fillWidth: true))
                    }
                }
                HStack(spacing: 4) {
                    ForEach([ConnectPreset.codex, .antigravity, .cursor]) { preset in
                        Button(preset.buttonTitle) {
                            _ = model.selectConnectPreset(preset, copyToClipboard: true)
                            openWindow(id: "connect")
                        }
                        .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectPreset == preset, compact: true, fillWidth: true))
                    }
                }
            }
            .padding(7)
            .background(AIMTheme.cream)
            .overlay(BevelOverlay(raised: false))

            HStack(alignment: .bottom, spacing: 6) {
                CaptionTool(title: "Help", compact: true) {
                    model.showingWelcome = true
                } icon: {
                    Text("?")
                        .font(AIMTheme.font(size: 15, bold: true))
                        .foregroundStyle(.black)
                }
                CaptionTool(title: "Setup", compact: true) {
                    model.showingKeySheet = true
                } icon: {
                    Text("⚒")
                        .font(AIMTheme.font(size: 13))
                        .foregroundStyle(.black)
                }
                CaptionTool(title: "Connect", compact: true) {
                    openWindow(id: "connect")
                } icon: {
                    Text("C")
                        .font(AIMTheme.font(size: 13, bold: true))
                        .foregroundStyle(.black)
                }
                CaptionTool(title: "Sign On", compact: true) {
                    model.signOn()
                } icon: {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AIMTheme.client)
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                let onlineAgents = model.buddies.filter { $0.online && $0.enabled }.count
                group("Agents", countBadge: "\(onlineAgents)/\(model.buddies.count)") {
                    ForEach(model.buddies) { buddy in
                        let isOnline = buddy.online && buddy.enabled
                        row(
                            dotState: isOnline ? .online : .offline,
                            title: buddy.id.screenName,
                            trailing: isOnline ? "Online" : (buddy.enabled ? "Offline" : "Off"),
                            selected: selection == .buddy(buddy.id),
                            online: isOnline,
                            help: buddy.reason
                        ) {
                            selection = .buddy(buddy.id)
                        } double: {
                            selection = .buddy(buddy.id)
                            if buddy.id == .grok && !model.keySaved {
                                model.showingKeySheet = true
                            } else {
                                model.openBuddy(buddy.id)
                            }
                        }
                    }
                }
                let bridgeCount = ConnectPreset.bridgeRosterPresets.count + customConnectedGuests.count
                let connectedCount = model.joinedGuests.count
                group("Bridge Programs", countBadge: connectedCount > 0 ? "\(connectedCount) live" : "\(bridgeCount)") {
                    ForEach(ConnectPreset.bridgeRosterPresets) { preset in
                        let connected = model.isGuestConnected(preset.screenName)
                        let installed = preset.installedAppURL() != nil
                        row(
                            dotState: connected ? .online : (installed ? .installed : .offline),
                            title: preset.displayName,
                            trailing: connected ? "Connected" : (installed ? "Installed ↗" : "Copy Prompt"),
                            selected: selection == .guest(preset.screenName),
                            online: connected || installed,
                            help: connected
                                ? "\(preset.displayName) is connected via 127.0.0.1:\(model.bridgePort). Double-click to open Lobby."
                                : (installed
                                    ? "Click to copy prompt for \(preset.displayName). Double-click to copy & open \(preset.displayName)."
                                    : "Click to copy the ready-to-paste prompt for \(preset.displayName). Double-click to copy & open Connect.")
                        ) {
                            selection = .guest(preset.screenName)
                            _ = model.selectConnectPreset(preset, copyToClipboard: true)
                        } double: {
                            selection = .guest(preset.screenName)
                            if connected {
                                _ = model.selectConnectPreset(preset, copyToClipboard: true)
                                model.openLobby()
                            } else if installed {
                                model.copyAndOpenApp(for: preset)
                            } else {
                                _ = model.selectConnectPreset(preset, copyToClipboard: true)
                                openWindow(id: "connect")
                            }
                        }
                        .contextMenu {
                            Button("Copy Connect Prompt for \(preset.displayName)") {
                                _ = model.selectConnectPreset(preset, copyToClipboard: true)
                            }
                            Button("Copy Context Handoff Packet") {
                                _ = model.copyHandoffPacket(preset: preset)
                            }
                            Button("Copy 1-Line Command") {
                                _ = model.copyOneLiner(preset: preset)
                            }
                            if installed {
                                Button("Copy Prompt & Open \(preset.displayName)") {
                                    model.copyAndOpenApp(for: preset)
                                }
                            }
                            Divider()
                            Button("Open Connect Window…") {
                                _ = model.selectConnectPreset(preset, copyToClipboard: false)
                                openWindow(id: "connect")
                            }
                        }
                    }
                    ForEach(customConnectedGuests, id: \.self) { guest in
                        row(
                            dotState: .online,
                            title: guest,
                            trailing: "Connected",
                            selected: selection == .guest(guest),
                            online: true,
                            help: "\(guest) is connected via the localhost bridge."
                        ) {
                            selection = .guest(guest)
                        } double: {
                            selection = .guest(guest)
                            model.openLobby()
                        }
                    }
                }
                group("Buddies", countBadge: model.signedOn ? "1/1" : "0/1") {
                    row(
                        dotState: model.signedOn ? .online : .offline,
                        title: model.screenName.isEmpty ? "Me" : model.screenName,
                        trailing: model.signedOn ? "Online" : "Offline",
                        selected: selection == .buddy(.me),
                        online: model.signedOn,
                        help: model.signedOn ? "Signed on" : "Not signed on"
                    ) {
                        selection = .buddy(.me)
                    } double: {
                        selection = .buddy(.me)
                        model.openLobby()
                    }
                }
                group("Rooms", countBadge: "\(model.rooms.count)") {
                    ForEach(model.rooms) { room in
                        let phase = (model.engines[room.id]?.phase ?? room.runState)
                        let badge = room.kind == .lobby
                            ? (phase == .running ? "Lobby · Run" : "Lobby")
                            : (phase == .running ? "Project · Run" : "Project")
                        row(
                            dotState: phase == .running ? .online : .installed,
                            title: room.name,
                            trailing: badge,
                            selected: selection == .room(room.id),
                            online: true,
                            help: room.projectPath ?? "Double-click to open \(room.name)"
                        ) {
                            selection = .room(room.id)
                        } double: {
                            selection = .room(room.id)
                            model.requestOpen(room.id)
                        }
                    }
                    HStack {
                        Button("Add Project Room…") { chooseProject() }
                            .buttonStyle(AIMButtonStyle(compact: true))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .overlay(BevelOverlay(raised: false))
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(AIMTheme.client)
    }

    private var signedOnToolbar: some View {
        HStack(spacing: 4) {
            CaptionTool(title: "Lobby", compact: true, action: { model.openLobby() }) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
            }
            CaptionTool(title: "Connect", compact: true, action: { openWindow(id: "connect") }) {
                Text("C")
                    .font(AIMTheme.font(size: 13, bold: true))
                    .foregroundStyle(.black)
            }
            CaptionTool(title: "Setup", compact: true, action: { model.showingKeySheet = true }) {
                Text("⚒")
                    .font(AIMTheme.font(size: 13))
                    .foregroundStyle(.black)
            }
            CaptionTool(title: "Help", compact: true, action: { model.showingWelcome = true }) {
                Text("?")
                    .font(AIMTheme.font(size: 14, bold: true))
                    .foregroundStyle(.black)
            }
            CaptionTool(title: "Project", compact: true, action: chooseProject) {
                Text("+")
                    .font(AIMTheme.font(size: 15, bold: true))
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(AIMTheme.client)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(footerText)
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(AIMTheme.cream)
                .overlay(BevelOverlay(raised: false))

            HStack(spacing: 6) {
                Text(model.bridgePort > 0 ? "v\(model.version) · 127.0.0.1:\(model.bridgePort)" : "Version \(model.version)")
                    .font(AIMTheme.font(size: 9.5))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Connect") { openWindow(id: "connect") }
                    .buttonStyle(AIMButtonStyle(compact: true))
                if model.signedOn {
                    Button("Sign Off") { model.signOff() }
                        .buttonStyle(AIMButtonStyle(compact: true))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(AIMTheme.client)
        .overlay(alignment: .top) {
            Rectangle().fill(AIMTheme.bevelDark.opacity(0.35)).frame(height: 1)
        }
    }

    private var customConnectedGuests: [String] {
        let standardNames = Set(ConnectPreset.bridgeRosterPresets.map { $0.screenName.lowercased() })
        return model.joinedGuests.filter { !standardNames.contains($0.lowercased()) }
    }

    private var footerText: String {
        switch selection {
        case .buddy(let id):
            if id == .me {
                return model.signedOn ? "\(model.screenName) is signed on. Double-click Lobby to chat." : "Sign on to open Lobby."
            }
            return model.buddies.first(where: { $0.id == id })?.reason ?? ""
        case .guest(let name):
            if model.isGuestConnected(name) {
                return "\(name) is connected via 127.0.0.1:\(model.bridgePort). Double-click to chat in Lobby."
            }
            return "Copied \(name) prompt! Paste (⌘V) into \(name) to connect."
        case .room(let id):
            if let room = model.room(id) {
                return "\(room.name) — double-click to open instant message window."
            }
            return ""
        case nil:
            if !model.connectBannerText.isEmpty {
                return model.connectBannerText
            }
            return model.signedOn ? "Double-click a room or click a Bridge Program to copy its prompt." : "Sign on to open Lobby."
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    private func group<Content: View>(_ title: String, countBadge: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded.contains(title) { expanded.remove(title) } else { expanded.insert(title) }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded.contains(title) ? "▼" : "▶")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 10)
                    Text(title)
                        .font(AIMTheme.font(size: 11.5, bold: true))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !countBadge.isEmpty {
                        Text(countBadge)
                            .font(AIMTheme.font(size: 9.5))
                            .foregroundStyle(.black.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(.black)
                .background(AIMTheme.groupHeader)
                .overlay(BevelOverlay(raised: true))
            }
            .buttonStyle(.plain)
            if expanded.contains(title) {
                content()
            }
        }
    }

    private func row(
        dotState: PresenceDotState,
        title: String,
        trailing: String,
        selected: Bool,
        online: Bool = true,
        help: String,
        action: @escaping () -> Void,
        double: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
            PresenceDot(state: dotState, selected: selected)
            Text(title)
                .font(AIMTheme.font(size: 11.5, bold: selected))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(trailing)
                .font(AIMTheme.font(size: 10))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(selected ? 0.95 : 0.80)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(selected ? Color.white : (online ? Color.black : Color(white: 0.45)))
        .background(selected ? AIMTheme.highlight : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: double)
        .onTapGesture(count: 1, perform: action)
        .help(help)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder for a ShadowChat room."
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.addProjectRoom(path: url.path)
        }
    }
}
