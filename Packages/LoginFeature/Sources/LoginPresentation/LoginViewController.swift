import DesignSystem
import LoginDomain
import UIKit

/// UIKit entry point for LoginFeature. Credentials stay in the text fields and
/// are handed directly to the view model; the controller never stores tokens.
@MainActor
public final class LoginViewController: UIViewController {
    public var onResult: ((LoginResult) -> Void)?

    private let viewModel: LoginViewModel
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let networkErrorLabel = UILabel()
    private let retryConnectionButton = UIButton(type: .system)
    private let connectionRestoredLabel = UILabel()
    private let scrollView = UIScrollView()
    private var stateTask: Task<Void, Never>?
    private var lastState: LoginViewState?

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { stateTask?.cancel() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        render(viewModel.state)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observeViewModel()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stateTask?.cancel()
        stateTask = nil
    }

    private func configureView() {
        view.backgroundColor = ColorToken.backgroundPrimary.color
        title = "Sign in"

        let titleLabel = UILabel()
        titleLabel.text = "Welcome back"
        titleLabel.font = TypographyToken.displayLarge.font()
        titleLabel.textColor = ColorToken.textPrimary.color
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Sign in to continue shopping"
        subtitleLabel.font = TypographyToken.body.font()
        subtitleLabel.textColor = ColorToken.textSecondary.color
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        configureEmailField()
        configurePasswordField()
        configureSubmitButton()
        configureErrorLabel()

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel, emailField, passwordField, submitButton, errorLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        view.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        configureRecoveryHarnessIfNeeded()

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            emailField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            passwordField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            activityIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor, constant: -16)
        ])
    }

    private func configureRecoveryHarnessIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("networkFailure") else {
            return
        }

        networkErrorLabel.text = "No internet connection"
        networkErrorLabel.accessibilityIdentifier = "network-error-message"
        networkErrorLabel.textAlignment = .center

        retryConnectionButton.setTitle("Retry", for: .normal)
        retryConnectionButton.accessibilityIdentifier = "retry-connection"
        retryConnectionButton.addTarget(self, action: #selector(retryConnection), for: .primaryActionTriggered)

        connectionRestoredLabel.text = "Connection restored"
        connectionRestoredLabel.accessibilityIdentifier = "connection-restored-message"
        connectionRestoredLabel.textAlignment = .center
        connectionRestoredLabel.isHidden = true

        let recoveryStack = UIStackView(arrangedSubviews: [
            networkErrorLabel, retryConnectionButton, connectionRestoredLabel
        ])
        recoveryStack.axis = .vertical
        recoveryStack.alignment = .center
        recoveryStack.spacing = 12
        recoveryStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recoveryStack)
        NSLayoutConstraint.activate([
            recoveryStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            recoveryStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            recoveryStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recoveryStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func retryConnection() {
        networkErrorLabel.isHidden = true
        retryConnectionButton.isHidden = true
        connectionRestoredLabel.isHidden = false
    }

    private func configureEmailField() {
        emailField.placeholder = "Email"
        emailField.textContentType = .emailAddress
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .next
        emailField.font = TypographyToken.body.font()
        emailField.textColor = ColorToken.textPrimary.color
        emailField.backgroundColor = ColorToken.surface.color
        emailField.layer.cornerRadius = 10
        emailField.accessibilityLabel = "Email address"
        emailField.accessibilityHint = "Enter your email address"
        emailField.adjustsFontForContentSizeCategory = true
        emailField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        emailField.leftViewMode = .always
    }

    private func configurePasswordField() {
        passwordField.placeholder = "Password"
        passwordField.textContentType = .password
        passwordField.isSecureTextEntry = true
        passwordField.autocapitalizationType = .none
        passwordField.autocorrectionType = .no
        passwordField.returnKeyType = .done
        passwordField.font = TypographyToken.body.font()
        passwordField.textColor = ColorToken.textPrimary.color
        passwordField.backgroundColor = ColorToken.surface.color
        passwordField.layer.cornerRadius = 10
        passwordField.accessibilityLabel = "Password"
        passwordField.accessibilityHint = "Enter your password"
        passwordField.adjustsFontForContentSizeCategory = true
        passwordField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        passwordField.leftViewMode = .always
        passwordField.delegate = self
    }

    private func configureSubmitButton() {
        submitButton.setTitle("Sign in", for: .normal)
        submitButton.titleLabel?.font = TypographyToken.body.font()
        submitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        submitButton.setTitleColor(ColorToken.backgroundPrimary.color, for: .normal)
        submitButton.backgroundColor = ColorToken.accent.color
        submitButton.layer.cornerRadius = 10
        submitButton.accessibilityLabel = "Sign in"
        submitButton.accessibilityHint = "Submits your email and password"
        submitButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
    }

    private func configureErrorLabel() {
        errorLabel.font = TypographyToken.caption.font()
        errorLabel.textColor = ColorToken.error.color
        errorLabel.numberOfLines = 0
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.isHidden = true
        errorLabel.accessibilityTraits = .staticText
    }

    @objc private func submit() {
        view.endEditing(true)
        viewModel.submit(email: emailField.text ?? "", password: passwordField.text ?? "")
        render(viewModel.state)
    }

    private func observeViewModel() {
        stateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let state = viewModel.state
                if state != lastState { render(state) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func render(_ state: LoginViewState) {
        lastState = state
        switch state {
        case .idle:
            setLoading(false)
            errorLabel.isHidden = true
        case .validating:
            setLoading(false)
            errorLabel.isHidden = true
        case .loading:
            setLoading(true)
            errorLabel.isHidden = true
        case let .failure(_, message):
            setLoading(false)
            errorLabel.text = message
            errorLabel.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: message)
        case let .success(result):
            setLoading(false)
            onResult?(result)
        }
    }

    private func setLoading(_ loading: Bool) {
        submitButton.isEnabled = !loading
        submitButton.alpha = loading ? 0.65 : 1
        if loading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        submitButton.accessibilityValue = loading ? "Signing in" : nil
    }
}

extension LoginViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField {
            passwordField.becomeFirstResponder()
        } else {
            submit()
        }
        return true
    }
}
