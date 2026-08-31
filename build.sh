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
# Generic build / release script for FS mods.
# Automatically detects mod name from modDesc.xml and FS version from directory name.
#
# Usage:
#   ./build.sh build --mod_path PATH [--fs_ver VER]          Build the zip artifact
#   ./build.sh release-test --mod_path PATH [--fs_ver VER]   Alias for build (local snapshot)
#   ./build.sh release <semver> --mod_path PATH [--fs_ver VER] Tag + push to trigger CI release
#
# --fs_ver accepts a single version or comma-separated list (e.g. 25,28).
# If omitted, defaults to the highest-numbered FS*_Src directory found.
#
# Examples:
#   ./build.sh build --mod_path /path/to/mod                # builds for latest FS version
#   ./build.sh build --mod_path /path/to/mod --fs_ver 28    # builds FS28_{ModName}.zip
#   ./build.sh release 1.0.0.0 --mod_path /path/to/mod
#   ./build.sh release 1.0.0.0 --mod_path /path/to/mod --fs_ver 25,28
#   ./build.sh release 1.0.0.0-beta.1 --mod_path /path/to/mod --fs_ver 25
#   ./build.sh release 1.0.0.0-alpha.1 --mod_path /path/to/mod

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    echo "  $0 release <semver> --mod_path PATH [--fs_ver VER]"
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

do_release() {
    local base_path="$1"
    local version="$2"
    shift 2
    local fs_versions=("$@")

    local tag="release/${version}"

    # Validate version format: X.Y.Z.W or X.Y.Z.W-prerelease.N
    if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z]+\.[0-9]+)?$'; then
        echo "ERROR: Invalid version format '${version}'." >&2
        echo "  Expected: X.Y.Z.W  or  X.Y.Z.W-alpha.N  or  X.Y.Z.W-beta.N" >&2
        exit 1
    fi

    # Validate that source dirs exist for all requested FS versions
    for fv in "${fs_versions[@]}"; do
        local src_dir="${base_path}/FS${fv}_Src"
        if [ ! -d "$src_dir" ]; then
            echo "ERROR: Source directory not found: ${src_dir}" >&2
            exit 1
        fi
    done

    # Ensure working tree is clean
    if [ -n "$(git -C "$base_path" status --porcelain)" ]; then
        echo "ERROR: Working tree is not clean. Commit or stash changes first." >&2
        exit 1
    fi

    # Build all versions locally to verify artifacts are valid
    for fv in "${fs_versions[@]}"; do
        do_build "$base_path" "$fv"
    done

    # Update fs_versions.json so CI knows which versions to build
    local json_array
    json_array=$(printf '%s\n' "${fs_versions[@]}" | jq -s '.')
    echo "{\"versions\": ${json_array}}" > "${base_path}/fs_versions.json"

    # Commit the config change
    git -C "$base_path" add fs_versions.json
    if ! git -C "$base_path" diff --cached --quiet; then
        git -C "$base_path" commit -m "Set build targets to FS$(IFS=,; echo "${fs_versions[*]}") for ${version}"
    fi

    echo ""
    local fs_list
    fs_list=$(IFS=', '; echo "${fs_versions[*]}")
    echo "Creating tag: ${tag} (FS versions: ${fs_list})"
    git -C "$base_path" tag -a "$tag" -m "Release ${version} (FS${fs_list})"

    echo "Pushing commit and tag to origin ..."
    git -C "$base_path" push origin HEAD "$tag"

    echo ""
    echo "Release tag '${tag}' pushed. CI will build and publish the GitHub release."
}

# ---------------------------------------------------------------------------
# Main — parse arguments
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

# Collect positional args and --fs_ver flag
POSITIONAL=()
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
            POSITIONAL+=("$1")
            shift
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
    build)
        do_build "$MOD_BASE_PATH" "${FS_VERSIONS[0]}"
        ;;
    release-test)
        do_build "$MOD_BASE_PATH" "${FS_VERSIONS[0]}"
        ;;
    release)
        if [ ${#POSITIONAL[@]} -lt 1 ]; then
            echo "ERROR: release requires a version argument." >&2
            usage
        fi
        do_release "$MOD_BASE_PATH" "${POSITIONAL[0]}" "${FS_VERSIONS[@]}"
        ;;
    *)
        echo "ERROR: Unknown command '${COMMAND}'" >&2
        usage
        ;;
esac
