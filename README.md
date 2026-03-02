<div align="center">

# 🍎🧃 apple-juice

<br>

**Keep your Mac battery healthy, the secure way**

<br>

<a href="#-quick-start"><img src="https://img.shields.io/badge/Install-1a1a1a?style=for-the-badge" alt="Install"></a>
<a href="#-longevity-mode"><img src="https://img.shields.io/badge/Longevity_Mode-22c55e?style=for-the-badge" alt="Longevity Mode"></a>
<a href="#-how-it-works"><img src="https://img.shields.io/badge/How_It_Works-1a1a1a?style=for-the-badge" alt="How It Works"></a>
<a href="#-security"><img src="https://img.shields.io/badge/Security-1a1a1a?style=for-the-badge" alt="Security"></a>

<br>
<br>

*A security-hardened fork of [BatteryOptimizer_for_Mac](https://github.com/js4jiang5/BatteryOptimizer_for_Mac), rewritten in Swift.*

<img src="https://img.shields.io/badge/Apple_Silicon-black?style=flat-square&logo=apple&logoColor=white" alt="Apple Silicon">
<img src="https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
<img src="https://img.shields.io/badge/macOS_13+-1a1a1a?style=flat-square" alt="macOS 13+">

<br>
<br>

---

</div>

<br>

## 💚 Longevity Mode

<div align="center">

**The best way to preserve your Mac's battery health.**

</div>

<br>

```bash
brew install MoonBoi9001/tap/apple-juice
sudo apple-juice visudo
apple-juice maintain longevity
```

<br>

Three commands. Set it and forget it. Configure [macOS settings](#-setup) for notifications.

<br>

<div align="center">

| What it does | Why it matters |
|:---|:---|
| Maintains charge between **60-65%** | Sweet spot for lithium-ion longevity |
| Runs on wall power when plugged in | Battery sits idle at low voltage, minimal degradation |
| **Cell imbalance monitoring** | Shows per-cell voltages and imbalance in `status` |
| **BMS balancing** | Charges to 100% and holds for equalization when cells drift |

</div>

<br>

> Lithium-ion cells degrade faster at higher voltages. At 100% charge each cell sits at ~4.2V, accelerating chemical wear. At 60-65% the resting voltage drops to ~3.95V/cell, significantly reducing stress. Once the battery reaches 65%, charging is disabled. The laptop then runs entirely from wall power — no current flows through the battery at all. Charging re-enables if the battery drops below 60%.

<br>

---

<br>

## ⚡ Quick Start

**Homebrew (Apple Silicon only):**

```bash
brew install MoonBoi9001/tap/apple-juice
sudo apple-juice visudo
```

**Then run:**

```bash
apple-juice maintain longevity    # recommended
```

Or pick your own level:

```bash
apple-juice maintain 80           # maintain 75-80%
apple-juice maintain 80 50        # maintain 50-80%
```

<br>

---

<br>

## 🎯 All Commands

<br>

<details>
<summary><b>🔋 Battery Management</b></summary>

<br>

| Command | Description |
|:---|:---|
| `apple-juice maintain longevity` | **Recommended.** Maintain 60-65% for max lifespan |
| `apple-juice maintain 80` | Maintain 75-80% |
| `apple-juice maintain 80 50` | Maintain 50-80% |
| `apple-juice maintain suspend` | Temporarily charge to 100% |
| `apple-juice maintain recover` | Resume after suspend |
| `apple-juice maintain stop` | Disable completely |
| `apple-juice charge 90` | Charge to specific level |
| `apple-juice discharge 50` | Discharge to specific level |

</details>

<details>
<summary><b>🔄 Calibration</b></summary>

<br>

| Command | Description |
|:---|:---|
| `apple-juice calibrate` | Full calibration cycle |
| `apple-juice calibrate stop` | Stop calibration |
| `apple-juice balance` | Charges to 100%, holds 90 min for BMS equalization, then resumes previous mode |
| `apple-juice schedule` | Configure scheduled calibration |
| `apple-juice schedule disable` | Disable scheduled calibration |

</details>

<details>
<summary><b>📊 Monitoring</b></summary>

<br>

| Command | Description |
|:---|:---|
| `apple-juice status` | Health, temp, cycle count |
| `apple-juice status --csv` | Machine-readable CSV output |
| `apple-juice dailylog` | View daily battery log |
| `apple-juice calibratelog` | View calibration history |
| `apple-juice logs` | View CLI logs |
| `apple-juice ssd` | SSD health status |
| `apple-juice ssdlog` | SSD daily log |

</details>

<details>
<summary><b>⚙️ System</b></summary>

<br>

| Command | Description |
|:---|:---|
| `brew upgrade moonboi9001/tap/apple-juice` | Upgrade via Homebrew |
| `apple-juice update` | Update to latest version |
| `apple-juice version` | Show current version |
| `apple-juice changelog` | View latest changelog |
| `apple-juice reinstall` | Reinstall from scratch |
| `apple-juice uninstall` | Remove completely |

</details>

<br>

---

<br>

## 🔒 Security

The v2.0 rewrite eliminates entire classes of vulnerabilities present in the original bash implementation:

- No shell interpolation — native Swift binary, no bash/sed/awk attack surface
- Atomic file writes for all config and PID files
- Signal handler serialization via GCD (no re-entrancy)
- Input validation on all user-facing commands
- Process verification on PID files (confirms apple-juice owns the process)

SMC access is granted through visudo with specific command allowlists — only the exact `smc` key/value pairs needed for charging control are permitted.

<br>

---

<br>

## 🔧 How It Works

apple-juice runs as a background daemon managed by macOS `launchd`. It reads battery state through IOKit and controls charging via SMC keys using the bundled `smc` binary.

When the battery reaches the upper limit (65% in longevity mode), charging is disabled via SMC. The laptop continues to run entirely from wall power — the battery sits idle at its resting voltage with no current flowing. Charging only re-enables when the battery drops below the lower limit (60%), which only happens if you unplug.

The daemon is configured as a LaunchAgent with `KeepAlive`, so macOS automatically restarts it if the process dies unexpectedly. On clean shutdown (`maintain stop`), it re-enables charging and stays stopped. A startup recovery check runs before every command: if charging is found disabled but the daemon is not running, charging is re-enabled automatically. This ensures a Mac is never left in a non-charging state.

**Architecture:**

- Native Swift binary (no bash, no Python, no runtime dependencies)
- IOKit for direct battery reads (no `ioreg` subprocess overhead)
- IOKit power notifications for sleep/wake handling (no sleepwatcher dependency)
- `IOPMAssertionCreateWithName` for sleep prevention (no caffeinate)
- File-per-key config storage with atomic writes
- Serial dispatch queue for thread-safe SMC access

<br>

---

<br>

## 🗑️ Uninstalling

Always use `apple-juice uninstall` rather than `brew uninstall` directly. The uninstall command re-enables charging, stops the LaunchAgent, and cleans up all configuration files.

```bash
apple-juice uninstall
brew uninstall apple-juice    # optional, removes the binary
```

Running `brew uninstall` alone will remove the binary but leave the LaunchAgent plist and configuration in place.

<br>

---

<br>

## ⚙️ Setup

<div align="center">

<br>

**Three quick settings to configure:**

<br>

</div>

<table>
<tr>
<td>

```
🔋  STEP 1
```

</td>
<td>

**System Settings → Battery → Battery Health**

Turn off `Optimize Battery Charging`

</td>
</tr>
<tr>
<td>

```
🔔  STEP 2
```

</td>
<td>

**System Settings → Notifications**

Turn on `Allow notifications when mirroring or sharing`

</td>
</tr>
<tr>
<td>

```
📝  STEP 3
```

</td>
<td>

**System Settings → Notifications → Script Editor**

Select `Alerts`

</td>
</tr>
</table>

<br>

---

<br>

<div align="center">

**[🐛 Report Issue](https://github.com/MoonBoi9001/apple-juice/issues)** · **[⭐ Star on GitHub](https://github.com/MoonBoi9001/apple-juice)**

</div>

<br>

---

<div align="center">

<br>

```
                ╔═══════════════════════════════════════════════════════════════╗
                ║                                                               ║
                ║                        DISCLAIMER                             ║
                ║                                                               ║
                ║   This software is provided as-is, without warranty of any    ║
                ║   kind. Use at your own risk. Battery management involves     ║
                ║   low-level system operations. The authors are not liable     ║
                ║   for any damage to your device. Back up before use.          ║
                ║                                                               ║
                ╚═══════════════════════════════════════════════════════════════╝
```

<br>

<sub>Made with 🧃 by the community</sub>

<br>
<br>

</div>
