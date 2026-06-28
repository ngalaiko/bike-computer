import Foundation
import SwiftData

@MainActor
final class PointStore {
    private let container: ModelContainer

    init() throws {
        let config = ModelConfiguration(
            "rawpoints",
            url: URL.documentsDirectory.appending(path: "rawpoints.store")
        )
        container = try ModelContainer(for: RawPoint.self, configurations: config)
    }

    func insert(_ point: DataPoint) throws {
        container.mainContext.insert(RawPoint(from: point))
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
