import Foundation

// Timings and lengths only. Transcript text never goes to the log.
enum Log {
    static let path: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/Dictate.log"
    }()

    private static let queue = DispatchQueue(label: "dictate.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        queue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil)
            }
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                h.closeFile()
            }
        }
    }
}
