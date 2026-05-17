import Foundation

enum Diagnostics {
    private static let logURL: URL = {
        let dir = URL(fileURLWithPath: "/tmp")
        return dir.appendingPathComponent("promptmaker.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String, file: String = #file, line: Int = #line) {
        let basename = (file as NSString).lastPathComponent
        let line = "\(formatter.string(from: Date())) [\(basename):\(line)] \(message)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
        if let h = try? FileHandle(forWritingTo: logURL) {
            _ = try? h.seekToEnd()
            h.write(line.data(using: .utf8) ?? Data())
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL)
        }
    }
}
