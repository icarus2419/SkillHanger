import Foundation

/// Tracks the finger in points and decides whether release closes, reveals, or commits.
struct InstalledRowSwipe {
    enum Axis { case undecided, horizontal, vertical }
    static let actionWidth: CGFloat = 72
    static let fullSwipeThreshold: CGFloat = 152
    let initiallyOpen: Bool
    private(set) var axis: Axis = .undecided
    private var translation: CGFloat = 0

    init(initiallyOpen: Bool) { self.initiallyOpen = initiallyOpen }

    var offset: CGFloat {
        let start = initiallyOpen ? -Self.actionWidth : 0
        return min(0, start + (axis == .horizontal ? translation : 0))
    }

    mutating func update(translation: CGSize) -> Bool {
        guard translation.width.isFinite, translation.height.isFinite else { return false }
        if axis == .undecided {
            guard translation.width != 0 || translation.height != 0 else { return false }
            axis = abs(translation.width) > abs(translation.height) * 1.25 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return false }
        self.translation = translation.width
        return true
    }

    func finish(cancelled: Bool = false) -> Bool {
        guard !cancelled, axis == .horizontal else { return initiallyOpen }
        if commitsFullSwipe() { return false }
        return offset <= -Self.actionWidth / 2
    }

    func commitsFullSwipe(cancelled: Bool = false) -> Bool {
        !cancelled && axis == .horizontal && offset <= -Self.fullSwipeThreshold
    }
}
