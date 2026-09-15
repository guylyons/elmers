import Foundation

/// Unmarked clipboard content copied across a foreground transition has no reliable source.
/// Drop transitions involving excluded/unknown sources; retain transitions between allowed apps.
public struct CapturePolicy {
    private var lastSource: String?
    public init(source: String?) { lastSource = source }
    public func sourceChanged(to source: String?) -> Bool { source != lastSource }
    public mutating func accepts(currentSource: String?, declaredSource: String?, excluded: Set<String>) -> Bool {
        defer { lastSource = currentSource }
        if let declaredSource, !declaredSource.isEmpty { return !excluded.contains(declaredSource) }
        if currentSource != lastSource {
            guard let lastSource, !excluded.contains(lastSource) else { return false }
        }
        return currentSource.map { !excluded.contains($0) } ?? false
    }
    public mutating func transitioned(to source: String?) { lastSource = source }
}
