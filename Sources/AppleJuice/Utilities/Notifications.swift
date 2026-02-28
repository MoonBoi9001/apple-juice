import Foundation

/// Wrappers around osascript for user notifications and dialogs.
enum Notifications {
    /// Display a macOS notification via osascript.
    static func displayNotification(message: String, title: String) {
        let escapedMessage = escapeOsascript(message)
        let escapedTitle = escapeOsascript(title)
        let script = "display notification '\(escapedMessage)' with title '\(escapedTitle)'"
        ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
    }

    /// Display a dialog with buttons and optional timeout.
    /// Returns the button clicked, or nil on timeout.
    @discardableResult
    static func displayDialog(
        message: String,
        buttons: [String] = ["OK"],
        timeout: Int? = nil
    ) -> String? {
        let escapedMessage = escapeOsascript(message)
        let buttonList = buttons.map { "\"" + escapeOsascript($0) + "\"" }.joined(separator: ", ")
        var script = "display dialog '\(escapedMessage)' buttons {\(buttonList)}"
        if let timeout {
            script += " giving up after \(timeout)"
        }

        let result = ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        if result.succeeded {
            // Parse "button returned:OK" from output
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = output.range(of: "button returned:") {
                return String(output[range.upperBound...])
            }
        }
        return nil
    }

    /// Escape single quotes for safe use in osascript.
    /// Matches bash: `printf '%s' "$1" | sed "s/'/'\\\\''/g"`
    private static func escapeOsascript(_ input: String) -> String {
        input.replacingOccurrences(of: "'", with: "'\\''")
    }
}
