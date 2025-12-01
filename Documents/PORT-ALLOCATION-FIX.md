# Port Allocation Fix for Single-Server Deployment

## Problem
- Original design: All validators of same flavor+mode (e.g., AQY-G1, AQY-G2, AQY-G3) used **SAME ports**
- This required each validator to run on a **different IP address** (different physical servers)
- **Port conflicts** occurred when trying to run multiple validators on the same server for testing

## Solution
Changed port allocation scheme to add **per-validator index offsets**:
- Each validator gets unique ports: G1=+0, G2=+10, G3=+20, G4=+30, etc.
- Spacing: 10 ports per validator (UDP requires 5 ports: 25000-25004)
- Mode offsets preserved: G=+0, P=+50, F=+100
- Flavor offsets preserved: AQY=+0, ASY=+150, AUY=+300, etc.

## Changes Made

### 1. MainForm.cs - ComputeOffsetForIndex()
**Location:** Line ~2313

**OLD CODE:**
```csharp
private int ComputeOffsetForIndex(int oneBasedIndex)
{
    // All validators of the same flavor+mode use THE SAME offset
    // They run on different IP addresses (different physical servers)
    // No index offset - flavor+mode only
    return GetFlavorModeOffset(cmbNetwork.Text, GetCurrentMode());
}
```

**NEW CODE:**
```csharp
private int ComputeOffsetForIndex(int oneBasedIndex)
{
    // Multiple validators CAN run on the same server with different ports
    // Each validator gets a unique port offset:
    //   G1 = base + 0, G2 = base + 10, G3 = base + 20, etc.
    //   P1 = base + 50, P2 = base + 60, P3 = base + 70, etc.
    // This allows testing blockchain transactions on a single server
    int flavorModeBase = GetFlavorModeOffset(cmbNetwork.Text, GetCurrentMode());
    int validatorIndexOffset = (oneBasedIndex - 1) * 10;
    return flavorModeBase + validatorIndexOffset;
}
```

### 2. GenesisBaselineProcessor.cs - PortStep
**Location:** Line 16

**OLD:** `private const int PortStep = 50;`
**NEW:** `private const int PortStep = 10;`

**Comment Updated:**
```csharp
/// <summary>
/// For each validator (0-based index), add PortStep * validatorIndex to any /udp/<port>/ in the multiaddr.
/// Validator-1 (index 0) remains unchanged; Validator-2 (+10), Validator-3 (+20), etc.
/// This allows multiple validators to run on the same server without port conflicts.
/// </summary>
```

### 3. Template YAML Documentation Updated
- `/home/apollo/Apollo/mnt-ChainABC/ChainABC/AManager/fullnode.yaml`
- `/home/apollo/Apollo/mnt-ChainABC/ChainABC/AManager/validator.yaml`

Updated port allocation scheme comments to reflect new per-validator offsets.

## New Port Allocation Examples

### Single Server Deployment (192.168.12.100)

**AQY Validators:**
- AQY-G1: RPC=21000, Metrics=23000, UDP=25000-25004
- AQY-G2: RPC=21010, Metrics=23010, UDP=25010-25014
- AQY-G3: RPC=21020, Metrics=23020, UDP=25020-25024
- AQY-G4: RPC=21030, Metrics=23030, UDP=25030-25034

**AQY Post-Genesis:**
- AQY-P1: RPC=21050, Metrics=23050, UDP=25050-25054
- AQY-P2: RPC=21060, Metrics=23060, UDP=25060-25064

**AQY Full Nodes:**
- AQY-F1: RPC=21100, Metrics=23100, UDP=25100-25104
- AQY-F2: RPC=21110, Metrics=23110, UDP=25110-25114

**ASY Validators (different flavor):**
- ASY-G1: RPC=21150, Metrics=23150, UDP=25150-25154
- ASY-G2: RPC=21160, Metrics=23160, UDP=25160-25164

## Formula
```
Total Offset = FlavorOffset + ModeOffset + (ValidatorIndex - 1) * 10

Where:
  FlavorOffset: AQY=0, ASY=150, AUY=300, AIY=450, ARY=600, AGO=750, ABC=900
  ModeOffset:   G=0, P=50, F=100
  ValidatorIndex: 1, 2, 3, 4, ... (per-validator number)

Port = BasePort + TotalOffset
  BasePort: RPC=21000, Metrics=23000, UDP=25000
```

## Build Instructions

**Cannot build on Linux** (requires Windows Desktop SDK)

**Build in Wine/Windows:**
1. Open Visual Studio (or run in Wine)
2. Open AManager solution
3. Build > Build Solution (F6)

**Or use dotnet CLI in Windows:**
```bash
cd /path/to/ChainABC/AManager
dotnet build -c Debug
```

## Testing

After rebuilding:
1. Run AManager
2. Click "Generate All" to create genesis with multiple validators
3. Verify generated genesis YAML has unique ports:
   - AQY-G1: ports 25000-25004
   - AQY-G2: ports 25010-25014
   - AQY-G3: ports 25020-25024

## Benefits
✅ Multiple validators can run on **single server** for testing
✅ No port conflicts between G1, G2, G3, etc.
✅ Enables easy testing of blockchain transactions locally
✅ Maintains backward compatibility with flavor/mode offsets
