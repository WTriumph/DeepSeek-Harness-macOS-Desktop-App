import Foundation
import HarnessDesktopCore
import Testing

@Suite("Harness ready URL parsing")
struct HarnessURLParserTests {
    @Test func parsesStrictLoopbackReadyLine() {
        #expect(
            HarnessURLParser.parseReadyURL(from: "dsh web: http://127.0.0.1:43123")?.absoluteString
                == "http://127.0.0.1:43123"
        )
    }

    @Test func acceptsDisplaySuffixButNotURLPath() {
        #expect(
            HarnessURLParser.parseReadyURL(
                from: "dsh web: http://127.0.0.1:43123 (LAN: http://192.168.1.2:43123)"
            )?.port == 43_123
        )
        #expect(HarnessURLParser.parseReadyURL(from: "dsh web: http://127.0.0.1:43123/admin") == nil)
    }

    @Test func rejectsRemoteOrAmbiguousAuthorities() {
        let invalid = [
            "dsh web: https://127.0.0.1:43123",
            "dsh web: http://localhost:43123",
            "dsh web: http://0.0.0.0:43123",
            "dsh web: http://127.0.0.1",
            "dsh web: http://user@127.0.0.1:43123",
            "prefix dsh web: http://127.0.0.1:43123",
            "dsh web: http://127.0.0.1:70000",
        ]
        for value in invalid {
            #expect(HarnessURLParser.parseReadyURL(from: value) == nil, Comment(rawValue: value))
        }
    }

    @Test func lineAccumulatorHandlesPartialAndCRLFLines() {
        var accumulator = LineAccumulator()
        #expect(accumulator.append(Data("one".utf8)) == [])
        #expect(accumulator.append(Data(" two\r\nthree\npart".utf8)) == ["one two", "three"])
        #expect(accumulator.append(Data()) == ["part"])
    }
}
