import AppKit
import SwiftUI

/// First-run guide and Help. Plain words first, power-user shortcuts underneath.
struct WelcomeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: "Welcome to ShadowChat", showWindowControls: false) {
                model.dismissWelcome()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(BevelOverlay(raised: false))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome to ShadowChat")
                            .font(AIMTheme.font(size: 16, bold: true))
                        Text("A classic instant messenger room on your Mac where you and all your AI programs talk together.")
                            .font(AIMTheme.font(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.black)

                card(title: "New here? Three easy steps") {
                    step("1", "Type any name in the Screen Name box and click Sign On. Everything stays on this Mac.")
                    step("2", "Double-click a helper with a green dot, or double-click Lobby to open the group chat room.")
                    step("3", "Type a message and press Return. Start a line with @Claude, @Codex, or @all to pick who answers.")
                    step("?", "Helper offline? Hover over it in the Buddy List to see what is needed.")
                }

                card(title: "Multi-Program AI Hub (Grok Bot, Muse, Claude, Codex, Antigravity & more)") {
                    step("•", "Click Connect, click any program's button (or right-click it in Bridge Programs), then press Paste (⌘V).")
                    step("•", "Role tags: @all (everyone) · @coders (coding apps/CLIs) · @thinkers (reasoning apps) · @bridge (external apps) · @local (built-in CLIs).")
                    step("•", "Multi-AI workflows: /compare <question> · /review [focus] · /handoff [app] [note] · /apps.")
                }

                card(title: "Power users & terminal automation") {
                    step("•", "Commands: /who /apps /compare /review /handoff /start /pause /stop /roundtable /clear /export /connect /help.")
                    step("•", "Local bridge on 127.0.0.1 with /join /say /message /wait /transcript /handoff /status /prompt.")
                    step("•", "Auto-looping CLI: ~/Library/Application Support/ShadowChat/shadowchat-cli listen <Name> <Room>")
                    step("•", "File edits stay off unless you explicitly allow them per project room (isolated git worktree).")
                }

                HStack {
                    Button("Open Connect Window") {
                        model.dismissWelcome()
                        openWindow(id: "connect")
                    }
                    .buttonStyle(AIMButtonStyle())
                    Spacer()
                    Button("Got It") { model.dismissWelcome() }
                        .buttonStyle(AIMButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(AIMTheme.client)
            .padding(4)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(AIMTheme.frameBlue)
        .preferredColorScheme(.light)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AIMTheme.font(size: 11.5, bold: true))
                .foregroundStyle(.black)
                .lineLimit(1)
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
                .font(AIMTheme.font(size: 10.5, bold: true))
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(AIMTheme.font(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
    }
}
