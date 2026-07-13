import UIKit

public enum ConnectivityBannerState: Sendable {
    case offline
    case restored
}

@MainActor
public final class ConnectivityBanner: UIView {
    private let messageLabel = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public func show(_ state: ConnectivityBannerState) {
        switch state {
        case .offline:
            messageLabel.text = "No internet connection · Waiting to reconnect"
            backgroundColor = ColorToken.warning.color
            accessibilityLabel = "No internet connection"
            accessibilityValue = "Waiting to reconnect"
        case .restored:
            messageLabel.text = "Internet connection restored"
            backgroundColor = ColorToken.success.color
            accessibilityLabel = "Internet connection restored"
            accessibilityValue = nil
        }

        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
    }

    private func configureView() {
        isAccessibilityElement = true
        accessibilityTraits = [.staticText, .updatesFrequently]
        layer.cornerRadius = 8
        clipsToBounds = true

        messageLabel.font = TypographyToken.caption.font()
        messageLabel.textColor = ColorToken.backgroundPrimary.color
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
}
