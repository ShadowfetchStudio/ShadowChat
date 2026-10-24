import AppKit
import SwiftUI

struct SystemConnectView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var copied = false
    @State private var copiedOneLine = false
    @State private var copiedHandoff = false

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: windowTitle)
            VStack(spacing: 0) {
                menuBar
                presetBar
                guideBanner
                transcript
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
        .frame(minWidth: 700, minHeight: 540)
        .preferredColorScheme(.light)
        .onChange(of: model.showingKeySheet) { _, show in if show { openWindow(id: "setup") } }
        .onChange(of: model.showingAwaySheet) { _, show in if show { openWindow(id: "away") } }
    }

    private var windowTitle: String {
        let who = model.screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ShadowChat System : \(who.isEmpty ? "Me" : who) - Instant Message"
    }

    private var menuBar: some View {
        HStack(spacing: 6) {
            ClassicMenuButton(title: "File", items: [
                ("Open Target Room", "l", openTargetRoom),
                ("Close", "w", { NSApp.keyWindow?.performClose(nil) })
            ])
            ClassicMenuButton(title: "Edit", items: [
                ("Copy Prompt", "c", copyPrompt),
                ("Copy Context Handoff Packet", "h", copyHandoff),
                ("Copy 1-Line Command", "1", copyOneLiner),
                ("---", "", {}),
                ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
            ])
            ClassicMenuButton(title: "Program", items: programMenuItems)
            ClassicMenuButton(title: "Room", items: roomMenuItems)
            ClassicMenuButton(title: "Mode", items: modeMenuItems)
            Spacer(minLength: 8)
            PresenceDot(state: model.bridgePort > 0 ? .online : .offline)
            Text(status)
                .font(AIMTheme.font(size: 10, bold: true))
                .foregroundStyle(.black)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 24)
        .background(AIMTheme.client)
    }

    private var presetBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("1-Click Copy:")
                    .font(AIMTheme.font(size: 10.5, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(ConnectPreset.featured) { preset in
                            let isOnline = preset != .universal && model.isGuestConnected(preset.screenName)
                            Button((isOnline ? "● " : "") + preset.buttonTitle) {
                                selectPreset(preset)
                            }
                            .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectPreset == preset, compact: true))
                        }
                        ClassicMenuButton(
                            title: "More ▾",
                            fontSize: 11,
                            bold: ConnectPreset.additional.contains(model.selectedConnectPreset),
                            items: ConnectPreset.additional.map { preset in
                                let isOnline = model.isGuestConnected(preset.screenName)
                                return ((isOnline ? "● " : "") + preset.displayName, "", { selectPreset(preset) })
                            }
                        )
                        .padding(.horizontal, 4)
                        .frame(height: 22)
                        .background(ConnectPreset.additional.contains(model.selectedConnectPreset) ? AIMTheme.clientPressed : AIMTheme.client)
                        .overlay(BevelOverlay(raised: !ConnectPreset.additional.contains(model.selectedConnectPreset)))
                        .fixedSize()
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Target Room:")
                    .font(AIMTheme.font(size: 10.5, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .fixedSize()
                ClassicMenuButton(title: "\(model.selectedConnectRoom) ▾", fontSize: 11, items: roomMenuItems)
                    .padding(.horizontal, 4)
                    .frame(height: 22)
                    .background(Color.white)
                    .overlay(BevelOverlay(raised: false))
                    .fixedSize()
                Text("Format:")
                    .font(AIMTheme.font(size: 10.5, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 4)
                ForEach(ConnectPromptMode.allCases) { mode in
                    Button(mode.label) {
                        model.selectConnectMode(mode, copyToClipboard: true)
                        copied = true
                        copiedOneLine = false
                        copiedHandoff = false
                    }
                    .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectMode == mode, compact: true))
                }
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AIMTheme.groupHeader.opacity(0.55))
        .overlay(BevelOverlay(raised: true))
        .padding(.horizontal, 8)
    }

    private var guideBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(bannerHeadline)
                    .font(AIMTheme.font(size: 11, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !model.joinedGuests.isEmpty {
                    Text("Online via Bridge: \(model.joinedGuests.joined(separator: ", "))")
                        .font(AIMTheme.font(size: 10, bold: true))
                        .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.13))
                        .lineLimit(1)
                }
            }
            Text("Step 1: Click your program button above (auto-copies prompt)  ➔  Step 2: Paste (⌘V) into Grok Bot, Muse, Claude, Codex, Antigravity, Cursor, etc.  ➔  Step 3: Chat in \(model.selectedConnectRoom)!")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.84))
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIMTheme.cream)
        .overlay(BevelOverlay(raised: false))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var transcript: some View {
        TranscriptView(messages: systemMessages, scrollToBottom: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AIMTheme.client)
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 6) {
            CaptionTool(title: copied ? "Copied" : "Copy", sunken: copied, action: copyPrompt) {
                Text("C")
                    .font(AIMTheme.font(size: 14, bold: true))
                    .foregroundStyle(.black)
            }
            CaptionTool(title: copiedHandoff ? "Copied!" : "Handoff", sunken: copiedHandoff, action: copyHandoff) {
                Text("⇄")
                    .font(AIMTheme.font(size: 14, bold: true))
                    .foregroundStyle(.black)
            }
            .help("Copy recent room transcript + live Connect Prompt to hand off context to another AI app")
            CaptionTool(title: copiedOneLine ? "Copied 1L" : "1-Line", sunken: copiedOneLine, action: copyOneLiner) {
                Text("⌘")
                    .font(AIMTheme.font(size: 13, bold: true))
                    .foregroundStyle(.black)
            }
            if let appURL = activeAppURL {
                CaptionTool(title: "Open App", action: {
                    model.copyAndOpenApp(for: model.selectedConnectPreset, roomName: model.selectedConnectRoom)
                    copied = true
                    copiedOneLine = false
                    copiedHandoff = false
                }) {
                    Text("↗")
                        .font(AIMTheme.font(size: 14, bold: true))
                        .foregroundStyle(.black)
                }
                .help("Copy prompt and open \(appURL.deletingPathExtension().lastPathComponent)")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Works with Grok Bot, Muse, Claude, Codex, Antigravity, Cursor, Gemini, ChatGPT, Windsurf, Aider, Goose, Cline, OpenCode, Warp, Zed & more.")
                    .font(AIMTheme.font(size: 10))
                    .foregroundStyle(.black.opacity(0.85))
                    .lineLimit(2)
                Toggle("Show this window at launch", isOn: $model.showConnectAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(AIMTheme.font(size: 10))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 6)
            CaptionTool(title: "Open Room", action: openTargetRoom) {
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

    private var activeAppURL: URL? {
        model.selectedConnectPreset.installedAppURL()
    }

    private var bannerHeadline: String {
        if !model.connectBannerText.isEmpty {
            return "✓ " + model.connectBannerText
        }
        let preset = model.selectedConnectPreset
        return "Ready-to-Paste Connect Prompt for \(preset.displayName) (Room: \(model.selectedConnectRoom))"
    }

    private var status: String {
        if model.bridgePort > 0 {
            let count = model.joinedGuests.count
            let suffix = count > 0 ? " · \(count) connected" : ""
            return "Local bridge 127.0.0.1:\(model.bridgePort)\(suffix)"
        }
        return "Local bridge is not listening"
    }

    private var programMenuItems: [(title: String, key: String, action: () -> Void)] {
        var items: [(title: String, key: String, action: () -> Void)] = ConnectPreset.allCases.map { preset in
            let connected = preset != .universal && model.isGuestConnected(preset.screenName)
            let prefix = connected ? "● " : ""
            return (prefix + preset.displayName, "", { selectPreset(preset) })
        }
        let installed = ConnectPreset.installedPresets()
        if !installed.isEmpty {
            items.append(("---", "", {}))
            for preset in installed {
                items.append(("Copy & Open \(preset.displayName) ↗", "", {
                    model.copyAndOpenApp(for: preset, roomName: model.selectedConnectRoom)
                    copied = true
                    copiedOneLine = false
                    copiedHandoff = false
                }))
            }
        }
        return items
    }

    private var roomMenuItems: [(title: String, key: String, action: () -> Void)] {
        let names = model.rooms.map(\.name)
        let list = names.isEmpty ? ["Lobby"] : names
        return list.map { name in
            (name, "", {
                model.selectConnectRoom(name, copyToClipboard: true)
                copied = true
                copiedOneLine = false
                copiedHandoff = false
            })
        }
    }

    private var modeMenuItems: [(title: String, key: String, action: () -> Void)] {
        ConnectPromptMode.allCases.map { mode in
            (mode.label, "", {
                model.selectConnectMode(mode, copyToClipboard: true)
                copied = true
                copiedOneLine = false
                copiedHandoff = false
            })
        }
    }

    private var systemMessages: [ChatMessage] {
        [
            ChatMessage(
                id: "shadowchat-system",
                roomID: "system",
                sender: .me,
                senderName: "ShadowChat",
                body: model.connectPrompt,
                rtf: nil,
                status: .complete,
                createdAt: model.connectIssuedAt
            )
        ]
    }

    private func selectPreset(_ preset: ConnectPreset) {
        _ = model.selectConnectPreset(preset, copyToClipboard: true)
        copied = true
        copiedOneLine = false
        copiedHandoff = false
    }

    private func copyPrompt() {
        _ = model.selectConnectPreset(model.selectedConnectPreset, copyToClipboard: true)
        copied = true
        copiedOneLine = false
        copiedHandoff = false
    }

    private func copyHandoff() {
        _ = model.copyHandoffPacket(preset: model.selectedConnectPreset)
        copiedHandoff = true
        copied = false
        copiedOneLine = false
    }

    private func copyOneLiner() {
        _ = model.copyOneLiner()
        copiedOneLine = true
        copied = false
        copiedHandoff = false
    }

    private func openTargetRoom() {
        if let target = model.rooms.first(where: { $0.name.caseInsensitiveCompare(model.selectedConnectRoom) == .orderedSame }) {
            model.requestOpen(target.id)
        } else {
            model.openLobby()
        }
    }
}
