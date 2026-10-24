import AppKit
import SwiftUI

/// First-run guide and Help. Plain words first, power-user shortcuts underneath.
struct WelcomeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .background(AIMTheme.logoBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to ShadowChat")
                        .font(AIMTheme.font(size: 16, bold: true))
                    Text("A chat room on your Mac where you and your AI helpers talk together.")
                        .font(AIMTheme.font(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.black)

            card(title: "New here? Three steps") {
                step("1", "Type any name in the Screen Name box and click Sign On. It stays on this Mac.")
                step("2", "Double-click a helper with a green dot (●) to chat, or just type in the Lobby.")
                step("3", "Type a message and press Return. Start a line with @Claude, @Codex or @all to pick who answers.")
                step("?", "Helper greyed out? Hover over it to see exactly what to do. Nothing is broken.")
            }

            card(title: "Use lots of AI apps? (Grok Bot, Muse, Claude, Codex, Antigravity, Cursor…)") {
                step("•", "Click Connect, click any app's button (or right-click it in Bridge Programs to Copy & Open App), then paste (⌘V).")
                step("•", "Role tags: @all (everyone) · @coders (coding apps/CLIs) · @thinkers (reasoning/brainstorm apps) · @bridge (outside apps only) · @local (built-in CLIs only).")
                step("•", "Multi-AI workflows: /compare <question> · /review [focus] · /handoff [app] [note] · /apps.")
            }

            card(title: "Power users & terminal automation") {
                step("•", "Commands: /who /apps /compare /review /handoff /start /pause /stop /roundtable /clear /export /connect /help.")
                step("•", "Local bridge on 127.0.0.1 with /join /say /message /wait /transcript /handoff /status /prompt.")
                step("•", "Auto-looping CLI: ~/Library/Application Support/ShadowChat/shadowchat-cli listen <Name> <Room>")
                step("•", "File edits stay off unless you allow them per project room (isolated git worktree).")
            }

            HStack {
                Button("Open Connect") {
                    model.dismissWelcome()
                    openWindow(id: "connect")
                }
                .buttonStyle(AIMButtonStyle())
                Spacer()
                Button("Got it") { model.dismissWelcome() }
                    .buttonStyle(AIMButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 500)
        .background(AIMTheme.client)
        .preferredColorScheme(.light)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AIMTheme.font(size: 12, bold: true))
                .foregroundStyle(.black)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIMTheme.cream)
        .overlay(BevelOverlay(raised: false))
    }

    private func step(_ mark: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(mark)
                .font(AIMTheme.font(size: 11, bold: true))
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(AIMTheme.font(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
    }
}
