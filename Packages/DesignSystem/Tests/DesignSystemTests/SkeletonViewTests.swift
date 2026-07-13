import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite("SkeletonView")
struct SkeletonViewTests {
    @Test("reduce motion renders a static skeleton")
    func reduceMotionRendersStaticSkeleton() {
        let view = SkeletonView(reduceMotionEnabled: { true })

        view.startAnimating()

        #expect(view.isAnimating == false)
        #expect(view.hasShimmerAnimation == false)
    }

    @Test("standard motion starts the shimmer")
    func standardMotionStartsShimmer() {
        let view = SkeletonView(reduceMotionEnabled: { false })

        view.startAnimating()

        #expect(view.isAnimating)
        #expect(view.hasShimmerAnimation)
    }
}
