# FS Mod Build Scripts

Cross-platform build and release scripts for Farming Simulator mods. Both scripts are functionally identical — `build.ps1` for Windows PowerShell, `build.sh` for Linux/macOS/Git Bash.

## Requirements

- A mod repository with one or more `FS<version>_Src/` directories containing a `modDesc.xml`
- `zip` or `git` (bash script), PowerShell 7+ (ps1 script)

## Expected folder structure

```
<mod-root>/
├── FS25_Src/               # Source for FS25 — becomes the zip contents
│   ├── modDesc.xml         # Mod name and version are read from here
│   ├── icon_*.dds
│   ├── scripts/
│   │   ├── YourModName.lua
│   │   └── events/
│   ├── l10n/
│   ├── i3d/
│   └── screenshots/
├── FS28_Src/               # Optional — additional FS version
│   └── ...
├── docs/
├── tools/
├── dist/                   # Created automatically; holds build output
│   └── FS25_ModName.zip
└── fs_versions.json        # Read by CI to determine which FS versions to build
```

## How it works

The scripts read the mod name from `modDesc.xml` and auto-detect the FS version from the highest-numbered `FS*_Src/` directory found under the provided mod path. The output zip is written to `<mod_path>/dist/FS<version>_<ModName>.zip`.

Dev files (`.bak`, `.log`, `.png`) are excluded from the zip. Zip entries always use forward-slash paths, which is required by the GIANTS Engine.

## Commands

| Command | Description |
|---|---|
| `build` | Builds the zip artifact |
| `release-test` | Alias for `build` (local snapshot) |

## Usage

**PowerShell:**
```powershell
.\build.ps1 build -mod_path <path-to-mod-root>
.\build.ps1 build -mod_path <path-to-mod-root> -fs_ver 28
```

**Bash:**
```bash
./build.sh build --mod_path <path-to-mod-root>
./build.sh build --mod_path <path-to-mod-root> --fs_ver 28
```

`--fs_ver` accepts a single version number or a comma-separated list (e.g. `25,28`). If omitted, the highest-numbered `FS*_Src/` directory is used.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).

