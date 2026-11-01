import SwiftUI
import AppKit

/// Transparent, click-through panel at the top-centre of the screen (the notch area).
final class NotchOverlayWindow: NSPanel {
    init(model: NotchModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w: CGFloat = 240, h: CGFloat = 44
        let frame = CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: NotchGlowView(model: model))
        orderFrontRegardless()
    }
}

struct NotchGlowView: View {
    @ObservedObject var model: NotchModel
    @State private var pulse = false

    private var color: Color { model.state == .ready ? .blue : .green }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color, lineWidth: 2))
                .shadow(color: color, radius: 10)
                .opacity(model.state == .ready ? (pulse ? 1 : 0.25) : (model.state == .idle ? 0 : 1))
            if model.state == .transferring {
                Text(model.fileName).font(.caption2).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 12)
            }
        }
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
        .animation(.easeOut(duration: 0.8), value: model.state)
        .onAppear { pulse = true }
    }
}
