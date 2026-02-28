# Changelog

## v2.0.0

Complete rewrite from bash to Swift. Apple Silicon only.

### Added
- Native Swift binary via Swift Package Manager (no runtime dependencies)
- LaunchAgent with `KeepAlive` for automatic daemon restart on crash/SIGKILL/OOM
- IOKit direct battery reads (replaces all `ioreg | grep | awk` chains)
- IOKit sleep/wake notifications with CHWA management (replaces sleepwatcher)
- `IOPMAssertionCreateWithName` for sleep prevention (replaces caffeinate)
- Startup recovery check: re-enables charging if daemon is not running
- SMC write verification with consecutive failure detection
- Serial dispatch queue for thread-safe SMC access across main loop, sleep/wake, and signal handlers
- Daily log rotation (365 entries, ~1 year)
- Main log rotation (5MB threshold)
- PID file write error handling with stderr fallback
- `ProcessType: Interactive` and `ExitTimeOut: 30` in LaunchAgent plist
- LaunchAgent migration for v1.x users upgrading (auto-regenerates plist with KeepAlive)
- Config key migration from old formats
- `status --csv` flag for machine-readable output
- `advanceCalibrateNext` for proper `week_period`/`month_period` enforcement
- Webhook events for calibration Method 2
- CI/CD: GitHub Actions for build/test and release binary generation

### Changed
- Daemon lifecycle managed by `launchctl bootstrap`/`bootout` instead of `nohup`
- `maintain stop` uses `launchctl bootout` for clean daemon shutdown
- `uninstall` properly unloads LaunchAgent before removing plist
- Signal ACK setup occurs before sending SIGUSR1 (fixes race condition)
- Clean stop exits with code 0 (KeepAlive does not restart); crashes exit non-zero (restart)
- Config uses file-per-key storage with atomic writes (replaces single parsed file)
- All curl calls have `--max-time` timeouts with exponential backoff

### Removed
- Intel Mac support (Apple Silicon M1+ only)
- Bash script (`apple-juice.sh`)
- sleepwatcher dependency
- `setup.sh` (installation via Homebrew)
- Sleep/wake hook scripts (`.sleep`, `.wakeup`, `.reboot`, `.shutdown`)
- `notification_permission.scpt`
- `shutdown.sh` and `apple-juice_shutdown.plist`

## v1.0.2

### Fixed
- Create config file automatically if missing (fixes brew installs)

## v1.0.1

### Fixed
- Auto-detect installation directory for Homebrew compatibility
- Process detection now works correctly (use `args` instead of `comm`)
- osascript quote escaping in setup dialog

### Changed
- Removed Chinese language support (English only)
- Status now shows "Longevity mode active" when using longevity preset
- Clean up orphaned language config on update

## v1.0.0

Initial release - fork of BatteryOptimizer_for_Mac with full rebrand.

### Security
- Root-owned executables in `/usr/local/co.apple-juice`
- Symlinks in `/usr/local/bin` for PATH accessibility
- mktemp for visudo temp files (isolated from user config)
- `-h` flag on chown calls to prevent symlink attacks

### Changes
- Full rebrand: `battery` command is now `apple-juice`
- Config directory: `~/.battery` is now `~/.apple-juice`
- Removed Electron GUI app (CLI only)
- Removed donation prompts
