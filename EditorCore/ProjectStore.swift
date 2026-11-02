import Foundation

public struct ProjectStore {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    public func save(_ history: EditHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: url(for: history.current.id), options: .atomic)
    }

    public func load(id: UUID) throws -> EditHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(EditHistory.self, from: Data(contentsOf: url(for: id)))
        guard history.current.schemaVersion == 1, history.current.color.underwaterMappingVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return history
    }

    public func loadAll() throws -> [EditHistory] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return try load(id: id)
            }
    }
}
