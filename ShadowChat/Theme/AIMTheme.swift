import AppKit
import SwiftUI

enum AIMTheme {
    static let titleTop = Color(red: 0.22, green: 0.47, blue: 0.84)
    static let titleBottom = Color(red: 0.06, green: 0.24, blue: 0.58)
    static let frameBlue = Color(red: 0.05, green: 0.16, blue: 0.45)
    static let client = Color(red: 0.835, green: 0.820, blue: 0.788)
    static let clientPressed = Color(red: 0.765, green: 0.750, blue: 0.718)
    static let groupHeader = Color(red: 0.755, green: 0.742, blue: 0.710)
    static let highlight = Color(red: 0.04, green: 0.16, blue: 0.46)
    static let cream = Color(red: 0.992, green: 0.968, blue: 0.925)
    static let wordmark = Color.white
    static let logoBlue = Color(red: 0.02, green: 0.20, blue: 0.56)
    static let titleBlue = Color(red: 0.12, green: 0.39, blue: 0.78)
    static let bevelDark = Color(white: 0.30)
    static let bevelMid = Color(white: 0.55)
    static let fieldWhite = Color.white
    static let onlineGreen = Color(red: 0.06, green: 0.64, blue: 0.20)
    static let installedAmber = Color(red: 0.84, green: 0.52, blue: 0.04)

    static func nsFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        if italic && bold, let font = NSFont(name: "Verdana-BoldItalic", size: size) { return font }
        if bold, let font = NSFont(name: "Verdana-Bold", size: size) { return font }
        if italic, let font = NSFont(name: "Verdana-Italic", size: size) { return font }
        if let font = NSFont(name: "Verdana", size: size) { return font }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
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
                path.addLine(to: CGPoint(x: max(0, width - 1.5), y: 1.5))
                path.addLine(to: CGPoint(x: 1.5, y: 1.5))
                path.addLine(to: CGPoint(x: 1.5, y: max(0, height - 1.5)))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(raised ? Color.white : AIMTheme.bevelDark)
            Path { path in
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: 1.5, y: max(0, height - 1.5)))
                path.addLine(to: CGPoint(x: max(0, width - 1.5), y: max(0, height - 1.5)))
                path.addLine(to: CGPoint(x: max(0, width - 1.5), y: 1.5))
                path.closeSubpath()
            }
            .fill(raised ? AIMTheme.bevelDark : Color.white)
        }
        .allowsHitTesting(false)
    }
}

struct AIMButtonStyle: ButtonStyle {
    var sunken: Bool = false
    var compact: Bool = false
    var chip: Bool = false
    var fillWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || sunken
        let fontSize: CGFloat = chip ? 10.5 : (compact ? 11 : 11.5)
        let hPad: CGFloat = chip ? 4.5 : (compact ? 6 : 8)
        let vPad: CGFloat = chip ? 2.5 : (compact ? 3 : 4)
        let minH: CGFloat = chip ? 20 : (compact ? 22 : 24)
        configuration.label
            .font(AIMTheme.font(size: fontSize, bold: sunken))
            .foregroundStyle(.black)
            .lineLimit(1)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: minH)
            .background(pressed ? AIMTheme.clientPressed : AIMTheme.client)
            .overlay(BevelOverlay(raised: !pressed))
            .fixedSize(horizontal: !fillWidth, vertical: true)
    }
}

enum PresenceDotState {
    case online
    case installed
    case offline
}

struct PresenceDot: View {
    var state: PresenceDotState
    var selected: Bool = false

    var body: some View {
        ZStack {
            switch state {
            case .online:
                Circle()
                    .fill(AIMTheme.onlineGreen)
                Circle()
                    .strokeBorder(selected ? Color.white : Color.black.opacity(0.45), lineWidth: 1)
            case .installed:
                Circle()
                    .fill(AIMTheme.installedAmber)
                Circle()
                    .strokeBorder(selected ? Color.white : Color.black.opacity(0.45), lineWidth: 1)
            case .offline:
                Circle()
                    .strokeBorder(selected ? Color.white.opacity(0.85) : Color.gray.opacity(0.75), lineWidth: 1.2)
            }
        }
        .frame(width: 8, height: 8)
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
    var dialog: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = TitlebarHider()
        view.title = title
        view.dialog = dialog
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitlebarHider)?.title = title
        (nsView as? TitlebarHider)?.dialog = dialog
        (nsView as? TitlebarHider)?.apply()
    }
}

final class TitlebarHider: NSView {
    var title = ""
    /// Dialogs keep their own small size instead of the buddy-list minimums.
    var dialog = false

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
        if !dialog {
            if frame.width < 280 { frame.size.width = min(330, visible.width - 16) }
            if frame.height < 420 { frame.size.height = min(560, visible.height - 16) }
        }
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
    var showWindowControls: Bool = true
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AIMTheme.titleTop, AIMTheme.titleBottom],
                startPoint: .leading,
                endPoint: .trailing
            )
            WindowDragView()
            HStack(spacing: 6) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(title)
                    .font(AIMTheme.font(size: 12, bold: true))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.45), radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if showWindowControls {
                    HStack(spacing: 3) {
                        WindowGlyphButton(kind: .minimize) { $0.miniaturize(nil) }
                            .frame(width: 18, height: 16)
                        WindowGlyphButton(kind: .zoom) { $0.zoom(nil) }
                            .frame(width: 18, height: 16)
                        WindowGlyphButton(kind: .close) { window in
                            if let onClose {
                                onClose()
                            } else {
                                window.performClose(nil)
                            }
                        }
                        .frame(width: 18, height: 16)
                    }
                } else if let onClose {
                    Button(action: onClose) {
                        ZStack {
                            AIMTheme.client
                            CloseCrossShape()
                                .stroke(Color.black, lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                            BevelOverlay(raised: true)
                        }
                        .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 26)
    }
}

private struct CloseCrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

struct WindowGlyphButton: NSViewRepresentable {
    enum Kind {
        case minimize
        case zoom
        case close
    }

    var kind: Kind = .close
    var glyph: String = ""
    var action: (NSWindow) -> Void

    init(kind: Kind, action: @escaping (NSWindow) -> Void) {
        self.kind = kind
        self.action = action
    }

    init(glyph: String, action: @escaping (NSWindow) -> Void) {
        self.glyph = glyph
        switch glyph {
        case "_": self.kind = .minimize
        case "□": self.kind = .zoom
        default: self.kind = .close
        }
        self.action = action
    }

    func makeNSView(context: Context) -> ClassicWindowControlNSButton {
        let button = ClassicWindowControlNSButton(kind: kind)
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire(_:))
        context.coordinator.action = action
        return button
    }

    func updateNSView(_ nsView: ClassicWindowControlNSButton, context: Context) {
        nsView.kind = kind
        context.coordinator.action = action
        nsView.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClassicWindowControlNSButton, context: Context) -> CGSize {
        CGSize(width: 18, height: 16)
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

final class ClassicWindowControlNSButton: NSButton {
    var kind: WindowGlyphButton.Kind

    override var isFlipped: Bool { true }

    init(kind: WindowGlyphButton.Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 16))
        isBordered = false
        title = ""
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = isHighlighted
        let bg = pressed
            ? NSColor(calibratedRed: 0.76, green: 0.75, blue: 0.72, alpha: 1)
            : NSColor(calibratedRed: 0.835, green: 0.820, blue: 0.788, alpha: 1)
        bg.setFill()
        bounds.fill()

        let topLeft = pressed ? NSColor(calibratedWhite: 0.30, alpha: 1) : NSColor.white
        let bottomRight = pressed ? NSColor.white : NSColor(calibratedWhite: 0.30, alpha: 1)

        topLeft.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1.5).fill()
        NSRect(x: 0, y: 0, width: 1.5, height: bounds.height).fill()

        bottomRight.setFill()
        NSRect(x: 0, y: bounds.height - 1.5, width: bounds.width, height: 1.5).fill()
        NSRect(x: bounds.width - 1.5, y: 0, width: 1.5, height: bounds.height).fill()

        NSColor.black.setStroke()
        NSColor.black.setFill()
        let offset: CGFloat = pressed ? 0.5 : 0.0

        switch kind {
        case .minimize:
            let bar = NSRect(x: 5 + offset, y: bounds.height - 5.5 + offset, width: 8, height: 2)
            bar.fill()
        case .zoom:
            let box = NSRect(x: 4.5 + offset, y: 3.5 + offset, width: 9, height: 8.5)
            let path = NSBezierPath(rect: box)
            path.lineWidth = 1.2
            path.stroke()
            NSRect(x: 4.5 + offset, y: 3.5 + offset, width: 9, height: 2.2).fill()
        case .close:
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.move(to: NSPoint(x: 5 + offset, y: 4 + offset))
            path.line(to: NSPoint(x: 13 + offset, y: 12 + offset))
            path.move(to: NSPoint(x: 13 + offset, y: 4 + offset))
            path.line(to: NSPoint(x: 5 + offset, y: 12 + offset))
            path.stroke()
        }
    }
}

struct CaptionTool<Icon: View>: View {
    var title: String
    var sunken: Bool = false
    var compact: Bool = false
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                icon()
                    .frame(width: compact ? 20 : 22, height: compact ? 18 : 20)
                Text(title)
                    .font(AIMTheme.font(size: compact ? 9.5 : 10, bold: sunken))
                    .foregroundStyle(.black)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 3 : 6)
            .padding(.vertical, 3)
            .frame(
                minWidth: compact ? 48 : 56,
                maxWidth: compact ? .infinity : nil,
                minHeight: compact ? 42 : 46
            )
            .background(sunken ? AIMTheme.clientPressed : AIMTheme.client)
            .overlay(BevelOverlay(raised: !sunken))
            .fixedSize(horizontal: !compact, vertical: true)
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
        VStack(spacing: 0) {
            ClassicTitleBar(title: "ShadowChat Setup", showWindowControls: false) {
                ClassicDialog.close("ShadowChat Setup")
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Name")
                        .font(AIMTheme.font(size: 12, bold: true))
                        .foregroundStyle(.black)
                    TextField("Me", text: $name)
                        .textFieldStyle(.plain)
                        .font(AIMTheme.font(size: 12))
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Color.white)
                        .overlay(BevelOverlay(raised: false))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Grok Model (xAI)")
                        .font(AIMTheme.font(size: 12, bold: true))
                        .foregroundStyle(.black)
                    TextField(CLIPaths.defaultGrokModel, text: $modelName)
                        .textFieldStyle(.plain)
                        .font(AIMTheme.font(size: 12))
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Color.white)
                        .overlay(BevelOverlay(raised: false))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("xAI API Key")
                        .font(AIMTheme.font(size: 12, bold: true))
                        .foregroundStyle(.black)
                    Text(model.keySaved ? "✓ An xAI API key is saved in the macOS Keychain. Leave blank to keep it." : "Optional — stored only in the macOS Keychain for direct Grok turns.")
                        .font(AIMTheme.font(size: 10.5))
                        .foregroundStyle(.black.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("Paste xAI API key…", text: $keyDraft)
                        .textFieldStyle(.plain)
                        .font(AIMTheme.font(size: 12))
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Color.white)
                        .overlay(BevelOverlay(raised: false))
                }
                .padding(8)
                .background(AIMTheme.cream)
                .overlay(BevelOverlay(raised: false))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferences")
                        .font(AIMTheme.font(size: 12, bold: true))
                        .foregroundStyle(.black)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Play sounds", isOn: $model.soundsOn)
                            Toggle("Show timestamps", isOn: $model.showTimestamps)
                            Toggle("Show smileys as pictures", isOn: $model.smileyGraphics)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Auto sign on at launch", isOn: $model.autoSignOn)
                            Toggle("Open windows for new messages", isOn: $model.openOnIncoming)
                            Toggle("Show Connect window at launch", isOn: $model.showConnectAtLaunch)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(AIMTheme.font(size: 11))
                    .foregroundStyle(.black)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AIMTheme.cream)
                .overlay(BevelOverlay(raised: false))

                HStack(spacing: 8) {
                    Button("Save") {
                        model.saveSetup(screenName: name, modelName: modelName, apiKey: keyDraft)
                        keyDraft = ""
                        ClassicDialog.close("ShadowChat Setup")
                    }
                    .buttonStyle(AIMButtonStyle())
                    if model.keySaved {
                        Button("Delete Key") {
                            model.deleteAPIKey()
                            keyDraft = ""
                        }
                        .buttonStyle(AIMButtonStyle())
                    }
                    Spacer()
                    Button("Close") { ClassicDialog.close("ShadowChat Setup") }
                        .buttonStyle(AIMButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(AIMTheme.client)
            .padding(4)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(AIMTheme.frameBlue)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(WindowConfigurator(title: "ShadowChat Setup", dialog: true).frame(width: 0, height: 0))
        .preferredColorScheme(.light)
        .onDisappear { model.showingKeySheet = false }
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
    static func render(_ messages: [ChatMessage], timestamps: Bool = false, smileys: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        paragraph.paragraphSpacing = 3.0

        let bodyFont = AIMTheme.nsFont(size: 12)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let noteFont = AIMTheme.nsFont(size: 12, italic: true)
        let stampAttrs: [NSAttributedString.Key: Any] = [
            .font: AIMTheme.nsFont(size: 10),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: paragraph
        ]
        for message in messages {
            if message.status == .streaming && message.body.isEmpty {
                // The "is typing…" line under the transcript covers a reply that has not started yet.
                continue
            }
            let nameFont = AIMTheme.nsFont(size: 12, bold: true)
            let isNotice = message.senderName == "ShadowChat"
            let name = NSAttributedString(
                string: message.senderName,
                attributes: [
                    .font: nameFont,
                    .foregroundColor: ScreenColors.color(sender: message.sender, name: message.senderName),
                    .paragraphStyle: paragraph
                ]
            )
            result.append(name)
            if timestamps {
                result.append(NSAttributedString(string: " " + TranscriptStamp.text(for: message.createdAt), attributes: stampAttrs))
            }
            result.append(NSAttributedString(string: ": ", attributes: bodyAttrs))
            let body: NSMutableAttributedString
            if message.sender == .me, let rtf = message.rtf,
               let rich = NSAttributedString(rtf: rtf, documentAttributes: nil), rich.length > 0 {
                body = NSMutableAttributedString(attributedString: rich)
            } else if isNotice {
                body = NSMutableAttributedString(string: message.body, attributes: [
                    .font: noteFont,
                    .foregroundColor: NSColor(calibratedWhite: 0.30, alpha: 1),
                    .paragraphStyle: paragraph
                ])
            } else {
                body = NSMutableAttributedString(string: message.body, attributes: bodyAttrs)
            }
            if smileys {
                Smileys.replace(in: body)
            }
            result.append(body)
            if message.status == .cancelled {
                result.append(NSAttributedString(
                    string: " (cancelled)",
                    attributes: [.font: noteFont, .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph]
                ))
            } else if message.status == .error {
                result.append(NSAttributedString(
                    string: " (error)",
                    attributes: [.font: noteFont, .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph]
                ))
            }
            result.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        return result
    }
}

enum ClassicDialog {
    /// Closes a dialog window by the title its WindowConfigurator gave it.
    static func close(_ title: String) {
        NSApp.windows.first { $0.title == title && $0.isVisible }?.close()
    }
}
