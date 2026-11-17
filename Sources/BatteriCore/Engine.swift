import Foundation

/// How to start the engine: the bundled Python, or a `batteri` command installed by the user.
public struct EngineCommand: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]

    public init(executable: URL, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum EngineError: Error, Equatable {
    /// Neither a bundled engine nor an installed `batteri` command was found.
    case notFound
    /// No saved iCloud session, or it has expired.
    case needsLogin
    case failed(String)
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}

/// Talks to the `batteri` command-line tool, which does the actual work.
public struct Engine: Sendable {
    /// Exit status the engine uses for "sign in first".
    public static let needsLoginStatus: Int32 = 3

    public let command: EngineCommand

    public init(command: EngineCommand) {
        self.command = command
    }

    /// Looks for the engine inside the app first, then in the usual install locations.
    public static func locate(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> EngineCommand? {
        if let override = environment["BATTERI_ENGINE"], isExecutable(override) {
            return EngineCommand(executable: URL(fileURLWithPath: override))
        }
        if let python = resourceURL?.appendingPathComponent("engine/python/bin/python3"),
           isExecutable(python.path) {
            // -I: ignore the user's Python settings. -B: never write into the signed app bundle.
            return EngineCommand(executable: python, arguments: ["-I", "-B", "-m", "batteri"])
        }
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/batteri").path,
            "/opt/homebrew/bin/batteri",
            "/usr/local/bin/batteri",
        ]
        for path in candidates where isExecutable(path) {
            return EngineCommand(executable: URL(fileURLWithPath: path))
        }
        return nil
    }

    public func devices(includeFamily: Bool) async throws -> [Device] {
        var arguments = ["--json"]
        if includeFamily { arguments.append("--familj") }
        let result: ProcessResult
        do {
            result = try await Engine.run(command, arguments: arguments)
        } catch {
            throw EngineError.failed(error.localizedDescription)
        }
        if result.status == Engine.needsLoginStatus {
            throw EngineError.needsLogin
        }
        guard result.status == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw EngineError.failed(message.isEmpty ? "The engine exited with status \(result.status)." : message)
        }
        do {
            return try JSONDecoder().decode([Device].self, from: result.stdout)
        } catch {
            throw EngineError.failed("Unexpected response from the engine.")
        }
    }

    /// Runs the engine to completion without blocking the caller's thread.
    public static func run(_ command: EngineCommand, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = command.executable
                process.arguments = command.arguments + arguments
                process.standardInput = FileHandle.nullDevice
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Drain both pipes while the process runs so a full pipe cannot stall it.
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus, stdout: outData, stderr: errData
                ))
            }
        }
    }
}
