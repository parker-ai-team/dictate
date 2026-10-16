import Foundation

protocol SpeechToText {
    var name: String { get }
    func transcribe(wav: Data) async throws -> String
}

// Keeps whisper.cpp's server warm on localhost so the 1.6 GB model is loaded
// once, not per utterance. Measured on M4 Max: CLI cold start 1.6-2.1 s per
// clip, warm server 0.56-0.71 s for the same clips.
final class WhisperServerSTT: SpeechToText {
    let name = "whisper.cpp server (local)"

    private var process: Process?
    private let stateQueue = DispatchQueue(label: "dictate.whisper.state")
    private(set) var lastError: String?
    private var startingTask: Task<Bool, Never>?

    var serverPath: String { Settings.shared.whisperServerPath }
    var modelPath: String { Settings.shared.whisperModelPath }
    var port: Int { Settings.shared.whisperPort }
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    static let whisperLogPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/Dictate-whisper.log"
    }()

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    // True if a whisper server answers on the port.
    func isHealthy() async -> Bool {
        var req = URLRequest(url: baseURL)
        req.timeoutInterval = 1.0
        guard let result = try? await session.data(for: req) else { return false }
        let (data, resp) = result
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        let body = String(data: data, encoding: .utf8) ?? ""
        return body.lowercased().contains("whisper")
    }

    // Spawns the server if nothing healthy is on the port. Safe to call often.
    @discardableResult
    func ensureRunning() async -> Bool {
        if await isHealthy() { return true }
        // One spawn at a time; a second caller waits on the same task.
        let task: Task<Bool, Never> = stateQueue.sync {
            if let t = startingTask { return t }
            let t = Task<Bool, Never> { await self.spawnAndWait() }
            startingTask = t
            return t
        }
        let ok = await task.value
        stateQueue.sync { if startingTask == task { startingTask = nil } }
        return ok
    }

    private func spawnAndWait() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: serverPath) else {
            lastError = "whisper-server not found at \(serverPath)"
            Log.info("stt: \(lastError!)")
            return false
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            lastError = "model not found at \(modelPath)"
            Log.info("stt: \(lastError!)")
            return false
        }
        if let p = process, p.isRunning { p.terminate() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverPath)
        p.arguments = [
            "-m", modelPath,
            "-l", "auto",
            "--host", "127.0.0.1",
            "--port", String(port),
            "-nt",
            "-t", "4",
        ]
        FileManager.default.createFile(atPath: Self.whisperLogPath, contents: nil)
        if let h = FileHandle(forWritingAtPath: Self.whisperLogPath) {
            p.standardOutput = h
            p.standardError = h
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        p.terminationHandler = { proc in
            Log.info("stt: whisper-server exited with status \(proc.terminationStatus)")
        }
        do {
            try p.run()
        } catch {
            lastError = "could not start whisper-server: \(error.localizedDescription)"
            Log.info("stt: \(lastError!)")
            return false
        }
        process = p
        Log.info("stt: whisper-server started pid \(p.processIdentifier) on port \(port)")
        let t0 = Date()
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !p.isRunning {
                lastError = "whisper-server exited during start (see \(Self.whisperLogPath))"
                Log.info("stt: \(lastError!)")
                return false
            }
            if await isHealthy() {
                Log.info(String(format: "stt: whisper-server ready after %.1fs", Date().timeIntervalSince(t0)))
                lastError = nil
                return true
            }
        }
        lastError = "whisper-server did not become ready in 30s"
        Log.info("stt: \(lastError!)")
        return false
    }

    func stop() {
        if let p = process, p.isRunning {
            p.terminate()
            Log.info("stt: whisper-server terminated")
        }
        process = nil
    }

    func restart() async -> Bool {
        stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        return await ensureRunning()
    }

    func transcribe(wav: Data) async throws -> String {
        guard await ensureRunning() else {
            throw DictateError.engineNotReady(lastError ?? "unknown")
        }
        let boundary = "----DictateBoundary\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("response_format", "text")
        field("language", "auto")
        field("temperature", "0.0")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: baseURL.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw DictateError.sttFailed("HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return Self.clean(text)
    }

    // Drops whisper's non-speech markers like [BLANK_AUDIO], (silence), [Music].
    static func clean(_ raw: String) -> String {
        let pattern = #"[\[\(][^\]\)]{0,40}[\]\)]"#
        let stripped = raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
