import ArgumentParser
import Foundation

struct Visudo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "visudo",
        abstract: "Configure passwordless sudo for SMC operations"
    )

    func run() throws {
        log("Setting up visudo for apple-juice")

        let smcPath = Paths.smcPath
        let visudoConfig = """
        # Visudo settings for apple-juice installed from https://github.com/MoonBoi9001/apple-juice
        # intended to be placed in \(Paths.visudoFile) on a mac
        Cmnd_Alias      BATTERYOFF = \(smcPath) -k CH0B -w 02, \(smcPath) -k CH0C -w 02, \(smcPath) -k CHTE -w 01000000, \(smcPath) -k CH0B -r, \(smcPath) -k CH0C -r, \(smcPath) -k CHTE -r
        Cmnd_Alias      BATTERYON = \(smcPath) -k CH0B -w 00, \(smcPath) -k CH0C -w 00, \(smcPath) -k CHTE -w 00000000
        Cmnd_Alias      DISCHARGEOFF = \(smcPath) -k CH0I -w 00, \(smcPath) -k CH0I -r, \(smcPath) -k CH0J -w 00, \(smcPath) -k CH0J -r, \(smcPath) -k CH0K -w 00, \(smcPath) -k CH0K -r, \(smcPath) -k CHIE -w 00, \(smcPath) -k CHIE -r, \(smcPath) -d off
        Cmnd_Alias      DISCHARGEON = \(smcPath) -k CH0I -w 01, \(smcPath) -k CH0J -w 01, \(smcPath) -k CH0K -w 01, \(smcPath) -k CHIE -w 08, \(smcPath) -d on
        Cmnd_Alias      LEDCONTROL = \(smcPath) -k ACLC -w 04, \(smcPath) -k ACLC -w 03, \(smcPath) -k ACLC -w 02, \(smcPath) -k ACLC -w 01, \(smcPath) -k ACLC -w 00, \(smcPath) -k ACLC -r
        Cmnd_Alias      BATTERYCHWA = \(smcPath) -k CHWA -w 00, \(smcPath) -k CHWA -w 01, \(smcPath) -k CHWA -r
        Cmnd_Alias      BATTERYCHBI = \(smcPath) -k CHBI -r
        Cmnd_Alias      BATTERYB0AC = \(smcPath) -k B0AC -r
        Cmnd_Alias      PMSETWAKE = /usr/bin/pmset schedule wake *, /usr/bin/pmset schedule cancel wake *
        ALL ALL = NOPASSWD: BATTERYOFF
        ALL ALL = NOPASSWD: BATTERYON
        ALL ALL = NOPASSWD: DISCHARGEOFF
        ALL ALL = NOPASSWD: DISCHARGEON
        ALL ALL = NOPASSWD: LEDCONTROL
        ALL ALL = NOPASSWD: BATTERYCHWA
        ALL ALL = NOPASSWD: BATTERYCHBI
        ALL ALL = NOPASSWD: BATTERYB0AC
        ALL ALL = NOPASSWD: PMSETWAKE
        """

        // Write to temp file
        let tmpDir = NSTemporaryDirectory() + "apple-juice-visudo.\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let tmpFile = (tmpDir as NSString).appendingPathComponent("visudo.tmp")
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        try visudoConfig.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        // Check if existing file matches
        let cmpResult = ProcessRunner.shell("sudo cmp '\(Paths.visudoFile)' '\(tmpFile)' 2>/dev/null")
        if cmpResult.succeeded {
            print("The existing visudo file is what it should be for version v\(appVersion)")
            // Verify permissions
            let permsResult = ProcessRunner.shell("stat -f '%Lp' '\(Paths.visudoFile)'")
            if permsResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "440" {
                ProcessRunner.shell("sudo chmod 440 '\(Paths.visudoFile)'")
            }
            return
        }

        // Validate the visudo file
        let validateResult = ProcessRunner.shell("sudo visudo -c -f '\(tmpFile)' 2>/dev/null")
        guard validateResult.succeeded else {
            print("Error validating visudo file, this should never happen:")
            ProcessRunner.shell("sudo visudo -c -f '\(tmpFile)'")
            throw ExitCode.failure
        }

        // Create sudoers directory if needed
        ProcessRunner.shell("sudo mkdir -p '\(Paths.visudoFolder)'")

        // Install
        ProcessRunner.shell("sudo cp '\(tmpFile)' '\(Paths.visudoFile)'")
        ProcessRunner.shell("sudo chmod 440 '\(Paths.visudoFile)'")

        print("Visudo file updated successfully")
    }
}
