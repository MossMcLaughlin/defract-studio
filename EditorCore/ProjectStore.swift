import Foundation

public struct ProjectStore {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    public func save(_ history: EditHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(history).write(to: url(for: history.current.id), options: .atomic)
    }

    public func load(id: UUID) throws -> EditHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let data = try Data(contentsOf: url(for: id))
        let history: EditHistory
        if let current = try? decoder.decode(EditHistory.self, from: data) {
            history = current
        } else {
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode(EditHistory.self, from: data)
        }
        guard (1...2).contains(history.current.schemaVersion),
              (history.current.rendererVersion ?? 1) == history.current.schemaVersion,
              history.current.color.underwaterMappingVersion == 1 else {
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

    public func loadRecovering() throws -> (histories: [EditHistory], failedFiles: [URL]) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], []) }
        var histories: [EditHistory] = []
        var failedFiles: [URL] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
               let history = try? load(id: id) {
                histories.append(history)
            } else { failedFiles.append(url) }
        }
        return (histories, failedFiles)
    }
}
