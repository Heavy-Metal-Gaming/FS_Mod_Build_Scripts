# FS Mod Build Scripts

Cross-platform build and release scripts for Farming Simulator mods. Both scripts are functionally identical — `build.ps1` for Windows PowerShell, `build.sh` for Linux/macOS/Git Bash.

## Requirements

- A mod repository with one or more `FS<version>_Src/` directories containing a `modDesc.xml`
- `zip` or `git` (bash script), PowerShell 7+ (ps1 script)
- `git` and `jq` required for the `release` command

## Expected folder structure

```
<mod-root>/
├── FS25_Src/               # Source for FS25 — becomes the zip contents
│   ├── modDesc.xml         # Mod name and version are read from here
│   ├── scripts/
│   ├── l10n/
│   └── ...
├── FS28_Src/               # Optional — additional FS version
│   └── ...
├── dist/                   # Created automatically; holds build output
│   └── FS25_ModName.zip
└── fs_versions.json        # Written by the release command for CI
```

## How it works

The scripts read the mod name from `modDesc.xml` and auto-detect the FS version from the highest-numbered `FS*_Src/` directory found under the provided mod path. The output zip is written to `<mod_path>/dist/FS<version>_<ModName>.zip`.

Dev files (`.bak`, `.log`, `.png`) are excluded from the zip. Zip entries always use forward-slash paths, which is required by the GIANTS Engine.

## Commands

| Command | Description |
|---|---|
| `build` | Builds the zip artifact |
| `release-test` | Same as `build` (local snapshot) |
| `release <version>` | Builds, tags, and pushes to trigger CI release |

The `release` command requires a clean working tree, validates the version format (`X.Y.Z.W` or `X.Y.Z.W-alpha.N` / `-beta.N`), updates `fs_versions.json`, creates an annotated git tag (`release/<version>`), and pushes to origin.

## Usage

**PowerShell:**
```powershell
.\build.ps1 build -mod_path <path-to-mod-root>
.\build.ps1 build -mod_path <path-to-mod-root> -fs_ver 28
.\build.ps1 release 1.0.0.0 -mod_path <path-to-mod-root>
.\build.ps1 release 1.0.0.0 -mod_path <path-to-mod-root> -fs_ver 25,28
.\build.ps1 release 1.0.0.0-beta.1 -mod_path <path-to-mod-root> -fs_ver 25
```

**Bash:**
```bash
./build.sh build --mod_path <path-to-mod-root>
./build.sh build --mod_path <path-to-mod-root> --fs_ver 28
./build.sh release 1.0.0.0 --mod_path <path-to-mod-root>
./build.sh release 1.0.0.0 --mod_path <path-to-mod-root> --fs_ver 25,28
./build.sh release 1.0.0.0-beta.1 --mod_path <path-to-mod-root> --fs_ver 25
```

`--fs_ver` accepts a single version number or a comma-separated list (e.g. `25,28`). If omitted, the highest-numbered `FS*_Src/` directory is used.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).

