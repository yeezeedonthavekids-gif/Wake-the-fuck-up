import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Generates QR codes on the device. Nothing is looked up online.
enum QRCodeImage {
    static func make(_ text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// On-device image classification for the "Photo check" mode of Find an item.
/// The photo is analyzed in memory and never saved or uploaded.
enum ItemRecognizer {
    static func labels(for image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            let results = request.results ?? []
            return results.filter { $0.confidence > 0.12 }.prefix(10).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
    }

    static func matches(_ labels: [String], item: HouseholdItem) -> Bool {
        let keys = (item.keywords + item.name.lowercased().split(separator: " ").map(String.init))
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
        return labels.contains { label in keys.contains { label.lowercased().contains($0) } }
    }
}

/// Reads upright frames from the front camera and reports the joints of the side of the body
/// the camera sees best. Runs Vision's body-pose detection about 12 times a second, on-device.
final class PoseProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((PoseFrame) -> Void)?
    private var lastRun = Date.distantPast

    private static let left: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle]
    private static let right: [VNHumanBodyPoseObservation.JointName] = [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle]

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.08 else { return }
        lastRun = now
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:]).perform([request])
        var frame = PoseFrame()
        if let body = request.results?.first, let points = try? body.recognizedPoints(.all) {
            let score: ([VNHumanBodyPoseObservation.JointName]) -> Float = { names in
                names.reduce(0) { $0 + (points[$1]?.confidence ?? 0) }
            }
            let side = score(Self.left) >= score(Self.right) ? Self.left : Self.right
            let joint: (Int) -> CGPoint? = { index in
                guard let point = points[side[index]], point.confidence > 0.3 else { return nil }
                return point.location
            }
            frame = PoseFrame(shoulder: joint(0), elbow: joint(1), wrist: joint(2), hip: joint(3), knee: joint(4), ankle: joint(5))
        }
        DispatchQueue.main.async { [weak self] in self?.onFrame?(frame) }
    }
}

/// Front camera: reports the width of the largest face as a share of the frame, about 12 times a second.
final class FaceSizeProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFace: ((Double?) -> Void)?
    private var lastRun = Date.distantPast

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.08 else { return }
        lastRun = now
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:]).perform([request])
        let width = (request.results ?? []).map { Double($0.boundingBox.width) }.max()
        DispatchQueue.main.async { [weak self] in self?.onFace?(width) }
    }
}
