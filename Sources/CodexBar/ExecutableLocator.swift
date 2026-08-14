import Foundation

final class ExecutableLocator {
    /// Resolves an agent executable path. A user-supplied path wins when it is
    /// executable; otherwise the command is looked up on PATH via a login shell.
    static func locateExecutable(
        name: String,
        customPath: String,
        completion: @escaping (String?) -> Void
    ) {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           FileManager.default.isExecutableFile(atPath: trimmed) {
            completion(trimmed)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", "command -v \(name) 2>/dev/null"]
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                let candidates = text
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let found = candidates.last(where: { FileManager.default.isExecutableFile(atPath: $0) })
                DispatchQueue.main.async { completion(found) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
