import Foundation

actor GeminiCLIService: AICompletionService {
    private let model: String?
    private static let pathBox = PathBox()

    init(model: String? = nil) {
        self.model = model
    }

    func complete(input: String) async throws -> CompletionResult {
        let binPath = try await Self.pathBox.resolve()
        let combined = SYSTEM_PROMPT + "\n\n---INPUT---\n" + input

        var args: [String] = []
        if let model, !model.isEmpty {
            args.append(contentsOf: ["-m", model])
        }
        args.append(contentsOf: ["-p", combined])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = args
        // Ensure node/nvm and homebrew are on PATH for the child process.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            (env["HOME"].map { "\($0)/.nvm/versions/node" }) ?? ""
        ].filter { !$0.isEmpty }
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // Drain pipes off the actor to avoid potential blocking on large output.
        let (outData, errData) = await Task.detached {
            let o = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let e = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return (o, e)
        }.value
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw CompletionError.nonZeroExit(process.terminationStatus, stderr.isEmpty ? stdout : stderr)
        }

        return try parseCompletionJSON(stdout)
    }
}

private actor PathBox {
    private var cached: String?

    func resolve() async throws -> String {
        if let cached { return cached }

        let fm = FileManager.default
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""

        var candidates: [String] = [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
        ]

        // Probe nvm node versions for a `gemini` binary.
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            for v in versions {
                candidates.append("\(nvmRoot)/\(v)/bin/gemini")
            }
        }

        for path in candidates where fm.isExecutableFile(atPath: path) {
            cached = path
            return path
        }

        // Final fallback: ask a login shell.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "which gemini"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fm.isExecutableFile(atPath: path) {
                cached = path
                return path
            }
        } catch {}

        throw CompletionError.cliNotFound
    }
}
