import Foundation

enum TaskHistoryTranscriptStore {
    private static var directoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("TaskHistory", isDirectory: true)
    }

    private static func fileURL(for id: UUID) -> URL? {
        directoryURL?.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    @discardableResult
    static func save(_ transcript: TaskHistoryTranscript, for id: UUID) -> Bool {
        guard let directoryURL, let fileURL = fileURL(for: id) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(transcript)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(for id: UUID) -> TaskHistoryTranscript? {
        guard let fileURL = fileURL(for: id),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TaskHistoryTranscript.self, from: data)
    }

    static func delete(for id: UUID) {
        guard let fileURL = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func clear() {
        guard let directoryURL else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
