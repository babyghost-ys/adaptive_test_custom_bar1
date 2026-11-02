import UIKit

/// Holds a layer still for the first half of a screen turn and moves it to
/// its final state in one step at the half-way point.
///
/// On iOS 26+ a rotation lays a picture of the old screen over the new layout
/// and fades it out over the first frames of the turn. The picture is
/// invisible wherever what lies under it is the same pixels and shows as a
/// cut wherever it is not. UIKit animates every view towards its new frame
/// from the first frame, while Flutter keeps its old frame until half way
/// through the turn and then draws the new one. Pausing the layer that holds
/// a window's content keeps UIKit's views where the picture shows them while
/// it fades; running the paused animations to their end at the half-way
/// point moves them together with Flutter's new layout. Nothing is hidden,
/// copied or covered, and only the layer clock is touched.
final class TurnHold {
    /// Lag after Flutter's half-way redraw before the snap: the new frame
    /// reaches the screen a frame or two after the engine takes the new size.
    private static let snapLag: TimeInterval = 1.0 / 30

    /// Without a coordinator the hold ends this long after it began, so a
    /// layer can never stay paused (a turn takes about 0.4 s).
    private static let fallback: TimeInterval = 0.5

    private let layer: () -> CALayer?
    /// How far the layer clock has been run ahead to finish paused
    /// animations at once; its `timeOffset` between turns. Moved ahead, never
    /// reset, so nothing added to the layer since is disturbed.
    private var clockOffset: CFTimeInterval = 0
    private(set) var holding = false
    private var snapScheduled = false
    private var fallbackWork: DispatchWorkItem?

    init(layer: @escaping () -> CALayer?) {
        self.layer = layer
    }

    /// Pauses the layer unless it is paused already. Must run before UIKit
    /// adds the turn's animations: a controller's `viewWillTransition`, or
    /// earlier, a window's frame setter. With a coordinator the snap is
    /// scheduled from its duration (half way, plus a frame) and again from
    /// its completion; without one the fallback ends the hold.
    func hold(coordinator: UIViewControllerTransitionCoordinator?) {
        guard let layer = layer() else { return }
        if !holding {
            holding = true
            snapScheduled = false
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
            let work = DispatchWorkItem { [weak self] in self?.snap(duration: Self.fallback) }
            fallbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallback, execute: work)
        }
        guard let coordinator, !snapScheduled else { return }
        let duration = coordinator.transitionDuration
        guard duration > 0 else {
            snap(duration: 0)
            return
        }
        snapScheduled = true
        fallbackWork?.cancel()
        fallbackWork = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2 + Self.snapLag) { [weak self] in
            self?.snap(duration: duration)
        }
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.snap(duration: duration)
        }
    }

    /// Runs the paused animations past their end, so the layer shows its
    /// final state at once. Safe to call when nothing is held.
    func snap(duration: TimeInterval) {
        holding = false
        snapScheduled = false
        fallbackWork?.cancel()
        fallbackWork = nil
        guard let layer = layer(), layer.speed == 0 else { return }
        clockOffset += duration + 1
        layer.speed = 1
        layer.timeOffset = clockOffset
    }
}
