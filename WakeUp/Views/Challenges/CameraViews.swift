import AVFoundation
import SwiftUI
import UIKit

// MARK: - QR scanning

/// Asks for camera access, then scans for a QR code. Everything happens on the device.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    var onUnavailable: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Bool? = nil

    var body: some View {
        NavigationStack {
            Group {
                if allowed == true {
                    QRScannerView { code in
                        dismiss()
                        onCode(code)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("Point your camera at the WakeUp code")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(24)
                    }
                } else if allowed == false {
                    CameraUnavailableView {
                        dismiss()
                        onUnavailable?()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Scan code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task { allowed = await CameraAccess.request() }
    }
}

struct CameraUnavailableView: View {
    let useBackup: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Palette.text3)
            Text(CameraAccess.hasCamera ? "Camera access is off for WakeUp." : "This device has no camera.")
                .font(.headline)
            Text("You can turn it on in Settings, or use a backup challenge now.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.text2)
            if CameraAccess.hasCamera {
                Button("Open Settings") { SystemSettings.open() }.buttonStyle(SecondaryButtonStyle())
            }
            Button("Use a backup challenge", action: useBackup).buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let reader = QRReader()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        reader.onCode = { [weak self] code in self?.onCode?(code) }
        output.setMetadataObjectsDelegate(reader, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

final class QRReader: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private var delivered = false

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        delivered = true
        onCode?(code)
    }
}

// MARK: - Photo capture

struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(_ onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

// MARK: - Pose camera

/// Front camera preview that feeds shoulder height to a callback. Stops the camera when it disappears.
struct PoseCameraView: UIViewControllerRepresentable {
    let onPosition: (Double) -> Void
    let onNoBody: () -> Void

    func makeUIViewController(context: Context) -> PoseCameraController {
        let controller = PoseCameraController()
        controller.processor.onPosition = onPosition
        controller.processor.onNoBody = onNoBody
        return controller
    }

    func updateUIViewController(_ controller: PoseCameraController, context: Context) {}
}

final class PoseCameraController: UIViewController {
    let processor = PoseProcessor()
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "wakeup.pose")
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(processor, queue: queue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let session = session
        queue.async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        queue.async { session.stopRunning() }
    }
}
