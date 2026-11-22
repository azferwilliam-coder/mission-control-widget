import Foundation

/// A point on the pulse line (kept free of CoreGraphics so it tests anywhere).
public struct PulsePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum Pulse {
    /// The heartbeat line. Busier Mac → taller beats. Always stays inside the box.
    public static func heartbeat(width: Double, height: Double, load: Double) -> [PulsePoint] {
        let l = min(1, max(0, load.isFinite ? load : 0))
        let amp = 0.25 + 0.75 * l
        let base = height * 0.6
        // Shape taken from the approved mockup (252 × 80 box), as x fraction and y offset fraction.
        let shape: [(Double, Double)] = [
            (0, 0), (40, 0), (52, -4), (60, 0), (92, 0), (100, -28), (108, 22), (116, -14), (124, 0),
            (160, 0), (170, -8), (178, 0), (212, 0), (220, -22), (228, 12), (236, 0), (252, 0),
        ]
        return shape.map { p in
            let x = p.0 / 252 * width
            let dy = p.1 / 80 * height * amp
            let y = min(height - 1, max(1, base + dy))
            return PulsePoint(x: x, y: y)
        }
    }
}

/// Decides when the drawer opens and closes. The window code just follows its answers.
public struct DrawerLogic: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case expand
        case scheduleCollapse(after: TimeInterval)
        case collapse
    }

    public static let collapseDelay: TimeInterval = 0.6

    public private(set) var expanded = false
    public private(set) var pinned = false
    public private(set) var pointerInside = false
    /// Bumped on every pointer change, so a late timer from an earlier exit can be ignored.
    public private(set) var generation = 0

    public init() {}

    public mutating func pointerEntered() -> Action {
        pointerInside = true
        generation += 1
        if expanded { return .none }
        expanded = true
        return .expand
    }

    public mutating func pointerExited() -> Action {
        pointerInside = false
        generation += 1
        guard expanded, !pinned else { return .none }
        return .scheduleCollapse(after: DrawerLogic.collapseDelay)
    }

    /// The timer set by pointerExited. Only acts if nothing has happened since.
    public mutating func collapseTimerFired(generation g: Int) -> Action {
        guard g == generation, expanded, !pinned, !pointerInside else { return .none }
        expanded = false
        return .collapse
    }

    /// A safety net run every second: compares against where the pointer really is, in case the
    /// system missed an enter or exit (fast flicks, menus, Space switches, launching under the pointer).
    public mutating func reconcile(pointerIsInside inside: Bool) -> Action {
        guard inside != pointerInside else { return .none }
        return inside ? pointerEntered() : pointerExited()
    }

    /// The drawer's pin keeps it open until clicked again.
    public mutating func togglePin() -> Action {
        pinned.toggle()
        if pinned {
            if expanded { return .none }
            expanded = true
            return .expand
        }
        if !pointerInside, expanded {
            expanded = false
            return .collapse
        }
        return .none
    }
}
