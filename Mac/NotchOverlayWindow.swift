import SwiftUI
import AppKit

/// Click-through panel at the top-centre of the screen; hosts the notch pill.
final class NotchOverlayWindow: NSPanel {
    var onDrop: (([URL]) -> Void)?
    /// Only accept drops while an iPhone is connected.
    var dropEnabled = false
    private var monitors: [Any] = []
    private let model: NotchModel

    static var notchHeight: CGFloat {
        let h = (NSScreen.main ?? NSScreen.screens[0]).safeAreaInsets.top
        return h > 0 ? h : 32
    }

    init(model: NotchModel) {
        self.model = model
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
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let host = NSHostingView(rootView: NotchPillView(model: model, notchHeight: Self.notchHeight))
        host.frame = container.bounds; host.autoresizingMask = [.width, .height]
        let drop = FileDropView(frame: container.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onEnter = { [weak self] in self?.dragEntered() }
        drop.onExit = { [weak self] in self?.dragExited() }
        drop.onDrop = { [weak self] urls in self?.onDrop?(urls) }
        container.addSubview(host); container.addSubview(drop)
        contentView = container
        orderFrontRegardless()
        installDragMonitors()
    }
}

extension NotchOverlayWindow {
    /// The panel is click-through; it only captures the mouse while a file is being dragged near the top centre.
    fileprivate func installDragMonitors() {
        let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, self.dropEnabled else { return }
            let hasFile = NSPasteboard(name: .drag).canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            let inZone = self.frame.insetBy(dx: -40, dy: -40).contains(NSEvent.mouseLocation)
            self.ignoresMouseEvents = !(hasFile && inZone)
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.ignoresMouseEvents = true
        }
        monitors = [drag, up].compactMap { $0 }
    }

    fileprivate func dragEntered() {
        if dropEnabled { model.state = .dropTarget; NotchShareSound.play("Tink") }
    }
    fileprivate func dragExited() {
        if model.state == .dropTarget { model.state = .idle }
        ignoresMouseEvents = true
    }
}

enum NotchShareSound { static func play(_ n: String) { NSSound(named: NSSound.Name(n))?.play() } }

final class FileDropView: NSView {
    var onEnter: (() -> Void)?, onExit: (() -> Void)?, onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { onEnter?(); return .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { onExit?() }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                    options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls); return true
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

    private var accent: Color { (model.state == .ready || model.state == .dropTarget) ? .blue : .green }

    private var size: CGSize {
        switch model.state {
        case .idle: return CGSize(width: 190, height: notchHeight)
        case .ready, .dropTarget: return CGSize(width: 300, height: notchHeight + 46)
        case .sending, .transferring: return CGSize(width: 340, height: notchHeight + 58)
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
        case .dropTarget:
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.doc.fill").foregroundStyle(.blue)
                Text("Drop to send to iPhone").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
            }
        case .sending, .transferring:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: model.state == .sending ? "arrow.up.doc.fill" : "arrow.down.doc.fill")
                        .foregroundStyle(.green)
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
                Text(model.doneText).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }
}

private extension View {
    @ViewBuilder func symbolEffect(pulse: Bool) -> some View {
        if #available(macOS 14.0, *) { self.symbolEffect(.pulse, isActive: true) } else { self }
    }
}
