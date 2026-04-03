import SwiftUI
import AVFoundation

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showQRScanner = false
    @State private var showQRPasteSheet = false
    @State private var qrJSONText = ""
    @State private var scannedPayload: QRPayload?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("Beamlet")
                        .font(.title.bold())

                    Text("Connect to your Beamlet server")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Scan QR button
                Button {
                    showQRScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)

                // Paste fallback
                Button {
                    showQRPasteSheet = true
                } label: {
                    Label("Paste QR Code", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.horizontal, 24)

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                    Text("or enter manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                }
                .padding(.horizontal, 24)

                // Manual form
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL")
                            .font(.headline)
                        TextField("https://beamlet.example.com", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Token")
                            .font(.headline)
                        SecureField("Paste your token here", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 24)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal, 24)
                }

                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showQRScanner) {
            QRScannerSheet { code in
                showQRScanner = false
                handleScannedCode(code)
            } onCancel: {
                showQRScanner = false
            }
        }
        .sheet(isPresented: $showQRPasteSheet) {
            qrPasteSheet
        }
        .sheet(item: $scannedPayload) { payload in
            NameEntrySheet(
                serverURL: payload.url,
                inviteToken: payload.invite,
                onComplete: { scannedPayload = nil }
            )
            .environment(authRepository)
            .environment(api)
        }
    }

    // MARK: - QR Paste Sheet

    private var qrPasteSheet: some View {
        VStack(spacing: 16) {
            Text("Paste QR Code JSON")
                .font(.headline)
                .padding(.top, 16)

            Text("Copy the QR code content from another device and paste it below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $qrJSONText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .border(Color.secondary.opacity(0.3))
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    qrJSONText = ""
                    showQRPasteSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    handleQRPaste()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(qrJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 360, height: 280)
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code"
            return
        }
        scannedPayload = payload
    }

    private func handleQRPaste() {
        let trimmed = qrJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code JSON. Expected format: {\"u\":\"...\",\"i\":\"...\"}"
            showQRPasteSheet = false
            return
        }
        showQRPasteSheet = false
        qrJSONText = ""
        scannedPayload = payload
    }

    private func connect() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            var validationRequest = URLRequest(url: url.appendingPathComponent("api/contacts"))
            validationRequest.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")

            do {
                let (_, response) = try await URLSession.shared.data(for: validationRequest)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    error = "Invalid token or server URL"
                    isConnecting = false
                    return
                }
            } catch {
                self.error = "Could not connect to server"
                isConnecting = false
                return
            }

            authRepository.store(serverURL: url, token: trimmedToken)

            if let me = try? await api.getMe() {
                authRepository.storeUserID(me.id)
            }

            isConnecting = false
        }
    }
}

// MARK: - QR Scanner Sheet (Camera)

private struct QRScannerSheet: View {
    let onScanned: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scan QR Code")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            CameraQRView(onScanned: onScanned)
                .frame(width: 400, height: 350)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

            Text("Point your camera at a Beamlet QR code")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 440, height: 460)
    }
}

// MARK: - Camera QR View (AVFoundation)

private struct CameraQRView: NSViewRepresentable {
    let onScanned: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.setupCamera(in: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScanned: (String) -> Void
        private var session: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasScanned = false

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func setupCamera(in view: NSView) {
            let session = AVCaptureSession()
            self.session = session

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer = CALayer()
            view.wantsLayer = true
            view.layer?.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else { return }

            hasScanned = true
            session?.stopRunning()
            onScanned(value)
        }

        deinit {
            session?.stopRunning()
        }
    }
}

// MARK: - Name Entry Sheet (for invite flow)

private struct NameEntrySheet: View {
    let serverURL: String
    let inviteToken: String
    let onComplete: () -> Void

    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Your Name")
                .font(.headline)
                .padding(.top, 16)

            Text("Choose a display name for your Beamlet account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                    onComplete()
                }
                .keyboardShortcut(.cancelAction)

                Button("Join") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 320, height: 220)
    }

    private func submit() {
        guard let url = URL(string: serverURL) else {
            error = "Invalid server URL"
            return
        }

        isSubmitting = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInvite(
                    serverURL: url,
                    inviteToken: inviteToken,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                if let token = response.token {
                    authRepository.store(serverURL: url, token: token)
                    if let userID = response.userID {
                        authRepository.storeUserID(userID)
                    }
                }

                dismiss()
                onComplete()
            } catch {
                self.error = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
