import AppKit
import SwiftUI

final class ComposeController: ObservableObject {
    weak var textView: NSTextView?
    var onSend: (() -> Void)?

    func plainText() -> String {
        textView?.string ?? ""
    }

    func rtfData() -> Data? {
        guard let textView else { return nil }
        let length = textView.attributedString().length
        guard length > 0 else { return nil }
        return textView.attributedString().rtf(from: NSRange(location: 0, length: length), documentAttributes: [:])
    }

    func clear() {
        textView?.string = ""
        var attrs = textView?.typingAttributes ?? [:]
        attrs[.font] = AIMTheme.nsFont(size: currentSize())
        textView?.typingAttributes = attrs
    }

    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let current = textView.typingAttributes[.underlineStyle] as? Int ?? 0
        let next = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        if range.length == 0 {
            var attrs = textView.typingAttributes
            if next == 0 {
                attrs.removeValue(forKey: .underlineStyle)
            } else {
                attrs[.underlineStyle] = next
            }
            textView.typingAttributes = attrs
        } else if next == 0 {
            textView.textStorage?.removeAttribute(.underlineStyle, range: range)
        } else {
            textView.textStorage?.addAttribute(.underlineStyle, value: next, range: range)
        }
    }

    func setPointSize(_ size: CGFloat) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange()
        func sized(_ font: NSFont) -> NSFont { manager.convert(font, toSize: size) }
        if range.length > 0 {
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? AIMTheme.nsFont(size: size)
                textView.textStorage?.addAttribute(.font, value: sized(font), range: subrange)
            }
            textView.textStorage?.endEditing()
        }
        var attrs = textView.typingAttributes
        let font = (attrs[.font] as? NSFont) ?? AIMTheme.nsFont(size: size)
        attrs[.font] = sized(font)
        textView.typingAttributes = attrs
    }

    func insert(_ text: String) {
        guard let textView else { return }
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private func currentSize() -> CGFloat {
        (textView?.typingAttributes[.font] as? NSFont)?.pointSize ?? 12
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange()
        let typingFont = (textView.typingAttributes[.font] as? NSFont) ?? AIMTheme.nsFont(size: 12)
        let turnOff = manager.traits(of: typingFont).contains(trait)
        func convert(_ font: NSFont) -> NSFont {
            turnOff ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
        }
        if range.length > 0 {
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? typingFont
                textView.textStorage?.addAttribute(.font, value: convert(font), range: subrange)
            }
            textView.textStorage?.endEditing()
        }
        var attrs = textView.typingAttributes
        attrs[.font] = convert((attrs[.font] as? NSFont) ?? typingFont)
        textView.typingAttributes = attrs
    }
}

struct ComposeBox: NSViewRepresentable {
    @ObservedObject var controller: ComposeController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let text = NSTextView()
        text.isRichText = true
        text.isEditable = true
        text.isSelectable = true
        text.allowsUndo = true
        text.drawsBackground = true
        text.backgroundColor = .white
        text.font = AIMTheme.nsFont(size: 12)
        text.textColor = .black
        text.insertionPointColor = .black
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.textContainer?.widthTracksTextView = true
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.delegate = context.coordinator
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.borderType = .noBorder
        controller.textView = text
        context.coordinator.controller = controller
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.controller = controller
        if let text = nsView.documentView as? NSTextView {
            controller.textView = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var controller: ComposeController
        init(controller: ComposeController) { self.controller = controller }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) { return false }
                controller.onSend?()
                return true
            }
            return false
        }
    }
}

struct TranscriptView: NSViewRepresentable {
    var messages: [ChatMessage]
    var scrollToBottom: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = true
        text.backgroundColor = .white
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let text = nsView.documentView as? NSTextView else { return }
        let rendered = TranscriptRenderer.render(messages)
        if text.attributedString() != rendered {
            text.textStorage?.setAttributedString(rendered)
            if scrollToBottom {
                text.scrollToEndOfDocument(nil)
            } else {
                text.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }
    }
}

struct ClassicMenuButton: NSViewRepresentable {
    var title: String
    var fontSize: CGFloat = 11.5
    var bold: Bool = false
    var items: [(title: String, key: String, action: () -> Void)]

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.pop(_:)))
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.font = AIMTheme.nsFont(size: fontSize, bold: bold)
        button.contentTintColor = .black
        button.setButtonType(.momentaryPushIn)
        button.lineBreakMode = .byClipping
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = title
        nsView.font = AIMTheme.nsFont(size: fontSize, bold: bold)
        context.coordinator.items = items
        nsView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize {
        let font = AIMTheme.nsFont(size: fontSize, bold: bold)
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: ceil(textWidth) + 8, height: 18)
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    final class Coordinator: NSObject {
        var items: [(title: String, key: String, action: () -> Void)]
        private var retain: [ActionTarget] = []
        init(items: [(title: String, key: String, action: () -> Void)]) { self.items = items }

        @objc func pop(_ sender: NSButton) {
            let menu = NSMenu()
            menu.font = AIMTheme.nsFont(size: 12)
            menu.autoenablesItems = false
            retain.removeAll()
            for item in items {
                if item.title == "---" {
                    menu.addItem(.separator())
                    continue
                }
                let target = ActionTarget(item.action)
                retain.append(target)
                let menuItem = NSMenuItem(title: item.title, action: #selector(ActionTarget.run), keyEquivalent: item.key)
                menuItem.target = target
                menu.addItem(menuItem)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }
    }
}

final class ActionTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func run() { body() }
}
