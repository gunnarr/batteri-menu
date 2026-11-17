import Foundation

/// The saved iCloud sign-in, shared with the `batteri` command-line tool.
public struct Account: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Account {
        if let override = environment["BATTERI_HOME"], !override.isEmpty {
            return Account(directory: URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        return Account(directory: homeDirectory.appendingPathComponent(".config/batteri"))
    }

    /// The Apple ID that was used to sign in, if any.
    public var appleID: String? {
        let file = directory.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "apple_id" else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            // The engine writes the value as a JSON string, which is also valid TOML.
            if let value = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Removes the saved session. This also signs out the command-line tool.
    public func signOut() throws {
        let manager = FileManager.default
        for name in ["session", "config.toml", "state.json"] {
            let url = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
            }
        }
    }
}
