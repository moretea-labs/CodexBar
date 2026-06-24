import Foundation

final class CodexRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let lock = NSLock()
    private let fileReadLock = NSLock()
    private let streamQueue = DispatchQueue(label: "com.greyson.codexbar.codex-output")
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    func start(
        executablePath: String,
        workspacePath: String,
        prompt: String,
        onEventLine: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Int32, Error>) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process?.isRunning != true else {
            throw CodexBarError.processAlreadyRunning
        }

        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)

        let task = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()

        // Use JSONL output so the UI can render agent messages, commands,
        // file changes, plans and errors as distinct timeline blocks.
        let command = [
            "exec",
            ShellUtilities.shellQuote(executablePath),
            "--ask-for-approval", "never",
            "exec",
            "--cd", ShellUtilities.shellQuote(workspacePath),
            "--sandbox", "workspace-write",
            "--json",
            "-"
        ].joined(separator: " ")

        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.currentDirectoryURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        task.arguments = ["-lic", command]
        task.standardOutput = stdout
        task.standardError = stderr
        task.standardInput = stdin

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.fileReadLock.lock()
            let data = handle.availableData
            self.fileReadLock.unlock()
            guard !data.isEmpty else { return }
            self.consume(
                data,
                stream: .stdout,
                onEventLine: onEventLine,
                onDiagnostic: onDiagnostic
            )
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.fileReadLock.lock()
            let data = handle.availableData
            self.fileReadLock.unlock()
            guard !data.isEmpty else { return }
            self.consume(
                data,
                stream: .stderr,
                onEventLine: onEventLine,
                onDiagnostic: onDiagnostic
            )
        }

        task.terminationHandler = { [weak self] finishedTask in
            guard let self else { return }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            // Drain bytes that may have reached the pipe after the last readability callback.
            self.fileReadLock.lock()
            let remainingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
            let remainingStderr = stderr.fileHandleForReading.readDataToEndOfFile()
            self.fileReadLock.unlock()

            self.streamQueue.sync {
                if !remainingStdout.isEmpty {
                    self.stdoutBuffer.append(remainingStdout)
                    self.emitCompleteLines(
                        from: &self.stdoutBuffer,
                        stream: .stdout,
                        onEventLine: onEventLine,
                        onDiagnostic: onDiagnostic
                    )
                }
                if !remainingStderr.isEmpty {
                    self.stderrBuffer.append(remainingStderr)
                    self.emitCompleteLines(
                        from: &self.stderrBuffer,
                        stream: .stderr,
                        onEventLine: onEventLine,
                        onDiagnostic: onDiagnostic
                    )
                }
                self.flushRemaining(
                    stream: .stdout,
                    onEventLine: onEventLine,
                    onDiagnostic: onDiagnostic
                )
                self.flushRemaining(
                    stream: .stderr,
                    onEventLine: onEventLine,
                    onDiagnostic: onDiagnostic
                )
            }

            self.lock.lock()
            self.process = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.lock.unlock()

            DispatchQueue.main.async {
                onCompletion(.success(finishedTask.terminationStatus))
            }
        }

        do {
            try task.run()
            process = task
            stdoutPipe = stdout
            stderrPipe = stderr

            if let data = prompt.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw CodexBarError.processLaunchFailed(error.localizedDescription)
        }
    }

    func cancel() {
        lock.lock()
        let runningProcess = process
        lock.unlock()

        guard let runningProcess, runningProcess.isRunning else { return }
        runningProcess.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if runningProcess.isRunning {
                runningProcess.terminate()
            }
        }
    }

    private enum OutputStream {
        case stdout
        case stderr
    }

    private func consume(
        _ data: Data,
        stream: OutputStream,
        onEventLine: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        streamQueue.async { [weak self] in
            guard let self else { return }
            switch stream {
            case .stdout:
                self.stdoutBuffer.append(data)
                self.emitCompleteLines(
                    from: &self.stdoutBuffer,
                    stream: stream,
                    onEventLine: onEventLine,
                    onDiagnostic: onDiagnostic
                )
            case .stderr:
                self.stderrBuffer.append(data)
                self.emitCompleteLines(
                    from: &self.stderrBuffer,
                    stream: stream,
                    onEventLine: onEventLine,
                    onDiagnostic: onDiagnostic
                )
            }
        }
    }

    private func emitCompleteLines(
        from buffer: inout Data,
        stream: OutputStream,
        onEventLine: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        let newline = UInt8(ascii: "\n")
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            emit(
                String(decoding: lineData, as: UTF8.self),
                stream: stream,
                onEventLine: onEventLine,
                onDiagnostic: onDiagnostic
            )
        }
    }

    private func flushRemaining(
        stream: OutputStream,
        onEventLine: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        let data: Data
        switch stream {
        case .stdout:
            data = stdoutBuffer
            stdoutBuffer.removeAll(keepingCapacity: true)
        case .stderr:
            data = stderrBuffer
            stderrBuffer.removeAll(keepingCapacity: true)
        }
        guard !data.isEmpty else { return }
        emit(
            String(decoding: data, as: UTF8.self),
            stream: stream,
            onEventLine: onEventLine,
            onDiagnostic: onDiagnostic
        )
    }

    private func emit(
        _ line: String,
        stream: OutputStream,
        onEventLine: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            switch stream {
            case .stdout: onEventLine(trimmed)
            case .stderr: onDiagnostic(trimmed)
            }
        }
    }
}
