# Changelog

## v1.0.0

Initial release -- fork of BatteryOptimizer_for_Mac with full rebrand.

- `battery` command renamed to `apple-juice`, config directory moved from `~/.battery` to `~/.apple-juice`
- Removed Electron GUI app (CLI only) and donation prompts
- Root-owned executables in `/usr/local/co.apple-juice` with symlinks in `/usr/local/bin`
- mktemp for visudo temp files, `-h` flag on chown calls to prevent symlink attacks

## v1.0.1

- Auto-detect installation directory for Homebrew compatibility
- Process detection fix (use `args` instead of `comm`)
- osascript quote escaping fix in setup dialog
- Removed Chinese language support (English only)
- Status now shows "Longevity mode active" when using longevity preset

## v1.0.2

- Create config file automatically if missing (fixes brew installs)

## v2.0.0

Complete rewrite from bash to Swift. Apple Silicon only.

- Native Swift binary via Swift Package Manager (no runtime dependencies)
- LaunchAgent with `KeepAlive` for automatic daemon restart on crash/SIGKILL/OOM
- IOKit direct battery reads (replaces `ioreg | grep | awk` chains)
- IOKit sleep/wake notifications with CHWA management (replaces sleepwatcher)
- `IOPMAssertionCreateWithName` for sleep prevention (replaces caffeinate)
- Startup recovery check: re-enables charging if daemon is not running
- SMC write verification with consecutive failure detection
- Serial dispatch queue for thread-safe SMC access across main loop, sleep/wake, and signal handlers
- Daemon lifecycle managed by `launchctl bootstrap`/`bootout` instead of `nohup`
- Config uses file-per-key storage with atomic writes (replaces single parsed file)
- Daily log rotation (365 entries), main log rotation (5MB threshold)
- `status --csv` flag for machine-readable output
- CI/CD: GitHub Actions for build/test and release binary generation
- Dropped Intel Mac support, bash script, sleepwatcher dependency, and sleep/wake hook scripts

## v2.0.1

- Resolve binary path when invoked via PATH

## v2.0.2

- Register maintain-daemon as top-level subcommand

## v2.0.3

- Daemon startup, cell voltage reading, and launchctl logging fixes

## v2.0.4

- Use stable symlink path in LaunchAgent plists (survives Homebrew upgrades)

## v2.0.5

- Redesigned status output with extended battery telemetry: capacity (mAh), adapter details, battery current draw, time estimates
- Cell imbalance warnings at >20mV and >=50mV
- Calibration skipped when cells are balanced (<50mV imbalance)

## v2.0.6

- Version line in status output with update check and brew upgrade command

## v2.0.7

- Safety recovery and watchdog now attempt to restart the daemon before falling back to re-enabling charging

## v2.0.8

- Status power description uses IOKit instead of lagging SMC keys
- Daemon applies charging control immediately on startup
- Status warns when longevity is configured but daemon isn't running

## v2.0.9

- `startDaemon()` ensures the LaunchAgent service is enabled before bootstrap, preventing `Input/output error` after `maintain stop` + `maintain longevity` cycle
- Suppressed expected launchctl bootout errors from user-facing output

## v2.1.0

- Added `aj` as a shorthand alias for the `apple-juice` CLI

## v2.1.1

- Safety watchdog switched from `StartInterval` (affected by kqueue sleep bug) to `StartCalendarInterval`, which coalesces missed intervals and fires on wake
- Always run launchctl enable/bootout/bootstrap for the safety daemon, even when the plist is unchanged on disk
- SMC failure backoff increased to 30s with threshold raised to 10 consecutive failures, preventing premature daemon exits during Power Nap

## v2.1.2

- Added delay and retry between launchd `bootout` and `bootstrap` calls, preventing bootstrap race conditions during daemon startup
- Removed immediate kickstart of the safety watchdog during daemon startup (was causing false "daemon not running" detection)
- `maintain` now waits up to 5s for the old daemon process to exit before starting the new one

## v3.0.0

Safety watchdog fix and CLI cleanup. **Breaking**: six commands removed (see below). Scripts referencing `aj schedule`, `aj ssd`, `aj dailylog`, `aj calibratelog`, `aj ssdlog`, or `aj reinstall` will fail with an unknown-command error.

- Safety watchdog stale PID detection now uses system uptime (monotonic clock) instead of wall clock time, preventing false triggers after sleep
- When a hung daemon is detected, the watchdog kills it for launchd restart instead of re-enabling charging (which fought the daemon's own control loop)
- Stale PID threshold tightened from 5 minutes to 2 minutes of awake time
- Removed commands: `schedule`, `ssd`, `ssd-log`, `daily-log`, `calibrate-log`, `reinstall`
- Hidden commands: `charge`, `discharge`, `visudo` (still functional, used internally)
- Longevity mode schedule setup no longer depends on the `schedule` command
- Added CodeRabbit configuration for automated PR reviews

## v3.0.1

- Daemon writes "sleeping" to PID file on willSleep so the safety watchdog skips the staleness check during Power Nap (the daemon is app-napped and can't update the PID file, but the process is healthy)
- Schedule plist is now recreated on every longevity activation, recovering from missing or corrupt files
