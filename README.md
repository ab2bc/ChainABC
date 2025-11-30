# ChainABC Workspace

This workspace contains the management tools for the AQY blockchain ecosystem (a Sui fork/rebrand).

## Projects

### AManager
Windows Forms application for managing blockchain validators, genesis files, and network configuration.

- **Location**: `AManager/`
- **Repository**: https://github.com/ab2bc/AManager
- **Quick Start**: 
  ```bash
  cd AManager
  ./run.sh
  ```
- **Documentation**: See `AManager/BUILD.md` and `AManager/QUICKSTART.md`

### SuiRenamer
Tool for renaming and rebranding Sui blockchain code to AQY/ChainABC.

- **Location**: `SuiRenamer/`
- **Repository**: https://github.com/ab2bc/SuiRenamer
- **Purpose**: Automated code transformation and rebranding

## Quick Start

### Running AManager on Linux

```bash
cd AManager
./run.sh
```

**Requirements:**
- Wine with .NET Desktop Runtime 8
- Install: `winetricks dotnetdesktop8`

### Building

See individual project documentation:
- AManager: `AManager/BUILD.md`
- SuiRenamer: Check project documentation

## Repository Structure

```
ChainABC/
├── ChainABC.sln          # Visual Studio solution
├── AManager/             # Validator management tool (submodule)
├── SuiRenamer/           # Rebranding tool (submodule)
├── FIXES-APPLIED.md      # Applied fixes log
└── verify-templates.sh   # Template verification
```

## Git Repositories

This workspace uses git submodules:

- **Root**: ChainABC workspace configuration
- **AManager**: https://github.com/ab2bc/AManager (submodule)
- **SuiRenamer**: https://github.com/ab2bc/SuiRenamer (submodule)

Each project maintains its own repository and can be developed independently.

## Notes

- AManager and SuiRenamer are Windows Forms applications
- They run on Linux using Wine with .NET Desktop Runtime 8
- Pre-built binaries are included in each repository
- For development, Windows or Wine with .NET SDK is recommended

## Support

For issues or questions, refer to individual project repositories.
