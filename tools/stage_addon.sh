#!/usr/bin/env bash
# Stages an addon for one client flavor: stage_addon.sh <interface> <dest-dir> [addon]
# Copies <addon>/ (default GuildCensus, plus LICENSE) into <dest-dir>/ and sets that flavor's
# Interface number in its TOC. The repo's TOCs target Forever. Shared by the build and release
# workflows so both ship identical files.
set -euo pipefail

interface="${1:?usage: stage_addon.sh <interface> <dest-dir> [addon]}"
dest="${2:?usage: stage_addon.sh <interface> <dest-dir> [addon]}"
addon="${3:-GuildCensus}"

mkdir -p "$dest"
cp -r "$addon" "$dest/"
cp LICENSE "$dest/$addon/"
rm -f "$dest/$addon/scratchpad.md" # working notes, not part of the addon
sed -i "s/^## Interface:.*/## Interface: $interface/" "$dest/$addon/$addon.toc"
grep -x "## Interface: $interface" "$dest/$addon/$addon.toc"
