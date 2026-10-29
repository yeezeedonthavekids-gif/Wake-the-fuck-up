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

/// Reads frames from the front camera and reports the average height of the neck and shoulders.
/// Runs Vision's body-pose detection about 10 times a second on a background queue.
final class PoseProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onPosition: ((Double) -> Void)?
    var onNoBody: (() -> Void)?
    private var lastRun = Date.distantPast

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.1 else { return }
        lastRun = now
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
        guard let body = request.results?.first,
              let points = try? body.recognizedPoints(.torso) else {
            DispatchQueue.main.async { [weak self] in self?.onNoBody?() }
            return
        }
        let joints: [VNHumanBodyPoseObservation.JointName] = [.neck, .leftShoulder, .rightShoulder]
        let heights = joints.compactMap { points[$0] }.filter { $0.confidence > 0.3 }.map { Double($0.location.y) }
        guard !heights.isEmpty else {
            DispatchQueue.main.async { [weak self] in self?.onNoBody?() }
            return
        }
        let average = heights.reduce(0, +) / Double(heights.count)
        DispatchQueue.main.async { [weak self] in self?.onPosition?(average) }
    }
}
