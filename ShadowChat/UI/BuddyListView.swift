import AppKit
import SwiftUI

struct BuddyListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var expanded: Set<String> = ["Agents", "Buddies", "Rooms"]
    @State private var selection: Selection?

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: model.signedOn ? (model.screenName.isEmpty ? "Me" : model.screenName) : "Sign On")
            VStack(spacing: 0) {
                if model.signedOn {
                    groupList
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
        .overlay(WindowConfigurator(title: "ShadowChat").frame(width: 0, height: 0))
        .frame(minWidth: 300, minHeight: 520)
        .preferredColorScheme(.light)
        .onAppear { openWindow(id: "connect") }
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
    }

    private var logoPanel: some View {
        VStack(spacing: 6) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 132, height: 132)
                .background(AIMTheme.logoBlue)
            Text("ShadowChat")
                .font(AIMTheme.font(size: 20, bold: true))
                .foregroundStyle(.white)
                .shadow(color: Color.yellow, radius: 0, x: 1, y: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AIMTheme.logoBlue)
        .overlay(BevelOverlay(raised: true))
        .padding(8)
        .background(AIMTheme.client)
    }

    private var signOnPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Name")
                .font(AIMTheme.font(size: 12, bold: true))
                .foregroundStyle(.black)
            TextField("Me", text: $model.screenName)
                .textFieldStyle(.plain)
                .font(AIMTheme.font(size: 13))
                .foregroundStyle(.black)
                .padding(4)
                .background(Color.white)
                .overlay(BevelOverlay(raised: false))
            Text("Local sign on. No password leaves this Mac.")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.7))
            HStack(alignment: .bottom, spacing: 8) {
                CaptionTool(title: "Help") {
                    model.alert = "Mention @ClaudeCode, @Codex, @Grok, @CursorGrok, or @all. Press Start, then Send. Roundtable invites the roster when nobody is mentioned. Turn limit is 1 to 12. File changes stay off until you allow them for a Git project room."
                } icon: {
                    Text("?")
                        .font(AIMTheme.font(size: 16, bold: true))
                        .foregroundStyle(.black)
                }
                CaptionTool(title: "Setup") {
                    model.showingKeySheet = true
                } icon: {
                    Text("⚒")
                        .font(AIMTheme.font(size: 14))
                        .foregroundStyle(.black)
                }
                Spacer()
                CaptionTool(title: "Sign On") {
                    model.signOn()
                } icon: {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                }
            }
        }
        .padding(10)
        .background(AIMTheme.client)
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                group("Agents") {
                    ForEach(model.buddies) { buddy in
                        row(
                            title: buddy.id.screenName,
                            trailing: "",
                            selected: selection == .buddy(buddy.id),
                            online: buddy.online && buddy.enabled,
                            help: buddy.reason
                        ) {
                            selection = .buddy(buddy.id)
                        } double: {
                            selection = .buddy(buddy.id)
                            model.openBuddy(buddy.id)
                        }
                    }
                }
                group("Buddies") {
                    row(
                        title: model.screenName.isEmpty ? "Me" : model.screenName,
                        trailing: model.signedOn ? "Online" : "Offline",
                        selected: selection == .buddy(.me),
                        online: model.signedOn,
                        help: model.signedOn ? "Signed on" : "Not signed on"
                    ) {
                        selection = .buddy(.me)
                    } double: {
                        selection = .buddy(.me)
                    }
                }
                group("Rooms") {
                    ForEach(model.rooms) { room in
                        row(
                            title: room.name,
                            trailing: room.kind == .lobby ? "Lobby" : "Project",
                            selected: selection == .room(room.id),
                            help: room.projectPath ?? "Local room"
                        ) {
                            selection = .room(room.id)
                        } double: {
                            selection = .room(room.id)
                            model.requestOpen(room.id)
                        }
                    }
                    Button("Add Project…") { chooseProject() }
                        .buttonStyle(AIMButtonStyle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
        .background(AIMTheme.client)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text(footerText)
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(3)
            Spacer(minLength: 8)
            Button("Connect") { openWindow(id: "connect") }
                .buttonStyle(AIMButtonStyle())
            if model.signedOn {
                Button("Sign Off") { model.signOff() }
                    .buttonStyle(AIMButtonStyle())
            }
            Text("Version: \(model.version)")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
        .background(AIMTheme.client)
        .overlay(alignment: .top) {
            Rectangle().fill(AIMTheme.bevelDark.opacity(0.45)).frame(height: 1)
        }
    }

    private var footerText: String {
        switch selection {
        case .buddy(let id):
            if id == .me {
                return model.signedOn ? "\(model.screenName) is signed on." : "Sign on to open Lobby."
            }
            return model.buddies.first(where: { $0.id == id })?.reason ?? ""
        case .room(let id):
            return model.room(id)?.name ?? ""
        case nil:
            return "Sign on to open Lobby."
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded.contains(title) { expanded.remove(title) } else { expanded.insert(title) }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded.contains(title) ? "▼" : "▶")
                        .font(.system(size: 9))
                    Text(title)
                        .font(AIMTheme.font(size: 12, bold: true))
                    Spacer()
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
        title: String,
        trailing: String,
        selected: Bool,
        online: Bool = true,
        help: String,
        action: @escaping () -> Void,
        double: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(AIMTheme.font(size: 12))
            Spacer()
            Text(trailing)
                .font(AIMTheme.font(size: 10))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .foregroundStyle(selected ? Color.white : (online ? Color.black : Color.gray))
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
