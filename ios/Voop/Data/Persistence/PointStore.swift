import Foundation
import SwiftData

@MainActor
final class PointStore {
    private let container: ModelContainer

    private static let storeURL = URL.documentsDirectory.appending(path: "rawpoints.store")

    init(inMemory: Bool = false) throws {
        let config: ModelConfiguration = inMemory
            ? ModelConfiguration("rawpoints", isStoredInMemoryOnly: true)
            : ModelConfiguration("rawpoints", url: Self.storeURL)
        container = try ModelContainer(for: RawPoint.self, configurations: config)
    }

    /// Opens the on-disk store, recovering rather than crashing on a corrupt/unreadable file:
    /// wipe the store (and its SQLite sidecars) and retry once, then fall back to an in-memory
    /// store so the app still launches. Losing history beats bricking on a bad file.
    static func openOrRecover() -> PointStore {
        if let store = try? PointStore() { return store }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        if let store = try? PointStore() { return store }
        if let store = try? PointStore(inMemory: true) { return store }
        // An in-memory container for this trivial model effectively cannot fail; if it somehow
        // does, there's no usable persistence layer left to launch with.
        fatalError("Unable to create even an in-memory point store")
    }

    /// Inserts a point into the context *without* saving. Returns the stored model so the caller
    /// can mirror it in memory without re-fetching. Call `save()` to flush a batch to disk —
    /// losing the last few unflushed seconds on a crash is acceptable for a fitness logger.
    @discardableResult
    func insert(_ point: DataPoint) -> RawPoint {
        let raw = RawPoint(from: point)
        container.mainContext.insert(raw)
        return raw
    }

    func save() throws {
        try container.mainContext.save()
    }

    func fetchAll() throws -> [RawPoint] {
        let descriptor = FetchDescriptor<RawPoint>(sortBy: [SortDescriptor(\.receivedAt)])
        return try container.mainContext.fetch(descriptor)
    }

    func delete(_ points: [RawPoint]) throws {
        for point in points {
            container.mainContext.delete(point)
        }
        try container.mainContext.save()
    }
}
