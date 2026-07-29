import Foundation

enum ShellCommandRisk: String, Codable, CaseIterable, Identifiable, Hashable {
    case low
    case confirm
    case terminalOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "可直接执行"
        case .confirm: return "执行前确认"
        case .terminalOnly: return "仅限 Terminal"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield"
        case .confirm: return "exclamationmark.shield"
        case .terminalOnly: return "terminal.fill"
        }
    }
}

struct ShellCommandAssessment: Identifiable, Equatable {
    let command: String
    let risk: ShellCommandRisk
    let reason: String

    var id: String { command }
    var allowsDirectExecution: Bool { risk != .terminalOnly }
}

enum ShellCommandPolicy {
    private struct Rule {
        let pattern: String
        let reason: String
    }

    private static let terminalOnlyRules: [Rule] = [
        Rule(pattern: #"\bsudo\b"#, reason: "需要管理员权限的命令必须在 Terminal 中执行。"),
        Rule(pattern: #"\bgit\s+reset\s+--hard(\s|$)"#, reason: "硬重置可能永久丢失未提交修改。"),
        Rule(pattern: #"\bgit\s+clean\s+[^\n]*-[^\s]*f"#, reason: "强制清理可能永久删除未跟踪文件。"),
        Rule(pattern: #"\b(diskutil\s+(erase|partition|delete)|mkfs(\.|\s)|shutdown(\s|$)|reboot(\s|$)|halt(\s|$))"#, reason: "该命令可能影响磁盘或系统运行状态。"),
        Rule(pattern: #"\b(chmod|chown)\s+[^\n]*(-r|--recursive)"#, reason: "递归修改权限或所有者必须在 Terminal 中确认范围。"),
        Rule(pattern: #"\bfind\b[^\n]*(-delete|-exec|-execdir)"#, reason: "该 find 命令包含删除或执行动作，必须在 Terminal 中检查。"),
        Rule(pattern: #"\bdd\b[^\n]*\bof="#, reason: "dd 写入目标可能覆盖文件或磁盘，必须在 Terminal 中检查。"),
        Rule(pattern: #"(^|[;&|]\s*)(eval|bash\s+-c|zsh\s+-c|sh\s+-c)(\s|$)"#, reason: "嵌套 Shell 或动态执行无法可靠检查，必须在 Terminal 中运行。"),
        Rule(pattern: #"\b(curl|wget)\b[^\n]*\|\s*(bash|zsh|sh)(\s|$)"#, reason: "下载后直接执行脚本必须在 Terminal 中人工检查。")
    ]

    private static let confirmationRules: [Rule] = [
        Rule(pattern: #"(^|[;&|]\s*)git\s+(push|commit|tag|merge|rebase)(\s|$)"#, reason: "该 Git 操作会修改提交历史或远端状态。"),
        Rule(pattern: #"(^|[;&|]\s*)(rm|mv)\s+"#, reason: "该命令会删除或移动文件。"),
        Rule(pattern: #"(^|[;&|]\s*)docker(\s+compose)?\s+(down|restart|rm)(\s|$)"#, reason: "该命令会停止或删除容器资源。"),
        Rule(pattern: #"(^|[;&|]\s*)(kill|pkill|killall)(\s|$)"#, reason: "该命令会终止正在运行的进程。"),
        Rule(pattern: #"(^|[;&|]\s*)brew\s+(install|uninstall|upgrade|update)(\s|$)"#, reason: "该命令会修改本机工具或软件包。"),
        Rule(pattern: #"(^|[;&|]\s*)(npm|pnpm|yarn)\s+publish(\s|$)"#, reason: "发布命令可能影响公共或组织包仓库。"),
        Rule(pattern: #"(^|[;&|]\s*)kubectl\s+(apply|delete|rollout\s+restart|scale)(\s|$)"#, reason: "该命令会修改 Kubernetes 资源。")
    ]

    private static let directExecutionRules: [String] = [
        #"^(pwd|whoami|date|env)$"#,
        #"^(uname|which|type)(\s|$)"#,
        #"^(ls|tree|cat|head|tail|grep|rg)(\s|$)"#,
        #"^git\s+(status|diff|log|show|rev-parse)(\s|$)"#,
        #"^git\s+branch(\s+--(list|show-current))?$"#,
        #"^git\s+remote\s+(-v|get-url\s+[^\s]+)$"#,
        #"^(swift\s+(test|build)|xcodebuild\s+(-version|-list|build|test))(\s|$)"#,
        #"^(mvn|mvnw|\.\/mvnw)\s+(test|verify|package|compile)(\s|$)"#,
        #"^(gradle|\.\/gradlew)\s+(test|check|build|assemble)(\s|$)"#,
        #"^(npm|pnpm|yarn)\s+(test|run\s+(test|build|lint|typecheck)|build|lint)(\s|$)"#,
        #"^docker(\s+compose)?\s+(ps|logs|config|images|version)(\s|$)"#,
        #"^kubectl\s+(get|describe|logs)(\s|$)"#,
        #"^kubectl\s+config\s+(view|current-context|get-contexts)(\s|$)"#,
        #"^cargo\s+(test|check|build)(\s|$)"#,
        #"^(java|javac|node|npm|pnpm|yarn|python3?|ruby|go|rustc|cargo|swift)\s+--?version(\s|$)"#
    ]

    static func command(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func assess(_ command: String) -> ShellCommandAssessment {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()

        if containsRecursiveForcedRemoval(lowercased) {
            return ShellCommandAssessment(
                command: normalized,
                risk: .terminalOnly,
                reason: "递归强制删除必须在 Terminal 中人工检查。"
            )
        }
        if let rule = terminalOnlyRules.first(where: { matches($0.pattern, in: lowercased) }) {
            return ShellCommandAssessment(command: normalized, risk: .terminalOnly, reason: rule.reason)
        }
        if let rule = confirmationRules.first(where: { matches($0.pattern, in: lowercased) }) {
            return ShellCommandAssessment(command: normalized, risk: .confirm, reason: rule.reason)
        }
        if !containsShellComposition(lowercased),
           directExecutionRules.contains(where: { matches($0, in: lowercased) }) {
            return ShellCommandAssessment(
                command: normalized,
                risk: .low,
                reason: "已识别为只读、检查或构建命令，将在当前项目目录执行。"
            )
        }
        return ShellCommandAssessment(
            command: normalized,
            risk: .confirm,
            reason: "该命令不在直接执行白名单中，请检查目录和完整命令后确认。"
        )
    }

    private static func containsRecursiveForcedRemoval(_ value: String) -> Bool {
        guard matches(#"\brm\b"#, in: value) else { return false }
        let recursive = matches(#"(^|\s)-[a-z]*r[a-z]*(\s|$)"#, in: value)
            || matches(#"(^|\s)--recursive(\s|$)"#, in: value)
        let forced = matches(#"(^|\s)-[a-z]*f[a-z]*(\s|$)"#, in: value)
            || matches(#"(^|\s)--force(\s|$)"#, in: value)
        return recursive && forced
    }

    private static func containsShellComposition(_ value: String) -> Bool {
        value.range(of: #"[;&|`$<>]"#, options: .regularExpression) != nil
    }

    private static func matches(_ pattern: String, in value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

struct ShellCommandRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let command: String
    let workspaceName: String
    let workspacePath: String
    let startedAt: Date
    let finishedAt: Date
    let exitCode: Int32
    let outputTail: String

    init(
        id: UUID = UUID(),
        command: String,
        workspaceName: String,
        workspacePath: String,
        startedAt: Date,
        finishedAt: Date,
        exitCode: Int32,
        outputTail: String
    ) {
        self.id = id
        self.command = command
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.outputTail = outputTail
    }

    var succeeded: Bool { exitCode == 0 }
}

enum ShellCommandPersistenceStore {
    private static let key = "CodexBar.shellCommands.v1"

    static func load() -> [ShellCommandRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ShellCommandRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [ShellCommandRecord]) {
        guard let data = try? JSONEncoder().encode(Array(records.prefix(100))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

final class ShellCommandRunner {
    private let lock = NSLock()
    private let readLock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    func start(
        command: String,
        workspacePath: String,
        onOutput: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Int32, Error>) -> Void
    ) throws {
        lock.lock()
        guard process?.isRunning != true else {
            lock.unlock()
            throw CodexBarError.processAlreadyRunning
        }

        let task = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process = task
        stdoutPipe = stdout
        stderrPipe = stderr
        lock.unlock()

        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let script = "cd -- \(ShellUtilities.shellQuote(workspacePath)) && \(command)"
        task.arguments = ["-lic", script]
        task.currentDirectoryURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        task.standardOutput = stdout
        task.standardError = stderr

        let emit: (FileHandle) -> Void = { [weak self] handle in
            guard let self else { return }
            self.readLock.lock()
            let data = handle.availableData
            self.readLock.unlock()
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { onOutput(text) }
        }
        stdout.fileHandleForReading.readabilityHandler = emit
        stderr.fileHandleForReading.readabilityHandler = emit

        task.terminationHandler = { [weak self] finishedTask in
            guard let self else { return }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            self.readLock.lock()
            var remaining = stdout.fileHandleForReading.readDataToEndOfFile()
            remaining.append(stderr.fileHandleForReading.readDataToEndOfFile())
            self.readLock.unlock()

            self.lock.lock()
            self.process = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.lock.unlock()

            DispatchQueue.main.async {
                if !remaining.isEmpty {
                    onOutput(String(decoding: remaining, as: UTF8.self))
                }
                onCompletion(.success(finishedTask.terminationStatus))
            }
        }

        do {
            try task.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            process = nil
            stdoutPipe = nil
            stderrPipe = nil
            lock.unlock()
            throw CodexBarError.commandLaunchFailed(error.localizedDescription)
        }
    }

    func cancel() {
        lock.lock()
        let runningProcess = process
        lock.unlock()
        guard let runningProcess, runningProcess.isRunning else { return }
        runningProcess.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if runningProcess.isRunning {
                runningProcess.terminate()
            }
        }
    }

    deinit {
        cancel()
    }
}
