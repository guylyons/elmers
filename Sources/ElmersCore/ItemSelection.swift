import Foundation

public struct ItemSelection: Equatable {
    public private(set) var ids: Set<UUID> = []
    public private(set) var focus: UUID?
    private var anchor: UUID?
    public init() {}
    public mutating func select(_ id: UUID, extend: Bool = false, toggle: Bool = false, in ordered: [UUID]) {
        guard ordered.contains(id) else { return }
        if extend, let anchor, let start = ordered.firstIndex(of: anchor), let end = ordered.firstIndex(of: id) {
            ids = Set(ordered[min(start,end)...max(start,end)])
        } else if toggle {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        } else { ids = [id]; anchor = id }
        focus = ids.contains(id) ? id : ordered.first(where: { ids.contains($0) })
    }
    public mutating func move(_ offset: Int, extend: Bool = false, in ordered: [UUID]) {
        guard !ordered.isEmpty else { return }
        let index = focus.flatMap { ordered.firstIndex(of: $0) } ?? 0
        select(ordered[min(max(index + offset, 0), ordered.count - 1)], extend: extend, in: ordered)
    }
    public mutating func selectAll(in ordered: [UUID]) { ids = Set(ordered); focus = focus ?? ordered.first; anchor = focus }
    public mutating func reconcile(in ordered: [UUID]) {
        ids.formIntersection(ordered)
        if let focus, ids.contains(focus) { return }
        focus = ordered.first(where: { ids.contains($0) }) ?? ordered.first
        if let focus, ids.isEmpty { ids = [focus] }
        anchor = focus
    }
    public mutating func clear() { ids = []; focus = nil; anchor = nil }
}
