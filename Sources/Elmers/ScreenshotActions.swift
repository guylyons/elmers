import Foundation
import ElmersCore

enum ScreenshotActions {
    static func resolve(_ origin: ScreenshotOrigin, completion: @escaping @MainActor (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = origin.resolveOriginal()
            Task { @MainActor in completion(url) }
        }
    }
}
