#!/usr/bin/env bash
# Stages the addon for one client flavor: stage_addon.sh <interface> <dest-dir>
# Copies GuildCensus/ (plus LICENSE) into <dest-dir>/ and sets that flavor's Interface
# number in the TOC. The repo's TOC targets Forever. Shared by the build and release
# workflows so both ship identical files.
set -euo pipefail

interface="${1:?usage: stage_addon.sh <interface> <dest-dir>}"
dest="${2:?usage: stage_addon.sh <interface> <dest-dir>}"

mkdir -p "$dest"
cp -r GuildCensus "$dest/"
cp LICENSE "$dest/GuildCensus/"
sed -i "s/^## Interface:.*/## Interface: $interface/" "$dest/GuildCensus/GuildCensus.toc"
grep -x "## Interface: $interface" "$dest/GuildCensus/GuildCensus.toc"
