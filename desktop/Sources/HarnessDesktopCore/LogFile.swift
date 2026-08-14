import Foundation

public final class LogFile {
    private let fileURL: URL
    private let maximumBytes: UInt64
    private let queue = DispatchQueue(label: "com.deepseek.harness.desktop.log")
    private let fileManager: FileManager

    public init(fileURL: URL, maximumBytes: UInt64 = 2 * 1_024 * 1_024, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
        self.fileManager = fileManager
    }

    public func append(_ message: String) {
        queue.async { [fileURL, maximumBytes, fileManager] in
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Self.rotateIfNeeded(
                    fileURL: fileURL,
                    maximumBytes: maximumBytes,
                    fileManager: fileManager
                )
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let data = Data("\(timestamp) \(message)\n".utf8)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileManager.createFile(atPath: fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fputs("DeepSeek Harness logging failed: \(error)\n", stderr)
            }
        }
    }

    public func flush() {
        queue.sync {}
    }

    private static func rotateIfNeeded(
        fileURL: URL,
        maximumBytes: UInt64,
        fileManager: FileManager
    ) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value >= maximumBytes
        else {
            return
        }

        let rotated = fileURL.appendingPathExtension("1")
        if fileManager.fileExists(atPath: rotated.path) {
            try fileManager.removeItem(at: rotated)
        }
        try fileManager.moveItem(at: fileURL, to: rotated)
    }
}
