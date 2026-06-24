import Foundation

final class ExecutableLocator {
    static func locateCodex(customPath: String, completion: @escaping (String?) -> Void) {
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
            process.arguments = ["-lic", "command -v codex 2>/dev/null"]
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
