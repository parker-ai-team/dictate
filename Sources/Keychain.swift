import Foundation

// The key lives in the login keychain as a generic password
// (service = the app's bundle id, account "anthropic").
// Read and write go through /usr/bin/security so the ACL stays
// bound to the security tool, not to this app's code signature.
// That survives rebuilds (ad-hoc signatures change every build)
// without a new "allow access" prompt.
enum Keychain {
    static let service = bundleIdentifier
    static let account = "anthropic"

    private static var cached: String?

    static func readAPIKey() -> String? {
        if let cached { return cached }
        let (status, out) = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        guard status == 0 else { return nil }
        let key = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        cached = key
        return key
    }

    static func hasAPIKey() -> Bool { readAPIKey() != nil }

    static func keyLength() -> Int { readAPIKey()?.count ?? 0 }

    @discardableResult
    static func writeAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let (status, _) = run([
            "add-generic-password", "-U",
            "-s", service, "-a", account,
            "-l", "Dictate - Anthropic API key",
            "-T", "/usr/bin/security",
            "-w", trimmed,
        ])
        if status == 0 { cached = trimmed }
        return status == 0
    }

    private static func run(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return (-1, "")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
