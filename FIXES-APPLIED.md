# Fixes Applied - November 30, 2025

## Issues Resolved from FIX.md

### 1. ✅ Full Node Genesis Path Configuration - FIXED

**Issue**: Full nodes fail with "Unable to load Genesis from /genesis/genesis.blob"

**Root Cause**: Container mounts genesis to `/work/genesis` but config used `/genesis`

**Fix Applied**:
- Updated `fullnode.yaml` template: Changed genesis path to `/work/genesis/genesis.blob`
- Updated `validator.yaml` template: Changed genesis path to `/work/genesis/genesis.blob`
- Updated comments to reflect correct mount point: `/work/genesis`

**Files Modified**:
- `/mnt/c/Apollo/ChainABC/AManager/fullnode.yaml`
- `/mnt/c/Apollo/ChainABC/AManager/validator.yaml`

---

### 2. ✅ P2P Listen Address Format - ALREADY CORRECT

**Issue**: Docker image requires `IP:PORT` format, not QUIC multiaddr for `listen-address`

**Status**: Templates already use correct format

**Verified**:
- validator.yaml: `listen-address: "0.0.0.0:25000"` ✓
- fullnode.yaml: `listen-address: 0.0.0.0:25000` ✓
- external-address correctly uses QUIC multiaddr format ✓

**Code Verification**:
- `UpdateYaml.cs` line 268: Uses `ip + ":" + p2pPort` format ✓
- No multiaddr format for listen-address in code ✓

---

### 3. ✅ Port Offset System - VERIFIED CORRECT

**Status**: No index offset as required

**Verified**:
- All validators of same flavor+mode use SAME ports (different IPs)
- `ComputeOffsetForIndex()`: Returns `GetFlavorModeOffset()` only (no index addition)
- `DockerScript.ComputeFixedOffset()`: Returns flavor+mode offset only
- Port allocation: Flavor base (0/150/300/450/600/750/900) + Mode offset (0/50/100)

**Examples**:
- AQY-G1, AQY-G2, AQY-G3: All use UDP 25000 (different IPs)
- AQY-P1, AQY-P2: All use UDP 25050 (different IPs)
- AQY-F*: All use UDP 25100 (different IPs)

---

### 4. ⚠️ Docker Permission Issues - NOTED

**Issue**: Deployment requires sudo for Docker access

**Status**: Known issue documented - deployment scripts should use sudo

**Workaround**: Run deployment with `sudo bash deploy-*.sh`

**Future Enhancement**: Script could add docker permission check at startup

---

## Summary of Changes

### Template Files Updated:

1. **validator.yaml**:
   - Genesis path: `/genesis/genesis.blob` → `/work/genesis/genesis.blob`
   - Container mount comment updated
   - listen-address format: Already correct `"0.0.0.0:25000"`

2. **fullnode.yaml**:
   - Genesis path: `/genesis/genesis.blob` → `/work/genesis/genesis.blob`
   - Updated comment: Removed incorrect "QUIC multiaddr required" note
   - Added note: "listen-address uses IP:PORT format (ghcr.io/ab2bc/aqy-node:dev requirement)"
   - listen-address format: Already correct `0.0.0.0:25000`

### Code Verification:

- ✅ `MainForm.cs`: Port calculation verified - no index offset
- ✅ `DockerScript.cs`: Offset calculation verified - flavor+mode only
- ✅ `UpdateYaml.cs`: listen-address uses IP:PORT format
- ✅ Build successful: 0 errors, warnings only in SuiRenamerLib (not AManager)

---

## Testing Recommendations

After deploying with updated templates:

1. **Generate new node configs** using the application
2. **Verify ZIP files** contain correct paths:
   ```bash
   unzip -p nodes/AQY-F1/AQY-F1.zip fullnode.yaml | grep "genesis-file-location"
   # Should show: /work/genesis/genesis.blob
   
   unzip -p nodes/AQY-F1/AQY-F1.zip fullnode.yaml | grep "listen-address"
   # Should show: 0.0.0.0:25100 (IP:PORT format)
   ```

3. **Deploy and test**:
   ```bash
   sudo bash deploy-192-168-12-100.sh
   sudo docker ps --filter "name=AQY"
   curl http://192.168.12.100:23100/metrics | head
   ```

4. **Monitor logs**:
   ```bash
   sudo docker logs AQY-F1 2>&1 | grep -i "genesis\|error"
   # Should NOT see "Unable to load Genesis" error
   ```

---

## Next Steps

1. Rebuild node deployment packages using updated templates
2. Test deployment on 192.168.12.100
3. Verify all containers start successfully
4. Confirm metrics and RPC endpoints accessible
5. Check for P2P peer connections in logs

---

## Files Location

- Templates: `~/Apollo/ChainABC/validator.yaml`, `~/Apollo/ChainABC/fullnode.yaml`
- Source: `/mnt/c/Apollo/ChainABC/AManager/`
- Binaries: `~/Apollo/ChainABC/AManager.dll` and dependencies

