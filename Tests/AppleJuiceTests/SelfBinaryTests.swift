import Testing
import Foundation
@testable import apple_juice

@Suite("Self Binary Resolution Tests")
struct SelfBinaryTests {
    @Test func absolutePathIsKeptAsIs() {
        #expect(Paths.resolveSelfBinary(from: "/usr/bin/true") == "/usr/bin/true")
    }

    @Test func relativePathWithSlashIsAnchoredToCwd() {
        let resolved = Paths.resolveSelfBinary(from: "./some/dir/apple-juice")
        let cwd = FileManager.default.currentDirectoryPath
        #expect(resolved == "\(cwd)/some/dir/apple-juice")
    }

    @Test func bareNameIsResolvedThroughPath() {
        // Foundation's Process does no PATH lookup, so a bare argv[0] must
        // come back as an absolute path for self-invocations to launch.
        let resolved = Paths.resolveSelfBinary(from: "sh")
        #expect(resolved.hasPrefix("/"))
        #expect(FileManager.default.isExecutableFile(atPath: resolved))
    }

    @Test func unresolvableBareNameFallsBackToInput() {
        let resolved = Paths.resolveSelfBinary(from: "definitely-not-a-real-binary-xyz")
        #expect(resolved == "definitely-not-a-real-binary-xyz")
    }
}
