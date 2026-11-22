import SwiftUI
import AppKit
import MissionCore

/// A see-through, borderless panel that floats at the top-left of the screen, on every Space,
/// and never steals focus from the app you're using.
final class DrawerWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Dusk.tabWidth, height: Dusk.tabHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // Liquid Glass draws its own soft shadow; a window shadow would trace the text instead.
        hasShadow = false
        // Always the dark look, so the white text stays readable even when the Mac is in Light mode.
        appearance = NSAppearance(named: .darkAqua)
        // Note: setting isFloatingPanel also resets the level, so it must come first.
        isFloatingPanel = false
        level = DrawerWindow.desktopLevel
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    // Never takes the keyboard from the app you're typing in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Just above the desktop icons and below every app window, like a desktop widget.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
}

/// Hosting view that reports the pointer coming and going even when another app is in front,
/// and lets the first click land straight away.
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // One area that follows the view's size by itself (.inVisibleRect), made once.
        guard area == nil else { return }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onEnter()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onExit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Opens and closes the drawer, following DrawerLogic, and keeps the window the right size.
@MainActor
final class DrawerController: ObservableObject {
    @Published private(set) var showDrawer = false
    @Published private(set) var logic = DrawerLogic()
    /// Off: sits on the desktop behind your windows. On: floats over everything. Remembered between launches.
    @Published private(set) var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")

    private let model: DashboardModel
    private var window: DrawerWindow?
    private var host: HoverHostingView<RootView>?

    init(model: DashboardModel) {
        self.model = model
    }

    func install() {
        let w = DrawerWindow()
        let h = HoverHostingView(rootView: RootView(model: model, drawer: self))
        h.sizingOptions = []   // the controller decides the window size, not SwiftUI
        h.onEnter = { [weak self] in self?.handle { $0.pointerEntered() } }
        h.onExit = { [weak self] in self?.handle { $0.pointerExited() } }
        w.contentView = h
        window = w
        host = h
        place(size: CGSize(width: Dusk.tabWidth, height: Dusk.tabHeight))
        applyLevel()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        // Every second, double-check where the pointer is, in case the system missed an enter or exit.
        model.onTick = { [weak self] in self?.reconcilePointer() }
        reconcilePointer()
    }

    /// Is the pointer over the visible part of the widget right now?
    private func pointerIsInside() -> Bool {
        // Ignore the pointer when the widget isn't on screen (another Space, or a full-screen app).
        guard let window, window.isVisible, window.isOnActiveSpace else { return false }
        let mouse = NSEvent.mouseLocation
        var area = window.frame
        if !showDrawer {
            // While tucked away only the tab counts, even if the window hasn't shrunk yet.
            area = NSRect(x: area.minX, y: area.maxY - Dusk.tabHeight, width: Dusk.tabWidth, height: Dusk.tabHeight)
        }
        guard area.contains(mouse) else { return false }
        // On the desktop the widget can be covered by another window; only count it when it's really the one under the pointer.
        return NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == window.windowNumber
    }

    func reconcilePointer() {
        handle { $0.reconcile(pointerIsInside: pointerIsInside()) }
    }

    /// The open drawer grew or shrank (for example a calendar note appeared), so fit the window to it.
    func drawerHeightChanged(_ height: CGFloat) {
        guard height > 0, logic.expanded, showDrawer, let window else { return }
        let want = max(Dusk.tabHeight, ceil(height))
        guard abs(window.frame.height - want) > 0.5 else { return }
        place(size: CGSize(width: Dusk.drawerWidth, height: want))
    }

    func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
        applyLevel()
    }

    private func applyLevel() {
        guard let window else { return }
        // isFloatingPanel resets the level as a side effect, so set it first and the real level after.
        window.isFloatingPanel = alwaysOnTop
        window.level = alwaysOnTop ? .floating : DrawerWindow.desktopLevel
        window.orderFrontRegardless()
        reconcilePointer()
    }

    func togglePin() {
        handle { $0.togglePin() }
    }

    private func handle(_ change: (inout DrawerLogic) -> DrawerLogic.Action) {
        var l = logic
        let action = change(&l)
        logic = l
        switch action {
        case .none:
            break
        case .expand:
            place(size: drawerSize())
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { showDrawer = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.window?.invalidateShadow()
                self?.reconcilePointer()
            }
        case .scheduleCollapse(let delay):
            let g = logic.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.handle { $0.collapseTimerFired(generation: g) }
            }
        case .collapse:
            withAnimation(.easeIn(duration: 0.22)) { showDrawer = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                guard let self, !self.logic.expanded else { return }
                self.place(size: CGSize(width: Dusk.tabWidth, height: Dusk.tabHeight))
                self.window?.invalidateShadow()
                self.reconcilePointer()
            }
        }
    }

    private func drawerSize() -> CGSize {
        let probe = NSHostingView(rootView: DrawerPanelView(model: model, animate: false))
        let fit = probe.fittingSize
        return CGSize(width: Dusk.drawerWidth, height: max(Dusk.tabHeight, ceil(fit.height)))
    }

    private func reposition() {
        let size = logic.expanded ? drawerSize() : CGSize(width: Dusk.tabWidth, height: Dusk.tabHeight)
        place(size: size)
        reconcilePointer()
    }

    /// Top-left of the main screen, just under the menu bar.
    private func place(size: CGSize) {
        guard let window else { return }
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let frame = NSRect(x: vf.minX, y: vf.maxY - Dusk.topGap - size.height, width: size.width, height: size.height)
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }
}
