import AppKit
import SwiftUI

struct SystemConnectView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: windowTitle)
            VStack(spacing: 0) {
                menuBar
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
        .frame(minWidth: 620, minHeight: 460)
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
                ("Close", "w", { NSApp.keyWindow?.performClose(nil) })
            ])
            ClassicMenuButton(title: "Edit", items: [
                ("Copy", "c", copyPrompt),
                ("Select All", "a", { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) })
            ])
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: 26)
        Text(status)
            .font(AIMTheme.font(size: 10))
            .foregroundStyle(.black)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
        }
        .background(AIMTheme.client)
    }

    private var transcript: some View {
        TranscriptView(messages: systemMessages)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(BevelOverlay(raised: false))
            .padding(8)
            .background(AIMTheme.client)
    }

    private var toolbar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            CaptionTool(title: copied ? "Copied" : "Copy", sunken: copied, action: copyPrompt) {
                Text("C")
                    .font(AIMTheme.font(size: 14, bold: true))
                    .foregroundStyle(.black)
            }
            Text("Paste this into Codex, Claude, Antigravity, Cursor, Grok, Grok Bot, or Muse.")
                .font(AIMTheme.font(size: 11))
                .foregroundStyle(.black)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AIMTheme.client)
    }

    private var status: String {
        if model.bridgePort > 0 {
            return "Local bridge 127.0.0.1:\(model.bridgePort)"
        }
        return "Local bridge is not listening"
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

    private func copyPrompt() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(model.connectPrompt, forType: .string)
        copied = true
    }
}
