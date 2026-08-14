import Foundation

public enum HarnessURLParser {
    private static let prefix = "dsh web: "

    public static func parseReadyURL(from line: String) -> URL? {
        guard line.hasPrefix(prefix) else { return nil }
        let remainder = line.dropFirst(prefix.count)
        guard let firstToken = remainder.split(whereSeparator: \Character.isWhitespace).first,
              let components = URLComponents(string: String(firstToken)),
              components.scheme == "http",
              components.host == "127.0.0.1",
              components.user == nil,
              components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil,
              let port = components.port,
              (1...65_535).contains(port),
              let url = components.url
        else {
            return nil
        }
        return url
    }
}

public struct LineAccumulator {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return flush() }
        buffer.append(data)
        var lines: [String] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.last == "\r" { line.removeLast() }
            lines.append(line)
        }
        return lines
    }

    public mutating func flush() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: false)
        return [line]
    }
}
