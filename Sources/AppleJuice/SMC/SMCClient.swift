import Foundation
import IOKit

/// Protocol for reading/writing SMC keys. Enables testing with mock implementations.
protocol SMCClientProtocol {
    /// Read a key's raw hex string (e.g., "02", "00000000").
    func readHex(_ key: SMCKey) -> String?

    /// Read a key's decimal value.
    func readDecimal(_ key: SMCKey) -> Int?

    /// Write a hex value to a key (requires sudo).
    @discardableResult
    func write(_ key: SMCKey, value: String) -> Bool

    /// Check if a key is available (returns data, not "no data").
    func keyAvailable(_ key: SMCKey) -> Bool
}

// MARK: - Default implementations

extension SMCClientProtocol {
    func readDecimal(_ key: SMCKey) -> Int? {
        guard let hex = readHex(key), !hex.isEmpty else { return nil }
        return Int(hex, radix: 16)
    }

    func keyAvailable(_ key: SMCKey) -> Bool {
        readHex(key) != nil
    }
}

// MARK: - SMC Binary Client

/// Reads and writes SMC keys by shelling out to the `smc` binary.
/// This is the primary write path on all macOS versions (entitlement-safe).
struct SMCBinaryClient: SMCClientProtocol {
    let smcPath: String

    init(smcPath: String = Paths.smcPath) {
        self.smcPath = smcPath
    }

    func readHex(_ key: SMCKey) -> String? {
        let result = ProcessRunner.run(smcPath, arguments: ["-k", key.rawValue, "-r"])
        return parseHexFromSMCOutput(result.stdout)
    }

    func write(_ key: SMCKey, value: String) -> Bool {
        let result = ProcessRunner.sudoSMC("-k", key.rawValue, "-w", value)
        return result.succeeded
    }

    /// Parse hex value from smc output.
    /// Input format: "  CH0B  [ui8 ]  (bytes 02)"
    /// Output: "02"
    func parseHexFromSMCOutput(_ output: String) -> String? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // "no data" means key not available
        if line.contains("no data") || line.contains("Error") {
            return nil
        }

        // Extract bytes after "bytes" and before ")"
        guard let bytesRange = line.range(of: "bytes") else { return nil }
        let afterBytes = line[bytesRange.upperBound...]
        let hex = afterBytes
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)

        return hex.isEmpty ? nil : hex
    }
}

// MARK: - IOKit SMC Client

/// Direct IOKit SMC reads (no subprocess overhead). Falls back to SMCBinaryClient for writes
/// and if IOKit open fails (macOS 15+ entitlement restriction on newly compiled binaries).
final class IOKitSMCClient: SMCClientProtocol {
    // SMC kernel interface constants
    private static let smcHandleYieldValue: UInt8 = 2
    private static let smcCmdReadKeyInfo: UInt8 = 9
    private static let smcCmdReadBytes: UInt8 = 5

    private var connection: io_connect_t = 0
    private let fallback: SMCBinaryClient
    private let ioKitAvailable: Bool

    init(smcPath: String = Paths.smcPath) {
        self.fallback = SMCBinaryClient(smcPath: smcPath)

        // Try to open IOKit connection to AppleSMC
        let service = IOServiceGetMatchingService(
            kIOMainPortCompat,
            IOServiceMatching("AppleSMC"))

        if service != 0 {
            var conn: io_connect_t = 0
            let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
            IOObjectRelease(service)

            if result == kIOReturnSuccess {
                self.connection = conn
                self.ioKitAvailable = true
            } else {
                self.ioKitAvailable = false
            }
        } else {
            self.ioKitAvailable = false
        }
    }

    deinit {
        if ioKitAvailable && connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readHex(_ key: SMCKey) -> String? {
        guard ioKitAvailable else { return fallback.readHex(key) }

        let keyName = key.rawValue
        guard keyName.count == 4 else { return fallback.readHex(key) }

        // Encode 4-char key as UInt32
        let keyBytes = Array(keyName.utf8)
        let keyCode = UInt32(keyBytes[0]) << 24
            | UInt32(keyBytes[1]) << 16
            | UInt32(keyBytes[2]) << 8
            | UInt32(keyBytes[3])

        // First: read key info to get data size and type
        var inputInfo = SMCParamStruct()
        inputInfo.key = keyCode
        inputInfo.data8 = Self.smcCmdReadKeyInfo

        var outputInfo = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let infoResult = IOConnectCallStructMethod(
            connection,
            UInt32(Self.smcHandleYieldValue),
            &inputInfo,
            MemoryLayout<SMCParamStruct>.stride,
            &outputInfo,
            &outputSize)

        guard infoResult == kIOReturnSuccess else { return fallback.readHex(key) }

        let dataSize = outputInfo.keyInfo.dataSize
        guard dataSize > 0, dataSize <= 32 else { return fallback.readHex(key) }

        // Second: read the actual bytes
        var inputRead = SMCParamStruct()
        inputRead.key = keyCode
        inputRead.keyInfo.dataSize = dataSize
        inputRead.data8 = Self.smcCmdReadBytes

        var outputRead = SMCParamStruct()
        outputSize = MemoryLayout<SMCParamStruct>.stride

        let readResult = IOConnectCallStructMethod(
            connection,
            UInt32(Self.smcHandleYieldValue),
            &inputRead,
            MemoryLayout<SMCParamStruct>.stride,
            &outputRead,
            &outputSize)

        guard readResult == kIOReturnSuccess else { return fallback.readHex(key) }

        // Convert bytes to hex string
        let bytes = outputRead.bytes
        let byteArray = withUnsafeBytes(of: bytes) { Array($0) }
        let hex = byteArray.prefix(Int(dataSize)).map { String(format: "%02x", $0) }.joined()

        return hex.isEmpty ? nil : hex
    }

    func write(_ key: SMCKey, value: String) -> Bool {
        // Writes always go through the smc binary (entitlement-safe path)
        fallback.write(key, value: value)
    }
}

// MARK: - SMC IOKit structs

/// Mirrors the kernel's SMCParamStruct used by IOConnectCallStructMethod.
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

/// Compatibility shim for kIOMainPortCompat across macOS versions.
private let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0 // kIOMasterPortDefault
    }
}()
