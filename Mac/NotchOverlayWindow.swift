import SwiftUI
import AppKit

/// Click-through panel at the top-centre of the screen; hosts the notch pill.
final class NotchOverlayWindow: NSPanel {
    static var notchHeight: CGFloat {
        let h = (NSScreen.main ?? NSScreen.screens[0]).safeAreaInsets.top
        return h > 0 ? h : 32
    }

    init(model: NotchModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w: CGFloat = 400, h: CGFloat = Self.notchHeight + 90
        let frame = CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: NotchPillView(model: model, notchHeight: Self.notchHeight))
        orderFrontRegardless()
    }
}

/// Black pill with rounded bottom corners so it looks like the notch growing downward.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct NotchPillView: View {
    @ObservedObject var model: NotchModel
    let notchHeight: CGFloat
    @State private var pulse = false

    private var accent: Color { model.state == .ready ? .blue : .green }

    private var size: CGSize {
        switch model.state {
        case .idle: return CGSize(width: 190, height: notchHeight)
        case .ready: return CGSize(width: 300, height: notchHeight + 46)
        case .transferring: return CGSize(width: 340, height: notchHeight + 58)
        case .done: return CGSize(width: 260, height: notchHeight + 46)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                NotchShape(radius: model.state == .idle ? 10 : 22)
                    .fill(.black)
                    .overlay(NotchShape(radius: model.state == .idle ? 10 : 22)
                        .stroke(accent.opacity(model.state == .idle ? 0 : (pulse ? 0.9 : 0.3)), lineWidth: 1.5))
                    .shadow(color: accent.opacity(model.state == .idle ? 0 : 0.6), radius: pulse ? 14 : 6)
                content.padding(.bottom, 10).padding(.horizontal, 18)
                    .opacity(model.state == .idle ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: model.state)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .ready:
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .foregroundStyle(.blue).symbolEffect(pulse: pulse)
                Text("iPhone nearby").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("Tap Send").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        case .transferring:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.doc.fill").foregroundStyle(.green)
                    Text(model.fileName).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text("\(Int(model.progress * 100))%").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                ProgressView(value: model.progress).tint(.green)
            }
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                Text("Received").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }
}

private extension View {
    @ViewBuilder func symbolEffect(pulse: Bool) -> some View {
        if #available(macOS 14.0, *) { self.symbolEffect(.pulse, isActive: true) } else { self }
    }
}
