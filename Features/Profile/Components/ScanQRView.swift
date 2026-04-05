//
//  ScanQRView.swift
//  MOMENTA
//
//  App 内相机扫码页面，解析 momenta://add-friend?code=xxx 或纯文本好友码。
//

import SwiftUI
import AVFoundation

struct ScanQRView: View {
    let onCodeScanned: (String, String?) -> Void   // code, note

    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?
    @State private var searchResult: FriendProfile?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showRequestSheet = false
    @State private var manualCodeInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // 相机全屏，忽略所有安全区域
                QRScannerRepresentable(onCodeFound: handleScannedValue)
                    .ignoresSafeArea()
                    .onTapGesture { hideKeyboard() }

                // 扫码框 + 输入面板合并在同一 VStack，键盘弹出时整体上移
                VStack(spacing: 0) {
                    Spacer()

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 3)
                        .frame(width: 260, height: 260)

                    Spacer()

                    manualEntryPanel
                }

                if let scannedCode, isSearching {
                    loadingOverlay(code: scannedCode)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showRequestSheet) {
                if let profile = searchResult {
                    SendFriendRequestSheet(
                        profile: profile,
                        onSend: { note in
                            onCodeScanned(scannedCode ?? "", note)
                            dismiss()
                        },
                        onCancel: { resetScan() }
                    )
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("Try Again") { resetScan() }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// 与 `FriendsListView` 使用同一 `FriendsAddByCodeListSection`
    private var manualEntryPanel: some View {
        List {
            FriendsAddByCodeListSection(
                codeInput: $manualCodeInput,
                isSearching: isSearching,
                onSearch: submitManualCode
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(maxHeight: 200)
        .padding(.horizontal, 8)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func loadingOverlay(code: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Looking up \(code)...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func handleScannedValue(_ value: String) {
        guard scannedCode == nil, !isSearching else { return }

        let code = extractFriendCode(from: value)
        guard let code, !code.isEmpty else { return }

        lookupFriend(code: code)
    }

    private func submitManualCode() {
        guard scannedCode == nil, !isSearching else { return }

        let raw = manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        guard let code = extractFriendCode(from: raw) else {
            errorMessage = "Enter a valid friend code (letters and numbers) or paste an invite link."
            return
        }

        lookupFriend(code: code)
    }

    private func lookupFriend(code: String) {
        scannedCode = code
        isSearching = true
        manualCodeInput = ""

        Task {
            do {
                guard let profile = try await FriendService.shared.searchByFriendCode(code) else {
                    errorMessage = "No user found with code \"\(code)\""
                    isSearching = false
                    scannedCode = nil
                    return
                }
                searchResult = profile
                isSearching = false
                showRequestSheet = true
            } catch {
                errorMessage = error.localizedDescription
                isSearching = false
                scannedCode = nil
            }
        }
    }

    private func resetScan() {
        scannedCode = nil
        searchResult = nil
        errorMessage = nil
        isSearching = false
        manualCodeInput = ""
    }

    private func extractFriendCode(from value: String) -> String? {
        if let url = URL(string: value),
           url.scheme?.lowercased() == "momenta",
           url.host == "add-friend",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 6 && trimmed.count <= 12 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return trimmed
        }

        return nil
    }
}

// MARK: - AVCaptureSession QR Scanner

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeFound: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeFound = onCodeFound
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

private class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeFound: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasFoundCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.captureSession.isRunning == false {
                self?.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.captureSession.isRunning == true {
                self?.captureSession.stopRunning()
            }
        }
    }

    private func setupCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasFoundCode,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }

        hasFoundCode = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onCodeFound?(stringValue)
    }
}
