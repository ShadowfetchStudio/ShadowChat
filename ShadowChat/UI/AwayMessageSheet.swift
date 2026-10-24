import SwiftUI

/// The classic "Away Message" dialog: pick a saved message or write a new one, then click I'm Away.
struct AwayMessageSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var label = ""
    @State private var message = ""
    @State private var saveForLater = true

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(title: "Away Message", showWindowControls: false) {
                ClassicDialog.close("Away Message")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AwayNoteIcon()
                        .frame(width: 28, height: 28)
                    Text("Let everyone know you stepped away. Your helpers keep chatting, and sending any message sets you back to Available.")
                        .font(AIMTheme.font(size: 11))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved messages")
                        .font(AIMTheme.font(size: 11, bold: true))
                        .foregroundStyle(.black)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.awayPresets) { preset in
                                let picked = preset.label == label
                                HStack(spacing: 6) {
                                    AwayNoteIcon().frame(width: 11, height: 11)
                                    Text(preset.label)
                                        .font(AIMTheme.font(size: 11.5, bold: picked))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundStyle(picked ? Color.white : Color.black)
                                .background(picked ? AIMTheme.highlight : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    model.goAway(preset.message)
                                    ClassicDialog.close("Away Message")
                                }
                                .onTapGesture {
                                    label = preset.label
                                    message = preset.message
                                }
                                .contextMenu {
                                    Button("Delete \(preset.label)") { model.deleteAwayPreset(label: preset.label) }
                                }
                            }
                        }
                    }
                    .frame(height: 92)
                    .background(Color.white)
                    .overlay(BevelOverlay(raised: false))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Label")
                        .font(AIMTheme.font(size: 11, bold: true))
                        .foregroundStyle(.black)
                    TextField("Be Right Back", text: $label)
                        .textFieldStyle(.plain)
                        .font(AIMTheme.font(size: 12))
                        .foregroundStyle(.black)
                        .padding(5)
                        .background(Color.white)
                        .overlay(BevelOverlay(raised: false))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Away message")
                        .font(AIMTheme.font(size: 11, bold: true))
                        .foregroundStyle(.black)
                    TextEditor(text: $message)
                        .font(AIMTheme.font(size: 12))
                        .foregroundStyle(.black)
                        .scrollContentBackground(.hidden)
                        .padding(3)
                        .frame(height: 64)
                        .background(Color.white)
                        .overlay(BevelOverlay(raised: false))
                    Text("Special codes: %n = your screen name · %t = time · %d = date")
                        .font(AIMTheme.font(size: 9.5))
                        .foregroundStyle(.black.opacity(0.7))
                    if !message.isEmpty {
                        Text("Preview: \(AwayPreset.expand(message, screenName: model.screenName))")
                            .font(AIMTheme.font(size: 10.5))
                            .italic()
                            .foregroundStyle(.black.opacity(0.85))
                            .lineLimit(2)
                    }
                }

                Toggle("Save for later use", isOn: $saveForLater)
                    .toggleStyle(.checkbox)
                    .font(AIMTheme.font(size: 11))
                    .foregroundStyle(.black)

                HStack(spacing: 8) {
                    if model.isAway {
                        Button("I'm Back") {
                            model.comeBack()
                            ClassicDialog.close("Away Message")
                        }
                        .buttonStyle(AIMButtonStyle())
                    }
                    Spacer()
                    Button("Cancel") { ClassicDialog.close("Away Message") }
                        .buttonStyle(AIMButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("I'm Away") {
                        if saveForLater { model.saveAwayPreset(label: label, message: message) }
                        model.goAway(message)
                        ClassicDialog.close("Away Message")
                    }
                    .buttonStyle(AIMButtonStyle(sunken: false))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .background(AIMTheme.client)
            .padding(4)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(AIMTheme.frameBlue)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(WindowConfigurator(title: "Away Message", dialog: true).frame(width: 0, height: 0))
        .preferredColorScheme(.light)
        .onDisappear { model.showingAwaySheet = false }
        .onAppear {
            if let current = model.awayMessage {
                message = current
                label = model.awayPresets.first(where: { $0.message == current })?.label ?? ""
            } else if let first = model.awayPresets.first {
                label = first.label
                message = first.message
            }
        }
    }
}

/// A little yellow sticky note, the universal "this buddy is away" mark.
struct AwayNoteIcon: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    let fold = side * 0.28
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: side, y: 0))
                    path.addLine(to: CGPoint(x: side, y: side - fold))
                    path.addLine(to: CGPoint(x: side - fold, y: side))
                    path.addLine(to: CGPoint(x: 0, y: side))
                    path.closeSubpath()
                }
                .fill(Color(red: 1.0, green: 0.90, blue: 0.35))
                Path { path in
                    let fold = side * 0.28
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: side, y: 0))
                    path.addLine(to: CGPoint(x: side, y: side - fold))
                    path.addLine(to: CGPoint(x: side - fold, y: side))
                    path.addLine(to: CGPoint(x: 0, y: side))
                    path.closeSubpath()
                    for row in 1...3 {
                        let y = side * CGFloat(row) * 0.22
                        path.move(to: CGPoint(x: side * 0.18, y: y))
                        path.addLine(to: CGPoint(x: side * 0.78, y: y))
                    }
                }
                .stroke(Color(red: 0.55, green: 0.42, blue: 0.05), lineWidth: max(0.8, side / 14))
            }
            .frame(width: side, height: side)
        }
    }
}

/// An open or closed door, shown beside a buddy who just signed on or off.
struct DoorIcon: View {
    var open: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.30, green: 0.20, blue: 0.10))
                .frame(width: 9, height: 12)
            if open {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.93, blue: 0.55))
                    .frame(width: 7, height: 10)
                    .offset(x: 1)
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 1))
                    path.addLine(to: CGPoint(x: 5, y: 2.5))
                    path.addLine(to: CGPoint(x: 5, y: 12.5))
                    path.addLine(to: CGPoint(x: 1, y: 11))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.62, green: 0.38, blue: 0.16))
            } else {
                Rectangle()
                    .fill(Color(red: 0.62, green: 0.38, blue: 0.16))
                    .frame(width: 7, height: 10)
                    .offset(x: 1)
                Circle()
                    .fill(Color(red: 0.95, green: 0.80, blue: 0.25))
                    .frame(width: 2, height: 2)
                    .offset(x: 6)
            }
        }
        .frame(width: 10, height: 12)
    }
}
