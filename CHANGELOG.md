# Changelog

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
