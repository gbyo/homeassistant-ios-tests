@testable import HomeAssistant
import SwiftUI
import Testing
import UIKit

/// The numbers here are read off `home-assistant-logo-loading.svg`, the animation this overlay
/// replaced: a `120 × 120` artwork whose three nodes rest at radius `10.5` and pulse in a `1300ms`
/// loop, each starting `200ms` after the one before it.
@MainActor
struct HomeAssistantLoadingLogoAnimationViewTests {
    private typealias AnimationView = HomeAssistantLoadingLogoAnimationView.AnimationView

    /// Node centers in the SVG's coordinate space, in the order the layers are created.
    private static let svgNodeCenters = [
        CGPoint(x: 30, y: 90),
        CGPoint(x: 60, y: 42),
        CGPoint(x: 90, y: 73.5),
    ]
    private static let svgNodeRadius: CGFloat = 10.5

    @Test func nodesLandOnTheLogoArtworkGeometryAtTheSvgSize() {
        let view = AnimationView()
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        view.layoutIfNeeded()

        #expect(view.nodeLayers.count == Self.svgNodeCenters.count)
        for (nodeLayer, center) in zip(view.nodeLayers, Self.svgNodeCenters) {
            #expect(nodeLayer.position == center)
            #expect(nodeLayer.bounds.size == CGSize(width: Self.svgNodeRadius * 2, height: Self.svgNodeRadius * 2))
            #expect(nodeLayer.cornerRadius == Self.svgNodeRadius)
        }
    }

    /// The static logo is drawn aspect-fit, so the nodes have to follow the same centered square
    /// rather than stretching with the bounds — the stand-by view hands the overlay whatever frame
    /// its layout produces.
    @Test func nodesFollowTheCenteredSquareInNonSquareBounds() {
        let view = AnimationView()
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
        view.layoutIfNeeded()

        let squareOriginX: CGFloat = 60
        for (nodeLayer, center) in zip(view.nodeLayers, Self.svgNodeCenters) {
            #expect(nodeLayer.position == CGPoint(x: squareOriginX + center.x, y: center.y))
            #expect(nodeLayer.bounds.width == Self.svgNodeRadius * 2)
        }
    }

    @Test func animatingWhileOnScreenAddsExactlyOnePulsePerNode() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let view = AnimationView()
        window.addSubview(view)

        view.setAnimating(true)
        let firstPulses = view.nodeLayers.map { $0.animation(forKey: AnimationView.pulseAnimationKey) }
        view.setAnimating(true)
        view.setAnimating(true)

        for (nodeLayer, firstPulse) in zip(view.nodeLayers, firstPulses) {
            let pulse = try #require(nodeLayer.animation(forKey: AnimationView.pulseAnimationKey))
            // Identical to the first one: a repeat call must not restart the loop from its first frame.
            #expect(pulse === firstPulse)
            #expect(nodeLayer.animationKeys()?.count == 1)
            #expect(!nodeLayer.isHidden)
        }
    }

    @Test func eachNodePulsesOnItsOwnScheduleFromTheSvg() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let view = AnimationView()
        window.addSubview(view)
        view.setAnimating(true)

        // Seconds into the 1.3s loop at which each node is at rest, at full scale, and back at rest.
        let expectedKeySeconds: [[TimeInterval]] = [
            [0, 0.2, 0.5, 1.3],
            [0, 0.4, 0.6, 0.9, 1.3],
            [0, 0.2, 0.4, 0.7, 1.3],
        ]
        let expectedScales: [[CGFloat]] = [
            [1, 1.3, 1, 1],
            [1, 1, 1.3, 1, 1],
            [1, 1, 1.3, 1, 1],
        ]

        for (index, nodeLayer) in view.nodeLayers.enumerated() {
            let animation = nodeLayer.animation(forKey: AnimationView.pulseAnimationKey)
            let pulse = try #require(animation as? CAKeyframeAnimation)
            #expect(pulse.keyPath == "transform.scale")
            #expect(pulse.duration == 1.3)
            #expect(pulse.repeatCount == .greatestFiniteMagnitude)

            let keyTimes = pulse.keyTimes?.map(\.doubleValue) ?? []
            let expectedKeyTimes = expectedKeySeconds[index].map { $0 / 1.3 }
            #expect(keyTimes.count == expectedKeyTimes.count)
            for (keyTime, expected) in zip(keyTimes, expectedKeyTimes) {
                #expect(abs(keyTime - expected) < 0.0001)
            }

            let scales = pulse.values as? [CGFloat] ?? []
            #expect(scales == expectedScales[index])
            #expect(scales.max() == 1.3)
            // One timing function per segment; the grow and shrink segments carry the SVG's easing.
            #expect(pulse.timingFunctions?.count == expectedScales[index].count - 1)
        }
    }

    @Test func disablingAnimationRemovesThePulse() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let view = AnimationView()
        window.addSubview(view)
        view.setAnimating(true)

        view.setAnimating(false)

        for nodeLayer in view.nodeLayers {
            #expect(nodeLayer.animation(forKey: AnimationView.pulseAnimationKey) == nil)
            #expect(nodeLayer.isHidden)
        }
    }

    /// Core Animation drops a detached layer's animations, so the pulse has to be handed back every
    /// time the overlay returns — the stand-by view comes and goes with every reload.
    @Test func detachingStopsThePulseAndReattachingStartsItAgain() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let view = AnimationView()
        window.addSubview(view)
        view.setAnimating(true)

        view.removeFromSuperview()
        let whileDetached = view.nodeLayers.compactMap { $0.animation(forKey: AnimationView.pulseAnimationKey) }
        window.addSubview(view)

        #expect(whileDetached.isEmpty)
        for nodeLayer in view.nodeLayers {
            #expect(nodeLayer.animation(forKey: AnimationView.pulseAnimationKey) != nil)
        }
    }

    @Test func reattachingDoesNotRestartAPulseThatWasNeverRequested() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let view = AnimationView()
        window.addSubview(view)
        view.setAnimating(false)

        view.removeFromSuperview()
        window.addSubview(view)

        for nodeLayer in view.nodeLayers {
            #expect(nodeLayer.animation(forKey: AnimationView.pulseAnimationKey) == nil)
        }
    }

    /// The stand-by view drops the overlay into a `ZStack` sized to the logo and expects it to fill
    /// that frame; a representable that sized itself to nothing would pulse invisibly.
    @Test func hostedOverlayFillsTheLogoFrameAndPulses() throws {
        let logoSide: CGFloat = 120
        let controller = UIHostingController(
            rootView: HomeAssistantLoadingLogoAnimationView(isAnimating: true)
                .frame(width: logoSide, height: logoSide)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let animationView = try #require(Self.firstAnimationView(in: controller.view))
        #expect(animationView.bounds.size == CGSize(width: logoSide, height: logoSide))
        for (nodeLayer, center) in zip(animationView.nodeLayers, Self.svgNodeCenters) {
            #expect(nodeLayer.position == center)
            #expect(nodeLayer.animation(forKey: AnimationView.pulseAnimationKey) != nil)
        }
    }

    private static func firstAnimationView(in view: UIView) -> AnimationView? {
        if let animationView = view as? AnimationView {
            return animationView
        }
        return view.subviews.lazy.compactMap { firstAnimationView(in: $0) }.first
    }

    /// The logo carries a hidden ten-tap escape hatch behind the overlay.
    @Test func overlayLetsTapsThrough() {
        let view = AnimationView()
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 120)

        #expect(view.hitTest(CGPoint(x: 60, y: 60), with: nil) == nil)
    }
}
