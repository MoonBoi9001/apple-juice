#!/bin/bash

# update.sh -- Migration-aware update script for apple-juice
#
# This script handles upgrading apple-juice to the latest Swift binary release.
# Bash v1.x users running `apple-juice update` will download this script and
# get migrated to the Swift binary automatically.
#
# Apple Silicon (M1+) only.

set -euo pipefail

function read_config() {
	local name=$1
	cat "$configfolder/$name" 2>/dev/null || true
}

function write_config() {
	local name=$1
	local val=$2
	mkdir -p "$configfolder"
	if [[ -n "$val" ]]; then
		echo "$val" > "$configfolder/$name"
	else
		rm -f "$configfolder/$name"
	fi
}

# Check architecture
if [[ $(uname -m) != "arm64" ]]; then
	echo "Error: apple-juice requires Apple Silicon (M1 or later)."
	echo "Intel Macs are not supported in v2.x."
	exit 1
fi

# Force-set path to include sbin
PATH="/usr/local/co.apple-juice:$PATH:/usr/sbin"

# Set environment variables
tempfolder=$(mktemp -d "${TMPDIR:-/tmp}/apple-juice-update.XXXXXX")
trap 'rm -rf "$tempfolder"' EXIT
binfolder=/usr/local/co.apple-juice
configfolder=$HOME/.apple-juice
github_repo="MoonBoi9001/apple-juice"

echo -e "Starting apple-juice update\n"

# Ensure binfolder exists with correct ownership
if [[ ! -d "$binfolder" ]]; then
	sudo install -d -m 755 -o root -g wheel "$binfolder"
fi

# Cleanup old installations from /usr/local/bin (migration from vulnerable versions)
for f in apple-juice smc shutdown.sh; do
	if [[ -f "/usr/local/bin/$f" && ! -L "/usr/local/bin/$f" ]]; then
		sudo rm -f "/usr/local/bin/$f"
	fi
done

# Fetch the latest release from GitHub API
echo "[ 1 ] Checking for latest release"
latest_release=$(curl -sSL --max-time 10 "https://api.github.com/repos/$github_repo/releases/latest" 2>/dev/null || true)

# Extract download URL and version
download_url=$(echo "$latest_release" | grep -o '"browser_download_url":\s*"[^"]*arm64\.tar\.gz"' | head -1 | sed 's/"browser_download_url":\s*"//;s/"$//')
version_new=$(echo "$latest_release" | grep -o '"tag_name":\s*"[^"]*"' | head -1 | sed 's/"tag_name":\s*"//;s/"$//')

if [[ -z "$download_url" ]]; then
	echo "Error: could not find a release to download"
	exit 1
fi

echo "[ 2 ] Downloading Swift binary ($version_new)"
curl -sSL --max-time 60 -o "$tempfolder/apple-juice.tar.gz" "$download_url"
mkdir -p "$tempfolder/extract"
tar xzf "$tempfolder/apple-juice.tar.gz" -C "$tempfolder/extract"

echo "[ 3 ] Installing apple-juice binary"
sudo cp "$tempfolder/extract/apple-juice" "$binfolder/apple-juice"
sudo chown root:wheel "$binfolder/apple-juice"
sudo chmod 755 "$binfolder/apple-juice"

# Install smc binary (included in the tarball)
if [[ -f "$tempfolder/extract/smc" ]]; then
	sudo cp "$tempfolder/extract/smc" "$binfolder/smc"
	sudo chown root:wheel "$binfolder/smc"
	sudo chmod 755 "$binfolder/smc"
fi

# Create/update symlinks in /usr/local/bin for PATH accessibility
sudo mkdir -p /usr/local/bin
sudo ln -sf "$binfolder/apple-juice" /usr/local/bin/apple-juice
sudo chown -h root:wheel /usr/local/bin/apple-juice
sudo ln -sf "$binfolder/smc" /usr/local/bin/smc
sudo chown -h root:wheel /usr/local/bin/smc

echo "[ 4 ] Setting up visudo"
sudo "$binfolder/apple-juice" visudo

echo "[ 5 ] Running migration"
mkdir -p "$configfolder"

# Migrate old single-file config to file-per-key format
old_config="$configfolder/config"
if [[ -f "$old_config" ]]; then
	while IFS=' = ' read -r key val; do
		[[ -n "$key" && "$key" != "#"* ]] && echo "$val" > "$configfolder/$key"
	done < "$old_config"
	mv "$old_config" "$old_config.migrated"
fi

# Migrate old config key names
if [[ -f "$configfolder/informed.version" && ! -f "$configfolder/informed_version" ]]; then
	cp "$configfolder/informed.version" "$configfolder/informed_version"
	rm -f "$configfolder/informed.version"
fi
if [[ -f "$configfolder/maintain.percentage" && ! -f "$configfolder/maintain_percentage" ]]; then
	cp "$configfolder/maintain.percentage" "$configfolder/maintain_percentage"
	rm -f "$configfolder/maintain.percentage"
fi
if [[ -f "$configfolder/ha_webhook.id" && ! -f "$configfolder/webhookid" ]]; then
	cp "$configfolder/ha_webhook.id" "$configfolder/webhookid"
	rm -f "$configfolder/ha_webhook.id"
fi

# Clean up deprecated config files
rm -f "$configfolder/sig" "$configfolder/state" "$configfolder/language.code" "$configfolder/language"

# Clean up sleepwatcher hooks (no longer needed -- Swift uses IOKit)
for f in .sleep .wakeup; do
	hook="$HOME/$f"
	if [[ -f "$hook" ]] && grep -qE "apple-juice|\.battery" "$hook" 2>/dev/null; then
		rm -f "$hook"
	fi
done
# Remove shutdown LaunchAgent and script
rm -f "$HOME/Library/LaunchAgents/apple-juice_shutdown.plist"
sudo rm -f "$binfolder/shutdown.sh" /usr/local/bin/shutdown.sh 2>/dev/null

# Remove Intel smc binary if present
sudo rm -f "$binfolder/smc_intel" /usr/local/bin/smc_intel 2>/dev/null

write_config informed_version "$version_new"

# Restart maintain
echo "[ 6 ] Restarting apple-juice maintain"
pkill -f "$binfolder/apple-juice " 2>/dev/null || true
sleep 1
pkill -9 -f "$binfolder/apple-juice " 2>/dev/null || true
"$binfolder/apple-juice" maintain recover 2>/dev/null || true

echo -e "\napple-juice updated to $version_new.\n"
osascript -e "display dialog \"Updated to $version_new\" buttons {\"Done\"} default button 1 with icon note with title \"apple-juice\"" 2>/dev/null || true
