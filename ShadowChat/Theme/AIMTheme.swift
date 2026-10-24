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
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.45, alpha: 1)
        window.isRestorable = false
        window.appearance = NSAppearance(named: .aqua)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
                Spacer(minLength: 4)
                captionGlyph("_") { NSApp.keyWindow?.miniaturize(nil) }
                captionGlyph("□") { NSApp.keyWindow?.zoom(nil) }
                captionGlyph("×") { NSApp.keyWindow?.performClose(nil) }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 26)
    }

    private func captionGlyph(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(AIMTheme.font(size: 11, bold: true))
                .foregroundStyle(.black)
                .frame(width: 16, height: 14)
                .background(AIMTheme.client)
                .overlay(BevelOverlay(raised: true))
        }
        .buttonStyle(.plain)
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
                    .foregroundColor: message.sender.nsColor
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
