import Foundation

/// Controls battery charging and discharging via SMC keys.
/// Apple Silicon only.
struct ChargingController {
    let client: SMCClientProtocol
    let caps: SMCCapabilities

    // MARK: - Charging control

    func enableCharging() {
        disableDischarging()
        log("Enabling battery charging")

        if caps.hasCH0B {
            if !client.write(.CH0B, value: SMCWriteValue.CH0B_enable) {
                log("Warning: Failed to set CH0B")
            }
        }
        if caps.hasCH0C {
            if !client.write(.CH0C, value: SMCWriteValue.CH0C_enable) {
                log("Warning: Failed to set CH0C")
            }
        }
        if caps.hasCHTE && !caps.hasCH0B {
            if !client.write(.CHTE, value: SMCWriteValue.CHTE_enable) {
                log("Warning: Failed to set CHTE")
            }
        }

        Thread.sleep(forTimeInterval: 1)
    }

    func disableCharging() {
        log("Disabling battery charging")

        if caps.hasCH0B {
            if !client.write(.CH0B, value: SMCWriteValue.CH0B_disable) {
                log("Warning: Failed to set CH0B")
            }
        }
        if caps.hasCH0C {
            if !client.write(.CH0C, value: SMCWriteValue.CH0C_disable) {
                log("Warning: Failed to set CH0C")
            }
        }
        if caps.hasCHTE && !caps.hasCH0B {
            if !client.write(.CHTE, value: SMCWriteValue.CHTE_disable) {
                log("Warning: Failed to set CHTE")
            }
        }

        Thread.sleep(forTimeInterval: 1)
    }

    // MARK: - Discharging control

    func enableDischarging() {
        disableCharging()
        log("Enabling battery discharging")

        if caps.hasCH0I {
            if !client.write(.CH0I, value: SMCWriteValue.CH0I_enable) {
                log("Warning: Failed to set CH0I")
            }
        } else {
            if caps.hasCH0J {
                if !client.write(.CH0J, value: SMCWriteValue.CH0J_enable) {
                    log("Warning: Failed to set CH0J")
                }
            }
            if caps.hasCHIE {
                if !client.write(.CHIE, value: SMCWriteValue.CHIE_enable) {
                    log("Warning: Failed to set CHIE")
                }
            }
        }
        if caps.hasACLC { client.write(.ACLC, value: SMCWriteValue.ACLC_discharge) }

        Thread.sleep(forTimeInterval: 1)
    }

    func disableDischarging() {
        log("Disabling battery discharging")

        if caps.hasCH0I {
            if !client.write(.CH0I, value: SMCWriteValue.CH0I_disable) {
                log("Warning: Failed to set CH0I")
            }
        } else {
            if caps.hasCH0J {
                if !client.write(.CH0J, value: SMCWriteValue.CH0J_disable) {
                    log("Warning: Failed to set CH0J")
                }
            }
            if caps.hasCHIE {
                if !client.write(.CHIE, value: SMCWriteValue.CHIE_disable) {
                    log("Warning: Failed to set CHIE")
                }
            }
        }
    }

    // MARK: - MagSafe LED

    enum LEDColor: String {
        case green, orange, none, off, auto
    }

    func changeMagSafeLED(_ color: LEDColor) {
        var resolvedColor = color

        if color == .auto {
            let state = getChargingState(using: client)
            switch state {
            case .charging:
                if caps.hasACLC {
                    let current = client.readHex(.ACLC) ?? ""
                    if current == "04" { return }
                }
                resolvedColor = .orange
            case .notCharging:
                if caps.hasACLC {
                    let current = client.readHex(.ACLC) ?? ""
                    if current == "03" { return }
                }
                resolvedColor = .green
            case .discharging:
                if caps.hasACLC {
                    let current = client.readHex(.ACLC) ?? ""
                    if current == "01" { return }
                }
                resolvedColor = .none
            }
        }

        guard caps.hasACLC else { return }

        log("Setting magsafe color to \(resolvedColor.rawValue)")

        switch resolvedColor {
        case .green:
            client.write(.ACLC, value: SMCWriteValue.ACLC_green)
        case .orange:
            client.write(.ACLC, value: SMCWriteValue.ACLC_orange)
        case .none:
            client.write(.ACLC, value: SMCWriteValue.ACLC_none)
        case .off, .auto:
            client.write(.ACLC, value: SMCWriteValue.ACLC_off)
        }
    }

    // MARK: - Status queries

    var chargingStatus: String {
        getSMCChargingStatus(using: client, caps: caps)
    }

    var dischargingStatus: String {
        getSMCDischargingStatus(using: client, caps: caps)
    }

    var chargingState: ChargingState {
        getChargingState(using: client)
    }
}
