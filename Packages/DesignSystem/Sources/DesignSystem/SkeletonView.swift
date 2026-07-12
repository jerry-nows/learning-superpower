import UIKit

@MainActor
public final class SkeletonView: UIView {
    public private(set) var isAnimating = false

    var hasShimmerAnimation: Bool {
        gradientLayer.animation(forKey: Self.animationKey) != nil
    }

    private static let animationKey = "designSystem.skeleton.shimmer"
    private let gradientLayer = CAGradientLayer()
    private let reduceMotionEnabled: () -> Bool

    public init(
        reduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    ) {
        self.reduceMotionEnabled = reduceMotionEnabled
        super.init(frame: .zero)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        layer.cornerRadius = min(8, bounds.height / 2)
    }

    public func startAnimating() {
        guard !reduceMotionEnabled() else {
            stopAnimating()
            return
        }

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1, -0.5, 0]
        animation.toValue = [1, 1.5, 2]
        animation.duration = 1.2
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: Self.animationKey)
        isAnimating = true
    }

    public func stopAnimating() {
        gradientLayer.removeAnimation(forKey: Self.animationKey)
        isAnimating = false
    }

    private func configureView() {
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        gradientLayer.colors = [
            ColorToken.skeletonBase.color.cgColor,
            ColorToken.skeletonHighlight.color.cgColor,
            ColorToken.skeletonBase.color.cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradientLayer)
    }
}
