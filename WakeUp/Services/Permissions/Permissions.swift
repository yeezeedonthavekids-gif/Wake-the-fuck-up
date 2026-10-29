import AVFoundation
import UIKit

/// Camera access is only requested when a challenge that needs it is about to start.
enum CameraAccess {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    static var description: String {
        guard hasCamera else { return "No camera on this device" }
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Off in Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    static func request() async -> Bool {
        guard hasCamera else { return false }
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

enum SystemSettings {
    @MainActor
    static func open() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

enum Haptics {
    nonisolated(unsafe) static var enabled = true

    @MainActor static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
