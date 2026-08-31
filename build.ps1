#!/usr/bin/env pwsh
<#
.LICENSE
    GNU AFFERO GENERAL PUBLIC LICENSE
    Version 3, 19 November 2007

    Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
    Everyone is permitted to copy and distribute verbatim copies
    of this license document, but changing it is not allowed.

    This project is licensed under the GNU Affero General Public License
    version 3 or (at your option) any later version.

    The full license text is available in the repository LICENSE file:
    https://www.gnu.org/licenses/agpl-3.0.txt
.SYNOPSIS
    Generic build script for FS mods.
.DESCRIPTION
    Builds a distributable .zip mod artifact.
    Automatically detects mod name from modDesc.xml and FS version from directory name.

    -fs_ver accepts a single version or comma-separated list (e.g. 25,28).
    If omitted, defaults to the highest-numbered FS*_Src directory found.
.PARAMETER Command
    One of: build, release-test
.PARAMETER fs_ver
    FS version(s) as a comma-separated string. Defaults to latest FS*_Src found.
.PARAMETER mod_path
    Required mod base path containing FS*_Src directories.
.EXAMPLE
    .\build.ps1 build -mod_path <path-to-mod-root>
    .\build.ps1 build -mod_path <path-to-mod-root> -fs_ver 28
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("build", "release-test")]
    [string]$Command,

    [Alias("fs_ver")]
    [string]$FsVer,

    [Alias("mod_path")]
    [string]$ModPath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if ($RemainingArgs) {
    for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
        $arg = $RemainingArgs[$i]
        switch ($arg) {
            "--mod_path" {
                if ($i + 1 -ge $RemainingArgs.Count) {
                    Write-Error "--mod_path requires a value."
                    exit 1
                }
                $ModPath = $RemainingArgs[$i + 1]
                $i++
            }
            "-mod_path" {
                if ($i + 1 -ge $RemainingArgs.Count) {
                    Write-Error "-mod_path requires a value."
                    exit 1
                }
                $ModPath = $RemainingArgs[$i + 1]
                $i++
            }
            "--fs_ver" {
                if ($i + 1 -ge $RemainingArgs.Count) {
                    Write-Error "--fs_ver requires a value."
                    exit 1
                }
                $FsVer = $RemainingArgs[$i + 1]
                $i++
            }
            "-fs_ver" {
                if ($i + 1 -ge $RemainingArgs.Count) {
                    Write-Error "-fs_ver requires a value."
                    exit 1
                }
                $FsVer = $RemainingArgs[$i + 1]
                $i++
            }
            default {
                Write-Error "Unknown argument: $arg"
                exit 1
            }
        }
    }
}

if (-not $ModPath) {
    Write-Error "mod_path is required. Usage: .\build.ps1 <build|release-test> -mod_path <path> [-fs_ver VER]"
    exit 1
}

if (-not (Test-Path -Path $ModPath -PathType Container)) {
    Write-Error "mod_path does not exist or is not a directory: $ModPath"
    exit 1
}

$ModBasePath = (Resolve-Path -Path $ModPath).Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Extract mod name from modDesc.xml title element
function Get-ModNameFromDescriptor {
    param([string]$DescPath)
    if (-not (Test-Path $DescPath)) {
        Write-Error "modDesc.xml not found: $DescPath"
        exit 1
    }
    
    [xml]$xml = Get-Content $DescPath -Encoding UTF8
    $title = $xml.modDesc.title | Select-Object -First 1
    if ($title -is [string]) {
        $name = $title
    } else {
        $name = $title.en
    }
    
    if (-not $name) {
        Write-Error "Could not parse mod title from $DescPath"
        exit 1
    }
    
    # Convert to safe filename: remove spaces/special chars, keep alphanumeric and underscores
    $safeName = [regex]::Replace($name, '[^a-zA-Z0-9_]', '')
    return $safeName
}

# Find the highest-numbered FS*_Src directory
function Get-LatestFsVersion {
    param([string]$BasePath)

    $latest = $null
    Get-ChildItem -Path $BasePath -Directory -Filter "FS*_Src" | ForEach-Object {
        $n = $_.Name -replace '^FS(\d+)_Src$', '$1'
        if ($n -match '^\d+$') {
            $num = [int]$n
            if ($null -eq $latest -or $num -gt $latest) {
                $latest = $num
            }
        }
    }
    if ($null -eq $latest) {
        Write-Error "No FS*_Src directories found in $BasePath"
        exit 1
    }
    return $latest.ToString()
}

# Parse --fs_ver value (comma-separated) or detect latest
function Resolve-FsVersions {
    param([string]$Raw)
    if ($Raw) {
        return $Raw -split ',' | ForEach-Object { $_.Trim() }
    }
    return @(Get-LatestFsVersion -BasePath $ModBasePath)
}

function Invoke-Build {
    param([string]$FsVer, [string]$BasePath)

    $srcDir  = Join-Path $BasePath "FS${FsVer}_Src"
    $modDesc = Join-Path $srcDir "modDesc.xml"
    $modName = Get-ModNameFromDescriptor -DescPath $modDesc
    $zipName = "FS${FsVer}_${modName}"
    $outDir  = Join-Path $BasePath "dist"
    $zipPath = Join-Path $outDir "${zipName}.zip"

    if (-not (Test-Path $srcDir)) {
        Write-Error "Source directory not found: $srcDir"
        exit 1
    }

    Write-Host "Building ${zipName}.zip from FS${FsVer}_Src ..." -ForegroundColor Cyan

    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Remove previous artifact
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    # Stage into a temp dir
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "${zipName}-staging-$(Get-Random)"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    # Copy mod contents to staging
    Get-ChildItem -Path $srcDir -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            Copy-Item $_.FullName -Destination (Join-Path $staging $_.Name) -Recurse -Force
        } else {
            Copy-Item $_.FullName -Destination (Join-Path $staging $_.Name) -Force
        }
    }

    # Remove dev files (backups, logs)
    Get-ChildItem -Path $staging -Recurse -Filter '*.bak' | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $staging -Recurse -Filter '*.log' | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $staging -Recurse -Filter '*.png' | Remove-Item -Force -ErrorAction SilentlyContinue

    # Create zip using .NET ZipFile to ensure forward-slash paths (GIANTS Engine requires it)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipStream = [System.IO.File]::Create($zipPath)
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    $stagingFullPath = (Resolve-Path $staging).Path
    Get-ChildItem -Path $staging -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($stagingFullPath.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $relativePath, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $archive.Dispose()
    $zipStream.Dispose()

    # Cleanup
    Remove-Item $staging -Recurse -Force

    $sizeKB = [math]::Round((Get-Item $zipPath).Length / 1024, 1)
    Write-Host "  Created: $zipPath ($sizeKB KB)" -ForegroundColor Green
    Write-Host "Done." -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$fsVersions = @(Resolve-FsVersions -Raw $FsVer)

switch ($Command) {
    { $_ -in 'build', 'release-test' } {
        Invoke-Build -FsVer $fsVersions[0] -BasePath $ModBasePath
    }
}
