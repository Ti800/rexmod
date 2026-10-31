import AppKit
import SwiftUI

private enum Palette {
    static let added = Color(red: 0.25, green: 0.85, blue: 0.55)
    static let modified = Color(red: 1.0, green: 0.68, blue: 0.10)
    static let deleted = Color(red: 1.0, green: 0.30, blue: 0.40)
    static let renamed = Color(red: 0.20, green: 0.85, blue: 1.0)
    static let accent = Color(red: 0.73, green: 0.0, blue: 1.0)

    static func status(_ s: String) -> Color {
        switch s {
        case "A": return added
        case "M", "T": return modified
        case "D": return deleted
        case "R": return renamed
        default: return .secondary
        }
    }
}

private func fileIcon(_ name: String) -> (String, Color) {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "go": return ("chevron.left.forwardslash.chevron.right", Color(red: 0.3, green: 0.8, blue: 0.95))
    case "swift": return ("swift", Color(red: 1.0, green: 0.45, blue: 0.2))
    case "ts", "tsx": return ("curlybraces", Color(red: 0.3, green: 0.6, blue: 1.0))
    case "js", "jsx", "mjs", "cjs": return ("curlybraces", Color(red: 0.95, green: 0.85, blue: 0.3))
    case "json", "jsonc": return ("curlybraces.square", Color(red: 0.95, green: 0.75, blue: 0.3))
    case "md", "mdx", "txt": return ("doc.text", .secondary)
    case "py": return ("chevron.left.forwardslash.chevron.right", Color(red: 0.4, green: 0.65, blue: 1.0))
    case "rs": return ("gearshape", Color(red: 0.9, green: 0.5, blue: 0.3))
    case "lua": return ("moon", Color(red: 0.4, green: 0.5, blue: 1.0))
    case "sh", "fish", "zsh", "bash": return ("terminal", Color(red: 0.5, green: 0.85, blue: 0.5))
    case "yml", "yaml", "toml", "ini", "conf": return ("slider.horizontal.3", .secondary)
    case "png", "jpg", "jpeg", "gif", "svg", "webp", "icns", "ico": return ("photo", Color(red: 0.8, green: 0.5, blue: 0.9))
    case "css", "scss": return ("paintbrush", Color(red: 0.4, green: 0.7, blue: 1.0))
    case "html", "htm": return ("globe", Color(red: 1.0, green: 0.55, blue: 0.3))
    case "kt", "kts", "gradle", "java": return ("cup.and.saucer", Color(red: 0.7, green: 0.5, blue: 1.0))
    case "lock", "sum": return ("lock", .secondary)
    default: return ("doc", .secondary)
    }
}

// MARK: - Building blocks

private func hexColor(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

/// Rex's icon button looks, measured on screen.
struct RexIconStyle {
    var rest: NSColor
    var restInactive: NSColor
    var hover: NSColor
    var circle: NSColor

    /// Sidebar header icons (ChromeIconButton): white at 0.7, white on a
    /// #313132 circle (over #161619) when hovered.
    static let sidebar = RexIconStyle(rest: NSColor.white.withAlphaComponent(0.7), restInactive: NSColor.white.withAlphaComponent(0.7),
                                      hover: .white, circle: NSColor.white.withAlphaComponent(0.084))
    /// Pane title actions (split, float, zoom, close): #7d7d7e at rest
    /// (#5d5d5d in an inactive window), #a1a1a3 on a #2d2d2f circle hovered.
    static let paneAction = RexIconStyle(rest: hexColor(0x7d7d7e), restInactive: hexColor(0x5d5d5d),
                                         hover: hexColor(0xa1a1a3), circle: hexColor(0x2d2d2f))
}

/// Rex's shortcut tip: a dark rounded box under the button with the title
/// and a key cap (e.g. "Split Right  ⌘D"), measured from Rex.
final class RexTip {
    static let shared = RexTip()
    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?

    func show(title: String, shortcut: String?, below anchor: NSView) {
        hide()
        guard let window = anchor.window else { return }
        let text = NSTextField(labelWithString: title)
        text.font = .systemFont(ofSize: 12.5)
        text.textColor = hexColor(0x939393)
        text.sizeToFit()
        var width = 12 + text.frame.width + 12
        let height: CGFloat = 28
        var cap: NSView?
        if let shortcut = shortcut {
            let k = NSTextField(labelWithString: shortcut)
            k.font = .systemFont(ofSize: 11.5)
            k.textColor = hexColor(0x939393)
            k.sizeToFit()
            let box = NSView(frame: NSRect(x: 0, y: 0, width: k.frame.width + 10, height: 18))
            box.wantsLayer = true
            box.layer?.cornerRadius = 5
            box.layer?.cornerCurve = .continuous
            box.layer?.borderWidth = 1
            box.layer?.borderColor = hexColor(0x4f4f4f).cgColor
            k.frame.origin = NSPoint(x: 5, y: (18 - k.frame.height) / 2)
            box.addSubview(k)
            cap = box
            width = 12 + text.frame.width + 9 + box.frame.width + 7
        }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = hexColor(0x212121).cgColor
        content.layer?.cornerRadius = 10
        content.layer?.cornerCurve = .continuous
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = hexColor(0x4f4f50).cgColor
        text.frame.origin = NSPoint(x: 12, y: (height - text.frame.height) / 2)
        content.addSubview(text)
        if let cap = cap {
            cap.frame.origin = NSPoint(x: width - 7 - cap.frame.width, y: (height - cap.frame.height) / 2)
            content.addSubview(cap)
        }
        let a = anchor.convert(anchor.bounds, to: nil)
        let screenRect = window.convertToScreen(a)
        // Centred under the button, but kept inside the window (the toggle is
        // the rightmost control, so a centred tip would hang past the edge).
        var limits = window.frame.insetBy(dx: 8, dy: 0)
        if let visible = window.screen?.visibleFrame { limits = limits.intersection(visible.insetBy(dx: 4, dy: 0)) }
        var x = screenRect.midX - width / 2
        if !limits.isEmpty { x = max(limits.minX, min(x, limits.maxX - width)) }
        let frame = NSRect(x: x, y: screenRect.minY - 5 - height, width: width, height: height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.contentView = content
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        parentWindow = window
    }

    func hide() {
        if let p = panel {
            parentWindow?.removeChildWindow(p)
            p.orderOut(nil)
        }
        panel = nil
    }
}

/// An icon button with Rex's look (one of RexIconStyle) and Rex's tip.
final class RexStyleIconButton: NSButton {
    var style = RexIconStyle.sidebar { didSet { updateLook() } }
    var tipTitle: String?
    var tipShortcut: String?

    private let circle = CALayer()
    private var tracking: NSTrackingArea?
    private var tipTimer: Timer?
    private var hovered = false { didSet { updateLook() } }
    private var keyObservers: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        wantsLayer = true
        circle.cornerCurve = .continuous
        layer?.insertSublayer(circle, at: 0)
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: frame.width, height: frame.width) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.frame = bounds
        circle.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let w = window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                self?.updateLook()
            })
        }
        updateLook()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        tipTimer?.invalidate()
        if let title = tipTitle {
            tipTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self = self, self.hovered else { return }
                RexTip.shared.show(title: title, shortcut: self.tipShortcut, below: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        tipTimer?.invalidate()
        RexTip.shared.hide()
    }

    override func mouseDown(with event: NSEvent) {
        tipTimer?.invalidate()
        RexTip.shared.hide()
        super.mouseDown(with: event)
    }

    private func updateLook() {
        let active = window?.isKeyWindow ?? true
        contentTintColor = hovered ? style.hover : (active ? style.rest : style.restInactive)
        circle.backgroundColor = hovered ? style.circle.cgColor : nil
    }
}

/// Rex's own chrome icon button (the eye, ⌘ and + of its sidebar header), so
/// size, tint and hover are Rex's. Falls back to a borderless NSButton.
enum RexChrome {
    // Rex's ChromeIconButton traps in -initWithFrame: (Rex builds it with its
    // own Swift initializer), so the look is reproduced in RexStyleIconButton.
    static func makeIconButton(symbol: String, help: String, size: CGFloat, shortcut: String? = nil) -> NSButton {
        let b = RexStyleIconButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        b.tipTitle = help
        b.tipShortcut = shortcut
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        return b
    }
}

struct RexIconButton: NSViewRepresentable {
    let symbol: String
    let help: String
    var shortcut: String? = nil
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action) }

    func makeNSView(context: Context) -> NSButton {
        let b = RexChrome.makeIconButton(symbol: symbol, help: help, size: 28, shortcut: shortcut)
        b.target = context.coordinator
        b.action = #selector(Coordinator.fire)
        return b
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }

    func updateNSView(_ b: NSButton, context: Context) {
        context.coordinator.action = action
    }
}

/// Rex's selection and hover look for sidebar rows and tabs: the selected item
/// sits on a regular Liquid Glass capsule (NSGlassEffectView, radius 15, no
/// tint), a hovered one on a faint capsule.
struct RexItemBackground: ViewModifier {
    let selected: Bool
    let hover: Bool

    func body(content: Content) -> some View {
        content.background {
            if selected {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(Color.primary.opacity(0.12))
                }
            } else if hover {
                Capsule().fill(Color.primary.opacity(0.06))
            }
        }
    }
}

extension View {
    func rexItemBackground(selected: Bool, hover: Bool) -> some View {
        modifier(RexItemBackground(selected: selected, hover: hover))
    }
}

struct Pills: View {
    let items: [(id: String, title: String)]
    @Binding var selection: String
    var fill = false
    var framed = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                PillButton(title: item.title, selected: item.id == selection, fill: fill) { selection = item.id }
            }
        }
    }
}

private struct PillButton: View {
    let title: String
    let selected: Bool
    let fill: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .frame(maxWidth: fill ? .infinity : nil)
                .rexItemBackground(selected: selected, hover: hover)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .rotationEffect(.degrees(spinning ? 180 : 0))
                .animation(spinning ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

struct RowView: View {
    let row: TreeRow
    @ObservedObject var model: PanelModel
    let isOpen: Bool
    let showPath: Bool
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let n = row.node
        let deleted = n.change?.status == "D"
        HStack(spacing: 6) {
            if row.depth > 0 { Spacer().frame(width: CGFloat(row.depth) * 12) }
            if n.isDir {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                if let img = FlowIcons.shared.folder(n.name, open: isOpen, dark: scheme == .dark) {
                    Image(nsImage: img).resizable().interpolation(.high).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .frame(width: 16)
                }
                Text(n.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Spacer().frame(width: 10)
                let base = String(n.name.split(separator: "/").last ?? Substring(n.name))
                if let img = FlowIcons.shared.file(base, dark: scheme == .dark) {
                    Image(nsImage: img).resizable().interpolation(.high).frame(width: 16, height: 16)
                } else {
                    let icon = fileIcon(n.name)
                    Image(systemName: icon.0)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(icon.1)
                        .frame(width: 16)
                }
                if showPath, let slash = n.name.lastIndex(of: "/") {
                    (Text(String(n.name[n.name.index(after: slash)...])).foregroundColor(.primary)
                        + Text("  " + String(n.name[..<slash])).foregroundColor(.secondary))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(n.name)
                        .font(.system(size: 13))
                        .foregroundStyle(deleted ? Color.secondary : Color.primary)
                        .strikethrough(deleted, color: .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if let c = n.change {
                if hover && !(c.binary ?? false) && (c.add > 0 || c.del > 0) {
                    HStack(spacing: 4) {
                        if c.add > 0 { Text("+\(c.add)").foregroundStyle(Palette.added) }
                        if c.del > 0 { Text("−\(c.del)").foregroundStyle(Palette.deleted) }
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
                Text(c.status)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.status(c.status))
                    .frame(width: 12)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 24)
        .rexItemBackground(selected: model.selected == n.id && !n.isDir, hover: hover)
        .background(alignment: .leading) {
            // Indent guides: one line per level, through the chevron column.
            ZStack(alignment: .leading) {
                ForEach(0..<row.depth, id: \.self) { level in
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                        .offset(x: 6 + 5 + CGFloat(level) * 12)
                }
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if n.isDir { model.toggleFolder(n.id) } else if !deleted { model.open(n.id) }
        }
        // One element per row for VoiceOver (and automation), acting like the tap.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.isDir ? "\(n.name) folder" : n.id)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if n.isDir { model.toggleFolder(n.id) } else if !deleted { model.open(n.id) }
        }
        .help(n.change.map { c in
            c.oldPath.map { "\($0) → \(n.id)" } ?? "\(n.id)  +\(c.add) −\(c.del)"
        } ?? n.id)
        .contextMenu {
            if !n.isDir && !deleted {
                Button("Open in Editor") { model.open(n.id) }
            }
            Button("Copy Relative Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(n.id, forType: .string)
            }
            if let repo = model.target?.repo {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo + "/" + n.id)])
                }
            }
        }
    }
}

// MARK: - Empty states

struct EmptyAction {
    let title: String
    var shortcut: String?
    let run: () -> Void
}

/// A centred glass tile with a symbol, a title, one line of help and an
/// optional action, in Rex's type scale.
struct EmptyState: View {
    let symbol: String?
    let title: String
    let message: String?
    var action: EmptyAction?
    var pulse = false
    @State private var hover = false
    @State private var dim = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if #available(macOS 26.0, *) {
                    Color.clear.frame(width: 46, height: 46)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.07)).frame(width: 46, height: 46)
                }
                if let symbol = symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.secondary)
                        .opacity(pulse && dim ? 0.35 : 1)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let message = message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let action = action {
                Button(action: action.run) {
                    HStack(spacing: 6) {
                        Text(action.title).font(.system(size: 12.5))
                        if let k = action.shortcut {
                            Text(k).font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .rexItemBackground(selected: true, hover: false)
                    .opacity(hover ? 1 : 0.9)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: 236)
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .onAppear {
            if pulse { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true } }
        }
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var topInset: CGFloat
    var onHide: () -> Void

    var body: some View {
        if model.panelVisible { full } else { Color.clear }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: 50)
            if model.tab == .changes { changes } else { filesView }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    /// Mirrors Rex's sidebar header: 28pt icon buttons, 2pt apart, 10pt from
    /// the edge, centred 25pt below the top like the title row.
    private var header: some View {
        HStack(spacing: 2) {
            Pills(items: [("changes", "Changes"), ("files", "Files")],
                  selection: Binding(get: { model.tab.rawValue },
                                     set: { model.tab = PanelTab(rawValue: $0) ?? .changes }))
            Spacer()
            if let n = model.state?.pendingComments, n > 0 {
                Button { model.sendComments() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "text.bubble.fill").font(.system(size: 11))
                        Text("\(n)").font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Send \(n) pending review comment\(n == 1 ? "" : "s") to \(model.agentName)")
                .accessibilityLabel("Send \(n) pending review comment\(n == 1 ? "" : "s")")
                .padding(.trailing, 4)
            }
            RexIconButton(symbol: "magnifyingglass", help: "Find File", shortcut: "⌘P") { model.openPicker() }
                .frame(width: 28, height: 28)
            RexIconButton(symbol: "arrow.clockwise", help: "Refresh") {
                model.refresh(reason: "button")
                if model.tab == .files { model.refreshFiles() }
            }
            .frame(width: 28, height: 28)
            RexIconButton(symbol: "sidebar.right", help: "Hide Changes Panel", shortcut: "⌘⇧E", action: onHide)
                .frame(width: 28, height: 28)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
    }

    @ViewBuilder private var repoLine: some View {
        if let t = model.target, let repo = t.repoName {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 10.5))
                Text(t.branch ?? "").font(.system(size: 11.5, weight: .medium))
                Text("·").foregroundStyle(.tertiary)
                Text(repo).font(.system(size: 11.5))
                if let agent = t.agent {
                    Spacer()
                    agentBadge(t, agent: agent)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// The agent the panel follows. With more than one agent in the tab it
    /// is a menu: picking one focuses that pane and the panel follows it.
    @ViewBuilder private func agentBadge(_ t: TargetDTO, agent: String) -> some View {
        let agents = t.agents ?? []
        let current = agents.first { $0.blockId == t.agentBlockId }?.name ?? agent
        let label = HStack(spacing: 2) {
            Text(current).font(.system(size: 10, weight: .semibold))
            if agents.count > 1 {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        if agents.count > 1 {
            Menu {
                ForEach(agents) { a in
                    Button { model.follow(a.blockId) } label: {
                        if a.blockId == t.agentBlockId { Label(a.name, systemImage: "checkmark") } else { Text(a.name) }
                    }
                }
            } label: { label }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Following \(current). The panel follows the agent you focused last; pick another here.")
        } else {
            label.help("Following the \(agent) pane of this tab")
        }
    }

    @ViewBuilder private var changes: some View {
        if model.target?.repo == nil {
            noRepoState
        } else {
            Pills(items: changeModes, selection: $model.mode, fill: true)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            summary
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            let rows = model.changeRows()
            if rows.isEmpty {
                noChangesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            RowView(row: r, model: model, isOpen: !model.collapsed.contains(r.id), showPath: false)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder private var summary: some View {
        if let c = model.currentChanges, !c.files.isEmpty {
            HStack(spacing: 6) {
                Text("\(c.files.count) file\(c.files.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                if c.add > 0 { Text("+\(c.add)").foregroundStyle(Palette.added) }
                if c.del > 0 { Text("−\(c.del)").foregroundStyle(Palette.deleted) }
                Spacer()
                if c.mode == "last-turn", c.running == true {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        Text("in progress")
                    }
                    .foregroundStyle(.secondary)
                    .help("\(model.agentName) is working; changes since the turn started")
                } else if c.mode == "branch", let ref = c.baseRef {
                    Text("vs \(ref)").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 11.5))
        }
    }

    @ViewBuilder private var filesView: some View {
        if model.target?.repo == nil {
            noRepoState
        } else {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Filter files", text: $model.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !model.filter.isEmpty {
                    Button { model.filter = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            let rows = model.fileRows()
            if rows.isEmpty {
                if model.files.isEmpty {
                    EmptyState(symbol: nil, title: "Loading files…", message: nil)
                } else {
                    EmptyState(symbol: "magnifyingglass", title: "No matches",
                               message: "Nothing in this repository matches “\(model.filter)”.",
                               action: EmptyAction(title: "Clear filter") { model.filter = "" })
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            RowView(row: r, model: model, isOpen: model.expandedFiles.contains(r.id),
                                    showPath: !model.filter.isEmpty)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// The bottom line: branch and repo, or a message for a few seconds.
    @ViewBuilder private var footer: some View {
        Group {
            if let f = model.flash {
                Text(f)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                repoLine
            }
        }
        // The branch glyph lines up with the left edge of the tab pills.
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var noRepoState: some View {
        if model.state == nil {
            EmptyState(symbol: nil, title: "Loading…", message: nil)
        } else if let err = model.state?.error {
            EmptyState(symbol: "rectangle.dashed", title: "Nothing to follow", message: err)
        } else {
            EmptyState(symbol: "folder.badge.questionmark", title: "No repository in this tab",
                       message: "The panel follows this tab's coding agent (Claude Code, Codex, OpenCode or Pi). Start one inside a git repository, or cd into one here.")
        }
    }

    @ViewBuilder private var noChangesState: some View {
        let c = model.currentChanges
        let branch = model.target?.branch ?? "this branch"
        let find = EmptyAction(title: "Find a file", shortcut: "⌘P") { model.openPicker() }
        switch c?.mode {
        case "last-turn" where c?.base == nil:
            EmptyState(symbol: "sparkles", title: "No turn yet",
                       message: "Files \(model.agentName) touches in its next turn show up here. This needs the rexmod hooks (scripts/install-hooks.sh).")
        case "last-turn" where c?.running == true:
            EmptyState(symbol: "ellipsis.circle", title: "\(model.agentName) is working",
                       message: "Nothing has changed in this turn yet.", pulse: true)
        case "last-turn":
            EmptyState(symbol: "checkmark.circle", title: "Last turn changed nothing",
                       message: "\(model.agentName)'s last reply didn't touch any files.", action: find)
        case "branch":
            EmptyState(symbol: "arrow.triangle.branch", title: "Nothing new on this branch",
                       message: "\(branch) has no changes against \(c?.baseRef ?? "its base").", action: find)
        default:
            EmptyState(symbol: "checkmark.seal", title: "Working tree is clean",
                       message: "No uncommitted changes on \(branch).", action: find)
        }
    }
}
