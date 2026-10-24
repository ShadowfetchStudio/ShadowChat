import AppKit
import SwiftUI

struct SystemConnectView: View {
    @EnvironmentObject private var model: AppModel
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
        .ignoresSafeArea()
        .overlay(WindowConfigurator(title: windowTitle).frame(width: 0, height: 0))
        .frame(minWidth: 680, minHeight: 530)
        .preferredColorScheme(.light)
    }

    private var windowTitle: String {
        let who = model.screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ShadowChat System : \(who.isEmpty ? "Me" : who) - Instant Message"
    }

    private var menuBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ClassicMenuButton(title: "File", items: [
                    ("Open Target Room", "l", openTargetRoom),
                    ("Close", "w", { NSApp.keyWindow?.performClose(nil) })
                ])
                ClassicMenuButton(title: "Edit", items: [
                    ("Copy Prompt", "c", copyPrompt),
                    ("Copy Context Handoff Packet", "h", copyHandoff),
                    ("Copy 1-Line Command", "1", copyOneLiner),
                    ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
                ])
                ClassicMenuButton(title: "Program", items: programMenuItems)
                ClassicMenuButton(title: "Room", items: roomMenuItems)
                ClassicMenuButton(title: "Mode", items: modeMenuItems)
                Spacer(minLength: 8)
                Text(status)
                    .font(AIMTheme.font(size: 10, bold: true))
                    .foregroundStyle(.black)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(height: 26)
        }
        .background(AIMTheme.client)
    }

    private var presetBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("1-Click Copy for:")
                    .font(AIMTheme.font(size: 10, bold: true))
                    .foregroundStyle(.black)
                ForEach(ConnectPreset.featured) { preset in
                    let isOnline = preset != .universal && model.isGuestConnected(preset.screenName)
                    Button((isOnline ? "● " : "") + preset.buttonTitle) {
                        selectPreset(preset)
                    }
                    .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectPreset == preset))
                }
                ClassicMenuButton(title: "More ▾", items: ConnectPreset.additional.map { preset in
                    let isOnline = model.isGuestConnected(preset.screenName)
                    return ((isOnline ? "● " : "") + preset.displayName, "", { selectPreset(preset) })
                })
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AIMTheme.client)
                .overlay(BevelOverlay(raised: !ConnectPreset.additional.contains(model.selectedConnectPreset)))
                Spacer(minLength: 4)
            }
            HStack(spacing: 6) {
                Text("Target Room:")
                    .font(AIMTheme.font(size: 10, bold: true))
                    .foregroundStyle(.black)
                ClassicMenuButton(title: "\(model.selectedConnectRoom) ▾", items: roomMenuItems)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .overlay(BevelOverlay(raised: false))
                Text("Format:")
                    .font(AIMTheme.font(size: 10, bold: true))
                    .foregroundStyle(.black)
                ForEach(ConnectPromptMode.allCases) { mode in
                    Button(mode.label) {
                        model.selectConnectMode(mode, copyToClipboard: true)
                        copied = true
                        copiedOneLine = false
                        copiedHandoff = false
                    }
                    .buttonStyle(AIMButtonStyle(sunken: model.selectedConnectMode == mode))
                }
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
                Spacer()
                if !model.joinedGuests.isEmpty {
                    Text("Online via Bridge: \(model.joinedGuests.joined(separator: ", "))")
                        .font(AIMTheme.font(size: 10, bold: true))
                        .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.13))
                }
            }
            Text("Step 1: Click your program button above (auto-copies prompt)  ➔  Step 2: Paste (⌘V) into Grok Bot, Muse, Claude, Codex, Antigravity, Cursor, etc.  ➔  Step 3: Chat in \(model.selectedConnectRoom)!")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black.opacity(0.82))
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
        TranscriptView(messages: systemMessages)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AIMTheme.client)
    }

    private var toolbar: some View {
        HStack(alignment: .bottom, spacing: 6) {
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
            Text("Works with Grok Bot, Muse, Claude, Codex, Antigravity, Cursor, Gemini, ChatGPT, Windsurf, Aider, Goose, Cline, OpenCode, Warp, Zed & more.")
                .font(AIMTheme.font(size: 10))
                .foregroundStyle(.black)
                .lineLimit(2)
            Spacer(minLength: 8)
            CaptionTool(title: "Open Room", action: openTargetRoom) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
