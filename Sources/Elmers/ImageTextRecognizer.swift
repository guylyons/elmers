import AppKit
import Vision
import ElmersCore

/// On-device text recognition for image items so their contents are searchable, as in Paste.
enum ImageTextRecognizer {
    /// `level`: accurate for real captures (runs in the background, slow on first use); fast for checks.
    static func recognize(_ item: ClipboardItem, level: VNRequestTextRecognitionLevel = .accurate, completion: @escaping @MainActor (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let image = imagePreview(item), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Task { @MainActor in completion(nil) }; return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level; request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let text: String?
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                text = lines.isEmpty ? nil : lines.joined(separator: "\n")
            } catch { text = nil }
            Task { @MainActor in completion(text) }
        }
    }
}
