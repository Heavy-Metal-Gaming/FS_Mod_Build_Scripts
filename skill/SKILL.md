# FS Mod Build Scripts — AI Skill Reference

> **IMPORTANT**: Every time this skill is invoked, reload it from disk first to ensure the latest revision is being used.

This document is the authoritative reference for any AI assistant working with the `FS_Mod_Build_Scripts` repo or any mod repo that uses it.

- **Repo**: `<your-org>/FS_Mod_Build_Scripts` on GitHub
- **Local clone**: `<clone-path>/FS_Mod_Build_Scripts`

---

## Scripts

| File | Platform |
|---|---|
| `build.ps1` | Windows PowerShell 7+ |
| `build.sh` | Linux / macOS / Git Bash |

Both scripts are functionally identical. `-mod_path` / `--mod_path` is required on every invocation.

---

## Usage

**PowerShell:**
```powershell
<clone-path>\FS_Mod_Build_Scripts\build.ps1 build -mod_path <path-to-mod>
<clone-path>\FS_Mod_Build_Scripts\build.ps1 build -mod_path <path-to-mod> -fs_ver 28
<clone-path>\FS_Mod_Build_Scripts\build.ps1 release-test -mod_path <path-to-mod>
```

**Bash:**
```bash
<clone-path>/FS_Mod_Build_Scripts/build.sh build --mod_path <path-to-mod>
<clone-path>/FS_Mod_Build_Scripts/build.sh build --mod_path <path-to-mod> --fs_ver 28
<clone-path>/FS_Mod_Build_Scripts/build.sh release-test --mod_path <path-to-mod>
```

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `build` / `release-test` | Yes (positional) | Command — both produce the same zip artifact. |
| `--mod_path` / `-mod_path` | Yes | Absolute path to the mod repo root. |
| `--fs_ver` / `-fs_ver` | No | FS version number(s), e.g. `25` or `25,28`. Defaults to highest-numbered `FS*_Src/` found. |

### What the build does

1. Reads mod name from `<mod_path>/FS<ver>_Src/modDesc.xml` `<title>` element.
2. Copies `FS<ver>_Src/` contents to a temp staging directory.
3. Strips `.bak`, `.log`, and `.png` files from the staging copy.
4. Creates `<mod_path>/dist/FS<ver>_<ModName>.zip` with forward-slash paths (required by GIANTS Engine).

---

## Expected mod folder structure

This is the canonical layout for FS mods. Use it to audit and restructure any mod repo.

```
<mod-root>/
├── FS25_Src/                    # Source for FS25 — becomes the zip contents
│   ├── modDesc.xml              # Mod name, version, dependencies
│   ├── icon_*.dds               # Mod icon (DDS format)
│   ├── scripts/                 # Lua scripts
│   │   ├── YourModName.lua      # Primary mod class
│   │   ├── *.lua
│   │   └── events/              # Network sync event classes
│   │       ├── *Event.lua
│   │       └── *InitialEvent.lua
│   ├── l10n/                    # Localization files
│   │   ├── l10n_template.xml
│   │   ├── l10n_en.xml
│   │   └── l10n_de.xml
│   ├── i3d/                     # 3D scene files (if applicable)
│   │   └── *.i3d, *.i3d.shapes
│   └── screenshots/             # Marketing screenshots (optional)
│       └── backup/
├── FS28_Src/                    # Optional — additional FS version
│   └── (same structure as FS25_Src)
├── docs/
│   ├── CONTRIBUTING.md
│   └── (project-specific docs)
├── tools/                       # Dev-only utility scripts; not shipped in zip
│   └── *.ps1
├── dist/                        # Created automatically by build scripts; git-ignored
│   └── FS25_<ModName>.zip
├── fs_versions.json             # Read by CI to determine which FS versions to build
├── README.md
└── .github/
    └── workflows/
        └── release.yml          # CI release workflow (copy from examples/release.yml here)
```

### Structure rules

- `FS*_Src/` is the **only** directory that becomes the distributed zip.
- `dist/` and `*.zip` must be git-ignored.
- `tools/` and `docs/` are tracked in git but never shipped.
- Build scripts are **not** in the mod repo root — they live in the shared `FS_Mod_Build_Scripts` clone.

---

## Restructuring a mod into the correct layout

When a mod's folder structure does not match the above, apply the following steps:

1. Identify all Lua scripts, `modDesc.xml`, DDS icons, l10n XMLs, and i3d files — these belong under `FS<ver>_Src/`.
2. Identify documentation files — move to `docs/`.
3. Identify utility/dev scripts — move to `tools/`.
4. Ensure `dist/` and `*.zip` are in `.gitignore`.
5. Ensure no `build.ps1` or `build.sh` exist in the mod root.
6. Create or update `fs_versions.json`:
   ```json
   {"versions":[25]}
   ```
7. Verify `modDesc.xml` has a parseable `<title>` — either a plain string or an `<en>` child element.

---

## Version tracking

`VERSION.txt` in the `FS_Mod_Build_Scripts` repo holds the canonical version string (e.g. `v1.3.0`). Both scripts embed the same version as a static string (`SCRIPT_VERSION` in bash, `$ScriptVersion` in PowerShell) and log it at startup. When `VERSION.txt` is updated, the embedded strings in both scripts must be updated to match.

---

## CI release workflow

`examples/release.yml` in the `FS_Mod_Build_Scripts` repo is a ready-to-copy GitHub Actions workflow for mod repos. It:

- Triggers on `release/*` (published) and `draft-release/*` (draft) tag pushes.
- Reads `fs_versions.json` to determine which FS versions to build.
- Downloads `build.sh` from a pinned or latest release of `FS_Mod_Build_Scripts`.
- Builds one zip per FS version and attaches all zips to a GitHub Release.

To trigger a release from a mod repo:
```bash
git tag release/1.0.0.0
git push origin release/1.0.0.0

# draft:
git tag draft-release/1.0.0.0-beta.1
git push origin draft-release/1.0.0.0-beta.1
```
