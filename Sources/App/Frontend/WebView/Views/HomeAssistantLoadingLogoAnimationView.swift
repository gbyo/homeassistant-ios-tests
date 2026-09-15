import Shared
import SwiftUI
import UIKit

/// Pulses the three white nodes of the Home Assistant logo, drawn on top of the static `Image(.logo)`
/// the stand-by loader already shows. Only the nodes move, so the overlay draws nothing else: the
/// house, the connecting lines and every resting pixel keep coming from the canonical logo asset
/// underneath, which is also what the launch-splash hand-off and the empty-state move animate.
///
/// The geometry and timing are transcribed from the `home-assistant-logo-loading.svg` this replaces,
/// whose `120 × 120` artwork put the nodes at `(30, 90)`, `(60, 42)` and `(90, 73.5)` with a resting
/// radius of `10.5` — normalized below against the logo's square so they follow it at any size.
struct HomeAssistantLoadingLogoAnimationView: UIViewRepresentable {
    /// Whether the nodes should pulse. Core Animation runs the loop entirely on the render server, so
    /// turning this off is what actually stops the work.
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> AnimationView {
        AnimationView()
    }

    func updateUIView(_ uiView: AnimationView, context: Context) {
        // Reduce Motion needs no substitute: the static logo underneath is already the resting artwork.
        uiView.setAnimating(isAnimating && !reduceMotion)
    }

    /// Draws and animates the nodes. A plain `UIView` with three circular sublayers rather than hosted
    /// SwiftUI views, so the whole loop is three `CAKeyframeAnimation`s the render server owns.
    final class AnimationView: UIView {
        /// The key every node's pulse is added under, so a repeat call can tell an animation is already
        /// running instead of stacking a second copy on top of it.
        static let pulseAnimationKey = "pulse"

        /// Length of one full loop, matching the SVG's `1300ms`.
        static let loopDuration: TimeInterval = 1.3
        /// How large a node gets at the peak of its pulse.
        static let maximumScale: CGFloat = 1.3

        /// How long a node takes to reach `maximumScale`, and then to settle back to its resting size.
        private static let growDuration: TimeInterval = 0.2
        private static let shrinkDuration: TimeInterval = 0.3
        /// Node radius as a fraction of the logo's square side: `10.5 / 120`.
        private static let nodeRadius: CGFloat = 0.0875

        /// The nodes, in the order the artwork reads them: lower left, top, right. Their pulses are
        /// identical apart from starting `0.2s` further into the loop each time, which is the stagger
        /// that makes the logo look like it is passing a signal along.
        private static let nodes = [
            Node(center: CGPoint(x: 0.25, y: 0.75), growStart: 0),
            Node(center: CGPoint(x: 0.5, y: 0.35), growStart: 0.4),
            Node(center: CGPoint(x: 0.75, y: 0.6125), growStart: 0.2),
        ]

        /// One layer per entry in `nodes`, in the same order.
        private(set) var nodeLayers: [CALayer] = []

        private var isAnimating = false

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            // The logo carries a ten-tap escape hatch behind this overlay, so taps have to fall through.
            isUserInteractionEnabled = false
            self.nodeLayers = Self.nodes.map { _ in
                let nodeLayer = CALayer()
                nodeLayer.backgroundColor = UIColor(Color.brandBackground).cgColor
                nodeLayer.isHidden = true
                layer.addSublayer(nodeLayer)
                return nodeLayer
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Core Animation drops a detached layer's animations, so a view that comes back has to be
            // given them again; leaving the window is what stops the loop consuming anything.
            updateAnimations()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The logo is drawn aspect-fit, so follow the same square rather than the full bounds.
            let side = min(bounds.width, bounds.height)
            let squareOrigin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
            let diameter = side * Self.nodeRadius * 2
            // Without this the stand-by view's own resize — the loading logo shrinking into the
            // empty-state one — would hand every layer an implicit animation of its own to run.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (node, nodeLayer) in zip(Self.nodes, nodeLayers) {
                // Set `bounds` and `position` rather than `frame`, which is undefined while the layer
                // carries a scale transform.
                nodeLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                nodeLayer.position = CGPoint(
                    x: squareOrigin.x + node.center.x * side,
                    y: squareOrigin.y + node.center.y * side
                )
                nodeLayer.cornerRadius = diameter / 2
            }
            CATransaction.commit()
        }

        /// Starts or stops the pulse. Safe to call repeatedly: a node that is already pulsing keeps the
        /// animation it has, so a redundant call never restarts the loop from its first frame.
        func setAnimating(_ animating: Bool) {
            isAnimating = animating
            updateAnimations()
        }

        private func updateAnimations() {
            let shouldAnimate = isAnimating && window != nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (node, nodeLayer) in zip(Self.nodes, nodeLayers) {
                nodeLayer.isHidden = !shouldAnimate
                guard shouldAnimate else {
                    nodeLayer.removeAnimation(forKey: Self.pulseAnimationKey)
                    continue
                }
                guard nodeLayer.animation(forKey: Self.pulseAnimationKey) == nil else { continue }
                nodeLayer.add(Self.pulseAnimation(growStart: node.growStart), forKey: Self.pulseAnimationKey)
            }
            CATransaction.commit()
        }

        /// A node's full loop: rest until `growStart`, grow, shrink back, then rest out the remainder.
        /// Keyframes rather than a SwiftUI `easeInOut` so the SVG's timing survives exactly — including
        /// the resting stretches, which an eased animation would round off.
        private static func pulseAnimation(growStart: TimeInterval) -> CAKeyframeAnimation {
            let ease = CAMediaTimingFunction(controlPoints: 0.39, 0.575, 0.565, 1)
            let linear = CAMediaTimingFunction(name: .linear)
            let peak = growStart + growDuration
            let settled = peak + shrinkDuration

            var times = [TimeInterval]()
            var values = [CGFloat]()
            var timingFunctions = [CAMediaTimingFunction]()
            if growStart > 0 {
                times.append(contentsOf: [0, growStart])
                values.append(contentsOf: [1, 1])
                timingFunctions.append(linear)
            } else {
                times.append(0)
                values.append(1)
            }
            times.append(contentsOf: [peak, settled, loopDuration])
            values.append(contentsOf: [maximumScale, 1, 1])
            timingFunctions.append(contentsOf: [ease, ease, linear])

            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.duration = loopDuration
            animation.repeatCount = .greatestFiniteMagnitude
            animation.keyTimes = times.map { NSNumber(value: $0 / loopDuration) }
            animation.values = values
            animation.timingFunctions = timingFunctions
            return animation
        }

        /// Where a node sits inside the logo's square, as a fraction of its side, and how far into the
        /// loop it starts growing.
        private struct Node {
            let center: CGPoint
            let growStart: TimeInterval
        }
    }
}

#Preview {
    ZStack {
        WebViewEmptyStateIcon(style: nil, size: LaunchSplashOverlayView.Constants.splashLogoSize)
        HomeAssistantLoadingLogoAnimationView(isAnimating: true)
    }
    .frame(
        width: LaunchSplashOverlayView.Constants.splashLogoSize.width,
        height: LaunchSplashOverlayView.Constants.splashLogoSize.height
    )
}
