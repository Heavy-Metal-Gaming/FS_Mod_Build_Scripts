#!/usr/bin/env bash
#
# GNU AFFERO GENERAL PUBLIC LICENSE
# Version 3, 19 November 2007
#
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.
#
# This project is licensed under the GNU Affero General Public License
# version 3 or (at your option) any later version.
#
# The full license text is available in the repository LICENSE file:
# https://www.gnu.org/licenses/agpl-3.0.txt
#
# Generic build script for FS mods.
# Automatically detects mod name from modDesc.xml and FS version from directory name.
#
# Usage:
#   ./build.sh build --mod_path PATH [--fs_ver VER]
#   ./build.sh release-test --mod_path PATH [--fs_ver VER]   (alias for build)
#
# --fs_ver accepts a single version or comma-separated list (e.g. 25,28).
# If omitted, defaults to the highest-numbered FS*_Src directory found.
#
# Examples:
#   ./build.sh build --mod_path /path/to/mod
#   ./build.sh build --mod_path /path/to/mod --fs_ver 28    # builds FS28_{ModName}.zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="v1.2.0"
MOD_BASE_PATH=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Extract mod name from modDesc.xml title element
get_mod_name_from_descriptor() {
    local desc_path="$1"
    if [ ! -f "$desc_path" ]; then
        echo "ERROR: modDesc.xml not found: $desc_path" >&2
        exit 1
    fi
    
    # Extract first title element (English or first available)
    local title
    title=$(grep -oP '(?<=<title>)[^<]*(?=</title>)' "$desc_path" | head -1)
    
    if [ -z "$title" ]; then
        # Try to extract from <en> or <de> tags within <title>
        title=$(sed -n 's/.*<\(en\|de\)>\([^<]*\)<.*/\2/p' "$desc_path" | head -1)
    fi
    
    if [ -z "$title" ]; then
        echo "ERROR: Could not parse mod title from $desc_path" >&2
        exit 1
    fi
    
    # Convert to valid filename: remove spaces/special chars, keep alphanumeric and underscores
    echo "$title" | sed 's/[^a-zA-Z0-9_]//g'
}

# Find the highest-numbered FS*_Src directory
detect_latest_fs_version() {
    local base_path="$1"
    local latest=""
    for d in "${base_path}"/FS*_Src; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        local ver="${name#FS}"
        ver="${ver%_Src}"
        if [ -z "$latest" ] || [ "$ver" -gt "$latest" ] 2>/dev/null; then
            latest="$ver"
        fi
    done

    if [ -z "$latest" ]; then
        echo "ERROR: No FS*_Src directories found in ${base_path}" >&2
        exit 1
    fi
    echo "$latest"
}

# Parse comma-separated --fs_ver value into the FS_VERSIONS array
parse_fs_versions() {
    local raw="$1"
    IFS=',' read -ra FS_VERSIONS <<< "$raw"
}

usage() {
    echo "Usage:"
    echo "  $0 build --mod_path PATH [--fs_ver VER]"
    echo "  $0 release-test --mod_path PATH [--fs_ver VER]"
    echo ""
    echo "PATH is the mod base path containing FS*_Src directories."
    echo "VER is a single version (25) or comma-separated list (25,28)."
    echo "Defaults to the latest FS*_Src directory if omitted."
    exit 1
}

do_build() {
    local base_path="$1"
    local fs_ver="$2"
    local src_dir="${base_path}/FS${fs_ver}_Src"
    local mod_name=$(get_mod_name_from_descriptor "${src_dir}/modDesc.xml")
    local zip_name="FS${fs_ver}_${mod_name}"
    local out_dir="${base_path}/dist"
    local zip_path="${out_dir}/${zip_name}.zip"

    if [ ! -d "$src_dir" ]; then
        echo "ERROR: Source directory not found: ${src_dir}" >&2
        exit 1
    fi

    echo "Building ${zip_name}.zip from FS${fs_ver}_Src ..."

    mkdir -p "$out_dir"

    # Remove previous artifact
    rm -f "$zip_path"

    # Stage into a temp dir
    local staging
    staging="$(mktemp -d)"

    # Copy mod contents (exclude dev-only files)
    cp -r "$src_dir"/* "$staging/"

    # Remove dev files (backups, logs)
    find "$staging" -name '*.bak' -delete 2>/dev/null || true
    find "$staging" -name '*.log' -delete 2>/dev/null || true
    find "$staging" -name '*.png' -delete 2>/dev/null || true

    # Create the zip with contents at the archive root
    if command -v zip &>/dev/null; then
        (cd "$staging" && zip -r "$zip_path" .)
    elif command -v git &>/dev/null; then
        (cd "$staging" && git init -q && git add -A && git commit -qm "build" && git archive --format=zip -o "$zip_path" HEAD)
        rm -rf "$staging/.git"
    else
        echo "ERROR: No zip tool found. Install 'zip' or 'git'." >&2
        rm -rf "$staging"
        exit 1
    fi

    rm -rf "$staging"

    local size
    size=$(du -k "$zip_path" | cut -f1)
    echo "  Created: ${zip_path} (${size} KB)"
    echo "Done."
}

# ---------------------------------------------------------------------------
# Main — parse arguments
# ---------------------------------------------------------------------------
echo "FS Mod Build Scripts ${SCRIPT_VERSION}"

if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

# Collect --fs_ver flag
FS_VERSIONS=()
FS_VER_RAW=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mod_path)
            if [ $# -lt 2 ]; then
                echo "ERROR: --mod_path requires a value (path to mod base directory)" >&2
                exit 1
            fi
            MOD_BASE_PATH="$2"
            shift 2
            ;;
        --fs_ver)
            if [ $# -lt 2 ]; then
                echo "ERROR: --fs_ver requires a value (e.g. --fs_ver 25,28)" >&2
                exit 1
            fi
            FS_VER_RAW="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument '$1'" >&2
            usage
            ;;
    esac
done

if [ -z "$MOD_BASE_PATH" ]; then
    echo "ERROR: --mod_path is required." >&2
    usage
fi

if [ ! -d "$MOD_BASE_PATH" ]; then
    echo "ERROR: Mod base path not found: $MOD_BASE_PATH" >&2
    exit 1
fi

MOD_BASE_PATH="$(cd "$MOD_BASE_PATH" && pwd)"

# Parse --fs_ver or detect latest
if [ -n "$FS_VER_RAW" ]; then
    parse_fs_versions "$FS_VER_RAW"
else
    FS_VERSIONS=("$(detect_latest_fs_version "$MOD_BASE_PATH")")
fi

case "$COMMAND" in
    build|release-test)
        do_build "$MOD_BASE_PATH" "${FS_VERSIONS[0]}"
        ;;
    *)
        echo "ERROR: Unknown command '${COMMAND}'" >&2
        usage
        ;;
esac
