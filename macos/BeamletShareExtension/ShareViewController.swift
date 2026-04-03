import Cocoa
import SwiftUI

class ShareViewController: NSViewController {

    override var nibName: NSNib.Name? {
        return nil
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 340))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let authRepository = AuthRepository()

        guard authRepository.isAuthenticated else {
            showNotAuthenticatedUI()
            return
        }

        let api = BeamletAPI(authRepository: authRepository)
        let shareView = ShareView(api: api, extensionContext: extensionContext)

        let hostingView = NSHostingView(rootView: shareView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func showNotAuthenticatedUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Not Connected")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.alignment = .center
        stackView.addArrangedSubview(titleLabel)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Open the Beamlet app and connect to a server first.")
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center
        stackView.addArrangedSubview(descriptionLabel)

        let cancelButton = NSButton(title: "OK", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        stackView.addArrangedSubview(cancelButton)

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func cancel() {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: cancelError)
    }
}
