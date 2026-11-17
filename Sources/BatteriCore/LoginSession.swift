import Foundation

public enum LoginFailure: Equatable, Sendable {
    case badCredentials
    case securityKey
    case unsupportedVerification
    /// The engine could not be started or stopped answering.
    case engine
    case other(String)
}

public enum LoginReply: Equatable, Sendable {
    case signedIn
    /// Apple has sent a verification code. `retry` is true when the previous code was wrong.
    case needsCode(retry: Bool)
    case failed(LoginFailure)
}

/// One sign-in conversation with the engine (`batteri login --stdio`).
///
/// The engine process stays alive between the password and the verification code, because
/// it holds the half-finished iCloud session. The password is written to the engine's
/// standard input only; it is never passed as an argument, logged or stored.
public actor LoginSession {
    private let command: EngineCommand
    private var process: Process?
    private var input: FileHandle?
    private var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator?

    public init(command: EngineCommand) {
        self.command = command
    }

    public func start(appleID: String, password: String) async -> LoginReply {
        stop()
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments + ["login", "--stdio"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed(.engine)
        }
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.lines = stdout.fileHandleForReading.bytes.lines.makeAsyncIterator()
        return await exchange(["apple_id": appleID, "password": password])
    }

    public func submit(code: String) async -> LoginReply {
        guard process != nil else { return .failed(.engine) }
        return await exchange(["code": code])
    }

    /// Ends the conversation, for example when the window is closed.
    public func cancel() {
        stop()
    }

    private func stop() {
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        lines = nil
    }

    private func exchange(_ message: [String: String]) async -> LoginReply {
        guard let input, var iterator = lines,
              var data = try? JSONSerialization.data(withJSONObject: message) else {
            return .failed(.engine)
        }
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
            let line = try await iterator.next()
            lines = iterator
            guard let line else {
                stop()
                return .failed(.engine)
            }
            let reply = LoginSession.parse(line)
            if case .needsCode = reply { return reply }
            stop()
            return reply
        } catch {
            stop()
            return .failed(.engine)
        }
    }

    /// Decodes one line of the engine's protocol.
    public static func parse(_ line: String) -> LoginReply {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let state = object["state"] as? String else {
            return .failed(.engine)
        }
        let code = object["code"] as? String ?? ""
        switch state {
        case "ok":
            return .signedIn
        case "needs_code":
            return .needsCode(retry: code == "bad_code")
        default:
            switch code {
            case "bad_credentials": return .failed(.badCredentials)
            case "security_key": return .failed(.securityKey)
            case "unsupported_2sa": return .failed(.unsupportedVerification)
            default: return .failed(.other(object["message"] as? String ?? ""))
            }
        }
    }
}
