import Testing
import Foundation
@testable import apple_juice

@Suite("ConfigStore Tests")
struct ConfigStoreTests {
    let tempDir: String
    let store: ConfigStore

    init() throws {
        tempDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        store = ConfigStore(folder: tempDir)
    }

    // MARK: - Read

    @Test func readNonexistentKeyReturnsNil() {
        #expect(store.read("nonexistent") == nil)
    }

    @Test func readExistingKey() throws {
        let path = (tempDir as NSString).appendingPathComponent("test_key")
        try "hello".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(store.read("test_key") == "hello")
    }

    @Test func readTrimsWhitespace() throws {
        let path = (tempDir as NSString).appendingPathComponent("padded")
        try "  value  \n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(store.read("padded") == "value")
    }

    @Test func readEmptyFileReturnsNil() throws {
        let path = (tempDir as NSString).appendingPathComponent("empty")
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(store.read("empty") == nil)
    }

    @Test func readWhitespaceOnlyReturnsNil() throws {
        let path = (tempDir as NSString).appendingPathComponent("spaces")
        try "   \n  ".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(store.read("spaces") == nil)
    }

    // MARK: - Write

    @Test func writeCreatesFile() throws {
        try store.write("new_key", value: "new_value")
        let path = (tempDir as NSString).appendingPathComponent("new_key")
        #expect(FileManager.default.fileExists(atPath: path))
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == "new_value")
    }

    @Test func writeOverwritesExistingValue() throws {
        try store.write("key", value: "first")
        try store.write("key", value: "second")
        #expect(store.read("key") == "second")
    }

    @Test func writeNilDeletesFile() throws {
        try store.write("doomed", value: "exists")
        #expect(store.exists("doomed"))
        try store.write("doomed", value: nil)
        #expect(!store.exists("doomed"))
    }

    @Test func writeEmptyStringDeletesFile() throws {
        try store.write("doomed", value: "exists")
        try store.write("doomed", value: "")
        #expect(!store.exists("doomed"))
    }

    // MARK: - Delete

    @Test func deleteRemovesFile() throws {
        try store.write("target", value: "present")
        store.delete("target")
        #expect(store.read("target") == nil)
    }

    @Test func deleteNonexistentKeyDoesNotThrow() {
        store.delete("ghost")
    }

    // MARK: - Exists

    @Test func existsReturnsTrueForExistingKey() throws {
        try store.write("here", value: "yes")
        #expect(store.exists("here"))
    }

    @Test func existsReturnsFalseForMissingKey() {
        #expect(!store.exists("not_here"))
    }

    // MARK: - Directory creation

    @Test func writeCreatesDirectoryIfMissing() throws {
        let nested = tempDir + "/sub/dir"
        let nestedStore = ConfigStore(folder: nested)
        try nestedStore.write("deep", value: "val")
        #expect(nestedStore.read("deep") == "val")
    }

    // MARK: - Multi-word values (maintain_percentage format)

    @Test func readMultiWordValue() throws {
        try store.write("maintain_percentage", value: "80 50")
        #expect(store.read("maintain_percentage") == "80 50")
    }
}
