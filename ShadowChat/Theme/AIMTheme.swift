import AppKit
import SwiftUI

enum AIMTheme {
    static let titleTop = Color(red: 0.36, green: 0.55, blue: 0.84)
    static let titleBottom = Color(red: 0.10, green: 0.28, blue: 0.62)
    static let frameBlue = Color(red: 0.05, green: 0.16, blue: 0.45)
    static let client = Color(red: 0.831, green: 0.816, blue: 0.784)
    static let groupHeader = Color(red: 0.75, green: 0.74, blue: 0.71)
    static let highlight = Color(red: 0.04, green: 0.14, blue: 0.42)
    static let cream = Color(red: 0.992, green: 0.965, blue: 0.925)
    static let wordmark = Color.white
    static let logoBlue = Color(red: 0.00, green: 0.20, blue: 0.58)
    static let titleBlue = Color(red: 0.12, green: 0.39, blue: 0.78)
    static let bevelDark = Color(white: 0.32)
    static let fieldWhite = Color.white

    static func nsFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        if italic && bold, let font = NSFont(name: "Verdana-BoldItalic", size: size) { return font }
        if bold, let font = NSFont(name: "Verdana-Bold", size: size) { return font }
        if italic, let font = NSFont(name: "Verdana-Italic", size: size) { return font }
        if let font = NSFont(name: "Verdana", size: size) { return font }
        return NSFont.systemFont(ofSize: size)
    }

    static func font(size: CGFloat, bold: Bool = false) -> Font {
        Font(nsFont(size: size, bold: bold))
    }
}

struct BevelOverlay: View {
    var raised: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: max(0, width - 2), y: 2))
                path.addLine(to: CGPoint(x: 2, y: 2))
                path.addLine(to: CGPoint(x: 2, y: max(0, height - 2)))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(raised ? Color.white : AIMTheme.bevelDark)
            Path { path in
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: 2, y: max(0, height - 2)))
                path.addLine(to: CGPoint(x: max(0, width - 2), y: max(0, height - 2)))
                path.addLine(to: CGPoint(x: max(0, width - 2), y: 2))
                path.closeSubpath()
            }
            .fill(raised ? AIMTheme.bevelDark : Color.white)
        }
        .allowsHitTesting(false)
    }
}

struct AIMButtonStyle: ButtonStyle {
    var sunken: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || sunken
        configuration.label
            .font(AIMTheme.font(size: 12))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AIMTheme.client)
            .overlay(BevelOverlay(raised: !pressed))
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct WindowConfigurator: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        let view = TitlebarHider()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitlebarHider)?.title = title
        (nsView as? TitlebarHider)?.apply()
    }
}

final class TitlebarHider: NSView {
    var title = ""

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    private var placed = false

    func apply() {
        guard let window else { return }
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.45, alpha: 1)
        window.isRestorable = false
        window.appearance = NSAppearance(named: .aqua)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            button.isHidden = true
            button.alphaValue = 0
        }
        placeIfNeeded(window)
    }

    private func placeIfNeeded(_ window: NSWindow) {
        guard !placed else { return }
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        guard frame.width > 40, frame.height > 40 else { return }
        if frame.width < 280 { frame.size.width = min(320, visible.width - 16) }
        if frame.height < 420 { frame.size.height = min(560, visible.height - 16) }
        if frame.minX < visible.minX { frame.origin.x = visible.minX + 8 }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width - 8 }
        if frame.minY < visible.minY { frame.origin.y = visible.minY + 8 }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height - 8 }
        let stacked = NSApp.windows.contains { other in
            other !== window && abs(other.frame.origin.x - frame.origin.x) < 8 && abs(other.frame.origin.y - frame.origin.y) < 8
        }
        if stacked {
            frame.origin.x = min(frame.origin.x + 28, visible.maxX - frame.width - 8)
            frame.origin.y = max(frame.origin.y - 28, visible.minY + 8)
        }
        placed = true
        window.setFrame(frame, display: false)
    }
}

struct ClassicTitleBar: View {
    var title: String

    var body: some View {
        ZStack {
            AIMTheme.titleBlue
            WindowDragView()
            HStack(spacing: 6) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(AIMTheme.font(size: 12, bold: true))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                WindowGlyphButton(glyph: "_") { $0.miniaturize(nil) }.frame(width: 18, height: 16)
                WindowGlyphButton(glyph: "□") { $0.zoom(nil) }.frame(width: 18, height: 16)
                WindowGlyphButton(glyph: "×") { $0.performClose(nil) }.frame(width: 18, height: 16)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 26)
    }

}

struct WindowGlyphButton: NSViewRepresentable {
    var glyph: String
    var action: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: glyph, target: context.coordinator, action: #selector(Coordinator.fire(_:)))
        button.isBordered = true
        button.bezelStyle = .shadowlessSquare
        button.font = AIMTheme.nsFont(size: 11, bold: true)
        button.setButtonType(.momentaryPushIn)
        button.controlSize = .small
        context.coordinator.action = action
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = glyph
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: (NSWindow) -> Void
        init(action: @escaping (NSWindow) -> Void) { self.action = action }
        @objc func fire(_ sender: NSButton) {
            guard let window = sender.window else { return }
            window.makeKeyAndOrderFront(nil)
            action(window)
        }
    }
}

struct CaptionTool<Icon: View>: View {
    var title: String
    var sunken: Bool = false
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                icon()
                    .frame(width: 24, height: 20)
                Text(title)
                    .font(AIMTheme.font(size: 10))
                    .foregroundStyle(.black)
                    .lineLimit(1)
            }
            .frame(minWidth: 58, minHeight: 46)
            .padding(.horizontal, 2)
            .background(AIMTheme.client)
            .overlay(BevelOverlay(raised: !sunken))
        }
        .buttonStyle(.plain)
    }
}

struct SetupSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var modelName = ""
    @State private var keyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup")
                .font(AIMTheme.font(size: 16, bold: true))
            Text("Screen name")
                .font(AIMTheme.font(size: 12, bold: true))
            TextField("Me", text: $name)
                .textFieldStyle(.plain)
                .font(AIMTheme.font(size: 12))
                .padding(4)
                .background(Color.white)
                .overlay(BevelOverlay(raised: false))
            Text("Grok model")
                .font(AIMTheme.font(size: 12, bold: true))
            TextField(CLIPaths.defaultGrokModel, text: $modelName)
                .textFieldStyle(.plain)
                .font(AIMTheme.font(size: 12))
                .padding(4)
                .background(Color.white)
                .overlay(BevelOverlay(raised: false))
            Text(model.keySaved ? "An xAI API key is in the Keychain. Leave the field blank to keep it." : "No xAI API key is saved. It is stored in the Keychain only.")
                .font(AIMTheme.font(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            SecureField("xAI API key", text: $keyDraft)
                .textFieldStyle(.plain)
                .font(AIMTheme.font(size: 12))
                .padding(4)
                .background(Color.white)
                .overlay(BevelOverlay(raised: false))
            HStack {
                Button("Save") {
                    model.saveSetup(screenName: name, modelName: modelName, apiKey: keyDraft)
                    keyDraft = ""
                }
                .buttonStyle(AIMButtonStyle())
                Button("Delete Key") {
                    model.deleteAPIKey()
                    keyDraft = ""
                }
                .buttonStyle(AIMButtonStyle())
                Spacer()
                Button("Close") { model.showingKeySheet = false }
                    .buttonStyle(AIMButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(AIMTheme.client)
        .preferredColorScheme(.light)
        .onAppear {
            name = model.screenName
            modelName = model.grokModel
        }
    }
}

enum ScreenColors {
    static func color(sender: ParticipantID, name: String) -> NSColor {
        switch name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
        case "shadowchat":
            return NSColor(calibratedRed: 0.15, green: 0.12, blue: 0.35, alpha: 1)
        case "codex":
            return ParticipantID.codex.nsColor
        case "claude", "claudecode":
            return ParticipantID.claudeCode.nsColor
        case "grok", "grokbot":
            return ParticipantID.grok.nsColor
        case "cursor", "cursorgrok":
            return ParticipantID.cursorGrok.nsColor
        case "antigravity", "agy":
            return NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.68, alpha: 1)
        case "muse":
            return NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.55, alpha: 1)
        case "gemini", "geminicli":
            return NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.72, alpha: 1)
        case "chatgpt", "openai":
            return NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.32, alpha: 1)
        case "windsurf", "aider", "goose", "cline", "opencode", "warp", "zed", "copilot", "deepseek", "perplexity":
            return NSColor(calibratedRed: 0.28, green: 0.18, blue: 0.44, alpha: 1)
        default:
            return sender.nsColor
        }
    }
}

enum TranscriptRenderer {
    static func render(_ messages: [ChatMessage]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = AIMTheme.nsFont(size: 12)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]
        let noteFont = AIMTheme.nsFont(size: 12, italic: true)
        for message in messages {
            let nameFont = AIMTheme.nsFont(size: 12, bold: true)
            let name = NSAttributedString(
                string: message.senderName,
                attributes: [
                    .font: nameFont,
                    .foregroundColor: ScreenColors.color(sender: message.sender, name: message.senderName)
                ]
            )
            result.append(name)
            result.append(NSAttributedString(string: ": ", attributes: bodyAttrs))
            if message.sender == .me, let rtf = message.rtf,
               let rich = NSAttributedString(rtf: rtf, documentAttributes: nil), rich.length > 0 {
                result.append(rich)
            } else {
                result.append(NSAttributedString(string: message.body, attributes: bodyAttrs))
            }
            if message.status == .cancelled {
                result.append(NSAttributedString(
                    string: " (cancelled)",
                    attributes: [.font: noteFont, .foregroundColor: NSColor.darkGray]
                ))
            } else if message.status == .error {
                result.append(NSAttributedString(
                    string: " (error)",
                    attributes: [.font: noteFont, .foregroundColor: NSColor.darkGray]
                ))
            }
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        return result
    }
}
